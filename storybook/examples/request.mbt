// Port of docs/examples/request-example.js — async requests.
//
// TWO PORT NOTES.
//
// 1. Lifecycle. Tutuca has NO lifecycle: nothing in the framework calls
//    `receive.init`. The host dispatches it — JS does `app.start();
//    app.sendAtRoot("init", [])`, and this port adds the same hook,
//    `App::send_at_root` (app/loop.mbt). `init` is an ordinary receive handler.
//
// 2. Requests are CALLBACK-style here, not async/await. A RequestFn is
//    `(args, respond) -> Unit`; it calls `respond(Ok(v))` or `respond(Err(e))`
//    whenever it is done — immediately, or from a real fetch's callback. The
//    component side is unchanged: `ctx.request("loadData", [])` fires it, and
//    the `response` bucket receives the result.
//
// Because the request handler is registered OUTSIDE the component, the same
// component can be driven by a real fetch in production and by a fixture in a
// test — which is exactly what the tests here do.

///|
priv struct RequestExampleState {
  items : Array[@tutuca.Value]
  query : String
  view : String
  isLoading : Bool
  error : @tutuca.Value
} derive(ToJson, FromJson)

///|
fn request_example_comp(entry : @component.Component) -> @component.Component {
  @component.component(
    name="RequestExample",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <div class="alert alert-info alert-outline loading" @show=".isLoading">Loading</div>
      #|  <div class="flex justify-between" @hide=".isLoading">
      #|    <input type="search" class="input" :value=".query"
      #|      @on.input="$setQuery value" @on.keydown+cancel="$resetQuery"
      #|      placeholder="Filter entries" />
      #|    <button class="btn bnt-sm btn-primary btn-outline another" @on.click="loadAnotherWay">Load Another Way</button>
      #|    <button class="btn bnt-sm btn-primary toggle-btn" @text=".view" @on.click="$toggleView"></button>
      #|  </div>
      #|  <div class="flex flex-col gap-3 max-h-[40vh] overflow-y-auto pr-3 rows" @hide=".isLoading" @push-view=".view">
      #|    <x render-each=".items" @when="filterItem"></x>
      #|  </div>
      #|  <div class="error" @show="truthy? .error"><x text=".error"></x></div>
      #|</section>
    ),
    init=RequestExampleState::{
      items: [],
      query: "",
      view: "main",
      isLoading: false,
      error: Null,
    },
    mutate={
      "toggleView": (s : RequestExampleState, _args) => {
        ..s,
        view: if s.view == "main" {
          "edit"
        } else {
          "main"
        },
      },
    },
    update=(s : RequestExampleState, msg, ctx) => {
      match msg {
        // the host dispatches this after start() — see App::send_at_root
        Receive("init", _) => {
          ctx.request("loadData", [], @tutuca.RequestOpts::new())
          Some({ ..s, isLoading: true })
        }
        // the same request, routed to DIFFERENT response handlers by name
        Input("loadAnotherWay", _) => {
          ctx.request(
            "loadData",
            [],
            @tutuca.RequestOpts::new(
              on_ok_name="loadDataOk",
              on_error_name="loadDataErr",
            ),
          )
          Some({ ..s, isLoading: true })
        }
        // the default response handler gets BOTH the result and the error
        Response("loadData", [res, _err]) =>
          Some(entries_from_response(s, entry, res))
        Response("loadDataOk", [res, ..]) =>
          Some(entries_from_response(s, entry, res))
        Response("loadDataErr", args) => {
          let err = match args {
            [Str(e), ..] => e
            [_, ..] => "request failed"
            _ => "request failed"
          }
          Some({ ..s, isLoading: false, error: Str(err) })
        }
        _ => None
      }
    },
    when={
      "filterItem": (s : RequestExampleState, _k, item, _iter) => {
        contains_text_filter(s.query, item)
      },
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
/// The fixture the tests and the demo use in place of a real fetch. Responds
/// synchronously; a real handler would call `respond` from its network callback.
fn fixture_request_handlers() -> Map[String, @component.RequestFn] {
  {
    "loadData": RequestFn((_args, respond) => {
      respond(
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
  }
}

///|
/// A handler that always fails — proves the error path and the onErrorName
/// routing.
pub fn failing_request_handlers() -> Map[String, @component.RequestFn] {
  {
    "loadData": RequestFn((_args, respond) => {
      respond(Err(Str("network is down")))
    }),
  }
}

///|
pub fn request_module(
  requests? : Map[String, @component.RequestFn] = fixture_request_handlers(),
) -> @component.ModuleDef {
  let entry = entry_comp()
  @component.ModuleDef::new(
    name="request-example",
    components=[request_example_comp(entry), entry],
    requests~,
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
