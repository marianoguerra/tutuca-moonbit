// Port of test/vdom-diff.test.js: diff and patch, keyed reordering,
// duplicate keys, algorithm corner cases.

///|
fn nodes_from_array(arr : Array[String?]) -> @vdom.Vdom {
  let children : Array[@vdom.Vdom] = []
  for i, key in arr {
    match key {
      Some(k) =>
        children.push(
          @vdom.h("div", attrs={ "id": Str(k) }, key=k, childs=[@vdom.text(k)]),
        )
      None => {
        let id = "no-key-\{i}"
        children.push(
          @vdom.h("div", attrs={ "id": Str(id) }, childs=[@vdom.text(id)]),
        )
      }
    }
  }
  @vdom.h("div", childs=children)
}

///|
test "diff and patch: morph equals fresh render" {
  assert_patch_produces(div_text("hello"), div_text("goodbye"))
  assert_patch_produces(
    div_text("hello"),
    @vdom.h("div", childs=[span_text("goodbye")]),
  )
  assert_patch_produces(
    div_text("hello"),
    @vdom.h("span", childs=[@vdom.text("hello"), @vdom.text("again")]),
  )
  assert_patch_produces(
    @vdom.h("span", childs=[@vdom.text("hello"), @vdom.text("again")]),
    div_text("hello"),
  )
  assert_patch_produces(
    @vdom.h("div", attrs={ "className": Str("hello") }, childs=[
      @vdom.text("hello"),
    ]),
    @vdom.h("div", attrs={ "className": Str("goodbye") }, childs=[
      @vdom.text("goodbye"),
    ]),
  )
  assert_patch_produces(div_text("hello"), span_text("goodbye"))
  assert_patch_produces(
    @vdom.h("div", childs=[span_text("hello")]),
    @vdom.h("div", childs=[span_text("hello"), span_text("again")]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[span_text("hello"), span_text("again")]),
    @vdom.h("div", childs=[span_text("hello")]),
  )
}

///|
test "allows empty textnode" {
  let dom = to_dom(span_text(""))
  inspect(dom.childs.length(), content="1")
  inspect(dom.childs[0].data, content="")
}

///|
test "can replace vnode with vtext in place" {
  let (c, o) = new_env()
  let r1 = @vdom.render(@vdom.h("div", childs=[@vdom.h("div")]), c, o)
  let root = c.childs[0]
  assert_true(root.childs[0].kind is Element)
  let _ = @vdom.render(div_text("text"), c, o, prev=r1)
  assert_true(physical_equal(c.childs[0], root))
  inspect(root.childs.length(), content="1")
  assert_true(root.childs[0].kind is TextNode)
}

///|
test "keyed reordering preserves DOM references" {
  let left = nodes_from_array([
    Some("1"),
    Some("2"),
    Some("3"),
    Some("4"),
    Some("test"),
    Some("6"),
    Some("good"),
    Some("7"),
  ])
  let right = nodes_from_array([
    Some("7"),
    Some("4"),
    Some("3"),
    Some("2"),
    Some("6"),
    Some("test"),
    Some("good"),
    Some("1"),
  ])
  let (c, o) = new_env()
  let r1 = @vdom.render(left, c, o)
  let root = c.childs[0]
  let before = root.childs.copy()
  let _ = @vdom.render(right, c, o, prev=r1)
  assert_true(physical_equal(c.childs[0], root))
  inspect(root.childs.length(), content="8")
  assert_true(physical_equal(root.childs[7], before[0]))
  assert_true(physical_equal(root.childs[3], before[1]))
  assert_true(physical_equal(root.childs[2], before[2]))
  assert_true(physical_equal(root.childs[1], before[3]))
  assert_true(physical_equal(root.childs[5], before[4]))
  assert_true(physical_equal(root.childs[4], before[5]))
  assert_true(physical_equal(root.childs[6], before[6]))
  assert_true(physical_equal(root.childs[0], before[7]))
}

