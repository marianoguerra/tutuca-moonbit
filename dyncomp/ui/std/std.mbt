///| The standard components: what the universal UI can always place.
///
/// The shape worth noticing is how little is here. A container arranges the
/// universals it holds, a universal holds one thing, a leaf renders itself —
/// and none of them knows what a catalog, a bundle or an editor is. Everything
/// about CHOOSING what goes in a universal belongs to the app, which is why
/// `hold` takes a finished instance rather than a name: building one may need
/// the dyncomp bridge, and a package that stayed backend-agnostic could not.

///|
/// The module's components, and the one thing they need of each other.
///
/// A container that inserts a cell has to build a `Universal`, and a component
/// cannot construct a sibling without the registry that holds it — the same
/// `reg` pattern `inspector/` and `dyncomp/ui` both take, for the same reason.
pub struct Std {
  comps : Map[String, @component.Component]
}

///|
fn Std::make_(
  self : Std,
  name : String,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  match self.comps.get(name) {
    Some(c) => c.make(args)
    None => Null
  }
}

///|
/// Build one of the standard components by name. `Null` for a name this module
/// does not declare, which is the same answer a missing slot gives — a caller
/// that asked for something absent gets nothing rather than a crash.
///
/// A container comes back USABLE. Its cells are not in its declared arguments
/// — they hold components, and a form offering to type one in would be
/// offering something that cannot work — so a caller passing only properties
/// would otherwise get a grid that says it is 2×2 and has no cells in it. The
/// invariant belongs here because this is the one place everything is built.
pub fn Std::build(
  self : Std,
  name : String,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let full : Map[String, @tutuca.Value] = Map([])
  for k, v in args {
    full[k] = v
  }
  let count = (key : String, fallback : Int) => {
    match args.get(key) {
      Some(Num(n)) if n >= 1.0 => n.to_int()
      _ => fallback
    }
  }
  match name {
    "Grid" =>
      if !full.contains("children") {
        let (c, r) = (count("cols", 2), count("rows", 2))
        full["cols"] = Num(c.to_double())
        full["rows"] = Num(r.to_double())
        let cells : Array[@tutuca.Value] = []
        for _ in 0..<(c * r) {
          cells.push(self.cell())
        }
        full["children"] = List(cells)
      }
    // One cell rather than none: an empty container draws nothing to click,
    // and a person who just placed a stack is owed somewhere to put the next
    // thing.
    "Stack" =>
      if !full.contains("children") {
        full["children"] = List([self.cell()])
      }
    "Tabs" =>
      if !full.contains("tabs") {
        full["tabs"] = List([self.tab_page(label="tab 1")])
        full["active"] = Num(0.0)
      }
    "TabPage" => if !full.contains("body") { full["body"] = self.cell() }
    _ => ()
  }
  self.make_(name, full)
}

///|
/// A fresh empty cell — a `Universal` holding nothing, which is what draws a
/// `+`. Every container's children are these and only these.
pub fn Std::cell(self : Std) -> @tutuca.Value {
  self.make_("Universal", { "child": Null })
}

// --- the universal ----------------------------------------------------------

///|
/// What a held component is CALLED, for the badge that sits on top of it.
///
/// Read off the instance's own declared schema, so a guest is named by what it
/// declared and a standard component by the same thing. `?` for a value that
/// answers no schema, which is a value nothing here should be holding — saying
/// so beats an empty badge that reads as "no name".
fn label_of(child : @tutuca.Value) -> String {
  match child.schema() {
    Some(s) if s.name != "" => s.name
    _ => if child is Null { "" } else { "?" }
  }
}

///|
/// A `drop` that landed on a cell: the config pill, or an OS file drag that
/// happens to have landed here.
///
/// Only the first is ours. The second has to keep travelling, because a drop
/// stops at the first component that handles it and the shell's bundle loader
/// is further up — so an unrecognized payload answers `Unhandled` rather than
/// swallowing it.
fn drop_on_cell(
  s : UniversalState,
  ctx : &@tutuca.Ctx,
  info : @tutuca.Value,
) -> @component.Update[UniversalState] {
  if info.field("type").str() == "config-pill" {
    UniversalIntent::ConfigRequested(s.child).dispatch(ctx)
    ctx.stop_propagation()
    return Next(s)
  }
  Unhandled
}

