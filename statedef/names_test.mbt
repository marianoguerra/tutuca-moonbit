// Names, orderings and the "did you mean" guess.
//
// Four small functions that every generated identifier and every diagnostic
// goes through, and that nothing tested. They are pinned here rather than
// through the emitters, because the emitters would still pass if two of them
// changed in compensating ways.
//
// The parser's diagnostics are pinned here too: they carry an exact span that
// the view-file layer can rebase onto the source file.

///|
/// The error a state block raises, or None when it parses.
fn def_err(src : String) -> @statedef.DefError? {
  try {
    @statedef.parse_state(src) |> ignore
    None
  } catch {
    e => Some(e)
  }
}

///|
test "the three name shapes, and where the keyword escape lands" {
  // A field is written the way a view reads it, so these two exist for the
  // shapes that genuinely differ: a MoonBit type or variant name is
  // UpperCamel, and a binding has to dodge the keywords.
  assert_eq(@statedef.camel_name("set-label"), "setLabel")
  assert_eq(@statedef.camel_name("reset"), "reset")
  assert_eq(@statedef.camel_name("with-history"), "withHistory")
  // Separators are anything non-alphanumeric, and the first character is
  // lowered whatever it was.
  assert_eq(@statedef.camel_name("Set_Label"), "setLabel")
  assert_eq(@statedef.camel_name("a-1-b"), "a1B")

  // kebab -> UpperCamel: a MoonBit type or enum-variant name
  assert_eq(@statedef.upper_name("set-label"), "SetLabel")
  assert_eq(@statedef.upper_name("reset"), "Reset")
  assert_eq(@statedef.upper_name("high-ish"), "HighIsh")

  // The keyword escape lands on the binding only. Renaming the runtime name
  // would break both the view that reads it and the JSON that carries it.
  assert_eq(@statedef.binding_name("type"), "type_")
  assert_eq(@statedef.binding_name("init"), "init_")
  assert_eq(@statedef.binding_name("match"), "match_")
  // Reserved-for-future-use words are escaped too: MoonBit warns on them, and
  // a generated file must not be the thing that warns.
  assert_eq(@statedef.binding_name("lazy"), "lazy_")
  assert_eq(@statedef.binding_name("package"), "package_")
  // Everything else passes through untouched.
  assert_eq(@statedef.binding_name("label"), "label")
  assert_eq(@statedef.binding_name("isOpen"), "isOpen")
}

///|
test "a keyword field keeps its runtime name and escapes only its binding" {
  // MoonBit keywords that are perfectly good field names — which is the whole
  // situation the escape exists for.
  let d = def_of("state { match: String, lazy: Int, guard: Bool }")
  assert_eq(d.fields.map(f => f.name), ["match", "lazy", "guard"])
  assert_eq(d.fields.map(f => f.name), ["match", "lazy", "guard"])
  assert_eq(d.fields.map(f => f.binding), ["match_", "lazy_", "guard_"])
}

///|
test "str_cmp is byte order, not MoonBit's length-first Compare" {
  // The example from the rationale: `Compare for String` is length-first, so
  // `a < b` would put `sel` before `item`, and a generated list ordered by
  // length reads as unordered.
  assert_true(@statedef.str_cmp("item", "sel") < 0)
  assert_true("sel" < "item")
  // A prefix sorts before what extends it; equals is 0.
  assert_true(@statedef.str_cmp("a", "aa") < 0)
  assert_eq(@statedef.str_cmp("same", "same"), 0)
  assert_true(@statedef.str_cmp("b", "a") > 0)
}

///|
test "nearest guesses within a length-scaled budget, and otherwise not at all" {
  let fields = ["label", "count", "history"]
  // One edit in a five-character name is inside the budget (1 + len/3).
  assert_eq(@statedef.nearest("labl", fields), Some("label"))
  assert_eq(@statedef.nearest("counr", fields), Some("count"))
  // An exact name is its own nearest.
  assert_eq(@statedef.nearest("count", fields), Some("count"))
  // Far enough away and it declines rather than pointing somewhere arbitrary:
  // a wrong suggestion costs more than none.
  assert_eq(@statedef.nearest("wildlyDifferent", fields), None)
  assert_eq(@statedef.nearest("x", fields), None)
  // Nothing to choose from is None, not a crash.
  assert_eq(@statedef.nearest("label", []), None)
}

