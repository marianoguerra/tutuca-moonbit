// Headless harness: mount a ModuleDef as a LIVE app on the in-memory DOM, then
// drive it with real events through the transactor and read the resulting HTML
// back. "The example works" means click/type → new state → re-rendered DOM, not
// a static render snapshot.
//
// Backend-agnostic (memdom runs on every target), so `moon test` covers it with
// no browser and no server. The browser host is the spot-check for what only a
// real DOM can show.

///|
/// A mounted app and the element it was mounted into.
///
/// Generic over the node type for the same reason `App` is: the verbs below are
/// written against `@vdom.DomWalk` and nothing else, so the same "click the
/// third row" drives memdom under `moon test` and a real page in a browser.
/// That is not a convenience — a second implementation of `nth` is how two of
/// them start disagreeing, and a card's fixture is DRIVEN on the page it is
/// shown on.
pub struct Harness[N] {
  app : @app.App[N]
  container : N
}

///|
/// The harness over the IN-MEMORY DOM — what `mount` answers, and what every
/// headless test holds.
///
/// Spelled here so a caller can name the type without importing memdom for the
/// sake of one annotation: a test that mounts a module and a benchmark that
/// hands one around both want to say "the ordinary harness", and neither has
/// any other reason to know which node type that is.
pub type MemHarness = Harness[@memdom.MemNode]

///|
/// Build the module's scope, make `root` with `args`, and mount it.
pub fn mount(
  m : @component.ModuleDef,
  root : String,
  args? : Map[String, @tutuca.Value] = Map([]),
  view? : String = "",
) -> Harness[@memdom.MemNode] raise {
  let (doc, container) = new_mount()
  let app = @app.App::from_module(
    m,
    root,
    container,
    @vdom.RenderOpts::new(doc),
    args~,
    view~,
  )
  Harness::over(app, container)
}

///|
/// The verbs, over an app somebody else mounted.
///
/// `mount` is the answer for a `ModuleDef`, which is what an ahead-of-time
/// build produces. It is not the only way an app comes to exist: a dyncomp
/// BUNDLE is registered into a scope and its root instance is made from the
/// manifest, and a card compiled in a browser is exactly that — so a driver
/// for one has an `App[MemNode]` in hand and no `ModuleDef` anywhere.
///
/// Everything below this line is written against the two fields and nothing
/// else, so handing them in is all it takes. The alternative was a second copy
/// of the selector engine and the twenty verbs beside it, which is how two
/// implementations of "click the third row" start disagreeing about what
/// `nth` counts.
pub fn[N] Harness::over(app : @app.App[N], container : N) -> Harness[N] {
  { app, container }
}

///|
/// A fresh memdom document and the `<div>` an app mounts into.
///
/// The mount container is a real element rather than the document itself
/// because the renderer replaces its children, and a document's children are
/// not a component's to own.
pub fn new_mount() -> (@memdom.MemNode, @memdom.MemNode) {
  let doc = @memdom.document()
  (doc, @vdom.DomNode::create_element(doc, "DIV", None, None))
}

///|
/// Mount one of the module's own `ExampleDef`s, by title.
///
/// Prefer this whenever an example's args contain CHILD COMPONENT INSTANCES: a
/// Component value carries an id and is bound to the scope it was registered
/// in, so instances must be made from the very same Component the module
/// registers. The ExampleDef args already are. (Building a child from a fresh
/// `x_comp()` in a test would produce an instance whose id no component in the
/// mounted scope claims, and it would not render.)
///
/// It also means these tests exercise exactly the examples the CLI renders and
/// the storybook shows.
pub fn mount_example(
  m : @component.ModuleDef,
  title : String,
) -> Harness[@memdom.MemNode] raise {
  for ex in m.examples {
    if ex.title == title {
      return mount(m, ex.component, args=ex.args, view=ex.view.unwrap_or(""))
    }
  }
  fail("mount_example: no example titled '\{title}' in module '\{m.name}'")
}

///|
/// The mounted DOM, serialized. The wrapping <div> is the mount container.
pub fn Harness::html(self : Harness[@memdom.MemNode]) -> String {
  self.container.to_html()
}

///|
/// Release the app and its DOM. The harness is dead afterwards — no find, no
/// fire, no html.
///
/// Both halves of a mounted app are reference cycles the native backend does
/// not reclaim (App <-> transactor closures, MemNode parent <-> childs), so a
/// caller that mounts in a loop must tear each one down or it grows until it
/// is killed. A test that mounts once per case can skip it; the process exits
/// first.
pub fn Harness::destroy(self : Harness[@memdom.MemNode]) -> Unit {
  self.app.destroy()
  self.container.destroy_tree()
}

