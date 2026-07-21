// Ports of:
//   docs/examples/svg-interactive.js — clickable SVG, :attr bindings on shapes
//   docs/examples/mathml-formula.js  — a reactive MathML formula
//
// SVG and MathML subtrees keep their namespace through the parser, so the usual
// directives (@each, :attr, @on.click, @if, @enrich-with, macros) all work on
// real namespaced elements — no special casing.

///|
let palette : Array[@tutuca.Value] = [
  Str("#ef4444"),
  Str("#f97316"),
  Str("#eab308"),
  Str("#22c55e"),
  Str("#06b6d4"),
  Str("#3b82f6"),
  Str("#8b5cf6"),
  Str("#ec4899"),
]

///|
/// Clicking a `<circle>` sets `color`; the preview `<rect>` binds `:fill` to it,
/// and the enricher marks the selected swatch with a ring.
fn swatch_picker_comp() -> @component.Component {
  @component.component(
    name="SwatchPicker",
    view=(
      #|<div class="flex flex-col gap-2">
      #|  <svg viewBox="0 0 380 130" role="img">
      #|    <rect class="preview" x="20" y="12" width="340" height="52" rx="8" :fill=".color"></rect>
      #|    <circle @each=".palette" @enrich-with="swatch"
      #|      :cx="@cx" cy="98" r="18" :fill="@value"
      #|      stroke-width="3" :stroke="@ring"
      #|      @on.click="$setColor @value"></circle>
      #|  </svg>
      #|  <p class="text-sm label">Selected: <x text=".color"></x></p>
      #|</div>
    ),
    fields={
      "color": @component.FieldSpec::of_default(Str("#ef4444")),
      "palette": @component.FieldSpec::of_default(List(palette)),
    },
    alter={
      // lay each swatch out along a row and ring the selected one; `this` is the
      // component, so the current `color` field decides which ring shows
      "swatch": (inst, args) => {
        match args {
          [Map(binds), Num(key), value, ..] => {
            binds["cx"] = Num(32.0 + key * 46.0)
            binds["ring"] = if value == inst.get("color") {
              Str("#0f172a")
            } else {
              Str("transparent")
            }
          }
          _ => ()
        }
        Null
      },
    },
  )
}

///|
pub fn svg_interactive_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="svg-interactive",
    components=[swatch_picker_comp()],
    examples=[
      { component: "SwatchPicker", title: "Default", args: Map([]), view: None },
      {
        component: "SwatchPicker",
        title: "Blue selected",
        args: { "color": Str("#3b82f6") },
        view: None,
      },
    ],
  )
}

///|
/// `@text` on an `<mn>` makes the displayed number reactive; the discriminant
/// classifies the equation as the coefficients change.
fn quadratic_comp() -> @component.Component {
  @component.component(
    name="Quadratic",
    view=(
      #|<div class="flex flex-col gap-3">
      #|  <div class="flex gap-3 text-sm">
      #|    <label class="flex items-center gap-1">a <input type="number" class="input input-sm w-16 in-a" :value=".a" @on.input="$setA valueAsInt" /></label>
      #|    <label class="flex items-center gap-1">b <input type="number" class="input input-sm w-16 in-b" :value=".b" @on.input="$setB valueAsInt" /></label>
      #|    <label class="flex items-center gap-1">c <input type="number" class="input input-sm w-16 in-c" :value=".c" @on.input="$setC valueAsInt" /></label>
      #|  </div>
      #|  <math display="block">
      #|    <mn class="m-a" @text=".a"></mn>
      #|    <mo>&#x2062;</mo>
      #|    <msup><mi>x</mi><mn>2</mn></msup>
      #|    <mo>+</mo>
      #|    <mn class="m-b" @text=".b"></mn>
      #|    <mo>&#x2062;</mo>
      #|    <mi>x</mi>
      #|    <mo>+</mo>
      #|    <mn class="m-c" @text=".c"></mn>
      #|    <mo>=</mo>
      #|    <mn>0</mn>
      #|  </math>
      #|  <p class="text-sm">Discriminant: <span class="disc" @text="$discriminant"></span></p>
      #|  <p class="text-sm">There are <span class="classify" @text="$classify"></span>.</p>
      #|</div>
    ),
    fields={
      "a": @component.FieldSpec::of_default(Num(1)),
      "b": @component.FieldSpec::of_default(Num(-3)),
      "c": @component.FieldSpec::of_default(Num(2)),
    },
    methods={
      // b² − 4ac decides how many real roots the equation has
      "discriminant": (inst, _args) => Num(discriminant_of(inst)),
      "classify": (inst, _args) => {
        let d = discriminant_of(inst)
        if d > 0.0 {
          Str("two distinct real roots")
        } else if d == 0.0 {
          Str("one repeated real root")
        } else {
          Str("no real roots")
        }
      },
    },
  )
}

///|
fn discriminant_of(inst : @component.Instance) -> Double {
  match (inst.get("a"), inst.get("b"), inst.get("c")) {
    (Num(a), Num(b), Num(c)) => b * b - 4.0 * a * c
    _ => 0.0
  }
}

///|
pub fn mathml_formula_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="mathml-formula",
    components=[quadratic_comp()],
    examples=[
      { component: "Quadratic", title: "Two roots", args: Map([]), view: None },
      {
        component: "Quadratic",
        title: "No real roots",
        args: { "a": Num(1), "b": Num(0), "c": Num(4) },
        view: None,
      },
    ],
  )
}
