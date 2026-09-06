// Reading a declaration's header: the shapes every section shares.
//
// `field n :: Int = 0`, `receive drop(i :: Int)`, `pred room`,
// `message load_rows_ok(List.of(Row))` — each is a word, a name, an optional
// parameter list, an optional annotation, an optional initialiser, and the
// options that lead its block. One reader, because they are one shape.

///|
/// One declaration inside a section's component, before anything is printed.
pub(all) struct Member {
  /// The leading word: `field`, `receive`, `pred`, `property`, …
  word : String
  name : String
  /// `(a :: T, b)` if it has one.
  params : Array[Param]
  /// `:: T` if it has one.
  ty : Ex?
  /// `= expr` if it has one.
  init : Ex?
  /// `~name: value` and bare `~name`, in source order.
  options : Array[(String, Ex?)]
  /// The block under it, if any.
  body : @ast.Node?
  /// The block's groups, minus the `~option:` lines that lead it.
  stmts : Array[@ast.Node]
  /// Everything after the name that is neither, kept for the readers that
  /// need the raw terms (a `where` clause is a relation, not a call).
  rest : Array[@ast.Node]
  span : @report.Span
  doc : String?
}

///|
/// One parameter of a member: a name and an optional annotation.
pub(all) struct Param {
  name : String
  ty : Ex?
}

///|
/// Read one group as a member declaration.
///
/// `prev` is the sibling before this one, and it is here because of where
/// shrubbery puts a doc comment. `///` lines between two members attach as the
/// SUFFIX of the one before, not as the prefix of the one after — so a member's
/// own prefix carries its doc only when nothing precedes it, and every later
/// member in a block read its doc as `None`. Every doc comment but the first in
/// a block was being dropped: fields, rules and handlers alike.
pub fn read_member(
  group : @ast.Node,
  prev? : @ast.Node?,
) -> Member raise ExError {
  guard group.it is Group(parts) && parts.length() > 0 else {
    raise ExError(
      message="this is not a declaration",
      help="a declaration starts with a word — `field`, `receive`, `pred`, `property`",
      span=span_of(group),
    )
  }
  guard parts[0].it is Id(word) else {
    raise ExError(
      message="a declaration starts with a word",
      help="`\{node_text(parts[0])}` names no kind of member",
      span=span_of(parts[0]),
    )
  }
  let mut name = ""
  let params = []
  let mut ty : Ex? = None
  let mut init : Ex? = None
  let options = []
  let mut body : @ast.Node? = None
  let rest = []
  let mut i = 1
  // A member may be QUALIFIED — `receive Holder::hold(inst)` answers a
  // protocol's message rather than one of its own. The name is read whole,
  // before `::` can be mistaken for the annotation operator beside it.
  match (if can_qualify(word) { qualified(parts, 1) } else { None }) {
    Some((q, next)) => {
      name = q
      i = next
      if i < parts.length() && parts[i].it is Parens(gs) {
        for g in gs {
          params.push(read_param(g))
        }
        i = i + 1
      }
    }
    None =>
      if i < parts.length() && parts[i].it is Id(n) {
        name = n
        i = i + 1
        // a parameter list belongs to the name it follows
        if i < parts.length() && parts[i].it is Parens(gs) {
          for g in gs {
            params.push(read_param(g))
          }
          i = i + 1
        }
      }
  }
  while i < parts.length() {
    let t = parts[i]
    match t.it {
      Op("::") => {
        let stop = next_boundary(parts, i + 1)
        ty = Some(read_ex(parts[i + 1:stop]))
        i = stop
      }
      Op("=") => {
        let stop = next_boundary(parts, i + 1)
        init = Some(read_ex(parts[i + 1:stop]))
        i = stop
      }
      // An option on the HEADER is a flag: a block after it is the member's
      // body, because options that carry a value lead the block instead.
      Kw(o) => {
        options.push((o, None))
        i = i + 1
      }
      Block(_) => {
        body = Some(t)
        i = i + 1
      }
      _ => {
        rest.push(t)
        i = i + 1
      }
    }
  }
  // Options lead the block; the body follows. That one rule is what lets a
  // rule's `~format`, a handler's `~requires` and a scene's `~component` be
  // the same construct, so it is read in one place for all of them.
  let stmts = []
  match body {
    Some(node) =>
      match node.it {
        Block(groups) => {
          let mut leading = true
          for g in groups {
            if leading &&
              g.it is Group(gp) &&
              gp.length() >= 1 &&
              gp[0].it is Kw(name) {
              if gp.length() >= 2 && gp[1].it is Block(bgs) && bgs.length() == 1 {
                options.push((name, Some(read_group(bgs[0]))))
              } else {
                options.push((name, None))
              }
            } else {
              leading = false
              stmts.push(g)
            }
          }
        }
        _ => ()
      }
    None => ()
  }
  {
    word,
    name,
    params,
    ty,
    init,
    options,
    body,
    stmts,
    rest,
    span: span_of(group),
    doc: member_doc(group, prev.bind(x => x)),
  }
}

