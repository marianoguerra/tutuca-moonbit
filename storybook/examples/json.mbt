// Port of docs/examples/json.js — a composable JSON editor built from typed
// primitives (null/bool/string/number/array/object), 8 mutually-recursive
// components.
//
// TWO PORT PATTERNS worth calling out:
//
// 1. Self-replacement. In JS a JsonSelector's `setTo(Comp)` returns
//    `Comp.make()` — a fresh instance of a DIFFERENT component type, which the
//    framework swaps in where the selector was. That works unchanged here: a
//    handler returns a Value, and an instance of any component is a Value.
//
// 2. The component-as-argument problem (as in todo.js), but sharper: a selector
//    must build SIX different component types, and Array/Object build each other
//    and the selector — mutual recursion that a capture-at-definition closure
//    can't express. The fix is a `reg` map of name -> Component, populated AFTER
//    all components are built; the handlers close over `reg` and look their
//    target up at dispatch time. This mirrors what the scope does, using only
//    public API.

///|
/// name -> Component, shared by the handlers that construct other component
/// types. Filled once, after every component is built.
priv struct JsonReg {
  comps : Map[String, @component.Component]
}

///|
fn JsonReg::make_(
  self : JsonReg,
  name : String,
  args? : Map[String, @tutuca.Value] = Map([]),
) -> @tutuca.Value {
  match self.comps.get(name) {
    Some(c) => c.make(args).to_value()
    None => Null
  }
}

///|
fn json_null_comp() -> @component.Component {
  @component.component(
    name="JsonNull",
    view=(
      #|<span class="text-warning text-xs font-mono p-3 json-null">null</span>
    ),
  )
}

///|
fn json_bool_comp() -> @component.Component {
  @component.component(
    name="JsonBool",
    // NOTE: @if.class OVERWRITES the class attribute, so a static class here
    // would be clobbered — the stable test hook is `data-bool` instead.
    view=(
      #|<button data-bool
      #|  @if.class=".value"
      #|  @then="'btn btn-sm btn-soft btn-success font-mono true'"
      #|  @else="'btn btn-sm btn-soft btn-error font-mono false'"
      #|  @on.click="$toggleValue">
      #|  <span @show=".value">true</span>
      #|  <span @hide=".value">false</span>
      #|</button>
    ),
    fields={ "value": @component.FieldSpec::of_default(Bool(true)) },
  )
}

///|
fn json_string_comp() -> @component.Component {
  @component.component(
    name="JsonString",
    view=(
      #|<input class="input input-sm input-ghost text-green-500 font-mono json-string" :value=".value" @on.input="$setValue value" />
    ),
    fields={ "value": @component.FieldSpec::of_default(Str("hello")) },
  )
}

///|
fn json_number_comp() -> @component.Component {
  @component.component(
    name="JsonNumber",
    view=(
      #|<input type="number" class="input input-sm input-ghost text-primary font-mono json-number" :title=".value" :value=".strValue" @on.input="$setRawValue value" />
    ),
    fields={
      "strValue": @component.FieldSpec::of_default(Str("0")),
      "value": @component.FieldSpec::of_default(Num(0)),
    },
    methods={
      // keep the raw string always, update the numeric value only when finite
      "setRawValue": (inst, args) => {
        let raw = match args {
          [Str(s)] => s
          _ => ""
        }
        let parsed : Double? = Some(@string.parse_double(raw)) catch {
          _ => None
        }
        match parsed {
          Some(n) =>
            inst.set("value", Num(n)).set("strValue", Str(raw)).to_value()
          None => inst.set("strValue", Str(raw)).to_value()
        }
      },
    },
  )
}

