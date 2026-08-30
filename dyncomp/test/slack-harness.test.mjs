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
  send: (name, args) => emitted.push({ kind: 'send', name, args }),
  sendAt: (path, name, args) => emitted.push({ kind: 'sendAt', path, name, args }),
  intent: (name, args, opts) => emitted.push({ kind: 'intent', name, args, route: opts.route }),
  intentAt: (path, name, args, opts) => emitted.push({ kind: 'intentAt', path, name, args, opts }),
  forward: (args, opts) => emitted.push({ kind: 'forward', args, opts }),
  reply: (v) => emitted.push({ kind: 'reply', value: v }),
  fail: (e) => emitted.push({ kind: 'fail', value: e }),
  stopPropagation: () => emitted.push({ kind: 'stopPropagation' }),
  sendReply: (name, args) => emitted.push({ kind: 'sendReply', name, args }),
  lookup: () => ({ tag: 'nil' }),
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
  const result = bucket === 'intent'
    ? inst.handleIntent(name, args)
    : inst.handleMessage(name, args);
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
    'tutuca:component/values@0.11.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.11.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
  manifest = JSON.parse(
    await readFile(new URL('../../guests/slack/manifest.json', import.meta.url), 'utf8'),
  );
});

test('the static manifest declares eight nesting components', { skip: !built }, () => {
  assert.equal(manifest.apiVersion, 10);
  assert.equal(manifest.moduleName, 'slacklib');
  // nothing ambient — no clock for the timestamps, no entropy for the ids;
  // the pictures' origins are the host's to allow (`allowing_external_urls`)
  assert.ok(!('capabilities' in manifest));
  assert.deepEqual(manifest.components.map((c) => c.name), [
    'Segment', 'Scope', 'RichText', 'Reaction', 'Message', 'Thread', 'FileList', 'ChannelHistory',
  ]);
  // the nesting is declared, so a host can see the shape without loading it
  const ty = (comp, field) => {
    const c = manifest.components.find((x) => x.name === comp);
    return c.types[c.fields.find((f) => f.name === field).ty];
  };
  assert.equal(ty('Message', 'body').name, 'RichText');
  assert.equal(ty('Thread', 'root').name, 'Message');
  assert.equal(ty('ChannelHistory', 'threads').kind, 'ty-list');
  // the two surfaces that disclose their own coverage hang the same component
  assert.equal(ty('ChannelHistory', 'scope').name, 'Scope');
  assert.equal(ty('FileList', 'scope').name, 'Scope');
  // and every `$name` the views call is declared, which is what keeps an
  // undeclared method from evaluating to Null and silently dropping an attr
  const declared = manifest.components.find((c) => c.name === 'ChannelHistory');
  assert.deepEqual(declared.methods, [
    'channelLabel', 'memberLabel', 'orderLabel', 'countLabel', 'hasError', 'isEmpty',
    // the pager's five, in the spelling the bluesky and mastodon bundles use
    'paged', 'atFirst', 'atLast', 'pageLabel', 'rangeLabel',
  ]);
  // including the three the avatar is drawn from: an undeclared one resolves to
  // Null, which hides the image and leaves the initials looking correct — the
  // exact bug this assertion exists to catch
  assert.deepEqual(manifest.components.find((c) => c.name === 'Message').methods, [
    'initials', 'slackCdnPath', 'slackAvatarsPath', 'gravatarPath',
    'authorLabel', 'channelLabel', 'hasChannel', 'timeLabel',
    // the timestamp a reader has to retype when it is not on screen, and the
    // link this bundle can offer but never follow
    'hasId', 'idTitle', 'hasPermalink',
  ]);
  assert.deepEqual(manifest.components.find((c) => c.name === 'Thread').methods, [
    'hasReplies', 'replyLabel', 'hasUnloadedReplies', 'loadLabel', 'loadTitle',
    'paged', 'atFirst', 'atLast', 'pageLabel', 'rangeLabel',
  ]);
  // the three list-shaped components take a page size and the leaves do not: a
  // column of messages is the thing that can arrive too long to draw
  for (const name of ['Thread', 'FileList', 'ChannelHistory']) {
    const c = manifest.components.find((x) => x.name === name);
    assert.equal(ty(name, 'pageSize').kind, 'ty-int', name);
    assert.deepEqual(c.fields.find((f) => f.name === 'pageSize').constraint, { min: 1, max: 500 }, name);
  }
  // `intents` is the routed-bucket HANDLER surface, the way `receives` is:
  // Segment RAISES openLink and answers none, and the one component that can
  // decide what a link or an unfetched thread means answers all three
  assert.deepEqual(manifest.components.find((c) => c.name === 'Segment').intents, []);
  assert.deepEqual(declared.intents, ['openLink', 'reacted', 'openThread']);
});

