// Emitting the declared message buckets.
//
// The views can type every name an `@on` attribute writes. They cannot type
// what arrives from anywhere else: a message raised by `ctx.send`, an intent
// raised by `ctx.intent`, or the answer a walk produced, all from MoonBit code
// the views never see. Without the schema those were string-keyed
// `Array[Value]` end to end — the one place the generator had nothing to say.
//
// Declaring them buys both directions at once: a typed decode on the way in
// (`CounterReceive::from_dispatch`) and a typed raise on the way out
// (`CounterReceive::Tick.send(ctx)`), so the name is written once, in the
// schema, instead of twice as a matching pair of string literals.

///|
/// The declared buckets, if the schema declares any.
///
/// Two, and the interesting one is `Receive`: it is the schema's `receive`
/// variant **merged with the view names**, because one bucket holds every
/// addressed message whoever sent it. `Intent` is the schema's `intent`
/// variant.
fn emit_msgs(
  t : String,
  def : @statedef.StateDef,
  surface : Surface,
  out : StringBuilder,
) -> Unit raise GenError {
  emit_bucket_enum(
    t,
    "Receive",
    "Receive",
    merged_receive(def, surface),
    def,
    out,
  )
  emit_bucket_enum(t, "Intent", "Intent", def.intent, def, out)
}

///|
/// The schema's `receive` cases, plus every view name the schema does not
/// declare.
///
/// **This is the merge**, and it is where the design's new build error comes
/// from. A name in BOTH places is checked: the schema declares the payload and
/// the call sites have to match it. Two separate enums could not report that,
/// because nothing would compare them.
///
/// A view-only name is typed from what the call sites wrote, exactly as
/// `<T>Msg` types it — one inference, read from `InputSig` in both places.
fn merged_receive(
  def : @statedef.StateDef,
  surface : Surface,
) -> Array[@statedef.MsgDef] raise GenError {
  let out : Array[@statedef.MsgDef] = []
  let declared : Map[String, @statedef.MsgDef] = Map([])
  for m in def.receive {
    declared[m.name] = m
    out.push(m)
  }
  for sig in surface.inputs {
    match declared.get(sig.name) {
      // In both. The schema wins, and a disagreement is a build error.
      Some(m) => check_payload(m, sig)
      None => out.push(msg_of_sig(sig))
    }
  }
  out
}

///|
/// A view call site's inferred shape against the schema's declared payload.
///
/// Arity and scalar kind, and nothing finer. `args: None` is the join of call
/// sites that disagreed about arity, which is already opaque — the generator
/// cannot say what it should have been, so it says nothing. `VValue` is the
/// same answer one argument at a time.
fn check_payload(m : @statedef.MsgDef, sig : InputSig) -> Unit raise GenError {
  guard sig.args is Some(types) else { return }
  fn disagree(written : String) -> Unit raise GenError {
    raise PayloadDisagrees(
      name=m.name,
      declared=m.source_name +
        (if m.payload.is_empty() {
          ""
        } else {
          "(" + m.payload.map(p => p.show_source()).join(", ") + ")"
        }),
      written~,
      sites=sig.sites.join(", "),
    )
  }

  let wrote = m.name +
    (if types.is_empty() {
      ""
    } else {
      "(" + types.map(t => arg_kind_word(t)).join(", ") + ")"
    })
  if types.length() != m.payload.length() {
    disagree(wrote)
  }
  for i, t in types {
    if !arg_fits(t, m.payload[i]) {
      disagree(wrote)
    }
  }
}

///|
/// Whether a call site's inferred argument shape can be the declared type.
///
/// `VValue` fits everything: it is what the inference answers when the call
/// sites wrote something it cannot read as a scalar, and "unknown is not
/// wrong" is the rule the whole generator turns on. A declared type that is
/// not a scalar takes anything for the same reason — the payload rides as a
/// raw `@tutuca.Value` there (`msg_payload_ty`), so there is nothing to
/// disagree with.
fn arg_fits(t : ArgType, declared : @statedef.StateTy) -> Bool {
  match (t, declared) {
    (VValue, _) => true
    (VDouble, TInt(..) | TFloat) => true
    (VString, TText) => true
    (VBool, TBool) => true
    (_, TInt(..) | TFloat | TText | TBool) => false
    _ => true
  }
}

