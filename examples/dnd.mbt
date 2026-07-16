// Port of docs/examples/dnd-example.js — reorder a list by dragging.
//
// How a drop knows what was dragged: `dragstart` captures a DragInfo from the
// SOURCE render — the dragged value plus the source's rebuilt stack — so the
// drop handler reads the source row's loop key with
// `dragInfo.lookupBind("key")`, even though the event fires on the TARGET row.
// The `data-dragtype` / `data-droptarget` attributes pair a source with the
// targets that accept it; the app stamps `data-dragging` / `data-draggingover`
// for styling.
//
// PORT DIVERGENCE — drop geometry. JS also takes the raw DOM event and measures
// the pointer against the target's bounding box (`dropWasAbove`) to decide
// whether the row lands above or below the one it was dropped on. MoonBit's
// event layer deliberately does not expose DOM objects as Values (there is no
// `event` / `target` arg; see render/dom_event.mbt), so this port derives the
// side from the drag DIRECTION instead: dragging downward lands after the
// target, upward lands before it. Same reorder, no geometry.

///|
/// Move `source` to sit at `target`, shifting the rest — the list equivalent of
/// dragging a row onto another row.
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
  // Removing the source shifts indices above it down by one, so inserting at
  // the raw `target` lands after it when dragging down and before it when
  // dragging up — the direction-derived drop side described above.
  out.insert(@cmp.minimum(target, out.length()), moved)
  out
}

///|
fn dnd_comp() -> @component.Component {
  @component.component(
    name="DnDExample",
    view=(
      #|<section class="flex flex-col gap-3">
      #|  <input type="search" class="input" :value=".query"
      #|    @on.input="$setQuery value" @on.keydown+cancel="$resetQuery"
      #|    placeholder="Filter entries" />
      #|  <div>
      #|    <div class="cursor-grab row" @each=".items" @when="filterItem"
      #|      draggable="true"
      #|      data-dragtype="my-list-item"
      #|      data-droptarget="my-list-item"
      #|      @on.drop="onDropOnItem @key dragInfo">
      #|      <span class="k" @text="@key"></span>: <x text="@value"></x>
      #|    </div>
      #|  </div>
      #|</section>
    ),
    style=(
      #|[data-dragging="1"] { opacity: 0.5; }
      #|[data-draggingover="my-list-item"] {
      #|  border-top: 2rem solid transparent;
      #|  outline: 1px solid #77777777;
      #|  transition: 0.15s border-top ease;
      #|}
    ),
    fields={
      "items": @component.FieldSpec::of_default(List([])),
      "query": @component.FieldSpec::of_default(Str("")),
    },
    alter={
      "filterItem": (inst, args) => {
        match (inst.get("query"), args) {
          (Str(q), [_key, Str(item), ..]) => Bool(item.contains(q))
          _ => Bool(true)
        }
      },
    },
    input={
      // args: [@key (the TARGET row's key), dragInfo]
      "onDropOnItem": (inst, args, _ctx) => {
        let items = match inst.get("items") {
          List(a) => a
          _ => return None
        }
        let target = match args {
          [Num(t), ..] => t.to_int()
          _ => return None
        }
        // the SOURCE row's key, read off the drag's captured stack
        let source = match args {
          [_, Obj(di), ..] =>
            match di.obj_field("lookupBind") {
              Some(Fn(lookup)) =>
                match lookup([Null, Str("key")]) {
                  Num(s) => s.to_int()
                  _ => -1
                }
              _ => -1
            }
          _ => -1
        }
        Some(
          inst.set("items", List(move_index_to_index(items, source, target))),
        )
      },
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
