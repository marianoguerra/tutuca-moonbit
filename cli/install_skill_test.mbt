// install-skill pure-core behavior. The embedded asset list is generated
// (skill_assets_gen.mbt); these tests only rely on properties that hold in
// both states (empty placeholder or real embed).

///|
test "install-skill -h prints its help" {
  match @cli.plan(["install-skill", "-h"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 0)
      assert_true(emit.out.has_prefix("tutuca install-skill"))
      assert_true(emit.out.contains("--dry-run"))
    }
    _ => fail("expected Done")
  }
}

///|
test "install-skill rejects --user with --project" {
  match @cli.plan(["install-skill", "--user", "--project"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("mutually exclusive"))
    }
    _ => fail("expected Done")
  }
}

///|
test "install-skill rejects unknown flags" {
  match @cli.plan(["install-skill", "--wat"]) {
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("unknown flag '--wat'"))
    }
    _ => fail("expected Done")
  }
}

///|
test "install-skill either plans writes or reports missing assets" {
  // With the generated embed present this returns an InstallSkill plan whose
  // files are exactly the embedded ones; with the placeholder it errors with
  // the regeneration hint. Both are correct states of the machinery.
  match @cli.plan(["install-skill"]) {
    InstallSkill(_, plan~) => {
      assert_false(plan.user_scope)
      assert_false(plan.force)
      assert_eq(plan.target_rel, ".claude/skills/tutuca")
      assert_true(plan.files.length() > 0)
      // dry-run of the same install stays pure and lists every file
      match @cli.plan(["install-skill", "--dry-run"]) {
        Done(emit) => {
          assert_eq(emit.exit_code, 0)
          assert_true(
            emit.out.has_prefix(
              "would install tutuca skill → .claude/skills/tutuca\n",
            ),
          )
          for pair in plan.files {
            assert_true(emit.out.contains("  + \{pair.0}\n"))
          }
        }
        _ => fail("expected Done for --dry-run")
      }
      // --user + --dot-agents change the target
      match @cli.plan(["install-skill", "--user", "--dot-agents", "--force"]) {
        InstallSkill(_, plan~) => {
          assert_true(plan.user_scope)
          assert_true(plan.force)
          assert_eq(plan.target_rel, ".agents/skills/tutuca")
        }
        _ => fail("expected InstallSkill")
      }
    }
    Done(emit) => {
      assert_eq(emit.exit_code, 1)
      assert_true(emit.err.contains("no skill assets embedded"))
      assert_true(emit.err.contains("skill-embed"))
    }
    _ => fail("unexpected outcome")
  }
}
