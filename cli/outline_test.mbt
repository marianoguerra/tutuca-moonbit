// `tutuca outline`: the plan it makes, and the text it answers with.

///|
test "outline plans a read of the file it was given" {
  match @cli.plan(["outline", "card.tutu"]) {
    Outline(_, plan~) => {
      @debug.assert_eq(plan.path, "card.tutu")
      assert_false(plan.json)
    }
    _ => fail("expected an Outline outcome")
  }
}

///|
test "outline with no file says what to pass" {
  match @cli.plan(["outline"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("outline requires a .tutu file"))
    }
    _ => fail("expected a finished outcome")
  }
}

///|
test "the outline is one line per section, in file order" {
  let src =
    #|spec:
    #|  Todos ~root:
    #|    field draft :: String
    #|  struct Line(what :: String)
    #|
    #|view:
    #|  Todos:
    #|    @div{x}
    #|
  let emit = @cli.outline_apply({ path: "card.tutu", json: false, }, src)
  assert_eq(emit.exit_code, 0)
  inspect(
    emit.out,
    content=(
      #|card.tutu
      #|  spec      Todos ~root, struct Line
      #|  view      Todos
      #|
    ),
  )
}

///|
test "a file whose shape is wrong exits 1 and says why" {
  let src =
    #|script:
    #|  Todos:
    #|    receive add: it.draft := ""
    #|
  let emit = @cli.outline_apply({ path: "card.tutu", json: false, }, src)
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("there is no `script:` section"))
  assert_true(
    emit.err.contains(
      "write `logic:` — the section was renamed when it stopped living in a `<script>` tag",
    ),
  )
}
