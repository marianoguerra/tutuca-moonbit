# Addressed or routed: two channels replace four

v2 has two channels, and one question separates them: **does the sender know
who handles this?**

- If yes, the sender **sends a message**. It goes to one component and stops.
- If no, the sender **dispatches an intent**. It walks a route until something
  answers.

A message is sent. An intent is dispatched. Everything else in this document
follows from that sentence.

This shipped in 0.23.0. It was written as a design and is kept as the argument
behind the code — every "why" the source comments point at is a section here.
For how to USE the two channels rather than why there are two, read
`skill/tutuca/messages-and-intents.md`.

Companion documents: `skill/tutuca/messages-and-intents.md` is the authoring
guide this argues for. `skill/tutuca/events.md` is the view surface section 7
changed. `skill/tutuca/semantics.md` is the path and transaction model that
stayed. `dyncomp/DESIGN.md` is the guest contract section 11 changed — and the
one place v1 survives, because a bundle somebody else compiled has to keep
loading.

The file name uses the spelling the request used. The project name stays
`tutuca`, and so does every identifier below.

## Context

v1 has four dispatch channels (`component/spec.mbt:172`). Sort them by the
question above, and they collapse into two pairs.

| v1 channel | Sender knows the target? | Walks |
| --- | --- | --- |
| `Input` (a DOM event) | yes — this component | nothing |
| `Receive` (`ctx.send`) | yes — one addressed position | nothing |
| `Bubble` (`ctx.bubble`) | no | the **dynamic** scope: the `DispatchPath`, one `pop_step()` for each hop (`transactor/transactor.mbt:501`) |
| `Response` (`ctx.request`) | no | the **lexical** scope (`app/app.mbt:18`, `component/scope.mbt:149`) |

Each pair is one thing split by an accident.

**`Input` and `Receive` are one thing split by who sent it.** Both arrive at one
known component. Neither propagates. Neither can be answered. The only real
difference is a fallback: an `Input` falls through to `swap` and to the
generated mutators, and a `Receive` does not (`input_fallback`,
`component/instance.mbt:391`). So `@on.click="setQuery value"` reaches the
generated setter, and a parent's `ctx.send("setQuery", …)` to the same component
does not. Nothing about the message justifies that; only its origin does.

**`Bubble` and `Response` are one thing split by which scope answers.** Both
search for a handler the sender did not name. One searches ancestors, the other
searches the registration scope. A component that needs something from an
ancestor must spell it as a bubble and invent its own answer, because `request`
reaches the lexical scope only.

The split costs four things.

1. **The author chooses by who answers, not by what is asked.** Four spellings
   for one idea.
2. **A local handler cannot become a shared one.** A view calls
   `@on.click="save"`, and the component answers with `on save`. To let an
   ancestor answer instead, the author rewrites the view handler into a `bubble`
   effect and moves the body. The name is the same, and the code is not.
3. **Answers arrive in two buckets.** A reply to a request lands in `Response`.
   A message lands in `Receive`. The two hold the same kind of data.
4. **The reply payload has two shapes.** The default arm gets `[res, err]`. A
   split arm gets `[res]` or `[err]` (`transactor/transactor.mbt:232`). A split
   arm that matches `[res, err]` reads the wrong argument. The skill calls this
   "a common bug" — v1's skill said so outright.

## 1. Two channels

| | **message** | **intent** |
| --- | --- | --- |
| the verb | **sent** | **dispatched** |
| the sender | knows the target | does not |
| goes to | one component | a route: ancestors, the scope, or both |
| propagates | **no** | yes, until something answers |
| can be answered | no | yes |
| declared with | `receive` | `intent` |

A message stops where it is addressed. If the target declares no arm for the
name, nothing happens, and there is no next position to try, because no route
was ever chosen.

An intent searches. The sender does not name an answerer, and that is the whole
point of it.

### Where a message comes from

Four sources, one bucket. A handler cannot tell them apart, and does not need to.

| Source | Written as | Called a |
| --- | --- | --- |
| this component's own view | `@on.click="save"` | **view message** |
| another component | `sendAt &.email 'focus'` | **directed message** |
| the host | `app.send_at_root("init")` | **host message** |
| an answer to an intent this component dispatched | the runtime writes it | **answer** |

The names are for reading. Nothing declares them, and the runtime does not
distinguish them.

### Two kinds of intent

An intent searches, so the interesting question about one is whether the sender
waits for an answer.

| Kind | The sender declares | The name reads like | Corpus examples |
| --- | --- | --- | --- |
| **notification** | no answer arm | something that **happened** | `rowPicked`, `treeItemSelected`, `queryChanged`, `fieldEdited` |
| **request** | `<name>Ok`, `<name>Error` or `<name>Unhandled` | something to **do** | `loadRows`, `saveDraft`, `applyTheme`, `persistState` |

A notification says "this happened; act on it or do not". A request says "I
cannot do this myself; please do it and tell me".

**This is not a new mechanism.** It is the rule in section 6 read as vocabulary:
a sender expects an answer if, and only if, it declares an answer arm. The
generator therefore already knows which kind each intent is, and no one declares
it.

Two rules of thumb follow. Both are **conventions**, and the last subsection of
this section says what that costs.

- Name a notification for what happened. `rowPicked`, not `pickRow`.
- Name a request for what you want done. `saveDraft`, not `draftSaved`.

### `forward` is the bridge

`forward` is the one thing that crosses between the two channels. It takes the
message a component is handling and **dispatches it as an intent**.

```
receive save(text) { forward }
```

That is the whole of what a component says when a name is not its own. Section 5
has the mechanics.

Nothing crosses the other way. An intent never becomes a message; it produces
an **answer**, which is a message (section 6).

### What the v1 corpus says about all this

The two ideas — **which scope answers** and **whether an answer is expected** —
are independent. v1 has one mechanism for each scope, so it makes the author
encode both in one choice. The corpus shows the strain.

Every v1 `ctx.request` name is a verb: `loadData`, `loadQuote`, `loadState`,
`applyTheme`, `persistState`. Requests to the scope are consistently requests.

v1 `ctx.bubble` names split two ways. Half are notifications: `rowPicked`,
`componentPicked`, `treeItemSelected`, `queryChanged`, `lineReady`,
`fieldEdited`, `navPicked`. Half are verbs — real requests aimed at an ancestor:
`submitForm`, `cancelForm`, `toggleAllViews`, `toggleAllSections`,
`restoreTree`, `rebuildCard`, `closeConfig`.

That second half has no other spelling in v1. The other direction strains too: a
notification to the scope must be sent as a `request` whose answer the sender
discards, which the skill documents as "fire-and-forget"
(`skill/tutuca/messages-and-intents.md`, *Fire-and-forget*).

v2 separates the two ideas. The **route** says which scope answers. The **name
and the declared answer arms** say whether an answer is expected. Each is written
once, in the place it belongs.

### What is checked, and what is only convention

The vocabulary above is not one thing. Some of it the compiler knows. Some of it
is advice, and this document says which is which.

