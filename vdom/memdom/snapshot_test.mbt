// to_html snapshot regression net (fill with moon test --update).

///|
test "snapshot: basic tree" {
  let dom = to_dom(
    @vdom.h("div", attrs={ "className": Str("card"), "id": Str("root") }, childs=[
      @vdom.h("ul", childs=[
        @vdom.h("li", childs=[@vdom.text("one")]),
        @vdom.h("li", key="k2", childs=[@vdom.text("two")]),
      ]),
      @vdom.comment("marker"),
      @vdom.h("p", childs=[@vdom.text("text")]),
    ]),
  )
  inspect(
    dom.to_html(),
    content=(
      #|<div class="card" id="root"><ul><li>one</li><li>two</li></ul><!--marker--><p>text</p></div>
    ),
  )
}

///|
test "snapshot: svg with foreignObject" {
  let dom = to_dom(
    @vdom.h("svg", attrs={ "viewBox": Str("0 0 10 10") }, childs=[
      @vdom.h("rect", attrs={ "x": @vdom.AttrValue::int(1) }),
      @vdom.h("foreignObject", ns=Svg, childs=[div_text("hi")]),
    ]),
  )
  inspect(
    dom.to_html(),
    content=(
      #|<svg viewBox="0 0 10 10"><rect x="1"></rect><foreignObject><div>hi</div></foreignObject></svg>
    ),
  )
}

///|
test "snapshot: morph result equals fresh render serialization" {
  let a = @vdom.h("div", childs=[span_text("one"), span_text("two")])
  let b = @vdom.h("div", attrs={ "data-x": Str("1") }, childs=[
    span_text("two"),
    @vdom.comment("mid"),
    span_text("three"),
  ])
  let c = morphed(a, b)
  inspect(
    c.childs[0].to_html(),
    content=(
      #|<div data-x="1"><span>two</span><!--mid--><span>three</span></div>
    ),
  )
  inspect(
    rendered(b).childs[0].to_html(),
    content=(
      #|<div data-x="1"><span>two</span><!--mid--><span>three</span></div>
    ),
  )
}

///|
test "snapshot: fragment root" {
  let (c, o) = new_env()
  let _ = @vdom.render(
    @vdom.fragment([
      @vdom.comment("start"),
      @vdom.h("section", childs=[@vdom.text("body")]),
    ]),
    c,
    o,
  )
  inspect(
    c.to_html(),
    content=(
      #|<div><!--start--><section>body</section></div>
    ),
  )
}
