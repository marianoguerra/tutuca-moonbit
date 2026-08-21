// Components registry + ComponentStack lexical registration scope.

///|
pub fn Components::new() -> Components {
  { by_id: Map([]) }
}

///|
pub fn Components::register(self : Components, comp : Component) -> Unit {
  self.by_id[comp.id] = comp
}

///|
pub fn Components::get_component_for_id(
  self : Components,
  id : Int,
) -> Component? {
  self.by_id.get(id)
}

///|
pub fn Components::get_comp_for(
  self : Components,
  v : @tutuca.Value,
) -> Component? {
  match v {
    Obj(o) =>
      match o.component_id() {
        Some(id) => self.by_id.get(id)
        None => None
      }
    _ => None
  }
}

///|
pub fn Components::compile_styles(self : Components) -> String {
  let sb = StringBuilder()
  for _, comp in self.by_id {
    sb <+ "\{comp.compile_style()}"
  }
  sb.to_string()
}

///|
/// Every class name the registered components' compiled views can show, for a
/// margaui-style scanner. Walks each component's compiled view roots via
/// ANode::collect_classes; the caller hands the result to a margaui compiler
/// (the demos pass it to demo/margaui's compile_classes — the MoonBit
/// marianoguerra/tailwindcss port — then inject the CSS: tutuca collects,
/// margaui compiles). Sorted for a stable order across runs. Call after compile.
pub fn Components::collect_classes(self : Components) -> Array[String] {
  let into : Set[String] = Set([])
  for _, comp in self.by_id {
    for _, view in comp.views {
      match view.anode {
        Some(node) => node.collect_classes(into)
        None => ()
      }
    }
  }
  let classes = into.to_array()
  classes.sort()
  classes
}

///|
pub fn ComponentStack::new(comps? : Components) -> ComponentStack {
  {
    comps: match comps {
      Some(c) => c
      None => Components::new()
    },
    parent: None,
    by_name: Map([]),
    intents: Map([]),
    macros: Map([]),
  }
}

///|
pub fn ComponentStack::enter(self : ComponentStack) -> ComponentStack {
  {
    comps: self.comps,
    parent: Some(self),
    by_name: Map([]),
    intents: Map([]),
    macros: Map([]),
  }
}

///|
pub fn ComponentStack::register_components(
  self : ComponentStack,
  comps : Array[Component],
  aliases? : Map[String, String] = Map([]),
) -> Unit {
  for comp in comps {
    comp.scope = Some(self.enter()) // fresh scope per comp (JS)
    self.comps.register(comp)
    self.by_name[comp.name] = comp
  }
  for alias_name, target in aliases {
    match self.lookup_component(target) {
      Some(c) => self.by_name[alias_name] = c
      None => ()
    }
  }
}

///|
pub fn ComponentStack::register_macros(
  self : ComponentStack,
  macros : Map[String, @anode.Macro],
) -> Unit {
  for k, m in macros {
    self.macros[k] = m
  }
}

///|
pub fn ComponentStack::lookup_component(
  self : ComponentStack,
  name : String,
) -> Component? {
  match self.by_name.get(name) {
    Some(c) => Some(c)
    None =>
      match self.parent {
        Some(p) => p.lookup_component(name)
        None => None
      }
  }
}

///|
pub fn ComponentStack::register_intent_handlers(
  self : ComponentStack,
  handlers : Map[String, Array[IntentFn]],
) -> Unit {
  for k, hs in handlers {
    match self.intents.get(k) {
      // Appended rather than replaced: two registrations of one name are two
      // candidates, in registration order, and the walk asks both. Replacing
      // would only make sense if a handler had to answer; because an
      // `IntentFn` may answer `Pass` and decline, the second registration is a
      // fallback rather than a shadow.
      Some(existing) => existing.append(hs)
      None => self.intents[k] = hs.copy()
    }
  }
}

///|
pub fn ComponentStack::lookup_intent(
  self : ComponentStack,
  name : String,
) -> Array[IntentFn] {
  let out : Array[IntentFn] = []
  for frame = Some(self) {
    match frame {
      Some(s) => {
        match s.intents.get(name) {
          Some(hs) => out.append(hs)
          None => ()
        }
        continue s.parent
      }
      None => break
    }
  }
  out
}

///|
pub impl @anode.MacroScope for ComponentStack with fn lookup_macro(self, name) {
  match self.macros.get(name) {
    Some(m) => Some(m)
    None =>
      match self.parent {
        Some(p) => p.lookup_macro(name)
        None => None
      }
  }
}

///|
pub fn ComponentStack::compile_all(self : ComponentStack) -> Unit raise {
  for _, comp in self.comps.by_id {
    comp.compile()
  }
}

///|
pub fn resolve_dyn_producer(comp : Component, name : String) -> DynProducer? {
  fn steps_of(val : @tutuca.Val) -> Array[@tutuca.Step] {
    match val.to_path_item() {
      Some(s) => [s]
      None => []
    }
  }

  match comp.lookup.get(name) {
    Some(lk) =>
      match comp.scope {
        Some(s) =>
          match s.lookup_component(lk.comp_name) {
            Some(producer) =>
              match producer.provide.get(lk.provide_name) {
                Some(p) =>
                  Some({ producer: producer.id, steps: steps_of(p.val) })
                None => None
              }
            None => None
          }
        None => None
      }
    None =>
      match comp.provide.get(name) {
        Some(p) => Some({ producer: comp.id, steps: steps_of(p.val) })
        None => None
      }
  }
}

///|
pub fn DynBinds::lookup(self : DynBinds, key : ProvideKey) -> @tutuca.Value? {
  match self.binds.get(key) {
    Some(v) => Some(v)
    None =>
      match self.parent {
        Some(p) => p.lookup(key)
        None => None
      }
  }
}
