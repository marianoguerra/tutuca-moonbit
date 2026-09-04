///| The arrangement, saved and restored.
///
/// What is stored is `to_component_json` over the canvas — the component tree
/// IS the layout, so there is nothing beside it to keep in step. Rebuilding it
/// is `from_component_json` over a source that resolves a name against the
/// catalog and builds through the module that owns it.

///|
extern "js" fn store_write(key : String, value : String) -> Unit =
  #|(k, v) => { try { localStorage.setItem(k, v); } catch (e) {} }

///|
extern "js" fn store_read(key : String) -> String =
  #|(k) => { try { return localStorage.getItem(k) ?? ""; } catch (e) { return ""; } }

///|
/// Where a saved arrangement resolves a component name.
///
/// The app's own `ComponentStack` cannot answer: `register_module` puts a
/// module's components in a CHILD scope, so the root scope has never heard of
/// them by name. The catalog has, and it knows which module owns each name.
fn saved_source() -> @tutuca.FnSource {
  @tutuca.FnSource::new(
    (module_, component, args, _at) => {
      let want = module_.unwrap_or("")
      guard catalog.find(component, module_=want) is Some(entry) else {
        return None
      }
      @guest.make_instance(entry.ref_.module_, entry.ref_.name, args~)
    },
    describe=(module_, component) => {
      let want = module_.unwrap_or("")
      guard catalog.find(component, module_=want) is Some(entry) else {
        return None
      }
      match @guest.module_of(entry.ref_.module_) {
        Some(loaded) => loaded.schema_of(entry.ref_.name)
        None => None
      }
    },
  )
}

///|
fn save() -> Unit {
  guard live.val is Some(app) else { return }
  let canvas = app.root_value().field("canvas")
  if canvas is Null {
    note("there is nothing on the canvas to save")
    return
  }
  // The module keys travel BESIDE the tree, because the tree names components
  // and not the modules they came from — so a restore can say which card to
  // load rather than quietly dropping the cells it could not build.
  let doc = Json::object({
    "modules": Json::array(@guest.loaded_keys().map(Json::string)),
    "tree": canvas.to_component_json(),
  })
  store_write(@ui.saved_key, doc.stringify())
  note("saved")
}

///|
fn restore() -> Unit {
  guard live.val is Some(app) else { return }
  let raw = store_read(@ui.saved_key)
  if raw == "" {
    note("there is nothing saved")
    return
  }
  let doc = @json.parse(raw) catch {
    _ => {
      note("what is saved is not readable", tone="error")
      return
    }
  }
  guard doc is Object(o) else {
    note("what is saved is not an arrangement", tone="error")
    return
  }
  // NAME THE MISSING ONES. A component whose module is not loaded decodes to
  // nothing, and `decode_field` treats nothing as "omit the field" — so the
  // cell comes back as an empty `+`. That is the right outcome and it must not
  // be the silent one.
  match o.get("modules") {
    Some(Array(keys)) => {
      let here = @guest.loaded_keys()
      for k in keys {
        if k is String(name) && !here.contains(name) {
          note(
            "`\{name}` is not loaded, so anything it drew comes back empty — load it and restore again",
            tone="error",
          )
        }
      }
    }
    _ => ()
  }
  guard o.get("tree") is Some(tree) else {
    note("what is saved has no arrangement in it", tone="error")
    return
  }
  let src = saved_source()
  guard @tutuca.Value::from_component_json(tree, src) is Some(canvas) else {
    note("the arrangement could not be rebuilt", tone="error")
    return
  }
  @ui.forget_cell()
  app.send_at_root("placeBuilt", args=[canvas, Bool(false)]) |> ignore
  note("restored")
}

///|
/// Back to one empty hole, which is where the page starts.
fn clear_canvas() -> Unit {
  guard live.val is Some(app) else { return }
  guard @guest.make_instance(@std.module_name(), "Hole") is Some(hole) else {
    note("the layout kit is not loaded", tone="error")
    return
  }
  @ui.forget_cell()
  app.send_at_root("placeBuilt", args=[hole, Bool(false)]) |> ignore
}
