// The v2 batch, held in place.
//
// Nothing runs `cases()` yet — the two backends cannot compile a v2 body
// until an adapter picks it up — so this is what stands between a case
// somebody wrote and a case somebody quietly dropped while making the tree
// compile again. It pins the roster and the effect vocabulary, and nothing
// about the ANSWERS, which are the backends' job to reach.

///|
test "the v2 corpus still holds every case it was written with" {
  let names = @conformance.cases().map(c => c.name)
  inspect(
    names.join("\n"),
    content=(
      #|a message answered at home
      #|a message no arm answers produces no successor
      #|a view name and a schema-declared name share one bucket
      #|a bare ask with no legs takes the default route
      #|a bare ask dyn walks the ancestors only
      #|a bare ask lex walks the registered handlers only
      #|a bare ask lex dyn walks the legs in the order written
      #|a bare ask amends the arguments and keeps the name and the route
      #|a handler may run and then ask
      #|a bare value fills a nullable field
      #|null empties one, and is the one literal the wanted type names
      #|an ask with no legs takes the default route
      #|ask dyn is what v1 spelled bubble
      #|ask lex is what v1 spelled request
      #|ask lex dyn reverses the legs
      #|a reply to a message names itself
      #|a reply is an effect like the rest, and buffers with them
      #|effects come out in order, with the state
      #|an intent answered where it arrives
      #|fail answers with an error and ends the walk
      #|a handler that does not reply is an observer
      #|an intent handler may run and then continue the walk
      #|a body may queue two replies, and both come out of it
      #|drop ends the walk before any reply, and answers nothing
      #|a requires that does not hold takes the reply with it
      #|an ensures that does not hold takes the reply with it
      #|an answer arrives as an ordinary message
      #|a failure answer arrives as an ordinary message too
      #|the retired Error spelling still names an arm
      #|a parameter named `s` is the argument, not the state
    ),
  )
}

///|
/// The effect vocabulary, and the routes. A backend reads `kind` and `route`
/// to know what to emit, so a word gained or lost here is a word a backend
/// has to learn — which is a decision, not a typo.
test "the v2 effects use the vocabulary the design gives them" {
  let seen : Map[String, Int] = Map([])
  let routes : Map[String, Int] = Map([])
  for c in @conformance.cases() {
    for e in c.effects {
      seen[e.kind] = seen.get(e.kind).unwrap_or(0) + 1
      if !e.route.is_empty() {
        routes[e.route] = routes.get(e.route).unwrap_or(0) + 1
      }
    }
  }
  fn tally(m : Map[String, Int], order : Array[String]) -> String {
    let out : Array[String] = []
    for k in order {
      out.push("\{k}=\{m.get(k).unwrap_or(0)}")
    }
    // Anything the order does not name is the point of the test.
    for k, v in m {
      if !order.contains(k) {
        out.push("UNEXPECTED \{k}=\{v}")
      }
    }
    out.join(" ")
  }

  inspect(
    tally(seen, ["drop", "fail", "forward", "intent", "reply", "send"]),
    content=(
      #|drop=2 fail=1 forward=7 intent=0 reply=5 send=2 UNEXPECTED ask=5
    ),
  )
  inspect(
    tally(routes, ["dyn", "dyn lex", "lex", "lex dyn"]),
    content="dyn=2 dyn lex=5 lex=3 lex dyn=2",
  )
}

///|
/// The printed form, which two adapters compare against. `ask`, `notify` and
/// `forward` are the ones that carry a route, and this is where the spelling
/// of one is decided rather than in each adapter.
test "a routed effect prints its route between the verb and the name" {
  let by_name : Map[String, @conformance.Case] = Map([])
  for c in @conformance.cases() {
    by_name[c.name] = c
  }
  fn printed(name : String) -> String {
    by_name.get(name).unwrap().effects.map(e => e.printed()).join(" | ")
  }

  inspect(
    printed("an ask with no legs takes the default route"),
    content=(
      #|ask dyn lex saveDraft RStr("ada")
    ),
  )
  inspect(
    printed("ask dyn is what v1 spelled bubble"),
    content="ask dyn picked RNum(3)",
  )
  inspect(
    printed("a bare ask with no legs takes the default route"),
    content="forward dyn lex",
  )
  inspect(
    printed("a bare ask amends the arguments and keeps the name and the route"),
    content="forward dyn lex RStr(\"ada\")",
  )
  inspect(
    printed("drop ends the walk before any reply, and answers nothing"),
    content="drop",
  )
  inspect(
    printed("an intent answered where it arrives"),
    content="reply RNum(1)",
  )
}
