// Recursive JSON editor: 8 mutually-recursive components (null/bool/string/
// number/array/object + selector + kv), a self-replacing type picker (the
// `swap` bucket), drag-to-reorder. Components look each other up through a
// shared `reg` map filled after all are built.

///|
/// name -> Component, shared by the handlers that construct other component
/// types. Filled once, after every component is built.
struct JsonReg {
  comps : Map[String, @component.Component]
}

///|
fn JsonReg::make_(
  self : JsonReg,
  name : String,
  args? : Map[String, @tutuca.Value] = Map([]),
) -> @tutuca.Value {
  match self.comps.get(name) {
    Some(c) => c.make(args)
    None => Null
  }
}

///|
/// A fresh selector instance (its swap handlers are part of the component).
fn json_make_selector(reg : JsonReg) -> @tutuca.Value {
  reg.make_("JsonSelector")
}

///|
struct JsonEmptyState {} derive(ToJson, FromJson)

///|
fn json_null_comp() -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<span class="text-warning text-xs font-mono p-3 json-null">null</span>
    )),
  },
  name="JsonNull",
  init=JsonEmptyState::{  },
)
}

///|
struct JsonBoolState {
  value : Bool
} derive(ToJson, FromJson)

///|
fn json_bool_comp() -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<button data-bool
      #|  @if.class=".value"
      #|  @then="'btn btn-sm btn-soft btn-success font-mono true'"
      #|  @else="'btn btn-sm btn-soft btn-error font-mono false'"
      #|  @on.click="$toggleValue">
      #|  <span @show=".value">true</span>
      #|  <span @hide=".value">false</span>
      #|</button>
    )),
  },
  name="JsonBool",
  init=JsonBoolState::{ value: true },
)
}

///|
struct JsonStringState {
  value : String
} derive(ToJson, FromJson)

///|
fn json_string_comp() -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<input class="input input-sm input-ghost text-green-500 font-mono json-string" :value=".value" @on.input="$setValue value" />
    )),
  },
  name="JsonString",
  init=JsonStringState::{ value: "hello" },
)
}

///|
struct JsonNumberState {
  strValue : String
  value : Double
} derive(ToJson, FromJson)

///|
fn json_number_comp() -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<input type="number" class="input input-sm input-ghost text-primary font-mono json-number" :title=".value" :value=".strValue" @on.input="$setRawValue value" />
    )),
  },
  name="JsonNumber",
  init=JsonNumberState::{ strValue: "0", value: 0 },
  mutate={
      // keep the raw string always, update the numeric value only when finite
      "setRawValue": (s : JsonNumberState, args) => {
        let raw = match args {
          [Str(t)] => t
          _ => ""
        }
        let parsed : Double? = Some(@string.parse_double(raw)) catch {
          _ => None
        }
        match parsed {
          Some(n) => { strValue: raw, value: n }
          None => { ..s, strValue: raw }
        }
      },
    },
)
}

///|
/// The type picker. Each button swaps the selector for a fresh value of the
/// chosen type — the `swap` bucket answers an Input dispatch with a
/// REPLACEMENT node (an instance of a different component). `isCtrl` on the
/// bool button chooses the initial boolean — the event field reaches the
/// handler as an argument.
fn json_selector_comp(reg : JsonReg) -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<div class="join gap-3 font-mono json-selector">
      #|  <button class="btn btn-sm btn-soft btn-warning to-null" @on.click="$setToNull">null</button>
      #|  <button class="btn btn-sm btn-soft btn-success to-bool" @on.click="$setToBool isCtrl">bool</button>
      #|  <button class="btn btn-sm btn-soft btn-primary to-number" @on.click="$setToNumber">0</button>
      #|  <button class="btn btn-sm btn-soft btn-accent to-string" @on.click="$setToString">""</button>
      #|  <button class="btn btn-sm btn-soft btn-info to-array" @on.click="$setToArray">[]</button>
      #|  <button class="btn btn-sm btn-soft btn-info to-object" @on.click="$setToObject">&#123;&#125;</button>
      #|</div>
    )),
  },
  name="JsonSelector",
  init=JsonEmptyState::{  },
  swap={
      "setToNull": (_s : JsonEmptyState, _args, _ctx) => Some(
        reg.make_("JsonNull"),
      ),
      "setToBool": (_s : JsonEmptyState, args, _ctx) => {
        let is_ctrl = args.get(0) is Some(Bool(true))
        Some(reg.make_("JsonBool", args={ "value": Bool(!is_ctrl) }))
      },
      "setToNumber": (_s : JsonEmptyState, _args, _ctx) => Some(
        reg.make_("JsonNumber"),
      ),
      "setToString": (_s : JsonEmptyState, _args, _ctx) => Some(
        reg.make_("JsonString"),
      ),
      "setToArray": (_s : JsonEmptyState, _args, _ctx) => Some(
        reg.make_("JsonArray"),
      ),
      "setToObject": (_s : JsonEmptyState, _args, _ctx) => Some(
        reg.make_("JsonObject"),
      ),
    },
)
}

