// The state block's handled intent channel.
//
// The second message word and the last one needed: `receive` declares every
// MESSAGE the component accepts beyond the ones its own views send, and
// `intent` declares every INTENT it answers.

///|
fn parse_one(src : String) -> @statedef.StateDef raise {
  @statedef.parse_state(src)[0]
}

///|
test "intent declares a bucket beside receive" {
  let d = parse_one(
    (
      #|state Board { rows: Array[Any] }
      #|handle Board {
      #|  message { reset, loadRowsOk(Array[Any]) }
      #|  intent { rowPicked(Int), saveDraft(String) }
      #|}
    ),
  )
  assert_eq(d.receive.map(m => m.name), ["reset", "loadRowsOk"])
  assert_eq(d.intent.map(m => m.name), ["rowPicked", "saveDraft"])
  assert_eq(d.intent[1].payload.length(), 1)
}

///|
test "legacy message buckets are not declarations" {
  // There are two buckets and two words for them. A third is not a bucket
  // nobody uses — it is a parse error, which is what keeps the schema and the
  // dispatch model from drifting apart.
  for word in ["receive", "intent", "bubble", "response", "on"] {
    let src = "state Board { rows: Array[Any] }\n\{word} Board { rowPicked(Int) }"
    let failed = try {
      parse_one(src) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
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
      #|handle Board { intent { Intent(Intent) } }
    ),
  )
  assert_eq(d.types.map(t => t.source_name), ["Intent"])
  assert_eq(d.fields[0].name, "pending")
  assert_eq(d.intent.map(m => m.source_name), ["Intent"])
  assert_eq(d.intent[0].name, "intent")
}

///|
test "an unknown declaration word names the legal declarations" {
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
    msg, "spec block: `stat` is not a declaration — expected state, struct, enum, protocol or import",
  )
}
