// The mastodon guest over the contract, driven headlessly by the same fake host
// the other harnesses use. Build it first:
//   node guests/build-guest.mjs mastodon
// then:
//   node --test dyncomp/test/mastodon-harness.test.mjs
//
// This bundle READS someone else's records, so what is worth checking is not
// "does a post render" — the views are the host's job — but the five things the
// guest decides:
//
//   1. The rich text is FOUND rather than given. Mastodon's `content` is HTML
//      and an untrusted bundle may not emit markup, so the guest scans plain
//      text for `#tag`, `@mention` and `https://…` — and then links only what
//      the record's own `tags` / `mentions` confirm, because only the server
//      knows which of those runs resolved.
//   2. One picture origin covers a FEDERATED timeline, because the server
//      proxies what it federates (`/cache/…`). A lookalike host does not.
//   3. A remote status has no local permalink, and that is the one thing
//      proxying does not fix.
//   4. A poll is a CHILD component, made through `control.make-instance`, and
//      it owns which option is picked — a single choice moves every share.
//   5. The engagement flags stay APART from the counts the record came with.
//
// The fake host below implements `make-instance` the way the real bridge does
// (reserve a token now, construct after the call returns), because a guest that
// creates children is exactly what that rule exists for.
import { test, before } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const jsDir = new URL('../../guests/mastodon/dist/js/', import.meta.url);
const built = existsSync(fileURLToPath(new URL('mastodon.component.js', jsDir)));

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
/// The child a token names, and the field the view would read off it.
const child = (token) => children.get(token);
const rowField = (inst, name) => field(inst, 'rows').map((t) => field(child(t), name));

/// What the real bridge does when a guest returns a successor: give it a handle
/// of its own, in the same table `make-instance` fills.
const register = (inst) => { const t = nextToken++; children.set(t, inst); return t; };

/// The host writing a changed child home: it hands the parent its WHOLE list
/// with the new instance in place of the old one.
const writeRow = (parent, at, next, listField = 'rows') => {
  const tokens = field(parent, listField).slice();
  tokens[at] = register(next);
  return parent.withField(listField, list(tokens.map((t) => ({ tag: 'instance', val: t }))));
};

/// A guest value out of a plain JS one, so a fixture reads like the JSON it is.
const value = (v) => {
  if (Array.isArray(v)) return list(v.map(value));
  if (v !== null && typeof v === 'object') {
    return map(Object.fromEntries(Object.entries(v).map(([k, x]) => [k, value(x)])));
  }
  if (typeof v === 'number') return num(v);
  if (typeof v === 'boolean') return bool(v);
  return text(String(v));
};
const args = (obj) => Object.entries(obj).map(([k, v]) => [k, value(v)]);

let guest;
let manifest;
/// Construct what the guest asked for while it was running. The bridge does
/// this after every call into the guest, because the Component Model forbids
/// re-entering one while a call is active. It drains RECURSIVELY: a Status
/// reserves a Poll while it is itself being constructed.
const drain = () => {
  while (pending.length) {
    const [token, component, a] = pending.shift();
    children.set(token, new guest.Instance(component, a));
  }
};
const instance = (component, obj) => {
  const inst = new guest.Instance(component, args(obj));
  drain();
  return inst;
};

before(async () => {
  if (!built) return;
  const { instantiate } = await import(new URL('mastodon.component.js', jsDir));
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
    await readFile(new URL('../../guests/mastodon/manifest.json', import.meta.url), 'utf8'),
  );
  const rawEvent = guest.Instance.prototype.handleEvent;
  guest.Instance.prototype.handleEvent = function (...a) {
    const result = rawEvent.call(this, ...a);
    drain();
    return result.tag === 'changed' ? result.val : undefined;
  };
  const rawWith = guest.Instance.prototype.withField;
  guest.Instance.prototype.withField = function (...a) {
    const next = rawWith.call(this, ...a);
    drain();
    return next;
  };
});

