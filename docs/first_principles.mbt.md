# tutuca from first principles

This document rebuilds tutuca layer by layer: each section introduces the
datatypes, traits and logic of one package and shows why the layer above
needs it. Read [`tutorial.mbt.md`](tutorial.mbt.md) first if you want to
*use* the framework; read this if you want to know why it is shaped the way
it is.

Every block tagged `mbt check` compiles and runs under `moon test docs`.
`@tutuca` is this repo's conventional alias for the `core` package
(`marianoguerra/tutuca/core`).

## 0. The shape of the problem

A UI framework answers two questions, forever, in a loop:

1. Given the current **state**, what is the **DOM**?
2. Given an **event** on that DOM, what is the **next state**?

tutuca commits to three design decisions up front, and every datatype below
exists to serve one of them:

- **State is one immutable value tree.** Handlers return a *new* tree that
  shares everything untouched (copy-on-write), so "did this subtree change?"
  is an identity check — which makes caching and diffing cheap.
- **Views are pure functions** from that value to a virtual DOM, written in
  an HTML-ish template language with a tiny expression syntax inside
  attribute values.
- **Events are not wired to DOM nodes.** They are delegated at the root and
  routed to a component by *path* — the sequence of steps from the root value
  to that component's node in the tree. Paths, not object references, are how
  components address each other.

The layers, bottom to top:

| Layer | Package | Key types |
|---|---|---|
| dynamic values | `core` | `Value`, `PathNode` |
| the value language | `core` | `Lit`, `Val`, `Stack`, `ParseCtx` |
| paths & dispatch | `core` | `Step`, `Path`, `DispatchPath`, `Handler`, `Ctx`, `Obj` |
| virtual DOM | `vdom` (+ `memdom`, `browser`, `wasm`) | `Vdom`, `AttrValue`, `DomNode` |
| templates | `anode` | `ANode`, `Attrs`, `ParseContext`, `Macro` |
| rendering | `render` | `RenderStack`, `RenderCtx`, `Meta` |
| components | `component` | `Component`, `FieldSpec`, `Instance`, `ModuleDef` |
| state settlement | `transactor` | `Transactor`, `Transaction` |
| the loop | `app` | `App[N]` |

## 1. `Value`: one type for all runtime data

Everything the framework computes with at runtime — field contents, handler
arguments, event payloads — is a `Value`, a dynamic JSON-like sum type:

```mbt nocheck
///|
pub(all) enum Value {
  Null
  Bool(Bool)
  Num(Double)
  Str(String)
  List(Array[Value])
  Map(Map[String, Value])
  Fn((Array[Value]) -> Value) // a handler in a value position
  Obj(&Obj) // a component instance — see section 6
}
```

Why dynamic and not generic? Because templates are *strings*: `.count` in a
view cannot be type-checked against a component's fields at compile time, so
the boundary between templates and state is dynamically typed by
construction. `Value` also carries JS semantics with it — truthiness and
display follow JavaScript, because views ported from the JS framework must
render identically:

```mbt check
///|
test "Value: JSON in, JS truthiness and display out" {
  let v = @tutuca.Value::from_json({ "title": "notes", "count": 3.0 })
  guard v is Map(m)
  // Value's Debug output is an R-prefixed parallel shape (RNum, RStr, …):
  // the Fn variant holds a function and cannot derive Debug, so it renders
  // as an opaque RFn (see core/value_debug.mbt)
  debug_inspect(m.get("count"), content="Some(RNum(3))")
  // JS truthiness: "" and 0 are falsy, "0" is truthy
  inspect(@tutuca.Value::Str("").is_truthy(), content="false")
  inspect(@tutuca.Value::Num(0).is_truthy(), content="false")
  inspect(@tutuca.Value::Str("0").is_truthy(), content="true")
  // JS display: `String(3)` is "3", not "3.0"; null renders as "null"
  inspect(@tutuca.Value::Num(3).to_display_string(), content="3")
  inspect(@tutuca.Value::Null.to_display_string(), content="null")
}
```

The two non-JSON variants are the seams where the upper layers plug in:
`Fn` lets a handler travel through value positions, and `Obj` lets a
*component instance* live inside the tree without `core` knowing what a
component is.

