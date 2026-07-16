// Port of src/components/tutuca/component-inspector.js — inspect a Component
// *descriptor* (the value returned by `@component.component(...)`), not a
// `.make()` instance.
//
// A `@component.Component` is not a `@tutuca.Value`, so the inspector takes a
// SNAPSHOT: `component_summary(comp)` returns a plain Value Map (the port of
// JS `introspectComponent`) and the components render that. Port deviations:
// - `statics` disappear (the port has no statics — they are plain functions).
// - the Methods section lists USER methods only: the port stores generated
//   field mutators (setX/toggleX/…) in the same table, so they are filtered
//   out by name to match what the JS inspector showed.
// - JS `expandAll`/`collapseAll`/`setAllSections`/`setAllViews` instance
//   methods exist only as the bubble handlers (`toggleAllSections` /
//   `toggleAllViews`) that the views actually dispatch.

///|
fn field_kind_name(k : @component.FieldKind) -> String {
  match k {
    FBool => "bool"
    FText => "text"
    FInt => "int"
    FFloat => "float"
    FList => "list"
    FMap => "map"
    FAny => "any"
    FComp(comp~, ..) => "comp(\{comp})"
    FSet => "set"
    FOMap => "omap"
  }
}

///|
/// The names `gen_mutators` derives for a field, used to filter generated
/// mutators out of the methods listing (mirrors component/component.mbt).
fn generated_method_names(
  fields : Map[String, @component.FieldSpec],
) -> Map[String, Bool] {
  let out : Map[String, Bool] = {}
  for name, spec in fields {
    let u = if name.length() == 0 {
      name
    } else {
      name[0:1].to_owned().to_upper() + name[1:].to_owned()
    }
    out["set" + u] = true
    out["reset" + u] = true
    out["update" + u] = true
    out[name + "Len"] = true
    match spec.kind {
      FBool => out["toggle" + u] = true
      FSet => {
        out["addIn" + u] = true
        out["deleteIn" + u] = true
        out["removeIn" + u] = true
        out["hasIn" + u] = true
        out["toggleIn" + u] = true
      }
      FList | FMap | FOMap => {
        out["pushIn" + u] = true
        out["insertIn" + u + "At"] = true
        out["setIn" + u + "At"] = true
        out["updateIn" + u + "At"] = true
        out["deleteIn" + u + "At"] = true
        out["removeIn" + u + "At"] = true
      }
      _ => ()
    }
  }
  out
}

///|
/// The pure snapshot the component inspector renders (JS introspectComponent):
/// name, id, fields (name/type/default), the handler-channel name lists, and
/// each view's raw template source.
pub fn component_summary(comp : @component.Component) -> @tutuca.Value {
  let fields : Array[@tutuca.Value] = []
  for name, spec in comp.fields {
    fields.push(
      Map({
        "name": Str(name),
        "type": Str(field_kind_name(spec.kind)),
        "default": spec.default,
      }),
    )
  }
  let generated = generated_method_names(comp.fields)
  let names = (keys : Iter[String]) => {
    let out : Array[@tutuca.Value] = []
    for k in keys {
      out.push(Str(k))
    }
    @tutuca.Value::List(out)
  }
  let methods : Array[@tutuca.Value] = []
  for k in comp.methods.keys() {
    if !generated.contains(k) {
      methods.push(Str(k))
    }
  }
  let views : Array[@tutuca.Value] = []
  for _name, view in comp.views {
    views.push(Map({ "name": Str(view.name), "rawView": Str(view.raw_view) }))
  }
  Map({
    "name": Str(comp.name),
    "id": Num(comp.id.to_double()),
    "fields": List(fields),
    "methods": List(methods),
    "input": names(comp.input.keys()),
    "receive": names(comp.receive.keys()),
    "bubble": names(comp.bubble.keys()),
    "response": names(comp.response.keys()),
    "alter": names(comp.alter.keys()),
    "views": List(views),
  })
}

// ---------------------------------------------------------------------------
// Components
// ---------------------------------------------------------------------------

///|
/// A single name entry — used for methods and the handler channels, all of
/// which are just lists of names.
fn comp_name_comp() -> @component.Component {
  @component.component(
    name="CompName",
    fields={ "name": @component.FieldSpec::of_default(Str("")) },
    view=(
      #|<span class="font-mono text-sm leading-tight badge badge-sm badge-ghost comp-name" @text=".name"></span>
    ),
  )
}

