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
// immutable-inspector.js is therefore FOLDED into this file — see the git
// history of the dynamic-API version for the full mapping notes.

// ---------------------------------------------------------------------------
// Shared composite machinery (JS compositeFields / compositeMethods /
// compositeAlter / makeCompositeView), typed: every collapsible/paginated
// state struct implements the small Composite trait, and the compute/mutate/
// alter buckets are built generically over it.
// ---------------------------------------------------------------------------

///|
/// The composite surface every collapsible/paginated state exposes. States
/// stay plain flat structs (view fields are flat); this trait is only the
/// seam the shared pagination bucket builders need.
priv trait Composite {
  fn items(Self) -> Array[@tutuca.Value]
  fn is_expanded(Self) -> Bool
  fn per_page(Self) -> Int
  fn current_page(Self) -> Int
  fn with_current_page(Self, Int) -> Self
}

///|
/// The plain composite state: JsonArray / JsonObject.
priv struct CompositeState {
  items : Array[@tutuca.Value]
  isExpanded : Bool
  itemsPerPage : Int
  currentPage : Int
} derive(ToJson, FromJson)

///|
impl Composite for CompositeState with fn items(self) {
  self.items
}

///|
impl Composite for CompositeState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for CompositeState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for CompositeState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for CompositeState with fn with_current_page(self, p) {
  { ..self, currentPage: p }
}

///|
fn composite_init() -> CompositeState {
  { items: [], isExpanded: false, itemsPerPage: 10, currentPage: 0 }
}

///|
fn[S : Composite] items_per_page(s : S) -> Int {
  @cmp.maximum(1, s.per_page())
}

///|
fn[S : Composite] page_count_of(s : S) -> Int {
  let per = items_per_page(s)
  @cmp.maximum(1, (s.items().length() + per - 1) / per) // ceil
}

///|
fn[S : Composite] page_start_of(s : S) -> Int {
  s.current_page() * items_per_page(s)
}

///|
fn[S : Composite] page_end_of(s : S) -> Int {
  @cmp.minimum(s.items().length(), page_start_of(s) + items_per_page(s))
}

///|
fn[S : Composite] has_pagination(s : S) -> Bool {
  s.items().length() > items_per_page(s)
}

///|
/// JS compositeMethods, parametrized by the two per-component texts (JS
/// spreads `...compositeMethods` and overrides typeText/countText).
fn[S : Composite] composite_compute(
  type_text : (S) -> String,
  count_text : (S) -> String,
) -> Map[String, (S, Array[@tutuca.Value]) -> @tutuca.Value] {
  {
    "arrowText": (s, _args) => Str(if s.is_expanded() { "▼" } else { "▶" }),
    "isItemsEmpty": (s, _args) => Bool(s.items().length() == 0),
    "typeText": (s, _args) => Str(type_text(s)),
    "countText": (s, _args) => Str(count_text(s)),
    "showPagination": (s, _args) => Bool(s.is_expanded() && has_pagination(s)),
    "cannotPrevPage": (s, _args) => Bool(s.current_page() <= 0),
    "cannotNextPage": (s, _args) => {
      Bool(s.current_page() >= page_count_of(s) - 1)
    },
    "pageIndicatorText": (s, _args) => {
      let cur = s.current_page() + 1
      Str("\{cur} / \{page_count_of(s)}")
    },
  }
}

///|
/// The prev/next page mutators (pure state changes, $-called from the view).
fn[S : Composite] composite_mutate() -> Map[
  String,
  (S, Array[@tutuca.Value]) -> S,
] {
  {
    "prevPage": (s, _args) => {
      let cur = s.current_page()
      if cur > 0 {
        s.with_current_page(cur - 1)
      } else {
        s
      }
    },
    "nextPage": (s, _args) => {
      let cur = s.current_page()
      if cur < page_count_of(s) - 1 {
        s.with_current_page(cur + 1)
      } else {
        s
      }
    },
  }
}

///|
/// JS compositeAlter: the @loop-with hook slicing the iteration to one page.
fn[S : Composite] composite_loop_with() -> Map[
  String,
  (S, @tutuca.Value, @component.LoopCtx) -> @component.LoopWith,
] {
  {
    "getPageRange": (s, _seq, _ctx) => {
      @component.LoopWith::new(start=page_start_of(s), end=page_end_of(s))
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
priv struct EmptyState {} derive(ToJson, FromJson)

///|
fn json_null_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="font-mono text-sm leading-tight text-warning italic json-null">null</span>
        ),
      ),
    },
    name="JsonNull",
    init=EmptyState::{  },
  )
}

///|
priv struct BoolValueState {
  value : Bool
} derive(ToJson, FromJson)

