///| HANDWRITTEN — the one file you write.
///
/// Everything around it is generated: `top.mbt` and `ffi.mbt` are wit-bindgen
/// output for `tutuca:component@0.11.0`, and `sdk.mbt` implements every one of
/// their `declare`s over the `DynComponent` trait below. You write a struct per
/// component and one `dyn_module()` saying what the bundle holds.
///
/// What this file does NOT hold is the declaration. The component's doc, its
/// fields, its message buckets and its views live in `manifest.json` and
/// `views/`, as data beside the wasm — so a host can read what a bundle IS
/// before instantiating it, and an author edits a view as HTML rather than as
/// a string inside source. That split arrived with `tutuca:component@0.10.0`;
/// before it, this file carried a `dice_def()` and the guest exported
/// `get-manifest`.
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
/// exists to produce. It asks the page, through the `roll` intent, and the
/// page answers. Every other component in this family (a counter, a todo
/// list, a calculator) would still function with the host reduced to a
/// renderer; this one would not, which is why it is the thing worth showing.
///
/// Asking through an intent is the only route there is, and the right one:
/// it is not ambient authority. The page is not lending the die entropy; it
/// is answering one question, once, and it can decline. That is a smaller
/// thing to consent to, and it is why this die runs anywhere.

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
/// Handle a message. `self` in, the successor out.
///
/// Three answers, not two, and the third is what `tutuca:component@0.10.0`
/// added: `Changed(next)` carries a successor, `Unchanged` says the name was
/// MINE and nothing moved, and `Unhandled` says it was never mine at all. The
/// 0.5 contract returned `&DynComponent?` and collapsed the last two into one
/// `None`, which left the host unable to tell a handler that declined from a
/// component that had no such handler.
///
/// The internal SDK categories: MessageDispatch is what this component's own
/// views or a parent send and what an answer arrives through. IntentDispatch
/// is a routed intent offered at this component.
impl DynComponent for Dice with fn handle_dispatch(self, bucket, name, args) {
  match (bucket, name) {
    // The whole point. A request leaves now and the answer comes back later as
    // a MessageDispatch — so this is `Unchanged`: the click was handled, and a die
    // that showed a new face before the host had answered would be lying.
    (MessageDispatch, "roll") => {
      @control.intent("roll", [@values.Value::Number(self.faces)], {
        route: [LEX],
        on_ok: Some("rolled"),
        on_error: Some("rollFailed"),
        on_unhandled: None,
        live_path: false,
      })
      Unchanged
    }
    // `on_ok` means these args carry just the value; without it a response
    // arrives as [result, error] and this would have to unpack both.
    (MessageDispatch, "rolled") =>
      match args {
        [@values.Value::Number(n), ..] => {
          let rolls = self.rolls.copy()
          rolls.push(n)
          // Tell whoever holds this die what it came up. It travels UP as a
          // bubble and the host routes it; this component does not know, and
          // must not know, who is listening.
          @control.intent("rolled", [@values.Value::Number(n)], {
            route: [DYN],
            on_ok: None,
            on_error: None,
            on_unhandled: None,
            live_path: false,
          })
          Changed({ ..self, last: n, rolls, } as &DynComponent)
        }
        // An answer shaped wrong is still an answer to a question this die
        // asked, so it is Unchanged rather than Unhandled.
        _ => Unchanged
      }
    // A host that refuses to roll is a host that refuses; there is nothing to
    // do about it here, and nothing to show that would not be a made-up face.
    (MessageDispatch, "rollFailed") => Unchanged
    (MessageDispatch, "clear") =>
      Changed({ ..self, last: 0.0, rolls: [], } as &DynComponent)
    (MessageDispatch, "init") => Unchanged
    // Everything else is somebody else's message. Saying so — rather than
    // saying "handled, nothing changed" — is what lets the host keep routing it.
    _ => Unhandled
  }
}

///|
/// Answer a `$name` call from a view. Pure: it computes, it does not change.
impl DynComponent for Dice with fn render_call(self, name, args) {
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
/// Write one declared field. The runtime uses this for internal mutators the
/// component's own views invoke and for host-owned reconstruction. It is not
/// the public interface; that is the manifest's `properties` list.
///
/// `setFaces` is NOT in `handlers` below, and that is the point: the host
/// synthesizes it from the declared field and routes it here. Changing the
/// faces clears the history, because eleven pips on a d6 is not a record of
/// anything.
impl DynComponent for Dice with fn with_field(self, name, v) {
  match (name, v) {
    ("faces", @values.Value::Number(n)) => {
      let faces = if n < 2.0 { 2.0 } else { n }
      Some({ faces, last: 0.0, rolls: [], } as &DynComponent)
    }
    ("last", @values.Value::Number(n)) =>
      Some({ ..self, last: n, } as &DynComponent)
    ("rolls", @values.Value::List(l)) => {
      let rolls = []
      for i in 0U..<@values.list_len(l) {
        match @values.list_get(l, i) {
          @values.Value::Number(n) => rolls.push(n)
          _ => ()
        }
      }
      Some({ ..self, rolls, } as &DynComponent)
    }
    _ => None
  }
}

// `seq_entries` used to live here — an instance offering ITSELF as a sequence
// for a host `@each` to walk. It went with `tutuca:component@0.10.0` and is not
// missed: the view iterates `.rolls`, a declared list field the host already
// reads through `get_field`, so the second path was a second way to say the
// same thing and one more thing a guest could get wrong.

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
  let d : Dice = { faces: if faces < 2.0 { 2.0 } else { faces }, last, rolls, }
  d as &DynComponent
}

///|
/// The bundle: every component in it, and how to build each one.
///
/// Two lists used to live here — this one and a `dice_def()` describing the
/// component. The description moved to `manifest.json`, which is why this is
/// now the whole of what the wasm says about itself: a name and a factory. The
/// host reads the rest as data, before it instantiates anything.
///
/// No `serve` either: `roll` is a request this bundle does NOT answer, which is
/// what sends it past the bundle and out to the page. A bundle that served a
/// `roll` of its own would answer its own components first and the host would
/// never hear it.
fn dyn_module() -> DynModule {
  module_def([dyn_comp("Dice", make_dice)])
}
