// Renderer tests: end-to-end parse → render → memdom → HTML, over RenderStack +
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
fn render_view(
  view : @anode.View,
  stack : RenderStack,
  ctx : RenderCtx,
) -> @vdom.Vdom {
  match view.anode {
    Some(node) =>
      render(node, stack, ctx).unwrap_or(
        @vdom.comment("view \{view.name} rendered nothing"),
      )
    None => @vdom.comment("view \{view.name} was not compiled")
  }
}

///|
fn render_html(
  html : String,
  state? : @tutuca.Value = Map(Map([])),
  resolver? : &ViewResolver,
  filter? : &@filter.VdomFilter,
) -> String {
  let stack = RenderStack::new(state)
  let ctx = RenderCtx::new(view_resolver?=resolver, filter?)
  match render(parse_node(html), stack, ctx) {
    Some(v) => to_html(v)
    None => "<!-- suppressed -->"
  }
}

///|
/// A `RenderCtx` with no cache memoizes nothing: two passes over the same node
/// build two distinct trees that compare equal. Only a component render SITE
/// is ever cached (see cache_wbtest.mbt), and only when the ctx carries a cache.
test "a second render pass reuses nothing, and renders the same thing" {
  let node = parse_node("<p class=\"x\">hi</p>")
  let ctx = RenderCtx::new()
  let stack = RenderStack::new(Map(Map([])))
  guard! render(node, stack, ctx) is Some(first)
  guard! render(node, stack, ctx) is Some(second)
  assert_false(physical_equal(first, second))
  assert_true(first.is_equal_to(second))
  assert_eq(to_html(second), "<p class=\"x\">hi</p>")
}

