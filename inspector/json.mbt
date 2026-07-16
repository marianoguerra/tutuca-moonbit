// Port of src/components/data/json.js + data/data.js + data/immutable-inspector.js
// — the generic value inspector, collapsed onto `@tutuca.Value`.
//
// The JS library classifies THREE families of values (plain JSON, JS extras,
// Immutable.js collections) through a `chain(...)` dispatcher. The port has no
// JS values: everything is a `@tutuca.Value` (Null / Bool / Num / Str / List /
// Map / Fn / Obj), so the three JS classifiers collapse into ONE `classify`
// and the JS-only leaf components map as follows:
//
//   JsonNull                          -> JsonNull        (Value::Null)
//   JsonBoolean                       -> JsonBoolean     (Value::Bool)
//   JsonNumber / JsBigInt             -> JsonNumber      (Value::Num)
//   JsonString / JsSymbol / JsDate /
//   JsRegExp                          -> JsonString      (Value::Str)
//   JsonArray / ImList / ImStack /
//   JsSet / ImSet / ImOSet / ImRange  -> JsonArray       (Value::List)
//   JsonObject / ImMap / ImOMap /
//   JsMap / ImRecord                  -> JsonObject      (Value::Map)
//   JsFunction                        -> ValueFn         (Value::Fn)
//   JsClassInstance / JsError         -> ValueObj        (Value::Obj — leaf
//     via `obj_debug`; an Obj exposing `obj_seq_entries` renders as
//     JsonObject rows instead)
//   JsUndefined                       -> (no undefined; Null)
//
// immutable-inspector.js is therefore FOLDED into this file: under Value
// semantics its Im* components are exact duplicates of the JSON composites
// (only the accent colour differed), so `ImInspector`, `ImEntry`, `ImList`,
// `ImStack`, `ImMap`, `ImOMap`, `ImSet`, `ImOSet`, `ImRecord` and `ImRange`
// are not ported. Likewise `JsonViewer` and `DataInspector` (strict JSON vs
// everything) collapse into the single `DataInspector` wrapper, and
// `JsonProperty`/`ImEntry` into `JsonProperty`.

// ---------------------------------------------------------------------------
// Shared composite machinery (JS compositeFields / compositeMethods /
// compositeAlter / makeCompositeView)
// ---------------------------------------------------------------------------

///|
fn items_of(inst : @component.Instance) -> Array[@tutuca.Value] {
  match inst.get("items") {
    List(a) => a
    _ => []
  }
}

///|
fn int_field(inst : @component.Instance, name : String) -> Int {
  match inst.get(name) {
    Num(n) => n.to_int()
    _ => 0
  }
}

///|
fn str_field(inst : @component.Instance, name : String) -> String {
  match inst.get(name) {
    Str(s) => s
    _ => ""
  }
}

///|
fn bool_field(inst : @component.Instance, name : String) -> Bool {
  inst.get(name).is_truthy()
}

///|
fn items_per_page(inst : @component.Instance) -> Int {
  @cmp.maximum(1, int_field(inst, "itemsPerPage"))
}

///|
fn page_count_of(inst : @component.Instance) -> Int {
  let per = items_per_page(inst)
  @cmp.maximum(1, (items_of(inst).length() + per - 1) / per) // ceil
}

///|
fn page_start_of(inst : @component.Instance) -> Int {
  int_field(inst, "currentPage") * items_per_page(inst)
}

///|
fn page_end_of(inst : @component.Instance) -> Int {
  @cmp.minimum(
    items_of(inst).length(),
    page_start_of(inst) + items_per_page(inst),
  )
}

///|
fn has_pagination(inst : @component.Instance) -> Bool {
  items_of(inst).length() > items_per_page(inst)
}

///|
/// JS compositeFields: items / isExpanded / itemsPerPage / currentPage.
fn composite_fields() -> Map[String, @component.FieldSpec] {
  {
    "items": @component.FieldSpec::of_default(List([])),
    "isExpanded": @component.FieldSpec::of_default(Bool(false)),
    "itemsPerPage": @component.FieldSpec::of_default(Num(10)),
    "currentPage": @component.FieldSpec::of_default(Num(0)),
  }
}

