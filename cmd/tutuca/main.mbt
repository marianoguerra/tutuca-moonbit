// Native shell for the tutuca CLI. All parsing/dispatch/rendering is in the
// pure @cli package; this file only does argv, stdio, stdin, fs and exit.

///|
extern "c" fn process_exit(code : Int) = "exit"

///|
extern "c" fn isatty(fd : Int) -> Int = "isatty"

///|
async fn emit_and_exit(emit : @cli.Emit) -> Unit noraise {
  if emit.out != "" {
    @stdio.stdout.write(emit.out) catch {
      _ => ()
    }
  }
  if emit.err != "" {
    @stdio.stderr.write(emit.err) catch {
      _ => ()
    }
  }
  process_exit(emit.exit_code)
}

///|
/// Message fallback: piped stdin when no positional was
/// given (returns "" on a TTY or a read error).
async fn read_stdin_message() -> String noraise {
  if isatty(0) != 0 {
    return ""
  }
  @stdio.stdin.read_all().text() catch {
    _ => ""
  }
}

///|
async fn run_feedback(
  opts : @cli.GlobalOpts,
  message : String?,
) -> Unit noraise {
  let msg = match message {
    Some(m) => m
    None => read_stdin_message().trim(chars=" \t\r\n").to_owned()
  }
  if msg == "" {
    emit_and_exit(@cli.feedback_missing_message(opts))
  }
  guard @env.get_env_var("HOME") is Some(home) && home != "" else {
    emit_and_exit(
      @cli.error_emit(
        opts,
        @cli.err(
          @cli.CODE_INTERNAL,
          "cannot determine home directory (HOME unset)",
        ),
      ),
    )
  }
  let (dir, file) = @cli.feedback_paths(home)
  let line = @cli.feedback_record_line(
    @cli.iso8601_utc(@env.now()),
    @cli.VERSION,
    msg,
  )
  try {
    // @fs.mkdir raises even with recursive=true when the dir already exists.
    if !@fs.exists(dir) {
      @fs.mkdir(dir, recursive=true)
    }
    @fs.write_file(file, line, append=true, create_mode=OpenOrCreate)
  } catch {
    e =>
      emit_and_exit(
        @cli.error_emit(
          opts,
          @cli.err(@cli.CODE_INTERNAL, "failed to record feedback: \{e}"),
        ),
      )
  }
  emit_and_exit({
    out: @cli.feedback_success_line(file),
    err: "",
    exit_code: 0,
  })
}

///|
/// Directory of a path like "patterns/foo.md" ("" when it has none).
fn parent_dir(path : String) -> String {
  let mut last = -1
  let chars : Array[Char] = path.iter().collect()
  for i in 0..<chars.length() {
    if chars[i] == '/' {
      last = i
    }
  }
  if last < 0 {
    ""
  } else {
    path[:last].to_owned()
  }
}

///|
/// Write the embedded skill files (the shell half of `install-skill`):
/// resolve the base dir, refuse to overwrite existing skill files unless
/// --force, then mkdir + write everything in the plan.
async fn run_install_skill(
  opts : @cli.GlobalOpts,
  plan : @cli.SkillInstallPlan,
) -> Unit noraise {
  let mut base = "."
  if plan.user_scope {
    match @env.get_env_var("HOME") {
      Some(home) if home != "" => base = home
      _ => {
        emit_and_exit(
          @cli.error_emit(
            opts,
            @cli.err(
              @cli.CODE_INTERNAL,
              "cannot determine home directory (HOME unset)",
            ),
          ),
        )
        return
      }
    }
  }
  let target = "\{base}/\{plan.target_rel}"
  let shown = if plan.user_scope {
    "~/\{plan.target_rel}"
  } else {
    plan.target_rel
  }
  try {
    // refuse to clobber an existing install unless --force
    if !plan.force && @fs.exists(target) {
      for pair in plan.files {
        if @fs.exists("\{target}/\{pair.0}") {
          emit_and_exit(@cli.install_skill_target_exists(opts, shown))
        }
      }
    }
    for pair in plan.files {
      let (rel, contents) = pair
      let dir = match parent_dir(rel) {
        "" => target
        d => "\{target}/\{d}"
      }
      if !@fs.exists(dir) {
        @fs.mkdir(dir, recursive=true)
      }
      @fs.write_file("\{target}/\{rel}", contents, create_mode=CreateOrTruncate)
    }
  } catch {
    e =>
      emit_and_exit(
        @cli.error_emit(
          opts,
          @cli.err(@cli.CODE_INTERNAL, "failed to install skill: \{e}"),
        ),
      )
  }
  emit_and_exit({
    out: @cli.install_skill_success(shown),
    err: "",
    exit_code: 0,
  })
}

