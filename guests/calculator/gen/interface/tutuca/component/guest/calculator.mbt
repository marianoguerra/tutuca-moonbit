///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// A four-function calculator. What it is here to show is the split the
/// contract keeps asking about: which half of a component's state is DECLARED
/// and which half is its own.
///
/// `display` is declared, because it is the answer — the thing a host can
/// project, compare, put in a form and hand back after a reload. The pending
/// operand and the operator waiting on it are NOT: they are how the answer is
/// being arrived at, they mean nothing outside this component, and a host that
/// could write them could not reason about what it wrote. So they live in
/// `persist`, which is the case `persist` exists for.

///|
/// A calculator's whole state.
///
/// `entering` is the difference between "3" as something just typed and "3" as
/// the result of the last sum: a digit after a result starts a new number, a
/// digit after a digit extends one. Without it, `2 + 3 =` then `7` reads `57`.
priv struct Calc {
  /// What the screen says. TEXT rather than a number because a calculator
  /// shows `3.` and `0.10` and `-`, none of which is a number distinct from
  /// another, and all of which somebody is in the middle of typing.
  display : String
  /// The number waiting for an operator to be applied to it, if any.
  pending : Double?
  /// The operator waiting on `pending`: `+`, `-`, `*`, `/`, or "" for none.
  op : String
  /// Whether `display` is being typed rather than shown as an answer.
  entering : Bool
}

///|
const ERROR : String = "error"

///|
fn Calc::zero() -> Calc {
  { display: "0", pending: None, op: "", entering: false }
}

///|
/// The display as a number. A display that is not one reads as 0 — which it
/// can only be while being typed (`-`, `3.`), where 0 is what a calculator
/// shows anyway.
fn Calc::value(self : Calc) -> Double {
  @string.parse_double(self.display) catch {
    _ => 0.0
  }
}

///|
/// A number as a calculator shows it.
///
/// Rounded before it is printed, because the answer to `0.1 + 0.2` is
/// technically `0.30000000000000004` and practically broken: a calculator that
/// shows the float is right about the arithmetic and wrong about the job.
fn show_num(v : Double) -> String {
  if v != v {
    return ERROR
  }
  let rounded = (v * 1.0e10).round() / 1.0e10
  if rounded == rounded.floor() && rounded.abs() < 9.0e15 {
    return rounded.to_int64().to_string()
  }
  rounded.to_string()
}

///|
/// `a op b`, or None when there is no answer.
///
/// Division by zero is None rather than infinity: `error` is what a calculator
/// says, and infinity is not a number anybody asked for.
fn apply_op(op : String, a : Double, b : Double) -> Double? {
  match op {
    "+" => Some(a + b)
    "-" => Some(a - b)
    "*" => Some(a * b)
    "/" => if b == 0.0 { None } else { Some(a / b) }
    _ => Some(b)
  }
}

///|
/// The display with `d` appended, as a calculator appends it.
fn Calc::digit(self : Calc, d : String) -> Calc {
  if !self.entering || self.display == "0" || self.display == ERROR {
    return { ..self, display: d, entering: true }
  }
  // Long enough to be useful, short enough to stay on screen. A calculator you
  // can type into forever is one whose display you cannot read.
  if self.display.length() >= 14 {
    return self
  }
  { ..self, display: self.display + d, entering: true }
}

///|
/// A decimal point, at most one per number.
fn Calc::point(self : Calc) -> Calc {
  if !self.entering || self.display == ERROR {
    return { ..self, display: "0.", entering: true }
  }
  if self.display.contains(".") {
    return self
  }
  { ..self, display: self.display + ".", entering: true }
}

///|
/// Choose an operator.
///
/// Pressing one while another is pending EVALUATES first, so `2 + 3 * 4` runs
/// left to right and shows `5` on the way — which is what a four-function
/// calculator does and what somebody pressing the keys is watching for.
/// Precedence belongs to an expression parser, and this is not one.
fn Calc::operate(self : Calc, op : String) -> Calc {
  if self.display == ERROR {
    return self
  }
  let left = match (self.pending, self.entering) {
    // Nothing typed since the last operator: just change which one is waiting.
    (Some(p), false) => Some(p)
    (Some(p), true) => apply_op(self.op, p, self.value())
    (None, _) => Some(self.value())
  }
  match left {
    None => { display: ERROR, pending: None, op: "", entering: false }
    Some(v) => { display: show_num(v), pending: Some(v), op, entering: false }
  }
}

///|
/// Evaluate, leaving the answer on screen and nothing pending.
fn Calc::equals(self : Calc) -> Calc {
  match self.pending {
    None => { ..self, entering: false }
    Some(p) =>
      match apply_op(self.op, p, self.value()) {
        None => { display: ERROR, pending: None, op: "", entering: false }
        Some(out) =>
          { display: show_num(out), pending: None, op: "", entering: false }
      }
  }
}