| Statement | Status |
| --- | --- |
| A message goes to its target and no further | **runtime rule** (section 3) |
| A view name that the block neither answers nor forwards | **build warning**, `NO_VIEW_HANDLER` (section 7) |
| A sender expects an answer if it declares an answer arm | **the generator computes it** (section 6) |
| A view call site disagrees with the schema's payload types | **build error** (section 10) |
| An unknown bare name in an `@on` argument slot | **build error** (section 7) |
| Notification names read like events; request names like actions | **convention only** |
| A notification's handler does not call `reply` | **convention only** |

The last row cannot be checked, and the reason is worth stating. **A handler
does not know its sender.** Any component on a route may dispatch `saveDraft`,
and two of them may disagree about whether they want an answer. So no static
pass can decide whether a given `reply` is wanted.

At run time a reply nobody declared reaches no arm. That produces a `NO_HANDLER`
refusal — but only for a host that switched the refusal channel on, since the
channel is off by default (`core/path_path.mbt:248`, `refusing()`). For every
other host it is a silent no-op.

So: **write the convention down, do not rely on it being caught.** Section 18
asks whether the schema should declare that an intent is answerable, which would
turn the last row into a build error at the cost of a declaration.

## 2. Messages

A message has a name, arguments and a target. It has no route, no answer and no
next position.

```
send 'flash' .msg                    // to this component
sendAt &.status 'flash' 'Saved'      // to an addressed position
```

`&.place` names a **position**, not the value at it, and it is legal only as the
first argument of `sendAt` (`tscript/script_spec.mbt`, `ERef`). A position
survives the root being rebuilt, which is what makes an addressed delivery land
where it was aimed.

A component answers a message with `receive`:

```
receive flash(text) { .text = text }
```

### Delivery

A message is offered to three answerers, in this order. v1 uses the same order
for `Input` (`component/instance.mbt:391`).

1. a `swap` entry of that name;
2. a declared `receive` handler of that name;
3. the **generated mutator** of that name (`setX`, `pushInX`, `toggleX`, …).

If none of the three answers, nothing happens.

**This widens v1.** In v1 only an `Input` falls through to `swap` and the
generated mutators; a `ctx.send` does not. v2 removes that difference, because
nothing about a message justifies it — only its origin did. A parent can
therefore drive a child's generated setter with
`sendAt &.email 'setValue' 'x'`. `skill/tutuca/core.md` already blesses the
shape ("the owner returns a new state … or messages the child with `ctx.send`");
v2 makes the two spellings agree. Section 16 lists this as a risk.

## 3. Intents and routes

An intent has a name, arguments and a **route**. A route has one or two **legs**.

| Leg | Walks | Handlers are |
| --- | --- | --- |
| `dyn` | the dynamic scope: the dispatch path, up to the root | component **instances**, with state |
| `lex` | the lexical scope: the registration scope chain (`component/scope.mbt:149`) | **static** handlers, with no state |

Write the legs before the name. The default route is `dyn lex`.

```
intent 'save' .draft           // dyn, then lex — the default
intent dyn 'picked' @key       // dyn only — this is v1 bubble
intent lex 'loadRows' .query   // lex only — this is v1 request
intent lex dyn 'save' .draft   // lex, then dyn
```

The leg words are a closed set. The name is always a string literal. The parser
reads leg words until it finds a literal. This adds no ambiguity to
juxtaposition.

**The `dyn` leg starts at the parent** of the component that dispatched the
intent. One rule, so a component never re-enters its own handler, and a cycle
needs two components. A component cannot dispatch an intent to itself; use
`send`, which is what `receive` is for.

**A view never states a route.** A view raises a message (section 7), and a
message has no route. `forward` is where a view name picks one, and it is the
only place one can.

## 4. Why a view message does not walk by default

A view name that this component does not answer could walk to the ancestors
instead of stopping. It does not, and the reason is not only speed.

- **Work.** A name that nothing answers would visit every ancestor and then the
  whole registration chain, on every click. A silent name would be the most
  expensive one.
- **Meaning.** In v1 a view name that nothing answers is a no-op. If the same
  code walked in v2, a migrated project could change behaviour in silence: a
  dead click reaches an ancestor that declares the same name for its own view,
  and starts firing. A migration must not do that.

So escape is written, once, by the component that lets the name out. Section 7
gives it a checker rule as well, so a name that neither answers nor forwards is
reported rather than dead.

## 5. Delivery along a route, and `forward`

A dispatched intent walks the legs in the order the route gives.

1. On the `dyn` leg, the runtime visits each instance from the sender's parent
   up to the root.
2. On the `lex` leg, the runtime looks up the name in the registration scope,
   from the child scope to the parent scope.

At every routed position, only a declared `intent` handler can answer. A
generated mutator answers a message at home and never an intent up a route.

**Every handler on the route runs.** A handler that runs does not consume the
intent.

The walk ends for one of three reasons.

| Reason | What happens next |
| --- | --- |
| a handler calls `reply` or `fail` | the walk stops; the answer goes to the sender |
| a handler calls `stop` | the walk stops; no answer goes to the sender |
| the route ends | see section 6 |

One rule holds all of v1's behaviours. Many observers can watch an intent,
because an observer does not reply. One handler can answer an intent, because a
reply ends the walk.

**A failed `requires` does not consume the intent.** The transition does not
happen, the effects are dropped (`tscript/conformance/corpus.mbt`), and the walk
continues to the next handler. v1 can express this in no mechanism.

### `forward`

`forward` does two jobs, and they are the same job seen from two sides.

- In a **`receive`** body, it dispatches the message as an intent. The route
  starts at this component's parent.
- In an **`intent`** body, it continues the walk after this position.

```
receive saveDraft(text) {
  .attempts += 1
  forward
}
```

`forward` takes leg words, exactly as `intent` does. This is where a view name
chooses its route, and it is the only place one can.

```
forward              // dyn, then lex — the default
forward dyn          // ancestors only
forward lex          // registered handlers only
forward .enriched    // amend the payload, keep the name and the route
```

Two facts make `forward` different from dispatching the intent again.

- The **answer target does not move**. A handler further up answers the original
  component, not the one that forwarded. For a view message, that is the
  component the user clicked in.
- The **arguments do not have to be rebuilt**. `forward` with no arguments
  passes the ones that arrived.

Forwarding a message that came from an ancestor is well defined: the ancestor
receives it as an **intent**, in its `intent` bucket, which is not the bucket it
sent from. There is no cycle. It is rarely what you want, and the language does
not refuse it.

## 6. Three outcomes

The runtime derives three message names from the intent name.

| Outcome | What produced it | Message the sender receives |
| --- | --- | --- |
| success | a handler called `reply v` | `<name>Ok(v)` |
| failure | a handler called `fail e` | `<name>Error(e)` |
| unhandled | the route ended with no reply | `<name>Unhandled(…the intent's own arguments)` |

An intent named `loadRows` therefore answers as `loadRowsOk`, `loadRowsError` or
`loadRowsUnhandled`. The first two names match the `on_ok_name` and
`on_error_name` keys that `RequestOpts` already has (`core/path_spec.mbt:37-38`).
All three match the camelCase spelling of every generated mutator.

Each outcome has one name and one payload. The combined `[res, err]` payload of
v1 is removed, and the bug it causes is removed with it.

**An answer is a message.** It lands in `receive`, beside every other message. A
test can drive one with `send`, and a component cannot tell the two apart.

### The unhandled outcome

