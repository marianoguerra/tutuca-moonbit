// Every `logic:` body shape, as the declarations it reads to.
//
// This was a DIFFERENTIAL assertion: the section read directly, and printed as
// the block language for `@tscript.parse` to read back, compared declaration
// by declaration. A reader that merely parses is a reader that could be
// producing anything; a reader that agrees with the thing it replaces, shape
// by shape, is one you can take the other side away from. That is what made
// the printer safe to delete, and it went with it.
//
// It earned its keep on the way out. It found three disagreements on the first
// run and three more when the card compiler was switched onto this reader —
// the collection-method name, a row member's parameters and a property
// setter's `value`, each of which had a handler silently refused and dropped
// behind it. The corpus is what is left, snapshotted: read these, do not just
// refresh them.

///|
fn read_one(src : String) -> String {
  let sources = @report.Sources::new()
  let id = sources.add("t.tutu", src)
  let file = @tutufile.read(src, id)
  guard file.section(Logic) is Some(section) else { return "no logic section" }
  guard section.decls is [decl, ..] else { return "no component" }
  let rows = match file.section(View) {
    Some(v) => @sh.row_members(v.decls)
    None => []
  }
  let direct = read_logic(decl, rows~) catch {
    ExError(message~, ..) => return "ERR " + message
  }
  flat(scrub(direct))
}

///|
/// The Debug rendering wraps at a width, so the same tree prints differently
/// inside a longer parent. Whitespace out.
fn flat(s : String) -> String {
  let out = StringBuilder()
  let mut space = false
  for c in s {
    if c is (' ' | '\n' | '\t') {
      space = true
    } else {
      // A trailing comma before a closing bracket is layout too: the Debug
      // renderer writes one only when it broke the line.
      if space && !(c is (')' | ']' | '}')) {
        out.write_char(' ')
      }
      space = false
      out.write_char(c)
    }
  }
  let mut text = out.to_string()
  // Whatever the renderer put next to a bracket is layout: the space it used
  // to indent, and the trailing comma it writes only when it broke the line.
  for _ in 0..<3 {
    for
      pair in [
        (",)", ")"),
        (",]", "]"),
        (",}", "}"),
        ("( ", "("),
        ("[ ", "["),
        ("{ ", "{"),
        (" )", ")"),
        (" ]", "]"),
        (" }", "}"),
        (", )", ")"),
      ] {
      text = text.replace_all(old=pair.0, new=pair.1)
    }
  }
  text
}

///|
/// Spans are file positions and the two paths measure from different files —
/// one from the `.tutu`, one from the text it was printed to. Blanked, because
/// what is compared is the declarations and not where they sat.
fn scrub(ds : Array[@tscript.Decl]) -> String {
  let out = @debug.to_string(ds)
  let sb = StringBuilder()
  let cs = out.to_array()
  let mut i = 0
  while i < cs.length() {
    if i + 6 < cs.length() &&
      cs[i] == 's' &&
      cs[i + 1] == 'p' &&
      cs[i + 2] == 'a' &&
      cs[i + 3] == 'n' {
      // `span: {start: 12, end_: 30}` — skip to the closing brace.
      sb.write_string("span: _")
      while i < cs.length() && cs[i] != '}' {
        i = i + 1
      }
      i = i + 1
    } else {
      sb.write_char(cs[i])
      i = i + 1
    }
  }
  sb.to_string()
}

///|
/// One `logic:` body, as the declarations it reads to.
fn reads(body : String) -> String {
  read_one(
    "spec:\n  T:\n    field n :: Int\n    field xs :: List.of(String)\n    field s :: String\n    field rows :: List.of(Any)\n\nlogic:\n  T:\n" +
    body,
  )
}

