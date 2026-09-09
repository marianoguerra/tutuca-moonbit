fn build() -> @component.ModuleDef {
  let dnd = dn_d_example_component(
    initial=DnDExampleState::{ items: [], query: "" },
    when=w => match w {
      FilterItem =>
        Some((s, _key, item, _iter, _stack) => match item {
          Str(text) => text.contains(s.query)
          _ => true
        })
    },
    update=(s, msg, _ctx) => match DnDExampleMsg::from_dispatch(msg) {
      // args: [@key (the TARGET row's key), dragInfo]
      Some(OnDropOnItem(Num(t), Map(di))) => {
        let target = t.to_int()
        let source = match di.get("lookupBind") {
          Some(Fn(lookup)) =>
            match lookup([Null, Str("key")]) {
              Num(n) => n.to_int()
              _ => -1
            }
          _ => -1
        }
        Next({ ..s, items: move_index_to_index(s.items, source, target) })
      }
      Some(OnDropOnItem(_, _)) | Some(Unknown(_, _)) | None => Unhandled
    },
  )
  @component.ModuleDef::new(
    name="dnd-example",
    components=[dnd],
    examples=[
      { component: "DnDExample", title: "Default", args: { "items": List(dnd_items()) }, view: None },
    ],
  )
}

// Move `source` to sit at `target`, shifting the rest.
fn[T] move_index_to_index(
  list : Array[T],
  source : Int,
  target : Int,
) -> Array[T] {
  if source < 0 || target < 0 || source == target || source >= list.length() {
    return list
  }
  let out = list.copy()
  let moved = out.remove(source)
  let at = if target < out.length() { target } else { out.length() }
  out.insert(at, moved)
  out
}

fn dnd_items() -> Array[@tutuca.Value] {
  [
    Str("write the ones"), Str("read the twos"), Str("review the threes"),
    Str("ship the fours"), Str("plan the fives"),
  ]
}