test('a segment composes its classes from independent flags', { skip: !built }, () => {
  const plain = make('Segment', { text: 'plain text' });
  assert.deepEqual(plain.getField('text'), text('plain text'));
  assert.equal(plain.compute('segClass', []).val, 'seg');

  const both = make('Segment', { text: 'x', bold: true, code: true });
  assert.equal(
    both.compute('segClass', []).val,
    'seg font-bold font-mono text-sm bg-base-200 rounded px-1',
  );

  // every field is scalar, so the host's generated mutators all land
  const italic = plain.withField('italic', bool(true));
  assert.match(italic.compute('segClass', []).val, /italic/);
  assert.equal(plain.withField('segments', text('nope')), undefined);
});

test('a link segment reports its URL instead of following it', { skip: !built }, () => {
  const link = make('Segment', { text: 'docs', link: true, url: 'https://example.com' });
  dispatch(link, 'receive', 'open', []);
  assert.deepEqual(emitted, [
    { kind: 'intent', name: 'openLink', args: [text('https://example.com'), text('docs')], route: ['dyn'] },
  ]);

  // a run that is not a link has nothing to report
  const plain = make('Segment', { text: 'docs', url: 'https://example.com' });
  dispatch(plain, 'receive', 'open', []);
  assert.deepEqual(emitted, []);
});

test('a reaction changes its own count and tells whoever is above', { skip: !built }, () => {
  const r = make('Reaction', { emoji: '👀', count: 2 });
  const on = dispatch(r, 'receive', 'toggle', []);
  assert.deepEqual(on.getField('count'), num(3));
  assert.deepEqual(on.getField('reacted'), bool(true));
  assert.deepEqual(emitted, [{ kind: 'intent', name: 'reacted', args: [text('👀'), bool(true)], route: ['dyn'] }]);

  const off = dispatch(on, 'receive', 'toggle', []);
  assert.deepEqual(off.getField('count'), num(2));
  assert.deepEqual(emitted, [{ kind: 'intent', name: 'reacted', args: [text('👀'), bool(false)], route: ['dyn'] }]);
});

test('a message builds its body out of segments and reads its own timestamp', { skip: !built }, () => {
  const m = make('Message', initArgs('Message', 'root'));
  assert.deepEqual(m.compute('authorLabel', []), text('@Ada Lovelace'));
  assert.deepEqual(m.compute('channelLabel', []), text('#general'));
  // sliced out of the data it arrived with — no clock anywhere
  assert.deepEqual(m.compute('timeLabel', []), text('09:12'));
  assert.deepEqual(m.compute('hasChannel', []), bool(true));

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
  assert.deepEqual(reply.compute('hasChannel', []), bool(false));
  assert.deepEqual(reply.getField('compact'), bool(true));

  // and a message with nothing in it still renders something sayable
  const blank = make('Message');
  assert.deepEqual(blank.compute('authorLabel', []), text('@someone'));
  assert.deepEqual(blank.compute('timeLabel', []), text(''));
});

test('a message draws its picture over the initials it always has', { skip: !built }, () => {
  // Two initials off the display name. The picture is drawn OVER this disc, so
  // it is what shows for a message that has none — and for one whose fetch
  // fails, which an untrusted view has no `onerror` to notice.
  const m = make('Message', initArgs('Message', 'root'));
  assert.deepEqual(m.compute('initials', []), text('AL'));

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
      make('Message', { author: name }).compute('initials', []),
      text(want), name);
  }

  // Nothing to take initials from is drawn as a placeholder rather than as an
  // empty circle, which would read as a rendering bug.
  assert.deepEqual(make('Message').compute('initials', []), text('?'));
});

