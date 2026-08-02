///| HANDWRITTEN — the one file you write.
///
/// Everything around it is generated: `top.mbt` and `ffi.mbt` are wit-bindgen
/// output for `tutuca:component@0.4.0`, and `sdk.mbt` implements every one of
/// their `declare`s over the `DynComponent` trait below. You write a struct per
/// component and one `dyn_module()` saying what the bundle holds.
///
/// The host is the framework. Your views are DATA — tutuca template strings the
/// host compiles and renders; you never touch the DOM. Your state is opaque —
/// the host reads a field at a time through `get_field` while rendering, and a
/// handler takes self and returns the NEXT self. That is tutuca's copy-on-write
/// model, and it is why nothing here mutates.
///
/// ---
///
/// A DIE, and it is a die on purpose: it is the smallest component that cannot
/// work alone. This world imports no WASI — no clock, no entropy, nothing
/// ambient — so a die living in here has no way to produce the one number it
/// exists to produce. It asks the page, through `control.request "roll"`, and
/// the page answers. Every other component in this family (a counter, a todo
/// list, a calculator) would still function with the host reduced to a
/// renderer; this one would not, which is why it is the thing worth showing.
///
/// It could instead have declared `capabilities=[cap-random]` and used
/// `@env.random_u64()`. It deliberately does not. A capability is granted by
/// the HOST's policy, and a host that will not grant one REFUSES the bundle
/// rather than handing it a plausible lie — which is the right behaviour and
/// also means a bundle that asks for anything is a bundle some pages cannot
/// run. The default tier grants nothing, so a die that asked would be refused
/// by every page that had not thought about the question, including this one.
///
/// Asking through `control.request` is the route that stays open: it needs no
/// grant, because it is not ambient authority. The page is not lending the die
/// entropy; it is answering one question, once, and it can decline. That is a
/// smaller thing to consent to, and it is why this die runs anywhere.

///|
/// One component. Fields are ordinary MoonBit; only `get_field` decides what
/// the host may see, and only the `fields=` list below declares their shape.
priv struct Dice {
  faces : Double
  /// The face showing. 0 means "not rolled yet" rather than a face, because a
  /// die has no zero and the view can therefore tell the two apart.
  last : Double
  rolls : Array[Double]
}

///|
/// Read a declared field. Called lazily, once per `.name` a rendering view
/// reaches for — so it runs often, and cheap is the right default.
impl DynComponent for Dice with fn get_field(self, name) {
  match name {
    "faces" => Some(@values.Value::Number(self.faces))
    "last" => Some(@values.Value::Number(self.last))
    "rolls" => {
      let l = @values.list_new()
      for n in self.rolls {
        @values.list_push(l, @values.Value::Number(n))
      }
      Some(@values.Value::List(l))
    }
    _ => None
  }
}

///|
/// Handle a message. `self` in, the successor out — or `None` for "nothing
/// changed", which is cheaper than returning an identical copy.
///
/// The buckets: INPUT is what this component's own views raise (`@on.click`),
/// RECEIVE is what a parent sends it, BUBBLE is what a child raised, RESPONSE
/// is an answer to a request this component made.
impl DynComponent for Dice with fn handle(self, bucket, name, args) {
  match (bucket, name) {
    // The whole point. A request leaves now and the answer comes back later as
    // a RESPONSE — so this returns `None`: nothing has changed yet, and a die
    // that showed a new face before the host had answered would be lying.
    (INPUT, "roll") => {
      @control.request("roll", [@values.Value::Number(self.faces)], {
        on_ok: Some("rolled"),
        on_error: Some("rollFailed"),
        on_res: None,
        live_path: false,
      })
      None
    }
    // `on_ok` means these args carry just the value; without it a response
    // arrives as [result, error] and this would have to unpack both.
    (RESPONSE, "rolled") =>
      match args {
        [@values.Value::Number(n), ..] => {
          let rolls = self.rolls.copy()
          rolls.push(n)
          // Tell whoever holds this die what it came up. It travels UP as a
          // bubble and the host routes it; this component does not know, and
          // must not know, who is listening.
          @control.emit("rolled", [@values.Value::Number(n)])
          Some({ ..self, last: n, rolls } as &DynComponent)
        }
        _ => None
      }
    // A host that refuses to roll is a host that refuses; there is nothing to
    // do about it here, and nothing to show that would not be a made-up face.
    (RESPONSE, "rollFailed") => None
    (INPUT, "clear") =>
      Some({ ..self, last: 0.0, rolls: [] } as &DynComponent)
    (RECEIVE, "init") => None
    _ => None
  }
}

