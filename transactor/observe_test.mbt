// Observer tests (ports of the transactor.test.js observe section): one
// normalized record per handler invocation, pinned path keys, matched
// classification, bubble-chain visibility, request records, unsubscribe.

///|
priv struct OSheet {
  title : String
}

///|
fn osheet(title : String) -> @tutuca.Value {
  (Obj(OSheet::{ title, }) : @tutuca.Value)
}

///|
impl @tutuca.Obj for OSheet with fn obj_field(self, name) {
  match name {
    "title" => Some(Str(self.title))
    _ => None
  }
}

///|
impl @tutuca.Obj for OSheet with fn obj_handler(self, bucket, name) {
  match (bucket, name) {
    (Receive, "rename") =>
      Some(
        Handler((args, _ctx) => {
          match args {
            [Str(s)] => Some(osheet(s))
            _ => None
          }
        }),
      )
    (Receive, "catch-all") =>
      Some(Handler((_args, _ctx) => Some(osheet("\{self.title}?"))))
    (Receive, "poke-up") =>
      Some(
        Handler((_args, ctx) => {
          ctx.bubble("poked", [])
          None
        }),
      )
    _ => None
  }
}

///|
priv struct ORoot {
  sheets : @tutuca.Value // an OSheets box
  sel_id : String
}

///|
impl @tutuca.Obj for ORoot with fn obj_field(self, name) {
  match name {
    "selId" => {
      let v : @tutuca.Value = Str(self.sel_id)
      Some(v)
    }
    "sheets" => Some(self.sheets)
    _ => None
  }
}

///|
impl @tutuca.Obj for ORoot with fn obj_with_field(self, name, v) {
  match name {
    "sheets" => Some(Obj(ORoot::{ sheets: v, sel_id: self.sel_id }))
    _ => None
  }
}

///|
priv struct OSheets {
  items : Map[String, @tutuca.Value]
}

///|
impl @tutuca.Obj for OSheets with fn obj_item(self, key) {
  match key {
    KStr(k) => self.items.get(k)
    KInt(_) => None
  }
}

///|
impl @tutuca.Obj for OSheets with fn obj_with_item(self, key, v) {
  match key {
    KStr(k) => {
      let items = self.items.copy()
      items[k] = v
      Some(Obj(OSheets::{ items, }))
    }
    KInt(_) => None
  }
}

///|
test "observe: send records carry kind, matched, before/after and pinned keys" {
  let root : @tutuca.Value = Map({ "sheet": Obj(OSheet::{ title: "a" }) })
  let node : @tutuca.Value = root
  let tx = @transactor.Transactor::new(node)
  let records : Array[@transactor.ObserveRecord] = []
  let _un = tx.observe(r => records.push(r))
  let p = @tutuca.DispatchPath::of_steps([FieldStep("sheet")])
  let _ = tx.push_send(p, "rename", [Str("b")])
  let _ = tx.push_send(p, "no-such", [])
  tx.settle() |> ignore
  assert_eq(records.length(), 2)
  let r0 = records[0]
  assert_true(r0.kind is Receive)
  assert_eq(r0.name, "rename")
  assert_true(r0.matched is Exact)
  assert_true(r0.before is Some(Obj(_)))
  assert_true(r0.after is Some(Obj(_)))
  assert_true(r0.path_keys is [{ field: "sheet", key: None }])
  let r1 = records[1]
  assert_true(r1.matched is NoHandler) // nothing registers that name
  assert_true(r1.seq > r0.seq)
}

///|
test "observe: bubble chains emit one record per hop; skipSelf emits none" {
  let root : @tutuca.Value = Map({ "sheet": Obj(OSheet::{ title: "a" }) })
  let node : @tutuca.Value = root
  let tx = @transactor.Transactor::new(node)
  let kinds : Array[@transactor.ObserveKind] = []
  let names : Array[String] = []
  let _un = tx.observe(r => {
    kinds.push(r.kind)
    names.push(r.name)
  })
  let p = @tutuca.DispatchPath::of_steps([FieldStep("sheet")])
  let _ = tx.push_send(p, "poke-up", [])
  tx.settle() |> ignore
  // the receive that bubbled + one Bubble hop at the root (the skipSelf
  // first hop of ctx.bubble emits nothing)
  assert_true(kinds is [Receive, Bubble])
  assert_true(names is ["poke-up", "poked"])
}

