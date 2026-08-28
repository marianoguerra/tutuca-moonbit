// Interaction tests: mount the inspector module's examples on the in-memory
// DOM and drive the collapse/expand toggles, pagination, tabs, and the
// activity log through real dispatched events.

///|
test "data inspector: an expanded array shows every leaf, collapse hides them" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Small Array (expanded)",
  )
  inspect(h.text(".json-array"), content="Array")
  assert_true(h.texts(".json-number") == ["1"])
  assert_true(h.texts(".json-string") == ["\"two\""])
  inspect(h.text(".json-boolean"), content="true")
  inspect(h.find_all(".json-null").length(), content="1")
  // rows are keyed by index
  inspect(h.find_all(".json-property").length(), content="4")
  // the header button collapses the composite (@show removes the children)
  h.click(".json-array")
  inspect(h.find_all(".json-property").length(), content="0")
  h.click(".json-array")
  inspect(h.find_all(".json-property").length(), content="4")
}

///|
test "data inspector: pagination pages 25 items by 10" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Paginated Array (25 items, expanded)",
  )
  inspect(h.find_all(".json-number").length(), content="10")
  inspect(h.text(".pg-label"), content="1 / 3")
  inspect(h.text(".json-number"), content="1")
  h.click(".pg-next")
  inspect(h.text(".pg-label"), content="2 / 3")
  inspect(h.text(".json-number"), content="11")
  h.click(".pg-next")
  inspect(h.text(".pg-label"), content="3 / 3")
  inspect(h.find_all(".json-number").length(), content="5")
  h.click(".pg-prev")
  inspect(h.text(".pg-label"), content="2 / 3")
}

///|
test "data inspector: nested objects expand independently" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "API Response Shape (expanded)",
  )
  // top level expanded: profile is a nested Object, still collapsed
  inspect(h.texts(".json-object").length(), content="2") // root + profile (meta hidden)
  h.click(".json-object", nth=1) // expand profile
  inspect(h.texts(".json-object").length(), content="3") // meta now visible
  inspect(
    h.texts(".json-string").contains("\"alice@example.com\""),
    content="true",
  )
}

///|
test "schema viewer: boolean schema + raw toggle" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Schema: Boolean False",
  )
  inspect(h.text(".schema-boolean"), content="no value allowed (false)")
  inspect(h.text(".raw-toggle"), content="raw schema")
  h.click(".raw-toggle")
  inspect(h.text(".raw-toggle"), content="high-level view")
  // the raw view renders the plain value through the data inspector
  inspect(h.text(".json-boolean"), content="false")
  inspect(h.find_all(".schema-boolean").length(), content="0")
}

///|
test "schema viewer: kitchen sink renders properties, badges and markers" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Schema: Kitchen Sink (expanded)",
  )
  inspect(h.text(".schema-object"), content="object")
  let keys = h.texts(".schema-key")
  assert_true(keys.contains("id"))
  assert_true(keys.contains("email"))
  assert_true(keys.contains("contact"))
  // constraint badges are human-readable
  let text = h.text(".schema-viewer")
  assert_true(text.contains("format: email"))
  assert_true(text.contains("no additional properties"))
  assert_true(text.contains("read-only"))
  // enum / const / combinator nodes appear
  inspect(h.find_all(".schema-enum").length(), content="1")
  inspect(h.find_all(".schema-const").length(), content="1")
  inspect(h.text(".schema-combinator"), content="any of")
  // array of string inlines the item type
  assert_true(h.texts(".schema-array").contains("array of string"))
}

///|
test "schema viewer: conditional renders if/then/else regions" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Schema: Conditional",
  )
  let text = h.text(".schema-conditional")
  assert_true(text.contains("conditional"))
  assert_true(text.contains("if"))
  assert_true(text.contains("then"))
  assert_true(text.contains("else"))
}

