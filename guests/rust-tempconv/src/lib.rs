//! A tutuca:component guest in Rust: opaque native state + tutuca view
//! strings, implementing the same WIT as guests/counter with zero tutuca
//! code. Handlers are functional (self in, self out); the host renders the
//! views and drives everything.
//!
//! A temperature converter rather than another counter, because a counter
//! never has to answer the two questions the contract's newer halves exist
//! for: what a component keeps that its declared fields do not name, and how
//! it comes back after the page goes away.
//!
//! Here that half is the DRAFT — the characters typed so far, and which box
//! they were typed in. A converter holds exactly one number (`celsius`, which
//! is what it declares); but somebody heading for `-40` is at `-4` on the way,
//! and reformatting their box out from under them while they type is the
//! difference between a control that works and one that fights. `-` and `-4.`
//! are drafts that are not numbers at all, and no declared field can hold them.

// The repo's ONE WIT source (see guests/guests.mjs) — guests keep no copy, so
// a guest cannot silently implement a different contract than the host.
wit_bindgen::generate!({
    path: "../../dyncomp/wit",
    world: "dynamic-component",
});

use exports::tutuca::component::guest::{
    Bucket, ComponentDef, Constraint, FieldDef, Guest, GuestInstance, InitDef, Instance, Manifest,
    NamedDoc, RequestResult, TyDef, TyKind, ViewDef,
};
use tutuca::component::values::Value;

struct Component;

/// The one index into the component's type table (WIT has no recursive types,
/// so a compound names its parts by index; this one has no compounds).
const TY_FLOAT: u32 = 0;

impl Guest for Component {
    type Instance = TempConv;