`<name>Unhandled` carries **the intent's own arguments**, not an error value.
The sender can therefore degrade or retry without keeping a copy:

```
receive saveDraftUnhandled(text) {
  .queued.push text
  .note = 'saved locally'
}
```

**If the sender does not declare `<name>Unhandled`, the runtime sends
`<name>Error` instead**, with a `noHandler` value. A sender that does not care
why an answer is missing writes one arm. A sender that does care writes two.

The distinction is the one the refusal taxonomy already draws: *nothing claimed
it* is not *a rule refused it* (`skill/tutuca/schema.md`).

### When a sender expects an answer

**A sender expects an answer if, and only if, its schema declares `<name>Ok`,
`<name>Error` or `<name>Unhandled` in its `receive` variant.** This is the rule
that makes an intent a request rather than a notification (section 1).

The property is static. The schema shows it, and the generator reads it. It
decides what happens when the route ends with no reply:

- The sender expects an answer. The runtime sends `<name>Unhandled`, or
  `<name>Error` when the first is not declared.
- The sender expects no answer. Nothing happens. This is a notification, and no
  ancestor had to answer it.

A sender that declares `<name>Ok` alone gets a refusal record for each failure
and each unhandled intent. An answer never disappears in silence.

`stop` produces no answer at all, even when the sender expects one. `stop` says
"served, and no answer".

## 7. The view sends a message

`@on.<event>="<name> <arg> <arg>…"` **sends a message** with that name and those
arguments, to the component that owns the view. The shape is the one v1 already
has. What changes is what the dispatch means, and how an event argument is
spelled.

```html
<button @on.click="inc">+</button>
<input  @on.input="setQuery e.value" />
<button @on.click="removeInItemsAt @key">x</button>
<button @on.click="saveDraft .text">Save</button>
```

What does not change:

- The **message name** is written **bare**. A leading `$` is still refused in an
  event position.
- Event modifiers are the same guards on `keydown` and `click`.
- The generated mutators still answer. `setQuery` and `removeInItemsAt` reach
  the setter every field gets.
- An unanswered name still costs one lookup, exactly as v1 does.

Two things change. **The name can leave the component**, which is the rest of
this section. And **event arguments carry a prefix**, which is the next
subsection.

In v1 a view name reaches this component and stops, forever. In v2 it reaches
this component and stops **until a handler forwards it**, and then it is an
intent, and an ancestor or a registered handler can answer it.

This is the point of the change. A view that says `@on.click="saveDraft .text"`
says what the user asked for. It does not say who answers. The component may
answer it today, a parent may answer it tomorrow, and the view does not change.

### Event arguments are written `e.`

**An `@on` handler is the boundary between two domains.** On one side is the
DOM: elements, events, host objects, anything a browser has. On the other side
is tutuca: `Value`, and nothing else. The handler's whole job is to map the
first into the second.

**The argument list is the boundary, and each argument is one crossing.** Only a
`Value` crosses. Everything past the boundary — every handler, every test, every
guest — sees `Value` and never sees the DOM. This is the rule the rest of this
section follows from, and every choice below is that rule applied.

An argument that reads the DOM event is written `e.<path>`: `e.value`,
`e.valueAsInt`, `e.isAlt`, `e.detail.unicode`, `e.target.dataset.rowId`.

```html
<input  @on.input="setQuery e.value" />
<input  @on.input="setCount e.valueAsInt" />
<button @on.click="pick @key e.isAlt">pick</button>
<li     @on.drop="moveHere e.dragKey @key">…</li>
<section @on.emoji-click="onEmoji e.detail.unicode">…</section>
```

**An argument is a prefixed read or a literal. No bare name is allowed.** The
message name is the one unprefixed name in a handler, and it is always first.

| Written | Reads |
| --- | --- |
| `.x` | a field on this component's state |
| `@x` | a loop or scope binding |
| `e.x`, `e.x.y` | the DOM event that fired |
| `'…'`, a number, `true`, `false`, `null` | a literal |

**`e` is a namespace, not a value.** There is no bare `e`, the way there is no
bare `$$`. Section "Why `e` is not a value" says what that is worth.

v1 leaves event accessors bare, which makes them the one value form in the whole
notation with no prefix (`skill/tutuca/core.md`, *Notation Reference*). The cost
of that is measurable in this repository.

| Written in an `@on` argument | Means | Uses |
| --- | --- | --- |
| `value` | the DOM event's value | 315 |
| `@value` | the loop item | 8 |
| `key` | the **keyboard** key | 1 |
| `@key` | the **loop** key | 153 |

The two pairs have **opposite defaults**, and one sigil separates each pair. An
author who learns that `value` is the event's value will read `@key` and
reasonably guess that `key` is the loop's key. It is not. 479 handlers pass a
bare accessor and an `@` binding side by side, so the two namespaces sit next to
each other in almost every handler that takes arguments.

#### How `e.<path>` resolves

Two layers, in this order.

1. **A known accessor.** `value`, `valueAsInt`, `valueAsFloat`, `key`, `keyCode`,
   `isAlt`, `isShift`, `isCtrl`, `isCmd`, `isSend`, `isCancel`, `isTabKey`,
   `isUpKey`, `isDownKey`, `dragInfo`, `dragKey`, `dragValue`, `dragType`.
2. **A path on the event**, otherwise. Every step through a host object must be
   on the allowlist below. Only the **leaf** crosses, converted to a `Value`; a
   step in the middle stays on the DOM side. A path that does not resolve, or
   whose leaf is not representable, is `Null`.

**The known accessors are not raw property reads, and this is why layer 1 must
come first.** A DOM `Event` has no `value` property at all. `value` is computed
by the glue: the checked state on a checkbox, the picked file's metadata `Map` on
a file input, the `detail` on a `CustomEvent`, and the input's string otherwise
(`skill/tutuca/events.md`). Resolve it dynamically and all 315 call sites read
`Null`. So the known names stay, as **typed computed shorthands that shadow the
path**, and everything else falls through.

Both layers cross at the leaf, and they differ in who chose the crossing. Layer
1 is a **curated** crossing the framework knows and types. Layer 2 is an
**ad-hoc** crossing the author names, within an allowlist. Neither lets a DOM
object through: the traversal happens on the DOM side, and only the leaf is
converted.

- Layer 1 keeps the **payload types**. `e.value` on a checkbox is `Bool`,
  `e.valueAsInt` is `Double`, `e.isAlt` is `Bool` — the inference table v1
  already has (`skill/tutuca/events.md`). It is not a permission list any more;
  it is a **type oracle**.
- Layer 2 keeps the **language open**. `e.deltaY`, `e.pointerId`,
  `e.detail.unicode`, `e.target.dataset.rowId` work with no framework release. A
  layer-2 read is `@tutuca.Value`, because nothing knows its type.

`e.detail.unicode` is worth calling out. v1 routes a `CustomEvent`'s `detail`
through `value` as a `Map`, and the handler opens it
(`skill/tutuca/events.md`, *Web components*). v2 reads the field.

#### Every step is allowlisted, and the result is always a `Value`

Two rules, and the second is the one that is easy to get wrong.

**1. An `e.` path always produces a `Value`.** Never an element, never a
document, never a host object of any kind. A path whose leaf is not
representable is `Null`. So `e.target` on its own is `Null`: an `Element` is a
DOM-domain object, and the boundary does not let one across.