## 2. The value language: `Val`, `Stack`, `eval`

Attribute values in templates are a tiny expression language, one sigil per
resolution rule. Parsing produces a `Val` AST — one variant per syntactic
form:

```mbt nocheck
///|
pub(all) enum Val {
  Const(lit~ : Lit, from_macro~ : Bool) // 'text', 42, true
  StrTpl(Array[Val?]) // $'a {.b} c'
  Predicate(pred~ : Pred, args~ : Array[Val]) // truthy? .x / equals? .a .b
  Name(String) // bare lowercase: input handler / event arg
  HandlerName(name~ : String, ns~ : HandlerNamespace)
  TypeName(String) // bare Uppercase
  Bind(String) // @name
  BindMember(name~ : String, prop~ : String) // @name.member (one level)
  Dyn(String) // *name
  Field(String) // .name
  Method(String) // $name
  SeqAccess(seq~ : String, key~ : String) // .seq[.key]
}
```

The parse functions (`parse_token`, `parse_text`, `parse_field`, …) differ
only in which forms they allow per attribute role; a `ParseCtx` collects
issues (the linter reads them later) instead of failing:

```mbt check
///|
test "parsing: one sigil, one Val variant" {
  let px = @tutuca.ParseCtx::new()
  debug_inspect(
    @tutuca.parse_token(".count", px),
    content=(
      #|Some(Field("count"))
    ),
  )
  debug_inspect(
    @tutuca.parse_token("@key", px),
    content=(
      #|Some(Bind("key"))
    ),
  )
  // predicates are only legal in boolean slots (@show, @hide, @if, @when),
  // so they parse through parse_bool, not parse_text
  debug_inspect(
    @tutuca.parse_bool("truthy? .msg", px),
    content=(
      #|Some(Predicate(pred=IsTruthy, args=[Field("msg")]))
    ),
  )
  debug_inspect(
    @tutuca.parse_text("$'hi {.name}!'", px),
    content=(
      #|Some(
      #|  StrTpl(
      #|    [
      #|      Some(Const(lit=LStr("hi "), from_macro=false)),
      #|      Some(Field("name")),
      #|      Some(Const(lit=LStr("!"), from_macro=false)),
      #|    ],
      #|  ),
      #|)
    ),
  )
}
```

Evaluation is where the key abstraction appears. A `Val` never reads state
directly — it reads through the `Stack` trait, which has one lookup method
per sigil:

```mbt nocheck
///|
pub(open) trait Stack {
  fn lookup_name(Self, String) -> Value = _
  fn lookup_bind(Self, String) -> Value = _
  fn lookup_dynamic(Self, String) -> Value = _
  fn lookup_field_raw(Self, String) -> Value = _
  fn lookup_method(Self, String) -> Value = _
  fn lookup_type(Self, String) -> Value = _
  fn get_handler_for(Self, String, HandlerNamespace) -> Value = _
}
```

`Val::eval(&Stack) -> Value` is a direct dispatch: `Field(name)` calls
`lookup_field_raw`, `Bind(name)` calls `lookup_bind`, and so on (see
`core/value_eval.mbt`). Every default returns `Null` — a stack implements
only the lookups it can answer. That means *anything* can be a stack;
components come much later:

```mbt check
///|
/// A minimal Stack: fields come from a plain map. This is all `eval` needs.
struct FieldMap {
  fields : Map[String, @tutuca.Value]
}

///|
impl @tutuca.Stack for FieldMap with fn lookup_field_raw(self, name) {
  self.fields.get(name).unwrap_or(Null)
}

///|
test "eval: a Val reads state through the Stack trait" {
  let px = @tutuca.ParseCtx::new()
  let stack = FieldMap::{ fields: { "count": Num(3), "name": Str("ada") } }
  guard @tutuca.parse_token(".count", px) is Some(count)
  debug_inspect(
    count.eval(stack),
    content=(
      #|RNum(3)
    ),
  )
  guard @tutuca.parse_text("$'hi {.name}!'", px) is Some(tpl)
  debug_inspect(
    tpl.eval(stack),
    content=(
      #|RStr("hi ada!")
    ),
  )
  // a lookup the stack does not implement falls back to Null
  guard @tutuca.parse_token("@missing", px) is Some(bind)
  debug_inspect(
    bind.eval(stack),
    content=(
      #|RNull
    ),
  )
}
```

