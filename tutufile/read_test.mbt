// What the reader answers, and what it says when it cannot.
//
// The failure tests assert on the MESSAGE and the HELP, never on the code.
// A code is a constant that stays green while the sentence beside it rots,
// and the sentence is the whole product here.

///|
/// Read one source, with a name for the reports to point at.
fn read_one(src : String) -> (TutuFile, @report.Sources) {
  let sources = @report.Sources::new()
  let id = sources.add("todos.tutu", src)
  (read(src, id), sources)
}

///|
/// The headline of the first thing that went wrong.
fn first_message(src : String) -> String {
  let (file, _) = read_one(src)
  guard file.reports.length() > 0 else { return "<no reports>" }
  file.reports[0].message
}

///|
/// The repair the first report names.
fn first_help(src : String) -> String {
  let (file, _) = read_one(src)
  guard file.reports.length() > 0 else { return "<no reports>" }
  match file.reports[0].help {
    Some(h) => h
    None => "<no help>"
  }
}

///|
/// A whole card, the way the proposal writes one.
let whole_card : String =
  #|spec:
  #|  /// A list that makes its own rows.
  #|  Todos ~root:
  #|    field draft :: String
  #|    field items :: List.of(Todo)
  #|  Todo:
  #|    field text :: String
  #|    field done :: Bool
  #|  struct Line(what :: String, qty :: Int)
  #|
  #|logic:
  #|  Todos:
  #|    receive add:
  #|      ~requires: typed
  #|      it.items.push(Todo(text: it.draft, done: false))
  #|      it.draft := ""
  #|  Todo:
  #|    receive toggle: it.done := !it.done
  #|
  #|view:
  #|  Todos:
  #|    @div{
  #|      @input(~class: "draft", ~value: it.draft)
  #|      @button(~class: "add", ~on_click: add){add}
  #|      @ul{@each(row in it.items){@render(row)}}
  #|    }
  #|  Todo:
  #|    @li(~class: "todo", ~on_click: toggle){@(it.caption)}
  #|  macro badge(~label: "New"):
  #|    @span(~class: "badge"){@(label)}
  #|  @style{ .todo { color: red; } }
  #|
  #|fixtures:
  #|  "three rows" ~default:
  #|    ~doc: "A list that has been used."
  #|    it.draft = ""
  #|
  #|tests:
  #|  "typing and adding makes a row":
  #|    type("input.draft", "write it")
  #|    click("button.add")
  #|    expect count("li.todo") == 1
  #|

///|
test "a whole card reads into five sections" {
  let (file, _) = read_one(whole_card)
  assert_true(file.ok())
  let names = []
  for s in file.sections {
    names.push(s.section.name())
  }
  debug_inspect(
    names,
    content=(
      #|["spec", "logic", "view", "fixtures", "tests"]
    ),
  )
}

///|
test "each section lists what it declares, in source order" {
  let (file, _) = read_one(whole_card)
  debug_inspect(
    file.section(Spec).unwrap().names(),
    content=(
      #|["Todos", "Todo", "Line"]
    ),
  )
  debug_inspect(
    file.section(Logic).unwrap().names(),
    content=(
      #|["Todos", "Todo"]
    ),
  )
  // the style block has no name; it is the one declaration that answers to none
  debug_inspect(
    file.section(View).unwrap().names(),
    content=(
      #|["Todos", "Todo", "badge", ""]
    ),
  )
  debug_inspect(
    file.section(Fixtures).unwrap().names(),
    content=(
      #|["three rows"]
    ),
  )
  debug_inspect(
    file.section(Tests).unwrap().names(),
    content=(
      #|["typing and adding makes a row"]
    ),
  )
}

///|
test "a bare name is the section's own kind, and the rest name themselves" {
  let (file, _) = read_one(whole_card)
  let spec = file.section(Spec).unwrap()
  assert_true(spec.decls[0].kind is Component)
  assert_true(spec.decls[2].kind is Struct)
  // the same line in `view:` is a view, because the section says what it is
  assert_true(file.section(View).unwrap().decls[0].kind is View)
  assert_true(file.section(View).unwrap().decls[2].kind is Macro)
  assert_true(file.section(View).unwrap().decls[3].kind is Style)
  assert_true(file.section(Fixtures).unwrap().decls[0].kind is Fixture)
  assert_true(file.section(Tests).unwrap().decls[0].kind is Scene)
}

