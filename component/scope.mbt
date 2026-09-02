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
    paths: Map([]),
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
    paths: Map([]),
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
pub fn ComponentStack::register_paths(
  self : ComponentStack,
  paths : Map[String, @tutuca.Path],
) -> Unit {
  for name, path in paths {
    // A registered path is a VALUE position; the type keyspace is published as
    // a component id and never as an address. `provide_kind` is asked with no
    // source, since there is none to read here.
    if provide_kind(name) is ProvideValue {
      self.paths[name] = path
    }
  }
}

///|
pub fn ComponentStack::lookup_path(
  self : ComponentStack,
  name : String,
) -> @tutuca.Path? {
  match self.paths.get(name) {
    Some(path) => Some(path)
    None =>
      match self.parent {
        Some(parent) => parent.lookup_path(name)
        None => None
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
/// Whether some component visible in this registration chain can publish
/// `name` at runtime. This is only the checker's existence test; the live
/// render stack decides which provider is nearest for an instance.
fn ComponentStack::has_provider(self : ComponentStack, name : String) -> Bool {
  for _, comp in self.by_name {
    if comp.provide.contains(name) {
      return true
    }
  }
  match self.parent {
    Some(p) => p.has_provider(name)
    None => false
  }
}

///|
/// The nearest located value published under `name`, walking outward.
pub fn DynBinds::lookup_located(
  self : DynBinds,
  name : String,
) -> LocatedValue? {
  match self.binds.get(name) {
    Some(v) => Some(v)
    None =>
      match self.parent {
        Some(p) => p.lookup_located(name)
        None => None
      }
  }
}

///|
/// The nearest value published under `name`, walking outward.
pub fn DynBinds::lookup(self : DynBinds, name : String) -> @tutuca.Value? {
  match self.lookup_located(name) {
    Some(v) => Some(v.value)
    None => None
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