test('a picture is a path under one of the three origins the view names', { skip: !built }, () => {
  const paths = (avatar) => {
    const m = make('Message', { author: 'Ada Lovelace', avatar });
    return ['slackCdnPath', 'slackAvatarsPath', 'gravatarPath']
      .map((name) => m.compute(name, []).val);
  };
  // Each origin is paired with the path it gets, and only ever one of them:
  // what crosses to the view is the path, and the origin is the view's own
  // literal, so nothing a profile carries can move it.
  assert.deepEqual(
    paths('https://ca.slack-edge.com/T024BE7LD-U024BE7LH-g4c4f4f4f4f4-512'),
    ['T024BE7LD-U024BE7LH-g4c4f4f4f4f4-512', '', '']);
  assert.deepEqual(
    paths('https://avatars.slack-edge.com/2026-06-23/ada_512.png'),
    ['', '2026-06-23/ada_512.png', '']);
  assert.deepEqual(
    paths('https://secure.gravatar.com/avatar/abc123?s=96&d=identicon'),
    ['', '', 'avatar/abc123?s=96&d=identicon']);

  // Anything else is no picture at all, which is the state the initials under
  // it were already drawing. A host that reads this view knows the bundle's
  // whole reach; a profile cannot add to it.
  for (const elsewhere of [
    'https://ca.slack-edge.com.attacker.test/x-512',
    'https://ca.slack-edge.com@attacker.test/x-512',
    'http://ca.slack-edge.com/x-512',
    'https://files.slack.com/x-512',
    '/x-512',
    'javascript:alert(1)',
    '',
  ]) {
    assert.deepEqual(paths(elsewhere), ['', '', ''], elsewhere);
  }

  // and the message keeps the url it arrived with, so a host projecting the
  // field back gets what it wrote
  const url = 'https://secure.gravatar.com/avatar/abc123?s=96&d=identicon';
  assert.deepEqual(make('Message', { avatar: url }).getField('avatar'), text(url));
});

test('a thread forces its replies compact and folds them', { skip: !built }, () => {
  const t = make('Thread', initArgs('Thread', 'expanded'));
  assert.deepEqual(t.getField('expanded'), bool(true));
  assert.deepEqual(t.getField('replyCount'), num(2));
  assert.deepEqual(t.compute('hasReplies', []), bool(true));
  assert.deepEqual(t.compute('replyLabel', []), text('▾ 2 replies'));

  // "is this a reply" is a fact about position, so the thread decides it and
  // the fixture does not have to say `compact` on every reply
  for (const r of childrenOf(t, 'replies')) {
    assert.deepEqual(r.getField('compact'), bool(true));
  }

  const folded = dispatch(t, 'receive', 'toggle', []);
  assert.deepEqual(folded.getField('expanded'), bool(false));
  assert.deepEqual(folded.compute('replyLabel', []), text('▸ 2 replies'));

  // from outside: a receive rather than an input, which is what a channel's
  // expand-all reaches with control.send-at
  const reopened = dispatch(folded, 'receive', 'setExpanded', [bool(true)]);
  assert.deepEqual(reopened.getField('expanded'), bool(true));

  const alone = make('Thread', initArgs('Thread', 'no-replies'));
  assert.deepEqual(alone.compute('hasReplies', []), bool(false));
  assert.deepEqual(alone.getField('replyCount'), num(0));
});

test('a channel builds its whole tree from one init', { skip: !built }, () => {
  const c = make('ChannelHistory', initArgs('ChannelHistory', 'general'));
  assert.deepEqual(c.compute('channelLabel', []), text('#general'));
  assert.deepEqual(c.compute('memberLabel', []), text('214 members'));
  assert.deepEqual(c.compute('countLabel', []), text('3 conversations'));
  assert.deepEqual(c.compute('isEmpty', []), bool(false));
  assert.deepEqual(c.compute('hasError', []), bool(false));

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
  const oldest = dispatch(c, 'receive', 'toggleOrder', []);
  assert.deepEqual(authors(oldest), ['Grace Hopper', 'Ada Lovelace', 'Alan Turing']);
  assert.deepEqual(oldest.compute('orderLabel', []), text('oldest first'));

  // the filter reaches reply text too — "compiler" is in a reply only
  const filtered = dispatch(c, 'receive', 'setQuery', [text('compiler')]);
  assert.deepEqual(authors(filtered), ['Ada Lovelace']);
  assert.deepEqual(filtered.compute('countLabel', []), text('1 of 3 conversations'));

  // a query nothing matches is the empty state, not an error
  const none = dispatch(c, 'receive', 'setQuery', [text('zzz')]);
  assert.deepEqual(childrenOf(none, 'threads'), []);
  assert.deepEqual(none.compute('isEmpty', []), bool(true));

  // and clearing it brings everything back
  const cleared = dispatch(none, 'receive', 'setQuery', [text('')]);
  assert.equal(childrenOf(cleared, 'threads').length, 3);
});

