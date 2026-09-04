///|
/// The probe, installed on `globalThis.__twomod` when this script loads.
fn main {
  install()
}

///|
extern "js" fn install_probe(
  register : (String, String) -> String,
  mount : (String, String, String, String, String) -> String,
  mount_empty : (String, String) -> String,
  hold : (String, String, String) -> String,
  send : (String, String) -> String,
  click : (String) -> String,
  html : () -> String,
) -> Unit =
  #|(register, mount, mountEmpty, hold, send, click, html) => {
  #|  globalThis.__twomod = { register, mount, mountEmpty, hold, send, click, html };
  #|}

///|
/// ONE scope, which is the arrangement a page holding two cards is in:
/// `register_module` enters a child scope per module, so names are isolated and
/// ids are shared — and sharing ids is what lets a component from one module be
/// held by a component from another.
let scope : @component.ComponentStack = @component.ComponentStack::new()

///|
let live : Ref[@harness.Harness[@memdom.MemNode]?] = Ref(None)

///|
fn install() -> Unit {
  install_probe(
    (key, manifest) => register(key, manifest),
    (hk, hc, hf, ck, cc) => mount(hk, hc, hf, ck, cc),
    (hk, hc) => mount_empty(hk, hc),
    (name, ck, cc) => hold(name, ck, cc),
    (name, arg) => send(name, arg),
    sel => click(sel),
    () => current_html(),
  )
}

///|
/// Register a module whose guest `card.js` has already instantiated.
fn register(key : String, _manifest_json : String) -> String {
  match @guest.register(key, scope, @policy.Policy::granted()) {
    Ok(_) => "ok"
    Err(reason) => "refused: " + reason
  }
}

///|
/// Build the child, put it in the holder's field, mount the holder.
fn mount(
  holder_key : String,
  holder_comp : String,
  holder_field : String,
  child_key : String,
  child_comp : String,
) -> String {
  guard @guest.make_instance(child_key, child_comp) is Some(child) else {
    return "could not build \{child_key}/\{child_comp}"
  }
  let args : Map[String, @tutuca.Value] = Map([])
  args[holder_field] = child
  guard @guest.make_instance(holder_key, holder_comp, args~) is Some(holder) else {
    return "could not build \{holder_key}/\{holder_comp}"
  }
  mount_value(holder)
}

///|
fn mount_value(root : @tutuca.Value) -> String {
  let (doc, container) = @harness.new_mount()
  let app = @app.App::new(scope, root, container, @vdom.RenderOpts::new(doc)) catch {
    e => return "would not mount: \{e}"
  }
  app.start()
  live.val = Some(@harness.Harness::over(app, container))
  current_html()
}

///|
/// Mount the holder EMPTY, the way a page does: a hole exists before anything
/// is put in it, and what goes in arrives later as a message.
fn mount_empty(holder_key : String, holder_comp : String) -> String {
  guard @guest.make_instance(holder_key, holder_comp) is Some(holder) else {
    return "could not build \{holder_key}/\{holder_comp}"
  }
  mount_value(holder)
}

///|
/// Send the holder a message carrying a component from another module.
///
/// This is the path a placement actually takes — the hole is built empty and
/// filled by a `receive`, rather than handed its child as a construction
/// argument — and the two are not the same crossing.
fn hold(name : String, child_key : String, child_comp : String) -> String {
  guard live.val is Some(h) else { return "nothing is mounted" }
  guard @guest.make_instance(child_key, child_comp) is Some(child) else {
    return "could not build \{child_key}/\{child_comp}"
  }
  h.send_at_root(name, args=[child])
  current_html()
}

///|
/// Send the mounted root a message with one string argument.
fn send(name : String, arg : String) -> String {
  guard live.val is Some(h) else { return "nothing is mounted" }
  h.send_at_root(name, args=[Str(arg)])
  current_html()
}

///|
fn click(sel : String) -> String {
  guard live.val is Some(h) else { return "nothing is mounted" }
  h.click(sel) catch {
    e => return "click failed: \{e}"
  }
  current_html()
}

///|
fn current_html() -> String {
  match live.val {
    Some(h) => h.html()
    None => ""
  }
}