    fn get_manifest() -> Manifest {
        Manifest {
            api_version: 4,
            module_name: "rusttemplib".into(),
            doc: "The polyglot proof: the same contract, in Rust, with no tutuca code.".into(),
            version: "0.4.0".into(),
            homepage: "".into(),
            authors: vec![],
            // It asks the host for nothing — no clock, no randomness, no timer.
            capabilities: vec![],
            components: vec![ComponentDef {
                name: "TempConv".into(),
                doc: "Type a temperature in Celsius, Fahrenheit or Kelvin; the other two follow."
                    .into(),
                keywords: vec![
                    "temperature".into(),
                    "convert".into(),
                    "celsius".into(),
                    "fahrenheit".into(),
                    "kelvin".into(),
                    "units".into(),
                    "rust".into(),
                ],
                category: "input".into(),
                message_docs: vec![
                    NamedDoc {
                        name: "editC".into(),
                        doc: "Set the temperature from the Celsius box.".into(),
                    },
                    NamedDoc {
                        name: "editF".into(),
                        doc: "Set the temperature from the Fahrenheit box.".into(),
                    },
                    NamedDoc {
                        name: "editK".into(),
                        doc: "Set the temperature from the Kelvin box.".into(),
                    },
                    NamedDoc {
                        name: "preset".into(),
                        doc: "Jump to a well-known temperature, in Celsius.".into(),
                    },
                    NamedDoc {
                        name: "cText".into(),
                        doc: "What the Celsius box shows.".into(),
                    },
                    NamedDoc {
                        name: "fText".into(),
                        doc: "What the Fahrenheit box shows.".into(),
                    },
                    NamedDoc {
                        name: "kText".into(),
                        doc: "What the Kelvin box shows.".into(),
                    },
                    NamedDoc {
                        name: "note".into(),
                        doc: "What this temperature is, in a few words.".into(),
                    },
                ],
                views: vec![ViewDef {
                    name: "main".into(),
                    // margaui (daisyUI) classes, matching the universal demo's
                    // styling; the "rust" badge marks this as the Rust guest.
                    //
                    // Each box shows a METHOD rather than the declared field,
                    // because the box being typed in has to show those
                    // characters while the other two show the number. One field
                    // could only ever do one of those.
                    html: r#"<div class="card bg-base-100 border border-base-300 shadow-sm w-80 tempconv">
  <div class="card-body gap-2 p-4">
    <div class="flex items-center gap-2">
      <span class="badge badge-sm badge-warning">rust</span>
      <span class="text-xs opacity-70 grow note" @text="$note"></span>
    </div>
    <label class="flex items-center gap-2">
      <span class="w-6 text-sm opacity-70">&#176;C</span>
      <input class="input input-bordered input-sm w-full box-c" inputmode="decimal"
             :value="$cText" @on.input="editC value" />
    </label>
    <label class="flex items-center gap-2">
      <span class="w-6 text-sm opacity-70">&#176;F</span>
      <input class="input input-bordered input-sm w-full box-f" inputmode="decimal"
             :value="$fText" @on.input="editF value" />
    </label>
    <label class="flex items-center gap-2">
      <span class="w-6 text-sm opacity-70">K</span>
      <input class="input input-bordered input-sm w-full box-k" inputmode="decimal"
             :value="$kText" @on.input="editK value" />
    </label>
    <div class="join">
      <button class="btn btn-xs join-item preset-freeze" @on.click="preset 0">freezing</button>
      <button class="btn btn-xs join-item preset-body" @on.click="preset 37">body</button>
      <button class="btn btn-xs join-item preset-boil" @on.click="preset 100">boiling</button>
    </div>
  </div>
</div>"#
                        .into(),
                }],
                // The declared state: ONE number. Everything the view shows is
                // derived from it, and everything the guest keeps beyond it is
                // a draft — which is exactly why this component has a `persist`
                // and the counter does not.
                types: vec![TyDef {
                    kind: TyKind::TyFloat,
                    elem: None,
                    items: vec![],
                    name: "".into(),
                    members: vec![],
                }],
                fields: vec![FieldDef {
                    name: "celsius".into(),
                    ty: TY_FLOAT,
                    doc: "The temperature, in degrees Celsius.".into(),
                    required: false,
                    constraint: Some(Constraint {
                        // Absolute zero is a floor the physics gives us, and a
                        // form offering to go below it is offering a
                        // temperature that does not exist.
                        min: Some(-273.15),
                        max: Some(10_000.0),
                        min_len: None,
                        max_len: None,
                        pattern: "".into(),
                        format: "".into(),
                        enum_json: "".into(),
                        default_json: "20".into(),
                    }),
                }],
                // `setCelsius` is absent on purpose: the `celsius` field
                // implies it, and the host answers it through `with_field`.
                handlers: vec![
                    "editC".into(),
                    "editF".into(),
                    "editK".into(),
                    "preset".into(),
                ],
                receives: vec!["init".into()],
                bubbles: vec![],
                responses: vec![],
                methods: vec![
                    "cText".into(),
                    "fText".into(),
                    "kText".into(),
                    "note".into(),
                ],
                whens: vec![],
                requests: vec![],
                inits: vec![InitDef {
                    name: "body-heat".into(),
                    args_json: r#"{"celsius":37}"#.into(),
                    doc: "Starts at body temperature.".into(),
                }],
                // styling is entirely margaui (daisyUI) classes; no fallback CSS
                style: "".into(),
            }],
        }
    }

    /// This bundle serves no requests of its own.
    fn handle_request(name: String, _args: Vec<Value>) -> RequestResult {
        RequestResult::Err(Value::Text(format!("rusttemplib: no request {name}")))
    }
}

pub struct TempConv {
    /// The temperature, and the only thing this component DECLARES.
    celsius: f64,
    /// The characters typed into `unit`'s box, exactly as typed. Empty when
    /// nobody is mid-edit, which is every state a page opens in.
    draft: String,
    /// Which box the draft belongs to: `c`, `f`, `k`, or a space for none.
    unit: char,
}

impl TempConv {
    /// A settled instance: a temperature and no edit in progress.
    fn at(celsius: f64) -> Option<Instance> {
        Some(Instance::new(TempConv {
            celsius: clamp(celsius),
            draft: String::new(),
            unit: ' ',
        }))
    }

