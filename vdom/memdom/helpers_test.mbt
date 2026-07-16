// Shared helpers for the memdom test suites (ports of test/dom.js utilities).

///|
/// Fresh (container, opts) pair — the JS setupJsdom + createElement("div").
fn new_env() -> (@memdom.MemNode, @vdom.RenderOpts[@memdom.MemNode]) {
  let d = @memdom.document()
  let c = @vdom.DomNode::create_element(d, "DIV", None, None)
  (c, @vdom.RenderOpts::new(d))
}

///|
/// Render old then morph to new in one container; fresh-render new in a
/// second container; both must be structurally equal (JS
/// assertPatchProduces).
fn assert_patch_produces(old_v : @vdom.Vdom, new_v : @vdom.Vdom) -> Unit raise {
  let (c1, o1) = new_env()
  let r1 = @vdom.render(old_v, c1, o1)
  let _ = @vdom.render(new_v, c1, o1, prev=r1)
  let (c2, o2) = new_env()
  let _ = @vdom.render(new_v, c2, o2)
  assert_true(@memdom.dom_equal(c1.childs[0], c2.childs[0]))
}

///|
/// Render `a`, morph to `b`, return the container.
fn morphed(a : @vdom.Vdom, b : @vdom.Vdom) -> @memdom.MemNode {
  let (c, o) = new_env()
  let r1 = @vdom.render(a, c, o)
  let _ = @vdom.render(b, c, o, prev=r1)
  c
}

///|
fn rendered(v : @vdom.Vdom) -> @memdom.MemNode {
  let (c, o) = new_env()
  let _ = @vdom.render(v, c, o)
  c
}

///|
/// The JS renderVNode: build a standalone subtree without a container.
fn to_dom(v : @vdom.Vdom) -> @memdom.MemNode {
  @vdom.to_dom(v, @vdom.RenderOpts::new(@memdom.document()))
}

///|
fn span_text(s : String) -> @vdom.Vdom {
  @vdom.h("span", childs=[@vdom.text(s)])
}

///|
fn div_text(s : String) -> @vdom.Vdom {
  @vdom.h("div", childs=[@vdom.text(s)])
}
