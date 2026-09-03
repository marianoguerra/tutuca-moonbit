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
/// even with `recursive=true`, so guard on `exists` first (same as cmd/tutuca).
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
/// Where the guest template's three sources live, and where each lands in the
/// tree `new-guest` writes out.
///
/// The bindings and the SDK are BORROWED from `guests/counter` rather than kept
/// as a sixth copy: that guest is regenerated from the WIT, drift-checked, built
/// by `guests`, and driven by `dyncomp/test` — so a template taken from it
/// cannot quietly rot the way a hand-maintained one would. Its own component
/// source and README are dropped; `guests/template/` supplies replacements that
/// carry placeholders.
const TEMPLATE_GUEST : String = "guests/counter"

///|
const TEMPLATE_OVERLAY : String = "guests/template"

///|
/// The ONE WIT, read at embed time. It is deliberately NOT copied into
/// `guests/template/wit/`: `.gitignore` allows exactly `dyncomp/wit/*.wit`, and
/// a second checked-in copy is the drift this repo has gone out of its way to
/// make impossible.
const TEMPLATE_WIT : String = "dyncomp/wit/tutuca-component.wit"

///|
/// The gallery project `tutuca new-storybook` writes out. One hand-written
/// tree, unlike the guest template's three sources — a gallery borrows no
/// generated bindings, only a demo component whose view module is kept honest
/// by the `gen` sweep.
const STORYBOOK_TEMPLATE : String = "storybook/template"

///|
/// The author's component source, inside the generated guest package — the one
/// place a `declare` can be implemented and a method on `Instance` defined.
const TEMPLATE_GUEST_PKG : String = "gen/interface/tutuca/component/guest"

///|
/// Lexicographic path order. `String::compare` orders by LENGTH first, which is
/// deterministic — enough for a reproducible embed — but lists a directory tree
/// in an order nobody can follow, and `new-guest --dry-run` prints this list to
/// a person. Compare character by character instead.
fn path_before(a : String, b : String) -> Int {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return if a[i] < b[i] { -1 } else { 1 }
    }
  }
  a.length() - b.length()
}

///|
/// Build output inside the borrowed guest tree. `guests/counter` is a working
/// guest, so it has been built, and `_build/`/`dist/` hold wasm — bytes that
/// are not text, let alone text worth shipping to someone starting a new guest.
fn is_build_output(rel : String) -> Bool {
  rel.has_prefix("_build/") ||
  rel.has_prefix("dist/") ||
  rel.has_prefix("target/")
}

///|
/// What the borrowed guest tree does NOT contribute: its build output, and the
/// files the overlay replaces with placeholder-carrying versions.
fn skip_from_guest(rel : String) -> Bool {
  let own_source = TEMPLATE_GUEST_PKG + "/counter.mbt"
  rel == "README.md" ||
  rel == "manifest.json" ||
  rel.has_prefix("views/") ||
  rel == own_source ||
  is_build_output(rel)
}

///|
/// Where an overlay file lands. `.tmpl` marks a file that carries placeholders
/// and therefore cannot compile in place; `dot.gitignore` is spelled without
/// the dot so it does not act on `guests/template/` itself.
fn overlay_dest(rel : String) -> String {
  match rel {
    "component.mbt.tmpl" => "\{TEMPLATE_GUEST_PKG}/{{name_ident}}.mbt"
    "dot.gitignore" => ".gitignore"
    _ =>
      if rel.has_suffix(".tmpl") {
        rel[0:rel.length() - 5].to_owned()
      } else {
        rel
      }
  }
}

///|
/// Where a storybook-template file lands. `.tmpl` marks a file carrying
/// placeholders, or one whose real name would make the template a package of
/// THIS module (`moon.pkg`, `moon.mod`); `dot.gitignore` is spelled without the
/// dot so it does not act on `storybook/template/` itself.
fn storybook_dest(rel : String) -> String {
  match rel {
    "dot.gitignore" => ".gitignore"
    _ =>
      if rel.has_suffix(".tmpl") {
        rel[0:rel.length() - 5].to_owned()
      } else {
        rel
      }
  }
}

///|
/// Embed the storybook template and write the generated module to `to`. Paths
/// are sorted so two runs on the same tree agree.
async fn gen_storybook_template(to : String) -> Int noraise {
  try {
    let files : Array[(String, String)] = []
    for rel in walk_rel(STORYBOOK_TEMPLATE, "") {
      if is_build_output(rel) {
        continue
      }
      files.push(
        (
          storybook_dest(rel),
          @fs.read_file("\{STORYBOOK_TEMPLATE}/\{rel}").text(),
        ),
      )
    }
    if files.is_empty() {
      err("  ✗ no storybook template files found\n")
      return 1
    }
    files.sort_by(fn(a, b) { path_before(a.0, b.0) })
    @fs.write_file(
      to,
      @tasks.storybook_template_source(files),
      create_mode=CreateOrTruncate,
    )
    out("  \{files.length()} files embedded\n")
    0
  } catch {
    e => {
      err("  ✗ storybook-template-embed -> \{to}: \{e}\n")
      1
    }
  }
}

///|
/// Assemble the guest template from its three sources and write the generated
/// module to `to`. Paths are sorted so two runs on the same tree agree.
async fn gen_guest_template(to : String) -> Int noraise {
  try {
    let files : Array[(String, String)] = []
    // 1. the checked-in bindings + SDK, minus what the overlay replaces
    for rel in walk_rel(TEMPLATE_GUEST, "") {
      if skip_from_guest(rel) {
        continue
      }
      files.push((rel, @fs.read_file("\{TEMPLATE_GUEST}/\{rel}").text()))
    }
    // 2. the contract, at the path build.mjs embeds from
    files.push(("wit/tutuca-component.wit", @fs.read_file(TEMPLATE_WIT).text()))
    // 3. the hand-written overlay
    for rel in walk_rel(TEMPLATE_OVERLAY, "") {
      files.push(
        (overlay_dest(rel), @fs.read_file("\{TEMPLATE_OVERLAY}/\{rel}").text()),
      )
    }
    if files.is_empty() {
      err("  ✗ no guest template files found\n")
      return 1
    }
    files.sort_by(fn(a, b) { path_before(a.0, b.0) })
    @fs.write_file(
      to,
      @tasks.guest_template_source(files),
      create_mode=CreateOrTruncate,
    )
    out("  \{files.length()} files embedded\n")
    0
  } catch {
    e => {
      err("  ✗ guest-template-embed -> \{to}: \{e}\n")
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
    GenStorybookTemplate(to~) => {
      out("• storybook-template-embed -> \{to}\n")
      gen_storybook_template(to)
    }
    GenGuestTemplate(to~) => {
      out("› guest-template-embed -> \{to}\n")
      gen_guest_template(to)
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