**2. Every step through a host object must be on an allowlist.** Not only the
first one.

The second rule is not caution, it is necessary. An earlier draft of this
section allowlisted the **root** segment and let the path run free below it.
That does not hold:

```
e.target.ownerDocument.defaultView.localStorage.length
```

`target` is a permitted root, every step after it is an ordinary property read,
and the leaf is a number — so it converts cleanly, and a view template has just
read the window. Rule 1 alone does not stop this, because the leaf **is**
representable. A view is data the host compiles, including a view a dyncomp
guest supplied (`dyncomp/DESIGN.md`, principle 2), so this is ambient authority
that no guest declared — what principle 4 of that document forbids.

The allowlist therefore covers **paths, not roots**:

| Allowed | Why |
| --- | --- |
| a scalar on the event interface — `e.deltaY`, `e.pointerId`, `e.clientX` | it is already a value; nothing is traversed |
| `e.target.value`, `.checked`, `.id`, `.name`, `.selectedIndex`, … | the element's own form state |
| `e.target.dataset.<anything>` | `data-` attributes, which the author wrote |
| `e.detail.<anything>` | a `CustomEvent` payload, which the app itself built |
| `e.dataTransfer.types` | the drop's declared types |
| **anything else through a host object** | **refused** |

Note where the list stops needing to be a list. `dataset` and `detail` are
**author data**, not host capability — a `DOMStringMap` of strings, and an
object the application constructed. Once a step reaches author data, the rest of
the path is free, because there is nothing left to escalate into. The allowlist
governs exactly the boundary between host objects and data, and no further.

That is also what keeps the language open. The **scalars** come from a
**generated** table (below), so `e.deltaY` and any property a future event
interface gains work with no framework release. Only the handful of
**object-valued** steps are curated, and those are the ones that can escalate.

The generated table should come from a **machine-readable DOM specification** at
a pinned commit, not from a transcription. This repository already does exactly
that for the sanitizer baseline: `anode/sanitize/spec_default_gen.mbt` is
regenerated by the `sanitizer-defaults` task from the WHATWG spec repo
(`AGENTS.md`), after the first hand-read list dropped SVG's `script` and opened a
hole. The rule there applies here word for word: **never hand-transcribe an
allow-list.**

#### Privileged information is an intent, not a path

The event boundary is deliberately narrow. A component that needs something the
allowlist does not carry — the window size, the URL, the clipboard, a stored
preference — **dispatches an intent**, and the host registers a handler for it.

```
receive resized { intent lex 'viewportSize' }
receive viewportSizeOk(size) { .w = size.w }
```

This is not a workaround. It is the only place the two channels differ in a way
that matters for authority.

- An **event path** has no caller. A view is compiled data, so nothing is on the
  other end to authorize. It therefore must be narrow, and it must be narrow by
  construction rather than by policy.
- An **intent** carries `IntentCall.from`, the sender's `DispatchPath`
  (section 10). A host can look at who is asking and decide. A `DynObj` sitting
  at that path names its bundle, which is what
  `dyncomp/SECURITY.md` §5 asks for and cannot have today.

So: **capability is granted through a channel that knows the caller, never
reached through one that does not.** That is `dyncomp/DESIGN.md`'s fourth
principle — "ambient authority is granted, never assumed" — applied to the DOM
instead of to wasm imports. It is the same rule the runtime-markup directives
already follow: an untrusted guest may not use `@setinnerhtml`, not because of
XSS, but because an `<img src>` is a request to an origin the guest chose
(`skill/tutuca/core.md`).

#### The lint

A step that is not on the allowlist is a **build error**. It can never resolve,
and reporting it as a warning would leave a view that reads `Null` forever.

A rooted path that names a property the DOM specification does not have is a
**warning**: `e.target.valeu` is a typing mistake, and `e.target.someVendorThing`
may be deliberate. The warning names the closest known property.

#### Why `e` is not a value

An earlier draft of this document let `e` be the whole event, as an `Obj`
snapshot. That draft was wrong, and the principle at the top of this section is
why: an event is a DOM-domain object, so it is exactly the thing that must not
cross.

The practical payoff is in testing. **A handler only ever receives plain
`Value`s.** So a test drives a handler by supplying values, and nothing has to
build an event-shaped object to pass in.
`@harness`'s `click` / `type_into` / `key_down` / `drag` stay what they are, and
`send_at_root` and a dyncomp guest's synthetic dispatch need no event mock at
all. v1 makes this point about its own design — "an arm matching `[Str(q), ..]`
off a plain `value` is trivial to call from a test"
(`skill/tutuca/events.md`) — and a bare `e` would have given it up.

A snapshot `e` also has to be built eagerly, because a message a handler
**forwards** becomes a queued intent, and by then the DOM event is gone. With no
bare `e`, nothing is ever snapshotted: each argument is resolved to one value at
dispatch, which is what v1 already does.

The cost is that a handler cannot take "the whole event". It has to name the
parts it wants. Given that naming the parts is what makes the payload typed and
the test simple, that is the right cost.

### Every view name is declared: `NO_VIEW_HANDLER`

A view name the component does not answer does nothing. That is the safe
default, and it is also the shape of a typing mistake. The checker therefore
reports it.

```
receive saveDraft(text) { forward }
```

`NO_VIEW_HANDLER` names a view name that the block neither answers nor forwards.
The message names both fixes.

```
NO_VIEW_HANDLER  Draft: the view sends `saveDraft`, and this block neither
answers it nor forwards it. Write `receive saveDraft(text) { forward }` to
dispatch it as an intent, or `receive saveDraft(text) { … }` to answer it here.
```

The rule buys three things.

1. **Typing mistakes stop at the build.** A misspelled `@on` name has no
   handler and no forwarder, so it is reported. In v1 the same mistake is a
   silent no-op that nothing finds.
2. **A component states its own vocabulary.** Read the block, and you know every
   name the component answers and every name it lets out. Nothing is inferred
   from the absence of a declaration.
3. **The route is compiled, not discovered.** The generator knows which names
   leave before anything runs.

The rule does not have to carry the run-time cost as well, because the default
already does. This is what makes a **warning** the right severity: a project
that ignores it behaves exactly as v1 behaves.

The finding belongs in `tscript/check`, which already holds the view surface and
the block declarations together (`tscript/check/check.mbt`). It joins `NO_PRED`,
`NO_FIELD` and `NO_TARGET`, which report the same kind of gap.

**Warning first, error later.** Land it as a warning and run it over the corpus.
Read what it finds, then decide if a strict mode makes it an error. This is the
order `docs/` uses for every diagnostic that touches existing code, and here it
is safe by construction: the warned code already behaves as v1 does.

## 8. The block language

The declaration kinds go from nine to **seven**.

| v1 kind | v2 kind |
| --- | --- |
| `on` | `receive` — a view name is a message |
| `receive` | `receive` — now also holds view names and answers |
| `bubble` | `intent` |
| `response` | removed; the answer is a `receive` |
| `compute`, `pred`, `invariant`, `enrich`, `enrichScope` | unchanged |

`on` and `receive` fold together because v1 split one thing by who sent it
(Context). `bubble` becomes `intent` because a bubble is a routed dispatch that
could only search one scope.