///|
test "mix keys without keys" {
  fn tree(key_first : Bool) {
    let children : Array[@vdom.Vdom] = []
    if key_first {
      children.push(@vdom.h("div", key="1"))
    }
    for _i in 0..<7 {
      children.push(@vdom.h("div"))
    }
    if !key_first {
      children.push(@vdom.h("div", key="1"))
    }
    @vdom.h("div", childs=children)
  }

  let (c, o) = new_env()
  let r1 = @vdom.render(tree(true), c, o)
  let root = c.childs[0]
  let before = root.childs.copy()
  let _ = @vdom.render(tree(false), c, o, prev=r1)
  assert_true(physical_equal(c.childs[0], root))
  inspect(root.childs.length(), content="8")
  // keyed node moved to the end; first unkeyed slot reuses old second child
  assert_true(physical_equal(root.childs[0], before[1]))
  assert_true(physical_equal(root.childs[7], before[0]))
}

///|
test "avoid unnecessary reordering" {
  fn tree() {
    @vdom.h("div", childs=[
      @vdom.h("div"),
      @vdom.h("div", key="1"),
      @vdom.h("div"),
    ])
  }

  let (c, o) = new_env()
  let r1 = @vdom.render(tree(), c, o)
  let root = c.childs[0]
  let before = root.childs.copy()
  let _ = @vdom.render(tree(), c, o, prev=r1)
  assert_true(physical_equal(c.childs[0], root))
  for i in 0..<3 {
    assert_true(physical_equal(root.childs[i], before[i]))
  }
}

///|
fn keyed_div(k : String, txt : String) -> @vdom.Vdom {
  @vdom.h("div", key=k, childs=[@vdom.text(txt)])
}

///|
test "delete key at start / add key to start / delete end / add end" {
  fn keys(ks : Array[String]) {
    @vdom.h("div", childs=ks.map(k => keyed_div(k, k)))
  }
  // delete at start: b, c keep their DOM nodes

  let (c, o) = new_env()
  let r1 = @vdom.render(keys(["a", "b", "c"]), c, o)
  let root = c.childs[0]
  let before = root.childs.copy()
  let _ = @vdom.render(keys(["b", "c"]), c, o, prev=r1)
  inspect(root.childs.length(), content="2")
  assert_true(physical_equal(root.childs[0], before[1]))
  assert_true(physical_equal(root.childs[1], before[2]))
  // add key to start
  let (c2, o2) = new_env()
  let r2 = @vdom.render(keys(["b", "c"]), c2, o2)
  let root2 = c2.childs[0]
  let before2 = root2.childs.copy()
  let _ = @vdom.render(keys(["a", "b", "c"]), c2, o2, prev=r2)
  inspect(root2.childs.length(), content="3")
  assert_true(physical_equal(root2.childs[1], before2[0]))
  assert_true(physical_equal(root2.childs[2], before2[1]))
  // delete key at end
  let (c3, o3) = new_env()
  let r3 = @vdom.render(keys(["a", "b", "c"]), c3, o3)
  let root3 = c3.childs[0]
  let before3 = root3.childs.copy()
  let _ = @vdom.render(keys(["a", "b"]), c3, o3, prev=r3)
  inspect(root3.childs.length(), content="2")
  assert_true(physical_equal(root3.childs[0], before3[0]))
  assert_true(physical_equal(root3.childs[1], before3[1]))
  // add key to end
  let (c4, o4) = new_env()
  let r4 = @vdom.render(keys(["a", "b"]), c4, o4)
  let root4 = c4.childs[0]
  let before4 = root4.childs.copy()
  let _ = @vdom.render(keys(["a", "b", "c"]), c4, o4, prev=r4)
  inspect(root4.childs.length(), content="3")
  assert_true(physical_equal(root4.childs[0], before4[0]))
  assert_true(physical_equal(root4.childs[1], before4[1]))
}

///|
test "delete key in the middle preserves survivors" {
  let (c, o) = new_env()
  let r1 = @vdom.render(
    @vdom.h("div", childs=[
      keyed_div("a", "a"),
      keyed_div("b", "b"),
      keyed_div("c", "c"),
    ]),
    c,
    o,
  )
  let root = c.childs[0]
  let before = root.childs.copy()
  let _ = @vdom.render(
    @vdom.h("div", childs=[keyed_div("a", "a"), keyed_div("c", "c")]),
    c,
    o,
    prev=r1,
  )
  inspect(root.childs.length(), content="2")
  assert_true(physical_equal(root.childs[0], before[0]))
  assert_true(physical_equal(root.childs[1], before[2]))
}

