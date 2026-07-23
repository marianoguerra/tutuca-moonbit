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
priv struct SwatchPickerState {
  color : String
  palette : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
/// Clicking a `<circle>` sets `color`; the preview `<rect>` binds `:fill` to it,
/// and the enricher marks the selected swatch with a ring.
fn swatch_picker_comp() -> @component.Component {
  @component.component(
    views=swatch_picker_views(),
    name="SwatchPicker",
    init=SwatchPickerState::{ color: "#ef4444", palette },
    enrich={
      "swatch": (
        // lay each swatch out along a row and ring the selected one; the typed
        // state's current `color` field decides which ring shows
        s : SwatchPickerState,
        binds,
        key,
        value,
        _iter,
      ) => {
        match key {
          Num(k) => {
            binds["cx"] = Num(32.0 + k * 46.0)
            binds["ring"] = if value == Str(s.color) {
              Str("#0f172a")
            } else {
              Str("transparent")
            }
          }
          _ => ()
        }
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
priv struct QuadraticState {
  a : Int
  b : Int
  c : Int
} derive(ToJson, FromJson)

///|
/// `@text` on an `<mn>` makes the displayed number reactive; the discriminant
/// classifies the equation as the coefficients change.
fn quadratic_comp() -> @component.Component {
  @component.component(
    views=quadratic_views(),
    name="Quadratic",
    init=QuadraticState::{ a: 1, b: -3, c: 2 },
    compute={
      // b² − 4ac decides how many real roots the equation has
      "discriminant": (s : QuadraticState, _args) => {
        Num(discriminant_of(s).to_double())
      },
      "classify": (s : QuadraticState, _args) => {
        let d = discriminant_of(s)
        if d > 0 {
          Str("two distinct real roots")
        } else if d == 0 {
          Str("one repeated real root")
        } else {
          Str("no real roots")
        }
      },
    },
  )
}

///|
fn discriminant_of(s : QuadraticState) -> Int {
  s.b * s.b - 4 * s.a * s.c
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
