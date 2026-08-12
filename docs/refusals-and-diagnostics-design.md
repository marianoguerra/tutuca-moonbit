# Refusals: making "nothing happened" observable

Every place the framework decides **not** to do something, reported as one kind
of data, through one channel, with a static counterpart that finds the same
situations before they run.

Companion to [`predicates-and-invariants-design.md`](predicates-and-invariants-design.md)
(which adds several new ways to refuse, and the `format` clause that gives a
refusal its sentence) and [`inline-handler-language-design.md`](inline-handler-language-design.md).
It is worth doing on its own: most of the cases below exist today.

## Context

tutuca is built on the idea that *nothing happened* is a legal outcome.
`Path::update` returns the **same** `root` object for an unresolvable path, a
missing handler, a handler that answered `None`, and a leaf that came back
physically unchanged. Every generated mutator answers `(inst.value)()` — the
instance it was given — when handed something it cannot use. The transactor reads
`physical_equal` as "nothing changed" and does not rebuild the spine.

That is a good design. It is why a click on a component that has no opinion about
the click costs nothing, why an async response arriving at a deleted row is safe,
and why a wrong-shaped argument cannot corrupt a state.

It is also why a mistake is invisible: **the success path and the failure path
produce byte-identical results.** A handler name misspelled by one letter, an
argument the schema cannot accept, a response nobody handles, a request whose
handler was never registered — each produces exactly what a correct no-op
produces. The framework already knows the difference at the moment it decides.
It simply does not say.

Three of these are documented as known holes, in the docs' own words:

- `@on.input="setCount event"` — "resolves to `Null` and the handler receives
  `[Null, ..]`. **Nothing reports it** — the dispatch lands and does nothing."
- `comp.make` — "every arg is coerced through its DECLARED kind (a wrong-shaped
  value falls back to the default — **silently**)."
- `as="edit"` naming a view the child lacks — falls back to `main`, which the
  commit log records as a behaviour that had to be *documented* because nothing
  reports it.

The predicates design multiplies them: a precondition that declines, an invariant
that refuses a successor, a constraint that rejects a value, and a response whose
error arm is missing are four new ways to produce a silent no-op. Adding those
without adding this would be a mistake.

## 1. Most of the channel already exists

`transactor/spec.mbt:152-163` defines `ObserveRecord`, and it is already the
right shape:

```moonbit
pub(all) struct ObserveRecord {
  kind : ObserveKind          // Receive | Input | Bubble | Response | Request
  name : String
  args : Array[@tutuca.Value]
  path : @tutuca.Path
  path_keys : Array[@tutuca.StepKey]
  target_path : @tutuca.DispatchPath
  matched : ObserveMatch      // Exact | NoHandler
  before : @tutuca.Value?
  after : @tutuca.Value?
  seq : Int
}
```

It is **already data** — `ObserveRecord::to_json` exists so "a devtool can show
it, or a host can post it across a boundary". It is **already free when nobody is
looking**: `Transactor::emit` returns early on `self.observers.is_empty()`, which
is what "makes a no-op update free". And `after` is *absent rather than null*
when the handler made no change, which the file itself calls "the distinction the
whole no-op path turns on".

So this design is not a new channel. It is three moves on an existing one:

1. **`matched` grows from two cases into a reason.** `NoHandler` is one refusal;
   there are a dozen and they are all more useful named.
2. **The emitting sites widen.** The transactor sees dispatches; it does not see a
   mutator rejecting an argument, `coerce` rejecting a field, the renderer falling
   back to `main`, or `comp.make` coercing to a default. Those live below and
   beside it and need somewhere to report to.
3. **A static counterpart.** Every refusal that is decidable before it runs gets a
   lint code with the same name, so "what could refuse" and "what did refuse" are
   one vocabulary.

## 2. The rule that decides whether this is useful

A channel that reports every declined step is noise, gets muted, and was not worth
building. The distinction that keeps it usable:

> **A refusal is only reported where the resolution chain ends.**

An `update` arm returning `None` has not refused anything — it has declined, and
dispatch precedence then offers the name to the generated mutator, which is the
documented and intended design (`Some(RemoveInItemsAt(_)) => None` appears eight
times in the corpus for exactly this reason). A bubble passing an ancestor that
does not handle it has not refused; bubbling *is* walking up until something does.