    /// The state after typing `text` into `unit`'s box.
    ///
    /// Text that is not a number leaves the temperature ALONE and keeps the
    /// draft: `-`, `-4.` and `` are all real things to have typed on the way to
    /// a number, and clearing the other boxes because of one of them would
    /// punish somebody for typing the minus sign first.
    fn typed(&self, unit: char, text: &str) -> Option<Instance> {
        let celsius = match parse(text) {
            Some(v) => clamp(from_unit(unit, v)),
            None => self.celsius,
        };
        Some(Instance::new(TempConv {
            celsius,
            draft: text.to_string(),
            unit,
        }))
    }

    /// What one box shows: the draft when it is the box being typed in, and
    /// the number otherwise.
    fn shown(&self, unit: char) -> String {
        if self.unit == unit {
            self.draft.clone()
        } else {
            format_num(to_unit(unit, self.celsius))
        }
    }
}

/// Below absolute zero is not a temperature. Clamped rather than refused,
/// because the number arrives one keystroke at a time and refusing halfway
/// through would mean rejecting a prefix of something valid.
fn clamp(celsius: f64) -> f64 {
    if celsius.is_nan() {
        0.0
    } else if celsius < -273.15 {
        -273.15
    } else {
        celsius
    }
}

fn from_unit(unit: char, v: f64) -> f64 {
    match unit {
        'f' => (v - 32.0) * 5.0 / 9.0,
        'k' => v - 273.15,
        _ => v,
    }
}

fn to_unit(unit: char, celsius: f64) -> f64 {
    match unit {
        'f' => celsius * 9.0 / 5.0 + 32.0,
        'k' => celsius + 273.15,
        _ => celsius,
    }
}

/// A number as a person would write it: two decimals at most, and no trailing
/// zeros. `20` rather than `20.00`, because a converter that turns round
/// numbers into ragged ones reads as less accurate rather than more.
fn format_num(v: f64) -> String {
    let rounded = (v * 100.0).round() / 100.0;
    let mut s = format!("{rounded}");
    if s.contains('.') {
        while s.ends_with('0') {
            s.pop();
        }
        if s.ends_with('.') {
            s.pop();
        }
    }
    if s == "-0" {
        s = "0".into();
    }
    s
}

fn parse(text: &str) -> Option<f64> {
    let t = text.trim();
    if t.is_empty() {
        return None;
    }
    t.parse::<f64>().ok().filter(|v| v.is_finite())
}

fn text_arg(args: &[Value]) -> Option<String> {
    match args.first() {
        Some(Value::Text(s)) => Some(s.clone()),
        _ => None,
    }
}

fn num_arg(args: &[Value]) -> Option<f64> {
    match args.first() {
        Some(Value::Number(n)) => Some(*n),
        _ => None,
    }
}

// --- persistence -------------------------------------------------------------
//
// The format is this guest's own business: the host stores the bytes and hands
// them back without looking. Length-prefixed rather than JSON because a draft
// is arbitrary text — escaping is where a hand-rolled format goes wrong, and a
// byte count cannot be confused by anything the text contains.
//
//   tutuca-tempconv/1\n<celsius>\n<unit>\n<draft bytes>\n<draft>

const PERSIST_TAG: &str = "tutuca-tempconv/1";

fn persist_bytes(state: &TempConv) -> Vec<u8> {
    let mut out = String::new();
    out.push_str(PERSIST_TAG);
    out.push('\n');
    out.push_str(&state.celsius.to_string());
    out.push('\n');
    out.push(state.unit);
    out.push('\n');
    out.push_str(&state.draft.len().to_string());
    out.push('\n');
    out.push_str(&state.draft);
    out.into_bytes()
}

/// A reader over the bytes above. Every step can fail, and every failure means
/// the same thing: this is not what this version wrote, so refuse it and let
/// the host rebuild from the declared fields instead.
struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> Reader<'a> {
    fn line(&mut self) -> Option<&'a str> {
        let end = self.bytes.get(self.at..)?.iter().position(|b| *b == b'\n')? + self.at;
        let s = std::str::from_utf8(&self.bytes[self.at..end]).ok()?;
        self.at = end + 1;
        Some(s)
    }

    /// A length-prefixed run of text. The count is BYTES, so a draft with
    /// anything non-ASCII in it reads back exactly as it was written.
    fn chunk(&mut self) -> Option<String> {
        let len = self.line()?.parse::<usize>().ok()?;
        let end = self.at.checked_add(len)?;
        if end > self.bytes.len() {
            return None;
        }
        let s = std::str::from_utf8(&self.bytes[self.at..end])
            .ok()?
            .to_string();
        self.at = end;
        Some(s)
    }
}

