# slack — a chat conversation as a `tutuca:component` guest

Six components that display a Slack-style conversation: one message, a thread,
and a channel's history. It is a port of the Feeling-of-Computing conversations
reader ([`at-foc/src/components.js`][foc]) onto the dynamic-component contract
([`../../dyncomp/DESIGN.md`](../../dyncomp/DESIGN.md)).

[foc]: https://github.com/marianoguerra/Feeling-of-Computing/blob/main/at-foc/src/components.js

The shared reference for how a MoonBit guest is laid out, built and packed is
[`../counter/README.md`](../counter/README.md); this one differs only in what it
computes. What is worth reading here is the part of the contract it exists to
exercise, and the two places the contract said no.

| component | what it is |
| --- | --- |
| `Segment` | one styled run of a body: bold, italic, struck, code, a mention, a channel reference, a link |
| `RichText` | a body, as a flat list of `Segment`s |
| `Reaction` | one emoji with its count; clicking toggles yours |
| `Message` | who wrote it, when, its `RichText` body and its `Reaction`s. `compact` is what a reply looks like |
| `Thread` | a root `Message` and its replies, foldable |
| `ChannelHistory` | a channel's `Thread`s, with a filter box and an ordering toggle |

## What it exercises: a DEEP tree of same-bundle children

The other sample guests nest one level at most (`counter`'s `Pair` holds two
`Counter`s). This one nests five: `ChannelHistory` → `Thread` → `Message` →
`RichText` → `Segment`, and the whole tree is built by `control.make-instance`
from ordinary JSON in one `init`.

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

## Two places the contract said no

**No `href`.** An untrusted bundle may not use a network sink attribute
(`dyncomp/policy/view_authority.mbt`), so a link segment is styled text that
`emit`s `openLink` with its URL. Whoever is above decides what a URL means —
here `ChannelHistory` catches it, stops the bubble, and says so in its footer. A
real host would open it, or ask first.

**No global CSS.** The original hides replies, reactions and channel badges with
three `globalStyle` rules (`.hide-replies .msg-foot { display: none }`). There is
no field for global CSS in the manifest, deliberately, so those three toggles are
not ported. Doing it inside the contract means pushing the flags down with
`control.send-at`, the way `expandAll` already does — which is a real
implementation rather than a workaround, just a bigger one than three CSS rules.

**No clock.** `capabilities` is empty. Timestamps are data the message arrived
with, and `timeLabel` slices `"…T09:12:00Z"` down to `"09:12"` — reading a string
you already hold is not a fact about the world.

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

## The `inits` are the storybook

Thirty named configurations across the six components — every `Segment` style,
a mixed body, a reaction at three counts, a message as a root and as a reply, a
thread expanded and folded, and a channel loaded / filtered / reversed / empty /
loading / failed.

They are not documentation of the storybook; they ARE it. `dyncomp/storybook`
builds one card per `init` straight from the manifest, so `moon run --target
native cmd/dev -- dyncomp-storybook` and opening `/dyncomp-storybook/` shows all
thirty with no story file anywhere. Adding an `init` here adds a card there.

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