test('the static manifest declares six components and asks for one capability', { skip: !built }, () => {
  const m = manifest;
  assert.equal(m.apiVersion, 6);
  assert.equal(m.moduleName, 'mastodonlib');
  // the one thing this bundle asks a host for, and it asks with a reason: the
  // origins its views name are the whole of its network reach
  assert.deepEqual(m.capabilities.map((c) => c.cap), ['cap-external-urls']);
  assert.match(m.capabilities[0].reason, /files\.mastodon\.social/);
  assert.deepEqual(m.components.map((c) => c.name),
    ['Scope', 'Status', 'Poll', 'Thread', 'Timeline', 'Profile']);

  const [scope, status, poll, thread, timeline, profile] = m.components;
  assert.deepEqual(status.bubbles, [
    'favourited', 'unfavourited', 'boosted', 'unboosted',
    'bookmarked', 'unbookmarked', 'replyTo', 'folded', 'unfolded',
  ]);
  assert.deepEqual(poll.bubbles, ['voted', 'unvoted']);
  assert.deepEqual(thread.fields.map((f) => f.name), ['posts', 'focus', 'scope']);
  assert.deepEqual(timeline.fields.map((f) => f.name), ['title', 'posts', 'query', 'mediaOnly', 'scope']);
  // field-for-field the component the bluesky bundle has, and that is the point rather than a
  // coincidence: a host drawing both should not learn two spellings of "this is not everything"
  assert.deepEqual(scope.fields.map((f) => f.name), ['truncated', 'truncatedBy', 'more', 'notes']);
  assert.ok(profile.fields.some((f) => f.name === 'fields'));
  // every component ships a fixture, so dropping the bundle shows something,
  // and every fixture is JSON the host can actually read
  for (const c of m.components) {
    assert.ok(c.inits.length >= 1, c.name);
    for (const i of c.inits) JSON.parse(i.argsJson);
  }
  // the fixtures with pictures point at the origin the views name, so the
  // gallery shows the loaded state and not only the fallback
  for (const [name, init] of [['Status', 'with pictures'], ['Profile', 'mastodon']]) {
    const a = JSON.parse(m.components.find((c) => c.name === name).inits.find((i) => i.name === init).argsJson);
    assert.ok(a.avatar.startsWith('https://files.mastodon.social/'), name);
  }
  // and the federated one points at the same origin through the proxy path,
  // which is the whole reason one origin is enough
  const remote = JSON.parse(
    m.components.find((c) => c.name === 'Status').inits.find((i) => i.name === 'from another server').argsJson,
  );
  assert.ok(remote.avatar.startsWith('https://files.mastodon.social/cache/'));
  assert.ok(remote.acct.includes('@'));
});

test('a post finds its own entities, and links only the ones the record confirms', { skip: !built }, () => {
  const s = instance('Status', {
    acct: 'alice',
    content: 'hello @bob and @nobody, see https://tutuca.dev/dyncomp #wasm #notatag',
    // the server resolved one mention and one hashtag; the other two runs are
    // shapes anybody can type, and this bundle does not guess on its behalf
    mentions: ['bob@other.test'],
    tags: ['wasm'],
  });
  assert.deepEqual(field(s, 'segments'), [
    { text: 'hello ', target: '', path: '', external: false, kind: 'text' },
    { text: '@bob', target: 'mastodon.social/@bob@other.test', path: '@bob@other.test', external: false, kind: 'mention' },
    { text: ' and @nobody, see ', target: '', path: '', external: false, kind: 'text' },
    // a link's origin belongs to whoever posted it, so no view can name it: it
    // stays `external` — text, with the whole url in the tooltip
    { text: 'tutuca.dev/dyncomp', target: 'https://tutuca.dev/dyncomp', path: '', external: true, kind: 'link' },
    { text: ' ', target: '', path: '', external: false, kind: 'text' },
    { text: '#wasm', target: 'mastodon.social/tags/wasm', path: 'tags/wasm', external: false, kind: 'tag' },
    { text: ' #notatag', target: '', path: '', external: false, kind: 'text' },
  ]);
});

