///|
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
  // Removing the source shifts indices above it down by one, so inserting at
  // the raw `target` lands after it when dragging down and before it when
  // dragging up — the direction-derived drop side described above.
  out.insert(@cmp.minimum(target, out.length()), moved)
  out
}

///|
fn dnd_comp() -> @component.Component {
  dn_d_example_component(
    initial={ items: [], query: "", },
    when=w => {
      match w {
        FilterItem =>
          Some((s, _key, value, _iter, _stack) => {
            match value {
              Str(item) => item.contains(s.query)
              _ => true
            }
          })
      }
    },
    update=(s, msg, _ctx) => {
      match DnDExampleMsg::from_dispatch(msg) {
        // args: [@key (the TARGET row's key), dragInfo]
        Some(OnDropOnItem(Num(t), Map(di))) => {
          let target = t.to_int()
          // the SOURCE row's key, read off the drag's captured stack
          let source = match di.get("lookupBind") {
            Some(Fn(lookup)) =>
              match lookup([Null, Str("key")]) {
                Num(n) => n.to_int()
                _ => -1
              }
            _ => -1
          }
          Next({ ..s, items: move_index_to_index(s.items, source, target), })
        }
        Some(OnDropOnItem(_, _)) | Some(Unknown(_, _)) | None => Unhandled
      }
    },
  )
}

///|
pub fn dnd_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="dnd-example", components=[dnd_comp()], examples=[
    {
      component: "DnDExample",
      title: "Default",
      args: { "items": List(items()) },
      view: None,
    },
    {
      component: "DnDExample",
      title: "Pre-filtered",
      args: { "items": List(items()), "query": Str("ones") },
      view: None,
    },
  ])
}