The effects change the same way.

| v1 effect | Minimum arguments | v2 effect | Minimum arguments |
| --- | --- | --- | --- |
| `send` | 1 | `send` | 1 |
| `sendAt` | 2 | `sendAt` | 2 |
| `bubble` | 1 | `intent` | 1, after the leg words |
| `request` | 1 | `intent` | 1, after the leg words |
| `stop` | 0 | `stop` | 0 |
| — | — | `forward` | 0, after the leg words |
| — | — | `reply` | 1 |
| — | — | `fail` | 1 |

`reply` and `fail` are legal in an `intent` body only: a message has no sender to
answer. `forward` is legal in a `receive` body and in an `intent` body. The
checker refuses each elsewhere, with the code `NOT_A_HANDLER`.

The word `intent` names both a declaration and an effect. v1 does the same with
`bubble` (`tscript/script_parse.mbt:158-184`). The position decides: a
declaration starts a line at the top level, and an effect starts a statement in a
body.

## 9. The state block

The three message variants become two.

```html
<!-- v1 -->
<script type="tutuca/state">
  state Board { rows: Array[Any], loading: Bool }
  receive  Board { Reset, FocusRow(Int) }
  bubble   Board { RowPicked(Int) }
  response Board { LoadRows(Array[Any]) }
</script>
```

```html
<!-- v2 -->
<script type="tutuca/state">
  state Board { rows: Array[Any], loading: Bool }
  receive Board {
    Reset, FocusRow(Int),
    LoadRowsOk(Array[Any]), LoadRowsError(String), LoadRowsUnhandled(String)
  }
  intent  Board { RowPicked(Int) }
</script>
```

`receive` declares every **message** the component accepts, beyond the ones its
own views send: what a parent sends it, what the host sends it, and every answer
it reads. `intent` declares every **intent** it answers.

## 10. The MoonBit surface

```moonbit
pub(all) enum Dispatch {
  /// Addressed: a view, a parent, the host, or an answer.
  Receive(String, Array[@tutuca.Value])
  /// Routed: dispatched by someone who did not name a target.
  Intent(String, Array[@tutuca.Value])
}

pub(all) enum HandlerBucket {
  Receive
  Intent
}

pub(all) enum Leg {
  Dyn
  Lex
}

pub(all) struct IntentOpts {
  /// The legs to walk, in order. `[Dyn, Lex]` when nothing says otherwise.
  route : Array[Leg]
  on_ok_name : String?
  on_error_name : String?
  on_unhandled_name : String?
  live_path : Bool
}

/// A static handler. It has no instance and no state.
pub(all) struct IntentFn(
  (IntentCall, (IntentAnswer) -> Unit) -> Unit
)

pub(all) enum IntentAnswer {
  Ok(@tutuca.Value)
  Failed(@tutuca.Value)
  /// Decline. The walk continues to the next handler on the route.
  Pass
}

pub(all) struct IntentCall {
  name : String
  args : Array[@tutuca.Value]
  /// The sender's position. A host reads it to decide if the sender may ask.
  from : @tutuca.DispatchPath
}
```

`IntentAnswer::Pass` is what a static handler needs and `RequestFn` does not
have. A `RequestFn` must answer (`transactor/transactor.mbt:232`). An `IntentFn`
may decline, which is the same freedom a component handler has when its `update`
arm answers `Unhandled`.

`Ctx` gains four methods and loses two.

| Method | Does |
| --- | --- |
| `send(name, args)` / `send_at_path(path, name, args)` | send a message |
| `intent(name, args, opts)` | dispatch an intent; the `dyn` leg starts at the parent |
| `forward(args?, opts?)` | dispatch the message being handled, or continue the walk |
| `reply(value)` / `fail(error)` | answer the intent this handler received |
| `stop_propagation()` | end the walk with no answer; keep the v1 name |
| ~~`bubble`~~, ~~`request`~~ | removed |

`IntentCall.from` closes an open item. `dyncomp/SECURITY.md` §5 says a host
cannot authorize its own request handlers, because `RequestFn` never receives the
caller's `DispatchPath`. The intent walk needs that path to route the answer. The
handler therefore gets it for free.

`Update[S]` does not change. `Next`, `Unchanged` and `Unhandled` keep their
meanings, and for an intent `Unhandled` now means "the walk goes on".

### The generated enums merge

v1 generates `<T>Msg` from the names the views call (`viewgen/emit.mbt:435`),
`<T>Receive` from the schema's `receive` variant, `<T>Bubble` from its `bubble`
variant and `<T>Response` from its `response` variant
(`viewgen/emit_msgs.mbt:17`). Four enums.

v2 generates two. `<T>Receive` merges the view names with the schema's `receive`
variant. When a name is in both, the schema declares the payload types and the
generator checks the view's inferred shape against it. A view call site that
disagrees with the schema is a build error. v1 cannot report this, because the
two names live in two enums. `<T>Intent` replaces `<T>Bubble`. `<T>Response` is
removed.

## 11. Dynamic components

`ControlMsg` (`dyncomp/host/guest.mbt:14`) changes to match.

| v1 | v2 |
| --- | --- |
| `Emit(name, args)` | `Intent(name, args, opts)` |
| `BubbleAt(steps, name, args)` | `IntentAt(steps, name, args, opts)` |
| `Request(name, args, opts)` | folded into `Intent` |
| `Send`, `SendAt`, `StopPropagation` | unchanged |
| — | `Reply(value)`, `Fail(error)`, `Forward(args, opts)` |

A guest manifest declares `receives` and `intents`. It no longer declares
`bubbles`, `responses` or `requests` (`dyncomp/host/dynobj.mbt:376`). The WIT
interface needs a major version. The section "What to check when changing this"
in `dyncomp/SECURITY.md` applies.

A bundle keeps its own intents in a child scope, as it keeps its own request
handlers today (`dyncomp/host/bundle.mbt:228`). The `lex` leg finds the bundle's
handler first, and the host's handler second.

## 12. Worked examples

### 12.1 A local handler

The name goes in the view. The handler answers it at home. Nothing is dispatched.

```html
<script type="tutuca/state">
  state Counter { count: Int }
</script>

<script type="tutuca/script" for="Counter">
  receive inc { .count += 1 }
</script>

<template id="Counter">
  <button @on.click="inc" @text=".count"></button>
</template>
```

`receive inc` replaces v1's `on inc`. The rename is the whole change, and it says
the truth: a click is a message to this component.

### 12.2 The same view, answered by a parent

`Counter` above answers `inc` itself. To let a parent answer instead, replace the
body with `forward`. The view does not change, and the name does not move.

```html
<script type="tutuca/script" for="Counter">
  receive inc { forward }
</script>
```

The parent then declares the name as an **intent** and answers it:

```html
<script type="tutuca/state">
  state Panel { total: Int }
  intent Panel { Inc }
</script>

<script type="tutuca/script" for="Panel">
  intent inc { .total += 1 }
</script>
```

This is the change worth having. In v1 the same move rewrites the view's handler
into a `bubble` effect, changes a declaration into an effect, and moves the body.
In v2 the view is untouched, the name stays where it was, and one body becomes
`forward`.