fn restore_bytes(state: &[u8]) -> Option<TempConv> {
    let mut r = Reader {
        bytes: state,
        at: 0,
    };
    if r.line()? != PERSIST_TAG {
        return None;
    }
    let celsius = r.line()?.parse::<f64>().ok()?;
    let unit = r.line()?.chars().next().unwrap_or(' ');
    let draft = r.chunk()?;
    Some(TempConv {
        celsius: clamp(celsius),
        draft,
        unit,
    })
}

impl GuestInstance for TempConv {
    fn new(_component: String, args: Vec<(String, Value)>) -> Self {
        // 20°C rather than 0: a converter that opens on absolute nothing shows
        // three zeros, and three zeros do not demonstrate a conversion.
        let mut celsius = 20.0;
        for (name, v) in args {
            if let ("celsius", Value::Number(n)) = (name.as_str(), v) {
                celsius = n;
            }
        }
        TempConv {
            celsius: clamp(celsius),
            draft: String::new(),
            unit: ' ',
        }
    }

    /// Bytes back into an instance. `component` is checked rather than assumed:
    /// a bundle can declare several, and bytes one of them wrote say nothing
    /// about another.
    fn restore(component: String, state: Vec<u8>) -> Option<Instance> {
        if component != "TempConv" {
            return None;
        }
        restore_bytes(&state).map(Instance::new)
    }

    fn get_field(&self, name: String) -> Option<Value> {
        match name.as_str() {
            "celsius" => Some(Value::Number(self.celsius)),
            _ => None,
        }
    }

    fn seq_entries(&self) -> Option<Vec<(String, Value)>> {
        None
    }

    fn handle_event(&self, b: Bucket, name: String, args: Vec<Value>) -> Option<Instance> {
        // There is no "setCelsius" case: `celsius` is a declared field, so the
        // host generates the mutator and writes it through `with_field`. A
        // handler here would be the same assignment written twice.
        if !matches!(b, Bucket::Input) {
            return None;
        }
        match name.as_str() {
            "editC" => self.typed('c', &text_arg(&args)?),
            "editF" => self.typed('f', &text_arg(&args)?),
            "editK" => self.typed('k', &text_arg(&args)?),
            // A preset ends any edit in progress, which is what makes the three
            // boxes agree again: `at` clears the draft.
            "preset" => TempConv::at(num_arg(&args)?),
            _ => None,
        }
    }

    fn call_method(&self, name: String, _args: Vec<Value>) -> Value {
        match name.as_str() {
            "cText" => Value::Text(self.shown('c')),
            "fText" => Value::Text(self.shown('f')),
            "kText" => Value::Text(self.shown('k')),
            "note" => Value::Text(note_for(self.celsius)),
            _ => Value::Nil,
        }
    }

    fn with_field(&self, name: String, v: Value) -> Option<Instance> {
        match (name.as_str(), v) {
            ("celsius", Value::Number(n)) => TempConv::at(n),
            _ => None,
        }
    }

    /// Everything, including the half-typed number and which box it is in —
    /// the half `celsius` does not say, and the half somebody notices is
    /// missing when they come back to a form they were part-way through.
    fn persist(&self) -> Vec<u8> {
        persist_bytes(self)
    }
}

/// What a temperature IS, in a few words. Water's fixed points are the ones
/// everybody already knows, so they are the ones worth naming.
fn note_for(c: f64) -> String {
    if c <= -273.0 {
        "as cold as it gets".into()
    } else if c <= 0.0 {
        "water freezes".into()
    } else if c < 10.0 {
        "cold".into()
    } else if c < 25.0 {
        "room temperature".into()
    } else if c < 35.0 {
        "warm".into()
    } else if c < 40.0 {
        "body heat".into()
    } else if c < 100.0 {
        "hot".into()
    } else {
        "water boils".into()
    }
}

export!(Component);
