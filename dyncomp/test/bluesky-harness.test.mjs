// The bluesky guest over the contract, driven headlessly by the same fake host
// the other harnesses use. Build it first:
//   node guests/build-guest.mjs bluesky
// then:
//   node --test dyncomp/test/bluesky-harness.test.mjs
//
// This bundle READS someone else's records, so what is worth checking is not
// "does a post render" — the views are the host's job — but the four things
// the guest decides:
//
//   1. Facets are UTF-8 BYTE offsets while a MoonBit string is UTF-16, so
//      `segments` has to cut the text on byte boundaries. An emoji in front of
//      a link is the case that catches a guest measuring characters.
//   2. A thread is a list of child `Post`s, made through `control.make-instance`
//      — the only shape in which a reply keeps its links, since a view cannot
//      iterate a value it found inside another iteration.
//   3. A row keeps its OWN like / repost / fold and returns a successor; the
//      thread additionally keeps which uris are folded, because only it knows
//      which rows sit under one and therefore stop rendering. Two facts about
//      the same click, and neither is the other's.
//   4. The engagement flags stay APART from the counts the record came with.
//
// The fake host below implements `make-instance` the way the real bridge does
// (reserve a token now, construct after the call returns), because a guest that
// creates children is exactly what that rule exists for.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const jsDir = new URL('../../guests/bluesky/dist/js/', import.meta.url);
const built = existsSync(fileURLToPath(new URL('bluesky.component.js', jsDir)));

/// What the guest emitted, oldest first. Cleared by the tests that read it.
const emitted = [];
/// Children whose construction the guest asked for, and the instances they
/// became — the bridge's pendingChildren / drainChildren, minimally.
const pending = [];
const children = new Map();
let nextToken = 1n;

const control = {
  log: () => {},
  send: () => {},
  sendAt: () => {},
  intent: (name, args) => emitted.push([name, args]),
  intentAt: (path, name, args) => emitted.push([name, args]),
  forward: () => {},
  reply: () => {},
  fail: () => {},
  stopPropagation: () => emitted.push(['stopPropagation', []]),
  sendReply: (name, args) => emitted.push(['sendReply', [name, args]]),
  lookup: () => ({ tag: 'nil' }),
  after: () => {},
  makeInstance: (component, args) => {
    const token = nextToken++;
    pending.push([token, component, args]);
    return token;
  },
  dropInstance: (token) => children.delete(token),
};

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
const list = (items) => ({ tag: 'list', val: put(items) });
const map = (obj) => ({ tag: 'map', val: put(new Map(Object.entries(obj))) });

/// A guest value as plain JS, following handles back out of the arena. An
/// `instance` stays a token: `child()` is what turns one back into a component.
const plain = (v) => {
  if (v === undefined || v.tag === 'nil') return null;
  if (v.tag === 'list') return arena.get(v.val).map(plain);
  if (v.tag === 'map') return Object.fromEntries([...arena.get(v.val)].map(([k, x]) => [k, plain(x)]));
  return v.val;
};
const field = (inst, name) => plain(inst.getField(name));
/// The child a row token names, and the field the view would read off it.
const child = (token) => children.get(token);
const rowField = (inst, name) => field(inst, 'rows').map((t) => field(child(t), name));

/// What the real bridge does when a guest returns a successor: give it a handle
/// of its own, in the same table `make-instance` fills.
const register = (inst) => { const t = nextToken++; children.set(t, inst); return t; };

/// The host writing a changed child home: it hands the parent its WHOLE list
/// with the new instance in place of the old one, which is
/// `obj_with_field("rows", List([… Obj …]))`. It only works because `child_json`
/// encodes an instance at any depth inside the value being written — before
/// that the list arrived as plain data, the guest refused it, and the successor
/// was dropped on the floor.
const writeRow = (parent, at, next) => {
  const tokens = field(parent, 'rows').slice();
  tokens[at] = register(next);
  return parent.withField('rows', list(tokens.map((t) => ({ tag: 'instance', val: t }))));
};

/// The message shape all three components read, as the host hands it over.
const message = (m) => map({
  uri: text(m.uri ?? ''),
  displayName: text(m.displayName ?? ''),
  handle: text(m.handle ?? ''),
  text: text(m.text ?? ''),
  createdAt: text(m.createdAt ?? ''),
  facets: list((m.facets ?? []).map((f) => map(facetValue(f)))),
  images: list((m.images ?? []).map((alt) => map({ alt: text(alt) }))),
  replyCount: num(m.replyCount ?? 0),
  repostCount: num(m.repostCount ?? 0),
  likeCount: num(m.likeCount ?? 0),
  depth: num(m.depth ?? 0),
});

const facetValue = (f) => ({
  byteStart: num(f.byteStart),
  byteEnd: num(f.byteEnd),
  kind: text(f.kind),
  value: text(f.value),
});

/// Byte offsets, the way the wire spells them — the whole point of the segment
/// test below.
const facetOf = (body, sub, kind, value) => {
  const at = body.indexOf(sub);
  const start = Buffer.byteLength(body.slice(0, at));
  return { byteStart: start, byteEnd: start + Buffer.byteLength(sub), kind, value };
};

let guest;
let manifest;
/// Construct what the guest asked for while it was running. The bridge does
/// this after every call into the guest, because the Component Model forbids
/// re-entering one while a call is active.
const drain = () => {
  while (pending.length) {
    const [token, component, args] = pending.shift();
    children.set(token, new guest.Instance(component, args));
  }
};
const instance = (component, args) => {
  const inst = new guest.Instance(component, args);
  drain();
  return inst;
};