///|
test "every statement shape, as the declarations it reads to" {
  let bodies = [
    "    receive inc:\n      it.n += 1\n", "    receive dec:\n      it.n -= 1\n",
    "    receive set_it(v):\n      it.n := v\n", "    receive push(v):\n      it.xs.push(v)\n",
    "    receive flash:\n      send(\"flash\", it.s)\n", "    receive save:\n      ask(\"save_draft\", it.s, ~route: lex)\n",
    "    receive tell:\n      notify(\"changed\", it.n)\n", "    receive stop_it:\n      drop()\n",
    "    receive guard_it:\n      if it.n > 0 | it.n := 0\n", "    receive two_ways:\n      if it.n > 0 | it.n := 0 | it.n := 1\n",
    "    compute caption(): it.s.length()\n", "    pred room: it.n < 10\n", "    receive bump:\n      ~requires: room\n      it.n += 1\n",
    "    bind_with info:\n      heading = it.s\n", "    receive drop_at(i):\n      it.xs.delete_at(i)\n",
    // A constructor inside an expression. There is no aggregate literal in the
    // value language, so it is lifted into the `new` / `cur` pair that builds
    // one — a `.tutu` writes a CALL where the old notation asked for the pair
    // by hand.
     "    receive add_row:\n      it.rows.push(Row())\n", "    receive add_named(t):\n      it.rows.push(Row(label: t))\n",
    // A property with a body, both accessors. `set:` is the one declaration
    // whose parameter nothing writes down — the notation has no place for it
    // and the reader supplies it.
     "    property shown :: Int:\n      get: it.n\n      set: it.n := value\n", "    property signed :: Int:\n      get: if it.n < 0 | -it.n | it.n\n      set:\n        if it.n < 0\n        | it.n := -value\n        | it.n := value\n",
    // A row member: the renderer's names for a row are fixed, so the author's
    // parameters ARE the bindings and the declaration keeps none.
     "    enrich row(value, key):\n      tag = value.to_string()\n",
  ]
  let out = StringBuilder()
  for b in bodies {
    out.write_string(b.trim().to_owned() + "\n  -> " + reads(b) + "\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|receive inc:
      #|      it.n += 1
      #|  -> [{kind: DReceive, name: "inc", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PState("n"), steps: []}, op=AAdd, value=ELit(lit=LNum(1), from_macro=false), span: _)]), doc: "", span: _, name_span: _}]
      #|receive dec:
      #|      it.n -= 1
      #|  -> [{kind: DReceive, name: "dec", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PState("n"), steps: []}, op=ASub, value=ELit(lit=LNum(1), from_macro=false), span: _)]), doc: "", span: _, name_span: _}]
      #|receive set_it(v):
      #|      it.n := v
      #|  -> [{kind: DReceive, name: "set_it", params: [{name: "v", span: _}], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PState("n"), steps: []}, op=ASet, value=EName(name="v"), span: _)]), doc: "", span: _, name_span: _}]
      #|receive push(v):
      #|      it.xs.push(v)
      #|  -> [{kind: DReceive, name: "push", params: [{name: "v", span: _}], requires_: None, ensures_: None, format: None, body: Stmts([SMethod(place={root: PState("xs"), steps: []}, call="push", args=[EName(name="v")], span: _)]), doc: "", span: _, name_span: _}]
      #|receive flash:
      #|      send("flash", it.s)
      #|  -> [{kind: DReceive, name: "flash", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SEffect(name="send", args=[ELit(lit=LStr("flash"), from_macro=false), ERead(place={root: PState("s"), steps: []})], route=[], span: _)]), doc: "", span: _, name_span: _}]
      #|receive save:
      #|      ask("save_draft", it.s, ~route: lex)
      #|  -> [{kind: DReceive, name: "save", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SEffect(name="ask", args=[ELit(lit=LStr("save_draft"), from_macro=false), ERead(place={root: PState("s"), steps: []})], route=[Lex], span: _)]), doc: "", span: _, name_span: _}]
      #|receive tell:
      #|      notify("changed", it.n)
      #|  -> [{kind: DReceive, name: "tell", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SEffect(name="notify", args=[ELit(lit=LStr("changed"), from_macro=false), ERead(place={root: PState("n"), steps: []})], route=[], span: _)]), doc: "", span: _, name_span: _}]
      #|receive stop_it:
      #|      drop()
      #|  -> [{kind: DReceive, name: "stop_it", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SEffect(name="drop", args=[], route=[], span: _)]), doc: "", span: _, name_span: _}]
      #|receive guard_it:
      #|      if it.n > 0 | it.n := 0
      #|  -> [{kind: DReceive, name: "guard_it", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SIf(cond=EChain(family=FCompare, ops=[">"], operands=[ERead(place={root: PState("n"), steps: []}), ELit(lit=LNum(0), from_macro=false)]), then_=[SAssign(place={root: PState("n"), steps: []}, op=ASet, value=ELit(lit=LNum(0), from_macro=false), span: _)], else_=[], span: _)]), doc: "", span: _, name_span: _}]
      #|receive two_ways:
      #|      if it.n > 0 | it.n := 0 | it.n := 1
      #|  -> [{kind: DReceive, name: "two_ways", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SIf(cond=EChain(family=FCompare, ops=[">"], operands=[ERead(place={root: PState("n"), steps: []}), ELit(lit=LNum(0), from_macro=false)]), then_=[SAssign(place={root: PState("n"), steps: []}, op=ASet, value=ELit(lit=LNum(0), from_macro=false), span: _)], else_=[SAssign(place={root: PState("n"), steps: []}, op=ASet, value=ELit(lit=LNum(1), from_macro=false), span: _)], span: _)]), doc: "", span: _, name_span: _}]
      #|compute caption(): it.s.length()
      #|  -> [{kind: DCompute, name: "caption", params: [], requires_: None, ensures_: None, format: None, body: Value(EApp(name="len", args=[ERead(place={root: PState("s"), steps: []})])), doc: "", span: _, name_span: _}]
      #|pred room: it.n < 10
      #|  -> [{kind: DPred, name: "room", params: [], requires_: None, ensures_: None, format: None, body: Value(EChain(family=FCompare, ops=["<"], operands=[ERead(place={root: PState("n"), steps: []}), ELit(lit=LNum(10), from_macro=false)])), doc: "", span: _, name_span: _}]
      #|receive bump:
      #|      ~requires: room
      #|      it.n += 1
      #|  -> [{kind: DReceive, name: "bump", params: [], requires_: Some({name: "room", span: _}), ensures_: None, format: None, body: Stmts([SAssign(place={root: PState("n"), steps: []}, op=AAdd, value=ELit(lit=LNum(1), from_macro=false), span: _)]), doc: "", span: _, name_span: _}]
      #|bind_with info:
      #|      heading = it.s
      #|  -> [{kind: DBindWith, name: "info", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PBind("heading"), steps: []}, op=ASet, value=ERead(place={root: PState("s"), steps: []}), span: _)]), doc: "", span: _, name_span: _}]
      #|receive drop_at(i):
      #|      it.xs.delete_at(i)
      #|  -> [{kind: DReceive, name: "drop_at", params: [{name: "i", span: _}], requires_: None, ensures_: None, format: None, body: Stmts([SMethod(place={root: PState("xs"), steps: []}, call="deleteAt", args=[EName(name="i")], span: _)]), doc: "", span: _, name_span: _}]
      #|receive add_row:
      #|      it.rows.push(Row())
      #|  -> [{kind: DReceive, name: "add_row", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SNew(ty={name: "Row", args: [], span: _}, span: _), SMethod(place={root: PState("rows"), steps: []}, call="push", args=[ERead(place={root: PTarget, steps: []})], span: _)]), doc: "", span: _, name_span: _}]
      #|receive add_named(t):
      #|      it.rows.push(Row(label: t))
      #|  -> [{kind: DReceive, name: "add_named", params: [{name: "t", span: _}], requires_: None, ensures_: None, format: None, body: Stmts([SNew(ty={name: "Row", args: [], span: _}, span: _), SAssign(place={root: PTarget, steps: [PField("label")]}, op=ASet, value=EName(name="t"), span: _), SMethod(place={root: PState("rows"), steps: []}, call="push", args=[ERead(place={root: PTarget, steps: []})], span: _)]), doc: "", span: _, name_span: _}]
      #|property shown :: Int:
      #|      get: it.n
      #|      set: it.n := value
      #|  -> [{kind: DGet, name: "shown", params: [], requires_: None, ensures_: None, format: None, body: Value(ERead(place={root: PState("n"), steps: []})), doc: "", span: _, name_span: _}, {kind: DSet, name: "shown", params: [{name: "value", span: _}], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PState("n"), steps: []}, op=ASet, value=EName(name="value"), span: _)]), doc: "", span: _, name_span: _}]
      #|property signed :: Int:
      #|      get: if it.n < 0 | -it.n | it.n
      #|      set:
      #|        if it.n < 0
      #|        | it.n := -value
      #|        | it.n := value
      #|  -> [{kind: DGet, name: "signed", params: [], requires_: None, ensures_: None, format: None, body: Value(EIf(cond=EChain(family=FCompare, ops=["<"], operands=[ERead(place={root: PState("n"), steps: []}), ELit(lit=LNum(0), from_macro=false)]), then_=EUnary(op=UNeg, operand=ERead(place={root: PState("n"), steps: []})), else_=ERead(place={root: PState("n"), steps: []}))), doc: "", span: _, name_span: _}, {kind: DSet, name: "signed", params: [{name: "value", span: _}], requires_: None, ensures_: None, format: None, body: Stmts([SIf(cond=EChain(family=FCompare, ops=["<"], operands=[ERead(place={root: PState("n"), steps: []}), ELit(lit=LNum(0), from_macro=false)]), then_=[SAssign(place={root: PState("n"), steps: []}, op=ASet, value=EUnary(op=UNeg, operand=EName(name="value")), span: _)], else_=[SAssign(place={root: PState("n"), steps: []}, op=ASet, value=EName(name="value"), span: _)], span: _)]), doc: "", span: _, name_span: _}]
      #|enrich row(value, key):
      #|      tag = value.to_string()
      #|  -> [{kind: DEnrich, name: "row", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PBind("tag"), steps: []}, op=ASet, value=EApp(name="str", args=[ERead(place={root: PBind("value"), steps: []})]), span: _)]), doc: "", span: _, name_span: _}]
      #|
    ),
  )
}

