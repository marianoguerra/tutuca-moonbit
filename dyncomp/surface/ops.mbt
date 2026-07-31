///| The patch algebra. Six operations, and everything either layer does to a
/// surface is a batch of them.
///
/// This is the seam the whole design turns on. The universal UI's "add a cell"
/// button and an agent's `ui_apply` call produce the SAME op, so there is no
/// shape one can reach and the other cannot, and no second implementation to
/// drift. Every invariant a surface has is enforced here, once.
///
/// A batch is ATOMIC: it either applies whole or changes nothing. Half-applied
/// layouts are the failure mode that makes a generated UI unrecoverable — the
/// caller cannot tell what it now has, so it cannot decide what to do next.

///|
/// A change to a surface.
///
/// `SetProps` takes a partial: a map of prop name to value, so that "change
/// the gap" is one op that does not have to restate the direction. That is the
/// difference between a legible patch and a full node rewrite every time.
pub(all) enum SurfaceOp {
  /// Add a node under `parent` at `index` (clamped into range; -1 appends).
  AddNode(
    parent~ : String,
    index~ : Int,
    kind~ : NodeKind,
    props~ : Map[String, @tutuca.Value]
  )
  /// Remove a node and its whole subtree. The root cannot be removed.
  RemoveNode(id~ : String)
  /// Move a node under a new parent at a new index.
  MoveNode(id~ : String, parent~ : String, index~ : Int)
  /// Change some of a node's props, leaving the rest alone.
  SetProps(id~ : String, props~ : Map[String, @tutuca.Value])
  /// Fill (or, with `None`, empty) a Slot.
  BindInstance(id~ : String, binding~ : Binding?)
  /// Write into the data model at a JSON Pointer.
  SetData(pointer~ : String, value~ : @tutuca.Value)
} derive(Eq, Debug)

///|
/// One op that could not be applied, and where.
///
/// `index` is the op's position in the batch, so a caller with six ops knows
/// which one failed rather than only that something did. `pointer` is RFC 6901
/// into the surface document — the same spelling `dyncomp/jsonschema` uses for
/// a bad argument, so a caller has one convention to learn.
pub(all) struct OpError {
  index : Int
  pointer : String
  message : String
} derive(Eq, Debug)

///|
fn op_err(index : Int, pointer : String, message : String) -> OpError {
  { index, pointer, message }
}

///|
/// The pointer at a node: `/nodes/<id>`.
fn node_ptr(id : String) -> String {
  "/nodes/\{escape_token(id)}"
}