///|
/// Answer a `$name` call from a view. Pure: it computes, it does not change.
impl DynComponent for Dice with fn call_method(self, name, args) {
  match name {
    "caption" =>
      @values.Value::Text(
        if self.last == 0.0 {
          "a d\{self.faces.to_int()}, unrolled"
        } else {
          "\{self.last.to_int()} on a d\{self.faces.to_int()}"
        },
      )
    // A `@when` filter over `rolls`, called with (key, item, iter-data) and
    // answered as a boolean: badge only the rolls that came up the maximum.
    "isMax" =>
      match args {
        [_, @values.Value::Number(v), ..] =>
          @values.Value::Boolean(v == self.faces)
        _ => @values.Value::Boolean(false)
      }
    _ => @values.Value::Nil
  }
}

///|
/// Write one declared field. The host uses this for the mutators your fields
/// imply and for the config form, so a component that declares fields wants it
/// — otherwise every edit has to go through a handler you wrote by hand.
///
/// `setFaces` is NOT in `handlers` below, and that is the point: the host
/// synthesizes it from the declared field and routes it here. Changing the
/// faces clears the history, because eleven pips on a d6 is not a record of
/// anything.
impl DynComponent for Dice with fn with_field(self, name, v) {
  match (name, v) {
    ("faces", @values.Value::Number(n)) => {
      let faces = if n < 2.0 { 2.0 } else { n }
      Some({ faces, last: 0.0, rolls: [] } as &DynComponent)
    }
    ("last", @values.Value::Number(n)) =>
      Some({ ..self, last: n } as &DynComponent)
    ("rolls", @values.Value::List(l)) => {
      let rolls = []
      for i in 0U..<@values.list_len(l) {
        match @values.list_get(l, i) {
          @values.Value::Number(n) => rolls.push(n)
          _ => ()
        }
      }
      Some({ ..self, rolls } as &DynComponent)
    }
    _ => None
  }
}

///|
/// Iterated by host `@each` over the instance itself.
impl DynComponent for Dice with fn seq_entries(self) {
  let out = []
  for i, n in self.rolls {
    out.push(("r\{i}", @values.Value::Number(n)))
  }
  Some(out)
}

///|
/// Build one. `args` are the declared fields the caller supplied — from a
/// generated form, from a named init, or handed back on a hot-swap migration.
fn make_dice(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut faces = 6.0
  let mut last = 0.0
  let rolls = []
  for arg in args {
    match arg {
      ("faces", @values.Value::Number(n)) => faces = n
      ("last", @values.Value::Number(n)) => last = n
      ("rolls", @values.Value::List(l)) =>
        for i in 0U..<@values.list_len(l) {
          match @values.list_get(l, i) {
            @values.Value::Number(n) => rolls.push(n)
            _ => ()
          }
        }
      _ => ()
    }
  }
  let d : Dice = { faces: if faces < 2.0 { 2.0 } else { faces }, last, rolls }
  d as &DynComponent
}