///|
/// A single field row: `name : type = <default value>`. The default value is
/// rendered with the data inspector so it can recurse/expand.
fn comp_field_comp() -> @component.Component {
  @component.component(
    name="CompField",
    fields={
      "name": @component.FieldSpec::of_default(Str("")),
      "typeName": @component.FieldSpec::of_default(Str("")),
      "child": @component.FieldSpec::of_default(Null),
    },
    view=(
      #|<div class="flex items-center gap-2 leading-tight comp-field">
      #|  <span class="text-base-content/70 font-mono text-sm" @text=".name"></span>
      #|  <span class="text-base-content/30">:</span>
      #|  <span class="text-base-content/50 font-mono text-xs" @text=".typeName"></span>
      #|  <span class="text-base-content/30">=</span>
      #|  <x render=".child"></x>
      #|</div>
    ),
  )
}

///|
/// Plain click toggles one collapsible; ctrl/cmd-click bubbles `bubble_name`
/// so the top-level inspector can toggle every one at once.
fn toggle_or_bubble(
  bubble_name : String,
) -> (@component.Instance, Array[@tutuca.Value], &@tutuca.Ctx) -> @component.Instance? {
  (inst, args, ctx) => {
    let is_ctrl = args.get(0) is Some(Bool(true))
    let expanded = bool_field(inst, "isExpanded")
    if is_ctrl {
      ctx.bubble(bubble_name, [Bool(!expanded)])
      Some(inst)
    } else {
      Some(inst.set("isExpanded", Bool(!expanded)))
    }
  }
}

///|
/// A single view: its name plus the raw template source in a code block. The
/// source collapses/expands independently.
fn comp_view_comp() -> @component.Component {
  @component.component(
    name="CompView",
    fields={
      "name": @component.FieldSpec::of_default(Str("")),
      "rawView": @component.FieldSpec::of_default(Str("")),
      "isExpanded": @component.FieldSpec::of_default(Bool(false)),
    },
    methods={
      "arrowText": (inst, _args) => {
        Str(if bool_field(inst, "isExpanded") { "▼" } else { "▶" })
      },
    },
    input={ "toggle": toggle_or_bubble("toggleAllViews") },
    view=(
      #|<div class="flex flex-col gap-0.5 leading-tight comp-view">
      #|  <button
      #|    type="button"
      #|    class="cursor-pointer text-base-content/70 hover:text-base-content inline-flex items-center gap-1 self-start"
      #|    @on.click="toggle isCtrl">
      #|    <span @text="$arrowText"></span>
      #|    <span class="font-mono text-sm comp-view-name" @text=".name"></span>
      #|  </button>
      #|  <pre @show=".isExpanded" class="text-xs bg-base-200 rounded p-2 overflow-x-auto whitespace-pre-wrap"><code @text=".rawView"></code></pre>
      #|</div>
    ),
  )
}

///|
/// A labelled, collapsible, paginated group of entries. Reuses the same
/// composite machinery the JSON inspector uses; neutral chrome — hierarchy
/// via weight, colour reserved for status/severity.
fn comp_section_comp() -> @component.Component {
  let fields = composite_fields()
  fields["label"] = @component.FieldSpec::of_default(Str(""))
  let methods = composite_methods(inst => str_field(inst, "label"), inst => {
    let n = items_of(inst).length()
    "(\{n})"
  })
  @component.component(
    name="CompSection",
    fields~,
    methods~,
    input={ "toggle": toggle_or_bubble("toggleAllSections") },
    alter=composite_alter(),
    view=make_composite_view(
      type_class="font-semibold comp-section",
      border_class="border-base-content/15",
      // Plain click toggles this section; ctrl/cmd-click bubbles up so the
      // inspector can toggle every section at once.
      toggle_handler="toggle isCtrl",
    ),
  )
}

///|
fn set_all_sections(
  inst : @component.Instance,
  state : Bool,
) -> @component.Instance {
  let sections = match inst.get("sections") {
    List(a) => a
    _ => []
  }
  inst.set(
    "sections",
    List(sections.map(s => obj_set(s, "isExpanded", Bool(state)))),
  )
}

///|
fn set_all_views(
  inst : @component.Instance,
  state : Bool,
) -> @component.Instance {
  let sections = match inst.get("sections") {
    List(a) => a
    _ => []
  }
  inst.set(
    "sections",
    List(
      sections.map(s => {
        if obj_get(s, "label") is Some(Str("Views")) {
          match obj_get(s, "items") {
            Some(List(views)) =>
              obj_set(
                s,
                "items",
                List(views.map(v => obj_set(v, "isExpanded", Bool(state)))),
              )
            _ => s
          }
        } else {
          s
        }
      }),
    ),
  )
}

