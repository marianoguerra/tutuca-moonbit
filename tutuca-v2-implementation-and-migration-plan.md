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

## How this lands: expand, migrate, contract

The task order below is the order the work has to happen in. It is **not** a
sequence of commits, and one fact decides that: `.githooks/pre-commit` runs
`moon check`, so a commit that does not compile cannot be made. Task 3 removing
`ctx.bubble` would break `transactor`, `component`, `app`, both backends,
`viewgen`, eleven guests and every example at once, and the tree would stay red
from task 3 to task 19 — no bisect, no working intermediate, and a `moon test`
that says nothing for the length of the release.

So each task lands **additively**. The v2 surface goes in beside the v1 one,
both compile, and the v1 one is deleted at the end in a separate contract step.
Where the design says a type "goes from four cases to two", the four gain a
fifth now and lose three later. That is what the task-2 corpus already did —
`cases_v2()` beside `cases()`, with the v1 list deleted in tasks 10 and 11 — so
this is the shape the plan chose the moment it wrote a second corpus rather than
editing the first.

Two consequences worth stating outright.

- **A five-arm `HandlerBucket` is not the design.** Every one of them carries a
  comment saying which v2 arm it folds into and that it is going. The
  intermediate state is a scaffold, not a compromise.
- **The contract step is a task**, added at the end as task 25, and it is not
  optional: an expand that never contracts is how a codebase ends up with two of
  everything.

## Tasks

**Phase 0 — decide**

