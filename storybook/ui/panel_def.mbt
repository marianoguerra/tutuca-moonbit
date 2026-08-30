// What the shell knows about a panel, and the doors a panel layer writes back
// through.
//
// The gallery's tabs beside Story are not built here and their values are not
// read here: a `PanelDef` is a key, a label, a field prefix and a closure, and
// the shell's whole involvement is deciding when to call the closure and where
// to put what comes back. That is what lets this package import neither the
// inspector nor the recorder nor the fuzz driver — `storybook/ui/panels`
// imports all three and hands the result in.

///|
/// One tab beside Story.
pub(all) struct PanelDef {
  /// The tab key: what `onStoryTab` writes into `t<N>`, what `setPanel`
  /// addresses, and the `<key>-tab` class on the tab itself.
  key : String
  /// The tab's label.
  label : String
  /// The per-story field prefix its value lives at (`"i"` -> `i0`, `i1`, …).
  /// Must not collide with the shell's own (`s`, `v`, `t`, `c`, `gv`, `pv`) or
  /// with another panel's; `build_shell` drops a panel that does and says so.
  field : String
  /// Builds the panel's value from the story's instance and a reader over the
  /// shell's own fields (the second is how a panel reaches the gallery-wide
  /// knobs it declared in `PanelSet::fields`).
  ///
  /// None for a panel that only ever arrives from the host through `setPanel`.
  build : ((@tutuca.Value, (String) -> @tutuca.Value) -> @tutuca.Value)?
  /// Rebuild on every write to the story while this tab is open. The Instance
  /// tab is the one that wants it: an explorer that showed the state as of the
  /// moment the tab opened would be a screenshot.
  live : Bool
  /// Survive leaving the tab. A recording does — it is a session someone
  /// captured — and an explorer does not: it is a whole component tree, and a
  /// closed tab has no use for one.
  keep : Bool
  /// Render the story above the panel. A run that cannot be watched is the
  /// headless run with extra steps.
  with_story : Bool
}

///|
/// A whole panel layer: the tabs, the fields they own, the components their
/// values are instances of, the intents they answer, and the callback that
/// hands them the app once it exists.
///
/// Generic over the node type because the intents drive the app — which is the
/// reason a panel layer cannot be a plain value and `mount` cannot build one.
pub(all) struct PanelSet[N] {
  defs : Array[PanelDef]
  /// Gallery-wide fields the panels own, name -> default. Declared here
  /// because the shell's descriptor has to carry them, and because `setFields`
  /// will write no name that is not in this map.
  fields : Map[String, @tutuca.Value]
  /// Components a panel's values are instances of. Registered in a child scope
  /// of the root's, so their names stay out of every story's way.
  components : Array[@component.Component]
  /// Intents the panels answer. Registered before the app exists, so they hold
  /// a slot rather than the app.
  intents : Map[String, Array[@component.IntentFn]]
  /// Called with the mounted app, before `start()`. This is what fills the
  /// slot the intents closed over.
  attach : (@app.App[N]) -> Unit
}

///|
/// No panels: the story pane is the whole pane, and the gallery imports
/// nothing to draw it.
pub fn[N] PanelSet::none() -> PanelSet[N] {
  {
    defs: [],
    fields: Map([]),
    components: [],
    intents: Map([]),
    attach: _app => (),
  }
}

///|
/// Where a story's instance lives in the shell's state.
///
/// The shell's field set is `sN` per story, so a story IS a place — which is
/// what makes "record only this example" expressible at all, and it is the
/// address a panel layer dispatches and cuts at.
pub fn story_field(idx : Int) -> String {
  "s\{idx}"
}

///|
/// The story the gallery is currently showing, as an index — or -1.
pub fn active_index(sections : Array[@sb.Section], active : String) -> Int {
  let mut idx = 0
  for sec in sections {
    for s in sec.stories {
      if s.id == active {
        return idx
      }
      idx = idx + 1
    }
  }
  -1
}

///|
/// The index of the story on screen, or -1.
pub fn[N] active_story(app : @app.App[N], sections : Array[@sb.Section]) -> Int {
  active_index(sections, app.root_value().field("active").str(default=""))
}

///|
/// One of the shell's own fields, read back out of the running app.
pub fn[N] shell_field(app : @app.App[N], name : String) -> @tutuca.Value {
  app.root_value().field(name)
}

///|
/// A story's live instance.
pub fn[N] story_value(app : @app.App[N], idx : Int) -> @tutuca.Value {
  app.root_value().field(story_field(idx))
}

///|
/// The scopes the stories were built in, by index.
///
/// A module-level slot for the reason the Trace tab's selection flag is one: a
/// gallery mounts ONCE per page, so there is one of these to be in, and the
/// alternative was threading a handle out of `mount` into the one export a
/// wasm host is allowed. A second mount in the same process replaces it, which
/// is what a test that mounts twice should expect.
let story_scopes : Ref[Array[@component.ComponentStack]] = { val: [], }

///|
/// The scope a story's components are registered in.
///
/// Stories get a scope EACH — `root_scope.enter()` per story — so that ~35
/// panel component names and one story's components do not become visible to
/// every other story. That is the right call and it has one consequence: a
/// caller holding only the app cannot rebuild a story's value from a snapshot,
/// because the names are not in `app.scope`.
///
/// A recording is exactly such a snapshot, so a rerun needs this. And it has
/// to be the story's OWN scope rather than a fresh one built from the same
/// module: a `Component` carries an id bound to the scope it was registered
/// in, so a value built elsewhere renders as a blank pane.
pub fn story_scope(idx : Int) -> @component.ComponentStack? {
  if idx < 0 || idx >= story_scopes.val.length() {
    None
  } else {
    Some(story_scopes.val[idx])
  }
}

///|
/// Put a value back into a story's pane.
///
/// The one write a panel layer does to a story rather than to a panel, and it
/// exists because a reset has to be EXACT: rewinding a component by sending it
/// the reverse of what it received is not a thing that exists.
pub fn[N] set_story_value(
  app : @app.App[N],
  idx : Int,
  value : @tutuca.Value,
) -> Unit {
  app.send_at_root("setStoryValue", args=[Num(idx.to_double()), value])
  |> ignore
}

///|
/// Hand a rebuilt panel to the pane that owns it.
///
/// Through `send_at_root` because that is the host's door into a running app,
/// and the shell routes it by key — the host knows the story index and the
/// panel it built, and nothing else about where the pane lives.
pub fn[N] push_panel(
  app : @app.App[N],
  idx : Int,
  key : String,
  panel : @tutuca.Value,
) -> Unit {
  app.send_at_root("setPanel", args=[Num(idx.to_double()), Str(key), panel])
  |> ignore
}

///|
/// Write back gallery-wide panel fields, so the shell and the panel cannot
/// disagree about what the rows underneath were drawn at. Names the panels did
/// not declare are ignored.
pub fn[N] set_panel_fields(
  app : @app.App[N],
  fields : Map[String, @tutuca.Value],
) -> Unit {
  app.send_at_root("setFields", args=[Map(fields)]) |> ignore
}

///|
/// Raise an intent from outside the app.
///
/// A panel's own effects are the host's — a document listener is not something
/// a component can install — but only a component can raise an intent, so this
/// asks the shell to raise one on the panel layer's behalf.
pub fn[N] raise_panel_intent(
  app : @app.App[N],
  name : String,
  payload : @tutuca.Value,
) -> Unit {
  app.send_at_root("panelIntent", args=[Str(name), payload]) |> ignore
}
