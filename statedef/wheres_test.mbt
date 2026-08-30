// The `where` layer: declared field domains in the spec block.
//
// What is tested here is the DECLARATION — which clauses parse, which names
// resolve, which type pairings are refused, and that a cycle is caught. What a
// clause does to a generated value is `@arb`'s question, and what it does to a
// running component is `component`'s.

///|
fn w_one(src : String) -> @statedef.StateDef raise {
  let defs = @statedef.parse_state(src)
  assert_eq(defs.length(), 1)
  defs[0]
}

///|
/// The message a block produces, or "" when it parsed.
fn w_err(src : String) -> String {
  try {
    @statedef.parse_state(src) |> ignore
    ""
  } catch {
    e => e.message()
  }
}

///|
test "the three clauses the fuzzer asked for" {
  let def = w_one(
    (
      #|state Gallery {
      #|  items        : Array[Int]
      #|  entries      : Map[String, Int]
      #|  currentIndex : Int
      #|  currentKey   : String
      #|  count        : Int
      #|
      #|  where currentIndex is index of .items
      #|  where currentKey   is key of .entries
      #|  where count >= 0
      #|}
    ),
  )
  assert_eq(def.wheres.length(), 3)
  assert_eq(def.wheres[0].subject, "currentIndex")
  assert_true(
    def.wheres[0].relation is RIndexOf(field="items", allow_none=false),
  )
  assert_eq(def.wheres[1].subject, "currentKey")
  assert_true(def.wheres[1].relation is RKeyOf(field="entries"))
  assert_true(def.wheres[2].relation is RCompare(op=CGe, rhs=OLit(0.0)))
  // The fields are untouched: reading a clause did not consume one.
  assert_eq(def.fields.length(), 5)
}

///|
test "the rest of the vocabulary" {
  let def = w_one(
    (
      #|enum Priority { Low, High }
      #|state Bag {
      #|  items   : Array[Int]
      #|  tags    : Set[String]
      #|  allTags : Set[String]
      #|  sel     : Int
      #|  tag     : String
      #|  some    : Set[String]
      #|  level   : String
      #|  lo      : Int
      #|  hi      : Int
      #|  name    : String
      #|  labels  : Array[String]
      #|
      #|  where sel is index of .items or none
      #|  where tag is member of .tags
      #|  where some is subset of .allTags
      #|  where items is nonempty
      #|  where items len <= 100
      #|  where tags len between 1 and 10
      #|  where level is one of ["debug", "info"]
      #|  where name is one of .labels
      #|  where name is one of Priority
      #|  where hi >= .lo
      #|  where lo between 0 and 99
      #|}
    ),
  )
  let r = def.wheres
  assert_true(r[0].relation is RIndexOf(field="items", allow_none=true))
  assert_true(r[1].relation is RMemberOf(field="tags"))
  assert_true(r[2].relation is RSubsetOf(field="allTags"))
  assert_true(r[3].relation is RNonEmpty)
  assert_true(r[4].relation is RLen(RCompare(op=CLe, rhs=OLit(100.0))))
  assert_true(r[5].relation is RLen(RBetween(lo=OLit(1.0), hi=OLit(10.0))))
  assert_true(r[6].relation is ROneOf(["debug", "info"]))
  // The list spelling of the same relation: the members are what a sibling
  // ARRAY holds, which is what a select field's options are.
  assert_true(r[7].relation is RElementOf(field="labels"))
  // The enum spelling is expanded to its members, which the PARSER could not
  // do — a `where` may be written above the `enum` it names.
  assert_true(r[8].relation is ROneOf(["Low", "High"]))
  assert_true(r[9].relation is RCompare(op=CGe, rhs=OField("lo")))
  assert_true(r[10].relation is RBetween(lo=OLit(0.0), hi=OLit(99.0)))
}

///|
test "several clauses on one field conjoin rather than collide" {
  // The difference from a rule, and the reason the two are separate lists: a
  // rule is a NAME and two would be one `$name` with two answers, while a
  // `where` has no name and nothing to collide with.
  let def = w_one(
    (
      #|state Dial { n : Int
      #|  where n >= 0
      #|  where n <= 100
      #|}
    ),
  )
  assert_eq(def.wheres.length(), 2)
  assert_eq(def.wheres[0].subject, def.wheres[1].subject)
}

