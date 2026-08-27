// Components registry + ComponentStack lexical registration scope.

///|
pub fn Components::new() -> Components {
  { by_id: Map([]), }
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
/// The first component along the chain that PROVIDES `name` — the producer a
/// consumer never had to name.
///
/// Innermost frame first, and within a frame whichever registration answers
/// first. That is only a well-defined choice while one provide name has one
/// producer per chain, which is what `PROVIDE_NAME_COLLISION` holds authors to;
/// with two, this answers the innermost and the checker has already said the
/// name is ambiguous.
pub fn ComponentStack::lookup_provider(
  self : ComponentStack,
  name : String,
) -> Component? {
  for _, comp in self.by_name {
    if comp.provide.contains(name) {
      return Some(comp)
    }
  }
  match self.parent {
    Some(p) => p.lookup_provider(name)
    None => None
  }
}

///|
/// Where `*name` physically lives: the component that produces it, plus that
/// component's own steps to the value. What the render-target teleport splices
/// in.
///
/// A consumer no longer names its producer, so the producer is found by scope
/// search. A published TYPE answers `None` on purpose — a component has no
/// path, so `<x render="*Board">` must stay unresolvable rather than resolve to
/// something that cannot be edited through.
pub fn resolve_dyn_producer(comp : Component, name : String) -> DynProducer? {
  fn steps_of(val : @tutuca.Val) -> Array[@tutuca.Step] {
    match val.to_path_item() {
      Some(s) => [s]
      None => []
    }
  }

  if @tutuca.is_type_name(name) {
    return None
  }
  match comp.provide.get(name) {
    Some(p) => Some({ producer: comp.id, steps: steps_of(p.val), })
    None =>
      match comp.scope {
        Some(s) =>
          match s.lookup_provider(name) {
            Some(producer) =>
              match producer.provide.get(name) {
                Some(p) =>
                  Some({ producer: producer.id, steps: steps_of(p.val), })
                None => None
              }
            None => None
          }
        None => None
      }
  }
}

///|
/// The nearest value published under `name`, walking outward.
pub fn DynBinds::lookup(self : DynBinds, name : String) -> @tutuca.Value? {
  match self.binds.get(name) {
    Some(v) => Some(v)
    None =>
      match self.parent {
        Some(p) => p.lookup(name)
        None => None
      }
  }
}

///|
/// The nearest component TYPE published under `name`, walking outward. The
/// same walk as `lookup`, over the frame's other half — see `DynBinds`.
pub fn DynBinds::lookup_type(self : DynBinds, name : String) -> Int? {
  match self.types.get(name) {
    Some(id) => Some(id)
    None =>
      match self.parent {
        Some(p) => p.lookup_type(name)
        None => None
      }
  }
}