The real renderer's `RenderStack` (section 5) is just a richer
implementation of this same trait.

## 3. The virtual DOM: `Vdom` over the `DomNode` trait

Independently of all the above, tutuca needs to produce and update a DOM.
The `vdom` package defines the tree —

```mbt nocheck
///|
pub(all) enum Vdom {
  Text(String)
  Comment(String)
  Fragment(Array[Vdom])
  Node(VElem) // tag, attrs : Map[String, AttrValue], childs, key?, ns?
}
```

— and two operations: `to_dom` (build fresh) and `morph` (mutate an existing
DOM in place to match a new tree, reusing keyed nodes). Neither touches a
real browser API: they are written against the **`DomNode` trait** (~24
methods: create/insert/remove, attributes, properties). Three
implementations exist — `vdom/memdom` (in-memory, runs everywhere, the test
substrate), `vdom/browser` (the real DOM via mizchi/js, js target) and
`vdom/wasm` (FFI, wasm-gc target). Same algorithms, three backends:

```mbt check
///|
test "vdom: render then morph against the in-memory DOM" {
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let opts = @vdom.RenderOpts::new(doc)
  let prev = @vdom.render(
    @vdom.h("ul", childs=[
      @vdom.h("li", key="a", childs=[@vdom.text("one")]),
      @vdom.h("li", key="b", childs=[@vdom.text("two")]),
    ]),
    container,
    opts,
  )
  // re-render: same keys in a new order — morph moves nodes, no rebuild
  let _ = @vdom.render(
    @vdom.h("ul", childs=[
      @vdom.h("li", key="b", childs=[@vdom.text("two")]),
      @vdom.h("li", key="a", childs=[@vdom.text("one")]),
    ]),
    container,
    opts,
    prev~,
  )
  inspect(
    container.to_html(),
    content=(
      #|<div><ul><li>two</li><li>one</li></ul></div>
    ),
  )
}
```

Note what `Vdom` does **not** have: event handlers. That is a deliberate
hole — events are handled by a different mechanism entirely (section 8).

## 4. Templates: `ANode`

Writing `h(...)` calls by hand is not the goal; HTML-ish template strings
are. The `anode` package parses a view string into an `ANode` — an AST that
is *almost* HTML, plus the framework's directives as dedicated variants:

```mbt nocheck
///|
pub(all) enum ANode {
  Text(TextData)
  Comment(TextData)
  Dom(DomData) // tag + Attrs + childs
  Fragment(FragmentData)
  RenderText(RenderTextData) // @text / <x text=…>
  Render(RenderData) // <x render=…>
  RenderIt(RenderItData) // <x render-it> (inside a loop)
  Show(WrapData)
  Hide(WrapData) // @show / @hide wrap their node
  PushView(WrapData)
  Scope(WrapData)
  Slot(SlotData) // <x:slot> inside a macro
  Each(EachData) // @each + @when/@enrich-with/@loop-with
  MacroCall(MacroData) // <x:name>
  RenderOnce(RenderOnceData)
}
```

Attribute values inside it are the `Val`s of section 2 — this is where the
two languages meet. Parsing happens once per view (`ANode::parse` +
`ParseContext`), not per render; directives like `@show` are *hoisted*: the
parser wraps the DOM node in a `Show` node so the renderer never re-inspects
attributes:

```mbt check
///|
test "templates: directives become structure, events are hoisted out" {
  let px = @anode.ParseContext::new()
  guard @anode.ANode::parse(
      (
        #|<p class="msg" @show=".visible" @on.click="hello">hi</p>
      ),
      px,
    )
    is Some(node)
  // @show wrapped the <p> in a Show node with the parsed Val
  guard node is Show(wrap)
  debug_inspect(
    wrap.val,
    content=(
      #|Field("visible")
    ),
  )
  guard wrap.node is Dom(dom)
  inspect(dom.tag, content="p")
  // @on.click did NOT stay on the node as a listener: it was collected into
  // the ParseContext's event table, keyed by node id — the routing layer
  // (section 8) looks handlers up there.
  inspect(px.events.length(), content="1")
  inspect(px.events[0].handlers[0].name, content="click")
  debug_inspect(
    px.events[0].handlers[0].handler.handler,
    content=(
      #|HandlerName(name="hello", ns=Input)
    ),
  )
}
```