before(async () => {
  if (!built) return;
  const { instantiate } = await import(new URL('bluesky.component.js', jsDir));
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
    await readFile(new URL('../../guests/bluesky/manifest.json', import.meta.url), 'utf8'),
  );
  const settle = (raw) => function (...args) {
    const result = raw.call(this, ...args);
    drain();
    return result.tag === 'changed' ? result.val : undefined;
  };
  guest.Instance.prototype.handleMessage = settle(guest.Instance.prototype.handleMessage);
  guest.Instance.prototype.handleIntent = settle(guest.Instance.prototype.handleIntent);
  const rawWith = guest.Instance.prototype.withField;
  guest.Instance.prototype.withField = function (...args) {
    const next = rawWith.call(this, ...args);
    drain();
    return next;
  };
});

test('the static manifest declares five components', { skip: !built }, () => {
  const m = manifest;
  assert.equal(m.apiVersion, 10);
  assert.equal(m.moduleName, 'blueskylib');
  // the origins its views name are the whole of its network reach, and the
  // host's policy (`allowing_external_urls`) is what decides them — the
  // manifest declares nothing
  assert.ok(!('capabilities' in m));
  assert.deepEqual(m.components.map((c) => c.name), ['Scope', 'Post', 'Feed', 'Thread', 'Profile']);

  const byName = Object.fromEntries(m.components.map((c) => [c.name, c]));
  const { Scope: scope, Post: post, Feed: feed, Thread: thread, Profile: profile } = byName;
  assert.deepEqual(post.fields.map((f) => f.name), [
    'uri', 'displayName', 'handle', 'text', 'createdAt', 'avatar', 'facets', 'images',
    'replyCount', 'repostCount', 'likeCount', 'liked', 'reposted',
    'depth', 'focus', 'foldable', 'folded', 'owned',
    // why this message is in front of this reader, what a moderator said about
    // it, and the three embeds that used to render as bare text
    'repostedBy', 'pinned', 'labels', 'external', 'quote', 'video',
  ]);
  assert.deepEqual(post.intents, ['liked', 'unliked', 'reposted', 'unreposted', 'folded', 'unfolded']);
  // `pageSize` is the one field the three list-shaped components share and the
  // leaves do not: a column of messages is the thing that can arrive too long
  // to draw, and a single message is not.
  assert.deepEqual(thread.fields.map((f) => f.name), ['posts', 'focus', 'scope', 'pageSize']);
  // a feed is a list and a thread is a conversation, so a feed declares no
  // reply vocabulary at all — that is the whole reason it exists
  // `title` first, the way the mastodon sibling's `Timeline` declares it: a feed is the one
  // surface that cannot say what it is from its own contents
  assert.deepEqual(feed.fields.map((f) => f.name), ['title', 'posts', 'scope', 'pageSize']);
  for (const c of [feed, thread, profile]) {
    assert.deepEqual(c.methods.slice(-5), ['paged', 'atFirst', 'atLast', 'pageLabel', 'rangeLabel'], c.name);
    assert.deepEqual(c.fields.find((f) => f.name === 'pageSize').constraint, { min: 1, max: 500 }, c.name);
  }
  assert.deepEqual(scope.fields.map((f) => f.name), ['truncated', 'truncatedBy', 'more', 'notes']);
  assert.deepEqual(profile.fields.map((f) => f.name).slice(-3), ['createdAt', 'pinnedPost', 'pageSize']);
  // the thread's bubbles are the ones it HEARS from its rows
  assert.deepEqual(thread.intents, ['folded', 'unfolded', 'liked', 'unliked', 'reposted', 'unreposted']);
  assert.deepEqual(feed.intents, ['liked', 'unliked', 'reposted', 'unreposted']);
  assert.deepEqual(profile.intents, ['followed', 'unfollowed', 'liked', 'unliked', 'reposted', 'unreposted']);
  // a `scope` field is a plain record whose keys ARE the Scope component's own
  // field names, so the two cannot drift without this failing
  const scopeFields = new Set(scope.fields.map((f) => f.name));
  for (const c of [feed, thread]) {
    const args = JSON.parse(c.inits.map((i) => i.argsJson).find((j) => j.includes('"scope"')) ?? '{"scope":{}}');
    for (const k of Object.keys(args.scope ?? {})) assert.ok(scopeFields.has(k), `${c.name}: scope.${k}`);
  }
  // every component ships a fixture, so dropping the bundle shows something
  for (const c of m.components) assert.ok(c.inits.length >= 1);
  // and every fixture is JSON the host can actually read
  for (const c of m.components) for (const i of c.inits) JSON.parse(i.argsJson);
  // the two fixtures with pictures point at the origin the views name, so the
  // gallery shows the loaded state and not only the fallback
  for (const name of ['Post', 'Profile']) {
    const args = JSON.parse(
      m.components.find((c) => c.name === name).inits.find((i) => i.name === 'with pictures').argsJson,
    );
    assert.ok(args.avatar.startsWith('https://cdn.bsky.app/'));
  }
});

test('a post cuts its text on the facets UTF-8 byte offsets', { skip: !built }, () => {
  // the emoji is three bytes and one UTF-16 unit, so a guest that measured
  // characters would slice this text three bytes early
  const body = '🚀 shipped it — tutuca.dev/dyncomp, thanks @bob.bsky.social #wasm';
  const p = instance('Post', [
    ['text', text(body)],
    ['facets', list([
      map(facetValue(facetOf(body, 'tutuca.dev/dyncomp', 'link', 'https://tutuca.dev/dyncomp'))),
      map(facetValue(facetOf(body, '@bob.bsky.social', 'mention', 'bob.bsky.social'))),
      map(facetValue(facetOf(body, '#wasm', 'tag', 'wasm'))),
    ])],
  ]);
  // `path` is the half a view can turn into a link, and only a mention and a
  // hashtag have one: a link somebody POSTED points at an origin no view can
  // name, so it stays `external` — text, with its target in the tooltip
  assert.deepEqual(field(p, 'segments'), [
    { text: '🚀 shipped it — ', target: '', path: '', external: false, kind: 'text' },
    { text: 'tutuca.dev/dyncomp', target: 'https://tutuca.dev/dyncomp', path: '', external: true, kind: 'link' },
    { text: ', thanks ', target: '', path: '', external: false, kind: 'text' },
    { text: '@bob.bsky.social', target: 'bsky.app/profile/bob.bsky.social', path: 'profile/bob.bsky.social', external: false, kind: 'mention' },
    { text: ' ', target: '', path: '', external: false, kind: 'text' },
    { text: '#wasm', target: 'bsky.app/hashtag/wasm', path: 'hashtag/wasm', external: false, kind: 'tag' },
  ]);
  // the runs put back together are the message, which matters more than any
  // single boundary
  assert.equal(field(p, 'segments').map((s) => s.text).join(''), body);
});

