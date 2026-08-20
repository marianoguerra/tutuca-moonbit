// The state block's `intent` variant.
//
// v2's third message word and the last one it needs: `receive` declares every
// MESSAGE the component accepts beyond the ones its own views send, and
// `intent` declares every INTENT it answers. `bubble` and `response` still
// parse and go in the plan's task 25.

///|
fn parse_one(src : String) -> @statedef.StateDef raise {
  @statedef.parse_state(src)[0]
}

///|
test "intent declares a bucket beside receive" {
  let d = parse_one(
    (
      #|state Board { rows: Array[Any] }
      #|receive Board { reset, loadRowsOk(Array[Any]) }
      #|intent  Board { rowPicked(Int), saveDraft(String) }
    ),
  )
  assert_eq(d.receive.map(m => m.name), ["reset", "loadRowsOk"])
  assert_eq(d.intent.map(m => m.name), ["rowPicked", "saveDraft"])
  assert_eq(d.intent[1].payload.length(), 1)
  // The two v1 buckets are still parseable and simply empty here.
  assert_eq(d.bubble.length(), 0)
  assert_eq(d.response.length(), 0)
}

///|
test "the v1 buckets still parse beside it" {
  let d = parse_one(
    (
      #|state Board { rows: Array[Any] }
      #|bubble   Board { rowPicked(Int) }
      #|response Board { loadRows(Array[Any]) }
      #|intent   Board { saveDraft(String) }
    ),
  )
  assert_eq(d.bubble.map(m => m.name), ["rowPicked"])
  assert_eq(d.response.map(m => m.name), ["loadRows"])
  assert_eq(d.intent.map(m => m.name), ["saveDraft"])
}

///|
test "a type may be called Intent, and a bucket case may be too" {
  // The risk this task carries: the declaration word is `intent` and a type
  // name is capitalized, so the two live in different namespaces — but a
  // parser that lowercased before matching would collide, and nothing else
  // would notice until somebody named a struct after the keyword.
  let d = parse_one(
    (
      #|struct Intent { name: String, urgent: Bool }
      #|state Board { pending: Intent }
      #|intent Board { Intent(Intent) }
    ),
  )
  assert_eq(d.types.map(t => t.source_name), ["Intent"])
  assert_eq(d.fields[0].name, "pending")
  assert_eq(d.intent.map(m => m.source_name), ["Intent"])
  assert_eq(d.intent[0].name, "intent")
}

///|
test "an unknown declaration word names the five that are legal" {
  let msg = try {
    parse_one("stat Board { a: Int }") |> ignore
    ""
  } catch {
    e => e.to_string()
  }
  // Two places name the legal words — the parser's `want` text and this
  // message — and a word added to the match without being added to both is a
  // parser that accepts something it says it does not.
  assert_eq(
    msg, "state block: `stat` is not a declaration — expected state, struct, enum, receive, intent, bubble or response",
  )
}