- [x] 1. [Close the blocking open questions](#1-close-the-blocking-open-questions)
- [x] 2. [Write the conformance corpus first](#2-write-the-conformance-corpus-first)

**Phase 1 — the runtime**

- [x] 3. [`core`: buckets, `Ctx`, `IntentOpts`](#3-core-buckets-ctx-intentopts)
- [x] 4. [`transactor`: the walk, `reply` / `fail` / `forward`](#4-transactor-the-walk-reply--fail--forward)
- [x] 5. [`component`: `Dispatch`, `obj_handler`, `IntentFn`](#5-component-dispatch-obj_handler-intentfn)
- [x] 6. [`app`: wire the lexical scope and the DOM entry](#6-app-wire-the-lexical-scope-and-the-dom-entry)

**Phase 2 — the language**

- [x] 7. [`tscript`: kinds, effects, leg words](#7-tscript-kinds-effects-leg-words)
- [x] 8. [`tscript/check`: the new findings](#8-tscriptcheck-the-new-findings)
- [x] 9. [`statedef` / `viewfile`: two message variants](#9-statedef--viewfile-two-message-variants)
- [x] 10. [`tscript/emit_mbt`: the AOT backend](#10-tscriptemit_mbt-the-aot-backend)
- [x] 11. [`tutucard/wasm`: the card backend](#11-tutucardwasm-the-card-backend)
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
- [ ] 25. [Contract: delete the v1 surface](#25-contract-delete-the-v1-surface)
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

**Done.** Additively, per "How this lands" above. `core/pkg.generated.mbti`
gains, and loses nothing:

- **`Leg`** (`Dyn`, `Lex`) with `Leg::word` and `route_label`, so a route has
  one spelling and not one per package that prints it.
- **`IntentOpts`** — `route : Array[Leg]`, `on_ok_name`, `on_error_name`,
  `on_unhandled_name`, `live_path`. v1's `on_res_name`, the combined
  `[res, err]` arm, has no field here. **`IntentOpts::new` is where the default
  route `[Dyn, Lex]` is written**, once, and every package asks for it rather
  than spelling the two arms itself.
- **`Ctx`** gains `intent`, `intent_at_path`, `forward(args?, opts?)`, `reply`
  and `fail`, each defaulting to nothing. `intent` defaults to `intent_at_path`
  at the ctx's own path, the way `send` does — "start at the parent" is the
  walk's rule and belongs to the transactor, not to the address.
- **`PathChanges::intent`**, so `ctx.at()` reaches the new channel.
- **`HandlerBucket`** gains `Intent` (five arms; three go in task 25).

`RequestOpts`, `ctx.bubble` and `ctx.request` are untouched and still work.

Pulled forward, because a fifth bucket arm makes them non-exhaustive and the
tree has to compile: `Dispatch::Intent` (task 5's enum, one arm early),
`ObserveKind::Intent` (task 4's), and the bucket arms in `dyncomp/host/dynobj.mbt`,
`dyncomp/host/wasm/glue.mbt` and `tutucard/playground/cardguest.mbt`. The two
guest-facing ones answer honestly rather than with a placeholder: no loaded
bundle declares an intent, so `DynObj::obj_handler` says `false` for the bucket,
and no bundle can see the wire number until task 16 puts it in the WIT.

**The risk held.** `core/path_intent_test.mbt` drives `intent`, `forward`,
`reply` and `fail` on a `NullCtx` and asserts each returns — a `reply` with no
transactor is a no-op, because there is no walk to answer. The same file pins
the default route in the one place it is written.

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

**Done.** Additively: `push_bubble` and `push_request` are untouched and
`bubble_test.mbt` / `request_test.mbt` still pass unchanged. The walk is a new
file, `transactor/walk.mbt`, and 22 new tests are in `transactor/walk_test.mbt`.

**`IntentWalk` is what replaced `Transaction.bubbles : Bool`**, and the two
answer different questions — a boolean can say "keep going up", it cannot say
which leg, how far along it, and whether the one allowed answer has been given.
It is shared **by reference** across every hop of one intent, which is what
makes each of the risks below fall out rather than need arranging. `Transaction`
carries `walk : IntentWalk?` and `is_answer : Bool`.

Three things end a walk, and `walk.mbt` is organized around them: `answer_walk`
(a handler replied or failed), `end_walk_unanswered` (`stop`), and
`exhaust_walk` (the route ran out). Everything else continues it.

- **The `dyn` leg** pops before each hop, so it starts at the sender's parent
  and a component never re-enters its own handler.
- **The `lex` leg** resolves through a new `Intents` trait that hands back the
  WHOLE chain, innermost first, and `try_lex` asks each in turn **inside the
  transaction already running** — the task-1 decision, and a test asserts the
  observer trace shows no queued hop per `Pass`. It is continuation-passing, so
  a static handler may still answer later.
- **`forward`** is one operation from two sides. In an intent body there is a
  walk, so it amends the hop the walk was going to make anyway (arguments, or a
  narrowed route) — the walk advances on its own, because every handler on the
  route runs. In a receive body there is no walk, so it starts one from this
  component's own position, which is where the answer comes back to.
- **Route exhaustion** consults only what the sender DECLARED — `Unhandled`,
  then `Error` with `noHandler`, then a refusal record if it declared `Ok`
  alone, then nothing. `reply` and `fail` DERIVE `<name>Ok` / `<name>Error` when
  the opt is absent, so a reply nobody declared an arm for reaches no arm and
  produces `NO_HANDLER` — design section 1. The asymmetry is deliberate and
  commented: section 6's fallback chain is defined in terms of declaredness and
  would be unobservable if it derived a name too.

**The three risks.**

- **Completion.** The sender's unit is held by the WALK, tracked when the walk
  starts and released exactly once — transferred onto the answer's subtree when
  there is an answer, released directly when there is not. Hop-to-hop linking
  keeps the sender open through the hops; the walk's unit keeps it open across
  an async `lex` handler and until the answer settles. Two tests: one asserts a
  sender settles only after its answer lands, one that a walk nobody answers
  still lets the sender go.
- **`SECOND_REPLY`.** `walk.answered` is per INTENT across hops, because the
  walk is one object shared by the hops. A test puts a replier at two positions
  and asserts one answer.
- **Depth.** `INTENT_DEPTH = 64` counts POSITIONS across the whole walk, not
  frames of one leg — the only reading that catches a cycle spanning both.
  Exceeding it takes the exhaustion path, so a sender that asked for an answer
  learns something, and reports the new `RefusalCode::IntentDepth`
  (`INTENT_DEPTH`).

`ObserveKind` gained `Answer` alongside task 3's `Intent`, and `transact` picks
it from `is_answer` rather than from the bucket — a handler must not be able to
tell an answer from any other message, and an inspector must.

`core` gained `IntentCall` (with `from`, which closes `dyncomp/SECURITY.md` §5's
open item) and `IntentAnswer` (`Ok` / `Failed` / `Pass`). They live in `core`
rather than beside `Dispatch` in `component`, where the design lists them,
because `transactor` constructs one and `component` consumes one and neither
imports the other.

**The four cases task 2 deferred here** are each a test: an observer above a
replier, a declining handler and the walk continuing, `reply` twice across two
hops, and route exhaustion in all three shapes.

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

**Done.** The widening is the only part of this task that is not additive, and
it is the point of the task, so it landed as written: `obj_handler`'s
`bucket is Input` conditions became `answers_at_home(bucket)`, one named
function used in all three places, which is `Input | Receive`. **`Intent` is
deliberately not in it** — a generated mutator answers a message at home and
never an intent up a route (design section 5), and a test asserts the negative
alongside the two positives.

**The widening broke nothing in the suite** (1528 tests). That is evidence and
not proof: it says no test in this repository depends on a `ctx.send` silently
missing a mutator. Task 18 still has to report the call sites, because a
component nobody tests can still have one.

Additive, alongside the v1 names:

- **`IntentFn`** beside `RequestFn` — takes an `IntentCall`, answers
  `Ok` / `Failed` / `Pass`.
- **`ComponentStack.intents : Map[String, Array[IntentFn]]`** and
  **`register_intent_handlers`**, which **appends** where `register_request_handlers`
  overwrites: two registrations of one name are two candidates in registration
  order, because a handler that can decline does not shadow the next one.
- **`ComponentStack::lookup_intent`** returns the whole chain, innermost frame
  first — the shape task 1 settled. `lookup_request` is untouched.
- **`ModuleDef.intents`** beside `ModuleDef.requests`, registered by
  `register_into`.

`Dispatch::Intent` and the `obj_handler` arm for it landed in task 3, where a
five-arm bucket forced them.

`Pass` continuing the walk is tested at the layer that does the continuing —
`transactor/walk_test.mbt`, task 4. What is tested here is the shape that makes
it possible: `lookup_intent` hands back four handlers across three frames, in
order.

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

**Done.** `ScopeIntents` beside `ScopeRequests` in `app/app.mbt`, resolving
through the same registration scope and answering with the whole chain;
`App::new` hands both to the transactor. `app/app.mbt:110`'s `push_input`
became `push_send`: **a view raises a message now.**

**The risk held.** `stop_on_no_event` is about finding a handler in the VIEW and
never looks at a bucket, so the early exit is untouched and an unanswered name
still costs one lookup.

**Three migration bridges**, all commented as such and all deleted in task 25.
Switching the DOM entry is the one change that reaches every component at once
— 393 `update` arms still say `Input` — so each dispatch site offers a `Receive`
nothing claimed a second time as an `Input`:

1. `TypedInstance::obj_handler`, for every generated and hand-written typed
   component. It cannot change a v2 component's behaviour: one with no `Input`
   arms answers `Unhandled` twice, at the cost of one extra match.
2. `DynObj::obj_handler`, for a loaded bundle built against the current WIT.
   The same file's `declared` table also collapsed `Input` and `Receive`, and
   that one is **not** a bridge but the merge itself: v2's `Receive` is v1's
   `Input` union v1's `Receive`, and the union of "always, discovered
   dynamically" with "only what the manifest declares" is the first.
   `def.receives` stops gating and starts documenting until task 16.
3. `storybook/ui/engine.mbt`'s `ShellInst`, the one hand-written `obj_handler`
   in the repository with `(Input, …)` arms. Its match moved into
   `ShellInst::handler_for` so the same retry could sit over it.

Without bridge 3 exactly one test failed, which is worth recording: the
gallery's shell is the only place in the repository where a component answers a
view name without going through `TypedInstance`.

`app/app_test.mbt` drives both halves in one click: the view's name arrives as
`Receive`, a `lex` intent is dispatched, the first scope handler declines and
the second answers — a walk, not a lookup — and `IntentCall.from` carries the
sender's position.

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

**Done.** Additively: `DeclKind` gains `DIntent` (ten arms; `DOn`, `DBubble` and
`DResponse` go in task 25), `kind_word` / `kind_of_word` / `is_transition`
follow, and `effect_min_arity` gains `intent` (1), `forward` (0), `reply` (1)
and `fail` (1) while keeping `bubble` and `request`.

**`SEffect` gains `route~ : Array[@tutuca.Leg]`** — 10 sites, most of which
already used `..`. It is written **as written, not resolved**: a bare
`intent 'save'` records the EMPTY route, not `[Dyn, Lex]`. The default lives in
`@tutuca.IntentOpts::new` and a parser that resolved it here would be a second
place for it to live and a second place for it to drift. (The corpus records the
route resolved, which is the opposite choice for the opposite reason: there it
is the backends' agreement being pinned, here it is the source being
represented.) A test asserts both halves.

**The one new parse rule** is `takes_route(name)` plus `leg_of_word(w)`: for
`intent` and `forward` only, read leg words while the next token is one, then
parse arguments normally. It adds no ambiguity to juxtaposition — an `intent`'s
name is always a string literal and `forward`'s arguments are values, so neither
can be the bare word `dyn` or `lex`.

**The collision risk held**, and there are five tests for it: `pred dyn`,
`receive dyn`, a parameter named `lex`, a parameter list `(dyn, lex)`, a
`requires lex` naming a pred, and `send 'flash' dyn` — where `send` takes no
route, so `dyn` is an ordinary name and the parser must not eat it. The lexer
emits both as `TIdent` and only the two route positions ever ask.

The one place the contextual keyword does cost something is written into the
test rather than left to be discovered: a parameter named `lex` cannot be
forwarded by writing `forward lex`, because that position is a route. Stage it
in a field and write `forward .staged`.

The printer puts the legs between the verb and the arguments, which is where
they are written and the only place they can be read back from; every form above
round-trips.

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

**Done — two of the five.** `NOT_A_HANDLER` and `NO_VIEW_HANDLER` are in, with
seven test cases and their exact messages asserted.

**The other three moved to task 15, and the reason is a dependency the plan has
backwards.** `BAD_EVENT_PATH` needs task 14's allowlist, `UNKNOWN_EVENT_PROP`
needs task 13's generated table, and `BARE_ARG` needs task 15's slot parser to
accept `e.` before a bare name can be called wrong. All three are findings
ABOUT the `e.` boundary and none of them can be written before the boundary
exists. Task 15 is where they go, and its Validation section names them.

**`Finding` gains `severity : Severity`** (`SError` / `SWarning`). It had none,
because every finding was fatal; `NO_VIEW_HANDLER` cannot be, since the code it
warns about behaves exactly as v1 behaves. `C::warn` is the second constructor
and `tutucard/wasm/compile.mbt` — the one place a finding stops a build — skips
warnings, while `check.mbt`, the reporting face, still lists them.

**The risk is already held, by an accident worth writing down.** The plan says
to land `NO_VIEW_HANDLER` silent, run it, and read the list. It IS silent: the
only two callers of `@check.check` are the card backend's, and both pass
`Surface::empty()`, so `surface.inputs` is empty and the rule cannot fire. The
AOT path does not call the checker at all. Wiring a real surface is task 10 and
12's work, and reading the list belongs there.

**Two rules changed as well as gained.**

- **`DYNAMIC_MESSAGE`** asked "is the first argument a literal" of every effect
  but `stop`, which in v1 was the same set as "effects that name a message". v2
  adds three that name none — `forward` re-dispatches the name that arrived,
  and `reply` / `fail` are addressed by the walk — so `reply 1` would have been
  reported as a dynamic message name. `names_a_message` is now explicit.
- **`NO_SUCH_MESSAGE`** no longer fires for a `receive` whose name the VIEWS
  send. That is the merge: the schema declares every message the component
  accepts *beyond the ones its own views send* (design section 9), so a
  `receive` answering a view name takes its parameter types from the call sites
  exactly as an `on` did. Without this, migrating `on save` to `receive save`
  would require a schema edit per handler.

**`addresses_a_field` is deliberately conservative.** This package imports
`tscript` and `statedef` and nothing else, so it cannot see
`component/gen_mutators`' verb table, and a second copy of that list is how two
lists drift. What it can see is that every generated name is built from a
declared field's name capitalized — plus `<field>Len`, the one that is not — so
a name containing none is certainly not a mutator and one that does might be.
Erring toward silence is this package's governing rule: a missed mutator is a
warning nobody wanted; a false one teaches people to ignore the rule.

`DIntent` gets opaque parameters for now: the state block has no `intent`
variant until task 9, and `msg_params` reads it there rather than reporting
`NO_SUCH_MESSAGE` against the wrong variant.

## 9. `statedef` / `viewfile`: two message variants

The state block's six keywords become five: `state`, `struct`, `enum`,
`receive`, `intent`. `bubble` and `response` go.

**Key files.** `statedef/`, `viewfile/split.mbt`, `viewfile/errors.mbt`.

**Risk.** The parser shares its name table with `new <Type>` in the block
language, so a type called `Intent` would now collide with a keyword. Check the
reserved-name list.

**Validation.** `statedef`'s own tests, plus `gen-views` over the repository's
`.html` files in task 19.

**Done.** Additively: the keyword list is `state`, `struct`, `enum`, `receive`,
`intent`, `bubble`, `response` — seven for now, five after task 25. `StateDef`
gains `intent : Array[MsgDef]` beside `receive`, `bubble` and `response`, and
one `StateDef` record literal (`tutucard/wasm/compile.mbt`'s no-state fallback)
gained the field.

**The risk did not materialize, and there is a test rather than an argument.**
The declaration word is lowercase `intent` and a type name is capitalized, so
`struct Intent`, a field of type `Intent`, and an `intent Board { Intent(Intent) }`
case all coexist — a parser that lowercased before matching would collide and
nothing else would notice until somebody named a struct after the keyword. The
case is written out.

`viewfile` needed nothing: neither `split.mbt` nor `errors.mbt` names a message
variant. The word list lives in exactly two places — the parser's `want` text
and `DefError`'s `UnknownDecl` message — and a test asserts the second in full,
so a word added to the match without being added to both is a parser that
accepts something it says it does not.

**Task 8's deferral is closed here.** `tscript/check`'s `msg_params` now maps
`DIntent` to `def.intent`, so an `intent` handler for a name the schema does not
declare reports `NO_SUCH_MESSAGE` naming the right variant.

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

**Done. All 24 v2 cases compile and pass, with zero refusals.** That number is
pinned in the driver, and it is the number worth having: every v2 case was
written against the design rather than against this backend, so a refusal here
would be the backend failing to express something the design says.

The kind-to-bucket map gains `DIntent => "Intent"`, `answers` and `EmitResult`
gain `answers_intent`, and the effect emitter gains all four. `intent` emits
`ctx.intent(name, payload, IntentOpts::new(…))`; `forward`, `reply` and `fail`
skip the literal-name guard entirely, because none of them names a message.

**`E::outcomes` is where "the generator computes it" becomes code.** Design
section 6 says a sender expects an answer if and only if it declares an answer
arm; `answer_arms` is the schema's `receive` variant plus the block's own
message declarations, and an `intent` effect gets `on_ok_name` /
`on_error_name` / `on_unhandled_name` filled in from whichever of
`<name>Ok` / `<name>Error` / `<name>Unhandled` the component actually answers.
Nobody writes them. **`intent_opts` emits no `route=` for an empty route**, so
the default `dyn lex` stays in `IntentOpts::new` rather than being spelled into
every generated module.

**The corpus needed a second projection, and one real decision inside it.**
`cmd/conformance` now writes `corpus_v2.html` + `table_v2_gen.mbt` beside the v1
pair, driven by `drive_v2_wbtest.mbt`; `dev/tasks.mbt`'s `gen-views` list gained
the file. Separate rather than merged because the two schemas have nothing in
common, and merging them would be work that exists only until task 25.

The decision: **`project_v2` GENERATES the schema's message variants from the
cases** rather than copying the corpus's own. v1 can copy, because it declares
one `receive`, one `bubble` and one `response` and everything else is an `Input`
whose names nothing declares. v2 cannot: six cases declare `intent saveDraft`
with six different bodies, which is the point of them, and one component answers
one name once. So every handler is renamed to `case<i>` and the schema follows,
one variant case per handler, typed from the values the case dispatches. A
consequence: **no view call sites are emitted** — a generated schema declares
the payloads outright, and for an `intent` a template would be wrong, since a
view raises messages and never intents.

One case is renamed and dispatched under a DIFFERENT name on purpose: `a message
no arm answers` declares `receive inc` and dispatches `nope`. The table records
the dispatched name, not the declaration's, or the projection would quietly
answer the case it exists to leave unanswered.

**The refusal door is intact** — `E::effect` still raises `Cannot` for what it
cannot compile, and a `forward` reached no new limit.

**One v1 case started compiling as a side effect, and it is a real
improvement.** `E::param_types` now falls back to the view surface for a
`DReceive` the schema does not declare — the same fallback `tscript/check` made
in task 8, for the same reason: with one bucket for a view's name and a
parent's, a `receive` answering a view name takes its types from the call sites.
v1's `case48` had been refused for want of a type and now emits an arm. The
driver's pinned refusal count is unchanged, because that case dispatches into
the `Input` bucket and still finds nothing there.

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

**Done. All 24 v2 cases pass here too, with zero refusals** — the same number
the AOT backend reached, reached independently. That is the whole point of the
corpus, and it is now doing the job: two compilers with nothing in common
between them agree about what a v2 block means.

**The wire, which is where the real decisions were.**

- `@abi.bucket_intent = 4`, and `handle_event_fn` gains a `DIntent` arm.
- Four effect kinds in the wax runtime (`tc_e_intent` 6, `forward` 7, `reply` 8,
  `fail` 9) and a **`route : i32` field on `tc_effect`** with
  `tc_effect_push_routed`. One i32 rather than a list, because **the set of
  routes is closed** — two legs in one of two orders, or one, or none — so it
  costs a word instead of a pointer and a length into linear memory.
  `@abi.route_*` is the table, and `route_code` in `stmt.mbt` and `ROUTE` in the
  harness are its two halves.
- `flush_fn` became a **flat chain** rather than a nest. It read as one thing at
  four kinds; at nine, nested five deep, it read as nothing.
- The four control imports are emitted **only when a card performs one of
  them**, so a v1 card's import section is byte-identical and an old bundle
  stays loadable by a host that was not rebuilt.
- `manifest.mbt` gains `intents` beside `bubbles` and `responses`.

**`route_none` resolves to the default, on both sides.** A bare
`intent 'save'` writes `route_none`, and the harness maps index 0 and index 3
to the same words. That is exactly why the corpus stores a route RESOLVED: the
default is the one thing two backends can agree to disagree about while every
explicit route passes, so both are made to say `dyn lex` out loud.

**Two things the harness needed, and both are about a card having no views.**
The harness builds one card per case with an empty `<template>`, so there are no
call sites — and in v2 a `receive` the schema does not declare is one the VIEWS
send. So `cmd/card-corpus` now emits the case's handler **as a variant case**
and the harness splices it into the schema. One case needs two: it declares
`receive inc` and dispatches `nope`, which is the point of it, so `decl_variant`
reparses the script for the declared name and the schema carries both.
`payload_ty` moved into the corpus package, because both projections need it and
two copies of a type inference is two ways to hand the two backends different
declarations for the same case.

**Pulled forward from task 16**, because the card could not otherwise be
instantiated: `abi.mjs`'s `BUCKET` enumeration and `loader.mjs`'s twin gain
`intent` as the fifth case, and `IMPORTS` gains the four control functions —
`abi.mjs` refuses any import outside the contract before a single guest
instruction runs, which is the check working. Task 16 owns the WIT itself; if it
lands on a `list<leg>` rather than a `u32` route, `IMPORTS`' row and
`@abi.route_*` are what move.

`just dev tutucard-playground` passes: all fourteen starter cards still compile,
and the region checks pass.

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

**Also here: the three checker findings task 8 could not write.** Each is about
the `e.` boundary and none can exist before it does — `BAD_EVENT_PATH` (a step
off task 14's allowlist; an error), `UNKNOWN_EVENT_PROP` (a rooted path naming a
property task 13's table does not have; a warning naming the closest match) and
`BARE_ARG` (a bare name in an `@on` argument slot; an error naming the three
prefixes). They live in `tscript/check` with the other two, and
`Finding.severity` from task 8 is what lets the middle one be a warning.

**Validation.** `moon test --target js` for the real DOM path. A test for each
accessor, a test for `e.detail.unicode`, a test that `e.target` alone is `Null`,
and the refusal tests from task 14. Plus one `check_test.mbt` case per finding
above, asserting the exact message.

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

## 25. Contract: delete the v1 surface

The other half of "How this lands". Everything the migration added beside a v1
name is only worth adding because this task removes the v1 name.

What goes: `HandlerBucket`'s `Input`, `Bubble` and `Response`; `Dispatch`'s
same three; `ObserveKind`'s `Input`, `Bubble`, `Response` and `Request`;
`RequestOpts` and `RequestOpts::new`; `Ctx::bubble`, `Ctx::bubble_at_path` and
`Ctx::request`; `PathChanges::bubble`; `RequestFn` and
`register_request_handlers`; `ScopeRequests`; `Case` and `cases()` in the
conformance corpus, with `V2Case` renamed back to `Case`; `DeclKind`'s `DOn`,
`DBubble` and `DResponse`; and the `bubble` / `request` effects.

**Key files.** Every file tasks 3–17 touched, minus the ones that only gained
something.

**Risk.** A deletion this wide is exactly where a v1 spelling survives in a
string, a comment or a generated table rather than in a type — the checker
cannot see those. Grep for each removed name after the types are gone, and
treat a hit in `skill/`, `docs/` or a `.html` as a task-19-or-20 miss rather
than as noise.

**Validation.** `just ci`, then `just dev guest-harness` and `just dev
tutucard-playground`. Then `git grep` for each deleted identifier: the only
hits should be in `CHANGELOG.md` and in the migration tool's own tables.
