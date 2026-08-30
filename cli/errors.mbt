// Error codes and rendering. Every code here is one this CLI can actually
// emit — the format/module-shape codes went with the commands that produced
// them.

///|
pub const CODE_USAGE_UNKNOWN_COMMAND : String = "ERR_USAGE_UNKNOWN_COMMAND"

///|
pub const CODE_USAGE_UNKNOWN_FLAG : String = "ERR_USAGE_UNKNOWN_FLAG"

///|
pub const CODE_USAGE_BAD_FLAG_VALUE : String = "ERR_USAGE_BAD_FLAG_VALUE"

///|
pub const CODE_USAGE_MUTUALLY_EXCLUSIVE : String = "ERR_USAGE_MUTUALLY_EXCLUSIVE"

///|
pub const CODE_USAGE_MISSING_ARGUMENT : String = "ERR_USAGE_MISSING_ARGUMENT"

///|
pub const CODE_SKILL_ASSETS_MISSING : String = "ERR_SKILL_ASSETS_MISSING"

///|
pub const CODE_SKILL_TARGET_EXISTS : String = "ERR_SKILL_TARGET_EXISTS"

///|
pub const CODE_GUEST_NAME_INVALID : String = "ERR_GUEST_NAME_INVALID"

///|
pub const CODE_GUEST_TEMPLATE_MISSING : String = "ERR_GUEST_TEMPLATE_MISSING"

///|
pub const CODE_GUEST_TARGET_EXISTS : String = "ERR_GUEST_TARGET_EXISTS"

///|
pub const CODE_STORYBOOK_NAME_INVALID : String = "ERR_STORYBOOK_NAME_INVALID"

///|
pub const CODE_STORYBOOK_TEMPLATE_MISSING : String = "ERR_STORYBOOK_TEMPLATE_MISSING"

///|
pub const CODE_STORYBOOK_TARGET_EXISTS : String = "ERR_STORYBOOK_TARGET_EXISTS"

///|
pub const CODE_VIEW_GEN_FAILED : String = "ERR_VIEW_GEN_FAILED"

///|
pub const CODE_INTERNAL : String = "ERR_INTERNAL"

///|
/// Every code, in the order agent-context emits them as `errorCodes`.
pub let error_codes : Array[String] = [
  CODE_USAGE_UNKNOWN_COMMAND,
  CODE_USAGE_UNKNOWN_FLAG,
  CODE_USAGE_BAD_FLAG_VALUE,
  CODE_USAGE_MUTUALLY_EXCLUSIVE,
  CODE_USAGE_MISSING_ARGUMENT,
  CODE_VIEW_GEN_FAILED,
  CODE_SKILL_ASSETS_MISSING,
  CODE_SKILL_TARGET_EXISTS,
  CODE_GUEST_NAME_INVALID,
  CODE_GUEST_TEMPLATE_MISSING,
  CODE_GUEST_TARGET_EXISTS,
  CODE_STORYBOOK_NAME_INVALID,
  CODE_STORYBOOK_TEMPLATE_MISSING,
  CODE_STORYBOOK_TARGET_EXISTS,
  CODE_INTERNAL,
]

///|
/// ErrShape constructor: exit code 1, everything else absent.
pub fn err(
  code : String,
  message : String,
  suggestion? : @lint.Suggestion,
  hint? : String,
  where_? : String,
  exit_code? : Int = 1,
) -> ErrShape {
  { code, message, suggestion, hint, where_, exit_code, }
}

///|
fn did_you_mean(name : String, candidates : Array[String]) -> @lint.Suggestion? {
  match @lint.closest_name(name, candidates) {
    Some(to) => Some(ReplaceName(from=name, to~))
    None => None
  }
}

///|
fn suggestion_to_message(suggestion : @lint.Suggestion?) -> String? {
  match suggestion {
    None => None
    Some(ReplaceName(to~, ..)) => Some("did you mean '\{to}'?")
    Some(DropPrefix(from~, to~)) => {
      let dropped = from[:from.length() - to.length()]
      Some("did you mean '\{to}'? (drop the leading '\{dropped}')")
    }
    Some(AddPrefix(from~, to~)) => {
      let added = to[:to.length() - from.length()]
      Some("did you mean '\{to}'? (add the leading '\{added}')")
    }
    Some(Remove(what~)) => Some("remove \{what}")
    Some(Rewrite(from~, to~)) => Some("use '\{to}' instead of '\{from}'")
    Some(Wrap(to~, ..)) => Some("wrap it in \{to}")
    Some(Rephrase(text~, ..)) => Some(text)
  }
}

///|
/// JSON form of a suggestion for the --json error envelope. The CLI only
/// produces ReplaceName and Rewrite; the other kinds mirror their enum
/// payloads should they ever flow through.
fn suggestion_to_json(suggestion : @lint.Suggestion) -> Json {
  match suggestion {
    ReplaceName(from~, to~) =>
      { "kind": "replace-name", "from": from.to_json(), "to": to.to_json() }
    AddPrefix(from~, to~) =>
      { "kind": "add-prefix", "from": from.to_json(), "to": to.to_json() }
    DropPrefix(from~, to~) =>
      { "kind": "drop-prefix", "from": from.to_json(), "to": to.to_json() }
    Remove(what~) => { "kind": "remove", "what": what.to_json() }
    Rephrase(from~, text~) =>
      { "kind": "rephrase", "from": from.to_json(), "text": text.to_json() }
    Rewrite(from~, to~) =>
      { "kind": "rewrite", "from": from.to_json(), "to": to.to_json() }
    Wrap(from~, to~) =>
      { "kind": "wrap", "from": from.to_json(), "to": to.to_json() }
  }
}

///|
fn render_error(opts : GlobalOpts, shape : ErrShape) -> String {
  if opts.json {
    let error : Map[String, Json] = {
      "code": shape.code.to_json(),
      "message": shape.message.to_json(),
    }
    match shape.suggestion {
      Some(s) => error["suggestion"] = suggestion_to_json(s)
      None => ()
    }
    match shape.hint {
      Some(h) => error["hint"] = h.to_json()
      None => ()
    }
    match shape.where_ {
      Some(w) => error["where"] = w.to_json()
      None => ()
    }
    let envelope : Json = Json::object({ "error": Json::object(error) })
    envelope.stringify(escape_slash=false) + "\n"
  } else {
    let buf = StringBuilder()
    let where_ = match shape.where_ {
      Some(w) => "[\{w}] "
      None => ""
    }
    buf.write_string("tutuca: \{where_}\{shape.message}\n")
    match suggestion_to_message(shape.suggestion) {
      Some(tail) => buf.write_string("  \{tail}\n")
      None => ()
    }
    match shape.hint {
      Some(h) => buf.write_string("  hint: \{h}\n")
      None => ()
    }
    buf.to_string()
  }
}

///|
/// Emit for an error: stderr text + the shape's exit code.
pub fn error_emit(opts : GlobalOpts, shape : ErrShape) -> Emit {
  { out: "", err: render_error(opts, shape), exit_code: shape.exit_code, }
}
