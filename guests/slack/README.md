# slack — a chat conversation as a `tutuca:component` guest

Eight components that display a Slack-style conversation: one message, a thread,
a channel's history, a file listing, and what an answer left out. It is a port
of the Feeling-of-Computing conversations reader ([`at-foc/src/components.js`][foc]) onto the dynamic-component contract
([`../../dyncomp/DESIGN.md`](../../dyncomp/DESIGN.md)).

[foc]: https://github.com/marianoguerra/Feeling-of-Computing/blob/main/at-foc/src/components.js

The shared reference for how a MoonBit guest is laid out, built and packed is
[`../counter/README.md`](../counter/README.md); this one differs only in what it
computes. What is worth reading here is the part of the contract it exists to
exercise, and what the policy boundary did to the rest.

| component | what it is |
| --- | --- |
| `Segment` | one styled run of a body: bold, italic, struck, code, a mention, a channel reference, a link |
| `RichText` | a body, as a flat list of `Segment`s |
| `Reaction` | one emoji with its count; clicking toggles yours |
| `Message` | who wrote it, when, its `RichText` body and its `Reaction`s. `compact` is what a reply looks like |
| `Thread` | a root `Message` and its replies — foldable when they are here, and asking for them when they are not |
| `ChannelHistory` | a channel's `Thread`s, with a filter box, an ordering toggle and a `Scope` |
| `FileList` | the files a channel or a search turned up. Metadata only, and it says so |
| `Scope` | what the answer above it covers, and what it never looked at |

## The two things a card was quieter about than the text

Both are cases where the prose beside a card had been saying something for
releases and the card had not — which made the card the more confident of the
two while being the less informed.

**A count with nothing behind it.** `conversations.history` answers with thread
roots carrying a `reply_count` and never with the replies, so every message in a
channel card was a collapsed thread saying "21 replies" over an empty list. The
caret expanded onto nothing. `Thread` now keeps `replyCount` — how many EXIST —
apart from `replies.length()` — how many arrived — and the two states are drawn
differently: a caret when they are here, and when they are not, a button that
says `21 replies — not loaded` beside the two arguments that would load them
(`channelName`, `rootTs`, both on the thread because a token is a bridge handle
and a parent cannot read a field off the child it built). Clicking it emits
`openThread`, which `ChannelHistory` catches and turns into
`read the replies: channel=…, ts=…` in its footer. The `ts` is also drawn on
every `Message` now, in the header beside the time: it is the argument every
follow-up call takes, and it lived in a field no view mentioned.

**A slice of a workspace, drawn as a workspace.** A token sees the public
channels, the private ones it was invited to, and nobody's DMs. `Scope` is that
sentence, as a component: which kinds were read, how many, whether a cap stopped
the scan, and — the one that matters most — that DMs were never in the set at
all. `ChannelHistory` and `FileList` each hang one under themselves and draw it
only when there is something to disclose.

**And a permalink that is shown, not followed.** `Message` takes one and draws
it, and clicking it `emit`s `openLink` exactly as a link segment does. That is
the same rule arrived at from the other direction: a permalink is
`https://<team>.slack.com/archives/…`, and the subdomain belongs to the
workspace, so there is no origin a view can write as a literal and nothing a
host's external-URL allowance could pin it to. See the `href` section below.

## What it exercises: a DEEP tree of same-bundle children

The other sample guests nest one level at most (`counter`'s `Pair` holds two
`Counter`s). This one nests five: `ChannelHistory` → `Thread` → `Message` →
`RichText` → `Segment`, and the whole tree is built by `control.make-instance`
from ordinary JSON in one `init`. `Scope` hangs off the side of that at one
level, from a plain record whose keys ARE its own field names — so a host that
writes JSON into `scope` gets the component it would have got by building one.

That works because the bridge's pending-children protocol drains recursively: a
component may not be re-entered while a call into it is active, so a token is
reserved during the call and its constructor runs after the call returns —
including the tokens THOSE constructors reserve. `dyncomp/test/slack-harness.test.mjs`
implements the same protocol against a fake host, and is what says so if it ever
stops.

One consequence shapes the whole file. **An instance token is a bridge handle,
not a guest pointer**: a parent that holds children cannot read them back, so a
`@when` filter over a list of children could not have worked. `ChannelHistory`
therefore keeps the text and timestamps it built each thread FROM — `haystack`
and `times`, parallel to the tokens — and filters and orders those. That is the
opaque-state model seen from the inside: the host cannot look into an instance,
and neither can the component that made it.

## Where the contract said no, and the one place it said "name it first"

**No `href`.** An untrusted bundle may not use a network sink attribute
(`dyncomp/policy/view_authority.mbt`), so a link segment is styled text that
`emit`s `openLink` with its URL. Whoever is above decides what a URL means —
here `ChannelHistory` catches it, stops the bubble, and says so in its footer. A
real host would open it, or ask first.

**An avatar, from three named origins.** The same rule refuses `src` too — but
what it cannot know ahead of time is the VALUE, not the ORIGIN, and a view that
writes its origin as a literal has settled that much before anything runs. So
`Message`'s views name the three hosts a Slack profile picture actually comes
from — `ca.slack-edge.com`, `avatars.slack-edge.com` and `secure.gravatar.com`,
one `<img>` each, all three readable in `views/Message.main.html` — origins a
hosting policy allows with `allowing_external_urls`. `avatar_path` keeps only
what follows one of them, so a picture hosted anywhere else is not drawn.