///|
/// JS compositeMethods, parametrized by the two per-component texts (JS spreads
/// `...compositeMethods` and overrides typeText/countText).
fn composite_methods(
  type_text : (@component.Instance) -> String,
  count_text : (@component.Instance) -> String,
) -> Map[String, @component.MethodFn] {
  {
    "arrowText": (inst, _args) => {
      Str(if bool_field(inst, "isExpanded") { "▼" } else { "▶" })
    },
    "isItemsEmpty": (inst, _args) => Bool(items_of(inst).length() == 0),
    "typeText": (inst, _args) => Str(type_text(inst)),
    "countText": (inst, _args) => Str(count_text(inst)),
    "showPagination": (inst, _args) => {
      Bool(bool_field(inst, "isExpanded") && has_pagination(inst))
    },
    "cannotPrevPage": (inst, _args) => Bool(int_field(inst, "currentPage") <= 0),
    "cannotNextPage": (inst, _args) => {
      Bool(int_field(inst, "currentPage") >= page_count_of(inst) - 1)
    },
    "pageIndicatorText": (inst, _args) => {
      let cur = int_field(inst, "currentPage") + 1
      Str("\{cur} / \{page_count_of(inst)}")
    },
    "prevPage": (inst, _args) => {
      let cur = int_field(inst, "currentPage")
      if cur > 0 {
        inst.set("currentPage", Num((cur - 1).to_double())).to_value()
      } else {
        inst.to_value()
      }
    },
    "nextPage": (inst, _args) => {
      let cur = int_field(inst, "currentPage")
      if cur < page_count_of(inst) - 1 {
        inst.set("currentPage", Num((cur + 1).to_double())).to_value()
      } else {
        inst.to_value()
      }
    },
  }
}

///|
/// JS compositeAlter: the @loop-with hook slicing the iteration to one page.
fn composite_alter() -> Map[String, @component.MethodFn] {
  {
    "getPageRange": (inst, _args) => {
      Map({
        "start": Num(page_start_of(inst).to_double()),
        "end": Num(page_end_of(inst).to_double()),
      })
    },
  }
}

///|
/// JS makeCompositeView({typeClass, borderClass, toggleHandler}).
fn make_composite_view(
  type_class? : String = "",
  border_class? : String = "border-base-content/10",
  toggle_handler? : String = "$toggleIsExpanded",
) -> String {
  let tpl =
    #|<span class="font-mono text-sm leading-tight inline-block">
    #|  <span class="inline-flex items-center gap-2">
    #|    <button
    #|      type="button"
    #|      class="cursor-pointer text-base-content/70 hover:text-base-content inline-flex items-center gap-1"
    #|      :disabled="$isItemsEmpty"
    #|      @on.click="__TOGGLE__">
    #|      <span @text="$arrowText"></span>
    #|      <span class="__TYPE_CLASS__" @text="$typeText"></span>
    #|      <span @text="$countText"></span>
    #|    </button>
    #|    <div @show="$showPagination" class="join">
    #|      <button type="button" class="join-item btn btn-xs pg-prev" :disabled="$cannotPrevPage" @on.click="$prevPage">«</button>
    #|      <span class="join-item badge font-mono text-xs pg-label" @text="$pageIndicatorText"></span>
    #|      <button type="button" class="join-item btn btn-xs pg-next" :disabled="$cannotNextPage" @on.click="$nextPage">»</button>
    #|    </div>
    #|  </span>
    #|  <div @show=".isExpanded" class="ml-1 flex flex-col gap-0.5 border-l __BORDER_CLASS__ pl-2 mt-0.5">
    #|    <x render-each=".items" @loop-with="getPageRange"></x>
    #|  </div>
    #|</span>

  tpl
  .replace(old="__TOGGLE__", new=toggle_handler)
  .replace(old="__TYPE_CLASS__", new=type_class)
  .replace(old="__BORDER_CLASS__", new=border_class)
}

// ---------------------------------------------------------------------------
// Leaf components
// ---------------------------------------------------------------------------

///|
fn json_null_comp() -> @component.Component {
  @component.component(
    name="JsonNull",
    view=(
      #|<span class="font-mono text-sm leading-tight text-warning italic json-null">null</span>
    ),
  )
}

///|
fn json_boolean_comp() -> @component.Component {
  @component.component(
    name="JsonBoolean",
    fields={ "value": @component.FieldSpec::of_default(Bool(false)) },
    methods={
      "text": (inst, _args) => {
        Str(if bool_field(inst, "value") { "true" } else { "false" })
      },
      "cssClass": (inst, _args) => {
        let color = if bool_field(inst, "value") {
          "text-success"
        } else {
          "text-warning"
        }
        Str("font-mono text-sm leading-tight json-boolean \{color}")
      },
    },
    view=(
      #|<span :class="$cssClass" @text="$text"></span>
    ),
    views={
      // Decoy: cssClass() builds these at runtime, so they never appear as
      // literals the margaui scanner can find. Never rendered — registering
      // the view is enough for the class scan to emit their CSS.
      "_margauiClasses": (
        #|<p class="text-success text-warning"></p>
      ),
    },
  )
}