So one dispatch produces **at most one refusal**, emitted when everything that
could have claimed it has declined, and it carries the chain it walked
(`update → mutator → none`) rather than one record per step. The same rule
applies to bubbling: the record is emitted at the root, listing the components
that passed.

This is the whole difference between a channel a team keeps on and one they turn
off in the first week.

## 3. The taxonomy

Grouped by what the framework was unable to do. Each kind names both a runtime
record and — where it is statically decidable — a lint code (§7).

### A · Nothing claimed it

| kind | happens when | today |
|---|---|---|
| `NO_HANDLER` | an `Input`/`Receive`/`Bubble` name that no handler, no `swap` and no generated mutator answers | `ObserveMatch::NoHandler` |
| `NO_RESPONSE_HANDLER` | a response arrives with no arm for its name | `NoHandler` |
| `NO_ERROR_HANDLER` | a request failed and only the success arm exists | new — see the response split |
| `NO_REQUEST_FN` | `request 'x'` with nothing registered under `x` | silent |
| `NO_METHOD` | `$name` in a slot with no `compute` entry | silent → renders null |
| `NO_VIEW` | `as="edit"` on a component with no `edit` view | silent → falls back to `main` |
| `NO_SWAP_RESULT` | a `swap` handler answered `None` | silent |

### B · A rule refused it