///|
/// Which members may carry a protocol-qualified name.
///
/// Not every member can: `field n :: Int` is a name and an annotation, and
/// `::` is the operator in both — so the two are told apart by what is being
/// declared rather than by looking at the terms, which cannot tell them apart
/// at all.
fn can_qualify(word : String) -> Bool {
  word
  is ("receive"
  | "answer"
  | "message"
  | "intent"
  | "express"
  | "property"
  | "view")
}

///|
/// Where an annotation or initialiser ends: the next option, block, or `=`.
fn next_boundary(parts : Array[@ast.Node], from : Int) -> Int {
  let mut i = from
  while i < parts.length() {
    match parts[i].it {
      Kw(_) | Block(_) | Op("=") => return i
      _ => i = i + 1
    }
  }
  i
}

///|
pub fn read_param(group : @ast.Node) -> Param raise ExError {
  // A macro's parameter carries a default and is written as an option, which
  // is what a default IS: `macro badge(~label: "New")`.
  if group.it is Group(kp) && kp.length() >= 1 && kp[0].it is Kw(name) {
    return { name, ty: None, }
  }
  guard group.it is Group(parts) && parts.length() > 0 else {
    raise ExError(
      message="a parameter is a name",
      help="write `(i :: Int)`, or `(item)` for one the caller names",
      span=span_of(group),
    )
  }
  guard parts[0].it is Id(name) else {
    raise ExError(
      message="a parameter is a name",
      help="write `(i :: Int)`",
      span=span_of(parts[0]),
    )
  }
  if parts.length() >= 3 && parts[1].it is Op("::") {
    { name, ty: Some(read_ex(parts[2:])), }
  } else {
    { name, ty: None, }
  }
}

///|
/// The `///` comment written above a declaration, if there is one.
///
/// Shrubbery keeps every comment in the node's prefix, so the doc a member
/// carries survives the lowering rather than being dropped at the boundary —
/// which is the whole reason the old block had `///` in the first place.
pub fn doc_of(node : @ast.Node) -> String? {
  let raw = node.meta.prefix.to_text()
  let lines : Array[String] = []
  for line in raw.split("\n") {
    let t = line.to_owned().trim(chars=" \t").to_owned()
    if t.has_prefix("///") {
      lines.push(t[3:].to_owned().trim(chars=" ").to_owned())
    }
  }
  if lines.is_empty() {
    None
  } else {
    Some(lines.join("\n"))
  }
}

///|
/// The value of one option, if it is written.
pub fn Member::option(self : Member, name : String) -> Ex? {
  for o in self.options {
    let (n, v) = o
    if n == name {
      return v
    }
  }
  None
}

///|
/// Whether a bare option is written.
pub fn Member::has_option(self : Member, name : String) -> Bool {
  for o in self.options {
    let (n, _) = o
    if n == name {
      return true
    }
  }
  false
}

///|
/// The groups of the block under a member, or nothing.
pub fn Member::block(self : Member) -> Array[@ast.Node] {
  self.stmts
}

///|
/// The doc comment for a member, which may be sitting on the member before it.
///
/// Shrubbery attaches the whitespace and comments BETWEEN two groups to the
/// first one's suffix. A doc comment is written above what it documents, so the
/// `///` lines at the end of one member's suffix are the next member's doc —
/// and a member that reads only its own prefix finds nothing unless it happens
/// to be first in its block.
///
/// Its own prefix wins when it has one, so nothing here can override a doc the
/// member really does carry.
pub fn member_doc(group : @ast.Node, prev : @ast.Node?) -> String? {
  match doc_of(group) {
    Some(d) => Some(d)
    None =>
      match prev {
        Some(p) => trailing_doc(p)
        None => None
      }
  }
}

///|
/// The `///` lines at the END of a node's suffix — the ones written under it
/// and therefore above whatever comes next.
///
/// Only a RUN that reaches the end counts. A `///` followed by a blank line and
/// then more text documents nothing that follows it, and taking it would put
/// one member's trailing note on the next member's declaration.
fn trailing_doc(node : @ast.Node) -> String? {
  let lines : Array[String] = []
  for line in node.meta.suffix.to_text().split("\n") {
    let t = line.to_owned().trim(chars=" \t").to_owned()
    if t.has_prefix("///") {
      lines.push(t[3:].to_owned().trim(chars=" ").to_owned())
    } else if t != "" {
      lines.clear()
    }
  }
  if lines.is_empty() {
    None
  } else {
    Some(lines.join("\n"))
  }
}

///|
/// The groups inside a declaration's block.
pub fn body_groups(decl : @tutufile.Decl) -> Array[@ast.Node] {
  match decl.body {
    Some(node) =>
      match node.it {
        Block(gs) => gs
        _ => []
      }
    None => []
  }
}