test('expand-all walks the RENDERED positions, not the stored ones', { skip: !built }, () => {
  const c = make('ChannelHistory', initArgs('ChannelHistory', 'general'));
  dispatch(c, 'receive', 'collapseAll', []);
  assert.deepEqual(
    emitted.map((m) => [m.kind, m.name, m.path[0].val.index, m.args[0].val]),
    [['sendAt', 'setExpanded', 0, false],
     ['sendAt', 'setExpanded', 1, false],
     ['sendAt', 'setExpanded', 2, false]],
  );

  // filtered, it addresses only what is on screen — a path counted against
  // the full list would reach the wrong thread
  const filtered = dispatch(c, 'receive', 'setQuery', [text('compiler')]);
  dispatch(filtered, 'receive', 'expandAll', []);
  assert.deepEqual(
    emitted.map((m) => [m.path[0].val.field, m.path[0].val.index, m.args[0].val]),
    [['threads', 0, true]],
  );
});

/// Seven conversations, so a page size of three makes three pages and a last
/// one that is not full — the case an off-by-one in `rangeLabel` would show up
/// in. The timestamps ascend, so newest-first draws them backwards.
const MANY_THREADS = Array.from({ length: 7 }, (_, i) => ({
  root: {
    id: `17000000${10 + i}.000001`,
    author: 'alice',
    channelName: 'general',
    createdAt: `2026-08-14T09:${10 + i}:00Z`,
    body: [{ text: `message ${i}` }],
  },
}));
/// The author of each conversation the card is drawing, in order.
const drawn = (c) => childrenOf(c, 'threads')
  .map((t) => childOf(t, 'root').getField('id').val);

test('a long channel is paged, and a page is not a filter', { skip: !built }, () => {
  // Below the threshold nothing changed: no window, no footer, every
  // conversation on screen — which is what this card did before it could page.
  const short = make('ChannelHistory', initArgs('ChannelHistory', 'general'));
  assert.deepEqual(short.compute('paged', []), bool(false));
  assert.deepEqual(short.getField('pageCount'), num(1));
  assert.deepEqual(short.compute('rangeLabel', []), text(''));

  // Asking for a page size is asking to be paged, whatever the length.
  let c = make('ChannelHistory', { channel: 'general', threads: MANY_THREADS, pageSize: 3 });
  assert.deepEqual(c.compute('paged', []), bool(true));
  // 1-based, because it is a label rather than an index
  assert.deepEqual(c.getField('page'), num(1));
  assert.deepEqual(c.getField('pageCount'), num(3));
  assert.deepEqual(c.compute('rangeLabel', []), text('1–3 of 7'));
  // newest first, so the newest three are the first page
  assert.deepEqual(drawn(c), ['1700000016.000001', '1700000015.000001', '1700000014.000001']);
  // the count is about the channel, not about the page
  assert.deepEqual(c.compute('countLabel', []), text('7 conversations'));

  // A button that would not move answers `unchanged`, and a name the pager
  // does not know keeps travelling.
  assert.equal(dispatch(c, 'receive', 'prevPage', []), undefined);
  assert.equal(dispatch(c, 'receive', 'somethingElse', []), undefined);

  c = dispatch(c, 'receive', 'nextPage', []);
  assert.deepEqual(drawn(c), ['1700000013.000001', '1700000012.000001', '1700000011.000001']);
  assert.deepEqual(c.compute('atFirst', []), bool(false));

  // Expand-all addresses THIS page: the paths are positions in what the
  // renderer drew, and a reader pressing it means the ones in front of them.
  dispatch(c, 'receive', 'expandAll', []);
  assert.deepEqual(emitted.map((m) => m.path[0].val.index), [0, 1, 2]);

  // the last page is the short one, and it says so
  const end = dispatch(c, 'receive', 'lastPage', []);
  assert.deepEqual(drawn(end), ['1700000010.000001']);
  assert.deepEqual(end.compute('rangeLabel', []), text('7–7 of 7'));
  assert.deepEqual(end.compute('atLast', []), bool(true));
  assert.equal(dispatch(end, 'receive', 'nextPage', []), undefined);

  // Filtering and reordering each make a different list, so page three of the
  // old one is a position in a channel that is not there any more.
  assert.deepEqual(dispatch(end, 'receive', 'setQuery', [text('message')]).getField('page'), num(1));
  assert.deepEqual(dispatch(end, 'receive', 'toggleOrder', []).getField('page'), num(1));
  // and a filter narrow enough to fit on one page puts the pager away
  const one = dispatch(end, 'receive', 'setQuery', [text('message 4')]);
  assert.deepEqual(one.compute('paged', []), bool(false));
  assert.deepEqual(drawn(one), ['1700000014.000001']);
});

