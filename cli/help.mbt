// `tutuca help [command]`: port of tools/cli/commands/help.js run() +
// lintRulesText(). The overview text itself lives in help_overview.mbt
// (generated verbatim from the JS CLI output).

///|
fn run_help(mode : CliMode, target : String?, opts : GlobalOpts) -> Emit {
  match target {
    None => { out: overview(mode), err: "", exit_code: 0 }
    Some("help") =>
      {
        out: "help: Show usage. `help <command>` for per-command detail.\n",
        err: "",
        exit_code: 0,
      }
    Some(name) =>
      match find_command(mode, name) {
        // `help lint` in a stock binary explains what lint needs rather than
        // documenting a command this binary cannot run.
        None => unresolved_command(name, opts)
        Some(cmd) => {
          let buf = StringBuilder::new()
          buf.write_string("\{cmd.name}: \{cmd.describe}\n")
          if cmd.name == "lint" {
            buf.write_string(lint_rules_text())
          } else {
            buf.write_string(
              "Run `tutuca help` for the full reference including signatures and flags.\n",
            )
          }
          { out: buf.to_string(), err: "", exit_code: 0 }
        }
      }
  }
}

///|
/// Rules grouped by their `group` field in first-appearance order (JS
/// lintRulesByGroup uses Map insertion order).
fn lint_rules_by_group() -> Array[(String, Array[LintRule])] {
  let groups : Array[(String, Array[LintRule])] = []
  for rule in lint_rules {
    let mut found = false
    for pair in groups {
      if pair.0 == rule.group {
        pair.1.push(rule)
        found = true
        break
      }
    }
    if !found {
      groups.push((rule.group, [rule]))
    }
  }
  groups
}

///|
/// Human-readable dump of every component-linter code, grouped — appended to
/// `tutuca help lint`. Same data agent-context emits as `lintCodes`.
fn lint_rules_text() -> String {
  let mut code_width = 0
  for rule in lint_rules {
    if rule.code.length() > code_width {
      code_width = rule.code.length()
    }
  }
  let buf = StringBuilder::new()
  buf.write_string(
    "\nReports findings at levels error / warn / hint; exits 2 if ANY finding\n" +
    "is at error level. lint also runs an HTML structural linter that emits\n" +
    "HTML_* codes. Component-linter codes:\n",
  )
  for pair in lint_rules_by_group() {
    buf.write_string("\n\{pair.0}\n")
    for rule in pair.1 {
      buf.write_string(
        "  \{rule.code.pad_end(code_width, ' ')}  \{rule.level.pad_end(5, ' ')}  \{rule.summary}\n",
      )
    }
  }
  buf.to_string()
}
