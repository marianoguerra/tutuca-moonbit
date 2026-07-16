///|
test "send-receive: a message reaches a sibling child by path" {
  let h = @harness.mount_example(send_receive_module(), "Default")
  // the Status child starts empty, so @show="truthy? .message" hides it
  inspect(h.find_all(".alert").length(), content="0")
  h.type_into("input", "hello there")
  h.click(".send")
  // ctx.send_at_path(...field("status"), "flash", [text]) landed on the child
  inspect(h.text(".msg"), content="hello there")
  inspect(h.text(".alert"), content="hello there (flashed 1 times)")
  // ctx.send("clearDraft") landed on SELF
  inspect(h.value_of("input"), content="")
}

///|
test "send-receive: the receiver accumulates its own state across messages" {
  let h = @harness.mount_example(send_receive_module(), "Default")
  h.type_into("input", "one")
  h.key_down("input", "Enter") // @on.keydown+send="submit"
  h.type_into("input", "two")
  h.click(".send")
  inspect(h.text(".alert"), content="two (flashed 2 times)")
  // and a clear message empties it again
  h.click(".clear")
  inspect(h.find_all(".alert").length(), content="0")
}

///|
test "send-receive: an empty draft sends nothing" {
  let h = @harness.mount_example(send_receive_module(), "Default")
  h.type_into("input", "   ")
  h.click(".send")
  inspect(h.find_all(".alert").length(), content="0")
}

///|
test "tree: a component renders itself recursively" {
  let h = @harness.mount_example(tree_module(), "Default")
  // src > (components > button.js, card.js), index.js, README.md  = 6 nodes
  debug_inspect(
    h.texts(".head"),
    content=(
      #|["src", "components", "button.js", "card.js", "index.js", "README.md"]
    ),
  )
  // @if.class with a $'…{.type}' template drives the folder / file icons
  debug_inspect(
    h.attr(".head", "class", nth=0),
    content=(
      #|Some("head open type-dir")
    ),
  )
  debug_inspect(
    h.attr(".head", "class", nth=2),
    content=(
      #|Some("head open type-file")
    ),
  )
}

///|
test "tree: clicking a node toggles it AND bubbles up to the root" {
  let h = @harness.mount_example(tree_module(), "Default")
  inspect(h.find_all("li").length(), content="0")
  // click "components" (a dir): it collapses, hiding its two children
  h.click(".head", nth=1)
  debug_inspect(
    h.texts(".head"),
    content=(
      #|["src", "components", "index.js", "README.md"]
    ),
  )
  debug_inspect(
    h.attr(".head", "class", nth=1),
    content=(
      #|Some("head closed type-dir")
    ),
  )
  // ctx.bubble walked up to TreeRoot, which logged it
  debug_inspect(
    h.texts("li"),
    content=(
      #|["selected: components"]
    ),
  )
  // a file deeper in the tree bubbles too — most recent first
  h.click(".head", nth=2) // index.js
  debug_inspect(
    h.texts("li"),
    content=(
      #|["selected: index.js", "selected: components"]
    ),
  )
}

///|
test "tree: a collapsed dir hides its subtree, and reopening restores it" {
  let h = @harness.mount_example(tree_module(), "Default")
  h.click(".head", nth=0) // collapse the root "src"
  debug_inspect(
    h.texts(".head"),
    content=(
      #|["src"]
    ),
  )
  h.click(".head", nth=0) // reopen
  debug_inspect(
    h.texts(".head"),
    content=(
      #|["src", "components", "button.js", "card.js", "index.js", "README.md"]
    ),
  )
}