test('a thread pages its replies, and a file list pages its rows', { skip: !built }, () => {
  // A thread's window is over the replies that ARE here; `replyCount` is how
  // many exist, which is a different number and stays put.
  const replies = Array.from({ length: 7 }, (_, i) => ({ author: 'bob', body: [{ text: `reply ${i}` }] }));
  let t = make('Thread', { root: { id: '1', author: 'alice' }, replies, replyCount: 21, pageSize: 3 });
  assert.deepEqual(t.compute('paged', []), bool(true));
  assert.deepEqual(t.getField('pageCount'), num(3));
  assert.deepEqual(t.compute('replyLabel', []), text('▾ 7 of 21 replies'));
  assert.equal(childrenOf(t, 'replies').length, 3);
  t = dispatch(t, 'receive', 'lastPage', []);
  assert.deepEqual(t.compute('rangeLabel', []), text('7–7 of 7'));
  assert.equal(childrenOf(t, 'replies').length, 1);

  // A host that went and fetched the replies writes a whole new list home,
  // which is a different write from handing back the page it was shown — and
  // it starts at the first page, because it is a different set of rows.
  const fetched = t.withField('replies', { tag: 'list', val: put([]) });
  assert.deepEqual(fetched.getField('page'), num(1));
  assert.deepEqual(fetched.getField('replyCount'), num(21));

  // A file row is a record rather than a child, so `@key` counts the rows the
  // view was GIVEN — which on page two are not the first files in the list.
  let f = make('FileList', { ...initArgs('FileList', 'a channel’s files'), pageSize: 2 });
  assert.deepEqual(f.compute('countLabel', []), text('3 files'));
  assert.deepEqual(f.compute('rangeLabel', []), text('1–2 of 3'));
  f = dispatch(f, 'receive', 'nextPage', []);
  dispatch(f, 'receive', 'openFile', [num(0)]);
  // position 0 of page two is the third file, which has no permalink to offer
  assert.deepEqual(emitted, []);
  dispatch(dispatch(f, 'receive', 'prevPage', []), 'receive', 'openFile', [num(1)]);
  assert.equal(emitted[0].name, 'openLink');
  assert.match(emitted[0].args[1].val, /latency\.png/);
});

test('a channel catches what its children report', { skip: !built }, () => {
  const c = make('ChannelHistory', initArgs('ChannelHistory', 'general'));

  const opened = dispatch(c, 'intent', 'openLink', [text('https://example.com'), text('docs')]);
  assert.deepEqual(opened.getField('lastAction'), text('link: https://example.com'));
  // and it stops there: nothing above this component could say more about it
  assert.deepEqual(emitted, [{ kind: 'stopPropagation' }]);

  const reacted = dispatch(c, 'intent', 'reacted', [text('🎉'), bool(true)]);
  assert.deepEqual(reacted.getField('lastAction'), text('reacted 🎉'));
  const undone = dispatch(c, 'intent', 'reacted', [text('🎉'), bool(false)]);
  assert.deepEqual(undone.getField('lastAction'), text('took back 🎉'));
});

test('the empty, loading and error inits are the states a host has to draw', { skip: !built }, () => {
  const empty = make('ChannelHistory', initArgs('ChannelHistory', 'empty'));
  assert.deepEqual(empty.compute('isEmpty', []), bool(true));
  assert.deepEqual(empty.compute('countLabel', []), text('0 conversations'));

  // loading is not empty: a spinner and "nothing here yet" are different claims
  const loading = make('ChannelHistory', initArgs('ChannelHistory', 'loading'));
  assert.deepEqual(loading.getField('loading'), bool(true));
  assert.deepEqual(loading.compute('isEmpty', []), bool(false));

  const failed = make('ChannelHistory', initArgs('ChannelHistory', 'error'));
  assert.deepEqual(failed.compute('hasError', []), bool(true));
  assert.deepEqual(failed.compute('isEmpty', []), bool(false));
});

