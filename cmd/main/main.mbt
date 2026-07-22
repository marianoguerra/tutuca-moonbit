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
/// Message fallback like the JS CLI: piped stdin when no positional was
/// given (feedback.js readStdinSync — returns "" on a TTY or a read error).
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
  emit_and_exit({ out: @cli.feedback_success_line(file), err: "", exit_code: 0 })
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
    // refuse to clobber an existing install unless --force (JS checks for
    // any .md file under the target)
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
/// The shell half of `gen-views`: read the input .html, hand it to the pure
/// generator, write (or under --dry-run print) what it plans. Unlike
/// install-skill this DOES overwrite without asking — regenerating a
/// generated file in place is the whole workflow.
async fn run_gen_views(
  opts : @cli.GlobalOpts,
  input : String,
  target : String,
  name : String,
  dry_run : Bool,
  ir : Bool,
) -> Unit noraise {
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
  let plan = match @cli.gen_views(source, name~, input~, target~, ir~) {
    Ok(plan) => plan
    Err(shape) => {
      emit_and_exit(@cli.error_emit(opts, shape))
      return
    }
  }
  if dry_run {
    let sb = StringBuilder::new()
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
    out: plan.files.map(f => @cli.gen_views_success(f.0, input)).join(""),
    err: plan.diagnostics.map(d => d + "\n").join(""),
    exit_code: 0,
  })
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
/// Regenerate one view file, reporting either outcome. Returns nothing: a
/// failed view is a message, not the end of the watch — the next save is
/// expected to fix it.
async fn regenerate(path : String, plan : @cli.WatchPlan) -> Unit noraise {
  let source = @fs.read_file(path).text() catch {
    e => {
      write_out(@cli.watch_error_line("\{path}: cannot read: \{e}"))
      return
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
    Err(shape) => write_out(@cli.watch_error_line(shape.message))
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
  for f in files {
    regenerate(f, plan)
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
      regenerate(e.path, plan)
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
    ServeStorybook(opts, dir~, port~, out~) =>
      run_serve_storybook(opts, dir, port, out)
    GenViews(opts, input~, target~, name~, dry_run~, ir~) =>
      run_gen_views(opts, input, target, name, dry_run, ir)
    Watch(opts, plan~) => run_watch(opts, plan)
  }
}
