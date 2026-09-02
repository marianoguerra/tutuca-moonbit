// What `compile` makes of a file, at the seams `check_card` cannot reach.
//
// A card that CHECKS and does not COMPILE is the failure mode this backend has
// to keep out of the playground, and checking says nothing about it: the issue
// list is about what the card said, and these are about what the module ends up
// holding.

///|
/// The card-wide functions are decided per CARD, so a card whose only effect
/// lives in its second component still has to carry them.
///
/// `tc_flush` is emitted once, for the module, and CALLED from a component's
/// dispatch chain — so the two halves of the decision have to agree about what
/// the whole card uses.
test "an effect in the SECOND component still gets the card's flush" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/spec">
      #|  state Board { rows: Array[Row] }
      #|  state Row { label: String }
      #|</script>
      #|<script type="tutuca/script" for="Board">
      #|  receive add {
      #|    new Row
      #|    @cur.label = 'a'
      #|    .rows.push @cur
      #|  }
      #|</script>
      #|<script type="tutuca/script" for="Row">
      #|  receive ask { intent dyn 'picked' .label }
      #|</script>
      #|<template id="Board:main"><ul><x render-each=".rows"></x></ul></template>
      #|<template id="Row:main"><li @on.click="ask"></li></template>
    ),
    name="Card",
  )
  @debug.assert_eq(out.components, ["Board", "Row"])
  @debug.assert_eq(out.refusals.map(r => r.name), [])
  // The call site and the definition, both present. Reading the Wax rather
  // than the bytes because the bytes only say it linked, and what broke was
  // which of the two the module was missing.
  assert_true(out.wax.contains("fn tc_flush()"))
  assert_true(out.wax.contains("tc_flush();"))
}

///|
/// The same seam from the other side: the card imports what the SECOND
/// component reaches for. An import section is a statement about the module,
/// and a routed effect names four host functions no other card needs.
test "an effect in the SECOND component decides the card's imports" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/spec">
      #|  state Board { rows: Array[Row] }
      #|  state Row { label: String }
      #|</script>
      #|<script type="tutuca/script" for="Board">
      #|  receive add {
      #|    new Row
      #|    @cur.label = 'a'
      #|    .rows.push @cur
      #|  }
      #|</script>
      #|<script type="tutuca/script" for="Row">
      #|  receive ask { intent dyn 'picked' .label }
      #|</script>
      #|<template id="Board:main"><ul><x render-each=".rows"></x></ul></template>
      #|<template id="Row:main"><li @on.click="ask"></li></template>
    ),
    name="Card",
  )
  assert_true(out.wax.contains("fn ctl_intent("))
}

///|
/// The wiring a card declares reaches the manifest as SOURCE TEXT.
///
/// Nothing about a dynamic binding crosses the guest ABI: the module a card
/// compiles to is byte-identical whether or not the card provides anything.
/// The host parses these expressions and evaluates them against the instance
/// while rendering, exactly as it does for a component written in MoonBit —
/// which is why a card gets `provide` / `lookup` with no new import.
test "a card's provide/lookup sections reach the manifest" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/spec">
      #|  state Board {
      #|    theme: String
      #|    slot: Slot
      #|    provide { theme = .theme, Cell = self }
      #|  }
      #|  state Slot {
      #|    made: String
      #|    lookup { theme, color = 'gray', Cell }
      #|  }
      #|</script>
      #|<template id="Board:main"><div><x render=".slot"></x></div></template>
      #|<template id="Slot:main"><em :style="$'color: {*theme}'"></em></template>
    ),
    name="Card",
  )
  guard! out.manifest is Object(root)
  guard! root.get("components") is Some(Array(comps))
  guard! comps.get(0) is Some(Object(board))
  guard! comps.get(1) is Some(Object(slot))
  @debug.assert_eq(
    board.get("provide"),
    Some(
      Json::array([
        Json::object({
          "name": Json::string("theme"),
          "source": Json::string(".theme"),
        }),
        Json::object({
          "name": Json::string("Cell"),
          "source": Json::string("self"),
        }),
      ]),
    ),
  )
  // A lookup with no default carries an empty string, which is the wire's way
  // of spelling "none" — the manifest is JSON and every other absent string
  // key spells it the same way.
  @debug.assert_eq(
    slot.get("lookup"),
    Some(
      Json::array([
        Json::object({
          "name": Json::string("theme"),
          "default": Json::string(""),
        }),
        Json::object({
          "name": Json::string("color"),
          "default": Json::string("'gray'"),
        }),
        Json::object({
          "name": Json::string("Cell"),
          "default": Json::string(""),
        }),
      ]),
    ),
  )
  // The key the HOST reads. It used to be `requests`, which nothing read, so a
  // card could not have declared a served intent even in principle.
  @debug.assert_eq(board.get("serves"), Some(Json::array([])))
}