test('a link is shortened the way mastodon shortens one, and keeps its whole url', { skip: !built }, () => {
  const url = 'https://blog.joinmastodon.org/2026/08/sharing-guidelines-about-mastodons-trade-mark-policy/';
  const s = instance('Status', { content: `read it here: ${url} (worth it).` });
  const [, link, tail] = field(s, 'segments');
  // the scheme is dropped and the tail cut at 30 characters, which is what the
  // `invisible` / `ellipsis` spans in Mastodon's own HTML do
  assert.equal(link.text, 'blog.joinmastodon.org/2026/08/…');
  assert.equal(link.target, url);
  assert.equal(link.path, '');
  // the sentence's punctuation is the sentence's, not the url's
  assert.equal(tail.text, ' (worth it).');

  // a `(` inside the url keeps its own `)`
  const wiki = 'https://en.wikipedia.org/wiki/Fediverse_(disambiguation)';
  assert.equal(field(instance('Status', { content: wiki }), 'segments')[0].target, wiki);
  // and an emoji before one does not shift the cut, since nothing here counts
  // bytes: the runs put back together are still the post
  const body = '🚀 shipped https://tutuca.dev/x now';
  const segs = field(instance('Status', { content: body }), 'segments');
  assert.deepEqual(segs.map((x) => x.kind), ['text', 'link', 'text']);
  assert.equal(segs[0].text, '🚀 shipped ');
  assert.equal(segs[2].text, ' now');
});

test('a picture is a path under the one origin the views name', { skip: !built }, () => {
  const host = 'https://files.mastodon.social';
  const shown = instance('Status', {
    displayName: 'War and Peas',
    avatar: `${host}/accounts/avatars/000/233/670/original/c051f22ff243a7a5.jpg`,
    media: [
      { description: 'a comic', previewUrl: `${host}/media_attachments/files/1/small/x.jpeg`, url: `${host}/media_attachments/files/1/original/x.jpeg`, type: 'image' },
      { description: 'no picture came with this one' },
    ],
  });
  // what crosses to the view is the PATH; the origin is the view's literal, so
  // nothing this bundle computes can move it
  assert.equal(field(shown, 'avatarPath'), 'accounts/avatars/000/233/670/original/c051f22ff243a7a5.jpg');
  assert.deepEqual(field(shown, 'mediaItems'), [
    { description: 'a comic', path: 'media_attachments/files/1/small/x.jpeg', fullPath: 'media_attachments/files/1/original/x.jpeg', type: 'image', described: true },
    { description: 'no picture came with this one', path: '', fullPath: '', type: 'image', described: true },
  ]);
  // and the record keeps the url it arrived with, so a host projecting the
  // field back gets what it wrote
  assert.equal(field(shown, 'avatar'), `${host}/accounts/avatars/000/233/670/original/c051f22ff243a7a5.jpg`);

  // A remote account's picture is on the SAME origin, under the proxy path.
  // That is the whole reason a federated reader can name one host.
  const remote = instance('Status', {
    acct: 'servo@floss.social',
    avatar: `${host}/cache/accounts/avatars/109/678/original/c3434ec91ea114b5.jpg`,
  });
  assert.equal(field(remote, 'avatarPath'), 'cache/accounts/avatars/109/678/original/c3434ec91ea114b5.jpg');

  // Everything else is no picture at all — which is the state the initials
  // under it were already drawing.
  for (const elsewhere of [
    'https://files.mastodon.social.attacker.test/accounts/avatars/x.png',
    'https://files.mastodon.social@attacker.test/accounts/avatars/x.png',
    'http://files.mastodon.social/accounts/avatars/x.png',
    'https://mastodon.social/accounts/avatars/x.png',
    '/accounts/avatars/x.png',
    'data:image/svg+xml,<svg/>',
    'javascript:alert(1)',
  ]) {
    assert.equal(field(instance('Status', { avatar: elsewhere }), 'avatarPath'), '', elsewhere);
  }
});

test('a local status has a permalink; a federated one has an address', { skip: !built }, () => {
  const local = instance('Status', {
    id: '117083691112770390',
    acct: 'Mastodon',
    url: 'https://mastodon.social/@Mastodon/117083691112770390',
  });
  assert.equal(field(local, 'permalinkPath'), '@Mastodon/117083691112770390');
  assert.equal(field(local, 'permalink'), 'mastodon.social/@Mastodon/117083691112770390');
  assert.equal(field(local, 'remoteLink'), false);
  // the profile is a page on THIS server either way, so it never falls back
  assert.equal(field(local, 'profilePath'), '@Mastodon');
  assert.equal(field(local, 'handleText'), '@Mastodon@mastodon.social');

  // A status from another server is a page on that server, and no view can name
  // its origin — so it is selectable text, exactly as a posted link is.
  const remote = instance('Status', {
    id: '117088598872448386',
    acct: 'servo@floss.social',
    url: 'https://floss.social/@servo/117088597479886002',
  });
  assert.equal(field(remote, 'permalinkPath'), '');
  assert.equal(field(remote, 'remoteLink'), true);
  assert.equal(field(remote, 'permalink'), 'floss.social/@servo/117088597479886002');
  // but its profile still is, because this server renders remote profiles too
  assert.equal(field(remote, 'profilePath'), '@servo@floss.social');
  assert.equal(field(remote, 'handleText'), '@servo@floss.social');
});