The two declarations read as what they are. `receive inc` is "a click reached
me". `intent inc` is "somebody below asked for this".

### 12.3 A notification up the tree

This replaces v1 `bubble`. The item declares no answer arm, so it expects no
answer, and the walk ends in silence.

```html
<script type="tutuca/state">
  state TreeItem { label: String }

  state TreeLog { log: Array[String], count: Int }
  intent TreeLog { ItemPicked(String) }
</script>

<script type="tutuca/script" for="TreeItem">
  receive itemPicked(label) { forward dyn }
</script>

<script type="tutuca/script" for="TreeLog">
  intent itemPicked(label) {
    .log.push label
    .count += 1
  }
</script>

<template id="TreeItem">
  <li @on.click="itemPicked .label" @text=".label"></li>
</template>
```

`TreeItem` forwards, which is how it says the name is not its own. `forward dyn`
keeps the notification inside the tree, since no registered handler serves it.
`TreeLog` records it and does not reply, so the walk continues to the root. A
second ancestor that also declares `itemPicked` also runs.

The forwarder is what the design costs here. A leaf that reports three things
declares three of them. It is the same line count as v1, which writes
`on itemPicked(label) { bubble 'itemPicked' label }` — but v2 does not repeat the
name, and does not turn a declaration into an effect. Section 18 asks whether the
language should shorten it further.

### 12.4 A request to the scope

This replaces v1 `request` and `response`.

```html
<script type="tutuca/state">
  state Rows {
    query   : String
    rows    : Array[Any]
    loading : Bool
    error   : String
  }
  receive Rows {
    Init,
    LoadRowsOk(Array[Any]), LoadRowsError(String), LoadRowsUnhandled(String)
  }
</script>

<script type="tutuca/script" for="Rows">
  receive init {
    intent lex 'loadRows' .query
    .loading = true
  }

  receive loadRowsOk(rows) {
    .rows = rows
    .loading = false
    .error = ''
  }

  receive loadRowsError(e) {
    .loading = false
    .error = e
  }

  receive loadRowsUnhandled(q) {
    .loading = false
    .error = $'no handler for "{q}"'
  }
</script>
```

`init` is a host message, and the three answers are messages too, so all four
arms are `receive`. Only the one dispatched thing is an `intent`.

The three answer arms say three different things. v1 says two of them with one
`[res, err]` arm, and cannot say the third: a missing handler arrives as the
string `Request not found: loadRows` in the error slot
(`transactor/transactor.mbt:232`).

### 12.5 The default route

`Draft` asks to save. It does not know who answers.

```html
<script type="tutuca/state">
  state Draft {
    text: String, savedId: String, dirty: Bool, error: String
    queued: Array[String]
  }
  receive Draft { SaveDraftOk(String), SaveDraftError(String), SaveDraftUnhandled(String) }

  state Form { pending: Array[String] }
  intent Form { SaveDraft(String) }
</script>

<script type="tutuca/script" for="Draft">
  receive saveDraft(text) { forward }

  receive saveDraftOk(id) {
    .savedId = id
    .dirty = false
  }

  receive saveDraftError(e) { .error = e }

  receive saveDraftUnhandled(text) {
    .queued.push text
    .error = 'offline; saved locally'
  }
</script>

<script type="tutuca/script" for="Form">
  intent saveDraft(text) {
    .pending.push text
    reply 'pending'
  }
</script>

<template id="Draft">
  <button @on.click="saveDraft .text">Save</button>
</template>
```

`Draft` declares one forwarder. That line is the whole of what it knows: the name
leaves, and somebody upstream owns it. Three results follow, and the view is the
same in all three:

- A `Form` encloses the draft. `Form` answers on the `dyn` leg, and the `lex` leg
  never runs.
- No `Form` encloses the draft. The `dyn` leg ends with no reply. The `lex` leg
  runs, and the registered `saveDraft` handler writes to the server.
- Nothing serves `saveDraft` on either leg. `saveDraftUnhandled` runs, and the
  draft is queued.

Delete the `forward` line and `Draft` keeps the name at home. The button then
does nothing, and the checker says so.

### 12.6 Handle locally, then forward

`Section` counts every save that passes through it. It does not answer.

```html
<script type="tutuca/script" for="Section">
  intent saveDraft(text) {
    .saves += 1
    forward
  }
</script>
```

The walk continues after `Section`. Whoever answers answers `Draft`, not
`Section`. `Section` does not rebuild the arguments.

### 12.7 The reversed route

`lex dyn` puts the application's policy first, and the enclosing component
second.

```html
<script type="tutuca/script" for="DeleteButton">
  receive deleteRow(id) { intent lex dyn 'askUser' id }

  receive askUserOk(id) { intent lex 'removeRow' id }
  receive askUserUnhandled(id) { .note = 'nobody can confirm' }
</script>
```

The registered handler answers when the user set "do not ask again". It declines
with `Pass` otherwise. The `dyn` leg then reaches the dialog host, which asks the
user and replies later. The button does not know which one answered.

### 12.8 Ask an ancestor for information

A handler on the `dyn` leg has state, so it can answer from that state.

```html
<script type="tutuca/state">
  state Session { user: String }
  intent Session { CurrentUser }

  state Greeting { name: String }
  receive Greeting { Init, CurrentUserOk(String), CurrentUserUnhandled }
</script>

<script type="tutuca/script" for="Session">
  intent currentUser { reply .user }
</script>

<script type="tutuca/script" for="Greeting">
  receive init { intent dyn 'currentUser' }
  receive currentUserOk(name) { .name = name }
  receive currentUserUnhandled { .name = 'guest' }
</script>
```

Read **down** the tree with a field, not with an intent. An ancestor already
holds its children and can read them (`skill/tutuca/core.md`, *Mental model*).
Dispatch an intent to read **up** the tree, where no field exists.

### 12.9 One bucket, four sources

```html
<script type="tutuca/script" for="Status">
  receive dismiss { .text = '' }                        // this view
  receive flash(text) { .text = text }                  // a parent's sendAt
  receive serverPushed(m) { .text = m }                 // the host
  receive saveDraftOk(id) { .text = $'saved {id}' }     // an answer
</script>

<script type="tutuca/script" for="Toolbar">
  receive ping { sendAt &.status 'flash' 'Saved' }
</script>
```

Four sources, one declaration kind. `Status` cannot tell them apart, and nothing
about its code would improve if it could.

## 13. Corner cases

