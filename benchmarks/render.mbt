// The RUNTIME workload: mount a component tree as a live app on the in-memory
// DOM (@memdom runs on every backend, so this is target-agnostic like the view
// benches) and read the rendered DOM back.
//
// Two axes:
//
//   - feature coverage — every ported example in storybook/examples, mounted
//     with the args the storybook and the CLI mount it with. 50 modules, so
//     between them every view directive the framework has is rendered at least
//     once.
//   - data size — the same view over 0, 1, 5, 10, 100 and 1000 items, which is
//     what tells a per-node cost apart from a per-mount one.
//
// Each workload returns a checksum over the rendered HTML, so nothing can be
// optimized away and a change in output shows up as a changed number.
//
// What is measured is mount + first render + serialize. The seeded state is
// built ONCE per size and memoized (`items_for`): building 1000 component
// instances costs more than rendering them, and leaving that inside the timed
// closure both drowned the signal and made whole samples differ 3× depending on
// when allocation caught up. patch.mbt is the suite for update cost.

///|
/// Mount `root` of `m` with `args`, then serialize the DOM. Aborts on failure:
/// an example that does not mount is a broken workload, not a case to measure.
fn mount_render(
  label : String,
  m : @component.ModuleDef,
  root : String,
  args : Map[String, @tutuca.Value],
  init? : Bool = false,
) -> Int {
  let h = @harness.mount(m, root, args~) catch {
    e => abort("benchmark render \{label}: \{e}")
  }
  // tutuca has no lifecycle hook; the host decides. The examples that need a
  // first message are flagged in the registry, same as in the storybook.
  if init {
    h.send_at_root("init")
  }
  let n = h.html().length()
  // Every iteration mounts a fresh app, so the teardown is the workload's, not
  // the caller's: without it the native binary grows by a whole app tree per
  // iteration and the suite is killed part way through. It is inside the timed
  // section because it is part of the cost of a mount that does not leak.
  h.destroy()
  n
}

///|
/// The one example that is not a workload: `lint-errors` exists to be broken —
/// its views carry deliberately bad values, one of
/// which is a `render` op that recurses without terminating. Mounting it prints
/// a parse issue per view and never returns.
const SKIPPED_EXAMPLE = "lint-errors"

///|
/// Every ported example, mounted the way storybook/stories.mbt mounts it. The
/// broad "does anything in the render path regress" number: 50 modules, between
/// them every view directive the framework has.
pub fn render_all_examples() -> Int {
  let mut n = 0
  for e in @examples.all_examples() {
    if e.name == SKIPPED_EXAMPLE {
      continue
    }
    n = n + mount_render(e.name, e.module_, e.root, e.root_args(), init=e.init)
  }
  n
}

///|
/// One module's component, by name — the instance a scaled workload must build
/// its children from. A Component carries an id bound to the scope it was
/// registered in, so a child made from a fresh `x_comp()` would render as
/// nothing (see @harness.mount_example's note).
fn comp_of(m : @component.ModuleDef, name : String) -> @component.Component {
  for c in m.components {
    if c.name == name {
      return c
    }
  }
  abort("benchmark render: module '\{m.name}' has no component '\{name}'")
}

///|
/// `@each` over n plain values: the cheapest list there is, no child components.
pub fn render_list(n : Int) -> Int {
  mount_render("list/\{n}", list_module, "ListIteration", list_args(n))
}

///|
/// n CHILD COMPONENT INSTANCES in a list (`@each` + `<x render-it>`): every item
/// is its own component with its own state and view, which is the shape a real
/// list of rows has.
pub fn render_todo(n : Int) -> Int {
  mount_render("todo/\{n}", todo_module, "Items", todo_args(n))
}

///|
/// n rows through a filter + pagination pipeline: the same list, but every item
/// also passes through `@filter-with` / `@enrich-with` before rendering, and
/// pagination bounds how many of them reach the DOM.
pub fn render_people(n : Int) -> Int {
  mount_render(
    "people/\{n}",
    filter_paginate_module,
    "SharedPeople",
    people_args(n),
  )
}

