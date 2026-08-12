# bluesky — a `tutuca:component` guest

Bluesky / ATProto content as a WebAssembly component: one message (`Post`), a
conversation (`Thread`) and an account (`Profile`), each rendering from plain
ATProto-shaped data. Ported from the JS `tutuca-components/src/atproto` module
group, and styled after [atproto-wc.com](https://atproto-wc.com) — the same
card, the same "12 replies · 34 reposts · 1.2K likes" row, light and dark.

Everything structural — layout, build, binding regeneration, the WIT source,
the toolchain pins and the Component Model gotchas — is identical to the counter
guest and documented once, in [`../counter/README.md`](../counter/README.md).
Only the component source differs:

- `gen/interface/tutuca/component/guest/bluesky.mbt` — the three components and the factories
- `manifest.json` + `views/` — their declaration and the host-compiled templates

```sh
node guests/build-guest.mjs bluesky        # dist/bluesky.component.wasm + dist/js/
node --test dyncomp/test/bluesky-harness.test.mjs
```

## What an untrusted reader can and cannot draw

This is a viewer for someone else's records, which makes it the guest where the
policy boundary shows up in the OUTPUT rather than in a doc:

- **No `src`, `href` or `style`.** `dyncomp/policy`'s view-authority rule refuses
  those attribute names outright for an Untrusted bundle, because what a dynamic
  attribute will hold is unknowable when the view is registered. So an avatar is
  the author's initials in a circle, an attached image is its alt text on a
  chip, a link is its text with the target as the tooltip, and the permalink is
  text you can select. Nothing is hidden — every facet target is on the page —
  and nothing here can make the page fetch.
- **No indentation attribute either**, which is why a row's `depth` arrives in
  the view as a `rail` list: that many spacer elements to draw, since a
  `style="margin-left:…"` is exactly the sink the rule refuses.
- **No arbitrary utility classes.** Bracketed Tailwind (`w-[560px]`) is
  guest-authored CSS and refused too, so the palette is daisyUI's semantic
  tokens — `base-100` / `base-300` / `base-content` follow the page's
  `data-theme`, which is what makes the light and dark variants free — plus a
  fixed `sky-500` for links and the focal ring, since atproto-wc keeps its
  accent the same in both themes.
- **No clock.** `env.now-ms` needs `cap-clock`, and a bundle that asks for a
  capability is refused by every page that has not decided about it (the
  reasoning is written out in `examples/dyncomp-dice`). A timestamp is therefore
  formatted from the record's own `createdAt` — "11 Aug 2026, 14:03" — instead
  of the "2h ago" nobody here can compute.
- **No writes.** Liking, reposting and following move a flag locally and `emit`
  a bubble (`liked`, `reposted`, `followed`, …). Whoever holds the component is
  the one that can turn that into an `app.bsky.feed.like` record; the counts
  stay split, so the number the record arrived with is never edited.

The result asks for nothing, so a stock host loads it with no policy decision
from anybody — which is the trade this guest exists to show.

## The three components

| component | declared fields | persists |
| --- | --- | --- |
| `Post` | the record: author, `text` + `facets`, `images`, the three counts, this reader's `liked` / `reposted`, and where it sits in a thread (`depth`, `focus`, `foldable`, `folded`, `owned`) | no |
| `Thread` | `posts` — the reply tree, FLAT, each message with a `depth` — and `focus` | no |
| `Profile` | the account, its three counts, `following`, and its recent `posts` | no |

None of them persists: each one's state is exactly the fields it declares, so
the host projects and rebuilds them itself (the other half of the contract the
todo guest shows by writing bytes).

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

### Facets

The one piece of real work is `segments_of`: ATProto facets index into UTF-8
**byte** offsets and a MoonBit string is UTF-16, so the text is measured a
character at a time and a facet that lands mid-character is dropped rather than
allowed to split one. `dyncomp/test/bluesky-harness.test.mjs` pins that with an
emoji in front of a link.
