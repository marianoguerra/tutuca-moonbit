///|
/// A page, faked with three closures.
///
/// This is what makes the walk assertable: no wasm, no browser, no catalog.
/// Every instance is a `Map` recording what it was built with, so the ORDER
/// and the ARGUMENTS are both readable afterwards.
struct Fake {
  built : Array[String]
  /// What each component answers when asked `cellField`, by name.
  cell_fields : Map[String, String]
  /// Names this fake refuses to build at all.
  refuse : Array[String]
}

///|
fn Fake::new(
  cell_fields? : Map[String, String] = Map([]),
  refuse? : Array[String] = [],
) -> Fake {
  { built: [], cell_fields, refuse, }
}

///|
fn Fake::host(self : Fake) -> @compose.ComposeHost {
  {
    make: (ref_, args) => {
      if self.refuse.contains(ref_.name) {
        return None
      }
      self.built.push(ref_.name)
      let fields : Map[String, @tutuca.Value] = Map([])
      for k, v in args {
        fields[k] = v
      }
      fields["__name"] = Str(ref_.name)
      Some(Map(fields))
    },
    property: (v, name) => {
      guard name == "cellField" else { return None }
      guard v is Map(m) else { return None }
      guard m.get("__name") is Some(Str(n)) else { return None }
      match self.cell_fields.get(n) {
        Some(f) => Some(Str(f))
        None => None
      }
    },
    hole: held => {
      self.built.push("Hole")
      Some(Map({ "__name": Str("Hole"), "child": held.unwrap_or(Null) }))
    },
  }
}

///|
fn node(
  name : String,
  cells? : Int = 0,
  args? : Map[String, Json] = Map([]),
  children? : Array[(Int, @compose.PlanNode)] = [],
) -> @compose.PlanNode {
  { ref_: { module_: "kit", name, }, args, cells, children, }
}

///|
fn cell_at(v : @tutuca.Value, field : String, i : Int) -> @tutuca.Value {
  match v {
    Map(m) =>
      match m.get(field) {
        Some(List(items)) => items.get(i).unwrap_or(Null)
        _ => Null
      }
    _ => Null
  }
}

///|
fn name_of(v : @tutuca.Value) -> String {
  match v {
    Map(m) =>
      match m.get("__name") {
        Some(Str(s)) => s
        _ => ""
      }
    _ => ""
  }
}

///|
test "a leaf is built once, with the arguments it was given" {
  let fake = Fake::new()
  let (out, report) = @compose.build(
    fake.host(),
    node("Text", args={ "text": Json::string("hi") }),
  )
  assert_eq(fake.built, ["Text"])
  assert_eq(report.problems, [])
  assert_eq(report.placed, ["kit/Text"])
  assert_true(out is Some(Map(_)))
}

///|
test "a container is built twice, and the first one is the question" {
  // `cellField` is a PROPERTY, and only an instance answers a property — the
  // manifest carries its declaration and not what it says. So an empty one is
  // built to ask, thrown away, and the real one built with the cells in it.
  let fake = Fake::new(cell_fields={ "Tabs": "tabs" })
  let (out, _) = @compose.build(fake.host(), node("Tabs", cells=2))
  assert_eq(fake.built, ["Tabs", "Hole", "Hole", "Tabs"])
  // …and the cells went in under the name it gave, not under the default.
  assert_eq(name_of(cell_at(out.unwrap(), "tabs", 0)), "Hole")
  assert_eq(cell_at(out.unwrap(), "children", 0), Null)
}

///|
test "a container that will not say gets the default, and it is named" {
  let fake = Fake::new()
  let (out, _) = @compose.build(fake.host(), node("Box", cells=1))
  assert_eq(@compose.default_cell_field, "children")
  assert_eq(name_of(cell_at(out.unwrap(), "children", 0)), "Hole")
}

///|
test "the build is bottom up: every cell exists before its container does" {
  let fake = Fake::new(cell_fields={ "Box": "children", "Grid": "children" })
  let (_, report) = @compose.build(
    fake.host(),
    node("Box", cells=2, children=[
      (0, node("Grid", cells=2)),
      (1, node("Text")),
    ]),
  )
  // The probe, then the inner grid's own probe and cells, then the grid, then
  // its hole, then the text and its hole, then the box. Deepest first, and the
  // box is last because it cannot exist until its cells do.
  assert_eq(fake.built, [
    "Box", "Grid", "Hole", "Hole", "Grid", "Hole", "Text", "Hole", "Box",
  ])
  assert_eq(report.placed, ["kit/Grid", "kit/Text", "kit/Box"])
}

///|
test "a cell nobody filled is an empty hole, not a missing cell" {
  let fake = Fake::new()
  let (out, report) = @compose.build(
    fake.host(),
    node("Box", cells=3, children=[(1, node("Text"))]),
  )
  assert_eq(report.problems, [])
  let root = out.unwrap()
  assert_eq(name_of(cell_at(root, "children", 0)), "Hole")
  assert_eq(cell_at(cell_at(root, "children", 0), "child", 0), Null)
  assert_eq(name_of(cell_at(cell_at(root, "children", 1), "child", 0)), "")
}

///|
test "cells widen to fit a child placed past the end" {
  let fake = Fake::new()
  let (out, _) = @compose.build(
    fake.host(),
    node("Box", cells=1, children=[(3, node("Text"))]),
  )
  // Four cells, not one: a child at index 3 is a claim about how big this is.
  assert_eq(name_of(cell_at(out.unwrap(), "children", 3)), "Hole")
  assert_eq(cell_at(out.unwrap(), "children", 4), Null)
}

///|
test "a child that could not be built leaves a hole and names itself" {
  let fake = Fake::new(refuse=["Missing"])
  let (out, report) = @compose.build(
    fake.host(),
    node("Box", cells=2, children=[(0, node("Missing")), (1, node("Text"))]),
  )
  // The arrangement still stands, with a gap a person can see and fill — and
  // the sibling was built, rather than the whole thing being abandoned.
  assert_eq(report.problems, ["could not build kit/Missing"])
  assert_eq(report.placed, ["kit/Text", "kit/Box"])
  assert_eq(name_of(cell_at(out.unwrap(), "children", 0)), "Hole")
}