///|
/// Write a scaffolded tree under `target`: create directories, refuse to
/// clobber without `--force`, write every file. The core has already decided
/// every path and every byte, placeholders and all, so this is the whole of the
/// shell half of a scaffolding command.
///
/// Shared by `new-guest` and `new-storybook`, which differ only in what they
/// print. The refusal is on the FIRST collision rather than afterwards:
/// scaffolding into a directory someone has been working in is the one way
/// these commands can destroy work.
async fn write_tree(
  opts : @cli.GlobalOpts,
  target : String,
  files : Array[(String, String)],
  force~ : Bool,
  exists_emit~ : () -> @cli.Emit,
  what~ : String,
) -> Unit noraise {
  try {
    if !force && @fs.exists(target) {
      for pair in files {
        if @fs.exists("\{target}/\{pair.0}") {
          emit_and_exit(exists_emit())
        }
      }
    }
    for pair in files {
      let (rel, contents) = pair
      let dir = match parent_dir(rel) {
        "" => target
        d => "\{target}/\{d}"
      }
      if !@fs.exists(dir) {
        @fs.mkdir(dir, recursive=true)
      }
      @fs.write_file("\{target}/\{rel}", contents, create_mode=CreateOrTruncate)
    }
  } catch {
    e =>
      emit_and_exit(
        @cli.error_emit(
          opts,
          @cli.err(@cli.CODE_INTERNAL, "failed to scaffold \{what}: \{e}"),
        ),
      )
  }
}

///|
/// Write the scaffolded guest tree (the shell half of `new-guest`).
async fn run_new_guest(
  opts : @cli.GlobalOpts,
  plan : @cli.GuestScaffoldPlan,
) -> Unit noraise {
  let target = plan.dir
  write_tree(
    opts,
    target,
    plan.files,
    force=plan.force,
    exists_emit=() => @cli.new_guest_target_exists(opts, target),
    what="guest",
  )
  emit_and_exit({
    out: @cli.new_guest_success(plan.name, target),
    err: "",
    exit_code: 0,
  })
}

///|
/// Write the scaffolded gallery project (the shell half of `new-storybook`).
async fn run_new_storybook(
  opts : @cli.GlobalOpts,
  plan : @cli.StorybookScaffoldPlan,
) -> Unit noraise {
  let target = plan.dir
  write_tree(
    opts,
    target,
    plan.files,
    force=plan.force,
    exists_emit=() => @cli.new_storybook_target_exists(opts, target),
    what="storybook",
  )
  emit_and_exit({
    out: @cli.new_storybook_success(plan.name, target),
    err: "",
    exit_code: 0,
  })
}

