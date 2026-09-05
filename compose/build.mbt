///|
/// One node of an arrangement, ready to build.
pub(all) struct PlanNode {
  ref_ : @catalog.ComponentRef
  args : Map[String, Json]
  /// How many cells to open with. Empty holes, all of them.
  cells : Int
  /// `(cell index, child)`, in order. A cell with no entry here is one left
  /// empty ON PURPOSE — the `+` a person fills in later — so it is absent
  /// rather than present and blank.
  children : Array[(Int, PlanNode)]
}

///|
/// What the builder needs from the page, and nothing else.
///
/// Three closures rather than a module handle, so the walk below is testable
/// with no wasm, no browser and no catalog — which is the only way the
/// bottom-up order gets asserted at all.
pub(all) struct ComposeHost {
  /// Build one component of one module.
  make : (@catalog.ComponentRef, Map[String, @tutuca.Value]) -> @tutuca.Value?
  /// Read a public property off a built instance.
  property : (@tutuca.Value, String) -> @tutuca.Value?
  /// A holder, empty or around something. Separate from `make` so the walk
  /// never learns which module the holder came from.
  hole : (@tutuca.Value?) -> @tutuca.Value?
}

///|
/// What a build could not do. Empty means it did everything.
pub(all) struct BuildReport {
  problems : Array[String]
  /// Deepest first, which is the order they were built in.
  placed : Array[String]
}

///|
/// The field name a container's cells go in when it will not say.
///
/// `children` is what every container in the kit calls them, so it is the
/// least surprising guess — and it is a GUESS, reached only when a component
/// claims the protocol and then does not answer its own property.
pub let default_cell_field : String = "children"

///|
/// Build one node and everything under it.
pub fn build(
  host : ComposeHost,
  node : PlanNode,
) -> (@tutuca.Value?, BuildReport) {
  let report : BuildReport = { problems: [], placed: [], }
  let out = built_tree(host, node, report)
  (out, report)
}

///|
fn value_args(args : Map[String, Json]) -> Map[String, @tutuca.Value] {
  let out : Map[String, @tutuca.Value] = Map([])
  for k, v in args {
    out[k] = @tutuca.Value::from_json(v)
  }
  out
}

///|
fn built_tree(
  host : ComposeHost,
  node : PlanNode,
  report : BuildReport,
) -> @tutuca.Value? {
  let id = node.ref_.to_id()
  // A leaf, or a node whose container-ness nobody asked for: build it and go.
  if node.cells <= 0 && node.children.is_empty() {
    let out = (host.make)(node.ref_, value_args(node.args))
    if out is None {
      report.problems.push("could not build \{id}")
    } else {
      report.placed.push(id)
    }
    return out
  }
  // A container is built TWICE, and the first one is the question.
  //
  // `cellField` is the guest's answer to "what are your cells called", and an
  // instance is the only thing that can be asked — a manifest carries the
  // property's declaration and not what it says. The empty one is thrown away.
  let probe = (host.make)(node.ref_, value_args(node.args))
  guard probe is Some(empty) else {
    report.problems.push("could not build \{id}")
    return None
  }
  let field = match (host.property)(empty, "cellField") {
    Some(Str(name)) if name != "" => name
    _ => default_cell_field
  }
  // The cells, deepest first. A child that could not be built leaves an EMPTY
  // hole rather than no cell: an arrangement with a gap in it is still an
  // arrangement, and a person can see which one failed and fill it.
  let by_index : Map[Int, PlanNode] = Map([])
  for pair in node.children {
    by_index[pair.0] = pair.1
  }
  let wanted = {
    let mut n = node.cells
    for pair in node.children {
      if pair.0 + 1 > n {
        n = pair.0 + 1
      }
    }
    n
  }
  let cells : Array[@tutuca.Value] = []
  for i in 0..<wanted {
    let inner = match by_index.get(i) {
      Some(child) => built_tree(host, child, report)
      None => None
    }
    match (host.hole)(inner) {
      Some(h) => cells.push(h)
      None => report.problems.push("could not build a cell for \{id}")
    }
  }
  let args = value_args(node.args)
  args[field] = List(cells)
  let out = (host.make)(node.ref_, args)
  if out is None {
    report.problems.push("could not build \{id}")
  } else {
    report.placed.push(id)
  }
  out
}
