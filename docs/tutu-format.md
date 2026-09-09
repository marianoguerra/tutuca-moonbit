# The `.tutu` component format

A `.tutu` file holds component contracts, views, logic, fixtures and tests in
Shrubbery notation. The native generator and card compiler use the same readers.
The authoring reference is [the bundled skill](../skill/tutuca/core.md).

## Sections

| Section | Purpose |
| --- | --- |
| `spec:` | Component fields, messages, protocols and constraints |
| `view:` | Named component views and shared macros |
| `logic:` | Message handlers, computations and predicates |
| `fixtures:` | Named initial states |
| `tests:` | Scenes that drive and inspect a component |

Sections name the component they describe. A component's unqualified view is
`main`; `Counter.row:` defines its `row` view. The same file may contain several
components. A view can render a component declared in another file in the same
generation batch.

```tutu
spec:
  Counter:
    field count :: Int
    message add(Int)

view:
  Counter:
    div():
      button(~on_click: add(1)): "+"
      span(): it.count

logic:
  Counter:
    receive add(n):
      it.count := it.count + n
```

Use `name(...)` for elements, labeled arguments for attributes and directives,
and an indented block after `:` for children. Expressions such as `it.count`
read component state. An event directive such as `~on_click` dispatches its
expression when the event occurs. See [events](../skill/tutuca/events.md) and
[the language semantics](../skill/tutuca/semantics.md) for the complete vocabulary.

## Generate and validate

```sh
tutuca gen path/to/counter.tutu
moon check
moon test
```

Generation writes `<stem>_view_gen.mbt` and `<stem>_view_ir_gen.mbt` beside the
input. These contain the typed vocabulary and compiled views. Edit the `.tutu`
source and regenerate; never edit the generated modules.

Pass several files or a directory to build one component index. A directory
contributes `.tutu` files that already have generated siblings and stops at
nested MoonBit modules. Pass a new file explicitly for its first generation.
`--out` chooses a directory or, for one input, a filename. Output collisions
are errors with a suggested repair.

`tutuca watch [path...]` performs the same batch generation at startup and after
each settled batch of changes. Optional CSS output is rebuilt from all remaining
inputs. Removing an input leaves its generated files for explicit cleanup.

In this repository, `just gen` also formats generated code. `just dev
check-generated` regenerates in a temporary tree and checks for drift without
rewriting the working tree.

## Runtime and compiler boundaries

`tutufile` reads the source. Its view, logic and data readers produce the shapes
used by `anode`, `tscript` and state definitions. `viewfile` owns the resulting
component-file model. `viewgen` emits MoonBit; `tgc/emit` compiles dynamic cards.

Runtime markup constructed through `anode.View::new` remains supported. It is
a separate entry point for applications whose view source is available only
at runtime; ordinary `.tutu` components use compiled views.
