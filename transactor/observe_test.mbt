// Observer tests: one
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
impl @tutuca.Obj for OSheet with fn field(self, name) {
  match name {
    "title" => Some(Str(self.title))
    _ => None
  }
}

///|
impl @tutuca.Obj for OSheet with fn handler(self, bucket, name) {
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
          ctx.intent("poked", [], @tutuca.IntentOpts::new(route=[Dyn]))
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
impl @tutuca.Obj for ORoot with fn field(self, name) {
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
impl @tutuca.Obj for ORoot with fn with_field(self, name, v) {
  match name {
    "sheets" => Some(Obj(ORoot::{ sheets: v, sel_id: self.sel_id, }))
    _ => None
  }
}

///|
priv struct OSheets {
  items : Map[String, @tutuca.Value]
}

///|
impl @tutuca.Obj for OSheets with fn item(self, key) {
  match key {
    KStr(k) => self.items.get(k)
    KInt(_) => None
  }
}

///|
impl @tutuca.Obj for OSheets with fn with_item(self, key, v) {
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
  let root : @tutuca.Value = Map({ "sheet": Obj(OSheet::{ title: "a", }) })
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
  assert_true(r0.bucket is Receive)
  assert_false(r0.is_answer)
  assert_eq(r0.name, "rename")
  assert_true(r0.matched is Exact)
  assert_true(r0.before is Some(Obj(_)))
  assert_true(r0.after is Some(Obj(_)))
  assert_true(r0.path_keys is [{ field: "sheet", key: None, }])
  let r1 = records[1]
  assert_true(r1.matched is NoHandler) // nothing registers that name
  assert_true(r1.seq > r0.seq)
}

///|
test "observe: bubble chains emit one record per hop; skipSelf emits none" {
  let root : @tutuca.Value = Map({ "sheet": Obj(OSheet::{ title: "a", }) })
  let node : @tutuca.Value = root
  let tx = @transactor.Transactor::new(node)
  let kinds : Array[String] = []
  let names : Array[String] = []
  let _un = tx.observe(r => {
    kinds.push(r.kind_label())
    names.push(r.name)
  })
  let p = @tutuca.DispatchPath::of_steps([FieldStep("sheet")])
  let _ = tx.push_send(p, "poke-up", [])
  tx.settle() |> ignore
  // the receive that raised the intent, then one Intent hop at the root: the
  // `dyn` leg starts at the sender's PARENT, so the sender is not offered its
  // own intent and emits no hop of its own.
  assert_eq(kinds, ["receive", "intent"])
  assert_true(names is ["poke-up", "poked"])
}

///|
test "on_drained fires once per outermost settle that did work" {
  let root : @tutuca.Value = Map({ "sheet": Obj(OSheet::{ title: "a", }) })
  let node : @tutuca.Value = root
  let tx = @transactor.Transactor::new(node)
  let drains : Ref[Int] = { val: 0, }
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
impl @tutuca.Obj for DSheet with fn schema(_self) {
  @tutuca.SchemaInfo::new(name="DSheet", fingerprint="dsheet", fields=[
    @tutuca.FieldInfo::new("title", TyText),
  ])
  |> Some
}

///|
impl @tutuca.Obj for DSheet with fn field(self, name) {
  match name {
    "title" => Some(Str(self.title))
    _ => None
  }
}

///|
impl @tutuca.Obj for DSheet with fn handler(_self, bucket, name) {
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
  let root : @tutuca.Value = Map({ "sheet": Obj(DSheet::{ title: "a", }) })
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
      #|{"origin":"host","kind":"receive","name":"rename","matched":"exact","path":"sheet","pathKeys":[{"f":"sheet"}],"seq":1,"args":["b"],"before":{"title":"a"},"after":{"title":"b"}}
    ),
  )
  // A handler that answered nothing has NO `after` key — absent, not null,
  // which is the distinction the whole no-op path turns on.
  let miss = records[1].to_json().stringify()
  assert_true(miss.contains("\"matched\":\"none\""))
  assert_false(miss.contains("\"after\""))
}
