// Dynamic bindings — a producer publishes a value under a name; any
// descendant reads it as `*name` (provide / lookup), and `*name` also works
// as a RENDER TARGET (teleport).
// `provide` must be ADDRESSABLE (a field or a `.seq[.key]` access), because it
// doubles as the teleport path — a method or a constant is a lint error.

///|
fn selector_entry_comp() -> @component.Component {
  selector_entry_component(init={ value: "entry-value", label: "Entry Label", })
}

///|
/// The CONSUMER: it has no items of its own, it reads the producer's list as
/// `*entries`. The `default` is used only when no producer is in the render
/// stack.
fn selector_comp() -> @component.Component {
  selector_component(init={ items: [], selectedValue: Null, }, lookup=[
    @component.lookup_or("entries", ".items"),
  ])
}

///|
/// The PRODUCER: every `provide` is evaluated and pushed onto the stack when the
/// component is entered during render — there is no hook to opt in.
fn entry_editor_comp(entry : @component.Component) -> @component.Component {
  entry_editor_and_selector_component(
    init={ ..EntryEditorAndSelectorState::zero(), items: [], },
    provide={ "entries": ".items" },
    update=(s, msg, _ctx) => {
      match EntryEditorAndSelectorMsg::from_dispatch(msg) {
        // Served by the mutators generated from the state's fields: the
        // view spells them bare now, so they arrive as Inputs, and
        // returning None falls through to them.
        Some(RemoveInItemsAt(_)) => Unhandled
        Some(OnAddItem) => {
          let num = s.items.length() + 1
          Next({
            ..s,
            items: s.items +
            [
              entry.make({
                "value": Str("entry-\{num}"),
                "label": Str("Entry #\{num}"),
              }),
            ],
          })
        }
        Some(Unknown(_, _)) | None => Unhandled
      }
    },
  )
}

///|
pub fn dynamic_bindings_module() -> @component.ModuleDef {
  let entry = selector_entry_comp()
  @component.ModuleDef::new(
    name="dynamic-bindings",
    components=[entry_editor_comp(entry), selector_comp(), entry],
    examples=[
      {
        component: "EntryEditorAndSelector",
        title: "Default",
        args: Map([]),
        view: None,
      },
      {
        component: "EntryEditorAndSelector",
        title: "With Entries",
        args: {
          "items": List([
            entry.make({ "value": Str("a"), "label": Str("Alpha") }),
            entry.make({ "value": Str("b"), "label": Str("Beta") }),
          ]),
        },
        view: None,
      },
    ],
  )
}

///|
/// A dynamic var resolves to a VALUE, so it works anywhere a value is read —
/// including as a component-render target: `<x render="*active">`.
fn sheet_comp() -> @component.Component {
  sheet_component(init={ title: "untitled", })
}

///|
/// The consumer, far from the producer: it renders a component it does not own.
fn toolbar_comp() -> @component.Component {
  toolbar_component(lookup=[@component.lookup_or("active", ".missing")])
}

///|
fn panel_comp() -> @component.Component {
  panel_component()
}

///|
/// The producer. The Sheet rendered inside Toolbar physically lives HERE, at
/// `Workspace.sheet` — so editing its title TELEPORTS: the event path is
/// expanded through Workspace → Panel → Toolbar for reconstruction, but the
/// transaction lands on `Workspace.sheet`. The echoed title at the top is the
/// proof; it updates in lock-step.
fn workspace_comp() -> @component.Component {
  workspace_component(provide={ "active": ".sheet" }, compute=m => {
    match m {
      SheetTitle =>
        Some((s, _args, _stack) => {
          match s.sheet {
            Obj(o) => o.obj_field("title").unwrap_or(Str(""))
            _ => Str("")
          }
        })
    }
  })
}

///|
pub fn dynamic_path_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="dynamic-path",
    components=[workspace_comp(), panel_comp(), toolbar_comp(), sheet_comp()],
    examples=[
      { component: "Workspace", title: "Default", args: Map([]), view: None, },
    ],
  )
}