test('a facet that is out of order, overlapping or mid-character is dropped', { skip: !built }, () => {
  const body = 'héllo world';
  const good = facetOf(body, 'world', 'link', 'https://example.com');
  const p = instance('Post', [
    ['text', text(body)],
    ['facets', list([
      map(facetValue(good)),
      // starts inside the accented character: not a boundary, so not a facet
      map(facetValue({ byteStart: 2, byteEnd: 4, kind: 'tag', value: 'no' })),
      // ends before it starts
      map(facetValue({ byteStart: 9, byteEnd: 3, kind: 'tag', value: 'no' })),
    ])],
  ]);
  assert.deepEqual(field(p, 'segments'), [
    { text: 'héllo ', target: '', path: '', external: false, kind: 'text' },
    { text: 'world', target: 'https://example.com', path: '', external: true, kind: 'link' },
  ]);
});

test('the projections a view reads: name, initials, time, counts, permalink', { skip: !built }, () => {
  const p = instance('Post', [
    ['uri', text('at://did:plc:alice000000000000000000/app.bsky.feed.post/3kaaa')],
    ['displayName', text('Alice Alpha')],
    ['handle', text('alice.bsky.social')],
    ['createdAt', text('2026-08-11T14:03:00Z')],
    ['replyCount', num(12)],
    ['repostCount', num(1234)],
    ['likeCount', num(2400000)],
  ]);
  assert.equal(field(p, 'name'), 'Alice Alpha');
  assert.equal(field(p, 'handleText'), '@alice.bsky.social');
  assert.equal(field(p, 'initials'), 'AA');
  // no clock is involved: the stamp is formatted from the record itself
  assert.equal(field(p, 'time'), '11 Aug 2026, 14:03');
  assert.equal(field(p, 'replies'), '12');
  assert.equal(field(p, 'reposts'), '1.2K');
  assert.equal(field(p, 'likes'), '2.4M');
  assert.equal(field(p, 'permalink'), 'bsky.app/profile/alice.bsky.social/post/3kaaa');
  // the same permalink split the way the view uses it: the origin is the
  // view's literal, and this is only ever the path under it
  assert.equal(field(p, 'permalinkPath'), 'profile/alice.bsky.social/post/3kaaa');
  // standing on its own: no rails to draw and no fold button
  assert.deepEqual(field(p, 'rail'), []);
  assert.equal(field(p, 'foldable'), 0);

  // a display name it does not have falls back to the handle, and the initials
  // to the handle's first two labels
  const bare = instance('Post', [['handle', text('bob.bsky.social')]]);
  assert.equal(field(bare, 'name'), 'bob.bsky.social');
  assert.equal(field(bare, 'initials'), 'BB');
  // a stamp this bundle cannot read is shown as it arrived rather than blanked
  assert.equal(field(instance('Post', [['createdAt', text('last tuesday')]]), 'time'), 'last tuesday');
  // an at:// uri that is not a post has no post permalink to give
  const profileUri = instance('Post', [['uri', text('at://did:plc:x/app.bsky.actor.profile/self')]]);
  assert.equal(field(profileUri, 'permalink'), '');
  assert.equal(field(profileUri, 'permalinkPath'), '');
});

test('a picture is a path under the one origin the views name', { skip: !built }, () => {
  const cdn = 'https://cdn.bsky.app';
  const shown = instance('Post', [
    ['displayName', text('Alice Alpha')],
    ['avatar', text(`${cdn}/img/avatar/plain/did:plc:alice/bafkreiavatar@jpeg`)],
    ['images', list([
      map({ alt: text('a terminal'), thumb: text(`${cdn}/img/feed_thumbnail/plain/did:plc:alice/bafkreithumb@jpeg`) }),
      map({ alt: text('no picture came with this one') }),
    ])],
  ]);
  // what crosses to the view is the PATH; the origin is the view's literal, so
  // nothing this bundle computes can move it
  assert.equal(field(shown, 'avatarPath'), 'img/avatar/plain/did:plc:alice/bafkreiavatar@jpeg');
  assert.deepEqual(field(shown, 'imageItems'), [
    { alt: 'a terminal', path: 'img/feed_thumbnail/plain/did:plc:alice/bafkreithumb@jpeg' },
    { alt: 'no picture came with this one', path: '' },
  ]);
  // and the record keeps the url it arrived with, so a host projecting the
  // field back gets what it wrote
  assert.equal(field(shown, 'avatar'), `${cdn}/img/avatar/plain/did:plc:alice/bafkreiavatar@jpeg`);

  // Everything else is no picture at all — which is the state the initials
  // under it were already drawing. A host that reads this bundle's views knows
  // its whole reach; a record cannot add to it.
  for (const elsewhere of [
    'https://cdn.bsky.app.attacker.test/img/avatar/plain/x@jpeg',
    'https://cdn.bsky.app@attacker.test/img/avatar/plain/x@jpeg',
    'http://cdn.bsky.app/img/avatar/plain/x@jpeg',
    '/img/avatar/plain/x@jpeg',
    'data:image/svg+xml,<svg/>',
    'javascript:alert(1)',
  ]) {
    const p = instance('Post', [['avatar', text(elsewhere)]]);
    assert.equal(field(p, 'avatarPath'), '', elsewhere);
  }

  // a profile carries two of them, and neither is drawn from anywhere else
  const prof = instance('Profile', [
    ['handle', text('bsky.app')],
    ['avatar', text(`${cdn}/img/avatar/plain/did:plc:bsky/bafkreiavatar@jpeg`)],
    ['banner', text('https://elsewhere.test/banner.jpg')],
  ]);
  assert.equal(field(prof, 'avatarPath'), 'img/avatar/plain/did:plc:bsky/bafkreiavatar@jpeg');
  assert.equal(field(prof, 'bannerPath'), '');
});

