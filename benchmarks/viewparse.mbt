// The view-pipeline workload, split into the stages `tutuca gen-views` runs so
// a profile can be attributed to one of them.
//
// Every stage returns a checksum that depends on its whole output, so nothing
// can be optimized away, and the numbers double as a correctness canary: a
// change that alters the generated text changes the checksum.
//
// The stages don't raise: a GenError on this input means the workload itself is
// broken, which is a bug to abort on, not a case to measure.

///|
/// Stage 1: source text -> per-component raw view sources.
pub fn split() -> Int {
  let file = split_workload()
  let mut n = file.macros.length()
  for c in file.components {
    n = n + c.name.length() + c.common_style.length() + c.global_style.length()
    for v in c.views {
      n = n + v.name.length() + v.source.length() + v.style.length()
    }
  }
  n
}

///|
/// Stage 2: compile every view and extract its typed surface. This is where the
/// views actually go through @anode (and, under it, the HTML parser).
pub fn surface() -> Int {
  let file = split_workload()
  let mut n = 0
  for c in file.components {
    let s = @viewgen.view_surface(c.views, macros=file.macros) catch {
      e => fail_stage("surface", e)
    }
    n = n + s.inputs.length() + s.methods.length() + s.fields.length()
    n = n + s.ids.length()
  }
  n
}

///|
/// Stage 3: build the compiled views without emitting anything — the value the
/// generated IR module reconstructs.
pub fn build() -> Int {
  let file = split_workload()
  let mut n = 0
  for c in file.components {
    n = n +
      (@viewgen.build_views(c, macros=file.macros) catch {
        e => fail_stage("build", e)
      }).length()
  }
  n
}

///|
/// The whole thing, exactly as cli/gen_views.mbt drives it: split, emit the
/// types module, then the companion IR module.
pub fn gen() -> Int {
  let file = split_workload()
  try {
    let mut n = @viewgen.emit_module(WORKLOAD_NAME, WORKLOAD_FILE, file).length()
    if @viewgen.ir_supported(file) {
      n = n +
        @viewgen.emit_ir_module(WORKLOAD_NAME, WORKLOAD_FILE, file).length()
    }
    n
  } catch {
    e => fail_stage("gen", e)
  }
}

///|
/// The component-name fallback and cited source file the emitters want. The
/// workload names every component, so the fallback is never used.
const WORKLOAD_NAME = "Bench"

///|
const WORKLOAD_FILE = "all_views.html"

///|
fn split_workload() -> @viewgen.ViewFile {
  @viewgen.split_file(all_views) catch {
    e => fail_stage("split", e)
  }
}

///|
fn[T] fail_stage(stage : String, e : @viewgen.GenError) -> T {
  abort("benchmark stage \{stage}: \{@viewgen.GenError::message(e)}")
}

///|
/// One entry per named workload, so the executable shell and the `moon bench`
/// blocks agree on the set.
pub let stages : Array[(String, () -> Int)] = [
  ("split", split),
  ("surface", surface),
  ("build", build),
  ("gen", gen),
]
