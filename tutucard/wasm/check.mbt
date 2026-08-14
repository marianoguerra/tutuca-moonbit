// Checking a card without compiling one.
//
// `compile` runs the checker before it builds a single instruction, so a card
// that does not check never reaches codegen. That makes `compile` a perfectly
// good validator and a wasteful one: a build step over a directory of cards, an
// agent validating what it just wrote, and the gate that keeps the starter
// cards loading all want the FINDINGS and none of them want a module.
//
// This is the front half of `compile`, stopping where the module would start.
// It is also what the card loader used to be for — a card was parsed and
// checked by `tutucard.load` on the way to being interpreted, and with the
// interpreter gone the checking half has to be reachable on its own.

///|
/// One thing wrong with a card, in the FILE's coordinates.
///
/// The same shape the loader reported, because it is the same finding: the
/// checker's code and message, rebased from the script block onto the file the
/// author has open.
pub(all) struct Issue {
  code : String
  message : String
  /// 1-based in the file.
  line : Int
  span : @tscript.Span
} derive(Debug, Eq)

///|
/// What a card is, and what is wrong with it.
///
/// `issues` being non-empty is the ORDINARY state of a card being edited, and
/// the reason this answers a list rather than raising: a card renders while the
/// things wrong with it are listed beside it, and refusing to show anything
/// until everything is right is what makes a live editor unusable.
///
/// `compile` is stricter — it turns a card with findings away whole — and that
/// is right for a card about to become a module a host will mount. It is wrong
/// for a card somebody is halfway through typing.
pub(all) struct Checked {
  component : String
  issues : Array[Issue]
} derive(Debug, Eq)

///|
/// Parse and check a card. Raises only for what leaves no card at all.
pub fn check_card(source : String, name~ : String) -> Checked raise GenError {
  let file = @viewfile.split_file(source, name~) catch {
    e => raise BadCard(e.message())
  }
  guard file.components.length() <= 1 else {
    raise BadCard(
      "a card is one component, but this file declares " +
      file.components.map(c => "`" + c.component_name(name) + "`").join(", "),
    )
  }
  guard file.components.get(0) is Some(views) else {
    raise BadCard(
      "a card needs at least one <template>: state and script describe a component, and a view is what makes one visible",
    )
  }
  let comp = views.component_name(name)
  let issues : Array[Issue] = []
  guard file.script_for(comp) is Some(b) else {
    return { component: comp, issues }
  }
  let decls = @tscript.parse_script(b.text) catch {
    e =>
      raise BadCard(
        "line " +
        (b.line + line_of(b.text, e.span().start) - 1).to_string() +
        ": " +
        e.message(),
      )
  }
  // No schema: nothing to check against, and checking against a guess would be
  // the checker inventing a type. A card with no state block is legal and its
  // handlers are unchecked — the same trade a view file with no schema makes.
  guard file.state.get(0) is Some(def) else {
    return { component: comp, issues }
  }
  for f in @check.check(decls, def) {
    issues.push({
      code: f.code,
      message: f.message,
      line: b.line + line_of(b.text, f.span.start) - 1,
      span: { start: f.span.start + b.offset, end_: f.span.end_ + b.offset },
    })
  }
  { component: comp, issues }
}