///|
fn universal_comp() -> @component.Component {
  universal_component(
    compute=m => {
      match m {
        Label => Some((s, _args) => Str(label_of(s.child)))
      }
    },
    update=(s, msg, ctx) => {
      match UniversalMsg::from_dispatch(msg) {
        // Both routes to the same place: the `+` asks for something to hold,
        // and ctrl/cmd asks to configure it on the way in.
        Some(Add(configure)) => {
          UniversalIntent::AddRequested(configure).dispatch(ctx)
          return Next(s)
        }
        // The badge is what configures, not the box: a click on the box would
        // mean never being able to click through to what is held.
        Some(Pick) => {
          UniversalIntent::ConfigRequested(s.child).dispatch(ctx)
          return Next(s)
        }
        // Emptying gives the `+` back rather than deleting the cell. Deleting
        // a cell is the container's affordance, because the container is what
        // owns how many there are.
        Some(Remove) => return Next({ child: Null })
        // `dropped` is the pill, or an OS file drag that happens to have
        // landed here. Only the first is ours; the second has to keep
        // travelling, because `drop` stops at the first component that
        // handles it and the shell's bundle loader is further up.
        // Read from the DECODED variant rather than by re-matching `msg`.
        //
        // Re-matching was the bug and then the second bug. This arm is reached
        // through `UniversalMsg::from_dispatch`, which decodes the `Input`
        // bucket, so `msg` here is an `Input` and not the `Receive` the view
        // raised — a pattern naming one bucket silently read `Null`. And a
        // pattern naming both is one a codemod rewrites into a duplicate the
        // next time it runs.
        //
        // The variant already carries the payload. Taking it from there needs
        // no bucket at all, which is why it survives both.
        Some(Dropped(info)) => return drop_on_cell(s, ctx, info)
        Some(Unknown("dropped", args)) =>
          return drop_on_cell(s, ctx, args.get(0).unwrap_or(Null))
        Some(Unknown(_, _)) | None => ()
      }
      match UniversalReceive::from_dispatch(msg) {
        Some(Hold(child)) => Next({ child, })
        Some(Empty) => Next({ child: Null })
        // Written through the child's own COW rather than by rebuilding it
        // from arguments: everything the schema does NOT name — a half-typed
        // sentence, a scroll position, whatever a guest keeps privately —
        // survives a change to what it does.
        Some(ApplyConfig(fields)) => {
          guard s.child is Obj(_) else { return Unchanged }
          guard fields is Map(m) else { return Unchanged }
          let mut next = s.child
          for k, v in m {
            next = next.with_field(k, v)
          }
          Next({ child: next })
        }
        // The merged `Receive` now carries this component's own VIEW names as
        // well as the schema's, so `Unknown` no longer covers everything this
        // match has nothing to say about. They are answered by the match
        // beside this one.
        _ => Unhandled
      }
    },
  )
}

// --- the stack --------------------------------------------------------------

///|
/// The CSS a stack's own properties come to.
///
/// Host-generated and inline, following the precedent the layout model set: a
/// computed style string rather than a generated class, which keeps the class
/// set bounded no matter how many stacks a page has.
fn stack_style(s : StackState) -> String {
  let parts = [
    "display:flex",
    "flex-direction:\{direction_css(s.direction)}",
    "flex-wrap:\{if s.wrap { "wrap" } else { "nowrap" }}",
    "justify-content:\{justify_css(s.justify)}",
    "align-items:\{align_css(s.align)}",
  ]
  if s.gap > 0 {
    parts.push("gap:\{s.gap}px")
  }
  if s.padding > 0 {
    parts.push("padding:\{s.padding}px")
  }
  parts.join(";")
}

