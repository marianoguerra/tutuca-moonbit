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
  guard bucket is INPUT else { return Unhandled }
  match name {
    "digit" =>
      match args {
        [@values.Value::Text(d), ..] => Changed(self.digit(d) as &DynComponent)
        _ => Unchanged
      }
    "point" => Changed(self.point() as &DynComponent)
    "operate" =>
      match args {
        [@values.Value::Text(op), ..] =>
          Changed(self.operate(op) as &DynComponent)
        _ => Unchanged
      }
    "equals" => Changed(self.equals() as &DynComponent)
    "clear" => Changed(Calc::zero() as &DynComponent)
    "back" => Changed(self.back() as &DynComponent)
    "negate" => Changed(self.negate() as &DynComponent)
    _ => Unhandled
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
fn dyn_module() -> DynModule {
  module_def(
    // It DOES persist, unlike the counter: half its state is not declared, so a
    // host projecting the declared fields would bring back the right number on
    // screen with no memory of the sum it was part-way through.
    [dyn_comp("Calculator", make_calc, restore=restore_calc)],
  )
}
