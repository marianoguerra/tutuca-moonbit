// Human messages for lint findings (port of tools/format/lint.js
// lintIdToMessage) plus the LintCode → canonical rule-code mapping. The
// structural/parse findings arrive as @lint.Finding (info pairs); the
// component checker (lint_component.mbt) builds its messages at report time
// with the same wording.

///|
/// Canonical SCREAMING_SNAKE rule code for a @lint.LintCode — the names the
/// rule catalog (lint_rules.mbt), agent-context and the JS CLI use.
pub fn lint_code_name(code : @lint.LintCode) -> String {
  match code {
    UnknownDirective => "UNKNOWN_DIRECTIVE"
    UnknownXOp => "UNKNOWN_X_OP"
    UnknownXAttr => "UNKNOWN_X_ATTR"
    BadValue => "BAD_VALUE"
    UnsupportedExprSyntax => "UNSUPPORTED_EXPR_SYNTAX"
    BindingMemberTooDeep => "BINDING_MEMBER_TOO_DEEP"
    XOpIgnoresChildren => "X_OP_IGNORES_CHILDREN"
    DeprecatedBareXDirective => "DEPRECATED_BARE_X_DIRECTIVE"
    MaybeAddAtPrefix => "MAYBE_ADD_AT_PREFIX"
    MaybeDropAtPrefix => "MAYBE_DROP_AT_PREFIX"
    HtmlTagNameHasUppercase => "HTML_TAG_NAME_HAS_UPPERCASE"
    HtmlSvgTagWillLowercase => "HTML_SVG_TAG_WILL_LOWERCASE"
    HtmlSvgAttrWillLowercase => "HTML_SVG_ATTR_WILL_LOWERCASE"
    HtmlMathmlAttrWillLowercase => "HTML_MATHML_ATTR_WILL_LOWERCASE"
    HtmlTagNotAllowedInParent => "HTML_TAG_NOT_ALLOWED_IN_PARENT"
    HtmlTextNotAllowedInParent => "HTML_TEXT_NOT_ALLOWED_IN_PARENT"
    HtmlVoidElementHasCloseTag => "HTML_VOID_ELEMENT_HAS_CLOSE_TAG"
    HtmlDuplicateForm => "HTML_DUPLICATE_FORM"
    HtmlNestedInteractive => "HTML_NESTED_INTERACTIVE"
    HtmlMisnestedFormatting => "HTML_MISNESTED_FORMATTING"
    HtmlUnexpectedEndTag => "HTML_UNEXPECTED_END_TAG"
    HtmlDuplicateAttribute => "HTML_DUPLICATE_ATTRIBUTE"
    HtmlAttributesOnEndTag => "HTML_ATTRIBUTES_ON_END_TAG"
    HtmlSelfClosingEndTag => "HTML_SELF_CLOSING_END_TAG"
    HtmlMissingAttributeValue => "HTML_MISSING_ATTRIBUTE_VALUE"
    HtmlCdataInHtmlNamespace => "HTML_CDATA_IN_HTML_NAMESPACE"
    HtmlBogusComment => "HTML_BOGUS_COMMENT"
    HtmlUnclosedBeforeEnd => "HTML_UNCLOSED_BEFORE_END"
  }
}

///|
fn info_get(info : Array[(String, String)], key : String) -> String? {
  for pair in info {
    if pair.0 == key {
      return Some(pair.1)
    }
  }
  None
}

///|
fn info_or(
  info : Array[(String, String)],
  key : String,
  dflt : String,
) -> String {
  info_get(info, key).unwrap_or(dflt)
}

///|
/// JSON-quote a value the way the JS formatter does (JSON.stringify).
fn q(s : String) -> String {
  s.to_json().stringify()
}

///|
/// " on <tag>" unless the tag is missing or the phantom `x` host.
fn tag_suffix(info : Array[(String, String)]) -> String {
  match info_get(info, "tag") {
    Some(t) => {
      let low = t.to_lower()
      if low == "x" {
        ""
      } else {
        " on <\{low}>"
      }
    }
    None => ""
  }
}

///|
fn location_suffix(loc : @lint.Location?) -> String {
  match loc {
    Some(l) => " at line \{l.line}, col \{l.column}"
    None => ""
  }
}

///|
/// tools/format/lint.js badValueMessage: role-specific phrasing.
fn bad_value_message(info : Array[(String, String)]) -> String {
  let v = q(info_or(info, "value", ""))
  let attr = info_or(info, "attr", "?")
  let directive = info_or(info, "directive", "?")
  let op = info_or(info, "op", "?")
  match info_or(info, "role", "") {
    "attr" => "Cannot parse value \{v} for attribute ':\{attr}'"
    "directive" => "Cannot parse value \{v} for directive '@\{directive}'"
    "if" => "Cannot parse condition \{v} for '@if.\{attr}'"
    "x-op" => "Cannot parse value \{v} for <x \{op}>"
    _ => "Cannot parse value \{v}"
  }
}

///|
fn unsupported_expr_label(detected : String) -> String {
  match detected {
    "ternary" => "ternary expression"
    "comparison" => "comparison"
    "logical" => "logical expression"
    "call-with-args" => "method call with arguments"
    "field-path" => "dotted field path"
    _ => "expression"
  }
}

///|
fn unsupported_expr_message(info : Array[(String, String)]) -> String {
  let v = q(info_or(info, "value", ""))
  let label = unsupported_expr_label(info_or(info, "detected", ""))
  let attr = info_or(info, "attr", "?")
  let directive = info_or(info, "directive", "?")
  let op = info_or(info, "op", "?")
  match info_or(info, "role", "") {
    "attr" => "Unsupported \{label} \{v} in dynamic attribute ':\{attr}'"
    "directive" => "Unsupported \{label} \{v} in directive '@\{directive}'"
    "if" => "Unsupported \{label} \{v} in '@if.\{attr}' condition"
    "x-op" => "Unsupported \{label} \{v} in <x \{op}>"
    _ => "Unsupported \{label} \{v}"
  }
}

