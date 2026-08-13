// The slack guest over the contract, driven headlessly. Build it first:
//   node guests/build-guest.mjs slack
// then:
//   node --test dyncomp/test/slack-harness.test.mjs
//
// The other harnesses drive ONE component. This one is here for the part of
// the contract they do not reach: a bundle whose components nest into each
// other five levels deep, built by `control.make-instance` from plain JSON.
//
// So the fake host below is fatter than the others: it implements the
// pending-children protocol the real bridge does (a token is reserved during
// the call and the constructor runs after it returns — the Component Model
// forbids re-entering a component while a call into it is active), and it
// keeps an instance table so a test can follow a token down to the `Segment`
// at the bottom. If that protocol ever stops draining recursively, this file
// is what says so.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const jsDir = new URL('../../guests/slack/dist/js/', import.meta.url);
const built = existsSync(fileURLToPath(new URL('slack.component.js', jsDir)));

// --- the value arena, as the bridge keeps it ------------------------------
const arena = new Map();
let nextHandle = 1n;
const put = (v) => { const h = nextHandle++; arena.set(h, v); return h; };
const values = {
  listLen: (h) => arena.get(h).length >>> 0,
  listGet: (h, i) => arena.get(h)[i],
  mapLen: (h) => arena.get(h).size >>> 0,
  mapKeys: (h) => [...arena.get(h).keys()],
  mapGet: (h, k) => arena.get(h).get(k),
  listNew: () => put([]),
  listPush: (h, v) => arena.get(h).push(v),
  mapNew: () => put(new Map()),
  mapSet: (h, k, v) => arena.get(h).set(k, v),
  toJson: (v) => JSON.stringify(v),
  fromJson: (j) => ({ tag: 'text', val: j }),
};

const text = (val) => ({ tag: 'text', val });
const num = (val) => ({ tag: 'number', val });
const bool = (val) => ({ tag: 'boolean', val });

/// Plain JSON -> the tagged values a guest reads, compounds through the arena.
const toGuest = (j) => {
  if (j === null || j === undefined) return { tag: 'nil' };
  if (typeof j === 'boolean') return bool(j);
  if (typeof j === 'number') return num(j);
  if (typeof j === 'string') return text(j);
  if (Array.isArray(j)) return { tag: 'list', val: put(j.map(toGuest)) };
  return { tag: 'map', val: put(new Map(Object.entries(j).map(([k, v]) => [k, toGuest(v)]))) };
};

// --- the instance table and the deferred-constructor protocol -------------
const instances = new Map(); // token -> guest Instance
let nextToken = 1n;
let pending = [];
/// Every control call the guest buffered during the last dispatch.
let emitted = [];

const control = {
  log: () => {},
  emit: (name, args) => emitted.push({ kind: 'emit', name, args }),
  send: (name, args) => emitted.push({ kind: 'send', name, args }),
  sendAt: (path, name, args) => emitted.push({ kind: 'sendAt', path, name, args }),
  bubbleAt: () => {},
  stopPropagation: () => emitted.push({ kind: 'stopPropagation' }),
  request: (name, args) => emitted.push({ kind: 'request', name, args }),
  after: () => {},
  makeInstance: (component, args) => {
    const token = nextToken++;
    pending.push({ token, component, args });
    return token;
  },
  dropInstance: (token) => instances.delete(token),
};

let guest;
let manifest;

/// Run every constructor whose token was reserved during a call — including
/// the ones those constructors reserve in turn, which is what makes a five
/// level tree arrive from one `new Instance`.
const drain = () => {
  while (pending.length) {
    const { token, component, args } = pending.shift();
    instances.set(token, new guest.Instance(component, args));
  }
};

/// Construct a top-level instance from plain JSON args, then settle its tree.
const make = (component, args = {}) => {
  emitted = [];
  const inst = new guest.Instance(
    component,
    Object.entries(args).map(([k, v]) => [k, toGuest(v)]),
  );
  drain();
  return inst;
};

/// Dispatch, settle, and answer the successor (or undefined when unchanged).
const dispatch = (inst, bucket, name, args = []) => {
  emitted = [];
  const result = inst.handleEvent(bucket, name, args);
  drain();
  return result.tag === 'changed' ? result.val : undefined;
};

/// A field holding one child, followed down to the instance behind the token.
const childOf = (inst, field) => instances.get(inst.getField(field).val);
/// A field holding a list of children, likewise.
const childrenOf = (inst, field) =>
  arena.get(inst.getField(field).val).map((v) => instances.get(v.val));
/// A named init's args, straight out of the static manifest.
const initArgs = (component, name) => {
  const c = manifest.components.find((x) => x.name === component);
  return JSON.parse(c.inits.find((i) => i.name === name).argsJson);
};

