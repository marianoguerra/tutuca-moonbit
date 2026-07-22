// Port of src/components/tutuca/instance-inspector.js — the field → value
// rows of a live component instance, plus a tabbed explorer over one
// instance (values / definition / lint).
//
// Typed-state deviations:
// - instances are opaque Values (Obj); field names/order come from the
//   descriptor's specs and values are read through the Obj trait, so every
//   entry point takes the value plus its Component (or a Components registry
//   via `build_inspector_views`).
// - the Tests tab is gone: test-inspector.js is not ported (`moon test` is
//   the runner here; there is no in-app test-report data source).

///|
/// The pure snapshot of an instance value: its component name plus a
/// field → value Map in declaration order.
pub fn instance_snapshot(
  v : @tutuca.Value,
  comp : @component.Component,
) -> @tutuca.Value {
  let fields : Map[String, @tutuca.Value] = Map([])
  for name, _spec in comp.specs {
    fields[name] = obj_get(v, name).unwrap_or(Null)
  }
  Map({ "name": Str(comp.name), "fields": Map(fields) })
}

///|
/// The field → value rows of an instance. Field names/order come from the
/// snapshot; each value renders (and recurses) like the other inspectors.
priv struct InstanceFieldsState {
  items : Array[@tutuca.Value]
  isExpanded : Bool
  itemsPerPage : Int
  currentPage : Int
  typeName : String
} derive(ToJson, FromJson)

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
  @component.component(
    name="InstanceFields",
    init=InstanceFieldsState::{
      items: [],
      isExpanded: false,
      itemsPerPage: 10,
      currentPage: 0,
      typeName: "",
    },
    compute=composite_compute((s : InstanceFieldsState) => s.typeName, s => {
      let n = s.items.length()
      "{\{n}}"
    }),
    mutate=composite_mutate(),
    loop_with=composite_loop_with(),
    view=make_composite_view(
      type_class="font-semibold instance-fields",
      border_class="border-base-content/15",
    ),
  )
}

///|
/// Thin wrapper around the rendered value, mirroring DataInspector: with a
/// snapshot it shows the field → value rows; for a non-instance it falls back
/// to the plain data inspector.
fn instance_inspector_comp() -> @component.Component {
  @component.component(
    name="InstanceInspector",
    init=WrapperState::{ value: Null },
    mutate={
      "toggleIsExpanded": (s : WrapperState, _args) => {
        value: toggle_wrapped(s.value),
      },
    },
    view=(
      #|<span class="contents"><x render=".value"></x></span>
    ),
  )
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
/// JS InstanceInspector.Class.fromData(instance, comp) for a live instance
/// value + its descriptor.
pub fn Inspector::inspect_instance(
  self : Inspector,
  v : @tutuca.Value,
  comp : @component.Component,
) -> @tutuca.Value {
  self.make_("InstanceInspector", args={
    "value": self.instance_fields_from(instance_snapshot(v, comp)),
  })
}

///|
/// The same for a plain Value + optional descriptor: with a comp it shows the
/// field rows, without one it falls back to the data inspector.
pub fn Inspector::inspect_value_as_instance(
  self : Inspector,
  v : @tutuca.Value,
  comp : @component.Component?,
) -> @tutuca.Value {
  let value = match comp {
    Some(c) => self.instance_fields_from(instance_snapshot(v, c))
    None => self.classify(v)
  }
  self.make_("InstanceInspector", args={ "value": value })
}

///|
priv struct InstanceExplorerState {
  activeTab : String
  instanceView : @tutuca.Value
  componentView : @tutuca.Value
  lintView : @tutuca.Value
  hasComponent : Bool
  hasLint : Bool
} derive(ToJson, FromJson)

///|
/// Up to three tabs over one instance: its values (InstanceInspector), its
/// definition (ComponentInspector) and — when provided — its lint findings
/// (LintReport). A tab only appears when it has content.
fn instance_explorer_comp() -> @component.Component {
  @component.component(
    name="InstanceExplorer",
    init=InstanceExplorerState::{
      activeTab: "instance",
      instanceView: Null,
      componentView: Null,
      lintView: Null,
      hasComponent: false,
      hasLint: false,
    },
    view=(
      #|<div class="font-mono text-sm leading-snug flex flex-col gap-3 instance-explorer">
      #|  <div role="tablist" class="tabs">
      #|    <a role="tab"
      #|      @if.class="equals? .activeTab 'instance'"
      #|      @then="'tab tab-active tab-instance'"
      #|      @else="'tab tab-instance'"
      #|      @on.click="$setActiveTab 'instance'">
      #|      Instance
      #|    </a>
      #|    <a role="tab" @show=".hasComponent"
      #|      @if.class="equals? .activeTab 'component'"
      #|      @then="'tab tab-active tab-component'"
      #|      @else="'tab tab-component'"
      #|      @on.click="$setActiveTab 'component'">
      #|      Component
      #|    </a>
      #|    <a role="tab" @show=".hasLint"
      #|      @if.class="equals? .activeTab 'lint'"
      #|      @then="'tab tab-active tab-lint'"
      #|      @else="'tab tab-lint'"
      #|      @on.click="$setActiveTab 'lint'">
      #|      Lint
      #|    </a>
      #|  </div>
      #|  <div @show="equals? .activeTab 'instance'">
      #|    <x render=".instanceView"></x>
      #|  </div>
      #|  <div @show="equals? .activeTab 'component'">
      #|    <div @show=".hasComponent"><x render=".componentView"></x></div>
      #|    <div @hide=".hasComponent" class="text-base-content/50 text-xs">
      #|      Pass the Component descriptor to inspect its definition.
      #|    </div>
      #|  </div>
      #|  <div @show="equals? .activeTab 'lint'">
      #|    <x render=".lintView"></x>
      #|  </div>
      #|</div>
    ),
  )
}

///|
/// JS InstanceExplorer.Class.fromData: instance + definition (+ lint) tabs.
/// `lint_findings` are `finding_value` Maps (see lint_inspector.mbt).
pub fn Inspector::explore_instance(
  self : Inspector,
  v : @tutuca.Value,
  comp : @component.Component,
  lint_findings? : Array[@tutuca.Value],
) -> @tutuca.Value {
  let lint_view = match lint_findings {
    Some(findings) => self.lint_report(findings)
    None => Null
  }
  self.make_("InstanceExplorer", args={
    "instanceView": self.inspect_instance(v, comp),
    "componentView": self.inspect_component(comp),
    "lintView": lint_view,
    "hasComponent": Bool(true),
    "hasLint": Bool(lint_findings is Some(_)),
  })
}
