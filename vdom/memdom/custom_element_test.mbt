// Object/array-valued custom-element properties (JS
// test/vdom-custom-element.test.js). memdom has no custom-element registry
// or setters, so instead of counting setter calls these assert the stored
// property value across render and morph — `Data` always takes the property
// path, never setAttribute.

///|
fn ce_container() -> (MemNode, @vdom.RenderOpts[MemNode]) {
  let doc = document()
  let container = @vdom.DomNode::create_element(doc, "DIV", None, None)
  (container, @vdom.RenderOpts::new(doc))
}

///|
test "array prop is assigned as a property on initial render" {
  let (container, opts) = ce_container()
  let tree = @vdom.h("x-array-thing", attrs={
    "items": Data([1, 2, 3]),
    "class": Str("w"),
  })
  let _ = @vdom.render(tree, container, opts)
  guard container.first_child() is Some(el)
  assert_true(el.props.get("items") == Some(@vdom.AttrValue::Data([1, 2, 3])))
  // never serialized to an attribute
  assert_false(el.attrs.contains("items"))
  assert_true(el.attrs.get("class") == Some("w"))
}

///|
test "array prop update re-assigns the new array on morph" {
  let (container, opts) = ce_container()
  let prev = @vdom.render(
    @vdom.h("x-array-update", attrs={ "items": Data([1, 2]) }),
    container,
    opts,
  )
  let _ = @vdom.render(
    @vdom.h("x-array-update", attrs={ "items": Data([9, 8, 7]) }),
    container,
    opts,
    prev~,
  )
  guard container.first_child() is Some(el)
  assert_true(el.props.get("items") == Some(@vdom.AttrValue::Data([9, 8, 7])))
}

///|
test "object prop carries nested structure" {
  let (container, opts) = ce_container()
  let cfg : Json = { "a": 1, "b": { "nested": true } }
  let _ = @vdom.render(
    @vdom.h("x-object-thing", attrs={ "config": Data(cfg) }),
    container,
    opts,
  )
  guard container.first_child() is Some(el)
  assert_true(el.props.get("config") == Some(@vdom.AttrValue::Data(cfg)))
  assert_false(el.attrs.contains("config"))
}

///|
test "object prop update replaces the whole value; removal clears it" {
  let (container, opts) = ce_container()
  let prev = @vdom.render(
    @vdom.h("x-object-update", attrs={ "config": Data({ "a": 1 }) }),
    container,
    opts,
  )
  let prev2 = @vdom.render(
    @vdom.h("x-object-update", attrs={ "config": Data({ "b": 2 }) }),
    container,
    opts,
    prev~,
  )
  guard container.first_child() is Some(el)
  assert_true(el.props.get("config") == Some(@vdom.AttrValue::Data({ "b": 2 })))
  // dropping the prop on the next morph clears the property state
  let _ = @vdom.render(@vdom.h("x-object-update"), container, opts, prev=prev2)
  assert_true(el.props.get("config") == Some(@vdom.AttrValue::Str("")))
}

///|
test "equal-content Data does not dirty the diff (value semantics)" {
  // Divergence from JS documented on AttrValue::Data: diffing is by value,
  // so an equal-content new object produces no prop patch at all.
  let a : Map[String, @vdom.AttrValue] = { "items": Data([1, 2, 3]) }
  let b : Map[String, @vdom.AttrValue] = { "items": Data([1, 2, 3]) }
  assert_true(@vdom.diff_props(a, b) is None)
  let c : Map[String, @vdom.AttrValue] = { "items": Data([4]) }
  guard @vdom.diff_props(a, c) is Some(patch)
  assert_true(patch.get("items") == Some(Some(@vdom.AttrValue::Data([4]))))
}
