// The v2 batch, held in place.
//
// Nothing runs `cases_v2()` yet — the two backends cannot compile a v2 body
// until the plan's tasks 10 and 11 — so this is what stands between a case
// somebody wrote and a case somebody quietly dropped while making the tree
// compile again. It pins the roster and the effect vocabulary, and nothing
// about the ANSWERS, which are the backends' job to reach.

///|
test "the v2 corpus still holds every case it was written with" {
  let names = @conformance.cases_v2().map(c => c.name)
  inspect(
    names.join("\n"),
    content=(
      #|a message answered at home
      #|a message no arm answers produces no successor
      #|a view name and a schema-declared name share one bucket
      #|forward with no legs takes the default route
      #|forward dyn walks the ancestors only
      #|forward lex walks the registered handlers only
      #|forward lex dyn walks the legs in the order written
      #|forward amends the arguments and keeps the name and the route
      #|a handler may run and then forward
      #|an intent with no legs takes the default route
      #|intent dyn is what v1 spelled bubble
      #|intent lex is what v1 spelled request
      #|intent lex dyn reverses the legs
      #|effects come out in order, with the state
      #|an intent answered where it arrives
      #|fail answers with an error and ends the walk
      #|a handler that does not reply is an observer
      #|an intent handler may run and then continue the walk
      #|a body may queue two replies, and both come out of it
      #|stop ends the walk before any reply, and answers nothing
      #|a requires that does not hold takes the reply with it
      #|an ensures that does not hold takes the reply with it
      #|an answer arrives as an ordinary message
      #|an error answer arrives as an ordinary message too
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
  for c in @conformance.cases_v2() {
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
    tally(seen, ["fail", "forward", "intent", "reply", "send", "stop"]),
    content="fail=1 forward=7 intent=5 reply=3 send=1 stop=2",
  )
  inspect(
    tally(routes, ["dyn", "dyn lex", "lex", "lex dyn"]),
    content="dyn=2 dyn lex=5 lex=3 lex dyn=2",
  )
}

///|
/// The printed form, which two adapters compare against. `intent` and
/// `forward` are the two that carry a route, and this is where the spelling of
/// one is decided rather than in each adapter.
test "a routed effect prints its route between the verb and the name" {
  let by_name : Map[String, @conformance.V2Case] = Map([])
  for c in @conformance.cases_v2() {
    by_name[c.name] = c
  }
  fn printed(name : String) -> String {
    by_name.get(name).unwrap().effects.map(e => e.printed()).join(" | ")
  }

  inspect(
    printed("an intent with no legs takes the default route"),
    content="intent dyn lex saveDraft RStr(\"ada\")",
  )
  inspect(
    printed("intent dyn is what v1 spelled bubble"),
    content="intent dyn picked RNum(3)",
  )
  inspect(
    printed("forward with no legs takes the default route"),
    content="forward dyn lex",
  )
  inspect(
    printed("forward amends the arguments and keeps the name and the route"),
    content="forward dyn lex RStr(\"ada\")",
  )
  inspect(
    printed("stop ends the walk before any reply, and answers nothing"),
    content="stop",
  )
  inspect(
    printed("an intent answered where it arrives"),
    content="reply RNum(1)",
  )
}