Macros (`Macro::{ defaults, raw_view }`) are handled here too: pure template
expansion at parse time, with `^param` substitution and `<x:slot>` grafting —
by the time rendering happens, macros are gone.

## 5. Rendering: `ANode` + `Stack` → `Vdom`

The `render` package walks an `ANode` with two inputs: a `RenderStack` (the
production implementation of section 2's `Stack` trait — current value `it`,
`@`-bindings, parent frame, current event) and a `RenderCtx` (view resolver
and caches). Output: the `Vdom` of section 3.

Nothing in this pipeline requires components — a plain `Map` value works as
state, which shows the layering honestly:

```mbt check
///|
test "render: template + value → vdom → HTML" {
  let px = @anode.ParseContext::new()
  guard @anode.ANode::parse(
      (
        #|<p>Hello <x text=".name"></x>!</p>
      ),
      px,
    )
    is Some(node)
  let stack = @render.RenderStack::new(Map({ "name": Str("world") }))
  guard @render.render(node, stack, @render.RenderCtx::new()) is Some(vdom)
  // realize it on the in-memory DOM
  let doc = @memdom.document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  let _ = @vdom.render(vdom, container, @vdom.RenderOpts::new(doc))
  inspect(
    container.to_html(),
    content=(
      #|<div><p>Hello world!</p></div>
    ),
  )
}
```

`RenderStack::lookup_field_raw` reads `.name` out of the current value —
exactly what our toy `FieldMap` did, plus frames, bindings and component
lookups. `@each` renders by entering a child stack frame per item;
`<x render>` swaps `it` to the child value and resolves its view.

The renderer leaves one more thing behind: **`Meta` comment markers**
(`Comp`/`Each`/`Scope`) embedded in the output as HTML comments. They look
inert, but they are the routing table for events — next section shows the
state side first.

## 6. Components: `Instance`, and the `Obj` escape hatch

A `Component` is a bag of compiled views plus handler buckets; `component()`
also derives typed fields (`FieldSpec` infers a kind from its default) and
*generates* the mutators (`setX`, `toggleX`, `pushInX`, …) as ordinary
methods. `Component::make(args)` produces an `Instance` — an immutable
`(component, fields)` pair where `set` returns a new instance:

```mbt check
///|
test "instances are copy-on-write values, visible through Obj" {
  let greeting = @component.component(
    name="Greeting",
    view=(
      #|<p @text=".name"></p>
    ),
    fields={ "name": @component.FieldSpec::of_default(Str("world")) },
  )
  let a = greeting.make(Map([]))
  let b = a.set("name", Str("reader"))
  debug_inspect(
    a.get("name"),
    content=(
      #|RStr("world")
    ),
  ) // the original is untouched
  debug_inspect(
    b.get("name"),
    content=(
      #|RStr("reader")
    ),
  )
  // to_value() wraps the instance as Value::Obj(&Obj): a component instance
  // IS a node in the value tree
  guard b.to_value() is Obj(o)
  debug_inspect(
    o.obj_field("name"),
    content=(
      #|Some(RStr("reader"))
    ),
  )
  inspect(o.component_id() is Some(_), content="true")
}
```

Here is the architectural knot: the state tree lives in `core` (`Value`),
but component instances are defined in `component`, which depends on `core`.
How can a `Value` *contain* an instance? Through the **`Obj` trait** —
`core` defines the protocol (`obj_field`, `obj_with_field`, `obj_handler`,
`obj_eq`, …) and `Value::Obj(&Obj)` stores any implementor. `Instance`
implements it, and so does `dyncomp`'s host object for WebAssembly guest
components — the value tree cannot tell the difference. `core` never learns
what a component is.

A `ModuleDef` bundles components + macros + request handlers;
`build_scope()` registers them into a `ComponentStack` (a lexical scope used
to resolve `FieldSpec::comp("Name")` references and macro names) and
compiles every view once.