| Case | Rule |
| --- | --- |
| A view name that the component answers | The `receive` arm, the `swap` entry or the generated mutator answers. Nothing is dispatched. |
| A view name that the component does not answer | Nothing happens, as in v1. The checker reports `NO_VIEW_HANDLER`. |
| A view name that must reach an ancestor | Declare `receive name(args) { forward }`. This is the only way out, and it is one line. |
| A view name that is also a generated mutator | The mutator answers. An ancestor never sees `setTitle` unless a `receive` arm forwards it first. This matches v1. |
| A parent's `sendAt` naming a generated mutator | The mutator answers. **This is new**: v1 restricts that fallback to a DOM event (section 2). |
| A handler that must mutate **and** let an ancestor see the name | Declare the handler, mutate, then `forward`. |
| A message the target does not declare | Nothing happens, and nothing propagates. A `NO_HANDLER` refusal is written when the host asked for one. |
| Forwarding a message that came from an ancestor | Well defined. The ancestor receives it in its `intent` bucket, not the `receive` it sent from, so there is no cycle. Rarely wanted, never refused. |
| Forwarding an **answer** (`fooOk`) | Legal, and dispatches an intent named `fooOk`. Almost certainly a mistake; nothing static can catch it. |
| Nothing on the route answers, and the sender declares `<name>Unhandled` | The sender receives `<name>Unhandled` with the intent's own arguments. |
| Nothing answers, and the sender declares `<name>Error` but not `<name>Unhandled` | The sender receives `<name>Error` with a `noHandler` value. |
| Nothing answers, and the sender declares none of the three | Nothing happens. This is a notification. |
| A handler calls `stop` | The walk ends and the sender receives nothing, even when it expects an answer. |
| An observer sits below a handler that replies | Both run. The observer runs first, because the walk goes upward. |
| Two handlers reply to one intent | The first reply ends the walk, so the second handler never runs. A second `reply` in one body is dropped, and the runtime writes a `SECOND_REPLY` refusal. |
| The sender's position no longer resolves when the answer arrives | The answer is a no-op, and the runtime writes a `PATH_UNRESOLVED` refusal. The position is pinned at dispatch time, as `live_path=false` does today. |
| A `requires` refuses a handler in the middle of the walk | The transition does not happen and its effects are dropped. The walk continues to the next handler. |
| A handler dispatches a new intent of the same name | The `dyn` leg starts at the parent, so the handler does not re-enter itself. |
| `forward` in a handler that already replied | The reply already ended the walk. The `forward` is dropped, and the runtime writes a `SECOND_REPLY` refusal. |
| Two components forward the same intent in a cycle | A depth counter ends the chain and writes an `INTENT_DEPTH` refusal. |
| Both legs serve the same name | The route order decides. Read the route to know the answer; do not read the registration order. |
| A handler replies to a sender that expects no answer | The message reaches no arm, and the refusal is the same one. Nothing static can catch it (section 1). |

## 14. Refusals

The refusal channel keeps its five codes (`skill/tutuca/schema.md`). It gains
two.

| Code | Means |
| --- | --- |
| `SECOND_REPLY` | A body answered twice, or forwarded after it answered. The second call is dropped. |
| `INTENT_DEPTH` | An intent chain passed the depth limit. The chain is cut. |

`NO_HANDLER` covers a message that reaches no arm. `PATH_UNRESOLVED` covers an
answer to a position that is gone.

## 15. Migration

The mapping is mechanical. A tool can do it.

| v1 | v2 |
| --- | --- |
| `on name(args) { … }` | `receive name(args) { … }` |
| `receive name(args) { … }` | unchanged |
| `bubble name(args) { … }` | `intent name(args) { … }` |
| `bubble 'name' args` | `intent dyn 'name' args` |
| `request 'name' args` | `intent lex 'name' args` |
| `bubble Name { … }` in the state block | `intent Name { … }` |
| `response Name { LoadRows(…) }` | `receive Name { LoadRowsOk(…), LoadRowsError(String), LoadRowsUnhandled(…) }` |
| `response name(res, err) { … }` | two or three `receive` arms |
| `@on.click="save"` | unchanged in text; a message at run time |
| `@on.input="setQuery value"` | `@on.input="setQuery e.value"` — every accessor gains `e.` |
| `Input(name, args)` in MoonBit | `Receive(name, args)` |
| `Receive(name, args)` | unchanged |
| `Bubble(name, args)` | `Intent(name, args)` |
| `Response(name, [res, err])` | `Receive(nameOk, [res])` and `Receive(nameError, [err])` |
| `RequestFn` | `IntentFn`, which may also `Pass` |
| `respond(Ok(v))` / `respond(Err(e))` | `Ok(v)` / `Failed(e)` |
| `ctx.stop_propagation()` | unchanged |

Two of those rows touch views. The `e.` rewrite is deterministic — the accessor
table is closed and an argument slot accepts nothing else — so a tool does all
522 call sites with no judgment, and reports every bare name that is not in the
table as it goes.

The mapping keeps the meaning of every v1 program, with one widening. A v1 view
name that nothing answers is a no-op in v1 and a no-op in v2. `bubble 'name'` in
a v1 handler becomes `intent dyn 'name'`, which walks the same chain. The one
behaviour that changes is the mutator fallback (section 2): a `ctx.send` naming a
generated mutator does nothing in v1 and mutates in v2. Audit `ctx.send` call
sites whose names collide with a generated mutator before migrating.

## 16. Costs and risks

**The mutator fallback widens.** In v1 only a DOM event falls through to `swap`
and the generated mutators. In v2 every message does. This removes an
inconsistency, and it also means a parent can mutate a child's field by name
without the child declaring anything. That is already the blessed shape in
`skill/tutuca/core.md`, but v1's narrower rule was an accidental guard, and
removing it is the one behaviour change a migration can trip over.

**Every view that passes an event argument changes.** 522 handlers in this
repository, plus the skill, the storybook, the cards and the playground
examples. It is one deterministic rewrite, and it breaks the promise this
document made in an earlier draft that view text would not change at all.

It is worth doing **now** rather than later, for one reason: v2 already rewrites
every handler declaration (`on` becomes `receive`), so the migration tool is
being written anyway. The `e.` rewrite is one more pass in it. A separate later
change would need the same tool built a second time, for a smaller payoff.

**A DOM property table has to be generated and pinned.** Section 7 needs one for
typing and for the lint, and `AGENTS.md` is explicit that a list like this is
never transcribed by hand. That is a new generator, a new pinned upstream commit
and a new drift check in `ci`, beside the three the repository already has.

**A reporting leaf gains a declaration.** In v1 a child that only bubbles writes
`on pick { bubble 'itemPicked' .label }`. In v2 it writes
`receive itemPicked(label) { forward dyn }`. The two are the same size, so
nothing is lost against v1. What is lost is the shorter design this document
considered and rejected, where a view name walked with no declaration at all. A
leaf that reports three names declares three forwarders. Section 18 asks whether
the language should shorten that.

**The default route walks further than v1.** An intent with no leg words walks
every ancestor before it reaches the lexical handler. Each hop is one queued
transaction (`transactor/transactor.mbt:501`). Measure a deep tree with a hot
intent. `intent lex` stays one lookup, as v1 is.

**A migrated program keeps the v1 shape and gains nothing.** The value comes from
the default route and from deleting local handlers, and the author must choose
both. Do not migrate to the default route by machine.

**The split answer is a breaking change.** Every v1 `response name(res, err)`
becomes two or three arms. The change is mechanical, and it is not small in a
large project.

**`Input` disappears from a public enum.** Every hand-written `update` match in
every consumer breaks at compile time. This is loud, which is correct, and it is
a lot of edits.

**The AOT backend must emit the leg words.** It already refuses some `sendAt`
places (`tutucard/wasm/examples/Addressing.html`). Each refusal falls back to
MoonBit, so no program breaks in silence.

**The guest contract changes.** The WIT needs a major version, and every guest
needs a rebuild.

**One word, two directions.** `intent` names the effect that dispatches and the
declaration that answers. v1 does the same with `bubble`, and it causes no
reported trouble.

