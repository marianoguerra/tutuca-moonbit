// The lint-errors module is the semantic linter's intentional-error fixture:
// every applicable rule code must actually fire on it (the JS example's
// "check the Lint tab" demo, asserted headlessly).

///|
test "lint-errors: every intentional finding fires" {
  let m = lint_errors_module()
  let _ = m.build_scope()
  let all : Array[String] = []
  for comp in m.components {
    for f in @cli.check_component(comp) {
      all.push(f.code)
    }
  }
  let expected = [
    // component-model rules (LintDemo)
    //
    // Typed-state note: `update` is one opaque pattern match, so the linter
    // can't enumerate input-handler names any more —
    // INPUT_HANDLER_NOT_REFERENCED and INPUT_HANDLER_FOR_INPUT_HANDLER_METHOD
    // are catalog-only (no enforcement site) and no longer expected. In
    // exchange, LintDemo has no `update` fn at all, which makes bare-name
    // references checkable: the unimplemented `doKeyDown` ones now fire
    // INPUT_HANDLER_NOT_IMPLEMENTED.
    "RENDER_IT_OUTSIDE_OF_LOOP", "UNKNOWN_EVENT_MODIFIER", "UNKNOWN_HANDLER_ARG_NAME",
    "INPUT_HANDLER_METHOD_FOR_INPUT_HANDLER", "INPUT_HANDLER_METHOD_NOT_IMPLEMENTED",
    "INPUT_HANDLER_NOT_IMPLEMENTED", "FIELD_VAL_NOT_DEFINED", "FIELD_VAL_IS_METHOD",
    "METHOD_VAL_IS_FIELD", "METHOD_VAL_NOT_DEFINED", "DYN_VAL_NOT_DEFINED", "UNKNOWN_COMPONENT_NAME",
    "ALT_HANDLER_NOT_DEFINED", "ALT_HANDLER_NOT_REFERENCED", "DYN_ALIAS_NOT_REFERENCED",
    "PROVIDE_NOT_ADDRESSABLE", "LOOKUP_TARGET_MALFORMED", "UNKNOWN_MACRO_ARG", "UNKNOWN_DIRECTIVE",
    "UNKNOWN_X_OP", "UNKNOWN_X_ATTR", "X_OP_IGNORES_CHILDREN", "DEPRECATED_BARE_X_DIRECTIVE",
    "MAYBE_DROP_AT_PREFIX", "MAYBE_ADD_AT_PREFIX", "BAD_VALUE", "BINDING_MEMBER_TOO_DEEP",
    "UNSUPPORTED_EXPR_SYNTAX", "REDUNDANT_TEMPLATE_STRING", "PLACEHOLDERLESS_TEMPLATE_STRING",
    "CONSTANT_CONDITION", "DUPLICATE_ATTR_DEFINITION", "IF_NO_BRANCH_SET",
    // scoped-style rules (ScopedStyleDemo)
     "TOP_LEVEL_AT_RULE_IN_SCOPED_STYLE", "GLOBAL_SELECTOR_IN_SCOPED_STYLE",
    // structural HTML rules (HtmlLintDemo)
     "HTML_TAG_NAME_HAS_UPPERCASE", "HTML_SVG_TAG_WILL_LOWERCASE", "HTML_TAG_NOT_ALLOWED_IN_PARENT",
    "HTML_TEXT_NOT_ALLOWED_IN_PARENT", "HTML_VOID_ELEMENT_HAS_CLOSE_TAG", "HTML_DUPLICATE_FORM",
    "HTML_NESTED_INTERACTIVE", "HTML_MISNESTED_FORMATTING", "HTML_UNEXPECTED_END_TAG",
    "HTML_UNCLOSED_BEFORE_END", "HTML_DUPLICATE_ATTRIBUTE", "HTML_ATTRIBUTES_ON_END_TAG",
    "HTML_SELF_CLOSING_END_TAG", "HTML_MISSING_ATTRIBUTE_VALUE", "HTML_CDATA_IN_HTML_NAMESPACE",
    "HTML_BOGUS_COMMENT", "HTML_SVG_ATTR_WILL_LOWERCASE", "HTML_MATHML_ATTR_WILL_LOWERCASE",
  ]
  let missing = expected.filter(code => !all.contains(code))
  if !missing.is_empty() {
    fail("expected lint codes did not fire: \{missing.join(", ")}")
  }
}