///|
test "a transition keeps its doc comment" {
  inspect(
    read_one(
      (
        #|spec:
        #|  T:
        #|    field n :: Int
        #|logic:
        #|  T:
        #|    /// One up.
        #|    receive inc:
        #|      it.n += 1
        #|
      ),
    ),
    content=(
      #|[{kind: DReceive, name: "inc", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PState("n"), steps: []}, op=AAdd, value=ELit(lit=LNum(1), from_macro=false), span: _)]), doc: "One up.", span: _, name_span: _}]
    ),
  )
}

///|
/// A path attached to a handler's own parameter is a path into the ARGUMENT.
///
/// `member_expr` sent every bare-name base to `bind_member`, so `t.iso` read
/// as the loop binding `@t` — and the refusal a card's author saw was "`@t` is
/// a binding, which a handler does not have — the renderer hands them to a
/// `@when`", about a construct they had not written. `PParam` is the root the
/// old script parser built for the same shape, and `tscript/check` has
/// answered `NO_PARAM` about it all along; the whole of what was missing was
/// this reader.
///
/// A body's free name is the parameter, and a name the body BOUND is the
/// binding — the two are told apart by the scope, which is what `Local` is
/// for.
test "a path on a parameter reads the argument, not a binding" {
  inspect(
    read_one(
      (
        #|spec:
        #|  T:
        #|    field now :: Any
        #|logic:
        #|  T:
        #|    receive ticked(t):
        #|      it.now := t.iso
        #|
      ),
    ),
    content=(
      #|[{kind: DReceive, name: "ticked", params: [{name: "t", span: _}], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PState("now"), steps: []}, op=ASet, value=ERead(place={root: PParam("t"), steps: [PField("iso")]}), span: _)]), doc: "", span: _, name_span: _}]
    ),
  )
}

