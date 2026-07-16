// Global-flag extraction: port of extractGlobals (tools/tutuca.js:12-54).

///|
pub let format_names : Array[String] = ["cli", "md", "json", "html"]

///|
/// Flag names listed as valid in unknown-flag hints. Includes "no-color"
/// for parity: the JS CLI lists it without ever parsing it.
pub let global_flag_names : Array[String] = [
  "format", "output", "pretty", "module", "json", "help", "no-color",
]

///|
pub fn extract_globals(
  argv : Array[String],
) -> Result[(GlobalOpts, Array[String]), (GlobalOpts, ErrShape)] {
  let rest : Array[String] = []
  let mut format : String? = None
  let mut output : String? = None
  let mut pretty = false
  let mut module_path : String? = None
  let mut help = false
  let take_value = (i : Int) => {
    if i < argv.length() {
      Some(argv[i])
    } else {
      None
    }
  }
  let mut i = 0
  while i < argv.length() {
    let a = argv[i]
    if a == "-f" || a == "--format" {
      i += 1
      format = take_value(i)
    } else if a.has_prefix("--format=") {
      format = Some(a[9:].to_owned())
    } else if a == "--json" {
      format = Some("json")
    } else if a == "-o" || a == "--output" {
      i += 1
      output = take_value(i)
    } else if a.has_prefix("--output=") {
      output = Some(a[9:].to_owned())
    } else if a == "--pretty" {
      pretty = true
    } else if a == "--module" {
      i += 1
      module_path = take_value(i)
    } else if a.has_prefix("--module=") {
      module_path = Some(a[9:].to_owned())
    } else if a == "-h" || a == "--help" {
      help = true
    } else {
      rest.push(a)
    }
    i += 1
  }
  let opts : GlobalOpts = { format, output, pretty, module_path, help }
  match format {
    Some(f) =>
      if format_names.contains(f) {
        Ok((opts, rest))
      } else {
        Err(
          (
            opts,
            err(
              CODE_FORMAT_UNKNOWN,
              "Unknown format '\{f}'",
              suggestion?=did_you_mean(f, format_names),
              hint="Valid formats: \{format_names.join(", ")}",
            ),
          ),
        )
      }
    None => Ok((opts, rest))
  }
}
