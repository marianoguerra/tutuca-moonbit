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
  assert_true(
    h.texts(".comp-section") ==
    ["Fields", "Methods", "Update", "Alter", "Views"],
  )
  // Fields starts expanded (4 rows), name sections collapsed
  inspect(h.find_all(".comp-field").length(), content="4")
  inspect(h.find_all(".comp-name").length(), content="0")
  // plain click expands just Methods (mutate + compute names)
  h.click(".comp-section", nth=1)
  assert_true(h.texts(".comp-name").contains("label"))
  assert_true(h.texts(".comp-name").contains("double"))
  assert_true(h.texts(".comp-name").contains("inc"))
  assert_true(h.texts(".comp-name").contains("reset"))
  // ctrl-click a COLLAPSED section bubbles toggleAllSections(true):
  // every section opens
  h.fire(
    ".comp-section",
    @render.DomEvent::new(name="click", ctrl_or_cmd=true),
    nth=2,
  )
  let names = h.texts(".comp-name")
  assert_true(names.contains("update")) // the opaque Dispatch match, as a flag
  assert_true(names.contains("rows"))
  inspect(h.find_all(".comp-view").length(), content="2")
}

///|
test "component inspector: a view's raw source expands verbatim" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Component: Rich Sample (expanded)",
  )
  // deep-expanded example: sections open, view sources open too
  let views = h.texts(".comp-view")
  assert_true(views.length() == 2)
  assert_true(h.find_all("pre").length() == 2)
  assert_true(h.text("code").contains(".title"))
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
test "instance explorer: tabs switch between instance/component/lint" {
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
  h.click(".tab-lint")
  inspect(h.text(".lint-errors"), content="2 errors")
}

///|
test "lint report: tallies, auto-expanded error group, suggestion line" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Lint Report With Findings",
  )
  inspect(h.text(".lint-title"), content="broken module")
  inspect(h.text(".lint-errors"), content="2 errors")
  inspect(h.text(".lint-warnings"), content="2 warnings")
  inspect(h.text(".lint-hints"), content="1 hint")
  inspect(h.find_all(".lint-clean").length(), content="0")
  // the Broken group is auto-expanded (it has errors); Other stays collapsed
  assert_true(h.texts(".lint-component") == ["Broken", "Other"])
  inspect(h.find_all(".lint-finding").length(), content="4")
  let msgs = h.texts(".finding-message")
  assert_true(
    msgs.contains("Field '.nope' is not defined (in @text, on <span>)"),
  )
  assert_true(h.texts(".finding-suggestion").contains("$'{.title}' → .title"))
  // expanding Other reveals its finding too
  h.click(".lint-component", nth=1)
  inspect(h.find_all(".lint-finding").length(), content="5")
}

///|
test "lint report: a clean run shows the clean badge" {
  let h = @harness.mount_example(
    @inspector.inspector_module(),
    "Lint Report Clean",
  )
  inspect(h.text(".lint-clean"), content="✓ clean")
  inspect(h.find_all(".lint-component").length(), content="0")
}

///|
test "activity log: observe entries land newest-first via appendEntry" {
  let insp = @inspector.Inspector::new()
  let h = @harness.mount(insp.module_(), "ActivityLog")
  inspect(h.find_all(".empty-hint").length(), content="1")
  let record : @transactor.ObserveRecord = {
    kind: Input,
    name: "click",
    args: [],
    path: @tutuca.Path::new(),
    path_keys: [{ field: "value", key: None }],
    target_path: @tutuca.DispatchPath::new(),
    matched: Exact,
    before: Some(Num(1)),
    after: Some(Num(2)),
    seq: 1,
  }
  h.send_at_root("appendEntry", args=[insp.record_to_entry(record)])
  inspect(h.find_all(".empty-hint").length(), content="0")
  inspect(h.find_all(".activity-entry").length(), content="1")
  inspect(h.text(".entry-kind"), content="input")
  inspect(h.text(".entry-name"), content="click")
  inspect(h.text(".entry-matched"), content="exact")
  inspect(h.text(".entry-time"), content="#1")
  // before/after value inspectors rendered
  assert_true(h.texts(".json-number") == ["1", "2"])
  // a second entry prepends
  let second = insp.record_to_entry(
    { ..record, name: "keydown", seq: 2 },
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
