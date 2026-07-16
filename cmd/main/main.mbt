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
async fn main {
  // args()[0] is the program name, like process.argv[1] under node.
  let argv = @env.args().iter().drop(1).to_array()
  match @cli.plan(argv) {
    Done(emit) => emit_and_exit(emit)
    Feedback(opts, message~) => run_feedback(opts, message)
    InstallSkill(opts, plan~) => run_install_skill(opts, plan)
    ServeStorybook(opts, dir~, port~, out~) =>
      run_serve_storybook(opts, dir, port, out)
  }
}
