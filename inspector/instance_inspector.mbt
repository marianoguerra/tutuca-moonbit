// Port of src/components/tutuca/instance-inspector.js — the field → value
// rows of a live component instance, plus a tabbed explorer over one
// instance (values / definition / lint).
//
// Port deviations:
// - JS resolved the descriptor via `scope.getCompFor(value)`; a port
//   `@component.Instance` carries its own Component, so `inspect_instance`
//   takes the instance directly. For a plain `Value` (e.g. an observe
//   record's before/after) use `inspect_value_as_instance` with the comp from
//   `Components::get_comp_for`.
// - the Tests tab is gone: test-inspector.js is not ported (`moon test` is
//   the runner here; there is no in-app test-report data source).

///|
/// The pure snapshot of an instance: its component name plus a field → value
/// Map in declaration order.
pub fn instance_snapshot(inst : @component.Instance) -> @tutuca.Value {
  let fields : Map[String, @tutuca.Value] = {}
  for name, _spec in inst.comp.fields {
    fields[name] = inst.get(name)
  }
  Map({ "name": Str(inst.comp.name), "fields": Map(fields) })
}

///|
/// The same snapshot for an instance reached as a plain Value (field names
/// come from the descriptor, values through the Obj trait).
fn value_snapshot(
  v : @tutuca.Value,
  comp : @component.Component,
) -> @tutuca.Value {
  let fields : Map[String, @tutuca.Value] = {}
  for name, _spec in comp.fields {
    fields[name] = obj_get(v, name).unwrap_or(Null)
  }
  Map({ "name": Str(comp.name), "fields": Map(fields) })
}

///|
/// The field → value rows of an instance. Field names/order come from the
/// snapshot; each value renders (and recurses) like the other inspectors.
fn instance_fields_comp() -> @component.Component {
  let fields = composite_fields()
  fields["typeName"] = @component.FieldSpec::of_default(Str(""))
  let methods = composite_methods(inst => str_field(inst, "typeName"), inst => {
    let n = items_of(inst).length()
    "{\{n}}"
  })
  @component.component(
    name="InstanceFields",
    fields~,
    methods~,
    alter=composite_alter(),
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
    fields={ "value": @component.FieldSpec::of_default(Null) },
    methods={ "toggleIsExpanded": wrapper_toggle },
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
/// JS InstanceInspector.Class.fromData(instance, comp) for a live Instance.
pub fn Inspector::inspect_instance(
  self : Inspector,
  inst : @component.Instance,
) -> @tutuca.Value {
  self.make_("InstanceInspector", args={
    "value": self.instance_fields_from(instance_snapshot(inst)),
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
    Some(c) => self.instance_fields_from(value_snapshot(v, c))
    None => self.classify(v)
  }
  self.make_("InstanceInspector", args={ "value": value })
}

///|
/// Up to three tabs over one instance: its values (InstanceInspector), its
/// definition (ComponentInspector) and — when provided — its lint findings
/// (LintReport). A tab only appears when it has content.
fn instance_explorer_comp() -> @component.Component {
  @component.component(
    name="InstanceExplorer",
    fields={
      "activeTab": @component.FieldSpec::of_default(Str("instance")),
      "instanceView": @component.FieldSpec::of_default(Null),
      "componentView": @component.FieldSpec::of_default(Null),
      "lintView": @component.FieldSpec::of_default(Null),
      "hasComponent": @component.FieldSpec::of_default(Bool(false)),
      "hasLint": @component.FieldSpec::of_default(Bool(false)),
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
  inst : @component.Instance,
  lint_findings? : Array[@tutuca.Value],
) -> @tutuca.Value {
  let lint_view = match lint_findings {
    Some(findings) => self.lint_report(findings)
    None => @tutuca.Value::Null
  }
  self.make_("InstanceExplorer", args={
    "instanceView": self.inspect_instance(inst),
    "componentView": self.inspect_component(inst.comp),
    "lintView": lint_view,
    "hasComponent": Bool(true),
    "hasLint": Bool(lint_findings is Some(_)),
  })
}
