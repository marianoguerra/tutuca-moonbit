// One step: perform it, or read and judge it.

///|
/// Why a scene could not be mounted. Its own type because `run` answers a
/// report rather than raising — a block of ten scenes whose fourth names a
/// component that does not exist should still report the other nine.
pub suberror MountError {
  MountError(String)
}

///|
pub fn MountError::message(self : MountError) -> String {
  let MountError(m) = self
  m
}

///|
/// Perform or read one step, and the refusals it raised.
///
/// EVERY step is wrapped, not just the drive verbs. A refusal raised while a
/// reader runs would otherwise be attributed to the next drive step, and the
/// report would name the wrong line of the block.
fn run_step(
  h : @harness.Harness,
  scene : @scenedef.Scene,
  at : Int,
  step : @scenedef.Step,
  take_log : () -> Array[String],
) -> (StepResult, Array[String], Array[String]) {
  let mut result : StepResult = { at, ok: true, got: None, want: None, why: "" }
  let refused = @harness.refusals_while(() => {
    match step {
      Read(e) => result = judge(h, scene, at, e, [])
      _ => perform(h, step)
    }
  }) catch {
    // A verb that raises is a selector that matched nothing, which is the one
    // failure the harness reports by raising rather than by doing nothing.
    e =>
      return (
        { at, ok: false, got: None, want: None, why: e.to_string() },
        [],
        take_log(),
      )
  }
  let lines = refused.map(r => r.to_line())
  // A reader that asked about refusals has to be told the ones raised by its
  // OWN step, which is nothing — it is asking about the step before it. Judged
  // again with the lines in hand rather than threaded through, because only
  // this reader wants them and only after the drive that produced them.
  // Accumulated until READ, rather than reset every step.
  //
  // "What the step before this one refused" is precise and is the wrong rule:
  // a scene clicks the guarded button, checks the DOM did not move, and only
  // then asks what happened — by which time a per-step window has already
  // closed. Reading is what empties them, so `{ "expect": "log" }` answers
  // everything since the last time a scene asked.
  let logged = take_log()
  for l in logged {
    prev_log.val.push(l)
  }
  for r in lines {
    prev_refusals.val.push(r)
  }
  match step {
    Read(e) =>
      match e.reader {
        RRefused => {
          result = judge(h, scene, at, e, prev_refusals.val)
          prev_refusals.val = []
        }
        RLog => {
          result = judge(h, scene, at, e, prev_refusals.val)
          prev_log.val = []
        }
        _ => ()
      }
    _ => ()
  }
  (result, lines, logged)
}

///|
/// What the previous step refused, for the one reader that asks.
///
/// A `Ref` rather than a parameter because the alternative is threading it
/// through `run_one`'s loop, `run_step` and `judge` for the sake of one reader.
/// Reset per scene by `run_one`.
let prev_refusals : Ref[Array[String]] = Ref([])

///|
/// What the previous step logged, for the reader that asks. Same shape and
/// same reason as the refusals above.
let prev_log : Ref[Array[String]] = Ref([])

///|
/// Forget the previous scene's refusals.
fn reset_refusals() -> Unit {
  prev_refusals.val = []
  prev_log.val = []
}

///|
/// The drive verbs. Each is one harness call and nothing else: what a click
/// DOES is the harness's business, and a second opinion about it here is how
/// two implementations of `nth` start disagreeing.
fn perform(h : @harness.Harness, step : @scenedef.Step) -> Unit raise {
  match step {
    Click(sel~, nth~) => h.click(sel, nth~)
    Type(sel~, value~, nth~) => h.type_into(sel, value, nth~)
    Key(sel~, key~, value~, nth~) =>
      match value {
        Some(v) => h.key_down(sel, key, value=v, nth~)
        None => h.key_down(sel, key, nth~)
      }
    Check(sel~, checked~, nth~) => h.check(sel, checked, nth~)
    Fire(sel~, event~, value~, key~, nth~) =>
      h.fire(
        sel,
        @render.DomEvent::new(name=event, value=value.unwrap_or(Null), key~),
        nth~,
      )
    Drag(sel~, from~, to~) => h.drag(sel, from, to)
    Send(name~, args~) => h.send_at_root(name, args~)
    Read(_) => ()
  }
}

