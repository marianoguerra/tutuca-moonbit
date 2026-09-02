// A two-level app, built without a view file.
//
// Hand-written rather than borrowed from `storybook/examples`, and the reason
// is the dependency: `storybook` is excluded from publish, and a published
// package whose tests reach into it is a package that only builds inside this
// repo. `View::from_ir` is what a generated view module calls anyway, so this
// is the same component a `.html` would have produced, written out.
//
// Two levels because that is the only shape where relocation means anything,
// and because the interesting events are the ones that CROSS between them.

// --- Row ----------------------------------------------------------------------

///|
priv struct RowState {
  label : String
  n : Int
}

///|
impl @component.Fields for RowState with fn schema() {
  @component.SchemaInfo::new(
    name="Row",
    fingerprint="row-v1",
    fields=[
      @component.FieldInfo::new("label", TyText),
      @component.FieldInfo::new("n", TyInt(width=32, signed=true)),
    ],
    view_names=["main"],
    receives=["bump", "reset", "save", "saved"],
  )
}

///|
impl @component.Fields for RowState with fn encode(s) {
  { "label": Str(s.label), "n": Num(s.n.to_double()) }
}

///|
impl @component.Fields for RowState with fn decode(f) {
  guard f.get("label") is Some(Str(label)) else { return None }
  guard f.get("n") is Some(Num(n)) else { return None }
  Some({ label, n: n.to_int(), })
}

///|
fn row_views() -> Map[String, @anode.View] {
  {
    "main": @anode.View::from_ir(
      "main",
      @anode.h("li", [@anode.attr("class", "row"), @anode.eid(0)], [
        @anode.dyn_text(@tutuca.Expr::field("label")),
        @anode.text(" "),
        @anode.h("span", [@anode.attr("class", "n")], [
          @anode.dyn_text(@tutuca.Expr::field("n")),
        ]),
      ]),
      [[@anode.on("click", @tutuca.Expr::name("bump"))]],
    ),
  }
}

///|
fn row_comp() -> @component.Component {
  @component.component(
    name="Row",
    views=row_views(),
    init=RowState::{ label: "", n: 0, },
    update=(s, msg, ctx) => {
      match msg {
        // Counting up, and asking the HOST to persist it. The intent is what
        // makes this fixture worth having: it is the one thing a rerun cannot
        // recompute for itself.
        Receive("bump", _) => {
          ctx.intent(
            "save",
            [Str(s.label)],
            @tutuca.IntentOpts::new(
              route=[Lex],
              on_ok_name="saved",
              on_unhandled_name="saved",
            ),
          )
          Next({ ..s, n: s.n + 1, })
        }
        Receive("saved", _) => Next({ ..s, label: s.label + "*", })
        Receive("reset", _) => Next({ ..s, n: 0, })
        _ => Unhandled
      }
    },
  )
}

// --- Board --------------------------------------------------------------------

///|
priv struct BoardState {
  title : String
  rows : Array[@tutuca.Value]
}

///|
impl @component.Fields for BoardState with fn schema() {
  @component.SchemaInfo::new(
    name="Board",
    fingerprint="board-v1",
    fields=[
      @component.FieldInfo::new("title", TyText),
      @component.FieldInfo::new("rows", TyList(TyComp(Some("Row")))),
    ],
    view_names=["main"],
    receives=["touch", "bumpFirst"],
  )
}

///|
impl @component.Fields for BoardState with fn encode(s) {
  { "title": Str(s.title), "rows": List(s.rows) }
}

///|
impl @component.Fields for BoardState with fn decode(f) {
  guard f.get("title") is Some(Str(title)) else { return None }
  guard f.get("rows") is Some(List(rows)) else { return None }
  Some({ title, rows, })
}

///|
fn board_views() -> Map[String, @anode.View] {
  {
    "main": @anode.View::from_ir(
      "main",
      @anode.h("div", [@anode.attr("class", "board")], [
        @anode.h("h1", [], [@anode.dyn_text(@tutuca.Expr::field("title"))]),
        // `<ul render-each=".rows">`: each row renders ITSELF, which is what
        // makes `rows[0]` a component boundary and therefore a place a
        // recording can be relocated onto.
        @anode.h("ul", [], [
          // The two ids are the each's node and the rendered item's, and they
          // must differ: they are what the event walker reads back out of the
          // DOM markers to tell "this is the loop" from "this is the child",
          // and a collision resolves a click on a row to the board.
          @anode.each(
            1,
            @tutuca.Expr::field("rows"),
            @anode.render_it(0),
            from_render_each=true,
          ),
        ]),
      ]),
      [],
    ),
  }
}

///|
fn board_comp() -> @component.Component {
  @component.component(
    name="Board",
    views=board_views(),
    init=BoardState::{ title: "", rows: [], },
    update=(s, msg, ctx) => {
      match msg {
        // The cross-level event: the board reacts to one message by sending into
        // a CHILD. After a cut to that child, this is the message that has to
        // survive as an input, because there is no board left to send it.
        Receive("touch", _) => {
          ctx.at().index("rows", 0).send("reset", [])
          Next({ ..s, title: s.title + ".", })
        }
        Receive("bumpFirst", _) => {
          ctx.at().index("rows", 0).send("bump", [])
          Unchanged
        }
        _ => Unhandled
      }
    },
  )
}

///|
fn board_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="board", components=[board_comp(), row_comp()])
}

///|
/// A scope with both components registered — what a recording is replayed
/// against, and what rebuilds its snapshot.
fn board_scope() -> @component.ComponentStack raise {
  board_module().build_scope()
}

///|
/// A board with two rows, built through the very same `Component` the scope
/// registers: an instance carries a component id, and one built from a fresh
/// `row_comp()` would name a component the mounted scope does not have.
fn board_value(scope : @component.ComponentStack) -> @tutuca.Value raise {
  guard scope.lookup_component("Row") is Some(row) else {
    fail("no Row in scope")
  }
  guard scope.lookup_component("Board") is Some(board) else {
    fail("no Board in scope")
  }
  board.make({
    "title": Str("shopping"),
    "rows": List([
      row.make({ "label": Str("milk"), "n": Num(0) }),
      row.make({ "label": Str("eggs"), "n": Num(0) }),
    ]),
  })
}
