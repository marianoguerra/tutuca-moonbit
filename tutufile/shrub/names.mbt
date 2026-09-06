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