///|
/// The word an inferred argument shape reads as in the disagreement message.
fn arg_kind_word(t : ArgType) -> String {
  match t {
    VDouble => "a number"
    VString => "text"
    VBool => "a boolean"
    VValue => "a value"
  }
}

///|
/// A view-only name as a schema-shaped message case.
///
/// The variant name goes through `variants_for` at the call site, so this only
/// has to answer what the name and the payload are. Payload types are the ones
/// the call sites wrote; `args: None` — call sites that disagreed about arity —
/// becomes an empty payload, and the decode's `Unknown` arm carries the
/// arguments instead, which is exactly what `<T>Msg` does with the same input.
fn msg_of_sig(sig : InputSig) -> @statedef.MsgDef {
  let capped = sig.name[0:1].to_owned().to_upper() + sig.name[1:].to_owned()
  {
    // As the view wrote it, which is what `source_name` means everywhere else
    // — a schema declares a case in the spelling its call sites use, and a
    // view-only name has no other spelling to offer.
    source_name: sig.name,
    name: sig.name,
    variant: capped,
    // `arg_state_ty` answers None for a shape the inference could not read,
    // and `TAny` is what that declares as: the payload rides as a raw
    // `@tutuca.Value` either way (`msg_payload_ty`), so the two agree.
    payload: match sig.args {
      Some(types) => types.map(t => arg_state_ty(t).unwrap_or(TAny))
      None => []
    },
    doc: None,
  }
}

