///|
fn request_example_comp(entry : @component.Component) -> @component.Component {
  request_example_component(
    initial={
      items: [],
      query: "",
      view: "main",
      is_loading: false,
      error: None,
    },
    update=(s, msg, ctx) => {
      match msg {
        // The same intent, dispatched from MoonBit rather than from the block
        // — which is what `IntentOpts` is for. The block's `ask(…, ~route: lex)
        // 'load_data'` gets these three names filled in by the generator, from
        // the schema; writing them here is how a sender names its own.
        Receive("load_another_way", _) => {
          ctx.intent(
            "load_data",
            [],
            @tutuca.IntentOpts::new(
              route=[Lex],
              on_ok_name="load_data_ok",
              on_failed_name="load_data_failed",
              on_unhandled_name="load_data_unhandled",
            ),
          )
          Next({ ..s, is_loading: true, })
        }
        // THREE outcomes, three arms, each with its own shape.
        //
        // There is deliberately no fourth. A combined `[res, err]` payload is
        // one an arm has to tell apart, which is one an arm can read the wrong
        // slot of; no arm here can be handed both.
        Receive("load_data_ok", [res, ..]) =>
          Next(entries_from_response(s, entry, res))
        Receive("load_data_failed", args) => {
          let err = match args {
            [Str(e), ..] => e
            [_, ..] => "the intent failed"
            _ => "the intent failed"
          }
          Next({ ..s, is_loading: false, error: Some(err), })
        }
        // The third outcome, and v2's own: the route ran out and NOBODY
        // answered. Not the same as a handler failing, which is why it has its
        // own name — "nothing claimed it" is not "a rule refused it".
        Receive("load_data_unhandled", _) =>
          Next({
            ..s,
            is_loading: false,
            error: Some("nothing in the scope answers `load_data`"),
          })
        _ => Unhandled
      }
    },
    when=w => {
      match w {
        FilterItem =>
          Some((s, _k, item, _iter, _stack) => {
            contains_text_filter(s.query, item)
          })
      }
    },
  )
}

///|
/// Turn the response payload (a list of {title, description} maps) into Entry
/// components, and clear the loading flag.
fn entries_from_response(
  s : RequestExampleState,
  entry : @component.Component,
  res : @tutuca.Value,
) -> RequestExampleState {
  let items : Array[@tutuca.Value] = match res {
    List(rows) =>
      rows.map(row => {
        match row {
          Map(m) =>
            entry.make({
              "title": m.get("title").unwrap_or(Str("")),
              "description": m.get("description").unwrap_or(Str("")),
            })
          _ => Null
        }
      })
    _ => []
  }
  { ..s, is_loading: false, items, }
}

///|
/// The fixture the tests and the demo use in place of a real fetch. Answers
/// synchronously; a real handler would call `answer` from its network callback.
///
/// A LIST per name, because the `lex` leg walks: a declining handler hands the
/// intent to the next one, and the scope chain can hold several for a name.
fn fixture_request_handlers() -> Map[String, Array[@component.IntentFn]] {
  {
    "load_data": [
      IntentFn((_call, answer) => {
        answer(
          Ok(
            List([
              Map({
                "title": Str("Tutuca"),
                "description": Str("A SPA framework that fits in your head"),
              }),
              Map({
                "title": Str("MoonBit"),
                "description": Str("The language this port is written in"),
              }),
              Map({
                "title": Str("Borges"),
                "description": Str("Wrote the list the other examples iterate"),
              }),
            ]),
          ),
        )
      }),
    ],
  }
}

///|
/// A handler that always fails — proves the failure path and the `on_failed_name`
/// routing.
pub fn failing_request_handlers() -> Map[String, Array[@component.IntentFn]] {
  {
    "load_data": [
      IntentFn((_call, answer) => answer(Failed(Str("network is down")))),
    ],
  }
}

///|
/// A scope that DECLINES — which is what `Pass` is for.
///
/// A handler that MUST respond has no way to decline, so one with nothing to contribute could
/// only invent an error. An `IntentFn` answers `Pass`, the walk goes on, and
/// when the route runs out the sender hears `load_data_unhandled` — which is a
/// different sentence from "it failed" and is what the third arm above draws.
pub fn declining_request_handlers() -> Map[String, Array[@component.IntentFn]] {
  { "load_data": [IntentFn((_call, answer) => answer(Pass))] }
}

///|
pub fn request_module(
  intents? : Map[String, Array[@component.IntentFn]] = fixture_request_handlers(),
) -> @component.ModuleDef {
  let entry = entry_comp()
  @component.ModuleDef::new(
    name="request-example",
    components=[request_example_comp(entry), entry],
    intents~,
    examples=[
      {
        component: "RequestExample",
        title: "Loaded",
        args: Map([]),
        view: None,
      },
      {
        component: "RequestExample",
        title: "Loading",
        args: { "is_loading": Bool(true) },
        view: None,
      },
    ],
  )
}
