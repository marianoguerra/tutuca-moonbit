// The page as a document.
//
// A saved page is the app's root component written out with
// `@tutuca.Value::to_component_json` and read back through here. Both
// directions are the core codec; what this file adds is the one thing it takes
// as a parameter — where a `$component` name resolves — which for this app is
// two namespaces at once: the standard components, compiled in, and whatever a
// loaded bundle answers for.
//
// It lives here rather than in the wasm shell that used to own it because
// nothing about either namespace is backend-specific. `MakeInstance` was
// already the seam for "build a loaded component", and `Std` was already the
// seam for "build a standard one". That is the whole resolver, and having it
// here means the round trip is a `moon test` away instead of needing a browser.

///|
/// What a standard component declares, so its fields decode BY TYPE.
///
/// A loaded one declines, and that is not a gap: its fields decode structurally
/// instead, which is what the document this codec wrote holds anyway. Reaching
/// into a bundle for its declared types would only change a document written by
/// hand.
pub impl @tutuca.ComponentSource for UniversalUi with fn describe(
  self,
  module_,
  name,
) {
  match self.resolve_ref(module_, name) {
    Some(ref_) if is_builtin(ref_) =>
      @tutuca.ComponentSource::describe(self.std, module_, name)
    _ => None
  }
}

///|
/// Which component a document meant.
///
/// A `$module` settles it. Without one, the standard components answer first
/// and the catalog answers second — the same order `Registry::describe` takes,
/// and for the same reason: a page that could lose its `+` to a dropped file is
/// a page that can be taken away. Two bundles declaring one name is the
/// ambiguity `$module` exists to resolve, and the first match wins otherwise.
fn UniversalUi::resolve_ref(
  self : UniversalUi,
  module_ : String?,
  name : String,
) -> @registry.ComponentRef? {
  match module_ {
    Some(m) => Some({ module_: m, name })
    None => {
      if self.std.declares(name) {
        return Some({ module_: builtin_module, name })
      }
      for d in self.registry.all() {
        if d.ref_.name == name {
          return Some(d.ref_)
        }
      }
      None
    }
  }
}

///|
/// Build it: a standard component through `Std`, a loaded one through
/// `MakeInstance`. That is the same fork `UniversalUi::build` already makes for
/// placing, which is deliberate — a restored tree should be built by the code
/// that built it the first time.
pub impl @tutuca.ComponentSource for UniversalUi with fn build(
  self,
  module_,
  name,
  args,
  at~ : String,
) {
  guard self.resolve_ref(module_, name) is Some(ref_) else { return None }
  if is_builtin(ref_) {
    return @tutuca.ComponentSource::build(self.std, module_, name, args, at~)
  }
  (self.make)(ref_, "", args)
}

///|
/// A source that asks `restore` first.
///
/// The hook exists for one caller — a session whose guest instances were saved
/// as their own bytes, keyed by WHERE they sit — and it takes the pointer
/// rather than the name because that is the key such a table has. Answering
/// `None` falls through to building a fresh one, which is what a guest with
/// nothing saved, or a bundle loaded since, both want.
priv struct RestoringUi {
  ui : UniversalUi
  restore : (String, @registry.ComponentRef) -> @tutuca.Value?
}

///|
impl @tutuca.ComponentSource for RestoringUi with fn describe(
  self,
  module_,
  name,
) {
  @tutuca.ComponentSource::describe(self.ui, module_, name)
}

///|
impl @tutuca.ComponentSource for RestoringUi with fn build(
  self,
  module_,
  name,
  args,
  at~ : String,
) {
  if self.ui.resolve_ref(module_, name) is Some(ref_) &&
    !is_builtin(ref_) &&
    (self.restore)(at, ref_) is Some(v) {
    return Some(v)
  }
  @tutuca.ComponentSource::build(self.ui, module_, name, args, at~)
}

///|
/// A saved page back into a tree. `Null` when the document names nothing this
/// app can build.
///
/// A component whose bundle is missing comes back as nothing, and the cell
/// holding it draws an empty `+`. The rest of the page still returns, and
/// dropping that bundle later and reloading fills it in — refusing the whole
/// session because one component is unavailable would be the wrong trade for a
/// page whose bundles arrive by hand.
pub fn UniversalUi::tree_of_json(
  self : UniversalUi,
  j : Json,
  restore? : (String, @registry.ComponentRef) -> @tutuca.Value?,
) -> @tutuca.Value {
  let src : &@tutuca.ComponentSource = match restore {
    Some(r) => RestoringUi::{ ui: self, restore: r } as &@tutuca.ComponentSource
    None => self as &@tutuca.ComponentSource
  }
  @tutuca.Value::from_component_json(j, src).unwrap_or(Null)
}
