# Implementing tutuca v2

The work to take [`totuka-v2.md`](totuka-v2.md) from a design to a release, in
the order it has to happen, with what each step touches and how to know it
worked.

Read the design first. This document does not restate it; it says who changes.

## Where the work actually is

Counted in this repository, before anything moves:

| Surface | Count | Migration |
| --- | --- | --- |
| `<script type="tutuca/script">` declarations (`on` / `receive` / `response`) | 135 | trivial — `on` becomes `receive` |
| MoonBit `update` arms (`Input` / `Receive` / `Bubble` / `Response`) | 393 | **the bulk of the hand work** |
| `@on` handlers passing an event accessor | 522 | mechanical — add `e.` |
| `@on` handlers in total | 1504 | most need nothing |
| Guest bundles | 11 | regenerate + rebuild |
| Skill files | 35 | prose, machine-checked by `check-skill` |
| Storybook / site / card examples | 59 | migrate with the codemod, then read |

The block language is the smallest surface and the loudest change. The MoonBit
`update` matches are the largest. Plan the schedule around the second number,
not the first.

## Tasks

**Phase 0 — decide**

- [x] 1. [Close the blocking open questions](#1-close-the-blocking-open-questions)
- [x] 2. [Write the conformance corpus first](#2-write-the-conformance-corpus-first)

**Phase 1 — the runtime**

- [ ] 3. [`core`: buckets, `Ctx`, `IntentOpts`](#3-core-buckets-ctx-intentopts)
- [ ] 4. [`transactor`: the walk, `reply` / `fail` / `forward`](#4-transactor-the-walk-reply--fail--forward)
- [ ] 5. [`component`: `Dispatch`, `obj_handler`, `IntentFn`](#5-component-dispatch-obj_handler-intentfn)
- [ ] 6. [`app`: wire the lexical scope and the DOM entry](#6-app-wire-the-lexical-scope-and-the-dom-entry)

**Phase 2 — the language**

- [ ] 7. [`tscript`: kinds, effects, leg words](#7-tscript-kinds-effects-leg-words)
- [ ] 8. [`tscript/check`: the new findings](#8-tscriptcheck-the-new-findings)
- [ ] 9. [`statedef` / `viewfile`: two message variants](#9-statedef--viewfile-two-message-variants)
- [ ] 10. [`tscript/emit_mbt`: the AOT backend](#10-tscriptemit_mbt-the-aot-backend)
- [ ] 11. [`tutucard/wasm`: the card backend](#11-tutucardwasm-the-card-backend)
- [ ] 12. [`viewgen`: merge four enums into two](#12-viewgen-merge-four-enums-into-two)

**Phase 3 — the DOM boundary**

- [ ] 13. [Generate the DOM property table](#13-generate-the-dom-property-table)
- [ ] 14. [Curate the object-step allowlist](#14-curate-the-object-step-allowlist)
- [ ] 15. [`e.` resolution in the glue and the slot parser](#15-e-resolution-in-the-glue-and-the-slot-parser)

**Phase 4 — dynamic components**

- [ ] 16. [WIT 0.8.0 and the host bridge](#16-wit-080-and-the-host-bridge)
- [ ] 17. [Regenerate and rebuild every guest](#17-regenerate-and-rebuild-every-guest)

**Phase 5 — migration**

- [ ] 18. [Build `tutuca migrate`](#18-build-tutuca-migrate)
- [ ] 19. [Migrate the repository's own code](#19-migrate-the-repositorys-own-code)

**Phase 6 — words**

- [ ] 20. [The skill](#20-the-skill)
- [ ] 21. [`docs/`, `README`, `AGENTS.md`](#21-docs-readme-agentsmd)
- [ ] 22. [The landing site and the playground](#22-the-landing-site-and-the-playground)

**Phase 7 — prove it**

- [ ] 23. [Measure the walk](#23-measure-the-walk)
- [ ] 24. [Release and the consumer examples](#24-release-and-the-consumer-examples)

---

## 1. Close the blocking open questions

Section 18 of the design lists nine open questions. Three block code and must be
answered before task 3. The rest can be answered later.

**Blocking.**

- **Does `lex` walk or resolve once?** `IntentAnswer::Pass` means a declining
  handler hands the intent to its parent scope, which turns
  `ComponentStack::lookup_request` from a lookup into a loop. Task 5 cannot be
  written without the answer.
- **What is the intent depth limit?** Task 4 needs a number for `INTENT_DEPTH`.
  Pick one, write it as a named constant, and revisit after task 23.
- **Which object steps are allowed?** Task 14 is the whole of it, but tasks 13
  and 15 are shaped by the answer, so decide the *shape* here: a curated list, a
  generated one, or a list per event interface.

**Not blocking.** Answerable messages, a schema answerability flag, a shorter
forwarder spelling, whether `NO_VIEW_HANDLER` becomes an error, `stop` with a
reason, narrowing a route mid-walk, and whether a guest sees `IntentCall.from`.
Each is additive. Do not hold the release for any of them.

**Risk.** Answering the `lex` question with "it walks" makes every declining
static handler a queue step. If the corpus has deep scope chains, this is the
one performance surprise in the design.

**Validation.** Each answer lands as a paragraph in `totuka-v2.md`, moved out of
section 18 and into section 17. An open question that stays open is a decision
nobody made.

**Done.** The three answers are the last three bullets of `totuka-v2.md`
section 17, and the three questions are gone from section 18, which is down to
six.

- **`lex` walks, and the walk is resolution rather than dispatch.** `Pass` means
  the same thing on both legs, so a declining static handler hands the intent to
  its parent scope and `lookup_request`'s three lines become a loop. The risk
  paragraph above asked what that costs, and the two legs answer differently on
  purpose: a `dyn` hop is a component instance with state and effects, so it
  queues a transaction as v1's bubble does; a `lex` frame holds registered
  functions with no state, so the transactor calls one inside the transaction
  already running (`transactor/transactor.mbt:332`, which is what v1 already
  does for `request`) and a `Pass` costs a map miss and a call. The chain is
  short too — a frame is one `ComponentStack::enter()` per registered component
  (`component/scope.mbt:101`), so it is bounded by module nesting, two frames in
  every app here, not by tree depth. **This defuses the risk above**: a
  declining static handler is not a queue step.
- **`INTENT_DEPTH` is 64**, a cycle breaker rather than a tuning knob, chosen to
  be unreachable by a legitimate route (tree depth plus scope depth). It is a
  different number from `max_turns` (10000, `transactor/transactor.mbt:347`),
  which bounds the whole queue and stays. Exhaustion ends the walk through
  section 6's route-exhaustion path, so a sender that declared an answer arm
  learns something rather than waiting, and reports `INTENT_DEPTH` on the
  refusal channel. Task 4 writes it as a named constant; task 23 revisits the
  number.
- **The object-step allowlist is one curated list: global, flat, checked at
  every step** — not one per event interface, which would multiply the release's
  single security decision by the number of interfaces for steps (`target`,
  `currentTarget`, `relatedTarget`, `detail`, `dataset`, `dataTransfer`) that
  are the same steps whichever interface carries them. It lives in
  `render/event_paths.mbt` (task 14) beside a second, smaller set — the
  author-data terminals `dataset` and `detail`, below which traversal is free.
  The generated per-interface table (task 13) answers the other question, does
  this property exist and what type is it, and neither table may answer the
  other's.

## 2. Write the conformance corpus first

`tscript/conformance/corpus.mbt` is the normative semantics as data: schema,
script, before-state, dispatch, after-state, effects. Both backends are held to
it. Write the v2 cases **before** writing either backend, so the two cannot
drift into agreeing with each other and not with the design.

Cases to add, at minimum: a message answered at home; a message no arm answers;
`forward` with no legs, with `dyn`, with `lex`, with amended arguments; an intent
answered on `dyn`; an intent answered on `lex`; an observer above a replier; a
`requires` refusing mid-walk and the walk continuing; `reply` twice; route
exhaustion with `<name>Unhandled` declared; route exhaustion with only
`<name>Error` declared; route exhaustion with neither; `stop` before any reply.

**Key files.** `tscript/conformance/corpus.mbt`,
`tscript/conformance/mbt/corpus.html` (generated), `dev/tasks.mbt`
(`gen-conformance`).

**Risk.** The corpus is projected into `corpus.html` and compiled, so a case the
MoonBit backend cannot express fails generation rather than reporting a
difference. Add cases in small batches and run `gen-conformance` after each.

**Validation.** `just dev gen-conformance`, then `just test`. Every new case
fails at this point — that is correct, and the failures are the specification of
tasks 10 and 11.

**Done.** 24 v2 cases in `cases_v2()` at the foot of
`tscript/conformance/corpus.mbt`, with `V2Case` and `V2Bucket` (`VReceive`,
`VIntent`) beside them. A second type rather than a widened `Case`, so the two
vocabularies cannot be mixed in one list while both exist.

`CaseEffect` gains **`route : String`**, written RESOLVED — a bare
`intent 'save'` records `dyn lex` — because the default route is exactly what
two backends can agree to disagree about while every explicit-route case passes.
`printed()` puts it between the verb and the name (`intent dyn lex saveDraft …`),
`effect()` takes it as an optional, and `cmd/card-corpus`'s `effect_json` carries
it for task 11.

**Nothing consumes `cases_v2()` yet, and that is the point.** The projection
cannot emit a v2 body until the parser accepts one (task 7), so running it now
would fail generation rather than report a difference — the risk above. So the
cases were written first, and the batch is held in place by
`tscript/conformance/corpus_test.mbt`: the roster by name, the effect
vocabulary and route tally, and the printed form of a routed effect. `cases()`
and its drivers are untouched; tasks 10 and 11 switch over and delete the v1
list.

**What went to task 4 instead.** A case is one transition, so a row can say
what a body EMITS and not where it goes. Four of the listed cases are walk
behaviour and have no single-transition form: an observer above a replier;
a `requires` refusing and the walk CONTINUING; `reply` twice across two hops
(the one-shot is per intent across hops, not per body); and route exhaustion in
its three shapes. They are listed in a comment above `cases_v2()` so the gap
between the two files does not swallow them. Each has a corpus half that IS
here — `a handler that does not reply is an observer`, `a requires that does
not hold takes the reply with it`, `a body may queue two replies`.

## 3. `core`: buckets, `Ctx`, `IntentOpts`

The type layer, and nothing that uses it yet.

`HandlerBucket` goes from four cases to two: `Receive`, `Intent`
(`core/path_spec.mbt:25`). `RequestOpts` becomes `IntentOpts` with `route :
Array[Leg]` and `on_unhandled_name`, keeping `on_ok_name`, `on_error_name` and
`live_path` (`core/path_spec.mbt:33`). `Ctx` gains `intent`, `forward`, `reply`
and `fail`, and loses `bubble` and `request` (`core/path_spec.mbt:56`).

`DispatchPath` and `Step` do not change. `pin_keys` does not change. This is the
part of v1 the design keeps whole.

**Key files.** `core/path_spec.mbt`, `core/path_path.mbt`, `core/spec.mbt`,
`core/path_changes.mbt` (the `ctx.at()` builder gains `.intent(...)`).

**Risk.** `Ctx` has default method implementations so a test can run a handler
with no dispatcher. Keep that property; a `reply` with no transactor must be a
no-op, not a crash.

**Validation.** `moon check` on all three targets. `moon info` and read the
`.mbti` diff — this task is entirely an interface change, so the diff **is** the
deliverable.

## 4. `transactor`: the walk, `reply` / `fail` / `forward`

The heart of it.

`push_bubble` and `push_request` become one `push_intent` that owns the route.
`Transaction.bubbles : Bool` becomes the remaining route — a leg list plus a
position — so `after_transaction` (`transactor/transactor.mbt:501`) advances
along it instead of asking one boolean. `push_request`'s pinning, its
`responded` one-shot `Ref` and its completion transfer
(`transactor/transactor.mbt:232`) all survive; what changes is that they now
apply to a walk that may visit many handlers before one answers.

New: `reply` and `fail` set the answer and end the walk. `forward` re-queues the
same intent at the next position with the answer target unchanged. Route
exhaustion consults the sender's declared arms and sends `<name>Unhandled`,
`<name>Error`, or nothing.

`ObserveRecord` (`transactor/observe.mbt`) needs a kind for an intent hop and
one for an answer, so the inspector and any persistence hook still see every
transaction.

**Key files.** `transactor/transactor.mbt`, `transactor/spec.mbt`,
`transactor/observe.mbt`, `transactor/bubble_test.mbt`,
`transactor/request_test.mbt`.

**Risks.**

- **Completion.** v1 transfers the parent's tracking unit onto the response
  subtree so a parent stays open until the whole chain settles. A walk has many
  hops and at most one answer. Decide what holds the unit while the walk runs,
  or a test that waits for settlement hangs.
- **`SECOND_REPLY`.** The one-shot `Ref` is per request in v1. In v2 it must be
  per intent across hops.
- **Depth.** A cycle now needs two components, which is easier to write by
  accident than v1's single-component loop.

**Validation.** The two existing test files, rewritten for the new shape, plus
the corpus from task 2 once task 10 lands. Add a test that a walk of N hops
produces N queued transactions and one answer.

## 5. `component`: `Dispatch`, `obj_handler`, `IntentFn`

`Dispatch` goes to two cases (`component/spec.mbt:172`). `obj_handler`
(`component/instance.mbt:391`) drops the `bucket is Input` conditions: `swap`
and the generated mutators now answer **any** message, which is the widening the
design's section 2 describes. `RequestFn` becomes `IntentFn` taking an
`IntentCall` — carrying `name`, `args` and `from` — and answering
`Ok` / `Failed` / `Pass` (`component/spec.mbt:234`).

`ComponentStack::lookup_request` becomes `lookup_intent`
(`component/scope.mbt:149`), shaped by task 1's answer. `ModuleDef.requests`
becomes `ModuleDef.intents` (`component/module.mbt:17`).

**Key files.** `component/spec.mbt`, `component/instance.mbt`,
`component/scope.mbt`, `component/module.mbt`, `component/component.mbt`.

**Risk.** The mutator widening is the one behaviour change a migration can trip
over. A v1 `ctx.send` whose name collides with a generated mutator does nothing
today and mutates after this task. Task 18 must be able to report those call
sites before task 19 runs.

**Validation.** `component/component_test.mbt`. Add a test that
`sendAt &.child 'setValue' 'x'` mutates, and a test that a `Pass` from a static
handler continues the walk.

## 6. `app`: wire the lexical scope and the DOM entry

`ScopeRequests` becomes `ScopeIntents` and adapts `IntentFn`
(`app/app.mbt:13-18`). `push_input` at `app/app.mbt:110` becomes a message push:
the DOM event now sends a message rather than dispatching an `Input`.
`App::send_at_root` (`app/loop.mbt:158`) needs no change in shape and a change
in name only if the team wants one.

**Key files.** `app/app.mbt`, `app/loop.mbt`, `app/browser/`, `app/wasm/`.

**Risk.** `render/events.mbt` builds the dispatch path by walking the DOM and
reading breadcrumbs, and it stops early when the leaf component has no handler
for the event (`stop_on_no_event`). That early exit is what keeps an unanswered
name cheap, and section 7 of the design promises it survives. Do not lose it.

**Validation.** `moon test --target js` (the happy-dom suite is the only thing
that drives real DOM events) and the `@harness` suite.

## 7. `tscript`: kinds, effects, leg words

`DeclKind` goes from nine to seven: `DOn` and `DReceive` merge, `DBubble`
becomes `DIntent`, `DResponse` goes (`tscript/script_spec.mbt`). `kind_word` and
`kind_of_word` follow (`tscript/script_parse.mbt:172`).

`effect_min_arity` (`tscript/script_parse.mbt:158`) loses `bubble` and
`request`, and gains `intent` (1), `forward` (0), `reply` (1) and `fail` (1).
`intent` and `forward` both accept leg words before their arguments, which is
the one new parse rule: read `dyn` / `lex` while the next token is one of them,
then parse normally.

`script_print.mbt` must round-trip all of it — the grammar is pinned by
parse-print-parse, so the printer is not optional.

**Key files.** `tscript/script_spec.mbt`, `tscript/script_parse.mbt`,
`tscript/script_lex.mbt`, `tscript/script_print.mbt`, `tscript/script_test.mbt`.

**Risk.** `dyn` and `lex` are now contextual keywords. A `pred dyn { … }` or a
parameter named `lex` must still work. The lexer emits them as `TIdent`, so the
context is the parser's job and the test suite must cover the collision.

**Validation.** `tscript/script_test.mbt` round-trips every declaration kind and
every effect. Add the collision cases.

## 8. `tscript/check`: the new findings

The checker holds the view surface and the block declarations together
(`tscript/check/check.mbt`), which is why the new findings live here.

- **`NO_VIEW_HANDLER`** — a view name the block neither answers nor forwards. A
  warning (design section 7).
- **`NOT_A_HANDLER`** — `reply` or `fail` outside an `intent` body, or `forward`
  outside a `receive` or `intent` body.
- **`BAD_EVENT_PATH`** — an `e.` path with a step off the allowlist. An error.
- **`UNKNOWN_EVENT_PROP`** — a rooted `e.` path naming a property the DOM
  specification does not have. A warning, naming the closest match.
- **`BARE_ARG`** — a bare name in an `@on` argument slot. An error naming the
  three prefixes.

`NO_SUCH_MESSAGE` keeps its job and now checks two variants instead of three.

**Key files.** `tscript/check/spec.mbt`, `tscript/check/check.mbt`,
`tscript/check/check_test.mbt`.

**Risk.** `NO_VIEW_HANDLER` fires for every reporting leaf in the corpus at
once. Land it silent, run it, read the list, and only then turn it on — the
order `docs/` uses for every diagnostic that touches existing code.

**Validation.** `check_test.mbt` with one case for each finding, asserting the
exact message. The messages are the user interface of this task.

## 9. `statedef` / `viewfile`: two message variants

The state block's six keywords become five: `state`, `struct`, `enum`,
`receive`, `intent`. `bubble` and `response` go.

**Key files.** `statedef/`, `viewfile/split.mbt`, `viewfile/errors.mbt`.

**Risk.** The parser shares its name table with `new <Type>` in the block
language, so a type called `Intent` would now collide with a keyword. Check the
reserved-name list.

**Validation.** `statedef`'s own tests, plus `gen-views` over the repository's
`.html` files in task 19.

## 10. `tscript/emit_mbt`: the AOT backend

The kind-to-bucket map at `tscript/emit_mbt/emit.mbt:145` goes from four entries
to two. The effect emitter at `:1240` gains `intent` (with a route), `forward`,
`reply` and `fail`, and loses `bubble` and `request`.

The effect queue stays exactly as it is: effects are collected and flushed only
if the body completes, which is what makes a failed `requires` drop them.

**Key files.** `tscript/emit_mbt/emit.mbt`, `tscript/emit_mbt/spec.mbt`.

**Risk.** The backend refuses what it cannot compile and falls back to MoonBit,
printing `<Comp>: <name> stays in MoonBit — <why> (script-refusal)`. Keep that
door: a `forward` inside an `if` may hit the same branch-scope limit `new`
already does.

**Validation.** The corpus from task 2, through `gen-conformance` and
`moon test`.

## 11. `tutucard/wasm`: the card backend

The second backend, held to the same corpus. `dispatch.mbt` routes by bucket,
`stmt.mbt` compiles the effects, `manifest.mbt` declares what a card answers.

**Key files.** `tutucard/wasm/dispatch.mbt`, `stmt.mbt`, `expr.mbt`,
`compile.mbt`, `manifest.mbt`, `tutucard/wasm/examples/*.html` (7).

**Risk.** Cards are compiled in the browser with no MoonBit compiler, so a card
that runs is not proof the same block compiles ahead of time — and the reverse.
Only the corpus proves both.

**Validation.** `just dev tutucard-playground`, which checks and compiles every
starter card and every `playground/site/cards/*.html` through the real entry
points.

## 12. `viewgen`: merge four enums into two

v1 emits `<T>Msg` from the view names (`viewgen/emit.mbt:435`) and `<T>Receive`,
`<T>Bubble`, `<T>Response` from the schema (`viewgen/emit_msgs.mbt:17`). v2
emits `<T>Receive` — the view names **merged with** the schema's `receive`
variant — and `<T>Intent`.

The merge is where the new build error comes from: when a name is in both, the
schema declares the payload types and the generator checks the view's inferred
shape against them. v1 cannot report this because the two names live in two
enums.

The raiser methods follow: `<T>Intent::dispatch(ctx)` replaces
`<T>Bubble::bubble(ctx)`, and `<T>Receive::send(ctx)` stays.

**Key files.** `viewgen/emit.mbt`, `viewgen/emit_msgs.mbt`,
`viewgen/emit_test.mbt`.

**Risk.** The payload-type inference reads the host element's static `type`
attribute for `value`. That logic moves to `e.value` unchanged; do not
reimplement it.

**Validation.** `viewgen/emit_test.mbt` snapshots, then `just dev gen-views` and
a drift check across the repository.

## 13. Generate the DOM property table

A new generator and a new pinned upstream, following
`anode/sanitize/spec_default_gen.mbt` exactly: fetch a machine-readable DOM
specification at a pinned commit, emit a MoonBit table, `moon fmt`, then
`git diff --exit-code`.

The table answers two questions: does this event interface have this property,
and what is its type. It is the type oracle for layer 1 and the lint source for
layer 2.

**Key files.** New `scripts/fetch-dom-props.mjs`, new
`render/dom_props_gen.mbt`, `dev/tasks.mbt` (a `dom-props` task), `AGENTS.md`
(the task table and the generated-file rules).

**Risks.**

- **Never hand-transcribe this.** `AGENTS.md` says why: the first hand-read
  sanitizer list dropped SVG's `script` and opened a hole.
- The task needs network, so it cannot run in `ci`. Drift-check the checked-in
  file instead, the way `sanitizer-defaults` does.

**Validation.** Run the task twice and diff — a generator that is not
reproducible is not checked in. Then a test that `value` on
`HTMLInputElement` types as it does today.

## 14. Curate the object-step allowlist

The small list that is **argued, not fetched**: which object-valued steps an
`e.` path may traverse. The design proposes `target`, `currentTarget`, `detail`,
`dataset`, `dataTransfer`, `relatedTarget`, and free depth once a step reaches
author data.

This is the one security decision in the release. It is also the only list in
the repository that cannot be generated, which makes it the only one that can
grow by accident.

**Key files.** A new `render/event_paths.mbt`, and a section in
`dyncomp/SECURITY.md` with the file-and-line evidence that convention requires.

**Risks.**

- **A permitted root is not a permitted path.**
  `e.target.ownerDocument.defaultView.localStorage.length` is a number, so it
  converts cleanly and reads the window. Every step is checked, or the list does
  nothing.
- A step added later without the security argument is the whole hole. Write the
  test that fails when the list changes.

**Validation.** A test that asserts the exact list, so growing it is a
deliberate edit to an assertion. A second test walking known escape paths and
asserting each is refused. Add both to `dyncomp/SECURITY.md`'s "What to check
when changing this".

## 15. `e.` resolution in the glue and the slot parser

Two halves.

**The slot parser** (`tscript/lex.mbt`, `tscript/parse.mbt`) accepts `e.<path>`
in an `@on` argument slot, and refuses a bare name there. The accessor table
stops being a permission list and becomes a type oracle.

**The glue** resolves it. Layer 1 is the existing computed accessors —
`render/dom_event.mbt:63` and around it, where `value` already means the checked
state on a checkbox, the file metadata on a file input and the `detail` on a
`CustomEvent`. Layer 2 is the allowlisted path walk, converting only the leaf.
Both the js and the wasm-gc glue need it (`app/browser/`, `app/wasm/`).

**Key files.** `tscript/lex.mbt`, `tscript/parse.mbt`, `render/dom_event.mbt`,
`render/events.mbt`, `app/browser/`, `app/wasm/`, `app/drag.mbt`.

**Risk.** A DOM `Event` has no `value` property. If layer 2 is consulted first,
all 315 `e.value` call sites read `Null` and every form in the repository stops
working. Layer 1 shadows layer 2 — assert it in a test, not in a comment.

**Validation.** `moon test --target js` for the real DOM path. A test for each
accessor, a test for `e.detail.unicode`, a test that `e.target` alone is `Null`,
and the refusal tests from task 14.

## 16. WIT 0.8.0 and the host bridge

`dyncomp/wit/tutuca-component.wit` is the one WIT in the repository. In the
`control` interface: `emit` and `bubble-at` become `intent` and `intent-at` with
a route, `request` folds into `intent`, and `reply`, `fail` and `forward` are
new. `request-opts` becomes `intent-opts`. A component's manifest declares
`receives` and `intents`, and drops `bubbles`, `responses` and `requests`.

`ControlMsg` (`dyncomp/host/guest.mbt:14`) and the `obj_handler` that reads the
declared name sets (`dyncomp/host/dynobj.mbt:376`) follow.

Bump the package version to `tutuca:component@0.8.0`.

**Key files.** `dyncomp/wit/tutuca-component.wit`, `dyncomp/host/guest.mbt`,
`dyncomp/host/dynobj.mbt`, `dyncomp/host/bundle.mbt`, `dyncomp/host/wasm/`,
`dyncomp/shell/`, `dyncomp/DESIGN.md`, `dyncomp/SECURITY.md`,
`dyncomp/ARCHITECTURE.md`.

**Risks.**

- `SECURITY.md` has a "What to check when changing this" section and `AGENTS.md`
  says to run it. Two of its three findings were fields nobody thought were a
  channel.
- `IntentCall.from` closes `SECURITY.md` §5's open item. Update that section
  rather than leaving it describing a gap that is now filled.

**Validation.** `just dev gen-guest-bindings` (drift-checks the generated
trees), then `just dev guest-harness` — the only runtime coverage the guest ABI
has. Needs wasm-tools and jco.

## 17. Regenerate and rebuild every guest

Eleven guest trees under `guests/*`, all generated from the one WIT and the one
SDK, plus the CLI's embedded template and the standalone dice example.

The handwritten file in each tree is the component source (`counter.mbt`,
`todo.mbt`, …), and it is the only one to edit by hand. Everything else is
`gen-guest-bindings` output.

**Key files.** `guests/*/`, `guests/sdk.mbt`, `guests/gen-bindings.mjs`,
`guests/guests.mjs`, `cli/guest_template_gen.mbt`, `guests/template/`,
`examples/dyncomp-dice/`.

**Risk.** `dev/tasks.mbt` keeps a guest list and `guests/guests.mjs` keeps
another. They have disagreed before — `guests/table` sat in one and not the
other, built by nothing. `check-guest-list` exists for this; make sure it runs.

**Validation.** `just dev check-guest-list`, `gen-guest-bindings`,
`guest-harness`, `check-guest-template`, and `dyncomp-storybook` for the
gallery.

## 18. Build `tutuca migrate`

A CLI command that rewrites v1 sources to v2. It is worth building because the
work is large, mechanical and repeated across this repository, the examples, the
site and every downstream project.

What it rewrites, all deterministically:

| In | Change |
| --- | --- |
| `.html` script blocks | `on name` → `receive name`; `bubble name` → `intent name`; `response name(res, err)` → two `receive` arms |
| `.html` state blocks | `bubble Comp {…}` → `intent Comp {…}`; `response Comp {…}` → `receive` arms |
| `.html` views | every event accessor gains `e.` |
| `.mbt` | `Input(` → `Receive(`; `Bubble(` → `Intent(`; `ctx.bubble` → `ctx.intent(… Dyn)`; `ctx.request` → `ctx.intent(… Lex)`; `RequestFn` → `IntentFn` |

What it **reports and does not rewrite**:

- a `ctx.send` naming a generated mutator — task 5's widening changes its
  behaviour;
- a `Response(name, [res, err])` arm, which becomes two arms and needs a human
  to split the body;
- a bare `@on` argument that is not in the accessor table — a latent v1 bug the
  rewrite surfaces.

**Key files.** New `cli/migrate.mbt`, `cmd/main`, `cli/cli_test.mbt`.

**Risk.** A codemod that is 95% right on 500 sites leaves 25 broken ones in a
diff nobody reads. Make the tool refuse a file it cannot fully handle, and list
those files, rather than half-editing them.

**Validation.** Run it over a copy of `storybook/examples/`, then `moon check`
and `moon test`. The tool is done when task 19 needs no hand edits outside its
reported list.

## 19. Migrate the repository's own code

Run task 18 over everything, then read the reported list by hand.

In rough order of how much each teaches: `storybook/examples/` (30 examples, the
worked reference), `playground/site/examples/` (12 pairs the landing page
compiles in a visitor's browser), `playground/site/cards/` (10) and
`tutucard/wasm/examples/` (7), `inspector/`, `dyncomp/ui/` and
`dyncomp/storybook/`, `demo/`, `docs/tutorial.mbt.md` and
`docs/first_principles.mbt.md` (both executable).

Then look for the places where v2 lets a component say less: a child that
bubbles a name its parent answers can often become one `forward`, and a
`response` pair can often gain an `Unhandled` arm that says something real.
**Do this as a second pass, deliberately.** A mechanical migration that also
redesigns is a diff nobody can review.

**Key files.** Everything above, plus `storybook/examples/README.md`.

**Risk.** `docs/*.mbt.md` blocks run under `moon test`, and
`playground/site/examples/*` are compiled in a browser by `<mb-playground>`. A
break in either is invisible to `moon check`.

**Validation.** `just ci`, then `just dev playground` (which drives generate →
compile → link headlessly for every site example) and `just dev
tutucard-playground`.

## 20. The skill

35 files under `skill/tutuca/`, embedded in the CLI binary and read by an agent
before it writes any tutuca code. A wrong snippet here is worse than a wrong
snippet anywhere else.

The files that change most: `request-response.md` (it is about the four
channels, and should probably be renamed and rewritten around messages and
intents), `events.md` (the `e.` boundary), `core.md` (the handler buckets, the
notation table, the four channels), `schema.md` (two message variants),
`semantics.md` (the dispatch table), `component-design.md` (which channel to
reach for — the advice changes), and `testing.md`.

`patterns/coordinate-components.md` is the one pattern file that is entirely
about this, and several others show `@on` handlers with accessors.

**Key files.** `skill/tutuca/*.md`, `skill/tutuca/patterns/*.md`,
`cli/skill_assets_gen.mbt` (generated by `skill-embed`).

**Risk.** The skill rots silently — `specs=` and `@component.FieldSpec` outlived
the parameter's removal by two releases in five files. `check-skill` exists
because of that: it compiles the MoonBit snippets and checks every identifier
against the checked-in `.mbti` files. Fences are load-bearing, and a `nocheck`
block **must** carry a `// nocheck: <reason>` line.

**Validation.** `just dev check-skill`, then `just dev skill-embed` and the
drift check. Both run in `ci`.

## 21. `docs/`, `README`, `AGENTS.md`

`docs/first_principles.mbt.md` rebuilds the framework layer by layer and its
dispatch chapter is now wrong. `docs/tutorial.mbt.md` teaches handlers. Both are
executable, so both fail loudly. `README.md` and `README.mbt.md` carry the
counter example and the channel summary.

`AGENTS.md` needs the new tasks in its table (`dom-props`, and whatever task 18
is called) and the new generated files in its "never hand-edit" list.

Fold `totuka-v2.md` and this plan into the record once the work lands. A design
document that describes shipped behaviour should either move into `docs/` with
its status banner removed, or be deleted — `AGENTS.md` is explicit that a
document specified against something that no longer exists gets deleted rather
than left to mislead.

**Key files.** `docs/*.md`, `README.md`, `README.mbt.md`, `AGENTS.md`,
`CHANGELOG.md`.

**Validation.** `moon test docs` for the executable pair, and a read-through of
`README.md` by somebody who did not do the work.

## 22. The landing site and the playground

`playground/site/` embeds two kinds of live example: `<mb-playground>`, which
compiles MoonBit in a visitor's browser, and `<mb-card>`, which compiles the
block language and no MoonBit. Both show handler code, so both show the change.

`playground/web/starter.js` holds the standalone playground's starter examples
as JS strings that no MoonBit test can reach, which is why the `playground` task
checks them through the real entry points.

**Key files.** `playground/site/`, `playground/web/starter.js`,
`playground/build/check-viewgen-tab.mjs`, `dist/cards.html`'s sources.

**Risk.** The starter strings and the card tutorial are the first tutuca code
most people read. They are also the least covered by `moon check`.

**Validation.** `just dev playground` and `just dev tutucard-playground`. Then
open `dist/` and click through the tutorial.

## 23. Measure the walk

The design makes two performance claims and neither is measured.

- An unanswered view name still costs one lookup, as v1 does. This is what makes
  stop-by-default worth having, so prove it.
- A default-route intent walks every ancestor, then the whole scope chain, one
  queued transaction per hop. Measure a deep tree with a hot intent.

If task 1 answered "`lex` walks", measure a declining static handler chain too.

**Key files.** `benchmarks/`, `benchmarks/OPTIMIZATIONS.md`.

**Risk.** The house rule in `OPTIMIZATIONS.md` is that a change which does not
move a number gets reverted, not kept because it should be faster. Hold this
design to it: if the default route is too slow to be the default, say so in
`totuka-v2.md` and change the default.

**Validation.** A benchmark checked in beside the existing ones, and a paragraph
in `OPTIMIZATIONS.md` with the numbers.

## 24. Release and the consumer examples

`examples/*` are not packages of this module. Each has its own `moon.mod`
depending on the **published** `marianoguerra/tutuca` from mooncakes, and each
has its own `build.mjs`. They are the only thing that proves a release is
complete on its own. `moon check`, `moon fmt` and `ci` never reach them.

So the order is fixed: release, then run the examples, then announce.

`examples/dyncomp-dice` exercises the wasm-gc loaders surviving `moon publish`,
the relative import between them being repointable, and `tutuca new-guest`
emitting a tree that builds. All three are touched by tasks 16 and 17.

**Key files.** `examples/`, `examples/dyncomp-dice/`, `CONTRIBUTING.md` (the
release steps), `CHANGELOG.md`.

**Risks.**

- An example must never gain a path dependency or a step that runs anything from
  this repository. That is the one thing it proves.
- This is a major version for the guest ABI. Every downstream guest needs a
  rebuild, and the changelog entry should say so in its first line.

**Validation.** Publish, then `node build.mjs` in each example, then open each
page. Then announce.
