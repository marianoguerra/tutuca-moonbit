// The rule layer: `pred` and `invariant` in the spec block.
//
// What is tested here is the SHAPE — where a rule may appear, how its body and
// its sentence are found, and which names collide. What a rule SAYS is
// `tscript`'s question: the two sources come out of this package as text, and
// nothing here reads them.

///|
fn one(src : String) -> @statedef.StateDef raise {
  let defs = @statedef.parse_state(src)
  assert_eq(defs.length(), 1)
  defs[0]
}

///|
test "a pred and an invariant, with their bodies taken whole" {
  let def = one(
    (
      #|state Ledger {
      #|  here  : Int
      #|  there : Int
      #|  total : Int
      #|  pred canPush { .here > 0 }
      #|  invariant conserved { (.here + .there) is .total }
      #|}
    ),
  )
  assert_eq(def.rules.length(), 2)
  assert_eq(def.rules[0].name, "canPush")
  assert_eq(def.rules[0].kind, RPred)
  assert_eq(def.rules[0].source, " .here > 0 ")
  assert_eq(def.rules[1].name, "conserved")
  assert_eq(def.rules[1].kind, RInvariant)
  assert_eq(def.rules[1].source, " (.here + .there) is .total ")
  // The fields are untouched: a rule is not a field, and reading one did not
  // consume the other.
  assert_eq(def.fields.length(), 3)
}

///|
test "the body's span rebases onto the block exactly" {
  let src =
    #|state L {
    #|  n : Int
    #|  pred ok { .n > 0 }
    #|}
  let def = one(src)
  let chars = src.to_array()
  let sp = def.rules[0].source_span
  let text = StringBuilder()
  for i in sp.start..<sp.end_ {
    text.write_char(chars[i])
  }
  // The INNER range: just past `{`, just before the matching `}`. Which is
  // what a caller parsing the block language rebases its own span onto.
  assert_eq(text.to_string(), " .n > 0 ")
}

///|
test "a format sentence runs to the body's brace, braces in the template included" {
  let def = one(
    (
      #|state L {
      #|  n : Int
      #|  invariant positive
      #|    format $'{.n} is not above zero' { .n > 0 }
      #|}
    ),
  )
  assert_eq(def.rules[0].format, "$'{.n} is not above zero'")
  assert_eq(def.rules[0].source, " .n > 0 ")
}

///|
test "a rule with no format says so with an empty string, not an absence" {
  let def = one("state L { n : Int  pred ok { .n > 0 } }")
  assert_eq(def.rules[0].format, "")
}

///|
test "a `}` inside a string does not close the body" {
  let def = one(
    (
      #|state L {
      #|  s : String
      #|  pred braced { .s is '}' }
      #|}
    ),
  )
  assert_eq(def.rules[0].source, " .s is '}' ")
}

///|
test "a nested brace is matched, not the first one found" {
  let def = one(
    (
      #|state L {
      #|  n : Int
      #|  pred ok { if (.n > 0) { true } else { false } }
      #|}
    ),
  )
  assert_eq(def.rules[0].source, " if (.n > 0) { true } else { false } ")
}

///|
test "the doc comment above a rule is its own" {
  let def = one(
    (
      #|state L {
      #|  n : Int
      #|  /// What the rule IS, as opposed to what went wrong this time.
      #|  pred ok { .n > 0 }
      #|}
    ),
  )
  assert_eq(
    def.rules[0].doc,
    Some("What the rule IS, as opposed to what went wrong this time."),
  )
}

///|
test "`pred` is not a reserved field name" {
  // The lexer arms on a SHAPE — the word, a name, and then a brace or
  // `format` — so nothing was taken away from an author to add the rule layer.
  let def = one("state L { pred : Bool  invariant : String }")
  assert_eq(def.rules.length(), 0)
  assert_eq(def.fields.length(), 2)
  assert_eq(def.fields[0].name, "pred")
  assert_eq(def.fields[1].name, "invariant")
}