///|
/// The type picker. Each button swaps the selector for a fresh value of the
/// chosen type (self-replacement). `isCtrl` on the bool button chooses the
/// initial boolean — the event field reaches the method as an argument.
fn json_selector_comp(reg : JsonReg) -> @component.Component {
  @component.component(
    name="JsonSelector",
    view=(
      #|<div class="join gap-3 font-mono json-selector">
      #|  <button class="btn btn-sm btn-soft btn-warning to-null" @on.click="$setToNull">null</button>
      #|  <button class="btn btn-sm btn-soft btn-success to-bool" @on.click="$setToBool isCtrl">bool</button>
      #|  <button class="btn btn-sm btn-soft btn-primary to-number" @on.click="$setToNumber">0</button>
      #|  <button class="btn btn-sm btn-soft btn-accent to-string" @on.click="$setToString">""</button>
      #|  <button class="btn btn-sm btn-soft btn-info to-array" @on.click="$setToArray">[]</button>
      #|  <button class="btn btn-sm btn-soft btn-info to-object" @on.click="$setToObject">&#123;&#125;</button>
      #|</div>
    ),
    methods={
      "setToNull": (_inst, _args) => reg.make_("JsonNull"),
      "setToBool": (_inst, args) => {
        let is_ctrl = args.get(0) is Some(Bool(true))
        reg.make_("JsonBool", args={ "value": Bool(!is_ctrl) })
      },
      "setToNumber": (_inst, _args) => reg.make_("JsonNumber"),
      "setToString": (_inst, _args) => reg.make_("JsonString"),
      "setToArray": (_inst, _args) => reg.make_("JsonArray"),
      "setToObject": (_inst, _args) => reg.make_("JsonObject"),
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
fn json_drop_handler(
  inst : @component.Instance,
  args : Array[@tutuca.Value],
) -> @component.Instance? {
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
  Some(inst.set("items", List(move_before(items, source, target))))
}

///|
fn json_array_comp(reg : JsonReg) -> @component.Component {
  @component.component(
    name="JsonArray",
    view=(
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
    ),
    style=(
      #|[data-draggingover="json-list-item"] {
      #|  border-top: 4rem solid transparent;
      #|  transition: 0.15s border-top ease;
      #|}
    ),
    fields={ "items": @component.FieldSpec::of_default(List([])) },
    input={
      // add a fresh JsonSelector so the user can pick the new element's type
      "addItem": (inst, _args, _ctx) => {
        let items = match inst.get("items") {
          List(a) => a.copy()
          _ => []
        }
        items.push(reg.make_("JsonSelector"))
        Some(inst.set("items", List(items)))
      },
      "onDropOnItem": (inst, args, _ctx) => json_drop_handler(inst, args),
    },
  )
}

///|
fn json_object_kv_comp() -> @component.Component {
  @component.component(
    name="JsonObjectKeyVal",
    view=(
      #|<div class="join gap-3 items-center justify-center json-kv">
      #|  <input class="input input-sm input-ghost text-green-500 font-mono json-key" :value=".key" @on.input="$setKey value" />
      #|  <span class="text-xs font-mono text-gray-500 colon">:</span>
      #|  <x render=".value"></x>
      #|</div>
    ),
    fields={
      "key": @component.FieldSpec::of_default(Str("k")),
      "value": @component.FieldSpec::of_default(Null),
    },
  )
}

///|
fn json_object_comp(reg : JsonReg) -> @component.Component {
  @component.component(
    name="JsonObject",
    view=(
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
    ),
    style=(
      #|[data-draggingover="json-kv-item"] {
      #|  border-top: 4rem solid transparent;
      #|  transition: 0.15s border-top ease;
      #|}
    ),
    fields={ "items": @component.FieldSpec::of_default(List([])) },
    input={
      // a key/value row whose value is a fresh selector
      "addItem": (inst, _args, _ctx) => {
        let items = match inst.get("items") {
          List(a) => a.copy()
          _ => []
        }
        items.push(
          match reg.comps.get("JsonObjectKeyVal") {
            Some(kv) =>
              kv.make({ "value": reg.make_("JsonSelector") }).to_value()
            None => Null
          },
        )
        Some(inst.set("items", List(items)))
      },
      "onDropOnItem": (inst, args, _ctx) => json_drop_handler(inst, args),
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
  let selector = json_selector_comp(reg)
  let array = json_array_comp(reg)
  let kv = json_object_kv_comp()
  let object = json_object_comp(reg)
  reg.comps["JsonNull"] = null
  reg.comps["JsonBool"] = bool_
  reg.comps["JsonString"] = string
  reg.comps["JsonNumber"] = number
  reg.comps["JsonSelector"] = selector
  reg.comps["JsonArray"] = array
  reg.comps["JsonObjectKeyVal"] = kv
  reg.comps["JsonObject"] = object
  @component.ModuleDef::new(
    name="json",
    components=[selector, null, bool_, string, number, array, kv, object],
    examples=[
      {
        component: "JsonArray",
        title: "Empty Array With Selector",
        args: { "items": List([selector.make(Map([])).to_value()]) },
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
