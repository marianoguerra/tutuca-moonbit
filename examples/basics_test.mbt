///|
test "minimum-viable-component: renders nothing, but mounts" {
  let h = @harness.mount(minimum_viable_module(), "MinimumViableComponent")
  inspect(h.text("div"), content="")
}

///|
test "static-view-component: renders its static view" {
  let h = @harness.mount(static_view_module(), "StaticViewComponent")
  inspect(h.text("p"), content="Hello, world!")
}

///|
test "text-directive: renders fields, a method call, and every value type" {
  let h = @harness.mount(text_directive_module(), "TextDirective")
  inspect(h.text(".v-str"), content="hello")
  // @text PREPENDS: the element's own children survive
  inspect(h.text(".v-num"), content="42 <- text directive is prepended")
  // a null value renders NOTHING (JS drops null children in vdom addChild)
  inspect(h.text(".v-notset"), content="")
  inspect(h.text(".v-method"), content="HELLO")
  // <x text=".bool"> is a bare text node — no element of its own
  inspect(h.html().contains("true"), content="true")
}

///|
test "text-directive: custom values" {
  let h = @harness.mount(text_directive_module(), "TextDirective", args={
    "str": Str("tutuca"),
    "num": Num(100),
    "bool": Bool(false),
  })
  inspect(h.text(".v-str"), content="tutuca")
  inspect(h.text(".v-method"), content="TUTUCA")
  inspect(h.html().contains("false"), content="true")
}

///|
test "danger-set-inner-html: raw markup lands as real elements" {
  let h = @harness.mount(danger_set_inner_html_module(), "DangerSetInnerHtml")
  inspect(
    h.find(".raw").to_html(),
    content=(
      #|<div class="raw"><strong><em>Raw HTML!</em></strong></div>
    ),
  )
}

///|
test "danger-set-inner-html: custom markup" {
  let h = @harness.mount(danger_set_inner_html_module(), "DangerSetInnerHtml", args={
    "content": Str("<h3>Title</h3><ul><li>One</li><li>Two</li></ul>"),
  })
  inspect(
    h.find(".raw").to_html(),
    content=(
      #|<div class="raw"><h3>Title</h3><ul><li>One</li><li>Two</li></ul></div>
    ),
  )
}