///|
test "`pred` is not a reserved case name either" {
  // A case list is the one place two bare identifiers sit side by side, which
  // is why the lexer needs two tokens of lookahead rather than one.
  let def = one(
    (
      #|enum Kind { pred invariant }
      #|state L { kind : Kind }
    ),
  )
  assert_eq(def.rules.length(), 0)
  assert_eq(
    def.types[0].kind,
    UEnum([("pred", "Pred"), ("invariant", "Invariant")]),
  )
}

///|
test "two rules with one name are refused, whatever their kinds" {
  // They share the `$name` namespace: `$conserved` reads an invariant from a
  // view exactly as `$canPush` reads a pred.
  for
    src in [
      "state L { n : Int  pred ok { .n > 0 }  pred ok { .n < 9 } }", "state L { n : Int  pred ok { .n > 0 }  invariant ok { .n < 9 } }",
    ] {
    try @statedef.parse_state(src) |> ignore catch {
      e => assert_true(e.message().contains("two rules named `ok`"))
    } noraise {
      _ => fail("expected the duplicate to be reported: \{src}")
    }
  }
}

///|
test "a rule outside a state body is refused, with where it belongs" {
  try
    @statedef.parse_state(
      "struct R { n : Int  pred ok { .n > 0 } }\nstate L { r : R }",
    )
    |> ignore
  catch {
    e => assert_true(e.message().contains("move it inside the `state` body"))
  } noraise {
    _ => fail("expected a rule in a struct to be refused")
  }
}

///|
test "a rule with no body is refused before anything guesses one" {
  try
    @statedef.parse_state("state L { n : Int  pred ok format 'no' }") |> ignore
  catch {
    e => assert_true(e.message().contains("needs a body"))
  } noraise {
    _ => fail("expected the missing body to be reported")
  }
}

///|
test "`invariants()` answers the kept rules, sorted" {
  let def = one(
    (
      #|state L {
      #|  n : Int
      #|  invariant zeta { .n > 0 }
      #|  pred helper { .n < 9 }
      #|  invariant alpha { .n < 100 }
      #|}
    ),
  )
  // Sorted, because WHICH rule broke is part of the answer and a report that
  // depended on declaration order would move when a rule was added above it.
  assert_eq(def.invariants(), ["alpha", "zeta"])
  assert_eq(def.rule("helper").unwrap().kind, RPred)
  assert_eq(def.rule("nothing"), None)
}

///|
test "a rule does not move the fingerprint" {
  // The digest is for noticing that a stored state can no longer be READ BACK,
  // and a rule changes nothing about readability. Tightening one should be the
  // cheapest edit in the block, not the most expensive.
  let bare = @statedef.parse_state("state L { n : Int }")
  let ruled = @statedef.parse_state(
    "state L { n : Int  invariant positive { .n > 0 } }",
  )
  assert_eq(@statedef.fingerprint(bare), @statedef.fingerprint(ruled))
}

///|
test "a rule with parameters is refused, with where a filter belongs" {
  // A rule here is a fact about the component's STATE. One that needs an
  // argument is about the particular call that supplied it — the same line
  // `CONTRACT_ARGS` draws for a contract clause — so it stays in the script
  // block beside the other render-time callables.
  try
    @statedef.parse_state(
      "state Row { title : String  pred containsText(q) { contains .title q } }",
    )
    |> ignore
  catch {
    e =>
      assert_true(
        e
        .message()
        .contains("takes parameters, and a rule in the spec block takes none"),
      )
  } noraise {
    _ => fail("expected a parameterised rule to be refused")
  }
}

///|
test "a rule reading a render binding is reported, not silently answered" {
  // `@value` is what a loop hands a filter, and a rule in the spec block is
  // asked from no loop at all. It parses — this package reads no bodies — and
  // the checker is what says so.
  let def = @statedef.parse_state(
      "state Row { needle : String  pred matches { contains (str @value) .needle } }",
    )[0]
  assert_eq(def.rules[0].source, " contains (str @value) .needle ")
}
