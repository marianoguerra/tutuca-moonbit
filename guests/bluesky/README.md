# bluesky — a `tutuca:component` guest

Bluesky / ATProto content as a WebAssembly component: one message (`Post`), a
list (`Feed`), a conversation (`Thread`), an account (`Profile`) and the
disclosure that an answer is partial (`Scope`), each rendering from plain
ATProto-shaped data. Ported from the JS `tutuca-components/src/atproto` module
group, and styled after [atproto-wc.com](https://atproto-wc.com) — the same
card, the same "12 replies · 34 reposts · 1.2K likes" row, light and dark.

Everything structural — layout, build, binding regeneration, the WIT source,
the toolchain pins and the Component Model gotchas — is identical to the counter
guest and documented once, in [`../counter/README.md`](../counter/README.md).
Only the component source differs:

- `gen/interface/tutuca/component/guest/bluesky.mbt` — the five components and the factories
- `manifest.json` + `views/` — their declaration and the host-compiled templates

```sh
node guests/build-guest.mjs bluesky        # dist/bluesky.component.wasm + dist/js/
node --test dyncomp/test/bluesky-harness.test.mjs
```

## What an untrusted reader can and cannot draw

This is a viewer for someone else's records, which makes it the guest where the
policy boundary shows up in the OUTPUT rather than in a doc:

- **Two origins, and they are written in the views.** `dyncomp/policy`'s
  view-authority rule refuses `src`, `href` and `style` outright for an
  Untrusted bundle, because what a dynamic attribute will hold is unknowable
  when the view is registered. What CAN be known is the ORIGIN, when the view
  states it as a literal — so this bundle asks for `cap-external-urls` and
  spends it on exactly two: `cdn.bsky.app` for the pictures, `bsky.app` for the
  links.

  ```html
  <!-- allowed: the origin is settled before anything runs -->
  <img :src="$'https://cdn.bsky.app/{.avatarPath}'" alt="">
  <!-- refused: this bundle would be picking the origin -->
  <img :src=".avatar">
  ```

  What crosses from the guest is therefore only a PATH. An avatar, a banner and
  a thumbnail arrive as the full urls the API hands out and are read back
  through `cdn_path`, which keeps what follows the CDN and refuses everything
  else — so a picture hosted anywhere but that CDN is not drawn. The links split
  the same way and for the same reason: a mention, a hashtag and the permalink
  are `bsky.app` paths and navigate, while a link somebody POSTED points
  wherever they chose, so it stays styled text with its target in the tooltip.
  An image with no thumbnail is still its alt text on a chip.

  **The fallback is a layer, not a branch.** The `<img>` sits over the initials
  disc rather than replacing it, so an author with no picture, a picture on an
  origin no view names, and a fetch that fails anyway all show the same two
  letters. An untrusted view has no `onerror` to write and does not need one.

  A host that does not grant the capability refuses this bundle whole rather
  than loading a version of it that draws half of itself — the bargain every
  capability here makes, and the reason the manifest states its reason. Both
  demo pages grant exactly the origins above (`@shell.sample_policy`). What the
  grant costs — an image is a GET the guest chose, so an allowed origin is an
  origin that can be told things — is in `dyncomp/SECURITY.md` §3.
- **No indentation attribute either**, which is why a row's `depth` arrives in
  the view as a `rail` list: that many spacer elements to draw, since a
  `style="margin-left:…"` is exactly the sink the rule refuses.
- **No arbitrary utility classes.** Bracketed Tailwind (`w-[560px]`) is
  guest-authored CSS and refused too, so the palette is daisyUI's semantic
  tokens — `base-100` / `base-300` / `base-content` follow the page's
  `data-theme`, which is what makes the light and dark variants free — plus a
  fixed `sky-500` for links and the focal ring, since atproto-wc keeps its
  accent the same in both themes.
- **No clock**, and the difference from the pictures is the point. `env.now-ms`
  needs `cap-clock`, and what a clock buys a reader is "2h ago" instead of a
  date it already has — a second capability for a nicer phrasing of something
  it can already say. A timestamp is therefore formatted from the record's own
  `createdAt`, "11 Aug 2026, 14:03", and the one capability this bundle does
  ask for is the one whose absence it cannot work around.
- **No writes.** Liking, reposting and following move a flag locally and `emit`
  a bubble (`liked`, `reposted`, `followed`, …). Whoever holds the component is
  the one that can turn that into an `app.bsky.feed.like` record; the counts
  stay split, so the number the record arrived with is never edited.

`Profile` says two more things it always had and never drew: when the account was
created (as a date, not a duration — "3 years ago" would need the clock this
bundle does without) and the at-uri of the message it pinned, as a bsky.app link.
The uri and not the message: `getProfiles` answers with a strong ref, so the
content is one more request away and this bundle makes none.

The result asks for one capability, spends it on two origins a host can read off
the views, and does without everything else. That is the trade this guest exists
to show: not that an untrusted bundle needs nothing — this one draws other
people's pictures, so it does — but that what it needs can be small enough to
check by looking.

## The five components

| component | declared fields | persists |
| --- | --- | --- |
| `Post` | the record: author, `text` + `facets`, `images`, the three counts, this reader's `liked` / `reposted`, where it sits in a thread (`depth`, `focus`, `foldable`, `folded`, `owned`), why it is in front of you (`repostedBy`, `pinned`), what a moderator said about it (`labels`) and its embeds (`external`, `quote`, `video`) | no |
| `Feed` | a `title`, `posts` — a list, every row at depth 0 — a `scope` and a `pageSize` | no |
| `Thread` | `posts` — the reply tree, FLAT, each message with a `depth` — plus `focus`, a `scope` and a `pageSize` | no |
| `Profile` | the account, its three counts, `following`, its recent `posts`, when it was `createdAt`, what it `pinnedPost` and a `pageSize` | no |
| `Scope` | what the answer above it does not cover: `truncated` / `truncatedBy`, `more`, and free-text `notes` | no |

None of them persists: each one's state is exactly the fields it declares, so
the host projects and rebuilds them itself (the other half of the contract the
todo guest shows by writing bytes).

### A feed is not a conversation

`Feed` exists because `Thread` was doing its job. A timeline, an author's posts
and a page of search results are all lists: every message arrives at depth 0 and
nothing under it replies to anything above it. A thread rendered them correctly
for the wrong reason — the rails and the fold button degraded to nothing, which
is not the same as meaning nothing — and a reader looking at the card could not
tell "these five messages happen to be flat" from "these five messages are a
conversation that happens to be flat". Same rows, same children, no reply
vocabulary at all — and a `title`, because a feed is the one surface here that
cannot say what it is from its own contents: three flat messages are three flat
messages whether they came from a timeline, an author or a search, so whoever
asked for them is the one who says. (`mastodonlib/Timeline` had one first.)

### Why a message is in front of you, and what a moderator said about it

A feed ITEM and a post are two records, and three fields live on the first:

- **`repostedBy`** is the highest-value thing this bundle can say and the one it
  could not. Without it a stranger's post drawn in an account's feed reads as
  something that account wrote — the one wrong claim a reader cannot detect by
  looking harder. It is drawn as a line ABOVE the card; the author is never
  rewritten, because rewriting it would attribute the post to the reposter.
- **`pinned`** is the same shape, one word long.
- **`labels`** is the one field whose absence was a safety question rather than a
  fidelity one: a labelled message drawn with no indicator is a labelled message
  this reader was not told about. Nothing here HIDES anything — which labels mean
  "blur this" needs the reader's own preferences and the labellers they subscribe
  to, and neither is in this bundle's reach — but the card stopped being silent.

### The three embeds, and which of them can be a link

`external` is an unfurled link, `quote` a quoted message, `video` a poster frame.
All three drew as bare text before, and between them they are most of what gets
posted.

They split on the same line everything else here does. An unfurled link points
where its poster chose, so it is drawn as a card with the target in the tooltip
and no `href` — while its THUMBNAIL is re-hosted by the AppView on
`cdn.bsky.app`, so it is drawn like any other picture. A quote IS on bsky.app, so
its permalink is a real link; its text is drawn plain, because a quote's own rich
text would need a loop inside a loop and the sequence an `@each` takes is a field
path rather than a loop binding. A video is its poster frame and its alt text and
no player: a playlist is an `.m3u8` fetch this bundle cannot make and has no
business being trusted with.

### A card that says what it does not cover

`Scope` is the disclosure that an answer is partial — a cap that stopped it, a
page nobody read, an index that only holds recent public posts. Until it existed
the prose beside a card said all of that and the card said none of it, which made
the card the more confident of the two while being the less informed. `Feed` and
`Thread` each hang one under themselves, from a plain record whose keys ARE its
own field names, and draw it only when there is something to disclose.

### A thread is a list of Posts, and why

A view cannot iterate a value it found inside another iteration — the sequence
`@each` takes is a field path, not a loop binding — so a message's rich text can
only be a loop in the component that OWNS the message. One component per message
is therefore not composition for its own sake: it is the only shape in which a
reply keeps its links. `Thread` and `Profile` make their rows with
`control.make-instance` and hand the host their tokens; `<x render-each=".rows">`
draws them.

Folding follows from the same choice. The tree arrives flat, so the messages
under one row are the contiguous run of deeper ones after it (`replies_under`),
and folding is a filter over the token list — the children are built once, so a
like three rows down survives a fold.

### Where a row's state lives

A row keeps its own like, repost and fold: `toggleLike` returns a successor and
the host writes it home into whatever list holds the row. It also EMITS —
`liked`, `reposted`, `folded` with the uri — because what the screen shows and
what somebody with a network connection should do about it are two different
jobs, and this bundle can only do the first.

The thread keeps one thing beside that, and only because it is the only one who
can: which uris are folded AWAY. A row knows it is folded — that is its own
glyph — but which messages sit UNDER it and therefore stop rendering is a fact
about the tree, and the tree is the thread's. So a fold is two facts about one
click, and the thread does not rebuild the row to record its half; rebuilding
would throw away the successor the host just wrote home.

A profile has no fold, so it keeps nothing: it does not handle those bubbles at
all, and they carry on up.

That is not how it was first written. Until `child_json`
(`dyncomp/host/dynobj.mbt`) recursed, the bridge markered a nested instance only
at the TOP level of a written value while the decoder already handled them at
any depth — so a child inside a LIST field could not come back, a row that kept
its own state counted up in the guest and not on the screen, and the flags had
to live in the thread keyed by uri with the row rebuilt around them. `owned`
survives from that arrangement with a smaller job: it now only says "this is a
row inside something larger", which is what the view reads to draw it smaller.

### A column that arrived too long

`Feed`, `Thread` and `Profile` are each a column of `Post`s, and how long one is
was never theirs to decide: a caller asks a service for a timeline and gets back
whatever a `limit` allowed. Forty rows is a card. Four hundred is a wall a reader
scrolls past rather than reads, drawn out of four hundred child components before
any one of them is looked at.

So a long list gets a window and the four buttons that move it — `firstPage` /
`prevPage` / `nextPage` / `lastPage`, over `page`, `pageCount`, `pageSize`,
`atFirst` / `atLast`, and the two labels a footer writes (`pageLabel`, and
`rangeLabel` for the `26–50 of 340` a page number does not say). That is the
`table` bundle's vocabulary rather than a new one, for the reason `Scope` is
field-for-field the mastodon bundle's: a host drawing both should not have to
learn two spellings of "show me the next lot".

A card pages only once it holds more than a hundred rows, so nothing that already
fits grew a control it does not need — and a host that wants the window anyway
asks for a `pageSize`, because asking is what that means. A thread's window is
over what the FOLDS left rather than over the records, which is the same list
`visible()` already decided; folding a branch away can therefore take a page with
it, and the stored page comes back inside what is left rather than showing
nothing.

Paging rebuilds nothing, so a like three pages back is still there when the
reader pages back to it.

### Facets

The one piece of real work is `segments_of`: ATProto facets index into UTF-8
**byte** offsets and a MoonBit string is UTF-16, so the text is measured a
character at a time and a facet that lands mid-character is dropped rather than
allowed to split one. `dyncomp/test/bluesky-harness.test.mjs` pins that with an
emoji in front of a link.