///|
/// An index on a parameter is the same path, so the two agree about what the
/// name is.
test "an index on a parameter reads the argument too" {
  inspect(
    read_one(
      (
        #|spec:
        #|  T:
        #|    field first :: Any
        #|logic:
        #|  T:
        #|    receive rows(rs):
        #|      it.first := rs[0]
        #|
      ),
    ),
    content=(
      #|[{kind: DReceive, name: "rows", params: [{name: "rs", span: _}], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PState("first"), steps: []}, op=ASet, value=ERead(place={root: PParam("rs"), steps: [PIndex(ELit(lit=LNum(0), from_macro=false))]}), span: _)]), doc: "", span: _, name_span: _}]
    ),
  )
}

///|
/// A name the body BOUND is still a binding, path and all.
///
/// The half that keeps the fix narrow: an enricher's `@name` and a loop's row
/// are bindings wherever they are in scope, and only a FREE name is the
/// argument.
test "a bound name keeps its member read as a binding's" {
  inspect(
    read_one(
      (
        #|spec:
        #|  T:
        #|    field label :: Any
        #|logic:
        #|  T:
        #|    enrich mark(item, i):
        #|      badge = item.title
        #|
      ),
    ),
    content=(
      #|[{kind: DEnrich, name: "mark", params: [], requires_: None, ensures_: None, format: None, body: Stmts([SAssign(place={root: PBind("badge"), steps: []}, op=ASet, value=ERead(place={root: PBind("value"), steps: [PField("title")]}), span: _)]), doc: "", span: _, name_span: _}]
    ),
  )
}