| kind | happens when |
|---|---|
| `PRECONDITION` | a handler's `requires` was false, so it did not run |
| `POSTCONDITION` | a handler ran and broke its own `ensures` — a bug, not a condition |
| `INVARIANT` | the successor state broke a rule the schema declares |
| `CONSTRAINT` | a value was rejected for a field (`coerce` / a form / an agent's arguments) |

These four carry `rule` (the predicate's name) and `message` (its `format`, its
doc comment, or its name, in that order).

### C · The value did not fit

| kind | happens when | today |
|---|---|---|
| `ARG_SHAPE` | a handler or mutator got an argument of the wrong shape — including `setCount event` resolving to `Null` | silent |
| `COERCED_TO_DEFAULT` | `comp.make` fell back to a field's default | "silently" |
| `DECODE_FAILED` | `Fields::decode` answered `None` | silent |
| `OUT_OF_RANGE` | a narrowing to `s32`/`u8`/… would not fit | silent |
| `KEY_MISSING` | an index or map key was not there | silent |

### D · The position did not resolve

| kind | happens when | today |
|---|---|---|
| `PATH_UNRESOLVED` | a pinned response target was deleted before the response landed | documented as "a safe no-op" |
| `TELEPORT_MISSING` | a `Dyn` marker's producer is gone |

### E · Nothing changed

| kind | happens when |
|---|---|
| `NO_CHANGE` | a handler ran, returned, and the leaf is physically equal |

`NO_CHANGE` is the ambiguous one and should default to off. Idempotent handlers
are correct and common; but "the handler ran and did nothing" is also what a
mistyped field name looks like in a MoonBit arm, so it is worth being able to
turn on.

### Not absorbed here

The sanitizer's dropped elements and attributes, and a bundle's load-time
complaints, already have `Bundle::diagnostics()` and a filter that makes "what
was dropped reachable without its type". Those are content decisions rather than
refused actions, they already have a home, and merging them would make one
channel answer two questions. Worth converging on a shared record *shape* — not
a shared stream.

## 4. The record

```moonbit
pub(all) struct Refusal {
  kind : RefusalKind
  /// What was asked for. `channel` is absent for refusals that are not a
  /// dispatch at all — a constraint checked by a form, a coercion in `make`.
  channel : ObserveKind?
  name : String
  args : Array[@tutuca.Value]
  /// Where. `path_keys` renders as `todos.items[1].title`, the label the
  /// observer records already use.
  path : @tutuca.Path
  path_keys : Array[@tutuca.StepKey]
  component : String
  /// Why, in the words of whoever refused: a predicate name, a field name, a
  /// view name.
  rule : String?
  message : String
  cause : String?
  /// What the caller could not otherwise see. `rejected` is the successor
  /// state an invariant or a postcondition refused — the single most useful
  /// field here, and one nothing can reach today.
  before : @tutuca.Value?
  rejected : @tutuca.Value?
  /// The resolution chain that ended in nothing: ["update", "mutator"].
  tried : Array[String]
  seq : Int
}
```

With `to_json` for a host boundary and `to_value` for a component, because the
natural place to *show* refusals is a tutuca component fed a `List` of `Map`s —
the dev overlay, the inspector's error pane, and a dyncomp storybook panel are
then the same thing built three ways. That self-hosting is worth the one rule it
demands: **delivery suppresses further refusals**, or a broken sink reports its
own brokenness forever.

## 5. Where the sink lives

Layering decides this. `transactor` imports `core`; `core` cannot import
`transactor`; and `component`, `render` and `dyncomp/jsonschema` all need to
report. So the type and the hook belong in `core`, beside `warn.mbt` — which is
the exact precedent, down to being redirectable:

```moonbit
/// Where refusals go. Defaults to a no-op: a refusal costs nothing until
/// someone is listening, matching `Transactor::emit`'s empty-observers guard.
pub let refusal_hook : Ref[(Refusal) -> Unit] = Ref(_ => ())
```

`warn` does not go away and is not replaced — it stays the untyped runtime
warning. A default sink that formats a `Refusal` through `warn` is one line, and
is what a host gets by opting in rather than by default.

The transactor keeps its observers and gains the refusal as a field on the
record, so a devtool subscribing to dispatches sees refusals in the same stream
and in order. A consumer that only wants refusals subscribes to the hook.

**Cost control**, because two of these sites are hot: an `@when` predicate runs
per item per render, and a mutator argument check runs per dispatch. Three
mitigations, in order: the hook defaults to a no-op so nothing is built; the
record is constructed lazily behind that check; and the collector dedupes by
`(kind, component, name, rule)` with a count, because the interesting fact is
"this happened", not "this happened 4,000 times".

## 6. Three modes, and the one that pays for itself

**Silent** — the default, the hook unset, nothing built. Production.

**Collect** — a host installs a collector, and refusals accumulate as data for an
overlay, a console group, or a posted message. Development.

**Strict** — the sink raises. This is the one worth building the rest for:
`@harness.mount` installs it, so **a refusal during a test fails the test**.

```moonbit
test "publishing needs a title" {
  let h = @harness.mount(post_module(), "Post")
  h.click(".publish")          // PRECONDITION: publishedNeedsTitle → test fails
}
```

Today that test passes. It asserts nothing, the click does nothing, and nothing
distinguishes "the button is guarded" from "the selector was wrong". Under strict
mode the second is a failure with a name, a path and a sentence. Every existing
test in the repo gains that for free, which is the cheapest coverage this design
can buy — and it is also the reason to expect the first run to be noisy, since
several tests will be relying on a fallback nobody had noticed.

Strict mode needs an opt-out per test for the cases where a refusal is the thing
being asserted (`h.expect_refusal(NO_HANDLER, …)` is the better spelling — it
turns a suppression into an assertion).

## 7. The static half

Everything above reports what happened. Most of it is decidable before anything
runs, because `gen-views` already knows every `@on` name, every message the schema
declares, every `$name` a view references, every `as=` view name, and — with the
predicates design — every rule and every contract.

**One lint code per decidable kind, sharing its name.** That is the whole idea:
`NO_ERROR_HANDLER` is a hint at build time when the arm is missing and a record at
runtime when the failure lands. An author who has read one has read the other.

| lint | reports |
|---|---|
| `NO_HANDLER` | an `@on` name with no arm, no mutator and no `swap` |
| `NO_RESPONSE_HANDLER` | a `variant response` case no arm answers |
| `NO_ERROR_HANDLER` | a `result`-typed response with an ok arm and no error arm |
| `NO_METHOD` | a `$name` no `compute` answers |
| `NO_VIEW` | an `as=` naming a view the target lacks — today an advisory hint, already half-built |
| `NO_RECEIVE_HANDLER` | a declared `receive`/`bubble` case nothing answers |
| `UNPROJECTABLE_INVARIANT` | a rule enforced at runtime that no JSON Schema can carry |
| `NO_FORMAT` | a rule that can refuse a user action with no `format` and no doc comment |

The last two are the ones that would not exist without the predicates design, and
`NO_FORMAT` is the one most likely to be quietly valuable: a rule that refuses a
click and cannot say why is a bug report waiting to happen.

### Strictness is declared, not flagged

Most of these are **hints**, because relying on a default is legal and often
right: falling through to a generated mutator is the documented way to get a
setter, and `as=` falling back to `main` is a feature.

So strictness is opt-in **per component**, in the state block, rather than a
global flag — which also fits a linter that deliberately has "no
`tutuca-lint-ignore` pragma and no per-line suppression" — with one exception:
**a dyncomp has it on by default** (§9), because a bundle authored by a model and
loaded at runtime is where a silent fallback costs the most and where nobody is
reading hints.

```html
interface post {
  record state { … }
} #[exhaustive]
```

`#[exhaustive]` promotes every hint above to an error for that component: every
declared message has an arm, every response has both arms, every `$name` has a
`compute`, every rule that can refuse has a `format`. A component that matters
turns it on; a sketch does not; and the decision is in the file rather than in a
build script.

## 8. Costs and risks

**The first run will be loud.** Turning strict mode on across the existing test
suite will find real fallbacks that nobody minded. That is the design working, and
it is also a migration: the honest plan is to land the channel silent, run it in
collect mode over the corpus, read what comes out, and only then decide which
kinds default to which mode.

**A dozen kinds is a vocabulary to learn.** The mitigation is that the lint and
the record share names, so it is one vocabulary learned twice rather than two. If
that stops being true — if a runtime kind has no static counterpart and no
obvious name — it is a sign the kind is too fine.

**`NO_CHANGE` is a trap.** Idempotent handlers are correct, so a channel that
reports them by default trains people to ignore it. Off by default, and never
promoted by `#[exhaustive]`.

**Refusals can describe state.** `rejected` carries the successor an invariant
turned down, and `before`/`args` carry values. A refusal stream is therefore as
sensitive as the state it describes, and a host that posts it across a boundary
is exporting state. That needs saying in the security notes, not discovering
later.

**The channel must not become an error-handling mechanism.** A refusal is an
observation; it is not a `Result` and handlers cannot catch it. The moment a
component tries to *recover* from one, the framework has grown exceptions
sideways. The line to hold: refusals go to a sink, never back to the handler that
caused one.

## 9. Settled

- **Delivery is the `core` hook plus the observer stream** (§5), and nothing
  else. Refusals do not route into the component tree: a dev overlay reads the
  hook as host code. `send_at_root` would have made the overlay an ordinary
  component with a `receive` arm — elegant, and it puts diagnostics inside the
  transaction queue they report on, which is exactly where a re-entrancy bug would
  be hardest to see. Not worth it for a pane.
- **`#[exhaustive]` is on by default for a dyncomp**, and opt-in for a compiled
  component. A bundle authored by a model and loaded at runtime is the case where
  a silent fallback is least acceptable and where nobody will read a hint. A guest
  that would fall back therefore fails to load, with the missing arm named — which
  means the failure lands on whoever can still fix it rather than on whoever
  happens to click the button.
- **Modes are per kind, not global.** `PRECONDITION` is worth failing a test;
  `COERCED_TO_DEFAULT` is not, and `NO_CHANGE` is off everywhere. The table is one
  more thing to configure and the alternative is a channel tuned to its noisiest
  member.
- **A bubble reports only when nothing on its path handled it**, and then at hint
  level. Passing an ancestor that has no opinion is what bubbling *is*.

## 10. Open questions

- **What does the host do with a guest's refusals?** A dyncomp guest refusing
  inside its own wasm has no `refusal_hook`. Either the ABI grows a channel back —
  a contract change — or the host enforces only the rules it can read from the
  manifest and the guest's own stay invisible. Making `#[exhaustive]` the default
  for guests raises the stakes on this rather than settling it: more rules are
  declared, and the ones the host cannot see are the ones that will surprise.
- **Does `#[exhaustive]` on a guest apply at pack time or at load time?** Failing
  at pack time puts the error in front of the author; failing at load puts it in
  front of a host that cannot fix it. Both, with different codes, is probably the
  answer.
- **How much of a refusal is safe to post across a boundary?** §8 notes that
  `rejected` and `args` carry state. A host that ships refusals to a server is
  exporting state, and the redaction rule should be written before somebody builds
  that rather than after.
