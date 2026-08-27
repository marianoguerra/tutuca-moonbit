// A composable JSON editor built from typed
// primitives (null/bool/string/number/array/object), 8 mutually-recursive
// components.
//
// TWO PATTERNS worth calling out:
//
// 1. Self-replacement. The handler returns
//    `Comp.make()` — a fresh instance of a DIFFERENT component type, which the
//    framework swaps in where the selector was. The typed `update` bucket
//    cannot express that (it returns a new S), so these handlers go in the
//    `swap` bucket: `(S, args, ctx) -> Value?` — Input-dispatched by name,
//    returning the replacement node (None = keep).
//
// 2. The component-as-argument problem (as in todo.mbt), but sharper: a selector
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
  json_null_component()
}

///|
fn json_bool_comp() -> @component.Component {
  json_bool_component(init={ value: true, })
}

///|
fn json_string_comp() -> @component.Component {
  json_string_component(init={ value: "hello", })
}

///|
fn json_number_comp() -> @component.Component {
  json_number_component(
    init={ strValue: "0", value: 0, },
    // Keep the raw string always, update the numeric value only when finite.
    // The payload is typed `String` by the generator, so the arg no longer
    // has to be unpacked from an untyped list.
    update=(s, msg, _ctx) => {
      match JsonNumberMsg::from_dispatch(msg) {
        Some(SetRawValue(raw)) => {
          let parsed : Double? = Some(@string.parse_double(raw)) catch {
            _ => None
          }
          Next(
            match parsed {
              Some(n) => { strValue: raw, value: n, }
              None => { ..s, strValue: raw, }
            },
          )
        }
        Some(Unknown(_, _)) | None => Unhandled
      }
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
  json_selector_component(swap=m => {
    match m {
      SetToNull => Some((_s, _args, _ctx) => Some(reg.make_("JsonNull")))
      SetToBool =>
        Some((_s, args, _ctx) => {
          let is_ctrl = args.get(0) is Some(Bool(true))
          Some(reg.make_("JsonBool", args={ "value": Bool(!is_ctrl) }))
        })
      SetToNumber => Some((_s, _args, _ctx) => Some(reg.make_("JsonNumber")))
      SetToString => Some((_s, _args, _ctx) => Some(reg.make_("JsonString")))
      SetToArray => Some((_s, _args, _ctx) => Some(reg.make_("JsonArray")))
      SetToObject => Some((_s, _args, _ctx) => Some(reg.make_("JsonObject")))
    }
  })
}

///|
/// Move the item currently at `source` to sit just before `target`.
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
  json_array_component(init={ items: [], }, update=(s, msg, _ctx) => {
    match JsonArrayMsg::from_dispatch(msg) {
      // Served by the mutators generated from the state's fields: the
      // view spells them bare now, so they arrive as Inputs, and `Unhandled`
      // falls through to them.
      Some(RemoveInItemsAt(_)) => Unhandled
      // add a fresh JsonSelector so the user can pick the new element's type
      Some(AddItem) => Next({ items: s.items + [json_make_selector(reg)], })
      Some(OnDropOnItem(a0, a1)) =>
        match json_dropped_items(s.items, [a0, a1]) {
          Some(items) => Next({ items, })
          // The drop did not land on a row this list holds. It claimed the
          // name, so nothing further is tried.
          None => Unchanged
        }
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}

///|
fn json_object_kv_comp() -> @component.Component {
  json_object_key_val_component(init={ key: "k", value: Null, })
}

///|
fn json_object_comp(reg : JsonReg) -> @component.Component {
  json_object_component(init={ items: [], }, update=(s, msg, _ctx) => {
    match JsonObjectMsg::from_dispatch(msg) {
      // Served by the mutators generated from the state's fields: the
      // view spells them bare now, so they arrive as Inputs, and `Unhandled`
      // falls through to them.
      Some(RemoveInItemsAt(_)) => Unhandled
      // a key/value row whose value is a fresh selector
      Some(AddItem) => {
        let row = match reg.comps.get("JsonObjectKeyVal") {
          Some(kv) => kv.make({ "value": json_make_selector(reg) })
          None => Null
        }
        Next({ items: s.items + [row], })
      }
      Some(OnDropOnItem(a0, a1)) =>
        match json_dropped_items(s.items, [a0, a1]) {
          Some(items) => Next({ items, })
          // The drop did not land on a row this list holds. It claimed the
          // name, so nothing further is tried.
          None => Unchanged
        }
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}

///|
pub fn json_module() -> @component.ModuleDef {
  let reg = JsonReg::{ comps: Map([]), }
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
      { component: "JsonObject", title: "Object", args: Map([]), view: None, },
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
