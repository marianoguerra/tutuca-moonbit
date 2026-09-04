///|
/// Every module instantiated on this page, by the key it was loaded under.
///
/// A PAGE-level table, because a page that holds an arrangement holds several
/// modules at once and a component from one of them can end up inside a
/// component from another. `card.js` keeps the matching table of instances for
/// the same reason: a name that does not say which module it belongs to cannot
/// be resolved by a host holding two.
let modules : Map[String, @host.Module] = Map([])

///|
/// Remember a registered module under the key its guest was loaded as.
pub fn adopt(key : String, loaded : @host.Module) -> Unit {
  modules[key] = loaded
}

///|
pub fn module_of(key : String) -> @host.Module? {
  modules.get(key)
}

///|
/// Forget a module, before it is instantiated again or after it is unmounted.
pub fn drop_module(key : String) -> Unit {
  modules.remove(key)
}

///|
pub fn loaded_keys() -> Array[String] {
  modules.keys().to_array()
}

///|
/// Instantiate a card and register it, in one call.
///
/// The two halves travel together on purpose: a manifest's field list is the
/// order `get-field` answers in, so a manifest paired with a different module is
/// a module whose halves disagree.
pub fn register(
  key : String,
  manifest_json : String,
  scope : @component.ComponentStack,
  policy : @policy.Policy,
) -> Result[@host.Module, String] {
  drop_module(key)
  // The guest is built BEFORE it is registered and told about the module
  // afterwards, which is the only order available: `register_module` takes the
  // guest, and the guest needs the module to wrap a child token. Nothing can
  // call the guest in between.
  let guest = CardGuest::{ key, registered: Ref(None), }
  let loaded = try {
    let manifest = @host.DynManifest::from_json_string(manifest_json)
    @host.register_module(scope, guest, manifest, policy~)
  } catch {
    e => return Err(e.message())
  }
  guest.registered.val = Some(loaded)
  adopt(key, loaded)
  Ok(loaded)
}

///|
/// Build one component of one loaded module.
pub fn make_instance(
  key : String,
  component : String,
  args? : Map[String, @tutuca.Value] = Map([]),
) -> @tutuca.Value? {
  match module_of(key) {
    Some(loaded) =>
      match loaded.make_instance(component, args~) {
        Some(inst) => Some(inst.to_value())
        None => None
      }
    None => None
  }
}

///|
/// The instance a `$dyn` marker names, wrapped by the module that MADE it.
///
/// The marker carries the module because a component name is only unique inside
/// one, and resolving it against whichever module happened to be decoding is
/// how a note came back wearing a hole's schema — its fields, its views, its
/// guest — with nothing failing anywhere.
///
/// `fallback` is the decoding module, and it is only reached for a marker from
/// a build that predates the key.
fn wrap_marked(
  module_ : String,
  comp : String,
  handle : Int,
  fallback : @host.Module?,
) -> @tutuca.Value {
  let owner = match module_of(module_) {
    Some(m) => Some(m)
    None => fallback
  }
  match owner {
    Some(loaded) =>
      match loaded.wrap_instance(comp, handle) {
        Some(v) => v
        None => Null
      }
    None => Null
  }
}
