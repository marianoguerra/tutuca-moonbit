// Parse-issue lint cases (the
// codes in scope: UNKNOWN_DIRECTIVE/X_OP/X_ATTR, BAD_VALUE,
// UNSUPPORTED_EXPR_SYNTAX, BINDING_MEMBER_TOO_DEEP, X_OP_IGNORES_CHILDREN,
// MAYBE_ADD/DROP_AT_PREFIX). Where triggering a
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
  guard! findings[0] is { code: UnknownXOp, level: Error, suggestion, .. }
  assert_true(suggestion is Some(ReplaceName(from="rendr", to="render")))
}

///|
test "at-prefixed x op typo suggests dropping the prefix plus a hint" {
  let findings = lint_parse("<x @render-it></x>")
  assert_eq(findings.length(), 2)
  guard! findings[0]
    is {
      code: UnknownXOp,
      level: Error,
      suggestion: Some(DropPrefix(from="@render-it", to="render-it")),
      ..
    }
  guard! findings[1] is { code: MaybeDropAtPrefix, level: Hint, .. }
}

///|
test "unknown x attr on render-it" {
  let findings = lint_parse("<x render-it nope=\"1\"></x>")
  guard! findings[0] is { code: UnknownXAttr, level: Error, info, .. }
  assert_true(info.contains(("op", "render-it")))
  assert_true(info.contains(("name", "nope")))
}

///|
/// The name is spelled right; the PLACE is wrong. So: an error, no
/// did-you-mean, and a rewrite that names the spelling that works. The parser
/// drops the whole `<x>` rather than building a render site with the loop
/// silently missing — see anode/xops.mbt `is_loop_directive`.
test "an iteration directive on an <x> op is an error with a rewrite" {
  let findings = lint_parse("<x render-it @each=\".rows\"></x>")
  assert_eq(findings.length(), 1)
  guard! findings[0]
    is { code: LoopDirectiveOnXOp, level: Error, info, suggestion, .. }
  assert_true(info.contains(("op", "render-it")))
  assert_true(info.contains(("name", "@each")))
  assert_true(
    suggestion
    is Some(Rewrite(from="@each=\".rows\"", to="<x render-each=\".rows\">")),
  )
  assert_true(
    @lint.lint_code_name(findings[0].code) == "LOOP_DIRECTIVE_ON_X_OP",
  )
  assert_true(@lint.finding_message(findings[0]).contains("render-each"))
}

///|
/// `@each` names the sequence, so it can be rewritten. Its companions only
/// qualify a loop that is not here: the only advice is to move them.
test "a loop companion on an <x> op is told to move, not to rewrite" {
  let findings = lint_parse("<x render=\".v\" @when=\"$w\"></x>")
  assert_eq(findings.length(), 1)
  guard! findings[0]
    is { code: LoopDirectiveOnXOp, level: Error, suggestion, .. }
  assert_true(suggestion is Some(Remove(what="'@when'")))
  assert_true(@lint.finding_message(findings[0]).contains("only qualifies"))
}

///|
test "x op ignoring children warns with a remove suggestion" {
  let findings = lint_parse("<x render-it><p>meaningful</p></x>")
  guard! findings[0]
    is { code: XOpIgnoresChildren, level: Warn, suggestion, .. }
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
  guard! findings[0]
    is {
      code: MaybeAddAtPrefix,
      level: Hint,
      suggestion: Some(AddPrefix(from="when", to="@when")),
      info,
      ..
    }
  assert_true(info.contains(("tag", "div")))
}

///|
test "@bind is known and bare bind hints at the @ prefix" {
  assert_eq(lint_parse("<input @bind=\".name\">").length(), 0)
  let findings = lint_parse("<input bind=\".name\">")
  guard! findings[0]
    is {
      code: MaybeAddAtPrefix,
      level: Hint,
      suggestion: Some(AddPrefix(from="bind", to="@bind")),
      ..
    }
}

///|
test "plain bad value stays BAD_VALUE" {
  let findings = synthetic(BadValue(role=Attr(name="class"), value="%a"))
  guard! findings[0] is { code: BadValue, level: Error, suggestion: None, .. }
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
    guard! findings[0]
      is { code: UnsupportedExprSyntax, level: Error, info, .. }
    assert_true(info.contains(("detected", expected)))
  }
}

///|
test "binding member too deep gets its own code" {
  let findings = synthetic(
    BadValue(role=Attr(name="title"), value="@item.user.name"),
  )
  guard! findings[0]
    is { code: BindingMemberTooDeep, level: Error, suggestion, .. }
  assert_true(suggestion is Some(Rephrase(..)))
  // One level stays a plain bad value (it should not even fail to parse,
  // but the classifier must not fire on it).
  let one = synthetic(BadValue(role=Attr(name="title"), value="@item.user"))
  guard! one[0] is { code: BadValue, .. }
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

///|
/// The safe markup directives are KNOWN, which is the half of `known_directive_names`
/// that has no test of its own elsewhere: a name missing from that list is not a
/// silent no-op, it is a hard `UnknownDirective` error on a directive that works.
test "the safe markup directives are known directives" {
  assert_eq(lint_parse("<div @setinnerhtml=\".body\">x</div>").length(), 0)
  assert_eq(lint_parse("<svg @setinnersvg=\".chart\"></svg>").length(), 0)
  // And a typo of one reaches the did-you-mean, which only works because the
  // real name is in the list to be near.
  let findings = lint_parse("<div @setinnerhtm=\".body\">x</div>")
  assert_eq(findings.length(), 1)
  assert_true(
    findings[0].suggestion
    is Some(ReplaceName(from="setinnerhtm", to="setinnerhtml")),
  )
}
