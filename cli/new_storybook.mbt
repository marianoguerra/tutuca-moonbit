// `tutuca new-storybook <name>` — scaffold a gallery of your own components.
//
// The gallery itself ships: `storybook` is the story model, `storybook/ui` the
// shell, `storybook/ui/wasm` the browser host. What a project still has to
// write is the part a library cannot supply — a wasm-gc export list is
// per-package `link` configuration and cannot come from a dependency — plus the
// page it loads from and the script that assembles both. That is what this
// command writes: a complete, buildable project whose only real content is
// which modules to show.
//
// The tree is embedded in this binary (storybook_template_gen.mbt, regenerated
// by `moon run --target native cmd/dev -- storybook-template-embed`), so
// scaffolding needs no network, and it runs nothing: cmd/tutuca spawns no
// subprocesses, so `moon build` and `node build.mjs` are the user's to run.

///|
/// What the shell should write: `files` are (path-relative-to-`dir`, contents)
/// with every placeholder already substituted; `dir` is relative to the cwd.
pub(all) struct StorybookScaffoldPlan {
  dir : String
  name : String
  force : Bool
  files : Array[(String, String)]
} derive(Debug, Eq)

///|
let new_storybook_help : String =
  #|tutuca new-storybook <name> [--dir <path>] [--dry-run] [--force]
  #|
  #|  Scaffolds a storybook gallery — a wasm page showing your own components,
  #|  one story per example a module declares — into ./<name>/ (or --dir).
  #|
  #|  <name> is kebab-case: it becomes the directory and the moon module name.
  #|
  #|  --dir <path> writes somewhere other than ./<name>/.
  #|  --dry-run prints the files that would be written without touching disk.
  #|  --force overwrites existing files.
  #|
  #|  Then: node build.mjs && tutuca storybook dist
  #|  Needs moon and node — nothing else. The first build fetches
  #|  marianoguerra/tutuca from mooncakes.
  #|

///|
/// Is this a name that can be a directory and a moon module name at once?
/// Kebab-lowercase is the intersection, so that is the rule. `None` = fine;
/// `Some(hint)` = why not.
///
/// Deliberately narrower than what moon accepts: a module may be
/// `handle/project`, but a name with a slash in it is also a nested directory,
/// and a scaffolder that quietly created two of them would be surprising. Edit
/// `moon.mod` afterwards to publish under a handle.
pub fn project_name_check(name : String) -> String? {
  if name.is_empty() {
    return Some("a name is required")
  }
  let first = name[0]
  if !(first >= 'a' && first <= 'z') {
    return Some("must start with a lowercase letter")
  }
  if name.has_suffix("-") {
    return Some("must not end with '-'")
  }
  let mut prev_dash = false
  for c in name {
    let ok = (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-'
    if !ok {
      return Some("only lowercase letters, digits and '-' are allowed")
    }
    if c == '-' && prev_dash {
      return Some("must not contain '--'")
    }
    prev_dash = c == '-'
  }
  None
}

///|
/// Substitute the template's placeholders. Applied to every emitted path AND to
/// every file's contents, so one embed serves every project.
///
/// `{{tutuca_version}}` is the module version this binary was built from
/// (`MODULE_VERSION`), so a scaffolded project depends on a release that
/// actually contains the packages its page imports.
pub fn substitute_storybook_name(text : String, name : String) -> String {
  text
  .replace_all(old="{{name_ident}}", new=snake_case(name))
  .replace_all(old="{{Name}}", new=pascal_case(name))
  .replace_all(old="{{name}}", new=name)
  .replace_all(old="{{tutuca_version}}", new=MODULE_VERSION)
}

///|
/// Parse new-storybook's own args and either finish purely (help, dry-run,
/// usage errors, missing assets) or hand the shell a write plan.
fn run_new_storybook(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("new-storybook")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: new_storybook_help, err: "", exit_code: 0, })
  }
  let dry_run = parsed.bool("dry-run")
  let force = parsed.bool("force")
  let dir = parsed.str("dir").unwrap_or("")
  if parsed.positionals.length() > 1 {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_UNKNOWN_FLAG,
          "new-storybook takes one name, got '\{parsed.positionals[0]}' and '\{parsed.positionals[1]}'",
          hint="one gallery per directory; run it again for the second.",
        ),
      ),
    )
  }
  let name = parsed.positionals.get(0).unwrap_or("")
  if name == "" {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "new-storybook needs a name",
          hint="e.g. `tutuca new-storybook my-gallery`; see -h for the naming rule",
        ),
      ),
    )
  }
  match project_name_check(name) {
    Some(why) =>
      return Done(
        error_emit(
          opts,
          err(
            CODE_STORYBOOK_NAME_INVALID,
            "'\{name}' is not a usable project name: \{why}",
            hint="kebab-case only — it becomes a directory and a moon module name at once. `my-gallery`, not `MyGallery`.",
          ),
        ),
      )
    None => ()
  }
  if storybook_template_files.is_empty() {
    return Done(
      error_emit(
        opts,
        err(
          CODE_STORYBOOK_TEMPLATE_MISSING,
          "no storybook template embedded in this binary",
          hint="regenerate with `moon run --target native cmd/dev -- storybook-template-embed` and rebuild",
        ),
      ),
    )
  }
  let target = if dir == "" { name } else { dir }
  let files : Array[(String, String)] = []
  for pair in storybook_template_files {
    files.push(
      (
        substitute_storybook_name(pair.0, name),
        substitute_storybook_name(pair.1, name),
      ),
    )
  }
  if dry_run {
    let sb = StringBuilder()
    sb.write_string("would scaffold storybook '\{name}' → \{target}/\n")
    for pair in files {
      sb.write_string("  + \{pair.0}\n")
    }
    return Done({ out: sb.to_string(), err: "", exit_code: 0, })
  }
  NewStorybook(opts, plan={ dir: target, name, force, files, })
}

