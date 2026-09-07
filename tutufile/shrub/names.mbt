// Protocols, and the members a component binds to them.
//
// A protocol id is a WIRE NAME: `"tutuca.dev/universal/Container@1"` and the
// members under it are what a second host dispatches by, so nothing here
// touches their spelling. `Container::appendCell` stays `appendCell` however
// the rest of the file is written — the `@1` in the id is a promise that the
// names do not move, and a printer that applied a naming convention to them
// would break it silently.

///|
/// A qualified name — `Holder::hold` — if the terms start with one.
pub fn qualified(parts : Array[@ast.Node], from : Int) -> (String, Int)? {
  guard from + 2 < parts.length() else { return None }
  guard parts[from].it is Id(a) else { return None }
  // A protocol name is UpperCamel, which is what tells `Holder::hold` from
  // the `count :: Int` beside it: `::` is one operator in both places, and
  // the terms cannot say which is meant.
  guard is_upper(a) else { return None }
  guard parts[from + 1].it is Op("::") else { return None }
  guard parts[from + 2].it is Id(b) else { return None }
  Some((a + "::" + b, from + 3))
}

///|
/// A member name, qualified or not, and where it ends.
pub fn member_name(parts : Array[@ast.Node], from : Int) -> (String, Int)? {
  match qualified(parts, from) {
    Some(pair) => Some(pair)
    None => {
      guard from < parts.length() && parts[from].it is Id(n) else {
        return None
      }
      Some((n, from + 1))
    }
  }
}

///|
/// Whether a name is UpperCamel, which is what tells a protocol name from a
/// member's.
pub fn is_upper(name : String) -> Bool {
  guard name.length() > 0 else { return false }
  let c = name.get_char(0)
  c is Some(ch) && ch >= 'A' && ch <= 'Z'
}

///|
/// A collection operation, under the name every layer below the notation
/// knows it by.
///
/// The notation writes `it.xs.delete_at(i)` and the checker, the interpreter
/// and all three backends match on `deleteAt`. That is a WIRE name rather than
/// a leftover: it is the string a `SMethod` carries, `component/instance.mbt`
/// dispatches on it, and 272 call sites across the tree spell it. Only the
/// readers translate, and they translate here — one table, so a `view:` action
/// and a `logic:` statement cannot disagree about what an operation is called.
pub fn collection_op(name : String) -> String? {
  match name {
    "push" => Some("push")
    "insert_at" => Some("insertAt")
    "set_at" => Some("setAt")
    "delete_at" => Some("deleteAt")
    "add" => Some("add")
    "remove" => Some("remove")
    "toggle" => Some("toggle")
    // Emptying a list. It is the ONLY spelling for the operation — there is no
    // list literal to assign — so it is a method like the rest rather than an
    // alias of anything.
    "clear" => Some("clear")
    _ => None
  }
}

///|
/// The names a view uses as `~when:`, `~enrich_with:` or `~loop_with:`.
///
/// A `pred` has two shapes and the old notation told them apart by what it did
/// not write: a `@when` filter took no parameters and read `@value` / `@key`
/// out of the air, while `pred containsText(q)` declared one and was CALLED
/// with it. The new notation names the row on both, so the declaration cannot
/// say which it is — but the view can, because a row member is exactly one a
/// render-time option names.
///
/// Collected from the view section and handed to the logic printer, which is
/// the only reason `print_logic` takes it. Without it every parameterised
/// predicate had its first argument renamed to `@value` and its parameter list
/// dropped, so it read a row it was never given and lost the argument it was.
pub fn row_members(decls : Array[@tutufile.Decl]) -> Array[String] {
  let out = []
  fn walk(node : @ast.Node) -> Unit {
    match node.it {
      Group(parts) => {
        let mut i = 0
        while i < parts.length() {
          if parts[i].it is Kw(name) &&
            name is ("when" | "enrich_with" | "loop_with") &&
            i + 1 < parts.length() &&
            parts[i + 1].it is Block(bgs) &&
            bgs.length() == 1 &&
            bgs[0].it is Group(one) &&
            one.length() == 1 &&
            one[0].it is Id(who) {
            if !out.contains(who) {
              out.push(who)
            }
          }
          walk(parts[i])
          i = i + 1
        }
      }
      Parens(gs) | Brackets(gs) | Braces(gs) | Block(gs) | Multi(gs) =>
        for g in gs {
          walk(g)
        }
      Alts(gs) =>
        for g in gs {
          walk(g)
        }
      _ => ()
    }
  }

  for d in decls {
    walk(d.node)
  }
  out
}