before(async () => {
  if (!built) return;
  const { instantiate } = await import(new URL('slack.component.js', jsDir));
  const getCoreModule = async (path) =>
    WebAssembly.compile(await readFile(new URL(path, jsDir)));
  const root = await instantiate(getCoreModule, {
    'tutuca:component/values@0.6.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.6.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
  manifest = JSON.parse(
    await readFile(new URL('../../guests/slack/manifest.json', import.meta.url), 'utf8'),
  );
});

test('the static manifest declares six nesting components', { skip: !built }, () => {
  assert.equal(manifest.apiVersion, 6);
  assert.equal(manifest.moduleName, 'slacklib');
  // nothing ambient: no clock for the timestamps, no entropy for the ids
  assert.deepEqual(manifest.capabilities, []);
  assert.deepEqual(manifest.components.map((c) => c.name), [
    'Segment', 'RichText', 'Reaction', 'Message', 'Thread', 'ChannelHistory',
  ]);
  // the nesting is declared, so a host can see the shape without loading it
  const ty = (comp, field) => {
    const c = manifest.components.find((x) => x.name === comp);
    return c.types[c.fields.find((f) => f.name === field).ty];
  };
  assert.equal(ty('Message', 'body').name, 'RichText');
  assert.equal(ty('Thread', 'root').name, 'Message');
  assert.equal(ty('ChannelHistory', 'threads').kind, 'ty-list');
  // and every `$name` the views call is declared, which is what keeps an
  // undeclared method from evaluating to Null and silently dropping an attr
  const declared = manifest.components.find((c) => c.name === 'ChannelHistory');
  assert.deepEqual(declared.methods, [
    'channelLabel', 'memberLabel', 'orderLabel', 'countLabel', 'hasError', 'isEmpty',
  ]);
});

test('a segment composes its classes from independent flags', { skip: !built }, () => {
  const plain = make('Segment', { text: 'plain text' });
  assert.deepEqual(plain.getField('text'), text('plain text'));
  assert.equal(plain.callMethod('segClass', []).val, 'seg');

  const both = make('Segment', { text: 'x', bold: true, code: true });
  assert.equal(
    both.callMethod('segClass', []).val,
    'seg font-bold font-mono text-sm bg-base-200 rounded px-1',
  );

  // every field is scalar, so the host's generated mutators all land
  const italic = plain.withField('italic', bool(true));
  assert.match(italic.callMethod('segClass', []).val, /italic/);
  assert.equal(plain.withField('segments', text('nope')), undefined);
});

test('a link segment reports its URL instead of following it', { skip: !built }, () => {
  const link = make('Segment', { text: 'docs', link: true, url: 'https://example.com' });
  dispatch(link, 'input', 'open', []);
  assert.deepEqual(emitted, [
    { kind: 'emit', name: 'openLink', args: [text('https://example.com'), text('docs')] },
  ]);

  // a run that is not a link has nothing to report
  const plain = make('Segment', { text: 'docs', url: 'https://example.com' });
  dispatch(plain, 'input', 'open', []);
  assert.deepEqual(emitted, []);
});

test('a reaction changes its own count and tells whoever is above', { skip: !built }, () => {
  const r = make('Reaction', { emoji: '👀', count: 2 });
  const on = dispatch(r, 'input', 'toggle', []);
  assert.deepEqual(on.getField('count'), num(3));
  assert.deepEqual(on.getField('reacted'), bool(true));
  assert.deepEqual(emitted, [{ kind: 'emit', name: 'reacted', args: [text('👀'), bool(true)] }]);

  const off = dispatch(on, 'input', 'toggle', []);
  assert.deepEqual(off.getField('count'), num(2));
  assert.deepEqual(emitted, [{ kind: 'emit', name: 'reacted', args: [text('👀'), bool(false)] }]);
});

test('a message builds its body out of segments and reads its own timestamp', { skip: !built }, () => {
  const m = make('Message', initArgs('Message', 'root'));
  assert.deepEqual(m.callMethod('authorLabel', []), text('@Ada Lovelace'));
  assert.deepEqual(m.callMethod('channelLabel', []), text('#general'));
  // sliced out of the data it arrived with — no clock capability anywhere
  assert.deepEqual(m.callMethod('timeLabel', []), text('09:12'));
  assert.deepEqual(m.callMethod('hasChannel', []), bool(true));

  // `body` accepted a bare segment list and wrapped it in a RichText
  const body = childOf(m, 'body');
  const segs = childrenOf(body, 'segments');
  assert.equal(segs.length, 5);
  assert.equal(segs.map((s) => s.getField('text').val).join(''),
    'Morning! The analytical-engine deploy is out — notes are in #releases.');
  assert.deepEqual(segs[1].getField('code'), bool(true));
  assert.deepEqual(segs[3].getField('channel'), bool(true));
  assert.equal(childrenOf(m, 'reactions').length, 2);

  // a reply is compact, and compact is what drops the channel badge
  const reply = make('Message', initArgs('Message', 'reply'));
  assert.deepEqual(reply.callMethod('hasChannel', []), bool(false));
  assert.deepEqual(reply.getField('compact'), bool(true));

  // and a message with nothing in it still renders something sayable
  const blank = make('Message');
  assert.deepEqual(blank.callMethod('authorLabel', []), text('@someone'));
  assert.deepEqual(blank.callMethod('timeLabel', []), text(''));
});

test('a message draws the only avatar an untrusted bundle can', { skip: !built }, () => {
  // Two initials off the display name. A bundle may not name an image source, so
  // there is no photograph to be had and the disc is the whole avatar.
  const m = make('Message', initArgs('Message', 'root'));
  assert.deepEqual(m.callMethod('initials', []), text('AL'));

  // One initial per word, which is the rule `bluesky/Post` uses: a host drawing
  // a Slack card beside a Bluesky one must not draw two kinds of disc. A
  // one-word name is therefore one letter, including an unresolved Slack id.
  for (const [name, want] of [
    ['ada.lovelace', 'AL'],
    ['mariano-guerra', 'MG'],
    ['@bot_name', 'BN'],
    ['Cher', 'C'],
    ['U0123ABCD', 'U'],
  ]) {
    assert.deepEqual(
      make('Message', { author: name }).callMethod('initials', []),
      text(want), name);
  }

  // Nothing to take initials from is drawn as a placeholder rather than as an
  // empty circle, which would read as a rendering bug.
  assert.deepEqual(make('Message').callMethod('initials', []), text('?'));
});

test('a thread forces its replies compact and folds them', { skip: !built }, () => {
  const t = make('Thread', initArgs('Thread', 'expanded'));
  assert.deepEqual(t.getField('expanded'), bool(true));
  assert.deepEqual(t.getField('replyCount'), num(2));
  assert.deepEqual(t.callMethod('hasReplies', []), bool(true));
  assert.deepEqual(t.callMethod('replyLabel', []), text('▾ 2 replies'));

  // "is this a reply" is a fact about position, so the thread decides it and
  // the fixture does not have to say `compact` on every reply
  for (const r of childrenOf(t, 'replies')) {
    assert.deepEqual(r.getField('compact'), bool(true));
  }

  const folded = dispatch(t, 'input', 'toggle', []);
  assert.deepEqual(folded.getField('expanded'), bool(false));
  assert.deepEqual(folded.callMethod('replyLabel', []), text('▸ 2 replies'));

  // from outside: a receive rather than an input, which is what a channel's
  // expand-all reaches with control.send-at
  const reopened = dispatch(folded, 'receive', 'setExpanded', [bool(true)]);
  assert.deepEqual(reopened.getField('expanded'), bool(true));

  const alone = make('Thread', initArgs('Thread', 'no-replies'));
  assert.deepEqual(alone.callMethod('hasReplies', []), bool(false));
  assert.deepEqual(alone.getField('replyCount'), num(0));
});

test('a channel builds its whole tree from one init', { skip: !built }, () => {
  const c = make('ChannelHistory', initArgs('ChannelHistory', 'general'));
  assert.deepEqual(c.callMethod('channelLabel', []), text('#general'));
  assert.deepEqual(c.callMethod('memberLabel', []), text('214 members'));
  assert.deepEqual(c.callMethod('countLabel', []), text('3 conversations'));
  assert.deepEqual(c.callMethod('isEmpty', []), bool(false));
  assert.deepEqual(c.callMethod('hasError', []), bool(false));

  // five levels down, from one `new Instance`: channel -> thread -> message
  // -> rich text -> segment
  const threads = childrenOf(c, 'threads');
  assert.equal(threads.length, 3);
  // (threads[0] is the newest, which is Alan Turing's — see the ordering test)
  const deepest = childrenOf(childOf(childOf(threads[0], 'root'), 'body'), 'segments');
  assert.deepEqual(deepest[0].getField('text'), text('Reminder: the design review moved to '));
  assert.deepEqual(deepest[1].getField('bold'), bool(true));
});

test('the filter box and the ordering toggle reshape what renders', { skip: !built }, () => {
  const c = make('ChannelHistory', initArgs('ChannelHistory', 'general'));
  const authors = (x) =>
    childrenOf(x, 'threads').map((t) => childOf(t, 'root').getField('author').val);

  // newest first by the ROOT timestamp, which is what makes a busy thread
  // stay where the conversation started
  assert.deepEqual(authors(c), ['Alan Turing', 'Ada Lovelace', 'Grace Hopper']);
  const oldest = dispatch(c, 'input', 'toggleOrder', []);
  assert.deepEqual(authors(oldest), ['Grace Hopper', 'Ada Lovelace', 'Alan Turing']);
  assert.deepEqual(oldest.callMethod('orderLabel', []), text('oldest first'));

  // the filter reaches reply text too — "compiler" is in a reply only
  const filtered = dispatch(c, 'input', 'setQuery', [text('compiler')]);
  assert.deepEqual(authors(filtered), ['Ada Lovelace']);
  assert.deepEqual(filtered.callMethod('countLabel', []), text('1 of 3 conversations'));

  // a query nothing matches is the empty state, not an error
  const none = dispatch(c, 'input', 'setQuery', [text('zzz')]);
  assert.deepEqual(childrenOf(none, 'threads'), []);
  assert.deepEqual(none.callMethod('isEmpty', []), bool(true));

  // and clearing it brings everything back
  const cleared = dispatch(none, 'input', 'setQuery', [text('')]);
  assert.equal(childrenOf(cleared, 'threads').length, 3);
});

test('expand-all walks the RENDERED positions, not the stored ones', { skip: !built }, () => {
  const c = make('ChannelHistory', initArgs('ChannelHistory', 'general'));
  dispatch(c, 'input', 'collapseAll', []);
  assert.deepEqual(
    emitted.map((m) => [m.kind, m.name, m.path[0].val.index, m.args[0].val]),
    [['sendAt', 'setExpanded', 0, false],
     ['sendAt', 'setExpanded', 1, false],
     ['sendAt', 'setExpanded', 2, false]],
  );

  // filtered, it addresses only what is on screen — a path counted against
  // the full list would reach the wrong thread
  const filtered = dispatch(c, 'input', 'setQuery', [text('compiler')]);
  dispatch(filtered, 'input', 'expandAll', []);
  assert.deepEqual(
    emitted.map((m) => [m.path[0].val.field, m.path[0].val.index, m.args[0].val]),
    [['threads', 0, true]],
  );
});

test('a channel catches what its children report', { skip: !built }, () => {
  const c = make('ChannelHistory', initArgs('ChannelHistory', 'general'));

  const opened = dispatch(c, 'bubble', 'openLink', [text('https://example.com'), text('docs')]);
  assert.deepEqual(opened.getField('lastAction'), text('link: https://example.com'));
  // and it stops there: nothing above this component could say more about it
  assert.deepEqual(emitted, [{ kind: 'stopPropagation' }]);

  const reacted = dispatch(c, 'bubble', 'reacted', [text('🎉'), bool(true)]);
  assert.deepEqual(reacted.getField('lastAction'), text('reacted 🎉'));
  const undone = dispatch(c, 'bubble', 'reacted', [text('🎉'), bool(false)]);
  assert.deepEqual(undone.getField('lastAction'), text('took back 🎉'));
});

test('the empty, loading and error inits are the states a host has to draw', { skip: !built }, () => {
  const empty = make('ChannelHistory', initArgs('ChannelHistory', 'empty'));
  assert.deepEqual(empty.callMethod('isEmpty', []), bool(true));
  assert.deepEqual(empty.callMethod('countLabel', []), text('0 conversations'));

  // loading is not empty: a spinner and "nothing here yet" are different claims
  const loading = make('ChannelHistory', initArgs('ChannelHistory', 'loading'));
  assert.deepEqual(loading.getField('loading'), bool(true));
  assert.deepEqual(loading.callMethod('isEmpty', []), bool(false));

  const failed = make('ChannelHistory', initArgs('ChannelHistory', 'error'));
  assert.deepEqual(failed.callMethod('hasError', []), bool(true));
  assert.deepEqual(failed.callMethod('isEmpty', []), bool(false));
});

test('every init in the manifest builds', { skip: !built }, () => {
  // The inits ARE the storybook's examples, so a fixture that no longer
  // constructs is a card that silently renders a default.
  for (const c of manifest.components) {
    for (const i of c.inits) {
      const inst = make(c.name, JSON.parse(i.argsJson));
      assert.ok(inst, `${c.name}/${i.name} did not construct`);
      // and every declared field answers, which is what the host reads while
      // rendering — a name it does not know comes back undefined
      for (const f of c.fields) {
        assert.notEqual(inst.getField(f.name), undefined, `${c.name}.${f.name}`);
      }
    }
  }
});
