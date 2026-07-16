// Request/response tests ported from test/transactor.test.js: callback
// responds (sync and stored-for-later), key pinning across a moved selection,
// live_path opt-out, resolved-then-deleted targets, response-name routing,
// unknown-request 404, and completion transfer across the response chain.

///|
priv struct RSheet {
  title : String
}

///|
fn rsheet(title : String) -> &@tutuca.PathNode {
  RSheet::{ title, }
}

///|
impl @tutuca.PathNode for RSheet with fn field(self, name) {
  match name {
    "title" => Some(@tutuca.Value::Str(self.title) as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for RSheet with fn handler(self, bucket, name) {
  ignore(self)
  match (bucket, name) {
    (Response, "load") =>
      Some(
        @tutuca.Handler((args, _ctx) => {
          match args {
            [Str(s), _] => Some(rsheet(s))
            [_, Str(e)] => Some(rsheet("err:\{e}"))
            _ => None
          }
        }),
      )
    (Response, "load-ok") =>
      Some(
        @tutuca.Handler((args, _ctx) => {
          match args {
            [Str(s)] => Some(rsheet("ok:\{s}"))
            _ => None
          }
        }),
      )
    (Response, "load-err") =>
      Some(
        @tutuca.Handler((args, _ctx) => {
          match args {
            [Str(e)] => Some(rsheet("failed:\{e}"))
            _ => None
          }
        }),
      )
    (Receive, "load-sel") =>
      Some(
        @tutuca.Handler((_args, ctx) => {
          ctx.request("load", [], @tutuca.RequestOpts::new())
          None
        }),
      )
    _ => None
  }
}

///|
priv struct RSheets {
  items : Map[String, &@tutuca.PathNode]
}

///|
impl @tutuca.PathNode for RSheets with fn item(self, key) {
  match key {
    KStr(k) => self.items.get(k)
    KInt(_) => None
  }
}

///|
impl @tutuca.PathNode for RSheets with fn with_item(self, key, v) {
  match key {
    KStr(k) =>
      if self.items.contains(k) {
        let items = self.items.copy()
        items[k] = v
        Some(RSheets::{ items, } as &@tutuca.PathNode)
      } else {
        None
      }
    KInt(_) => None
  }
}

///|
priv struct RApp {
  sheets : &@tutuca.PathNode
  sel_id : String
}

///|
impl @tutuca.PathNode for RApp with fn field(self, name) {
  match name {
    "sheets" => Some(self.sheets)
    "selId" => Some(@tutuca.Value::Str(self.sel_id) as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for RApp with fn with_field(self, name, v) {
  match name {
    "sheets" =>
      Some(RApp::{ sheets: v, sel_id: self.sel_id } as &@tutuca.PathNode)
    _ => None
  }
}

///|
impl @tutuca.PathNode for RApp with fn handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "select") =>
      Some(
        @tutuca.Handler((args, _ctx) => {
          match args {
            [Str(id)] =>
              Some(
                RApp::{ sheets: self.sheets, sel_id: id } as &@tutuca.PathNode,
              )
            _ => None
          }
        }),
      )
    (Receive, "clear") =>
      Some(
        @tutuca.Handler((_args, _ctx) => {
          Some(
            RApp::{ sheets: RSheets::{ items: {} }, sel_id: self.sel_id }
            as &@tutuca.PathNode,
          )
        }),
      )
    _ => None
  }
}

///|
/// Registry that STORES respond continuations ("load") so tests complete
/// requests later — the in-flight simulation — and answers "load-now"
/// synchronously.
priv struct TestRequests {
  pending : Array[(Result[@tutuca.Value, @tutuca.Value]) -> Unit]
}

///|
impl @transactor.Requests for TestRequests with fn request_for(
  self,
  _leaf,
  name,
) {
  match name {
    "load" =>
      Some(
        @transactor.RequestHandler((_args, respond) => {
          self.pending.push(respond)
        }),
      )
    "load-now" =>
      Some(
        @transactor.RequestHandler((_args, respond) => {
          respond(Ok(@tutuca.Value::Str("now")))
        }),
      )
    _ => None
  }
}

///|
fn make_rapp(sel_id : String) -> &@tutuca.PathNode {
  RApp::{
    sheets: RSheets::{ items: { "a": rsheet("first"), "b": rsheet("second") } },
    sel_id,
  }
}

///|
fn sel_dispatch() -> @tutuca.DispatchPath {
  @tutuca.DispatchPath::of_steps([
    SeqAccessStep(seq_field="sheets", key_field="selId"),
  ])
}

///|
fn rtitle(root : &@tutuca.PathNode, key : String) -> @tutuca.Value {
  match
    @tutuca.Path::new(steps=[
      SeqStep(field="sheets", key=KStr(key)),
      FieldStep("title"),
    ]).lookup(root) {
    Some(n) => n.as_value().unwrap_or(@tutuca.Value::Null)
    None => @tutuca.Value::Null
  }
}

///|
test "a synchronous respond delivers the response without manual settle" {
  let reqs = TestRequests::{ pending: [] }
  let tx = @transactor.Transactor::new(make_rapp("b"), requests=reqs)
  // the response dispatches under the request name unless routed: send it
  // to the sheet's "load" response handler
  tx.push_request(
    sel_dispatch(),
    "load-now",
    [],
    opts=@tutuca.RequestOpts::new(on_res_name="load"),
  )
  assert_true(rtitle(tx.root, "b") == @tutuca.Value::Str("now"))
}

///|
test "the response lands on the request-time item even if the key moved" {
  let reqs = TestRequests::{ pending: [] }
  let tx = @transactor.Transactor::new(make_rapp("b"), requests=reqs)
  tx.push_request(sel_dispatch(), "load", [])
  // the user switches selection while the request is in flight
  let _ = tx.push_send(@tutuca.DispatchPath::new(), "select", [
    @tutuca.Value::Str("a"),
  ])
  tx.settle()
  reqs.pending[0](Ok(@tutuca.Value::Str("late")))
  assert_true(rtitle(tx.root, "b") == @tutuca.Value::Str("late"))
  assert_true(rtitle(tx.root, "a") == @tutuca.Value::Str("first"))
}

///|
test "live_path re-evaluates the key on response" {
  let reqs = TestRequests::{ pending: [] }
  let tx = @transactor.Transactor::new(make_rapp("b"), requests=reqs)
  tx.push_request(
    sel_dispatch(),
    "load",
    [],
    opts=@tutuca.RequestOpts::new(live_path=true),
  )
  let _ = tx.push_send(@tutuca.DispatchPath::new(), "select", [
    @tutuca.Value::Str("a"),
  ])
  tx.settle()
  reqs.pending[0](Ok(@tutuca.Value::Str("late")))
  assert_true(rtitle(tx.root, "a") == @tutuca.Value::Str("late"))
  assert_true(rtitle(tx.root, "b") == @tutuca.Value::Str("second"))
}

///|
test "a pinned target deleted before the response is a physical no-op" {
  let reqs = TestRequests::{ pending: [] }
  let tx = @transactor.Transactor::new(make_rapp("b"), requests=reqs)
  tx.push_request(sel_dispatch(), "load", [])
  let _ = tx.push_send(@tutuca.DispatchPath::new(), "clear", [])
  tx.settle()
  let after_clear = tx.root
  reqs.pending[0](Ok(@tutuca.Value::Str("late")))
  assert_true(physical_equal(tx.root, after_clear))
}

///|
test "on_ok_name / on_error_name route the response to specific handlers" {
  let reqs = TestRequests::{ pending: [] }
  let tx = @transactor.Transactor::new(make_rapp("b"), requests=reqs)
  tx.push_request(
    sel_dispatch(),
    "load",
    [],
    opts=@tutuca.RequestOpts::new(
      on_ok_name="load-ok",
      on_error_name="load-err",
    ),
  )
  reqs.pending[0](Ok(@tutuca.Value::Str("v1")))
  assert_true(rtitle(tx.root, "b") == @tutuca.Value::Str("ok:v1"))
  tx.push_request(
    sel_dispatch(),
    "load",
    [],
    opts=@tutuca.RequestOpts::new(
      on_ok_name="load-ok",
      on_error_name="load-err",
    ),
  )
  reqs.pending[1](Err(@tutuca.Value::Str("boom")))
  assert_true(rtitle(tx.root, "b") == @tutuca.Value::Str("failed:boom"))
}

///|
test "an unknown request responds with a not-found error" {
  let reqs = TestRequests::{ pending: [] }
  let tx = @transactor.Transactor::new(make_rapp("b"), requests=reqs)
  tx.push_request(
    sel_dispatch(),
    "nope",
    [],
    opts=@tutuca.RequestOpts::new(on_res_name="load"),
  )
  assert_true(
    rtitle(tx.root, "b") == @tutuca.Value::Str("err:Request not found: nope"),
  )
}

///|
test "completion: a parent's subtree stays open until the response settles" {
  let reqs = TestRequests::{ pending: [] }
  let tx = @transactor.Transactor::new(make_rapp("b"), requests=reqs)
  // the sheet's receive handler issues the request from inside its ctx
  let t = tx.push_send(sel_dispatch(), "load-sel", [])
  let settled : Ref[Bool] = { val: false }
  t.completion().on_subtree_settled(() => settled.val = true)
  tx.settle()
  // the handler ran, but its request is still in flight
  assert_false(settled.val)
  reqs.pending[0](Ok(@tutuca.Value::Str("done")))
  assert_true(settled.val)
  assert_true(rtitle(tx.root, "b") == @tutuca.Value::Str("done"))
}