///|
test "component inspector: sections toggle one by one and all at once" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Component: Rich Sample",
  )
  inspect(h.text(".comp-title"), content="RichSample")
  // Receive and Intent appear only because the component is DESCRIBED: those
  // names are raised from MoonBit, never written in a view, so nothing at
  // runtime can recover them.
  //
  // One section per non-empty group: the view hides a section with no rows, so
  // a bucket this component does not use is absent rather than empty.
  @debug.assert_eq(h.texts(".comp-section"), [
    "Fields", "Methods", "View handlers", "Receive", "Intent", "Alter", "Views",
  ])
  // Fields starts expanded (4 rows), name sections collapsed
  inspect(h.find_all(".comp-field").length(), content="4")
  inspect(h.find_all(".comp-name").length(), content="0")
  // plain click expands just Methods (the compute names). `inc`/`reset` are
  // update arms, not methods — they answer a dispatch, not a field read, and
  // they show under "Update" now that the schema names them.
  h.click(".comp-section", nth=1)
  assert_true(h.texts(".comp-name").contains("label"))
  assert_true(h.texts(".comp-name").contains("double"))
  assert_false(h.texts(".comp-name").contains("inc"))
  assert_false(h.texts(".comp-name").contains("reset"))
  // ctrl-click a COLLAPSED section bubbles toggleAllSections(true):
  // every section opens
  h.fire(
    ".comp-section",
    @render.DomEvent::new(name="click", ctrl_or_cmd=true),
    nth=2,
  )
  let names = h.texts(".comp-name")
  // "update" as a bare flag is gone: the Update panel lists the names the
  // match actually answers, which is the whole point of describing it.
  assert_false(names.contains("update"))
  assert_true(names.contains("inc"))
  assert_true(names.contains("reset"))
  assert_true(names.contains("ping")) // Receive
  assert_true(names.contains("onChild")) // Bubble
  assert_true(names.contains("onData")) // Response
  assert_true(names.contains("rows")) // Alter, still reflected
  inspect(h.find_all(".comp-view").length(), content="2")
}

///|
/// A view compiled ahead of time carries no source: `View::from_ir` has a tree
/// and an event table, and the template it came from stays in the .html file
/// rather than being shipped in the binary to be printed. The panel says so
/// instead of expanding an empty block. A view PARSED at run time (a dyncomp
/// guest, the playground) still has its source and still shows it.
test "component inspector: an AOT view expands to a note, not empty source" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Component: Rich Sample (expanded)",
  )
  // deep-expanded example: sections open, view rows open too
  let views = h.texts(".comp-view")
  assert_true(views.length() == 2)
  assert_true(h.find_all("pre").length() == 0)
  assert_eq(h.find_all(".comp-view-aot").length(), 2)
}

///|
test "instance inspector: field rows render name : value" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Instance Inspector (expanded)",
  )
  inspect(h.text(".instance-fields"), content="SampleCard")
  let keys = h.texts(".json-property")
  inspect(keys.length(), content="4")
  assert_true(keys.contains("title : \"Hello\""))
  assert_true(keys.contains("count : 3"))
  assert_true(keys.contains("open : true"))
}

///|
test "instance explorer: tabs switch between instance and component" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Instance Explorer",
  )
  // instance tab active by default
  inspect(
    h.attr("a", "class").unwrap_or(""),
    content="tab tab-active tab-instance",
  )
  inspect(h.find_all(".instance-fields").length(), content="1")
  // @show/@hide REMOVE the node: the other tabs' bodies are not rendered
  inspect(h.find_all(".component-inspector").length(), content="0")
  h.click(".tab-component")
  inspect(
    h.attr(".tab-component", "class").unwrap_or(""),
    content="tab tab-active tab-component",
  )
  inspect(h.text(".comp-title"), content="SampleCard")
  // there is no third tab: lint is a compile-time concern, not a panel
  inspect(h.find_all(".tab-lint").length(), content="0")
}

