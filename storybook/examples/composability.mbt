// Teaches: composing independent example apps as fields of one root. A
// declared slot plus `slot_args~`
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
fn composability_comp(
  json_args : Map[String, @tutuca.Value],
  dnd_args : Map[String, @tutuca.Value],
) -> @component.Component {
  composability_component(
    initial={ ..ComposabilityState::zero(), activeSection: "todo", },
    // The component each slot holds is part of its declared type; the
    // arguments it is BUILT with are a value, which no type states.
    // `DnDExample` has adjacent capitals, which kebab-case cannot round-trip
    // (`d-n-d-example` comes back as `DNDExample`), so this one slot names its
    // component here rather than in the block.
    slots={ "dnd": "DnDExample" },
    slot_args={ "json": json_args, "dnd": dnd_args },
    update=(s, msg, ctx) => {
      match msg {
        // forward the host's init to the personal-site sub-app, which loads
        // its data through a request handler
        Receive("init", _) => {
          ctx.send_at_path(
            ctx.path().concat([FieldStep("personalSite")]),
            "init",
            [],
          )
          Next(s)
        }
        _ => Unhandled
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
  let intents : Map[String, Array[@component.IntentFn]] = Map([])
  for m in [todo, json, tree, personal_site, visual_wasm, dnd] {
    for k, v in m.macros {
      macros[k] = v
    }
    for k, v in m.intents {
      intents[k] = v
    }
  }
  @component.ModuleDef::new(
    name="composability",
    components~,
    macros~,
    intents~,
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
