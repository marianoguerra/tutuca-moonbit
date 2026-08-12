# A wax superset for tutuca state

Replacing the WIT subset in `statedef/` with a language that maps to wasm-gc,
adds sum types, infers recursion groups, and can emit the reflective layer as
wasm-gc rather than MoonBit source.

Companion to [`generative-dyncomps-in-the-browser-design.md`](generative-dyncomps-in-the-browser-design.md),
which covers compiling a dyncomp client-side. That design is about *how a bundle
is built*; this one is about *how state is declared*. They are independent —
either can ship without the other — but §7 notes where they meet.

## Context

`statedef/` parses a WIT subset out of `<script type="tutuca/state">
` blocks and
hands `viewgen` a typed `StateDef`. WIT costs three things:
- **No recursive types.** `statedef/from_wit.mbt`'s `check_acyclic` rejects
  `next: node`, `tuple<s32, node>`, `variant node { branch(node) }` and mutual
  `a↔b`. Only `list<node>` and `option<node>` pass, because heap indirection
  stops the walk. This is not pedantry: without it, `zero_expr` expands
  `{ field: zero, … }` forever and "ran the emitters off the end of the stack —
  a segfault with no message".
- **No spans.** mizchi/wit's AST carries no per-declaration positions, so
  `DefError::locus()` exists and `viewgen/split.mbt:487-560` scans the block for
  an identifier as a whole word to guess which line to blame.
- **No per-field docs.** `@wit.Field` has no `docs`, so `FieldDef.doc` and
  `MsgDef.doc` are **always `None`**. This is why
  `dyncomp/registry/descriptor.mbt` keeps `field_docs` separate from the schema:
  a guest has per-field docs, a host component cannot.
The migration is cheaper than it looks. **`@wit` appears in exactly one file** —
`from_wit.mbt`, 492 of statedef's 2457 lines. `pkg.generated.mbti` mentions no
WIT type. The whole contract is:
```moonbit
parse_state(String) -> Array[StateDef] raise DefError
```
`StateDef` / `FieldDef` / `MsgDef` / `StateTy`, the three emitters
(`moonbit_ty`, `zero_expr`, `ty_info_src`), `fingerprint`, `names.mbt` and
`init_block.mbt` (JSON, language-independent) all survive. `viewgen` is the only
real consumer; `cli/moon.pkg:12` imports statedef and never references it.
## 1. Why a superset, not a subset
Wax's `CompType` is `Func | Struct | Array | Cont` — because **wasm-gc has no sum
types**. Variants are encoded as a base type plus subtypes, dispatched by cast;
that is why wax carries `Match`/`Dispatch` instructions and `lower_match` /
`lower_dispatch` in `ast/utils.mbt`.
tutuca's state language is sum-type-centric: `enum`, `variant` with payloads, and
three message buckets that are all variants. Asking an author to hand-write
```rust
rec {
  type due = open { tag: i32 };
  type due_unscheduled : due = { tag: i32 };
  type due_on_day : due = { tag: i32, f0: i32 };
}
```
instead of `variant due { unscheduled, on-day(s32) }` is a bad trade, especially
for `variant receive { … }`, the most common declaration in the corpus.
So the language is a **superset**: wax's type syntax plus sum types plus implicit
recursion, lowered to wax's AST. The 1:1-with-wasm-gc property lives in the
lowering, not the surface.
**Scope: wasm-gc only.** The lowering targets wasm-gc exclusively — no
linear-memory wasm, no component model, no canonical ABI. That is a deliberate
narrowing and it removes the entire class of problems the companion design spends
its length on.
> **Assumption to confirm.** "wasm-gc only" constrains the *generated component*,
> not the *generator*. `statedef` and `viewgen` must keep running on **js** (for
> `playground/viewgen_js`, which is how the playground type-checks views in the
> browser) and on **native** (for `tutuca gen-views`). This distinction decides
> the dependency question in §6.
## 2. The surface language
Inherited from wax, unchanged:
| form | meaning |
|---|---|
| `{ f: T, g: mut U }` | struct; `mut` is assignable |
| `[T]` / `[mut T]` | array |
| `&T` | non-nullable reference |
| `&?T` | nullable reference |
| `type c : base = { … }` | subtyping |
| `open` | non-final (further subtypes allowed) |
| `..` | splice the supertype's fields |
| `#[attr = value]` | attributes |
Added by the superset:
| form | lowers to |
|---|---|
| `enum E { a, b }` | `i32` + a member table |
| `variant V { a, b(T), c(X, Y) }` | a rec group: base `open { tag: i32 }` + one subtype per case |
| `flags F { a, b }` | `i32` bitset |
| *(no `rec { }`)* | recursion groups inferred — §4 |
A block then reads close to what authors write today:
```rust
struct Label { text: String, done: Bool }
enum Priority { Low, High }
enum Due { Unscheduled, OnDay(Int) }
state NestedState { title: String, labels: Label, priority: Priority, due: Due, note: String, size: S32S32, parent: State }
```
### What stays a marker
wasm-gc has no map and no set, so wax does not help here and the marker table
does not shrink: `any`, `component`, `text-set`, `values`, `value-omap`,
`text-omap` all survive, and `map<K,V>` remains unavailable. Markers stay
reserved names for the reason `statedef/markers.mbt` gives — a user type
shadowing `any` would silently change every `any` in the file.
### What gets better for free
- **Per-field docs.** Wax's `trivia/` layer associates comments with spans, so
  `FieldDef.doc` and `MsgDef.doc` can stop being permanently `None`. That closes
  the gap that forces `Descriptor.field_docs` to sit outside the schema.
