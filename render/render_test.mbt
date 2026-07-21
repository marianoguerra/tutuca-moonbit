// Renderer tests: end-to-end parse → render → memdom → HTML. Ports of the
// render describes from test/anode-core.test.js, adapted to RenderStack +
// ViewMap (the component-less mocks from render-plan.md).

///|
fn parse_node(html : String) -> @anode.ANode {
  let px = @anode.ParseContext::new()
  @anode.ANode::parse(html, px).unwrap()
}

///|
fn to_html(v : @vdom.Vdom) -> String {
  let doc = @memdom.document()
  @vdom.to_dom(v, @vdom.RenderOpts::new(doc)).to_html()
}

///|
fn render_html(
  html : String,
  state? : @tutuca.Value = Map(Map([])),
  resolver? : &@render.ViewResolver,
) -> String {
  let stack = @render.RenderStack::new(state)
  let ctx = @render.RenderCtx::new(view_resolver?=resolver)
  match @render.render(parse_node(html), stack, ctx) {
    Some(v) => to_html(v)
    None => "<!-- suppressed -->"
  }
}

///|
test "RenderOnce memoizes a constant subtree across passes" {
  // optimize_node wraps a constant node in a RenderOnce marker; a shared ctx
  // (same render_once map) returns the identical Vdom on the second render,
  // observable via physical_equal.
  let node = @anode.optimize_node(parse_node("<p class=\"x\">hi</p>"))
  guard node is RenderOnce(_)
  let ctx = @render.RenderCtx::new()
  let stack = @render.RenderStack::new(Map(Map([])))
  guard @render.render(node, stack, ctx) is Some(first)
  guard @render.render(node, stack, ctx) is Some(second)
  assert_true(physical_equal(first, second))
  // and it still renders the right HTML
  assert_eq(to_html(second), "<p class=\"x\">hi</p>")
  // a fresh ctx (empty cache) renders a distinct object
  guard @render.render(node, stack, @render.RenderCtx::new()) is Some(other)
  assert_false(physical_equal(first, other))
}

///|
test "render cache reuses an unchanged component subtree, misses on change" {
  let card = parse_node("<div class=\"card\">static</div>")
  let resolver : &@render.ViewResolver = @render.ViewMap::{
    views: { "main": card },
  }
  let cache = @render.RenderCache::new()
  let v1 : @tutuca.Value = Map({ "a": Num(1) })
  let ctx = @render.RenderCtx::new(view_resolver=resolver, render_cache=cache)
  let stack = @render.RenderStack::new(v1)
  guard @render.render_root(v1, stack, ctx) is Some(first)  // miss, cached
  guard @render.render_root(v1, stack, ctx) is Some(second)  // hit (cur)
  assert_true(physical_equal(first, second))
  // survives one generation roll (promoted from prev)
  cache.next_generation()
  guard @render.render_root(v1, stack, ctx) is Some(third)
  assert_true(physical_equal(first, third))
  // falls out after two rolls with no reuse
  cache.next_generation()
  cache.next_generation()
  guard @render.render_root(v1, stack, ctx) is Some(fourth)
  assert_false(physical_equal(first, fourth))

  // identity validation: a different value under the same slot key is a miss
  // (never a stale hit), so it re-renders a distinct object.
  let cache2 = @render.RenderCache::new()
  let ctx2 = @render.RenderCtx::new(view_resolver=resolver, render_cache=cache2)
  let a : @tutuca.Value = Map({ "n": Num(1) })
  let b : @tutuca.Value = Map({ "n": Num(2) })
  guard @render.render_root(a, @render.RenderStack::new(a), ctx2) is Some(ra)
  guard @render.render_root(b, @render.RenderStack::new(b), ctx2) is Some(rb)
  assert_false(physical_equal(ra, rb))
}

// ─── value-free: static rendering ───────────────────────────────────────────

///|
test "static markup renders through to HTML" {
  assert_eq(
    render_html("<div class=\"m-4\"><p>hi</p> tail</div>"),
    "<div class=\"m-4\"><p>hi</p> tail</div>",
  )
}

