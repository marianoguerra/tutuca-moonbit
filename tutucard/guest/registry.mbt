///|
/// Every module instantiated on this page, by the key it was loaded under.
///
/// A PAGE-level table, because a page that holds an arrangement holds several
/// modules at once and a component from one of them can end up inside a
/// component from another. What it holds is the module — not a table of that
/// module's instances, which is the thing this seam stopped needing.
let modules : Map[String, @browser.NativeModule] = Map([])

///|
let hosted : Map[String, @host.Module] = Map([])

///|
pub fn module_of(key : String) -> @host.Module? {
  hosted.get(key)
}

///|
/// Forget a module, before it is instantiated again or after it is unmounted.
pub fn drop_module(key : String) -> Unit {
  modules.remove(key)
  hosted.remove(key)
}

///|
pub fn loaded_keys() -> Array[String] {
  hosted.keys().to_array()
}

///|
/// Register a card `card.js` has already instantiated.
///
/// The manifest is read off the MODULE rather than passed in. It travelled
/// separately when it had to — a JSON seam has no way to ask — and travelling
/// separately is how a manifest gets paired with a different module than the
/// one it describes.
pub fn register(
  key : String,
  scope : @component.ComponentStack,
  policy : @policy.Policy,
) -> Result[@host.Module, String] {
  drop_module(key)
  guard native_ready(key) else {
    return Err("no compiled card is instantiated under `\{key}`")
  }
  let native = @browser.NativeModule::new(key, native_rt(key), native_ex(key), peer => {
    modules.get(peer)
  })
  modules[key] = native
  let loaded = try {
    let manifest = @host.DynManifest::from_json_string(native.manifest_json())
    @host.register_module(scope, native, manifest, policy~)
  } catch {
    e => {
      modules.remove(key)
      return Err(e.message())
    }
  }
  // The module needs its own host record to wrap an instance as a `DynObj`,
  // and `register_module` takes the module and cannot also return into it.
  native.adopted(loaded)
  hosted[key] = loaded
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
/// What the card has SAID since this was last asked — a declined `requires`, an
/// `ensures` that did not hold, with the rule's own sentence over the state it
/// rejected. A host component raises a structured refusal for the same event; a
/// guest has no shape to put one in, so this is the whole of what it can say.
pub fn take_log(key : String) -> Array[String] {
  let raw = native_log(key)
  if raw == "" {
    []
  } else {
    raw.split("\n").map(l => l.to_owned()).collect()
  }
}

///|
/// A `&GuestModule` over a card `card.js` has instantiated, before it is
/// registered.
///
/// `register` is the ordinary door and does both halves. This is for a caller
/// that has to hold the module first and be told the host's record afterwards —
/// `tutucard/drive` takes the module, builds it, and hands it back through
/// `on_bundle`.
pub fn native_of(key : String) -> @browser.NativeModule? {
  if !native_ready(key) {
    return None
  }
  let m = @browser.NativeModule::new(key, native_rt(key), native_ex(key), peer => {
    modules.get(peer)
  })
  modules[key] = m
  Some(m)
}

///|
/// Tell a module the host's record of it, and the page's table too.
pub fn adopt(
  key : String,
  native : @browser.NativeModule,
  m : @host.Module,
) -> Unit {
  native.adopted(m)
  hosted[key] = m
}

///|
/// The manifest a module gives of itself.
pub fn manifest_json(key : String) -> String {
  match modules.get(key) {
    Some(m) => m.manifest_json()
    None => "{}"
  }
}

///|
/// Whether a compiled card is instantiated under this key.
pub extern "js" fn native_ready(key : String) -> Bool =
  #|(key) => !!(globalThis.__tgcmod && globalThis.__tgcmod[key])

///|
extern "js" fn native_rt(key : String) -> @core.Any =
  #|(key) => globalThis.__tgcmod[key].rt

///|
extern "js" fn native_ex(key : String) -> @core.Any =
  #|(key) => globalThis.__tgcmod[key].ex

///|
extern "js" fn native_log(key : String) -> String =
  #|(key) => { const b = globalThis.__cardlog?.[key] ?? []; const out = b.join("\n"); b.length = 0; return out; }