test('a message shows the timestamp every follow-up call takes', { skip: !built }, () => {
  const m = make('Message', {
    id: '1700000001.000001',
    author: 'alice',
    createdAt: '2026-06-23T09:12:00Z',
    permalink: 'https://acme.slack.com/archives/C0123/p1700000001000001',
  });
  // it was always carried and never drawn, which is what sent a reader off to
  // retype it off the prose and hit thread_not_found
  assert.deepEqual(m.getField('id'), text('1700000001.000001'));
  assert.deepEqual(m.compute('hasId', []), bool(true));
  assert.match(m.compute('idTitle', []).val, /^ts 1700000001\.000001 —/);

  // the permalink travels up rather than being followed: a workspace subdomain
  // is not an origin a view can write as a literal, so there is no href to have
  assert.deepEqual(m.compute('hasPermalink', []), bool(true));
  dispatch(m, 'receive', 'openPermalink', []);
  assert.deepEqual(emitted, [{
    kind: 'intent',
    name: 'openLink',
    args: [text('https://acme.slack.com/archives/C0123/p1700000001000001'), text('permalink')],
    route: ['dyn'],
  }]);

  // a message with neither says neither, and offers no button to press
  const bare = make('Message', { author: 'alice' });
  assert.deepEqual(bare.compute('hasId', []), bool(false));
  assert.deepEqual(bare.compute('hasPermalink', []), bool(false));
  assert.deepEqual(bare.compute('idTitle', []), text(''));
  dispatch(bare, 'receive', 'openPermalink', []);
  assert.deepEqual(emitted, []);
});

test('a counted thread with no replies says the call that would fetch them', { skip: !built }, () => {
  // exactly what `conversations.history` gives a card: a root with a count and
  // nothing behind it
  const t = make('Thread', {
    root: { id: '1700000001.000001', author: 'alice', channelName: 'general', body: ['about the migration'] },
    expanded: false,
    replyCount: 21,
  });
  assert.deepEqual(t.getField('replyCount'), num(21));
  // the caret is for replies that are HERE, so it is not offered
  assert.deepEqual(t.compute('hasReplies', []), bool(false));
  assert.deepEqual(t.compute('hasUnloadedReplies', []), bool(true));
  assert.deepEqual(t.compute('loadLabel', []), text('21 replies — not loaded'));
  // both arguments, filled in — the difference between a dead end and a step
  assert.deepEqual(
    t.compute('loadTitle', []),
    text('read them with channel=general, ts=1700000001.000001'),
  );
  // and they are taken off the root's own JSON, so a caller writes them once
  assert.deepEqual(t.getField('channelName'), text('general'));
  assert.deepEqual(t.getField('rootTs'), text('1700000001.000001'));

  dispatch(t, 'receive', 'openThread', []);
  assert.deepEqual(emitted, [{
    kind: 'intent',
    name: 'openThread',
    args: [text('general'), text('1700000001.000001'), num(21)],
    route: ['dyn'],
  }]);

  // a page of a long thread says it is a page rather than claiming the three
  // it was handed are all there are
  const paged = make('Thread', {
    root: { id: '1700000001.000001', author: 'alice' },
    replies: [{ author: 'bob' }, { author: 'carol' }],
    replyCount: 21,
  });
  assert.deepEqual(paged.compute('hasReplies', []), bool(true));
  assert.deepEqual(paged.compute('hasUnloadedReplies', []), bool(false));
  assert.deepEqual(paged.compute('replyLabel', []), text('▾ 2 of 21 replies'));

  // a thread read whole takes the count from what arrived, which is the same
  // number — nothing had to be told to it
  const whole = make('Thread', {
    root: { id: '1', author: 'alice' },
    replies: [{ author: 'bob' }],
  });
  assert.deepEqual(whole.getField('replyCount'), num(1));
  assert.deepEqual(whole.compute('replyLabel', []), text('▾ 1 reply'));
  assert.deepEqual(whole.compute('hasUnloadedReplies', []), bool(false));

  // writing the replies home does not move the count: how many exist is a fact
  // about the conversation, and how many are on screen is a fact about this
  // page of it
  const swapped = paged.withField('replies', { tag: 'list', val: put([]) });
  assert.deepEqual(swapped.getField('replyCount'), num(21));
  assert.deepEqual(swapped.compute('hasUnloadedReplies', []), bool(true));
  // and a list of plain data is refused rather than silently emptying the field
  assert.equal(paged.withField('replies', toGuest([{ author: 'bob' }])), undefined);
});