///|
test "style patches via attribute updates" {
  let c = morphed(
    @vdom.h("div", attrs={ "style": Str("border: 1px solid #000") }),
    @vdom.h("div", attrs={ "style": Str("padding: 5px") }),
  )
  assert_true(c.childs[0].get_attribute("style") is Some("padding: 5px"))
  // add from none
  let c2 = morphed(
    @vdom.h("div"),
    @vdom.h("div", attrs={ "style": Str("color: red") }),
  )
  assert_true(c2.childs[0].get_attribute("style") is Some("color: red"))
  // remove all styles
  let c3 = morphed(
    @vdom.h("div", attrs={ "style": Str("color: red; margin: 5px") }),
    @vdom.h("div"),
  )
  assert_true(c3.childs[0].get_attribute("style") is None)
}

///|
test "duplicate key behavior produces correct DOM" {
  assert_patch_produces(
    @vdom.h("div", childs=[keyed_div("a", "first"), keyed_div("b", "second")]),
    @vdom.h("div", childs=[keyed_div("a", "first"), keyed_div("a", "duplicate")]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[keyed_div("a", "A"), keyed_div("b", "B")]),
    @vdom.h("div", childs=[
      keyed_div("b", "B"),
      keyed_div("a", "A"),
      keyed_div("c", "C"),
    ]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[keyed_div("a", "A"), keyed_div("b", "B")]),
    @vdom.h("div", childs=[
      keyed_div("a", "A"),
      keyed_div("b", "B"),
      keyed_div("c", "C"),
    ]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[keyed_div("a", "A"), keyed_div("b", "B")]),
    @vdom.h("div", childs=[
      keyed_div("b", "B"),
      keyed_div("a", "A"),
      @vdom.h("div", childs=[@vdom.text("no key")]),
    ]),
  )
  // one-sided duplicates, both directions
  assert_patch_produces(
    @vdom.h("div", childs=[keyed_div("a", "a"), keyed_div("b", "b")]),
    @vdom.h("div", childs=[
      keyed_div("a", "a"),
      keyed_div("a", "a-dup"),
      keyed_div("b", "b"),
    ]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[
      keyed_div("a", "a"),
      keyed_div("a", "a-dup"),
      keyed_div("b", "b"),
    ]),
    @vdom.h("div", childs=[keyed_div("a", "a"), keyed_div("b", "b")]),
  )
}

///|
test "keyed reconciliation corner cases" {
  // complete key replacement
  assert_patch_produces(
    @vdom.h("div", childs=[
      keyed_div("a", "a"),
      keyed_div("b", "b"),
      keyed_div("c", "c"),
    ]),
    @vdom.h("div", childs=[
      keyed_div("d", "d"),
      keyed_div("e", "e"),
      keyed_div("f", "f"),
    ]),
  )
  // reorder with simultaneous content changes
  assert_patch_produces(
    @vdom.h("div", childs=[
      keyed_div("a", "X"),
      keyed_div("b", "Y"),
      keyed_div("c", "Z"),
    ]),
    @vdom.h("div", childs=[
      keyed_div("c", "Z2"),
      keyed_div("a", "X2"),
      keyed_div("b", "Y2"),
    ]),
  )
  // empty <-> keyed
  assert_patch_produces(
    @vdom.h("div"),
    @vdom.h("div", childs=[keyed_div("a", "a"), keyed_div("b", "b")]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[keyed_div("a", "a"), keyed_div("b", "b")]),
    @vdom.h("div"),
  )
}

///|
test "type-crossing patches" {
  assert_patch_produces(
    @vdom.h("div", childs=[@vdom.text("hello")]),
    @vdom.h("div", childs=[@vdom.comment("hello")]),
  )
  let c = morphed(
    @vdom.h("div", childs=[@vdom.text("hello")]),
    @vdom.h("div", childs=[@vdom.comment("hello")]),
  )
  assert_true(c.childs[0].childs[0].kind is CommentNode)
  inspect(c.childs[0].childs[0].data, content="hello")
  assert_patch_produces(
    @vdom.h("div", childs=[@vdom.comment("hello")]),
    @vdom.h("div", childs=[@vdom.text("hello")]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[@vdom.comment("old")]),
    @vdom.h("div", childs=[span_text("new")]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[span_text("old")]),
    @vdom.h("div", childs=[@vdom.comment("new")]),
  )
}