///|
/// The property that makes this the TWIN of `lint/closest_name.mbt` rather
/// than merely similar to it: a swapped pair is ONE edit in both, where plain
/// Levenshtein calls it two.
///
/// `hsitroy` is the case that actually separates them, and finding it took
/// measuring rather than guessing: at this length-scaled budget a SINGLE
/// transposition is inside the limit either way (`histroy` is 2 plain, and
/// the limit for seven characters is 3), so a one-swap example pins nothing.
/// Two swaps is 4 plain — outside — and 2 with transpositions.
test "nearest counts a transposition as one edit, the way lint does" {
  let fields = ["label", "count", "history"]
  assert_eq(@statedef.nearest("hsitroy", fields), Some("history"))
}

///|
test "show_source round-trips the spelling the author wrote" {
  let d = def_of(
    (
      #|enum Priority { Low, High }
      #|state {
      #|  label   : String
      #|  count   : Int
      #|  small   : UInt8
      #|  ratio   : Double
      #|  ok      : Bool
      #|  history : Array[Int]
      #|  pick    : String?
      #|  pair    : (String, Int)
      #|  pri     : Priority
      #|  tags    : Set[String]
      #|  blob    : Any
      #|}
    ),
  )
  let spellings = d.fields.map(f => f.ty.show_source())
  assert_eq(spellings, [
    "String", "Int", "UInt8", "Double", "Bool", "Array[Int]", "String?", "(String, Int)",
    // A named type shows the name the AUTHOR wrote, not the generated MoonBit
    // one (`CounterPriority`): this string ends up in a message about source
    // they have open, so it has to be the spelling they can find.
     "Priority",
    // A set spells its membership: open is `Set[String]`, and closed names
    // the enum where the members are declared.
     "Set[String]", "Any",
  ])
}

///|
test "a syntax error carries a span, not an identifier to go looking for" {
  guard! def_err("state { count: }") is Some(e)
  assert_eq(e.message(), "state block: expected a type, found `}`")
  assert_eq(e.span(), { start: 15, end_: 16, })
}

///|
test "every failure points at the thing it is about" {
  // A 64-bit integer is NAMED rather than left unknown: "unknown type
  // `Int64`" would read as a spelling mistake when the answer is that state
  // travels as JSON and a JSON number is a Double.
  guard! def_err("state { big: Int64 }") is Some(e1)
  assert_true(e1 is UnsupportedType(_))
  assert_true(e1.message().contains("2^53"))
  assert_eq(e1.span(), { start: 13, end_: 18, })

  guard! def_err("state { big: Nope }") is Some(e1b)
  assert_true(e1b is UnknownTypeRef(_))

  // A type application with the wrong arity.
  guard! def_err("state { xs: Array[Int, Int] }") is Some(e2)
  assert_true(e2 is BadTypeArgs(_))
  assert_eq(
    e2.message(),
    "state block: `Array` takes 1 type argument(s), not 2",
  )

  // A by-value cycle has no representation and no zero.
  guard! def_err("struct Node { next: Node }\nstate { n: Node }") is Some(e3)
  assert_true(e3 is CyclicType(_))

  // …and one through `Array` or `?` is fine, because both terminate.
  assert_true(def_err("struct Node { next: Node? }\nstate { n: Node }") is None)
  assert_true(
    def_err("struct Node { kids: Array[Node] }\nstate { n: Node }") is None,
  )

  // Two names collapsing onto one binding: the SECOND is the one to look at,
  // because the first was fine until the second arrived.
  guard! def_err("state { match: Int, match_: Int }") is Some(e4)
  assert_true(e4 is Collision(_))
}

///|
test "a block with no state describes no component" {
  guard! def_err("struct Label { text: String }") is Some(e)
  assert_true(e is NoState(_))
}

///|
test "a file names every component or none of them, as its templates do" {
  // The rule the `<template>` ids already follow, applied one block up: bare
  // means the file's single component, a name means that one.
  assert_true(def_err("state { n: Int }") is None)
  assert_true(def_err("state A { n: Int }\nstate B { m: Int }") is None)
  guard! def_err("state { n: Int }\nstate B { m: Int }") is Some(e)
  assert_true(e is MixedStateNames(_))
  guard! def_err("state A { n: Int }\nstate A { m: Int }") is Some(dup)
  assert_true(dup is DuplicateComponent(_))
}

///|
test "a builtin type name cannot be declared" {
  // Reserved for the reason the markers were: a user type called `Any` would
  // silently change what every `Any` in the file means.
  guard! def_err("struct Any { x: Int }\nstate { a: Int }") is Some(e)
  assert_true(e is ReservedName(_))
}