///|
/// The current settled root value — the transactor's root as a `Value`, after
/// every dispatched interaction has drained. `Null` if the root is not a value
/// node. The state-oriented read-back of the settled root value.
pub fn[N] Harness::drive_value(self : Harness[N]) -> @tutuca.Value {
  self.app.root_value()
}

///|
/// A minimal selector: an optional tag, plus any number of #id / .class /
/// [attr] qualifiers ("button", ".stat-value", "input#label", "li.done",
/// "[draggable]"). Deliberately not a CSS engine — no combinators, no
/// descendant matching; every example so far needs only these.
priv struct Sel {
  tag : String?
  id : String?
  classes : Array[String]
  attrs : Array[String]
}

///|
fn parse_selector(sel : String) -> Sel {
  // Split into (marker, name) tokens: the leading run (no marker) is the tag,
  // then each #/./[ starts a new qualifier.
  let toks : Array[(Char, String)] = []
  let mut kind = 't' // 't'ag | 'i'd | 'c'lass | 'a'ttr
  let cur = StringBuilder()
  for ch in sel {
    match ch {
      '#' | '.' | '[' => {
        toks.push((kind, cur.to_string()))
        cur.reset()
        kind = match ch {
          '#' => 'i'
          '.' => 'c'
          _ => 'a'
        }
      }
      ']' => ()
      _ => cur.write_char(ch)
    }
  }
  toks.push((kind, cur.to_string()))
  let mut tag = None
  let mut id = None
  let classes : Array[String] = []
  let attrs : Array[String] = []
  for t in toks {
    let (k, name) = t
    if name == "" {
      continue
    }
    match k {
      't' => tag = Some(name)
      'i' => id = Some(name)
      'c' => classes.push(name)
      _ => attrs.push(name)
    }
  }
  { tag, id, classes, attrs }
}

///|
fn[N : @vdom.DomWalk] node_has_class(n : N, want : String) -> Bool {
  guard n.attribute("class") is Some(cls) else { return false }
  for c in cls.split(" ") {
    if c.to_owned() == want {
      return true
    }
  }
  false
}

///|
fn[N : @vdom.DomWalk] matches(n : N, s : Sel) -> Bool {
  // 1 and 3 are the DOM's own node types, which is what `node_kind` answers on
  // every backend — memdom maps its enum onto them and a browser node has them
  // already.
  guard n.node_kind() == 1 else { return false }
  if s.tag is Some(t) && @vdom.DomNode::tag_name(n).to_lower() != t.to_lower() {
    return false
  }
  if s.id is Some(want) && !(n.attribute("id") is Some(got) && got == want) {
    return false
  }
  for c in s.classes {
    if !node_has_class(n, c) {
      return false
    }
  }
  for a in s.attrs {
    if !(n.attribute(a) is Some(_)) {
      return false
    }
  }
  true
}

///|
/// Elements matching the selector, in document order.
pub fn[N : @vdom.DomWalk] Harness::find_all(
  self : Harness[N],
  sel : String,
) -> Array[N] {
  let s = parse_selector(sel)
  let hits : Array[N] = []
  fn walk(n : N) {
    if matches(n, s) {
      hits.push(n)
    }
    for c in @vdom.DomNode::child_nodes(n) {
      walk(c)
    }
  }

  walk(self.container)
  hits
}

///|
/// The nth (default first) element matching the selector.
///
/// Stops at the nth match instead of collecting every one: the usual call asks
/// for the first element of a long list, and walking the remaining rows to throw
/// them away is the dominant cost of driving a big DOM (it showed up as ~4% of
/// benchmarks/'s update profile before this). A miss still visits everything, so
/// the count in the failure message is the true total.
pub fn[N : @vdom.DomWalk] Harness::find(
  self : Harness[N],
  sel : String,
  nth? : Int = 0,
) -> N raise {
  let s = parse_selector(sel)
  let mut seen = 0
  let mut found : N? = None
  fn walk(n : N) {
    if matches(n, s) {
      if seen == nth {
        found = Some(n)
        return
      }
      seen = seen + 1
    }
    for c in @vdom.DomNode::child_nodes(n) {
      walk(c)
      if found is Some(_) {
        return
      }
    }
  }

  walk(self.container)
  guard found is Some(n) else {
    fail("find: no element \{nth} matching '\{sel}' (found \{seen})")
  }
  n
}

///|
/// The element's rendered text (all descendant text nodes, concatenated), with
/// runs of whitespace collapsed to one space and the ends trimmed — the text as
/// a reader sees it, not as the template indented it. This is what most
/// assertions want; full-HTML snapshots carry meta comments and
/// data-cid/data-eid bookkeeping that obscure the point.
pub fn[N : @vdom.DomWalk] Harness::text(
  self : Harness[N],
  sel : String,
  nth? : Int = 0,
) -> String raise {
  node_text(self.find(sel, nth~))
}

