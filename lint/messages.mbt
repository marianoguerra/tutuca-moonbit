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
pub fn code_name(code : LintCode) -> String {
  match code {
    UnknownDirective => "UNKNOWN_DIRECTIVE"
    UnknownXOp => "UNKNOWN_X_OP"
    UnknownXAttr => "UNKNOWN_X_ATTR"
    LoopDirectiveOnXOp => "LOOP_DIRECTIVE_ON_X_OP"
    BadValue => "BAD_VALUE"
    UnsupportedExprSyntax => "UNSUPPORTED_EXPR_SYNTAX"
    BindingMemberTooDeep => "BINDING_MEMBER_TOO_DEEP"
    XOpIgnoresChildren => "X_OP_IGNORES_CHILDREN"
    UndeclaredMethod => "UNDECLARED_METHOD"
    ProvideNotAddressable => "PROVIDE_NOT_ADDRESSABLE"
    ProvideTypeBadShape => "PROVIDE_TYPE_BAD_SHAPE"
    LookupNoProvider => "LOOKUP_NO_PROVIDER"
    UnknownComponentName => "UNKNOWN_COMPONENT_NAME"
    MethodInEventPosition => "METHOD_IN_EVENT"
    EventPathUnsafeStep => "EVENT_PATH_UNSAFE_STEP"
    InertConstraint => "INERT_CONSTRAINT"
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
/// Human message for a structural/parse Finding (for the codes the lint
/// package emits).
pub fn finding_message(f : Finding) -> String {
  let info = f.info
  let tags = tag_suffix(info)
  let name = info_or(info, "name", "?")
  let value = q(info_or(info, "value", ""))
  let op = info_or(info, "op", "?")
  match f.code {
    UnknownDirective => "Unknown directive '@\{name}=\{value}'" + tags
    UnknownXOp => "Unknown <x> op '\{name}=\{value}'" + tags
    UnknownXAttr => "Unknown attribute '\{name}=\{value}' on <x \{op}>" + tags
    // `@each` names the sequence, so it can be rewritten; its companions only
    // qualify a loop that is not here, so they can only be moved.
    LoopDirectiveOnXOp =>
      (if name == "@each" {
        "'\{name}=\{value}' describes an iteration, but <x \{op}> is a single render site with no body to iterate — the whole <x> is dropped; write <x render-each=\{value}>, or put @each on a wrapper element around the <x>"
      } else {
        "'\{name}=\{value}' only qualifies an iteration, and <x \{op}> is not one — the whole <x> is dropped; move it to the @each (or <x render-each>) it belongs to"
      }) +
      tags
    XOpIgnoresChildren =>
      "<x \{op}> has child content, but the '\{op}' op ignores its children — they are silently dropped when the template is parsed; remove them" +
      tags
    ProvideNotAddressable => {
      let comp = info_or(info, "comp", "?")
      "'\{comp}' provides '\{name}' as \{value}, which is not addressable — a provide doubles as the path `<x render=\"*\{name}\">` resumes at, so it must be a field (`.f`) or a seq access (`.s[.k]`); this one is dropped and `*\{name}` resolves to nothing"
    }
    ProvideTypeBadShape => {
      let comp = info_or(info, "comp", "?")
      "'\{comp}' provides the TYPE '\{name}' as \{value}: an uppercase name publishes a component, and `\"self\"` is the only thing one can be — which is what makes a published type a component by construction rather than by trusting an expression"
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
    MethodInEventPosition => {
      let comp = info_or(info, "comp", "?")
      let site = info_or(info, "site", "~on")
      "'\{comp}' writes `\{site}: \{name}()`: a call in an event position is refused. Calling a `compute` and naming a handler are the same dispatch, so the parentheses claim a distinction that does not exist — write `\{site}: \{name}`"
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
        " — did you mean `\{closest}()`?"
      }
      "`\{name}()` is not a `compute` this component declares, so it evaluates to nothing and the option reading it is dropped silently; declare it in `logic:` as `compute \{name}:`" +
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
  }
}

///|
/// One finding as a printable line: `CODE (level) where: message`.
///
/// The shape `gen` prints and the shape a module's screening passes print, so
/// a reader learns one format. `where_` is whatever locates it for the caller —
/// a file and line for `gen`, a module name for a loaded component.
pub fn Finding::to_line(self : Finding, where_ : String) -> String {
  let level = match self.level {
    Error => "error"
    Warn => "warning"
    Hint => "hint"
  }
  "\{code_name(self.code)} (\{level}) \{where_}: \{finding_message(self)}"
}