///|
test "the options written on a header come back with it" {
  let (file, _) = read_one(whole_card)
  debug_inspect(
    file.decl(Spec, "Todos").unwrap().options,
    content=(
      #|["root"]
    ),
  )
  debug_inspect(
    file.decl(Fixtures, "three rows").unwrap().options,
    content=(
      #|["default"]
    ),
  )
  debug_inspect(file.decl(Spec, "Todo").unwrap().options, content="[]")
}

///|
test "a declaration keeps the block under it, unread" {
  let (file, _) = read_one(whole_card)
  let todo = file.decl(Logic, "Todo").unwrap()
  // the body is the shrubbery tree, not a parsed handler — this package does
  // not know what a `receive` is
  inspect(
    todo.body.unwrap().canonical(),
    content="(block (group |receive| |toggle| (block (group |it| (op |.|) |done| (op |:=|) (op |!|) |it| (op |.|) |done|))))",
  )
}

///|
test "a `.tutu` file has no script section, and the message says so" {
  let src =
    #|spec:
    #|  Todos:
    #|    field draft :: String
    #|
    #|script:
    #|  Todos:
    #|    receive add: it.draft := ""
    #|
  inspect(first_message(src), content="there is no `script:` section")
  inspect(
    first_help(src),
    content="write `logic:` — the section was renamed when it stopped living in a `<script>` tag",
  )
}

///|
test "the near misses an author arrives with are named, not listed" {
  inspect(
    first_help("test:\n  \"x\":\n    click(\"b\")\n"),
    content="write `tests:` — a section holds every scene, so it is plural",
  )
  inspect(
    first_help("views:\n  Todos:\n    @div{x}\n"),
    content="write `view:` — only `fixtures` and `tests` are plural",
  )
  inspect(
    first_help("template:\n  Todos:\n    @div{x}\n"),
    content="write `view:` — a `.tutu` file has no templates, it has views",
  )
}

///|
test "a section nobody could guess is answered with the five" {
  inspect(
    first_help("styles:\n  Todos:\n    @div{x}\n"),
    content="the sections are `spec:`, `logic:`, `view:`, `fixtures:`, `tests:`, in that order",
  )
}

///|
test "one section per name" {
  let src =
    #|spec:
    #|  Todos:
    #|    field a :: Int
    #|
    #|spec:
    #|  Todo:
    #|    field b :: Int
    #|
  inspect(first_message(src), content="`spec:` is declared twice")
  inspect(
    first_help(src),
    content="move these declarations into the first `spec:` — a file has one of each section",
  )
}

///|
test "the order is a rule, so a place to look never moves" {
  let src =
    #|tests:
    #|  "a scene":
    #|    click("button")
    #|
    #|spec:
    #|  Todos:
    #|    field a :: Int
    #|
  inspect(first_message(src), content="`spec:` comes after `tests:`")
  inspect(
    first_help(src),
    content="move `spec:` above `tests:` — the order is `spec:`, `logic:`, `view:`, `fixtures:`, `tests:`, so a reader always knows where to look",
  )
}

///|
test "a lowercase bare name is a forgotten keyword, and the help says both" {
  let src =
    #|spec:
    #|  todos:
    #|    field a :: Int
    #|
  inspect(first_message(src), content="`todos` is not a component name")
  inspect(
    first_help(src),
    content="write `Todos:` if it is a component, or name the kind you meant — `struct`, `enum`, `protocol`",
  )
}

