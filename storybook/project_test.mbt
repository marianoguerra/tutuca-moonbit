// The projection is pure data: it copies names, args and views out of a
// module's examples and never looks a component up. So these tests declare
// modules with no components at all.

///|
fn mod_(
  name : String,
  examples : Array[@component.ExampleDef],
) -> @component.ModuleDef {
  @component.ModuleDef::new(name~, components=[], examples~)
}

///|
fn ex_(component : String, title : String) -> @component.ExampleDef {
  { component, title, args: Map([]), view: None, }
}

///|
test "slug lowercases, collapses and trims" {
  assert_eq(slug("Basic Counter"), "basic-counter")
  assert_eq(slug("Lists & Data"), "lists-data")
  assert_eq(slug("  spaced  out  "), "spaced-out")
  assert_eq(slug("Todo/List (v2)"), "todo-list-v2")
  assert_eq(slug("!!!"), "")
}

///|
test "a story per declared example, in declaration order" {
  let m = mod_("counter", [
    ex_("Counter", "Basic"),
    ex_("Counter", "Negative start"),
  ])
  let stories = stories_of_module(m, section="Basics")
  assert_eq(stories.length(), 2)
  assert_eq(stories[0].id, "counter-counter-basic")
  assert_eq(stories[0].title, "Counter · Basic")
  assert_eq(stories[0].root, "Counter")
  assert_eq(stories[0].section, "Basics")
  // the safe defaults: render it, don't dispatch anything at it
  assert_true(stories[0].renderable)
  assert_false(stories[0].init)
  assert_eq(stories[1].id, "counter-counter-negative-start")
}

///|
test "an untitled example is titled by its component" {
  let stories = stories_of_module(mod_("hello", [ex_("Hello", "")]))
  assert_eq(stories[0].id, "hello-hello")
  assert_eq(stories[0].title, "Hello")
}

///|
test "args and view come from the example" {
  let m = mod_("todo", [
    {
      component: "Todo",
      title: "Editing",
      args: { "count": Num(3) },
      view: Some("edit"),
    },
  ])
  let s = stories_of_module(m)[0]
  assert_eq(s.args.get("count"), Some(@tutuca.Value::Num(3)))
  assert_eq(s.view, "edit")
}

///|
test "colliding ids are suffixed, never merged" {
  // same component, same title, twice: distinct stories need distinct ids,
  // because an id is a DOM id and a URL value
  let m = mod_("dup", [ex_("A", "One"), ex_("A", "One"), ex_("A", "One")])
  let ids = stories_of_module(m).map(s => s.id)
  assert_eq(ids, ["dup-a-one", "dup-a-one-2", "dup-a-one-3"])
}

///|
test "several modules at once, sectioned by module" {
  let a = mod_("counter", [ex_("Counter", "")])
  let b = mod_("todo", [ex_("Todo", ""), ex_("Todo", "Filtered")])
  let stories = stories_of_modules([a, b], section_of=m => {
    match m.name {
      "counter" => "Basics"
      _ => "Data"
    }
  })
  assert_eq(stories.map(s => s.id), [
    "counter-counter", "todo-todo", "todo-todo-filtered",
  ])
  assert_eq(stories.map(s => s.section), ["Basics", "Data", "Data"])
  // and grouping them puts the named order first
  let sections = sections_of(stories, order=["Data", "Basics"])
  assert_eq(sections.map(s => s.title), ["Data", "Basics"])
}

///|
test "a module with no examples projects to no stories" {
  assert_eq(stories_of_module(mod_("empty", [])).length(), 0)
}

///|
test "an unlisted section is kept, appended after the ordered ones" {
  let stories = [
    Story::new(
      id="a",
      title="A",
      module_=mod_("m", []),
      root="A",
      section="Zed",
    ),
    Story::new(
      id="b",
      title="B",
      module_=mod_("m", []),
      root="B",
      section="Basics",
    ),
  ]
  let sections = sections_of(stories, order=["Basics"])
  assert_eq(sections.map(s => s.title), ["Basics", "Zed"])
}
