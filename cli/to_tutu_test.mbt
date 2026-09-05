// `tutuca to-tutu`: the plan it makes, and what it refuses to write.

///|
test "to-tutu plans a conversion of the file it was given" {
  match @cli.plan(["to-tutu", "Counter.html", "--name", "Counter"]) {
    ToTutu(_, plan~) => {
      assert_eq(plan.path, "Counter.html")
      assert_eq(plan.name, "Counter")
      assert_eq(plan.target(), "Counter.tutu")
    }
    _ => fail("expected a to-tutu plan")
  }
}

///|
test "the target is the .html path with its extension changed" {
  match @cli.plan(["to-tutu", "a/b/Counter.html"]) {
    ToTutu(_, plan~) => assert_eq(plan.target(), "a/b/Counter.tutu")
    _ => fail("expected a to-tutu plan")
  }
  match @cli.plan(["to-tutu", "a.html", "-o", "elsewhere.tutu"]) {
    ToTutu(_, plan~) => assert_eq(plan.target(), "elsewhere.tutu")
    _ => fail("expected a to-tutu plan")
  }
}

///|
test "to-tutu with no file says what to pass" {
  match @cli.plan(["to-tutu"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("to-tutu requires an .html view file"))
    }
    _ => fail("expected a usage error")
  }
}

///|
/// A component is a TYPE, so its name is written as one. A lowercase `--name`
/// would produce a file whose first declaration is not one, and the error the
/// author read would be about the notation rather than about the flag.
test "a lowercase component name is refused, and names the spelling to use" {
  let emit = @cli.to_tutu_apply(
    { path: "counter.html", out: None, name: "counter", dry_run: true, },
    "",
  )
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("written `Counter`"))
}

///|
/// The refusal path: a construct the converter will not guess at stops the
/// write and says which one.
test "a construct with no spelling stops the write and names itself" {
  let html =
    #|<script type="tutuca/spec">
    #|  state Holder {
    #|    rows: Array[String]
    #|    provide { theme = .rows }
    #|  }
    #|</script>
    #|<template id="Holder"><div></div></template>
    #|
  let emit = @cli.to_tutu_apply(
    { path: "Holder.html", out: None, name: "Holder", dry_run: true, },
    html,
  )
  assert_eq(emit.exit_code, 1)
  assert_true(emit.err.contains("will not guess at"))
  assert_true(emit.err.contains("`provide`"))
}

///|
/// And the success path writes a file that `equiv` already agreed with.
test "a card converts and the check passes" {
  let html =
    #|<script type="tutuca/spec">
    #|  /// A number.
    #|  state Counter {
    #|    /// The current value.
    #|    count: Int
    #|  }
    #|</script>
    #|
    #|<script type="tutuca/script">
    #|  /// Add one.
    #|  receive inc {
    #|    .count += 1
    #|  }
    #|</script>
    #|
    #|<template id="Counter">
    #|  <div>
    #|    <button @on.click="inc">+</button>
    #|    <output @text=".count"></output>
    #|  </div>
    #|</template>
    #|
  let emit = @cli.to_tutu_apply(
    { path: "Counter.html", out: None, name: "Counter", dry_run: true, },
    html,
  )
  assert_eq(emit.err, "")
  assert_eq(emit.exit_code, 0)
  assert_true(emit.out.contains("receive inc:"))
  assert_true(emit.out.contains("@button(~on_click: inc){+}"))
}
