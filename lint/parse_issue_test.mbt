// Port of the parse-issue lint cases from tutuca test/lint.test.js (the
// codes in scope: UNKNOWN_DIRECTIVE/X_OP/X_ATTR, BAD_VALUE,
// UNSUPPORTED_EXPR_SYNTAX, BINDING_MEMBER_TOO_DEEP, X_OP_IGNORES_CHILDREN,
// DEPRECATED_BARE_X_DIRECTIVE, MAYBE_ADD/DROP_AT_PREFIX). Where triggering a
// rule needs the value layer, the collector is fed the issue directly.

///|
fn lint_parse(html : String) -> Array[@lint.Finding] {
  let collector = @lint.LintCollector::new()
  let px = @anode.ParseContext::new(handler=collector)
  @anode.ANode::parse(html, px) |> ignore
  @lint.check_collected(collector)
}

///|
fn synthetic(issue : @anode.ParseIssue) -> Array[@lint.Finding] {
  let collector = @lint.LintCollector::new()
  collector.parse_issues.push((issue, Some("div")))
  @lint.check_collected(collector)
}

///|
test "unknown directive gets a did-you-mean" {
  let findings = lint_parse("<div @eahc=\".items\">x</div>")
  assert_eq(findings.length(), 1)
  let f = findings[0]
  assert_true(f.code is UnknownDirective && f.level is Error)
  assert_true(f.suggestion is Some(ReplaceName(from="eahc", to="each")))
}

///|
test "unknown x op gets a did-you-mean" {
  let findings = lint_parse("<x rendr=\".v\"></x>")
  guard findings[0] is { code: UnknownXOp, level: Error, suggestion, .. }
  assert_true(suggestion is Some(ReplaceName(from="rendr", to="render")))
}

///|
test "at-prefixed x op typo suggests dropping the prefix plus a hint" {
  let findings = lint_parse("<x @render-it></x>")
  assert_eq(findings.length(), 2)
  guard findings[0]
    is {
      code: UnknownXOp,
      level: Error,
      suggestion: Some(DropPrefix(from="@render-it", to="render-it")),
      ..,
    }
  guard findings[1] is { code: MaybeDropAtPrefix, level: Hint, .. }
}

///|
test "unknown x attr on render-it" {
  let findings = lint_parse("<x render-it nope=\"1\"></x>")
  guard findings[0] is { code: UnknownXAttr, level: Error, info, .. }
  assert_true(info.contains(("op", "render-it")))
  assert_true(info.contains(("name", "nope")))
}

///|
test "x op ignoring children warns with a remove suggestion" {
  let findings = lint_parse("<x render-it><p>meaningful</p></x>")
  guard findings[0] is { code: XOpIgnoresChildren, level: Warn, suggestion, .. }
  assert_true(suggestion is Some(Remove(what="the ignored children")))
}

///|
test "comments and whitespace children do not trigger ignores-children" {
  let findings = lint_parse("<x render-it>\n  <!-- note -->\n</x>")
  assert_eq(findings.length(), 0)
}

///|
test "bare host directive name hints at the @ prefix" {
  let findings = lint_parse("<div when=\"x\">hi</div>")
  guard findings[0]
    is {
      code: MaybeAddAtPrefix,
      level: Hint,
      suggestion: Some(AddPrefix(from="when", to="@when")),
      info,
      ..,
    }
  assert_true(info.contains(("tag", "div")))
}

///|
test "plain bad value stays BAD_VALUE" {
  let findings = synthetic(BadValue(role=Attr(name="class"), value="%a"))
  guard findings[0] is { code: BadValue, level: Error, suggestion: None, .. }
}

///|
test "ternary/comparison/logical/call/field-path classify as unsupported expr" {
  for
    pair in [
      (".x ? 'a' : 'b'", "ternary"),
      (".count == 42", "comparison"),
      (".a && .b", "logical"),
      ("$fn .arg", "call-with-args"),
      (".user.name", "field-path"),
    ] {
    let (value, expected) = pair
    let findings = synthetic(BadValue(role=Attr(name="class"), value~))
    guard findings[0] is { code: UnsupportedExprSyntax, level: Error, info, .. }
    assert_true(info.contains(("detected", expected)))
  }
}

///|
test "binding member too deep gets its own code" {
  let findings = synthetic(
    BadValue(role=Attr(name="title"), value="@item.user.name"),
  )
  guard findings[0]
    is { code: BindingMemberTooDeep, level: Error, suggestion, .. }
  assert_true(suggestion is Some(Rephrase(..)))
  // One level stays a plain bad value (it should not even fail to parse,
  // but the classifier must not fire on it).
  let one = synthetic(BadValue(role=Attr(name="title"), value="@item.user"))
  guard one[0] is { code: BadValue, .. }
}

///|
test "deprecated bare x directive warns with add-prefix" {
  let collector = @lint.LintCollector::new()
  collector.deprecations.push(
    (BareXDirective(op="render-each", name="when"), Some("x")),
  )
  let findings = @lint.check_collected(collector)
  guard findings[0]
    is {
      code: DeprecatedBareXDirective,
      level: Warn,
      suggestion: Some(AddPrefix(from="when", to="@when")),
      ..,
    }
}

///|
test "closest_name: case typo wins, distance capped at 2, exact is None" {
  @debug.assert_eq(
    @lint.closest_name("Render", ["render", "slot"]),
    Some("render"),
  )
  @debug.assert_eq(
    @lint.closest_name("rendr", ["render", "slot"]),
    Some("render"),
  )
  @debug.assert_eq(@lint.closest_name("zzzzz", ["render", "slot"]), None)
  @debug.assert_eq(@lint.closest_name("render", ["render"]), None)
  // adjacent transposition counts as one edit
  @debug.assert_eq(@lint.closest_name("redner", ["render"]), Some("render"))
}