test('the projections a view reads: name, initials, time, counts, visibility', { skip: !built }, () => {
  const s = instance('Status', {
    displayName: 'Prof. Sam Lawler',
    acct: 'sundogplanets',
    createdAt: '2026-08-13T14:22:20.242Z',
    repliesCount: 8,
    reblogsCount: 1234,
    favouritesCount: 2400000,
    visibility: 'unlisted',
  });
  assert.equal(field(s, 'name'), 'Prof. Sam Lawler');
  assert.equal(field(s, 'initials'), 'PS');
  // no clock is involved: the stamp is formatted from the record itself
  assert.equal(field(s, 'time'), '13 Aug 2026, 14:22');
  assert.equal(field(s, 'replies'), '8');
  assert.equal(field(s, 'reblogs'), '1.2K');
  assert.equal(field(s, 'favourites'), '2.4M');
  assert.equal(field(s, 'visibilityGlyph'), '🔓');
  assert.equal(field(s, 'visibilityLabel'), 'Unlisted');
  // standing on its own: no rails to draw and no fold button
  assert.deepEqual(field(s, 'rail'), []);
  assert.equal(field(s, 'foldable'), 0);

  // a display name it does not have falls back to the handle
  const bare = instance('Status', { acct: 'bob@other.test' });
  assert.equal(field(bare, 'name'), 'bob@other.test');
  assert.equal(field(bare, 'initials'), 'BO');
  // a stamp this bundle cannot read is shown as it arrived rather than blanked
  assert.equal(field(instance('Status', { createdAt: 'last tuesday' }), 'time'), 'last tuesday');
});

test('favouriting is optimistic and announced, and leaves the record count alone', { skip: !built }, () => {
  emitted.length = 0;
  let s = instance('Status', { id: '117', favouritesCount: 99 });
  assert.equal(field(s, 'favourites'), '99');
  assert.equal(field(s, 'owned'), false);

  s = s.handleEvent('input', 'toggleFavourite', []);
  assert.equal(field(s, 'favourited'), true);
  assert.equal(field(s, 'favourites'), '100');
  // the count the record came with is untouched, so a refused write needs no
  // un-editing
  assert.equal(field(s, 'favouritesCount'), 99);
  assert.deepEqual(emitted, [['favourited', [{ tag: 'text', val: '117' }]]]);

  emitted.length = 0;
  s = s.handleEvent('input', 'toggleFavourite', []);
  assert.equal(field(s, 'favourited'), false);
  assert.deepEqual(emitted.map(([n]) => n), ['unfavourited']);

  // replying has no composer here, so it is only the announcement — and it
  // changes nothing, which is what `unchanged` is for
  emitted.length = 0;
  assert.equal(s.handleEvent('input', 'reply', []), undefined);
  assert.deepEqual(emitted.map(([n]) => n), ['replyTo']);

  // a name this component does not answer falls through to the host
  emitted.length = 0;
  assert.equal(s.handleEvent('input', 'somethingElse', []), undefined);
  assert.deepEqual(emitted, []);
  // and its state is exactly the declared fields, so it does not persist
  assert.deepEqual([...s.persist()], []);
});

test('a post nobody may boost refuses to be boosted', { skip: !built }, () => {
  for (const visibility of ['private', 'direct']) {
    emitted.length = 0;
    const s = instance('Status', { id: '1', visibility, reblogsCount: 4 });
    assert.equal(s.handleEvent('input', 'toggleBoost', []), undefined);
    assert.deepEqual(emitted, [], visibility);
    assert.match(s.callMethod('boostTitle', []).val, /does not allow boosting/);
  }
  // and one anybody may is boosted the way a favourite is favourited
  emitted.length = 0;
  const open = instance('Status', { id: '1', visibility: 'public', reblogsCount: 4 })
    .handleEvent('input', 'toggleBoost', []);
  assert.equal(field(open, 'reblogs'), '5');
  assert.deepEqual(emitted.map(([n]) => n), ['boosted']);
});

