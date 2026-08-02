// new-guest pure-core behavior. Like install_skill_test.mbt, these rely only
// on properties that hold whether the embedded template is the real tree or an
// empty placeholder — `check-guest-template` is what proves the real one
// compiles.

///|
test "new-guest -h prints its help" {
  match @cli.plan(["new-guest", "-h"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 0)
      assert_true(emit.out.has_prefix("tutuca new-guest"))
      assert_true(emit.out.contains("--dry-run"))
      // the naming rule is the thing people get wrong; the help must state it
      assert_true(emit.out.contains("kebab-case"))
    }
    _ => fail("expected Done")
  }
}

///|
test "new-guest needs a name" {
  match @cli.plan(["new-guest"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("needs a name"))
    }
    _ => fail("expected Done")
  }
}

///|
test "new-guest rejects unknown flags" {
  match @cli.plan(["new-guest", "clock", "--wat"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("unknown flag"))
    }
    _ => fail("expected Done")
  }
}

///|
test "new-guest rejects a second name" {
  match @cli.plan(["new-guest", "clock", "timer"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("one name"))
    }
    _ => fail("expected Done")
  }
}

///|
test "new-guest rejects --dir with no path" {
  match @cli.plan(["new-guest", "clock", "--dir"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("--dir needs a path"))
    }
    _ => fail("expected Done")
  }
}

///|
/// Every rejected shape, and why each would break something downstream: an
/// uppercase or underscored name is not a directory convention, a leading digit
/// is not a MoonBit identifier, and a trailing or doubled dash makes an empty
/// word for pascal_case to capitalize.
test "new-guest rejects names that cannot be a dir, a bundle and an ident" {
  for
    bad in [
      "Clock", "1clock", "my_clock", "clock-", "cl--ock", "clock!",
      // `smoke_test.mbt` is a MoonBit TEST file, so the author's dyn_module would
      // land in test scope and the bundle would declare nothing — a warning, not
      // an error, and therefore shippable. Caught here instead.
       "smoke-test", "x-wbtest",
    ] {
    match @cli.plan(["new-guest", bad]) {
      Done(emit) => {
        assert_eq(emit.exit_code, 1)
        assert_true(emit.err.contains("not a usable guest name"))
      }
      _ => fail("expected Done for '\{bad}'")
    }
  }
}

///|
test "guest_name_check accepts the kebab shapes" {
  assert_true(@cli.guest_name_check("clock") is None)
  assert_true(@cli.guest_name_check("temp-conv") is None)
  assert_true(@cli.guest_name_check("a1-b2-c3") is None)
  assert_true(@cli.guest_name_check("") is Some(_))
}

///|
test "a kebab name becomes a type name and an identifier" {
  assert_eq(@cli.pascal_case("clock"), "Clock")
  assert_eq(@cli.pascal_case("temp-conv"), "TempConv")
  assert_eq(@cli.pascal_case("a-b-c"), "ABC")
  assert_eq(@cli.snake_case("temp-conv"), "temp_conv")
  assert_eq(@cli.snake_case("clock"), "clock")
}

///|
/// `{{name}}` is a prefix of nothing else, but `{{name_ident}}` starts with the
/// same six characters — substituting the short one first would leave
/// `temp-conv_ident}}` behind. Longest first is the rule, and this is the test
/// that fails if someone reorders it.
test "substitution takes the longest placeholder first" {
  assert_eq(
    @cli.substitute_guest_name("{{name_ident}}|{{Name}}|{{name}}", "temp-conv"),
    "temp_conv|TempConv|temp-conv",
  )
}

///|
test "new-guest either plans writes or reports a missing template" {
  match @cli.plan(["new-guest", "clock"]) {
    NewGuest(_, plan~) => {
      assert_eq(plan.dir, "clock")
      assert_eq(plan.name, "clock")
      assert_false(plan.force)
      assert_false(plan.files.is_empty())
      // the three files that make it a guest rather than a directory
      let paths = plan.files.map(fn(p) { p.0 })
      assert_true(paths.contains("wit/tutuca-component.wit"))
      assert_true(
        paths.contains("gen/interface/tutuca/component/guest/sdk.mbt"),
      )
      assert_true(
        paths.contains("gen/interface/tutuca/component/guest/clock.mbt"),
      )
      // nothing of the guest it was derived from leaks through
      for path in paths {
        assert_false(path.contains("counter"))
      }
      // and no placeholder survives, in a path or in a byte
      for pair in plan.files {
        assert_false(pair.0.contains("{{"))
        assert_false(pair.1.contains("{{"))
      }
      // --dir moves the target and nothing else
      match @cli.plan(["new-guest", "clock", "--dir", "out/x", "--force"]) {
        NewGuest(_, plan~) => {
          assert_eq(plan.dir, "out/x")
          assert_eq(plan.name, "clock")
          assert_true(plan.force)
        }
        _ => fail("expected NewGuest")
      }
      // --dry-run decides everything purely and writes nothing
      match @cli.plan(["new-guest", "clock", "--dry-run"]) {
        Done(emit) => {
          assert_eq(emit.exit_code, 0)
          assert_true(emit.out.contains("would scaffold guest 'clock'"))
          assert_true(emit.out.contains("wit/tutuca-component.wit"))
        }
        _ => fail("expected Done for --dry-run")
      }
    }
    Done(emit) => {
      // no embed in this build: the only acceptable failure, and it has to say
      // how to fix itself
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("ERR_GUEST_TEMPLATE_MISSING"))
      assert_true(emit.err.contains("guest-template-embed"))
    }
    _ => fail("expected NewGuest or Done")
  }
}