///|
/// The shell half of `gen-views`: read the input .html, hand it to the pure
/// generator, write (or under --dry-run print) what it plans. Unlike
/// install-skill this DOES overwrite without asking — regenerating a
/// generated file in place is the whole workflow.
async fn run_gen_views(
  opts : @cli.GlobalOpts,
  roots : Array[String],
  out : String?,
  name : String?,
  dry_run : Bool,
  ir : Bool,
) -> Unit noraise {
  // The same expansion `watch` and the CSS commands use: an explicit .html at
  // its word, a directory contributing the files that already have a generated
  // sibling. That is what tells a view file from a page.
  let paths = collect_view_files(roots)
  if paths.is_empty() {
    emit_and_exit(
      @cli.error_emit(
        opts,
        @cli.err(
          @cli.CODE_USAGE_MISSING_ARGUMENT,
          "no view files under \{roots.join(", ")}",
          hint="a directory contributes the .html files that already have a generated sibling; pass the .html path directly the first time",
        ),
      ),
    )
    return
  }
  let inputs : Array[@cli.GenInput] = []
  for input in paths {
    let source = @fs.read_file(input).text() catch {
      e => {
        emit_and_exit(
          @cli.error_emit(
            opts,
            @cli.err(
              @cli.CODE_INTERNAL,
              "cannot read \{input}: \{e}",
              hint="pass the path to the .html file holding the component's views",
            ),
          ),
        )
        return
      }
    }
    let (target, comp) = @cli.gen_views_target(input, out?, name?)
    inputs.push({ input, target, name: comp, source, })
  }
  let plan = match @cli.gen_views_all(inputs, ir~) {
    Ok(plan) => plan
    Err(shape) => {
      emit_and_exit(@cli.error_emit(opts, shape))
      return
    }
  }
  if dry_run {
    let sb = StringBuilder()
    for pair in plan.files {
      sb.write_string(pair.1)
    }
    emit_and_exit({
      out: sb.to_string(),
      err: plan.diagnostics.map(d => d + "\n").join(""),
      exit_code: 0,
    })
  }
  try {
    for pair in plan.files {
      let (path, contents) = pair
      let dir = parent_dir(path)
      if dir != "" && !@fs.exists(dir) {
        @fs.mkdir(dir, recursive=true)
      }
      @fs.write_file(path, contents, create_mode=CreateOrTruncate)
    }
  } catch {
    e =>
      emit_and_exit(
        @cli.error_emit(
          opts,
          @cli.err(@cli.CODE_INTERNAL, "failed to write generated views: \{e}"),
        ),
      )
  }
  emit_and_exit({
    out: plan.files
    .map(f => @cli.gen_views_success(f.0, from_input(inputs, f.0)))
    .join(""),
    err: plan.diagnostics.map(d => d + "\n").join(""),
    exit_code: 0,
  })
}

///|
/// The shell half of `tutuca migrate`: read every view file under the roots,
/// let the pure core decide the edits, and — only under `--write` — write the
/// ones that changed back.
///
/// The discovery rule is `gen-views`', deliberately: a migration is aimed at
/// the files a project treats as views, and `index.html` is not one.
///
/// A file that comes back unchanged is not rewritten. Not as an optimisation —
/// writing identical bytes would touch every mtime in the tree, and every
/// watcher, formatter and build cache downstream would act as though the whole
/// project had moved.
async fn run_migrate(
  opts : @cli.GlobalOpts,
  roots : Array[String],
  write : Bool,
) -> Unit noraise {
  let paths = collect_view_files(roots)
  if paths.is_empty() {
    emit_and_exit(
      @cli.error_emit(
        opts,
        @cli.err(
          @cli.CODE_USAGE_MISSING_ARGUMENT,
          "no view files under \{roots.join(", ")}",
          hint="a directory contributes the .html files that already have a generated sibling; pass the .html path directly otherwise",
        ),
      ),
    )
    return
  }
  let inputs : Array[(String, String)] = []
  for path in paths {
    let source = @fs.read_file(path).text() catch {
      e => {
        emit_and_exit(
          @cli.error_emit(
            opts,
            @cli.err(@cli.CODE_INTERNAL, "cannot read \{path}: \{e}"),
          ),
        )
        return
      }
    }
    inputs.push((path, source))
  }
  let plan = @cli.migrate_all(inputs)
  if write {
    for i in 0..<plan.files.length() {
      let f = plan.files[i]
      guard f.out is Some(out) else { continue }
      if out == inputs[i].1 {
        continue
      }
      @fs.write_file(f.path, out, create_mode=CreateOrTruncate) catch {
        e => {
          emit_and_exit(
            @cli.error_emit(
              opts,
              @cli.err(@cli.CODE_INTERNAL, "cannot write \{f.path}: \{e}"),
            ),
          )
          return
        }
      }
    }
  }
  emit_and_exit(@cli.migrate_emit(opts, plan, write))
}

///|
/// Which input a written file came from, for the "generated X from Y" line.
/// Both of a file's modules are derived from its target, so the mapping is the
/// same rule that produced the paths rather than a second guess at them.
fn from_input(inputs : Array[@cli.GenInput], written : String) -> String {
  for f in inputs {
    if f.target == written || @cli.gen_views_ir_target(f.target) == written {
      return f.input
    }
  }
  written
}

