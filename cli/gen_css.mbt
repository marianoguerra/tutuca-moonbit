// `tutuca gen-tailwind-css` / `tutuca gen-margaui-css` — build-time CSS from a
// project's views. tutuca already knows which classes a view uses (the class
// collector every host calls before injecting a <style>); these commands run
// the same collection over the view FILES and hand the result to the compiler,
// so a project that compiles its views ahead of time can ship a static
// stylesheet holding exactly the utilities it uses.
//
// Pure like the rest of cli/: this half parses the flags and turns SOURCE TEXT
// into a class set. The shell (cmd/tutuca) walks the tree, reads the files, calls
// the compiler and writes the CSS — the same split gen-views uses.

///|
let gen_tailwind_css_help : String =
  #|tutuca gen-tailwind-css [path...] [--out <file>] [--entry <file>]
  #|                        [--classes <file>] [--print-classes] [--polyfills <0..3>]
  #|
  #|  Compile the classes used by a project's views into CSS, against stock
  #|  Tailwind — theme, preflight and utilities, no component library. Paths are
  #|  view .html files or directories to search; a directory contributes the
  #|  .html files that already have a generated sibling, so pointing this at a
  #|  project root does not try to compile index.html. Defaults to the current
  #|  directory.
  #|
  #|  --out     write the CSS here (default: stdout).
  #|  --entry   compile this CSS entry instead of the embedded one, resolving
  #|            its @imports from the filesystem. Use it for a project's own
  #|            theme, @source or plugin setup.
  #|  --classes extra candidate class names, one per line. Class names a view
  #|            assembles at run time (`:class="$'bg-{.color}'"`, or anything a
  #|            handler computes) are invisible to the collector; this is how
  #|            you add them back.
  #|  --print-classes  print the collected class names instead of the CSS, one
  #|            per line. The quickest way to see what the collector did and did
  #|            not find.
  #|  --polyfills  0=none, 1=@property, 2=color-mix, 3=all (default 3).
  #|

///|
let gen_margaui_css_help : String =
  #|tutuca gen-margaui-css [path...] [--out <file>] [--entry <file>]
  #|                       [--classes <file>] [--print-classes] [--polyfills <0..3>]
  #|
  #|  Exactly `gen-tailwind-css`, but compiled against Tailwind AND margaui —
  #|  the base layers, the themes and the component classes (btn, card, stat,
  #|  modal...). Use this one if your views use margaui components; the output
  #|  is a superset of what gen-tailwind-css produces for the same views.
  #|
  #|  --out     write the CSS here (default: stdout).
  #|  --entry   compile this CSS entry instead of the embedded one, resolving
  #|            its @imports from the filesystem.
  #|  --classes extra candidate class names, one per line (for classes a view
  #|            assembles at run time, which the collector cannot see).
  #|  --print-classes  print the collected class names instead of the CSS.
  #|  --polyfills  0=none, 1=@property, 2=color-mix, 3=all (default 3).
  #|

///|
/// Parse the shared args of both CSS commands. Finishes purely on help and
/// usage errors; otherwise hands the shell the roots to walk and what to do
/// with what it finds.
///
/// One parser for two commands: the flag sets are identical and only the
/// stylesheet set differs, so letting them drift apart would be a bug, not a
/// feature.
fn run_gen_css(
  args : Array[String],
  opts : GlobalOpts,
  margaui~ : Bool,
) -> Outcome {
  let help = if margaui { gen_margaui_css_help } else { gen_tailwind_css_help }
  let command = if margaui { "gen-margaui-css" } else { "gen-tailwind-css" }
  let parsed = match parse_flags(args, command_spec(command)) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: help, err: "", exit_code: 0 })
  }
  let paths = parsed.positionals
  let out = parsed.str("out")
  let entry = parsed.str("entry")
  let extra_classes = parsed.str("classes")
  let print_classes = parsed.bool("print-classes")
  // The registry declares the accepted values, so `parse_flags` has already
  // refused anything else; this is only the string -> Int mapping.
  // @tw.POLYFILL_ALL is the default.
  let polyfills = match parsed.str("polyfills") {
    Some(v) => parse_polyfills(v).unwrap_or(3)
    None => 3
  }
  // No roots means "this project", the same default `watch` takes.
  if paths.length() == 0 {
    paths.push(".")
  }
  GenCss(opts, plan={
    paths,
    out,
    entry,
    extra_classes,
    print_classes,
    polyfills,
    margaui,
  })
}

///|
/// `--polyfills` accepts exactly the compiler's four levels; anything else is a
/// usage error rather than a silent clamp. The values ARE the compiler's
/// `@tw.POLYFILL_*` constants (0..3), so the shell forwards the int unchanged —
/// keeping the pure core free of a dependency on the compiler package.
fn parse_polyfills(value : String) -> Int? {
  match value {
    "0" => Some(0)
    "1" => Some(1)
    "2" => Some(2)
    "3" => Some(3)
    _ => None
  }
}

///|
/// Every literal class name the given view files use, sorted and deduped.
///
/// This is the file-level twin of what a running app does through
/// `Components::collect_classes`: compile each view, then walk the tree. Going
/// through `build_views` rather than the raw parse is what makes macro bodies
/// visible — an uncompiled `MacroCall` holds no children to scan.
///
/// Only LITERAL fragments are collected, exactly as at run time: a class name a
/// view assembles from a field is not in the source to be found. `--classes`
/// exists for those.
pub fn collect_view_classes(
  sources : Array[(String, String)],
) -> Result[Array[String], ErrShape] {
  let found : Set[String] = Set([])
  for pair in sources {
    let (path, source) = pair
    try {
      let file = @viewgen.split_file(source)
      for comp in file.components {
        let views = @viewgen.build_views(comp, macros=file.macros)
        for _, view in views {
          if view.anode is Some(node) {
            node.collect_classes(found)
          }
        }
      }
    } catch {
      e =>
        return Err(
          err(
            CODE_VIEW_GEN_FAILED,
            "\{path}: \{@viewgen.GenError::message(e)}",
            where_=path,
          ),
        )
    }
  }
  let classes = found.iter().collect()
  classes.sort_by(lex_compare)
  Ok(classes)
}

///|
/// Byte-lexicographic string order.
///
/// NOT `String`'s own `Compare`, which orders by length first — that is fine for
/// a compiler candidate list, where order is irrelevant, but `--print-classes`
/// is read by a person, and a list that runs "b, k, n, s, on, rm, add, btn"
/// looks broken. Alphabetical is also the order a class list is scanned in when
/// checking what the collector missed.
pub fn lex_compare(a : String, b : String) -> Int {
  a.lexical_compare(b)
}

///|
/// The line the shell prints after writing the CSS.
pub fn gen_css_success(target : String, files~ : Int, classes~ : Int) -> String {
  let file_word = if files == 1 { "view" } else { "views" }
  let class_word = if classes == 1 { "class" } else { "classes" }
  "generated \{target} from \{files} \{file_word} (\{classes} \{class_word})\n"
}

///|
/// `--print-classes` output: one class name per line.
pub fn class_list_text(classes : Array[String]) -> String {
  let sb = StringBuilder::new()
  for c in classes {
    sb.write_string(c)
    sb.write_string("\n")
  }
  sb.to_string()
}