test('a content warning hides the body until the reader asks, and says nothing about it', { skip: !built }, () => {
  emitted.length = 0;
  let s = instance('Status', { spoilerText: 'spoilers for the finale', content: 'they were fine' });
  assert.equal(field(s, 'hasSpoiler'), true);
  assert.equal(field(s, 'bodyShown'), false);
  assert.equal(s.callMethod('revealLabel', []).val, 'Show more');

  s = s.handleEvent('input', 'toggleReveal', []);
  assert.equal(field(s, 'bodyShown'), true);
  assert.equal(s.callMethod('revealLabel', []).val, 'Show less');
  // unlike a favourite there is nothing for a host to write, so nothing is said
  assert.deepEqual(emitted, []);

  // a post with no warning has nothing to open
  const plainPost = instance('Status', { content: 'no warning here' });
  assert.equal(field(plainPost, 'bodyShown'), true);
  assert.equal(plainPost.handleEvent('input', 'toggleReveal', []), undefined);
});

const POLL = {
  options: [
    { title: 'yes, if the view names the origin', votesCount: 41 },
    { title: 'no, an image is a GET it chose', votesCount: 17 },
    { title: 'only from the host\'s own origin', votesCount: 8 },
  ],
  votesCount: 66,
  votersCount: 66,
  expiresAt: '2026-08-15T09:41:00Z',
  expired: false,
  multiple: false,
  voted: false,
  ownVotes: [],
};

test('a poll is a child component, and it owns which option is picked', { skip: !built }, () => {
  const s = instance('Status', { id: '117', content: 'settle it', poll: POLL });
  const tokens = field(s, 'pollRows');
  assert.equal(tokens.length, 1);
  const poll = child(tokens[0]);
  // the status told it what it belongs to; a poll cannot work that out itself
  assert.equal(field(poll, 'statusId'), '117');

  // before anybody votes, Mastodon shows the options and no numbers at all
  assert.equal(field(poll, 'showResults'), false);
  assert.equal(field(poll, 'openLabel'), 'Pick one');
  assert.deepEqual(field(poll, 'optionItems').map((o) => o.share), [62, 25, 12]);

  emitted.length = 0;
  const voted = poll.handleEvent('input', 'vote', [num(1)]);
  assert.notEqual(voted, undefined);
  assert.equal(field(voted, 'showResults'), true);
  assert.deepEqual(field(voted, 'ownVotes'), [1]);
  // the pick is counted on TOP of the record, which is left alone
  assert.equal(field(voted, 'votesCount'), 66);
  assert.equal(field(voted, 'totalLabel'), '67 votes');
  const items = field(voted, 'optionItems');
  assert.deepEqual(items.map((o) => o.votesCount), [41, 18, 8]);
  assert.deepEqual(items.map((o) => o.chosen), [false, true, false]);
  // every share moved, which is why the poll owns the pick and no option does
  assert.deepEqual(items.map((o) => o.shareLabel), ['61%', '26%', '11%']);
  assert.deepEqual(items.map((o) => o.leading), [true, false, false]);
  assert.deepEqual(emitted, [['voted', [{ tag: 'text', val: '117' }, { tag: 'number', val: 1 }]]]);

  // one choice replaces the previous one rather than adding to it
  const moved = voted.handleEvent('input', 'vote', [num(0)]);
  assert.deepEqual(field(moved, 'ownVotes'), [0]);
  assert.equal(field(moved, 'totalLabel'), '67 votes');
  // and picking the same one again takes it back
  assert.deepEqual(field(voted.handleEvent('input', 'vote', [num(1)]), 'ownVotes'), []);

  // a multiple-choice poll adds instead of replacing
  const multi = instance('Poll', { statusId: '1', ...POLL, multiple: true })
    .handleEvent('input', 'vote', [num(0)])
    .handleEvent('input', 'vote', [num(2)]);
  assert.deepEqual(field(multi, 'ownVotes'), [0, 2]);
  assert.equal(field(multi, 'openLabel'), 'Pick any');

  // a closed poll shows its results and refuses a vote
  const closed = instance('Poll', { statusId: '1', ...POLL, expired: true });
  assert.equal(field(closed, 'showResults'), true);
  assert.equal(closed.handleEvent('input', 'vote', [num(0)]), undefined);
  assert.equal(field(closed, 'stateLabel'), 'Closed');
  // and an index that is not an option is refused rather than crashing
  assert.equal(instance('Poll', { statusId: '1', ...POLL }).handleEvent('input', 'vote', [num(9)]), undefined);
});