///|
/// The document's spelling of a direction, which is also CSS's. Anything else
/// falls back to `column` rather than being written through: a style string
/// the host generates is one place a guest's text must not become CSS.
fn direction_css(v : String) -> String {
  match v {
    "row" | "column" | "row-reverse" | "column-reverse" => v
    _ => "column"
  }
}

///|
/// A panel offers `start`; the style says `flex-start`. Two vocabularies
/// because they are two audiences — a person picking, and a browser reading.
fn justify_css(v : String) -> String {
  match v {
    "center" => "center"
    "end" => "flex-end"
    "space-between" => "space-between"
    "space-around" => "space-around"
    "space-evenly" => "space-evenly"
    _ => "flex-start"
  }
}

///|
fn align_css(v : String) -> String {
  match v {
    "start" => "flex-start"
    "center" => "center"
    "end" => "flex-end"
    "baseline" => "baseline"
    _ => "stretch"
  }
}

///|
/// `children` with `cell` inserted at `at`, clamped. -1 appends, which is what
/// "add one" means and saves every caller a length lookup.
fn spliced(
  children : Array[@tutuca.Value],
  at : Int,
  cell : @tutuca.Value,
) -> Array[@tutuca.Value] {
  let out = children.copy()
  let i = if at < 0 || at > out.length() { out.length() } else { at }
  out.insert(i, cell)
  out
}

///|
fn Std::stack_comp(self : Std) -> @component.Component {
  stack_component(
    init={ ..StackState::zero(), direction: "column", gap: 8 },
    compute=m => {
      match m {
        Style => Some((s, _args) => Str(stack_style(s)))
        IsRow =>
          Some((s, _args) => Bool(direction_css(s.direction).has_prefix("row")))
      }
    },
    update=(s, msg, _ctx) => {
      match StackMsg::from_dispatch(msg) {
        Some(InsertAt(at)) =>
          Next({
            ..s,
            children: spliced(s.children, at.num().to_int(), self.cell()),
          })
        Some(AppendCell) =>
          Next({ ..s, children: spliced(s.children, -1, self.cell()) })
        Some(Unknown(_, _)) | None => Unhandled
      }
    },
  )
}

// --- the grid ---------------------------------------------------------------

///|
/// A uniform grid's CSS. `repeat(n, 1fr)` on both axes is the whole of it,
/// which is what "uniform" buys: there is no track list to get wrong, and a
/// cell added anywhere is the same size as every other.
fn grid_style(s : GridState) -> String {
  let cols = if s.cols < 1 { 1 } else { s.cols }
  let rows = if s.rows < 1 { 1 } else { s.rows }
  let parts = [
    "display:grid",
    "grid-template-columns:repeat(\{cols},minmax(0,1fr))",
    "grid-template-rows:repeat(\{rows},minmax(0,1fr))",
  ]
  if s.gap > 0 {
    parts.push("gap:\{s.gap}px")
  }
  if s.padding > 0 {
    parts.push("padding:\{s.padding}px")
  }
  parts.join(";")
}

///|
/// `children` reshaped from `cols × rows` to `cols2 × rows2`, in row-major
/// order.
///
/// Every cell that exists in BOTH shapes keeps its identity — it is the same
/// value, not a fresh one — so resizing a grid does not throw away what is in
/// the cells that survive. That is the difference between a resize and a
/// rebuild, and it is the only reason this is not two lines.
fn reshaped(
  children : Array[@tutuca.Value],
  cols : Int,
  rows : Int,
  cols2 : Int,
  rows2 : Int,
  fresh : () -> @tutuca.Value,
) -> Array[@tutuca.Value] {
  let out : Array[@tutuca.Value] = []
  for r in 0..<rows2 {
    for c in 0..<cols2 {
      let from = r * cols + c
      out.push(
        if r < rows && c < cols && from < children.length() {
          children[from]
        } else {
          fresh()
        },
      )
    }
  }
  out
}