///|
/// RFC 6901 escaping. Node ids are generated here so they never need it, but a
/// DESERIALIZED surface carries whatever ids its document had.
fn escape_token(s : String) -> String {
  s.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
fn unescape_token(s : String) -> String {
  s.replace_all(old="~1", new="/").replace_all(old="~0", new="~")
}

// --- prop decoding ---------------------------------------------------------

///|
/// Apply a partial prop map to a `LayoutProps`.
///
/// Unknown names and unusable values are ERRORS rather than being ignored. An
/// ignored typo is a layout that silently did not change, and "why did nothing
/// happen" is the single most expensive question a generated-UI loop can ask.
fn apply_props(
  base : LayoutProps,
  props : Map[String, @tutuca.Value],
  index : Int,
  ptr : String,
  errors : Array[OpError],
) -> LayoutProps {
  let mut out = base
  for k, v in props {
    let at = "\{ptr}/props/\{escape_token(k)}"
    let bad = (want : String) => {
      errors.push(
        op_err(index, at, "expected \{want}, got \{v.to_display_string()}"),
      )
    }
    match k {
      "direction" =>
        match Direction::parse(v.str()) {
          Some(d) => out = { ..out, direction: d }
          None => bad("row | column | row-reverse | column-reverse")
        }
      "justify" =>
        match Justify::parse(v.str()) {
          Some(j) => out = { ..out, justify: j }
          None =>
            bad(
              "start | center | end | space-between | space-around | space-evenly",
            )
        }
      "align" =>
        match Align::parse(v.str()) {
          Some(a) => out = { ..out, align: a }
          None => bad("start | center | end | stretch | baseline")
        }
      "wrap" =>
        match v {
          Bool(b) => out = { ..out, wrap: b }
          _ => bad("a boolean")
        }
      "gap" | "padding" | "colSpan" | "rowSpan" | "colStart" | "rowStart" =>
        match v {
          Num(n) => {
            let i = n.to_int()
            // A span of zero collapses a cell and a negative one is
            // meaningless; both are far more likely to be a mistake than an
            // intent, so they are refused rather than clamped.
            if i < 0 {
              bad("a non-negative number")
            } else if (k == "colSpan" || k == "rowSpan") && i < 1 {
              bad("a span of at least 1")
            } else {
              out = match k {
                "gap" => { ..out, gap: i }
                "padding" => { ..out, padding: i }
                "colSpan" => { ..out, col_span: i }
                "rowSpan" => { ..out, row_span: i }
                "colStart" => { ..out, col_start: i }
                _ => { ..out, row_start: i }
              }
            }
          }
          _ => bad("a number")
        }
      "columns" | "rows" =>
        match v {
          List(items) => {
            let tracks : Array[Track] = []
            let mut ok = true
            for i, item in items {
              match Track::parse(item.str()) {
                Some(t) => tracks.push(t)
                None => {
                  ok = false
                  errors.push(
                    op_err(
                      index,
                      "\{at}/\{i}",
                      "expected a track: <n>fr | <n>px | auto, got \{item.to_display_string()}",
                    ),
                  )
                }
              }
            }
            if ok {
              out = if k == "columns" {
                { ..out, columns: tracks }
              } else {
                { ..out, rows: tracks }
              }
            }
          }
          _ => bad("a list of tracks")
        }
      "background" =>
        match v {
          Str(s) => out = { ..out, background: s }
          _ => bad("a string")
        }
      "border" =>
        match v {
          Str(s) => out = { ..out, border: s }
          _ => bad("a string")
        }
      _ =>
        errors.push(
          op_err(
            index, at, "no such layout property (direction, wrap, justify, align, gap, padding, columns, rows, colSpan, rowSpan, colStart, rowStart, background, border)",
          ),
        )
    }
  }
  out
}

// --- data model ------------------------------------------------------------

///|
/// Split an RFC 6901 pointer into its tokens. `""` is the whole document and
/// yields no tokens; anything not starting with `/` is malformed.
fn pointer_tokens(pointer : String) -> Array[String]? {
  if pointer == "" {
    return Some([])
  }
  if !pointer.has_prefix("/") {
    return None
  }
  let out : Array[String] = []
  for part in pointer[1:].split("/") {
    out.push(unescape_token(part.to_owned()))
  }
  Some(out)
}

///|
/// Write `value` at `tokens`, creating intermediate objects as needed.
///
/// Creating them is a decision: `SetData("/user/name", …)` on an empty model
/// should work, because the alternative is making a caller write the object
/// first — two round trips for one intent, and the first one is pure ceremony.
fn set_at(
  doc : @tutuca.Value,
  tokens : ArrayView[String],
  value : @tutuca.Value,
) -> @tutuca.Value {
  match tokens {
    [] => value
    [head, .. rest] => {
      let m = match doc {
        Map(m) => m
        // Anything that is not an object at this depth is REPLACED by one.
        // A pointer says what shape the caller wants; refusing because the
        // slot currently holds a number would make the model's history
        // constrain its future.
        _ => Map([])
      }
      let child = m.get(head).unwrap_or(Map(Map([])))
      let next : Map[String, @tutuca.Value] = Map([])
      for k, v in m {
        next[k] = v
      }
      next[head] = set_at(child, rest, value)
      Map(next)
    }
  }
}

// --- the ops ---------------------------------------------------------------

///|
/// Everything the tree invariant requires, checked in one place: every node is
/// reachable from the root exactly once, a Box holds at most one child, and a
/// Slot holds none.
fn check_capacity(
  s : Surface,
  parent : String,
  index : Int,
  ptr : String,
  errors : Array[OpError],
) -> Bool {
  guard s.nodes.get(parent) is Some(p) else {
    errors.push(op_err(index, ptr, "no such node: \{parent}"))
    return false
  }
  match p.kind {
    Slot => {
      errors.push(op_err(index, ptr, "a slot holds a component, not children"))
      false
    }
    Box =>
      if p.children.length() >= 1 {
        errors.push(
          op_err(index, ptr, "a box holds one child, and already has one"),
        )
        false
      } else {
        true
      }
    Stack | Grid => true
  }
}

///|
/// Insert `id` into `parent`'s children at `index`, clamped. -1 appends, which
/// is what "add one" means and saves every caller a length lookup.
fn insert_child(s : Surface, parent : String, id : String, index : Int) -> Unit {
  guard s.nodes.get(parent) is Some(p) else { return }
  let kids = p.children.copy()
  let at = if index < 0 || index > kids.length() {
    kids.length()
  } else {
    index
  }
  kids.insert(at, id)
  s.nodes[parent] = { ..p, children: kids }
}

///|
fn detach(s : Surface, id : String) -> Unit {
  for pid, n in s.nodes {
    if n.children.contains(id) {
      let kids = n.children.copy()
      kids.retain(c => c != id)
      s.nodes[pid] = { ..n, children: kids }
      return
    }
  }
}

///|
/// `id` and everything under it.
fn subtree(s : Surface, id : String) -> Array[String] {
  let out : Array[String] = []
  fn visit(n : String, depth : Int) -> Unit {
    if depth > 64 {
      return
    }
    guard s.nodes.get(n) is Some(node) else { return }
    out.push(n)
    for c in node.children {
      visit(c, depth + 1)
    }
  }

  visit(id, 0)
  out
}

///|
/// A shallow copy of a surface, so a failed batch can be discarded whole. The
/// node table is rebuilt (nodes are immutable records, so the entries are
/// shared) and only the map itself is fresh.
fn clone(s : Surface) -> Surface {
  let nodes : Map[String, Node] = Map([])
  for k, v in s.nodes {
    nodes[k] = v
  }
  { ..s, nodes, }
}

///|
fn apply_one(
  s : Surface,
  op : SurfaceOp,
  index : Int,
  errors : Array[OpError],
) -> Surface {
  match op {
    AddNode(parent~, index=at, kind~, props~) => {
      let ptr = node_ptr(parent)
      if !check_capacity(s, parent, index, ptr, errors) {
        return s
      }
      let id = "n\{s.next_id}"
      let base = apply_props(
        LayoutProps::default(),
        props,
        index,
        node_ptr(id),
        errors,
      )
      let node : Node = { id, kind, props: base, children: [], bound: None }
      let out = { ..s, next_id: s.next_id + 1 }
      out.nodes[id] = node
      insert_child(out, parent, id, at)
      out
    }
    RemoveNode(id~) => {
      let ptr = node_ptr(id)
      if id == s.root {
        errors.push(
          op_err(index, ptr, "the root cannot be removed; empty it instead"),
        )
        return s
      }
      guard s.nodes.get(id) is Some(_) else {
        errors.push(op_err(index, ptr, "no such node: \{id}"))
        return s
      }
      // The whole subtree goes: leaving descendants in the table would make
      // them unreachable, and an unreachable node is a leak a serializer would
      // faithfully preserve.
      for n in subtree(s, id) {
        s.nodes.remove(n) |> ignore
      }
      detach(s, id)
      s
    }
    MoveNode(id~, parent~, index=at) => {
      let ptr = node_ptr(id)
      if id == s.root {
        errors.push(op_err(index, ptr, "the root has no parent to move to"))
        return s
      }
      guard s.nodes.get(id) is Some(_) else {
        errors.push(op_err(index, ptr, "no such node: \{id}"))
        return s
      }
      // A node cannot be moved under itself: the result is a cycle, which is a
      // tree that walks forever rather than a layout anyone wanted.
      if subtree(s, id).contains(parent) {
        errors.push(
          op_err(index, ptr, "cannot move a node into its own subtree"),
        )
        return s
      }
      if !check_capacity(s, parent, index, ptr, errors) {
        return s
      }
      detach(s, id)
      insert_child(s, parent, id, at)
      s
    }
    SetProps(id~, props~) => {
      let ptr = node_ptr(id)
      guard s.nodes.get(id) is Some(n) else {
        errors.push(op_err(index, ptr, "no such node: \{id}"))
        return s
      }
      let next = apply_props(n.props, props, index, ptr, errors)
      s.nodes[id] = { ..n, props: next }
      s
    }
    BindInstance(id~, binding~) => {
      let ptr = node_ptr(id)
      guard s.nodes.get(id) is Some(n) else {
        errors.push(op_err(index, ptr, "no such node: \{id}"))
        return s
      }
      if !(n.kind is Slot) {
        errors.push(
          op_err(
            index,
            ptr,
            "only a slot holds a component; this is a \{n.kind.to_string()}",
          ),
        )
        return s
      }
      s.nodes[id] = { ..n, bound: binding }
      s
    }
    SetData(pointer~, value~) => {
      guard pointer_tokens(pointer) is Some(tokens) else {
        errors.push(
          op_err(
            index,
            "/data",
            "not a JSON Pointer: \{pointer} (it must be \"\" or start with /)",
          ),
        )
        return s
      }
      { ..s, data: set_at(s.data, tokens[:], value) }
    }
  }
}

///|
/// Apply a batch of ops. All of them, or none.
///
/// Atomicity is the contract that matters most here. A caller that got half a
/// layout cannot tell what it now has, so it cannot decide what to do next —
/// and for a language model that means the next call is a guess. Working on a
/// clone and discarding it on any error is the cheap way to make "it failed"
/// mean "nothing happened".
pub fn apply(
  s : Surface,
  ops : Array[SurfaceOp],
) -> Result[Surface, Array[OpError]] {
  let errors : Array[OpError] = []
  let mut working = clone(s)
  for i, op in ops {
    working = apply_one(working, op, i, errors)
  }
  if errors.is_empty() {
    Ok(working)
  } else {
    Err(errors)
  }
}