///|
fn json_number_comp() -> @component.Component {
  @component.component(
    name="JsonNumber",
    fields={ "value": @component.FieldSpec::of_default(Num(0)) },
    methods={
      "text": (inst, _args) => Str(inst.get("value").to_display_string()),
    },
    view=(
      #|<span class="font-mono text-sm leading-tight text-info json-number" @text="$text"></span>
    ),
  )
}

///|
/// JSON.stringify for the string leaf's display text.
fn json_quote(s : String) -> String {
  let sb = StringBuilder()
  sb.write_char('"')
  for c in s {
    match c {
      '"' => sb.write_string("\\\"")
      '\\' => sb.write_string("\\\\")
      '\n' => sb.write_string("\\n")
      '\t' => sb.write_string("\\t")
      '\r' => sb.write_string("\\r")
      _ => sb.write_char(c)
    }
  }
  sb.write_char('"')
  sb.to_string()
}

///|
fn json_string_comp() -> @component.Component {
  @component.component(
    name="JsonString",
    fields={ "value": @component.FieldSpec::of_default(Str("")) },
    methods={
      "text": (inst, _args) => Str(json_quote(str_field(inst, "value"))),
    },
    view=(
      #|<span class="font-mono text-sm leading-tight inline-block max-w-xs truncate align-bottom json-string" :title=".value" @text="$text"></span>
    ),
  )
}

///|
/// Leaf for `Value::Fn` (stands in for the JS JsFunction component — the port
/// has no function names/kinds to show).
fn value_fn_comp() -> @component.Component {
  @component.component(
    name="ValueFn",
    view=(
      #|<span class="font-mono text-sm leading-tight text-base-content/40 value-fn">function () &#123; … &#125;</span>
    ),
  )
}

///|
/// Leaf for an opaque `Value::Obj` (no `obj_seq_entries`): its `obj_debug`
/// text, truncated. Stands in for the JS JsClassInstance/JsError leaves.
fn value_obj_comp() -> @component.Component {
  @component.component(
    name="ValueObj",
    fields={ "text": @component.FieldSpec::of_default(Str("")) },
    view=(
      #|<span class="font-mono text-sm leading-tight inline-block max-w-xs truncate align-bottom text-info value-obj" :title=".text" @text=".text"></span>
    ),
  )
}

// ---------------------------------------------------------------------------
// Composites
// ---------------------------------------------------------------------------

///|
fn json_array_comp() -> @component.Component {
  let methods = composite_methods(_inst => "Array", inst => {
    let n = items_of(inst).length()
    "(\{n})"
  })
  @component.component(
    name="JsonArray",
    fields=composite_fields(),
    methods~,
    alter=composite_alter(),
    view=make_composite_view(type_class="json-array"),
  )
}

///|
fn json_object_comp() -> @component.Component {
  let methods = composite_methods(_inst => "Object", inst => {
    let n = items_of(inst).length()
    "{\{n}}"
  })
  @component.component(
    name="JsonObject",
    fields=composite_fields(),
    methods~,
    alter=composite_alter(),
    view=make_composite_view(type_class="json-object"),
  )
}

///|
/// One key/value row of a composite (also stands in for the JS ImEntry).
fn json_property_comp() -> @component.Component {
  @component.component(
    name="JsonProperty",
    fields={
      "key": @component.FieldSpec::of_default(Str("")),
      "child": @component.FieldSpec::of_default(Null),
    },
    view=(
      #|<div class="flex items-center gap-2 leading-tight json-property">
      #|  <span class="text-base-content/60 font-mono text-sm" @text=".key"></span>
      #|  <span class="text-base-content/30">:</span>
      #|  <x render=".child"></x>
      #|</div>
    ),
  )
}

// ---------------------------------------------------------------------------
// Top-level wrapper + classifier
// ---------------------------------------------------------------------------

///|
/// Read a field of a component-instance Value through the Obj trait.
fn obj_get(v : @tutuca.Value, name : String) -> @tutuca.Value? {
  match v {
    Obj(o) => o.obj_field(name)
    _ => None
  }
}

///|
/// Write a field of a component-instance Value through the Obj trait;
/// returns the value unchanged when the field does not exist.
fn obj_set(
  v : @tutuca.Value,
  name : String,
  field_val : @tutuca.Value,
) -> @tutuca.Value {
  match v {
    Obj(o) =>
      match o.obj_with_field(name, field_val) {
        Some(nv) => nv
        None => v
      }
    _ => v
  }
}

