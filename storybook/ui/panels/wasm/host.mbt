// The standard panel layer, wired to a page.
//
// Three things a browser has and `storybook/ui/panels` cannot reach: an
// animation frame, a profiler, and a click that means "point at this" rather
// than "press this". The panel package is checked and tested on every backend,
// so a `globalThis` in it would make that untrue — the same split the URL
// services follow, one layer up.

///|
/// The standard tabs, with the page's effects wired in.
///
/// What a page passes to `@sbw.mount`'s `panels~`, and naming it is what links
/// the inspector, the recorder and the fuzz driver into the wasm.
pub fn all(sections : Array[@sb.Section]) -> @sbui.PanelSet[@wdom.WasmNode] {
  @panels.all(sections, effects=fuzz_effects())
}

///|
/// The Fuzz tab's two browser effects: the animation frame a run steps on, and
/// the profiler marks each dispatch is bracketed with.
pub fn fuzz_effects() -> @panels.FuzzEffects {
  { arm_frame: arm_fuzz_frame, mark: mark_fuzz, }
}

///|
/// The delegated DOM event entry point, with the one interception the panels
/// need: while the Trace panel is waiting to be pointed at, a click MEANS
/// something else. Letting it through as well would drive the app with the
/// click that was meant to point at it — so the pick consumes it, and
/// everything else goes on exactly as before.
pub fn on_event(ev : @core.Any) -> Unit {
  @sbw.on_event(ev, before=(node, name) => {
    if name != "click" {
      false
    } else {
      match @sbw.current_gallery() {
        Some(app) => @panels.take_select_click(app, node, app.root_node)
        None => false
      }
    }
  })
}

///|
/// Called from JS on each animation frame while a fuzz run is playing.
///
/// The page owns the scheduler, MoonBit owns what happens on the tick.
pub fn on_fuzz_tick() -> Unit {
  @panels.fuzz_tick()
}

///|
/// Ask the page for the next animation frame.
///
/// A call OUT and not a callback in: a closure cannot cross into JS on wasm-gc
/// — the same constraint `on_event` is shaped by — so the page installs
/// `__tutucaFuzzTick` as a one-shot `requestAnimationFrame` onto the
/// `on_fuzz_tick` export, and this pulls it. Nothing arms it again once a run
/// stops, so there is no permanent frame loop.
///
/// Silent when the page installed nothing: a gallery served by some other
/// index.html gets a Play that does not advance rather than a crash, and Step
/// and Burst still work.
fn arm_fuzz_frame() -> Unit {
  let g = @core.global_this()
  if @core.is_nullish(g) {
    return
  }
  let f = g._get("__tutucaFuzzTick")
  if @core.is_nullish(f) {
    return
  }
  let _ = f._invoke([])
}

///|
/// Bracket one step on DevTools' Timings track.
///
/// A LABEL, not a measurement. The numbers are the profiler's — that is what
/// it is for, and it sees layout, paint and GC that nothing in MoonBit can —
/// and what a run owes it is a name against each dispatch so the flame chart
/// can be read. No fallback clock where `performance` is absent, on purpose: a
/// second timebase nobody asked for is worse than none.
fn mark_fuzz(name : String, phase : String) -> Unit {
  let g = @core.global_this()
  if @core.is_nullish(g) {
    return
  }
  let perf = g._get("performance")
  if @core.is_nullish(perf) {
    return
  }
  if phase == "start" {
    let _ = perf._call("mark", [@core.any("fuzz:\{name}:start")])
  } else {
    let _ = perf._call("mark", [@core.any("fuzz:\{name}:end")])
    // Named for the dispatch, so a reader scanning the track sees which
    // message cost what without opening anything.
    let _ = perf._call("measure", [
      @core.any("fuzz \{name}"),
      @core.any("fuzz:\{name}:start"),
      @core.any("fuzz:\{name}:end"),
    ])
  }
}