///|
/// The text of every element matching the selector — the shape iteration
/// assertions want ("the list now reads [a, b, c]").
pub fn[N : @vdom.DomWalk] Harness::texts(
  self : Harness[N],
  sel : String,
) -> Array[String] {
  self.find_all(sel).map(node_text)
}

///|
fn[N : @vdom.DomWalk] node_text(n : N) -> String {
  let sb = StringBuilder()
  fn walk(n : N) {
    if n.node_kind() == 3 {
      sb.write_string(n.char_data())
    }
    for c in @vdom.DomNode::child_nodes(n) {
      walk(c)
    }
  }

  walk(n)
  collapse_ws(sb.to_string())
}

///|
/// Collapse whitespace runs to a single space and trim — HTML's own whitespace
/// semantics, so template indentation does not leak into assertions.
fn collapse_ws(s : String) -> String {
  let out = StringBuilder()
  let mut in_ws = false
  let mut wrote = false
  for ch in s {
    if ch is (' ' | '\n' | '\t' | '\r') {
      in_ws = true
    } else {
      if in_ws && wrote {
        out.write_char(' ')
      }
      in_ws = false
      out.write_char(ch)
      wrote = true
    }
  }
  out.to_string()
}

///|
/// An attribute of the matched element — for asserting :attr bindings and the
/// @if/@then/@else class swaps.
pub fn[N : @vdom.DomWalk] Harness::attr(
  self : Harness[N],
  sel : String,
  name : String,
  nth? : Int = 0,
) -> String? raise {
  self.find(sel, nth~).attribute(name)
}

///|
/// A DOM *property* of the matched element. Form-control state (`value`,
/// `checked`, `disabled`, `selected`) is set as a property, not an attribute —
/// so `:value=".title"` is read back with this, not with attr().
pub fn Harness::prop(
  self : Harness[@memdom.MemNode],
  sel : String,
  name : String,
  nth? : Int = 0,
) -> @vdom.AttrValue? raise {
  self.find(sel, nth~).get_property(name)
}

///|
/// The XML namespace the element was created in — "svg" / "mathml" / "html".
/// Proves an <svg>/<math> subtree really became namespaced elements rather than
/// HTML elements that merely look like them.
pub fn[N : @vdom.DomWalk] Harness::ns_of(
  self : Harness[N],
  sel : String,
  nth? : Int = 0,
) -> String raise {
  match @vdom.DomNode::namespace_uri(self.find(sel, nth~)) {
    Some(Svg) => "svg"
    Some(MathMl) => "mathml"
    Some(Other(uri)) => uri
    None => "html"
  }
}

///|
/// The `checked` property of a checkbox — the read-back for `:checked`.
pub fn Harness::checked_of(
  self : Harness[@memdom.MemNode],
  sel : String,
  nth? : Int = 0,
) -> Bool raise {
  self.prop(sel, "checked", nth~) is Some(Bool(true))
}

///|
/// The `value` property of an input — the read-back for `:value` bindings.
pub fn Harness::value_of(
  self : Harness[@memdom.MemNode],
  sel : String,
  nth? : Int = 0,
) -> String raise {
  match self.prop(sel, "value", nth~) {
    Some(Str(s)) => s
    Some(Num(n)) => n.to_string()
    Some(Bool(b)) => b.to_string()
    Some(Html(s)) | Some(Md(s)) | Some(SafeHtml(s)) | Some(Svg(s)) => s
    Some(Data(j)) => j.stringify()
    None => ""
  }
}

///|
/// Dispatch any event at the node matching `sel`. The escape hatch the typed
/// helpers below are built on — reach for it for keydown modifiers, drag, and
/// custom events.
pub fn[N : @vdom.DomWalk] Harness::fire(
  self : Harness[N],
  sel : String,
  e : @render.DomEvent,
  nth? : Int = 0,
) -> Unit raise {
  let node = self.find(sel, nth~)
  let _ = self.app.dispatch(node, e)
}

///|
pub fn[N : @vdom.DomWalk] Harness::click(
  self : Harness[N],
  sel : String,
  nth? : Int = 0,
) -> Unit raise {
  self.fire(sel, @render.DomEvent::new(name="click"), nth~)
}

///|
/// An `input` event carrying `value` — what `@on.input="setX e.value"` reads.
pub fn[N : @vdom.DomWalk] Harness::type_into(
  self : Harness[N],
  sel : String,
  value : String,
  nth? : Int = 0,
) -> Unit raise {
  self.fire(sel, @render.DomEvent::new(name="input", value=Str(value)), nth~)
}