///|
/// Top-level wrapper: one CompSection per non-empty group of the summary.
fn component_inspector_comp() -> @component.Component {
  @component.component(
    name="ComponentInspector",
    fields={
      "compName": @component.FieldSpec::of_default(Str("")),
      "compId": @component.FieldSpec::of_default(Num(0)),
      "sections": @component.FieldSpec::of_default(List([])),
    },
    methods={
      "idText": (inst, _args) => {
        let id = int_field(inst, "compId")
        Str("#\{id}")
      },
    },
    bubble={
      "toggleAllSections": (inst, args, _ctx) => {
        Some(set_all_sections(inst, args.get(0) is Some(Bool(true))))
      },
      "toggleAllViews": (inst, args, _ctx) => {
        Some(set_all_views(inst, args.get(0) is Some(Bool(true))))
      },
    },
    view=(
      #|<div class="font-mono text-sm leading-tight flex flex-col gap-1 component-inspector">
      #|  <div class="inline-flex items-center gap-2">
      #|    <span class="font-semibold comp-title" @text=".compName"></span>
      #|    <span class="text-base-content/40 text-xs" @text="$idText"></span>
      #|  </div>
      #|  <x render-each=".sections"></x>
      #|</div>
    ),
  )
}

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

///|
fn Inspector::comp_names_section(
  self : Inspector,
  label : String,
  names : @tutuca.Value,
) -> @tutuca.Value? {
  guard names is List(items) && items.length() > 0 else { return None }
  let rows = items.map(n => self.make_("CompName", args={ "name": n }))
  Some(
    self.make_("CompSection", args={ "label": Str(label), "items": List(rows) }),
  )
}

///|
/// Build a ComponentInspector instance from a `component_summary` snapshot
/// (JS ComponentInspector.Class.fromData). Empty groups are omitted.
pub fn Inspector::component_view(
  self : Inspector,
  summary : @tutuca.Value,
) -> @tutuca.Value {
  guard summary is Map(d) else { return self.inspect_value(summary) }
  let sections : Array[@tutuca.Value] = []
  // Fields start expanded — the most useful section when inspecting.
  match d.get("fields") {
    Some(List(fields)) if fields.length() > 0 => {
      let rows = fields.map(f => {
        let name = match f {
          Map(fm) => fm.get("name").unwrap_or(Null)
          _ => @tutuca.Value::Null
        }
        let type_name = match f {
          Map(fm) => fm.get("type").unwrap_or(Str(""))
          _ => Str("")
        }
        let dflt = match f {
          Map(fm) => fm.get("default").unwrap_or(Null)
          _ => @tutuca.Value::Null
        }
        self.make_("CompField", args={
          "name": name,
          "typeName": type_name,
          "child": self.inspect_value(dflt),
        })
      })
      sections.push(
        self.make_("CompSection", args={
          "label": Str("Fields"),
          "items": List(rows),
          "isExpanded": Bool(true),
        }),
      )
    }
    _ => ()
  }
  for
    group in [
      ("Methods", "methods"),
      ("Input", "input"),
      ("Receive", "receive"),
      ("Bubble", "bubble"),
      ("Response", "response"),
      ("Alter", "alter"),
    ] {
    let (label, key) = group
    match self.comp_names_section(label, d.get(key).unwrap_or(Null)) {
      Some(s) => sections.push(s)
      None => ()
    }
  }
  match d.get("views") {
    Some(List(views)) if views.length() > 0 => {
      let rows = views.map(v => {
        match v {
          Map(vm) =>
            self.make_("CompView", args={
              "name": vm.get("name").unwrap_or(Str("")),
              "rawView": vm.get("rawView").unwrap_or(Str("")),
            })
          _ => @tutuca.Value::Null
        }
      })
      sections.push(
        self.make_("CompSection", args={
          "label": Str("Views"),
          "items": List(rows),
        }),
      )
    }
    _ => ()
  }
  self.make_("ComponentInspector", args={
    "compName": d.get("name").unwrap_or(Str("")),
    "compId": d.get("id").unwrap_or(Num(0)),
    "sections": List(sections),
  })
}

///|
/// Snapshot + render in one step (JS ComponentInspector.Class.fromData(comp)).
pub fn Inspector::inspect_component(
  self : Inspector,
  comp : @component.Component,
) -> @tutuca.Value {
  self.component_view(component_summary(comp))
}