///|
fn json_boolean_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span :class="$cssClass" @text="$text"></span>
        ),
      ),
      "_margauiClasses": @anode.View::new(
        "_margauiClasses",
        raw_view=(
          #|<p class="text-success text-warning"></p>
        ),
      ),
    },
    name="JsonBoolean",
    init=BoolValueState::{ value: false },
    compute={
      "text": (s : BoolValueState, _args) => {
        Str(if s.value { "true" } else { "false" })
      },
      "cssClass": (s : BoolValueState, _args) => {
        let color = if s.value { "text-success" } else { "text-warning" }
        Str("font-mono text-sm leading-tight json-boolean \{color}")
      },
    },
  )
}

///|
priv struct NumValueState {
  value : Double
} derive(ToJson, FromJson)

///|
fn json_number_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="font-mono text-sm leading-tight text-info json-number" @text="$text"></span>
        ),
      ),
    },
    name="JsonNumber",
    init=NumValueState::{ value: 0 },
    compute={
      "text": (s : NumValueState, _args) => {
        Str(@tutuca.Value::Num(s.value).to_display_string())
      },
    },
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
priv struct StrValueState {
  value : String
} derive(ToJson, FromJson)

///|
fn json_string_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="font-mono text-sm leading-tight inline-block max-w-xs truncate align-bottom json-string" :title=".value" @text="$text"></span>
        ),
      ),
    },
    name="JsonString",
    init=StrValueState::{ value: "" },
    compute={ "text": (s : StrValueState, _args) => Str(json_quote(s.value)) },
  )
}

///|
/// Leaf for `Value::Fn` (stands in for the JS JsFunction component — the port
/// has no function names/kinds to show).
fn value_fn_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="font-mono text-sm leading-tight text-base-content/40 value-fn">function () &#123; … &#125;</span>
        ),
      ),
    },
    name="ValueFn",
    init=EmptyState::{  },
  )
}

///|
priv struct TextState {
  text : String
} derive(ToJson, FromJson)

///|
/// Leaf for an opaque `Value::Obj` (no `obj_seq_entries`): its `obj_debug`
/// text, truncated. Stands in for the JS JsClassInstance/JsError leaves.
fn value_obj_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="font-mono text-sm leading-tight inline-block max-w-xs truncate align-bottom text-info value-obj" :title=".text" @text=".text"></span>
        ),
      ),
    },
    name="ValueObj",
    init=TextState::{ text: "" },
  )
}

// ---------------------------------------------------------------------------
// Composites
// ---------------------------------------------------------------------------

///|
fn json_array_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=make_composite_view(type_class="json-array"),
      ),
    },
    name="JsonArray",
    init=composite_init(),
    compute=composite_compute(_s => "Array", s => {
      let n = s.items.length()
      "(\{n})"
    }),
    mutate=composite_mutate(),
    loop_with=composite_loop_with(),
  )
}

///|
fn json_object_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=make_composite_view(type_class="json-object"),
      ),
    },
    name="JsonObject",
    init=composite_init(),
    compute=composite_compute(_s => "Object", s => {
      let n = s.items.length()
      "{\{n}}"
    }),
    mutate=composite_mutate(),
    loop_with=composite_loop_with(),
  )
}

///|
priv struct PropertyState {
  key : String
  child : @tutuca.Value
} derive(ToJson, FromJson)

///|
/// One key/value row of a composite (also stands in for the JS ImEntry).
fn json_property_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="flex items-center gap-2 leading-tight json-property">
          #|  <span class="text-base-content/60 font-mono text-sm" @text=".key"></span>
          #|  <span class="text-base-content/30">:</span>
          #|  <x render=".child"></x>
          #|</div>
        ),
      ),
    },
    name="JsonProperty",
    init=PropertyState::{ key: "", child: Null },
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
/// to the wrapped value when it supports one; leaf values have no
/// `isExpanded` so the wrapper stays as-is.
fn toggle_wrapped(value : @tutuca.Value) -> @tutuca.Value {
  match obj_get(value, "isExpanded") {
    Some(cur) => obj_set(value, "isExpanded", Bool(!cur.is_truthy()))
    None => value
  }
}

///|
priv struct WrapperState {
  value : @tutuca.Value
} derive(ToJson, FromJson)

///|
/// The single top-level value inspector (JS JsonViewer + DataInspector +
/// ImInspector, collapsed — see the header comment): one `value` field holding
/// the classified tree, the delegating toggle, and a pass-through view.
fn data_inspector_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<span class="contents"><x render=".value"></x></span>
        ),
      ),
    },
    name="DataInspector",
    init=WrapperState::{ value: Null },
    mutate={
      "toggleIsExpanded": (s : WrapperState, _args) => {
        value: toggle_wrapped(s.value),
      },
    },
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
