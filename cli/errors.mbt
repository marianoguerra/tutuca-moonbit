// Error codes and rendering: port of tools/cli/errors.js (CODES table +
// emitError) and tools/format/lint.js suggestionToMessage. Code strings are
// kept verbatim, including the un-prefixed EXAMPLES_SHAPE_MISMATCH.

///|
pub const CODE_USAGE_UNKNOWN_COMMAND : String = "ERR_USAGE_UNKNOWN_COMMAND"

///|
pub const CODE_USAGE_UNKNOWN_FLAG : String = "ERR_USAGE_UNKNOWN_FLAG"

///|
pub const CODE_USAGE_BAD_FLAG_VALUE : String = "ERR_USAGE_BAD_FLAG_VALUE"

///|
pub const CODE_USAGE_MISSING_MODULE : String = "ERR_USAGE_MISSING_MODULE"

///|
pub const CODE_USAGE_MUTUALLY_EXCLUSIVE : String = "ERR_USAGE_MUTUALLY_EXCLUSIVE"

///|
pub const CODE_USAGE_MISSING_ARGUMENT : String = "ERR_USAGE_MISSING_ARGUMENT"

///|
pub const CODE_FORMAT_UNKNOWN : String = "ERR_FORMAT_UNKNOWN"

///|
pub const CODE_FORMAT_UNSUPPORTED : String = "ERR_FORMAT_UNSUPPORTED"

///|
pub const CODE_MODULE_LOAD_FAILED : String = "ERR_MODULE_LOAD_FAILED"

///|
pub const CODE_MODULE_SHAPE_MISMATCH : String = "EXAMPLES_SHAPE_MISMATCH"

///|
pub const CODE_SKILL_ASSETS_MISSING : String = "ERR_SKILL_ASSETS_MISSING"

///|
pub const CODE_SKILL_TARGET_EXISTS : String = "ERR_SKILL_TARGET_EXISTS"

///|
pub const CODE_INTERNAL : String = "ERR_INTERNAL"

///|
/// All codes in the CODES-table order agent-context emits as `errorCodes`.
pub let error_codes : Array[String] = [
  CODE_USAGE_UNKNOWN_COMMAND,
  CODE_USAGE_UNKNOWN_FLAG,
  CODE_USAGE_BAD_FLAG_VALUE,
  CODE_USAGE_MISSING_MODULE,
  CODE_USAGE_MUTUALLY_EXCLUSIVE,
  CODE_USAGE_MISSING_ARGUMENT,
  CODE_FORMAT_UNKNOWN,
  CODE_FORMAT_UNSUPPORTED,
  CODE_MODULE_LOAD_FAILED,
  CODE_MODULE_SHAPE_MISMATCH,
  CODE_SKILL_ASSETS_MISSING,
  CODE_SKILL_TARGET_EXISTS,
  CODE_INTERNAL,
]

///|
/// ErrShape constructor with the same defaults emitError applies
/// (exit code 1, everything else absent).
pub fn err(
  code : String,
  message : String,
  suggestion? : @lint.Suggestion,
  hint? : String,
  where_? : String,
  exit_code? : Int = 1,
) -> ErrShape {
  { code, message, suggestion, hint, where_, exit_code }
}

///|
pub fn did_you_mean(
  name : String,
  candidates : Array[String],
) -> @lint.Suggestion? {
  match @lint.closest_name(name, candidates) {
    Some(to) => Some(ReplaceName(from=name, to~))
    None => None
  }
}

///|
pub fn suggestion_to_message(suggestion : @lint.Suggestion?) -> String? {
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
pub fn render_error(opts : GlobalOpts, shape : ErrShape) -> String {
  if opts.format == Some("json") {
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
    let buf = StringBuilder::new()
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
  { out: "", err: render_error(opts, shape), exit_code: shape.exit_code }
}