///|
/// The shell half of `gen-tailwind-css` / `gen-margaui-css`: walk the roots for
/// view files, read them, collect their classes through the pure core, compile
/// those into CSS, and write the result.
///
/// The discovery rule is `watch`'s, deliberately — an explicit .html is taken at
/// its word, a directory contributes the .html files that already have a
/// generated sibling. A project's views are exactly the gen-views-managed ones,
/// and the rule is what keeps `index.html` from being parsed as a view.
async fn run_gen_css(
  opts : @cli.GlobalOpts,
  plan : @cli.CssPlan,
) -> Unit noraise {
  let files = collect_view_files(plan.paths)
  if files.length() == 0 {
    emit_and_exit(
      @cli.error_emit(
        opts,
        @cli.err(
          @cli.CODE_USAGE_MISSING_ARGUMENT,
          "no view files found under \{plan.paths.join(", ")}",
          hint="a directory contributes the .html files that already have a <stem>_view_gen.mbt sibling; run `tutuca gen-views` first, or pass the .html paths directly",
        ),
      ),
    )
    return
  }
  let classes = match css_candidates(plan, files) {
    Ok(classes) => classes
    Err(shape) => {
      emit_and_exit(@cli.error_emit(opts, shape))
      return
    }
  }
  if plan.print_classes {
    emit_and_exit({ out: @cli.class_list_text(classes), err: "", exit_code: 0, })
    return
  }
  let css = match compile_css(plan, classes) {
    Ok(css) => css
    Err(shape) => {
      emit_and_exit(@cli.error_emit(opts, shape))
      return
    }
  }
  match plan.out {
    None => emit_and_exit({ out: css, err: "", exit_code: 0, })
    Some(target) =>
      match write_text_file(target, css) {
        Err(shape) => emit_and_exit(@cli.error_emit(opts, shape))
        Ok(_) =>
          emit_and_exit({
            out: @cli.gen_css_success(
              target,
              files=files.length(),
              classes=classes.length(),
            ),
            err: "",
            exit_code: 0,
          })
      }
  }
}

// The CSS build in three steps. They return an ErrShape instead of exiting so
// `watch` can report a failure and stay in its loop — a view saved mid-edit must
// not kill the watcher, and neither must a stylesheet that briefly cannot build.

///|
/// Read `files`, collect the literal classes their views use, and merge in the
/// `--classes` candidates.
async fn css_candidates(
  plan : @cli.CssPlan,
  files : Array[String],
) -> Result[Array[String], @cli.ErrShape] noraise {
  let sources : Array[(String, String)] = []
  for path in files {
    let source = @fs.read_file(path).text() catch {
      e => return Err(@cli.err(@cli.CODE_INTERNAL, "cannot read \{path}: \{e}"))
    }
    sources.push((path, source))
  }
  let classes = match @cli.collect_view_classes(sources) {
    Ok(classes) => classes
    Err(shape) => return Err(shape)
  }
  // Names the collector cannot see because the view assembles them at run time.
  // Merged through a Set so a candidate listed in both places is not duplicated,
  // then re-sorted so the output does not depend on which source it came from.
  match plan.extra_classes {
    None => ()
    Some(path) => {
      let extra = @fs.read_file(path).text() catch {
        e =>
          return Err(@cli.err(@cli.CODE_INTERNAL, "cannot read \{path}: \{e}"))
      }
      let merged : Set[String] = Set([])
      for c in classes {
        merged.add(c)
      }
      for line in extra.split("\n") {
        let name = line.trim(chars=" \t\r").to_owned()
        if name != "" {
          merged.add(name)
        }
      }
      classes.clear()
      for c in merged {
        classes.push(c)
      }
      classes.sort_by(@cli.lex_compare)
    }
  }
  Ok(classes)
}

///|
/// Compile `classes` against the stylesheets the plan asks for.
///
/// The embedded path is sync and target-agnostic (the `css` package resolves its
/// `@import` graph from a bundle compiled in). `--entry` is the filesystem path:
/// a project's own entry, whose imports the async loader resolves from disk —
/// the same shape `marianoguerra/tailwindcss`'s own CLI uses.
async fn compile_css(
  plan : @cli.CssPlan,
  classes : Array[String],
) -> Result[String, @cli.ErrShape] noraise {
  match plan.entry {
    Some(path) => {
      let source = @fs.read_file(path).text() catch {
        e =>
          return Err(@cli.err(@cli.CODE_INTERNAL, "cannot read \{path}: \{e}"))
      }
      let css = @tw.compile(
        source,
        options=@tw.CompileOptions::new(
          base=parent_dir(path),
          from=path,
          loader=@twfs.FsStylesheetLoader::new(),
          polyfills=plan.polyfills,
        ),
      ).build(classes) catch {
        e =>
          return Err(
            @cli.err(
              @cli.CODE_INTERNAL,
              "\{e}",
              hint="--entry resolves the stylesheet's @imports relative to its own directory",
              where_=path,
            ),
          )
      }
      Ok(css)
    }
    None => {
      let css = try {
        if plan.margaui {
          @css.compile_margaui(classes, polyfills=plan.polyfills)
        } else {
          @css.compile_tailwind(classes, polyfills=plan.polyfills)
        }
      } catch {
        e =>
          return Err(
            @cli.err(
              @cli.CODE_INTERNAL,
              "compiling the embedded stylesheets failed: \{e}",
            ),
          )
      }
      Ok(css)
    }
  }
}