That is not a contradiction of the `href` case above, it is the other side of
it. What a message LINKS to was chosen by whoever wrote it, and no view can
name it; what it loads as an avatar was chosen by Slack, and a view can. The
allowance is exactly the difference.

The initials stay: the `<img>` is drawn OVER the disc rather than instead of
it, so a message with no picture, one hosted somewhere the view does not name,
and one whose fetch fails all show the same two letters — up to two, one per
word. An untrusted view has no `onerror` to write and does not need one.
`bluesky/Post` layers the same way and takes its initials by the same rule, and
the two deliberately agree: a host drawing a Slack card beside a Bluesky one
must not draw two different kinds of disc.

A page whose policy does not allow those origins refuses this bundle whole
rather than loading one that draws half of itself. Both demo pages allow those
three origins plus the bluesky reader's two (`@shell.sample_policy`); what the
allowance costs is in `dyncomp/SECURITY.md` §3.

**No global CSS.** The original hides replies, reactions and channel badges with
three `globalStyle` rules (`.hide-replies .msg-foot { display: none }`). There is
no field for global CSS in the manifest, deliberately, so those three toggles are
not ported. Doing it inside the contract means pushing the flags down with
`control.send-at`, the way `expandAll` already does — which is a real
implementation rather than a workaround, just a bigger one than three CSS rules.

**No clock.** A guest has none, and this one never misses it. Timestamps are
data the message arrived with, and `timeLabel` slices `"…T09:12:00Z"` down to
`"09:12"` — reading a string you already hold is not a fact about the world,
and an intent round trip that only bought a nicer phrasing would not be worth
asking a host for.

## The `margauiClasses` view

`Segment` composes its class string from eight independent flags, and the host's
margaui scanner reads `class=` LITERALS off the compiled views to decide which
utility CSS to emit — so a string built in `call-method` is invisible to it. The
bundle therefore ships a second view, `views/Segment.margauiClasses.html`, which
is never rendered and exists only to be scanned. `Components::collect_classes`
walks every view of every registered component, so being unrendered costs
nothing and misses nothing. (The original does the same thing, and calls it the
same name.)

Everything else uses `@if.class` / `@then` / `@else`, whose literals the scanner
DOES see, which is why only this one component needs it.

## A column that arrived too long

`ChannelHistory` holds conversations, `Thread` holds replies and `FileList` holds
files, and how long any of those is was never theirs to decide: a caller asks for
a history with a `limit` and gets back whatever it allowed. Forty rows is a card.
Four hundred is a wall a reader scrolls past rather than reads — and for the two
that build children, four hundred child components drawn before any one of them
is looked at.

So a long list gets a window and the four buttons that move it — `firstPage` /
`prevPage` / `nextPage` / `lastPage`, over `page`, `pageCount`, `pageSize`,
`atFirst` / `atLast`, and the two labels the footer writes (`pageLabel`, and
`rangeLabel` for the `26–50 of 340` a page number does not say). That is the
`table` bundle's vocabulary, and the one the bluesky and mastodon bundles use.

A card pages only once it holds more than a hundred rows, so nothing that already
fits grew a control it does not need; a host that wants the window anyway asks for
a `pageSize`. Three consequences are particular to this bundle:

- **The window is over what the filter left.** `shown()` is `visible()` cut to a
  page, and everything that counts rendered positions goes through it: the field
  the view reads, the write-back that lands by position, and expand-all's
  positional `send-at` paths. So expand-all means the conversations in front of
  the reader, which is what pressing it looks like it means.
- **`openFile` reads its row back through the same window.** A file row is a
  record rather than a child, so `@key` is a position in the rows the view was
  GIVEN — which on page two are not the first files in the list.
- **A thread's `replies` write-back now has two shapes.** The page it was shown
  with a successor in it goes home by position; a list of a different length is a
  host that went and fetched the replies `openThread` asked for, and starts at the
  first page. `replyCount` moves for neither: how many exist is a fact about the
  conversation.

## The `inits` are the storybook

Thirty-eight named configurations across the eight components — every `Segment` style,
a mixed body, a reaction at three counts, a message as a root and as a reply, a
thread expanded, folded, and counted-but-not-loaded, a file listing, two scopes,
a channel loaded / filtered / reversed / empty / loading / failed, and one of each
list-shaped card small enough to page so the footer is somewhere to be seen.

They are not documentation of the storybook; they ARE it. `dyncomp/storybook`
builds one card per `init` straight from the manifest, so `moon run --target
native cmd/dev -- dyncomp-storybook` and opening `/dyncomp-storybook/` shows all
of them with no story file anywhere. Adding an `init` here adds a card there.

## Build

```sh
node guests/build-guest.mjs slack      # from the repo root
node --test dyncomp/test/slack-harness.test.mjs
```

`manifest.json` is checked in and hand-editable, but the `argsJson` fixtures are
JSON inside a JSON string. Editing one by hand is worth doing carefully; the
harness's last test builds every `init` in the file and reads back every declared
field, so a fixture that no longer constructs fails there rather than showing an
empty card.
