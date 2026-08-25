// The field → value
// rows of a live component instance, plus a tabbed explorer over one
// instance (values / definition).
//
// Typed-state deviations:
// - instances are opaque Values (Obj); field names/order come from the
//   descriptor's specs and values are read through the Obj trait, so every
//   entry point takes the value plus its Component (or a Components registry
//   via `build_inspector_views`).
// - the Tests tab is gone: `moon test` is
//   the runner here; there is no in-app test-report data source.

///|
/// The pure snapshot of an instance value: its component name plus a
/// field → value Map in declaration order.
///
/// Read off the INSTANCE. `comp` is only a label for a value that declares
/// nothing (an opaque guest instance).
pub fn instance_snapshot(
  v : @tutuca.Value,
  comp? : @component.Component,
) -> @tutuca.Value {
  let name = match v.schema() {
    Some(s) if s.name != "" => s.name
    _ =>
      match comp {
        Some(c) => c.name
        None => ""
      }
  }
  let names = match (v.field_names(), comp) {
    // An instance that declares nothing has nothing to enumerate. There used
    // to be a fallback to the component's runtime specs here; those are built
    // FROM the schema now, so it could only ever repeat what the first arm
    // already answered.
    ([], Some(_)) => []
    (declared, _) => declared
  }
  let fields : Map[String, @tutuca.Value] = Map([])
  for n in names {
    fields[n] = v.field(n)
  }
  Map({ "name": Str(name), "fields": Map(fields) })
}

///|
/// The field → value rows of an instance. Field names/order come from the
/// snapshot; each value renders (and recurses) like the other inspectors.
/// `InstanceFieldsState` is generated from instance_inspector.html.

///|
impl Composite for InstanceFieldsState with fn items(self) {
  self.items
}

///|
impl Composite for InstanceFieldsState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for InstanceFieldsState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for InstanceFieldsState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for InstanceFieldsState with fn with_current_page(self, p) {
  { ..self, currentPage: p }
}

///|
fn instance_fields_comp() -> @component.Component {
  instance_fields_component(
    init={ ..InstanceFieldsState::zero(), itemsPerPage: 10 },
    update=(s, msg, _ctx) => composite_update(s, msg),
    compute=m => {
      match m {
        ArrowText => Some(composite_arrow_text)
        IsItemsEmpty => Some(composite_is_items_empty)
        ShowPagination => Some(composite_show_pagination)
        CannotPrevPage => Some(composite_cannot_prev_page)
        CannotNextPage => Some(composite_cannot_next_page)
        PageIndicatorText => Some(composite_page_indicator_text)
        TypeText => Some((s, _args, _stack) => Str(s.typeName))
        CountText => Some((s, _args, _stack) => Str("{\{s.items.length()}}"))
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
/// Thin wrapper around the rendered value, mirroring DataInspector: with a
/// snapshot it shows the field → value rows; for a non-instance it falls back
/// to the plain data inspector.
fn instance_inspector_comp() -> @component.Component {
  instance_inspector_component(update=(s, msg, _ctx) => {
    match msg {
      Receive("toggleIsExpanded", _) => Next({ value: toggle_wrapped(s.value) })
      _ => Unhandled
    }
  })
}

///|
/// Build the InstanceFields rows from an `instance_snapshot` Value.
fn Inspector::instance_fields_from(
  self : Inspector,
  snapshot : @tutuca.Value,
) -> @tutuca.Value {
  guard snapshot is Map(d) else { return self.classify(snapshot) }
  let rows : Array[@tutuca.Value] = []
  match d.get("fields") {
    Some(Map(fields)) =>
      for name, v in fields {
        rows.push(self.property(name, self.classify(v)))
      }
    _ => ()
  }
  // Start expanded — the field → value rows are the point of this view.
  self.make_("InstanceFields", args={
    "typeName": d.get("name").unwrap_or(Str("")),
    "items": List(rows),
    "isExpanded": Bool(true),
  })
}

///|
/// Snapshot a live instance
/// value + its descriptor.
pub fn Inspector::inspect_instance(
  self : Inspector,
  v : @tutuca.Value,
  comp : @component.Component,
) -> @tutuca.Value {
  self.make_("InstanceInspector", args={
    "value": self.instance_fields_from(instance_snapshot(v, comp~)),
  })
}

///|
/// The same for a plain Value + optional descriptor.
///
/// The field rows no longer need the descriptor: an instance that declares
/// itself shows them with no registry in hand, which is the case
/// `build_inspector_views` is called in when the host has a value and nothing
/// else. Only a value that declares nothing AND has no descriptor falls back
/// to the data inspector.
fn Inspector::inspect_value_as_instance(
  self : Inspector,
  v : @tutuca.Value,
  comp : @component.Component?,
) -> @tutuca.Value {
  let value = if v.schema() is Some(_) || comp is Some(_) {
    self.instance_fields_from(instance_snapshot(v, comp?))
  } else {
    self.classify(v)
  }
  self.make_("InstanceInspector", args={ "value": value })
}

///|
/// Two tabs over one instance: its values (InstanceInspector) and its
/// definition (ComponentInspector).
fn instance_explorer_comp() -> @component.Component {
  instance_explorer_component(init={
    ..InstanceExplorerState::zero(),
    activeTab: "instance",
  })
}

///|
/// Instance + definition tabs over one value.
fn Inspector::explore_instance(
  self : Inspector,
  v : @tutuca.Value,
  comp : @component.Component,
) -> @tutuca.Value {
  self.make_("InstanceExplorer", args={
    "instanceView": self.inspect_instance(v, comp),
    "componentView": self.inspect_component(comp),
    "hasComponent": Bool(true),
  })
}

///|
/// Instance + definition tabs over any value, with the registry optional.
///
/// The twin of `explore_instance` for a caller that has a value and not
/// necessarily its descriptor — a devtool handed a live instance, which is the
/// usual case. The Instance tab works either way now that a value names its
/// own fields; the registry only adds the Component tab beside it.
pub fn Inspector::explore_value(
  self : Inspector,
  v : @tutuca.Value,
  comps? : @component.Components,
) -> @tutuca.Value {
  let views = self.build_inspector_views(v, comps?)
  self.make_("InstanceExplorer", args={
    "instanceView": views.instance_view,
    "componentView": views.component_view,
    "hasComponent": Bool(views.has_component),
  })
}
