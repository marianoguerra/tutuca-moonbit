// Port of docs/examples/composability.js.
//
// Teaches: composing independent example apps as fields of one root. The JS
// module seeds each field with the sub-app's getRoot() instance; the port
// leans on the designed mechanism instead — `FieldSpec::comp(name, args~)`
// builds each child through the registration scope at make() time, with the
// args taken from the sub-module's own ExampleDef (the same seed the
// standalone example mounts with).

///|
fn example_args(
  m : @component.ModuleDef,
  title : String,
) -> Map[String, @tutuca.Value] {
  for e in m.examples {
    if e.title == title {
      return e.args
    }
  }
  Map([])
}

///|
priv struct ComposabilityState {
  activeSection : String
} derive(ToJson, FromJson)

///|
fn composability_comp(
  json_args : Map[String, @tutuca.Value],
  dnd_args : Map[String, @tutuca.Value],
) -> @component.Component {
  @component.component(
    views=composability_views(),
    name="Composability",
    init=ComposabilityState::{ activeSection: "todo" },
    specs={
      "todo": @component.FieldSpec::comp("Items"),
      "json": @component.FieldSpec::comp("JsonArray", args=json_args),
      "tree": @component.FieldSpec::comp("TreeRoot"),
      "personalSite": @component.FieldSpec::comp("Root"),
      "visualWasm": @component.FieldSpec::comp("Module"),
      "dnd": @component.FieldSpec::comp("DnDExample", args=dnd_args),
    },
    update=(s : ComposabilityState, msg, ctx) => {
      match msg {
        // forward the host's init to the personal-site sub-app, which loads
        // its data through a request handler
        Receive("init", _) => {
          ctx.send_at_path(
            ctx.path().concat([FieldStep("personalSite")]),
            "init",
            [],
          )
          Some(s)
        }
        _ => None
      }
    },
  )
}

///|
pub fn composability_module() -> @component.ModuleDef {
  let todo = todo_module()
  let json = json_module()
  let tree = tree_module()
  let personal_site = personal_site_module()
  let visual_wasm = visual_wasm_module()
  let dnd = dnd_module()
  let components : Array[@component.Component] = [
    composability_comp(
      example_args(json, "Empty Array With Selector"),
      example_args(dnd, "Default"),
    ),
  ]
  for m in [todo, json, tree, personal_site, visual_wasm, dnd] {
    components.append(m.components)
  }
  // the sub-apps' macros (visual-wasm) and request handlers (personal-site)
  let macros : Map[String, @anode.Macro] = Map([])
  let requests : Map[String, @component.RequestFn] = Map([])
  for m in [todo, json, tree, personal_site, visual_wasm, dnd] {
    for k, v in m.macros {
      macros[k] = v
    }
    for k, v in m.requests {
      requests[k] = v
    }
  }
  @component.ModuleDef::new(
    name="composability",
    components~,
    macros~,
    requests~,
    examples=[
      {
        component: "Composability",
        title: "Default (To-Do tab)",
        args: Map([]),
        view: None,
      },
      {
        component: "Composability",
        title: "JSON Editor Selected",
        args: { "activeSection": Str("json") },
        view: None,
      },
      {
        component: "Composability",
        title: "Tree Selected",
        args: { "activeSection": Str("tree") },
        view: None,
      },
    ],
  )
}
