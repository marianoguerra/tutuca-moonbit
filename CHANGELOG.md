# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- **One `Origin`, where there were three enums saying who.** `DispatchProvenance`
  is `@tutuca.Origin { Host, View, Handler }` — the fourth case, `Diagnostic`,
  existed only to say a stress run could reach a generated mutator, and there is
  no such fallback left to gate. `Ctx::provenance()` is `Ctx::origin()`.

  `transactor.Source { Extern, Derived }` is gone: it answered "is this an
  input a replay has to feed", which is exactly `origin.is_external()` —
  `Host | View`. So is `ObserveKind { Receive, Intent, Answer }`, which was
  `HandlerBucket` plus one bit: an `ObserveRecord` now carries `origin`,
  `bucket` and `is_answer`, and `ObserveRecord::kind_label()` is the one place
  that folds the last two into the word a reader sees. `HandlerBucket::label()`
  and `Origin::label()` are beside `ordinal()`.

  The activity log shows both, because they are two questions: a `receive`
  raised by a view and a `receive` a handler pushed read identically otherwise.
  A record's JSON gains `"origin"`; `"kind"` is unchanged.

  `Transaction`'s own `origin : DispatchPath?` — the sender's position, which
  `NO_SENDER` refuses on — is `sender`, and `IntentWalk.origin` with it. Two
  fields named `origin` meaning a place and a kind in one struct is the
  collision this release exists to remove.

- **An intent's failure answer is `<n>Failed`.** `Error` is a thing; `Failed`
  is what happened. `IntentOpts.on_error_name` is `on_failed_name`, the WIT
  record's `on-error` is `on-failed`, and the hosts pass `onFailed`.

  The old spellings still work for one release: `IntentOpts::new` keeps an
  `on_error_name?` keyword filling the same field, a script block's
  `receive <n>Error` arm is still wired to the failure, and
  `@tutuca.retired(AnswerName, name)` says what to write instead — matching on
  the SUFFIX, since a derived answer name is an intent's own plus one word.

- **`<n>Unhandled` is derived like the other two.** A sender that declared
  `on_ok_name` and nothing else used to hear a bare `NO_HANDLER` refusal naming
  the intent. It now hears `<n>Unhandled`, carrying the intent's own arguments
  the way a declared one does — and if it has no arm for that, the refusal
  names `<n>Unhandled`, which says more. A sender that declared nothing is
  still sending a notification and still hears nothing.

- **`scenedef.Answer` is `@tutuca.IntentAnswer`.** A second three-case enum
  saying the same three things, with a conversion in the card driver between
  them. Scenes hold the real one; the conversion is gone.

- **The guest world is `tutuca:component@0.12.0`.** The bump deferred from the
  `Ty`-as-JSON manifest change, landing with the `on-failed` rename. Manifest
  `apiVersion` stays at 10: the manifest shim that reads the old `ty : Int`
  form is what makes an older bundle's manifest readable, and bumping the gate
  beside it would make the shim unreachable.

- **A dispatch nothing answers is refused, not routed to a setter the field
  implies.** A `Receive` used to be offered to three things in order — the
  `swap` bucket, `update`, and then the generated mutator of that name — so
  `@on.click="setTitle 'x'"` reached a setter no one wrote, an `update` arm
  answering `Unhandled` fell through to one, and a real handler could be
  shadowed by the field beside it. There is one lookup now: `update`, and a
  name it does not claim is refused with `NO_HANDLER`.

  What replaces the fallback is the thing that was always the honest spelling
  of it — a **property action**, written in the view:

  ```html
  <button @on.click=".title = 'x'">rename</button>
  <input  @on.input=".query = e.value">
  <button @on.click=".open = not .open">toggle</button>
  <button @on.click=".count = default">reset</button>
  <button @on.click=".items.removeAt @key">x</button>
  ```

  A write reads as a write and a name reads as a message. Both go through the
  same doors — the domain and the invariants are asked either way — so nothing
  is given up by writing the field directly.

  Migrating a view is mechanical: `setX v` becomes `.x = v`, `toggleX` becomes
  `.x = not .x`, `resetX` becomes `.x = default`, and the `In…At` family becomes
  a member operation (`.items.removeAt @key`, `.items.push v`). An `update` arm
  whose only body was `Unhandled` for such a name is deleted with it.

- **`Update[S]` says what happened, in four words instead of two and a bucket.**
  Beside `Next` and `Unchanged` it gains `Replace(Value)` — this node is
  superseded by a different value, which is what the `swap` bucket existed for —
  and `Refused(Refusal)`, which turns a dispatch down and says why. The `swap`
  bucket is gone from `component()` and from the generated wrappers; a component
  that replaced itself now answers `Replace(v)` from an ordinary `update` arm.

- **`Outcome` is what a write ANSWERS, and its cases are spelled plainly.**
  `PropertyWrite` is an alias for the same enum; the constructors are `Missing`,
  `Unchanged`, `Refused(Refusal)` and `Changed(Value)`. `Refused` carries the
  refusal rather than a bare marker, so the reason a write was turned down
  travels with the answer.

- **A guest that answers `unhandled` has answered.** The host's dyncomp bridge
  no longer falls back to a mutator the guest's schema implies: a guest view
  writes its own property (`.count = 0`), and the write crosses through the
  property door.

- **The fuzz driver's fourth source is `Fields`, and it writes.** It used to
  DISPATCH generated mutator names, which only worked because of the fallback;
  it now draws a `SetField(name, value)` and goes through the write seam. In the
  storybook's Fuzz tab the button reads **Fields** rather than *Internal
  mutators*, and the source is named `fields`.

### Fixed

- **Every starter card in the card playground was refused, and the scenes
  behind them never ran.** `tutucard/wasm/check.mbt` passed the checker the
  spec block's rules lifted alongside the script block's own declarations —
  something only the EMITTER needs — so every `pred` and `invariant` in a spec
  block was reported as `RULE_IN_BOTH` against itself, under a span belonging
  to a different block that the reporter then rebased into this one. Seven
  cards did not load; the twenty-five scenes they declare were never reached.

  Behind that: the starter cards in `tutucard/web/examples.js` still dispatched
  generated mutator names (`setLabel e.value`, `resetCount`, `toggleIsOpen`),
  which no longer answer. They write their properties now, the way every other
  view in the repo does.

- **The card playground's structured editor could not find any card's spec
  block.** `tutucard/web/regions.js` matched `<script type="tutuca/state">`, a
  spelling this repo no longer writes — the same retired word the benchmark
  corpus builder was matching. It accepts both now, and the region is `spec`
  rather than `state`.

- **`tutucard/wasm/examples/Guarded.html` had its `pred` cut in half.** The
  rule's body ended up ten lines away, inside the script block and after the
  handler, left there by the sed that moved the rule layer into the spec block.
  The card had not parsed since.

- **The benchmark view corpus kept every schema block it was supposed to
  strip.** `benchmarks/build.mjs` matched `tutuca/state`, a spelling the repo
  no longer writes, so `all_views.html` concatenated 36 schema blocks into one
  file and `split_file` refused it as a duplicate. The corpus had been stale
  long enough to hide it.

## [0.47.1] - 2026-09-01

### Fixed

- **An instance handed to a guest as a constructor or message argument was
  flattened on the way in.** `create` and `dispatch` encoded their arguments
  with `Value::to_json`, which has no form for an `Obj` and so writes what the
  object HOLDS — a copy of an instance's state under a name that no longer
  refers to it. The guest stored a map, answered reads with a map, and a field
  declared to hold a component drew nothing: no refusal, no console error, an
  empty cell. `child_json` is the encoder that writes the HANDLE instead, and
  it was already used by `with_field` and `set_property` — so the same instance
  survived being written to a field and did not survive being passed to the
  constructor, which is what made this look like a rendering bug rather than an
  encoding one. Both bridges are fixed: `dyncomp/host/wasm` and the card
  playground's twin in `tutucard/playground`.

  This is what a holder actually needs. 0.47.0 made the host KEEP a component
  the guest cannot hold; a component the guest CAN hold — a sibling from the
  same card, which is the common case when a container and its primitives ship
  together — still had to cross, and this is the crossing.

- **`skill/tutuca/tutucard.md` said a card cannot message a component held in
  a hole.** It can: a message needs an ADDRESS, not the value, and `sendAt`
  carries a literal path the HOST resolves against the tree, where the hole's
  contents are. What stays out of reach is reading THROUGH such a field.

## [0.47.0] - 2026-09-01

### Fixed

- **A card could not be a holder: a component from outside the guest did not
  survive a round trip through its state.** A field declared as a bare
  `component` — "some component", naming none — was neither built by the host
  (`placeholder_fields` matches only a NAMED `ty-comp`, and rightly: there is
  nothing to build) nor holdable by the guest, because nothing the guest ABI
  carries can hold a host component. What crossed was `child_json`'s fallback,
  the instance's FIELDS, so the guest stored an object with the shape of a
  component and none of its behaviour and `<x render>` drew nothing at all —
  no refusal, no console error, an empty cell.

  Such a field is now held by the HOST when a caller passes an instance for
  it, through the same `owned` mechanism a named placeholder uses. A list of
  them is held the same way, so a container whose cells the host supplied
  renders all of them.

  The discriminator is the VALUE, not the field: an instance of the guest's
  OWN bundle crosses as a token it holds and reads back through
  `wrap_instance`, and taking that one over would put the host in charge of a
  child the guest makes and manages. Only an instance with no guest handle —
  one the guest could never have handed over — is held here. Same field, same
  declared type, different answer.

  `skill/tutuca/tutucard.md` said a card "may carry, render, and message" a
  child component, which was true only of its own components. It now says what
  each kind can do.

## [0.46.0] - 2026-09-01

### Fixed

- **A card declaring a protocol with a `property` member could never be
  registered.** The two sides disagreed about the shape of a protocol's
  property list: `tutucard/wasm` emitted an array of NAMES, and
  `dyncomp/host` read it with the same parser it uses for a component's
  properties, which requires objects and RAISES on anything else. One protocol
  property took the whole manifest down — `manifest: bad property-def` — while
  `parse_protocols` one level up was carefully skipping malformed entries.

  Both sides move, in the direction the host was already asking for. The
  emitter writes objects, with the member's declared type interned into the
  component's own type table like a field's or a property's: `DynProtocolDef`
  carries a property-def per member and resolves that index to build a
  `PropertyInfo`, so a list of names was dropping something the host has a use
  for. And the parser now accepts a bare string as a name-only member — what a
  hand-written manifest, or a compiler that had only the member list, can
  honestly say — reading it back as `TyAny` instead of refusing the bundle.
  Anything else in that list is skipped rather than raised, which is the stance
  the protocol parser around it already took.

### Added

- **`@dhw.load_error(load_id)`, and `dyncomp_load_error` beside the other host
  exports.** A refused registration told the PAGE (a `dyncompError` receive at
  the load's path) and told the caller nothing, so a host that resolves its own
  callback anywhere other than the `dyncompLoaded` handler could not tell a
  bundle that registered from one that did not. The symptom was a page
  reporting success with `loaded_components` empty and nothing anywhere saying
  why. The reason is now also answerable on demand, as many times as you like,
  and the JS bridge asks too — dropping the bundle it had registered on its
  side and putting the refusal in the console. Re-exporting it is optional: a
  host that does not is exactly as it was.

## [0.45.0] - 2026-09-01

### Fixed

- **A component nested inside another did not survive a reload.**
  `Snapshot.fields` was the UNTAGGED projection (`Value::to_json`), which walks
  by what a value happens to be rather than by what the schema declares: a
  field holding another component was stored as a plain object with no name on
  it, and came back as a Map, which is to say as nothing. What a person put in
  a guest's placeholder was lost on every reload while the guest around it came
  back fine.

  The projection is now `Value::to_component_json` — the TAGGED one, already
  what a saved page is written with — so the two finally agree, and
  `Snapshot::field_args` decodes it through an optional `src~`
  (`&ComponentSource`) that resolves the `$component` names in it.
  `Bundle::restore` and `@dhw.restore` take the same `src?` and thread it, and
  the universal host passes its own `UniversalUi`, which names the standard
  components and every loaded bundle.

  Two things fall out of doing it at the codec. A restore through the GUEST'S
  OWN BYTES now fills the placeholders too: they are host fields the guest was
  never told about, so they are not in its bytes, and only the projection
  beside them has them. And a component of the restoring bundle is deliberately
  NOT rebuilt host-side — that is a nested child the guest makes and owns, and
  building one here would hand the guest a second instance for the field.

  A session stored by an older host still restores: the snapshot names its own
  component, so a projection with no tag in it decodes exactly as it did.

## [0.44.0] - 2026-08-31

### Fixed

- **A `provide` inside an `@each` published the ROOT's address.** `@each`
  re-binds `it` to the item whether or not the body is a component, but the
  step recorded for the item was chosen off the body NODE, and only an
  `<x render-it>` directly under the loop earned an addressing one. The
  canonical `<div @each=".rows"><x render-it></x></div>` fell to a frame-only
  step, which resolves as the identity — so everything the item published
  claimed the address of the collection's owner, and because that path has no
  wire form the base written into `§Comp§` collapsed to `[]`, the root. A
  `<x render="*name">` below it resumed the whole app there, and every edit
  made inside it was silently dropped. The render still looked right: a value
  is published beside its path and rendering uses the value; only dispatch uses
  the path.

  The item step now comes from the iterated VALUE — `.rows` at `key` IS
  `rows[key]` — so the position moves with `it` for every body shape, not just
  the one spelling `<x render-each>` desugars to.

### Changed

- **A provide's path may be absent, and `LocatedValue.path` says so.** Before
  publishing, the render position is compacted and then CHECKED against the
  value actually being rendered; a position that cannot be written down as an
  address publishes no path at all. `*name` still reads such a value, and
  `<x render="*name">` renders it in place, entering no continuation frame —
  which is better than resuming at an address nobody verified. A constant
  `lookup` default reaches the same answer, and for the same reason.
  `render_path_text` now answers `None` rather than `"[]"`, since the empty
  path names the root.

- **An iteration directive on an `<x>` op is rejected, and the node is
  dropped.** `@each`, `@enrich-with`, and — outside the `<x render-each>` that
  consumes them — `@when` and `@loop-with` raise `LOOP_DIRECTIVE_ON_X_OP` (a
  new `@anode.ParseIssue` and `@lint.LintCode`) instead of the generic
  unknown-attribute warning that used to keep the site. An `<x>` op is one
  render site with no body to iterate, so dropping the directive quietly turned
  N renders into one — and `<x render-it @each=".rows">` without its loop
  renders the value that was to be iterated, which is the value already
  rendering. Write `<x render-each=".rows">`, or put the loop on a wrapper
  element around the `<x>`.

- **A render site that would re-enter the value already rendering stops
  there.** It leaves a `RECURSION AVOIDED` comment and no component boundary
  rather than descending until the stack runs out. The JS renderer has carried
  this guard all along; the port had not.

## [0.43.0] - 2026-08-31

### Changed

- **Component state is one member model, and the model is properties.** `.name`
  in a view resolves a declared property first and a state field second, so a
  field is an implicit private read/write property rather than a different kind
  of thing that happened to share the notation. An explicit property may derive
  its value, redirect a write, or both, and nothing downstream of `.name` can
  tell which one it read.

  Visibility became the property's own word. `pub` opts one into the interface a
  parent, host, storybook or property fuzzer may drive; everything else is
  private to the component's own views, and a protocol member is public by
  definition — so a protocol binding may expose a private local property under
  the protocol's name. Public fuzzing draws writes from `pub` properties only.

  What that costs a file already written:

  - A zero-argument `compute` becomes `get name` beside a `name: T { get }`
    declaration, and `$` in a view now means only a call with arguments. A
    derivation that reads `@value`, an enriched binding or a `*lookup` stays a
    `compute`: its answer belongs to one render position, not to the component
    as a member anyone can read.
  - Inside a script body, `state.name` reads the raw stored field past a
    same-named property.
  - `@bind` targets a member rather than a field, so it accepts a writable
    property and refuses a read-only one at generation.
  - Manifest v3. Every property carries visibility (`DynPropertyDef.public_`),
    and `supported_manifest_version` is 3.

  The generated per-field mutator names (`setCount`, `pushInItems`, …) survive
  only as an implementation table under `Obj::set_member` /
  `mutate_member` and `Transactor::set_member` / `mutate_member`; source,
  manifests and the host interface never spell them again. `member_at` is
  the private-capable read, `Stack::lookup_member` its value-position half, and
  `StateDef::property` / `member_ty` are how a generator asks what `.name` means
  here.

- **Dynamic `*name` rendering is a located continuation, not a portal.** A
  provider now publishes its value together with its absolute path, and a
  consumer renders that value by pushing a render-path frame. Dispatch walks
  the active frame upward and, at its top, pops directly back to the visual
  caller. Nested providers therefore shadow by live render ancestry without
  producer-qualified targets or teleport markers.

  Lowercase continuation names may also be registered lexically with
  `ModuleDef(paths=...)` or `ComponentStack::register_paths`. This makes
  session-, theme-, and host-owned resume points available in their natural
  registration scope; the application root need not publish them or exist
  solely as a wrapper. The normal lookup order remains `dyn lex`, so a nearer
  runtime provider wins before a lexical resume path.

- **A gallery page exports six entry points, not five.** `on_file_text` is the
  Trace tab's file read, answered asynchronously by the page. `tutuca
  new-storybook` scaffolds it; an existing page adds the forward, the export,
  and the `tfiles` namespace in its loader.

- **`Player.trace` and `Player.at` are methods rather than fields.** Both are
  the driver's now, and two copies of a position is one copy too many.

### Added

- **An event attribute can write a property, with no message in between.**
  `@on.input=".query = e.value"`, `.open = not .open`, `.items.removeAt @key`,
  `.tags.toggle @value`, `.selection = default` — synchronous property
  transitions that dispatch nothing, so the generated input enum stops gaining a
  case for a state edit that was never anything more than one. A leading `$` is
  refused in an event position; that sigil is a call with arguments.

  The field's kind decides the verbs — `push` / `insertAt` / `setAt` /
  `deleteAt` / `removeAt` on a list, `setAt` / `removeAt` on a map, `add` /
  `toggle` / `remove` on a set, assignment and `= default` on everything — and
  `viewgen` refuses the rest before anything runs, with `InvalidPropertyAction`:
  an unknown member, a read-only property, a collection verb applied through an
  explicit property (assign its complete value instead), or a verb the field's
  type cannot answer. `= default` writes the declared type's zero, which for a
  `T?` is `None` and not an empty string.

- **A recording can leave the tab and come back.** `trace/` could already write
  a recording as JSONL and read one back, and `trace/replay` could run one; what
  was missing was every step between. The storybook's Trace tab now downloads a
  recording as `.trace.jsonl`, loads one somebody else made, cuts one to the
  component the picker has been selecting since it was written, and replays it
  into the story on screen.

  The round trip is a `moon test`, which is the only reason to believe it:
  record in one gallery, download, mount a SECOND gallery sharing nothing but
  the text, load it there, replay, and hold the story's rendered state against
  what the first one produced. A round trip that only works while the recording
  is still in memory is not a round trip, it is a variable.

- **`files/` — handing the viewer a file, and reading one they chose.** A seam,
  an in-memory implementation, and `files/wasm` for the browser. The two
  directions are not alike and the trait says so: saving is synchronous and
  one-way, and reading is asynchronous and can fail several ways — so
  `read_text` takes a continuation rather than returning, because on wasm-gc a
  closure cannot cross into JS and the answer has to come back through an
  export.

  `files/wasm` brings its own `tfiles` import namespace through `instantiate`'s
  `makeExtra` hook rather than growing `tdom`. `tdom` is the namespace every
  tutuca page declares, so a function added there is a function every page's
  loader must supply — and a page carrying an older copy stops instantiating
  entirely. That has happened in this repo before. A page that never links the
  panel layer never mentions `tfiles`.

- **`@replay.Driver` — a recording fed into a transactor somebody else owns.**
  `Player` mounts its own app on the in-memory DOM, which is what `moon test`
  wants and what a browser cannot use: a gallery is ONE transactor with every
  story already mounted under it, and a component's view owns its subtree
  outright, so there is nowhere to put a second app — the panel's next render
  would destroy it, and the panel renders on every step.

  So the feeding moved out, with no app, no DOM and no mounting in it, and
  `Player` is now that plus "and I built the app myself". One thing is new:
  `base`, where the recording's root sits in the tree being fed. A recording cut
  to `.rows[0]` addresses its events relative to that, and the gallery calls the
  same component `.s3.rows[0]` — so `Place::under` puts back what `relocate`'s
  `strip_prefix` took off, and a test holds the two to being inverses.

  `verify` defaults to whether the aim is narrow enough for a comparison to
  mean anything: on under a base, off at the root of a tree that holds other
  things, where every dispatch the shell and the other stories make is
  indistinguishable from the app's.

- **`Transactor::set_intents`, and `intents()` beside it.** The pair
  `set_recorder` has had all along. It exists for one caller — a replay, which
  must answer an intent with what the host said last time rather than what it
  would say now — and it is swapped in around one push and one settle, never
  left installed. `Answers` hands out one walk's replies per ask, in order, so a
  recorded host left in place while anything else raises an intent spends the
  recording's answers on questions it was not answering, and the divergence that
  follows points nowhere useful.

- **`@replay.root_for`** — the three guards `mount` applies, on their own, for a
  rerun that does not mount. A version this build cannot read, a snapshot naming
  a component the scope cannot build, and a component whose fields have moved
  are each one sentence here and a mystery anywhere else.

- **`skill/tutuca/tracing.md`** — recording, saving, shortening and running a
  trace back, for a consumer building the same thing over their own components.

### Fixed

- **The Trace tab's tab strip moved the highlight and not the panes.** Which
  pane shows is computed by the host — it is the only thing that knows whether
  there is a recording behind one — so a click that only set the component's own
  `.tab` left the panes where they were. It now says so as well, and the host
  recomputes.

## [0.42.0] - 2026-08-30

### Added

- **`where value is one of .options`** — a scalar bounded by the contents of a
  sibling LIST, alongside the literal `is one of ["a", "b"]` it reads like.

  The shape the vocabulary could not state. `is member of .tags` wants a `Set`,
  and a select field's options are ORDERED, so they are an `Array`; `is index
  of .options` states the positional half, and what a select keeps is the
  option itself rather than its position. Twenty components in one corpus were
  carrying four to six `pred`s over the same field with no statement of the set
  anywhere, which is the state a `where` exists to replace.

  It reads backwards like every other relation: a generated write draws an
  element OF the list, so a run presses the values the component can take
  rather than spending itself on refusals it provoked. An empty list bounds
  nothing a draw could satisfy, so the generator falls back to the field's own
  — the same answer `is key of` gives for an empty map.

  Both doors enforce it: a write naming a value the list does not hold is
  turned down at the field, and shrinking the LIST out from under a value that
  was fine is caught after the transition.

## [0.41.5] - 2026-08-30

Three more from the same two migrations, all in the generated code.

### Fixed

- **A component-typed list payload forced its handler out of the script
  language.** `message { redraw(Array[ChatModelGroup]) }` bound raw, so
  assigning it to the field it came from was refused with "type is not known
  from the call sites" — and `Array[Any]` was refused the other way, because
  the field wants the element type. Both spellings produce the same runtime
  value: a list of component instances is `Array[@tutuca.Value]`, exactly as
  `Array[Any]` is, and there is nothing to decode. So the element type costs
  nothing at the handler now, which is the point of declaring one — 0.40 asks
  for typed collections, and this was the bill.

  A list of a declared RECORD is still refused, and honestly: that field holds
  decoded structs, and the decode loop is the thing this backend does not
  write.

- **A transition that reads no state warned in generated code.** On a one-field
  state the rebind is a whole record literal rather than `{ ..s, … }`, so a
  handler that only assigns never touched the parameter — `unused variable 's'`
  in a file nobody can edit. The parameter is `_s` when nothing reads it, the
  way the value bodies have always named theirs.

- **A doc comment above a section in a `handle`/`express` block** — carried over
  from 0.41.4's list, where it was described but landed in the same batch.

### Verified against the corpora

Both projects that reported the 0.41.x findings now build and pass on the
released package, from this repo:

- 320 components, 605 tests, `moon check` clean of warnings. The protocol
  migration that was blocked — 97 `implements Openable` with a canonical id —
  is green, and the seven ctrl-click/sibling failures are gone.
- 19 components across two packages, 442 tests over three targets, with the
  `invariant` calling its `pred`s rather than restating them.

## [0.41.4] - 2026-08-30

Four bugs found by two projects migrating a real corpus onto 0.41.x — 320
components in one, 19 in the other. Every one of them was silent.

### Fixed

- **A component slot declared `Component[X]?` stopped tracking its child.** The
  parent's fields map was updated and its STATE STRUCT was not, so the child's
  own view re-rendered while every `compute`, `loop_with` and `update` arm
  reading `s.pager` saw the child the parent was born with. The wrapper was not
  the cause: `s_fields` — the names a write re-decodes into the struct — was
  read off `encode(init)`, and a generated `encode` omits an option that is
  None. Seeded `None`, the field was absent from that list forever after.

  It comes from the schema now, which is where the question belongs: whether a
  field is part of the state type is a fact about the type, not about one value
  of it. Any option-typed field was affected; a component slot is where it
  showed, because a slot is the field whose successor arrives from elsewhere.

- **The other half of the protocol alias.** 0.41.1 taught the emitter to find a
  declared message by either spelling; the ARM it wrote still used the
  declaration spelling. So `receive Openable::setOpen(b)` compiled to
  `Receive("Openable::setOpen", …)` while `send`, `intent`, the codec and
  `receives=[…]` all used the canonical `id::member` — and the handler never
  ran. In a component with no `update~`, without a word. The arm now emits the
  runtime name, resolved in the one place that maps a written name to what the
  schema says it is.

- **An `invariant` that calls a `pred` generated MoonBit that does not
  compile.** The guard woven into a handler arm constructs a
  `@tutuca.CtxStack(ctx)` to call the pred with, and `CtxStack` was a plain
  `pub struct` — read-only outside `core`. `gen-views` said nothing and
  `moon check` failed afterwards, on advice the RENDER_ONLY diagnostic gives:
  it tells you to call the pred bare, and calling it bare is what produces the
  file. `pub(all)` now, and `demo/counterlib` carries the shape so `check`
  compiles it on every run.

- **A writable property drew arbitrary values of its type, ignoring the domain
  of the field it names.** `property { reading : String { get .view set .view } }`
  over `where view is one of ["main", "format"]` drew `"a/b"`, `"<script>"`,
  `"líne break"` — and the runtime declined every one, 16 of 40 steps spent
  proving the domain works while the two values that exercise the component
  were never drawn. It hit hardest on components whose surface is mostly
  properties, which is what 0.41.1's "empty Public API" hint pushes you toward.

  Two causes, both fixed: the property generator drew the property's TYPE and
  never looked at the backing field, and the field draw itself gave up whenever
  no state was in hand — which is every up-front draw — even for a domain like
  `is one of [...]` that needs nothing but itself to invert.

- **A doc comment above a section in a `handle`/`express` block was refused.**
  `/// what a parent may send` over `message { … }` is a sentence about the
  section, and the only place it reads is there; the parser wanted a keyword
  and reported "found a doc comment", sending an author to delete a comment
  that was in the right place.

## [0.41.3] - 2026-08-30

### Fixed

- **A `handle`/`express` block naming the component of a BARE `state` was
  dropped in silence.** The blocks were matched to a state declaration by raw
  name, and a bare `state { … }` has none — the file's single component is
  called whatever the caller says it is. So `handle Counter { message { inc,
  dec } }` beside `state { … }` declared a surface that nothing carried: no
  generated message type, nothing for a `send` to reach, and a Fuzz tab with
  nothing to draw.

  This is why 0.41.2's scaffold fix did nothing. The declaration was right and
  the parser discarded it, which is the same shape of bug as the two 0.41.1
  fixed: a name written one way, read another way, and the difference resolved
  by dropping something.

  A surface block that names no component in the file is now a **generation
  error** naming the nearest declared component. It used to be silence, which
  is the worst answer available for "you declared this and nothing has it".

## [0.41.2] - 2026-08-30

### Fixed

- **The scaffold's own demo component declared no message surface**, so a
  gallery written by `tutuca new-storybook` opened its Fuzz tab on the hint
  0.41.1 had just added — the first run of the first thing a new user builds,
  explaining why nothing could be generated. `Counter` declares
  `handle Counter { message { inc, dec } }` now, so the tab draws a script,
  and the block is there to be copied when a component of one's own is added.
  The `receive`s beside it are the implementations and the `@on.click`s are
  call sites; neither is a declaration, and the comment in the file says so.

## [0.41.1] - 2026-08-30

### Fixed

- **A protocol member declared under an alias tripped two rules that read its
  name.** A protocol's identity is its canonical id and a file imports it under
  a local alias, so `Openable::setOpen` and
  `tutuca.dev/std/Openable@1::setOpen` are the same member — the declaration
  spelling and the runtime spelling, different by design. Both readers treated
  the difference as a mistake:

  - `message-case` fired on every declared member, asking for the canonical
    spelling — which the declaration grammar cannot parse, since the qualifier
    there is an identifier and not a URL. It now compares the MEMBER halves,
    which is the casing question the rule is for, and suggests the fix under
    the file's own alias.
  - `receive Openable::setOpen(b)` found no declaration, so `b` had no type and
    the handler was refused out of the script language into MoonBit with a note
    asking for an annotation the block had already written. The emitter now
    matches a declared message by either spelling.

  Both vanished when the id string happened to equal the alias, which is what
  made this look like a naming preference rather than a bug.

- **The Fuzz tab's Play did nothing, and said nothing, when the source drew
  nothing.** A plan exists whenever the component declares a spec block, and
  that is a different question from whether the chosen source has any input in
  it: a component with state and rules but no `message` block and no writable
  property has an empty Public API. The panel only ever explained a MISSING
  plan, so an empty one showed a full set of controls that could not act.

  There are three states now, not two, and the middle one keeps the source
  switcher — switching is the thing to do about it. `Plan::has_inputs` is what
  the panel asks, and the opening panel derives a plan rather than assuming
  one, so the answer is right before anything is pressed.

- **`traffic-light` declared no message surface.** Its `receive nextLight` is a
  handler body, and view wiring is not a declaration either, so the story's
  public API was empty and the Fuzz tab drew an empty script. It declares
  `handle TrafficLight { message { nextLight } }` now. The same silence is
  waiting in most of the corpus, and the hint above is what says so.

- **The scaffold README `tutuca new-storybook` writes was a release behind.**
  0.41.0 embedded a copy showing `panels=@sbui.Panels::none()` — an API the
  same release renamed — because editing `storybook/template/` and forgetting
  to re-embed leaves a file that compiles and that
  `check-storybook-template` does not read: that check drives the SCAFFOLD, not
  the embed it came from. The scaffolded project itself was correct.

  `storybook-template-embed` now snapshots, regenerates and diffs, the way
  `skill-embed` has since the same class of miss shipped a broken skill, and
  `ci` runs it.

## [0.41.0] - 2026-08-30

### Added

- **The storybook ships.** `storybook` (the model), `storybook/ui` (the
  gallery), `storybook/ui/wasm` (the browser host) and `storybook/inspector`
  (the panels) are in the tarball, so a project can build a gallery of ITS OWN
  components: a sidebar of stories, a live pane each, and Instance / Trace /
  Fuzz / Spec / Raw beside them. `moon.mod` excludes `storybook/examples`
  instead of `storybook` — this repo's 52 demos and the fixtures the lint and
  view sweeps run over stay behind, because a story set is editorial content
  about one project's components and not a library.

- **A story is an example on a `ModuleDef`.** `stories_of_module` /
  `stories_of_modules` project one `Story` per declared `ExampleDef` — id, title,
  root, args and view all derived — so a consumer registers modules rather than
  maintaining a list, and the same example a story shows is the one
  `@harness.mount_example` mounts in a test. `sections_of` takes the sidebar
  order as an argument; `Story` is `pub(all)`, so `init`, `renderable`,
  `section` and `description` — the four things no `ExampleDef` field implies —
  are a `.map` with a record update.

  What made this possible was moving the corpus the other way: `stories()`, the
  52-arm `section_for`, the 52-arm `meta_for` and the `lint-errors` special case
  now live in `storybook/examples`, and the gallery's own integration test with
  them. A shipping package may not test-import an excluded one — a `for "test"`
  block survives `moon publish` — and `scripts/check-publish-graph.mjs` in `ci`
  now says so out loud instead of leaving it to luck.

- **`tutuca new-storybook <name>`** scaffolds the part a library cannot supply:
  a page package with the wasm-gc `link.exports` list (per-package `link`
  configuration cannot come from a dependency), an `index.html`, a `build.mjs`,
  and a demo component to delete. Embedded in the binary like `new-guest`'s
  tree, and its demo view is in the repo's `gen-views` sweep, so the generated
  module a stranger receives is the one this generator produces.
  `examples/storybook-gallery` is that scaffold committed unedited, and proves
  after a release that it still builds against the published package.

- **`themes~` and `panels~` on `mount`.** The 35 margaui palette names were
  hardcoded; they are now the default value of an argument.

- **The panels are a package, and the gallery links none of them by default.**
  A tab is a `PanelDef` — a key, a label, a per-story field prefix, a closure
  that builds its value, and `live`/`keep`/`with_story` — and a `PanelSet`
  bundles those with the fields they own, the components they are drawn with,
  the intents they answer and an `attach` the shell calls with the mounted app.
  `storybook/ui` therefore imports no inspector, no recorder, no fuzz driver and
  no renderer internals; `storybook/ui/panels` (with `storybook/ui/panels/wasm`
  for the browser effects) supplies the standard five, and the trace and fuzz
  SESSIONS moved there with them, since they were always host code.

  Not a tidying: it is what the tabs cost. The scaffolded gallery is 3.1 MB of
  wasm with them and 1.25 MB without (`--release`, before wasm-opt), and a page
  that wants stories and nothing else now pays for stories and nothing else. It
  also makes a project's own tab — a diff against a golden render, a props
  table — a `PanelDef` rather than a fork.

- **A story renders under the view its example named.** `ExampleDef.view` was
  read by `@harness.mount_example` and dropped on the floor by the gallery,
  which always resolved the component's default view. The Story and Fuzz panes
  (and focus mode) now push it.

### Changed

- **`tutuca storybook` serves any bundle, not one filename.** A bundle is a
  directory with an `index.html` and a `.wasm` beside it, rather than one named
  `storybook_wasm.wasm` — the name this repo's demo host happens to compile to,
  which meant the command could not serve a gallery built by the project it was
  written for.

- **`demo/storybook_wasm` is ~45 lines**: an export list and this repo's story
  set. The URL and theme services, the query-string codec, the fuzz frame, the
  event bridge and the margaui compile moved into `storybook/ui/wasm`, where a
  downstream page gets them too. `theme_base_url` is an argument there rather
  than a hardcoded GitHub Pages URL.

### Fixed

- **`mount` says when a story cannot render.** A `root` naming no component in
  the story's module, and an arg holding a component instance the story's scope
  cannot resolve, both produced a silently blank pane; both now warn through
  `@tutuca.warn`. The second is the one hazard a hand-written `Story` list has
  and a projected one cannot.

- **`Story.renderable`'s documentation described a Lint panel** that does not
  exist — lint is a compile-time concern and the gallery has five tabs beside
  Story, none of them lint. Same pass over `demo/storybook_wasm/moon.pkg`'s
  claim about a `mount()` lint callback, and `cli/version.mbt`'s claim that
  `VERSION` tracks `moon.mod` (it tracks the CLI's surface; the new
  `MODULE_VERSION` is the module's, checked against `moon.mod` in `ci`).

## [0.40.0] - 2026-08-28

### Added

- **A message payload is decoded at the type it declares.** Declaring one used
  to buy nothing: every composite payload was erased to `@tutuca.Value`, so
  `loadDataOk(Array[Row])` and `loadDataOk(Any)` generated the same code and
  every handler unpacked the shape by hand. The decode is now the state codec's
  own — one rule for a payload and a field of the same declared type — so an
  arm receives an `Array[BoardRow]`, a `Map[String, String]`, a `struct`, an
  `enum`, a `T?` or a tuple. `Any` and `Component` are unchanged, because
  `@tutuca.Value` is what they declare.

  The objection this reverses is worth keeping: a payload ARRIVES as
  `Array[@tutuca.Value]`, so typing one meant converting, and the only
  converter to hand was a JSON round trip. `dec_stmts` and `to_value_src` are
  not that — they are the halves the state codec was already written from.

  **Payload types are now load-bearing.** A schema that declared a shape it
  does not actually send was previously free; it now decodes to nothing.

- **`BAD_PAYLOAD`, on the refusal channel.** `Unknown` answered two different
  questions — nobody declares this name, and this name is declared here and was
  handed the wrong shape — and the second is a bug in the sender that was
  indistinguishable from silence. The decode's ANSWER is unchanged: the case
  still falls into `Unknown`, uncoerced. It is now also SAID, carrying the
  argument list that did not fit where a refusal normally carries the rejected
  state — because no arm ran, and the arguments are the thing to go and look
  at. Off until a host asks, like every other refusal.

- **A guest's field domains reach the host.** `where` clauses travel in the
  manifest as `FieldDomain`s, and `first_broken_domain` is the single function
  the runtime's post-transition door, the guard `gen-views` weaves into a
  generated arm, and the dynamic-component host all ask. A domain the woven
  guard admitted and the runtime then refused would be a component abandoning a
  transition its own compiled code called fine.

### Changed

- **A nullable field is writable from a `<script type="tutuca/script">`
  block.** It could not be — not `null`, and not a present value either — so
  every `T?` field pushed its own handlers out to MoonBit, and `Any`, which a
  block CAN write, became the spelling people reached for instead. Both halves
  are decided by the PLACE: `.sel = 'k'` compiles to `Some("k")` and
  `.sel = null` to `None`. Widening stays honest — `Some(…)` wraps only a
  conversion that was already legal, so `Any` into a `String?` is still
  refused.

  There is still no `clearX`, and there does not need to be: `resetX` writes
  the field's zero, and a nullable field's zero is `None`.

- **The corpus declares what its collections hold.** ~90 `Array[Any]` and
  `Map[String, Any]` fields across the storybook, the inspector, the playground
  examples, the dyncomp UI and the tutucard examples became `Array[Item]`,
  `Array[Component[Entry]]`, `Array[String]`, `Map[String, DseEntry]`,
  `Component?`, `Int?` and one `struct`. A field type may name a SIBLING
  `state`, and naming it is what lets the checker read an `@each` body against
  that component's own schema; `Array[Component]` over a mixed list is not
  checked but does change fuzzing, since `@arb` draws `Any` as arbitrary junk
  and a component slot as its zero. Three `Any`s remain, and each is one on
  purpose.

### Fixed

- **A nullable field under a relation never drew its own empty.**
  `domain_holds` admits `Null` under every relation — each guards on the shape
  it reads — but a domain-derived draw only produces the shape it inverted, so
  `sel : String?` under `where sel is key of .byKey` was never generated empty:
  the one state the `?` exists for. Fixed once in `field_gen` rather than per
  relation, at the same 1:2 ratio as the unconstrained `TyOption` draw, so
  adding a `where` does not quietly change how often a field is empty.

  `or none` is not the fix and was never about optionality: it admits SENTINEL
  INTEGERS — `-1`, or `0` over an empty list — which is a convention no type
  can state, and why only `index of` has it.

## [0.39.2] - 2026-08-28

### Fixed

- **A component declaring a bare `state { … }` had no fuzz plan.**
  `Plan::of_component` parsed the block without handing over the component's
  name. A bare state belongs to the file's single unnamed component, and the
  parser can only give it a name if the caller supplies one — the caller being
  the only thing that knows what that component is called. Without it the block
  parsed to a `StateDef` named `""`, matched nothing, and `Plan::of_component`
  answered `None`: every bare-state component in the corpus (counter, dnd,
  file-picker, list-iteration, nested-state, request, web-component,
  composability, loader-bar) reported "declares no spec block" while declaring
  one.

  The name is part of the parse rather than a filter applied after it, which is
  why passing it late could not have worked.

### Added

- **The storybook shows a story the block it was declared in.** Repo-only —
  `storybook/` is excluded from the tarball — but it is what made the bug above
  visible. The spec block became load-bearing at run time when the Fuzz tab
  started deriving a component's generators, and its whole oracle, from
  `Component::spec`; "what is this run held to" stopped being a question you
  answer by opening the `.html`. **Spec** re-parses the block and renders what
  it declares — fields in the author's own type spelling, messages with their
  payloads, `pred`/`invariant` rules with the expression and the sentence
  written for the moment they fail. **Raw** shows the same block verbatim: the
  parse is what the runtime reads, the source is what the author edits, and a
  reader reconciling a surprising verdict wants both.

## [0.39.1] - 2026-08-28

### Fixed

- **A fuzz run sent generated names that could not do anything.**
  `@arb.mutator_dispatch_of` took its names from
  `@component.schema_mutators` — deliberately, so it could not invent a name
  the runtime lacks — but that table is every generated CALLABLE, and two of
  its shapes only read. `<field>Len` and `hasIn<Field>` answer a scalar rather
  than a successor, so they are `$`-callables a view writes as `$tabLen`, not
  messages: the receive path takes a generated entry's result only when it is
  `Obj(_)`, and a reader falls through to `Unhandled`.

  So a run spent a share of every script on dispatches that could not move
  anything, and reported each as a refusal badge shaped exactly like a
  finding — noise that reads as a result. On the `tabbed-ui` story that is
  `tabLen`, drawn beside `setTab`.

  `@component.schema_writers` is the table minus those, and the split is
  recorded where the names are installed rather than recomputed by a second
  walk of the same fields: a second walk is a second opinion about which names
  those are, and the whole value of the list is that it cannot disagree with
  the table. `schema_mutators` is unchanged — the receive path and the
  `$`-callable lookup both still want all of it.

  The join guarded against names the runtime does not have. It did not guard
  against names it has that cannot be sent, which is the other half of the same
  question.

## [0.39.0] - 2026-08-28

### Added

- **An execution trace, as an artifact.** The transactor already had an
  observer channel, but a subscription is not something you can keep: it cannot
  be saved, handed to someone else, or run again. `trace/` is the format — the
  state a component tree started in plus every message and intent that crossed
  the runtime afterwards — with three shortening operations (`prefix`,
  `rebase`, `relocate`) and a compactor. Pure and target-agnostic: a `Trace` in,
  a `Trace` out, never a DOM and never an app, which is what lets those be
  `moon test`-able on every backend and lets the native CLI perform two of them
  with no component runtime at all.

  `trace/replay` is what proves the format. A recording that cannot be run back
  is a log; until the same events reach the same state, nothing built on it is
  worth having. Three recorders fill one: whole (`TraceRecorder`), scoped to a
  subtree (`ScopedRecorder`), and a bounded ring (`RingRecorder`).

- **A component carries the spec block it was declared in.** `gen-views` emits
  the `<script type="tutuca/spec">` source into the generated module (doc
  comments stripped) and `Component::spec` holds it, so a generator can be
  derived at runtime, on any backend, from the declaration the compiled arms
  came from. The `SchemaInfo` beside it is that block's PROJECTION, and the
  projection is lossy exactly where a generator needs it: a rule arrives as a
  name with no body, a message as a name with no payload.

- **`testing/fuzz` — the spec block's generators, run against a live
  component.** `Plan::of_component` → `script(seed~, steps~)` → `step` / `run`
  → `shrink`, generic over the node type so `moon test` and a browser host
  drive identically. A run is addressed entirely by (component, source, seed,
  steps), which is what makes one reproducible — and worth pointing a profiler
  at twice.

  Three things the runtime decided about its shape. A compiled invariant is
  already ENFORCED — the transition is abandoned and a `Refusal` raised — so
  `Outcome::Broke` means the opposite of the obvious: a rule declared and
  enforced by nothing. The differential check is preconditions-only, because a
  precondition is asked against the state a dispatch arrived at while an
  invariant is asked against the proposed successor, which was abandoned and
  which nothing ever sees. And `settle()` runs INSIDE the refusal capture,
  because a contract is checked as the transaction commits.

- **The storybook gets a Trace tab and a Fuzz tab.** The Trace tab records the
  gallery, whole or cut to one example, with selection mode to narrow a
  recording to the component under a click. The Fuzz tab derives generators
  from the story's own spec block and drives them at the instance on screen —
  rendering the story ABOVE the panel, because a run you cannot watch is the
  headless run with extra steps.

  Every run mode steps on the animation frame rather than inside the click that
  asked for it, and that is a correctness requirement: a refusal is held for
  the length of a dispatch and only the first escapes, so a run driven from
  inside the button's own chain shows an empty refusal column and a green
  verdict — indistinguishable from a component with no invariant at all.
  Performance stays the browser's to measure; the host brackets each dispatch
  with `performance.mark`/`measure` so DevTools' Timings track names them, and
  `storybook/ui` takes the two browser effects as a record rather than reaching
  for the FFI itself.

### Fixed

- **`gen-tailwind-css` / `gen-margaui-css` refused every view file using
  `@bind`.** The class collector built its views through `build_views`, which
  hardcoded "this file has no schema" — and `@bind` reads the field's type to
  pick its coercion, so a view `gen-views` compiled without complaint came back
  from the CSS pass as ``view "main": `@bind` needs a
  `<script type="tutuca/spec">` schema``, about the block sitting at the top of
  the file. `build_views` and `view_surface` now take the schema, the pairing
  rule that finds it lives on `ViewFile::state_of` so the generator and the CSS
  pass cannot read one file two ways, and `collect_view_classes` passes it.

  Under `watch --margaui-css` this was silent as well as wrong: the loop
  suppressed a view-gen failure from the CSS pass on the grounds that the
  regenerate pass had already printed it, which stopped being true the moment
  the two passes disagreed. It now suppresses a message only for a file it
  actually printed one for.

- **A script parameter could shadow the state it was being written into.**
  `receive setStatus(s) { .status = s }` emitted `let s = { ..s, status: s }` —
  the argument standing where the state should have been, in a generated module
  `moonc` then refused, out of a block `gen-views` reported nothing about.
  Author names and emitter names shared one namespace, and the emitter's
  namespace has no bound: `v1`, `cur0` and `d0` come off counters, so no
  reserved-name list could have closed it. Author-chosen locals are now spelled
  with a trailing `_` — injective, and disjoint from everything this backend
  generates. Generated code reads `let s = { ..s, status: s_ }`; nothing about
  a block's own spelling changes.

## [0.38.0] - 2026-08-27

### Added

- **Property-test generators derived from the spec block, with no code
  generation.** `derive(Arbitrary)` has nothing to derive over here: a
  component's shape is not a MoonBit type, it is a
  `<script type="tutuca/spec">` block. So `statedef/arb` derives the generators
  from the parsed `StateDef` at test time, and it is the randomized twin of
  `statedef/info` function for function — `value_of` walks the `StateTy` tree
  where `zero_of` walks it, `state_of` mirrors `zero_value`, `dispatch_of`
  reads `MsgDef.payload`, and `mutator_dispatch_of` takes its NAMES from
  `@component.schema_mutators` so it cannot drift from the table the runtime
  installs.

  `MsgDef.payload` is why the seam is the DECLARATION rather than a mounted
  component: the runtime `SchemaInfo` carries `receives` and `intents` as bare
  name lists with the payload types dropped, so a generator built by reflecting
  off an instance could name a message but never call it correctly.

- **`rules_of` — a `pred` or an `invariant`, evaluated rather than compiled.** A
  rule is ONE expression with no arguments (the spec block refuses a
  parameterised one by name, which is exactly what makes this possible), so
  `@tscript.parse_bool` lowers it to a `@core.Val` and `Val::eval` answers it
  over any state. An invariant is then both a FILTER on a generator and a
  PROPERTY a driven component is held to, and neither needs a backend.

  The bound is pinned rather than described: `Val` is what a SLOT holds, so the
  slot vocabulary is what lowers. There is no arithmetic, and
  `invariant conserved { (.here + .there) is .total }` lands in
  `Rules::unlowerable` carrying the grammar's own sentence instead of being
  silently treated as satisfied. Name the sum with a `compute` and compare
  against `$name`.

- **A differential test between the two readings of a contract**
  (`storybook/examples/svg_more_property_test.mbt`). `BarChart` declares two
  `pred`s used as preconditions and an `invariant`. The suite asks each
  precondition through `Val::eval` and checks the answer against the `Refusal`
  the `guard` that `gen-views` compiled from the same source line actually
  raised — two readings of one declaration that have to agree. A hand-written
  test cannot make that claim, because the two sides only diverge on the states
  nobody thought to write down.

  Beside it, the property no hand-written scene reaches: no generated mutator,
  from any reachable state, drives the chart through `neverEmpty`.
  `setValues []` is a legal dispatch that nothing in `svg_more.html` can
  produce — no button sends it, and both handlers guard against emptiness — but
  the runtime installs it for every declared field, so a page, a parent or a
  host can.

- `@component.Dispatch` derives `Eq` and `Debug`. A generated message sequence
  that breaks a component is the counterexample, and one that cannot be printed
  leaves the reader with "a property failed".

### Fixed

- **`handle` and `express` were reserved field names inside a `state` body.**
  `state BskyPost { handle : String }` — the obvious spelling for a Bluesky or
  Mastodon account name — failed with "expected `{` opening the handle
  section", because that arm matched on the WORD alone while every other
  section in the same loop guards on the word followed by a brace
  (`statedef/parse.mbt`). So `view : String` and `provide : String` were fields
  and `handle : String` was not, which is a distinction nothing ever meant to
  draw. Guarded now, and a `handle` field may sit beside a `handle { … }`
  section in one body.

  Present since 0.35.0, where `handle` / `express` became in-state sections —
  not a 0.37.0 regression, though 0.37.0 is the first release to say so.
  Adding a section should never take a name away from an author, and this arm
  was the one place that did.

## [0.37.0] - 2026-08-27

### BREAKING — the rule layer moved, and the block was renamed

- **`<script type="tutuca/state">` is now `<script type="tutuca/spec">`.** The
  old name still parses and `gen-views` reports it once per file, because a card
  in the field is one file someone else's page loads and breaking every one of
  them to rename a string is a cost the rename does not earn. Rename the `type=`
  and nothing else changes. A file carrying one of each spelling is two blocks,
  which is the answer two `tutuca/spec` blocks already got.

  The block outgrew the word. It held the fields, yes, but also the named types,
  the `handle`/`express` surfaces, the protocols and the `provide`/`lookup`
  wiring — and now the rules. "State" named one section of it. `spec` is the
  same promise `spec.mbt` makes one directory down: this is the declared
  contract, and the implementation is elsewhere.

- **`pred` and `invariant` are declared in the spec block, inside the `state`
  body they are about.** `script_spec.mbt` had already argued half of it:
  "`requires` and `ensures` attach BY NAME because what they say is local; an
  invariant's attachment point is the component, so the component's top level is
  where it goes." The component's top level is the other block. And a `pred` is
  the same construct with a different asker — one expression, no statements, no
  effects, no arguments — so it went with it.

  What this buys is the reading. A spec block now answers what a component IS,
  what it OBSERVES and what it PROMISES without opening a handler; the script
  block answers what it does. `requires` / `ensures` stay on the handler header,
  because what they say is local, and they still take a NAME — the rule those
  names reach is just up in the spec block now.

  Two `pred`s cannot move, and the boundary is the point: one that takes an
  argument (`pred containsText(q)`), and one that reads a render binding
  (`pred matches { contains (str @value) .needle }`). Neither is a rule about
  the component — they are filters about one row — so they stay in the script
  block beside the other render-time callables. A parameterised rule in the spec
  block is refused by name, with where it belongs.

  The old spelling still parses for one release. A rule declared in BOTH blocks
  is reported as `RULE_IN_BOTH` and the script block's copy is what runs, so
  moving one is deleting the old copy and nothing changes until you do.

### Added

- **An invariant now covers every dispatch, not just the ones the block wrote.**
  It used to be woven into script-declared arms and nowhere else — the 0.32.0
  entry said so outright: "it covers what the BLOCK declares, not the generated
  mutators a component answers by default." The names now ride in `SchemaInfo`,
  so `component()` asks them after every successor is built, and three paths are
  covered where one was:

  | dispatch | asked | effects if it fails |
  | --- | --- | --- |
  | a handler the script block declares | inline, before the effect queue flushes | never fire |
  | a generated mutator (`setHere`, `pushInItems`, …) | after the successor is built | there are none |
  | a hand-written MoonBit `update~` arm | after the successor is built | **may already have fired** |

  The third row is written down rather than papered over: the state is rolled
  back, the effects are not. Only the first carries the rule's `format`
  sentence, because a `format` is compiled beside the rule at the moment it
  fails and there is no such moment on the other two — they report the rule's
  NAME and the state that was rejected, which is what nothing could reach at all
  before.

- **`Init => Inv`, at build time.** `gen-views` writes a test into the generated
  module asserting that every `tutuca/init` fixture keeps every declared
  invariant. A rule that does not hold in the state a component starts in is
  broken before anything happens and every transition after it is refused, which
  makes it the one check worth making before the component runs.

  A generated test and not a static evaluation, which is the whole trick: the
  block interpreter was removed once the two compilers covered what it did, and
  a constant folder written to decide these would be a THIRD implementation of
  the expression semantics — the one place a rule could quietly mean something
  other than what it means at runtime. The invariant is already compiled into
  the module; calling it is exact by construction.

  The DECLARED fixtures, and not the schema's zero. A wrapper is normally called
  with `init~`, which the generator cannot see, so asserting over all-zeros
  would fail components that work — the shape of a check people turn off.

### Fixed

- **A card would not let a view filter with an `invariant`.** `@when="conserved"`
  compiled a body with the loop's three parameters and then left the name out of
  the manifest's `whens`, so the host had nothing to route to. The MoonBit
  backend folds an invariant into the when bucket the way it folds a `pred`, and
  the two now agree — which they must, since a rule kept differently by two
  backends is two answers to one question.

## [0.35.0] - 2026-08-27

### Added

- **String-identified component protocols.** State blocks can declare or import
  protocols, implement their handled and expressed messages/intents, semantic
  views, typed properties, and namespaced `provide`/`lookup` values, and use
  protocols as component-slot constraints. Static validation reports strict or
  gradual conformance; deferred runtime failures are structured notices with
  graceful UI-preserving fallbacks. Dynamic manifest API 9 carries the same
  protocol metadata.

### Changed

- **Component communication declarations are now `handle` and `express`.**
  The former is the inbound surface and the latter its outbound dual. Quoted
  effect names are explicitly raw, unquoted names use the component's implicit
  protocol, and `Protocol::member` uses the imported protocol's canonical id.
  The old top-level `receive` and `intent` state declarations have been removed
  without a compatibility parser.

- **External URLs survive, reframed: a host policy allowance rather than a
  manifest declaration.** `Policy.allows_external_urls : Bool` plus
  `Policy.external_origins`, set together by
  `Policy::allowing_external_urls(origins)` (an empty list means any `https`
  origin) and by `with_config` when a bound config variable is an origin —
  binding an origin is allowing it. Untrusted views still pin `<img src>` /
  `<a href>` to a literal origin the policy allows; a guest declares nothing,
  because the host's policy is the single source of what a view may reach.
  The refusal now reads "this host does not allow external URLs in views".

### Removed

- **Capabilities are gone from dynamic components; host↔guest communication is
  intents and messages, full stop.** The `Capability` enum (`cap-clock` /
  `cap-random` / `cap-timer` / `cap-external-urls`), `CapabilityReq`, the
  manifest `"capabilities"` key, `Policy.grants` and `check_capabilities` are
  all removed, along with the bridge's per-grant import gate. `interface env`
  (`now-ms`, `tz-offset-min`, `locale`, `random-u64`, `new-id`) and
  `control.after` are removed from the WIT contract (`tutuca:component@0.10.0`,
  version unchanged) — the world imports only `values`, `control`, `config`
  and `tables`, so a guest has no clock and no entropy at all. A fact it
  cannot compute for itself it asks the host for over an intent: the host
  registers an `IntentFn`, the guest calls `control.intent`, and the answer
  arrives as an ordinary message (the dice example's `roll`, answered with
  `rollOk` / `rollFailed`, is the worked version). That puts the host in the
  loop per question rather than per grant, and removes the one manifest field
  whose meaning was a promise about the future. **Breaking** for any bundle
  whose manifest carries a `"capabilities"` key or whose code imported `env`.

## [0.34.0] - 2026-08-26

### Added

- **`@dhw.guest_for` — a loaded bundle's guest and manifest, so a page can
  register that module again.** A host could reach an instantiated module and
  could not TEST it: `tutucard/drive` mounts a component on an in-memory DOM
  with one fresh `ComponentStack` per scene, which means registering the module
  again, and registering takes a `&Guest` and a `DynManifest` — neither of which
  this bridge published. `WasmGuest` is read-only outside the package and the
  bundle table is private, so there was no way to assemble the pair.

  The guest handed back is a NEW `WasmGuest` over the same instantiated module,
  not the one the bridge registered. That is the point rather than an
  implementation detail: a guest carries the bundle it was last registered as so
  a child token wraps through the right one, and a driver rebinds that per
  scene. Handing back the live guest would leave a page's own drawn instance
  wrapping through whichever scene ran last — a mounted component quietly
  breaking because something tested it.

## [0.33.0] - 2026-08-25

### Added

- **`@dhw.load_bytes` — a bundle a page BUILT, without the round trip through a
  URL.** There were two ways into the dynamic-component registry and both named
  a bundle the page did not have: a URL to fetch, or a file somebody dropped
  (whose ids come only out of a DOM drop event). A page that GENERATES bundles
  had them in hand and no way to say so, so it had to stage bytes it was
  already holding behind an object URL, carry the URL through wasm and back,
  fetch a blob that never left the process, and then revoke the URL in the one
  window that is neither too early (racing the load) nor too late (never).

  `registerArchive(bytes)` in `dyncomp/host/wasm/loader.mjs` holds the bytes and
  answers an id; `@dhw.load_bytes(path, id)` loads it, with the same completion
  contract as the other two. The id is consumed by the load — one id, one load.
  A `Uint8Array` cannot cross into wasm-gc, which is why this is an id rather
  than an argument, and why it is the same shape a drop already uses.

### Changed

- **Both load completions carry the load id, so a failure says WHOSE it is.**
  `load_url` / `load_dropped` / `load_bytes` return a load id that never came
  back. `dyncompLoaded` named its module, but `dyncompError` carried only a
  reason — and a reason on its own does not identify a load, so a host with two
  in flight could not tell which one failed, or answer the call that started it.

  The receives are now `dyncompLoaded(module-name, load-id)` and
  `dyncompError(reason, load-id)`, and `dyncomp/shell`'s `LoaderEvent` carries
  the id on `Started` too — the one moment a host knows both the id and what it
  asked for. **Breaking** for any host that declares these receives itself.

### Fixed

- **A resumed session no longer overwrites itself when a bundle fails to load.**
  The universal host counted in-flight loads and restored the saved page when
  the count reached zero — but only on success. A load that FAILED decremented
  the count and restored nothing, which is worse than it sounds: the same
  counter gates `save_session`, so the page went on to write its empty self
  over the session it was trying to restore. It now retires loads by id, and
  the last one restores whether it succeeded or failed: restoring without that
  bundle loses the components it owned and keeps everything else.

  Retiring by id also means a bundle dropped WHILE a resume is running no
  longer retires a slot the resume was waiting on.

- **A finished load's notify path is forgotten even with no app mounted.**
  `notify` returned before removing the entry, keeping the path alive for the
  life of the page.

## [0.32.0] - 2026-08-25

### Fixed

- **A card's views are checked against its own state block.** A card is one
  file holding a schema, a block and the templates, and it was checked as if
  the templates were somewhere else: `tutucard/wasm` handed the block checker a
  surface saying `knows_views: false` — "I have no views" — while the views sat
  in the same string it had just split. Three rules that already existed never
  fired for a card, and the view checks never ran at all:

  ```html
  <button @on.click="noSuchMessage">a</button>   <!-- NO_VIEW_HANDLER -->
  <button @on.click="bump 1 2 3">b</button>      <!-- ARITY -->
  <output @text=".noSuchField"></output>         <!-- UNKNOWN_STATE_FIELD -->
  ```

  All three now report, with a position in the file. A MoonBit component was
  never exposed this way — its view handler names become a generated `Input`
  enum whose unanswered variants break `update`'s `match` — which is why the
  gap survived: the language's other backend has a type system standing where
  the card had nothing.

  `viewgen.check_component_views` is the one call that answers both halves from
  one compile of the templates: it checks them against the schema and returns
  the `@check.Surface` the block is then checked against. `gen-views` gets both
  as a side effect of emitting; a card compiles no views, so it needed the walk
  to be reachable on its own.

  **A view finding does not stop a card compiling.** `check_card` lists it —
  that is the reporting face, and a card with a wrong `.field` in a template
  still renders — while `compile` falls back to the surface it had before. The
  errors that DO stop a build are the block's own, which is what stopped one
  before.

  `@check.Surface` gained `open_senders`, because `knows_views` was answering
  two questions with one bit. A card is mounted by a host that dispatches a
  STRING, driven by scenes that `{"send": …}` it one, and shares a file with
  siblings that `sendAt` and `sendReply` — so `receive poke` naming no schema
  case is a message that arrives, not `NO_SUCH_MESSAGE`. A MoonBit component
  keeps the stricter rule, where the parent's dispatch is typed and the finding
  is true. (`tutucard/wasm/check.mbt`, `tutucard/wasm/compile.mbt`,
  `viewgen/check_state.mbt`, `viewgen/errors.mbt`, `tscript/check/`.)

- **A toolchain release no longer freezes the deployed site.** Every Pages
  deploy since 2026-08-23 failed, so <https://marianoguerra.github.io/tutuca-moonbit/>
  served a build that predates 0.29.0 — where `@show=".n < 15"` is not in the
  slot vocabulary, so every conditional in a card rendered unconditionally. The
  failure was `assemble.mjs`'s toolchain guard: it compares the installed
  `moonc` against `playground/build/toolchain.json` and CI installs `latest`,
  because `cli.moonbitlang.com` serves nothing else. Every toolchain release
  was a red build until somebody bumped the pin by hand.

  The pin is now the fast path rather than the rule. The rule — the worker must
  be built from the moonc that is installed — is checkable directly: npm drops
  SemVer build metadata (`npm view` says `0.1.202608243` for a package whose
  own `package.json` says `0.1.202608243+f8a486b6f`), so a candidate is checked
  by downloading it, newest same-day first. It fails only when npm publishes no
  worker for the installed moonc, and prints the `toolchain.json` edit that
  makes today's answer tomorrow's fast path rather than writing it — a build
  step that rewrites a pinned file leaves every CI run with a dirty tree and
  nobody deciding anything. (`playground/build/fetch-compiler.mjs`,
  `playground/build/assemble.mjs`, `playground/vendor/README.md`.)

- **`.mbti` and the generated guest template match their sources again.**
  `dyncomp/host`, the root facade and `cli/guest_template_gen.mbt` were left
  behind by 0.30.0's `call_method` signature change and the WIT edit beside it.
  Regenerated; no behavior change.

## [0.31.0] - 2026-08-25

### Changed

- **The CLI package is `cmd/tutuca`, so the installed binary is `tutuca`.**
  `moon install` names the binary after the package's last path segment, and
  the package was `cmd/main` — so `moon install marianoguerra/tutuca/cmd/main`
  landed a binary called **`main`** in `~/.moon/bin/`. Nothing on PATH answered
  to `tutuca`, every command in the docs and in the bundled skill was wrong for
  a reader who had just installed it, and the workaround was a hand-made
  symlink. The package is renamed; `moon install marianoguerra/tutuca/cmd/tutuca`
  now installs `tutuca`.

  Local invocations change with it: `moon run --target native cmd/tutuca -- …`,
  and the built binary is `_build/native/debug/build/cmd/tutuca/tutuca.exe`.
  `just` recipes already wrap these. The other `cmd/*` shells keep their names —
  they are dev tools, excluded from the tarball, and never installed.

  README.md and [skill/tutuca/cli.md](skill/tutuca/cli.md) gained the install
  command, which neither had.

## [0.30.0] - 2026-08-25

### Fixed

- **A card's `compute`, `pred`, `@when` or `enrich` reads `*name` for real.**
  The third copy of the defect 0.29.0 fixed for MoonBit components, and the
  worst-behaved of the three: the card backend compiled `control.lookup`
  correctly, the checker allowed it, and the value came back **nil** — with no
  diagnostic anywhere, while the same body in a MoonBit component worked. That
  gap widened the moment 0.29.0 made value bodies work, because a card author
  now reasonably expects parity.

  The host resolved a component's declared lookups only on the DISPATCH path
  (`Guest::dispatch` carried `bindings`, `Guest::call_method` did not), and
  `control.lookup` reads those and nothing else. It now resolves them for the
  RENDER position too, from `stack.lookup_dynamic` — which is what a `*name` in
  the card's own view reads, so a `*name` in its `pred` answers the same thing.
  `DynObj` implements `method_at` / `obj_callable_at` to get the stack the
  call is being made under; `member` / `obj_callable` still pass a
  `NullStack`, which is the honest answer for a `$compute` read off a bare
  `Value` outside a render.

  **No `apiVersion` bump, and no bundle needs rebuilding.** The guest's
  `callMethod(name, args)` is unchanged and `control.lookup` is a host-side
  import shim, so an existing bundle starts answering correctly as soon as it
  is loaded by this host. What did change is the `@dyncomp.Guest` trait:
  `call_method` takes `bindings`, like `dispatch` beside it.
  (`dyncomp/host/guest.mbt`, `dyncomp/host/dynobj.mbt`,
  `dyncomp/host/wasm/glue.mbt`, `dyncomp/host/wasm/loader.mjs`,
  `dyncomp/wit/tutuca-component.wit`.)

- **A refusal reported for two roles is one hint, not two.** A refusal is per
  name AND role, which is right for the decision — the same `pred` can compile
  as a `@when` and be refused as a method. But every `pred` is folded into the
  method bucket as well as its own, so a body refused for a reason that is not
  about the role produced two byte-identical lines. (`viewgen/emit.mbt`.)

## [0.29.0] - 2026-08-25

### Changed

- **A conditional slot takes the block's expression language.** `@show`,
  `@hide` and `@if.<attr>` were the one place a closed five-name predicate
  table stood in for a grammar: `equals? .kind 'a'` parsed and `not .open` did
  not, while a block body took `not`, `and`, `or`, `is` and the comparisons and
  refused `equals?`. One idea had two vocabularies and two grammars, and which
  applied depended on which side of a `<script>` tag you were on.

  They are now one language. A slot parses through
  `@tscript.parse_expr_source` — the block's own `parse_expr`, promoted out of
  the declaration parser it never depended on — and lowers to `@tutuca.Val`,
  so all of this is a slot value:

  ```html
  <div @show="not .open">…</div>
  <div @show="not (empty? .kind)">…</div>
  <div @show="(len .items) is 1">…</div>
  <div @show=".open and .ready">…</div>
  <div @show="(.n > 0) and .open">…</div>
  ```

  Including the grammar's rules, which are the block's: application is
  juxtaposition, parentheses are required wherever precedence would otherwise
  be implicit, and mixing operator families in one unparenthesized chain is a
  parse error naming the parentheses to add. `.n > 0 and .open` is refused and
  `(.n > 0) and .open` is what it asks for — the same answer a `pred` gets,
  with the same sentence.

  **The AST did not change.** An operator lowers to `Val::App`, which already
  carried its name as a string resolved at eval time, so `a and b and c` is
  `App("and", [App("and", [a, b]), c])` and every walker that recurses through
  `App(args~, ..)` — the statedef collector, the `UnknownStateField` checker,
  the method collector, the IR emitter — keeps working untouched. `.open` is
  still collected out of `not (empty? .open)`. That is what the
  `enum Pred` → table migration was for: *"the set can grow."*

  `core/value_builtin.mbt` is now the ONE vocabulary, and
  `tscript/script_builtin.mbt` re-exports it rather than restating it: the
  operators, the shape predicates, and the block's reading builtins (`len`,
  `has`, `contains`, `min`, `max`, `clamp`, `int`, `num`, `str`, `lower`,
  `upper`, `trim`) all resolve in both places against the same rows.

  `and` and `or` short-circuit in `Val::eval` ahead of the table, because a
  `Builtin`'s `apply` takes arguments that are ALREADY evaluated and the
  compiled backend emits `&&` / `||`. Without it the two backends would
  disagree about `and (truthy? .items) ($firstLabel)` on an empty list.

  Four things a body writes and a slot still cannot, each refused by name
  rather than by silence: a nested read, an `if` expression, arithmetic, and a
  bare parameter.

  `^macro` and `$$config` are **operands**, so `@hide="empty? ^label"`,
  `@show="not ^collapsed"` and `@show="$$origin is 'x'"` all say what they
  read. The grammar has a leaf for each and the substitution happens as the
  value is lowered, through the same two functions the single-token path calls
  — one meaning per sigil rather than two that resemble each other. A `^name`
  expansion is still required to be exactly one token, which is what makes an
  operand position safe: a single token cannot regroup the expression around
  it. And `from_macro` rides on the `Const` rather than on the shape above it,
  so an operator over one cannot lose the mark that decides whether a constant
  may pin a URL origin (`dyncomp/policy/external_url.mbt`).

  Inside a `<script>` block both are refused by name — `NO_MACRO_FRAME` and
  `NO_CONFIG_FRAME`. A block is parsed once for the component, with no call
  site and no host around it (`parse_script` takes no context at all), so a
  `^title` there would read Null and say nothing. That asymmetry is why the two
  are not in the slot/block "refuse alike" corpus: they parse in both and are
  refused in one, and the difference is not grammatical.

  (`tscript/script_spec.mbt`, `tscript/script_parse.mbt`,
  `tscript/script_print.mbt`, `tscript/check/check.mbt`, `tscript/parse.mbt`,
  `core/value_builtin.mbt`, `core/value_eval.mbt`, `viewgen/surface.mbt`.)

- **`bad value 'not' in unknown predicate` is gone.** The role phrase was
  spliced in after "in", which reads as a place — and two of the roles are not
  places but explanations, so the result was ungrammatical and named neither
  the rule nor the way out. `UnknownPredicate` and the new `BadExpression` now
  answer with a whole sentence: the vocabulary, or the block grammar's own
  message for what it refused.

- **The four render-time buckets take a trailing `&@tutuca.Stack`.** `compute`,
  `when`, `enrich` and `enrich_scope` — not `swap`, which answers a dispatch and
  already carries a `&Ctx`, and not `loop_with`, which no value body compiles
  into. This is a breaking change to `@component.component`: a hand-written
  registration adds one `_stack` to each lambda, and `gen-views` writes the
  parameter for every generated one, naming it `_stack` when the body asks the
  stack nothing so a generated file is never the thing that warns.
  (`component/component.mbt`, `component/spec.mbt`, `viewgen/emit_comp.mbt`.)

### Fixed

- **`*name` works in a `compute`, a `pred`, a `@when` and an `enrich`.** It
  parsed, it checked, and it compiled — into a function body holding a free
  `ctx`, so a block that read a dynamic binding from a value body produced a
  module that did not build. `gen-views` said nothing, which made it worse than
  a refusal: the same binding inside an application was turned down cleanly by
  the argument-type guard, so it was refused one way and miscompiled the other.

  The cause was a category error rather than a missing check. `ctx.lookup` is a
  DISPATCH-time question and there is no dispatch in progress while a view is
  being built — a value body is called BY the render stack, not beside it. So a
  value body now takes a trailing `&@tutuca.Stack` and reads
  `stack.lookup_dynamic(name)`, which is literally the call
  `core/value_eval.mbt` makes for a `Val::Dyn` in a slot. The compiled and the
  interpreted backends answer one question one way rather than by two tables
  kept in step, and a `pred` reading `*theme` agrees with the `@text="*theme"`
  next to it by construction.

  A `compute` a TRANSITION calls as a sibling is the other caller, and it holds
  a `&@tutuca.Ctx` instead — so it is handed `@tutuca.CtxStack(ctx)`, which
  walks the intent's `dyn`/`lex` route and answers what a `*name` in this
  component's view would. One seam, two producers.

  `Value::Fn` carries `(Array[Value]) -> Value` and nothing else, so the stack
  could not ride in on the existing convention: `@tutuca.Obj` gains
  `method_at` and `obj_callable_at`, both DEFAULTED to the stackless answer,
  so every hand-written `Obj` keeps working untouched.
  (`core/spec.mbt`, `core/ctx_stack.mbt`, `core/value_dyn.mbt`,
  `render/stack.mbt`, `component/instance.mbt`, `tscript/emit_mbt/emit.mbt`.)

- **`gen-views <dir>` names every file that failed, not the first one.** A batch
  returned on the first bad file and wrote nothing — not even for the files that
  had already compiled — so a directory with three problems took three builds to
  even SEE the three. The run is still atomic, which is the half that was right:
  the cross-file component table has to be complete or a reference into a file
  that did not split reads as an absence, and a half-generated tree is the one
  state nobody can reason about. What changed is that one run now says
  everything. A single failure keeps the exact `[path] message` shape it has
  always had, because `where_` has one slot and picking one of three failing
  files to put in it would be a claim about the other two. A file that fails to
  SPLIT still stops the batch before the emit pass, for the reason above.
  (`cli/gen_views.mbt`.)

### Deprecated

- **`equals?` and `falsy?` are retired spellings.** `is` says the first and
  `not` says the second, and one meaning keeps one spelling — the rule that
  already kept `equals?` out of the block.

  Both still parse, and that is deliberate: a compiled dyncomp bundle carries
  its view markup as a STRING inside the wasm and the host parses it at load
  time (`dyncomp/host/manifest.mbt`), so deleting a spelling would break a
  bundle nobody can recompile. `@tutuca.retired(name)` is the one table saying
  what to write instead, `gen-views` hints once per name per component, and
  neither name is in `builtin_names()`, so no "did you mean" ever offers one.
  They go at the next apiVersion.

  The 109 uses in this repo are migrated — 94 in `.html` views plus the two
  embedders an `*.html` sweep misses, `tutucard/web/examples.js` (the starter
  cards) and `storybook/ui/engine.mbt` (view markup built as MoonBit string
  literals at run time).

## [0.28.1] - 2026-08-24

### Fixed

- **A `compute` or `pred` containing `/` or `mod` compiled into a module that
  did not build.** The MoonBit emitter emitted the divide-by-zero guard as
  `return Unchanged` — an `Update` constructor — regardless of what the body
  returns, so a value body carried an `Unchanged` where a `Value` (or a
  `Bool`) was wanted. The guard now leaves through the ROLE's answer:
  `Unchanged` in a transition, `Null` for a `compute`, `false` for a `@when`.
  The bounds-checked collection methods (`insertAt` / `removeAt` /
  `deleteAt` / `setAt`) had the same defect and get the same fix. An `enrich`
  cannot leave early without keeping its earlier writes, so those constructs
  are REFUSED there at generation time with the reason named, on the same rule
  that already refused opaque coercions in enrichers.
  (`tscript/emit_mbt/emit.mbt`, regression tests in
  `tscript/emit_mbt/emit_test.mbt`.)

- **A component whose view root is omitted by `@show`/`@hide` left stale DOM
  when it was the thing being patched.** When `render_root` answered None —
  the whole tree dropped out — `App::render_now` did nothing, leaving the
  previous render standing and `prev` pointing at it; the next non-empty pass
  then morphed against DOM that no longer matched the container. The mount
  point is now unmounted and `prev` reset, so a hidden component goes away and
  re-shows fresh.
  (`app/loop.mbt`, regression test "a root whose view renders nothing takes
  its DOM with it" in `testing/harness/harness_test.mbt`.)

## [0.28.0] - 2026-08-24

### Changed

- **Name lookup is unified under the intent's `dyn`/`lex` routes.** Type
  lookup, `provide`/`lookup` and intent routing were three answers to one
  question — what does this name mean, and where do I look for it. They now
  share two environments and one route vocabulary:

  | leg | environment |
  |---|---|
  | `dyn` | the render ancestry (`RenderStack.dyn_binds`) |
  | `lex` | the registration scope chain (`ComponentStack`) |

  `ctx.lookup(name, opts)` and `ctx.make(name, args, opts)` take `opts.route`
  with the same legs, the same array-is-walk-order contract and the same
  default (`@tutuca.default_route()`, `dyn lex`) as `ctx.intent`.
  `@tutuca.route_lookup` is the one walk all three share. There is no
  `lookup_type`: the only thing a handler can do with a resolved type is build
  one, and `core` cannot name a `@component.Component` anyway — which is also
  what the guest contract already said (`make-instance: func(component:
  string, …)`).

  The `lex` leg needs no stack. The `dyn` leg rebuilds one lazily from the ctx
  (`@app.ScopeNames`), because the stack that evaluated a handler's arguments
  is a local in the dispatch pipeline and is gone once the body runs.

- **Declarations became plain data.**

  ```moonbit
  provide={ "items": ".items", "Cell": "self" }
  lookup=[@component.lookup_name("theme"), @component.lookup_or("color", "'gray'")]
  ```

  A lookup names what it WANTS, not who provides it, so `LookupInfo` loses
  `comp_name` / `provide_name` and its sticky `ProducerKeyMemo`, `ProvideInfo`
  loses its `ProvideKey`, and `DynBinds` is keyed by plain name. An uppercase
  name is a component type; `"self"` is the only legal value for one, which
  keeps a published type a component by construction. Types and values share
  one frame because their keyspaces cannot collide.

  Dropping the qualified `"Producer.name"` target means `resolve_dyn_producer`
  finds the producer by scope search (`ComponentStack::lookup_provider`), which
  is sound only while one provide name has one producer per chain — hence
  `PROVIDE_NAME_COLLISION`.

- **Component types left the value language.** `KType` is in no grammar group,
  which removes them from handler arguments and macro attributes in one edit
  (`GComponent` never held them, so `<x render=".field">` is untouched). A
  handler that needs one asks by name.

### Added

- **`ctx.send_reply(name, args)`.** A message carries no expectation of an
  answer and its sender declares no arms, so the replier names the reply; an
  intent's answer is named by the runtime (`<name>Ok`) because its raiser did
  declare arms. The reply is an ordinary message, delivered at the sender's
  position as pinned at dispatch. Refuses `NO_SENDER` when nobody is waiting —
  a view's own `@on.*`, or the host's `send_at_root`. `ctx.reply` stays
  intent-only. `send` itself is unchanged and stays ADDRESSED: it walks
  nothing.

- **Five name-wiring checks**, in `lint`'s vocabulary and raised from
  `ComponentStack::check_names`: `PROVIDE_NOT_ADDRESSABLE`,
  `PROVIDE_TYPE_BAD_SHAPE`, `PROVIDE_NAME_COLLISION`, `LOOKUP_NO_PROVIDER`
  (an error without a default, a hint with one — whether a provider is above at
  render time is a runtime fact) and `UNKNOWN_COMPONENT_NAME`. `compile()` still
  drops a bad declaration rather than raising: what is wrong with one is a
  finding with a name and a place to point at, and the component renders while
  the list is read. A dyncomp bundle runs them at registration and reports them
  in its diagnostics.

- `RefusalCode::TypeNotFound` (`TYPE_NOT_FOUND`, carrying the route it walked)
  and `RefusalCode::NoSender` (`NO_SENDER`).

- **A card declares its own dynamic bindings.** `provide { … }` and
  `lookup { … }` are sections of a `state` body, so the one thing the schema
  block could not say — where a value comes from — is no longer MoonBit-only:

  ```html
  state Board {
    theme: String
    provide { theme = .theme, Cell = self }
  }
  state Slot {
    made: String
    lookup { theme, color = 'gray', Cell }
  }
  ```

  Nothing about this crosses the guest ABI and the compiled module is
  byte-identical either way: the expressions travel in the manifest as SOURCE
  TEXT (`DynComponentDef.provide` / `.lookup`), and the host parses and
  evaluates them against the instance while rendering, exactly as it does for a
  component written in MoonBit. So a guest reads a value a HOST ancestor
  published, and the host's own checks run over a bundle's wiring at
  registration.

  The two words are NOT reserved field names: a section opens on the word
  followed by a brace, so `provide: String` is still a field.

- **A guest component published as a type can be built.** `Component::make` on
  a bundle's component used to yield `Null`; it now goes through
  `Bundle::make_instance`, so the instance a `provide { Counter: "self" }`
  promises is one the guest actually created and still owns.

- **A card's handlers reach both.** `*name` is legal in a script block now, and
  is the same question the view one line down asks:

  ```
  receive stamp { .label = $'{.label} ({*theme})' }
  receive ping  { sendReply 'pong' .label }
  ```

  `*name` in a BODY used to be `RENDER_ONLY` — "a body cannot read a dynamic
  binding at all" — and that was true only while the two environments had no
  route vocabulary in common. It has one now, so the rule became
  `DYN_NOT_DECLARED`: whether a producer is above you at render time is a
  runtime fact, but whether you ever asked for the name is not. `$name` is
  still render-only, and for the reason `*name` no longer is — a `compute`
  really is the render stack's answer, and a body calls one bare.

  `sendReply 'name' args…` joins `send` / `sendAt` / `intent` / `forward` /
  `reply` / `fail` / `stop` as an effect, and is in the conformance corpus, so
  both backends are held to it.

### Fixed

- **A card could not have declared a served intent, even in principle.** The
  card manifest emitted `"requests"` and the host read `"serves"`, so the two
  never met. The key is now the one the host reads.

### BREAKING — the guest contract

`tutuca:component` goes **0.9.0 → 0.10.0**. A bundle built against 0.9.0 calls
functions this host still implements, but its export namespace carries the old
version and `abi.mjs` refuses it by that — which is a legible error rather than
a half-working guest. Rebuild guests against the new WIT.

- **`control.send-reply(name, args)`** — buffered like every other effect and
  applied through the dispatching `&Ctx`. With nobody waiting the HOST refuses
  `NO_SENDER`; the guest is not told, because who was listening was never its
  question.
- **`control.lookup(name) -> value`** — the first import on this interface that
  ANSWERS rather than acting, and the shape is why it is safe. It takes no
  route: the host resolves this component's DECLARED lookups at dispatch, along
  the default `[dyn, lex]`, and hands them in as `Guest::dispatch`'s new
  `bindings` parameter — so `lookup` is a map read over a set the manifest
  fixed, not a walk the guest takes. A name the manifest does not declare is
  not in the map. See `dyncomp/SECURITY.md` §5a.
- `Guest::dispatch` takes `bindings : Map[String, Value]`. Every transport and
  every fake implements it.

### BREAKING

No compat layer.

- `lookup` is a LIST, not a map, and names no producer:
  `lookup={"color": {source: "Theme.color", default: Some(X)}}` becomes
  `lookup=[@component.lookup_or("color", X)]`. The local name must equal the
  provided name; there is no alias, and none was in use.
- An uppercase token is no longer a value: `@on.click="addItem JsonSelector"`
  becomes `@on.click="addItem"` plus `ctx.make("JsonSelector", …)`, with the
  name declared in `lookup` where the checks can see it. A macro attribute
  cannot carry one either.
- `ProvideKey`, `ProducerKeyMemo` and `LookupInfo::resolve_producer_key` are
  gone; `DynBinds` is `{binds, types, parent}` keyed by name.
- `Transactor::new` takes a `names?` seam beside `intents?`. `App::new` wires
  it; a bare `Transactor::new` resolves no names, the way it answers no
  intents.

## [0.27.0] - 2026-08-22

### Added

- **`+prevent` and `+stop` event modifiers.** The two effect modifiers every
  JS framework has, and that tutuca's docs explicitly said it did not have:
  `@on.submit+prevent="save"` now really calls `preventDefault()`, and
  `@on.click+stop="pick"` calls `stopPropagation()` — on any event, run when
  the handler runs (after the guard modifiers gate it, per passing handler).
  Both reach the live event through closures the backend glue supplies on the
  `DomEvent` (`EventEffect`, the twin of `EventPathReader`); a test's or
  harness's event carries none and both are no-ops there.

  One architectural consequence worth reading before using `+stop`: events
  dispatch through ONE delegated listener per app, so a handler runs after the
  event has already bubbled to the mount. `+stop` keeps the event from leaving
  the app (a host page's document listener, an outer shell) — it cannot stop
  the component's own handler from firing, nor silence another `@on.` inside
  the same app.

### Changed

- **Event paths are open by default; the allowlist is the safe profile.** An
  `e.<path>` handler argument used to be refused at GENERATION time for every
  traversed step not on `eventpath`'s six-entry allow-list (`BadEventPath`), and
  answered `Null` at run time for the same. The two rules now answer different
  questions, because an author's own views and guest-supplied ones are held to
  different trusts:

  - **Native component authoring is OPEN.** Any path resolves, in viewgen and
    in the runtime resolver alike — a template is code its author could have
    written in JS, so gating their reads was ceremony. An off-list step is now
    reported as advice, twice over: a hint from `viewgen`'s events pass (the
    `BadEventPath` generation error is gone), and an `EVENT_PATH_UNSAFE_STEP`
    lint finding from `@lint.check_event_paths`, which `gen-views` prints with
    the rest of them.
  - **dyncomp hosts are SAFE, in every tier.** `Policy` carries
    `event_paths : @eventpath.EventPathProfile` (`Safe` in all three
    constructors; loosen deliberately with `with_open_event_paths`). It is
    enforced at registration — `Policy::check_event_paths` refuses a bundle
    whose views traverse an off-list step, naming step and index, where before
    the bundle loaded and read `Null` forever — and again at dispatch: the
    bridge hands the same profile to its app via the new
    `App::set_event_paths`, so `RenderStack`'s resolver agrees with what
    registration admitted.

  The list itself, its data terminals, and its exact-list test are unchanged;
  see `dyncomp/SECURITY.md` §9 for the profile split.

## [0.26.0] - 2026-08-21

A component can be instantiated from data. The pieces were all here — `make`
already coerced an args map and filled defaults, `to_json` already walked an
instance's declared fields — and what was missing was the one thing that turns a
projection into a document: a name saying what to build. This release adds it,
and replaces the bespoke codec the universal UI had been carrying with one that
reads a field's declared TYPE instead of guessing from its value.

### Added

- **`$component`: a tagged JSON projection, and its inverse.**
  `@tutuca.Value::to_component_json` writes an instance flat — its declared
  fields at the top level and a reserved `"$component"` key beside them, plus an
  optional `"$module"` where a host knows the bundle — and
  `@tutuca.Value::from_component_json` reads one back. Both walk by
  `FieldInfo.ty`, so a component-typed field recurses, a list of children
  recurses element by element, and an object carrying a tag hydrates anywhere
  the declared type permits an object. The reserved keys cannot collide: a
  declared field name can never begin with `$`.

  One rule governs everything that does not fit: a field the document omits, a
  value the type cannot hold, and a `$component` that resolves to nothing all
  fall back to the component's own default. `Value::to_json` is unchanged — the
  untagged projection every state dump and snapshot already reads keeps its
  meaning.

- **`Component::from_json` / `Component::to_json`**, resolving names through the
  component's own registration scope — the same namespace a view resolves a
  child through, so a document names a component the way a template does and an
  alias works in both.

- **`@tutuca.ComponentSource`**, the seam a name resolves through, implemented
  for `ComponentStack`, `@std.Std` and `@ui.UniversalUi`. A source answers what
  a name DECLARES (so its fields decode by type) and how to BUILD it; a source
  that can build a name it cannot describe — a foreign guest — answers only the
  second, and its fields decode structurally.

- **`UniversalUi::tree_of_json`**, with a `restore~` hook keyed by JSON Pointer
  for a host whose guests persist their own bytes. The page-tree codec is now
  backend-agnostic, which is why the round trip has a test: a notepad built by
  clicking is written out, read back, and still holds what was typed in each
  tab.

- **An Examples pane, and the tab that feeds it.** The tutucard playground shows
  the card at every state it says it can be in, one live box per
  `<script type="tutuca/init">` fixture: seeded from `value`, driven by `drive`,
  answered by `intents`, rendered under `view`, titled by its name with `doc`
  underneath. Each is the same module instantiated again in its own scope, so
  pressing a button in one changes that one and nothing else. The module is
  compiled once and instantiated per fixture — `loadGuest` takes a `module~`
  now — which is what makes a gallery affordable on a keystroke debounce.

  The structured editor grew an `examples` tab over the same block. It was the
  one block with no tab, which is how a card came to have named example states
  that only the raw view could reach.

- **`testing/harness` is generic over `@vdom.DomWalk`.** `Harness[N]`, with
  `MemHarness` for the in-memory one every headless test holds. This is what
  lets a fixture's `drive` steps run on the page the fixture is shown on: the
  verbs were already written against two fields and a dispatch, and what pinned
  them to memdom was reaching into `MemNode`'s struct rather than through the
  trait it already implements. So "click the third row" is one implementation
  driving both backends rather than two that can disagree about what `nth`
  counts. `tutucard/drive` exposes it as `seed(h, steps)` — the drive verbs with
  no report, since a fixture SHOWS and a scene CHECKS.

- **`view~` on `render_root` and `App::new`**, and `view` on a fixture. Which of
  a component's views to mount it under is the one thing a value cannot say
  about itself: a `Todo` has a `main` and a `row` over the same fields, and the
  choice is a fact about the showing. A name the component does not declare
  falls back to `main`, exactly as every other view name does.

- **`Bundle::default_init`**, and a host that reads it. A fixture marked
  `default: true` is what the playground and every `<mb-card>` embed now mount
  when nothing named one, so a card is met the way its author meant rather than
  at whatever the schema's zero happens to be. Explicit only — a card that marks
  none still opens at the zero. A `tutuca/test` scene is deliberately NOT
  affected: a test's starting point is a thing to write down, and a default is
  what to show someone who has said nothing.

### Fixed

- **An empty cell survives a save.** The universal UI's codec decided whether a
  field held a component by LOOKING at it, at exactly the moment an empty one
  holds nothing to recognize — so a `Universal` with no child and a container
  with no cells were written as scalars and did not come back. Reading the
  declared type answers without having to look.

- **A container emptied by hand no longer grows a cell back.** `Std::build`
  fills `children` when the key is absent; the codec now always writes every
  declared field, so "empty" stays a statement rather than a silence.

- **A card's `view` and `default` were carried and read by nobody.** Both
  reached `DynInitDef` and stopped there, so a fixture could say which view it
  wanted and be shown under `main` anyway. Now a mount reads them.

- **A margaui scope carrying a comma styled the wrong element.**
  `scopeSelector` prefixes by concatenation, so a scope of `#a, #b .c` split
  into two selectors — the first of them the bare `#a`, which then took the body
  of every rule the sheet writes about a themed root, `display: none` included.
  The scope is one selector now, with the alternatives inside `:is()`, and the
  constraint is written down where it is relied on.

### Changed

- **`@ui/wasm.tree_json` / `tree_of_json` each lose their `path` parameter** —
  the codec threads the pointer now — and the document they write is the
  `$component` shape rather than the old `{c, m, f, k, l}`. A session saved by
  an earlier version opens as an empty page.

- **`@harness.Harness` takes a type parameter.** A call site that named the type
  says `@harness.MemHarness`; one that inferred it is untouched. `html`,
  `destroy`, `prop`, `checked_of` and `value_of` stay on the in-memory node,
  since a browser mount is torn down by its host and its HTML is on screen.

- **`__tutucard.mountCompiled` takes a third argument**, the fixture to mount —
  `""` for "nothing was named", which is not the same as "no fixture". The JS
  `mountCard` spells it `init` in its options object.

- **The counter starter card declares four fixtures and a second view**, so the
  page opens on something the new pane can show.

- **The playground's Mounted panel is a tab in the Preview pane.** They answer
  the same question about the same card — what it looks like running — so a
  reader compares them by switching rather than by looking in two places, and
  the grid is back to two rows of three. `load & mount` switches to the tab it
  fills, before the instantiate rather than after it.

- **A tab looks like a tab and a button looks like a button.** Every strip on
  the page was boxed pills, so `wax`/`wat` (which change what is shown) and
  `download`/`load & mount` (which do something) were indistinguishable. Tabs
  are names on a rule with the chosen one underlined; the two actions keep the
  box.

## [0.25.0] - 2026-08-20

The script block is where a component's behaviour belongs, and MoonBit is the
answer for what that language cannot say. This release moves four handlers back
across that line — they were not refused by design, only missing from the
emitter — and rewrites the bundled skill, which had been teaching the escape
hatch as the entrance.

### Added

- **`has` compiles.** The membership read — `has .picked @value`, which every
  selection list grows — had no arm in the MoonBit backend, so a block a card
  ran refused under `gen-views`. A set or a map is asked for a KEY, through the
  display string that `hasIn<X>` writes and `tc_has` reads; a list is searched
  by equality at its element's own type.

- **An ordered map takes `setAt` / `deleteAt`.** They are what the checker
  allows and what the card implements — and they mirror the generated
  `setIn<X>At` / `deleteIn<X>At` mutators. The backend previously took only
  `set` / `remove` / `delete`, so one backend refused what the other ran over a
  spelling. All of them are accepted.

- **Three sections in the skill's `schema.md`.** *The reading vocabulary* (the
  sixteen builtins and five operator families, which the skill never listed),
  *Changing a collection* (the statement form, the per-type table, the
  canonical spellings, and the fact that a generated mutator is answered by the
  runtime and no script-refusal can disable one), and *What the ahead-of-time
  backend refuses*.

### Fixed

- **A `receive` payload of a collection type emitted a module that did not
  compile.** The parameter bound raw — a `Value` — while its type stayed the
  declared `Array[Any]`, so `.items = rows` assigned a `Value` into a typed
  field and `moonc` rejected the generated file, with nothing between the block
  and the build to say which arm did it. `Array[Any]` and `Map[String, Any]`
  now decode through their patterns; any other non-scalar binds raw with its
  type unknown, so a typed use is refused the way the code always claimed.

- **A `pred` a loop calls reported a refusal for a role nobody asked for.**
  Every `pred` is folded into the method bucket, because a parent may ask a
  child for one; a `@when` pred reads `@value`, which the method role cannot
  hand it, so every filter written the ordinary way printed `stays in MoonBit`
  about a function no view calls. It is reported now only when a view spells
  `$name`.

### Changed

- **The bundled skill's patterns lead with the view file.** Nine recipes showed
  behaviour as a MoonBit bucket argument that the block spells directly — a
  `@when` is a `pred`, a per-row binding is an `enrich`, a `$name` is a
  `compute`, a click handler is a `receive`, a message or an intent is an
  effect. Every recipe that keeps a MoonBit half now says which of the two
  reasons it is: wiring, or a body the block does not spell. `SKILL.md`,
  `patterns/README.md` and core.md's bucket section state the same order —
  generated mutator, then the block, then a bucket.

- **`scripts/check-skill-snippets.mjs` verifies the shape the docs now aim
  for.** It generated an `html` view file only when a `moonbit` block followed
  it, so a recipe whose whole answer is the view file was the one shape nothing
  checked. It generates them all, and a generation reporting a
  `script-refusal` now fails the check. `playground/viewgen_js` returns the
  hints it reads.

## [0.24.1] - 2026-08-20

### Fixed

- **Every compiled card with a view failed to load.** `tutucard/wasm` projects
  each `<template>` into an `html` string on the manifest and `packBundle` tars
  that manifest as it stands, because a compiled card has no archive to read
  views out of — only a page that has the card. The universal host's
  `hydrateManifest` read `view.src` off every view regardless, so the name came
  out `""`, the lookup missed, and the load died with `static manifest view is
  missing from archive: undefined`. Since a bare template IS the main view, that
  was every card rather than an unlucky few. A view that already carries its
  markup is now left alone; one that names a file is still refused by name when
  the file is absent.

  It shipped because nothing exercised the branch. There are two shapes through
  `hydrateManifest`: the guest-bundle path, where a view is a file the manifest
  points at with a `src` — which `examples/dyncomp-dice` proves end to end — and
  the card path, which had no coverage at all, since `dyncomp/test/archive.test.mjs`
  stopped at `untar` / `gunzip` / `requireDescriptor`. It now drives a gzipped
  archive built in memory through the dropped-file seam, which needed no new
  export: `createTcompImports` and `registerDroppedFiles` were already public and
  neither touches the DOM. Both shapes are checked where they diverge.

## [0.24.0] - 2026-08-20

**v2 only.** 0.23.0 shipped the two-channel model as a *migration*: the contract
kept v1's verbs, the generator downgraded a v1 spelling to a hint, and
`tutuca migrate` moved downstream code. The codemod is gone, this repository and
its guests are on v2, and what is left of v1 is a second grammar the parser, the
resolver, the generator, the schema, the card compiler and the WIT all still
carried for no reader. This release removes it.

**Every guest bundle needs rebuilding, and there is no compatibility path.** A
`.tutuca.tar.gz` built against `tutuca:component@0.7.0` or `@0.8.0` no longer
loads: the host refuses it by its export namespace with a message saying to
rebuild. That retires the promise 0.23.0 made deliberately, and it is the whole
cost of this release.

### Removed

- **v1's dispatch surface, everywhere it survived.** `Dispatch::Input` /
  `Bubble` / `Response`; the schema's `bubble` and `response` buckets and the
  `bubbles` / `responses` manifest keys; `HandlerNamespace::Input`; the
  generated `<T>Bubble` / `<T>Response` enums; `Ctx::is_answer`; and the
  `bubble` / `request` effect verbs in both the MoonBit backend and the card
  compiler. The block language stopped accepting `on` / `bubble` / `response`
  declarations before this release; the error messages that still offered them
  now agree with the parser.

- **The dyncomp v1 bridge.** `DynObj::handler` translated between the host's
  two buckets and the wire's five — an intent going out as `bubble`, an answer
  disambiguated by `is_answer`, an unclaimed `Receive` retried as `input`. All
  of it is gone; the bucket goes out as it came in. With it went `GuestBucket`,
  `RequestOpts`, and the `Emit` / `BubbleAt` / `Request` control messages.

- **`docs/two-channels.md`** — the design argument for a change that has
  shipped. `skill/tutuca/messages-and-intents.md` is the authoring guide it
  argued for; the source comments no longer cite section numbers.

### Changed

- **WIT is `tutuca:component@0.9.0`**, manifest `apiVersion` 7 → 8. `emit`,
  `bubble-at`, `request` and `request-opts` are gone from `control`, and
  `bucket` is `{ receive, intent }` — which RENUMBERS the cases, and is why the
  api version moves with it. `guest.handle-request` is now `serve-intent`
  answering `serve-result`, and the manifest key `requests` is `serves`: a
  bundle's own handlers are intents on the `lex` leg, and they are named that
  way now.

- **A bare event argument is a build error.** `@on.input="setStr value"` was
  v1's spelling and had been a hint since 0.23.0; it is `BareEventArg` now, and
  the message names all three sigils (`e.` the event, `.` state, `@` a
  binding). Every `@on` argument in the repository moved with it, and one
  guest's answer arm had to be renamed: a bundle that spelled a request and its
  answer both `triple` now collides, because one bucket holds both — the answer
  is `tripled`. The runtime fallback went with it: `lookup_name` no longer reaches
  the event's fields, so the shadowing rule where an `@each` bind named `value`
  quietly beat the DOM event is not a rule any more — the two spellings that
  needed telling apart are now one.

- **`SchemaInfo.inputs` is `view_handlers`.** Same data — the `@on` names the
  views raise — under a name that is not the deleted bucket's. `bubbles` and
  `responses` are gone from it and from the schema fingerprint, so every
  fingerprint changes and stored guest state from an older release is refused
  rather than misread.

### Fixed

Each of these was a live defect the compatibility layer was hiding:

- **The wasm host never implemented `intent`, `intent-at`, `forward`, `reply`
  or `fail`.** The WIT declared all five and the generated bindings exposed
  them, but `dyncomp/host/wasm/loader.mjs` bound none — so a guest that
  dispatched an intent failed to instantiate. Every guest in the repo was still
  written against `emit` / `request` because that was all that worked.

- **The core-module ABI's `intent` did not match the contract.**
  `dyncomp/host/wasm/abi.mjs` declared `intent(string, list<value>, u32)` — a
  compact route code, which is what the card compiler emits — where the WIT
  says `intent-opts`, a record carrying the route AND the three answer names.
  A wit-bindgen guest lowers that to sixteen i32s; the import binds by NAME, so
  eleven of them were read as something else. The symptom was subtle and worth
  naming: an intent whose route happened to be the default still walked, and
  one that named `on-ok` answered nobody, silently. `abi.mjs` now spells the
  record the contract does, and the card compiler builds it.

- **The card runtime imported `tutuca:component/values@0.7.0`** while its own
  ABI table pinned `@0.8.0`. It only linked because the host strips versions
  before looking an import up.

- **`tutucard`'s escape vocabulary had no `intent`.** `escape_role` matched
  `on` / `receive` / `bubble` / `response`, so a `card_intent_*` escape could
  not be recognized at all, while `dispatch.mbt` built only `receive` and
  `intent` arms.

- **`bench-views` had been broken since its input was deleted**, so the
  benchmark corpus was stale — it still spelled event arguments the v1 way
  while its own sources did not. Regenerating it surfaced a second fault: the
  builder never qualified a view file's `<script type="tutuca/script">` with
  `for=`, so concatenating two files that each had one produced a corpus that
  could not be split.

- **`statedef/info` and `dyncomp/host/bundle` never passed `intents` through**
  to `SchemaInfo`, so a schema declaring `intent { … }` reported none.

- **`cmd/card-corpus` emitted the same corpus twice**, under `cases` and
  `casesV2`, and `cmd/conformance` told readers to add cases to a `cases_v2()`
  that does not exist. The card conformance harness also injected a capitalized
  variant name beside its lower-case twin, which the schema then refused as a
  duplicate — 11 of its cases had been failing.

- **`tutuca migrate`** — the one-way v1→v2 codemod added in 0.23.0 is gone,
  along with `cli/migrate.mbt` and the `Migrate` command variant. It was a
  migration tool with a migration behind it: the repository, the examples, the
  site and the guests are on v2, and a codemod nobody runs is a second grammar
  to keep parse-print-parse honest for no reader. A v1 codebase that still
  needs moving runs the **0.23.0** binary, which has it; what that run refuses
  is still the work list.

  `cli` no longer imports `tscript` or `eventpath` — the codemod was the only
  thing in it that parsed the block language or needed the accessor vocabulary.

- **The skill documented v1's bare event argument.** `events.md` and the
  pattern files spelled an event read `@on.input="setStr value"`. Every `@on`
  example in `skill/` now carries the sigil, and `events.md` documents what was
  missing entirely: the two resolution layers (the computed accessors, which
  shadow the walk), the six allowlisted path steps behind
  `e.target.dataset.x` / `e.detail.x`, and `BadEventPath` as the error for a
  path that leaves the event.

## [0.23.0] - 2026-08-20

**Every downstream SOURCE tree needs migrating; a compiled bundle does not.**
This release changes the dispatch model and the buckets a component answers.
`tutuca migrate` is what moves a v1 codebase — run it BEFORE upgrading, because
two of its findings are refusals rather than rewrites and a human decides how
they split.

A `.tutuca.tar.gz` built against `tutuca:component@0.7.0` **keeps loading, with
no rebuild**: its imports resolve by unversioned interface name, its `emit` /
`bubble-at` / `request` are translated by the host, and its answer still arrives
under the name a `response` arm waits for. That is a promise this release makes
deliberately, and it is held in two places: `dyncomp/test/abi.test.mjs` binds a
module that imports the 0.7.0 world, and `dyncomp/host/host_test.mbt` drives the
v1 wire shapes — the `bubbles` manifest key, the `input` bucket, and a `request`
whose answer lands in a `response` arm. A guest that
wants to USE v2's routing needs the 0.8.0 WIT and regenerated bindings
(`cmd/dev -- gen-guest-bindings`, or `tutuca new-guest` for a fresh tree).

### Changed

- **Four dispatch channels became two.** `Input` / `Receive` / `Bubble` /
  `Response` are now `Receive` — a message addressed to one component, which
  stops there — and `Intent`, which names a job and walks a **route** until
  something answers. A route is a list of legs: `dyn` walks the dispatch path
  from the sender's PARENT up to the root, `lex` walks the handlers registered
  on the scope chain, and a bare `intent` takes `dyn lex`. What v1 spelled
  `bubble` is `intent dyn`; what it spelled `request` is `intent lex`. The verb
  no longer decides which scope answers — the route does, and it is written at
  the call site where the decision is.

  In the block language: `intent [dyn|lex]… 'name' args…` raises one,
  `reply` / `fail` answer it, `forward` hands it to the next hop, and `stop`
  ends the walk answering nothing. A handler that runs without replying is an
  **observer** — one rule, `a reply ends the walk, running does not`, replaces
  the separate listener bucket v1 would have needed.

- **An intent has three named outcomes, and each has its own shape.**
  `<name>Ok`, `<name>Error` and `<name>Unhandled` are dispatched back to the
  sender as ordinary `receive` messages. v1's combined `[res, err]` payload is
  gone, and so is the bug it caused: a split arm matching `[res, err]` read the
  wrong slot silently, and there is now no arm that can be handed both.

  `<name>Unhandled` is the outcome v1 had no word for. A `RequestFn` *had* to
  respond, so a handler with nothing to contribute could only invent an error;
  an `IntentFn` answers `Pass`, the walk goes on, and if the route runs out the
  sender hears "nothing claimed it" — a different sentence from "a handler
  refused it".

- **Scope handlers are `IntentFn`, registered as a list per name.**
  `ModuleDef::new(intents=…)` takes `Map[String, Array[IntentFn]]`, because the
  `lex` leg walks: a declining handler hands the intent to the next one.
  `RequestFn` and `requests=` still exist and still work; they are deprecated
  and will be removed.

- **`e.<path>` in an `@on` argument is checked against the browser specs.**
  `eventpath/dom_props_gen.mbt` is generated from `w3c/webref`'s machine-extracted
  WebIDL, so `e.target.value` is type-checked against the event interface it is
  reached through rather than accepted on faith. Regenerate with the `dom-props`
  task.

- **WIT is `tutuca:component@0.8.0`**, with `intent` added to the `bucket` enum
  (last, so existing discriminants are unchanged) and the four `control` intent
  functions on the host side. Every guest was regenerated.

- **A message case is declared the way it is used: `focusRow`, not
  `FocusRow`.** The parser always derived both the runtime name and the MoonBit
  variant from whatever spelling a `receive` / `intent` / `bubble` / `response`
  case was written in, so the UpperCamel in every schema block was the
  *generated* variant leaking into the authoring surface — a block reading
  `FocusRow(Int)` above a handler reading `receive focusRow(n)` and a view
  writing `send 'focusRow' 3`. Every declaration in the docs, the bundled
  skill, the playground cards, the storybook, the dyncomp and inspector
  components and the tutucard examples now reads the way the code around it
  reads. UpperCamel still parses and still generates the same module, so no
  existing component breaks.

  One error message improves for free: `PayloadDisagrees` used to report
  ``declared `Bump(Int)` `` against ``called as `bump(a number, a number)` ``,
  a mismatch in the half that was not wrong.

- **`gen-views` reports `message-case (warning)`** for a case declared in a
  spelling nothing else uses — the capital, and `set_label` for the same
  reason. A warning rather than a refusal: both spellings compile to the same
  message, and the fix is always the name the warning prints.

### Removed

- **The v1 dispatch surface is gone.** `HandlerBucket` and `Dispatch` have two
  arms; `ObserveKind` has three. Deleted: `RequestOpts`, `Ctx::request`,
  `Ctx::bubble`, `Ctx::bubble_at_path`, `PathChanges::bubble`, `RequestFn`,
  `ComponentStack::register_request_handlers` / `lookup_request`,
  `ScopeRequests`, the transactor's `Requests` / `RequestHandler` /
  `NoRequests` / `push_input` / `push_bubble` / `push_request`, the block
  language's `on` / `bubble` / `response` declarations and its `bubble` /
  `request` effects.

  BREAKING for every consumer. `tutuca migrate` (0.23.0 and later) moves a v1
  codebase; what it refuses is the work list. Run it BEFORE upgrading if your
  code uses `RequestFn` or a `response` arm — those two are refusals, not
  rewrites, and a human decides how they split.

- **A loaded WebAssembly bundle is NOT affected.** `tutuca:component@0.8.0`
  keeps its five-case `bucket` enum and its `bubble`, `bubble-at`, `request`
  and `request-opts`, because a `.tutuca.tar.gz` somebody compiled against the
  published contract has to keep loading. The host translates: `emit` and
  `bubble-at` become intents on the `dyn` leg, `request` becomes one on `lex`
  whose answer is named after the request rather than `<name>Ok`, and a bundle
  whose routed names are under `bubbles` is entered through that bucket. One
  fidelity is lost and is worth naming: a v1 `response` arm receives the
  answered value alone, where it used to receive `[res, err]`.

### Added

- **`Ctx::is_answer`** — whether the message being handled is one the runtime
  wrote. A component never needs it: an answer being indistinguishable from a
  message is the design's claim, and the reason one bucket is enough. A bridge
  to a foreign contract does, because v1 gave the two different buckets and a
  bundle built against it may have used one name for both.

- **`tutuca migrate`** — a one-way codemod from v1 to v2 over `.html` and the
  `.mbt` beside them. It refuses rather than half-migrates: a file holding a
  construct it cannot rewrite safely is reported by name with the reason and
  left exactly as it was, and refusal is per COMPONENT so a view is never
  rewritten against handlers that were not. The refusals are the work list.

### Fixed

- **`@statedef.fingerprint` hashes a declared name normalized**, so recasing a
  case list is no longer reported as a shape the stored state can no longer be
  read back into — which is what its own "over SHAPE, not over source text"
  contract always said. A type name a FIELD refers to is still hashed as
  written, because a `StateTy` carries that spelling.

- **`@statedef.fingerprint` covers the `intent` bucket**, under the letter `n`.
  It had been iterating `receive` / `bubble` / `response` only since intents
  gained their own bucket, so two schemas differing solely in what they
  answered hashed the same. Every fingerprint moves once with this release.

## [0.22.0] - 2026-08-15

### Removed

- **The card interpreter is gone, and the compiler is what a card runs on.**
  `tscript/interp` and `tutucard`'s `load` / `Card` / `CardObj` / `Deck` have
  been deleted. A card is mounted by compiling it to a
  `tutuca:component@0.7.0` core wasm module and instantiating it — which the
  page could already do, in a panel next door, to show you what the compiler
  would have made of the card it was interpreting. That panel's answer is the
  one on screen now.

  BREAKING for anyone importing `marianoguerra/tutuca/tutucard` or
  `marianoguerra/tutuca/tscript/interp`. `tutucard/wasm` is what replaces both:
  `compile` for a module, and a new `check_card` for the findings on their own,
  which is what `load` was mostly used for.

  The language has two implementations now rather than three, and the corpus is
  what keeps them honest. Losing the third cost something worth naming: it was
  the implementation you could read in an afternoon, and it was where a case's
  answer came from when somebody wrote one. Both corpus tables state their
  answers outright now — which they had to, for the compiler's adapter to exist
  at all.

### Added

- **`<script type="tutuca/wax">` — the escape hatch, for the backend that had
  none.** The ahead-of-time path has always refused a handler by name and handed
  it back as an `update~` argument you write in MoonBit. The compiled path
  refused by name and handed back *nothing*: a refused handler was simply
  absent. Now a card can answer it in the language the module is built out of.

  A function called `card_on_<name>` (or `card_compute_<name>`, …) takes the
  dispatch arm the block language would have had, and gets the same wrapper a
  compiled handler gets — the `requires` still guards, the invariants still
  hold, and the effects it buffers are still flushed only once every rule has
  held. It may also answer a name the script block never declared, which is how
  you add a handler tutuca cannot express.

  Two things make it writable rather than a research project. The generator
  emits `get_<field>` / `set_<field>` / `num_<field>` per declared field, because
  it addresses a field through a constant-pool index only it knows. And
  `runtime/escape_help.wax` adds the short list of things that were awkward —
  `tcx_fail()`, `tcx_send`, `tcx_str("…")`. Everything else was already the right
  shape; the README lists it.

  `allow_wax` is OFF by default — a card is untrusted content in the `<mb-card>`
  story, so whether one may carry hand-written code belongs to the host.
  Independently, the screen refuses everything a guest's authority is made of:
  no `import`, no `memory`, no `data`, no `#[export]`, no `#[start]`, no globals.

- **`request` and `sendAt` compile.** `request` was the one genuine gap the
  corpus showed, and the `request-opts` record that made it look hard is not one
  the block language can write — so it lowers to constant zeros. `sendAt` reifies
  a `&.place` into `control.path-step`s at compile time, deciding `item` vs `at`
  from the key's value at run time. One form stays refused, deliberately:
  `&.panes[.sel]` means "re-read `.sel` on every dispatch" and the wire has no
  case that says so, so freezing the key would be a different path that looks
  like this one.

- **`enrich`, `enrichScope`, and the row a filter is judging.** These were the
  worst gap the compiler had and the only INVISIBLE one: both enrichers appeared
  nowhere in the package, so a card using `@enrich-with` compiled with no refusal
  to show for it and quietly lost its bindings. `@key` / `@value` / `@iter` now
  compile too, so a `@when` filter reads the row it is judging rather than
  keeping every one.

- **A declined contract says so.** A `requires`, `ensures` or `invariant` that
  does not hold reports through `control.log` — the same line `core/warn.mbt`
  prints, `format` sentence included. The structured `Refusal` still has no shape
  in the guest world; the sentence does.

- **`num`, and calls that take more than four arguments.** The README claimed
  "all sixteen" reading builtins before it was true of `num`. A call and a `send`
  now take as many values as they are written with.

### Fixed

- **Nine builtins answered something plausible where the language answers
  nothing.** `lower`, `upper`, `trim`, `contains`, `has`, `len`, `min`, `max` and
  `clamp` returned the value unchanged, or `false`, or zero, or a comparison that
  read two strings as numbers — `min 'a' 'b'` answered `'a'` — where the language
  abandons the transition. Found the first time the compiled backend was driven
  against the corpus's *value* table, which nothing had ever done. A plausible
  answer is the worse one here: "the transition did not happen" is something a
  card author can see, and `false` is not.

- **`int` of a string, and of anything else.** `int "42"` answered null instead of
  42, and `int true` answered null instead of abandoning the transition.

- **A compiled card carries its macros.** `<x:badge>` in one was an unknown
  element that rendered as itself — the same bug the card loader had and fixed,
  one backend later. The manifest carries them now and `register_bundle`
  registers them.

- **A card with no `<script type="tutuca/spec">` block compiles.** It was turned
  away whole, while the loader mounted one happily.

## [0.21.0] - 2026-08-14

### Added

- **A card handed four hundred rows draws twenty-five of them.** The three social
  guests each hold lists whose length was never theirs to decide — a caller asks
  a server for a timeline, a conversation, an account's posts or a channel's
  history, and gets back whatever a `limit` allowed. Forty rows is a card. Four
  hundred is a wall a reader scrolls past rather than reads, built out of four
  hundred child components before any one of them is looked at.

  So nine components grew a window and the four buttons that move it:
  `mastodonlib`'s `Timeline` / `Thread` / `Profile`, `blueskylib`'s `Feed` /
  `Thread` / `Profile`, and `slacklib`'s `ChannelHistory` / `Thread` /
  `FileList`. The vocabulary is `tablelib`'s rather than a new one — a declared
  `pageSize`, derived `page` / `pageCount`, the `firstPage` / `prevPage` /
  `nextPage` / `lastPage` messages, and `paged` / `atFirst` / `atLast` /
  `pageLabel` / `rangeLabel` for the footer — because a host drawing two of these
  cards side by side should not have to learn two spellings of "show me the next
  lot".

  What is worth knowing about it:

  - **It appears only when it is worth appearing.** A card pages once it holds
    more than a hundred rows; below that it draws exactly what it drew before
    this existed, footer and all absent. A host that wants the window anyway asks
    for a `pageSize`, because asking for one is what asking means.
  - **The window is over what the FILTERS left**, not over the records. The
    search box narrows, the pager pages what is left, and typing in the box goes
    back to the first page — it made a different list. A thread's window is over
    what the folds left, for the same reason and through the same `visible()`.
  - **Paging rebuilds nothing.** A page is a claim about what is on screen rather
    than about what exists, so a favourite three pages back is still there when
    the reader pages back to it — the property the filter already had, for the
    same reason: the children are built once and something else chooses among
    them.
  - **Everything that counts rendered positions goes through one function.** A
    write-back lands by position and `ChannelHistory`'s expand-all addresses by
    positional path, so `shown()` decides what the view is given, where a
    successor goes home, and how many steps expand-all walks — which also settles
    what that button means: the conversations in front of the reader.
  - `slacklib/FileList` reads `openFile`'s `@key` back through the same window,
    since a file row is a record rather than a child and position 0 of page two
    is not the first file. `slacklib/Thread` now tells two writes to `replies`
    apart by length: the page it was shown with a successor in it, or the whole
    list a host went and fetched after hearing `openThread`.

  Nine new `init` fixtures come with it — one per paged component, small enough
  that the footer is somewhere to be seen in the storybook.

- **The render-time filter asks the tree what it could possibly find.** Every
  rule in `vdom/filter` asks two things of an attribute — does its NAME concern
  me, and is this render's VALUE allowed. The second is why the filter exists at
  all: a value is a `Val` expression until state produces it. The first is not
  like that. **Every attribute name in a view is a literal**, the same fact
  `Policy::check_view` rests on, so which rules an element could ever concern is
  the same answer on every render — and for almost every element the answer is
  "none of them".

  `@sinks.SinkHints` is that answer: four bits (`url`, `handler`, `css`,
  `markup`), computed by `render` off anode's attributes with `vdom/filter`'s own
  predicates, memoized on `DomData`, and handed to a new
  `VdomFilter::filter_elem_hinted`. A rule whose bit is clear returns without
  reading the attribute map at all. A `<div class= id=>` pays a field read where
  it used to pay a walk of its attributes and, for the CSS rule, a probe of an
  818-name property set per attribute.

  **What the filter still cost is now inside the noise.** It was +4% to +33% on
  the workloads that rebuild most (`OPTIMIZATIONS.md` §"What the filter still
  costs"); an A/B with only the call site swapped now saves 5–26% of those
  workloads' total time, and the same build measured against no filter at all
  comes out within the machine's own drift. §13 has the table.

  Three things about how it is built, since each was a design choice with an
  alternative:

  - **The type lives alone in `sinks/`, importing nothing.** `render` produces
    the fact and `vdom/filter` consumes it, and those two cannot name a type in
    each other's package: `vdom/filter` is "over `vdom` and nothing else" —
    importing `anode` would put a template compiler behind every render, which is
    why `handler.mbt` duplicates a two-line prefix test rather than import one —
    and `anode` is imported by everything, so a type it holds must not drag a CSS
    tokenizer in. Same shape of argument as `anode/sanitize/css`'s.
  - **It is a memo, not a parse result**, for that same reason: the tables that
    decide it are behind a tokenizer and an HTML parser that no consumer of a
    view tree should link. One `Option` test per element per render buys the same
    steady state, since a `DomData` is shared by every render of that element.
  - **Everything defaults generous**, because only a hint that is too NARROW
    could cost a rule: `filter_elem_hinted` defaults to ignoring its hints, so a
    filter this repo does not own still sees every element; an unclassified
    element means `SinkHints::all()`; the fold only ever sets bits. Two tests
    keep it honest — every rule under `all()` does exactly what `filter_elem`
    does, and the `data-*` names `set_data_attr` stamps after the walk concern no
    rule.

### Changed

- **The filter seam takes a POLICY, not a filter.** `App::set_filter` is gone.
  In its place:

  ```moonbit
  app.set_sanitizer(sanitizer)   // what the built-in chain enforces
  app.add_filter(my_rule)        // a rule of my own, BEHIND the built-in chain
  ```

  Two things were wrong with the old shape, and they were the same thing. **A
  filter is opaque**: `&VdomFilter` is a trait object, so "is the one you are
  installing at least as strict as the one it replaces" is not a question any
  code can ask — which means an API that takes one can only offer replacement,
  and replacement includes removal. And **order between filters is
  load-bearing** — a filter that replaces a subtree must run before the ones that
  inspect attributes, `CssFilter` must run before `Baseline` because it rewrites
  what that reads — so letting a host assemble its own chain put that invariant
  in the host's call sequence rather than in `@mdfilter.filter_for`, which exists
  to hold it.

  A `Sanitizer` is a value with structure instead, `add_filter` appends behind
  the built-in chain and there is no `remove_filter`, so the property that
  actually matters holds by construction: **the built-in chain always runs, and
  anything a host adds can only remove more.** Note what is NOT claimed — a
  policy may still widen: dyncomp's does, since a host granting `raw_markup` is
  the caller this seam was built for.

  **Migrating**, and what it costs:

  - `set_filter(Some(@mdfilter.filter_for(s)))` → `set_sanitizer(s)`. That is
    what `dyncomp`'s `set_app` did, and now does.
  - `set_filter(Some(my_filter))` → `add_filter(my_filter)`, with one behaviour
    change to know: an addition runs BEHIND the built-in rules, so a rule added
    to watch for `javascript:` URLs will never see one. It is behind the defense,
    not beside it.
  - `set_filter(None)` → **nothing**. There is no opt-out. Of the three reasons
    the docs gave for wanting one, a deliberate `javascript:` URL is no longer
    expressible (accepted deliberately: it was rare, and the alternative was an
    API where every app's defense could be removed by one call somebody wrote for
    one link), an all-developer-authored tree was "hard to promise" when it was
    written, and a render loop hot enough to notice was measured away by the
    hints above.

  Three tests went with the call. They mounted with `set_filter(None)` to pin the
  SECOND layer — a directive whose filter never ran renders an empty element,
  `set_prop` refuses a structured value on `href` — which is not an app property
  and stays pinned where it lives, in `render/render_wbtest.mbt` and
  `vdom/memdom/custom_element_test.mbt`.

## [0.20.0] - 2026-08-14

### Added

- **A CSS value validator: a subset parsed and re-emitted, instead of a name
  refused.** `anode/sanitize/css` reads a declaration list against a policy,
  refuses everything it does not understand, and writes back a CANONICAL form.
  Nothing it admits is a substring of what it was given, so a list that survives
  contains no byte the validator did not choose.

  Two ordered levels — `Constant` (paint and typography, no function anywhere)
  and `Computed` (layout, the colour and maths functions, gradients, `var()`) —
  and three switches that are separate from them because they are separate
  questions: `overlay` (can it leave its box), `url` (`NoUrl` / `FragmentOnly` /
  `Screened`), and `stylesheet` (may a `<style>` element survive). Three named
  policies cover the real cases: `deny()`, `payload()`, `app()`.

  What it bought:

  - `@setinnerhtml`, `@setinnersvg` and `@setinnermd` payloads may paint and lay
    themselves out again. They carried NO CSS before — `without_css` dropped the
    `style` attribute by name, because there was nothing that could tell
    `color:red` from `background:url(//evil.test/p)`.
  - **`Build`'s two sanitizers collapsed into one.** Narrowing CSS at the
    markdown filter used to take GFM column alignment with it —
    `style="text-align:left"`, which `build.mbt` writes itself — so the split was
    who AUTHORED the value, a question a name rule cannot ask. A value rule does
    not need to ask it: the alignment is admitted at the smallest level there is
    and a payload's `url(…)` is admitted at none.
  - **An untrusted dyncomp guest may state a constant style.**
    `fill="#1da1f2"`, `stroke="currentcolor"`, `style="display:flex;gap:4px"`,
    and `fill="url(#grad)"` pointing at a gradient it defined itself. A DYNAMIC
    value in one of those names stays refused, because `check_view` runs at
    registration and nothing downstream would look at what it could not see.
  - `@filter.CssFilter`, for an app's own tree. **Not** in `Baseline`: `app()`
    refuses an unquoted `url(/logo.png)` and `!important`, both ordinary in
    app-authored CSS, so making it the default would cost real pages for a threat
    model the payload filters already cover.

  Two findings shaped it, both in `docs/css-validator.md`:

  - **`mizchi/css/token` does not decode CSS escapes**, so
    `background-image:\75 rl(https://evil.test/p)` tokenizes as `Ident("75")
    Whitespace Function("rl")` while every browser reads `url(`. `Token` carries
    no source span, so nothing downstream can recover the spelling — which means
    no name comparison over that token stream is sound. The answer is to refuse
    a backslash outright, on the raw input: an escape spells a character you
    could have written directly, and no level here needs one. (Its `peek_char`
    also returns U+0000 for end-of-input, so an embedded NUL is indistinguishable
    from EOF; css-syntax-3 §3.3 preprocessing runs first and removes it.)
  - **Re-serializing CSS is SAFE, which is the inverse of the rule
    `docs/sanitizer.md` argues for HTML.** A sanitized HTML payload becomes
    NODES, so writing it back out as text adds a second parse that can disagree —
    mutation XSS. A CSS value is never nodes: it reaches the browser as a STRING
    the browser parses either way, so emitting our own canonical form removes the
    chance that ours and theirs disagreed rather than adding a parse.

  The property facts are **generated**, by `scripts/fetch-css-properties.mjs`
  from w3c/webref's CSS extracts at a pinned commit (plus mdn/data for the colour
  keyword tables, which css-color states as prose). It emits only what a
  specification states — 818 property names, which 33 transitively reach a URL,
  which reach a string or a colour, the keywords each grammar admits — and the
  POLICY stays in MoonBit beside the argument for it, held against the facts by
  tests. `moon run dev -- css-properties` regenerates and drift-checks.

  That paid for itself immediately: `untrusted_sink_attr` names fourteen CSS
  sinks by hand and the specs name thirty-three. Six of the misses are properties
  a level here admits, including `background` — the shorthand containing the
  `background-image` that IS on the hand-written list. None was a live hole,
  since the `style` attribute was refused wholesale, but reopening it is exactly
  what this change does.

  New dependency: `mizchi/css@0.7.3`, of which only `mizchi/css/token` is used —
  673 lines over `moonbitlang/core/string`. Its parser is not: `parse_inline_style`
  returns a layout engine's `Style`, which cannot round-trip a declaration list.

### Changed

- `Sanitizer`'s `no_css : Bool` is now `css : @safecss.CssPolicy`.
  `without_css()` stays and means `with_css(CssPolicy::deny())`; `with_css` is
  the general form. `Sanitizer::attribute_value` is the new value-side
  companion to `attribute_allowed`, routing `style` as a declaration list and an
  SVG presentation attribute as one property's value.
- `Policy::with_sanitizer` now carries the CSS policy across rather than taking
  the freshly compiled sanitizer's default, so a host tightening its element
  allow-list does not silently widen what a guest may paint with.
  `Policy::with_css` sets it directly.

## [0.19.0] - 2026-08-14

### Added

- **Config vars: one bundle, any instance.** A manifest can now declare
  variables — a name, a type, a default and a sentence saying what it is for —
  and a host binds them at load (`@policy.Policy::with_config`). The guest reads
  them through a new `tutuca:component/config` interface; a view names one as
  `$$mediaOrigin`, which resolves AT PARSE TIME to the string the host bound.

  `guests/mastodon` is the worked example and the reason. It could only ever
  read mastodon.social: the origin was hardcoded in nine `:src`/`:href` literals
  AND as two constants in the wasm, so pointing it at hachyderm.io meant editing
  two files that had to agree — and getting one wrong produced a timeline with
  no pictures and no error, because `media_path` discarded every url before a
  view saw one. It now names no host anywhere. Both halves read the same
  configured string, so they cannot drift.

  **The security invariant got stricter, not looser.** Before: the origin is a
  literal the guest wrote and the host allowed. After: the origin is a literal
  the HOST wrote. Both are settled before anything renders, and
  `external_url_refusal` is unchanged — it sees an ordinary pinned `Const`.
  Four things hold that boundary, each load-bearing:

  - a manifest DEFAULT is not a grant. An unbound `origin` reaches the guest and
    never a view, or a bundle could grant itself an origin by writing one in its
    own file. A page that ships the archives it loads opts in with
    `trusting_manifest_config`.
  - the type is stated by BOTH parties and a disagreement refuses the bundle.
    Otherwise a manifest could declare `type: "origin"` for a variable a host
    bound as prose and turn a string into a network grant.
  - only an `origin` reaches a view (`Policy::view_config`), because `$$name`
    becomes a `Const` the URL rule will pin.
  - both of `register_bundle`'s parses — the tree that renders and the throwaway
    tree the policy screens — get the same table, or the check is about a
    document nobody displays.

  The sharp edge, written into SECURITY.md §3a: **binding an origin is granting
  it.** `with_config` adds `cap-external-urls` and the origin together, because
  they are one decision — the same reasoning `allowing_external_urls` already
  used for fusing its list and its grant.

- **A bundle's identity is its module AND its config** (`Bundle::key`). Three
  maps keyed on the module name alone, and `glue.mbt`'s `on_loaded` called
  `tcomp_drop_bundle` on the previous one — so loading the same archive under a
  second configuration did not add a sibling, it TORE DOWN the first. A
  mastodon.social reader and a hachyderm.io reader now coexist. Reloading with
  the same config still hot-swaps, which is what that always meant; it just says
  so now. `by_key` is the identity, `by_name` stays a convenience index, and
  every lookup takes either.

- **`@setinnerhtml` and `@setinnersvg`: markup you did not write, without the
  escape hatch.** `@setinnermd`'s siblings, for a payload that is already
  markup — a CMS body, a server-rendered fragment, a chart another program drew.
  The payload is parsed ONCE and walked into described nodes, with every element
  and attribute value judged by the app's own `@sanitize.Sanitizer`; no HTML
  string is handed to the browser, so there is no second parse to disagree with
  the first. `App::new` installs the filter, so both work with no setup.

  Neither takes a permission, and the reason is worth stating because "we
  removed the safety check and renamed it safe" would be the wrong change.
  `raw_markup` gates `@dangerouslysetinnerhtml` because that directive's
  fallback is `set_inner_html` — nothing in the types says a host installed the
  filter. These two fail CLOSED in `set_prop`, like `@setinnermd`: no filter,
  empty element. There is no unchecked path to permit.

  The capability is also not new. `@setinnermd` already routed a markdown
  document's HTML blocks through the same builder with no permission, and
  `MdFilter` is installed by default — so "an arbitrary runtime string becomes
  sanitized HTML nodes" is what a default app has always done. An author who
  wanted it just had to wrap the payload in markdown to reach it.

  `@setinnersvg` differs in one thing: it parses in SVG context. A bare
  `<circle/>` works with no `<svg>` root of its own, and the payload cannot
  leave the namespace it was promised — the one route back to HTML is
  `<foreignObject>`, whose contents the parser labels HTML and the sanitizer
  therefore judges as HTML.

  In `dyncomp`, an **untrusted** guest may use none of the three
  runtime-markup directives. That refusal is about egress rather than XSS: an
  `<img src>` the sanitizer is happy with is still a request to an origin the
  guest chose, from the host's page.

  No new dependency. The HTML parser was already linked by `MdFilter`, and the
  CSS question below is answered by refusing rather than parsing, so
  `mizchi/css` did not have to become one yet.

### Changed

- **`tutuca:component@0.6.0` → `@0.7.0`**, and manifest `apiVersion` 6 → 7. The
  world gained `import config`; nothing existing changed shape. All ten guests
  regenerated and rebuilt, `cardwasm` emits the new world, and the harnesses
  bind the new interface. `examples/dyncomp-dice` is NOT migrated — it was
  already stranded at `@0.5.0`, still exporting the `get-manifest` that 0.6
  removed, so bringing it forward is a port rather than a rename.

- **`pinned_prefix` reads the leading literal RUN of a template**, not just its
  first part. `$'{$$origin}/{.path}'` splits into three parts whose first two
  are both settled, and refusing that spelling would have been a rule about
  where the `/` was typed rather than about what the origin is.

- **`@shell.sample_policy` no longer names Mastodon's two origins** — there is
  nothing left in that bundle to name them for. It uses
  `trusting_manifest_config`, which is the right shape for a page that ships the
  archives it loads and the wrong one for a page that does not.

- **`examples/dyncomp-dice` is a `@0.7.0` guest**, having sat at `@0.5.0`
  through two package bumps. It was not a version string: the die still
  exported the `get-manifest` and `seq-entries` that 0.6 removed, and carried
  its declaration as a `dice_def()` in MoonBit source. It now has a
  `manifest.json` and a `views/Dice.main.html` like every other guest, and its
  handler returns `HandleResult` — so it distinguishes "handled, nothing
  changed" from "never mine", which the old `&DynComponent?` collapsed.

  The reason it rotted is the part worth fixing: no script knew where it was.
  `guests/guests.mjs` now carries an `OUT_OF_TREE` map, so `gen-bindings.mjs`
  regenerates it and `dev/tasks.mbt` builds and packs it with the rest — and
  the existing guest-list drift check holds the two lists together. It is
  offered as a sample on the universal demo, because its own page cannot host
  it: that example builds against the PUBLISHED package and imports one this
  repo added since, so a guest nothing can run is a guest nothing notices going
  stale.

- **`@shell.sample_host_requests` serves `roll`.** The sharper demonstration of
  the request seam than `double`: the counter could compute its answer and asks
  as a courtesy, while the die genuinely cannot make a number and declares no
  `cap-random` to avoid being a bundle some pages cannot run.

- **SMIL is refused by the sanitizer baseline.** `<animate>`,
  `<animateMotion>`, `<animateTransform>` and `<set>` assign the attribute
  named by `attributeName` in the browser — *after* the registration-time pass
  has read the tree and after the render-time filter has read the built nodes.
  `<a><animate attributeName="href" to="javascript:…"/></a>` therefore showed
  both passes an `href` that is not the one that would navigate. `dyncomp`
  already refused all four for an untrusted guest; the baseline did not, and a
  plain app has no registration-time pass at all — it reached the same markup
  through `@setinnermd`'s HTML blocks. There is no value here to inspect and no
  later point to inspect it at, which leaves refusing the element.

- **`style` and `<style>` are dropped from a sanitized markup payload.** The
  new directives, and `@setinnermd`'s HTML blocks, run under
  `@sanitize.Sanitizer::without_css`. CSS is not script, but `url(…)` is a
  request to an origin the payload chose and a fixed-position overlay is a click
  somebody thought they were giving to something else — and there is no CSS
  parser here to tell the difference (`dyncomp/SECURITY.md` §4 has the plan).
  Markdown's OWN `style` is untouched: GFM column alignment still renders,
  because the split is who authored the value. `@dangerouslysetinnerhtml` is
  unchanged — unaltered markup is what it is for.

### Fixed

- **`on_loaded` stopped populating the module-name index.** Rekeying the bundle
  tables on `Bundle::key()` replaced the `by_name` write instead of joining it,
  and every entry point this bridge publishes takes a module NAME — so
  `make_instance("mastodonlib", "Status", …)` answered None and a page could
  load a bundle and then not place anything from it. Caught in a browser, not
  by a test: `glue.mbt` reaches the JS bridge through `extern "wasm"`, so
  nothing in `moon test` can drive it.

- **A `javascript:` URL under `xlink:href` survived the URL rule inside any raw
  markup payload.** `moonbit-community/html` implements the WHATWG "adjust
  foreign attributes" step faithfully and returns the name space-separated, so
  `xlink:href` in a payload arrived as `xlink href` — and every rule in the tree
  knows the colon form, because that is the only spelling a view can write. It
  would then have reached `set_attribute("xlink href", …)`, which throws on the
  space, so this was latent rather than live; relying on that is relying on an
  accident of the DOM API. The name is folded back before any rule reads it.

- **Drop reports name the directive the author wrote.** Four directives reach
  the shared markup builder now, so a report saying `dangerouslySetInnerHTML`
  was wrong in three of them — and a developer reading a drop log wants the
  attribute in their own view, not the builder's internal constant.

## [0.18.1] - 2026-08-13

### Fixed

- **A contract compiled everywhere except in a browser.** `gen-views` turns a
  `requires` / `ensures` / `invariant` into a guard that calls
  `@tutuca.precondition_failed(…)`, and in the playground `@tutuca` is the
  module-root facade rather than `core/` — which re-exported four types and no
  functions. So a card with a rule compiled in the repo, in the CLI and in every
  `moon` package, and failed in the one place an author writes one in a browser:
  `Value precondition_failed not found in package tutuca`. The facade now
  re-exports the three reporters, and the refusal channel with them, since a
  page that can be told a rule refused something and cannot ask to hear it is
  half a feature.

  It shipped unreachable because nothing tested it: the storybook example with
  contracts is compiled by `moon` against `core/`, where the name resolves, and
  no landing-site example has a rule at all. `check-viewgen-tab.mjs` now carries
  a `probe:contracts` case — inline, since the landing page should not grow a
  card nobody asked for to hold a regression test — which generates, compiles
  and links a block with a precondition and an invariant on both backends.

## [0.18.0] - 2026-08-13

### Added

- **A rule can say what went wrong, and the runtime can say that anything went
  wrong at all.** Two halves of one silence. A `pred` may now carry a `format`,
  and `@tutuca.on_refusal` is the channel the answer leaves by.

  ```html
  /// A post needs a title before it can go out.
  pred hasTitle
    format $'Cannot publish "{.slug}": the title is empty.'
  { (trim .title) is not '' }

  on publish requires hasTitle { .published = true }
  ```

  The doc comment and the format do different jobs, which is why a rule wants
  both: the comment says what the rule IS, statically, and the format says what
  went wrong THIS time, with the values that made it go wrong. It is an ordinary
  expression — almost always the `$'…'` template the views already interpolate
  with, so there is no second interpolation syntax — evaluated against the state
  that was rejected, and it describes the FALSE case, because a predicate is true
  when things are fine. `pred` and `invariant` only: a `compute` that might
  answer the string "ok" has no false case to describe. The checker walks it like
  any other expression (a typo in `{.slgu}` is reported where it is written, not
  as an empty sentence at the moment somebody most wants to read one) and asks it
  for a string, since a bare number is provenance rather than a sentence.

  The channel is the other half, and it exists because `Path::update` decides
  between four outcomes and hands back the same root for all four: an
  unresolvable path, a name nothing answers, a handler that declined, and a
  handler that ran and changed nothing. The success path and the failure path are
  byte-identical, which is why this framework is hard to break and why a click
  that did nothing has never been distinguishable from a click that was refused.
  A `Refusal` carries the code, what was asked for, which rule said no, the
  sentence that rule produced — and the state that was rejected, which is the
  thing you actually want to look at and the thing nothing could reach before.

  Four decisions worth stating, because each of them is a way this could have
  become noise nobody reads:

  - **A decline is not a refusal.** An `update` arm answering `None`, and the
    generated mutator behind it, are the intended design and stay silent. What is
    reported is a name nothing claimed (`NO_HANDLER`), a leaf that was not there
    (`PATH_UNRESOLVED`) and a rule that said no (`PRECONDITION` /
    `POSTCONDITION` / `INVARIANT`).
  - **Five codes, not eighteen.** The design this comes from names
    `NO_REQUEST_FN`, `DECODE_FAILED`, `COERCED_TO_DEFAULT`, `OUT_OF_RANGE`,
    `TELEPORT_MISSING` and more. None of them is here, because a code nothing
    raises is a promise the runtime does not keep — a host filtering on it would
    conclude the failure never happens. A case arrives with the site that raises
    it, in the same change.
  - **One dispatch, one record.** A refusal is reported where the chain ends;
    everything above it on the way out is the same failure being handed back.
  - **Off until a host asks.** A record carries the rejected state, so building
    one is not free. With nothing listening the report is the line `warn` has
    always printed — now carrying the sentence too, since that half is the
    author's and belongs in whichever door the report leaves by.

  Both backends keep it identically, which is the property the corpus exists to
  hold: the card interpreter evaluates the sentence over the state it rejected,
  and the MoonBit backend compiles it into the guard beside the rule, with the
  state encoded through `@component.Fields::encode` inside the refusal and
  nowhere else. The one asymmetry is deliberate and one-directional: a sentence
  that would need a GUARD is dropped by the compiled backend, because a guard
  stands in front of the condition and a message about a failure must never be
  able to cause one.

  For tests, `@harness.refusals_while(body)` collects what a stretch of driving
  refused and `@harness.no_refusals(body)` fails on it — which is what makes a
  test about a guarded button mean something. `h.click(".publish")` on a
  component whose precondition declines passes today, and a wrong selector passes
  the same way.

- **`guests/bluesky`, `guests/slack` and `guests/mastodon` say the things their
  prose was already saying.** The bundles drew cards that looked more complete
  than the text beside them, and in the same three ways.

  **Why a message is in front of you.** `Post` takes `repostedBy` and `pinned`.
  Without the first, a stranger's post drawn in an account's feed reads as
  something that account wrote — the one wrong claim a reader cannot detect by
  looking harder, and the one the prose has spelled `[reposted by @alice]` for
  as long as there has been a feed. It is drawn as a line ABOVE the card:
  rewriting the author to say it would attribute the post to the reposter.

  **A feed is not a conversation.** New `blueskylib/Feed`: same rows, same
  children, no reply vocabulary. A timeline, an author's posts and a page of
  search results were all rendered by `Thread`, which drew them correctly for the
  wrong reason — the rails and the fold button degraded to nothing, which is not
  the same as meaning nothing.

  **What the answer does not cover.** New `Scope` in all three bundles, hung
  under `Feed` / `Thread` / `Timeline` and under `ChannelHistory` / `FileList`,
  from a plain record whose keys are its own field names. It is not an error and
  not a warning: it is the sentence that turns a count into a claim someone can
  check, and it is what makes the card as honest as the text. `blueskylib`'s and
  `mastodonlib`'s are field-for-field the same component, deliberately — a host
  drawing both should not have to learn two spellings of "this is not
  everything" — while `slacklib`'s differs because what a Slack answer leaves
  out is conversations rather than pages of a feed.

  Beside those: `Post` reads the three embeds that used to draw as bare text
  (`external`, `quote`, `video`) and the `labels` it was dropping — the one
  dropped field that was a safety question rather than a fidelity one. `Profile`
  says when the account was created and what it pinned. `blueskylib/Feed` takes
  a `title`, the way `mastodonlib/Timeline` already did: three flat messages
  cannot say whether they came from a timeline, an author or a search, so
  whoever asked for them is the one who says. `slacklib/Message` draws
  its `ts` — the argument every follow-up call takes, which lived in a field no
  view mentioned — and takes a `permalink` it shows and emits rather than
  follows, since a workspace subdomain is not an origin a view can name.
  `slacklib/Thread` tells `replyCount` (how many exist) apart from
  `replies.length()` (how many arrived), so a collapsed row with twenty-one
  replies and none loaded says so and names the call that would load them
  instead of offering a caret that expands onto nothing. New
  `slacklib/FileList`, for the file listing that had no card at all.

- **`guests/mastodon` — the fediverse as a `tutuca:component` bundle: one post
  (`Status`), its poll (`Poll`), a conversation (`Thread`), a feed (`Timeline`)
  and an account (`Profile`), styled after mastodon.social/explore.** It is
  `guests/bluesky`'s sibling on purpose: the same job, the same policy, the
  other big open network — and reading the two together is what shows that the
  boundary is a shape rather than a special case, because Mastodon pushes
  against it in three places bluesky never touches.

  **The rich text has to be found before it can be cut.** ATProto hands a reader
  facets — byte ranges with a kind — so bluesky only slices on them. Mastodon
  hands a reader `content`, which is HTML, and no tier may emit markup. So this
  guest scans the plain text for `#tag`, `@mention` and `https://…` itself, and
  then links a run only when the record's own `tags` / `mentions` confirm it:
  `@bob` links when the server resolved it, `@nobody` beside it stays text. Only
  a server knows which of those shapes is an account rather than somebody's
  email address, and a viewer that guessed would be inventing links into the
  fediverse out of punctuation. A link is shortened the way Mastodon shortens
  one — no scheme, cut at 30 with an ellipsis, which is exactly what the
  `invisible` / `ellipsis` spans in its own HTML do — with the whole url in the
  tooltip, because its origin belongs to whoever posted it.

  **Federation turns out not to need more origins.** A federated timeline holds
  posts from every server there is, so naming their picture hosts as literals
  looks impossible — until you notice that an instance PROXIES what it
  federates: a remote account's avatar is re-served from
  `files.mastodon.social` under `/cache/`. So this bundle spends
  `cap-external-urls` on the same two-origin shape bluesky uses
  (`files.mastodon.social` for every picture, `mastodon.social` for every link),
  and one host really does draw the whole timeline. The one thing proxying does
  not fix is a remote post's permalink, which is a page on the server that holds
  it — so that stays selectable text, exactly as a posted link does.
  `@shell.sample_policy` grants the two, so both demo pages show it.

  **And a poll share is an element rather than a stylesheet.** An untrusted view
  has no `style`, so a bar cannot be a width. bluesky draws a reply indent as N
  spacer elements because HTML has nothing that means "indent" — but it does
  have something that means "a fraction of a whole", and `value` is neither a
  network nor a CSS sink, so `<progress :value max="100">` needed nothing
  reopened for it.

  Two smaller things the harness pins because the tempting implementation gets
  them wrong: `Timeline` builds its rows ONCE and filters among them, so a
  favourite survives typing in the search box (rebuilding from the matching
  records would throw away everything the reader did), and a `Poll` owns which
  option is picked rather than letting an option own it, because one choice
  un-picks the previous one and moves every share.

  `dyncomp/test/mastodon-harness.test.mjs` drives all five over the contract.

## [0.17.0] - 2026-08-13

### Added

- **The two readers spend `cap-external-urls`, and the capability stops being
  theoretical.** 0.16 shipped it with the guest that motivated it still drawing
  initials — the reasoning was that a reader which cannot fetch is the point,
  and that was the right call for a capability nobody had used yet. It has been
  used now, by the two bundles whose whole subject is other people's records,
  and what it looks like in practice is smaller than the doc made it sound.

  `bluesky` names two origins: `cdn.bsky.app` for an avatar, a profile banner
  and an attached image's thumbnail, and `bsky.app` for the links — a mention, a
  hashtag, a permalink. `slack` names the three a profile picture actually comes
  from (`ca.slack-edge.com`, `avatars.slack-edge.com`, `secure.gravatar.com`),
  one `<img>` each, because a bundle that named only the first would draw
  initials for half a real channel. Every one of the five is a literal in a
  view, so the list of hosts either bundle can reach is a thing you read rather
  than a thing you trust.

  The guests supply only the PATH. An avatar arrives as the full url the API
  hands out and goes through `cdn_path` / `avatar_path`, which keep what follows
  a known origin and refuse everything else — including, deliberately,
  `https://cdn.bsky.app.attacker.test/…` and `https://cdn.bsky.app@attacker.test/…`,
  the two that pass a prefix test written without the trailing slash. A picture
  anywhere else is simply not drawn.

  **And the fallback is a layer rather than a branch.** The `<img>` sits over
  the initials disc instead of replacing it, so a record with no picture, one
  hosted where no view points, and one whose fetch fails after all of that land
  on the same two letters. An untrusted view has no `onerror` to write and turns
  out not to need one — which is the sort of thing that only shows up once
  somebody uses the capability for real.

  What did NOT change is the line the guests draw around it. A link somebody
  POSTED still cannot be an `href` in either bundle: its origin was chosen by
  whoever wrote the message, so no view can name it, and it stays styled text
  with its target in the tooltip (slack keeps emitting `openLink`). That is the
  same rule as the avatar, not an exception to it — the difference is who picked
  the origin.

  Both demo pages grant exactly those five origins through the new
  `@shell.sample_policy`, beside `sample_host_requests` and for the same reason:
  two pages ship the same archives, so two copies of an answer about the network
  are two copies that can drift. The tier is untouched — still `untrusted`, no
  clock, no timer, no entropy, no bundle CSS — and the doc comment says what a
  DROPPED bundle gets out of the grant, because it gets it too. Verified in a
  browser rather than by reading: 22 of 28 message avatars load, the six that do
  not show initials, and the bluesky cards draw a banner, an avatar and a
  thumbnail off the CDN with the permalink a working link.

- **Three more starter cards: `file-picker`, `styles` and `contracts`.** Two of
  them exist because 0.16 made them possible and one because the selector had a
  hole in it.

  `file-picker` is the example that `f.name` was for. Its MoonBit arm was a
  `match` that pulled `name`, `size` and `type` out of a `Value::Map` one
  `unwrap_or` at a time, and the card is four assignments off a parameter —
  `@on.change="pick value"` hands the handler the whole file and the handler
  reads fields off it. It is also the first card whose only event is a
  `change`, which is how the shell bug below was found. The two formatters stay
  in MoonBit and the card says the size in bytes: a card should not pretend to
  be a place to write `format_size`.

  `contracts` is the trio with a runtime behind it. The landing site's tutorial
  step 8 had been the only place any of it ran, and a starter card is what
  somebody opens first. `seat` asks a precondition, `seatAll` and `rush` both
  claim the same postcondition — `rush` seats one person, so it keeps the claim
  exactly when one was all there was and is abandoned otherwise — and
  `withinCapacity` is an invariant that `overbook` never mentions and cannot
  escape. Every refusal names its rule in the console, which is the half that
  distinguishes a contract from an `if` at the top of a body.

  `styles` is the deliberate exception to the rule that these cards are written
  in margaui classes, and it earns it by showing what a class list cannot: a
  `<style>` inside a template scoped to that view, the file's common block
  shared by every view of the component, and a `data-global` block that is
  injected once for the page. Verified in a browser rather than by reading:
  `.mine` colours the card and leaves an identical element outside it alone,
  and `.styled-global` reaches both.

- **The card playground answers requests now, and a `requests` card asks.**
  `request` has been an effect the block language spells since the language had
  effects, and on this page it had nothing to reach: every name went out and
  came back "not found". That was honest — it is what the tutorial's step 7
  shows on purpose — but a card could not demonstrate the ordinary path, which
  is a host that answers.

  So the host registers three fixtures for every card it mounts: `rows` answers
  a list, `echo` answers the first thing it was handed, and `fail` answers an
  error. Fixtures rather than an API, because a request is a NAME and what the
  name means is the host's business — a page with a real fetch registers the
  same names against it and the card does not change. A name that is not among
  them still comes back unanswered, so nothing the tutorial says stopped being
  true, and `tut-7-response` still shows `Request not found: loadQuote`.

  They answer LATE, on a `setTimeout`, and that is the point rather than a
  simulation detail: a request answered inside the transaction that raised it
  never shows a card its own loading state, which is the half of asynchrony an
  author has to write for. Answering late means a card can be torn down — this
  page remounts on every keystroke — before its answer arrives, so each slot
  carries a generation and a fixture built for an older one stays quiet.

  The `requests` card is all three paths in one file: `receive init` asks, the
  loading line shows for as long as the ask takes, a `response` arm per request
  name unpacks the pair, and `break it` walks the error path with nothing
  mocked. It is the demo `storybook/examples/request` could not be — that one
  renders its rows as child components, which a card still cannot hold.

### Changed

- **The examples caught up with the two newest features.** `new` / `@cur` and
  the contracts each shipped with a corpus and a reference paragraph, and an
  audit of every `<script type="tutuca/script">` block in the tree found the
  examples still written as though neither existed.

  The storybook's bar chart is the clearest case: `addBar` and `removeBar` each
  wrapped their whole body in an `if` over a limit, and the comment above them
  defended the silence — an arm that claimed the name and moved nothing. They
  ask `requires hasRoom` / `requires hasSpare` now, which refuses the same
  presses and *says so*: the tenth press prints ``contract: `addBar` declined —
  its precondition `hasRoom` does not hold``. `randomize` stays a MoonBit
  handler and is therefore not one of the transitions the block's rules cover,
  which the comment now says rather than leaving to be discovered.

  Tutorial step 8 named all three kinds of rule and ran two. `pushAll` is the
  third — `on pushAll requires canPush ensures hereEmpty`, both clauses on one
  header, which is the shape the prose beside it describes and no card had. A
  card test pins it: the runtime had a test for an invariant refusing a handler
  that never mentions it, and none for a handler that asks and promises at once.

  Step 4's prose is the third gap, and the one the sweep got wrong first. It
  teaches `new Song` / `.songs.push @cur` beside a card whose `songs` is an
  `Array[String]` — a snippet that is a type error against the schema the
  reader is looking at. It says it is hypothetical now, and points at
  `nested-state`, the starter card where all of it runs. That card is also what
  the sweep missed: it read `.html` and `.md`, and the starter deck is JS
  string literals, so "no runnable example" was a fact about the search and not
  about the tree.

- **The skill documents `new` / `@cur`.** `skill/tutuca/schema.md` carried the
  contracts from the day they shipped and nothing at all about building a
  value, so an agent reading the skill could not write a record. The new
  section is the statement, the target, the six rules that follow from "a value
  is built by mutating it", and the three limits that belong to the
  ahead-of-time backend only — a `new` inside an `if`, an index into `@cur`,
  and `@cur = expr` with no `new` above it — each of which refuses the arm and
  falls through to your `update` rather than miscompiling. Every claim was
  checked by putting the section's own example through `gen-views`, which is
  how the third limit was found: it is not in the changelog entry that added
  the feature.

### Fixed

- **The card playground's State and Activity panes did not follow a `change`.**
  They were redrawn from capture-phase `click` and `input` listeners on the
  preview, which covers every card that had shipped — and misses a file input,
  whose click opens the chooser and whose redraw therefore lands before a file
  exists. The panes then sat on the previous state until the next click
  anywhere in the preview, which reads as "the handler did not run" for the one
  card where the handler is the whole point. The three names are one list now.

## [0.16.0] - 2026-08-13

### Added

- **`cap-external-urls`: a picture an untrusted bundle chose, from an origin
  the host did.** The Bluesky reader draws an avatar as the author's initials
  in a circle, and its README explains why: the untrusted view-authority rule
  refuses `src` and `href` by NAME, because what `:src=".avatar"` will hold is
  unknowable when the view is registered. That rule is right and the conclusion
  drawn from it was too strong. What cannot be known ahead of time is the
  VALUE; what can be known is the ORIGIN, whenever the view states it as a
  literal.

  So the fourth capability. `Policy::untrusted().allowing_external_urls(["https://cdn.bsky.app"])`
  grants it and names the origins in one call, because they are one decision —
  a list with no grant permits nothing and a grant with no list permits every
  `https://` origin there is, and both of those are policies somebody writes by
  accident. It reopens exactly two attributes, `src` on `<img>` and `href` on
  `<a>`, and only for a value whose literal head runs through the `/` that ends
  the authority: `<img :src="$'https://cdn.bsky.app/img/avatar/plain/{.did}/{.cid}@jpeg'">`
  is allowed, `<img :src=".avatar">` is not, and neither is a relative URL —
  `/logout` is a request to the HOST's origin with the host's cookies on it,
  which is a different grant from "may load pictures from a CDN".

  Decidable at registration for the same reason the sink-name rule is, and
  fussy in the two places that decide whether it means anything: `origin_of`
  refuses userinfo, so `https://cdn.bsky.app@attacker.test/` does not read as
  the CDN to a prefix comparison the way it does to every string-matching
  allowlist that has shipped this bug, and it refuses a backslash, a control
  character or a space in the authority, where the browser's own normalization
  would move the boundary after the check.

  What it does not pretend: an image is a GET the guest chose and the path is
  still the guest's to write, so an allowed origin is an origin that can be
  told things. Naming origins is what turns "this bundle can talk to anyone"
  into "this bundle can talk to the CDN its pictures are on"; the empty list
  means any `https://` origin and is the form to justify before using.
  `dyncomp/SECURITY.md` §3 carries the rest of the limits, including why
  `<iframe src>`, `<form action>`, `srcset` and the CSS sinks stay refused with
  it granted. The Bluesky reader still draws initials — it is the guest that
  shows what the strict tier looks like — and its README now says what a page
  that wants the pictures would say instead.

- **Contracts: `requires`, `ensures` and `invariant`, kept by the runtime.**
  The block language could already NAME a rule — a `pred` is the subset of
  `compute` whose answer is declared a boolean — and `script_spec.mbt` said an
  invariant would attach to one "later". Nothing did. So a precondition was an
  `if` at the top of a handler, a postcondition and an invariant were a badge
  in a view and an `assert_eq` in a test, and the tutorial step that introduced
  all three had to end by saying nothing enforced any of them.

  A rule attaches at one of three moments now, and where it attaches is what it
  IS: `on push requires canPush { … }` is asked before the body against the
  state as it arrived, `ensures moved` after it against the successor, and
  `invariant conserved { … }` — the ninth declaration keyword — after every
  transition the block declares, including the ones written later that never
  mention it. A rule that does not hold abandons the whole transition: no
  successor and no effects, the answer every other refusal in a body already
  gives.

  **And it reports.** That is the half that matters, and the reason this is not
  just a tidier `if`. "The transition did not happen" is already the
  framework's answer to everything and it is *invisible* — a state that did not
  move looks exactly like a state that had nothing to move — so a contract is
  the author saying which of those silences is a bug.
  `@tutuca.precondition_failed` / `postcondition_failed` / `invariant_failed`
  go through `warn_hook`, the same sink `mk404Handler` and the anode parse
  issues already use, and a host redirects it into an error pane without
  threading anything through a dispatch.

  Both backends keep them, which the corpus pins: the interpreter evaluates the
  rule and answers `Outcome::nothing()`, and `emit_mbt` compiles it INTO the
  arm as a `guard` — before the effect queue is flushed, which is what makes
  abandoning a postcondition cost nothing. The rule is compiled into the arm
  rather than called as the generated method, so the same `pred` written before
  a body and after it reads the two states `s` names at those two points.

  Deliberately small, in the spirit of the rest of the grammar: a clause takes
  a NAME (an expression there would be an `if` with a second spelling), the
  rule it names takes no arguments (one that needs a handler's argument is
  about that dispatch rather than about the component), one clause of each kind
  per handler (two rules become one by naming their `and`), and there is no
  `old` to name the state a transition started from. An `invariant` is a `pred`
  with a role, so `$conserved` still reads from a badge and `@when` still
  filters a row with it — and it covers what the BLOCK declares, not the
  generated mutators a component answers by default.

  Tutorial step 8 uses the syntax it introduces now, and its *cheat* button —
  which used to exist to show a badge going red — is refused by a rule it does
  not mention, with the reason in the console.

- **`f.name`: a path into a handler's argument.** A `@on.change="pick file"`
  hands the handler the whole file — an `Obj` with a name, a size and a type on
  it — and the block had no way to say `file.name`. A bare name was a parameter
  or an application and nothing else, so the way through was a `compute` per
  field per handler.

  A place can be rooted at a parameter now, and the steps below it are the same
  steps every other place takes — so `read_place` walks them, the checker
  resolves them against a DECLARED payload where the schema has one, and the
  MoonBit backend emits the `field_opt(…)` chain the interpreter already walks.
  What tells `f.name` from `f .name` is ATTACHMENT, which was already the rule
  in force (`min .a .b` is two arguments, `min .a.b` is one place), and a
  parameter is the one kind of name that can never be applied. An argument is a
  value the caller handed over rather than a place this component owns, so
  `f.name = 'x'` is refused by the parser, with a message that says what the
  path is instead of listing what a statement may be.

### Changed

- **The landing page's counter card is styled by class name.** It was the one
  card in the tree still carrying a `<style>` block, so the first card a
  visitor meets looked like the least of them — and looked nothing like the
  nine in the tutorial, which is where that visitor goes next. Its views name
  margaui's `card`, `btn`, `input` and `badge` now, the `<mb-card>` on
  `index.html` asks for `margaui`, and the CSS the page compiles is the class
  set the card actually used. The `<style>` block is still the other way to do
  it, and `cards.html` still documents both.

### Fixed

- **A macro call has two guest-controlled halves, and only one was being
  checked.** `visit_untrusted_view` descends a `MacroCall`'s SLOTS — the
  caller's subtrees — and deliberately does not descend its body, which is the
  host's own text. Its ARGUMENTS are the guest's too: `MacroData.attrs` are the
  caller's strings, substituted wherever `^name` appears in that body. Nothing
  read them. A host macro whose body places `^icon` in an `<img src>` therefore
  handed an untrusted bundle the sink the same bundle is refused by name two
  lines away — contingent on the host having macros, which is why it is a gap
  in the walk rather than a hole under everyone.

  Each argument is judged now for the worst position it could land in: a sink,
  so a URL in it is a request the guest chose, and a `class`, so brackets in it
  are guest-authored CSS. Arguments arrive as value SOURCE — `to_macro_vars`
  stringifies the parsed `Val`, so a constant arrives quoted and a template as
  `$'…{…}'` — and the two shapes that state text are read back and held to the
  same origin rule as an attribute. `/logout`, `//attacker.test/pixel` and
  `java{tab}script:alert(1)` are refused; `title="Ratio 1/2"` is not, because a
  macro takes ordinary strings and a rule that made that awkward would be
  traded away.

  The residual is stated rather than papered over, in `SECURITY.md` §3: an
  argument that is an EXPRESSION has no text until it renders, so a host macro
  that pipes a parameter into a URL sink still extends that sink to whoever can
  call it. That is authority the host granted by writing the macro.

  Two neighbouring claims in that document were stale and are corrected. The
  slot case it said "passes `check_view` with no refusal" has not for some
  time: both walks descend slots and both have tests. `ANode::for_each_child`
  still does not reach slots, and that is the contract rather than the bug — it
  is the walk over *structural* children, so an expanded call yields its body
  once instead of its slots twice, which is why `has_raw_html` and
  `collect_classes` both document "call on COMPILED views" and why no policy
  decision stands on either.

## [0.15.0] - 2026-08-13

> This section covers 0.14.0's entries too: the `## [0.14.0]` heading was
> folded back into `[Unreleased]` while the card work was landing under it, and
> splitting it retroactively would guess at which entry went out in which
> tarball. Every version is tagged and dated in git.

### Added

- **`dragKey`, `dragValue` and `dragType`: the drag arguments a handler can ask
  for by name.** A drop fires on the TARGET row, so the SOURCE row's key is the
  one thing it cannot see for itself — it lives only on the render stack the
  drag captured. The only way to ask was `dragInfo`, an `Obj` carrying a
  `lookupBind(name)` FUNCTION, so every drop handler in the repo opened the
  `Obj`, matched an `Fn` out of it and applied it before it could start doing
  its job.

  The three names sit beside `dragInfo` the way `valueAsInt` sits beside
  `value`: `dragKey` is `lookupBind("key")`, `dragValue` the dragged value,
  `dragType` the `data-dragtype` the source declared. All three are `Null` when
  no drag is in flight, which is why all three — and `dragInfo` — carry
  `@tutuca.Value` in a generated `Msg` rather than the type they look like.
  Three lines in the closed table in `render/dom_event.mbt`, and the same three
  named in `viewgen`'s argument-type inference so the two tables cannot drift.

  This is what a **card** was missing: a block cannot apply a function it did
  not name, and it should not learn how to, so `dnd` was the one example in the
  corpus blocked on something small. `drag-reorder` is in the card selector now
  — a filter, a `pred`, and one `on moveRow(target, source)` whose two arms
  read `.items[source]` before they mutate and account for the shift the insert
  just caused. `dragInfo` is unchanged beside them, for a handler that needs a
  bind the three do not name.

- **The card playground edits in CodeMirror now, by default.** Both of its
  editors — the raw card and the structured pane — were textareas with a
  hand-drawn line gutter beside them, on the reasoning that the page's claim is
  a card needs no build step and a highlighting dependency would be the largest
  thing on it. The dependency is already in `dist/tutucard/`: `<mb-card
  codemirror>` upgrades to it, and the page shipped it without using it. So the
  page upgrades its own textareas to the same editor, and the reasoning survives
  as the fetch order — the bundle is asked for AFTER the first card is mounted
  and typeable, so the 330 KB is never in front of the page, and an import that
  fails leaves a working textarea and a line in the console.

  `?editor=plain` keeps the textareas: a page that fetches nothing extra, and
  the first thing to try when the highlighting is what looks broken.

  What the editor knows that the gutter could not. The raw pane reads a card as
  what it is — a view file — so a directive is coloured apart from an attribute
  and the tutuca blocks inside it are coloured as the language they hold, rather
  than as a `<script>` element's grey text. The structured pane follows its own
  tabs: the block language for `state` and `handlers`, the view language for a
  view. And an issue is an underline on the exact characters with the message on
  hover, where the gutter could only carry a dot on the line — the diagnostics
  list beside the preview is unchanged, and clicking a line still selects the
  span it names.

  Four options on the shared `createEditor` seam, which the other two
  playgrounds do not pass and are unaffected by: `lang: "tutuca"` for a pane
  holding one block's body without the `<script>` tags around it, `dark` to pin
  the palette for a host that has one (this shell is dark whatever the OS says,
  and light highlighting on its panels would be unreadable), `wrap` because the
  pane is a third of a page and the textarea soft-wrapped, and `setSpans` for
  diagnostics whose positions the caller already holds — a card's loader answers
  in character offsets, so there is nothing to parse.

### Added

- **`new <Type>` and `@cur`: the block language can build a value now.** It had
  no literals for any aggregate — no list, no map, no record — so a list was
  seeded by repeating `.songs.push 'Ramble On'` in `receive init`, and a record
  could not be made at all. `Array[Label]` could be read into and written
  through (`.labels[i].done = true`) but never appended to, because a `Label`
  had no spelling. The zero of a declared type was already computable
  (`@statedef.info.zero_of`, `StateDef::zero_expr`); it was simply unspeakable.

  `new Label` builds that zero and makes it the **active target**, which the
  statements under it fill in through `@cur`:

  ```
  handle init {
    message {
    new Label
    @cur.text = 'Buy milk'
    @cur.done = true
    .labels.push @cur

    }
  }
  ```

  Still no literals: a value is built by mutating it, which is what the rest of
  the language already does. The type is written the way the state block writes
  it — `new Label`, `new Array[String]`, `new Map[String, Int]` — and resolves
  against that block's own declarations, sharing the name table with the state
  parser so `new Int16` and `count : Int16` cannot come to mean different
  things. A `new` resets the target; a path into one works, so `new Label` then
  `@cur.tags.push 'x'` fills a list inside the record, which is what makes ONE
  target enough for building outside-in.

  `@cur` is a workbench and never becomes output. An enricher's bindings BECOME
  a view's scope — `@name` in a template, replayed on every rebuild — so
  `@interp.run` withholds `cur` from the bindings it hands back and drops any it
  was handed, in one place rather than in each caller. A template that reads
  `@cur` reads nothing, and a card cannot publish a binding a compiled
  component could not.

  Both backends. The checker types the target from the `new` and walks a path
  into it with the same machinery a state path uses, so `@cur.dnoe` reports
  `Label has no field dnoe`, and `@cur` with no `new` above it is `NO_TARGET`.
  The MoonBit backend emits `let cur0 : Label = { … }` and rebinds it per write
  — which is a plain record update, not the spine rebuild it still refuses on
  `s`, because the target is a local whose type is known at every step. Five
  corpus cases hold the two to the same answers.

### Fixed

- **`compute`, `pred` and the two enrichers are compiled now.** The
  ahead-of-time backend skipped every value body — `emit.mbt` mapped the four
  dispatch kinds to buckets and `continue`d past the rest — so a block that
  declared `pred over { .count > 3 }` contributed the NAME to the method enum
  and nothing else. A view file that stated the rule and nothing beside it
  produced a component whose `$over` answered Null: the flag never showed, the
  label stayed empty, and nothing said why. The same file, run as a card, had
  always worked. Reported from a project on the latest version, and reproduced
  here by driving one file through both backends.

  Each body is compiled into one function — `<comp>_compute_<name>`,
  `_when_`, `_enrich_`, `_enrich_scope_` — and the generator writes the router
  that keys them by the bucket's own enum and composes it AHEAD of the author's
  `compute~` / `when~` / `enrich~`, exactly as it already composed `update~`.
  One body may compile twice, because a `pred` reached by `@when` is handed the
  row and the same `pred` read as `$name` is not; which of those exists comes
  from the views, so the generator tells the backend and the backend does not
  guess.

  Two rules the fix turns on. A body may CALL another by name — `compute status
  { if over { … } }` is a call, and it emits one — which is what makes a block
  a set of definitions rather than a list of one-liners. And an opaque value
  used at a type (a `@value`, an argument nothing declares) is GUARDED rather
  than coerced, with the guard a port of the interpreter's own: `lower` there
  is `guard args[0] is Str(s) else { return None }`, so a row of the wrong
  shape answers nothing in both backends instead of being coerced in one.

  `storybook/examples/render_child.mbt` loses the hand-written `compute~` it
  carried with a note saying it would go away when this landed.

- **A handler bucket asked the author for names the block had already
  answered.** The `Msg` enum has always been trimmed of what the script block
  answers — `update` is composed behind the block's transition, so an arm for a
  claimed name could not run — but the four HANDLER enums were not, though the
  wrapper composes them the same way. A file whose block declared `compute
  hasAttachments` and whose views also called `$rowLabel` got a `Method` enum
  carrying both, so the `compute~` match had to name `HasAttachments` to be
  exhaustive, in an arm the generated router makes unreachable. The corpus
  component was the worst of it: 16 cases to reach the 5 a MoonBit `compute`
  could still answer, and three buckets whose parameter could do nothing at all.

  The cost was never only the typing. `HasAttachments => Some(myHandler)`
  compiled and silently never fired — the exact failure the bucket enums exist
  to prevent, arrived at through the enum that was meant to prevent it. The
  alternative, a `_ => None` catch-all, trades it for the other loss: a genuinely
  new `$name` stops being a compile error.

  `Method`, `When`, `Enrich` and `EnrichScope` are trimmed now, each carrying the
  same note `Msg` carries saying which names went and why. A bucket the block
  answers ENTIRELY loses its enum and its wrapper parameter, and is passed as the
  map the block built. `Input` is still whole — it keys `swap`, which replaces
  the node rather than the state, and answering a name in the block must not take
  swapping it away — and a declaration the backend REFUSES is still not counted
  as answered, since the enum is the only place left to answer it.

  The generated router falls out simpler: keyed by source name into a
  `Map[String, H]` rather than matched over an enum that no longer carries those
  names, which retires the partial-wildcard arm it used to need.

- **The MoonBit backend emitted `not(x)`, which moonc deprecates.** Every
  negating form in a block — `not .ok`, `is not`, and the `(not a) or b` that
  `implies` expands to — compiled to the spelling the compiler warns about, so
  a view file whose author wrote nothing wrong produced a generated module that
  warned, and a `--deny-warn` build rejected it outright. All three emit `!`
  now, which is what the deprecation asks for and what the generated code has
  to be: a generated file must never be the thing that warns. Reported from a
  project that had worked around it by writing `(len .x) > 0` and
  `.loading is false` instead.

### Added

- **`upper`, and the escapes a string literal was missing.** `upper` joins
  `lower` in the reading vocabulary — one case fold each way, with the same
  guard — and `\n`, `\t` and `\r` join `\'` and `\\` as escapes. Both lexers
  read ONE table, so a `'a\nb'` means the same in `@text="…"` and in a handler,
  and the printer writes the escape back rather than a newline that would make
  a declaration three lines tall. (A literal could always span lines as itself;
  what was missing was the one-line spelling.) Both gaps came out of migrating
  the examples, and both cards that had worked around them now say what they
  meant.

- **A card can hold macros.** `<template id="macro:name">` was returned by the
  splitter and dropped by the loader, so `<x:badge>` in a card rendered as an
  unknown element. The `Card` carries them and the host passes them to
  `ModuleDef::new(macros~)` — the same path a generated module's take. The
  card playground's structured view gained a **macros** tab beside views, with
  the same add and rename its view tabs have; the two are one tab bar over two
  lists now, since a macro belongs to the FILE and a view to the component.
  Before this, a declared macro also showed up in the views tab as a view
  called `field` of a component called `macro`.

- **Seven more examples migrated, and two that needed `new`.** `text`,
  `raw-html`, `conditional-attrs`, `swatches` (SVG plus an enricher that lays
  the row out), `quadratic` (MathML, and one `compute` calling another),
  `macros` — the four macro demos that had to live in MoonBit — and
  `nested-state`, whose `Array[Label]` is seeded and grown with `new` / `@cur`.
  Twenty cards in the selector now, every one loaded by `check-examples` and
  driven in a browser.

- **Nine examples migrated into the card playground's selector.** It had four
  starters; it has thirteen cards now, and the nine are the repo's own demos
  rather than new ones — `traffic-light`, `tabs`, `show-hide`, `attributes`,
  `modifiers`, `scope`, `list-enrich`, `list-iteration` and `markdown`, taken
  from `storybook/examples/` and `playground/site/examples/` with their MoonBit
  `update` arms moved into the block and their `compute` entries into `compute`
  declarations. Every one is loaded by `check-examples` on each build and was
  driven in a browser.

  Two of the nine could not say in the block exactly what the MoonBit said, and
  both are one-line gaps rather than design questions: the reading vocabulary
  has `lower` and no `upper`, and a string literal has `\'` and `\\` and no
  `\n`. `docs/cards-from-examples.md` records what the whole corpus would take
  — 31 more components need only the porting work, and 49 need child
  components.

- **The conformance corpus covers value bodies.** It held transitions only —
  a dispatch, a before, an after — which is why the two backends could disagree
  about every `compute` and `pred` in the language without a test noticing. It
  now carries `ValueCase` beside `Case`: a body, a role, the bindings the
  renderer would hand it, and the answer. Seventeen cases, most of them lifted
  from blocks that exist in this repo — the site's counter card, the tutorial's
  steps, `render_child.html`'s `containsText`, the filter idiom every list
  component grows — because the thing worth pinning is what people write.

  Three adapters, as before: the interpreter's, the compiled one (which asks
  the generated component BY NAME, so it drives the router and the bucket
  composition too), and the projection that turns the corpus into a view file.
  It earned its place on the first run, catching a `pred` that the new backend
  boxed into a `Bool` where the interpreter answers the expression's own value
  — `<x text="$named">` would have printed `true` where a card prints `ada`.

- **`<mb-card codemirror>` — the embeddable card can be a real editor.** The
  same CodeMirror the two playgrounds use, reached through the same
  `createEditor` seam: line numbers, an active line, history, bracket matching,
  and highlighting that follows the reader's light/dark. Opt-in per element,
  like margaui, because the bundle is ~330 KB — a textarea is a perfectly good
  place to change three characters and watch what happens, and highlighting
  earns its weight on a page someone is meant to READ code on. The landing
  page's card and all nine tutorial cards ask for it.

  It is an UPGRADE of the textarea rather than a replacement for it: the card
  is already loaded and rendering when the import starts, so a page that ships
  the element without the bundle gets a working card and a line in the console.
  Everything the element does with the source — reload, reset, and selecting
  the characters a diagnostic is about — now goes through one accessor pair, so
  there is no second copy of the element's logic behind the flag.

  **The view mode learned the block language.** It knew tutuca's templates —
  which attributes are directives, where a value expression sits — and treated
  a `<script type="tutuca/script">` block as text, which for a card is its
  middle greyed out. It now tokenizes what is inside one: the declaration
  keywords, the statements and effects, `.field` / `@bind` / `$method` / `*dyn`
  spelled exactly as the templates spell them. The playground's View tab shows
  the same file format, so it gained this too.

- **Cards can be styled with margaui, and every card that ships now is.** The
  card runtime always collected the class names a mounted card uses — nothing
  ever compiled them, so a card saying `class="btn btn-primary"` rendered as an
  unstyled button and the four starter cards, written for margaui from the
  start, looked like markup. The card playground compiles them now, and an
  embedded card opts in with `<mb-card src="…" margaui>`.

  The card tutorial's nine examples are written in margaui too, `<style>`
  blocks and all replaced by class lists — `card`, `btn`, `input`, `badge`,
  `join`, `stats`, `alert`, `range`. Its styling section keeps the other route
  in a snippet rather than a card, because a view's own scoped `<style>` is
  still the answer for anything a design system does not have a name for.

  The compiler is the one that already existed: `margaui.wasm`, the wasm-gc
  build of `@css.compile_margaui` the other playground ships, fetched lazily on
  the first mount that publishes a class name. The new part is that a card
  mounts in the PAGE's own DOM rather than in an iframe, so its CSS cannot be
  injected as written — margaui's stylesheet carries Tailwind's preflight and a
  `:root` theme, and unscoped it does not style the card, it flattens the page
  around it. `tutucard/web/margaui.js` rewrites every rule to apply inside the
  preview only, using the browser's own parser rather than a regex over 60 KB
  of CSS, and flattens the cascade layers in declared order — an unlayered rule
  in the host page's stylesheet outranks any layered one, so keeping the layers
  would mean the page's `button {}` beating margaui's `.btn` inside the card.

  `__tutucard.classesAt(id)` is the new host entry: the existing `classes()`
  answers for the playground page's one card, which is not a thing an embed can
  ask about.

  The card playground's own `.preview button` / `.preview input` rules are gone
  with this — hand-written stand-ins for the styling that now exists, and
  unlayered, so they beat every margaui rule and painted a margaui input in the
  shell's palette. Its `.pane h2` became `.pane > h2` for the same reason: a
  card's `card-title` was being labelled like a pane header.

## [0.13.0] - 2026-08-13

> **Why this section covers a range of releases, and why it was not split
> retroactively.**
>
> Sixteen versions were published between 0.9.3 and this one (0.9.4 … 0.9.13,
> 0.10.0, 0.11.0, 0.12.0 … 0.12.2, tagged and dated in git) without moving
> these entries under version headings, so everything since 0.9.3 accumulated
> under `[Unreleased]` and is released here.
>
> Splitting it after the fact was attempted and abandoned: entries were
> not merely appended, they were REVISED in place across later releases, so
> reconstructing "what shipped in 0.10.0" from the history yields a block that
> overlaps its neighbours rather than a clean cut. A changelog that confidently
> attributes a change to the wrong release is worse than one that says a range
> of releases share a section, so this says the latter.
>
> `git log v0.9.3..` and the tags are the record for anything in between. From
> 0.13.0 on the boundary is clean: `[Unreleased]` above starts empty, and the
> next release moves its own entries and nobody else's, per CONTRIBUTING.md.

### Removed

- **Five public functions nothing called.** Each was reachable, documented and
  dead; keeping them meant every reader had to work out which of them mattered.

  - `@storybook.dry_run_text` / `dry_run_json`, and the `storybook/report.mbt`
    they lived in. They formatted the output of `tutuca storybook --dry-run`, a
    flag the CLI removed — `cli/dispatch_test.mbt` asserts it is now rejected.
    Their only remaining caller was their own test.
  - `@tscript.parse_slot_body` — no caller and no test, in production or
    anywhere else.
  - `@viewgen.ir_supported` — superseded by `emit_ir_module_opt`, which answers
    the same question by emitting rather than by compiling every view a second
    time to ask first. `gen-views` stopped calling it two releases ago; only
    tests still did, and each of those either asserted something its next line
    already proved or hid what it was skipping (see below).
  - `@storybook_ui.shell_component` — a one-line wrapper over `build_shell`
    that `mount` bypasses.
  - `@markup.filter_for`, deprecated since the chain moved to
    `vdom/filter/markdown`. It was kept on the argument that it was still right
    for a host wanting the raw-markup rule and the baseline and nothing else.
    Nothing ever wanted that, and an app wired through it rendered
    `@setinnermd` as an empty element. A host that does want the pair can build
    it in one line — `docs/sanitizer.md` shows it.

### Changed

- **The example-corpus sweep now says which views it skips, and why.** It asked
  `ir_supported` first and counted every `false` as "cannot be generated". That
  hid the actual reason: this harness feeds each view in ISOLATION, so a call
  to a macro its own file declares has no definition in scope and the view does
  not parse. The sweep now emits once and classifies the error, so the two
  expected causes are named and **every other error fails the test** instead of
  quietly inflating the unsupported count.

### Fixed

- **A `$name` written inside a body read Null, and nothing said so.** The
  sigil is answered by the render stack and a body runs after one, so
  `if $over { … }` took the else arm every time — the worst way for a rule to
  be false. The ahead-of-time backend refuses both `$name` and `*name` in a
  body by name; the checker now reports them too (`RENDER_ONLY`), and where
  the block declares the callable the message names the spelling that works:
  a body calls a `compute` or a `pred` **bare**. Their TYPE stays opaque, as
  "unknown is not wrong" requires — the value being Null is the separate fact,
  and it is the reportable one.

- **A card's `request` dropped its arguments.** `emit_mbt` emits
  `ctx.request(name, payload, RequestOpts::new())` and the interpreter emitted
  `ctx.request(name, [], …)`, so the two backends of one language disagreed
  about the only channel a request has — a `RequestFn` has no component
  instance and cannot read state. `@interp.Effect::ERequest` carries `args`
  now. `RequestOpts` still stays out of the block, deliberately.

- **A card's `@when` filter never saw the row it was judging.** A `pred` reached
  through the Alter namespace was built as a plain callable, which binds a
  declaration's PARAMETERS and nothing else — and a filter is written
  `pred matches { … @value … }` with no parameters, exactly as the shipped
  `filter` starter card and the language's own docs write it. So `@value` read
  `Null`, `contains` said no on every row, and the filter kept everything. It
  now goes through the same path `@enrich-with` does, where the renderer's
  `(key, value, iterData)` arrive as the binds `@key` / `@value` / `@iter`.

  The `filter` starter card also seeds itself with a `receive init` now. It had
  no names in it, so the one card whose subject is filtering had nothing to
  filter, and the bug above could not have been seen there anyway.

- **A card's `@enrich-with` bound nothing.** An enricher hands its binds over
  BY REFERENCE — `render/render.mbt` discards what the handler returns and
  reads back the map it passed in — and the card runtime only returned a fresh
  map. Every `@name` an `enrich` wrote was therefore unbound at the template,
  which renders as a blank where a value should be. The interpreter's `Outcome`
  now carries the binds a body ended with (it runs against copies, so there was
  no other way to hand them back), and the card writes them into the map it was
  given. Both are pinned by a mounted-and-driven test in `tutucard`.

- **Multi-line `<pre><code>` on the site rendered as one long line.** The
  stylesheet's `code` rule is `white-space: nowrap`, which is right for an
  inline snippet and destroys a block: every newline collapsed and the block
  became a horizontal scrollbar. `pre code` now restores `pre`.

- **`anode`'s default parse-issue handler bypassed the warning hook.** It used
  `println` directly, two lines below a doc comment promising it warns, so a
  host that redirected `@tutuca.warn` into an error pane or the browser console
  never saw parse issues. It now goes through the hook like the rest of the
  package.

### Security

- **Archive loading is now bounded and legacy JavaScript bundles are gone.**
  The tar reader coerced an octal entry size through `| 0`; a crafted size
  wrapped negative and made the offset stop advancing, freezing the page.
  Gzip expansion and fetched archive bodies were also unbounded before the
  manifest quotas could run. The loader now streams under compressed and
  expanded byte ceilings, validates tar checksums and checked sizes, requires
  every entry to advance within the input, and caps entry size/file count.
  Archives without `tutuca.json` are refused instead of importing a legacy
  `*.component.js` blob at page authority.

- **Untrusted dyncomp views can no longer use the DOM as a direct network
  channel.** Registration refuses URL-bearing attributes, inline/embedded and
  SVG CSS sinks, SMIL mutation elements, runtime Markdown, and bracketed
  arbitrary utility CSS. Autonomous custom elements and ordinary structured
  properties remain supported; customized built-ins (`is=`) are refused. A
  host-registered custom element's constructor/setters still run as trusted
  page code, so hosts can narrow that residual gadget surface with a sanitizer
  element/attribute allow-list.

- **A list- or map-valued URL attribute reached the DOM as a live
  `javascript:` URL.** An untrusted bundle with a `list<string>` field and

  ```html
  <a :href=".links">go</a>   <!-- links = ["javascript:alert(document.cookie)"] -->
  ```

  got script execution in the host's origin, with no host cooperation and
  nothing above the default `Policy::untrusted()` tier.

  Three layers each declined to stop it, for individually reasonable reasons.
  `value_to_attr` turns any structured value into `Data(Json)`, which is what
  makes `:items=".products"` work on a custom element. `UrlFilter` skipped
  `Data` on the grounds that a structured value is not a URL string. And
  `set_prop` routed `Data` to property assignment ahead of the `never_assign`
  check — the list that names `href` for precisely this reason. In the browser
  the glue then does `node.href = <array>`, and the IDL setter takes ToString of
  it: a one-element list stringifies to its element. Multi-element lists join
  with `,`, which is a JS comma expression, so they work too.

  The skip reasoning is true about the MoonBit value and false about what the
  browser does with it. Both halves are fixed, because they fail
  independently:

  - `@filter.UrlFilter` now drops a structured value bound to a URL attribute
    on shape alone, and reports it — no scheme inspection needed, since there
    is no legitimate structured URL. Structured values on any other name are
    untouched, which is the custom-element binding the `Data` shape exists for.
  - `set_prop` no longer lets `Data` skip `never_assign`. Those names degrade
    to a JSON-text attribute, which is an inert relative URL. This is the layer
    that holds under `set_filter(None)`.

  The live vectors were `<a href>` and `<form action>`; tutuca's default
  sanitizer is a denylist, so both elements are available to an untrusted
  bundle. `src`, `poster`, `srcset` and `ping` took the same path but are inert
  (`javascript:` does not execute in a subresource load), and `formaction` on
  `<button>`, `background` and a lowercased `innerhtml` became dead expandos.
  SVG `href` is a read-only `SVGAnimatedString` and silently dropped the
  assignment.

  The regression tests assert on the property map rather than on serialized
  HTML, which is what let this through: a live `form.action` leaves no
  attribute behind, so the existing `to_html().contains("javascript:")` checks
  could not observe it.

### Added

- **A card tutorial on the landing site (`dist/cards.html`).** Eight steps,
  eight live `<mb-card>` examples, each a whole file the page parses and
  mounts: the schema on its own and the mutators it generates, the
  `tutuca/script` block, `compute` / `pred`, lists, what a loop asks the block
  (`@when` and `@enrich-with`), messages, `request` / `response` — including
  the error path, which the page shows live by registering no handler at all —
  and invariants, pre- and postconditions, which are one construct (`pred`)
  used at three moments. It ends with the grammar on one screen — the eight
  declaration keywords, the statements, the five operator families and the
  closed reading vocabulary — and with the line past which a card is a
  component: it cannot name a MoonBit value.

  The cards live in `playground/site/cards/`, so
  `tutucard/build/check-examples.mjs` already loads every one of them through
  the real loader and fails the build if any reports an issue. Two of the six
  are there because writing them found bugs (see Fixed).

- **`<mb-card>` sizes itself to its card, and offers a way back.** The editor
  took a fixed 18rem whatever it held, which a page of eight examples of
  different lengths reads badly; it now sets `rows` from the source, bounded at
  both ends, and gives the source the larger share of the split. A **reset**
  button appears in the bar the moment the source differs from the file that
  was fetched, and puts that file back — an embedded example is an invitation
  to break it, and the way back should not be a page reload.

- **The card playground has a structured view.** The same card, two ways to
  look at it: `raw` is the file, and `structured` gives it a tab each for the
  state block, the handlers and the views — with the views tab carrying tabs of
  its own, `main` first, and a `+` that adds one (double-click a tab to rename
  it; `main` is the one name that is not the author's to change).

  The two cannot disagree, because the structured panes are not a second copy.
  They are projections of the SAME string, sliced at recorded offsets, and a
  structured edit splices back into it — so switching modes loses nothing and
  there is nothing to diff. Slicing rather than parsing-and-reprinting is
  deliberate: `viewfile` normalizes what it hands back, and running an editor's
  buffer through it would rewrite the author's file on every keystroke.

- **`dyncomp/storybook` — a storybook for dynamic components.** Every component
  every loaded bundle declares, once per configuration it declares, live and
  side by side. There is no story list anywhere: a `.tutuca.tar.gz` manifest
  already says what its components are and what named `inits` each ships, and a
  named initial state IS a story — so this works on a bundle nobody wrote it
  for, including one dropped on the page while it is running.

  Backend-agnostic, the same way `dyncomp/ui` is and for the same payoff:
  `moon test` drives the whole gallery — a bundle loading, cards appearing, the
  filter, the sidebar, reset, details — on the in-memory DOM with a fake guest.
  `dyncomp/storybook/wasm` adds only what cannot be done without a browser, and
  `demo/dyncomp_storybook_wasm` is the page: `cmd/dev -- dyncomp-storybook`,
  then `/dyncomp-storybook/`.

  It is not a second universal host. `demo/universal_wasm` is a blank page a
  person builds on, so it starts empty and hides its samples behind `?test`;
  this is a gallery, so it fetches every sample at mount. Per-card `reset`, a
  margaui theme picker and a grid/one-per-row switch vary what a manifest
  cannot: a component gets looked at in several themes without a reload.

- **`dyncomp/shell` — the floor under any wasm-gc page that hosts bundles.**
  The loader bar a bundle arrives through, `make_instance`, and the margaui
  refresh. There are two such pages and they are not variants of one thing —
  an editor and a gallery — but underneath they need exactly this and neither
  needs a different one, so it stopped being two copies.

  The bar reports through a `notify` hook rather than knowing what a load means:
  the universal host counts it against a session being restored, the storybook
  recompiles the stylesheet. It is deliberately NOT in `dyncomp/host/wasm` —
  the bridge should not have to depend on a CSS compiler and a view parser to
  answer `get-field`.

- **`guests/slack` — a chat conversation as a `tutuca:component` bundle: one
  message, a thread, and a channel's history.** Ported from the
  Feeling-of-Computing conversations reader (`at-foc/src/components.js`), and
  the guest where nesting goes DEEP: `ChannelHistory` → `Thread` → `Message` →
  `RichText` → `Segment`, all five levels built by `control.make-instance` from
  plain JSON in one `init`. `dyncomp/test/slack-harness.test.mjs` implements the
  bridge's pending-children protocol against a fake host, so that recursion has
  a test that needs no browser.

  It asks for no capability: the timestamps are data the messages arrived with,
  and `timeLabel` slices a string it already holds. Two places the policy said
  no are visible in the output — a link segment cannot navigate (`href` is a
  network sink), so it emits `openLink` and the channel decides what that means;
  and the original's replies/reactions/channel toggles are not ported, because
  they were three `globalStyle` rules and there is no field for global CSS on
  purpose.

  Its thirty `inits` are the storybook: `dyncomp/storybook` draws one card per
  configuration straight from the manifest, so adding an `init` here adds a card
  there.

- **`guests/bluesky` — an ATProto reader as a `tutuca:component` bundle:
  a message, a conversation and an account.** Ported from the JS
  `tutuca-components/src/atproto` module group and styled after
  [atproto-wc.com](https://atproto-wc.com), light and dark. It asks for no
  capability, so a stock `Policy::untrusted()` page loads it — and that is what
  makes it the guest where the policy boundary is visible in the output: with
  no `src`, no `href` and no `style` to reach for, an avatar is the author's
  initials, an image is its alt text on a chip, a link is its text with the
  target as the tooltip, and a permalink is text you can select. A reply's
  depth arrives in the view as a `rail` list to draw rather than as a margin.

  Two things fell out of building it and are written up in
  [`guests/bluesky/README.md`](guests/bluesky/README.md):

  - A view cannot iterate a value it found inside another iteration (`@each`
    takes a field path, not a loop binding), so a message's rich text can only
    be a loop in the component that owns the message. `Thread` and `Profile`
    therefore make one child `Post` per message through
    `control.make-instance` — the only shape in which a reply keeps its links.
  - A row keeps its own like / repost / fold and returns a successor; the thread
    keeps only which uris are folded AWAY, because a row knows it is folded and
    only the thread knows which messages sit UNDER it and therefore stop
    rendering. Two facts about one click, and the thread does not rebuild the
    row to record its half. A profile, having no fold, keeps nothing.

    It was first written with all three kept by the thread and the row rebuilt
    around them, because `with_field` markered a nested child only at the top
    level of the written value — see the `child_json` fix below. `owned`
    survives from that arrangement with a smaller job: it now only says "this is
    a row inside something larger", which is what the view reads to draw it
    smaller.

- **`dyncomp/host/wasm/abi.mjs` — the canonical ABI for `tutuca:component`,
  written once instead of shipped in every bundle.** A guest archive can now
  carry its core module and a four-field descriptor:

  ```json
  { "world": "tutuca:component@0.6.0", "encoding": "utf16",
    "core": "counter.component.core.wasm", "manifest": { "...": "..." } }
  ```

  and the host does the lifting. What it replaces is `jco transpile` output —
  5,000 to 7,500 lines per archive, and 38-57% of a gzipped one. That file
  never carried anything about the component: across fifteen bundles it takes
  eight distinct values, and which one you get is a pure function of the host
  functions the module imports and the string encoding it was embedded with.
  Everything else is the world, and the world is fixed, so `WORLD` in `abi.mjs`
  transcribes `wit/tutuca-component.wit` as type descriptors and one generic
  implementation of alignment, size, flattening, load/store and lift/lower
  walks them.

  Two things follow that are not about size:

  **An archive stops carrying executable JavaScript.** `loader.mjs` imported
  the guest's own transpiler output from a blob URL, which runs at PAGE
  AUTHORITY — the one channel the wasm sandbox says nothing about, and the
  thing `SECURITY.md` and a bundle audit both had to warn about rather than
  prevent. A descriptor archive has nothing to import.

  **A capability is checked against the import section.** Imports bind by name
  against a closed table, so anything outside `tutuca:component@0.6.0` is
  refused before a guest instruction runs — and `env` is refused unless the
  host granted the matching capability. This is the gap `SECURITY.md` §2
  admitted to: `Policy::check_capabilities` reads the manifest, a guest writes
  its own manifest, and a guest that imported `env.now-ms` without mentioning
  `cap-clock` got the clock anyway. It cannot any more. `setGrants()` is the
  page's side of that decision; its default is `Policy::untrusted()`'s answer,
  which is nothing.

  The two trampoline core modules are not needed either. They exist because the
  transpiler captures `memory` at instantiation time and has to break the
  resulting cycle; every import here reads memory at CALL time, so the main
  module is the only one instantiated — and the only one an archive must ship.

  `loader.mjs` now accepts only that descriptor shape. An archive without one
  is rejected rather than importing its transpiler output at page authority.

- **`tutuca:component@0.6.0` separates declaration from execution.** The WIT
  no longer exports the catalog/schema/view graph through `get-manifest`; it is
  static `manifest.json` plus HTML files. Input handler names are no longer
  duplicated there either: `handle-event` returns `unhandled`, `unchanged`, or
  `changed(instance)`, so the host can fall back to a generated field mutator
  without guessing. `seq-entries` is gone; iterable state is an ordinary
  declared list field. The guest SDK consequently asks authors only for
  behavior, factories, persistence, and optional request serving.

  Checked three ways against a fifteen-bundle corpus, not asserted: every bundle
  driven through both implementations with the same host agrees on 379 guest
  answers and 372 host calls; 337 computed layouts match the core signatures
  wit-component wrote into the shipped modules; and the two codecs — one over
  linear memory, one over flat core values — round-trip 18 types identically in
  both encodings. The Rust guest is the one that matters: utf8, hand-written
  bindings, and the host cannot tell.

- **`@setinnermd` — markdown in a view, sanitized by construction.** Takes a
  markdown SOURCE string and replaces the element's children with the nodes it
  parses to: CommonMark plus GFM (tables, task lists, strikethrough, footnotes),
  with no flag to turn any of it on.

  It is `@dangerouslysetinnerhtml`'s safe sibling, and the name carries no
  warning because it does not need one. The markdown never becomes an HTML
  string: `vdom/filter/markdown` walks the AST straight into vdom nodes, asking
  the app's own `@sanitize.Sanitizer` for a verdict on **every element** and
  running **every attribute value** past `@filter.attr_value_allowed` on the
  way — routed through one `emit` helper so no arm of the walk can skip it.
  `set_inner_html` is never called, so the browser never re-parses a string this
  code produced and there is no second parse for a mutation-XSS to live in.
  Raw HTML inside the document goes through the same `html_nodes` builder
  `@dangerouslysetinnerhtml` uses, so a `<script>` cannot be refused by one path
  and allowed by the other.

  **There is nothing to permit, so Pass 1 never refuses it.** `raw_markup` is a
  permission because a raw-HTML payload arrives as markup the config gets no say
  over; markdown has no such route. A host that wants less names the elements it
  will have, the same lever it already has over every other node in the tree.

  It works with no configuration: `App::new` now installs
  `@mdfilter.default_filter()` — `MdFilter` in front of the `@filter.Baseline`
  it installed before. **The cost is that every app links the vendored parser**
  (~4.7k lines), since the call is unconditional and nothing about it is dead.
  `set_filter(Some(@filter.Baseline::new()))` restores the previous footprint;
  `set_filter(None)` is still the full opt-out.

  Without a filter that understands it, `set_prop` **fails closed** — the
  element is cleared rather than being given the markdown as text or as markup.
  A directive whose name promises it is sanitized has to fail visibly when
  nothing sanitized it.

  A live editor is on the landing site: source on the left, preview on the
  right, and a second half of the document that is nothing but attacks — HTML
  and SVG `<script>` (different elements, since identity is namespace-qualified),
  `<iframe>`, `<base>`, `on*` handlers, `javascript:` and `data:text/html` URLs.
  None of it renders. See `docs/sanitizer.md` for the design.

- **`markdown/` — the parser, vendored from mizchi/markdown.mbt** (MIT, commit
  pinned in `markdown/UPSTREAM.md`). 15 of upstream's 29 production files,
  verbatim: the AST, scanner, block parser and inline parser. Its HTML renderer,
  markdown serializer, editor-preview renderer and incremental reparser are
  deliberately left behind — building nodes means never needing an HTML string.

  Vendored rather than depended on because the published `mizchi/markdown` drags
  `mizchi/moomaid` and declares `supported-targets: js+wasm`, while this module
  prefers wasm-gc. What is copied has no third-party dependency and no `extern`
  at all.

  Two findings from reading that parser shaped the design, and
  `markdown/parse_test.mbt` pins both so a re-sync cannot move them quietly:
  `Inline::HtmlInline` is only ever a complete HTML comment (so every raw-HTML
  carrier is self-contained and no half-open tag needs reassembling across
  siblings — which is what removed the AST→string step from the original plan);
  and `try_parse_autolink` accepts any `<…>` without whitespace, so `<span>`
  arrives as `Autolink(url="span")`. The builder renders an autolink as a link
  only when the URL has a real scheme, and as literal text otherwise —
  without that, an ordinary comment body would fill with stray relative links.

### Added

- **`<mb-card>` — a card, embedded in a page as an example.** The card sibling
  of `<mb-playground>`, and the difference between the two is the point being
  made: that one carries a 5.5 MB in-browser MoonBit compiler, a worker, a
  per-target prebuilt closure and a manifest; this one has a `.html` file and a
  runtime that is already on the page. The edit loop is one call, so the
  element is an editor, a preview, and the diagnostics the loader answers.

      <script src="./site/tutucard.js"></script>
      <script type="module" src="./site/card-embed.js"></script>
      ...
      <mb-card src="./site/cards/counter.html"></mb-card>

  The landing page embeds one, under the two `<mb-playground>` examples, so the
  subset is visible next to the thing it is a subset of.

  The host grew the half a page of examples needs: `mount(id, source, name)`
  and `unmount(id)` address a card by where it renders, and the one `current`
  app became a map keyed by mount point. `load` is now `mount` at the
  playground's own element, so the standalone page is one caller of the new
  entry rather than a second path.

  LIGHT DOM, deliberately. A card's `<style>` blocks are installed into the
  document and scoped there, so a shadow root would cut every card off from its
  own styles, and the host mounts by element id, which `getElementById` has to
  be able to find. The page's CSS reaching the preview is the behaviour an
  embedded example wants anyway.

### Changed

- **The corpus writes its handlers in the script block.** Every example whose
  behaviour the block can express now states it there, and the MoonBit beside
  it holds only what the block deliberately does not spell — a seed value, a
  request's options, a path walk, a child component being built.

  Sixteen handlers moved across eleven files. Six components lost their
  `update~` entirely (`storybook/examples`' counter, traffic light, show/hide,
  `Status`, the playground's counter and the landing page's hero snippet), and
  three schemas grew the `receive` declarations that made it possible —
  `Status`'s `Flash`/`Clear`, `SendReceive`'s `ClearDraft`, and the `Init` the
  host dispatches at `Request` and personal-site's `Root`. A message no view
  writes has nowhere else to be declared, and until the block could answer one
  there was no reason to declare it.

  What did NOT move is the more useful half of the answer, because each case
  names a boundary the language chose: a `@key` or a `value` argument carries
  no type from its call sites, so `selectItem @key` binds raw; a `compute` is
  answered by the render stack and a handler runs after one; and `walk_path`,
  `RequestOpts` and `Component::make` are MoonBit by design. The `pred` in
  `render_child.html` still has its body written twice for the same reason —
  the backend skips `compute`/`pred` declarations, so that block declares and
  MoonBit implements.

  Three emitter bugs surfaced by doing it, each of which had no corpus case:

      (.count + 1) mod 3     emitted unbalanced parentheses — `mod` wraps its
                             left-hand side, and the chain was built by
                             appending, which cannot reach backwards
      .count += 1            on a ONE-field state emitted `{ ..s, count: … }`,
                             which is `unused_struct_update`, and a generated
                             file must not be the thing that warns
      .values.push 3         into an `Array[Any]` was refused, though widening
                             into `Any` is the one conversion that needs no
                             guess

  `mod` and `/` now have corpus cases, so both backends are held to them.

- **A `<script type="tutuca/script">` block compiles to MoonBit.** `gen-views`
  emits `<comp>_inline_update` — one match over `@component.Dispatch` in the
  shape a hand-written arm takes — and the generated wrapper composes it ahead
  of the author's `update~`. `demo/counterlib`'s component definition is now
  `counter_component(init=CounterState::fresh())`, with `add` and `resetTo` in
  the file's script block.

  A name the block answers is DROPPED from the `Msg` enum: `update` is
  consulted only for a dispatch the block did not claim, so an arm for one
  could never run, and making the author write it would move the noise rather
  than remove it. The `Input` enum keeps it — that one keys `swap`, which wins
  over `update` and replaces the node rather than the state.

  What the backend cannot compile it REFUSES by name, with the reason, as a
  `script-refusal` hint. A block with one handler that reaches for a spine
  rebuild still has five that compile.

  Both backends are now held to the conformance corpus, and it earned its
  keep immediately: it caught the emitted code SATURATING on `1 / 0` where the
  interpreter answers "no change", letting an effect escape from a transition
  that then failed, and ABORTING on a list index past the end where a slice
  would. All three are fixed and pinned.

- **`update` answers an enum, not an `Option`.** `(S, Dispatch, &Ctx) -> S?`
  became `-> Update[S]`, with three cases:

      Unhandled     no arm claimed this name — try the generated mutators
      Unchanged     this arm answered, and the state stays as it is
      Next(s)       this arm answered; here is the successor

  `None` used to mean the first TWO of those, and the dispatch site could not
  tell them apart — so a handler could not veto a write: an
  `Input("setTitle", _) => None` meant to refuse fell through to the generated
  setter and the change landed anyway. `Some(s)` where `s` was the same object
  was the only way to say "handled, no change", which made `physical_equal`
  part of the CONTRACT rather than an optimization the transactor happens to
  make.

  They are the same three the refusal taxonomy names — nothing claimed it, a
  rule refused it, nothing changed — and the migration is mechanical: an arm
  that produced a successor becomes `Next(…)`, a trailing `_ => None` becomes
  `_ => Unhandled`, and a guard inside an arm that already claimed the name
  becomes `Unchanged`. `inspector`'s shared `composite_update` is the clearest
  case: at page 0, `prevPage` now REFUSES rather than falling through to
  whatever mutator happens to share the name.

- **The state block is no longer WIT.** `<script type="tutuca/spec">` now
  reads a small language of its own that spells its types the way MoonBit does:
  `state Counter { count : Int, tags : Set[String] }` where the file used to
  write `interface counter { record state { count: s32, tags: text-set } }`.
  Six keywords and no more — `state`, `struct`, `enum`, and the buckets
  `receive` / `bubble` / `response`. Five WIT forms went with it, each for
  something the language already had a place for: `interface` (a nesting level
  saying what a `<template id>` already says), `flags` (an enum plus a
  container), `type X = Y` (an alias contributing no type), `resource` (an
  empty declaration to make a name resolvable — now `Component[Name]`), and
  `func` (behaviour, in a block whose header says it holds none).

  A field has ONE spelling now, the one a view reads: `currentView`, not
  `current-view` in the block and `.currentView` everywhere else. Every `.html`
  in the tree is converted and every generated module regenerated.

  Two consequences worth naming. A **closed set now starts EMPTY** — a `flags`
  field began with every member present, because the type carried the
  membership and the zero was written from the type; `Set[Visibility]` lets the
  CONTAINER decide the zero and the enum decide the membership, which is one
  idea in each place. And a **diagnostic now carries a span**: the parser is
  ours, so "state block: expected a type, found `}`" points at a column, where
  `DefError::locus` used to answer an identifier for `split.mbt` to go looking
  for. `mizchi/wit` is dropped from `moon.mod`.

- **A `$`-callable no view names is declared in the script block.** With `func`
  gone from the state block, a method a PARENT asks of a component — the list
  item's `containsText`, which a parent's `@when` calls on every child — is a
  `pred` or a `compute` in `<script type="tutuca/script">`, and `gen-views`
  puts its name in the component's `Method` enum. A file declaring several
  components writes one block each, named `for="Entry"` the way a template
  writes `id="Entry:row"`.

- **`@uiw.HostToolsSample` is now `@shell.LoaderBarSample`,** and the bar itself
  moved from `dyncomp/ui/wasm` to `dyncomp/shell` so the storybook could stand
  on the same one. A page that named the old type — `demo/universal_wasm` and
  `examples/dyncomp-dice` — imports `marianoguerra/tutuca/dyncomp/shell` and
  renames it; nothing else about a host page changes, and `mount`, `on_event`
  and the other entry points stay exactly where a page already reaches for them.

  The universal page looks the same: the URL box the storybook draws is behind
  `show_url`, which defaults off.

- **The five boolean predicates are a table now, not an enum.**
  `Val::Predicate(pred~ : Pred, args~)` is `Val::App(name~ : String, args~)`,
  and `enum Pred` is gone. The names, the arities and the semantics live in a
  `Map[String, Builtin]` reachable through `builtin(name)` and
  `builtin_names()`; the AST carries the *name*, which is why `Val` still
  derives `Eq` and `Debug` even though a `Builtin` holds a closure.

  Nothing an author writes changes: `empty? .items` and
  `equals? .view 'detail'` parse to the same shape under a different
  constructor, `parse_bool` is still the only entry that builds one, and a
  condition slot is still the only place one is admitted. What changes is that
  the set can grow. An enum could never have held a predicate an author
  declares, because it would have needed a case per declaration — which is the
  whole reason `Predicate` needed its own AST node, its own parse path and its
  own no-kind exception in the group table.

  Two smaller consequences. `IssueRole::PredicateArity` carries
  `(name~, want~)` rather than a `Pred`, so the diagnostic can state the arity
  a reader can no longer look up in an enum — `'equals?' takes 2 arguments`.
  And every `*_view_ir_gen.mbt` regenerates, since the emitted IR names the
  builtin as a string instead of a constructor.

### Removed

- **`updateX` and `updateInXAt` are gone from the generated mutators.** Both
  took a *function* value and applied it to the current one. A view can write
  values and never a lambda, so no template could ever call either, and outside
  `component/component_test.mbt` the tree had no call site at all.

  It was worse than dead. The gap between "set a field" and "transform a field
  with a function nobody can supply" is exactly why `Some(Inc) => Some({ count:
  s.count + 1 })` is hand-written in every counter in the corpus: there was a
  mutator that assigns and a mutator that maps, and nothing in between.
  Deleting the one nothing could reach is what makes the missing middle
  visible.

- **The slot parser is out of `core`,** in a new `tscript` package —
  `ParseCtx`, `Issue`, `IssueRole`, `HandlerParse` and the nine `parse_*`
  entries, plus the tokenizer. `core` never called any of them: the production
  callers are `anode` (every directive and `<x>` op) and `component`
  (`provide` / `lookup`), which now import `tscript`. The AST stays where it
  was, because `Step::ScopeBindStep` embeds a `Val` and that cycle is why the
  value and path layers share one package.

  `tokenize_value(String) -> Array[String]` is `tokenize(String) ->
  Array[Token]`, and `Issue` gains a `span`.

- **`viewgen/split.mbt` is a package of its own, `viewfile`,** with `ViewFile`,
  `ViewSet`, `RawView`, `MacroDef` and a new `FileError` for what a FILE can do
  wrong — as opposed to what generation can. `@viewgen.split_file` stays and
  wraps the failure as `GenError::File(e)`, so callers about to call
  `emit_module` still hold one error type.

### Added

- **Every value-language diagnostic now carries a position.** A `Token` has a
  half-open character range, an `Issue` has the span of the token it is about,
  and `@show="empty? Foo"` blames `Foo` at column 7 instead of blaming the
  attribute. Until now the value language had no position anywhere in it and
  the best a caller could do was name the enclosing tag.

  Spans are character indices, not UTF-16 units — they index the same
  `Array[Char]` `viewfile` slices with and the WHATWG tokenizer counts in, so a
  span from a slot and a span from a file agree on any input. They stop at the
  token: a failure inside a `$'…'` placeholder reports the whole template
  token.

- **`<script type="tutuca/script">` is sliced out of a view file** as
  `ViewFile.script : Block?` — raw text, its character offset and its line.
  Unparsed on purpose: a state block is self-contained, and checking a script
  block needs the schema AND the argument types the views imply, neither of
  which exists at split time. Nothing reads it yet.

### Fixed

- **A declared bound the field's type cannot carry no longer reaches the
  generated JSON Schema, and is named at load.** A manifest's `constraint`
  object spells "not stated" two ways, because it mirrors WIT: `null` (or an
  absent key) for the four bounds, `""` for the four strings. Four of those keys
  are safe to write blank, which is what makes the other two a trap — writing
  the record out in full, as every sample guest's manifest modelled, states
  bounds nobody meant.

  They failed three different quiet ways. `"maxLen": 0` forbids every value: the
  form shows `≤ 0 chars` and Apply refuses the whole submission, including the
  fields that were fine. `"min"`/`"max"` on anything but a number was skipped
  when validating (`v is Num` guards it) but emitted into the schema anyway —
  `{"type":"string","format":"date-time","minimum":0,"maximum":0}` — which is a
  false statement to the one reader that cannot ask what was meant.
  `guests/slack`'s `Message.createdAt` had exactly that, written the day the
  guest was.

  Three changes, none of which touch the semantics — a stated zero is a real
  bound and the host still will not second-guess one:

  - `apply_constraint` gates numeric bounds on the type, the way the length
    keywords beside it already did.
  - `register_bundle` raises `INERT_CONSTRAINT` as a hint for a bound the type
    cannot carry, beside `UNDECLARED_METHOD` and for the same reason: the
    failure is silent, and load is the first moment the manifest and the type
    are both in hand.
  - The sample guests now write only the keys they mean, since copying one is
    how the habit spreads. `tutuca new-guest` already emitted
    `"constraint": null` and was the odd one out.

  `skill/tutuca/schema.md` documents the vocabulary, which appeared in no doc
  or skill file at all before this.

- **A named fixture did nothing when applied to a component already placed.**
  `place_form` emptied the argument map whenever a fixture was named, on the
  assumption that whatever built the component would resolve it — but the
  reconfigure branch returns before anything is built, and wrote the empty map
  through field by field. A per-field write cannot tell "write nothing" apart
  from "nothing changed", so the panel closed and the fixture silently did not
  apply. Only ctrl/cmd-clicking a catalog entry, which opens the form BEFORE
  placing, ever worked.

  The two operations are different on purpose — placing CONSTRUCTS, reconfiguring
  WRITES THROUGH so that everything the schema does not name survives — and a
  fixture is a statement about arguments, so it is now resolved to those
  arguments in `place_form`, where the decision belongs, and both paths consume
  the same map. `InitInfo::args` is already decoded host-side for a loaded
  bundle as much as a standard component, so nothing crosses the boundary to do
  it. `UniversalUi::build` loses its `init` parameter with the last of three
  copies of the resolution.

- **The dyncomp storybook lent no host services to what it hosted.** Its module
  was built without a `requests` map at all, so a guest that asked the page for
  something it cannot compute got nothing — the sample counter's `double` button
  was dead on every card while its `triple`, served by its own bundle, worked. A
  card whose button does nothing is a card that lies about the component.
  `mount` takes `requests` now, and the demo page lends the same `double` the
  universal demo does.

- **A guest child inside a LIST field can now be written back.**
  `WasmGuest::with_field` encoded a nested-child instance as its `$dyn` marker
  only at the TOP level of the written value, while `json_to_value` already
  decoded markers at any depth. A scalar `comp` field therefore worked (the
  sample counter's `Pair`) and a list did not: a child that returned a successor
  had the parent's whole list written back, that list arrived as plain data, the
  guest's `with-field` refused it, and the interaction silently did nothing —
  the guest counted and the screen did not.

  The encoder is now recursive and lives in `dyncomp/host` as `child_json`,
  beside `handle_field` and where a test can reach it. That is the write half of
  DESIGN.md's "host → guest encoding of an instance nested inside a compound
  value"; the read half — inspecting a child through the token that names it —
  stays open, and is why `guests/slack`'s channel keeps the text it built each
  thread from in order to filter them.

- **`cmd/dev -- universal` did not copy `dyncomp/host/wasm/abi.mjs`** beside the
  page. `dyncomp-loader.mjs` `import()`s it lazily, only while an archive is
  being unpacked, so `dist/universal/` mounted and drew and then failed on the
  first bundle with a message about a module nobody mentions. Both dyncomp pages
  copy it now, and `docs/dynamic-components.md` lists three JavaScript files
  rather than two.

### Changed

- **`filter_for` moved to `vdom/filter/markdown`.** The chain is now
  `[MarkupFilter?] → MdFilter → Baseline`, and `markup` cannot name it: the
  dependency runs `markdown` → `markup`, and a cycle is not available.
  `@markup.filter_for` is deprecated and still does what it always did — the
  right answer for a host that wants the raw-markup rule and nothing else.
- **`@markup.html_nodes` is public**, extracted from `MarkupFilter`'s private
  builder. One HTML-tree→sanitized-vdom builder shared by both directives,
  rather than two that could drift apart.
- `@vdom.AttrValue` gained `Md(String)`, and `@anode.AttrItem` gained
  `RawMarkdown`. Both are exhaustively matched, so a downstream `match` on
  either will need the new arm.

- **`examples/` — consumers of the published package, inside the repository.**
  Each is its own module depending on `marianoguerra/tutuca` from mooncakes
  with no path dependency and no `../`. Nothing else here can catch what they
  catch: `moon check` never leaves the module, so it cannot tell whether the
  two wasm-gc JS loaders survived `moon publish`, whether the relative import
  between them is repointable once they land beside a page, or whether `tutuca
  new-guest` emits a tree that builds. Excluded from publish; each has its own
  `build.mjs` and needs nothing from this repo. Run them after a release.

  The first is `examples/dyncomp-dice`: the universal dynamic-component host
  plus one guest of its own — a die, which asks the page for its number because
  a `tutuca:component` world imports no entropy. It found the jco breakage
  below on its first run.

- **`dyncomp/` ships.** It was excluded from the published package, so
  `moon add marianoguerra/tutuca` delivered the framework and the CLI and
  nothing of the dynamic-component story: no contract, no host, no policy, no
  catalog, no universal UI, and no way to write a guest. All nine packages are
  in the tarball now, with `dyncomp/wit/tutuca-component.wit` and the three
  design documents beside them. It imports nothing that was not already
  published, and `docs/`, which always shipped, has always linked into it —
  those links worked in the repository and not in the tarball. This is a MINOR
  bump: additive, with no existing package changed.

  The one part still excluded is `dyncomp/test`, whose `*.test.mjs` drive real
  guest bundles out of `guests/*/dist/js` — a path that exists in the repo and
  in no tarball.

- **`tutuca new-guest <name>`** — scaffold a `tutuca:component` guest. The
  whole tree is compiled into the binary: the WIT contract, the checked-in
  wit-bindgen bindings, the SDK, a working component to edit, and the
  build/pack scripts. Needs `moon`, `wasm-tools` and `node` — **not**
  `wit-bindgen`, since the bindings ship generated and the WIT is a contract to
  implement rather than a source to regenerate against.

  It is a scaffolder rather than a package to depend on, and that is forced
  rather than chosen: `sdk.mbt` implements the `declare`s in the generated
  `top.mbt` and defines methods on `Instance`, which `top.mbt` declares, and
  MoonBit puts both in the package that declares them. No import edge can carry
  them. `agent-context`'s `schemaVersion` is now 7, with three new error codes.

- **`dyncomp/ui/wasm`** — the universal UI as a mountable host. `dyncomp/ui` is
  backend-agnostic on purpose, and says in its own header what it therefore
  cannot do: fetch an archive, read a dropped file, reach localStorage. That
  half was 535 lines inside `demo/universal_wasm`, where nothing published
  could reach it. It is now a package, and the demo is the ~90-line executable
  around it: which bundles to offer, whether to remember a session, one service
  to lend, and the export list. A host is `@uiw.mount(session~, samples~,
  requests~)`.

  Two shapes changed on the way out. The mutable page state — the store, the
  in-flight count, the loaded URLs, the app and the UI — is a `UniversalHost`
  rather than five module-level refs. And the bar's sample buttons are DATA: a
  `list<sample>` the host passes in, rather than six URLs hardcoded in a view,
  since a published component cannot know any bundle's name. Persistence is one
  `Session?` rather than a boolean threaded through four functions, because it
  has to be gated at both ends: a page that restores but does not save, or the
  reverse, writes an empty tree over the thing it exists to keep.

- **[`docs/dynamic-components.md`](docs/dynamic-components.md)** — hosting a
  bundle and writing one, in the published docs, which is where someone who has
  only the package can find it.

### Changed

- **The playground gives its space to the preview.** The state and activity
  panels used to sit UNDER the preview, so the running component — the thing
  the page exists to show — got about half of half the window, and the other
  half was a code editor whether or not anyone was reading it. Three changes,
  one goal:

  - **State and Activity are a fourth tab of the LEFT pane**, beside Component,
    View and Generated. Putting them there rather than over the preview is what
    lets both be read at once: the inspector is next to the component it
    describes, not covering it. The tab carries a dot when state changes while
    another tab is showing.
  - **The code pane collapses** — the ⟨ button in its tab strip, the `Code`
    rail it leaves behind, or Ctrl/⌘+B — and the preview takes the whole
    window. A compile error re-opens it, because the diagnostics panel lives
    there and a red status line is not a message.
  - **The divider drags.** Width and collapsed state persist in
    `localStorage`, so the layout someone settles on survives a reload.

- **The wasm-gc JS import shims moved out of `demo/`.** `app/wasm` and
  `vdom/wasm` were shipping with their JS import contract living only in an
  excluded directory, so a consumer could build a wasm-gc page and have nothing
  to instantiate it with. `demo/wasm-loader-lib.mjs` is now two files, split
  along the seam it already had:

  - `app/wasm/loader.mjs` — `jscore`, `tdom` and `instantiate`; every wasm-gc
    tutuca page needs it
  - `dyncomp/host/wasm/loader.mjs` — `tcomp` and `tkv` plus the bundle
    unpacker, linked through `instantiate`'s `makeExtra` hook

  A page that never loads a bundle now carries none of the second, which the
  counter and storybook demos did before. **Breaking for anyone who copied
  `demo/wasm-loader-lib.mjs`**: import the two published files instead. In
  `dist/` they land beside each page as `app-loader.mjs` and
  `dyncomp-loader.mjs`.

- **One guest SDK, not five.** `sdk.mbt` was copy-pasted into all five MoonBit
  guest trees, byte-identical but for two comment lines — five copies of the
  guest contract are five chances to disagree. The canonical file is
  `guests/sdk.mbt`, and `gen-bindings.mjs` copies it into each guest, so the
  existing `git diff --exit-code -- guests` drift check now covers it too.

- **`ci` gained `check-guest-template`**, which scaffolds a guest with the
  embedded template and compiles it with `--deny-warn`. Nothing else covers
  that tree: CI never builds a guest, and the template is assembled from three
  sources with placeholders substituted at write time, so all three can be fine
  and the result still not compile. It caught one immediately — a guest named
  `*-test` produces `*_test.mbt`, which MoonBit reads as a test file, so the
  author's `dyn_module` lands in test scope and the bundle declares nothing.
  That was a *warning*, not an error. `new-guest` now rejects the name.

- **A component can outlive the page it was on.** `tutuca:component` is
  `0.4.0` (manifest `api-version: 4`): an instance answers `persist()` with
  bytes ONLY IT reads, and `[static]instance.restore(component, bytes)` builds
  one back. The host stores them and never looks inside, which is what lets a
  guest keep what its declared fields do not name — which tab was open, a
  sentence half-typed. Empty bytes mean "I do not persist" and are a decision
  rather than a failure: the host can already project the declared fields and
  construct from them, so a component whose state is exactly its fields should
  say nothing and let the framework do it. A `restore` that refuses (a format
  the guest no longer reads) falls back to the same projection.

- **`dyncomp/persist`** — a `Snapshot` (what a stored component IS: the guest's
  bytes, the declared-field projection, and what it is called) and a `Store`
  (somewhere to put it). Text-shaped on purpose, with the bytes base64 inside
  the JSON, because every store worth having on a page is string-shaped and
  otherwise every implementation would invent the same encoding. Everything
  read back out is treated as untrusted input — a store is shared with whoever
  else writes to the origin. `MemStore` for a host with no browser storage;
  **`dyncomp/persist/wasm`** is `localStorage`, four calls wide, swallowing
  what a browser throws in private mode or at a full quota.

- **`Obj::persist_id`** — what an instance is CALLED across sessions, which
  `identity` deliberately is not (that one is a handle and a revision, both
  facts about this run). None means "do not store me" rather than "store me
  under something invented". `Bundle::make_instance` mints one when the caller
  has no better name, and `with_persist_id` takes the better name when there is
  one — a slot in a saved document, a row in a list.

- **TodoMVC, as a guest bundle** (`guests/todomvc`): add, toggle, toggle-all,
  edit in place, delete, the three filters, count-left and clear-completed.
  It is here for the split it demonstrates — `items` and `filter` are DECLARED
  (so the host owns `setFilter`, the projection, equality and migration) while
  the draft, the row being edited and its text are the guest's own, invisible to
  the host and kept anyway because `persist` writes them. Filtering is a
  `@when` the guest answers, so a filtered row still carries its index in the
  whole list and every per-row handler keeps working.

- **The whole viewport is the app, and the app is a component tree:
  `dyncomp/ui` + `dyncomp/ui/std`.** The root holds ONE component and it starts
  as a `Universal` — an empty cell with a `+` in it — so the first thing a
  person does is choose what the page is, and everything after that is the same
  gesture one level in. Clicking a `+` opens a command bar over the page,
  searching a catalog that holds the standard components and everything any
  loaded bundle declares; ctrl/cmd opens the generated form instead, which also
  opens by itself when a component has a required argument nothing has answered.
  Dropping the bar's `config` pill on a cell — or clicking its badge — opens a
  sidebar: a component that declares a `config` view of its own gets it rendered
  live, and everything else gets the same generated form, pre-filled from what
  the instance already holds. Containers grow hover-only insert buttons: before
  each child and after the last on a `Stack`, one per edge on a `Grid`.

  **`Universal` is a HOLDER, not a placeholder that gets replaced**, and that
  one decision is what the rest rests on. Everything a person places sits inside
  one, so the editing chrome has a single host-owned home that nothing has to
  opt into — a guest component is decorated exactly like a standard one, because
  neither is asked to participate. Every container's children are universals, so
  "insert a cell" needs no kind and no binding. And emptying a cell gives the
  `+` back instead of deleting it.

  Edit mode is a VIEW rather than a field: the app pushes `edit` with
  `@push-view`, every component that declares one shows its affordances, and one
  that does not — every guest — is simply itself in both. A boolean threaded
  through the tree would be the same fact stored once per node, and a guest,
  which cannot grow the field, could never join in.

  The standard set is `Universal`, `Stack`, `Grid` (uniform m×n), `Tabs` /
  `TabPage`, `Text` and `Textarea` — ordinary tutuca components in a package
  that knows nothing about bundles, so `moon test` drives all of it on the
  in-memory DOM. Only `Universal` has to exist; the rest are convenience, and a
  bundle shipping a better stack would be no different in kind. `guests/rust-notepad`
  reproduced by composition — tabs, a tab holding a universal, pick a textarea —
  is a test rather than a claim.

- **A component from anywhere is in the same catalog as the host's own.**
  `Registry` holds `builtins` beside its loaded modules, and `dyncomp/ui/builtins.mbt`
  builds each one's `Descriptor` from the component's own declared schema, so
  nothing can describe a standard component differently from how it behaves. The
  same search ranks them, the same projection generates their form, the same
  validator refuses their bad arguments with the same JSON Pointers. The ONE
  place they differ is construction: one is compiled in, the other arrived in an
  archive.

- **A guest can offer a hole for a person to fill.** A component declaring a
  field whose type names a component from ANOTHER module (`resource universal;
  body: universal`) gets it built and answered by the HOST, and never sees it —
  `DynObj` holds it, `member` answers it without crossing the bridge, and a
  successor carries it. No contract change: `ty-comp` already carried the name.
  It has to work this way round because the boundary allows nothing else — a WIT
  `value` has no case that can carry a host component. A same-bundle `ty-comp`
  is left alone, because that is the guest's own nested child.

- **REMOVED: `dyncomp/surface`.** The layout document and its six-op patch
  algebra were built, shipped in this same unreleased cycle, and are gone. The
  component tree is the layout now, and what replaced the algebra is the runtime
  `core/` already had: a `+` bubbles, `ctx.target_path()` is the fixed path of
  whoever raised it, the app keeps that path across dispatches and sends the
  answer back to exactly that component. The trade, plainly: what was lost is a
  serializable document with one atomic apply and a wire format an agent could
  diff; what was gained is one class of thing instead of two, and a seam that
  reaches INSIDE a guest's own placeholder — which a document describing only
  the host's layout never could. `docs/agent-runtime.md` was specified against
  that document and now carries a banner saying it needs redesigning;
  `dyncomp/ARCHITECTURE.md` records both the new shape and the known gaps.

- **Two more MoonBit guests: a calculator and tic-tac-toe.** They exist to
  cover the halves of the contract the counter does not. `calclib/Calculator`
  declares `display` — the answer, which a host can project, form and hand
  back — and keeps the pending operand and its operator to itself, because
  they mean nothing outside the component and a host that could write them
  could not reason about what it wrote; so it `persist`s, as its own JSON.
  `gameslib/TicTacToe` declares the board as a list and stores nothing else:
  whose turn it is, who won and which line they won on are all functions of
  it, and state that can be computed is state that can be wrong. It has no
  `persist` for the same reason the counter has none — the board IS the
  declared field.

  Both are sample bundles on the universal demo. The tic-tac-toe board also
  re-learns a lesson the Rust notepad had already recorded: a `$method` takes
  no arguments in a conditional slot, so "is this square part of the winning
  line" rides ON each square rather than being asked per square. Written the
  other way it renders no class at all, silently.

- **`dyncomp/jsonschema`** — the declared schema to JSON Schema (draft 2020-12)
  and back. ONE projection with two consumers, a generated form and a tool's
  `parameters`, because two would drift in the direction of the form accepting
  what the tool rejects. `TyRecord` / `TyEnum` / `TyVariant` become a titled but
  UNCONSTRAINED `$defs` entry (the declared schema knows a record's name and not
  its fields, and claiming `type: object` would be inventing a fact); a `TyComp`
  slot becomes a component reference, since the host builds the child. Reading
  back collects EVERY error with a JSON Pointer rather than the first.

- **`dyncomp/registry`** — the catalog across loaded bundles, and search over
  it. The weights live in one place so the ranking is arguable rather than
  emergent, and every hit carries WHY it matched: a search a person cannot
  explain is one they stop trusting. Describing the catalog never calls a guest.

- **`dyncomp/surface`** — the layout model and the six-op patch algebra the
  editor drives. A flat node table with children by id, so an edit is not a
  rewrite of the path down to it; an ATOMIC batch, because a caller that got
  half a layout cannot tell what it now has; a flex/grid subset that stops at
  `Nfr` / `Npx` / `auto`, since `minmax` / `repeat` / `calc` are where a
  generated layout silently collapses; and unknown prop names as errors rather
  than silence. One document format for export, read-back and resuming.

- **`dyncomp/policy`** — the executable half of `dyncomp/SECURITY.md`. `host`
  owns the mechanics of loading and this owns the decisions, so "what can a
  dropped bundle do to my page" has one answer instead of six call sites.

- **A bundle says what it is.** `tutuca:component` is `0.3.0` (manifest
  `api-version: 3`): `doc` / `keywords` / `category` / `message-docs` per
  component, `doc` per field and per init fixture, and a `constraint` (min /
  max / lengths / pattern / format / enum / default) — the half a TYPE cannot
  state. `ty-def` says a field holds a string; the constraint says it holds an
  email under 254 characters, and a form and a JSON Schema both need the second
  half. The manifest also carries advisory catalog metadata (doc / version /
  homepage / authors) and its capability requests.

- **`env` and `control.after`, each behind a capability.** `now-ms` coarsened
  to a second and FROZEN for one dispatch, `random-u64` from a seeded xorshift,
  `new-id` monotonic per bundle, plus `locale` / `tz-offset-min` — deliberately
  weaker than the platform, because the world imports no WASI, a real monotonic
  clock is the primitive a timing side channel is built from, and an ambient
  clock makes a dispatch unreplayable. `control.after` asks the host for a later
  message; the host owns the timer, so there is no cancel. Both gaps are
  recorded rather than hidden: the browser bridge still supplies `env`
  unconditionally rather than per grant, and `control.after` has no host
  implementation yet.

- **`dyncomp/SECURITY.md`, `dyncomp/ARCHITECTURE.md` and
  `docs/agent-runtime.md`** — what a bundle can and cannot do with the
  file/line evidence for each claim, where this sits against AG-UI, A2UI and
  MCP Apps, and six fixed tools over a declarative surface patch (rather than
  one tool per component, which a runtime-mutable catalog cannot offer).

- **A wasm guest DECLARES its state, and stops implementing what the
  declaration already says.** `tutuca:component` is `0.2.0` (manifest
  `api-version: 2`, and a manifest declaring anything else is refused rather
  than adapted — the contract is prototype-stage and breaks cleanly). A
  `component-def` now carries its fields over a flat `ty-def` table (WIT has no
  recursive types, so a compound points at its parts by index), its message
  buckets, its `@when` filters, the requests it serves and its named `init`
  fixtures. From that the host builds a real `SchemaInfo`, which is what gives
  a guest — with no guest code — structural equality, `Value::to_json`, the
  debug rendering, hot-swap migration, the inspector's form, and the generated
  per-field mutators. A guest that declares `count: s32` gets `setCount`.

- **`@component.FieldBox` and `@component.schema_mutators`.** The generated
  mutators (`setX`, `toggleX`, `pushInX`, `setInXAt`, …) used to be written
  against `TypedInstance`; they are written against three closures now — read a
  field, write one, name the instance — so the same generator serves a typed
  instance and a wasm guest whose fields live behind `get-field` /
  `with-field`. One implementation, one set of semantics.

- **`SchemaInfo::shape_fingerprint`**, for a schema that arrives at runtime and
  has no generated `<v>_schema_fingerprint` to carry. The runtime twin of
  `@statedef.fingerprint`, which hashes the same shape one step earlier.

- **`Component::view_handler_names`**, and `compile()` filling in a schema's
  `inputs` when nothing stated them. The names a view raises live in the parsed
  tree; the generator states them ahead of time, and a component whose views
  arrive at RUNTIME now recovers them instead of having an empty descriptor.

- **A drop's files reach handlers as `value`.** `@on.drop="load value"` gets a
  `List` of the dropped files (`id`, name, size, type, lastModified) on both
  backends. The `File` itself never becomes a `Value` — the backend keeps the
  last drop's files and a host reads one back by id — which is what lets a page
  take a dropped file without installing a listener of its own. The universal
  demo's page-level drop-zone JS is gone.

- **Guests reach the rest of the framework**: the `bubble` bucket (a guest
  parent hears a guest child's `emit`), `stop-propagation`, `send-at` /
  `bubble-at` over paths relative to the dispatching component, `request-opts`
  (`on-ok` / `on-error` / `on-res` / `live-path`), `@when` filters answered
  through `call-method`, and requests a BUNDLE serves — registered in its own
  scope, so its components find them before the host's.

- **A bundle's views are linted when it loads** (`Bundle::diagnostics`), with
  the findings logged by the wasm glue. A guest's views are the one part of a
  component that never went through a build step, so this is the only feedback
  its author gets.

### Fixed

- **Every wasm-gc preview in the playground failed to link, and said the
  browser was at fault.** `playground/web/runtime.js` carried its own copy of
  the `jscore` and `tdom` import namespaces that `app/wasm/loader.mjs` defines.
  `tdom` grew `dropped_files`; the copy did not follow; from then on every
  wasm-gc mount — the DEFAULT target, in the standalone playground and in every
  `<mb-playground>` on the landing page — died with `LinkError: Import #8
  "tdom" "dropped_files": function import requires a callable`. The js fallback
  caught it, so the page kept working and reported `wasm-gc not supported
  here`, which is why it survived a release: the one message a reader cannot
  act on and an author reads as somebody else's problem.

  runtime.js now imports the loader (`./app-loader.mjs`, copied into
  `dist/playground/` by `assemble.mjs` and packed into the npm shell) and
  substitutes only `global_this`, which must be the preview iframe's window
  rather than the page's. There is no second copy of the contract left to drift.

  Two guards, because a wasm-gc mount is only exercised by a browser:
  `check-viewgen-tab.mjs` now instantiates its import object FROM that loader
  and fails the build when a linked module names something the loader does not
  supply (it catches this exact bug — verified by removing `dropped_files` and
  watching it fire), and the fallback now reports the real error instead of
  blaming the engine, in the standalone shell's status and diagnostics and as a
  `console.warn` from the embeddable element.

- **A browser host could not choose what it accepts.** `dyncomp/policy` has
  three tiers and `register_bundle` takes one, but `dyncomp/host/wasm` called it
  without an argument — so every bundle a page loaded was registered as
  `untrusted` and there was no way to say otherwise. A host that wanted to grant
  a capability could not, which made `Granted` and `System` reachable only from
  a test: any bundle declaring `cap-clock` or `cap-random` was refused by every
  page that could actually run one, and shipping its own CSS was likewise
  impossible. `@uiw.mount` now takes `policy` (still defaulting to `untrusted`,
  which is the only safe default for a loader whose purpose is to accept an
  archive from somewhere), `@dhw.set_app` takes it for a page that mounts
  itself, and `@dhw.set_policy` changes it afterwards for a host that asks a
  person first. It applies at LOAD, so narrowing it does not retract a bundle
  already registered — revoking is dropping the bundle.

- **A scaffolded guest could not be built.** `tutuca new-guest` writes a
  `build.mjs` that ran jco from a hard-coded `node_modules/@bytecodealliance/
  jco/src/jco.js`, and it declares that dependency as `^1.25.2`. jco 1.26 moved
  its entry point to `dist/jco.js`, so a scaffold created after that release
  npm-installed cleanly and then failed on the transpile step with "jco is not
  installed" — the one error message that could not be acted on, because it was
  installed. The path now comes from jco's own manifest (`bin.jco`), which is
  the one place that cannot disagree with the layout. Found by
  `examples/dyncomp-dice`, which is what it is for.

  The repository's own guest builders had the same hard-coded path and were
  merely hidden by its pin: `guests/build-guest.mjs` and
  `guests/rust-tempconv/build.mjs` broke the moment the devDependency moved to
  1.26, taking `just guests` with them. They ask the manifest now too, through
  a shared `jcoBin()` in `guests/guests.mjs` — resolved from this repository's
  `node_modules` and never from `PATH`, where the bare `jco` name is a
  dependency-confusion placeholder.

- **An update that changed only what a schema does not name was thrown away.**
  `reuse_equal` — the check that keeps a rebuilt-but-equal field from
  propagating a new object to the root — compared two INSTANCES structurally,
  and `eq` ranges over the declared fields. So a successor that changed
  something its schema does not name (an opaque guest's draft, a cursor, a
  parser's arena) looked exactly like its predecessor, the parent kept the
  predecessor, and the edit vanished — silently, with the successor's handle
  already queued for collection, which is where the bridge's `no live
  instance` warnings came from. Instances are compared by `identity` now:
  same origin and same revision, or not the same instance. Writing the SAME
  instance back still collapses, so a no-op interaction stays free.

- **A comment inside a view costs more than a comment should.** One before a
  template's root element makes the view a fragment; one INSIDE it sits where
  the renderer's `§…§` boundary meta is expected and ends the chain dispatch
  walks — which is how a click inside a component nested in that view stops
  reaching it. The editor had both, and its placed components were inert
  because of the second. The prose moved out of the template; the trap itself
  is still there and is worth a linter rule.

- **The editor held its placed instances twice**, and the copy went stale the
  moment one of them was used: a successor lands in the rendered tree, so the
  map beside it was one update behind and — once the superseded sweep ran — was
  holding a guest handle the host had already collected. The tree is the only
  holder now (`@ui.live_slots` reads them back out), and the bridge answers a
  handle it does not have with a warning and an empty answer instead of
  throwing mid-render.

- **An `@if` branch that does not parse says so.** `@then="btn btn-primary"` is
  a class list that forgot its quotes; it used to leave the branch unset, which
  is indistinguishable from not writing one, so the element rendered with no
  class and nothing reported why — least visible of all next to a static
  `class`, which then appears to work. It is a `BadValue` now, and `gen-views`
  fails on it. An unset branch stays legal and silent.

- **`<input class="a" />` is not a duplicate attribute.** The vendored
  tokenizer finishes the last attribute a second time when a solidus follows
  whitespace and reports its name as a duplicate of itself, so every
  self-closing element with attributes carried a bogus
  `HTML_DUPLICATE_ATTRIBUTE` warning. Found by running the linter over a wasm
  guest's views, which is where the warning had nowhere to be seen.

- **The universal demo's picker showed its chrome over the component it had
  already selected**, when that component's own `seq-entries` were empty (a
  fresh counter, whose history is). `truthy?` is the SIZED predicate; asking
  whether something has been picked is `null?`. Its layout buttons were also
  unclickable with a real mouse: `.btn:active` sets `translate`, which
  overrode `.indicator-item`'s and moved the button out from under the cursor
  between mousedown and mouseup.

### Removed

- **From the guest contract: `instance.eq`, `instance.to-json`, the
  `dom-event` record and `handle-event`'s event parameter, and the manifest's
  four handler-name lists.** Equality and the JSON projection are the declared
  schema's; a handler's arguments arrive evaluated (`event` / `target` / `ctx`
  are not handler arguments in tutuca); the names a view raises are read off
  the compiled views. What a guest still declares is `handlers` — the input
  names it answers ITSELF, the rest being mutators the host applies.

- **The storybook's "Dynamic" pane and `dyncomp/host/wasm`'s `shell_module`**,
  a second loading UX maintained beside the universal demo's. The demo gained
  what the pane demonstrated: loading a bundle by URL, and hot-swapping a
  loaded module with the mounted components migrating into it. `cmd/dev --
  storybook-bundle` goes with it.

- Test-only and internal `@render` exports: `ViewMap`, `ViewRegistry`,
  `CompiledView`, `CacheEntry`, `render_view`, and the non-lifecycle
  `RenderCache` methods (`get`, `set`, `stats`, `size`, `evict`). Production
  integrations keep `render_root`, the resolver/boundary traits, and
  `RenderCache::new` / `clear` / `next_generation`.

### Changed

- **BREAKING: every `App` sanitizes its own render output now.** `App::new`
  installs `@filter.Baseline` — the URL-scheme rule and the event-handler rule
  in one traversal — where the seam previously defaulted to absent. An app that
  renders `<a href="javascript:…">` from its state, or writes a raw `onclick`
  content attribute, loses that attribute instead of writing it to the DOM.

  The old behaviour is one call: `App::set_filter(None)`. Worth taking
  deliberately rather than reflexively — what it is for is an app with a
  genuinely intended `javascript:` URL, or a tree with no user-supplied data
  anywhere in it.

  The reasoning, for anyone who has to decide which way to go: the trusted
  default was paying nothing and getting nothing, while every app that had never
  heard of the seam was the one carrying the risk. `dyncomp` hosts were already
  covered because their glue installed a filter explicitly; a plain tutuca app
  was not, and `Policy::check_view` — the static pass — has a single call site
  and never runs for one. So "safe by default, opt out in one call" replaces
  "safe if you read `docs/sanitizer.md`".

- **`take_reports` is a `VdomFilter` trait method** rather than an inherent one
  on each filter, defaulting to none for a filter that only rewrites. A host no
  longer necessarily holds the concrete type — the filter that drops something
  is usually the one `App::new` installed — so draining had to work without it,
  or the new default would be a silent dropper and "why did my link vanish"
  would have no answer. `App::take_filter_reports()` is the accessor.

  `dyncomp`'s glue stops installing its own filter, since the app already
  carries one and two would split the reports across two logs. Its
  `take_filter_reports()` drains the app's. That also retires a caveat
  `SECURITY.md` carried: the install used to be one line in the wasm glue, which
  `moon test` never runs, and is now in `App::new`, which the suite exercises.

- **The Rust guest is a temperature converter** (`guests/rust-tempconv`, was
  `rust-notepad`, before that `rust-counter`). A counter never has to answer
  the questions the newer halves of the contract exist for; this does. It
  declares ONE number and shows it three ways, and the half its declared field
  cannot hold is the DRAFT: somebody heading for `-40` is at `-` on the way,
  and reformatting their box while they type is the difference between a
  control that works and one that fights. `-` is not a number and no declared
  field can hold it, so it goes in `persist` — a length-prefixed byte string of
  the guest's own, which demonstrates "the host never reads these" better than
  JSON would.

  The notepad it replaces is now buildable out of primitives (a `Tabs` holding
  a `Textarea`), and a component that primitives compose into is not one worth
  shipping as a bundle. That composition is the acceptance test in
  `dyncomp/ui/ui_test.mbt`.

- **The universal demo keeps your session.** The layout, the bundles (by URL —
  a dropped file is not something a page can fetch again) and every placed
  component go into `localStorage` on each settled cascade and come back on the
  next visit. A hot swap now carries placed instances across through the same
  snapshot, so reloading a bundle over a running one is a save and a load with
  no store in between.

- **`register_bundle` refuses with the reason in it.** It raises one error type
  now, so a page that turns a bundle away shows "this host takes no CSS from a
  bundle" instead of the generic "bad manifest or view" every failure used to
  collapse into.

- **The catalog of loaded components is kept by the wasm glue**
  (`@dhw.registry()`): registered on load, replaced in place on a hot swap so a
  module keeps its position in the palette, and forgotten on drop. That is the
  code that already knows about all three, and a second copy elsewhere would be
  a second thing to keep in sync.

- Render's package-only tests are white-box tests now, so their source-view
  resolvers and cache probes no longer inflate the published API. The render
  cache also stops maintaining hit/miss counters on every lookup; tests prove
  reuse and eviction directly through VDOM identity and cache generations.

- **Superseded guest handles are collected on the transactor's drained
  cascade** (`@dyncomp.install_gc`), after the App's re-render, rather than at
  the start of the next guest dispatch. The explicit settling work landed the
  hook this always wanted.

- **The universal demo is the one page that hosts runtime-loaded bundles**, and
  it is written the way the framework asks for now: a `component` slot instead
  of `any`, declared `receive` / `bubble` / `response` variants instead of
  string-matched dispatches, and typed messages raised through the generated
  `bubble` helper.

### Security

- **A bundle is `Policy::untrusted()` by default**, enforced before the manifest
  is parsed: no capabilities, no stylesheet of its own, quotas on manifest size.
  An ungranted capability refuses the BUNDLE rather than degrading it — a guest
  reading a frozen zero from an ungranted clock cannot tell that from midnight.
  The tiers differ in convenience, not authority: at every one a bundle can
  still declare components, ship views, hold state, handle events, nest children
  and serve its own requests. `allow_custom_css` currently means someone vouched
  for a bundle, not that anything checked it.

- **`@dangerouslysetinnerhtml` in a guest view is refused**, over the shadow
  parse the linter already does and before anything is registered. Guest CSS,
  which is scoped by concatenation and would escape through a `}`, is held
  instead as a contract invariant: no guest-declared field reaches the host's
  unscoped `global_style`, and the WIT says so.

- **The WHATWG Sanitizer API, ported over anode views** (`anode/sanitize`) —
  the spec's config model (`elements` / `removeElements` /
  `replaceWithChildrenElements` / `attributes` / `removeAttributes` /
  `comments` / `dataAttributes`) with its validity relation, over the compiled
  `ANode` tree. Everything the config model asks about is a NAME, and every name
  in a view is a literal — the parser lowercases what it reads and stores it as
  a `String`, so there is no `:onCl${x}ick` — which is what makes an allowlist
  over names COMPLETE over the described part of a view, and the pass decidable
  at registration rather than at render.

  Safety comes from the entry point rather than the config, as in the spec: the
  unsafe elements and every `on*` attribute are refused before a config is
  consulted, so a config naming `script` still does not get `script`. The event
  handler half is a prefix predicate rather than the spec's enumeration, which
  is a superset that cannot fall behind the platform.

  `SanitizerConfig::default()` is the BASELINE, not the spec's default
  configuration — those are different things, and conflating them would refuse
  an ordinary commented view. The spec's element allow-list is deliberately not
  transcribed: it has to come from the specification text rather than a summary
  of it, because an entry quietly lost is a component that mysteriously fails to
  render and one quietly gained is a hole. A host wanting an allow-list supplies
  one and gets `validate()` to keep it honest.

- **`Policy::check_view` runs the sanitizer instead of `has_raw_html`, which
  closes a live hole.** `ANode::for_each_child` never visits `MacroData.slots`,
  so raw markup inside a macro call's slot —
  `<x:card><div @dangerouslysetinnerhtml=".payload"></div></x:card>` — passed
  registration with no refusal. It only rendered if the host had registered a
  macro named `card` whose body placed the slot, so the hole was contingent
  rather than unconditional. The sanitizer carries its own walk rather than a
  fix to `for_each_child`, because `set_data_attr` and `collect_registered`
  share that function and adding `slots` would make them stamp and index the
  same subtree twice once expansion has run. Refusals now name the element and
  carry a locator.

- **A filter seam between render and diff** (`vdom/filter`), for the half the
  Sanitizer API declines to decide. The spec has no opinion about attribute
  VALUES — its own default configuration allows `href` on `<a>`, so
  `<a href="javascript:…">` comes through `setHTML()` untouched, and the
  platform answers that with CSP and Trusted Types instead. anode answers it
  here: a `&VdomFilter` runs between `render_root` and the diff, installed with
  `App::set_filter`.

  It is absent by default, so trusted code pays one `if` per render rather than
  a branch per attribute. It mutates rather than rebuilds, which is load-bearing
  and not a style preference: morph short-circuits a subtree by physical
  identity and the render cache hands back the same `Vdom` object when a site's
  inputs are unchanged, so a filter that rebuilt nodes would quietly turn every
  render into a full diff.

  `UrlFilter` is the rule that ships: normalize (strip whitespace and C0
  controls from anywhere, since `java&#9;script:` is `javascript:` to a browser,
  then lowercase), take the scheme only when its `:` precedes any `/`, `?` or
  `#`, deny `javascript` and `vbscript` outright, and deny `data` on the
  navigational names while allowing it on the media ones — `<img src="data:…">`
  is ordinary, `<a href="data:text/html,…">` is a same-origin document.
  `srcset` and `ping` are checked per entry, because they are lists and a
  whole-string check would pass `"a.png 1x, javascript:… 2x"`. A denied value
  drops the ATTRIBUTE, not the element, and is recorded in a bounded log the
  host drains with `take_reports()` — by then there is no author to report to,
  and the value may have come from application state rather than anyone's
  template.

  Installing is not retroactive: a value already in the DOM stays until
  something re-renders over it, for the same reason a policy applies at load.

- **The dyncomp host installs one**, so a loaded bundle gets both passes rather
  than only the static one — `set_app` calls `set_filter` beside the policy and
  the GC sweep, and `take_filter_reports()` drains the log.

- **Raw markup as described NODES** (`vdom/filter/markup`), its own package
  because it drags an HTML parser and the config model behind it and a host that
  only wants the URL rule should not pay for either. The obvious port of
  `setHTML()` — parse, prune, serialize, `set_inner_html` — is the shape that
  has bitten every sanitizer which shipped it: the browser parses the string a
  SECOND time, and any disagreement between the two parsers is a mutation-XSS
  vector. So the payload is parsed once, sanitized as a tree, and the result
  replaces the element's children; `set_inner_html` is never called, because the
  attribute `set_prop` looks for is gone by then. The subtree is checked by the
  builder, attribute values included, since no filter runs after the one that
  created those nodes.

  Guests are still refused the construct outright: `check_view` cannot know
  whether a host installed the filter, so a policy permitting raw markup beside
  an app mounted without it would send the payload straight to
  `set_inner_html` unchecked. Loosening that should be one explicit decision
  rather than a side effect of the capability existing.

- **memdom answers `has_property` truthfully for `on*`.** It listed reflected
  and state properties only, so `"onclick" in node` came back `false` and
  `set_prop` sent the name to `set_attribute` — writing a live
  `onclick="…"` content attribute where a browser, for which the name IS a
  property, assigns an inert string to `.onclick` instead. memdom is the DOM
  every `moon test` renders onto, so the divergence ran the wrong direction for
  a test double: anything asserting that this attack fails would have asserted
  it against a DOM that makes it succeed. Same prefix predicate as
  `@sanitize.is_event_handler_attr`.

- **`on*` attribute routing is pinned** (`vdom/memdom/event_attr_test.mbt`).
  Not a construct tutuca asks for — a handler is `@on.click`, which compiles to
  `data-eid` and never reaches vdom as an `on*` name — but a view that writes
  the content attribute directly is the case a sanitizer exists for. The tests
  record that on a plain HTML element the string lands on the property and is
  inert, that this is an accident of routing rather than a defense (the
  property branch falls through to `set_attribute` when assignment fails), and
  that **on a namespaced element it is not inert at all**: `uses_prop` is
  `!namespaced && …`, so `<svg onclick="…">` and `<circle onload="…">` are
  written verbatim as content attributes, which SVG honours. `anode/sanitize`
  refuses the name at registration, but only for a dyncomp guest — a plain app
  runs no static pass, so that half is open and `docs/sanitizer.md` now says
  which change closes it. There is also a test for why `never_assign` is not
  the fix: it would force the attribute path on plain HTML elements too.

- **An event-handler rule at render time** (`@filter.HandlerFilter`), which is
  the half of the name rule a plain app can reach. `anode/sanitize` settles
  names at registration and is the better place — it is cheaper and it can tell
  the author — but `Policy::check_view` has one call site, so that pass runs for
  a dyncomp guest and nobody else. The filter drops `on*` off the tree before
  the diff, by name and whatever the value's type, since a view cannot express
  a function and tutuca's own handlers are `@on.click` compiling to `data-eid`.
  It is the only thing that covers the namespaced case, where no accident of
  routing applies.

  `@filter.Baseline` composes it with the URL rule in ONE traversal, rather than
  `Chain::new([…])`, which walks the tree twice for two rules that both only
  read `attrs` — a difference worth a type given the filter runs on every
  render. `dyncomp` installs `Baseline` now instead of `UrlFilter`: the handler
  half is belt-and-braces there, since a guest carrying an `on*` name never
  loads, but a rule that only holds when another pass already held is not a
  second layer, and the shared walk makes it free.

  Still opt-in for a plain app — `App::set_filter(Some(@filter.Baseline::new()))`.
  Making it the default is a behaviour change for every existing app and is
  tracked separately in `docs/sanitizer.md`.

- **A `Policy` carries its own sanitizer**, so a host can tighten what a guest
  view may name or loosen it. `Policy::with_sanitizer(config)` returns the same
  policy checking against a different `@sanitize.Sanitizer`, raising on an
  invalid config rather than degrading — an invalid config is a programming
  error in the host, the one party here who can read the message and fix it.
  Tightening means an allow-list (the spec's own is still not transcribed, so a
  host that wants one writes it and gets `validate()` to keep it honest);
  loosening means `raw_markup: true`.

  That last one was held back before, because `Policy::check_view` had no way to
  know whether the render-time markup filter was installed, and the permission
  without the filter sends a payload straight to `set_inner_html` unchecked. The
  answer is `@markup.filter_for`, which derives the filter from the SAME
  sanitizer the policy checks against: the markup filter in front of `Baseline`
  when raw markup is permitted, `Baseline` alone when it is not. `set_app` calls
  it, so the two cannot come apart.

  A function rather than a type-level proof because `dyncomp/policy` is a leaf
  over `anode` and must not import `vdom`; the permission cannot carry evidence
  about a filter without inverting that direction. What is available is to make
  one function the only place the two are named together, and to test it from
  both sides.

  Order inside the chain is load-bearing: the markup filter REPLACES a subtree,
  so the attribute rules run after it or they inspect nodes that do not exist
  yet. Built the other way round, a payload's own `javascript:` URL survives.

  Defaults are unchanged — every tier still refuses raw markup, so a guest that
  was registered before is registered now. `Policy` is `pub(all)` and gained a
  field, so code building one as a literal has to add `sanitizer:` (or go
  through `untrusted()` / `granted()` / `system()`, which is the intended way);
  the `Policy::sanitizer()` method is now that field.

- **The filter runs where an element is CONSTRUCTED**, not over the finished
  tree. `RenderCtx` carries it and `render` applies it in the one place it
  builds an element, so every element is filtered exactly once and a subtree the
  render cache hands back — never rebuilt — is never filtered again.

  Applied to the finished tree it had the wrong complexity, which defaulting it
  on made everyone's problem: the cache returns the same `Vdom` object for an
  unchanged site and morph then short-circuits it by physical identity, so the
  filter did O(whole tree) work beside a pipeline that is otherwise O(changed).
  On a thousand-row list, morph touches one row and the filter touched a
  thousand.

  The obvious fix — walk each rebuilt body, stopping at nested `§Comp§`
  boundaries — does NOT work, and the reason is worth knowing: `@vdom.fragment`
  flattens nested fragments (`normalize_childs`), so a nested component's
  `[meta, body]` is spliced inline into its parent's child list and there is no
  boundary left to stop at. A test counting filtered elements caught it at once.
  Hooking construction sidesteps the question entirely and costs no walk at all.

  Two consequences. `App::set_filter` now **clears the render cache**, because a
  cached subtree carries the verdict of whichever filter built it and a newly
  installed one would otherwise never see most of the tree. And a filter that
  replaces children owns checking what it built — nothing runs after it on nodes
  it created — which `MarkupFilter` already did by design and now depends on.

  `VdomFilter`'s primitive is `filter_elem` accordingly; `filter_tree` remains
  as a defaulted convenience for a caller holding a tree.

  Measured: `OPTIMIZATIONS.md` #11. Interleaved 3× per side on both targets —
  `patch move json 8x4` −34.8% / −37.9%, `toggle todo 1000` −28.6% / −20.4%,
  `add+remove todo 1000` −24.7% / −17.4%. The win scales with how much a render
  reuses, so the rebuild-everything workloads move inside their own spread.

  What the filter still costs, with that fixed, is +4% to +33% on what actually
  rebuilds — measured against `set_filter(None)` and recorded in #11. Inspecting
  every attribute of every element BUILT is the irreducible part; the only
  remaining lever that does not weaken the rule is the skip set.

- **The filter's no-op path stops allocating** (`OPTIMIZATIONS.md` #12).
  `url_attrs.contains(name.to_lower())` allocated a String for every attribute
  of every element before discovering the name is not a URL attribute at all —
  which is what almost every name is. `is_url_attr` probes the set with the name
  as it stands and falls back to `to_lower` only for a name that contains an
  uppercase letter. Both filters also allocated a `doomed` array per element for
  names they almost never collect; lazy now. −2% to −3.5% on the workloads that
  construct the most elements, consistent in direction, nothing worse.

- **An SVG `<script>` was not refused.** `<svg><script>alert(1)</script></svg>`
  in a guest view passed `Policy::check_view` with **no violation at all** — so
  it registered, rendered into the host's page, and an SVG `script` inserted
  through the DOM executes.

  The cause is worth stating plainly, because it is the exact failure the design
  document had warned about in the abstract: the baseline list was written from
  a SUMMARY of the spec rather than from the spec. The spec's baseline lists
  `script` **twice**, once per namespace, and element identity here is
  namespace-qualified (`ElementName::key` prefixes `svg:`), so `html("script")`
  never matched it. `svg("script")` is in `unsafe_elements` now.

  `unsafe_elements` is held against the spec's own baseline by a test from here
  on, against a list generated rather than typed. Containment, not equality:
  tutuca additionally refuses `base` — a `<base href>` retargets every relative
  URL on the host's page — and the difference is asserted explicitly so a
  regeneration cannot absorb it silently.

- **The spec's default allow-list is transcribed**, as
  `SanitizerConfig::spec_default()`: 121 elements across three namespaces with
  their per-element attributes, 58 global attributes, comments and `data-*` off.
  Generated by `scripts/fetch-sanitizer-defaults.mjs` from the machine-readable
  `builtins/` in the spec repo at a pinned commit — which is what the spec's own
  prose is generated from, so it cannot drift from the text the way a hand
  transcription can. `--check` fails if the committed file is stale.

  **It is offered, not imposed, and `default()` is still the baseline.** Not
  caution: the spec's default configuration allows no interactive or media
  element at all — no `button`, no `input`, no `img`, no `form`, no `select`. It
  is built for pasting document content into a page, and a tutuca view describes
  an interactive component, so adopting it as the default would refuse
  essentially every real guest. A host whose guests really are document content
  hands it to `Policy::with_sanitizer` and gets the platform's own answer.

  `AGENTS.md` now carries the general rule: never hand-transcribe an allow-list,
  and never take one from MDN or a blog post. An entry quietly lost is a
  component that mysteriously fails to render; one quietly gained is a hole.

- **`SECURITY.md` §3 is rewritten**, including a claim it got wrong about URL
  schemes. Design, and the work still open, in `docs/sanitizer.md`.

## [0.9.3] - 2026-07-30

### Fixed

- **`slots~` now names a slot the schema declared as the bare `component`
  marker.** A state block can say "this field is a component slot" without saying
  *which* — most often because the name is not spellable there, kebab-case being
  unable to round-trip `DnDExample` (`d-n-d-example` comes back as
  `DNDExample`). `slots~` is then the only place the name can come from, and it
  was read and dropped: `component()` only added slots for fields the schema did
  **not** declare, so a declared-but-unnamed slot kept its empty component name,
  `lookup_component("")` found nothing, and the field stayed `Null`.

  The visible cost was the composability example's Drag-and-Drop tab rendering
  empty, in the storybook and in every demo host. That example had no test, which
  is why it went unnoticed; it has one now, asserting on the child's own markup
  after clicking the tab rather than on the slot merely being non-null.

  A slot the schema **names** is still not overridable — a caller contradicting a
  declared type would leave the inspector and structural equality disagreeing with
  the block — and that half is now pinned by a test too.

  This also restores, in a narrower and true form, the reason the `as=`-view check
  in `gen-views` is a hint rather than an error: the component filling a bare
  `component` slot is MoonBit the generator cannot see. The comments in
  `viewgen/` and `cli/gen_views.mbt` that stated the old, broader rationale are
  corrected.

- **Two stale doc comments in the library.** `Path::update`'s contract in
  `core/path_spec.mbt` still described resolving a handler "exact name, then the
  `$unknown` fallback" — that sentinel was removed in 0.9.0 and dispatch does one
  lookup. `component()`'s doc comment still described the `specs` parameter and
  `FieldSpec::comp`, both removed; it documents `slots` / `slot_args` now.

- **`testing.md` overpromised the harness's selectors.** They are ONE compound
  selector — a tag plus `#id` / `.class` / `[attr]` qualifiers — with no
  descendant combinator, so `.pane .row` silently matches nothing rather than
  scoping. Found while writing the composability test; the skill said
  "CSS-selector addressed".

## [0.9.2] - 2026-07-30

### Added

- **`cmd/dev -- check-skill` compiles the bundled skill's snippets**, and `ci`
  runs it. Nothing compiled `skill/tutuca/` before, and it rotted: `specs=` and
  `@component.FieldSpec::comp(...)` outlived the parameter's removal by two
  releases in five files, and the skill ships *inside* the CLI binary, so a wrong
  snippet is what an agent reads before writing any tutuca code.

  A recipe that shows both halves — a `.html` view file, then the MoonBit that
  uses it — gets the view half generated by the same js-built generator the
  playground check uses, and the pair compiled together, so a snippet is checked
  against the REAL generated surface (`counter_component`, `CounterMsg`) rather
  than a stub. The unit is a markdown **section**: snippets in one section refer
  to each other, snippets in different sections are unrelated components that
  would collide.

  Fences are load-bearing — bare ` ```moonbit ` is compiled, `moonbit fragment`
  is wrapped in a `fn` first, and `moonbit nocheck` is skipped but must carry a
  `// nocheck: <reason>` line. Most blocks are bucket-argument fragments
  (`update=(s, msg, ctx) => ...,`) that no wrapper makes compilable, which is the
  right shape for the doc and also exactly where the rot lived. So every block,
  `nocheck` included, additionally goes through an **identifier check** against
  the checked-in `.mbti` files: a `@pkg.Name` that appears in no interface file,
  or a `name=` keyword argument no tutuca API takes, fails. That second pass is
  what catches a removed parameter, and the run reports its own coverage (18 of
  67 blocks compiled) rather than implying the whole skill is compile-verified.

- **`skill/tutuca/schema.md`** — the `<script type="tutuca/spec">` language in
  one place: every field spelling, the mutators each kind generates, slots,
  message buckets, declared `$`-callables, `tutuca/init` fixtures. It merges
  cli.md's WIT-subset section with core.md's field-kind table, which described
  the same thing from opposite ends with core.md holding the stale copy. It also
  covers three declarations nothing documented: a freestanding `func` (which
  cli.md listed as UNsupported — the opposite of the truth), `variant bubble` /
  `variant response`, and `resource` / `own<c>` / `borrow<c>` slots.

- **`skill/tutuca/events.md`** — handler argument names, the generated
  `<Comp>Msg` payload-type table, modifiers, and custom-element events, out of
  core.md.

- **`core.md` gained the sections its own frontmatter promised.** *The handler
  buckets* is now one canonical anchor covering all seven buckets, the
  enum-match vs string-keyed-map spellings, and `Input` dispatch precedence
  (swap → update → generated mutator) — replacing a disclaimer that was paid for
  in eight places. **`swap` is documented at all**: it was named in the SKILL.md
  description and nowhere else, a trigger that loaded the skill and dead-ended.
  Also new: teardown and observation of a mounted `App` (`root_value`,
  `render_count`, `event_names`, `transactor.observe`'s unsubscribe closure,
  `destroy`), and, in cli.md, every diagnostic `gen-views` can report — the 27
  lint codes with their three levels, `state-without-views`, `NotIterable` /
  `NotRenderable`, and the drift check.

### Fixed

- **~25 stale or invented API references in the bundled skill**, each verified
  against the checked-in `.mbti` files. The parameter `specs=` and the type
  `@component.FieldSpec` no longer exist (`slots~` / `slot_args~` replaced them);
  `Component` lost `compute_names` / `generated_names` / `has_update` in 0.7.0;
  the `"$unknown"` dispatch sentinel is gone; `DispatchStep` has two cases, not
  three; `counter_compute` / `counter_swap` are parameters of
  `counter_component(...)`, not functions; `Transactor::observe` returns an
  unsubscribe closure and its record carries five more fields;
  `ANode::collect_classes` fills a set rather than returning one; and
  `compile_margaui` takes an `ArrayView` plus `polyfills?` and **raises**.

- **Three lint codes and a suppression pragma that were never implemented.**
  `TOP_LEVEL_AT_RULE_IN_SCOPED_STYLE`, `GLOBAL_SELECTOR_IN_SCOPED_STYLE`,
  `DUPLICATE_ATTR_DEFINITION` and `/* tutuca-lint-ignore */` appear nowhere in
  `LintCode`. Each is now replaced by what actually happens, which is worse and
  worth knowing: nothing checks these, and the browser or the renderer drops the
  offending thing in silence.

- **`event`, `target` and `ctx` are not handler arguments.** A DOM object is not
  a `Value`, so each resolves to `Null` (`render/dom_event.mbt:55`) — the
  handler silently receives nothing. They were listed as built-ins, given a row
  in the `Msg` payload table, and testing.md's "bad example" was premised on
  digging through an event `Map` that never arrives. Relatedly: modifiers are
  guards on `keydown` and `click` only, not "all events", and the JS framework's
  `+prevent` / `+stop` have no counterpart here — they are ignored rather than
  refused, so a ported `@on.submit+prevent` silently loses its `preventDefault`.

- **`slots~` cannot rename a slot the schema already declares.** Verified
  empirically, not read: with `dnd: component` in the schema,
  `slots={ "dnd": "DnDExample" }` leaves the slot `Null`, because the schema
  field wins and a bare `component` carries no name to look up
  (`component/component.mbt:178`). The skill said the opposite in three places,
  and used it to justify a `gen-views` hint. Documented accurately; the
  underlying gap is not fixed here.

- **Two recipes that could not be run and one that could not compile.**
  `share-state-across-the-tree.md` and `edit-through-a-dynamic-target.md` showed
  machine-mangled MoonBit with `raw_view=...` placeholders and a
  `// ... — from the view file` comment standing in for the markup; both are now
  `.html` + `.mbt` pairs verified through `gen-views`, as are
  `render-a-child-component.md`, `tabbed-interface.md` and `paginate-a-list.md`
  (which showed the pre-schema `priv struct` + stray `init=` form). And
  `patterns/todo-list.md` had a genuine syntax error — a multi-line lambda
  without braces, plus a trailing comma after a match arm — found by the new
  check on its first run.

- **A bad `provide` expression is dropped silently** (`component/component.mbt:369`),
  not reported as a lint error; advanced.md said the latter. If a dynamic binding
  reads as its fallback everywhere, the producer's expression is the thing to
  suspect.

### Changed

- **The skill's own vocabulary stopped contradicting itself.** cli.md said "there
  is no run-time linter and no lint-code table" while six other files said "the
  linter flags…" — and `gen-views` does run the rules, printing
  `CODE (level) Comp/view: message` (`cli/gen_views.mbt:59-67`). What does not
  exist is a `tutuca lint` command to invoke them with, which is now what every
  one of those places says.

- **`SKILL.md`'s frontmatter names the artifact the skill is actually about.**
  It described "`#|` raw-string HTML views" — the older spelling — while the rest
  of the skill treats the `.html` view file plus `gen-views` as canonical, so a
  prompt about a `.html` view, a `<template>`, a `<script type="tutuca/spec">`,
  `tutuca watch`, `moon check`, a storybook example or the playground had nothing
  to match. Routing gained rows for schema.md and events.md.

- **Adding a storybook example has three metadata steps, all silent if skipped**
  (`patterns/add-an-example.md`): registering the module, mapping its name to a
  sidebar section (unlisted names land in "Other"), and giving it a title and
  description (unlisted, the title falls back to the raw registry name). None of
  this was written down anywhere.

- `core.md` is about the same length (1068 lines): ~170 lines of reference tables
  moved out to schema.md and events.md, and a comparable amount of new coverage
  moved in.

## [0.9.1] - 2026-07-29

### Fixed

- **`value`'s inferred payload type follows the host element.** The generated
  `<Comp>Msg` case for a `value` handler arg on `<input type="checkbox">` now
  carries `Bool` (the checked state the glue delivers) and on
  `<input type="file">` the metadata `@tutuca.Value` — previously both
  inferred `String`, so those dispatches could only ever land in `Unknown`.
  Only a static `type` attribute participates: a dynamic `:type` keeps the
  `String` default, and call sites that disagree still join to
  `@tutuca.Value`.

### Changed

- **The bundled skill is self-contained.** No more pointers at repo files
  (`storybook/examples/*.mbt`, the margaui repo's skill) — worked examples are
  inlined, since the skill ships in the CLI binary and the reader may have
  nothing else. New content driven by coding-agent feedback: the two bucket
  spellings are labeled everywhere (enum-match for generated wrappers vs
  string-keyed maps for raw `component()` calls) with examples leading with
  the enum form, core.md gained a generated-`Msg` payload-type table and the
  closed/view-driven bucket-enum rule, cli.md a `values` / `list<any>` worked
  example, margaui.md an inline starter class vocabulary, plus two new files:
  a complete todo-list pattern (`patterns/todo-list.md`) and a playground
  authoring guide (`playground.md`).

## [0.9.0] - 2026-07-29

### Added

- **The playground is packaged for npm.** `cmd/dev -- npm-pack` stages and packs
  two packages out of an assembled `dist/`:
  `@marianoguerra/tutuca-playground` (the shell — `<mb-playground>`, worker,
  editor, view generator, margaui; ~0.5 MB) and
  `@marianoguerra/tutuca-playground-payload` (`manifest.json` + `fs/`, the
  `.mi`/`.core` bundles user code compiles against; ~8.6 MB). Manifests and
  READMEs live in `playground/npm/`; both take their version from `moon.mod`.

  Two packages because they turn over for different reasons — the payload is
  rebuilt whenever the MoonBit toolchain moves, the shell is not — and they
  unpack into the same `playground/` + `site/` layout, so a consumer copying
  both into a static directory gets the arrangement everything resolves against
  by default. The in-browser compiler is not packed: it is upstream's
  `@moonbit/moonc-worker` build, published with no license field, so the payload
  names the exact version in `peerDependencies` and the playground is pointed at
  the consumer's own copy. `npm-pack` refuses a `dist/` assembled under a
  different toolchain than `playground/build/toolchain.json` pins, and packs
  only — publishing stays a deliberate manual step (see CONTRIBUTING.md).

- **`<mb-playground target="js">`** pins one element's backend, the way
  `?target=` does for the standalone playground, so a page about one backend can
  say so in the markup. Ignored when the payload has no such target.

### Changed

- **The playground shell stopped assuming it is the site.** Every URL it fetches
  — the worker, `moonc-web.cjs`, `manifest.json`, `fs/` — used to be written
  relative to the page (`./playground/compiler.worker.js`) or resolved by the
  worker against its own location. Both are now resolved once, absolutely, from
  the calling module's `import.meta.url` and handed to the worker in the init
  message (`playgroundConfig` + `makeCompiler` in `playground/web/runtime.js`),
  so the worker resolves nothing itself.

  That buys three things the old layout could not do. The folders relocate — a
  package directory, a subfolder, a CDN — with nothing to configure. A host can
  split them apart with `globalThis.MB_PLAYGROUND = { payloadBase, compilerUrl,
  workerUrl }`, which is what lets them serve their own installed
  `@moonbit/moonc-worker` instead of a copy of the 5.5 MB blob. And a worker on
  another origin now works at all: a `Worker` script must be same-origin, so a
  cross-origin one gets a same-origin blob shim that `importScripts` it — which
  is only safe because the worker no longer resolves anything against the blob's
  base URL, which points at nothing.

  A host-supplied compiler is checked against the payload it was built for:
  `manifest.json` carries `mooncWorker` (plus `mooncBuild` and `moon`, so the
  pin travels with the bundles), and the worker compares it against the
  `package.json` npm ships beside `moonc-web.cjs` when one is there. The payload
  and the compiler are one pair; a mismatch used to surface as `[E4018] … no
  impl is defined` against perfectly good user code, and now says so before
  fetching 5.5 MB. Versions are compared as semver identities, not strings —
  npm publishes the compiler with build metadata the registry and the pin both
  leave off (`0.1.202607282+5e7afb0c0`), and when it is there the build must
  match `manifest.mooncBuild` too. Either shell also stops labelling a failed
  compiler load "wasm instantiate failed", which hid exactly that message.

- **The standalone playground opens on wasm-gc, and `?target=` pins a backend.**
  A linked wasm-gc module is ~0.26 MB where the js one is ~1.1 MB of
  JavaScript, and it is what the landing page's embeds already run. `?target=js`
  or `?target=wasm-gc` wins over the default, so a link can pin the backend it
  is about; the toggle keeps the query parameter in step, so the URL in the
  address bar always reproduces what is on screen. A payload without wasm-gc
  (`JS_ONLY=1`) still opens on js, and — since the default now needs
  JS-String-Builtins — a mount that throws drops the page to js once and says
  why, the same fallback the embeds make.

- **The playground toolbar got a once-over.** One height and one shape for every
  control (the UA widgets agreed on neither, which is what made the row look
  ragged), a primary Run button, uppercase labels on both selects, and a status
  chip with a state-coloured dot at the far end. The chrome's colours moved into
  CSS custom properties, so dark mode is a token swap rather than a second copy
  of every rule that draws a line.

- **The landing page's embedded playgrounds compile to wasm-gc.** A linked
  wasm-gc module is ~0.26 MB where the js one is ~1.1 MB of JavaScript, which is
  the better trade on a page that mounts ten of them. Each embed falls back to
  js on its own if the payload carries no wasm-gc (a `JS_ONLY=1` build) or if
  the mount throws — what an engine without JS-String-Builtins looks like — so
  the toggle is still there and the page still works where wasm-gc doesn't. The
  standalone playground still opens on js.

  Two things had to work first. `mountWasm` did not compile the app's margaui
  classes, so a class-styled example would have rendered unstyled; it now reads
  them back through the exported `classes_json`, and the injected CSS is
  byte-identical to what the js mount produces. And the compiler worker — ONE
  worker for the whole page — held a single payload, so whichever `init()` ran
  last decided what every element compiled against. It keeps a payload per
  target now and picks one per compile from the request. That bug was reachable
  before this change too: toggling any single playground's target and back
  handed a wasm binary to the js mount (`Invalid or unexpected token`) or JS
  text to `WebAssembly.instantiate` (`expected magic word 00 61 73 6d`).

### Fixed

- **The playground's wasm-gc target runs.** It has compiled and linked user
  code for a while, but the linked module never validated: on wasm-gc a MoonBit
  `String` lowers either as a JS-String-Builtins `externref` or as MoonBit's
  native `(ref 1)` char array, the choice is made at link time for every core in
  the set at once, and the baked cores are built for the js-string ABI. Linking
  without asking for it mixed the two, and the browser rejected the bytes with
  `array.new_fixed[0] expected type externref, found local.get of type (ref 1)`.

  `linkCore` had no knob for this when the blocker was first written up; the
  pin moved to `@moonbit/moonc-worker@0.1.202607282`, which exposes one. The
  worker now passes `useJsBuiltinString: true` and `importedStringConstants:
  "_"` for wasm-gc, matching what `runtime.js` already instantiated with. The
  module's imports come out as `jscore`/`tdom`/`console` — the same surface the
  shipped `demo/counter_wasm` links to through the native `moonc`.

  That left a second fault of its own: the module instantiated, `mount()` ran,
  and nothing appeared. The wasm host reads the DOM as
  `@core.global_this()._get("document")`, and the `jscore` import handed back
  the shell page's `globalThis`, so the app looked for `#app` outside the
  preview iframe and logged that it was missing. `jsCoreImports` now takes the
  realm to answer with and `mountWasm` passes the iframe's window.

  All four picker examples now compile, render, route events through the
  exported `on_event`, and report state and activity through the exported
  getters on wasm-gc. `WASM_TARGET_STATUS.md` stops being a blocker report and
  describes the two couplings that keep the backend working.

## [0.8.1] - 2026-07-29

### Fixed

- **Every compiler warning is gone, on all three targets.** `moon check`
  reported 11 and `cmd/dev -- check` — which opts into
  `--warn-list +unnecessary_annotation` — reported 362 more.

  The 11: `to_repr(x)` as a *free* function is deprecated in favour of
  `Repr(x)` (the `impl Debug with fn to_repr` definitions are untouched — only
  the free form moved); `storybook/ui` reached `@string.parse_int` without
  importing `moonbitlang/core/string`; and three structs in the js smoke test
  still derived `ToJson`/`FromJson`, unread since the state codec replaced the
  Json bridge.

  The 362 were all `unnecessary_annotation` — `T::{ … }` where the position
  already has a type. 294 were in generated modules, so they are fixed in the
  **emitters** and the modules regenerated, never hand-edited: `<T>State::zero`,
  the state and user-record decoders, an init fixture's full-record form, and
  `StateDef::zero_expr` for enums, variants and records. A zero always lands
  somewhere its type is known, and MoonBit resolves a constructor against the
  expected type — two enums in one module both declaring `low` stay
  unambiguous. `ty_info_src` already wrote its constructors bare for a related
  reason; the two now say so as a pair.

### Changed

- **A field-less generated state derives `Default` and is built through it.**
  This is the one interface change in this release, and it is a workaround, not
  a preference: MoonBit has no warning-free literal for an empty struct. A bare
  `{  }` parses as an empty `Map` and fails to type, and `<T>State::{  }` — the
  only form that compiles — is then reported as an unnecessary annotation. So
  the struct derives `Default` and `zero()`/`decode` call
  `<T>State::default()`. Empty structs in hand-written code take the same route
  spelled `Default::default()`, because a `priv` struct's derived `default` is
  not implicitly promoted.

## [0.8.0] - 2026-07-29

### Added

- **An instance carries a fingerprint and a revision (`@tutuca.ObjId`), so a
  render cache has something cheap to key on.** `0.7.0` removed all render
  memoization; `benchmarks/OPTIMIZATIONS.md` #8 recorded that the render-site
  cache paid for itself where it hit (`toggle todo 1000` +58.9% without it) and
  was a net loss where it missed, because it built a per-site string key and
  then missed with it. The fingerprint replaces that string.

  `ObjId` is a **bucket, not an identity**, and it is deliberately not unique.
  Two instances created from the same arguments get the same origin; so do the
  same component loaded twice at runtime from two different bundles. That is
  what removes the need for a process-global counter, and with it the question
  of how two independently loaded components avoid clashing — they do not have
  to, because a bucket collision costs a miss and the cache checks physical
  identity on the value it stored before returning anything.

  It rides on machinery that already existed. `TypedInstance::make` is the only
  place a host instance comes into being — creation, an `update` handler and a
  field write all land there — and it already returns the ORIGINAL instance
  when nothing changed, so "the revision moved" means "the instance really
  changed" without a second rule being written. Guest instances get the same
  treatment through `DynObj::successor`, which already threaded a struct copy.

  Fingerprinting stays cheap through one rule: a nested `Obj` contributes its
  own origin and never its contents, so a parent costs a pass over its own
  fields rather than a walk of the subtree under it. `Bundle.comps` carries the
  manifest fingerprint hashed once at registration for the same reason.

  The id is absent from `member`, `eq`, `debug`, the schema and the
  JSON projection: a bucket is not state, and every DOM snapshot, inspector row
  and `gen-views` output is unchanged by this.

- **The component render-site cache, rebuilt on that key — updates are 27–57%
  faster.** `@render.RenderCache` keys a `Map[UInt64, _]` on the fingerprint, so
  nothing is built at lookup time, and it DECLINES for a value that has no one
  (a plain `Map` render site, a component-less `ViewMap` embedding) rather than
  keying and missing — the two things `benchmarks/OPTIMIZATIONS.md` #8 asked a
  reintroduced cache to fix. `App` holds one across passes and rolls a
  generation per render; `RenderCtx` carries it as `RenderCache?`, and `None`
  renders exactly as the uncached port did.

  A hit requires the revision, the render-site `node_id`, the resolved
  `(cid, vid)`, `physical_equal` on the stored value and on the dyn-binds
  chain. That is all a site reads: a component boundary is a bind barrier, so
  the enclosing `@each` binds cannot reach inside it, and position is never
  baked into a subtree (the dispatch path is reconstructed from the DOM at
  event time). Anything else is a miss that overwrites, so a bucket collision
  can cost time and never correctness.

  `RenderOnce` and the constant-attribute memo did NOT come back — they are the
  half that reached into the AST and made `viewgen` parse each view two ways.

  One row costs: `patch counter` is 3.0% slower, because a single component
  whose state changes on every click misses every pass and the lookup buys
  nothing. The old cache cost 9.8% there; the rest of it was `site_cache_key`
  building a string to miss with. Full numbers and the comparison against #8's
  table are entry #9.

## [0.7.0] - 2026-07-29

### Added

- **`gen-views` takes `[path…]`, and the checks that need two components come
  with it.** Paths are `.html` files or directories, following `watch`'s rule
  (a directory contributes the files that already have a generated sibling), so
  `tutuca gen-views src/` compiles a project in one invocation. Every file is
  split before any is emitted, which is what makes a reference to a component
  declared in ANOTHER file checkable:

  - **`<x render=".slot" as="edit">` where the child has no `edit` view.** At
    run time `resolve_view` returns None and the site renders *nothing* — the
    same silent blank that `.field` had before the schema could answer it.
    Reported as a hint rather than a failure, because `component()`'s `slots~`
    can point a declared slot at a different component than the schema names
    and the generator cannot see that.
  - **`.field` and `@value.member` inside a loop over child components.**
    `list<todo>` names the Todo component, so the body is checked against
    *that* schema instead of going opaque. A misspelt field is a build error
    naming the near miss, where before it was not even looked at.

  A component outside the paths passed is unknown, and unknown is not wrong —
  so a single-file invocation still works and simply checks less. `--name` and
  an `--out` ending in `.mbt` each name one thing, so both are refused for a
  batch. `agent-context`'s `schemaVersion` is 6.

- **A container in `@show` / `@hide` fails generation.** `Value::is_truthy`
  answers `true` for List, Map and Obj unconditionally, so `@show=".alts"`
  shows the element for an empty list too: it reads as a guard and is not one.
  The message names `empty? .alts` as the fix. `StateTy::is_boolish` existed,
  was tested, and was called by nothing; it now says what its own comment
  always said — a string, a number and an option are left alone, because
  `@show=".role"` beside `@text=".role"` is the idiomatic way to hide an empty
  badge.

- **A constant `id` inside an `@each` fails generation.** The loop stamps the
  body once per item, so the id is not unique the moment the sequence holds
  two. Only the compiled tree knows the element repeats, which is why no HTML
  linter reading the source can catch it.

### Performance

- **Constant attributes are evaluated once, not once per element per render.**
  `eval_attrs` rebuilt a `Map[String, AttrValue]` for every `ConstAttrs`
  element on every pass and `@vdom.h` copied it into a second map — two
  allocations per element per pass for attributes that cannot change. They are
  memoized now on a per-element key minted at load time (the same contract a
  `RenderOnce` id has), and `h` adopts an attribute map rather than copying it
  when there is nothing to strip out of it. The point is not the allocations:
  handing the differ the SAME map is what lets `diff_props` short-circuit on
  `physical_equal` instead of hashing every key in both directions, which
  `benchmarks/OPTIMIZATIONS.md` ranked first under "Not yet tried".

  `RenderOnce` does not already cover these — it needs the whole subtree
  constant, so `<div class="row"><x text=".name"></x></div>` misses it, and
  that is the shape of every list row. Native, release, against a saved
  baseline: `patch counter` −17.1%, `add+remove todo 10/100/1000`
  −17.6/−15.4/−14.6%, `toggle todo 10/100/1000` −10.9/−11.4/−5.6%,
  `switch view` −13.4%, `page people 1000` −11.9%, `refilter people 100`
  −11.9%.

### Removed (BREAKING)

- **All render caching.** Rendering memoized three ways and now memoizes
  nothing: the component render-site cache keyed on value identity
  (`@render.RenderCache`), the `RenderOnce` constant-subtree memo, and the
  constant-attribute memo added earlier in this same Unreleased section. Every
  pass rebuilds every subtree and every attribute map from the value tree, and
  `@vdom`'s differ is what keeps the DOM writes proportional to the change.

  This is deliberate and it costs time — `patch toggle todo 1000` +110%,
  `patch move json 8x4` +150%, `patch counter` +23% (wasm-gc; the full table
  and the per-cache attribution are entry #8 in `benchmarks/OPTIMIZATIONS.md`).
  The caches reached into the AST, the view pipeline and the render context,
  which is more structure than is worth holding still while the core design is
  moving. They are meant to come back, keyed on whatever it settles on.

  Removed from the public API:

  - `@render.RenderCache` and all its methods (`new`, `get`, `set`,
    `next_generation`, `stats`, `size`, `evict`, `clear`).
  - `@render.RenderCtx`'s `render_once`, `render_cache` and `const_attrs`
    fields, and the matching `RenderCtx::new` parameters — it is now
    `RenderCtx::new(view_resolver?)`.
  - `@anode.optimize_node`, the `ANode::RenderOnce` variant and
    `@anode.RenderOnceData`, `DomData::attrs_id`, and
    `ParseContext::new`'s `cache_const_nodes` parameter.

  A `match` over `@anode.ANode` that had a `RenderOnce` arm must drop it; one
  that was exhaustive without it is unaffected. `@anode.Attrs`'s
  `ConstAttrs`/`DynAttrs` split is NOT affected — that is a representation
  choice about re-evaluating `Val` expressions, independent of the memo.

  What did **not** change: the no-op-update short-circuit and everything that
  feeds it (`TypedInstance`'s memoized `Obj(self)`, `REUSE_FUEL`/`reuse_equal`,
  `with_field`/`with_item` returning the untouched container). That win comes
  from the transactor's root-identity check, not from any render cache —
  `patch noop todo 1000` is in fact 8.3% *faster* now.

## [0.6.0] - 2026-07-27

### Added

- **Every storybook story gets a live Instance tab.** Story | Instance beside
  each pane; the Instance pane renders the inspector's explorer over that
  story's own instance, with the Component tab beside its fields. It stays live
  because `i<N>` is rebuilt in the same successor that writes `s<N>` — a story
  dispatch rebuilds the spine through the shell's `with_member`, so the
  explorer tracks the story rather than showing the state as of the moment the
  tab was opened. Built when the tab is opened and dropped when it is closed:
  a gallery has ~50 stories and an explorer is a whole component tree.

  `Inspector::explore_value(v, comps?)` is the entry point — the registry is
  optional now that a value names its own fields.

- **A schema-driven state editor.** `@inspector.Inspector::edit_instance(v)`
  renders a form over any component instance: one row per DECLARED field, a
  control chosen from the field's kind (checkbox / number / text, with a
  collection or a child slot shown rather than edited), the WIT spelling as
  the type label, and an edit written back through the per-field mutator
  (`setTitle`, `setCount`, …) resolved by name off the instance. No part of it
  is written per component and none of it needs a downcast.

  It edits the instance it holds — a storybook knob or a fixture builder —
  rather than writing through to a mounted app, which would need the path the
  instance sits at.

- **The playground's Activity panel is the transactor's observer stream.** One
  line per handler invocation with its bucket, name, args, path and whether the
  leaf changed, newest first. It was a numbered list of state STRINGS, because
  a record could not be serialized: `before`/`after` are component instances.
  `ObserveRecord::to_json` exists now, along with `ObserveKind::label` /
  `ObserveMatch::label`, and the wasm host's `state_json` returns real JSON
  like the js one.

- **A component instance can describe itself.** `@tutuca.Obj` gains
  `schema()`, and with it the whole generic-access layer in `@tutuca`:
  `Value::field_opt` / `item` / `index` / `key` / `entries` / `size` /
  `field_names` / `field_info` / `snapshot` / `call` / `call_field`, the `_opt`
  coercers, total copy-on-write `with_field` / `with_item`, and the
  Path-addressed `at` / `at_opt` / `with_at` with fluent `Path::field` /
  `index` / `key` and a `Show` for `Path`.

  Holding a bare `Value`, you can now ask what fields it has, what type each
  one is, how long a sequence is and what its items are. Before, you could ask
  for a NAMED field and nothing else, and every consumer worked around that
  differently: the inspector took the field names from a `Components` registry
  or a hardcoded literal list, the dyncomp host parsed a
  `__dyncomp_state_json` pseudo-field, `state_json()` returned the `Show`
  rendering and said so in a comment.

  Concretely: the inspector opens a component instance into its fields instead
  of one line of `debug` text; `Value::to_json` projects a described
  instance instead of flattening it to null; `size_of` answers for a custom
  collection; `eq` and `debug` come off the schema rather than being
  hand-written per implementor (`DynObj` had never implemented `eq` at
  all, so two guest instances never compared equal).

### Fixed

- **`.seq[.key]` on a custom collection.** The seq-access evaluator spelled the
  container match out itself and its copy had lost the `Obj` arm, so a
  collection that `@each` iterated fine answered `Null` through seq-access. All
  four copies of that match are one lookup now.

- **The storybook's Instance tab rendered blank.** The explorer was built
  correctly and had no descriptor anyone could render it with: `<x render>`
  resolves an instance through the shared registry by component id, and the
  gallery registered the shell and each story's module but never the
  inspector's own components. `Inspector::components` is public so a host that
  renders an inspector view it built itself can register them.

- **A nested instance rendered as `Object`.** Only the inspector's ROOT row
  read the name off `v.schema()`; every level below it went through
  `classify`, which matched on `schema()` for the fields and dropped the
  name, so a component holding child components opened into `Object {1}`
  instead of `JsonBoolean {1}`.

### Changed (BREAKING)

- **`component()` takes `encode`, `decode` and `schema` off the state type, not
  as parameters.** They are the three methods of `@tutuca.Fields`, which the
  state type implements; `component()` is bounded on it and the three
  parameters are gone. `gen-views` writes the impl, so a component with a view
  file changes nothing at its call site — it just stops passing three
  arguments. A hand-written state writes three short methods instead, in a
  place that cannot drift from the type they describe. One consequence is
  deliberate: a schema now belongs to a TYPE, so two components sharing a state
  struct share its description.

- **`FieldKind`, `FieldInfo` and `SchemaInfo` moved to `@tutuca`.** They
  mention only `Value`, and living in `component/` put them out of reach of
  everything that has only a `Value` — which is what `schema` needed. They
  are re-exported, so `@component.SchemaInfo` still resolves; an enum
  CONSTRUCTOR does not travel through a re-export, so `@component.FBool`
  becomes `@tutuca.FBool` or bare `FBool` (the generator writes it bare).
  `SchemaInfo` also gains `name`, which `component()` fills in from its own
  `name~` when a hand-written descriptor leaves it unstated.

- **`instance_snapshot(v, comp)` takes the descriptor as an option**, and
  `instance_args(v, names)` drops its name list: both read the instance now.

- **`component()` requires `schema~`, `encode~` and `decode~`; `for_type()`
  requires `schema~`.** They were optional, and omitting them was the normal
  case — each omission had the runtime do the work instead. There is one
  component shape now, and no shape that specifies less. `gen-views` writes all
  three, so a component with a view file passes them through its generated
  wrapper and nothing changes at the call site; a component built by hand
  supplies them by hand, complete. `SchemaInfo::new` / `FieldInfo::new` default
  the channels a hand-written descriptor does not use.

- **The state struct needs no derives.** `component()` no longer bounds `S` on
  `ToJson + FromJson` — the generated codec does the conversion — so the
  generator stops emitting `derive(ToJson, FromJson)` and a state struct is a
  plain struct. A keyword field no longer needs
  `derive(ToJson(fields(type_(rename="type"))))` either: the codec keys by the
  runtime name.

- **The generated `<C>State` and `<c>_component` are `pub`.** They were
  package-private, which made a generated component unusable from another
  package or from a blackbox test — including the executable guides.

- **Handler buckets are keyed by generated enums, not strings.** `compute`,
  `swap`, `when`, `enrich`, `enrich_scope` and `loop_with` were
  `Map[String, closure]`; each is now a function from an enum generated out of
  the names the views use, so a `$name` or an `@when` added to a view makes the
  author's match non-exhaustive. A bucket the views never use is not a
  parameter at all. `swap` is keyed by the INPUT enum — it answers an Input
  dispatch ahead of `update`, not a `$name`.

- **`Component.schema` is no longer an Option**, and `compute_names`,
  `generated_names` and `has_update` are gone from `Component`.

- **`ObserveMatch::Unknown` is gone** with the `"$unknown"` catch-all it
  reported: dispatch does one lookup, so a miss is a miss.

### Performance

- **An ahead-of-time wasm bundle is 44.9% smaller.** `View::compile` branched
  on an `ir : Bool`, so every program that compiled a view named
  `ANode::parse` — and through it the vendored WHATWG HTML tokenizer — on the
  branch it did not take. A linker cannot prune a runtime `if`. The flag is
  the parse step itself now: only `View::new` names the parser, so a program
  built entirely ahead of time does not link one. `demo/counter_wasm`:
  438,803 → 241,941 bytes. No call site changed.

### Removed

- **The JSON state bridge and its stash.** `encode_state` / `decode_state`
  converted state through `S -> Json -> Value` for a component with no
  generated codec, and `core`'s `with_value_stash` existed solely to smuggle
  `Obj` and `Fn` across that trip as `{"\u{0}tutuca-ref\u{0}": i}` markers.
  Both are deleted, along with the process-global mutable and the "strictly
  synchronous" caveat it carried. It was measured at ~2x slower on encode and
  ~5x on decode; see `benchmarks/OPTIMIZATIONS.md`.

- **`FieldSpec::of_default`**, which read a field's kind off its seed value —
  why `FInt` vs `FFloat` depended on whether a double happened to be integral.

- **The reflected component description** (`summary_from_specs`). The inspector
  reads one source: what the component declares. Field rows show the author's
  WIT spelling rather than a label rebuilt from a runtime kind, and `update`
  lists the names it answers instead of the bare fact that it exists.

- **The `"$unknown"` handler sentinel**, a second string lookup on every
  dispatch miss.

### Added

- **A WIT `func` in the state block declares a `$`-callable.** A method a
  PARENT calls on a component — `contains-text: func(q: string) -> bool;`,
  asked by a list's `@when` of every child regardless of the child's shape —
  appears in no view of the component itself, so the schema is the only place
  it can be named. The parser used to reject `func` outright, on the grounds
  that behaviour lives in the MoonBit `update`; that is right about event
  handlers and wrong about a value a parent reads.

- **`gen-views` drift-checks its own output**, and `ci` runs it. A stale
  `*_view_gen.mbt` type-checks and tests green while no longer describing the
  `.html` beside it, and nothing caught that before.

- **Direct codecs for every schema-backed component**, `record` / `enum` /
  `variant` / `option` / `tuple` included, and for a state with no carried
  fields at all. Previously 79 of 93 components had one and the rest fell back
  to the JSON bridge.

- **A component's state can be declared in the view file, in a subset of WIT,
  and is then generated.** A `<script type="tutuca/spec">` block holds one
  `interface` per component and one `record state` in each; `gen-views` emits
  the struct, a `zero()`, a `Field` table whose `kind()` is *declared*, the
  state <-> Value codec, and the `specs~` map. Sets, ordered maps and
  child slots — the three kinds a struct could never express, and which had to
  be threaded by hand through `specs~` and `missing_fields(extra~)` — are now
  written in the schema and derived from it.

  It rides in a `<script>` and not a `<template>` because script content is raw
  text to an HTML parser while template content is markup: `list<s32>` inside a
  template parses as an `<s32>` element.

  Parsed with `mizchi/wit`. WIT rather than a bespoke DSL because tutuca
  already speaks it at the dyncomp boundary and because its type lattice maps
  almost exactly onto `FieldKind`. What WIT genuinely cannot spell — an open
  type, an ordered map (WIT's own `map` is unordered by definition), a child
  component — arrives as a marker name (`any`, `text-set`, `value-omap`, or a
  sibling interface's name).
- **Named initial states**, in a `<script type="tutuca/init">` block of their
  own, because a default is a value and not a type. Each is checked against the
  schema at generation time — a fixture setting a field the schema dropped, or
  writing `2.5` into an `s32`, fails the build instead of being coerced away at
  runtime — and becomes `State::fresh()` plus a public `<v>_init_args("fresh")`
  for a `ModuleDef` example.
- **Typed `Receive` / `Bubble` / `Response` buckets.** These names are raised
  from MoonBit rather than written in a view, so the views could never type
  them; the schema can. Each declared bucket gets an enum, a bucket-scoped
  `from_dispatch`, and a `to_dispatch` plus sender, so a message name is
  written once instead of twice as a matching pair of string literals. An
  integer payload is integrality- and range-checked rather than truncated.
- **Direct state <-> Value codecs, generated from the schema.** The runtime
  bridged typed state to the Value world through `Json` — `S -> Json -> Value`
  and back, once per state write, inside `with_value_stash` because `Obj` and
  `Fn` cannot survive JSON at all. With the schema in hand the conversion is
  written field by field, and a field that already holds a `Value` is passed
  straight through instead of being rescued from a round trip it never needed
  to take. `component()` takes them as `encode~`/`decode~`; a component with no
  schema still uses the JSON bridge. Adopted only after measuring, because it
  is a second encoder to keep in step with the derived one: **encode ~2x,
  decode ~5x** in isolation (`benchmarks/codec_bench_test.mbt`), and an
  interleaved A/B on the render path puts `patch counter` at 19.0/19.5 µs
  against 20.3 µs — a few percent, which is what a bridge that is not the
  bottleneck should look like.
- **The generator exports a static description, and the inspector reads it.**
  `gen-views` emits `<v>_schema()`, a `@component.SchemaInfo` carrying the
  field types with their element types and a `flags` set's members, the `@on`
  names the views raise, the declared message buckets, the constant element
  ids, the view names and the named fixtures. A component passes it as
  `schema~`.

  The headline is `update`. At runtime it is one opaque pattern match, so
  introspection could only ever report THAT an update exists — the component
  inspector literally rendered `["update"]`. The schema knows every name it
  answers, and the panel now lists them. Receive / Bubble / Response appear at
  all for the first time: those names are raised from MoonBit, never written
  in a view, so nothing at runtime could recover them.

  Passing `schema~` also stops `component()` inferring field kinds from the
  encoded init value — the guess that made `FInt` vs `FFloat` depend on
  whether a seed double happened to be integral. Two sources of truth for the
  same fact is worse than either alone, so the declared kind simply wins. A
  component with no schema keeps the reflection path unchanged, which is what
  every unmigrated one still uses.

  This supersedes the generated `<v>_specs()` helper, which was emitted but
  never passed by anything — the runtime was guessing kinds it had already
  been told. Removed. Net cost to a generated module: ~700 bytes.

- **Schema-only view files.** A file may carry a `tutuca/spec` block and no
  `<template>`, which is how a component whose views are built in MoonBit
  still gets a generated state type — the schema lives in a view file, so it
  needs one even with no views. One file may also mix the two: templates for
  some components, state alone for others. An interface with no template is
  reported as a hint rather than an error, because it is also what a mistyped
  interface name looks like.
- **`gen-views --wit`** writes the schema back out as a self-contained `.wit`
  document for `wit-bindgen`, with the markers lowered; `<v>_schema_fingerprint`
  is its structural identity, over shape rather than over source text.

### Fixed

- **The benchmark view corpora had become unparseable, and nothing noticed.**
  `moon test` does not execute a `bench` body, so a corpus that no longer
  splits fails only under `moon bench`. Once view files started carrying
  schema blocks, `all_views` — every view file concatenated into one —
  collected 36 of them, which `split_file` rightly refuses; and a
  `<template>` written inside a schema *comment* was taken for an opening
  tag, unbalancing `one_big_view`. The corpus builder now strips schema
  blocks before anything scans for tags, and a plain test asserts both
  corpora split.

- **`@push-view` and `@enrich-with` were treated as opening a new state
  scope.** `@push-view` pushes a view NAME onto the render stack
  (`render/render.mbt`, `push_view_name`) and `@enrich-with` pushes binds;
  neither changes what `.field` addresses. Found by the new view checker while
  migrating `storybook/examples/rendering`.
- **The embedded Tailwind stylesheets were a minor version behind the compiler
  reading them.** `theme.css` / `preflight.css` came from margaui's `tw/`
  directory, which margaui's own README calls a manual mirror — at v0.5606.3 it
  was still missing the `mauve`, `olive`, `mist` and `taupe` palettes upstream
  added in **4.3.2**, on top of 4.3.3's `--font-sans` change and the
  `oklch(… 0 none)` achromatic form for `zinc-50` and `neutral-50…950` (at
  v0.5704.0 the palettes and the font stack are still behind).
  Meanwhile `marianoguerra/tailwindcss` is ported from **v4.3.3** exactly. The
  `css-bundle` task now takes those three files from the `tailwindcss` npm
  tarball pinned to the port's own `UPSTREAM.md` tag, and
  `scripts/fetch-tailwind.mjs` fails the build if the two pins drift apart;
  margaui's copies are dropped from its bundle (`--skip-prefix tw/`) and its
  `./tw/*` imports resolve against the good ones. The wasm demos gain the four
  palettes and a different default `--font-sans` stack.

### Changed

- **The `mutate` bucket is removed (breaking).** With `$` refused at an `@on`
  site, `mutate` had no job left that `update` does not do: both are reached
  by the same bare name and the same dispatch, `update` is strictly more
  capable (it gets a `ctx`), and nothing internal used the bucket — the
  generated setters live in their own table. Its one remaining claim was
  purity-by-signature, which is not worth a second place for a handler to
  live.

  `component()` loses the `mutate~` parameter, `TypedSpec` loses the field
  and its three dispatch reads, and `gen-views` stops emitting the
  `<v>_mutate` builder. All 41 call sites across 24 files are migrated by
  hand: 21 were a rename, 8 genuinely transformed (an untyped `Array[Value]`
  becomes the typed payload of a `<C>Msg` variant), and the shared inspector
  paging bucket became a `composite_update` helper that a component's own
  `update` delegates to from its fallback arm.

  `compute` and `swap` stay. `compute` answers a `$name` in a VALUE position
  (`@text="$label"`), where there is no event and no ctx and an `update` arm
  cannot reach; `swap` returns a `Value`, so it can replace a node with a
  different component's instance, which `update` — returning `S?` — cannot.

- **A `$name` in an `@on` handler position is now a generation error.** It
  was never a second mechanism: `app/app.mbt` collapses `HandlerName` and
  `Method` into one string and hands both to `push_input`, so `@on.click="$inc"`
  and `@on.click="inc"` are the *same dispatch* — verified for user buckets
  and for the generated mutators, which answer to either spelling. The sigil
  therefore claimed a distinction that does not exist, and readers reasonably
  inferred one. `$` keeps its meaning where it has one: a value position
  (`@text="$label"`, `@show="$canSubmit"`), where there is no event and no
  `ctx` and an input handler cannot go.

  All 338 call sites across 33 view files are rewritten to bare names. A name
  that moves from `$` to bare moves from `<C>Method` into `<C>Msg`, so six
  `update` matches gained a fall-through arm returning `None` — which is how
  a handler served by a generated mutator was always meant to read.

- **Views are now type-checked against the state schema (breaking for any
  component that adopts one).** An unknown `.field` is a generation failure
  naming the near miss, where it used to render as `null` in the browser. The
  check reaches **inside `@each` bodies** — with the element type in hand,
  `@value.titel` in a loop is caught, where before it was not merely unchecked
  but not even looked at. Also checked: `@each` over a non-collection, and
  `<x render>` on something that is not a component. Unknown is never wrong — a
  `$method` result, an `any` field and a child component's fields all open an
  opaque scope that silences the checks inside it.
- **`<v>_fields` / `<v>_missing_fields` are no longer emitted for a
  schema-backed component.** They existed because the generator could not check
  a read: they listed the names and left you to assert, in a test you had to
  remember to write, that the state carried them — and they only ever covered a
  view's root scope. A component with no schema block still gets them, and
  generates exactly what it generated before.
- **Every example with a view file now declares its schema**: all 26 view files
  across `demo/` and `storybook/examples`, 70 components in total. The five
  example files that build their views at runtime (`macros`, `visual_wasm`,
  `lint_errors`, `svg_more`, `todo_macros`) have no view file to hold a block
  and keep their hand-written structs — the schema lives in the view file, so a
  component without one has no schema.
- **margaui bumped to v0.5704.0** (from v0.5606.3). `MARGAUI_REF` in
  `scripts/fetch-margaui.mjs` moves and `css/margaui_bundle_gen.mbt` +
  `css/assets/margaui.bundle.json` are regenerated from that tag — same 80
  files, no utility renamed or removed, so no view needs changing. New:
  `menu-paged`, a menu whose open submenu replaces the panel instead of
  expanding in place, with its `summary` turning into a "Back" row
  (`aria-label` overrides the label). Fixes across `avatar` (centred
  `align-self`), `calendar` (hover no longer washes out today/selected),
  `fieldset`, `indicator` (start/end offsets default to `auto`), `input`
  (LTR fields align by `text-align`, pixel-exact affix insets), `kbd` and
  `radial-progress` (`flex-shrink: 0`), `menu` (`[disabled]` styled like
  `menu-disabled`), `modal` (child-scoped `.modal-box`, RTL slide), `otp`
  (forced LTR), `select` (subtle placeholder colour no longer leaks to a
  wrapper's other children), and `tab` (indicator width from `--tab-p`).
  `loading` and `progress` now treat reduced motion as the default and put
  the fast animation behind `prefers-reduced-motion: no-preference`. margaui's
  own `tw/*.css` is still skipped — the stock Tailwind stylesheets keep coming
  from the pinned npm tarball.
- **A no-op interaction no longer re-renders.** Writing a component field the
  value it already holds now keeps the instance — and so the root — as the
  SAME object, so the transactor reports no swap and `App::render_now` is
  never reached. Getting there meant preserving identity at three seams that
  were throwing it away on every update: an instance now memoizes its `Value`
  (each `Obj(self)` cast used to allocate a fresh one); `with_state` keeps the
  old object for every encoded field equal to the one it replaces, instead of
  taking whatever the `Json` round trip rebuilt; and `TypedInstance::set`,
  `Value::with_field`/`with_item` and the transactor's root check all
  short-circuit an unchanged write. `patch noop todo 1000` went 8.33 ms → 19.5
  µs (−99.8%); `toggle`, `add+remove`, `move` and the render path are
  unchanged within noise. See `benchmarks/OPTIMIZATIONS.md` #6.
- **The CLI does only what the compiler cannot.** tutuca-mb compiles ahead of
  time, so mimicking the JS CLI's dynamic module inspection was answering
  questions later and more weakly than the build already answers them. The
  module commands (`get`, `list`, `examples`, `show`, `lint`, `render`),
  `plan_with_module`, the component linter behind `lint`, and the
  `demo/counter_cli` embedding demo are all removed — as is the idea that a
  project embeds the CLI. What ships is `gen-views`, `watch`, `storybook`,
  `install-skill`, `feedback`, `agent-context` and `help`: the jobs that
  genuinely happen outside the compiler. View checking runs at GENERATION
  time (a view that would emit a parse issue fails `gen-views`), and
  everything the linter used to report about fields and handlers is a type
  error in the generated view module.
- `agent-context` is `schemaVersion` 5: one command set, no `mode`, no
  `lintCodes`, no `formats`, no per-command `needsModule` / `needsEnv` /
  `defaultFormat`. Its `invocation.note` says where the checks went, so an
  agent reading the schema does not go looking for a `lint` command.
- Global flags are `--json` and `--help`. `--format`, `--output` and
  `--pretty` existed to shape module-command output and are gone with it;
  `--json` now only switches the error envelope. Exit codes are 0 and 1 —
  2 (lint findings) and 3 (render crash) went with their commands.
- The storybook's per-story Lint panel and the inspector's Lint view are
  removed along with the linter that fed them.
- `tutuca storybook` is a static file server and nothing else: `--dry-run` and
  the accepted-but-ignored `--no-margaui` / `--no-check` / `--no-tests` are
  gone. With them went the runtime `cli` → `storybook` dependency, so the
  storybook packages are now excluded from the published archive and stay in
  the repo as demos and as the corpus the view-generation sweep runs over.
- `README.md` is a short repository README rather than a symlink to
  `README.mbt.md`; the detailed guide remains the executable `README.mbt.md`.
- One parameterized guest builder (`guests/build-guest.mjs <name>`) replaces
  the duplicated `guests/{counter,todo}/build.mjs`, and
  `dyncomp/wit/tutuca-component.wit` is the sole WIT: the per-guest copies are
  gone and every guest (including the Rust one) reads that file.

### Added

- **`tutuca gen-tailwind-css` and `tutuca gen-margaui-css`** — build-time CSS
  from a project's views. tutuca already knows which classes a view uses; these
  run that same collection over the view *files* and compile the result, so an
  ahead-of-time project can ship a static stylesheet holding exactly the
  utilities it uses, with no Node, no CDN and no margaui checkout. Paths follow
  `watch`'s rule (a directory contributes the `.html` files that already have a
  generated sibling), defaulting to the current directory. `gen-margaui-css`
  output is a superset of `gen-tailwind-css` for the same views. Flags:
  `-o/--out`, `--entry` (compile your own CSS entry, resolving its `@import`s
  from disk), `--polyfills`, and — for the literal-only limit the runtime
  collector also has — `--print-classes` to see what was collected and
  `--classes <file>` to add back the names a view assembles at run time.
- `tutuca watch --tailwind-css <file>` / `--margaui-css <file>` — keep a
  stylesheet current alongside the view modules, so the authoring loop is one
  process again. Rebuilt over every watched view once per settled batch (a
  stylesheet is a whole-project artifact, and compiling is the expensive half),
  and `WatchPlan` carries a whole `CssPlan` so watch runs the very same
  collect/compile/write path the one-shot commands do. `--css-entry` and
  `--css-classes` forward to their `--entry` / `--classes`.
- `css/` — a published, target-agnostic package holding the stylesheet bundles
  and `compile_tailwind` / `compile_margaui`. It replaces `demo/margaui`, which
  was wasm-gc-only and excluded from the published archive; the wasm demo hosts
  and the playground now compile through it, as does the CLI.
- `cmd/dev -- gen-guest-bindings`: regenerate both MoonBit guest binding trees
  from the canonical WIT and drift-check them. `wit-bindgen` emits its FFI
  shims in hash order, so `guests/gen-bindings.mjs` normalizes the output —
  which is what makes the checked-in trees reproducible at all.
- `@render.RenderCache::stats` / `::size`: read the hit/miss counters and entry
  counts without clearing the cache, which `evict` cannot do.
- `@tutuca.same_node`: physical identity across the `&PathNode` trait-object
  boxing, which a plain `physical_equal` defeats.

### Removed

- A large amount of public API that nothing outside its own package used:
  `@cli`'s command-dispatch internals (`run_help`, `run_storybook`,
  `render_error`, `did_you_mean`, the command tables …), `@anode`'s AST
  mutators and macro internals, `@core`'s `Pred` accessors and `step_put`,
  `@transactor`'s `Completion` API, `@vdom`'s `morph_node`/`morph_children`
  and namespace URIs, `@viewgen`'s naming helpers, `@inspector`'s per-view
  methods, and `@component`'s `FieldSpec` constructors. The stable CLI error
  codes and `warn_hook` stay public — they are documented extension points.
  `@core.Val::render`, `@core.Value::entries` and `@core.parse_handler_arg`
  were dead and are deleted outright.
- `@cli.plan_with_module`, `@cli.check_component` and the whole component
  linter (`LintFinding`, `LintRule`, the rule/style tables), `@cli.stub` and
  `CmdImpl`, `CliMode`, and `@inspector`'s lint report components. `GlobalOpts`
  is down to `json` and `help`.

## [0.5.3]

### Added

- `benchmarks/` — three benchmark suites, all target-agnostic (the view corpora
  are embedded as strings and `@memdom` runs everywhere, so they need neither a
  filesystem nor a browser): the **view pipeline** over every view `.html` in
  the repo, both as one file of 108 views and as one enormous view, plus a
  1×/2×/4× probe for costs that are superlinear in a single view's size; the
  **render path** over all 50 usable example modules and over lists of 0 to
  1000 items in four shapes; and **diff/patch**, where each workload is a change
  and the change back applied to an app mounted once, from a no-op through a
  one-row edit to switching views. `benchmarks/report.mjs` collapses `moon
  bench`'s output to one line per benchmark and takes `--save` / `--baseline`
  for A/B runs; `cmd/dev -- bench` and `-- bench-views` drive it, and
  `benchmarks/OPTIMIZATIONS.md` is the log. Repo-only, excluded from
  `moon package`.
- `@viewgen.emit_ir_module_opt`: the companion IR module, or None when the file
  cannot be emitted as compiled trees — `ir_supported` and `emit_ir_module` in
  one pass. `ir_supported` stays for callers that only want the answer.
- `@anode` builders for the AST: `h`, `text`, `dyn_text`, `frag`, `attr` /
  `attr_num` / `dyn_attr` / `if_attr` / `eid`, `show` / `hide` / `each` /
  `render` / `scope`, `on`, and the `const_*` value shorthands. They are the
  parser's own output with the rarely-set fields defaulted — hyperscript-shaped
  constructors, not a new representation — so a hand-written view or test can
  build a tree the renderer cannot tell from a parsed one. `@anode.h` chooses
  ConstAttrs vs DynAttrs through `attrs_of_items`, the rule the attribute
  parser now also calls, so the two paths cannot disagree.

### Changed

- Performance, all measured on `benchmarks/` and all leaving output
  byte-identical (the generated `*_view_gen.mbt` files still regenerate
  unchanged, and the DOM snapshots in the test suite are untouched):
  - `tutuca gen-views` is 16–18% faster. `if ir_supported(file) {
    emit_ir_module(...) }` compiled every view twice, since both halves go
    through the same parse; with `emit_module`'s own pass that made three
    compiles of every view per job. `emit_ir_module_opt` does the check by
    emitting.
  - `@viewgen`'s `split` stage is 6% faster and no longer superlinear in a view
    file's size: recovering a view's source walked its span one character at a
    time and rescanned the whole style-region array at each one. It now copies
    the runs between the regions.
  - Rendering is up to 21% faster and updating up to 34%. Every render site and
    every `@each` iteration emits a `§{…}§` boundary comment, and building it
    meant allocating a `Json` object and stringifying it — ~2000 of them per
    pass for a 1000-row list. Those, and the render cache's per-slot key, are
    now written straight into a `StringBuilder`.
- `@harness.Harness::find` stops at the match it asks for instead of collecting
  every match in the DOM and indexing one. Same semantics; on a long list it is
  the difference between a full-tree walk and a few nodes, which is worth 30–78%
  on the update benchmarks and shows up in any test that drives a large DOM.
- `gen-views` emits the compiled tree with those builders instead of raw
  struct literals: the 26 checked-in `*_view_ir_gen.mbt` files went from 6530
  to 3121 lines, and a `<button class="x">-</button>` from seven lines to one.
  Three things it used to write are now recovered at load: the `NodeEvents`
  ids (an id is the entry's position, so the table is a plain
  `[[on(…)], …]`), the `data-vid` stamp (`View::from_ir` applies it anyway),
  and the ConstAttrs/DynAttrs choice.
- `@anode.View::from_ir` takes the handler table
  (`Array[Array[NodeEvent]]`) instead of a `ParseContext`, and builds the
  context itself — the caller no longer names `root` twice or constructs a
  parse context to hand straight back.
- The generated `XMsg::of_dispatch` is now `XMsg::from_dispatch`, matching the
  `from_*` prefix the rest of the codebase and MoonBit core use for named
  source conversions (`View::from_ir`, `Value::from_json`). The suffix stays:
  it names the source type, which is the only place a reader of an `update`
  closure learns that `msg` is a `@component.Dispatch`.
- `@viewgen.compiled_views` is now `@viewgen.build_views`. The old name
  predates 0.5.0, when the component argument was `compiled_views~`; with
  views always being `@anode.View` values there is no compiled-vs-uncompiled
  distinction left to name.
- The `gen-views` task runs `moon fmt` after generating. The CLI emits
  unformatted source, so `gen-views` followed by `git diff --exit-code` — the
  drift check the docs describe — always reported churn before this.
- `marianoguerra/tailwindcss` is now 0.2.0 (was 0.1.3). The two APIs tutuca
  uses are unchanged (`compile_sync` for `demo/margaui`, `collect_imports` for
  `cmd/margaui-bundle`): the compiled margaui CSS and the regenerated
  `demo/assets/margaui.bundle.json` are byte-identical to 0.1.3's.
- The `margaui-bundle` task no longer needs a sibling `../margaui` working
  copy. `scripts/fetch-margaui.mjs` clones margaui from GitHub at a pinned tag
  into the gitignored `_build/margaui`, which is also the tool's new default
  `--base`. The pin is what makes the committed bundle reproducible — anyone
  can now regenerate it and get the same bytes; before, the result depended on
  whatever state the local checkout happened to be in. Bump `MARGAUI_REF` to
  pick up new margaui CSS.

### Fixed

- Every GitHub link on the landing site pointed at `marianoguerra/tutuca`,
  the upstream JS framework, rather than at this port
  (`marianoguerra/tutuca-moonbit`). "What's Next" now links both, and the
  nav / hero / footer link the port.
- The example library's last runtime-built static views (counter,
  personal_site, filter_paginate) are compiled ahead of time. What still
  builds views at runtime does so because it cannot be generated: dyncomp
  guest bundles, macro-using and programmatically-assembled views,
  deliberately-broken lint fixtures, the playground's editable examples, and
  test fixtures.
- Documentation that still described the pre-0.4 view arguments
  (`view~` / `style~` / `view_styles`), the pre-typed-state component API,
  removed generated constants, renamed demo packages, and moved example
  paths.

## [0.5.0]

### Changed — `compiled_views~` renamed to `views~` (breaking)

Now that it is the only view argument, the `compiled_` qualifier was
redundant: `component(...)` and `Component::for_type(...)` take `views~ :
Map[String, @anode.View]`. `tutuca gen-views` emits the builder as
`counter_views()` (was `counter_compiled_views()`), so a component reads
`views=counter_views()`.

The generated types module no longer emits the dead source-string constants
(`counter_main_view`, `counter_views()` returning `Map[String, String]`,
`counter_style`, `counter_view_styles()`) — they existed only for the removed
`view~` / `views~` / `style~` arguments. `counter_common_style` /
`counter_global_style` stay (they back `common_style~` / `global_style~`), and
each view's own style rides inside its `@anode.View`.

## [0.4.0]

### Changed — views are `@anode.View` values, not strings (breaking)

`component(...)` and `Component::for_type(...)` no longer take `view~` /
`views~` / `style~` / `view_styles~`. The view input is now
`compiled_views~ : Map[String, @anode.View]` — a view is a built `@anode.View`,
keyed by name (`"main"` renders by default), each carrying its own per-view
style. Component-level `common_style` / `global_style` stay.

Build the map either way:

- **Ahead of time** (recommended) — `tutuca gen-views counter.html` emits
  `counter_compiled_views()`; pass `compiled_views=counter_compiled_views()`.
- **At runtime** — `@anode.View::new("main", raw_view="…", style~)` for a
  genuinely dynamic view (e.g. the dyncomp guest bundle) or a test fixture.
  This is the same primitive the generated code sits on.

Migration: replace `view="…"` with
`compiled_views={ "main": @anode.View::new("main", raw_view="…") }`, and add
each `views` entry / `style` the same way; or move the views into an `.html`
file and generate the map. The whole repo (examples, docs, inspector, demos)
moved over; the demo shows the gen-views path end to end.

### `tutuca watch`, HTML macros, multi-component files

Also in this release (were staged as 0.3.1): `tutuca watch` regenerates view
modules on save; macros are declared in the view file
(`<template id="macro:…">`) and expanded at generation time; one view file
names several components with `id="Counter:main"`; the structural-HTML and
parse-issue lint rules run at generation time; the lint package renders its
own findings.

## [0.3.1]

### Added — ahead-of-time view compilation (`tutuca gen-views`)

An optional AOT step: an `.html` file of views compiles into a companion
MoonBit module of typed view surfaces, so a view's vocabulary stops being
strings the compiler cannot see. This is **additive** — `component(view~)`
still works unchanged; a component opts in by passing `compiled_views~`.

- `tutuca gen-views <file.html>` emits two modules: the types
  (`CounterInput` / `CounterMsg` with `of_dispatch`, whose payload types are
  inferred from the `@on` call sites; `CounterMethod` bucket builders;
  `CounterView` / `CounterId`; the field list) and the already-compiled
  `@anode` tree (`counter_compiled_views()`), which lets `compiled_views~`
  skip template parsing at startup. Adding an `@on` handler to the view and
  regenerating turns the component's `update` match non-exhaustive — a
  compile error where the string-matched `_ => None` arm used to do nothing.
- One view file per module, naming several components with
  `id="Counter:main"`. Macros are declared in the file
  (`<template id="macro:icon">`) and expanded at generation time, so a macro
  view compiles to a tree too.
- `tutuca watch [path…]` regenerates managed view files on every save
  (mizchi/fswatch).
- The structural-HTML and parse-issue lint rules now also run at generation
  time, and the lint package renders its own findings (message rendering
  moved from `cli`).
- The in-browser playground gains a View tab that generates the module the
  Component tab imports, live.

### Changed — typed-state components (breaking)

The dynamic component API was replaced by a typed-state model (inspired by
[rabbita](https://github.com/moonbit-community/rabbita)'s TEA shape):

- State is a plain struct with `derive(ToJson, FromJson)`; `component(...)`
  takes `init~` instead of `fields=` and every handler is compiler-checked
  against the struct. `Instance`, `InstanceHandler` and `MethodFn` are gone;
  `Component::make` returns the instance as a `@tutuca.Value`.
- The four effectful buckets (`input`/`receive`/`bubble`/`response`) fold
  into ONE `update : (S, Dispatch, &Ctx) -> S?` pattern match over the new
  `Dispatch` enum. `methods` splits into `mutate` (pure state changes,
  `$name`) and `compute` (value reads, `$label`).
- `alter` splits into four typed render-time buckets matching the directive
  call conventions: `when : (S, key, value, iter) -> Bool`,
  `enrich : (S, binds, key, value, iter) -> Unit`,
  `enrich_scope : (S) -> Map[String, Value]`, and
  `loop_with : (S, seq, LoopCtx) -> LoopWith`.
- Child-component slots and Set/OMap kinds are declared via `specs=`
  (`FieldSpec::comp` / `::set` / `::omap`); fields of type `@tutuca.Value`
  (or collections of it) carry instances/functions losslessly through state
  updates via a core value stash (`with_value_stash` + `ToJson`/`FromJson`
  impls for `Value`).
- Core gains coercing accessors on `Value`: `int` / `num` / `str` / `bool` /
  `list` / `entries` / `field`.
- The inspector's component summary now reports the typed buckets (fields /
  methods / update flag / alter / views).

## [0.1.0]

Initial public release: a MoonBit port of the
[tutuca](https://github.com/marianoguerra/tutuca) UI framework.

- Value language (parse / tokenize / eval) and reactive path/dispatch system.
- `anode` template parser, `render` layer, `component`/`app`/`transactor`
  runtime.
- Virtual DOM (`vdom`) with in-memory, js (real DOM), and wasm-gc backends.
- `lint` (parse-issue rules + structural HTML linter) and `inspector`.
- Native `tutuca` CLI (`get` / `list` / `examples` / `show` / `lint` /
  `render` / `storybook` / `install-skill`).
- 32 ported examples, browser/CLI/wasm demos, an in-browser playground, and a
  compiled storybook gallery.

[Unreleased]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.47.1...HEAD
[0.47.1]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.47.0...v0.47.1
[0.47.0]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.46.0...v0.47.0
[0.46.0]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.45.0...v0.46.0
[0.45.0]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.44.0...v0.45.0
[0.44.0]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.43.0...v0.44.0
[0.43.0]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.42.0...v0.43.0
[0.42.0]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.41.5...v0.42.0
[0.40.0]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.39.2...v0.40.0
[0.39.2]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.39.1...v0.39.2
[0.39.1]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.39.0...v0.39.1
[0.39.0]: https://github.com/marianoguerra/tutuca-moonbit/compare/v0.38.0...v0.39.0
[0.1.0]: https://github.com/marianoguerra/tutuca-moonbit/releases/tag/v0.1.0