///|
/// Read what the expectation names, then say whether it is what was wanted.
///
/// `got` is filled in whether or not the step passed, and whether or not it
/// asked for anything: an expectation written with no answer is the RECORD
/// form, and what it wants is exactly this.
fn judge(
  h : @harness.Harness,
  scene : @scenedef.Scene,
  at : Int,
  e : @scenedef.Expect,
  refused : Array[String],
) -> StepResult {
  let got = read(h, scene, e, refused) catch {
    err => return { at, ok: false, got: None, want: None, why: err.to_string() }
  }
  match e.want {
    // RECORD: read it and hand it back. Never a failure — the whole point is
    // to run a drive you have not written the answers to yet.
    None => { at, ok: true, got: Some(got), want: None, why: "" }
    Some(WIs(want)) =>
      if same(got, want) {
        { at, ok: true, got: Some(got), want: Some(want), why: "" }
      } else {
        {
          at,
          ok: false,
          got: Some(got),
          want: Some(want),
          why: "`" +
          e.reader.word() +
          "` answered " +
          show(got) +
          ", not " +
          show(want),
        }
      }
    Some(WContains(want)) => {
      let hay = match got {
        Str(s) => s
        other => show(other)
      }
      if hay.contains(want) {
        { at, ok: true, got: Some(got), want: Some(Str(want)), why: "" }
      } else {
        {
          at,
          ok: false,
          got: Some(got),
          want: Some(Str(want)),
          why: "`" + e.reader.word() + "` does not contain " + show(Str(want)),
        }
      }
    }
  }
}

///|
/// Each reader, as the one harness call it stands for.
fn read(
  h : @harness.Harness,
  scene : @scenedef.Scene,
  e : @scenedef.Expect,
  refused : Array[String],
) -> @tutuca.Value raise {
  match e.reader {
    RText => Str(h.text(e.sel, nth=e.nth))
    RTexts => List(h.texts(e.sel).map(t => Str(t)))
    RAttr =>
      match h.attr(e.sel, e.name, nth=e.nth) {
        Some(v) => Str(v)
        None => Null
      }
    RProp =>
      match h.prop(e.sel, e.name, nth=e.nth) {
        Some(v) => of_attr(v)
        None => Null
      }
    RValue => Str(h.value_of(e.sel, nth=e.nth))
    RChecked => Bool(h.checked_of(e.sel, nth=e.nth))
    RCount => Num(h.find_all(e.sel).length().to_double())
    RState => {
      let root = h.drive_value()
      if e.place.is_empty() {
        root
      } else {
        @tutuca.Path::new(steps=e.place).lookup(root).unwrap_or(Null)
      }
    }
    RHtml =>
      Str(
        if scene.raw {
          h.container.to_html()
        } else {
          clean_html(h.container)
        },
      )
    RRenders => Num(h.render_count().to_double())
    RRefused => List(refused.map(r => Str(r)))
    RLog => List(prev_log.val.map(l => Str(l)))
  }
}

///|
/// A DOM property as a value. Every case that carries markup answers the
/// markup: a scene asserting on `innerHTML` wants the string, and wrapping it
/// in a kind it would then have to unwrap says nothing extra.
fn of_attr(v : @vdom.AttrValue) -> @tutuca.Value {
  match v {
    Str(s) | Html(s) | Md(s) | SafeHtml(s) | Svg(s) => Str(s)
    Num(n) => Num(n)
    Bool(b) => Bool(b)
    Data(j) => @tutuca.Value::from_json(j)
  }
}

///|
/// A value as the JSON a report prints, so `why` reads the way the block is
/// written rather than the way MoonBit debugs.
fn show(v : @tutuca.Value) -> String {
  v.to_json().stringify()
}

///|
/// Whether a read answered what the block asked for.
///
/// Compared as JSON rather than as `Value`, and that is not a shortcut. What a
/// scene writes is JSON, so what it MEANS is a JSON value — and the two are not
/// the same thing on this side: a component instance is `Value::Obj`, which
/// projects to its declared fields and can never be `Eq` to the `Value::Map` a
/// block's `{ "count": 2 }` parses into, however identically the two print.
/// `{ "expect": "state" }` with no place is exactly that comparison, so
/// comparing values would make the whole-state form permanently false.
///
/// Objects compare UNORDERED. A `Value::Map` is insertion-ordered and a block
/// is written by a person, so requiring the two to agree on the order of two
/// keys would fail a scene for a reason that is not about the component.
fn same(got : @tutuca.Value, want : @tutuca.Value) -> Bool {
  json_eq(got.to_json(), want.to_json())
}

///|
fn json_eq(a : Json, b : Json) -> Bool {
  match (a, b) {
    (Object(x), Object(y)) => {
      if x.length() != y.length() {
        return false
      }
      for k, v in x {
        guard y.get(k) is Some(w) && json_eq(v, w) else { return false }
      }
      true
    }
    (Array(x), Array(y)) => {
      if x.length() != y.length() {
        return false
      }
      for i, v in x {
        guard json_eq(v, y[i]) else { return false }
      }
      true
    }
    _ => a == b
  }
}
