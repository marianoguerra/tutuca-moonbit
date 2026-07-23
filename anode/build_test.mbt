// The builders are only useful if they are the parser's own output spelled
// out: `tutuca gen-views` emits calls to them for a tree it got from the
// parser, and the renderer must not be able to tell the two apart. So the
// test is the equality itself — parse a view, write the same view with the
// builders, compare the values.

///|
fn tree_repr(node : @anode.ANode) -> String {
  @debug.render(to_repr(node))
}

///|
test "a hand-built tree is the parsed tree" {
  let px = @anode.ParseContext::new()
  let parsed = @anode.ANode::parse(
    (
      #|<div class="card" :title=".label"><b class="lbl"><x text=".label"></x></b><button class="go" @on.click="add 1" @on.keydown+send="$inc">go</button></div>
    ),
    px,
  ).unwrap()
  let built = @anode.h(
    "div",
    [@anode.attr("class", "card"), @anode.dyn_attr("title", Field("label"))],
    [
      @anode.h("b", [@anode.attr("class", "lbl")], [
        @anode.dyn_text(Field("label"), id=0),
      ]),
      @anode.h("button", [@anode.attr("class", "go"), @anode.eid(0)], [
        @anode.text("go"),
      ]),
    ],
  )
  assert_eq(tree_repr(built), tree_repr(parsed))
  // The event table the same markup registers, rebuilt from its positions.
  assert_eq(
    @debug.render(
      to_repr(
        @anode.events_of([
          [
            @anode.on("click", HandlerName(name="add", ns=Input), args=[
              @anode.const_num(1),
            ]),
            @anode.on("keydown", Method("inc"), modifiers=["send"]),
          ],
        ]),
      ),
    ),
    @debug.render(to_repr(px.events)),
  )
}

///|
test "wrappers, loops and conditional attributes build the same way" {
  let px = @anode.ParseContext::new()
  let parsed = @anode.ANode::parse(
    (
      #|<ul @show=".items" @if.class=".open" @then.class="'on'" @else.class="'off'"><li @each=".items"><x text="@value"></x></li></ul>
    ),
    px,
  ).unwrap()
  // The ids are the registration order the parser walked in: the <x text> node
  // first, then the loop that wraps it.
  let built = @anode.show(
    Field("items"),
    @anode.h(
      "ul",
      [
        @anode.if_attr(
          "class",
          Field("open"),
          then_val=@anode.const_str("on"),
          else_val=@anode.const_str("off"),
        ),
      ],
      [
        @anode.each(
          1,
          Field("items"),
          @anode.h("li", [], [@anode.dyn_text(Bind("value"), id=0)]),
        ),
      ],
    ),
  )
  assert_eq(tree_repr(built), tree_repr(parsed))
}

///|
test "the attribute list decides the representation, exactly as the parser" {
  // Nothing dynamic — including a `:attr` whose value parsed to a constant —
  // collapses to the evaluated map.
  guard @anode.h(
      "div",
      [@anode.attr("class", "a"), @anode.dyn_attr("id", @anode.const_str("b"))],
      [],
    )
    is Dom(d)
  guard d.attrs is ConstAttrs(m)
  assert_true(m.get("class") is Some(LStr("a")))
  assert_true(m.get("id") is Some(LStr("b")))
  // One dynamic value keeps the whole list.
  guard @anode.h(
      "div",
      [@anode.attr("class", "a"), @anode.dyn_attr("id", Field("id"))],
      [],
    )
    is Dom(d2)
  assert_true(d2.attrs is DynAttrs(_))
  // So does an @if, whose branches are not attribute values at all.
  guard @anode.h("div", [@anode.if_attr("class", Field("on"))], []) is Dom(d3)
  assert_true(d3.attrs is DynAttrs(_))
}