///|
/// JS valueWrapperMethods.toggleIsExpanded: delegate an expand/collapse toggle
/// to the wrapped `value` when it supports one; leaf values have no
/// `isExpanded` so the wrapper stays as-is.
fn wrapper_toggle(
  inst : @component.Instance,
  _args : Array[@tutuca.Value],
) -> @tutuca.Value {
  let value = inst.get("value")
  match obj_get(value, "isExpanded") {
    Some(cur) =>
      inst
      .set("value", obj_set(value, "isExpanded", Bool(!cur.is_truthy())))
      .to_value()
    None => inst.to_value()
  }
}

///|
/// The single top-level value inspector (JS JsonViewer + DataInspector +
/// ImInspector, collapsed — see the header comment): one `value` field holding
/// the classified tree, the delegating toggle, and a pass-through view.
fn data_inspector_comp() -> @component.Component {
  @component.component(
    name="DataInspector",
    fields={ "value": @component.FieldSpec::of_default(Null) },
    methods={ "toggleIsExpanded": wrapper_toggle },
    view=(
      #|<span class="contents"><x render=".value"></x></span>
    ),
  )
}

///|
fn fmt_path_key(k : @tutuca.PathKey) -> String {
  match k {
    KInt(i) => i.to_string()
    KStr(s) => s
  }
}

///|
/// JS classifyData / chain(classifyImmutable, classifyJsExtra, classifyJson):
/// one classifier over the whole Value enum. Returns the classified component
/// tree (component instances all the way down), NOT wrapped in DataInspector.
pub fn Inspector::classify(
  self : Inspector,
  v : @tutuca.Value,
) -> @tutuca.Value {
  match v {
    Null => self.make_("JsonNull")
    Bool(b) => self.make_("JsonBoolean", args={ "value": Bool(b) })
    Num(n) => self.make_("JsonNumber", args={ "value": Num(n) })
    Str(s) => self.make_("JsonString", args={ "value": Str(s) })
    Fn(_) => self.make_("ValueFn")
    List(items) => {
      let rows : Array[@tutuca.Value] = []
      for i, item in items {
        rows.push(self.property(i.to_string(), self.classify(item)))
      }
      self.make_("JsonArray", args={ "items": List(rows) })
    }
    Map(m) => {
      let rows : Array[@tutuca.Value] = []
      for k, item in m {
        rows.push(self.property(k, self.classify(item)))
      }
      self.make_("JsonObject", args={ "items": List(rows) })
    }
    Obj(o) =>
      match o.obj_seq_entries() {
        Some(entries) => {
          let rows : Array[@tutuca.Value] = []
          for entry in entries {
            let (k, item) = entry
            rows.push(self.property(fmt_path_key(k), self.classify(item)))
          }
          self.make_("JsonObject", args={ "items": List(rows) })
        }
        None => self.make_("ValueObj", args={ "text": Str(o.obj_debug()) })
      }
  }
}

///|
fn Inspector::property(
  self : Inspector,
  key : String,
  child : @tutuca.Value,
) -> @tutuca.Value {
  self.make_("JsonProperty", args={ "key": Str(key), "child": child })
}

///|
/// JS DataInspector.Class.fromData: classify + wrap in the DataInspector.
pub fn Inspector::inspect_value(
  self : Inspector,
  v : @tutuca.Value,
) -> @tutuca.Value {
  self.make_("DataInspector", args={ "value": self.classify(v) })
}

///|
/// Recursively expand a classified tree so an example renders open (port of
/// the .dev.js `deepExpand` helpers).
pub fn deep_expand(v : @tutuca.Value) -> @tutuca.Value {
  match v {
    Obj(_) => {
      let mut cur = v
      if obj_get(cur, "isExpanded") is Some(_) {
        cur = obj_set(cur, "isExpanded", Bool(true))
      }
      // single-child fields (wrapper value + raw, property child, not-child,
      // if/then/else nodes)
      for name in ["value", "raw", "child", "ifNode", "thenNode", "elseNode"] {
        match obj_get(cur, name) {
          Some(Obj(_) as inner) => cur = obj_set(cur, name, deep_expand(inner))
          _ => ()
        }
      }
      for name in ["items", "sections", "components", "events"] {
        match obj_get(cur, name) {
          Some(List(items)) =>
            cur = obj_set(cur, name, List(items.map(deep_expand)))
          _ => ()
        }
      }
      cur
    }
    _ => v
  }
}