///|
/// A checkbox `input` event (the value read back is `checked` for checkboxes).
pub fn[N : @vdom.DomWalk] Harness::check(
  self : Harness[N],
  sel : String,
  checked : Bool,
  nth? : Int = 0,
) -> Unit raise {
  self.fire(sel, @render.DomEvent::new(name="input", value=Bool(checked)), nth~)
}

///|
/// A keydown carrying `key` — drives the +send (Enter) / +cancel (Escape)
/// modifiers.
pub fn[N : @vdom.DomWalk] Harness::key_down(
  self : Harness[N],
  sel : String,
  key : String,
  value? : @tutuca.Value = Null,
  nth? : Int = 0,
) -> Unit raise {
  self.fire(sel, @render.DomEvent::new(name="keydown", key~, value~), nth~)
}

///|
/// Run a full drag gesture: dragstart on the source row, dragover the target,
/// then drop on it. The app's drag state machine captures the DragInfo at
/// dragstart, which is what the drop handler reads the source key from.
pub fn[N : @vdom.DomWalk] Harness::drag(
  self : Harness[N],
  sel : String,
  from : Int,
  to : Int,
) -> Unit raise {
  self.fire(sel, @render.DomEvent::new(name="dragstart"), nth=from)
  self.fire(sel, @render.DomEvent::new(name="dragover"), nth=to)
  self.fire(sel, @render.DomEvent::new(name="drop"), nth=to)
  self.fire(sel, @render.DomEvent::new(name="dragend"), nth=to)
}

///|
/// Renders performed so far — proves the batching invariant (one morph per
/// drained cascade), and that an interaction re-rendered at all.
pub fn[N] Harness::render_count(self : Harness[N]) -> Int {
  self.app.render_count
}

///|
/// The CSS the scope compiles for every registered component (style +
/// commonStyle + globalStyle, scoped by data-cid / data-vid). In a browser the
/// glue injects this into a <style> tag; headless, we assert on it directly.
pub fn[N] Harness::styles(self : Harness[N]) -> String {
  self.app.scope.comps.compile_styles()
}

///|
/// Dispatch a message at the root — the host's job, since tutuca has no
/// lifecycle. This is the `app.sendAtRoot("init")` hook, and it is what makes
/// `receive.init` run.
pub fn[N] Harness::send_at_root(
  self : Harness[N],
  name : String,
  args? : Array[@tutuca.Value] = [],
) -> Unit {
  let first = self.app.send_at_root(name, args~)
  if first.pending {
    self.app.drain_batched(max_per_batch=10000, () => ()) |> ignore
  }
}

///|
/// Every refusal `body` produced — filtered from the runtime notice channel,
/// scoped to one stretch of driving and switched off again afterwards.
///
/// A free function rather than a `Harness` method because it needs no harness:
/// the channel is the runtime's, and a card mounted by some other harness
/// reports through the same one. It is here because this is where a test author
/// looks.
///
/// Not on by default, deliberately. A refusal replaces the line `warn` prints,
/// so a harness that installed a listener for every mount would silently change
/// what every other test sees — and a channel that a team never switches on is
/// exactly where they were before it existed. Switching it on is one call:
///
/// ```moonbit nocheck
/// // nocheck: `post_module` is the reader's own module
/// let h = @harness.mount(post_module(), "Post")
/// let refused = @harness.refusals_while(() => h.click(".publish"))
/// inspect(
///   refused.map(r => r.to_line()),
///   content=(
///     #|["PRECONDITION publishedNeedsTitle at `publish` — Cannot publish \"draft-2\": the title is empty."]
///   ),
/// )
/// ```
pub fn refusals_while(body : () -> Unit raise) -> Array[@tutuca.Refusal] raise {
  let out : Array[@tutuca.Refusal] = []
  let off = @tutuca.on_runtime_notice(n => {
    match n {
      Refused(r) => out.push(r)
      _ => ()
    }
  })
  // Switched off on the way out of a failure too: a driving call that raises —
  // a selector matching nothing — must not leave the channel open for whatever
  // test runs next.
  errdefer off()
  body()
  off()
  out
}

///|
/// Drive `body` and FAIL if anything was refused.
///
/// This is the half that makes a test about a guarded button mean something.
/// `h.click(".publish")` on a component whose precondition declines passes
/// today — the DOM does not move, which is exactly what a correct guard and a
/// wrong selector both look like. Here the two are different: one is a failure
/// naming the rule, the path and the sentence, and the other is silence.
pub fn no_refusals(body : () -> Unit raise) -> Unit raise {
  let refused = refusals_while(body)
  guard refused.is_empty() else {
    fail("refused: " + refused.map(r => r.to_line()).join("; "))
  }
}
