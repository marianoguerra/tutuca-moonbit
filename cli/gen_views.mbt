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
  /// View problems worth reporting that do not stop generation: structural
  /// HTML mistakes and the deprecation nudges. Anything that makes the
  /// emitted types wrong already fails generation instead (@viewgen), so a
  /// diagnostic here never means "the output is untrustworthy".
  diagnostics : Array[String]
} derive(Debug, Eq)

///|
/// View diagnostics, reported at generation time.
///
/// This is where view checking happens, and the only place it happens: these
/// rules need nothing but the view text, and the generator is already parsing
/// every view. The rules that used to need a live component — which names are
/// fields, which are methods, what is registered in the scope — are not
/// deferred to a run-time linter any more; the generated types answer them at
/// compile time, and what the types cannot express is not worth a second,
/// weaker check.
fn view_diagnostics(
  file : @viewgen.ViewFile,
  fallback : String,
) -> Array[String] {
  let out : Array[String] = []
  // A schema interface with no template declares state for a component whose
  // views are built in MoonBit. Legitimate, and also what a mistyped
  // interface name looks like — so it is reported, not generated in silence.
  let declared = @viewgen.declared_components(file, fallback)
  for def in file.state {
    if !declared.contains(def.component) {
      out.push(
        "state-without-views (hint) \{def.component}: the schema declares it but no <template> here gives it views" +
        (if declared.is_empty() {
          ""
        } else {
          " (this file declares \{declared.join(", ")})"
        }),
      )
    }
  }
  for comp in file.components {
    let cname = comp.component_name(fallback)
    for view in comp.views {
      let where_ = "\{cname}/\{view.name}"
      // Structural HTML (mismatched tags, bad nesting): the WHATWG-tokenizer
      // linter, which needs only the source text.
      for f in @lint.lint_html(view.source) {
        out.push(diagnostic_line(where_, f))
      }
      // Parse-issue rules, deprecation nudges and host bare directives. A
      // fresh shadow parse, never the live tree.
      let collector = @lint.LintCollector::new()
      let px = @anode.ParseContext::new(handler=collector)
      let _ = @anode.ANode::parse(view.source, px)
      for f in @lint.check_collected(collector) {
        out.push(diagnostic_line(where_, f))
      }
    }
  }
  out
}

///|
fn diagnostic_line(where_ : String, f : @lint.Finding) -> String {
  let level = match f.level {
    Error => "error"
    Warn => "warning"
    Hint => "hint"
  }
  "\{@lint.lint_code_name(f.code)} (\{level}) \{where_}: \{@lint.finding_message(f)}"
}

///|
let gen_views_help : String =
  #|tutuca gen-views [path...] [--name <Name>] [--out <dir-or-file>] [--dry-run]
  #|
  #|  Compiles the views in each path into a MoonBit module of typed view
  #|  surfaces, written next to the component that uses them.
  #|
  #|  Paths are .html files or directories, following watch's rule: a directory
  #|  contributes the .html files that ALREADY have a generated sibling, so
  #|  pointing this at a project root does not try to compile index.html.
  #|
  #|  Passing more than one path is not just a convenience. The checks that span
  #|  components — whether the component a view renders exists, and whether it
  #|  has the view `as=` names — can only see what one invocation was given. The
  #|  program is the set of paths you passed; a component outside it is unknown,
  #|  and unknown is never reported as wrong.
  #|
  #|  Template ids say what each one is:
  #|    (none)         the single unnamed component's `main` view
  #|    row            ...its `row` view
  #|    Counter:main   the `Counter` component's `main` view
  #|    Counter        shorthand for `Counter:main`
  #|    macro:icon     a macro shared by every component in the file; its
  #|                   data-* attributes are the defaults for the body's ^vars
  #|
  #|  One file per MoonBit module, not per component: a file names as many
  #|  components as the module defines. A <style> inside a template is that
  #|  view's style; one at file level is the first component's common style,
  #|  or its global style with data-global.
  #|
  #|  The generated module declares, for a component named Counter:
  #|    counter_main_view / counter_views()  the view sources, for component()
  #|    CounterInput / CounterMsg            @on handler names, with the argument
  #|                                         shapes inferred from the call sites,
  #|                                         plus CounterMsg::from_dispatch
  #|    CounterMethod                        $-callable names, answered as an
  #|                                         exhaustive match
  #|
  #|  With a <script type="tutuca/state"> block it also declares CounterState,
  #|  its zero, its codec, and one SchemaInfo carrying the whole declaration:
  #|  the fields with their declared kinds, the handler channels, the view
  #|  names, the element ids and the fixture names. That descriptor is what an
  #|  instance answers obj_schema() with, so an inspector holding a bare Value
  #|  can read it with no component registry.
  #|
  #|  --name  the component name, for a file whose templates do not name one
  #|          (default: the file's basename, capitalized). A file that names
  #|          its components with `id="Comp:view"` ignores it. Names ONE
  #|          component, so it is refused with more than one path.
  #|  --out   directory (default: each input's) or an explicit .mbt file path.
  #|          The .mbt form names one file, so it too is refused for a batch.
  #|  --dry-run prints the generated modules to stdout instead of writing.
  #|  --no-ir skips the companion <stem>_view_ir_gen.mbt (the compiled tree,
  #|          which `views~` takes so the parser never runs at
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
fn run_gen_views(args : Array[String], opts : GlobalOpts) -> Outcome {
  let roots : Array[String] = []
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
        } else {
          roots.push(a)
        }
    }
    i = i + 1
  }
  if opts.help {
    return Done({ out: gen_views_help, err: "", exit_code: 0 })
  }
  if roots.is_empty() {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "gen-views requires an input .html file or a directory",
          hint="`tutuca gen-views path/to/counter.html --name Counter`, or `tutuca gen-views src/`",
        ),
      ),
    )
  }
  // Both of these name ONE component or ONE output file, so neither survives a
  // batch. Rejected rather than silently applied to the first path: quietly
  // writing every module to the same `--out` file is worse than not starting.
  if roots.length() > 1 && name is Some(_) {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MUTUALLY_EXCLUSIVE,
          "--name names one component, so it cannot be used with \{roots.length()} paths",
          hint="generate that file on its own, or let each file's basename name its component",
        ),
      ),
    )
  }
  if roots.length() > 1 && out is Some(o) && o.has_suffix(".mbt") {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MUTUALLY_EXCLUSIVE,
          "--out '\{o}' is one file, so it cannot take \{roots.length()} paths",
          hint="pass a directory instead, and each file keeps its own module name",
        ),
      ),
    )
  }
  GenViews(opts, roots~, out~, name~, dry_run~, ir~)
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
/// Generate the module from one file's contents — `gen_views_all` for a batch
/// of one, kept because most callers (the playground, the tests) have exactly
/// one file and no project around it.
pub fn gen_views(
  source : String,
  name~ : String,
  input~ : String,
  target~ : String,
  ir~ : Bool,
) -> Result[GenPlan, ErrShape] {
  gen_views_all([{ input, target, name, source }], ir~)
}