test('a post without a poll builds no child', { skip: !built }, () => {
  assert.deepEqual(field(instance('Status', { content: 'no poll here' }), 'pollRows'), []);
  // and one that is given one later builds it then
  const later = instance('Status', { id: '5', content: 'x' }).withField('poll', value(POLL));
  assert.equal(field(later, 'pollRows').length, 1);
  assert.equal(field(child(field(later, 'pollRows')[0]), 'statusId'), '5');
});

const CONVERSATION = [
  { id: '1', acct: 'alice', displayName: 'Alice', content: 'root', repliesCount: 2, depth: 0 },
  { id: '2', acct: 'bob@other.test', displayName: 'Bob', content: 'reply', repliesCount: 1, depth: 1 },
  { id: '3', acct: 'alice', displayName: 'Alice', content: 'reply to reply', depth: 2 },
  { id: '4', acct: 'carol', displayName: 'Carol', content: 'other branch', depth: 1 },
];
const thread = (extra = {}) => instance('Thread', { posts: CONVERSATION, ...extra });

test('a thread is a list of Statuses, indented by depth', { skip: !built }, () => {
  const t = thread();
  // one child per post, each a real component with its own rich text
  assert.deepEqual(rowField(t, 'name'), ['Alice', 'Bob', 'Alice', 'Carol']);
  // an untrusted view has no `style` attribute, so the indent arrives as that
  // many rails to draw
  assert.deepEqual(rowField(t, 'rail').map((r) => r.length), [0, 1, 2, 1]);
  // and each row is told how much hangs under it, which is what its fold button
  // counts — the row cannot see the thread to work that out
  assert.deepEqual(rowField(t, 'foldable'), [3, 1, 0, 0]);
  assert.deepEqual(rowField(t, 'owned'), [true, true, true, true]);
  assert.equal(t.callMethod('summary', []).val, '4 posts');
});

test("folding is the row's flag and the thread's filter, not one or the other", { skip: !built }, () => {
  const t = thread();
  const rows = field(t, 'rows');
  emitted.length = 0;

  // The row keeps its own flag — it returns a successor — AND announces, because
  // the thread is the only one that knows what sits under it.
  const folded = child(rows[1]).handleEvent('input', 'toggleFold', []);
  assert.equal(field(folded, 'folded'), true);
  assert.equal(field(folded, 'foldLabel'), '+1');
  assert.deepEqual(emitted, [['folded', [{ tag: 'text', val: '2' }]]]);

  // The host writes that successor home, and the thread — hearing the bubble —
  // drops what was under it and keeps the bubble from travelling on to a page
  // that has no use for it.
  emitted.length = 0;
  const t2 = writeRow(t, 1, folded).handleEvent('bubble', 'folded', [text('2')]);
  assert.deepEqual(rowField(t2, 'name'), ['Alice', 'Bob', 'Carol']);
  assert.equal(t2.callMethod('summary', []).val, '4 posts · 1 folded away');
  assert.deepEqual(emitted.map(([n]) => n), ['stopPropagation']);

  // The thread rebuilt NOTHING: every row it did not touch is the same child it
  // was, which is what keeps a favourite three rows down.
  const after = field(t2, 'rows');
  assert.equal(after[0], rows[0]);
  assert.equal(after[2], rows[3]);

  // unfolding puts them back
  assert.equal(field(t2.handleEvent('bubble', 'unfolded', [text('2')]), 'rows').length, 4);
  // and a bubble naming a post this thread does not have is not its to act on
  assert.equal(t2.handleEvent('bubble', 'folded', [text('nope')]), undefined);
});

test('a row keeps its own favourite, and still announces it', { skip: !built }, () => {
  const t = thread();
  emitted.length = 0;

  // The row is the one that changed, so the row is the one that returns a
  // successor. The thread has nothing to add — it does not handle the bubble at
  // all, and does not stop it: only whoever is above can write the record.
  const liked = child(field(t, 'rows')[0]).handleEvent('input', 'toggleFavourite', []);
  assert.equal(field(liked, 'favourited'), true);
  assert.equal(field(liked, 'favouritesCount'), 0);
  assert.equal(field(liked, 'favourites'), '1');
  assert.deepEqual(emitted.map(([n]) => n), ['favourited']);

  emitted.length = 0;
  const t2 = writeRow(t, 0, liked);
  assert.deepEqual(rowField(t2, 'favourited'), [true, false, false, false]);
  assert.equal(t2.handleEvent('bubble', 'favourited', [text('1')]), undefined);
  assert.deepEqual(emitted, []);
});