///|
/// What this component IS, in the terms a catalog can rank and a form can draw.
/// `doc`, `keywords` and `message_docs` are not decoration: they are what lets
/// someone — or a language model — find this component among forty they have
/// never seen, and generate a form for it without trusting it.
fn dice_def() -> ComponentDef {
  component_def(
    "Dice",
    doc="A die you roll. It asks the host for the number, because it has no way to make one.",
    keywords=["dice", "die", "random", "roll", "game", "chance"],
    category="input",
    message_docs=[
      { name: "roll", doc: "Ask the host for a number and show it." },
      { name: "clear", doc: "Forget every roll." },
      { name: "rolled", doc: "The host answered with a face." },
      { name: "rollFailed", doc: "The host would not roll." },
      { name: "caption", doc: "The die and its face as one sentence." },
      { name: "isMax", doc: "Was this roll the highest face?" },
    ],
    views=[
      {
        name: "main",
        html: (
          #|<div class="card bg-base-100 border border-base-300 shadow-sm">
          #|  <div class="card-body gap-3 items-center p-4">
          #|    <span class="text-sm opacity-70" @text="$caption"></span>
          #|    <div class="rounded-box bg-base-200 px-6 py-3 text-5xl font-bold tabular-nums" @text=".last"></div>
          #|    <div class="join">
          #|      <button class="btn btn-sm btn-primary join-item" @on.click="roll">roll</button>
          #|      <button class="btn btn-sm btn-ghost join-item" @on.click="clear">clear</button>
          #|    </div>
          #|    <ul class="flex gap-1 flex-wrap justify-center"><li class="badge badge-sm badge-primary" @each=".rolls" @when="isMax" @text="@value"></li></ul>
          #|  </div>
          #|</div>
        ),
      },
    ],
    // The declared shape, as a FLAT table: WIT has no recursive types, so a
    // field names its type by INDEX into this array rather than inline, and a
    // compound points at its parts the same way (`elem`, `items`, `members`).
    types=[
      { kind: TY_FLOAT, elem: None, items: [], name: "", members: [] },
      { kind: TY_LIST, elem: Some(0), items: [], name: "", members: [] },
    ],
    // The constraint is the half a TYPE cannot state, and it is what the
    // generated config form draws its bounds from — nothing here validates
    // `faces` a second time except `with_field`'s floor.
    fields=[
      field(
        "faces",
        0,
        doc="How many faces. Six unless you say otherwise.",
        required=false,
        constraint=Some({ ..no_limits(), min: Some(2), max: Some(100) }),
      ),
      field("last", 0, doc="The face showing, or 0 before the first roll."),
      field("rolls", 1, doc="Every face this die has shown, oldest first."),
    ],
    // what its own views raise. `setFaces` is deliberately absent: it is the
    // mutator `faces` implies, and the host answers it through `with_field` —
    // declaring it here would take it back.
    handlers=["roll", "clear"],
    // what a parent may send it
    receives=["init"],
    // what it raises for whoever holds it
    bubbles=["rolled"],
    // answers to requests it made
    responses=["rolled", "rollFailed"],
    // what its views call with `$`
    methods=["caption"],
    // what its views filter with `@when`
    whens=["isMax"],
    // a named initial state a host can offer instead of the bare constructor
    inits=[
      {
        name: "d20",
        args_json: "{\"faces\": 20}",
        doc: "A twenty-sided die.",
      },
    ],
    // Styling is entirely margaui (daisyUI) classes above. Under the untrusted
    // tier an empty `style` is the only thing a bundle may ship, and the host
    // recompiles its utility CSS after this bundle loads so the classes above
    // are styled by the time anything renders.
  )
}

///|
/// The bundle: every component in it, and how to build each one.
///
/// `capabilities` is the honest list of ambient facts this bundle needs — a
/// clock, randomness, a timer. Asking for none is what makes a bundle safe to
/// mount from anywhere, and an untrusted host REFUSES one that asks for
/// something it will not grant rather than handing it a plausible lie.
///
/// No `serve` either: `roll` is a request this bundle does NOT answer, which is
/// what sends it past the bundle and out to the page. A bundle that served a
/// `roll` of its own would answer its own components first and the host would
/// never hear it.
fn dyn_module() -> DynModule {
  module_def(
    "dice",
    [dyn_comp(dice_def(), make_dice)],
    doc="A die you roll. It asks the host for the number, because it cannot make one.",
    version="0.1.0",
    capabilities=[],
  )
}
