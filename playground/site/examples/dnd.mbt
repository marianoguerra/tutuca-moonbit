// Drag to reorder a filterable list. `dragstart` captures the source row from
// its render; the drop handler on the TARGET row reads the source's loop key via
// `dragInfo.lookupBind("key")`. data-dragtype/data-droptarget pair a source with
// the targets that accept it. Styled with margaui classes.
fn build() -> @component.ModuleDef {
  let dnd = @component.component(
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
      "filterItem": (inst, args) => match (inst.get("query"), args) {
        (Str(q), [_key, Str(item), ..]) => Bool(item.contains(q))
        _ => Bool(true)
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
        Some(inst.set("items", List(move_index_to_index(items, source, target))))
      },
    },
  )
  @component.ModuleDef::new(
    name="dnd-example", components=[dnd],
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