test('a channel history says what it does not cover', { skip: !built }, () => {
  const c = make('ChannelHistory', {
    channel: 'general',
    threads: [{ root: { id: '1700000001.000001', author: 'alice', channelName: 'general' }, replyCount: 21 }],
    scope: { privateChannels: true, channelsScanned: 11, truncated: true, truncatedBy: 'max_search_channels' },
  });
  assert.deepEqual(c.getField('hasScope'), bool(true));
  const s = childOf(c, 'scope');
  assert.deepEqual(s.compute('hasAny', []), bool(true));
  assert.deepEqual(
    s.compute('kindsLabel', []),
    text('public channels, and the private ones this token is in'),
  );
  assert.deepEqual(s.compute('scannedLabel', []), text('11 conversations read'));
  // the absence is the disclosure: a card listing what it DID cover and saying
  // nothing about DMs reads as covering everything
  assert.deepEqual(s.compute('hasDmNote', []), bool(true));
  assert.match(s.compute('truncatedLabel', []).val, /max_search_channels cap/);
  assert.match(s.compute('summary', []).val, /^scope: public channels and the private/);

  // a card whose builder said nothing about coverage does not grow a coverage
  // box out of defaults it was never given
  const quiet = make('ChannelHistory', { channel: 'general', threads: [] });
  assert.deepEqual(quiet.getField('hasScope'), bool(false));

  // and the thread's request for its unfetched replies stops here, because this
  // is the component that can name the call
  const t = childrenOf(c, 'threads')[0];
  dispatch(t, 'receive', 'openThread', []);
  const next = dispatch(c, 'intent', 'openThread', [text('general'), text('1700000001.000001'), num(21)]);
  assert.ok(emitted.some((e) => e.kind === 'stopPropagation'));
  assert.deepEqual(
    next.getField('lastAction'),
    text('read the replies: channel=general, ts=1700000001.000001'),
  );
});

test('a file list is metadata, and says so', { skip: !built }, () => {
  const f = make('FileList', initArgs('FileList', 'a channel’s files'));
  assert.deepEqual(f.compute('title', []), text('Files in #incidents'));
  assert.deepEqual(f.compute('countLabel', []), text('3 files'));
  assert.deepEqual(f.compute('isEmpty', []), bool(false));
  assert.match(f.compute('note', []).val, /contents are not available/);

  const rows = arena.get(f.getField('rows').val).map((v) =>
    Object.fromEntries([...arena.get(v.val)].map(([k, x]) => [k, x.val])));
  // a title beats a filename, a filename beats an id, and every row says which
  // it is by carrying the id beside the label
  assert.deepEqual(rows.map((r) => r.label), [
    'Postmortem: the 14 August outage', 'latency.png', 'raw-metrics.csv',
  ]);
  // one decimal only while it buys something: `17.9 KB` and `17 KB` are the
  // same fact, and the second is the one a row has space for
  assert.deepEqual(rows.map((r) => r.size), ['17 KB', '238 KB', '3 MB']);
  assert.deepEqual(rows.map((r) => r.by), ['@alice', '@bob', '@carol']);
  assert.deepEqual(rows.map((r) => r.time), ['09:12', '09:20', '10:02']);
  // the third file has no permalink, so there is no link to offer for it
  assert.deepEqual(rows.map((r) => r.linked), [true, true, false]);

  // a row is opened by its POSITION, because `@key` is what a loop can hand a
  // handler — the view never carries a url it might pass to the wrong component
  dispatch(f, 'receive', 'openFile', [num(1)]);
  assert.deepEqual(emitted, [{
    kind: 'intent',
    name: 'openLink',
    args: [text('https://acme.slack.com/files/U0124/F0124EFGH/latency.png'), text('latency.png')],
    route: ['dyn'],
  }]);
  // a row with no link, and a position that is not a row, both do nothing
  dispatch(f, 'receive', 'openFile', [num(2)]);
  assert.deepEqual(emitted, []);
  dispatch(f, 'receive', 'openFile', [num(9)]);
  assert.deepEqual(emitted, []);

  const empty = make('FileList', { files: [] });
  assert.deepEqual(empty.compute('title', []), text('Files'));
  assert.deepEqual(empty.compute('isEmpty', []), bool(true));
  assert.deepEqual(empty.getField('hasScope'), bool(false));
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