///|
/// Resolve one view path's output module and component name.
pub fn gen_views_target(
  path : String,
  out? : String,
  name? : String,
) -> (String, String) {
  let (dir, stem) = split_path(path)
  let target = match out {
    Some(o) =>
      if o.has_suffix(".mbt") {
        o
      } else {
        join_path(o, "\{stem}_view_gen.mbt")
      }
    None => join_path(dir, "\{stem}_view_gen.mbt")
  }
  (target, name.unwrap_or(default_name(stem)))
}

///|
/// Compile a whole batch into one plan. The only impure parts are reading the
/// sources and writing the plan, both of which the shell does.
pub fn gen_views_all(
  files : Array[GenInput],
  ir~ : Bool,
) -> Result[GenPlan, ErrShape] {
  let out : Array[(String, String)] = []
  let diagnostics : Array[String] = []
  // Split everything BEFORE emitting anything: the component table has to be
  // complete or a cross-file reference reads as an absence.
  let split : Array[(GenInput, @viewgen.ViewFile)] = []
  let index = @viewgen.ProgramIndex::new()
  for f in files {
    let views = @viewgen.split_file(f.source) catch {
      e =>
        return Err(
          err(
            CODE_VIEW_GEN_FAILED,
            "\{f.input}: \{@viewgen.GenError::message(e)}",
            where_=f.input,
          ),
        )
    }
    index.add(views, f.name)
    split.push((f, views))
  }
  for pair in split {
    let (f, views) = pair
    let file = basename(f.input)
    try {
      for d in view_diagnostics(views, f.name) {
        diagnostics.push(where_prefixed(files, f, d))
      }
      // `hints` is the schema check's advisory half — the findings a `slots~`
      // entry naming a bare `component` slot could legitimately defeat, so they
      // are reported here rather than failing generation.
      let hints : Array[String] = []
      let generated = @viewgen.emit_modules(
        f.name,
        file,
        views,
        include_ir=ir,
        hints~,
        program=index,
      )
      for h in hints {
        diagnostics.push(where_prefixed(files, f, h))
      }
      out.push((f.target, generated.types_source))
      // The compiled tree goes in its own module: it is by far the biggest
      // part of the output and nothing in the types file depends on it, so a
      // component that opts out just never references it.
      if generated.ir_source is Some(ir_src) {
        out.push((gen_views_ir_target(f.target), ir_src))
      }
    } catch {
      e =>
        return Err(
          err(
            CODE_VIEW_GEN_FAILED,
            "\{f.input}: \{@viewgen.GenError::message(e)}",
            where_=f.input,
          ),
        )
    }
  }
  Ok({ files: out, diagnostics })
}

///|
/// Name the file a diagnostic came from, but only when there is more than one
/// — a single-file run already says which file it is on the command line, and
/// prefixing it there would change every existing message.
fn where_prefixed(
  files : Array[GenInput],
  f : GenInput,
  line : String,
) -> String {
  if files.length() > 1 {
    "\{f.input}: \{line}"
  } else {
    line
  }
}

///|
/// "…/counter_view_gen.mbt" -> "…/counter_view_ir_gen.mbt"
///
/// Public because the shell reports which input each written file came from,
/// and a batch has more than one input to attribute them to.
pub fn gen_views_ir_target(target : String) -> String {
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