///|
/// Move the item currently at `source` to sit just before `target` (JS
/// `List.moveKeyBeforeKey`).
fn move_before(
  list : Array[@tutuca.Value],
  source : Int,
  target : Int,
) -> Array[@tutuca.Value] {
  if source < 0 || target < 0 || source >= list.length() || source == target {
    return list
  }
  let out = list.copy()
  let moved = out.remove(source)
  // after the removal, indices past the source shifted down by one
  let at = if target > source { target - 1 } else { target }
  out.insert(@cmp.minimum(@cmp.maximum(0, at), out.length()), moved)
  out
}

///|
/// A drop handler shared by Array and Object: reorder `items` by moving the
/// dragged row before the drop target. `args` are `[@key, dragInfo]`.
fn json_dropped_items(
  items : Array[@tutuca.Value],
  args : Array[@tutuca.Value],
) -> Array[@tutuca.Value]? {
  let target = match args {
    [Num(t), ..] => t.to_int()
    _ => return None
  }
  let source = match args {
    [_, Obj(di), ..] =>
      match di.obj_field("lookupBind") {
        Some(Fn(lookup)) =>
          match lookup([Null, Str("key")]) {
            Num(sv) => sv.to_int()
            _ => -1
          }
        _ => -1
      }
    _ => -1
  }
  Some(move_before(items, source, target))
}

///|
/// The state shared by JsonArray and JsonObject: just the item list.
struct JsonItemsState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
fn json_array_comp(reg : JsonReg) -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<section class="join join-vertical gap-3 pl-3 border-l-1 border-l-neutral-500 json-array">
      #|  <button class="btn btn-sm btn-soft btn-primary add" @on.click="addItem">+</button>
      #|  <div class="join join-vertical gap-3">
      #|    <div class="join gap-3 justify-between items-center group entry" @each=".items"
      #|      draggable="true"
      #|      data-dragtype="json-list-item" data-droptarget="json-list-item"
      #|      @on.drop="onDropOnItem @key dragInfo">
      #|      <x render-it></x>
      #|      <button class="btn btn-sm btn-soft btn-circle btn-error font-mono opacity-20 group-hover:opacity-100 rm" @on.click="$removeInItemsAt @key">x</button>
      #|    </div>
      #|  </div>
      #|</section>
    ), style=(
      #|[data-draggingover="json-list-item"] {
      #|  border-top: 4rem solid transparent;
      #|  transition: 0.15s border-top ease;
      #|}
    )),
  },
  name="JsonArray",
  init=JsonItemsState::{ items: [] },
  update=(s : JsonItemsState, msg, _ctx) => match msg {
      // add a fresh JsonSelector so the user can pick the new element's type
      Input("addItem", _) => Some({ items: s.items + [json_make_selector(reg)] })
      Input("onDropOnItem", args) =>
        match json_dropped_items(s.items, args) {
          Some(items) => Some({ items, })
          None => None
        }
      _ => None
    },
)
}

///|
struct JsonKvState {
  key : String
  value : @tutuca.Value
} derive(ToJson, FromJson)

