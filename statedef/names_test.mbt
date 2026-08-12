// Names, orderings and the "did you mean" guess.
//
// Four small functions that every generated identifier and every diagnostic
// goes through, and that nothing tested. They are pinned here rather than
// through the emitters because the emitters would still pass if two of these
// changed in compensating ways — and because `locus` in particular is a
// contract with a caller in another package: `viewgen/split.mbt` scans the
// block for the identifier this returns in order to blame a line, so a locus
// that changes shape silently moves every semantic error to line 1.

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
  // kebab -> lowerCamel: the runtime name, what a view writes and JSON carries
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

  // The keyword escape lands on the BINDING only. `type` and `enum` are
  // perfectly good field names in an IDL, and renaming the runtime name would
  // break both the view that reads it and the JSON that carries it.
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
  // MoonBit keywords that WIT is perfectly happy with — which is the whole
  // situation the escape exists for.
  let d = def_of(
    "interface c { record state { match: string, lazy: s32, struct: bool } }",
  )
  assert_eq(d.fields.map(f => f.wit_name), ["match", "lazy", "struct"])
  assert_eq(d.fields.map(f => f.name), ["match", "lazy", "struct"])
  assert_eq(d.fields.map(f => f.binding), ["match_", "lazy_", "struct_"])
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
test "show_wit round-trips the spelling the author wrote" {
  let d = def_of(
    (
      #|interface counter {
      #|  enum priority { low, high }
      #|  record state {
      #|    label: string,
      #|    count: s32,
      #|    small: u8,
      #|    ratio: f64,
      #|    ok: bool,
      #|    history: list<s32>,
      #|    pick: option<string>,
      #|    pair: tuple<string, s32>,
      #|    pri: priority,
      #|    tags: text-set,
      #|    blob: any,
      #|  }
      #|}
    ),
  )
  let spellings = d.fields.map(f => f.ty.show_wit())
  assert_eq(spellings, [
    "string", "s32", "u8", "f64", "bool", "list<s32>", "option<string>", "tuple<string, s32>",
    // A named type shows the WIT name, NOT the generated MoonBit one
    // (`CounterPriority`): this string ends up in a message about source the
    // author wrote, so it has to be the spelling they can find.
     "priority", "text-set", "any",
  ])
}

///|
test "a syntax error's offset indexes the author's text, not the parser's" {
  // statedef prepends `package tutuca:state;` before handing the block to the
  // WIT parser, and subtracts it back off. Without that, every syntax error
  // in every state block in the corpus would point one line too far down.
  guard! def_err("interface c { record state { count: s32 } }\n@@@") is Some(e)
  guard e is WitSyntax(offset~, ..) else { fail("expected a syntax error") }
  assert_true(offset >= 44)
  // Nothing to point at by name — the position is exact, so there is no
  // identifier to scan for.
  assert_eq(e.locus(), None)
}

///|
test "a semantic error names the identifier a caller can scan for" {
  // `locus` exists because mizchi/wit carries no per-declaration spans, so a
  // semantic failure cannot report a position of its own. Naming the
  // identifier is what lets `viewgen/split.mbt` land on the right line.

  // A type outside the subset: the locus is the FIELD, the last segment of
  // the dotted path — that is what the author can find.
  guard! def_err("interface c { record state { big: s64 } }") is Some(e1)
  assert_true(e1 is UnsupportedType(_))
  assert_eq(e1.locus(), Some("big"))

  // An unresolvable type reference, same rule.
  guard! def_err("interface c { record state { x: nope } }") is Some(e2)
  assert_true(e2 is UnknownTypeRef(_))
  assert_eq(e2.locus(), Some("x"))

  // A by-value cycle has no representation and no zero; the locus is the type.
  guard! def_err(
      "interface c { record node { next: node } record state { n: node } }",
    )
    is Some(e3)
  assert_true(e3 is CyclicType(_))
  assert_eq(e3.locus(), Some("node"))

  // A missing state record blames the interface.
  guard! def_err("interface c { record other { x: s32 } }") is Some(e4)
  assert_true(e4 is NoStateRecord(_))
  assert_eq(e4.locus(), Some("c"))

  // Two names mapping onto one identifier: the SECOND is the one to look at,
  // because the first was fine until the second arrived.
  guard! def_err(
      "interface c { record state { set-label: s32, set_label: s32 } }",
    )
    is Some(e5)
  assert_true(e5 is Collision(_))
  assert_eq(e5.locus(), Some("set_label"))
}

///|
test "a block carrying its own package decl is refused before parsing" {
  // Prepending the header to a block that already has one yields "expected
  // interface" pointing at the author's line, so the case is caught first.
  guard! def_err("package a:b;\ninterface c { record state { x: s32 } }")
    is Some(e)
  assert_true(e is UnexpectedPackage(_))
  // Nothing useful to scan for: the offending text is a keyword, not a name.
  assert_eq(e.locus(), None)
}