## 7. Paths and updates: rebuilding the spine

Handlers return new instances; something must splice a new instance into an
immutable tree. That something is a `Path` — a sequence of `Step`s
(`FieldStep`, `SeqStep`, …) from the root — operating on the **`PathNode`**
trait (`field`/`item` to read, `with_field`/`with_item` to build a modified
copy, `handler` to find a handler bucket). `Value` implements `PathNode`
(`Obj` values delegate to the instance), so the whole state tree is
navigable and rebuildable:

```mbt check
///|
/// A parent holding a child component in a field — the smallest tree with a
/// spine worth rebuilding.
fn mailbox_module() -> @component.ModuleDef {
  let note = @component.component(
    name="Note",
    view=(
      #|<p class="note" @text=".text"></p>
    ),
    fields={ "text": @component.FieldSpec::of_default(Str("")) },
    receive={
      "write": (inst, args, _ctx) => {
        match args {
          [Str(s), ..] => Some(inst.set("text", Str(s)))
          _ => None
        }
      },
    },
  )
  let mailbox = @component.component(
    name="Mailbox",
    view=(
      #|<section><x render=".note"></x></section>
    ),
    fields={ "note": @component.FieldSpec::comp("Note") },
    receive={
      // forward to the child by path — used from the host in section 9
      "write": (_inst, args, ctx) => {
        ctx.send_at_path(ctx.path().concat([FieldStep("note")]), "write", args)
        None
      },
    },
  )
  @component.ModuleDef::new(name="mailbox", components=[mailbox, note])
}

///|
test "Path::update: run a handler at a path, rebuild only the spine" {
  let m = mailbox_module()
  let _scope = m.build_scope() // registers components so FieldSpec::comp resolves
  let root : @tutuca.Value = m.components[0].make(Map([])).to_value()
  // dispatch `write` on the Receive bucket of the node at .note
  let path = @tutuca.Path::new(steps=[FieldStep("note")])
  let new_root = path.update(root, Receive, "write", [Str("dear reader")])
  // the new tree has the new text…
  guard new_root.field("note") is Some(note)
  guard note.as_value() is Some(Obj(o))
  debug_inspect(
    o.obj_field("text"),
    content=(
      #|Some(RStr("dear reader"))
    ),
  )
  // …and the original tree is untouched (copy-on-write, not mutation)
  guard root.field("note") is Some(old_note)
  guard old_note.as_value() is Some(Obj(old))
  debug_inspect(
    old.obj_field("text"),
    content=(
      #|Some(RStr(""))
    ),
  )
}
```

`Path::update` walks down collecting the chain of nodes, asks the target for
its handler (`PathNode::handler(bucket, name)` → the instance's `receive`
entry), runs it, then rebuilds **only the spine** — parent nodes on the way
back up via `with_field`. Siblings keep their physical identity, which is
what makes the render cache's "same value → same vdom" check an O(1)
identity comparison.

Two refinements exist on top of plain `Path`:

- `DispatchPath` — a path whose steps can also be *frames* (loop bindings,
  scope enrichments) and *dynamic* segments (provide/lookup teleports). It
  is what event routing produces; `to_transaction_path()` strips it back to
  a plain state path.
- `Handler` — the uniform shape every bucket entry is wrapped into:
  `(Array[Value], &Ctx) -> &PathNode?`. The **`Ctx` trait** is the
  handler's window to the world: `path()`, `send`, `bubble`,
  `send_at_path`, `request`, `stop_propagation`. Handlers see only that
  trait, so the same component code runs under the real transactor, a test
  double, or a wasm-guest bridge.

## 8. The transactor: settling state

One event can trigger a cascade: a handler `send`s to a child, whose handler
`bubble`s up, which fires a `request`, whose response mutates again. The
`transactor` package serializes that cascade. `Transactor` owns the root
(`mut root : &PathNode` — the *only* mutable state cell in the framework),
queues `Transaction`s, and `settle()` runs them until quiet — each one a
`Path::update` producing the next root:

```mbt check
///|
test "transactor: messages queue, settle produces one new root" {
  let m = mailbox_module()
  let _scope = m.build_scope()
  let root : @tutuca.Value = m.components[0].make(Map([])).to_value()
  let txr = @transactor.Transactor::new(root)
  let mut changes = 0
  txr.on_change((_before, _after) => changes = changes + 1)
  let _ = txr.push_send(
    @tutuca.DispatchPath::of_steps([FieldStep("note")]),
    "write",
    [Str("hello")],
  )
  txr.settle()
  inspect(changes, content="1")
  guard txr.root.field("note") is Some(note)
  guard note.as_value() is Some(Obj(o))
  debug_inspect(
    o.obj_field("text"),
    content=(
      #|Some(RStr("hello"))
    ),
  )
}
```

The `ctx` a handler receives is the transactor's: `ctx.send(...)` pushes
another transaction rather than running the handler reentrantly — that is
how one user interaction becomes *one* `on_change`, no matter how many
messages it fans out into. Bubbling walks the path towards the root trying
each ancestor's `bubble` bucket; requests resolve through the `Requests`
trait and come back as `Response`-bucket transactions; `observe()` exposes
the whole dispatch feed (the inspector consumes it).

## 9. Closing the loop: events without listeners

Now the piece the vdom deliberately left out. The renderer embedded `Meta`
comment markers (section 5), and the template parser hoisted every
`@on.<event>` into a `NodeEvents` table (section 4). Event routing combines
them: the app installs **one** listener per event name at the root; when an
event fires, `render.from_node_and_event_name` walks *up* the real DOM from
the target (via the `DomWalk` trait), reading comment markers to reconstruct
the `DispatchPath` — which component, which loop iteration, which scope —
and the event tables to find the handler and its parsed argument `Val`s.
Those args are evaluated against a rebuilt `RenderStack` whose `event` slot
answers names like `value` and `key`, modifiers (`+send`, `+ctrl`) gate the
dispatch, and the result is pushed into the transactor.

`App[N]` is the thin loop that ties it together — generic over the same
`DomNode`/`DomWalk` trait as the vdom, so the identical `App` runs on
memdom (tests), the browser DOM (js) and wasm:

```
compile scope → render root → to_dom
        ⇑                        ⇓
   on_change: render → morph   DOM event → route by Meta → transactor → settle
```

End to end, through the public API — every layer of this document in five
lines:

```mbt check
///|
test "the whole loop, headless" {
  let h = @harness.mount(mailbox_module(), "Mailbox")
  inspect(h.text(".note"), content="")
  // host → root receive handler → send_at_path to the child → transactor
  // settles → on_change → render → morph. One interaction, one re-render.
  let before = h.render_count()
  h.send_at_root("write", args=[Str("hi")])
  inspect(h.text(".note"), content="hi")
  assert_eq(h.render_count(), before + 1)
}
```

## 10. Why `core` is one package

Value language and path/dispatch system share the `core` package because
their types form a single unbreakable cycle:

```
Obj::obj_handler returns Handler
  → Handler carries &Ctx and returns &PathNode?
    → Ctx::path() returns DispatchPath
      → DispatchPath steps carry Val (dynamic/frame segments)
        → Val evaluates to Value
          → Value::Obj(&Obj)  — back to the start
```

Split the package anywhere and one arrow has to cross backwards. Everything
*outside* the cycle did split: templates (`anode`), rendering (`render`),
the vdom (`vdom`), components (`component`), settlement (`transactor`), the
loop (`app`).

The same traits that close the cycle are the framework's extension points,
and each has more than one real implementor:

| Trait | Contract | Implementors |
|---|---|---|
| `Stack` | name resolution for `eval` | `RenderStack`, `NullStack`, your test doubles |
| `PathNode` | navigate/rebuild state | `Value` (delegating to `Obj`) |
| `Obj` | "acts like a component instance" | `Instance`, dyncomp's wasm-guest host object |
| `Ctx` | a handler's effects | the transactor's ctx, `NullCtx` |
| `DomNode`/`DomWalk` | a DOM | `memdom`, `browser`, `wasm` |

Each package also carries a `spec.mbt` stating its contract — start with
`core/spec.mbt`, which documents the cycle above in the code itself.