test('liking is optimistic and announced, and leaves the record count alone', { skip: !built }, () => {
  emitted.length = 0;
  const uri = 'at://did:plc:alice000000000000000000/app.bsky.feed.post/3kaaa';
  let p = instance('Post', [['uri', text(uri)], ['likeCount', num(99)]]);
  assert.equal(field(p, 'likes'), '99');

  // on its own, a post is not `owned`, so it keeps the answer itself
  assert.equal(field(p, 'owned'), false);
  p = p.handleMessage('toggleLike', []);
  assert.equal(field(p, 'liked'), true);
  assert.equal(field(p, 'likes'), '100');
  // the count the record came with is untouched, so a refused write needs no
  // un-editing
  assert.equal(field(p, 'likeCount'), 99);
  assert.deepEqual(emitted, [['liked', [{ tag: 'text', val: uri }]]]);

  emitted.length = 0;
  p = p.handleMessage('toggleLike', []);
  assert.equal(field(p, 'liked'), false);
  assert.equal(field(p, 'likes'), '99');
  assert.deepEqual(emitted.map(([n]) => n), ['unliked']);

  // a message with nothing under it has no fold to toggle
  emitted.length = 0;
  assert.equal(p.handleMessage('toggleFold', []), undefined);
  assert.deepEqual(emitted, []);

  // a name this component does not answer falls through to the host, which is
  // what `unhandled` is for
  assert.equal(p.handleMessage('somethingElse', []), undefined);
  // and its state is exactly the declared fields, so it does not persist
  assert.deepEqual([...p.persist()], []);
});

const CONVERSATION = [
  { uri: 'at://a/app.bsky.feed.post/1', displayName: 'Alice', handle: 'alice.bsky.social', text: 'root', replyCount: 2, depth: 0 },
  { uri: 'at://b/app.bsky.feed.post/2', displayName: 'Bob', handle: 'bob.bsky.social', text: 'reply', replyCount: 1, depth: 1 },
  { uri: 'at://a/app.bsky.feed.post/3', displayName: 'Alice', handle: 'alice.bsky.social', text: 'reply to reply', depth: 2 },
  { uri: 'at://c/app.bsky.feed.post/4', displayName: 'Carol', handle: 'carol.bsky.social', text: 'other branch', depth: 1 },
];
const thread = (extra = []) =>
  instance('Thread', [['posts', list(CONVERSATION.map(message))], ...extra]);

test('a thread is a list of Posts, indented by depth', { skip: !built }, () => {
  const t = thread();
  // one child per message, each a real component with its own rich text
  assert.deepEqual(rowField(t, 'name'), ['Alice', 'Bob', 'Alice', 'Carol']);
  assert.deepEqual(rowField(t, 'text'), ['root', 'reply', 'reply to reply', 'other branch']);
  // an untrusted view has no `style` attribute, so the indent arrives as that
  // many rails to draw
  assert.deepEqual(rowField(t, 'rail').map((r) => r.length), [0, 1, 2, 1]);
  // and each row is told how much hangs under it, which is what its fold
  // button counts — the row cannot see the thread to work that out
  assert.deepEqual(rowField(t, 'foldable'), [3, 1, 0, 0]);
  assert.equal(t.compute('summary', []).val, '4 messages');
});

test('folding is the row\'s flag and the thread\'s filter, not one or the other', { skip: !built }, () => {
  const t = thread();
  const rows = field(t, 'rows');
  emitted.length = 0;

  // The row keeps its own flag — it returns a successor — AND announces, because
  // the thread is the only one that knows what sits under it.
  const folded = child(rows[1]).handleMessage('toggleFold', []);
  assert.notEqual(folded, undefined);
  assert.equal(field(folded, 'folded'), true);
  assert.equal(field(folded, 'foldLabel'), '+1');
  assert.deepEqual(emitted, [['folded', [{ tag: 'text', val: 'at://b/app.bsky.feed.post/2' }]]]);

  // The host writes that successor home, and the thread — hearing the bubble —
  // drops what was under it and keeps the bubble from travelling on to a page
  // that has no use for it.
  emitted.length = 0;
  const t2 = writeRow(t, 1, folded)
    .handleIntent('folded', [text('at://b/app.bsky.feed.post/2')]);
  assert.deepEqual(rowField(t2, 'name'), ['Alice', 'Bob', 'Carol']);
  assert.deepEqual(rowField(t2, 'folded'), [false, true, false]);
  assert.deepEqual(rowField(t2, 'foldLabel'), ['−', '+1', '−']);
  assert.equal(t2.compute('summary', []).val, '4 messages · 1 folded away');
  assert.deepEqual(emitted.map(([n]) => n), ['stopPropagation']);

  // The thread rebuilt NOTHING: every row it did not touch is the same child it
  // was, which is what keeps a like three rows down. (It used to destroy and
  // remake the folded row to hand it the flag back; now the row already has it,
  // and remaking it would throw away whatever else the reader had done.)
  const after = field(t2, 'rows');
  assert.equal(after[0], rows[0]);
  assert.equal(after[2], rows[3]);

  // folding the root takes everything below it
  const rootRow = child(field(t2, 'rows')[0]);
  const rootFolded = writeRow(t2, 0, rootRow.handleMessage('toggleFold', []))
    .handleIntent('folded', [text('at://a/app.bsky.feed.post/1')]);
  assert.deepEqual(rowField(rootFolded, 'name'), ['Alice']);
  // and unfolding puts them back
  const back = rootFolded
    .handleIntent('unfolded', [text('at://a/app.bsky.feed.post/1')])
    .handleIntent('unfolded', [text('at://b/app.bsky.feed.post/2')]);
  assert.equal(field(back, 'rows').length, 4);
});