- **Constraints.** Wax has real attribute syntax, so
  `#[min = 0] count: s32` becomes expressible. `dyncomp/jsonschema/constraint.mbt`
  (min/max/minLen/pattern/format/default — "the half a type cannot say") is today
  reachable only from a guest's `manifest.json`. Attributes would let host
  components declare the same things from one source.
- **`flags` becomes a bitset.** Today `flags` and `text-set` both become
  `Map[String, Bool]` in MoonBit. Closed membership on wasm-gc is an `i32`.
## 3. Sum-type lowering
**`enum`** — payload-free, so `i32` with an ordinal per case. The member names
live in metadata, not in the type. `zero` is case 0, matching today's
`zero_expr` (`cs[0].1`).
**`flags`** — `i32` bitset, one bit per member, up to 32. Beyond 32 members,
reject (WIT's `flags` has the same practical bound). `zero` is `0`.
**`variant`** — a rec group:
```rust
// variant due { unscheduled, on-day(s32) }
type due            = open { tag: i32 }
type due_unscheduled : due = { .. }
type due_on_day      : due = { .., f0: s32 }
```
The explicit `tag` is not strictly required — `ref.test` / `br_on_cast` can
discriminate without it — but the meta layer (§5) must be able to *report* which
case a value is, and one `i32` load beats a cascade of casts. Tuple payloads keep
today's semantics: `c(X, Y)` is a multi-arg message, so it becomes two fields.
`zero` is the first case, as today.
## 4. Implicit recursion groups
No `rec { }` in the surface. The parser:
1. builds the type-reference graph over all declarations in the interface,
2. computes strongly-connected components (Tarjan),
3. emits each SCC as one wax `rec { }` group, in topological order,
4. emits singleton SCCs as plain `type` declarations.
This is where `check_acyclic` changes job. Today it **rejects** cycles. In the
new language it **groups** them, and rejects a strictly smaller set: a cycle in
which every edge is by-value.
The rule the author can see:
| edge | terminates? |
|---|---|
| `&?T`, `[T]`, `option<T>`, marker containers | yes — the cycle is legal |
| `&T`, plain `T`, tuple element | no — by-value |
A cycle whose every edge is by-value has no representation and no zero, and is
refused with the same `CyclicType` error. A cycle passing through even one
nullable ref, list or option is legal, and `zero_expr` terminates because
`&?T` zeroes to `None`.
That is the real advance, and it is worth stating precisely: **recursion becomes
legal not because a new parser allows it, but because the surface makes
indirection explicit, which gives the emitters a termination story.** Today's
implicit "list and option stop the walk" rule becomes something written down in
the type.
## 5. Two backends, one declaration
```
   <script type="tutuca/state">  (superset syntax)
              |
              v
        superset AST  (own parser, own spans)
         /                    \
        v                      v
  Backend 1                Backend 2
  MoonBit source           wax AST -> wasm-gc
  (viewgen, today)         (the meta layer)
```
### Backend 1 — MoonBit source, unchanged contract
`moonbit_ty` / `zero_expr` / `ty_info_src` keep their signatures, so `viewgen`'s
~70 call sites do not move. `enum` maps to a MoonBit enum, `variant` to a MoonBit
enum with payloads, `flags` to a bitset-backed type instead of
`Map[String, Bool]`, `&?T` to `T?`.
### Backend 2 — the meta layer as wasm-gc
**The precedent that makes this credible is already in the tree.** The field
mutators are *not* generated: `component/component.mbt:487-602` builds
`setX`, `updateX`, `resetX`, `toggleX`, `xLen`, `pushInX`, `setInXAt`,
`updateInXAt`, `deleteInXAt`, `addInX`, `toggleInX` from the `SchemaInfo` at
runtime. No `*_view_gen.mbt` contains any of them. tutuca already proved the
reflective layer can be schema-driven rather than emitted.
What *is* generated per component is small — counter's whole module is 241 lines:
the state struct, `zero()`, init fixtures, `Fields::encode`/`decode`,
the `Receive`/`Input`/`Msg` dispatch enums, and `Fields::schema()`.
Backend 2 would emit, as wasm-gc:
- the state struct type and its rec group,
- `zero() -> ref state`,
- `get_field(ref state, name) -> Value` and `with_field(ref state, name, Value) -> ref state`,
- `encode` / `decode` against the generic value representation,
- the schema table the runtime-generic mutators already consume.
That is exactly the surface `dyncomp`'s WIT `guest` resource exports
(`get-field`, `with-field`, `persist`, `restore`) — which is not a coincidence
and is the point of §7.
### The wall, stated plainly
**MoonBit cannot name an externally-defined wasm-gc type.** `moonc link-core`
has no type-import flag; `#external` yields an opaque `externref`. So Backend 2's
output cannot be consumed by MoonBit component code *as typed state*. A MoonBit
component holding one of these values holds an opaque reference and reaches its
fields through generated accessor calls, not through `s.count`.
That gives three honest positions:
1. **Backend 2 serves non-MoonBit consumers only** — the host reading fields
   generically, a dyncomp guest, the inspector. Backend 1 continues to serve
   MoonBit components with real typed structs. Both generated from one
   declaration, no wall hit. **This is the recommended scope.**
2. **Backend 2 becomes the representation, Backend 1 emits typed wrappers over
   it.** Coherent — the wrappers are typed, the implementation is shared, the
   state becomes language-neutral and host-inspectable. Cost: every field access
   is a cross-module call, and MoonBit loses pattern matching over state. Needs
   the externref round-trip probe below before it can be costed.
3. **Behaviour also moves to wax.** No MoonBit in the component at all, so no
   wall. Authoring ergonomics collapse; not recommended.
The decisive unknown for position 2 is whether MoonBit can hold and pass such a
reference at all — whether `#external` values survive a round trip through a
generated module's exports. That is one small probe (two modules, a JS harness),
and it should be run before position 2 is costed, not argued about.
## 6. Costs and risks
**The generator ships to the browser.** `playground/viewgen_js` compiles viewgen
to JS so the playground runs parse → `StateDef` → MoonBit-source client-side;
`dist/playground/fs/{js,wasm-gc}/lib/statedef/statedef.mi` is in the payload
today. statedef is currently a leaf with three small deps.
`waxmb/wax` is ~37k lines over 20 packages, including a ~24k-line
moonyacc-generated parser, and depends on `moonbitlang/async`. Pulling that into
the playground payload is a large regression for a package whose stated design is
"pure and target-agnostic: source text in, typed `StateDef` out".
Since the parser is ours anyway, the dependency is only needed where the lowering
runs — which is Backend 2, not Backend 1. **Backend 1 needs no wax dependency at
all.** That split is what keeps the browser payload flat.
**Migration surface.** 58 `.html` files carry state blocks, plus `skill/tutuca/`
(`schema.md` is the language definition), `README.md`, `README.mbt.md`,
`CHANGELOG.md` and the pattern files. 46 `*_view_gen.mbt` + 42
`*_view_ir_gen.mbt` regenerate under the existing `git diff --exit-code` drift
check.
**The fingerprint is safe.** `show_wit()` feeds `fingerprint()`, but the value is
never compared against anything and never persisted — it is an input to
`ObjId::of(fingerprint, fields)` (`core/obj_id.mbt:96`), and `core/schema.mbt:75`
records that the two fingerprints "hash different inputs… neither is compared
against the other". Changing the spelling is a regenerate-everything change the
drift check catches, not a data migration.
**`init_block.mbt` is untested.** `parse_init` / `InitError` have no test
anywhere in the repo, and only one fixture (`demo/counterlib/counter.html`)
exercises the path. Anything that touches `StateTy` should land tests here first.
## 7. Where this meets dyncomp
`dyncomp/host/manifest.mbt` carries a guest's types as a **flat table**
(`DynTyDef { kind, elem, items, name, members }`) rebuilt into nesting by
`ty_info_at` with a depth-16 cycle guard — and the reason is written in the file:
"WIT has no recursive types, so a compound points at its parts by index". It is a
second implementation of what `from_wit.mbt` does, over JSON instead of a WIT
AST.
One declaration language that has recursion natively could serve both, and
Backend 2's output is the same surface the WIT `guest` resource exports. That is
the convergence worth keeping in view — but it is a consequence, not a
prerequisite. Nothing here needs to happen for the state-language migration to
pay off.
## 8. Implementation plan
Staged so each step is independently verifiable and the risky part comes last.
### 1. Freeze the contract with tests
Before touching the parser, cover what has no tests: `parse_init` / `InitError`,
`binding_name`'s keyword list, `str_cmp`, `nearest`, `DefError::locus`,
`show_wit`. The fingerprint test already guards shape-vs-formatting.
*Done when:* the existing WIT parser passes a suite that does not mention WIT.
### 2. The superset parser
Replace `from_wit.mbt` with a hand-written parser for the superset, producing the
same `StateDef`. Carry real spans on every declaration. Drop `mizchi/wit` from
`statedef/moon.pkg` and the root `moon.mod`.
Recursion becomes SCC grouping (§4); `CyclicType` narrows to all-by-value cycles.
*Done when:* the §1 suite passes unchanged against the new parser, and
`DefError` carries spans.
### 3. Delete the line-guessing hack
With real spans, `viewgen/split.mbt:487-560`'s `locus()` + `find_word` scan goes,
and `DefError::locus` with it.
*Done when:* a bad state block reports the line the author wrote it on, proven by
a test with a deliberately duplicated identifier elsewhere in the file.
### 4. Migrate the corpus
Write `to_wax` — statedef had a `to_wit`/`to_guest` emitter, deleted as unused;
same shape, and this time it is a one-shot converter you can diff. Run it over
the 58 blocks, regenerate, let the drift check adjudicate. Update
`skill/tutuca/schema.md` (the language definition), the pattern files and the
READMEs.
*Done when:* `moon run --target native cmd/dev -- ci` is green with no WIT in the
tree.
### 5. Earn the new expressiveness
Per-field docs through trivia; `#[…]` constraints wired to
`dyncomp/jsonschema/constraint.mbt`; `flags` as a bitset. Each is independent and
each is a reason the migration was worth doing rather than a lateral move.
### 6. Backend 2 — exploratory
Probe the externref round trip first (§5). Then emit the wasm-gc meta layer for a
single component and drive it from the runtime-generic mutator path in
`component/component.mbt`, which needs only a `SchemaInfo` and get/set by name.
Position 1 scope: non-MoonBit consumers only.
*Done when:* one component's fields are readable and settable through generated
wasm-gc accessors, with the existing mutator layer unmodified.
## 9. Open questions
- **Does the generator stay wax-free?** Backend 1 needs no wax; Backend 2 does.
  If Backend 2 ever has to run in the browser, the payload question in §6 comes
  back.
- **`enum` ordinal stability.** Reordering cases silently changes the wire value.
  The fingerprint moves, but nothing compares fingerprints — so this needs either
  an explicit ordinal syntax or a documented rule.
- **Attribute vocabulary.** Which constraints are worth surfacing, and whether
  host components and guests validate them at the same point.
- **Does `variant` need the explicit `tag`,** or is `br_on_cast` enough once the
  meta layer's needs are written down concretely?