///|
test "index calculation with deep subtrees and mixed node types" {
  assert_patch_produces(
    @vdom.h("div", childs=[
      @vdom.h("div", childs=[
        @vdom.h("span", childs=[@vdom.h("b", childs=[@vdom.text("deep")])]),
      ]),
      div_text("leaf"),
      @vdom.h("div", childs=[@vdom.h("p", childs=[@vdom.text("shallow")])]),
    ]),
    @vdom.h("div", childs=[
      @vdom.h("div", childs=[
        @vdom.h("span", childs=[@vdom.h("b", childs=[@vdom.text("DEEP")])]),
      ]),
      div_text("LEAF"),
      @vdom.h("div", childs=[@vdom.h("p", childs=[@vdom.text("SHALLOW")])]),
    ]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[
      @vdom.text("text1"),
      @vdom.h("div", childs=[span_text("inner")]),
      @vdom.comment("comment1"),
      @vdom.h("p", childs=[@vdom.text("leaf")]),
    ]),
    @vdom.h("div", childs=[
      @vdom.text("TEXT1"),
      @vdom.h("div", childs=[span_text("INNER")]),
      @vdom.comment("COMMENT1"),
      @vdom.h("p", childs=[@vdom.text("LEAF")]),
    ]),
  )
}

///|
test "is_equal_to with different attr keys patches correctly" {
  let a = @vdom.h("div", attrs={ "foo": Str("1") })
  let b = @vdom.h("div", attrs={ "bar": Str("1") })
  assert_false(a.is_equal_to(b))
  assert_patch_produces(a, b)
}

///|
test "comment CRUD as children" {
  assert_patch_produces(
    @vdom.h("div", childs=[span_text("x")]),
    @vdom.h("div", childs=[span_text("x"), @vdom.comment("new")]),
  )
  let c = morphed(
    @vdom.h("div", childs=[span_text("x")]),
    @vdom.h("div", childs=[span_text("x"), @vdom.comment("new")]),
  )
  let root = c.childs[0]
  inspect(root.childs.length(), content="2")
  assert_true(root.childs[1].kind is CommentNode)
  inspect(root.childs[1].data, content="new")
  assert_patch_produces(
    @vdom.h("div", childs=[@vdom.comment("old")]),
    @vdom.h("div", childs=[@vdom.comment("new")]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[span_text("x"), @vdom.comment("bye")]),
    @vdom.h("div", childs=[span_text("x")]),
  )
}

///|
test "unchanged comment keeps its DOM reference" {
  let (c, o) = new_env()
  let r1 = @vdom.render(
    @vdom.h("div", childs=[@vdom.comment("same"), span_text("old")]),
    c,
    o,
  )
  let comment_ref = c.childs[0].childs[0]
  let _ = @vdom.render(
    @vdom.h("div", childs=[@vdom.comment("same"), span_text("new")]),
    c,
    o,
    prev=r1,
  )
  assert_true(physical_equal(c.childs[0].childs[0], comment_ref))
  inspect(comment_ref.data, content="same")
}

///|
test "key change and removal replace the element" {
  assert_patch_produces(
    @vdom.h("div", childs=[keyed_div("a", "text")]),
    @vdom.h("div", childs=[keyed_div("b", "text")]),
  )
  assert_patch_produces(
    @vdom.h("div", childs=[keyed_div("a", "text")]),
    @vdom.h("div", childs=[@vdom.h("div", childs=[@vdom.text("text")])]),
  )
}

///|
test "props change + children reorder on same element" {
  let left = @vdom.h("div", attrs={ "className": Str("old") }, childs=[
    keyed_div("a", "a"),
    keyed_div("b", "b"),
    keyed_div("c", "c"),
  ])
  let right = @vdom.h("div", attrs={ "className": Str("new") }, childs=[
    keyed_div("c", "c"),
    keyed_div("a", "a"),
    keyed_div("b", "b"),
  ])
  assert_patch_produces(left, right)
  let c = morphed(left, right)
  assert_true(c.childs[0].get_attribute("class") is Some("new"))
}

///|
test "comments mixed with keyed nodes" {
  assert_patch_produces(
    @vdom.h("div", childs=[
      @vdom.comment("separator"),
      keyed_div("a", "a"),
      @vdom.comment("middle"),
      keyed_div("b", "b"),
    ]),
    @vdom.h("div", childs=[
      @vdom.comment("separator"),
      keyed_div("b", "b"),
      @vdom.comment("middle"),
      keyed_div("a", "a"),
    ]),
  )
}