test('a row keeps its own like, and still announces it', { skip: !built }, () => {
  const t = thread();
  emitted.length = 0;

  // The row is the one that changed, so the row is the one that returns a
  // successor. The thread has nothing to add — it does not handle the bubble at
  // all, and does not stop it: only whoever is above can write the record.
  const row = child(field(t, 'rows')[0]);
  const liked = row.handleMessage('toggleLike', []);
  assert.notEqual(liked, undefined);
  assert.equal(field(liked, 'liked'), true);
  // the count the record came with is untouched; the flag is added on top
  assert.equal(field(liked, 'likeCount'), 0);
  assert.equal(field(liked, 'likes'), '1');
  assert.deepEqual(emitted.map(([n]) => n), ['liked']);

  emitted.length = 0;
  const t2 = writeRow(t, 0, liked);
  assert.deepEqual(rowField(t2, 'liked'), [true, false, false, false]);
  assert.deepEqual(rowField(t2, 'likes'), ['1', '0', '0', '0']);
  // the thread neither claimed the bubble nor stopped it
  assert.equal(t2.handleIntent('liked', [text('at://a/app.bsky.feed.post/1')]), undefined);
  assert.deepEqual(emitted, []);

  const unliked = child(field(t2, 'rows')[0]).handleMessage('toggleLike', []);
  assert.equal(field(unliked, 'liked'), false);

  // a repost is the same shape, and lands on a different row
  const reposted = child(field(t2, 'rows')[3]).handleMessage('toggleRepost', []);
  const t3 = writeRow(t2, 3, reposted);
  assert.deepEqual(rowField(t3, 'reposted'), [false, false, false, true]);
  // and the like three rows up is still there, because nothing was rebuilt
  assert.deepEqual(rowField(t3, 'liked'), [true, false, false, false]);
});

test('the focused message is the one the thread was told about', { skip: !built }, () => {
  const t = thread([['focus', text('at://a/app.bsky.feed.post/3')]]);
  assert.deepEqual(rowField(t, 'focus'), [false, false, true, false]);

  // `focus` is declared, so the host's generated `setFocus` lands in with-field
  // — and rebuilds the rows, since a row is told at build time which it is
  const moved = t.withField('focus', text('at://c/app.bsky.feed.post/4'));
  assert.deepEqual(rowField(moved, 'focus'), [false, false, false, true]);
  assert.notDeepEqual(field(moved, 'rows'), field(t, 'rows'));
});

test('the host writes declared fields through with-field, not through handlers', { skip: !built }, () => {
  const t = thread();
  // rewriting the messages rebuilds the rows around them
  const two = t.withField('posts', list(CONVERSATION.slice(0, 2).map(message)));
  assert.deepEqual(rowField(two, 'name'), ['Alice', 'Bob']);
  // and a field this component does not have is refused rather than swallowed
  assert.equal(t.withField('nonsense', text('x')), undefined);
  // a thread is its declared fields plus host-owned tokens, so it keeps nothing
  assert.deepEqual([...t.persist()], []);

  const p = instance('Post', []);
  assert.equal(field(p.withField('text', text('hello')), 'text'), 'hello');
  // the type has to match: `likeCount` is a number, and a word is not one
  assert.equal(p.withField('likeCount', text('lots')), undefined);
});

test('a profile counts a follow on top of the number the record came with', { skip: !built }, () => {
  emitted.length = 0;
  let p = instance('Profile', [
    ['displayName', text('Alice Alpha')],
    ['handle', text('alice.bsky.social')],
    ['followersCount', num(12400)],
    ['followsCount', num(312)],
    ['postsCount', num(2870)],
    ['posts', list(CONVERSATION.slice(0, 2).map(message))],
  ]);
  assert.equal(field(p, 'followersLabel'), '12K');
  assert.equal(field(p, 'followsLabel'), '312');
  assert.equal(field(p, 'postsLabel'), '2.8K');
  assert.equal(p.compute('followLabel', []).val, 'Follow');

  p = p.handleMessage('toggleFollow', []);
  assert.equal(field(p, 'following'), true);
  assert.equal(field(p, 'followersLabel'), '12K');
  assert.equal(field(p, 'followersCount'), 12400);
  assert.equal(p.compute('followLabel', []).val, 'Following');
  assert.deepEqual(emitted, [['followed', [{ tag: 'text', val: 'alice.bsky.social' }]]]);

  // its recent messages are Posts too, standing on their own: a feed has no
  // depth and nothing to fold, whatever the records happened to carry
  assert.deepEqual(rowField(p, 'name'), ['Alice', 'Bob']);
  assert.deepEqual(rowField(p, 'rail').map((r) => r.length), [0, 0]);
  assert.deepEqual(rowField(p, 'foldable'), [0, 0]);
  assert.deepEqual(rowField(p, 'owned'), [true, true]);

  // A row of the feed keeps its own like, exactly as a row of a thread does.
  // The feed itself has nothing to add — no fold, so nothing it alone knows —
  // so it does not handle the bubble and does not stop it.
  const liked = child(field(p, 'rows')[0]).handleMessage('toggleLike', []);
  const withLike = writeRow(p, 0, liked);
  assert.deepEqual(rowField(withLike, 'liked'), [true, false]);
  assert.equal(p.handleIntent('liked', [text('at://a/app.bsky.feed.post/1')]), undefined);
  assert.match(p.compute('summary', []).val, /^Alice Alpha @alice\.bsky\.social — 12K followers/);
});