## 17. Settled

- **Two channels, and one question separates them.** A message is sent to a
  known target. An intent is dispatched to a route. Everything else follows.
- **v1's `Input` and `Receive` were one thing.** They differ only in a fallback,
  and the fallback was about the origin rather than the message. v2 merges them
  and keeps the fallback for both.
- **A message does not propagate.** It reaches its target and stops. This costs
  one lookup, exactly as v1 does, and it means a migration cannot change
  behaviour in silence.
- **`forward` is the only bridge**, and it is where a view name picks its route.
  Escape is written, once, by the component that lets the name out.
- **A routed intent's `dyn` leg starts at the parent** of whoever dispatched it.
  One rule, so a component never re-enters its own handler.
- **A reply ends the walk. Running does not.** This is the one rule that holds
  every v1 behaviour.
- **`forward` keeps the answer target and the arguments.** Dispatching again
  would move both.
- **Three outcomes, three names, derived.** `Unhandled` falls back to `Error`, so
  a sender that does not care writes one arm.
- **An answer is a message.** It lands in `receive` with everything else, and a
  test can drive one with `send`.
- **Scope and expectation are independent.** The route says who answers. The
  declared answer arms say whether an answer is expected. v1 makes one choice
  carry both, and the corpus shows it.
- **An `@on` handler maps the DOM domain into the tutuca domain, and the
  argument list is the boundary.** Only a `Value` crosses. Every handler, every
  test and every guest past that line sees `Value` and never sees the DOM.
- **`e` is a namespace, not a value.** An event is a DOM object, so it is
  precisely the thing that must not cross. Naming the parts is what keeps a
  payload typed and a test free of mocks.
- **An `e.` path always produces a `Value`, and every step through a host object
  is allowlisted.** Allowlisting only the root does not hold: `target` is a
  permitted root and `e.target.ownerDocument.defaultView` walks out of the event
  entirely. The allowlist stops where host objects stop — `detail` and `dataset`
  are author data, and depth past them is free.
- **Capability is granted through a channel that knows its caller.** An event
  path has no caller to authorize, so it stays narrow. A component that needs
  privileged information dispatches an intent, and the host — holding
  `IntentCall.from` — decides. This is `dyncomp/DESIGN.md`'s fourth principle
  applied to the DOM.
- **No bare name in an argument.** Every argument is a prefixed read —
  `.field`, `@binding`, `e.path` — or a literal. The message name is the one
  unprefixed name, always first.
- **The vocabulary is for reading.** Message, intent, notification, request,
  view message, directed message: the compiler needs none of these words. It
  computes what they name.
- **`NO_VIEW_HANDLER` is a warning, not an error.** The default already makes
  ignoring it safe: the code behaves as v1 behaves.
- **`lex` walks, and its walk is resolution, not dispatch.** `Pass` has to mean
  the same thing on both legs — a handler that declines is not a handler — so a
  declining static handler hands the intent to its parent scope, and
  `lookup_request`'s three lines become `lookup_intent`'s loop
  (`component/scope.mbt:149`). What that loop costs is the real question, and
  the two legs answer it differently on purpose. A `dyn` hop is a component
  instance with state and effects, so it queues a transaction, exactly as v1's
  bubble does. A `lex` frame holds registered functions with no state, so the
  transactor calls one directly inside the transaction already running
  (`transactor/transactor.mbt:332`), which is what v1 already does for
  `request`; a `Pass` there costs a map miss and a call, not a queue step. The
  chain is short as well: a frame comes from `ComponentStack::enter()`, one per
  registered component (`component/scope.mbt:101`), so a `lex` leg is bounded by
  module nesting — two frames in every app in this repository — and not by tree
  depth.
- **An intent walks at most `INTENT_DEPTH` = 64 positions.** This is not a
  tuning knob, it is a cycle breaker, and 64 is chosen to be unreachable by
  anything legitimate: a route is bounded by tree depth plus scope depth, and
  the deepest thing in the corpus is nowhere near it. What it catches is a
  `forward` cycle between two components, which section 3's "the `dyn` leg
  starts at the parent" makes possible and which no single-component loop in v1
  could produce. It is a different number from `max_turns` (10000,
  `transactor/transactor.mbt:347`), which bounds the whole queue rather than one
  chain, and it does not replace it. On exhaustion the walk ends the way section
  6's route exhaustion ends — the sender's declared arm is consulted, so a
  sender that asked for an answer learns something instead of waiting forever —
  and the refusal channel reports `INTENT_DEPTH` for a host that has it on
  (`core/path_path.mbt:248`). Revisit the number after the measurements in the
  plan's task 23, not before.
- **The object steps are one curated list: global, flat, and consulted at every
  step.** Not one list per event interface. A per-interface list would multiply
  the one security decision in the release by the number of interfaces, and each
  entry would then need its own argument in a place nobody reads twice; the
  steps that can escalate — `target`, `currentTarget`, `relatedTarget`,
  `detail`, `dataset`, `dataTransfer` — are the same steps whichever interface
  carries them. The list lives in `eventpath/event_paths.mbt` beside a second,
  smaller set: the **author-data terminals**, `dataset` and `detail`, below
  which traversal is free because there is no host object left to escalate into.
  Two tables, two questions: this one says whether a step may be traversed and
  is argued, and the generated one says whether a property exists and what type
  it has and is fetched. Neither is allowed to answer the other's question.

## 18. Open questions

- **Should a message be answerable?** A parent that wants an answer from one
  known child cannot ask for one; it sends a message and waits for the child to
  send one back, which is v1's situation. `reply` needs a sender to answer, and a
  message has one. So the mechanism would work. It would also give two ways to
  ask a question, and the second would not search.
- **Should the schema declare that an intent is answerable?** Nothing can check
  that a notification's handler does not `reply` (section 1), because a handler
  cannot see its sender. A flag on the schema's `intent` variant would make it a
  build error. It would also put the notification/request split into a
  declaration, which section 1 argues it should not need.
- **Should a forwarder have a shorter spelling?** `receive itemPicked(label)
  { forward dyn }` is one line, and a reporting leaf writes one for each name it
  raises. A bodyless `receive itemPicked(label) forward dyn` could mean the same
  thing. It is sugar for a one-line body, and this design has argued against
  second spellings everywhere else. Count the forwarders in a migrated corpus
  before adding one.
- **Should `NO_VIEW_HANDLER` ever become an error?** With a forwarder available,
  every legitimate case can be written, including a name a handler in another
  module answers. So an error is expressible. It is also a build break on the
  first keystroke after adding an `@on` name, which is the flow v1 already has
  for a new handler. Decide it from the corpus, not from this document.
- **Should `stop` carry a reason?** Today it says "served, no answer". A sender
  that expects an answer learns nothing. `stop 'reason'` would tell it, and would
  add a second way to end a walk.
- **May a forwarder narrow a route that is already walking?** `forward dyn` on a
  message picks the route for the first time, which is settled. `forward lex` on
  an intent that is already on the `dyn` leg would cut the rest of that leg. That
  is either a useful diversion or a way to lose an answerer the sender expected.
- **Does a guest need `IntentCall.from`?** The host reads the path to authorize.
  A guest that reads it learns where it sits in the host's tree. That is more
  than a guest needs to know.