///|
test "activity log: observe entries land newest-first via appendEntry" {
  let insp = @inspector.Inspector::new()
  let h = @harness.mount(insp.module_(), "ActivityLog")
  inspect(h.find_all(".empty-hint").length(), content="1")
  let record : @transactor.ObserveRecord = {
    kind: Receive,
    name: "click",
    args: [],
    path: @tutuca.Path::new(),
    path_keys: [{ field: "value", key: None, }],
    target_path: @tutuca.DispatchPath::new(),
    matched: Exact,
    before: Some(Num(1)),
    after: Some(Num(2)),
    seq: 1,
    walk: 0,
    parent_seq: 0,
  }
  h.send_at_root("appendEntry", args=[insp.record_to_entry(record)])
  inspect(h.find_all(".empty-hint").length(), content="0")
  inspect(h.find_all(".activity-entry").length(), content="1")
  inspect(
    h.text(".entry-kind"),
    content=(
      #|receive
    ),
  )
  inspect(h.text(".entry-name"), content="click")
  inspect(h.text(".entry-matched"), content="exact")
  inspect(h.text(".entry-time"), content="#1")
  // before/after value inspectors rendered
  assert_true(h.texts(".json-number") == ["1", "2"])
  // a second entry prepends
  let second = insp.record_to_entry(
    { ..record, name: "keydown", seq: 2, },
    time="#2",
  )
  h.send_at_root("appendEntry", args=[second])
  assert_true(h.texts(".entry-name") == ["keydown", "click"])
}

///|
test "activity entry example renders the dispatch chrome" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Activity Entry",
  )
  inspect(h.text(".entry-kind"), content="input")
  inspect(h.text(".entry-name"), content="click")
  inspect(h.text(".entry-path"), content="value.rows[1]")
  let text = h.text(".activity-entry")
  assert_true(text.contains("before"))
  assert_true(text.contains("after"))
}

///|
test "every example mounts and renders" {
  let module_ = @inspector.inspector_module()
  for e in module_.examples {
    let h = @harness.mount_example(@inspector.inspector_module(), e.title)
    assert_true(h.html().length() > 0)
  }
  ignore(module_)
}

///|
/// Drive the generated form through the real DOM: type into the text control,
/// tick the checkbox, and read the edited instance back.
///
/// The chain under test is the whole feature — the row's control came from the
/// declared kind, the edit bubbled with the field NAME, and the write went
/// through the per-field mutator resolved by name off the instance. No part of
/// it knows what component this is.
test "state editor: editing a control rewrites the instance" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "State Editor (schema-driven)",
  )
  // one row per declared field, and the component names itself
  inspect(h.text(".editor-name"), content="SampleCard")
  inspect(h.find_all(".state-editor-row").length(), content="4")
  debug_inspect(
    h.texts(".row-name"),
    content=(
      #|["title", "count", "tags", "open"]
    ),
  )
  // the control per kind: text, number, read-only text, checkbox
  inspect(h.value_of(".row-text"), content="Hello")
  inspect(h.value_of(".row-num"), content="3")
  assert_true(h.checked_of(".row-bool"))
  // ...and a list has no control at all, only its rendering
  inspect(
    h.text(".row-readonly"),
    content=(
      #|["a","b"]
    ),
  )
  // edit the text field: the row bubbles, the editor calls `setTitle`
  h.type_into(".row-text", "Edited")
  inspect(h.value_of(".row-text"), content="Edited")
  // the instance itself changed, not just the control
  let target = h.drive_value().field("target")
  assert_true(target.field("title") is Str("Edited"))
  // a checkbox writes a Bool through `setOpen`
  h.check(".row-bool", false)
  assert_true(h.drive_value().field("target").field("open") is Bool(false))
  // and the untouched fields came along unchanged
  assert_true(h.drive_value().field("target").field("count") is Num(3.0))
}