test('a profile says when it was created and what it pinned', { skip: !built }, () => {
  const p = instance('Profile', [
    ['handle', text('alice.bsky.social')],
    ['createdAt', text('2023-05-14T09:31:00Z')],
    ['pinnedPost', text('at://did:plc:alice/app.bsky.feed.post/3kaaa')],
  ]);
  // a date and not a duration: "3 years ago" needs a clock, and this bundle
  // has none
  assert.equal(field(p, 'joinedLabel'), 'Joined 14 May 2023');
  assert.equal(field(p, 'hasJoined'), true);
  // the link the prose has always offered, now under the view's own origin
  assert.equal(field(p, 'pinnedPath'), 'profile/alice.bsky.social/post/3kaaa');
  assert.equal(field(p, 'hasPinned'), true);

  // absent stays absent rather than becoming a link to nowhere
  const bare = instance('Profile', [['handle', text('alice.bsky.social')]]);
  assert.equal(field(bare, 'hasJoined'), false);
  assert.equal(field(bare, 'hasPinned'), false);
  assert.equal(field(bare, 'pinnedPath'), '');
  // and a pinned ref that is not a post has no page to point at, so it offers
  // none rather than one built out of a shrug
  const listed = instance('Profile', [
    ['handle', text('alice.bsky.social')],
    ['pinnedPost', text('at://did:plc:alice/app.bsky.graph.list/3kaaa')],
  ]);
  assert.equal(field(listed, 'hasPinned'), false);
});

test('a post says who put it in front of you, and what a moderator said about it', { skip: !built }, () => {
  const p = instance('Post', [
    ['handle', text('carol.bsky.social')],
    ['text', text('the write-up is out')],
    ['repostedBy', text('alice.bsky.social')],
    ['pinned', bool(true)],
    ['labels', list([text('!warn'), text('spam')])],
  ]);
  // the attribution is a line ABOVE the card: the author is never rewritten,
  // because the message is still the message
  assert.equal(field(p, 'handle'), 'carol.bsky.social');
  assert.equal(field(p, 'repostedBy'), 'alice.bsky.social');
  assert.equal(field(p, 'repostLabel'), 'Reposted by @alice.bsky.social');
  assert.equal(field(p, 'repostPath'), 'profile/alice.bsky.social');
  assert.equal(field(p, 'viaRepost'), true);
  assert.equal(field(p, 'hasAttribution'), true);

  assert.deepEqual(field(p, 'labels'), ['!warn', 'spam']);
  assert.equal(field(p, 'hasLabels'), true);
  assert.equal(field(p, 'labelTitle'), 'labelled !warn, spam by a moderation service');

  // a plain post says none of it, and draws no empty attribution strip
  const plainPost = instance('Post', [['text', text('hi')]]);
  assert.equal(field(plainPost, 'hasAttribution'), false);
  assert.equal(field(plainPost, 'viaRepost'), false);
  assert.equal(field(plainPost, 'hasLabels'), false);
  assert.equal(field(plainPost, 'repostLabel'), '');

  // labels also arrive in the shape the wire uses, so a host projecting the raw
  // record does not have to flatten them first
  const wire = instance('Post', [
    ['labels', list([map({ val: text('porn'), src: text('did:plc:labeller') })])],
  ]);
  assert.deepEqual(field(wire, 'labels'), ['porn']);
});

