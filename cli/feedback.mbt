// Pure half of `tutuca feedback` (tools/cli/commands/feedback.js): help
// text, flag parsing, the record line and paths. The shell (cmd/main) does
// the stdin fallback and the ~/.tutuca/feedback.jsonl append.

///|
let feedback_help_text : String =
  #|tutuca feedback [message]
  #|
  #|  Append a feedback record to ~/.tutuca/feedback.jsonl (created if missing).
  #|  Use this for bugs, confusing messages, or suggestions about the CLI,
  #|  bundled skills, docs, or the library itself.
  #|
  #|  Provide the message as a positional argument:
  #|    tutuca feedback "the lint code FIELD_VAL_NOT_DEFINED was confusing"
  #|
  #|  ...or via stdin (useful for multi-line notes):
  #|    echo "..." | tutuca feedback
  #|    tutuca feedback < notes.txt
  #|
  #|  Each record is one JSON object per line: {ts, version, message}.

///|
/// Parse `tutuca feedback`'s own args. The JS version lets node:util
/// parseArgs throw an uncaught stack trace on an unknown flag; here it gets
/// the same coded error the dispatcher uses elsewhere.
pub fn run_feedback(args : Array[String], opts : GlobalOpts) -> Outcome {
  let positionals : Array[String] = []
  for a in args {
    if a == "-h" || a == "--help" {
      return Done({ out: feedback_help_text + "\n", err: "", exit_code: 0 })
    }
    if a.has_prefix("-") && a != "-" {
      let stripped = a.trim_start(chars="-").to_owned()
      return Done(
        error_emit(
          opts,
          err(
            CODE_USAGE_UNKNOWN_FLAG,
            "Unknown flag '\{a}'",
            suggestion?=match did_you_mean(stripped, ["help"]) {
              Some(_) =>
                Some(@lint.Suggestion::ReplaceName(from=a, to="--help"))
              None => None
            },
            hint="Valid flags: --help",
          ),
        ),
      )
    }
    positionals.push(a)
  }
  let message = positionals.join(" ").trim(chars=" \t\r\n").to_owned()
  Feedback(opts, message=if message == "" { None } else { Some(message) })
}

///|
pub fn feedback_missing_message(opts : GlobalOpts) -> Emit {
  error_emit(
    opts,
    err(
      CODE_USAGE_MISSING_ARGUMENT,
      "feedback requires a message (positional arg or piped stdin)",
      hint="Example: `tutuca feedback \"the lint code FIELD_VAL_NOT_DEFINED was confusing\"` or `echo ... | tutuca feedback`.",
    ),
  )
}

///|
pub fn feedback_record_line(
  ts_iso : String,
  version : String,
  message : String,
) -> String {
  let record : Json = {
    "ts": ts_iso.to_json(),
    "version": version.to_json(),
    "message": message.to_json(),
  }
  record.stringify(escape_slash=false) + "\n"
}

///|
pub fn feedback_paths(home : String) -> (String, String) {
  let dir = "\{home}/.tutuca"
  (dir, "\{dir}/feedback.jsonl")
}

///|
pub fn feedback_success_line(file : String) -> String {
  "recorded feedback → \{file}\n"
}