///|
test "observe: request records pin live keys; unsubscribe stops delivery" {
  let sheets : @tutuca.Value = Obj(OSheets::{
    items: { "a": osheet("first"), "b": osheet("second") },
  })
  let node : @tutuca.Value = Obj(ORoot::{ sheets, sel_id: "b" })
  let tx = @transactor.Transactor::new(node)
  let records : Array[@transactor.ObserveRecord] = []
  let un = tx.observe(r => records.push(r))
  tx.push_request(
    @tutuca.DispatchPath::of_steps([
      SeqAccessStep(seq_field="sheets", key_field="selId"),
    ]),
    "load",
    [],
  )
  // the request record (NoHandler: no registry) with the key pinned to "b"
  guard records is [req, ..] else { fail("no request record") }
  assert_true(req.kind is Request)
  assert_true(req.matched is NoHandler)
  assert_true(req.path_keys is [{ field: "sheets", key: Some(KStr("b")) }])
  let seen = records.length()
  un()
  let _ = tx.push_send(
    @tutuca.DispatchPath::of_steps([FieldStep("sheet")]),
    "rename",
    [Str("x")],
  )
  tx.settle() |> ignore
  assert_eq(records.length(), seen) // unsubscribed: nothing new
}

///|
test "on_drained fires once per outermost settle that did work" {
  let root : @tutuca.Value = Map({ "sheet": Obj(OSheet::{ title: "a" }) })
  let node : @tutuca.Value = root
  let tx = @transactor.Transactor::new(node)
  let drains : Ref[Int] = { val: 0 }
  tx.on_drained(() => drains.val = drains.val + 1)
  // empty settle: no work, no callback
  tx.settle() |> ignore
  assert_eq(drains.val, 0)
  // a bubbling cascade drains in ONE outer settle -> one callback
  let p = @tutuca.DispatchPath::of_steps([FieldStep("sheet")])
  let _ = tx.push_send(p, "poke-up", [])
  tx.settle() |> ignore
  assert_eq(drains.val, 1)
  // two separate drains -> two callbacks
  let _ = tx.push_send(p, "rename", [Str("b")])
  tx.settle() |> ignore
  assert_eq(drains.val, 2)
}

///|
/// A described instance, so `before`/`after` have a JSON form. `OSheet` above
/// declares nothing on purpose — it is the older fixture, and what it pins is
/// that a record still SERIALIZES when its leaf cannot.
priv struct DSheet {
  title : String
}

///|
fn dsheet(title : String) -> @tutuca.Value {
  (Obj(DSheet::{ title, }) : @tutuca.Value)
}

///|
impl @tutuca.Obj for DSheet with fn obj_schema(_self) {
  @tutuca.SchemaInfo::new(name="DSheet", fingerprint="dsheet", fields=[
    @tutuca.FieldInfo::new("title", TyText),
  ])
  |> Some
}

///|
impl @tutuca.Obj for DSheet with fn obj_field(self, name) {
  match name {
    "title" => Some(Str(self.title))
    _ => None
  }
}

///|
impl @tutuca.Obj for DSheet with fn obj_handler(_self, bucket, name) {
  match (bucket, name) {
    (Receive, "rename") =>
      Some(
        Handler((args, _ctx) => {
          match args {
            [Str(s)] => Some(dsheet(s))
            _ => None
          }
        }),
      )
    _ => None
  }
}

///|
/// A record as JSON — the shape a devtools panel reads.
///
/// This is what could not be written before: `before` and `after` are the leaf
/// the handler read and returned, which for every component in the tree is an
/// instance, and an instance flattened to `null`. The record serialized to
/// everything EXCEPT the state change it exists to describe.
test "observe: a record serializes, state change and all" {
  let root : @tutuca.Value = Map({ "sheet": Obj(DSheet::{ title: "a" }) })
  let tx = @transactor.Transactor::new(root)
  let records : Array[@transactor.ObserveRecord] = []
  let _un = tx.observe(r => records.push(r))
  let p = @tutuca.DispatchPath::of_steps([FieldStep("sheet")])
  let _ = tx.push_send(p, "rename", [Str("b")])
  let _ = tx.push_send(p, "no-such", [])
  tx.settle() |> ignore
  inspect(
    records[0].to_json().stringify(),
    content=(
      #|{"kind":"receive","name":"rename","matched":"exact","path":"sheet","seq":1,"args":["b"],"before":{"title":"a"},"after":{"title":"b"}}
    ),
  )
  // A handler that answered nothing has NO `after` key — absent, not null,
  // which is the distinction the whole no-op path turns on.
  let miss = records[1].to_json().stringify()
  assert_true(miss.contains("\"matched\":\"none\""))
  assert_false(miss.contains("\"after\""))
}