///|
/// One bucket: the enum, its decode, and its raise helpers.
fn emit_bucket_enum(
  t : String,
  suffix : String,
  dispatch_arm : String,
  msgs : Array[@statedef.MsgDef],
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit raise GenError {
  if msgs.is_empty() {
    return
  }
  // Guards against a schema whose case names collapse onto one variant.
  variants_for(msgs.map(m => m.name)) |> ignore
  let ty = "\{t}\{suffix}"
  let lower = suffix.to_lower()
  out.write_string(
    "///|\n" +
    "/// The \{dispatch_arm} arm of @component.Dispatch, decoded.\n" +
    "///\n" +
    "/// Declared as `variant \{lower}` in the state block. These names are\n" +
    "/// raised by component code rather than written in a view, so the views\n" +
    "/// cannot type them — the schema is the only place they can be declared.\n" +
    "pub(all) enum \{ty} {\n",
  )
  for m in msgs {
    // Line by line: a doc comment is a paragraph now. `MsgDef.doc` was
    // permanently `None` under WIT — `@wit.Field` carried no docs at all — so
    // this wrote a single line that never had a second one in it.
    match m.doc {
      Some(d) =>
        for line in d.split("\n") {
          out.write_string("  /// \{line}\n")
        }
      None => ()
    }
    if m.payload.is_empty() {
      out.write_string("  \{m.variant}\n")
    } else {
      let ps = m.payload.map(p => msg_payload_ty(def, p)).join(", ")
      out.write_string("  \{m.variant}(\{ps})\n")
    }
  }
  out.write_string(
    "  /// A \{lower} the schema does not declare, or a declared name whose\n" +
    "  /// runtime arguments did not match the declared types.\n" +
    "  Unknown(String, Array[@tutuca.Value])\n" +
    "}\n\n",
  )
  // -- decode ---------------------------------------------------------------
  out.write_string(
    "///|\n" +
    "/// Decode a \{dispatch_arm} dispatch. None for any other bucket.\n" +
    "///\n" +
    "/// A payload that does not match falls into `Unknown` rather than being\n" +
    "/// coerced: an `s32` handler handed 2.5 has been sent the wrong thing,\n" +
    "/// and silently truncating it would hide that.\n" +
    "pub fn \{ty}::from_dispatch(d : @component.Dispatch) -> \{ty}? {\n" +
    "  guard d is \{dispatch_arm}(name, args) else { return None }\n" +
    "  Some(\n" +
    "    match (name, args) {\n",
  )
  for m in msgs {
    emit_decode_arm(m, def, out)
  }
  out.write_string("      _ => Unknown(name, args)\n    },\n  )\n}\n\n")
  // -- raise ----------------------------------------------------------------
  emit_raise(ty, suffix, msgs, def, out)
}

///|
/// One decode arm: the argument patterns, plus a guard for anything the
/// pattern alone cannot express.
fn emit_decode_arm(
  m : @statedef.MsgDef,
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit {
  if m.payload.is_empty() {
    out.write_string("      (\{quote(m.name)}, []) => \{m.variant}\n")
    return
  }
  let pats : Array[String] = []
  let binds : Array[String] = []
  let guards : Array[String] = []
  for i, p in m.payload {
    let a = "a\{i}"
    match p {
      TInt(width~, signed~) => {
        pats.push("Num(\{a})")
        binds.push("\{a}.to_int()")
        // Integrality first, then range: a Double is the only numeric shape
        // a Value has, so both have to be checked here or not at all.
        guards.push("\{a}.to_int().to_double() == \{a}")
        let (lo, hi) = int_range(width, signed)
        guards.push("\{a} >= \{lo}.0")
        guards.push("\{a} <= \{hi}.0")
      }
      TFloat => {
        pats.push("Num(\{a})")
        binds.push(a)
      }
      TText => {
        pats.push("Str(\{a})")
        binds.push(a)
      }
      TBool => {
        pats.push("Bool(\{a})")
        binds.push(a)
      }
      // Everything else rides as the raw Value: a record, a list or a child
      // instance has no pattern this decode could usefully write.
      _ => {
        pats.push(a)
        binds.push(a)
        // Keeps `def` used on every path and the emitted type honest.
        def.moonbit_ty(p) |> ignore
      }
    }
  }
  let when_ = if guards.is_empty() { "" } else { " if " + guards.join(" && ") }
  out.write_string(
    "      (\{quote(m.name)}, [" +
    pats.join(", ") +
    "])\{when_} => \{m.variant}(" +
    binds.join(", ") +
    ")\n",
  )
}

///|
/// The inclusive range of a WIT integer width, as decimal text.
fn int_range(width : Int, signed : Bool) -> (String, String) {
  if signed {
    match width {
      8 => ("-128", "127")
      16 => ("-32768", "32767")
      _ => ("-2147483648", "2147483647")
    }
  } else {
    match width {
      8 => ("0", "255")
      16 => ("0", "65535")
      _ => ("0", "4294967295")
    }
  }
}

///|
/// The raise side: turn a typed message back into the name and arguments the
/// runtime dispatches, so the name is never written as a string twice.
fn emit_raise(
  ty : String,
  suffix : String,
  msgs : Array[@statedef.MsgDef],
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit {
  out.write_string(
    "///|\n" +
    "/// The dispatch name and arguments this message raises as.\n" +
    "pub fn \{ty}::to_dispatch(self : \{ty}) -> (String, Array[@tutuca.Value]) {\n" +
    "  match self {\n",
  )
  for m in msgs {
    if m.payload.is_empty() {
      out.write_string("    \{m.variant} => (\{quote(m.name)}, [])\n")
    } else {
      let binders = m.payload.mapi((i, _) => "a\{i}")
      let args = m.payload.mapi((i, p) => to_value_expr(p, binders[i], def))
      out.write_string(
        "    \{m.variant}(" +
        binders.join(", ") +
        ") => (\{quote(m.name)}, [" +
        args.join(", ") +
        "])\n",
      )
    }
  }
  out.write_string("    Unknown(n, args) => (n, args)\n  }\n}\n\n")
  // A Response is raised by the host answering a request, never by the
  // component, so it gets no sender. In v2 that whole bucket is gone: an
  // answer is an ordinary message and lands in `Receive` with everything else,
  // which is why `Intent` gets a raiser and nothing replaces `Response`'s
  // absence.
  match suffix {
    "Receive" =>
      emit_sender(
        ty, "send", "send", "Send this message to self; it arrives as a later Receive dispatch.",
        out,
      )
    "Intent" => emit_intent_sender(ty, out)
    "Bubble" =>
      emit_sender(
        ty, "bubble", "bubble", "Bubble this message to the parent component.", out,
      )
    _ => ()
  }
}

///|
/// `<T>Intent::dispatch(ctx)` — the v2 face of `<T>Bubble::bubble(ctx)`.
///
/// Separate from `emit_sender` because it takes a third argument the others do
/// not: the ROUTE, which is the whole of what v2 added. The default is written
/// once, in `@tutuca.IntentOpts::new`, and this passes it rather than spelling
/// the two legs — the same rule the parser and both backends follow.
fn emit_intent_sender(ty : String, out : StringBuilder) -> Unit {
  out.write_string(
    "///|\n" +
    "/// Dispatch this intent along `opts.route` — the default `dyn lex` when\n" +
    "/// nothing says otherwise. The `dyn` leg starts at this component's\n" +
    "/// PARENT, so a component never re-enters its own handler.\n" +
    "///\n" +
    "/// The name comes from the schema, so it cannot drift from the one\n" +
    "/// `from_dispatch` decodes.\n" +
    "pub fn \{ty}::dispatch(\n" +
    "  self : \{ty},\n" +
    "  ctx : &@tutuca.Ctx,\n" +
    "  opts? : @tutuca.IntentOpts = @tutuca.IntentOpts::new(),\n" +
    ") -> Unit {\n" +
    "  let (name, args) = self.to_dispatch()\n" +
    "  ctx.intent(name, args, opts)\n" +
    "}\n\n",
  )
}

///|
fn emit_sender(
  ty : String,
  fn_name : String,
  ctx_method : String,
  doc : String,
  out : StringBuilder,
) -> Unit {
  out.write_string(
    "///|\n" +
    "/// \{doc}\n" +
    "///\n" +
    "/// The name comes from the schema, so it cannot drift from the one\n" +
    "/// `from_dispatch` decodes.\n" +
    "pub fn \{ty}::\{fn_name}(self : \{ty}, ctx : &@tutuca.Ctx) -> Unit {\n" +
    "  let (name, args) = self.to_dispatch()\n" +
    "  ctx.\{ctx_method}(name, args)\n" +
    "}\n\n",
  )
}

///|
/// A MoonBit value of this type, as a @tutuca.Value.
fn to_value_expr(
  ty : @statedef.StateTy,
  binder : String,
  def : @statedef.StateDef,
) -> String {
  def.moonbit_ty(ty) |> ignore
  match ty {
    TInt(..) => "Num(\{binder}.to_double())"
    TFloat => "Num(\{binder})"
    TText => "Str(\{binder})"
    TBool => "Bool(\{binder})"
    // Everything else already IS the Value — see `msg_payload_ty`.
    _ => binder
  }
}

///|
/// The MoonBit type one message payload carries.
///
/// A scalar is its own type; everything else is `@tutuca.Value`. This is the
/// ONE place that decides, because three sites have to agree — the enum
/// variant, the pattern `from_dispatch` matches, and the expression
/// `to_dispatch` writes — and they did not: the variant said
/// `Array[@tutuca.Value]` for a `values` payload while the decode bound the raw
/// Value, so the generated module did not compile.
///
/// Value rather than the declared collection because a dispatch payload
/// arrives as `Array[@tutuca.Value]` and always did. Typing it as an
/// `Array[String]` would mean converting, and the only converter to hand was a
/// JSON round trip — the same one the state codec exists to avoid. The handler
/// destructures the Value instead, which is what the `Unknown` arm does too.
fn msg_payload_ty(def : @statedef.StateDef, ty : @statedef.StateTy) -> String {
  match ty {
    TInt(..) | TFloat | TText | TBool => def.moonbit_ty(ty)
    _ => "@tutuca.Value"
  }
}
