///| The mechanism the whole universal app is addressed by, pinned on its own.
///
/// A component tree has no node ids. What replaces them is `ctx.target_path()`:
/// while the root handles a bubble, that is the FIXED path of the component
/// that raised it, and `send_at_path` back down reaches exactly that one. The
/// app's whole "click a `+`, pick something from a bar that opens over the
/// page, and have it land in the cell you clicked" turns on it — and on the
/// half `transactor/bubble_test.mbt` does not cover: the path being kept ACROSS
/// dispatches, and surviving the component boundaries a rendered tree has that
/// a hand-built `Obj` tree does not.
///
/// It is kept on the app rather than in its state on purpose. A `DispatchPath`
/// is not a `Value` — it carries dynamic-render markers a JSON shape would have
/// to invent a spelling for — and the thing it names is transient UI focus that
/// nothing persists. `demo/universal_wasm` already keeps its in-flight loads
/// this way.

///|
/// A stand-in for the app: it holds a universal, hears what that universal
/// asks for, and answers on a later dispatch.
priv struct SpikeState {
  root : @tutuca.Value
  mode : String
  status : String
}

///|
impl @component.Fields for SpikeState with fn schema() {
  @component.SchemaInfo::new(
    name="Spike",
    fingerprint="spike-target-path",
    // `TyComp(Some("Universal"))` is what makes the child auto-construct
    // through the registration scope — the same thing the app's own root does,
    // so the spike is not testing a shape the app will not have.
    fields=[
      @component.FieldInfo::new("root", TyComp(Some("Universal"))),
      @component.FieldInfo::new("mode", TyText),
      @component.FieldInfo::new("status", TyText),
    ],
    view_handlers=["place", "useStack"],
  )
}

///|
impl @component.Fields for SpikeState with fn encode(s) {
  { "root": s.root, "mode": Str(s.mode), "status": Str(s.status) }
}

///|
impl @component.Fields for SpikeState with fn decode(f) {
  guard f.get("mode") is Some(Str(mode)) else { return None }
  guard f.get("status") is Some(Str(status)) else { return None }
  Some({ root: f.get("root").unwrap_or(Null), mode, status, })
}

///|
fn spike_module() -> (@component.ModuleDef, Std) {
  let (comps, std) = std_components()
  // What the app keeps: where the last request came from. Held here rather
  // than in state, for the reason at the top of this file.
  let target : Ref[@tutuca.DispatchPath?] = { val: None, }
  let spike = @component.component(
    name="Spike",
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div><button class="place" @on.click="place">place</button><button class="use-stack" @on.click="useStack">stack</button><span class="status" @text=".status"></span><div @push-view=".mode"><x render=".root"></x></div></div>
        ),
      ),
    },
    init=SpikeState::{ root: Null, mode: "edit", status: "", },
    update=(s, msg, ctx) => {
      match msg {
        // The bubble arrives with a SHORTENED path (one hop popped per
        // component it passed) but a fixed `target_path`, which is the one
        // worth keeping.
        Intent("addRequested", _) => {
          target.val = Some(ctx.target_path())
          ctx.stop_propagation()
          Next({
            ..s,
            status: "asked:\{ctx.target_path().to_transaction_path().steps.length()}",
          })
        }
        // A LATER dispatch, with nothing of the first one still on the stack —
        // which is the case the app is actually in when somebody picks a row
        // out of the command bar.
        Receive("place", _) =>
          match target.val {
            Some(p) => {
              ctx.send_at_path(p, "hold", [
                std.build("Text", { "text": Str("landed"), "size": Str("") }),
              ])
              Next({ ..s, status: "placed", })
            }
            None => Next({ ..s, status: "no target", })
          }
        // Put a two-cell stack in the root universal, so the next request comes
        // from a universal INSIDE a container — one more component boundary for
        // the path to cross, which is the case every real layout is in.
        Receive("useStack", _) => {
          ctx.send_at_path(ctx.path().concat([FieldStep("root")]), "hold", [
            std.build("Stack", {
              "children": List([std.cell(), std.cell()]),
              "direction": Str("column"),
              "justify": Str("start"),
              "align": Str("stretch"),
              "gap": Num(8.0),
              "padding": Num(0.0),
              "wrap": Bool(false),
            }),
          ])
          Next({ ..s, status: "stacked", })
        }
        // Plant a tree built in MoonBit. The other tests in this package use it
        // to set up a shape without clicking their way to it — the clicking is
        // what they are testing, not what they need to arrange.
        Receive("setRoot", [v, ..]) => Next({ ..s, root: v, })
        Receive("setMode", [Str(m), ..]) => Next({ ..s, mode: m, })
        _ => Unhandled
      }
    },
  )
  (@component.ModuleDef::new(name="spike", components=[spike, ..comps]), std)
}

///|
/// A mounted app whose root holds `root`, in edit mode, plus the `Std` that
/// built it. What every test below starts from.
/// The `Std` MUST be the one the module was built with: a component's
/// instances carry the id of the `Component` that made them, and a second
/// `std_components()` would hand back look-alikes the mounted scope cannot
/// resolve. One pair, threaded through.
fn mount_std(root : (Std) -> @tutuca.Value) -> (@harness.MemHarness, Std) raise {
  let (module_, std) = spike_module()
  let h = @harness.mount(module_, "Spike")
  h.send_at_root("setRoot", args=[root(std)])
  (h, std)
}

///|
test "a universal's request reaches the root, and the answer reaches back" {
  let (module_, _) = spike_module()
  let h = @harness.mount(module_, "Spike")
  // One empty universal, auto-constructed into the root's declared slot.
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
  h.click(".universal-add")
  // The root heard it, and `target_path` named the universal one hop down
  // rather than the root the bubble was handled at.
  @debug.assert_eq(h.text(".status"), "asked:1")
  // Nothing has been placed yet: asking and answering are two dispatches, and
  // that is the whole point.
  @debug.assert_eq(h.find_all(".tut-text").length(), 0)
  h.click(".place")
  @debug.assert_eq(h.text(".status"), "placed")
  // The answer landed in the universal that asked: the `+` is gone and what it
  // now holds is on screen.
  @debug.assert_eq(h.find_all(".universal-add").length(), 0)
  @debug.assert_eq(h.text(".tut-text"), "landed")
  h.destroy()
}

///|
test "the path survives a container between the root and the universal" {
  let (module_, _) = spike_module()
  let h = @harness.mount(module_, "Spike")
  // Answering with nothing to answer changes nothing and says so, which is the
  // state the app is in before anybody has clicked a `+`.
  h.click(".place")
  @debug.assert_eq(h.text(".status"), "no target")
  h.click(".use-stack")
  // Two nested empty universals now, each with its own `+`: the root one holds
  // the stack, and the stack holds two cells.
  @debug.assert_eq(h.find_all(".universal-add").length(), 2)
  // Click the SECOND one and answer it. The answer has to land in that one and
  // not in the first, which is the whole claim.
  h.click(".universal-add", nth=1)
  h.click(".place")
  @debug.assert_eq(h.find_all(".universal-add").length(), 1)
  @debug.assert_eq(h.texts(".tut-text"), ["landed"])
  h.destroy()
}
