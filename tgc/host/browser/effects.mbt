///| What a card asked the host to do during the call that just returned.
///
/// The HOST buffers rather than the guest, because the host is what brackets
/// the call and therefore knows when it ended — an effect performed before a
/// statement that abandons is discarded with the transition, and only this side
/// can tell that the transition abandoned.
///
/// The buffer itself stays in JS, holding RAW `tg_val`s. That is deliberate and
/// it is what makes this design carry to wasm-gc: a MoonBit closure cannot
/// cross into JS there, so the `tut` imports a module is instantiated against
/// have to be JS functions whatever the host is written in. What changed is
/// only what they keep — a reference rather than a string.

///|
/// Take everything the module buffered, as one `tg_val` list.
/// Empty the buffer BEFORE a call, so what `drained` reads afterwards is this
/// call's and only this call's.
///
/// The JSON seam cleared here too. Without it a dispatch inherits whatever a
/// render call left behind, and effects arrive attributed to the wrong
/// transition.
pub fn clear_control(key : String) -> Unit {
  take_control(key) |> ignore
}

///|
extern "js" fn take_control(key : String) -> @core.Any =
  #|(key) => { const b = globalThis.__tgcmod[key].control; return b.splice(0, b.length); }

///|
/// One buffered call: a verb and its arguments, positionally.
///
/// The shape is `[verb, ...]` and each verb's remaining slots are fixed. It is
/// an array rather than a map because it is written and read by two halves of
/// one seam, twenty lines apart, and a map would only be a place for the names
/// to differ.
/// The VERB, which is an ordinary JS string: this half of the seam writes it
/// and this half reads it, so there is nothing to encode.
extern "js" fn entry_verb(e : @core.Any) -> String =
  #|(e) => e[0]

///|
/// A NAME, which is `tg_bytes`: the guest wrote it, and the guest keeps text
/// as bytes.
fn entry_str(rt : @core.Any, e : @core.Any, i : Int) -> String {
  let v = arr_at(e, i)
  if is_absent(v) {
    ""
  } else {
    text_of(rt, v)
  }
}

///|
/// The route an `ask` or a `notify` named, as the one integer the emitter
/// writes it as.
///
/// Written RESOLVED — a bare `ask` is `dyn lex` — because the default route is
/// exactly the kind of thing two backends can agree to disagree about while
/// every case with an explicit route passes.
fn route_of(n : Int) -> Array[@tutuca.Leg] {
  match n {
    1 => [Dyn]
    2 => [Lex]
    3 => [Dyn, Lex]
    4 => [Lex, Dyn]
    _ => []
  }
}

///|
fn opts_of(n : Int) -> @tutuca.IntentOpts {
  let legs = route_of(n)
  if legs.is_empty() {
    @tutuca.IntentOpts::new()
  } else {
    @tutuca.IntentOpts::new(route=legs)
  }
}

///|
/// A reified place, as the host's own steps.
///
/// The generator writes these in the host's spelling already — `{"field":…}`,
/// `{"item":[seq,key]}`, `{"at":[seq,i]}` — so this reads them rather than
/// translating them.
fn steps_of(v : @tutuca.Value) -> Array[@tutuca.Step] {
  let out : Array[@tutuca.Step] = []
  guard v is List(items) else { return out }
  for item in items {
    guard item is Map(m) else { continue }
    match m.get("field") {
      Some(Str(f)) => {
        out.push(FieldStep(f))
        continue
      }
      _ => ()
    }
    // `{"item": [field, key]}` is a keyed read and `{"at": [field, index]}` is
    // an indexed one — both a `SeqStep`, differing only in the kind of key.
    // `mk_step_key` in `tgc/rt/rt.wax` decides which, and it decides by whether
    // the key is a whole non-negative number.
    match m.get("item") {
      Some(List([Str(field), Str(key)])) => {
        out.push(SeqStep(field~, key=KStr(key)))
        continue
      }
      _ => ()
    }
    match m.get("at") {
      Some(List([Str(field), Num(i)])) => {
        out.push(SeqStep(field~, key=KInt(i.to_int())))
        continue
      }
      _ => ()
    }
  }
  out
}

///|
/// Everything the module buffered, as the host's control vocabulary.
fn drained(owner : NativeModule) -> Array[@host.ControlMsg] {
  let raw = take_control(owner.key)
  let out : Array[@host.ControlMsg] = []
  let rt = owner.rt
  let decode = (v : @core.Any) => {
    value_of(rt, v, inst => wrap(owner, inst)).unwrap_or(Null)
  }
  let args_at = (e : @core.Any, i : Int) => {
    match decode(arr_at(e, i)) {
      List(items) => items
      Null => []
      other => [other]
    }
  }
  for i in 0..<arr_len(raw) {
    let e = arr_at(raw, i)
    match entry_verb(e) {
      "send" => out.push(Send(entry_str(rt, e, 1), args_at(e, 2)))
      "sendAt" =>
        out.push(
          SendAt(
            steps_of(decode(arr_at(e, 1))),
            entry_str(rt, e, 2),
            args_at(e, 3),
          ),
        )
      "sendReply" => out.push(SendReply(entry_str(rt, e, 1), args_at(e, 2)))
      "reply" => out.push(Reply(decode(arr_at(e, 1))))
      "fail" => out.push(Fail(decode(arr_at(e, 1))))
      "intent" =>
        out.push(
          Intent(
            entry_str(rt, e, 1),
            args_at(e, 2),
            opts_of(as_int(arr_at(e, 3))),
          ),
        )
      "forward" =>
        out.push(Forward(args_at(e, 1), opts_of(as_int(arr_at(e, 2)))))
      "setAt" =>
        out.push(
          SetAt(
            steps_of(decode(arr_at(e, 1))),
            entry_str(rt, e, 2),
            decode(arr_at(e, 3)),
          ),
        )
      "stopPropagation" => out.push(StopPropagation)
      _ => ()
    }
  }
  out
}