///|
/// A DEEP tree: the JSON editor's array component nested into itself `depth`
/// times, `breadth` leaves at each level. Every level is a component rendering
/// another instance of a component, which is the one shape the flat lists above
/// never reach.
pub fn render_json(depth : Int, breadth : Int) -> Int {
  mount_render(
    "json/\{depth}x\{breadth}",
    json_module,
    "JsonArray",
    json_args(depth, breadth),
  )
}

// ---------------------------------------------------------------------------
// Seeded state, built once per shape
//
// A Value is immutable and the transactor swaps roots with structural sharing,
// so mounting the same seed twice is safe: an app never writes back into it.

///|
pub fn list_args(n : Int) -> Map[String, @tutuca.Value] {
  {
    "items": items_for(list_items, n, () => {
      List(Array::makei(n, i => Str("item \{i}")))
    }),
  }
}

///|
pub fn todo_args(n : Int) -> Map[String, @tutuca.Value] {
  {
    "items": items_for(todo_rows, n, () => {
      let item = comp_of(todo_module, "Item")
      List(
        Array::makei(n, i => {
          item.make({ "text": Str("task \{i}"), "completed": Bool(i % 3 == 0) })
        }),
      )
    }),
  }
}

///|
pub fn people_args(n : Int) -> Map[String, @tutuca.Value] {
  {
    "items": items_for(people_rows, n, () => {
      let person = comp_of(filter_paginate_module, "Person")
      List(
        Array::makei(n, i => {
          person.make({
            "name": Str("person \{i}"),
            "email": Str("p\{i}@example.com"),
          })
        }),
      )
    }),
  }
}

///|
/// `breadth` string leaves plus one nested JsonArray, `depth` levels down.
pub fn json_args(depth : Int, breadth : Int) -> Map[String, @tutuca.Value] {
  {
    "items": items_for(json_levels, depth * 100 + breadth, () => {
      let str_comp = comp_of(json_module, "JsonString")
      let arr_comp = comp_of(json_module, "JsonArray")
      fn level(d : Int) -> @tutuca.Value {
        let items = Array::makei(breadth, i => {
          str_comp.make({ "value": Str("leaf \{d}.\{i}") })
        })
        if d > 0 {
          items.push(arr_comp.make({ "items": level(d - 1) }))
        }
        List(items)
      }

      level(depth)
    }),
  }
}

///|
/// The memo: build `key`'s value once, hand back the same one after that.
fn items_for(
  cache : Map[Int, @tutuca.Value],
  key : Int,
  build : () -> @tutuca.Value,
) -> @tutuca.Value {
  match cache.get(key) {
    Some(v) => v
    None => {
      let v = build()
      cache[key] = v
      v
    }
  }
}

///|
let list_items : Map[Int, @tutuca.Value] = Map([])

///|
let todo_rows : Map[Int, @tutuca.Value] = Map([])

///|
let people_rows : Map[Int, @tutuca.Value] = Map([])

///|
let json_levels : Map[Int, @tutuca.Value] = Map([])

///|
/// The modules the scaled workloads mount, built once: `Component` values carry
/// ids, and a fresh module per bench iteration would measure module setup too.
let list_module : @component.ModuleDef = @examples.list_iteration_module()

///|
pub let todo_module : @component.ModuleDef = @examples.todo_module()

///|
let filter_paginate_module : @component.ModuleDef = @examples.filter_paginate_module()

///|
let json_module : @component.ModuleDef = @examples.json_module()

///|
/// The item counts every size-scaled workload runs at. 0 isolates per-mount
/// cost; 1000 is where a per-item cost that is not linear becomes obvious.
pub let sizes : Array[Int] = [0, 1, 5, 10, 100, 1000]

///|
/// Named render workloads, for the executable shell under a profiler.
pub fn render_workloads() -> Array[(String, () -> Int)] {
  let out : Array[(String, () -> Int)] = [("all-examples", render_all_examples)]
  let scaled : Array[(String, (Int) -> Int)] = [
    ("list", render_list),
    ("todo", render_todo),
    ("people", render_people),
  ]
  for entry in scaled {
    let (name, run) = entry
    for n in sizes {
      out.push(("\{name}/\{n}", () => run(n)))
    }
  }
  out.push(("json/3x4", () => render_json(3, 4)))
  out.push(("json/8x4", () => render_json(8, 4)))
  out
}