///|
test "a component is named by an identifier and a scene by a string" {
  let quoted =
    #|spec:
    #|  "Todos":
    #|    field a :: Int
    #|
  inspect(
    first_message(quoted),
    content="a component is named by an identifier, not a string",
  )
  inspect(
    first_help(quoted),
    content="drop the quotes — only a fixture and a scene are named in prose, because their names are sentences",
  )
  let bare =
    #|tests:
    #|  TypingAdds:
    #|    click("button")
    #|
  inspect(first_message(bare), content="a scene is named by a string")
  inspect(
    first_help(bare),
    content="put the name in quotes, like `\"three rows\":` — a scene name is prose",
  )
}

///|
test "a keyword declaration in the wrong section is sent to the right one" {
  let src =
    #|spec:
    #|  macro badge(~label: "New"):
    #|    @span{x}
    #|
  inspect(first_message(src), content="a macro cannot be declared in `spec:`")
  inspect(first_help(src), content="move it to `view:`")
  let styled =
    #|logic:
    #|  @style{ .a { color: red; } }
    #|
  inspect(
    first_message(styled),
    content="a style block cannot be declared in `logic:`",
  )
}

///|
test "a struct's fields are its header, so an empty one is caught there" {
  let src =
    #|spec:
    #|  struct Line
    #|
  inspect(first_message(src), content="`Line` declares no fields")
  inspect(
    first_help(src),
    content="write the fields in parentheses, like `struct Line(what :: String, qty :: Int)`",
  )
}

///|
test "a component with no block declares nothing" {
  let src =
    #|spec:
    #|  Todos ~root
    #|
  inspect(first_message(src), content="`Todos` declares nothing")
  inspect(
    first_help(src),
    content="end the line with `:` and indent what the component holds under it",
  )
}

///|
test "a file that declares nothing says what a file opens with" {
  inspect(first_message("\n"), content="this file declares nothing")
  inspect(
    first_help("\n"),
    content="a `.tutu` file opens with a section — `spec:`, `logic:`, `view:`, `fixtures:`, `tests:`, in that order",
  )
}

///|
test "a shrubbery failure is reported as itself, not swallowed" {
  // the second group is indented differently from the first: shrubbery's
  // error, carried through unchanged, because this package has nothing to add
  let src =
    #|spec:
    #|  Todos:
    #|    field a :: Int
    #|   Todo:
    #|    field b :: Int
    #|
  inspect(
    first_message(src),
    content="this group is not indented like the ones around it",
  )
}

///|
test "one bad section does not hide the next" {
  let src =
    #|spec:
    #|  todos:
    #|    field a :: Int
    #|
    #|view:
    #|  Todos:
    #|    @div{x}
    #|
  let (file, _) = read_one(src)
  assert_false(file.ok())
  // the spec section is still there, minus the declaration that failed
  debug_inspect(file.section(Spec).unwrap().names(), content="[]")
  debug_inspect(
    file.section(View).unwrap().names(),
    content=(
      #|["Todos"]
    ),
  )
}

///|
test "the spans a report carries land on the source it came from" {
  let src =
    #|spec:
    #|  todos:
    #|    field a :: Int
    #|
  let (file, sources) = read_one(src)
  let config = {
    ..@render.default_config,
    theme: @style.mono_theme,
    color: Never,
  }
  inspect(
    @render.render_string(file.reports[0], sources, config),
    content=(
      #|error[tutu::not_a_type_name]: `todos` is not a component name
      #|  ╭─[ todos.tutu:2:3 ]
      #|  │
      #|1 │ spec:
      #|2 │   todos:
      #|  │   ──┬──
      #|  │     ╰─ this starts lowercase
      #|3 │     field a :: Int
      #|  │
      #|  ├─ help: write `Todos:` if it is a component, or name the kind you meant — `struct`, `enum`, `protocol`
      #|  ╰─
      #|
    ),
  )
}

///|
test "a view may carry the view name as well as the component's" {
  let src =
    #|view:
    #|  Note:
    #|    @p{@(it.title)}
    #|  Note.edit:
    #|    @input(~value: it.title)
    #|
  let (file, _) = read_one(src)
  assert_true(file.ok())
  debug_inspect(
    file.section(View).unwrap().names(),
    content=(
      #|["Note", "Note.edit"]
    ),
  )
}
