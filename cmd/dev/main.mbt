// Native shell for the tutuca dev task runner. All task knowledge lives in the
// pure @dev package; this file only reads argv, spawns processes, does fs, and
// exits. Run with: moon run --target native cmd/dev -- <task>

///|
extern "c" fn process_exit(code : Int) = "exit"

///|
async fn out(text : String) -> Unit noraise {
  @stdio.stdout.write(text) catch {
    _ => ()
  }
}

///|
async fn err(text : String) -> Unit noraise {
  @stdio.stderr.write(text) catch {
    _ => ()
  }
}

///|
/// Ensure a directory exists. `@fs.mkdir` raises when the dir already exists,
/// even with `recursive=true`, so guard on `exists` first (same as cmd/main).
async fn ensure_dir(path : String) -> Int noraise {
  try {
    if !@fs.exists(path) {
      @fs.mkdir(path, recursive=true)
    }
    0
  } catch {
    e => {
      err("  ✗ mkdir \{path}: \{e}\n")
      1
    }
  }
}

///|
async fn copy_file(from : String, to : String) -> Int noraise {
  try {
    let data = @fs.read_file(from)
    // 0o755 so the copied native CLI binary stays executable; harmless for js.
    @fs.write_file(to, data, create_mode=CreateOrTruncate, permission=0o755)
    0
  } catch {
    e => {
      err("  ✗ copy \{from} -> \{to}: \{e}\n")
      1
    }
  }
}

///|
async fn write_rewritten(
  from : String,
  to : String,
  old_src : String,
  new_src : String,
) -> Int noraise {
  try {
    let text = @fs.read_file(from).text()
    let html = @tasks.rewrite(text, old_src~, new_src~)
    @fs.write_file(to, html, create_mode=CreateOrTruncate)
    0
  } catch {
    e => {
      err("  ✗ rewrite \{from} -> \{to}: \{e}\n")
      1
    }
  }
}

///|
/// Depth-first file walk relative to `root`; returns sorted relative paths.
async fn walk_rel(root : String, prefix : String) -> Array[String] {
  let out : Array[String] = []
  let names = @fs.readdir(
    "\{root}/\{prefix}".trim(chars="/").to_owned(),
    sort=true,
  )
  for name in names {
    let rel = if prefix == "" { name } else { "\{prefix}/\{name}" }
    match @fs.kind("\{root}/\{rel}") {
      Directory => out.append(walk_rel(root, rel))
      _ => out.push(rel)
    }
  }
  out
}

///|
/// The skill-embed codegen: walk `src_dir`, read every file, write the
/// generated MoonBit module (@tasks.skill_assets_source) to `to`.
async fn gen_skill_assets(src_dir : String, to : String) -> Int noraise {
  try {
    let files : Array[(String, String)] = []
    for rel in walk_rel(src_dir, "") {
      files.push((rel, @fs.read_file("\{src_dir}/\{rel}").text()))
    }
    if files.is_empty() {
      err("  ✗ no skill files found under \{src_dir}\n")
      return 1
    }
    @fs.write_file(
      to,
      @tasks.skill_assets_source(files),
      create_mode=CreateOrTruncate,
    )
    out("  \{files.length()} files embedded\n")
    0
  } catch {
    e => {
      err("  ✗ skill-embed \{src_dir} -> \{to}: \{e}\n")
      1
    }
  }
}

///|
/// Run one step; returns the process/op exit code (0 = ok).
async fn run_step(step : @tasks.Step) -> Int noraise {
  match step {
    Run(cmd) => {
      out("› \{cmd.label}\n")
      @process.run(cmd.prog, cmd.args) catch {
        e => {
          err("  ✗ \{cmd.prog}: \{e}\n")
          1
        }
      }
    }
    Mkdir(path) => ensure_dir(path)
    Copy(from~, to~) => {
      out("› copy \{to}\n")
      copy_file(from, to)
    }
    WriteRewritten(from~, to~, old_src~, new_src~) => {
      out("› write \{to}\n")
      write_rewritten(from, to, old_src, new_src)
    }
    GenSkillAssets(src_dir~, to~) => {
      out("› skill-embed \{src_dir} -> \{to}\n")
      gen_skill_assets(src_dir, to)
    }
  }
}

///|
async fn run_all(steps : Array[@tasks.Step]) -> Unit noraise {
  for step in steps {
    let code = run_step(step)
    if code != 0 {
      process_exit(code)
    }
  }
  process_exit(0)
}

///|
async fn main {
  // args()[0] is the program name; the task name is the first real argument.
  let argv = @env.args().iter().drop(1).to_array()
  match argv.get(0) {
    None => {
      out(@tasks.help_text())
      process_exit(0)
    }
    Some(name) =>
      match @tasks.plan(name) {
        Some(steps) => run_all(steps)
        None => {
          err(@tasks.help_text())
          err("\nunknown task: \{name}\n")
          process_exit(2)
        }
      }
  }
}
