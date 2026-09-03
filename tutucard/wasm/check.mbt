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
  span : @tutuca.Span
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
  //
  // The index is built once and covers every component in the file, so a
  // `<x render>` or an `as="edit"` naming a SIBLING is checked against that
  // sibling's views rather than against nothing.
  let prog = @viewgen.ProgramIndex::of(file, name)
  for views in file.components {
    let comp = views.component_name(name)
    let block = script_for(file, comp)
    let decls : Array[@tscript.Decl] = match block {
      Some(b) =>
        @tscript.parse_script(b.text) catch {
          e =>
            raise BadCard(
              "line " +
              (b.line + line_of(b.text, e.span().start) - 1).to_string() +
              ": " +
              e.message(),
            )
        }
      None => []
    }
    // No schema: nothing to check against, and checking against a guess would
    // be the checker inventing a type. A card with no state block is legal and
    // its handlers are unchecked — the same trade a view file with no schema
    // makes.
    guard state_for(file, comp, name) is Some(def) else { continue }
    // The VIEWS, against that same schema — and the surface that says what
    // they SEND, which is what makes the block checkable against them.
    //
    // A card is the one caller that has both halves in one file and used to
    // check them apart: the block against a surface that said "I have no
    // views", the views against nothing at all. A finding here is listed like
    // any other rather than raised, because this is the reporting face and a
    // card with a wrong `.field` in a template still renders.
    let hints : Array[String] = []
    let surface = @viewgen.check_component_views(
      views.views,
      def,
      prog,
      macros=file.macros,
      comps=components,
      // A card is mounted by a host that dispatches a name into it, and
      // driven by scenes that send it one. Neither is in this file.
      open_senders=true,
      hints~,
    ) catch {
      e => {
        let (line, span) = locate_view(source, views, view=e.view())
        issues.push({ comp, code: e.code(), message: e.message(), line, span, })
        // What is no longer known is what the views send. `knows_views:
        // false` is how the checker is told that, and it is the difference
        // between "they send nothing" and "I could not look".
        {
          inputs: Map([]),
          knows_views: false,
          open_senders: true,
          comps: components,
        }
      }
    }
    // The spec block's rules, checked against the schema they are about. Their
    // spans are the SPEC block's, so they are located with that block rather
    // than with the script block below — which is why the checker keeps the two
    // entry points apart.
    for f in @check.check_rules(def) {
      let (line, span) : (Int, @tutuca.Span) = match file.state_block {
        Some(b) =>
          (
            b.line + line_of(b.text, f.span.start) - 1,
            { start: f.span.start + b.offset, end_: f.span.end_ + b.offset, },
          )
        None => locate_view(source, views, view=None)
      }
      issues.push({ comp, code: f.code, message: f.message, line, span, })
    }
    for h in hints {
      let (line, span) = locate_view(source, views, view=None)
      issues.push({ comp, code: "HINT", message: h, line, span, })
    }
    // A card with views and no block has been checked as far as it goes: there
    // is nothing to check the surface against.
    guard block is Some(b) else { continue }
    // The block's OWN declarations, and not the spec block's rules lifted
    // alongside them. `check` reads `def.rules` itself, so lifting them in
    // added nothing — and cost twice: every spec-block rule was reported as
    // `RULE_IN_BOTH` against itself, under a span belonging to a different
    // block, which the rebasing below then turned into a line number in this
    // one. `compile` passes the block's own decls here for the same reason;
    // the lifted list it builds is for the EMITTER, which does need the bodies.
    for f in @check.check(decls, def, surface~) {
      // The checker's warnings are listed here rather than dropped — this is
      // the reporting face, and a warning is worth showing. `compile.mbt` is
      // the one that decides what stops a build, and it skips them.
      issues.push({
        comp,
        code: f.code,
        message: f.message,
        line: b.line + line_of(b.text, f.span.start) - 1,
        span: { start: f.span.start + b.offset, end_: f.span.end_ + b.offset, },
      })
    }
  }
  { component: root, components, issues, }
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

///|
/// Where a view sits in the FILE, for a finding the VIEW checker raised.
///
/// Those findings have no span of their own: the checker walks a compiled
/// tree, and its nodes carry no offsets back into the source. The template the
/// finding names is the finest position available, so that is what gets
/// pointed at — its FIRST LINE rather than its whole body, because an editor
/// highlighting forty lines says "somewhere in here", which the message
/// already said better.
///
/// `None`, or a name no template answers to, falls back to the component's
/// first view; a body that is not found verbatim in the source falls back to
/// the top of the file, which is what every whole-card failure reports.
fn locate_view(
  source : String,
  views : @viewfile.ViewSet,
  view~ : String?,
) -> (Int, @tutuca.Span) {
  let mut body = ""
  if view is Some(want) {
    for v in views.views {
      if v.name == want {
        body = v.source
        break
      }
    }
  }
  if body.is_empty() && views.views.get(0) is Some(first) {
    body = first.source
  }
  if body.is_empty() {
    return (1, { start: 0, end_: 0, })
  }
  // The FIRST LINE of the body, not the body: `viewfile` dedents a template
  // when it lifts it (`split.mbt` `dedent`), so the body it carries is not a
  // substring of the file it came from. One line of it still is — dedenting
  // takes a COMMON prefix off every line, so what is left of the first one
  // appears verbatim, with the indentation sitting just before the match.
  let first_line = match body.find("\n") {
    Some(n) => body[0:n].to_owned()
    None => body
  }
  match source.find(first_line) {
    Some(i) => {
      // Counted over the prefix rather than by indexing into the whole file:
      // `find` answers in the string's own units and `line_of` walks
      // characters, and slicing here is what keeps the two from disagreeing.
      let prefix = source[0:i].to_owned()
      (
        line_of(prefix, prefix.length()),
        { start: i, end_: i + first_line.length(), },
      )
    }
    None => (1, { start: 0, end_: 0, })
  }
}