///|
fn json_object_kv_comp() -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<div class="join gap-3 items-center justify-center json-kv">
      #|  <input class="input input-sm input-ghost text-green-500 font-mono json-key" :value=".key" @on.input="$setKey value" />
      #|  <span class="text-xs font-mono text-gray-500 colon">:</span>
      #|  <x render=".value"></x>
      #|</div>
    )),
  },
  name="JsonObjectKeyVal",
  init=JsonKvState::{ key: "k", value: Null },
)
}

///|
fn json_object_comp(reg : JsonReg) -> @component.Component {
  @component.component(
  views={
    "main": @anode.View::new("main", raw_view=(
      #|<section class="join join-vertical gap-3 pl-3 border-l-1 border-l-neutral-500 json-object">
      #|  <button class="btn btn-sm btn-soft font-mono btn-primary add" @on.click="addItem">+</button>
      #|  <div class="join join-vertical gap-3">
      #|    <div class="join gap-3 justify-between items-center group entry" @each=".items"
      #|      draggable="true"
      #|      data-dragtype="json-kv-item" data-droptarget="json-kv-item"
      #|      @on.drop="onDropOnItem @key dragInfo">
      #|      <x render-it></x>
      #|      <button class="btn btn-sm btn-soft btn-circle btn-error font-mono opacity-20 group-hover:opacity-100 rm" @on.click="$removeInItemsAt @key">x</button>
      #|    </div>
      #|  </div>
      #|</section>
    ), style=(
      #|[data-draggingover="json-kv-item"] {
      #|  border-top: 4rem solid transparent;
      #|  transition: 0.15s border-top ease;
      #|}
    )),
  },
  name="JsonObject",
  init=JsonItemsState::{ items: [] },
  update=(s : JsonItemsState, msg, _ctx) => match msg {
      // a key/value row whose value is a fresh selector
      Input("addItem", _) => {
        let row = match reg.comps.get("JsonObjectKeyVal") {
          Some(kv) => kv.make({ "value": json_make_selector(reg) })
          None => Null
        }
        Some({ items: s.items + [row] })
      }
      Input("onDropOnItem", args) =>
        match json_dropped_items(s.items, args) {
          Some(items) => Some({ items, })
          None => None
        }
      _ => None
    },
)
}

///|
pub fn json_module() -> @component.ModuleDef {
  let reg = JsonReg::{ comps: Map([]) }
  let null = json_null_comp()
  let bool_ = json_bool_comp()
  let string = json_string_comp()
  let number = json_number_comp()
  let array = json_array_comp(reg)
  let kv = json_object_kv_comp()
  let object = json_object_comp(reg)
  reg.comps["JsonNull"] = null
  reg.comps["JsonBool"] = bool_
  reg.comps["JsonString"] = string
  reg.comps["JsonNumber"] = number
  reg.comps["JsonArray"] = array
  reg.comps["JsonObjectKeyVal"] = kv
  reg.comps["JsonObject"] = object
  let selector = json_selector_comp(reg)
  reg.comps["JsonSelector"] = selector
  @component.ModuleDef::new(
    name="json",
    components=[selector, null, bool_, string, number, array, kv, object],
    examples=[
      {
        component: "JsonArray",
        title: "Empty Array With Selector",
        args: { "items": List([json_make_selector(reg)]) },
        view: None,
      },
      { component: "JsonObject", title: "Object", args: Map([]), view: None },
      {
        component: "JsonSelector",
        title: "Type Selector",
        args: Map([]),
        view: None,
      },
      {
        component: "JsonString",
        title: "String Value",
        args: { "value": Str("tutuca") },
        view: None,
      },
      {
        component: "JsonBool",
        title: "Boolean True",
        args: { "value": Bool(true) },
        view: None,
      },
      {
        component: "JsonNumber",
        title: "Number",
        args: { "value": Num(42), "strValue": Str("42") },
        view: None,
      },
    ],
  )
}

///|
fn build() -> @component.ModuleDef {
  json_module()
}