test('the three embeds are read, and the two the poster chose are not links', { skip: !built }, () => {
  const p = instance('Post', [
    ['handle', text('carol.bsky.social')],
    ['external', map({
      uri: text('https://www.example.com/blog/post?utm=1'),
      title: text('Dynamic components, end to end'),
      description: text('what a bundle may reach'),
      // the AppView re-hosts an unfurled thumbnail, so it lands on the origin
      // the view already names
      thumb: text('https://cdn.bsky.app/img/feed_thumbnail/plain/did/bafk1'),
    })],
  ]);
  assert.equal(field(p, 'hasExternal'), true);
  assert.equal(field(p, 'hasEmbed'), true);
  // the host is a LABEL, and the full target is what the tooltip carries: no
  // view can name an origin the person who posted it chose
  assert.equal(field(p, 'externalHost'), 'example.com');
  assert.equal(field(p, 'externalTarget'), 'https://www.example.com/blog/post?utm=1');
  assert.equal(field(p, 'externalThumbPath'), 'img/feed_thumbnail/plain/did/bafk1');
  // a thumbnail anywhere else is not drawn at all, which is the state a record
  // with no thumbnail already has
  const elsewhere = instance('Post', [
    ['external', map({ uri: text('https://example.com/x'), thumb: text('https://cdn.bsky.app.attacker.test/x') })],
  ]);
  assert.equal(field(elsewhere, 'externalThumbPath'), '');
  // and an unfurl with nowhere to point is not an embed
  const nowhere = instance('Post', [['external', map({ title: text('orphan') })]]);
  assert.equal(field(nowhere, 'hasExternal'), false);

  const q = instance('Post', [
    ['quote', map({
      uri: text('at://did:plc:alice/app.bsky.feed.post/3kaaa'),
      displayName: text('Alice Alpha'),
      handle: text('alice.bsky.social'),
      text: text('a component that cannot fetch'),
      createdAt: text('2026-08-11T14:03:00Z'),
    })],
  ]);
  assert.equal(field(q, 'hasQuote'), true);
  assert.equal(field(q, 'quoteName'), 'Alice Alpha');
  assert.equal(field(q, 'quoteHandleText'), '@alice.bsky.social');
  assert.equal(field(q, 'quoteInitials'), 'AA');
  assert.equal(field(q, 'quoteTime'), '11 Aug 2026, 14:03');
  // a quote IS on bsky.app, so unlike the unfurl it gets a path the view can
  // hang under its own literal origin
  assert.equal(field(q, 'quotePermalinkPath'), 'profile/alice.bsky.social/post/3kaaa');
  // a quote of a record that was deleted or blocked arrives empty, and an empty
  // card would say a message is there when it is not
  assert.equal(field(instance('Post', [['quote', map({})]]), 'hasQuote'), false);

  const v = instance('Post', [
    ['video', map({ thumb: text('https://cdn.bsky.app/img/thumb/plain/did/bafk2'), alt: text('a terminal') })],
  ]);
  assert.equal(field(v, 'hasVideo'), true);
  assert.equal(field(v, 'videoThumbPath'), 'img/thumb/plain/did/bafk2');
  assert.equal(field(v, 'videoAlt'), 'a terminal');
  // no poster frame and no alt text is nothing this bundle can draw
  assert.equal(field(instance('Post', [['video', map({})]]), 'hasVideo'), false);
  // a post with none of the three says so once, which is what the view gates on
  assert.equal(field(instance('Post', [['text', text('hi')]]), 'hasEmbed'), false);

  // an embed round-trips: the host projects it and writes it back unchanged,
  // and `nil` is the clear rather than a value nobody can read
  const back = p.withField('external', p.getField('external'));
  assert.equal(field(back, 'externalHost'), 'example.com');
  assert.equal(field(p.withField('external', { tag: 'nil' }), 'hasExternal'), false);
  // anything that is neither a record nor nil is refused, because emptying a
  // field because a write could not be understood is the quiet kind of wrong
  assert.equal(p.withField('external', text('https://example.com')), undefined);
});

test('a feed is a list, and says what the list left out', { skip: !built }, () => {
  const f = instance('Feed', [
    ['posts', list(CONVERSATION.slice(0, 3).map(message))],
    ['scope', map({
      truncated: bool(true),
      truncatedBy: text('limit'),
      more: bool(true),
      notes: list([text('search indexes recent public posts only')]),
    })],
  ]);
  // every row stands on its own: a feed has no reply structure to imply, which
  // is the whole reason it is not a Thread
  assert.deepEqual(rowField(f, 'name'), ['Alice', 'Bob', 'Alice']);
  assert.deepEqual(rowField(f, 'rail').map((r) => r.length), [0, 0, 0]);
  assert.deepEqual(rowField(f, 'foldable'), [0, 0, 0]);
  assert.deepEqual(rowField(f, 'focus'), [false, false, false]);
  assert.equal(f.compute('summary', []).val, '3 messages');
  // no heading unless one was given: the summary line stands on its own
  assert.equal(field(f, 'hasTitle'), false);
  const titled = instance('Feed', [
    ['title', text('@bsky.app — posts and replies')],
    ['posts', list(CONVERSATION.slice(0, 1).map(message))],
  ]);
  assert.equal(field(titled, 'title'), '@bsky.app — posts and replies');
  assert.equal(field(titled, 'hasTitle'), true);

  // the scope is a child of its own, and the feed keeps whether it has anything
  // to say — a token is a bridge handle, so a parent cannot read one back
  assert.equal(field(f, 'hasScope'), true);
  const s = child(f.getField('scope').val);
  assert.equal(field(s, 'hasAny'), true);
  assert.equal(field(s, 'truncatedLabel'), 'stopped at the limit cap — this is not everything');
  assert.equal(field(s, 'moreLabel'), 'more pages were not read');
  assert.deepEqual(field(s, 'notes'), ['search indexes recent public posts only']);
  assert.match(s.compute('summary', []).val, /^scope: stopped at the limit cap; more pages unread;/);

  // an answer with nothing to disclose still HAS a scope, and it draws nothing
  const complete = instance('Feed', [['posts', list(CONVERSATION.slice(0, 1).map(message))]]);
  assert.equal(field(complete, 'hasScope'), false);
  assert.equal(field(child(complete.getField('scope').val), 'hasAny'), false);
  assert.equal(child(complete.getField('scope').val).compute('summary', []).val, '');

  // a row of a feed keeps its own like and the feed does not claim the bubble,
  // the same way a profile's feed behaves
  const liked = child(field(f, 'rows')[0]).handleMessage('toggleLike', []);
  assert.deepEqual(rowField(writeRow(f, 0, liked), 'liked'), [true, false, false]);
  assert.equal(f.handleIntent('liked', [text('at://a/app.bsky.feed.post/1')]), undefined);

  // rewriting the messages rebuilds the rows and keeps the scope: a new list is
  // not a new claim about what was covered
  const two = f.withField('posts', list(CONVERSATION.slice(0, 2).map(message)));
  assert.deepEqual(rowField(two, 'name'), ['Alice', 'Bob']);
  assert.equal(field(two, 'hasScope'), true);

  // a feed summary counts what somebody else put in front of you
  const mixed = instance('Feed', [
    ['posts', list([
      message({ uri: 'at://a/app.bsky.feed.post/1', displayName: 'Alice' }),
      map({ uri: text('at://c/app.bsky.feed.post/9'), displayName: text('Carol'), repostedBy: text('alice.bsky.social') }),
    ])],
  ]);
  assert.equal(mixed.compute('summary', []).val, '2 messages · 1 reposted in');
  assert.deepEqual(rowField(mixed, 'repostLabel'), ['', 'Reposted by @alice.bsky.social']);
});

