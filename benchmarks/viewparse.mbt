// The view-pipeline workload, split into the stages `tutuca gen-views` runs so
// a profile can be attributed to one of them, over either corpus (see
// corpus_gen.mbt): the same nodes as 108 small views, or as one enormous one.
//
// Every stage returns a checksum that depends on its whole output, so nothing
// can be optimized away, and the numbers double as a correctness canary: a
// change that alters the generated text changes the checksum.
//
// The stages don't raise: a GenError on this input means the workload itself is
// broken, which is a bug to abort on, not a case to measure.

///|
/// Stage 1: source text -> per-component raw view sources.
pub fn split(source : String) -> Int {
  let file = split_corpus(source)
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
pub fn surface(source : String) -> Int {
  let file = split_corpus(source)
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
pub fn build(source : String) -> Int {
  let file = split_corpus(source)
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
pub fn gen(source : String) -> Int {
  let file = split_corpus(source)
  let generated = @viewgen.emit_modules(WORKLOAD_NAME, WORKLOAD_FILE, file) catch {
    e => fail_stage("gen", e)
  }
  let mut n = generated.types_source.length()
  if generated.ir_source is Some(src) {
    n = n + src.length()
  }
  n
}

///|
/// The component-name fallback and cited source file the emitters want. Both
/// corpora name every component, so the fallback is never used.
const WORKLOAD_NAME = "Bench"

///|
const WORKLOAD_FILE = "corpus.html"

///|
fn split_corpus(source : String) -> @viewgen.ViewFile {
  @viewgen.split_file(source) catch {
    e => fail_stage("split", e)
  }
}

///|
fn[T] fail_stage(stage : String, e : @viewgen.GenError) -> T {
  abort("benchmark stage \{stage}: \{@viewgen.GenError::message(e)}")
}

///|
/// `one_big_view_body` wrapped in a `<template>` `times` times over: one view
/// holding `times` copies of every view body in the repo. `giant_view(1)` is
/// benchmarks/one_big_view.html; higher counts are the scaling probe.
pub fn giant_view(times : Int) -> String {
  let sb = StringBuilder::new()
  sb.write_string("<template id=\"GiantView\">\n")
  for _ in 0..<times {
    sb.write_string(one_big_view_body)
    sb.write_char('\n')
  }
  sb.write_string("</template>")
  sb.to_string()
}

///|
/// The two corpora, and the four stages each is run through — so the executable
/// shell and the `moon bench` blocks agree on the set.
pub let corpora : Array[(String, String)] = [
  ("many-views", all_views),
  ("one-big-view", giant_view(1)),
]

///|
pub let stages : Array[(String, (String) -> Int)] = [
  ("split", split),
  ("surface", surface),
  ("build", build),
  ("gen", gen),
]