///|
test "`where` is still available as a field and as a case name" {
  // The bargain `pred` and `provide` already struck: the trigger is a SHAPE,
  // so nothing was taken away from an author to add the clause.
  let def = w_one(
    (
      #|enum Mode { where, is, len }
      #|state Q { where : String, is : Int, len : Int, mode : Mode }
    ),
  )
  assert_eq(def.fields.length(), 4)
  assert_eq(def.fields[0].name, "where")
  assert_eq(def.wheres.length(), 0)
}

///|
test "a name the state does not declare, with a suggestion" {
  assert_eq(
    w_err(
      (
        #|state G { items : Array[Int], idx : Int
        #|  where idxx is index of .items
        #|}
      ),
    ),
    "spec block: `where idxx` — this state declares no field `idxx`, did you mean `idx`?",
  )
  assert_eq(
    w_err(
      (
        #|state G { items : Array[Int], idx : Int
        #|  where idx is index of .item
        #|}
      ),
    ),
    "spec block: `.item` — this state declares no field `item`, did you mean `items`?",
  )
}

///|
test "a relation that cannot mean anything for the types it was written over" {
  // The subject is not a number.
  assert_true(
    w_err(
      (
        #|state G { items : Array[Int], idx : String
        #|  where idx is index of .items
        #|}
      ),
    ).contains("an index is a whole number, and `idx` is a `String`"),
  )
  // A map has keys and not positions, and the message says which to reach for.
  assert_true(
    w_err(
      (
        #|state G { m : Map[String, Int], idx : Int
        #|  where idx is index of .m
        #|}
      ),
    ).contains("A map is keyed rather than positioned — say `key of` instead"),
  )
  // A length is not a thing an Int has.
  assert_true(
    w_err(
      (
        #|state G { n : Int
        #|  where n len <= 3
        #|}
      ),
    ).contains("`len` is about a length"),
  )
  // An ordering over text points at the clause that does work.
  assert_true(
    w_err(
      (
        #|state G { s : String
        #|  where s >= 0
        #|}
      ),
    ).contains("write `is one of […]`"),
  )
  // Bounds the wrong way round admit nothing, and are silent at every later
  // stage if they get through.
  assert_true(
    w_err(
      (
        #|state G { n : Int
        #|  where n between 10 and 1
        #|}
      ),
    ).contains("admits nothing"),
  )
}

///|
test "a cycle is refused, and names only the fields in it" {
  let msg = w_err(
    (
      #|state G { a : Int, b : Int, c : Int
      #|  where c >= 0
      #|  where a >= .b
      #|  where b >= .a
      #|}
    ),
  )
  assert_true(msg.contains("depend on each other in a cycle"))
  assert_true(msg.contains("`a`"))
  assert_true(msg.contains("`b`"))
  // `c` has a clause too, and is not part of the cycle.
  assert_false(msg.contains("`c`"))
}

///|
test "a chain is not a cycle" {
  let def = w_one(
    (
      #|state G { a : Int, b : Int, c : Int
      #|  where a >= .b
      #|  where b >= .c
      #|}
    ),
  )
  assert_eq(def.wheres.length(), 2)
}

///|
test "a `where` outside a state says so, rather than asking for a colon" {
  assert_eq(
    w_err(
      (
        #|struct R { n : Int
        #|  where n >= 0
        #|}
        #|state G { r : R }
      ),
    ),
    "spec block: a `where` names a field beside it, so it belongs inside the `state` body",
  )
}

///|
test "the vocabulary is closed, and says what it admits" {
  assert_true(
    w_err(
      (
        #|state G { n : Int
        #|  where n is prime
        #|}
      ),
    ).contains("`prime` is not something a `where` can say"),
  )
  assert_true(
    w_err(
      (
        #|state G { items : Array[Int], n : Int
        #|  where n is index .items
        #|}
      ),
    ).contains("`index` in a `where` is followed by `of`"),
  )
  assert_true(
    w_err(
      (
        #|state G { n : String
        #|  where n is one of Missing
        #|}
      ),
    ).contains("names no enum this block declares"),
  )
  // `one of` is about membership; for numbers the answer is a range, which a
  // generator can draw from without the author listing every value.
  assert_true(
    w_err(
      (
        #|state G { n : Int
        #|  where n is one of ["1", "2"]
        #|}
      ),
    ).contains("For a closed range of numbers, write `between a and b`"),
  )
}