///|
/// The grid one row or column bigger, with the new cells at the near or far
/// edge.
///
/// Growing at the FAR edge is `reshaped` unchanged — the surviving cells keep
/// their coordinates. Growing at the NEAR edge shifts every existing cell by
/// one, which is why "before" is not just "after with a different number": the
/// cell that was at (0,0) has to end up at (0,1).
fn Std::grow(
  self : Std,
  s : GridState,
  cols2 : Int,
  rows2 : Int,
  shift_col : Int,
  shift_row : Int,
) -> GridState {
  let out : Array[@tutuca.Value] = []
  for r in 0..<rows2 {
    for c in 0..<cols2 {
      let from_c = c - shift_col
      let from_r = r - shift_row
      let from = from_r * s.cols + from_c
      out.push(
        if from_c >= 0 &&
          from_c < s.cols &&
          from_r >= 0 &&
          from_r < s.rows &&
          from < s.children.length() {
          s.children[from]
        } else {
          self.cell()
        },
      )
    }
  }
  { ..s, cols: cols2, rows: rows2, children: out }
}

///|
/// A grid at `cols × rows`, with exactly that many cells.
///
/// A thin wrapper over `build`, which is where the invariant lives — this
/// exists so a caller can name the two numbers rather than box them.
pub fn Std::grid(self : Std, cols? : Int = 2, rows? : Int = 2) -> @tutuca.Value {
  self.build("Grid", {
    "cols": Num(cols.to_double()),
    "rows": Num(rows.to_double()),
    "gap": Num(8.0),
    "padding": Num(0.0),
  })
}

///|
fn Std::grid_comp(self : Std) -> @component.Component {
  grid_component(
    init={ ..GridState::zero(), cols: 2, rows: 2, gap: 8 },
    compute=m => {
      match m {
        Style => Some((s, _args) => Str(grid_style(s)))
      }
    },
    update=(s, msg, _ctx) => {
      match GridMsg::from_dispatch(msg) {
        Some(AddColBefore) => Next(self.grow(s, s.cols + 1, s.rows, 1, 0))
        Some(AddColAfter) => Next(self.grow(s, s.cols + 1, s.rows, 0, 0))
        Some(AddRowBefore) => Next(self.grow(s, s.cols, s.rows + 1, 0, 1))
        Some(AddRowAfter) => Next(self.grow(s, s.cols, s.rows + 1, 0, 0))
        Some(Unknown(_, _)) | None => Unhandled
      }
    },
  )
}

///|
/// A grid resized from the settings panel, where a person types a number
/// rather than stepping one edge at a time.
///
/// Kept beside `grow` rather than folded into it because the two answer
/// different questions: `grow` knows WHICH edge, and this one only knows the
/// new shape — so it keeps the overlap and fills the rest.
pub fn Std::resize_grid(
  self : Std,
  s : GridState,
  cols~ : Int,
  rows~ : Int,
) -> GridState {
  let c = if cols < 1 { 1 } else { cols }
  let r = if rows < 1 { 1 } else { rows }
  {
    ..s,
    cols: c,
    rows: r,
    children: reshaped(s.children, s.cols, s.rows, c, r, () => self.cell()),
  }
}

// --- the tabs ---------------------------------------------------------------

///|
/// A tab page: a name, and a universal under it.
///
/// A fresh page opens on a `+` rather than on anything in particular, which is
/// what makes the notepad a composition — add a tab, pick a textarea — instead
/// of a component somebody had to write.
pub fn Std::tab_page(self : Std, label? : String = "untitled") -> @tutuca.Value {
  self.make_("TabPage", { "label": Str(label), "body": self.cell() })
}

///|
/// Tabs holding `count` fresh pages, the first one active.
pub fn Std::tabs(self : Std, count? : Int = 1) -> @tutuca.Value {
  let pages : Array[@tutuca.Value] = []
  for i in 0..<(if count < 1 { 1 } else { count }) {
    pages.push(self.tab_page(label="tab \{i + 1}"))
  }
  self.make_("Tabs", { "tabs": List(pages), "active": Num(0.0) })
}

