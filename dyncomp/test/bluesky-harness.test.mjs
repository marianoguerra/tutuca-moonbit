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
//   3. Folding is a bubble from a row and a filter here: the children are built
//      once, so a like three rows down survives a fold.
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
  emit: (name, args) => emitted.push([name, args]),
  send: () => {},
  sendAt: () => {},
  bubbleAt: () => {},
  stopPropagation: () => emitted.push(['stopPropagation', []]),
  request: () => {},
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
    'tutuca:component/values@0.6.0': values,
    'tutuca:component/values': values,
    'tutuca:component/control@0.6.0': control,
    'tutuca:component/control': control,
  });
  guest = root.guest;
  manifest = JSON.parse(
    await readFile(new URL('../../guests/bluesky/manifest.json', import.meta.url), 'utf8'),
  );
  const rawEvent = guest.Instance.prototype.handleEvent;
  guest.Instance.prototype.handleEvent = function (...args) {
    const result = rawEvent.call(this, ...args);
    drain();
    return result.tag === 'changed' ? result.val : undefined;
  };
  const rawWith = guest.Instance.prototype.withField;
  guest.Instance.prototype.withField = function (...args) {
    const next = rawWith.call(this, ...args);
    drain();
    return next;
  };
});

test('the static manifest declares three components and asks for nothing', { skip: !built }, () => {
  const m = manifest;
  assert.equal(m.apiVersion, 6);
  assert.equal(m.moduleName, 'blueskylib');
  // the whole point of this bundle: no capability, so a stock host loads it
  // without anyone having to decide anything
  assert.deepEqual(m.capabilities, []);
  assert.deepEqual(m.components.map((c) => c.name), ['Post', 'Thread', 'Profile']);

  const [post, thread, profile] = m.components;
  assert.deepEqual(post.fields.map((f) => f.name), [
    'uri', 'displayName', 'handle', 'text', 'createdAt', 'facets', 'images',
    'replyCount', 'repostCount', 'likeCount', 'liked', 'reposted',
    'depth', 'focus', 'foldable', 'folded', 'owned',
  ]);
  assert.deepEqual(post.bubbles, ['liked', 'unliked', 'reposted', 'unreposted', 'folded', 'unfolded']);
  assert.deepEqual(thread.fields.map((f) => f.name), ['posts', 'focus']);
  // the thread's bubbles are the ones it HEARS from its rows
  assert.deepEqual(thread.bubbles, ['folded', 'unfolded', 'liked', 'unliked', 'reposted', 'unreposted']);
  assert.deepEqual(profile.bubbles, ['followed', 'unfollowed', 'liked', 'unliked', 'reposted', 'unreposted']);
  // every component ships a fixture, so dropping the bundle shows something
  for (const c of m.components) assert.equal(c.inits.length, 1);
  // and every fixture is JSON the host can actually read
  for (const c of m.components) JSON.parse(c.inits[0].argsJson);
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
  assert.deepEqual(field(p, 'segments'), [
    { text: '🚀 shipped it — ', target: '', kind: 'text' },
    { text: 'tutuca.dev/dyncomp', target: 'https://tutuca.dev/dyncomp', kind: 'link' },
    { text: ', thanks ', target: '', kind: 'text' },
    { text: '@bob.bsky.social', target: 'bsky.app/profile/bob.bsky.social', kind: 'mention' },
    { text: ' ', target: '', kind: 'text' },
    { text: '#wasm', target: 'bsky.app/hashtag/wasm', kind: 'tag' },
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
    { text: 'héllo ', target: '', kind: 'text' },
    { text: 'world', target: 'https://example.com', kind: 'link' },
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
});

test('liking is optimistic and announced, and leaves the record count alone', { skip: !built }, () => {
  emitted.length = 0;
  const uri = 'at://did:plc:alice000000000000000000/app.bsky.feed.post/3kaaa';
  let p = instance('Post', [['uri', text(uri)], ['likeCount', num(99)]]);
  assert.equal(field(p, 'likes'), '99');

  // on its own, a post is not `owned`, so it keeps the answer itself
  assert.equal(field(p, 'owned'), false);
  p = p.handleEvent('input', 'toggleLike', []);
  assert.equal(field(p, 'liked'), true);
  assert.equal(field(p, 'likes'), '100');
  // the count the record came with is untouched, so a refused write needs no
  // un-editing
  assert.equal(field(p, 'likeCount'), 99);
  assert.deepEqual(emitted, [['liked', [{ tag: 'text', val: uri }]]]);

  emitted.length = 0;
  p = p.handleEvent('input', 'toggleLike', []);
  assert.equal(field(p, 'liked'), false);
  assert.equal(field(p, 'likes'), '99');
  assert.deepEqual(emitted.map(([n]) => n), ['unliked']);

  // a message with nothing under it has no fold to toggle
  emitted.length = 0;
  assert.equal(p.handleEvent('input', 'toggleFold', []), undefined);
  assert.deepEqual(emitted, []);

  // a name this component does not answer falls through to the host, which is
  // what `unhandled` is for
  assert.equal(p.handleEvent('input', 'somethingElse', []), undefined);
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
  assert.equal(t.callMethod('summary', []).val, '4 messages');
});

test('folding is a bubble from a row and a filter here', { skip: !built }, () => {
  const t = thread();
  const rows = field(t, 'rows');
  emitted.length = 0;

  // The row announces and keeps nothing: its state belongs to the thread, so
  // `toggleFold` is `unchanged` plus a bubble.
  assert.equal(child(rows[1]).handleEvent('input', 'toggleFold', []), undefined);
  assert.deepEqual(emitted, [['folded', [{ tag: 'text', val: 'at://b/app.bsky.feed.post/2' }]]]);

  // …and the thread, hearing it, drops what was under it, hands that row back
  // rebuilt with the flag, and keeps the bubble from travelling on to a page
  // that has no use for it
  emitted.length = 0;
  const t2 = t.handleEvent('bubble', 'folded', [text('at://b/app.bsky.feed.post/2')]);
  assert.deepEqual(rowField(t2, 'name'), ['Alice', 'Bob', 'Carol']);
  assert.deepEqual(rowField(t2, 'folded'), [false, true, false]);
  assert.deepEqual(rowField(t2, 'foldLabel'), ['−', '+1', '−']);
  assert.equal(t2.callMethod('summary', []).val, '4 messages · 1 folded away');
  assert.deepEqual(emitted.map(([n]) => n), ['stopPropagation']);

  // only the folded row was rebuilt; the others are the same children, which
  // is what keeps a like three rows down
  const after = field(t2, 'rows');
  assert.equal(after[0], rows[0]);
  assert.notEqual(after[1], rows[1]);

  // folding the root takes everything below it
  const rootFolded = t2.handleEvent('bubble', 'folded', [text('at://a/app.bsky.feed.post/1')]);
  assert.deepEqual(rowField(rootFolded, 'name'), ['Alice']);
  // and unfolding puts them back
  const back = rootFolded
    .handleEvent('bubble', 'unfolded', [text('at://a/app.bsky.feed.post/1')])
    .handleEvent('bubble', 'unfolded', [text('at://b/app.bsky.feed.post/2')]);
  assert.equal(field(back, 'rows').length, 4);
  assert.deepEqual(rowField(back, 'folded'), [false, false, false, false]);

  // a row with nothing under it changes nothing, even if it says it folded
  const leaf = t.handleEvent('bubble', 'folded', [text('at://c/app.bsky.feed.post/4')]);
  assert.equal(field(leaf, 'rows').length, 4);
});

test('a row liked in a thread is kept BY the thread, and still announced', { skip: !built }, () => {
  const t = thread();
  emitted.length = 0;

  // the row announces; it does not keep the like, so nothing is superseded and
  // nothing has to travel back into the thread's list of children
  assert.equal(child(field(t, 'rows')[0]).handleEvent('input', 'toggleLike', []), undefined);
  assert.deepEqual(emitted.map(([n]) => n), ['liked']);

  emitted.length = 0;
  const liked = t.handleEvent('bubble', 'liked', [text('at://a/app.bsky.feed.post/1')]);
  assert.deepEqual(rowField(liked, 'liked'), [true, false, false, false]);
  // the count the record came with is still what it was; the flag is added on
  assert.deepEqual(rowField(liked, 'likeCount'), [0, 0, 0, 0]);
  assert.deepEqual(rowField(liked, 'likes'), ['1', '0', '0', '0']);
  // and the bubble is NOT stopped: only whoever is above can write the record
  assert.deepEqual(emitted, []);

  const unliked = liked.handleEvent('bubble', 'unliked', [text('at://a/app.bsky.feed.post/1')]);
  assert.deepEqual(rowField(unliked, 'liked'), [false, false, false, false]);

  // a repost is the same shape. Note this continues from the LATEST thread
  // rather than from `t`: rebuilding a row releases the token the row had, so
  // the superseded instance that still names it is not one to read again —
  // which is true of a superseded instance anyway.
  const reposted = unliked.handleEvent('bubble', 'reposted', [text('at://c/app.bsky.feed.post/4')]);
  assert.deepEqual(rowField(reposted, 'reposted'), [false, false, false, true]);

  // a bubble about a message this thread does not have changes nothing
  assert.equal(reposted.handleEvent('bubble', 'liked', [text('at://z/app.bsky.feed.post/9')]), undefined);
  // and one from a message with no uri cannot be tracked at all
  assert.equal(reposted.handleEvent('bubble', 'liked', [text('')]), undefined);
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
  assert.equal(p.callMethod('followLabel', []).val, 'Follow');

  p = p.handleEvent('input', 'toggleFollow', []);
  assert.equal(field(p, 'following'), true);
  assert.equal(field(p, 'followersLabel'), '12K');
  assert.equal(field(p, 'followersCount'), 12400);
  assert.equal(p.callMethod('followLabel', []).val, 'Following');
  assert.deepEqual(emitted, [['followed', [{ tag: 'text', val: 'alice.bsky.social' }]]]);

  // its recent messages are Posts too, standing on their own: a feed has no
  // depth and nothing to fold, whatever the records happened to carry
  assert.deepEqual(rowField(p, 'name'), ['Alice', 'Bob']);
  assert.deepEqual(rowField(p, 'rail').map((r) => r.length), [0, 0]);
  assert.deepEqual(rowField(p, 'foldable'), [0, 0]);
  assert.deepEqual(rowField(p, 'owned'), [true, true]);

  // and a row of the feed is kept the same way a thread keeps one
  const withLike = p.handleEvent('bubble', 'liked', [text('at://a/app.bsky.feed.post/1')]);
  assert.deepEqual(rowField(withLike, 'liked'), [true, false]);
  assert.match(p.callMethod('summary', []).val, /^Alice Alpha @alice\.bsky\.social — 12K followers/);
});
