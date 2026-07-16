// Headless harness: mount a ModuleDef as a LIVE app on the in-memory DOM, then
// drive it with real events through the transactor and read the resulting HTML
// back. "The example works" means click/type → new state → re-rendered DOM, not
// a static render snapshot.
//
// Backend-agnostic (memdom runs on every target), so `moon test` covers it with
// no browser and no server. The browser host is the spot-check for what only a
// real DOM can show.

///|
pub struct Harness {
  app : @app.App[@memdom.MemNode]
  container : @memdom.MemNode
}

///|
/// Build the module's scope, make `root` with `args`, and mount it.
pub fn mount(
  m : @component.ModuleDef,
  root : String,
  args? : Map[String, @tutuca.Value] = {},
) -> Harness raise {
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let app = @app.App::from_module(
    m,
    root,
    container,
    @vdom.RenderOpts::new(doc),
    args~,
  )
  { app, container }
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
pub fn mount_example(m : @component.ModuleDef, title : String) -> Harness raise {
  for ex in m.examples {
    if ex.title == title {
      return mount(m, ex.component, args=ex.args)
    }
  }
  fail("mount_example: no example titled '\{title}' in module '\{m.name}'")
}

///|
/// The mounted DOM, serialized. The wrapping <div> is the mount container.
pub fn Harness::html(self : Harness) -> String {
  self.container.to_html()
}

///|
/// The current settled root value — the transactor's root as a `Value`, after
/// every dispatched interaction has drained. `Null` if the root is not a value
/// node. The state-oriented read-back that mirrors the JS `drive()` return.
pub fn Harness::drive_value(self : Harness) -> @tutuca.Value {
  self.app.root_value().unwrap_or(@tutuca.Value::Null)
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
fn node_has_class(n : @memdom.MemNode, want : String) -> Bool {
  guard n.get_attribute("class") is Some(cls) else { return false }
  for c in cls.split(" ") {
    if c.to_owned() == want {
      return true
    }
  }
  false
}

///|
fn matches(n : @memdom.MemNode, s : Sel) -> Bool {
  guard n.kind is Element else { return false }
  if s.tag is Some(t) && n.tag.to_lower() != t.to_lower() {
    return false
  }
  if s.id is Some(want) && !(n.get_attribute("id") is Some(got) && got == want) {
    return false
  }
  for c in s.classes {
    if !node_has_class(n, c) {
      return false
    }
  }
  for a in s.attrs {
    if !(n.get_attribute(a) is Some(_)) {
      return false
    }
  }
  true
}

///|
/// Elements matching the selector, in document order.
pub fn Harness::find_all(
  self : Harness,
  sel : String,
) -> Array[@memdom.MemNode] {
  let s = parse_selector(sel)
  let hits : Array[@memdom.MemNode] = []
  fn walk(n : @memdom.MemNode) {
    if matches(n, s) {
      hits.push(n)
    }
    for c in n.childs {
      walk(c)
    }
  }

  walk(self.container)
  hits
}

///|
/// The nth (default first) element matching the selector.
pub fn Harness::find(
  self : Harness,
  sel : String,
  nth? : Int = 0,
) -> @memdom.MemNode raise {
  let hits = self.find_all(sel)
  guard hits.get(nth) is Some(n) else {
    fail("find: no element \{nth} matching '\{sel}' (found \{hits.length()})")
  }
  n
}

///|
/// The element's rendered text (all descendant text nodes, concatenated), with
/// runs of whitespace collapsed to one space and the ends trimmed — the text as
/// a reader sees it, not as the template indented it. This is what most
/// assertions want; full-HTML snapshots carry meta comments and
/// data-cid/data-eid bookkeeping that obscure the point.
pub fn Harness::text(
  self : Harness,
  sel : String,
  nth? : Int = 0,
) -> String raise {
  node_text(self.find(sel, nth~))
}

///|
/// The text of every element matching the selector — the shape iteration
/// assertions want ("the list now reads [a, b, c]").
pub fn Harness::texts(self : Harness, sel : String) -> Array[String] {
  self.find_all(sel).map(node_text)
}

///|
fn node_text(n : @memdom.MemNode) -> String {
  let sb = StringBuilder()
  fn walk(n : @memdom.MemNode) {
    if n.kind is TextNode {
      sb.write_string(n.data)
    }
    for c in n.childs {
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
pub fn Harness::attr(
  self : Harness,
  sel : String,
  name : String,
  nth? : Int = 0,
) -> String? raise {
  self.find(sel, nth~).get_attribute(name)
}

///|
/// A DOM *property* of the matched element. Form-control state (`value`,
/// `checked`, `disabled`, `selected`) is set as a property, not an attribute —
/// so `:value=".title"` is read back with this, not with attr().
pub fn Harness::prop(
  self : Harness,
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
pub fn Harness::ns_of(
  self : Harness,
  sel : String,
  nth? : Int = 0,
) -> String raise {
  match self.find(sel, nth~).ns {
    Some(Svg) => "svg"
    Some(MathMl) => "mathml"
    Some(Other(uri)) => uri
    None => "html"
  }
}

///|
/// The `checked` property of a checkbox — the read-back for `:checked`.
pub fn Harness::checked_of(
  self : Harness,
  sel : String,
  nth? : Int = 0,
) -> Bool raise {
  self.prop(sel, "checked", nth~) is Some(Bool(true))
}

///|
/// The `value` property of an input — the read-back for `:value` bindings.
pub fn Harness::value_of(
  self : Harness,
  sel : String,
  nth? : Int = 0,
) -> String raise {
  match self.prop(sel, "value", nth~) {
    Some(Str(s)) => s
    Some(Num(n)) => n.to_string()
    Some(Bool(b)) => b.to_string()
    Some(Html(s)) => s
    Some(Data(j)) => j.stringify()
    None => ""
  }
}

///|
/// Dispatch any event at the node matching `sel`. The escape hatch the typed
/// helpers below are built on — reach for it for keydown modifiers, drag, and
/// custom events.
pub fn Harness::fire(
  self : Harness,
  sel : String,
  e : @render.DomEvent,
  nth? : Int = 0,
) -> Unit raise {
  let node = self.find(sel, nth~)
  let _ = self.app.dispatch(node, e)
}

///|
pub fn Harness::click(
  self : Harness,
  sel : String,
  nth? : Int = 0,
) -> Unit raise {
  self.fire(sel, @render.DomEvent::new(name="click"), nth~)
}

///|
/// An `input` event carrying `value` — what `@on.input="setX value"` reads.
pub fn Harness::type_into(
  self : Harness,
  sel : String,
  value : String,
  nth? : Int = 0,
) -> Unit raise {
  self.fire(sel, @render.DomEvent::new(name="input", value=Str(value)), nth~)
}

///|
/// A checkbox `input` event (JS getValue returns `checked` for checkboxes).
pub fn Harness::check(
  self : Harness,
  sel : String,
  checked : Bool,
  nth? : Int = 0,
) -> Unit raise {
  self.fire(sel, @render.DomEvent::new(name="input", value=Bool(checked)), nth~)
}

///|
/// A keydown carrying `key` — drives the +send (Enter) / +cancel (Escape)
/// modifiers.
pub fn Harness::key_down(
  self : Harness,
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
pub fn Harness::drag(
  self : Harness,
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
pub fn Harness::render_count(self : Harness) -> Int {
  self.app.render_count
}

///|
/// The CSS the scope compiles for every registered component (style +
/// commonStyle + globalStyle, scoped by data-cid / data-vid). In a browser the
/// glue injects this into a <style> tag; headless, we assert on it directly.
pub fn Harness::styles(self : Harness) -> String {
  self.app.scope.comps.compile_styles()
}

///|
/// Dispatch a message at the root — the host's job, since tutuca has no
/// lifecycle. The JS playground calls `app.sendAtRoot("init")` right after
/// start(); this is the same hook, and it is what makes `receive.init` run.
pub fn Harness::send_at_root(
  self : Harness,
  name : String,
  args? : Array[@tutuca.Value] = [],
) -> Unit {
  self.app.send_at_root(name, args~)
}