///|
/// The last thing entered, undone: a digit at a time while typing, and the
/// whole thing otherwise.
fn Calc::back(self : Calc) -> Calc {
  if !self.entering || self.display == ERROR {
    return Calc::zero()
  }
  if self.display.length() <= 1 {
    return { ..self, display: "0", entering: false }
  }
  { ..self, display: self.display[0:self.display.length() - 1].to_owned() }
}

///|
/// The sign of what is on screen.
///
/// Its own key rather than a `-` digit, because `-` is already an operator and
/// a calculator that made you press `0 - 5` to get `-5` is one nobody uses
/// twice.
fn Calc::negate(self : Calc) -> Calc {
  if self.display == ERROR || self.display == "0" {
    return self
  }
  if self.display.has_prefix("-") {
    { ..self, display: self.display[1:].to_owned() }
  } else {
    { ..self, display: "-" + self.display }
  }
}

// --- the contract -----------------------------------------------------------

///|
impl DynComponent for Calc with fn get_field(self, name) {
  match name {
    "display" => Some(@values.Value::Text(self.display))
    _ => None
  }
}

///|
impl DynComponent for Calc with fn handle(self, bucket, name, args) {
  guard bucket is INPUT else { return None }
  match name {
    "digit" =>
      match args {
        [@values.Value::Text(d), ..] => Some(self.digit(d) as &DynComponent)
        _ => None
      }
    "point" => Some(self.point() as &DynComponent)
    "operate" =>
      match args {
        [@values.Value::Text(op), ..] => Some(self.operate(op) as &DynComponent)
        _ => None
      }
    "equals" => Some(self.equals() as &DynComponent)
    "clear" => Some(Calc::zero() as &DynComponent)
    "back" => Some(self.back() as &DynComponent)
    "negate" => Some(self.negate() as &DynComponent)
    _ => None
  }
}

