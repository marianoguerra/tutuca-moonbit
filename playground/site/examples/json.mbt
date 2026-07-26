// Recursive JSON editor: 8 mutually-recursive components (null/bool/string/
// number/array/object + selector + kv), a self-replacing type picker (the
// `swap` bucket), drag-to-reorder. Components look each other up through a
// shared `reg` map filled after all are built.
//
// All eight views live in the View tab (json.html), one `<template id="…">`
// each, and arrive here compiled: json_null_views(), json_array_views(), …
// `JsonArrayMsg` / `JsonObjectMsg` type the two components with `@on` handlers
// of their own — the rest drive everything through generated `$` mutators.

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
fn json_null_comp() -> @component.Component {
  json_null_component(
  )
}


///|
fn json_bool_comp() -> @component.Component {
  json_bool_component(
    init=JsonBoolState::{ value: true },
  )
}


///|
fn json_string_comp() -> @component.Component {
  json_string_component(
    init=JsonStringState::{ value: "hello" },
  )
}


///|
fn json_number_comp() -> @component.Component {
  json_number_component(
    init=JsonNumberState::{ strValue: "0", value: 0 },
    // Keep the raw string always, update the numeric value only when finite.
    // The payload is typed String by the generator, so no unpacking.
    update=(s, msg, _ctx) => match JsonNumberMsg::from_dispatch(msg) {
      Some(SetRawValue(raw)) => {
        let parsed : Double? = Some(@string.parse_double(raw)) catch { _ => None }
        Some(match parsed {
          Some(n) => { strValue: raw, value: n }
          None => { ..s, strValue: raw }
        })
      }
      Some(Unknown(_, _)) | None => None
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
  json_selector_component(
    swap={
      "setToNull": (_s, _args, _ctx) => Some(
        reg.make_("JsonNull"),
      ),
      "setToBool": (_s, args, _ctx) => {
        let is_ctrl = args.get(0) is Some(Bool(true))
        Some(reg.make_("JsonBool", args={ "value": Bool(!is_ctrl) }))
      },
      "setToNumber": (_s, _args, _ctx) => Some(
        reg.make_("JsonNumber"),
      ),
      "setToString": (_s, _args, _ctx) => Some(
        reg.make_("JsonString"),
      ),
      "setToArray": (_s, _args, _ctx) => Some(
        reg.make_("JsonArray"),
      ),
      "setToObject": (_s, _args, _ctx) => Some(
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
fn json_array_comp(reg : JsonReg) -> @component.Component {
  json_array_component(
    init=JsonArrayState::{ items: [] },
    update=(s, msg, _ctx) => match JsonArrayMsg::from_dispatch(msg) {
      // add a fresh JsonSelector so the user can pick the new element's type
      Some(AddItem) => Some({ items: s.items + [json_make_selector(reg)] })
      Some(OnDropOnItem(key, drag_info)) =>
        match json_dropped_items(s.items, [key, drag_info]) {
          Some(items) => Some({ items, })
          None => None
        }
      // Served by a generated mutator or another bucket: the view
      // spells these bare now, so they arrive as Inputs, and
      // returning None falls through to whatever answers them.
      Some(RemoveInItemsAt(_)) => None
      Some(Unknown(_, _)) | None => None
    },
  )
}


///|
fn json_object_kv_comp() -> @component.Component {
  json_object_key_val_component(
    init=JsonObjectKeyValState::{ key: "k", value: Null },
  )
}

///|
fn json_object_comp(reg : JsonReg) -> @component.Component {
  json_object_component(
    init=JsonObjectState::{ items: [] },
    update=(s, msg, _ctx) => match JsonObjectMsg::from_dispatch(msg) {
      // a key/value row whose value is a fresh selector
      Some(AddItem) => {
        let row = match reg.comps.get("JsonObjectKeyVal") {
          Some(kv) => kv.make({ "value": json_make_selector(reg) })
          None => Null
        }
        Some({ items: s.items + [row] })
      }
      Some(OnDropOnItem(key, drag_info)) =>
        match json_dropped_items(s.items, [key, drag_info]) {
          Some(items) => Some({ items, })
          None => None
        }
      // Served by a generated mutator or another bucket: the view
      // spells these bare now, so they arrive as Inputs, and
      // returning None falls through to whatever answers them.
      Some(RemoveInItemsAt(_)) => None
      Some(Unknown(_, _)) | None => None
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