/// Seven messages, so a page size of three makes three pages and a last one
/// that is not full — the case an off-by-one in `rangeLabel` would show up in.
const MANY = Array.from({ length: 7 }, (_, i) => ({
  uri: `at://a/app.bsky.feed.post/${100 + i}`,
  displayName: 'Alice', handle: 'alice.bsky.social', text: `message ${i}`,
}));
const manyPosts = () => list(MANY.map(message));

test('a long feed is paged, and a page is not a rebuild', { skip: !built }, () => {
  // Below the threshold nothing changed: no window, no footer, every row on
  // screen — which is what these cards did before they could page at all.
  const short = instance('Feed', [['posts', list(CONVERSATION.map(message))]]);
  assert.equal(short.compute('paged', []).val, false);
  assert.equal(field(short, 'pageCount'), 1);
  assert.equal(field(short, 'rows').length, 4);

  // Asking for a page size is asking to be paged, whatever the length.
  let f = instance('Feed', [['posts', manyPosts()], ['pageSize', num(3)]]);
  assert.equal(f.compute('paged', []).val, true);
  // 1-based, because it is a label rather than an index
  assert.equal(field(f, 'page'), 1);
  assert.equal(field(f, 'pageCount'), 3);
  assert.equal(f.compute('rangeLabel', []).val, '1–3 of 7');
  assert.deepEqual(rowField(f, 'text'), ['message 0', 'message 1', 'message 2']);
  // the summary is about the feed, not about the page
  assert.equal(f.compute('summary', []).val, '7 messages');

  // A button that would not move answers `unchanged` rather than rebuilding the
  // same page, and a name the pager does not know keeps travelling.
  assert.equal(f.handleMessage('prevPage', []), undefined);
  assert.equal(f.handleMessage('somethingElse', []), undefined);

  const first = field(f, 'rows');
  f = f.handleMessage('nextPage', []);
  assert.deepEqual(rowField(f, 'text'), ['message 3', 'message 4', 'message 5']);
  assert.equal(f.compute('atFirst', []).val, false);

  // The host writes a successor home by its position IN THE PAGE — position 0
  // here is message 3 — so the write-back and the render have to agree about
  // which rows those are.
  const liked = child(field(f, 'rows')[0]).handleMessage('toggleLike', []);
  f = writeRow(f, 0, liked);
  assert.deepEqual(rowField(f, 'liked'), [true, false, false]);

  // Page back: the rows are the same children, not rebuilt ones, so the like
  // three rows on is still where the reader left it.
  f = f.handleMessage('prevPage', []);
  assert.deepEqual(field(f, 'rows'), first);
  assert.deepEqual(rowField(f, 'liked'), [false, false, false]);
  assert.deepEqual(rowField(f.handleMessage('nextPage', []), 'liked'), [true, false, false]);

  // the last page is the short one, and it says so
  const end = f.handleMessage('lastPage', []);
  assert.deepEqual(rowField(end, 'text'), ['message 6']);
  assert.equal(end.compute('rangeLabel', []).val, '7–7 of 7');
  assert.equal(end.compute('atLast', []).val, true);
  assert.equal(end.handleMessage('nextPage', []), undefined);

  // A new list starts at its beginning, and so does a window a host just chose.
  assert.equal(field(end.withField('posts', manyPosts()), 'page'), 1);
  assert.equal(field(end.withField('pageSize', num(2)), 'page'), 1);
  assert.equal(field(end.withField('pageSize', num(2)), 'pageCount'), 4);
});

test('a thread pages what the folds left, and a profile pages its messages', { skip: !built }, () => {
  // A thread's list is what is unfolded, so the pager counts those and not the
  // records: fold the branch away and the page it was on goes with it.
  const posts = MANY.map((m, i) => ({ ...m, depth: i === 0 ? 0 : 1 }));
  let t = instance('Thread', [['posts', list(posts.map(message))], ['pageSize', num(3)]]);
  assert.equal(field(t, 'pageCount'), 3);
  t = t.handleMessage('lastPage', []);
  assert.deepEqual(rowField(t, 'text'), ['message 6']);

  // Folding the root hides the six under it, which leaves one page — and the
  // stored page comes back inside it rather than showing nothing.
  t = t.handleIntent('folded', [text(posts[0].uri)]);
  assert.equal(field(t, 'pageCount'), 1);
  assert.equal(t.compute('paged', []).val, false);
  assert.deepEqual(rowField(t, 'text'), ['message 0']);

  // An account's messages page the same way, with no fold in front of them.
  const p = instance('Profile', [
    ['handle', text('alice.bsky.social')],
    ['posts', manyPosts()],
    ['pageSize', num(4)],
  ]);
  assert.equal(field(p, 'pageCount'), 2);
  assert.equal(p.compute('rangeLabel', []).val, '1–4 of 7');
  assert.deepEqual(rowField(p.handleMessage('nextPage', []), 'text'),
    ['message 4', 'message 5', 'message 6']);
  // and its own button still works, which is the arm the pager was added beside
  assert.notEqual(p.handleMessage('toggleFollow', []), undefined);
});

test('a thread carries a scope too, and keeps it across a rewrite', { skip: !built }, () => {
  const t = instance('Thread', [
    ['posts', list(CONVERSATION.map(message))],
    ['scope', map({ truncated: bool(true), truncatedBy: text('depth') })],
  ]);
  assert.equal(field(t, 'hasScope'), true);
  const s = child(t.getField('scope').val);
  assert.equal(field(s, 'truncatedLabel'), 'stopped at the depth cap — this is not everything');
  assert.equal(field(s, 'moreLabel'), '');
  const two = t.withField('posts', list(CONVERSATION.slice(0, 2).map(message)));
  assert.equal(field(two, 'hasScope'), true);
  assert.equal(child(two.getField('scope').val), s);
});