///|
test "boolean attr and comment render" {
  // vdom serializes AttrValue::Bool(true) as ="true" (JS setAttribute does
  // the same); the browser treats both spellings identically.
  assert_eq(
    render_html("<details open><!-- note --></details>"),
    "<details open=\"true\"><!-- note --></details>",
  )
}

///|
test "fragment root renders all children" {
  assert_eq(render_html("<b>a</b><i>b</i>"), "<b>a</b><i>b</i>")
}

///|
test "svg subtree keeps its namespace" {
  let node = parse_node("<svg viewBox=\"0 0 1 1\"><circle/></svg>")
  let stack = @render.RenderStack::new(Map(Map([])))
  guard @render.render(node, stack, @render.RenderCtx::new()) is Some(v)
  guard v is Node(el)
  assert_true(el.ns is Some(Svg))
  assert_true(el.attrs.get("viewBox") is Some(Str("0 0 1 1")))
}

///|
test "render-it resolves through a ViewMap and enters the value" {
  let card = parse_node("<div class=\"card\">static</div>")
  let resolver = @render.ViewMap::{ views: { "main": card } }
  assert_eq(
    render_html("<section><x render-it></x></section>", resolver~),
    "<section><!--§{\"$\":\"Comp\",\"nid\":0,\"cid\":0,\"vid\":\"main\"}§--><div class=\"card\">static</div></section>",
  )
}

///|
test "render-it with as= picks the named view" {
  let detail = parse_node("<p>detail</p>")
  let resolver = @render.ViewMap::{ views: { "detail": detail } }
  assert_eq(
    render_html("<x render-it as=\"detail\"></x>", resolver~),
    "<!--§{\"$\":\"Comp\",\"nid\":0,\"cid\":0,\"vid\":\"detail\"}§--><p>detail</p>",
  )
}

///|
test "unresolved render site is suppressed like JS" {
  assert_eq(render_html("<x render-it></x>"), "<!-- suppressed -->")
  assert_eq(
    render_html("<div><x render-it></x><p>after</p></div>"),
    "<div><p>after</p></div>",
  )
}

///|
priv struct MacroTestScope {
  macros : Map[String, @anode.Macro]
}

///|
impl @anode.MacroScope for MacroTestScope with fn lookup_macro(self, name) {
  self.macros.get(name)
}

///|
test "compiled macro call renders its expansion" {
  let card = @anode.Macro::{
    defaults: Map([]),
    raw_view: "<div class=\"card\"><x:slot name=\"body\"><p>default</p></x:slot></div>",
  }
  let v = @anode.View::new(
    "main",
    raw_view="<section><x:card><x slot=\"body\"><em>custom</em></x></x:card></section>",
  )
  let px = @anode.ParseContext::new()
  v.compile(px, MacroTestScope::{ macros: { "card": card } })
  let stack = @render.RenderStack::new(Map(Map([])))
  let html = to_html(@render.render_view(v, stack, @render.RenderCtx::new()))
  // View::compile stamps data-vid on the root (JS strips data-* only in
  // renderToString's cleanAttrs pass, which is not ported).
  assert_eq(
    html, "<section data-vid=\"main\"><div class=\"card\"><em>custom</em></div></section>",
  )
}

///|
test "RenderStack lookups: binds chain, it fields, view names" {
  let state : @tutuca.Value = Map({ "title": Str("hello") })
  let root = @render.RenderStack::new(state)
  assert_true(root.it is Map(_))
  let child = root.enter(Str("item"), { "key": Num(0) }, is_frame=false)
  let grand = child.enter(Str("inner"), { "value": Str("v") }, is_frame=false)
  // binds resolve along the chain of transparent scopes
  assert_true(@tutuca.Stack::lookup_bind(grand, "value") is Str("v"))
  assert_true(@tutuca.Stack::lookup_bind(grand, "key") is Num(0))
  assert_true(@tutuca.Stack::lookup_bind(grand, "missing") is Null)
  // a frame is a barrier: binds never cross a component boundary
  let framed = child.enter(Str("comp"), Map([]))
  assert_true(@tutuca.Stack::lookup_bind(framed, "key") is Null)
  // fields read the CURRENT item, per frame (JS this.it[name]): a scalar it
  // has no fields; the root frame's map does
  assert_true(@tutuca.Stack::lookup_field_raw(grand, "title") is Null)
  assert_true(@tutuca.Stack::lookup_field_raw(root, "title") is Str("hello"))
  // dynamic/type lookups stay at the Null default (component territory)
  assert_true(@tutuca.Stack::lookup_dynamic(grand, "x") is Null)
  let pushed = grand.push_view_name("detail")
  @debug.assert_eq(pushed.view_names, ["detail"])
  assert_eq(grand.view_names.length(), 0) // copy-on-push
}