///|
/// Write a file, making its directory first.
///
/// Named for what it does rather than for the first command that wanted it:
/// a stylesheet and a trimmed trace are the same job, and a `write_css` that
/// writes traces is a name that has stopped being true.
async fn write_text_file(
  target : String,
  text : String,
) -> Result[Unit, @cli.ErrShape] noraise {
  try {
    let dir = parent_dir(target)
    if dir != "" && !@fs.exists(dir) {
      @fs.mkdir(dir, recursive=true)
    }
    @fs.write_file(target, text, create_mode=CreateOrTruncate)
    Ok(())
  } catch {
    e => Err(@cli.err(@cli.CODE_INTERNAL, "failed to write \{target}: \{e}"))
  }
}

///|
/// Rebuild the stylesheet `watch` was asked to keep current.
///
/// Over EVERY watched view, not just the changed ones: a stylesheet is a
/// whole-project artifact, so a class dropped from the file you just saved has
/// to disappear from it too. Failures print and the loop continues.
async fn refresh_watch_css(
  plan : @cli.CssPlan,
  files : Array[String],
  reported~ : Map[String, Bool],
) -> Unit noraise {
  guard plan.out is Some(target) else { return }
  let classes = match css_candidates(plan, files) {
    Ok(classes) => classes
    Err(shape) => {
      // A view that will not parse has already been reported, file by file, by
      // the regenerate pass — and it is the same message. Only say something
      // the run of ✗ lines above does not already say.
      //
      // Which file it was, not just which code: the two passes agreeing on
      // every file is a PROPERTY, and a bug in it is exactly what this line
      // hides. One did — the CSS pass built views without their schema, so it
      // refused an `@bind` file the regenerate pass had just written a ✓ for,
      // and the stylesheet stopped rebuilding without a word on screen.
      let seen = shape.where_ is Some(path) && reported.contains(path)
      if !(shape.code == @cli.CODE_VIEW_GEN_FAILED && seen) {
        write_out(@cli.watch_error_line(shape.message))
      }
      return
    }
  }
  let css = match compile_css(plan, classes) {
    Ok(css) => css
    Err(shape) => {
      write_out(@cli.watch_error_line(shape.message))
      return
    }
  }
  match write_text_file(target, css) {
    Err(shape) => write_out(@cli.watch_error_line(shape.message))
    Ok(_) => write_out(@cli.watch_css_line(target, classes=classes.length()))
  }
}

///|
/// Every view file a watched path contributes.
///
/// An explicit .html path is taken at its word; a directory contributes the
/// .html files that already have a generated sibling. That rule is what
/// tells a view file from a page — watching a project root should not try to
/// compile index.html — and it means adding a view to a watched tree takes
/// one `tutuca gen-views` before watch picks it up.
async fn collect_view_files(paths : Array[String]) -> Array[String] noraise {
  let found : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  for p in paths {
    if @cli.is_view_path(p) {
      if !seen.contains(p) {
        seen[p] = true
        found.push(p)
      }
    } else {
      scan_dir(p, found, seen)
    }
  }
  found
}

///|
/// Directory names never worth descending into: build output and vendored
/// trees hold .html files that are pages, not views.
fn skip_dir(name : String) -> Bool {
  name
  is ("_build" | "target" | "dist" | ".git" | "node_modules" | ".mooncakes")
}

