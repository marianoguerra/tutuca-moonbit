// The `spec:` section, read back from the text a generated module carries.
//
// `<comp>_spec_source` is the section as the file wrote it, and two readers
// want it back: `testing/fuzz`, which derives a component's generators from
// the rules the schema projects away, and the inspector's Spec tab, which
// shows what the file declared. Both used to call `parse_state` on a block of
// the old notation; the text is a `.tutu` fragment now, and this is the one
// place that says so.
//
// Here rather than in each of them because a second reading of "what is a
// spec section" is how two readings drift apart.

///|
/// The components a `spec:` fragment declares.
///
/// `name` is the fallback for a component the fragment never names, exactly as
/// `parse_state` takes it — a `.tutu` always names its components, so it only
/// reaches the shared half.
pub fn read_spec(
  source : String,
  name? : String = "",
) -> Array[StateDef] raise DefError {
  let sources = @report.Sources::new()
  let id = sources.add("spec.tutu", source)
  let file = @tutufile.read(source, id)
  if file.reports is [r, ..] {
    raise Syntax(msg=r.message, span={ start: 0, end_: 0, })
  }
  match file.section(Spec) {
    Some(block) => state_of_tutu(block.decls, name~)
    None => []
  }
}
