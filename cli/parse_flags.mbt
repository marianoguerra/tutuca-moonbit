// One flag parser, driven by the registry.
//
// `registry.mbt` holds every flag's name, short form, type and enum — it calls
// itself the single source of truth "for dispatch, `help`, and the
// `agent-context` schema", and that is true of parsing too. A flag added there
// is parsed, suggested and rejected-when-unknown with no second edit.

///|
/// What a command's arguments parsed into: every flag by its long name, and
/// the positionals in the order they were written.
///
/// Booleans are present-or-absent (`Bool(true)` when given); string flags
/// carry their value. A caller reads what it declared and ignores the rest.
pub(all) struct ParsedArgs {
  flags : Map[String, FlagValue]
  positionals : Array[String]
}

///|
pub(all) enum FlagValue {
  Bool(Bool)
  Str(String)
} derive(Debug, Eq)

///|
/// `Some(value)` for a string flag that was given, `None` otherwise.
pub fn ParsedArgs::str(self : ParsedArgs, name : String) -> String? {
  match self.flags.get(name) {
    Some(Str(v)) => Some(v)
    _ => None
  }
}

///|
/// Whether a boolean flag was given.
pub fn ParsedArgs::bool(self : ParsedArgs, name : String) -> Bool {
  match self.flags.get(name) {
    Some(Bool(v)) => v
    _ => false
  }
}

///|
/// Every spelling that names this flag: `--long`, and `-s` when it has a short
/// form. The parser matches these EXACTLY (or followed by `=`), which is what
/// makes `--output` an unknown flag rather than a malformed `--out`.
fn flag_spellings(f : FlagSpec) -> Array[String] {
  let out = ["--" + f.name]
  match f.short {
    Some(s) => out.push("-" + s)
    None => ()
  }
  out
}

///|
/// Parse `args` against a command's declared flags.
///
/// Returns the parse, or the error to report. `--help`/`-h` is not special
/// here: it is an ordinary boolean in every command's flag list, so it lands
/// in `flags` and the caller decides what showing help means.
///
/// `--` is a terminator: everything after it is a positional, which is how a
/// path that begins with a dash gets passed at all.
pub fn parse_flags(
  args : Array[String],
  spec : CommandSpec,
) -> Result[ParsedArgs, ErrShape] {
  let flags : Map[String, FlagValue] = Map([])
  let positionals : Array[String] = []
  let mut i = 0
  let mut only_positionals = false
  while i < args.length() {
    let a = args[i]
    if only_positionals || !a.has_prefix("-") || a == "-" {
      positionals.push(a)
      i = i + 1
      continue
    }
    if a == "--" {
      only_positionals = true
      i = i + 1
      continue
    }
    // Exact spelling, or `--name=value`. Nothing matches by prefix.
    let mut matched : FlagSpec? = None
    let mut inline : String? = None
    for f in spec.flags {
      for spelling in flag_spellings(f) {
        if a == spelling {
          matched = Some(f)
        } else if a.has_prefix(spelling + "=") {
          matched = Some(f)
          inline = Some(a[spelling.length() + 1:].to_owned())
        }
      }
    }
    guard matched is Some(f) else { return Err(unknown_flag_error(a, spec)) }
    if f.type_ == "boolean" {
      // `--flag=false` is not a spelling this CLI has; a boolean is present or
      // it is not, which is the shape `agent-context` publishes.
      if inline is Some(_) {
        return Err(
          err(
            CODE_USAGE_BAD_FLAG_VALUE,
            "flag '--\{f.name}' takes no value",
            hint="it is a switch: pass '--\{f.name}' on its own",
          ),
        )
      }
      flags[f.name] = Bool(true)
      i = i + 1
      continue
    }
    let value = match inline {
      Some(v) => v
      None => {
        i = i + 1
        if i >= args.length() {
          return Err(missing_value_error(f))
        }
        args[i]
      }
    }
    match f.enum_ {
      Some(allowed) =>
        if !allowed.contains(value) {
          // The flag's own description is the better hint when it has one —
          // `--polyfills` accepts "0".."3", and what a reader needs is that 1
          // is @property and 2 is color-mix. Both live in the registry.
          let hint = match f.description {
            Some(d) => "accepted: \{allowed.join(", ")} — \{d}"
            None => "accepted: \{allowed.join(", ")}"
          }
          // No "did you mean" here, unlike the unknown-flag path: the hint
          // already lists every accepted value, and with a set like 0..3 every
          // candidate is one edit from the input, so the "nearest" is whichever
          // came first. `--polyfills 9` suggesting `0` is noise wearing the
          // costume of help.
          return Err(
            err(
              CODE_USAGE_BAD_FLAG_VALUE,
              "'--\{f.name}' expects \{allowed.join(", ")}, got '\{value}'",
              hint~,
            ),
          )
        }
      None => ()
    }
    flags[f.name] = Str(value)
    i = i + 1
  }
  Ok({ flags, positionals })
}

///|
/// The unknown-flag error, with the suggestion the docs have always promised.
///
/// Candidates are every spelling the command accepts, so `--dry-runn` finds
/// `--dry-run` and a stray `-0` finds nothing rather than something arbitrary.
fn unknown_flag_error(given : String, spec : CommandSpec) -> ErrShape {
  let candidates : Array[String] = []
  for f in spec.flags {
    for spelling in flag_spellings(f) {
      candidates.push(spelling)
    }
  }
  err(
    CODE_USAGE_UNKNOWN_FLAG,
    "unknown flag '\{given}' for \{spec.name}",
    suggestion?=did_you_mean(given, candidates),
    hint="see `tutuca \{spec.name} -h` for the accepted flags",
  )
}

///|
fn missing_value_error(f : FlagSpec) -> ErrShape {
  err(
    CODE_USAGE_MISSING_ARGUMENT,
    "'--\{f.name}' needs a value",
    hint="write it as `--\{f.name} <value>` or `--\{f.name}=<value>`",
  )
}
