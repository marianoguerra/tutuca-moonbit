// Two examples showing SVG rendering straight from a tutuca template — a
// reactive bar chart and parametrized SVG icons as macros. The `<svg>` subtree
// keeps its namespace, so `<rect>`/`<line>`/`<text>`/`<path>` are real SVG
// elements and every directive (@each, @loop-with, @enrich-with, :attr, macros)
// works on them.

///|
/// A bar chart driven by a list field. `@loop-with` computes shared layout once,
/// `@enrich-with` derives each bar's geometry, and the buttons mutate the data.
///
/// `randomize` avoids real randomness: to keep the headless
/// tests deterministic (and because randomness is not the point), this derives
/// the next heights from the current ones instead — still reactive, still
/// re-renders the bars, just reproducible.
///
/// `addBar` and `removeBar` are in the view file's
/// `<script type="tutuca/script">` block: adding to and deleting from a list
/// under a bound is what its collection methods are for, and their caps are
/// `requires` clauses, so a press at the limit is refused by a rule with a
/// name rather than by an `if` nobody hears. `randomize` stays here — it
/// rewrites EVERY element, which is a map over the list and not a mutation of
/// one position, and being a MoonBit handler it is not one of the transitions
/// the block's contracts cover.
fn bar_chart_comp() -> @component.Component {
  bar_chart_component(
    init={ values: [Num(40), Num(72), Num(28), Num(90), Num(55), Num(63)] },
    loop_with=l => {
      match l {
        // once per render, before the loop: split the 300-wide viewBox among the
        // bars there currently are
        Layout =>
          Some((_s, seq, _ctx) => {
            let size = match seq {
              List(a) => a.length()
              _ => 1
            }
            let step = 300.0 / @cmp.maximum(1, size).to_double()
            @component.LoopWith::new(
              iter_data=Map({ "step": Num(step), "barW": Num(step * 0.62) }),
            )
          })
      }
    },
    enrich=e => {
      match e {
        // per bar: index + value -> pixel geometry
        Bar =>
          Some((_s, binds, key, value, iter, _stack) => {
            match (key, value, iter) {
              (Num(k), Num(v), Map(idata)) => {
                let step = num_of(idata.get("step"), 0.0)
                let bar_w = num_of(idata.get("barW"), 0.0)
                binds["x"] = Num(k * step + (step - bar_w) / 2.0)
                binds["w"] = Num(bar_w)
                binds["h"] = Num(v)
                binds["y"] = Num(110.0 - v)
                binds["cx"] = Num(k * step + step / 2.0)
                binds["labelY"] = Num(110.0 - v - 5.0)
              }
              _ => ()
            }
          })
      }
    },
    update=(s, msg, _ctx) => {
      match msg {
        Receive("randomize", _) => {
          let next : Array[@tutuca.Value] = s.values.map(v => {
            match v {
              // deterministic stand-in for Math.random, in the 10..99 range
              Num(n) => Num(((n.to_int() * 7 + 13) % 90 + 10).to_double())
              _ => v
            }
          })
          Next({ values: next })
        }
        _ => Unhandled
      }
    },
  )
}

///|
fn num_of(v : @tutuca.Value?, dflt : Double) -> Double {
  match v {
    Some(Num(n)) => n
    _ => dflt
  }
}

///|
pub fn svg_bar_chart_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="svg-bar-chart",
    components=[bar_chart_comp()],
    examples=[
      { component: "BarChart", title: "Default", args: Map([]), view: None },
      {
        component: "BarChart",
        title: "Single bar",
        args: { "values": List([Num(70)]) },
        view: None,
      },
    ],
  )
}

///|
/// The SVG body shared by every icon macro: `^size` / `^color` are macro
/// parameters, so passing them dynamically makes the icon react to state.
fn icon_svg(path : String) -> String {
  "<svg :width=\"^size\" :height=\"^size\" viewBox=\"0 0 24 24\" fill=\"none\" :stroke=\"^color\" stroke-width=\"2\" stroke-linecap=\"round\" stroke-linejoin=\"round\"><path d=\"\{path}\"></path></svg>"
}

///|
fn icon_macro(path : String) -> @anode.Macro {
  {
    defaults: { "size": "'24'", "color": "'currentColor'" },
    raw_view: icon_svg(path),
  }
}

///|
fn icon_gallery_comp() -> @component.Component {
  @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="flex flex-col gap-4">
          #|  <label class="flex items-center gap-2 text-sm">
          #|    Size
          #|    <input type="range" min="16" max="80" :value=".size" @on.input="setSize e.valueAsInt" />
          #|    <code class="sizeval" @text=".size"></code>
          #|  </label>
          #|  <div class="flex items-end gap-6 text-primary icons">
          #|    <x:iconheart :size=".size" :color="'#e11d48'"></x:iconheart>
          #|    <x:iconstar :size=".size" :color="'#f59e0b'"></x:iconstar>
          #|    <x:iconbolt :size=".size" :color="'#2563eb'"></x:iconbolt>
          #|  </div>
          #|  <div class="flex items-center gap-3 fixed">
          #|    <span class="text-sm">Fixed 20px:</span>
          #|    <x:iconheart size="20"></x:iconheart>
          #|    <x:iconstar size="20"></x:iconstar>
          #|    <x:iconbolt size="20"></x:iconbolt>
          #|  </div>
          #|</div>
        ),
      ),
    },
    name="IconGallery",
    init=IconGalleryState::{ size: 40 },
  )
}

///|
pub fn svg_icon_macro_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="svg-icon-macro",
    components=[icon_gallery_comp()],
    macros={
      "iconheart": icon_macro(
        "M19 14c1.49-1.46 3-3.21 3-5.5A5.5 5.5 0 0 0 16.5 3c-1.76 0-3 .5-4.5 2-1.5-1.5-2.74-2-4.5-2A5.5 5.5 0 0 0 2 8.5c0 2.29 1.49 4.04 3 5.5l7 7Z",
      ),
      "iconstar": icon_macro(
        "M12 2l3.09 6.26L22 9.27l-5 4.87 1.18 6.88L12 17.77l-6.18 3.25L7 14.14 2 9.27l6.91-1.01z",
      ),
      "iconbolt": icon_macro("M13 2L3 14h7l-1 8 10-12h-7z"),
    },
    examples=[
      { component: "IconGallery", title: "Default", args: Map([]), view: None },
      {
        component: "IconGallery",
        title: "Small",
        args: { "size": Num(16) },
        view: None,
      },
    ],
  )
}