///|
/// The already-exists refusal, pre-rendered for the shell once it has found a
/// file it would overwrite. Scaffolding into a directory someone has been
/// working in is the one way this command can destroy work, so it refuses on
/// the FIRST collision rather than asking afterwards.
pub fn new_storybook_target_exists(opts : GlobalOpts, dir : String) -> Emit {
  error_emit(
    opts,
    err(
      CODE_STORYBOOK_TARGET_EXISTS,
      "\{dir} already contains project files",
      hint="Re-run with --force to overwrite, or --dry-run to see what would change.",
    ),
  )
}

///|
/// What the shell prints after writing: the two commands in order, and the one
/// idea a gallery is built on — a story is an example on a module, so the way
/// to add one is to declare it where the component lives.
pub fn new_storybook_success(name : String, dir : String) -> String {
  "scaffolded storybook '\{name}' → \{dir}/\n" +
  "\n" +
  "  cd \{dir}\n" +
  "  node build.mjs           # moon build --target wasm-gc --release page → dist/\n" +
  "  tutuca storybook dist    # or any static server over dist/\n" +
  "\n" +
  "A story is an example on a ModuleDef: add one to `examples=[...]` and it\n" +
  "shows up in the gallery — and in `@harness.mount_example` — with no list to\n" +
  "edit. Start in page/main.mbt; see README.md in the new directory.\n"
}

///|
/// `temp-conv` -> `TempConv`: the struct and component name.
fn pascal_case(name : String) -> String {
  let sb = StringBuilder()
  let mut upper = true
  for c in name {
    if c == '-' {
      upper = true
    } else if upper {
      sb.write_char(c.to_ascii_uppercase())
      upper = false
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// `temp-conv` -> `temp_conv`: the file stem and function prefix. A MoonBit
/// identifier cannot hold a hyphen, and a file named with one cannot be a
/// module path either.
fn snake_case(name : String) -> String {
  let sb = StringBuilder()
  for c in name {
    sb.write_char(if c == '-' { '_' } else { c })
  }
  sb.to_string()
}