///|
async fn scan_dir(
  dir : String,
  found : Array[String],
  seen : Map[String, Bool],
) -> Unit noraise {
  let names = @fs.readdir(dir) catch { _ => return }
  for n in names {
    if skip_dir(n) {
      continue
    }
    let full = if dir.has_suffix("/") { dir + n } else { dir + "/" + n }
    let kind = @fs.kind(full) catch { _ => continue }
    if kind is Directory {
      scan_dir(full, found, seen)
    } else if @cli.is_view_path(full) && !seen.contains(full) {
      let managed = @fs.exists(@cli.watch_sibling(full)) catch { _ => false }
      if managed {
        seen[full] = true
        found.push(full)
      }
    }
  }
}

///|
/// The directories to hand the watcher: one per view file's parent, deduped.
fn watch_roots(files : Array[String], paths : Array[String]) -> Array[String] {
  let roots : Array[String] = []
  let seen : Map[String, Bool] = Map([])
  fn add(d : String) {
    let dir = if d == "" { "." } else { d }
    if !seen.contains(dir) {
      seen[dir] = true
      roots.push(dir)
    }
  }

  for f in files {
    add(parent_dir(f))
  }
  // With no view files yet there is still something to watch: the paths the
  // user named, so the first `gen-views` in that tree is picked up.
  if roots.is_empty() {
    for p in paths {
      add(if @cli.is_view_path(p) { parent_dir(p) } else { p })
    }
  }
  roots
}

///|
/// Regenerate one view file, reporting either outcome. A failed view is a
/// message, not the end of the watch — the next save is expected to fix it.
///
/// Answers whether it PRINTED a failure for this path, which is what lets
/// `refresh_watch_css` tell "the CSS pass is about to repeat a message already
/// on screen" from "the CSS pass found something this one did not".
async fn regenerate(path : String, plan : @cli.WatchPlan) -> Bool noraise {
  let source = @fs.read_file(path).text() catch {
    e => {
      write_out(@cli.watch_error_line("\{path}: cannot read: \{e}"))
      return true
    }
  }
  let target = @cli.watch_target(path, plan.out)
  match
    @cli.gen_views(
      source,
      name=@cli.watch_name(path, plan.name),
      input=path,
      target~,
      ir=plan.ir,
    ) {
    Err(shape) => {
      write_out(@cli.watch_error_line(shape.message))
      return true
    }
    Ok(gen) => {
      for d in gen.diagnostics {
        write_out(@cli.watch_error_line(d))
      }
      for pair in gen.files {
        let (p, contents) = pair
        try {
          let dir = parent_dir(p)
          if dir != "" && !@fs.exists(dir) {
            @fs.mkdir(dir, recursive=true)
          }
          @fs.write_file(p, contents, create_mode=CreateOrTruncate)
          write_out(@cli.watch_generated_line(p))
        } catch {
          e => write_out(@cli.watch_error_line("\{p}: cannot write: \{e}"))
        }
      }
    }
  }
  false
}

///|
async fn write_out(s : String) -> Unit noraise {
  @stdio.stdout.write(s) catch {
    _ => ()
  }
}

///|
/// The shell half of `watch`: resolve the view files, generate them once,
/// then regenerate on every change until interrupted.
async fn run_watch(
  opts : @cli.GlobalOpts,
  plan : @cli.WatchPlan,
) -> Unit noraise {
  let files = collect_view_files(plan.paths)
  let roots = watch_roots(files, plan.paths)
  write_out(@cli.watch_banner(files, roots))
  // Generate once up front so the tree is correct before the first edit,
  // not just after it.
  // The paths the regenerate pass has already printed a failure for, so the
  // CSS pass below can stay quiet about those and only those.
  let reported : Map[String, Bool] = Map([])
  for f in files {
    if regenerate(f, plan) {
      reported[f] = true
    } else {
      reported.remove(f)
    }
  }
  if plan.css is Some(css_plan) {
    refresh_watch_css(css_plan, files, reported~)
  }
  let watcher = @fswatch.start(roots) catch {
    e => {
      emit_and_exit(
        @cli.error_emit(
          opts,
          @cli.err(@cli.CODE_INTERNAL, "cannot watch \{roots.join(", ")}: \{e}"),
        ),
      )
      return
    }
  }
  defer watcher.close()
  for ;; {
    let events = watcher.next() catch {
      e => {
        write_out(@cli.watch_error_line("watch: \{e}"))
        return
      }
    }
    if events.length() == 0 {
      return
    }
    // One save can surface several events for the same file (write, then
    // metadata); regenerate each path once per drain.
    let done : Map[String, Bool] = Map([])
    let mut regenerated = false
    for e in events {
      if !@cli.is_view_path(e.path) || done.contains(e.path) {
        continue
      }
      done[e.path] = true
      if e.kind is Removed {
        continue
      }
      // A file created in a watched tree only counts once it is one we
      // manage — the same sibling rule the initial scan used.
      let known = files.contains(e.path)
      let managed = known ||
        (@fs.exists(@cli.watch_sibling(e.path)) catch { _ => false })
      if !managed {
        continue
      }
      if !known {
        files.push(e.path)
      }
      write_out("\{e.path}\n")
      // A file that regenerates cleanly this time drops out of `reported`:
      // the ✗ it printed on the last save is scrolled off and is no longer a
      // reason for the CSS pass to keep quiet about it.
      if regenerate(e.path, plan) {
        reported[e.path] = true
      } else {
        reported.remove(e.path)
      }
      regenerated = true
    }
    // Once per settled batch, not once per file: the stylesheet covers the
    // whole project, and compiling it is the expensive half of the loop.
    if regenerated && plan.css is Some(css_plan) {
      refresh_watch_css(css_plan, files, reported~)
    }
  }
}