///|
/// The declaration, read back out of the component that was built from it.
///
/// A block is FILE-level, so RichSample's carries SampleCard's arm too — both
/// show, and the one the panel was opened for is the one that starts open.
test "spec viewer: the block's arms, the story's own expanded" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Spec: Rich Sample",
  )
  // one section per arm; RichSample is expanded, so its own groups show
  // between it and the collapsed SampleCard below.
  @debug.assert_eq(h.texts(".comp-section"), [
    "RichSample", "Fields", "Receive", "Intent", "SampleCard",
  ])
  // Fields starts expanded: the section a reader opened this for.
  @debug.assert_eq(h.texts(".spec-field-name"), [
    "title", "count", "tags", "open",
  ])
  @debug.assert_eq(h.texts(".spec-field-type"), [
    "String", "Int", "Array[String]", "Bool",
  ])
  // messages are collapsed until asked for, and then carry the names a
  // dispatch is addressed to
  assert_eq(h.find_all(".spec-msg").length(), 0)
  h.click(".comp-section", nth=2)
  @debug.assert_eq(h.texts(".spec-msg-name"), ["ping", "onData"])
  // `gen-views` shipped this block without its prose, and the pane says so
  // rather than leaving a reader to wonder where the file's comments went.
  assert_eq(h.find_all(".spec-doc-block").length(), 0)
  assert_true(h.text(".spec-note").contains("without its doc comments"))
  // the other arm opens on its own
  h.click(".comp-section", nth=4)
  assert_true(h.texts(".comp-section").contains("Fields"))
}

///|
/// The half of a block that `gen-views` does not ship, over a block that
/// reached the runtime whole: the prose, the rules, and the named types.
///
/// The rules are the ones that matter. A rule reaches `SchemaInfo` as a bare
/// name, so the component inspector beside this can only say THAT one exists —
/// and a rule is the whole oracle the Fuzz tab holds a component to, so a
/// reader deciding whether a green run means anything has to see its words.
test "spec viewer: rules, named types and prose" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Spec: Rules and Types",
  )
  // one arm, expanded, with the groups the block fills
  @debug.assert_eq(h.texts(".comp-section"), [
    "Shipment", "Fields", "Receive", "Rules", "Types",
  ])
  // the block came in whole, so there is nothing missing to warn about
  assert_eq(h.find_all(".spec-note").length(), 0)
  // types are the author's spelling throughout — `Array[Parcel]`, not the
  // component-prefixed MoonBit type the generator would emit for it
  @debug.assert_eq(h.texts(".spec-field-type"), [
    "String", "Double", "Array[Parcel]", "Status",
  ])
  assert_true(
    h.text(".spec-doc-block").contains("two things that must stay true"),
  )
  // Rules start expanded beside Fields: the expression is carried verbatim,
  // and so is the sentence its author wrote for the moment it fails.
  @debug.assert_eq(h.texts(".rule-kind"), ["pred", "invariant"])
  @debug.assert_eq(h.texts(".spec-rule-name"), ["loadable", "addressed"])
  @debug.assert_eq(h.texts(".spec-rule-source"), [
    ".weightKg > 0", "not (.to is '')",
  ])
  // the sentence as SOURCE, quotes and all: a `format` may be a `$'…{expr}'`
  // template, and half-unquoting one would be a lie about what was written.
  @debug.assert_eq(h.texts(".spec-rule-format"), [
    "'weight must be above zero'", "'a booked shipment must name a destination'",
  ])
  // a message's payload, which the schema cannot carry either
  h.click(".comp-section", nth=2)
  @debug.assert_eq(h.texts(".spec-msg-name"), ["addParcel", "reweigh"])
  @debug.assert_eq(h.texts(".spec-msg-payload"), [
    "(String, Double)", "(Double)",
  ])
  // the named types, one nested section each
  h.click(".comp-section", nth=4)
  let labels = h.texts(".comp-section")
  assert_true(labels.contains("struct Parcel"))
  assert_true(labels.contains("enum Status"))
}

///|
/// The same block, verbatim — what the author edits, beside what the runtime
/// reads.
test "spec source: the block as written" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Spec source: Rich Sample",
  )
  let src = h.text(".spec-source-text")
  assert_true(src.contains("state RichSample {"))
  assert_true(src.contains("count : Int"))
  assert_true(src.contains("state SampleCard {"))
  assert_eq(h.find_all(".spec-source-hint").length(), 0)
}

///|
/// A component with nothing to show says so. Every hand-written component is
/// this case, and so is every component the Fuzz tab cannot generate for —
/// which is the same fact, said once.
test "spec viewer: no component resolved, no empty pane" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Spec: none declared",
  )
  assert_eq(h.find_all(".comp-section").length(), 0)
  assert_true(h.text(".spec-hint").contains("does not resolve"))
}