///|
fn html_action_phrase(action : String, tag : String, parent : String) -> String {
  match action {
    "ignored" | "drop" => "the parser will drop this <\{tag}>"
    "auto-close-implicit" =>
      "the parser will close <\{parent}> first, then place <\{tag}> as a sibling"
    "foster-parent" =>
      "the parser will move <\{tag}> outside <\{parent}> (foster-parenting)"
    "foreign-breakout" =>
      "the parser will exit foreign content and re-process <\{tag}> in HTML mode"
    _ => "parser action: \{action}"
  }
}

///|
/// Human message for a structural/parse @lint.Finding (port of
/// lintIdToMessage for the codes the lint package emits).
pub fn finding_message(f : @lint.Finding) -> String {
  let info = f.info
  let loc = location_suffix(f.location)
  let tags = tag_suffix(info)
  let name = info_or(info, "name", "?")
  let value = q(info_or(info, "value", ""))
  let op = info_or(info, "op", "?")
  let tag = info_or(info, "tag", "?")
  let raw = info_or(info, "raw", "?")
  match f.code {
    UnknownDirective => "Unknown directive '@\{name}=\{value}'" + tags
    UnknownXOp => "Unknown <x> op '\{name}=\{value}'" + tags
    UnknownXAttr => "Unknown attribute '\{name}=\{value}' on <x \{op}>" + tags
    XOpIgnoresChildren =>
      "<x \{op}> has child content, but the '\{op}' op ignores its children — they are silently dropped when the template is parsed; remove them" +
      tags
    MaybeDropAtPrefix => {
      let written = match info_get(info, "value") {
        Some(v) => "\{name}=\{q(v)}"
        None => name
      }
      "'\{written}' on <x> looks like a directive but is actually an x op/attr written with a leading '@'"
    }
    MaybeAddAtPrefix => {
      let low = info_or(info, "tag", "").to_lower()
      "'\{name}' on <\{low}> is a plain attribute, but '@\{name}' is a directive — add the leading '@'"
    }
    DeprecatedBareXDirective =>
      "'\{name}' on <x \{op}> is deprecated — write '@\{name}' instead" + tags
    BadValue => bad_value_message(info) + tags
    UnsupportedExprSyntax => unsupported_expr_message(info) + tags
    BindingMemberTooDeep =>
      "Binding member read \{value} goes more than one level deep — only one member is allowed (like '@value.title')" +
      tags
    HtmlTagNameHasUppercase => {
      let lowercased = info_or(info, "lowercased", "?")
      "Tag <\{raw}> will be lowercased to <\{lowercased}>" + loc
    }
    HtmlSvgTagWillLowercase => {
      let lowercased = info_or(info, "lowercased", "?")
      "SVG tag <\{raw}> is not in the WHATWG case-correction list — will be lowercased to <\{lowercased}>" +
      loc
    }
    HtmlSvgAttrWillLowercase => {
      let canonical = info_or(info, "canonical", "?")
      "SVG attribute '\{raw}' will be rewritten to '\{canonical}'" + loc
    }
    HtmlMathmlAttrWillLowercase => {
      let canonical = info_or(info, "canonical", "?")
      "MathML attribute '\{raw}' will be rewritten to '\{canonical}'" + loc
    }
    HtmlTagNotAllowedInParent => {
      let parent = info_or(info, "parent", "?")
      let mode = info_or(info, "mode", "?")
      let action = html_action_phrase(info_or(info, "action", "?"), tag, parent)
      "<\{tag}> not allowed under <\{parent}> in \{mode} — \{action}" + loc
    }
    HtmlTextNotAllowedInParent => {
      let mode = info_or(info, "mode", "?")
      let snippet = q(info_or(info, "snippet", ""))
      "Non-whitespace text not allowed in \{mode}: \{snippet}" + loc
    }
    HtmlVoidElementHasCloseTag =>
      "Void element <\{tag}> has an explicit close tag" + loc
    HtmlDuplicateForm =>
      "Nested <form> — the inner form will be dropped by the parser" + loc
    HtmlNestedInteractive =>
      "<\{tag}> nested inside another <\{tag}> — adoption agency will reorder" +
      loc
    HtmlMisnestedFormatting =>
      "Misnested formatting tag </\{tag}> — adoption agency will reorder nodes" +
      loc
    HtmlUnexpectedEndTag => "Unexpected end tag </\{tag}>" + loc
    HtmlUnclosedBeforeEnd => {
      let unclosed = info_or(info, "unclosed", "?")
      "<\{unclosed}> still open when </\{tag}> was seen — implicitly closed" +
      loc
    }
    HtmlDuplicateAttribute =>
      "Duplicate attribute '\{name}' — second occurrence dropped" + loc
    HtmlAttributesOnEndTag =>
      "Attributes on end tag </\{tag}> — dropped by the parser" + loc
    HtmlSelfClosingEndTag =>
      "Self-closing end tag </\{tag}/> — trailing '/' is meaningless" + loc
    HtmlMissingAttributeValue => "Attribute '\{name}' is missing a value" + loc
    HtmlCdataInHtmlNamespace =>
      "CDATA section in HTML namespace — reinterpreted as a bogus comment" +
      loc
    HtmlBogusComment => "Bogus comment — content dropped by the parser" + loc
  }
}