///|
/// A tab page, which also draws its own NAME on the strip (the `tabname` view).
///
/// The name box lives here rather than in the strip's `@each` for a reason the
/// framework forces: inside a loop, a bare `value` handler argument resolves to
/// the loop's `@value` bind — the item — and never to the DOM event's value.
/// That shadowing is deliberate (`render/stack.mbt`), and `@enrich-with` cannot
/// undo it, because the loop restores `key` and `value` after the enricher
/// runs. A component boundary is a bind frame, so rendering the box as THIS
/// component's own view is what lets `value` mean what it says.
///
/// Typing writes the label on every keystroke, so the strip renames as you
/// type. What Enter and Escape MEAN is the strip's business — it is the thing
/// holding the old name — so they leave as bubbles.
fn tab_page_comp() -> @component.Component {
  tab_page_component(init={ ..TabPageState::zero(), label: "untitled" }, update=(
    s,
    msg,
    ctx,
  ) => {
    match TabPageMsg::from_dispatch(msg) {
      Some(SetLabel(label)) => Next({ ..s, label, })
      Some(DoneRename) => {
        TabPageIntent::DoneRename.dispatch(ctx)
        Unchanged
      }
      Some(CancelRename) => {
        TabPageIntent::CancelRename.dispatch(ctx)
        Unchanged
      }
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}

///|
/// The index the tab strip is showing, clamped into what exists. A stored
/// index that outran its list is what closing the last tab produces, and a
/// clamp here means every reader gets a legal answer instead of each one
/// guarding.
fn active_of(s : TabsState) -> Int {
  if s.tabs.is_empty() {
    -1
  } else if s.active < 0 {
    0
  } else if s.active >= s.tabs.length() {
    s.tabs.length() - 1
  } else {
    s.active
  }
}

///|
fn Std::tabs_comp(self : Std) -> @component.Component {
  tabs_component(
    // Which page to render, as a filter over the list rather than a field
    // holding the page: two places naming the same page is two places that can
    // disagree about which one it is.
    when=w => {
      match w {
        IsActivePage =>
          Some((s, key, _value, _iter) => key.num().to_int() == active_of(s))
      }
    },
    // The strip needs two per-row facts a `compute` cannot answer: it is pure
    // over the STATE and never sees the loop's key. `editing` is derived from
    // the other two rather than stored per row, so a row cannot be being
    // renamed while some other row is the one open.
    enrich=e => {
      match e {
        MarkActive =>
          Some((s, binds, key, _value, _iter) => {
            let here = key.num().to_int() == active_of(s)
            binds["active"] = Bool(here)
            binds["editing"] = Bool(here && s.renaming)
          })
      }
    },
    update=(s, msg, _ctx) => {
      match TabsMsg::from_dispatch(msg) {
        // Two call sites with different arities (the `main` strip cannot
        // rename, so it passes no modifier), which the generator joins into
        // one variadic case.
        Some(Activate(args)) => {
          let at = match args {
            [i, ..] => i.num().to_int()
            _ => return Unchanged
          }
          guard at >= 0 && at < s.tabs.length() else { return Unchanged }
          let configure = match args {
            [_, c, ..] => c.is_truthy()
            _ => false
          }
          // ctrl/cmd is "configure this" everywhere else in the app, and a
          // tab's only configuration is its name.
          return if configure {
            Next({
              ..s,
              active: at,
              renaming: true,
              original: s.tabs[at].field("label").str(),
            })
          } else {
            Next({ ..s, active: at, renaming: false, original: "" })
          }
        }
        Some(AddTab) => {
          let tabs = s.tabs.copy()
          tabs.push(self.tab_page(label="tab \{tabs.length() + 1}"))
          return Next({
            tabs,
            active: tabs.length() - 1,
            renaming: false,
            original: "",
          })
        }
        // Closing keeps the neighbour on the left, which is where the eye
        // already is; closing the last one leaves no tabs and no page, and the
        // `+` on the strip is how you get one back.
        Some(CloseActive) => {
          let at = active_of(s)
          if at < 0 {
            return Unhandled
          }
          let tabs = s.tabs.copy()
          tabs.remove(at) |> ignore
          return Next({
            tabs,
            active: if at > 0 {
              at - 1
            } else {
              0
            },
            renaming: false,
            original: "",
          })
        }
        Some(Unknown(_, _)) | None => ()
      }
      match msg {
        Intent("doneRename", _) =>
          if s.renaming {
            Next({ ..s, renaming: false, original: "" })
          } else {
            Unhandled
          }
        // Escape puts the old name back. It is kept rather than recomputed,
        // because typing already overwrote it — that is what renaming live
        // costs, and this is what pays it.
        Intent("cancelRename", _) => {
          guard s.renaming else { return Unchanged }
          let at = active_of(s)
          guard at >= 0 else {
            return Next({ ..s, renaming: false, original: "" })
          }
          let tabs = s.tabs.copy()
          tabs[at] = tabs[at].call_field("setLabel", [Str(s.original)])
          Next({ ..s, tabs, renaming: false, original: "" })
        }
        _ => Unhandled
      }
    },
  )
}

// --- the leaves -------------------------------------------------------------

///|
fn text_comp() -> @component.Component {
  text_component(compute=m => {
    match m {
      Style =>
        Some((s, _args) => {
          Str(
            match s.size {
              "small" => "font-size:0.85rem"
              "large" => "font-size:1.5rem;font-weight:600"
              _ => ""
            },
          )
        })
    }
  })
}

///|
/// The textarea needs no `update`: `setText` is the mutator its declared `text`
/// field implies, and the framework answers it. Saying so here is cheaper than
/// letting a reader wonder where the handler went.
fn textarea_comp() -> @component.Component {
  textarea_component(init={
    ..TextareaState::zero(),
    rows: 6,
    placeholder: "type here…",
  })
}

// --- the module -------------------------------------------------------------

///|
/// Every standard component, and a `Std` that can build any of them.
///
/// Returned as a pair rather than as a `ModuleDef` alone because the app needs
/// the second half: placing a component means constructing one by name, and
/// `Std::build` is what does it for everything in here.
pub fn std_components() -> (Array[@component.Component], Std) {
  let std : Std = { comps: Map([]) }
  // Leaves first, and not for tidiness: every container builds a `Universal`
  // when it inserts a cell, and `Tabs` builds a `TabPage` that builds one, so
  // `comps` has to hold them by the time any of those handlers runs.
  let comps = [universal_comp(), tab_page_comp(), text_comp(), textarea_comp()]
  for c in comps {
    std.comps[c.name] = c
  }
  for c in [std.stack_comp(), std.grid_comp(), std.tabs_comp()] {
    std.comps[c.name] = c
    comps.push(c)
  }
  (comps, std)
}

///|
/// The standard components as a module of their own.
pub fn std_module() -> @component.ModuleDef {
  let (comps, _) = std_components()
  @component.ModuleDef::new(name=module_name, components=comps)
}

///|
/// What the catalog calls this module. One name, stated once, because both the
/// registry and the app branch on it.
pub let module_name : String = "std"

///|
/// The standard components, as a `ComponentSource`: what a saved page resolves
/// its `$component` names through.
///
/// `build` goes to `Std::build` and not to `Component::make`, which is the
/// whole reason this impl is here rather than being the generic
/// `ComponentStack` one: a container comes back USABLE, with the cells its
/// declared arguments cannot carry. A document written by the codec always
/// names them, so the invariant only fires for a document written by hand.
pub impl @tutuca.ComponentSource for Std with fn describe(self, _module_, name) {
  self.comps.get(name).map(c => c.schema)
}

///|
pub impl @tutuca.ComponentSource for Std with fn build(
  self,
  _module_,
  name,
  args,
  // `Std` keeps no side table; a host that does wraps this one.
  at~ : String,
) {
  ignore(at)
  // `Some` only for a name this module declares, so an unknown one falls to
  // the field's default instead of writing a `Null` over it.
  self.comps.get(name).map(_c => Std::build(self, name, args))
}

///|
/// Whether this module declares `name`. What a caller resolving a bare
/// component name asks first, so the compiled-in components answer before a
/// dropped bundle gets a chance to shadow one.
pub fn Std::declares(self : Std, name : String) -> Bool {
  self.comps.contains(name)
}
