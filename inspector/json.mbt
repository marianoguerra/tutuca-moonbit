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
/// JsonArray and JsonObject have the same composite shape, and each now has
/// its OWN generated state type — so the trait is implemented twice over
/// identical bodies rather than once over a shared struct. That is the trade
/// the generator makes everywhere: the state a view reads is described by the
/// view file, not by a struct two components happen to share.
impl Composite for JsonArrayState with fn items(self) {
  self.items
}

///|
impl Composite for JsonArrayState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for JsonArrayState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for JsonArrayState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for JsonArrayState with fn with_current_page(self, p) {
  { ..self, currentPage: p }
}

///|
impl Composite for JsonObjectState with fn items(self) {
  self.items
}

///|
impl Composite for JsonObjectState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for JsonObjectState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for JsonObjectState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for JsonObjectState with fn with_current_page(self, p) {
  { ..self, currentPage: p }
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
/// The composite `$`-callables, one function each (JS compositeMethods).
///
/// Individually rather than as a bucket map: the buckets are keyed by each
/// component's own generated Method enum now, so what is shared is the
/// HANDLER, and the match that names it is per component — which is what
/// makes a name added to the composite view a build error in every component
/// that uses it.
fn[S : Composite] composite_arrow_text(
  s : S,
  _args : Array[@tutuca.Value],
) -> @tutuca.Value {
  Str(if s.is_expanded() { "▼" } else { "▶" })
}

///|
fn[S : Composite] composite_is_items_empty(
  s : S,
  _args : Array[@tutuca.Value],
) -> @tutuca.Value {
  Bool(s.items().length() == 0)
}

///|
fn[S : Composite] composite_show_pagination(
  s : S,
  _args : Array[@tutuca.Value],
) -> @tutuca.Value {
  Bool(s.is_expanded() && has_pagination(s))
}

///|
fn[S : Composite] composite_cannot_prev_page(
  s : S,
  _args : Array[@tutuca.Value],
) -> @tutuca.Value {
  Bool(s.current_page() <= 0)
}

///|
fn[S : Composite] composite_cannot_next_page(
  s : S,
  _args : Array[@tutuca.Value],
) -> @tutuca.Value {
  Bool(s.current_page() >= page_count_of(s) - 1)
}

///|
fn[S : Composite] composite_page_indicator_text(
  s : S,
  _args : Array[@tutuca.Value],
) -> @tutuca.Value {
  let cur = s.current_page() + 1
  Str("\{cur} / \{page_count_of(s)}")
}

///|
/// The @loop-with hook slicing the iteration to one page (JS compositeAlter).
fn[S : Composite] composite_page_range(
  s : S,
  _seq : @tutuca.Value,
  _ctx : @component.LoopCtx,
) -> @component.LoopWith {
  @component.LoopWith::new(start=page_start_of(s), end=page_end_of(s))
}

///|
/// The prev/next page arms, shared by every paged inspector component.
///
/// A helper an `update` DELEGATES to rather than a bucket of its own: a
/// component with arms of its own ends its match with
/// `_ => composite_update(s, msg)`, so the sharing survives without a second
/// place for a handler to live. `None` means "no change", which is what the
/// old bucket expressed by returning `s` unchanged at a boundary.
fn[S : Composite] composite_update(s : S, msg : @component.Dispatch) -> S? {
  match msg {
    Input("prevPage", _) => {
      let cur = s.current_page()
      if cur > 0 {
        Some(s.with_current_page(cur - 1))
      } else {
        None
      }
    }
    Input("nextPage", _) => {
      let cur = s.current_page()
      if cur < page_count_of(s) - 1 {
        Some(s.with_current_page(cur + 1))
      } else {
        None
      }
    }
    _ => None
  }
}

// ---------------------------------------------------------------------------
// Leaf components
// ---------------------------------------------------------------------------

///|
fn json_null_comp() -> @component.Component {
  json_null_component()
}

///|
fn json_boolean_comp() -> @component.Component {
  json_boolean_component(compute=m => {
    match m {
      Text => Some((s, _args) => Str(if s.value { "true" } else { "false" }))
      CssClass =>
        Some((s, _args) => {
          let color = if s.value { "text-success" } else { "text-warning" }
          Str("font-mono text-sm leading-tight json-boolean \{color}")
        })
    }
  })
}

///|
fn json_number_comp() -> @component.Component {
  json_number_component(compute=m => {
    match m {
      Text =>
        Some((s, _args) => {
          Str((@tutuca.Value::Num(s.value) : @tutuca.Value).to_display_string())
        })
    }
  })
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
  json_string_component(compute=m => {
    match m {
      Text => Some((s, _args) => Str(json_quote(s.value)))
    }
  })
}

///|
/// Leaf for `Value::Fn` (stands in for the JS JsFunction component — the port
/// has no function names/kinds to show).
fn value_fn_comp() -> @component.Component {
  value_fn_component()
}

///|
/// Leaf for an opaque `Value::Obj` (no `obj_seq_entries`): its `obj_debug`
/// text, truncated. Stands in for the JS JsClassInstance/JsError leaves.
fn value_obj_comp() -> @component.Component {
  value_obj_component()
}

// ---------------------------------------------------------------------------
// Composites
// ---------------------------------------------------------------------------

///|
fn json_array_comp() -> @component.Component {
  json_array_component(
    init={ ..JsonArrayState::zero(), itemsPerPage: 10 },
    update=(s, msg, _ctx) => composite_update(s, msg),
    compute=m => {
      match m {
        ArrowText => Some(composite_arrow_text)
        IsItemsEmpty => Some(composite_is_items_empty)
        ShowPagination => Some(composite_show_pagination)
        CannotPrevPage => Some(composite_cannot_prev_page)
        CannotNextPage => Some(composite_cannot_next_page)
        PageIndicatorText => Some(composite_page_indicator_text)
        TypeText => Some((_s, _args) => Str("Array"))
        CountText => Some((s, _args) => Str("(\{s.items.length()})"))
      }
    },
    loop_with=l => {
      match l {
        GetPageRange => Some(composite_page_range)
      }
    },
  )
}

///|
fn json_object_comp() -> @component.Component {
  json_object_component(
    init={ ..JsonObjectState::zero(), itemsPerPage: 10 },
    update=(s, msg, _ctx) => composite_update(s, msg),
    compute=m => {
      match m {
        ArrowText => Some(composite_arrow_text)
        IsItemsEmpty => Some(composite_is_items_empty)
        ShowPagination => Some(composite_show_pagination)
        CannotPrevPage => Some(composite_cannot_prev_page)
        CannotNextPage => Some(composite_cannot_next_page)
        PageIndicatorText => Some(composite_page_indicator_text)
        TypeText => Some((_s, _args) => Str("Object"))
        CountText => Some((s, _args) => Str("{\{s.items.length()}}"))
      }
    },
    loop_with=l => {
      match l {
        GetPageRange => Some(composite_page_range)
      }
    },
  )
}

///|
/// One key/value row of a composite (also stands in for the JS ImEntry).
fn json_property_comp() -> @component.Component {
  json_property_component()
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
/// The single top-level value inspector (JS JsonViewer + DataInspector +
/// ImInspector, collapsed — see the header comment): one `value` field holding
/// the classified tree, the delegating toggle, and a pass-through view.
fn data_inspector_comp() -> @component.Component {
  data_inspector_component(update=(s, msg, _ctx) => {
    match msg {
      Input("toggleIsExpanded", _) => Some({ value: toggle_wrapped(s.value) })
      _ => None
    }
  })
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
fn Inspector::inspect_value(
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
