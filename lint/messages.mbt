// Human messages for lint findings — the render side of the linter, so
// callers (the CLI, the view generator) do not each reinvent the wording.
// Moved here from cli/ so the lint package renders its own findings.
// Also holds the LintCode → canonical rule-code mapping. The
// structural/parse findings arrive as Finding (info pairs); the
// component checker (lint_component.mbt) builds its messages at report time
// with the same wording.

///|
/// Canonical SCREAMING_SNAKE rule code for a LintCode — the names the
/// rule catalog (lint_rules.mbt), agent-context and the CLI use.
pub fn lint_code_name(code : LintCode) -> String {
  match code {
    UnknownDirective => "UNKNOWN_DIRECTIVE"
    UnknownXOp => "UNKNOWN_X_OP"
    UnknownXAttr => "UNKNOWN_X_ATTR"
    BadValue => "BAD_VALUE"
    UnsupportedExprSyntax => "UNSUPPORTED_EXPR_SYNTAX"
    BindingMemberTooDeep => "BINDING_MEMBER_TOO_DEEP"
    XOpIgnoresChildren => "X_OP_IGNORES_CHILDREN"
    MaybeAddAtPrefix => "MAYBE_ADD_AT_PREFIX"
    MaybeDropAtPrefix => "MAYBE_DROP_AT_PREFIX"
    UndeclaredMethod => "UNDECLARED_METHOD"
    ProvideNotAddressable => "PROVIDE_NOT_ADDRESSABLE"
    ProvideTypeBadShape => "PROVIDE_TYPE_BAD_SHAPE"
    ProvideNameCollision => "PROVIDE_NAME_COLLISION"
    LookupNoProvider => "LOOKUP_NO_PROVIDER"
    UnknownComponentName => "UNKNOWN_COMPONENT_NAME"
    EventPathUnsafeStep => "EVENT_PATH_UNSAFE_STEP"
    InertConstraint => "INERT_CONSTRAINT"
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
/// JSON-quote a value the way JSON.stringify does.
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
fn location_suffix(loc : Location?) -> String {
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
/// Human message for a structural/parse Finding (for the codes the lint
/// package emits).
pub fn finding_message(f : Finding) -> String {
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
    ProvideNotAddressable => {
      let comp = info_or(info, "comp", "?")
      "'\{comp}' provides '\{name}' as \{value}, which is not addressable — a provide doubles as the path `<x render=\"*\{name}\">` teleports through, so it must be a field (`.f`) or a seq access (`.s[.k]`); this one is dropped and `*\{name}` resolves to nothing"
    }
    ProvideTypeBadShape => {
      let comp = info_or(info, "comp", "?")
      "'\{comp}' provides the TYPE '\{name}' as \{value}: an uppercase name publishes a component, and `\"self\"` is the only thing one can be — which is what makes a published type a component by construction rather than by trusting an expression"
    }
    ProvideNameCollision => {
      let comp = info_or(info, "comp", "?")
      let other = info_or(info, "other", "?")
      "'\{comp}' and '\{other}' both provide '\{name}' in one scope chain, and a lookup names what it WANTS rather than who provides it — so which one a consumer reaches, and which one an edit through `*\{name}` lands on, is not decidable; rename one"
    }
    LookupNoProvider => {
      let comp = info_or(info, "comp", "?")
      let has_default = info_or(info, "hasDefault", "false") == "true"
      let head = "'\{comp}' looks up '\{name}', and nothing in its scope chain provides that name"
      if has_default {
        head +
        " — the declared default is what every read will get, unless a provider that is not registered here renders above it"
      } else {
        head + ", and it declares no default, so `*\{name}` is always nothing"
      }
    }
    UnknownComponentName => {
      let comp = info_or(info, "comp", "?")
      let closest = info_or(info, "closest", "")
      let hint = if closest == "" {
        ""
      } else {
        " — did you mean '\{closest}'?"
      }
      "'\{comp}' looks up the component type '\{name}', and nothing is registered under that name in its scope" +
      hint
    }
    UndeclaredMethod => {
      let closest = info_or(info, "closest", "")
      let hint = if closest == "" {
        ""
      } else {
        " — did you mean '$\{closest}'?"
      }
      "'$\{name}' is not a method this component declares, so it evaluates to nothing and the attribute or directive reading it is dropped silently; add it to the component's declared methods" +
      hint
    }
    // The manifest's constraint record spells "unstated" two ways — `null` for
    // the four bounds, `""` for the strings beside them — so a guest that
    // writes the record out in full states bounds it did not mean. The zeros
    // are the ones that bite: `"maxLen": 0` forbids every value, and the form
    // then refuses the whole submission including the fields that were fine.
    InertConstraint => {
      let key = info_or(info, "key", "")
      let kind = info_or(info, "kind", "")
      "'\{key}' says nothing about '\{name}', which is \{kind} — it is ignored when validating and dropped from the generated schema; the manifest spells an unstated bound as `null` or by leaving the key out, so a 0 written to fill the record in is a bound nobody meant"
    }
    BadValue => bad_value_message(info) + tags
    UnsupportedExprSyntax => unsupported_expr_message(info) + tags
    EventPathUnsafeStep => {
      let path = info_or(info, "path", "?")
      let step = info_or(info, "step", "?")
      "Event path '\{path}' traverses '\{step}', which is off the event-path allowlist — it resolves in an app's own views, but a host compiling guest-supplied views refuses the bundle over it; keep paths to target/currentTarget/relatedTarget/detail/dataset/dataTransfer and ask the host for anything beyond" +
      tags
    }
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
