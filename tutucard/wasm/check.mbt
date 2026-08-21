// Checking a card without compiling one.
//
// `compile` runs the checker before it builds a single instruction, so a card
// that does not check never reaches codegen. That makes `compile` a perfectly
// good validator and a wasteful one: a build step over a directory of cards, an
// agent validating what it just wrote, and the gate that keeps the starter
// cards loading all want the FINDINGS and none of them want a module.
//
// This is the front half of `compile`, stopping where the module would start.

///|
/// One thing wrong with a card, in the FILE's coordinates.
///
/// The same shape the loader reported, because it is the same finding: the
/// checker's code and message, rebased from the script block onto the file the
/// author has open.
pub(all) struct Issue {
  /// Which component's block it was found in. Same reason a `Refusal` carries
  /// one: a file with two components can be wrong about `.count` twice.
  comp : String
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
  /// The ROOT — the component a host mounts when it is told no other name.
  component : String
  /// Every component the file declares, in file order. `component` is the
  /// first of these.
  components : Array[String]
  issues : Array[Issue]
} derive(Debug, Eq)

///|
/// Parse and check a card. Raises only for what leaves no card at all.
pub fn check_card(source : String, name~ : String) -> Checked raise GenError {
  let file = @viewfile.split_file(source, name~) catch {
    e => raise BadCard(e.message())
  }
  guard file.components.get(0) is Some(root_views) else {
    raise BadCard(
      "a card needs at least one <template>: state and script describe a component, and a view is what makes one visible",
    )
  }
  // The root: what a `data-root` marker names, or the first component in the
  // file. `components[0]` stays what it always was — a file-level `<style>`
  // belongs to it — so the marker moves which component a HOST mounts and
  // nothing else.
  let components = file.components.map(v => v.component_name(name))
  let root = if file.root != "" && components.contains(file.root) {
    file.root
  } else {
    root_views.component_name(name)
  }
  let issues : Array[Issue] = []
  // Every component the file declares, checked against its OWN schema and its
  // own block. One iteration for a card that declares one, which is every card
  // that has ever compiled — the loop is here so that lifting the guard above
  // is a deletion rather than a rewrite.
  for views in file.components {
    let comp = views.component_name(name)
    guard script_for(file, comp) is Some(b) else { continue }
    let decls = @tscript.parse_script(b.text) catch {
      e =>
        raise BadCard(
          "line " +
          (b.line + line_of(b.text, e.span().start) - 1).to_string() +
          ": " +
          e.message(),
        )
    }
    // No schema: nothing to check against, and checking against a guess would
    // be the checker inventing a type. A card with no state block is legal and
    // its handlers are unchecked — the same trade a view file with no schema
    // makes.
    guard state_for(file, comp, name) is Some(def) else { continue }
    for
      f in @check.check(decls, def, surface={
        inputs: Map([]),
        knows_views: false,
        comps: components,
      }) {
      // The checker's warnings are listed here rather than dropped — this is
      // the reporting face, and a warning is worth showing. `compile.mbt` is
      // the one that decides what stops a build, and it skips them.
      issues.push({
        comp,
        code: f.code,
        message: f.message,
        line: b.line + line_of(b.text, f.span.start) - 1,
        span: { start: f.span.start + b.offset, end_: f.span.end_ + b.offset },
      })
    }
  }
  { component: root, components, issues }
}

///|
/// The script block for one component, WITHOUT the bare-block fallback when
/// the file declares several.
///
/// `ViewFile::script_for` answers a lone unqualified block for any name it is
/// asked about, which is exactly right for a file with one component and wrong
/// for a file with four: all four would compile the same handlers. So the
/// fallback is taken only when there is nothing for it to be ambiguous with.
fn script_for(file : @viewfile.ViewFile, comp : String) -> @viewfile.Block? {
  if file.components.length() <= 1 {
    return file.script_for(comp)
  }
  for sb in file.scripts {
    if sb.comp == comp {
      return Some(sb.block)
    }
  }
  None
}

///|
/// The `<script type="tutuca/wax">` block for one component, under the same
/// rule — and it matters more here: a bare escape block spliced once per
/// component is the same Wax function defined N times, which Wax rejects as a
/// duplicate and this backend reports as `BadModule`, the error whose message
/// says "this is a cardwasm bug".
fn wax_for(file : @viewfile.ViewFile, comp : String) -> @viewfile.Block? {
  if file.components.length() <= 1 {
    return file.wax_for(comp)
  }
  for wb in file.wax {
    if wb.comp == comp {
      return Some(wb.block)
    }
  }
  None
}

///|
/// The schema for one component.
///
/// `file.state` is in the order the state block declares its `state`s, which is
/// not the order the templates appear in — so `state.get(0)` is the right
/// answer only when there is exactly one of each. Matched by name instead, the
/// way `viewgen/emit.mbt` has always done it.
fn state_for(
  file : @viewfile.ViewFile,
  comp : String,
  fallback : String,
) -> @statedef.StateDef? {
  for def in file.state {
    if def.component_name(fallback) == comp {
      return Some(def)
    }
  }
  // The names need not agree, and usually do not: a card writes
  // `state Counter { … }` and a bare `<template>`, so the schema says `Counter`
  // and the component is named from the fallback. With one component and one
  // schema there is nothing for that to be ambiguous WITH, so the lone schema
  // is this component's — which is what `file.state.get(0)` meant before there
  // could be two of them.
  if file.components.length() <= 1 && file.state.length() == 1 {
    return file.state.get(0)
  }
  None
}