///|
impl DynComponent for Calc with fn call_method(self, name, _args) {
  match name {
    // What is waiting, for the small line above the display. It is the half of
    // the state the screen does not show, and a calculator that hides it makes
    // you remember which operator you pressed.
    "pendingLabel" =>
      match self.pending {
        Some(p) if self.op != "" =>
          @values.Value::Text("\{show_num(p)} \{self.op}")
        _ => @values.Value::Text("")
      }
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Calc with fn with_field(_self, name, v) {
  match (name, v) {
    // A host writing the display — the generated `setDisplay`, or a restore
    // from the declared fields — SETTLES the calculator: whatever was pending
    // belonged to a sum nobody else can finish.
    ("display", @values.Value::Text(s)) =>
      Some(
        ({ display: s, pending: None, op: "", entering: false } : Calc)
        as &DynComponent,
      )
    _ => None
  }
}

///|
/// Everything, including the half `display` does not say.
///
/// JSON because this state is four scalars with nothing arbitrary in them —
/// the case where the length-prefixed format the Rust guest uses would be
/// ceremony rather than safety.
impl DynComponent for Calc with fn persist(self) {
  let m : Map[String, Json] = {
    "v": Json::number(1),
    "display": Json::string(self.display),
    "op": Json::string(self.op),
    "entering": Json::boolean(self.entering),
  }
  match self.pending {
    Some(p) => m["pending"] = Json::number(p)
    None => ()
  }
  bytes_of(Json::object(m).stringify())
}

///|
/// The inverse. Anything unreadable is REFUSED rather than patched up: the
/// host then rebuilds from the declared fields, which is a calculator showing
/// the right number with nothing pending — a worse restore than the real one,
/// and a much better one than a wrong pending operand.
fn restore_calc(state : FixedArray[Byte]) -> &DynComponent? {
  let text = text_of(state)
  if text == "" {
    return None
  }
  let parsed = @json.parse(text) catch { _ => return None }
  guard parsed is Object(m) else { return None }
  guard m.get("v") is Some(Number(1.0, ..)) else { return None }
  guard m.get("display") is Some(String(display)) else { return None }
  let op = match m.get("op") {
    Some(String(s)) => s
    _ => ""
  }
  let entering = m.get("entering") is Some(True)
  let pending = match m.get("pending") {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
  Some(({ display, pending, op, entering } : Calc) as &DynComponent)
}

///|
fn make_calc(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut display = "0"
  for arg in args {
    let (name, v) = arg
    if name == "display" && v is @values.Value::Text(s) && s != "" {
      display = s
    }
  }
  ({ ..Calc::zero(), display, } : Calc) as &DynComponent
}

// --- the view ---------------------------------------------------------------

///|
/// One key of the pad. Written once, because twenty buttons differing only in
/// a label and a handler is twenty chances to mistype one.
fn key(label : String, handler : String, cls? : String = "btn-soft") -> String {
  "<button class=\"btn \{cls} k\" @on.click=\"\{handler}\">\{label}</button>"
}

///|
/// The keypad, as the classic four-column grid:
///
///   C  ±  ←  /
///   7  8  9  *
///   4  5  6  -
///   1  2  3  +
///   0     .  =
///
/// `0` spans two columns rather than leaving a hole beside it: a gap in a
/// keypad reads as a key that failed to render.
fn calc_view() -> String {
  let rows = [
    [
      key("C", "clear", cls="btn-error btn-soft"),
      key("±", "negate"),
      key("←", "back"),
      key("/", "operate '/'", cls="btn-primary"),
    ],
    [
      key("7", "digit '7'", cls=""),
      key("8", "digit '8'", cls=""),
      key("9", "digit '9'", cls=""),
      key("*", "operate '*'", cls="btn-primary"),
    ],
    [
      key("4", "digit '4'", cls=""),
      key("5", "digit '5'", cls=""),
      key("6", "digit '6'", cls=""),
      key("-", "operate '-'", cls="btn-primary"),
    ],
    [
      key("1", "digit '1'", cls=""),
      key("2", "digit '2'", cls=""),
      key("3", "digit '3'", cls=""),
      key("+", "operate '+'", cls="btn-primary"),
    ],
    [
      key("0", "digit '0'", cls="col-span-2"),
      key(".", "point", cls=""),
      key("=", "equals", cls="btn-secondary"),
    ],
  ]
  let pad = StringBuilder::new()
  for row in rows {
    for k in row {
      pad.write_string(k)
    }
  }
  let sb = StringBuilder::new()
  sb.write_string(
    "<div class=\"card card-border bg-base-100 border-base-300 shadow-sm w-64 calculator\">",
  )
  sb.write_string("<div class=\"card-body gap-3 p-4\">")
  // The screen: one block, right-aligned, with the pending sum above it in
  // small type. `tabular-nums` so a digit changing does not move the ones
  // beside it, which is what makes a calculator display feel steady.
  sb.write_string(
    "<div class=\"rounded-box bg-base-200 px-3 py-2 text-right\">",
  )
  sb.write_string(
    "<div class=\"h-4 text-xs opacity-50 font-mono tabular-nums pending\" @text=\"$pendingLabel\"></div>",
  )
  sb.write_string(
    "<div class=\"text-3xl font-mono tabular-nums truncate display\" @text=\".display\"></div>",
  )
  sb.write_string("</div>")
  sb.write_string("<div class=\"grid grid-cols-4 gap-1.5 pad\">")
  sb.write_string(pad.to_string())
  sb.write_string("</div></div></div>")
  sb.to_string()
}

///|
fn calc_def() -> ComponentDef {
  component_def(
    "Calculator",
    doc="A four-function calculator: digits, the four operators, and an answer.",
    keywords=[
      "calculator", "math", "arithmetic", "numbers", "add", "multiply", "sum",
    ],
    category="tool",
    message_docs=[
      { name: "digit", doc: "Type a digit." },
      { name: "point", doc: "Type a decimal point." },
      {
        name: "operate",
        doc: "Choose an operator, working out anything pending first.",
      },
      { name: "equals", doc: "Work out the answer." },
      { name: "clear", doc: "Start again from zero." },
      { name: "back", doc: "Undo the last digit." },
      { name: "negate", doc: "Flip the sign of what is on screen." },
      {
        name: "pendingLabel",
        doc: "The number and operator waiting, for the line above the display.",
      },
    ],
    views=[{ name: "main", html: calc_view() }],
    // ONE declared field, and it is the answer rather than the working. What is
    // pending is real state — it is in `persist` — but it means nothing outside
    // this component, so declaring it would invite a host to write something it
    // cannot reason about.
    types=[{ kind: TY_TEXT, elem: None, items: [], name: "", members: [] }],
    fields=[
      field(
        "display",
        0,
        doc="What the screen says.",
        constraint=Some({
          ..no_limits(),
          max_len: Some(16),
          default_json: "\"0\"",
        }),
      ),
    ],
    // `setDisplay` is deliberately absent: it is the mutator `display` implies,
    // and the host answers it.
    handlers=["digit", "point", "operate", "equals", "clear", "back", "negate"],
    receives=["init"],
    methods=["pendingLabel"],
    inits=[
      {
        name: "answer",
        args_json: "{\"display\": \"42\"}",
        doc: "Starts showing the answer to everything.",
      },
    ],
  )
}

///|
fn dyn_module() -> DynModule {
  module_def(
    "calclib",
    // It DOES persist, unlike the counter: half its state is not declared, so a
    // host projecting the declared fields would bring back the right number on
    // screen with no memory of the sum it was part-way through.
    [dyn_comp(calc_def(), make_calc, restore=restore_calc)],
    doc="A calculator, as a loadable component.",
    version="0.4.0",
    // It asks for nothing: no clock, no randomness, no timer.
    capabilities=[],
  )
}