///|
/// A rule declared in the SPEC block reaches the card's module and its
/// manifest — the same rule, from the same synthesis, as the MoonBit backend.
///
/// Two backends keeping different rules for one file would be two answers to
/// one question, which is why the synthesis lives in `tscript/check` and both
/// call it rather than each carrying a copy.
test "the spec block's rules compile into the card and its manifest" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/spec">
      #|  state Ledger {
      #|    here  : Int
      #|    there : Int
      #|    total : Int
      #|
      #|    pred canPush
      #|      format 'nothing left here to push' { .here > 0 }
      #|
      #|    invariant conserved { (.here + .there) is .total }
      #|  }
      #|</script>
      #|<script type="tutuca/script">
      #|  receive push requires canPush {
      #|    .here -= 1
      #|    .there += 1
      #|  }
      #|</script>
      #|<template>
      #|  <button @on.click="push" @if.class="$conserved" @then="'ok'" @else="'bad'">
      #|    <x text=".here"></x>
      #|  </button>
      #|</template>
    ),
    name="Ledger",
  )
  guard! out.manifest is Object(root)
  guard! root.get("components") is Some(Array(comps))
  guard! comps.get(0) is Some(Object(ledger))
  // Both rules are `$`-callables, the way every value body is, so a badge
  // reading `$conserved` finds one.
  @debug.assert_eq(
    ledger.get("methods"),
    Some(Json::array([Json::string("canPush"), Json::string("conserved")])),
  )
  // …and both are predicates, so a `@when` may filter with either.
  @debug.assert_eq(
    ledger.get("whens"),
    Some(Json::array([Json::string("canPush"), Json::string("conserved")])),
  )
}

///|
/// A `where` LEAVES the card, and this is the only door it has.
///
/// The rules above compile INTO the module — a card declines its own
/// transition, before its buffered effects go out. A domain does not: the
/// vocabulary is closed precisely so a generator can read it backwards, and
/// what reads it at runtime is `core/domain.mbt`, which the guest world has no
/// shape for. So the declaration travels in the manifest and the HOST enforces
/// it, at the two doors `DynObj` owns, and this is the hop that has to work
/// for any of that to happen.
test "the spec block's `where` clauses reach the manifest" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/spec">
      #|  state Gallery {
      #|    items        : Array[Any]
      #|    entries      : Map[String, Any]
      #|    currentIndex : Int
      #|    currentKey   : String
      #|    view         : String
      #|    count        : Int
      #|
      #|    where currentIndex is index of .items
      #|    where currentKey   is key of .entries
      #|    where view is one of ["main", "edit"]
      #|    where count between 0 and 10
      #|    where items is nonempty
      #|  }
      #|</script>
      #|<template><span @text=".currentKey"></span></template>
    ),
    name="Gallery",
  )
  guard! out.manifest is Object(root)
  guard! root.get("components") is Some(Array(comps))
  guard! comps.get(0) is Some(Object(gallery))
  guard! gallery.get("domains") is Some(domains)
  // Read back with the reader the HOST uses, rather than compared as JSON: the
  // claim is that a host can act on this, and the shape it is written in is
  // `core`'s business rather than this test's.
  let read = @tutuca.domains_of_json(domains)
  @debug.assert_eq(read.map(d => d.field), [
    "currentIndex", "currentKey", "view", "count", "items",
  ])
  @debug.assert_eq(read[0].domain, DIndexOf(field="items", allow_none=false))
  @debug.assert_eq(read[1].domain, DKeyOf(field="entries"))
  @debug.assert_eq(read[2].domain, DOneOf([Str("main"), Str("edit")]))
  @debug.assert_eq(read[3].domain, DBetween(lo=DLit(0), hi=DLit(10)))
  @debug.assert_eq(read[4].domain, DNonEmpty)
}

///|
/// A card that declares none carries an empty list, not a missing key.
test "a card with no `where` carries an empty domain list" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/spec">
      #|  state Plain { count : Int }
      #|</script>
      #|<template><span @text=".count"></span></template>
    ),
    name="Plain",
  )
  guard! out.manifest is Object(root)
  guard! root.get("components") is Some(Array(comps))
  guard! comps.get(0) is Some(Object(plain))
  @debug.assert_eq(plain.get("domains"), Some(Json::array([])))
}

///|
/// A protocol's properties reach the manifest as OBJECTS, with the type the
/// declaration wrote down.
///
/// Names alone would be a lossy spelling of something the host has a use for:
/// `DynProtocolDef` carries a property-def per member and reads its `ty` to
/// build a `PropertyInfo`. They were names once, and `dyncomp/host` refused
/// every bundle that had one — the parser wanted the shape the declaration
/// could have given it all along.
test "a protocol's properties reach the manifest with their types" {
  let out = @wasm.compile(
    (
      #|<script type="tutuca/spec">
      #|  protocol Holder = "x/Holder@1" {
      #|    property { filled: Bool }
      #|  }
      #|  state Hole implements Holder {
      #|    kept: String
      #|    flag: Bool
      #|    property {
      #|      filled: Bool { get .flag }
      #|      Holder::filled = filled
      #|    }
      #|  }
      #|</script>
      #|<template id="Hole:main"><div @text=".kept"></div></template>
    ),
    name="Card",
  )
  guard! out.manifest is Object(root)
  guard! root.get("components") is Some(Array(comps))
  guard! comps.get(0) is Some(Object(hole))
  guard! hole.get("protocols") is Some(Array(protos))
  guard! protos.get(0) is Some(Object(holder))
  guard! holder.get("properties") is Some(Array(props))
  guard! props.get(0) is Some(Object(filled))
  @debug.assert_eq(filled.get("name"), Some(Json::string("filled")))
  @debug.assert_eq(filled.get("public"), Some(Json::boolean(true)))
  // The type is the TYPE, written where it is used. It was an index into a
  // per-component table, which is how a list's element type came to be
  // omitted from every manifest ever written.
  guard! filled.get("ty") is Some(ty)
  @debug.assert_eq(@tutuca.Ty::of_json(ty), TyBool)
}