///|
/// The component-less path, which the cache DECLINES: a `ViewMap` render site
/// is handed a plain `Map`, which carries no `ObjId`, so nothing is keyed and
/// every pass rebuilds. Supplying a cache here would change nothing, which is
/// the point of declining rather than keying and missing.
test "a component render site rebuilds every pass, and tracks its value" {
  let card = parse_node("<div class=\"card\">static</div>")
  let resolver : &ViewResolver = ViewMap::{ views: { "main": card }, }
  let ctx = RenderCtx::new(view_resolver=resolver)
  let v1 : @tutuca.Value = Map({ "a": Num(1) })
  let stack = RenderStack::new(v1)
  guard! render_root(v1, stack, ctx) is Some(first)
  guard! render_root(v1, stack, ctx) is Some(second)
  // An unchanged value buys no reused subtree — a fresh tree that
  // compares equal is what the differ works from.
  assert_false(physical_equal(first, second))
  assert_true(first.is_equal_to(second))

  // Different values render distinct trees.
  let a : @tutuca.Value = Map({ "n": Num(1) })
  let b : @tutuca.Value = Map({ "n": Num(2) })
  guard! render_root(a, RenderStack::new(a), ctx) is Some(ra)
  guard! render_root(b, RenderStack::new(b), ctx) is Some(rb)
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
  // vdom serializes AttrValue::Bool(true) as ="true" (setAttribute does
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
test "elements and fragments both drop suppressed children" {
  let state = state_of([("visible", Bool(false))])
  assert_eq(
    render_html(
      "<main><b>a</b><i @show=\".visible\">b</i><u>c</u></main>",
      state~,
    ),
    "<main><b>a</b><u>c</u></main>",
  )
  assert_eq(
    render_html("<b>a</b><i @show=\".visible\">b</i><u>c</u>", state~),
    "<b>a</b><u>c</u>",
  )
}

///|
test "svg subtree keeps its namespace" {
  let node = parse_node("<svg viewBox=\"0 0 1 1\"><circle/></svg>")
  let stack = RenderStack::new(Map(Map([])))
  guard! render(node, stack, RenderCtx::new()) is Some(v)
  guard! v is Node(el)
  assert_true(el.ns is Some(Svg))
  assert_true(el.attrs.get("viewBox") is Some(Str("0 0 1 1")))
}

///|
test "render-it resolves through a ViewMap and enters the value" {
  let card = parse_node("<div class=\"card\">static</div>")
  let resolver = ViewMap::{ views: { "main": card }, }
  assert_eq(
    render_html("<section><x render-it></x></section>", resolver~),
    "<section><!--§{\"$\":\"Comp\",\"nid\":0,\"cid\":0,\"vid\":\"main\"}§--><div class=\"card\">static</div></section>",
  )
}

///|
test "render-it with as= picks the named view" {
  let detail = parse_node("<p>detail</p>")
  let resolver = ViewMap::{ views: { "detail": detail }, }
  assert_eq(
    render_html("<x render-it as=\"detail\"></x>", resolver~),
    "<!--§{\"$\":\"Comp\",\"nid\":0,\"cid\":0,\"vid\":\"detail\"}§--><p>detail</p>",
  )
}

///|
/// A view that renders its own value again is unbounded — the second pass
/// reaches the same node with the same value and does it again. The site
/// leaves a marker instead, and no §Comp§ boundary: an event walking back up
/// must not cross a component that is not there.
test "a view that renders its own value again stops instead of recursing" {
  let selfish = parse_node("<div class=\"loop\"><x render-it></x></div>")
  let resolver = ViewMap::{ views: { "main": selfish }, }
  assert_eq(
    render_html("<x render-it></x>", resolver~),
    "<!--§{\"$\":\"Comp\",\"nid\":0,\"cid\":0,\"vid\":\"main\"}§--><div class=\"loop\"><!--RECURSION AVOIDED--></div>",
  )
}

///|
/// The guard reads the nearest enclosing FRAME, and `@each` items are
/// transparent scopes: the item is a different value from the collection's
/// owner, so the ordinary iteration shape renders through untouched.
test "an @each item is not its owner, so render-it inside a loop is fine" {
  let row = parse_node("<li><x text=\".n\"></x></li>")
  let resolver = ViewMap::{ views: { "main": row }, }
  let rows : Array[@tutuca.Value] = [
    Map({ "n": Str("a") }),
    Map({ "n": Str("b") }),
  ]
  let state = state_of([("rows", List(rows))])
  assert_true(
    render_html("<ul><x render-each=\".rows\"></x></ul>", state~, resolver~).contains(
      "<li>a</li>",
    ),
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
  v.compile(px, MacroTestScope::{ macros: { "card": card }, })
  let stack = RenderStack::new(Map(Map([])))
  let html = to_html(render_view(v, stack, RenderCtx::new()))
  // View::compile stamps data-vid on the root (the headless cleanup that
  // strips data-* is not ported).
  assert_eq(
    html, "<section data-vid=\"main\"><div class=\"card\"><em>custom</em></div></section>",
  )
}

///|
test "RenderStack lookups: binds chain, it fields, view names" {
  let state : @tutuca.Value = Map({ "title": Str("hello") })
  let root = RenderStack::new(state)
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
  // fields read the CURRENT item, per frame (this.it[name]): a scalar it
  // has no fields; the root frame's map does
  assert_true(@tutuca.Stack::lookup_storage(grand, "title") is Null)
  assert_true(@tutuca.Stack::lookup_storage(root, "title") is Str("hello"))
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
  let stack = RenderStack::new(state)
  // lookup_method invokes; lookup_trigger returns the raw Fn
  assert_true(@tutuca.Stack::lookup_method(stack, "greet") is Str("hi"))
  assert_true(@tutuca.Stack::lookup_trigger(stack, "greet") is Fn(_))
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
// A custom collection: iterated by @each through seq_entries,
// keyed by insertion order; item resolves the same keys.
priv struct KeyedList {
  order : Array[String]
  items : Map[String, @tutuca.Value]
}

///|
impl @tutuca.Obj for KeyedList with fn seq_entries(self) {
  Some(self.order.map(k => (KStr(k), self.items.get(k).unwrap_or(Null))))
}

///|
impl @tutuca.Obj for KeyedList with fn item(self, key) {
  match key {
    KStr(s) => self.items.get(s)
    _ => None
  }
}

///|
test "@each iterates a custom collection via seq_entries (SEQ_INFO)" {
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
  // (id 1: the inner <x text> registered first); the headless cleanup that
  // strips data-* is not ported.
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
  let resolver = ViewMap::{ views: { "main": item_view }, }
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

///|
/// `@setinnermd` evaluates to the markdown SOURCE under its own attribute name,
/// which is as far as `render` takes it — turning that into elements is
/// `vdom/filter/markdown`'s job, and this test deliberately runs without it.
///
/// What memdom shows here is the fail-closed branch in `set_prop`: no filter
/// consumed the attribute, so the element is CLEARED rather than being given
/// the markdown as text or as markup. A directive whose name promises it is
/// sanitized fails visibly when nothing sanitized it.
test "setinnermd evaluates to its source, and renders nothing on its own" {
  assert_eq(
    render_html(
      "<div @setinnermd=\".body\"></div>",
      state=state_of([("body", Str("# hi"))]),
    ),
    "<div></div>",
  )
}

///|
/// The same directive with the filter that understands it. This is the one test
/// that walks the whole path — directive → `AttrItem::RawMarkdown` → `Md` →
/// `MdFilter` → nodes → DOM — and the assertion is that `<h1>` is a real
/// element with a real text child, not a string anybody parsed twice.
test "setinnermd renders described nodes once a filter is installed" {
  assert_eq(
    render_html(
      "<div @setinnermd=\".body\"></div>",
      state=state_of([("body", Str("# hi\n\n[x](javascript:alert(1))"))]),
      filter=@mdfilter.default_filter(),
    ),
    "<div><h1>hi</h1><p><a>x</a></p></div>",
  )
}

///|
/// The two safe markup directives, on their own. Same fail-closed shape as
/// `@setinnermd` above and for the same reason: no filter consumed the
/// attribute, so `set_prop` CLEARS the element rather than handing the payload
/// to `set_inner_html`. This is the branch that lets Pass 1 wave both through —
/// "the builder ran" is not an assumption the static pass has to make.
test "the safe markup directives render nothing on their own" {
  assert_eq(
    render_html(
      "<div @setinnerhtml=\".body\"></div>",
      state=state_of([("body", Str("<b>markup</b>"))]),
    ),
    "<div></div>",
  )
  assert_eq(
    render_html(
      "<svg @setinnersvg=\".chart\"></svg>",
      state=state_of([("chart", Str("<circle r=\"1\"/>"))]),
    ),
    "<svg></svg>",
  )
}

///|
/// And with the filter installed, the whole path: directive →
/// `AttrItem::SafeHtml` → `AttrValue::SafeHtml` → `SafeMarkupFilter` → nodes →
/// DOM. The `<script>` is gone and the `javascript:` href is gone, which is
/// what the safe name is promising; `<b>` and the link text stay.
test "setinnerhtml renders sanitized nodes once a filter is installed" {
  assert_eq(
    render_html(
      "<div @setinnerhtml=\".body\"></div>",
      state=state_of([
        (
          "body",
          Str(
            "<b>ok</b><script>alert(1)</script><a href=\"javascript:alert(2)\">x</a>",
          ),
        ),
      ]),
      filter=@mdfilter.default_filter(),
    ),
    "<div><b>ok</b><a>x</a></div>",
  )
}

///|
/// The SVG half, through the same filter. A bare fragment with no `<svg>` root
/// becomes SVG-namespaced elements, and the SMIL element that would have
/// rewritten the `href` after every filter had run is not there.
test "setinnersvg renders namespaced nodes and drops SMIL" {
  assert_eq(
    render_html(
      "<svg @setinnersvg=\".chart\"></svg>",
      state=state_of([
        (
          "chart",
          Str(
            "<circle r=\"1\"/><a href=\"/ok\"><animate attributeName=\"href\" to=\"javascript:alert(1)\"/></a>",
          ),
        ),
      ]),
      filter=@mdfilter.default_filter(),
    ),
    "<svg><circle r=\"1\"></circle><a href=\"/ok\"></a></svg>",
  )
}