///|
async fn main {
  // args()[0] is the program name, like process.argv[1] under node.
  let argv = @env.args().iter().drop(1).to_array()
  match @cli.plan(argv) {
    Done(emit) => emit_and_exit(emit)
    Feedback(opts, message~) => run_feedback(opts, message)
    InstallSkill(opts, plan~) => run_install_skill(opts, plan)
    NewGuest(opts, plan~) => run_new_guest(opts, plan)
    NewStorybook(opts, plan~) => run_new_storybook(opts, plan)
    ServeStorybook(opts, dir~, port~, out~) =>
      run_serve_storybook(opts, dir, port, out)
    GenViews(opts, roots~, out~, name~, dry_run~, ir~) =>
      run_gen_views(opts, roots, out, name, dry_run, ir)
    Migrate(opts, roots~, write~) => run_migrate(opts, roots, write)
    Watch(opts, plan~) => run_watch(opts, plan)
    GenCss(opts, plan~) => run_gen_css(opts, plan)
    Trace(opts, plan~) => run_trace(opts, plan)
  }
}

///|
/// `tutuca trace`: read the file, do the one thing, write the answer.
///
/// The core decides and performs the operation — `trace_apply` is text in,
/// text out — so what is left here is the two ends nothing pure can do.
async fn run_trace(
  opts : @cli.GlobalOpts,
  plan : @cli.TracePlan,
) -> Unit noraise {
  let source = @fs.read_file(plan.path).text() catch {
    e => {
      emit_and_exit(
        @cli.error_emit(
          opts,
          @cli.err(
            @cli.CODE_INTERNAL,
            "cannot read \{plan.path}: \{e}",
            hint="pass the path to a .trace.jsonl file",
          ),
        ),
      )
      return
    }
  }
  let result = match @cli.trace_apply(plan, source) {
    Ok(r) => r
    Err(shape) => {
      emit_and_exit(@cli.error_emit(opts, shape))
      return
    }
  }
  // Gaps are warnings beside a result, not an error instead of one: a
  // relocated trace missing something is usually missing something that did
  // not matter, and it is still worth having.
  let warnings = result.diagnostics.map(d => d + "\n").join("")
  match (result.file, plan.out) {
    // Nothing to write — `info` only reports.
    (None, _) =>
      emit_and_exit({ out: result.report, err: warnings, exit_code: 0, })
    // To a file, with the report going to stderr so the two never mix: what
    // was asked for is the FILE, and a summary printed into it would corrupt
    // the one thing this command produces.
    (Some(text), Some(target)) =>
      match write_text_file(target, text) {
        Ok(_) =>
          emit_and_exit({
            out: "",
            err: warnings + result.report,
            exit_code: 0,
          })
        Err(shape) => emit_and_exit(@cli.error_emit(opts, shape))
      }
    // To stdout, which makes the trace pipeable — so the REPORT goes to
    // stderr, or it would end up in whatever the pipe was feeding.
    (Some(text), None) =>
      emit_and_exit({ out: text, err: warnings + result.report, exit_code: 0, })
  }
}
