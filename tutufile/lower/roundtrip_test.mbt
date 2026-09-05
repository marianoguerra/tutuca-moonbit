// The two properties the parser promises, asserted over every `.tutu` source
// this package holds: what it reads reproduces its input exactly, and what it
// re-formats reads back to the same tree.
//
// Asked for by the library's author before considering the 0.1.1 fix closed,
// and worth keeping afterwards: a reader that cannot reproduce its input
// cannot be the basis of a formatter or a converter, and both are coming.

///|
/// Every `.tutu` source in this package's tests, as one corpus.
fn corpus() -> Array[(String, String)] {
  [
    ("guarded", guarded),
    ("protocols", with_protocols),
    ("whole card", whole_card_view),
  ]
}

///|
let whole_card_view : String =
  #|spec:
  #|  Todos ~root:
  #|    ~category: "lists"
  #|    ~keywords: ["todo", "list"]
  #|    field draft :: String
  #|    field items :: List.of(Todo)
  #|    where it.draft.length() <= 100
  #|  Todo:
  #|    field text :: String
  #|  struct Line(what :: String, qty :: Int)
  #|
  #|logic:
  #|  Todos:
  #|    receive add:
  #|      it.items.push(Todo(text: it.draft))
  #|      it.draft := ""
  #|    compute caption(): @str{@(it.draft) x}
  #|
  #|view:
  #|  macro badge(~label: "New"):
  #|    @span{@(label)}
  #|  Todos:
  #|    @div(~class: "list"){
  #|      @each(row, i in it.items){
  #|        @li(~class: if it.draft.is_empty() | "a" | "b"){@render(row)}
  #|      }
  #|      @badge(~label: "x")
  #|    }
  #|  @style{ .list { color: red; } }
  #|
  #|fixtures:
  #|  "some":
  #|    ~doc: "a few"
  #|    it.draft = "x"
  #|
  #|tests:
  #|  "adding":
  #|    type("input", "x")
  #|    click("button")
  #|    expect count("li") == 1
  #|

///|
test "every source reproduces itself exactly" {
  let broken = []
  for c in corpus() {
    let (name, src) = c
    let parsed = @shrub.parse(src) catch {
      e => {
        broken.push(name + ": parse: " + e.diagnostic().kind.code())
        continue
      }
    }
    if @shrub.to_source(parsed.root()) != src {
      broken.push(name + ": to_source differs from the input")
    }
  }
  @debug.assert_eq(broken, [])
}

///|
test "and re-formatting reads back to the same tree" {
  let broken = []
  for c in corpus() {
    let (name, src) = c
    let first = @shrub.parse(src) catch {
      e => {
        broken.push(name + ": parse: " + e.diagnostic().kind.code())
        continue
      }
    }
    let written = @shrub.write(first.root(), style=Pretty, width=Some(0))
    let second = @shrub.parse(written) catch {
      e => {
        broken.push(name + ": reparse: " + e.diagnostic().kind.code())
        continue
      }
    }
    if first.root().canonical() != second.root().canonical() {
      broken.push(name + ": the re-formatted tree is not the same tree")
    }
  }
  @debug.assert_eq(broken, [])
}

///|
test "how deep real at-notation nests, against the depth bound" {
  // `max_depth` defaults to 64, set by the smallest backend's stack rather
  // than by the grammar. This says where a view written the way the guide
  // writes one actually sits — a number worth having before anyone raises it.
  let deep = StringBuilder()
  deep.write_string("view:\n  T:\n")
  let levels = 20
  for i in 0..<levels {
    deep.write_string("    ")
    for _ in 0..<i {
      deep.write_string("  ")
    }
    deep.write_string("@div(~class: \"l\"){\n")
  }
  for i in 0..<levels {
    deep.write_string("    ")
    for _ in 0..<(levels - 1 - i) {
      deep.write_string("  ")
    }
    deep.write_string("}\n")
  }
  let src = deep.to_string()
  // twenty nested elements is deeper than any view in this repository, and it
  // parses well inside the bound
  let out = lower_text(src)
  assert_eq(out.reports.length(), 0)
  assert_true(out.text.contains("<div class=\"l\">"))
}
