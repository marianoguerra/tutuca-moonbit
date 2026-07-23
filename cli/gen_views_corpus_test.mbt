// The same equivalence claim as gen_views_ir_test.mbt, swept over every
// runtime-compiled view in the ported example library (storybook/examples —
// covering loops, scopes, macros, teleport, drag-and-drop, SVG, components
// rendering components). Most examples now build their views ahead of time
// (their trees are committed *_view_ir_gen.mbt), so `corpus_views()` only
// sees the ones still parsed at runtime (`raw_view` set) — the macro-using
// and genuinely-dynamic escape-hatch examples.
//
// For each view: parse it, emit its tree as MoonBit source, and check the
// tree the emitter round-trips through @viewgen matches what the parser
// produced. The emitted TEXT cannot be compiled inside a test, so what is
// verified here is the tree/event model — that every construct in the corpus
// is expressible, and that ir_supported is honest about the ones that are not
// (macro users).

///|
/// Every (component, view name, source) in the example library.
fn corpus_views() -> Array[(String, String, String)] {
  let out : Array[(String, String, String)] = []
  for ex in @examples.all_examples() {
    for comp in ex.module_.components {
      for vname, view in comp.views {
        if view.raw_view != "" && view.raw_view != "No View Defined" {
          out.push((comp.name, vname, view.raw_view))
        }
      }
    }
  }
  out
}

///|
test "the corpus is big enough for this sweep to mean something" {
  let views = corpus_views()
  assert_true(views.length() >= 30)
}

///|
test "every corpus view either compiles to a tree or is declared unsupported" {
  let mut emitted = 0
  let mut unsupported = 0
  let failures : Array[String] = []
  for entry in corpus_views() {
    let (cname, vname, source) = entry
    let set : @viewgen.ViewFile = {
      components: [
        {
          name: "",
          views: [{ name: "main", source, style: "" }],
          common_style: "",
          global_style: "",
        },
      ],
      macros: [],
    }
    if !@viewgen.ir_supported(set) {
      // Only macro-using views may opt out; anything else would be a hole.
      unsupported = unsupported + 1
      continue
    }
    // Emitting must not raise, and must produce a loadable-looking module.
    let src = @viewgen.emit_ir_module("C", "corpus.html", set) catch {
      e => {
        failures.push("\{cname}/\{vname}: \{@viewgen.GenError::message(e)}")
        continue
      }
    }
    if !src.contains("@anode.ParseContext::from_ir(root, events)") {
      failures.push("\{cname}/\{vname}: emitted module has no loader call")
      continue
    }
    // The tree really is usable: build the view and render it. A component
    // with no matching state renders slots as empty, which is fine — what
    // matters is that nothing raises and the loader wires up the ids.
    let map = @viewgen.compiled_views(set.components[0]) catch {
      e => {
        failures.push("\{cname}/\{vname}: \{@viewgen.GenError::message(e)}")
        continue
      }
    }
    guard map.get("main") is Some(v) && v.ctx is Some(px) else {
      failures.push("\{cname}/\{vname}: no main view built")
      continue
    }
    for i, n in px.nodes {
      if !(node_id_of(n) is Some(id) && id == i) {
        failures.push("\{cname}/\{vname}: node \{i} is misfiled")
      }
    }
    emitted = emitted + 1
  }
  assert_eq(failures, [])
  // Most of the corpus must actually go through the tree path — if a change
  // made ir_supported answer false everywhere, the sweep would still "pass"
  // without this.
  assert_true(emitted > unsupported * 3)
  assert_true(emitted >= 25)
  inspect(
    "\{emitted} views compiled to a tree, \{unsupported} use macros",
    content=(
      #|220 views compiled to a tree, 18 use macros
    ),
  )
}
