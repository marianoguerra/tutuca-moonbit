# Pattern — a gallery of your own components

**Goal:** browse every component in a project, live, with its state and a
recording of what it did beside it.

**Shape:** declare examples on your modules, scaffold a page, project the
modules into stories.

## 1. Declare examples where the component lives

```moonbit nocheck
// nocheck: `todo_component` / `entry_component` are the reader's
pub fn todo_module() -> @component.ModuleDef {
  @component.ModuleDef::new(name="todo", components=[todo_component(), entry_component()], examples=[
    { component: "Todo", title: "Empty", args: Map([]), view: None },
    {
      component: "Todo",
      title: "Three items",
      // built HERE, inside the module that registers Entry — which is what
      // makes a child-component instance in `args` renderable
      args: { "items": List([entry_component().make({ "text": Str("write it down") })]) },
      view: None,
    },
  ])
}
```

## 2. Scaffold the page once

```sh
tutuca new-storybook my-gallery
```

## 3. Project the modules

In `page/main.mbt`:

```moonbit nocheck
// nocheck: the modules are the reader's
fn sections() -> Array[@sb.Section] {
  @sb.sections_of(
    @sb.stories_of_modules([todo_module(), counter_module()], section_of=m => match
      m.name {
        "todo" => "Data"
        _ => "Basics"
      }),
    order=["Basics", "Data"],
  )
}

pub fn mount() -> Unit {
  @sbw.mount(sections()) |> ignore
}
```

## 4. Build and look

```sh
node build.mjs && tutuca storybook dist
```

## Adding the next story

Add an `ExampleDef` to the module. Nothing else changes — not `sections()`, not
the page, not a list. The same example is also what a test mounts:

```moonbit nocheck
// nocheck: `todo_module` is the reader's
test "three items render" {
  let h = @harness.mount_example(todo_module(), "Three items")
  assert_eq(h.find_all(".entry").length(), 3)
}
```

Full reference: [../storybook.md](../storybook.md).
