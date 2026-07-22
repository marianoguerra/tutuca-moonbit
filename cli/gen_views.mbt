// `tutuca gen-views` — ahead-of-time view compilation. An .html file holding
// one or more views becomes a companion MoonBit module of typed view
// surfaces, so handler names, argument shapes, view names and element ids
// stop being strings the compiler cannot see.
//
// Pure like the rest of cli/: this half parses the flags and turns SOURCE
// TEXT into GENERATED TEXT. The shell (cmd/main) reads the input file and
// writes the plan, the same split `install-skill` uses.

///|
/// What the shell should write: (path, contents) pairs, already resolved
/// against `--out`.
pub(all) struct GenPlan {
  files : Array[(String, String)]
} derive(Debug, Eq)

///|
let gen_views_help : String =
  #|tutuca gen-views <file.html> [--name <Name>] [--out <dir-or-file>] [--dry-run]
  #|
  #|  Compiles the views in <file.html> into a MoonBit module of typed view
  #|  surfaces, written next to the component that uses them.
  #|
  #|  The file holds either one bare view, or several <template> elements whose
  #|  id attributes name them; the template with no id is the `main` view. A
  #|  <style> inside a template is that view's style; one at file level is the
  #|  component's common style, or its global style with data-global.
  #|
  #|  The generated module declares, for a component named Counter:
  #|    counter_main_view / counter_views()  the view sources, for component()
  #|    CounterInput / CounterMsg            @on handler names, with the argument
  #|                                         shapes inferred from the call sites,
  #|                                         plus CounterMsg::of_dispatch
  #|    CounterMethod + counter_mutate/…     $-callable names as exhaustive matches
  #|    CounterView / CounterId              view names and element ids
  #|    counter_fields / …_missing_fields    the state fields the views read
  #|
  #|  --name  the component name (default: the file's basename, capitalized).
  #|  --out   directory (default: the input's) or an explicit .mbt file path.
  #|  --dry-run prints the generated modules to stdout instead of writing.
  #|  --no-ir skips the companion <stem>_view_ir_gen.mbt (the compiled tree,
  #|          which `compiled_views~` takes so the parser never runs at
  #|          startup). It is skipped automatically for a view using a macro,
  #|          which only MoonBit can expand.
  #|
  #|  The generated file is checked in and regenerated, never hand-edited; its
  #|  package must import "marianoguerra/tutuca/core" @tutuca,
  #|  "marianoguerra/tutuca/component" and "moonbitlang/core/debug".
  #|

///|
/// "a/b/counter.html" -> ("a/b", "counter")
fn split_path(path : String) -> (String, String) {
  let chars = path.to_array()
  let mut slash = -1
  let mut dot = -1
  for i, c in chars {
    if c == '/' {
      slash = i
      dot = -1 // a dot in a directory name is not an extension
    } else if c == '.' {
      dot = i
    }
  }
  let dir = if slash < 0 { "" } else { path[:slash].to_owned() }
  let stem_start = slash + 1
  let stem_end = if dot > slash { dot } else { chars.length() }
  (dir, path[stem_start:stem_end].to_owned())
}

///|
/// "counter" -> "Counter", "todo-list" -> "TodoList"
fn default_name(stem : String) -> String {
  @viewgen.variant_name(stem)
}

///|
/// Join a directory and a file name, tolerating an empty or trailing-slash
/// directory.
fn join_path(dir : String, file : String) -> String {
  if dir == "" {
    file
  } else if dir.has_suffix("/") {
    dir + file
  } else {
    dir + "/" + file
  }
}