///|
test "state Fn fields back methods and handlers" {
  let state : @tutuca.Value = Map({
    "greet": Fn(args => {
      match args {
        // element 0 is `this` (the state map)
        [Map(_), ..] => Str("hi")
        _ => Str("no-this")
      }
    }),
  })
  let stack = @render.RenderStack::new(state)
  // lookup_method invokes; get_handler_for returns the raw Fn
  assert_true(@tutuca.Stack::lookup_method(stack, "greet") is Str("hi"))
  assert_true(@tutuca.Stack::get_handler_for(stack, "greet", Input) is Fn(_))
  assert_true(@tutuca.Stack::lookup_method(stack, "missing") is Null)
}

// ─── value evaluation against a state map ──────────────────────────────────

///|
fn state_of(pairs : Array[(String, @tutuca.Value)]) -> @tutuca.Value {
  let m : Map[String, @tutuca.Value] = Map([])
  for pair in pairs {
    m[pair.0] = pair.1
  }
  Map(m)
}

///|
test "x text renders the evaluated value" {
  assert_eq(
    render_html("<span><x text=\"'hi'\"></x></span>"),
    "<span>hi</span>",
  )
  assert_eq(
    render_html(
      "<span><x text=\".title\"></x></span>",
      state=state_of([("title", Str("hello"))]),
    ),
    "<span>hello</span>",
  )
}

///|
test "@show and @hide gate on truthiness" {
  let state = state_of([("isOpen", Bool(true)), ("isClosed", Bool(false))])
  assert_eq(
    render_html("<div @show=\".isOpen\">shown</div>", state~),
    "<div>shown</div>",
  )
  assert_eq(
    render_html("<div @show=\".isClosed\">shown</div>", state~),
    "<!-- suppressed -->",
  )
  assert_eq(
    render_html("<div @hide=\".isClosed\">kept</div>", state~),
    "<div>kept</div>",
  )
}

///|
test "dynamic attrs evaluate against the state" {
  let state = state_of([("cls", Str("m-4")), ("hidden", Bool(false))])
  assert_eq(
    render_html("<p :class=\".cls\" :hidden=\".hidden\">x</p>", state~),
    "<p class=\"m-4\">x</p>", // false attr is omitted
  )
}

///|
test "@if.class with @then/@else picks the branch" {
  let on = state_of([("cond", Bool(true))])
  let off = state_of([("cond", Bool(false))])
  let tpl = "<div @if.class=\".cond\" @then=\"'a'\" @else=\"'d'\"></div>"
  assert_eq(render_html(tpl, state=on), "<div class=\"a\"></div>")
  assert_eq(render_html(tpl, state=off), "<div class=\"d\"></div>")
}

///|
test "@each renders per item with key/value binds" {
  let state = state_of([("items", List([Str("a"), Str("b")]))])
  assert_eq(
    render_html(
      "<ul><li @each=\".items\"><x text=\"@value\"></x></li></ul>",
      state~,
    ),
    (
      #|<ul><!--§{"$":"Each","nid":1,"si":0}§--><li>a</li><!--§{"$":"Each","nid":1,"si":1}§--><li>b</li></ul>
    ),
  )
}

///|
// A custom collection (JS SEQ_INFO): iterated by @each through obj_seq_entries,
// keyed by insertion order; obj_item resolves the same keys.
priv struct KeyedList {
  order : Array[String]
  items : Map[String, @tutuca.Value]
}

///|
impl @tutuca.Obj for KeyedList with fn obj_seq_entries(self) {
  Some(self.order.map(k => (KStr(k), self.items.get(k).unwrap_or(Null))))
}

