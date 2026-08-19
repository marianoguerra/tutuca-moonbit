// Port of docs/examples/request-example.js — async requests.
//
// TWO PORT NOTES.
//
// 1. Lifecycle. Tutuca has NO lifecycle: nothing in the framework calls
//    `receive.init`. The host dispatches it — JS does `app.start();
//    app.sendAtRoot("init", [])`, and this port adds the same hook,
//    `App::send_at_root` (app/loop.mbt). `init` is an ordinary receive handler.
//
// 2. Intents on the `lex` leg are CALLBACK-style here, not async/await. An
//    IntentFn is `(call, answer) -> Unit`; it calls `answer(Ok(v))`,
//    `answer(Failed(e))` or `answer(Pass)` whenever it is done — immediately,
//    or from a real fetch's callback. `Pass` is the one v1 could not say: a
//    handler with nothing to contribute DECLINES, and the walk goes on to the
//    next one instead of it having to invent an error.
//
//    The component side dispatches `intent lex 'loadData'`, and the answer
//    arrives as an ordinary message — `loadDataOk`, `loadDataError` or
//    `loadDataUnhandled` — in the same `receive` bucket everything else lands
//    in. A handler cannot tell an answer from a message a parent sent, and
//    does not need to.
//
// Because the request handler is registered OUTSIDE the component, the same
// component can be driven by a real fetch in production and by a fixture in a
// test — which is exactly what the tests here do.

///|
/// `init` and `toggleView` are in the view file's
/// `<script type="tutuca/script">` block: `intent` is one of the effects that
/// language spells, and the block queues it so it goes out only if the whole
/// transition finished. What is left here is the half a small language would
/// model badly — an intent's OPTIONS, and the answers, which unpack a result
/// into entries.
fn request_example_comp(entry : @component.Component) -> @component.Component {
  request_example_component(
    init={ items: [], query: "", view: "main", isLoading: false, error: Null },
    update=(s, msg, ctx) => {
      match msg {
        // The same intent, dispatched from MoonBit rather than from the block
        // — which is what `IntentOpts` is for. The block's `intent lex
        // 'loadData'` gets these three names filled in by the generator, from
        // the schema; writing them here is how a sender names its own.
        Receive("loadAnotherWay", _) => {
          ctx.intent(
            "loadData",
            [],
            @tutuca.IntentOpts::new(
              route=[Lex],
              on_ok_name="loadDataOk",
              on_error_name="loadDataError",
              on_unhandled_name="loadDataUnhandled",
            ),
          )
          Next({ ..s, isLoading: true })
        }
        // THREE outcomes, three arms, each with its own shape.
        //
        // v1 had a fourth: a combined `[res, err]` payload that the default
        // arm received and a split arm read the wrong slot of. It is gone, and
        // so is the bug — there is no arm here that can be handed both.
        Receive("loadDataOk", [res, ..]) =>
          Next(entries_from_response(s, entry, res))
        Receive("loadDataError", args) => {
          let err = match args {
            [Str(e), ..] => e
            [_, ..] => "the intent failed"
            _ => "the intent failed"
          }
          Next({ ..s, isLoading: false, error: Str(err) })
        }
        // The third outcome, and v2's own: the route ran out and NOBODY
        // answered. Not the same as a handler failing, which is why it has its
        // own name — "nothing claimed it" is not "a rule refused it".
        Receive("loadDataUnhandled", _) =>
          Next({
            ..s,
            isLoading: false,
            error: Str("nothing in the scope answers `loadData`"),
          })
        _ => Unhandled
      }
    },
    when=w => {
      match w {
        FilterItem =>
          Some((s, _k, item, _iter) => contains_text_filter(s.query, item))
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
  { ..s, isLoading: false, items }
}

///|
/// The fixture the tests and the demo use in place of a real fetch. Answers
/// synchronously; a real handler would call `answer` from its network callback.
///
/// A LIST per name, because the `lex` leg walks: a declining handler hands the
/// intent to the next one, and the scope chain can hold several for a name.
fn fixture_request_handlers() -> Map[String, Array[@component.IntentFn]] {
  {
    "loadData": [
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
/// A handler that always fails — proves the error path and the `on_error_name`
/// routing.
pub fn failing_request_handlers() -> Map[String, Array[@component.IntentFn]] {
  {
    "loadData": [
      IntentFn((_call, answer) => answer(Failed(Str("network is down")))),
    ],
  }
}

///|
/// A scope that DECLINES — the answer v1 had no word for.
///
/// A `RequestFn` had to respond, so a handler with nothing to contribute could
/// only invent an error. An `IntentFn` answers `Pass`, the walk goes on, and
/// when the route runs out the sender hears `loadDataUnhandled` — which is a
/// different sentence from "it failed" and is what the third arm above draws.
pub fn declining_request_handlers() -> Map[String, Array[@component.IntentFn]] {
  { "loadData": [IntentFn((_call, answer) => answer(Pass))] }
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
        args: { "isLoading": Bool(true) },
        view: None,
      },
    ],
  )
}