test('the focused post is the one the thread was told about', { skip: !built }, () => {
  const t = thread({ focus: '3' });
  assert.deepEqual(rowField(t, 'focus'), [false, false, true, false]);
  // `focus` is declared, so the host's generated setter lands in with-field —
  // and rebuilds the rows, since a row is told at build time which it is
  const moved = t.withField('focus', text('4'));
  assert.deepEqual(rowField(moved, 'focus'), [false, false, false, true]);
  // a thread is its declared fields plus host-owned tokens, so it keeps nothing
  assert.deepEqual([...t.persist()], []);
  // and a field it does not have is refused rather than swallowed
  assert.equal(t.withField('nonsense', text('x')), undefined);
});

const TRENDING = [
  { id: '10', acct: 'warandpeas', displayName: 'War and Peas', content: '',
    media: [{ description: 'a comic', previewUrl: 'https://files.mastodon.social/media_attachments/files/1/small/x.jpeg', url: '', type: 'image' }] },
  { id: '11', acct: 'Mastodon', displayName: 'Mastodon', content: 'guidelines about our Trade Mark Policy' },
  { id: '12', acct: 'mcc', displayName: 'mcc', content: 'When Tom Scott is trying to flirt with you',
    boostedBy: 'Prof. Sam Lawler',
    media: [{ description: 'a thumbnail', previewUrl: 'https://files.mastodon.social/media_attachments/files/2/small/y.png', url: '', type: 'image' }] },
];
const timeline = (extra = {}) => instance('Timeline', { title: 'Trending', posts: TRENDING, ...extra });

test('a timeline filters among rows it already built, so nothing a reader did is lost', { skip: !built }, () => {
  let tl = timeline();
  assert.deepEqual(rowField(tl, 'name'), ['War and Peas', 'Mastodon', 'mcc']);
  assert.equal(tl.callMethod('countLabel', []).val, '3 posts');
  assert.equal(field(tl, 'isFiltered'), false);
  // a boost header is what the row was told, not something it worked out
  assert.deepEqual(rowField(tl, 'boostLabel'), ['', '', 'Prof. Sam Lawler boosted']);

  const before = field(tl, 'rows');
  // favourite the middle row, and write the successor home
  const liked = child(before[1]).handleEvent('input', 'toggleFavourite', []);
  tl = writeRow(tl, 1, liked);

  // filtering it out and back does NOT rebuild it: the children are built once
  // and the filter chooses among them
  tl = tl.handleEvent('input', 'setQuery', [text('war and peas')]);
  assert.deepEqual(rowField(tl, 'name'), ['War and Peas']);
  assert.equal(tl.callMethod('countLabel', []).val, '1 of 3 posts');
  tl = tl.handleEvent('input', 'clearQuery', []);
  assert.deepEqual(rowField(tl, 'favourited'), [false, true, false]);

  // the search reads the body, the name and the handle
  assert.deepEqual(rowField(tl.handleEvent('input', 'setQuery', [text('TRADE MARK')]), 'name'), ['Mastodon']);
  assert.deepEqual(rowField(tl.handleEvent('input', 'setQuery', [text('mcc')]), 'name'), ['mcc']);
  // and nothing matching is an empty state rather than a wrong one
  const none = tl.handleEvent('input', 'setQuery', [text('zzz')]);
  assert.deepEqual(field(none, 'rows'), []);
  assert.equal(field(none, 'isEmpty'), true);

  // media-only is the other filter, and it is not text
  const media = tl.handleEvent('input', 'toggleMediaOnly', []);
  assert.deepEqual(rowField(media, 'name'), ['War and Peas', 'mcc']);
  assert.equal(media.callMethod('mediaLabel', []).val, '✓ media only');
  assert.equal(field(media, 'isFiltered'), true);
  // and the favourite is still on the row the filter hid
  assert.deepEqual(rowField(media.handleEvent('input', 'toggleMediaOnly', []), 'favourited'), [false, true, false]);
});