///|
/// Parse gen-views' own args. Finishes purely on help and usage errors;
/// otherwise hands the shell the input path to read and what to do with it.
pub fn run_gen_views(args : Array[String], opts : GlobalOpts) -> Outcome {
  let mut input : String? = None
  let mut name : String? = None
  let mut out : String? = None
  let mut dry_run = false
  let mut ir = true
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    let value_of = (flag : String) => {
      if a.has_prefix(flag + "=") {
        Some(a[flag.length() + 1:].to_owned())
      } else if a == flag && i + 1 < args.length() {
        i = i + 1
        Some(args[i])
      } else {
        None
      }
    }
    match a {
      "-h" | "--help" =>
        return Done({ out: gen_views_help, err: "", exit_code: 0 })
      "--dry-run" => dry_run = true
      "--no-ir" => ir = false
      _ =>
        if a.has_prefix("--name") {
          match value_of("--name") {
            Some(v) => name = Some(v)
            None => return Done(missing_value(opts, "--name"))
          }
        } else if a.has_prefix("--out") {
          match value_of("--out") {
            Some(v) => out = Some(v)
            None => return Done(missing_value(opts, "--out"))
          }
        } else if a.has_prefix("-") {
          return Done(
            error_emit(
              opts,
              err(
                CODE_USAGE_UNKNOWN_FLAG,
                "unknown flag '\{a}' for gen-views",
                hint="see `tutuca gen-views -h` for the accepted flags",
              ),
            ),
          )
        } else if input is None {
          input = Some(a)
        } else {
          return Done(
            error_emit(
              opts,
              err(
                CODE_USAGE_UNKNOWN_FLAG,
                "gen-views takes one input file, got a second positional '\{a}'",
                hint="generate one component's views per invocation",
              ),
            ),
          )
        }
    }
    i = i + 1
  }
  if opts.help {
    return Done({ out: gen_views_help, err: "", exit_code: 0 })
  }
  guard input is Some(path) else {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "gen-views requires an input .html file",
          hint="`tutuca gen-views path/to/counter.html --name Counter`",
        ),
      ),
    )
  }
  let (dir, stem) = split_path(path)
  let comp_name = name.unwrap_or(default_name(stem))
  // --out names a .mbt file directly, or the directory to write into.
  let target = match out {
    Some(o) =>
      if o.has_suffix(".mbt") {
        o
      } else {
        join_path(o, "\{stem}_view_gen.mbt")
      }
    None => join_path(dir, "\{stem}_view_gen.mbt")
  }
  GenViews(opts, input=path, target~, name=comp_name, dry_run~, ir~)
}

///|
fn missing_value(opts : GlobalOpts, flag : String) -> Emit {
  error_emit(
    opts,
    err(
      CODE_USAGE_MISSING_ARGUMENT,
      "\{flag} needs a value",
      hint="write it as `\{flag}=<value>` or `\{flag} <value>`",
    ),
  )
}

///|
/// Generate the module from the file's contents. The only impure part is
/// reading `source` and writing the plan, both of which the shell does.
pub fn gen_views(
  source : String,
  name~ : String,
  input~ : String,
  target~ : String,
  ir~ : Bool,
) -> Result[GenPlan, ErrShape] {
  let files : Array[(String, String)] = []
  let file = basename(input)
  try {
    let views = @viewgen.split_views(source)
    let surface = @viewgen.view_surface(views.views, macros=views.macros)
    files.push((target, @viewgen.emit_module(name, file, views, surface)))
    // The compiled tree goes in its own module: it is by far the biggest
    // part of the output and nothing in the types file depends on it, so a
    // component that opts out just never references it.
    if ir && @viewgen.ir_supported(views.views, macros=views.macros) {
      files.push(
        (ir_target(target), @viewgen.emit_ir_module(name, file, views)),
      )
    }
  } catch {
    e =>
      return Err(
        err(
          CODE_VIEW_GEN_FAILED,
          "\{input}: \{@viewgen.GenError::message(e)}",
          where_=input,
        ),
      )
  }
  Ok({ files, })
}

///|
/// "…/counter_view_gen.mbt" -> "…/counter_view_ir_gen.mbt"
fn ir_target(target : String) -> String {
  if target.has_suffix("_gen.mbt") {
    target[:target.length() - 8].to_owned() + "_ir_gen.mbt"
  } else if target.has_suffix(".mbt") {
    target[:target.length() - 4].to_owned() + "_ir.mbt"
  } else {
    target + "_ir.mbt"
  }
}

///|
/// "a/b/counter.html" -> "counter.html" (what the generated header cites).
fn basename(path : String) -> String {
  let chars = path.to_array()
  let mut slash = -1
  for i, c in chars {
    if c == '/' {
      slash = i
    }
  }
  path[slash + 1:].to_owned()
}

///|
/// The line the shell prints after writing.
pub fn gen_views_success(target : String, input : String) -> String {
  "generated \{target} from \{input}\n"
}
