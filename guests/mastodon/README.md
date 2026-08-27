# mastodon — a `tutuca:component` guest

Mastodon / fediverse content as a WebAssembly component: one post (`Status`),
its poll (`Poll`), a conversation (`Thread`), a feed (`Timeline`), an account
(`Profile`) and the disclosure that an answer is partial (`Scope`), each
rendering from plain Mastodon-shaped data. Styled after
[mastodon.social/explore](https://mastodon.social/explore) — the rounded-square
avatar, the name over the `@user@server` handle, the visibility glyph beside the
stamp, the reply / boost / favourite row, and the divided column they sit in.

Everything structural — layout, build, binding regeneration, the WIT source, the
toolchain pins and the Component Model gotchas — is identical to the counter
guest and documented once, in [`../counter/README.md`](../counter/README.md).
Only the component source differs:

- `gen/interface/tutuca/component/guest/mastodon.mbt` — the six components and the factories
- `manifest.json` + `views/` — their declaration and the host-compiled templates

```sh
node guests/build-guest.mjs mastodon        # dist/mastodon.component.wasm + dist/js/
node --test dyncomp/test/mastodon-harness.test.mjs
```

Its sibling is [`../bluesky/`](../bluesky/README.md), which reads the other big
open social network under the same rules. Reading the two together is the point:
the policy boundary is identical and the two networks push against it in
different places, so what each guest does about it is a different answer to the
same question.

## Three things that are not bluesky's answers

### 1. The rich text is FOUND, not given

ATProto hands a reader **facets** — byte ranges with a kind — so `guests/bluesky`
only has to cut the text on them. Mastodon hands a reader `content`, which is
**HTML**, and an untrusted bundle may not emit markup at any tier. So this guest
takes the plain text and scans it (`segments_of`) for the three shapes:
`#tag`, `@mention`, `https://…`.

Finding them is the easy half. The half worth keeping is that a found run is
only a **link** when the record's own `tags` / `mentions` confirm it:

```
content:  "hello @bob and @nobody, see https://tutuca.dev/x #wasm #notatag"
mentions: ["bob@other.test"]        tags: ["wasm"]
          └─ @bob links                    └─ #wasm links
             @nobody stays text               #notatag stays text
```

Only the server knows whether `@bob@example.test` is an account or somebody's
email address, and a viewer that guessed on its behalf would be inventing links
into the fediverse out of punctuation. The carried spelling is also what the
link uses — `@bob` in the text becomes `mastodon.social/@bob@other.test`, because
`@bob` alone is a different account here.

A link is shortened the way Mastodon shortens one — scheme dropped, cut at 30
characters with an ellipsis, which is exactly what the `invisible` / `ellipsis`
spans in its own HTML do — and the whole url stays in the tooltip, because that
is all a reader gets: its origin belongs to whoever posted it, so no view can
name it.

### 2. Federation is why ONE picture origin is enough — and config is why it can be ANY one

A post in a federated timeline comes from any server there is, so no view could
name the origins its avatars live on. Except that an instance **proxies what it
federates**: a remote account's avatar and a remote post's attachment are both
re-served from the instance's own media host, under `/cache/`. So this bundle's
views reach exactly two origins.

Neither of them is written here. They are **config vars** — declared in
`manifest.json` with a default, bound by the host at load — so one build of this
bundle reads mastodon.social, hachyderm.io, or any instance somebody points it
at, with no rebuild and no edit:

```json
{ "name": "mediaOrigin", "type": "origin", "default": "https://files.mastodon.social/" },
{ "name": "webOrigin",   "type": "origin", "default": "https://mastodon.social/" }
```

```html
<!-- allowed: the origin is settled before anything runs — the HOST settled it -->
<img :src="$'{$$mediaOrigin}{.avatarPath}'" alt="">
<!-- refused: this bundle would be picking the origin -->
<img :src=".avatar">
```

`$$mediaOrigin` resolves at PARSE time to the string the host bound, so what the
policy checks is an ordinary pinned literal and the rule is exactly the one
`bluesky` and `slack` pass with hosts written into their views. The origin moved
from the bundle to the host, which is the direction that makes it stricter:
before, the host approved an origin the guest chose; now the host writes it.

What crosses from the guest is therefore still only a PATH. An avatar, a header
and an attachment preview arrive as the urls the API hands out and are read back
through `media_path`, which keeps what follows the host and refuses everything
else — including `files.mastodon.social.attacker.test` and
`files.mastodon.social@attacker.test`, which is why the bound origin ends in a
`/`. Both halves now read the SAME string (`@config.get("mediaOrigin")` and
`$$mediaOrigin`), so the two cannot drift: pointing this bundle somewhere else
is binding a variable, not editing two files that have to agree.

A host that binds nothing gets the defaults for the guest's half and **no
pictures**, on purpose: a bundle that could open a URL sink with an origin from
its own manifest would make the rule decorative. A page that ships this archive
says so with `trusting_manifest_config`; a page that loads bundles it did not
ship binds with `with_config`. See `dyncomp/SECURITY.md` §3a.

**The fallback is a layer, not a branch.** The `<img>` sits over the initials
square rather than replacing it, so an author with no picture, a picture on an
origin no view names, and a fetch that fails anyway all show the same two
letters. An untrusted view has no `onerror` to write and does not need one.

The one thing proxying does not fix is a **permalink**: a remote post is a page
on the server that holds it. So a local post gets a link under `webOrigin` and a
remote one stays selectable text with its address in the tooltip — the same
split bluesky makes between a hashtag and a link somebody posted, arrived at
from a different direction. Profiles and hashtags need no such split: this server
renders remote profiles at its own address, so `@servo@floss.social` is a page
here.

The server's NAME is a third variable, `instanceName`, and it is `text` rather
than `origin` — deliberately. It is prose: the `@user@server` handle, a
tooltip, the visible text under a permalink. A `text` variable cannot be named
by a view at all, which is what stops it from becoming an origin.

### 3. A poll bar is an element, not a stylesheet

Untrusted views have no `style` attribute, so a share cannot be a width.
`guests/bluesky` draws a reply indent as N spacer elements, because there is no
element that means "indent" — but there IS one that means "a fraction of a
whole", and `value` is neither a network nor a CSS sink:

```html
<progress class="progress progress-primary" :value="@value.share" max="100"></progress>
```

Nothing had to be reopened for it. The rails are still there for the indent,
where the platform really does have nothing to offer.

## The six components

| component | declared fields | persists |
| --- | --- | --- |
| `Status` | the record: author, `content` + `tags` / `mentions`, `media`, `poll`, the three counts, this reader's `favourited` / `reblogged` / `bookmarked` / `revealed`, and where it sits in a thread (`depth`, `focus`, `foldable`, `folded`, `owned`) | no |
| `Poll` | `options`, the two counts, `expiresAt` / `expired` / `multiple` / `voted` / `ownVotes`, and the `statusId` it belongs to | no |
| `Thread` | `posts` — the reply tree, FLAT, each post with a `depth` — plus `focus`, a `scope` and a `pageSize` | no |
| `Timeline` | `title`, `posts`, the two filters (`query`, `mediaOnly`), a `scope` and a `pageSize` | no |
| `Profile` | the account, its four columns, `locked` / `bot` / `following`, its metadata `fields`, its recent `posts` and a `pageSize` | no |
| `Scope` | what the answer above it does not cover: `truncated` / `truncatedBy`, `more`, and free-text `notes` | no |

None of them persists: each one's state is exactly the fields it declares, so
the host projects and rebuilds them itself (the other half of the contract the
todo guest shows by writing bytes).

### Everything is a list of Statuses, and why

A view cannot iterate a value it found inside another iteration — the sequence
`@each` takes is a field path, not a loop binding — so a post's rich text can
only be a loop in the component that OWNS the post. One component per post is
therefore not composition for its own sake: it is the only shape in which a
reply keeps its links. `Thread`, `Timeline` and `Profile` make their rows with
`control.make-instance` and hand the host their tokens; `<x render-each=".rows">`
draws them.

`Poll` is a child for a different reason: it owns a **decision**. A single-choice
vote un-picks the previous one and moves every share, so the answer belongs to
the poll and not to any option in it. `Status` reserves its token in the same
call that builds the status, which works because the bridge's pending-children
protocol drains recursively — a `Timeline` builds five `Status`es and each of
those may reserve a `Poll`, all from one `init`.

### Where a row's state lives

A row keeps its own favourite, boost, bookmark, content-warning and fold:
`toggleFavourite` returns a successor and the host writes it home into whatever
list holds the row. It also EMITS — `favourited`, `boosted`, `folded` with the id
— because what the screen shows and what somebody with a network connection
should do about it are two different jobs, and this bundle can only do the first.
Opening a content warning is the one exception that proves it: it changes the
screen and there is nothing for a host to write, so it announces nothing.

Two surfaces keep one thing beside that, and only because they are the only ones
who can:

- `Thread` keeps which ids are folded AWAY. A row knows it is folded — that is
  its own glyph — but which posts sit UNDER it is a fact about the tree, and the
  tree is the thread's. So a fold is two facts about one click, and the thread
  does not rebuild the row to record its half; rebuilding would throw away the
  successor the host just wrote home.
- `Timeline` keeps its two filters, and for the same reason it builds its rows
  **once**: the filter chooses among children that already exist, so a favourite
  survives typing in the search box and toggling media-only twice. The harness
  pins that, because the tempting implementation — rebuild the rows from the
  records that match — silently throws away everything the reader did.

`Profile` has neither, so it keeps nothing: it does not handle those bubbles at
all, and they carry on up.

## A card that says what it does not cover

`Scope` is the disclosure that an answer is partial — a cap that stopped it, a
page nobody read, an instance that only holds what it has federated. That last
one is why a fediverse reader needs it most: a federated timeline is what THIS
server has seen, which is not the network, and a card that draws five posts with
no note draws them as if they were five posts. `Timeline` and `Thread` each hang
one under themselves, from a plain record whose keys are its own field names, and
draw it only when there is something to disclose.

It is field-for-field the component `guests/bluesky` has, and that is the point
rather than a coincidence: a host drawing a mastodon card beside an ATProto one
should not have to learn two spellings of "this is not everything". The slack
bundle's twin differs, because what a Slack answer leaves out is conversations
rather than pages of a feed.

## A column that arrived too long

`Thread`, `Timeline` and `Profile` are each a column of `Status`es, and how long
one is was never theirs to decide: a caller asks a server for a timeline and gets
back whatever a `limit` allowed. Forty rows is a card. Four hundred is a wall a
reader scrolls past rather than reads, drawn out of four hundred child components
before any one of them is looked at.

So a long list gets a window and the four buttons that move it — `firstPage` /
`prevPage` / `nextPage` / `lastPage`, over `page`, `pageCount`, `pageSize`,
`atFirst` / `atLast`, and the two labels a footer writes (`pageLabel`, and
`rangeLabel` for the `26–50 of 340` a page number does not say). That is the
`table` bundle's vocabulary rather than a new one, for the reason `Scope` is
bluesky's component rather than a second spelling of it.

Two things decide when it appears. A card pages only once it holds more than a
hundred rows, so nothing that already fits grew a control it does not need — and
a host that wants the window anyway asks for a `pageSize`, because asking is what
that means. And the window is over what the FILTERS left rather than over the
records: the search box narrows, the pager pages what is left, and typing in the
box takes the reader back to the first page, since it made a different list.

Paging rebuilds nothing. It is the property the filter already had, for the same
reason — the children are built once and something else chooses among them — so
a favourite three pages back is still there when the reader pages back to it.

## No clock, and no writes

A guest has no clock at all — the time is a fact only the host can supply, over
an intent — and what a clock buys a reader is "4h" instead of a date the record
already carries: a round trip for a nicer phrasing of something it can already
say. mastodon.social writes "4h"; this writes "13 Aug 2026, 16:02", from the
record's own `createdAt`, and the one thing this bundle does need from a host —
its two bound origins — is the one whose absence it cannot work around.

Nothing here writes either. Favouriting, boosting, following and voting move a
flag locally and `emit` a bubble; whoever holds the component is the one that can
turn that into an API call. The counts stay split — the number the record arrived
with is never edited, and this reader's own answer is added on top — so a refused
write has nothing to un-edit.

Two Mastodon rules are enforced here rather than left to the host, because they
are about what the record says rather than about the network: a followers-only or
direct post refuses to be boosted (and the button's title says why), and a closed
poll refuses a vote.

## Styling

daisyUI's semantic tokens — `base-100` / `base-300` / `base-content` follow the
page's `data-theme`, which is what makes light and dark free — plus a fixed
`indigo-500` for links, the accent and an active boost, `amber-500` for a
favourite and `rose-500` for a bookmark, which is roughly where Mastodon puts
them. Bracketed Tailwind (`w-[560px]`) is guest-authored CSS and refused, so
there is none; every class is a literal, which is also what lets the host's
margaui collector see them.

Icons are text glyphs (`↩ ⇄ ★ ⚑`) rather than inline SVG. Not a limitation —
`<svg>` is allowed — but `fill` and `stroke` are on the refused-attribute list
(both take `url(…)`), so an SVG icon would have to be styled entirely through
utility classes, which is a lot of markup for four shapes.

Two of those four carry **U+FE0E** (`↩︎`, `⚑︎`) and it is not decoration. Both
have an emoji presentation the browser picks by default, and an emoji glyph
draws in its own colours — so the boost that turns indigo and the favourite that
turns amber sat next to a reply arrow that stayed blue whatever the CSS said.
The variation selector asks for the text presentation, which inherits
`currentColor` like everything else.