test('a profile counts a follow on top of the number the record came with', { skip: !built }, () => {
  emitted.length = 0;
  let p = instance('Profile', {
    displayName: 'Mastodon',
    acct: 'Mastodon',
    note: 'the primary account for the Mastodon project.',
    followersCount: 877054,
    followingCount: 51,
    statusesCount: 560,
    createdAt: '2016-11-23T00:00:00.000Z',
    fields: [
      { name: 'Homepage', value: 'https://joinmastodon.org', verified: true },
      { name: 'Pronouns', value: 'they/them', verified: false },
    ],
    posts: CONVERSATION.slice(0, 2),
  });
  assert.equal(field(p, 'followersLabel'), '877K');
  assert.equal(field(p, 'followingLabel'), '51');
  assert.equal(field(p, 'statusesLabel'), '560');
  // the fourth column Mastodon shows and bluesky does not
  assert.equal(field(p, 'joinedLabel'), '2016');
  assert.equal(field(p, 'handleText'), '@Mastodon@mastodon.social');
  assert.equal(p.callMethod('followLabel', []).val, 'Follow');

  // a metadata row's value is a link on the ACCOUNT's origin, so it is shown the
  // way a posted link is: shortened text, whole url in the tooltip, no href
  assert.deepEqual(field(p, 'fieldItems'), [
    { name: 'Homepage', value: 'joinmastodon.org', target: 'https://joinmastodon.org', verified: true },
    { name: 'Pronouns', value: 'they/them', target: 'they/them', verified: false },
  ]);

  p = p.handleEvent('input', 'toggleFollow', []);
  assert.equal(field(p, 'following'), true);
  assert.equal(field(p, 'followersCount'), 877054);
  assert.equal(p.callMethod('followLabel', []).val, 'Following');
  assert.deepEqual(emitted, [['followed', [{ tag: 'text', val: 'Mastodon' }]]]);

  // its recent posts are Statuses too, standing on their own
  assert.deepEqual(rowField(p, 'name'), ['Alice', 'Bob']);
  assert.deepEqual(rowField(p, 'rail').map((r) => r.length), [0, 0]);
  assert.deepEqual(rowField(p, 'foldable'), [0, 0]);

  // an account that approves its followers by hand asks instead of following
  const locked = instance('Profile', { acct: 'alice', locked: true });
  assert.equal(locked.callMethod('followLabel', []).val, 'Request follow');
  // and one with no pictures draws the initials, which is a state the view has
  assert.equal(field(locked, 'avatarPath'), '');
  assert.equal(field(locked, 'headerPath'), '');
});

test('a timeline and a thread each say what they do not cover', { skip: !built }, () => {
  const t = instance('Timeline', {
    title: 'Trending',
    posts: CONVERSATION.slice(0, 2),
    scope: {
      more: true,
      notes: ['this instance only holds posts it has federated'],
    },
  });
  // the scope is a child of its own, and the timeline keeps whether it has
  // anything to say — a token is a bridge handle, so a parent cannot read one back
  assert.equal(field(t, 'hasScope'), true);
  const s = child(t.getField('scope').val);
  assert.equal(field(s, 'hasAny'), true);
  assert.equal(field(s, 'moreLabel'), 'more pages were not read');
  assert.equal(field(s, 'truncatedLabel'), '');
  assert.deepEqual(field(s, 'notes'), ['this instance only holds posts it has federated']);
  assert.match(s.callMethod('summary', []).val, /^scope: more pages unread; this instance/);

  // an answer with nothing to disclose still HAS a scope, and it draws nothing
  const quiet = instance('Timeline', { posts: CONVERSATION.slice(0, 1) });
  assert.equal(field(quiet, 'hasScope'), false);
  assert.equal(field(child(quiet.getField('scope').val), 'hasAny'), false);

  // rewriting the posts rebuilds the rows and keeps the scope: a new list is not
  // a new claim about what was covered
  const one = t.withField('posts', value(CONVERSATION.slice(0, 1)));
  assert.equal(field(one, 'hasScope'), true);
  assert.equal(child(one.getField('scope').val), s);

  // and a thread carries the same component, with the vocabulary a depth cap needs
  const th = instance('Thread', {
    posts: CONVERSATION,
    scope: { truncated: true, truncatedBy: 'depth' },
  });
  assert.equal(field(th, 'hasScope'), true);
  assert.equal(
    field(child(th.getField('scope').val), 'truncatedLabel'),
    'stopped at the depth cap — this is not everything',
  );
});
