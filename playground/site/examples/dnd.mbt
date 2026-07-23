// Drag to reorder a filterable list. `dragstart` captures the source row from
// its render; the drop handler on the TARGET row reads the source's loop key via
// `dragInfo.lookupBind("key")`. data-dragtype/data-droptarget pair a source with
// the targets that accept it. Styled with margaui classes.
//
// The view lives in the View tab (dnd.html): `dnd_example_views()` is its
// compiled tree, and `DnDExampleMsg` types the one `@on` handler it declares,
// argument shapes included.
struct DnDState {
  items : Array[@tutuca.Value]
  query : String
} derive(ToJson, FromJson)

fn build() -> @component.ModuleDef {
  let dnd = @component.component(
    views=dn_d_example_views(),
    name="DnDExample",
    init=DnDState::{ items: [], query: "" },
    when={
      "filterItem": (s : DnDState, _key, item, _iter) => match item {
        Str(text) => text.contains(s.query)
        _ => true
      },
    },
    update=(s : DnDState, msg, _ctx) => match DnDExampleMsg::of_dispatch(msg) {
      // args: [@key (the TARGET row's key), dragInfo]
      Some(OnDropOnItem(Num(t), Obj(di))) => {
        let target = t.to_int()
        let source = match di.obj_field("lookupBind") {
          Some(Fn(lookup)) =>
            match lookup([Null, Str("key")]) {
              Num(n) => n.to_int()
              _ => -1
            }
          _ => -1
        }
        Some({ ..s, items: move_index_to_index(s.items, source, target) })
      }
      Some(OnDropOnItem(_, _)) | Some(Unknown(_, _)) | None => None
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
fn move_index_to_index(
  list : Array[@tutuca.Value],
  source : Int,
  target : Int,
) -> Array[@tutuca.Value] {
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