///|
impl @tutuca.Obj for KeyedList with fn obj_item(self, key) {
  match key {
    KStr(s) => self.items.get(s)
    _ => None
  }
}

///|
test "@each iterates a custom collection via obj_seq_entries (SEQ_INFO)" {
  let songs = KeyedList::{
    order: ["a", "b"],
    items: { "a": Str("x"), "b": Str("y") },
  }
  let state = state_of([("songs", Obj(songs))])
  // keyed entries emit `sk` breadcrumbs (not `si`) and preserve their keys
  assert_eq(
    render_html(
      "<ul><li @each=\".songs\"><x text=\"@value\"></x></li></ul>",
      state~,
    ),
    (
      #|<ul><!--§{"$":"Each","nid":1,"sk":"a"}§--><li>x</li><!--§{"$":"Each","nid":1,"sk":"b"}§--><li>y</li></ul>
    ),
  )
}

///|
test "@each with @when filters items" {
  let state = state_of([
    ("items", List([Num(1), Num(2), Num(3)])),
    (
      "big",
      Fn(args => {
        match args {
          // (this, key, value, iterData) — value > 1 passes
          [_, _, Num(v), _] => Bool(v > 1.0)
          _ => Bool(false)
        }
      }),
    ),
  ])
  assert_eq(
    render_html(
      "<ul><li @each=\".items\" @when=\"big\"><x text=\"@value\"></x></li></ul>",
      state~,
    ),
    (
      #|<ul><!--§{"$":"Each","nid":1,"si":1}§--><li>2</li><!--§{"$":"Each","nid":1,"si":2}§--><li>3</li></ul>
    ),
  )
}

///|
test "@each with @enrich-with adds binds without clobbering key/value" {
  let state = state_of([
    ("items", List([Str("x")])),
    (
      "decorate",
      Fn(args => {
        match args {
          [_, Map(binds), ..] => {
            binds["label"] = Str("item!")
            binds["value"] = Str("clobbered") // must be restored by the loop
            Null
          }
          _ => Null
        }
      }),
    ),
  ])
  assert_eq(
    render_html(
      "<p @each=\".items\" @enrich-with=\"decorate\"><x text=\"@label\"></x>:<x text=\"@value\"></x></p>",
      state~,
    ),
    (
      #|<!--§{"$":"Each","nid":2,"si":0}§--><p>item!:x</p>
    ),
  )
}

///|
test "loop-less @enrich-with opens a scope frame" {
  let state = state_of([
    (
      "info",
      Fn(args => {
        match args {
          [_] => Map({ "label": Str("scoped") })
          _ => Null
        }
      }),
    ),
  ])
  // data-nid is the Scope wrapper's parse-time stamp on its wrapped node
  // (id 1: the inner <x text> registered first); JS strips data-* only in
  // renderToString's cleanAttrs pass, which is not ported.
  assert_eq(
    render_html(
      "<div @enrich-with=\"info\"><x text=\"@label\"></x></div>",
      state~,
    ),
    (
      #|<!--§{"$":"Scope","nid":1}§--><div data-nid="1">scoped</div>
    ),
  )
}

///|
test "render-each over a sequence via ViewMap" {
  let item_view = parse_node("<li>item</li>")
  let resolver = @render.ViewMap::{ views: { "main": item_view } }
  assert_eq(
    render_html(
      "<ul><x render-each=\".items\"></x></ul>",
      state=state_of([("items", List([Num(1), Num(2)]))]),
      resolver~,
    ),
    (
      #|<ul><!--§{"$":"Each","nid":1,"si":0}§--><!--§{"$":"Comp","nid":0,"cid":0,"vid":"main"}§--><li>item</li><!--§{"$":"Each","nid":1,"si":1}§--><!--§{"$":"Comp","nid":0,"cid":0,"vid":"main"}§--><li>item</li></ul>
    ),
  )
}

///|
test "dangerouslysetinnerhtml renders raw html" {
  assert_eq(
    render_html(
      "<div @dangerouslysetinnerhtml=\".markup\"></div>",
      state=state_of([("markup", Str("<b>raw</b>"))]),
    ),
    "<div><b>raw</b></div>",
  )
}
