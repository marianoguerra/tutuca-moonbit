// Emitting the declared message buckets.
//
// The views can type every name an `@on` attribute writes. They cannot type
// what arrives from anywhere else: a message raised by `ctx.send`, an intent
// raised by `ctx.intent`, or the answer a walk produced, all from MoonBit code
// the views never see. Without the schema those were string-keyed
// `Array[Value]` end to end — the one place the generator had nothing to say.
//
// Declaring them buys both directions at once: a typed decode on the way in
// (`CounterMsg::from_dispatch`) and a typed raise on the way out
// (`CounterMsg::Tick.send(ctx)`), so the name is written once, in the
// schema, instead of twice as a matching pair of string literals.

///|
/// The two message enums.
///
/// `<T>Msg` is the schema's `message` variant **merged with the view names**,
/// because one bucket holds every addressed message whoever sent it — and
/// there is one type over it for the same reason. There used to be two: this
/// one under the name `<T>Receive`, and a `<T>Msg` in `emit.mbt` holding the
/// view names alone with their inferred shapes. The second was a strictly
/// weaker view of the first — every name in it is in this one, typed by the
/// schema where the schema says anything — so an author matching the bucket
/// had to write two matches over one thing, or find out which of the two to
/// use. `<T>Intent` is the schema's `intent` variant.
fn emit_msgs(
  t : String,
  def : @statedef.StateDef,
  surface : Surface,
  answered_inputs : Array[String],
  out : StringBuilder,
) -> Unit raise GenError {
  emit_bucket_enum(
    t,
    "Msg",
    "Receive",
    merged_receive(def, surface),
    def,
    answered_inputs,
    out,
  )
  emit_bucket_enum(t, "Intent", "Intent", def.intent, def, [], out)
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
fn arg_fits(t : ArgType, declared : @tutuca.Ty) -> Bool {
  match (t, declared) {
    (VValue, _) => true
    (VDouble, TyInt(..) | TyFloat) => true
    (VString, TyText) => true
    (VBool, TyBool) => true
    (_, TyInt(..) | TyFloat | TyText | TyBool) => false
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
/// is VARIADIC, and the arm is handed the raw argument list. Not an empty
/// payload: `activate @key` and `activate @key e.isCtrl` are two call sites of
/// one name, and a case that took nothing would decode both to `Unknown`.
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
    // and `TyAny` is what that declares as: the payload rides as a raw
    // `@tutuca.Value` either way (`msg_payload_ty`), so the two agree.
    payload: match sig.args {
      Some(types) => types.map(t => arg_state_ty(t).unwrap_or(TyAny))
      None => []
    },
    variadic: sig.args is None,
    doc: None,
  }
}

///|
/// Which cases the script block already answers, as a doc line.
///
/// They are still IN the enum, because its variants are also what
/// `to_dispatch` raises and a parent raising one is exactly what the block is
/// there to answer. What the note buys is the other half: an `update` arm for
/// one of these can never run, because the generated wrapper consults the
/// author's `update` only for a dispatch the block did not claim.
fn answered_note(answered : Array[String]) -> String {
  if answered.is_empty() {
    return ""
  }
  "///\n" +
  "/// The script block answers \{answered.join(", ")}, so an `update` arm for\n" +
  "/// one of those can never run — the wrapper consults `update` only for a\n" +
  "/// dispatch the block did not claim. They are still here because raising\n" +
  "/// one is what a parent does, and `to_dispatch` is how.\n"
}

///|
/// A schema that declares nothing, to build a view-only enum against.
///
/// It is only ever asked to resolve a payload's user type, and a view-inferred
/// payload has none — the inference answers scalars and `TyAny`. So there is
/// nothing for it to carry and no reason to make one that does.
fn empty_def() -> @statedef.StateDef {
  {
    source_name: "",
    component: "",
    fields: [],
    properties: [],
    receive: [],
    intent: [],
    express_message: [],
    express_intent: [],
    implements: [],
    protocols: [],
    protocol_imports: [],
    property_bindings: [],
    view_bindings: [],
    provide_bindings: [],
    lookup_bindings: [],
    types: [],
    provide: [],
    lookup: [],
    rules: [],
    wheres: [],
    doc: None,
  }
}

///|
/// The same enum for a file that declares no schema.
///
/// Every case comes from a view call site, so there is nothing to merge and no
/// user type a payload could name — which is why an empty `StateDef` is enough
/// to build it with, and why this is a call rather than a second emitter.
fn emit_view_only_msgs(
  t : String,
  surface : Surface,
  answered_inputs : Array[String],
  out : StringBuilder,
) -> Unit raise GenError {
  emit_bucket_enum(
    t,
    "Msg",
    "Receive",
    surface.inputs.map(msg_of_sig),
    empty_def(),
    answered_inputs,
    out,
  )
}

///|
/// Where a bucket's names come from, as the enum's own doc comment.
///
/// The two answer differently and it is worth saying which: an `intent` is
/// raised by component code and never written in a view, so the schema is the
/// only place it can be declared; a message is written in both, and the enum
/// is the union with the schema winning where they overlap.
fn origin_note(suffix : String) -> String {
  if suffix == "Msg" {
    "/// Every addressed name: the `message` variant the state block declares,\n" +
    "/// plus every bare `@on` handler the views write. One bucket holds them\n" +
    "/// however they were sent, so one type covers it — where the two overlap\n" +
    "/// the schema's declared payload wins, and a view whose call sites\n" +
    "/// disagree with it is a build error.\n"
  } else {
    "/// Declared as `variant intent` in the state block. These names are\n" +
    "/// raised by component code rather than written in a view, so the views\n" +
    "/// cannot type them — the schema is the only place they can be declared.\n"
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
  answered_inputs : Array[String],
  out : StringBuilder,
) -> Unit raise GenError {
  if msgs.is_empty() {
    return
  }
  // Guards against a schema whose case names collapse onto one variant.
  variants_for(msgs.map(m => m.name)) |> ignore
  let ty = "\{t}\{suffix}"
  // The word the doc comments use for one of these. `Msg` is the merged
  // bucket, and what a reader calls one is a message.
  let lower = if suffix == "Msg" { "message" } else { suffix.to_lower() }
  out.write_string(
    "///|\n" +
    "/// The \{dispatch_arm} arm of @component.Dispatch, decoded.\n" +
    "///\n" +
    "\{origin_note(suffix)}" +
    "\{answered_note(answered_inputs)}" +
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
    if m.variadic {
      // Any number, of shapes the call sites did not agree on. The raw list,
      // which is the honest answer and the one the arm can still read.
      out.write_string("  \{m.variant}(Array[@tutuca.Value])\n")
    } else if m.payload.is_empty() {
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
  for m in msgs {
    emit_payload_decoder(ty, t, suffix, m, def, out)
  }
  out.write_string(
    "///|\n" +
    "/// Decode a \{dispatch_arm} dispatch. None for any other bucket.\n" +
    "///\n" +
    "/// A payload that does not match falls into `Unknown` rather than being\n" +
    "/// coerced: an `s32` handler handed 2.5 has been sent the wrong thing,\n" +
    "/// and silently truncating it would hide that.\n" +
    "///\n" +
    "/// It is also REPORTED. `Unknown` answers two different questions —\n" +
    "/// nobody declares this name, and this name is declared here and was\n" +
    "/// handed the wrong shape — and the second one is a bug in the sender\n" +
    "/// that used to be indistinguishable from silence. Every arm below that\n" +
    "/// can fail on a DECLARED name says so through `@tutuca.bad_payload`,\n" +
    "/// which costs nothing unless a host is listening.\n" +
    "pub fn \{ty}::from_dispatch(d : @component.Dispatch) -> \{ty}? {\n" +
    "  guard d is \{dispatch_arm}(name, args) else { return None }\n" +
    "  Some(\n" +
    "    match (name, args) {\n",
  )
  for m in msgs {
    emit_decode_arm(t, suffix, m, def, out)
  }
  out.write_string("      _ => {\n")
  emit_bad_payload_report(msgs, out)
  out.write_string("        Unknown(name, args)\n      }\n    },\n  )\n}\n\n")
  // -- raise ----------------------------------------------------------------
  emit_raise(ty, suffix, msgs, def, out)
}

///|
/// The decoder for one case whose payload the pattern cannot read.
///
/// Nothing for a case that needs none — a payload of scalars, `Any` and slots
/// is read by the arm itself, which keeps the integer width guards where they
/// can be read beside the pattern they qualify.
fn emit_payload_decoder(
  ty : String,
  t : String,
  suffix : String,
  m : @statedef.MsgDef,
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit {
  if m.payload.is_empty() || m.payload.iter().all(payload_is_patternable) {
    return
  }
  let name = payload_decoder_name(t, suffix, m)
  out.write_string(
    "///|\n" +
    "/// `\{m.source_name}`'s arguments, decoded at the declared types.\n" +
    "///\n" +
    "/// The same `dec_stmts` the state codec is written from, so a payload and\n" +
    "/// a field of the same declared type are read by one rule. `None` is a\n" +
    "/// mismatch anywhere in the shape, however deep.\n" +
    "fn \{name}(args : Array[@tutuca.Value]) -> \{ty}? {\n" +
    "  guard args.length() == \{m.payload.length()} else { return None }\n",
  )
  for i, p in m.payload {
    out.write_string(dec_stmts(def, p, "args.get(\{i})", "a\{i}", "\{i}", 1))
  }
  let binds = m.payload.mapi((i, _) => "a\{i}").join(", ")
  out.write_string("  Some(\{m.variant}(\{binds}))\n}\n\n")
}

///|
/// The `_` arm's report: a DECLARED name that reached the fallback was handed
/// arguments no arm could read.
///
/// A name nothing declares reaches the same arm and says nothing, because
/// there is nothing to say — an unaddressed message is a message, not a
/// mistake.
fn emit_bad_payload_report(
  msgs : Array[@statedef.MsgDef],
  out : StringBuilder,
) -> Unit {
  out.write_string("        match name {\n")
  for m in msgs {
    // A variadic name cannot reach here: its arm matches on the name alone,
    // so nothing about its arguments can be wrong.
    if m.variadic {
      continue
    }
    out.write_string(
      "          \{quote(m.name)} =>\n" +
      "            @tutuca.bad_payload(name, \{quote(payload_source(m))}, args)\n",
    )
  }
  out.write_string("          _ => ()\n        }\n")
}

///|
/// One decode arm: the argument patterns, plus a guard for anything the
/// pattern alone cannot express.
fn emit_decode_arm(
  t : String,
  suffix : String,
  m : @statedef.MsgDef,
  def : @statedef.StateDef,
  out : StringBuilder,
) -> Unit {
  if m.variadic {
    // Any arguments at all, handed over as they arrived. Nothing can be wrong
    // with the shape, because nothing said what the shape should be.
    out.write_string("      (\{quote(m.name)}, _) => \{m.variant}(args)\n")
    return
  }
  if m.payload.is_empty() {
    out.write_string("      (\{quote(m.name)}, []) => \{m.variant}\n")
    return
  }
  // A shape the pattern cannot read goes through the generated decoder, and
  // the arm matches the NAME alone — arity included, so a call with the wrong
  // number of arguments is reported here rather than falling to `_`.
  if !m.payload.iter().all(payload_is_patternable) {
    let dec = payload_decoder_name(t, suffix, m)
    out.write_string(
      "      (\{quote(m.name)}, _) =>\n" +
      "        match \{dec}(args) {\n" +
      "          Some(v) => v\n" +
      "          None => {\n" +
      "            @tutuca.bad_payload(name, \{quote(payload_source(m))}, args)\n" +
      "            Unknown(name, args)\n" +
      "          }\n" +
      "        }\n",
    )
    return
  }
  let pats : Array[String] = []
  let binds : Array[String] = []
  let guards : Array[String] = []
  for i, p in m.payload {
    let a = "a\{i}"
    match p {
      TyInt(width~, signed~) => {
        pats.push("Num(\{a})")
        binds.push("\{a}.to_int()")
        // Integrality first, then range: a Double is the only numeric shape
        // a Value has, so both have to be checked here or not at all.
        guards.push("\{a}.to_int().to_double() == \{a}")
        let (lo, hi) = int_range(width, signed)
        guards.push("\{a} >= \{lo}.0")
        guards.push("\{a} <= \{hi}.0")
      }
      TyFloat => {
        pats.push("Num(\{a})")
        binds.push(a)
      }
      TyText => {
        pats.push("Str(\{a})")
        binds.push(a)
      }
      TyBool => {
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
    if m.variadic {
      out.write_string("    \{m.variant}(args) => (\{quote(m.name)}, args)\n")
    } else if m.payload.is_empty() {
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
    "Msg" =>
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
///
/// `enc_expr` and nothing local, so the raise side and the state codec cannot
/// disagree about a set or a nested record — the same reason `enc_expr` itself
/// defers to `statedef`.
fn to_value_expr(
  ty : @tutuca.Ty,
  binder : String,
  def : @statedef.StateDef,
) -> String {
  enc_expr(def, ty, binder)
}

///|
/// The MoonBit type one message payload carries.
///
/// The DECLARED type, whatever it is. This is the ONE place that decides,
/// because three sites have to agree — the enum variant, what `from_dispatch`
/// binds, and the expression `to_dispatch` writes — and a disagreement here
/// emits a module that does not compile.
///
/// This used to answer `@tutuca.Value` for everything but a scalar, and the
/// reason it no longer does is worth keeping: the objection was that a
/// dispatch payload ARRIVES as `Array[@tutuca.Value]`, so typing a payload as
/// `Array[String]` would mean converting, and the only converter to hand was a
/// JSON round trip. That is no longer true — `dec_stmts` and `to_value_src`
/// are the state codec's own halves, and a payload is the same shape a field
/// is. So the payload is decoded at the boundary exactly as a field is, and a
/// handler reads a typed value instead of destructuring a Value by hand.
///
/// `Any` and a component slot stay `@tutuca.Value`, because that IS their
/// declared type — nothing was erased and nothing is decoded.
fn msg_payload_ty(def : @statedef.StateDef, ty : @tutuca.Ty) -> String {
  def.moonbit_ty(ty)
}

///|
/// Whether a payload of this type can be read by the decode's PATTERN alone.
///
/// A scalar can — with a guard for an integer's width, which is the one range
/// a pattern cannot state — and `Any` and a slot can, trivially, because the
/// pattern binds the Value they already are. Everything else needs the codec,
/// and a case carrying one gets a decoder function of its own.
fn payload_is_patternable(ty : @tutuca.Ty) -> Bool {
  match ty {
    TyInt(..)
    | TyFloat
    | TyText
    | TyBool
    | TyAny
    | TyComp(_)
    | TyCompProtocols(_) => true
    _ => false
  }
}

///|
/// The declared payload, in the schema's own spelling, for a refusal to quote.
///
/// Baked in at generation time because nothing at runtime can reconstruct it:
/// the arguments that arrive are the ones that did NOT fit.
fn payload_source(m : @statedef.MsgDef) -> String {
  m.payload.map(p => p.show_source()).join(", ")
}

///|
/// The decoder function for one case's arguments: `Some(variant)` or `None`.
///
/// A function and not an inline arm because `dec_stmts` writes STATEMENTS that
/// `return None` on a mismatch, which is the same shape the state codec's
/// decode has and the same shape a nested list needs. An arm of a `match`
/// expression has nowhere to return to.
fn payload_decoder_name(
  t : String,
  suffix : String,
  m : @statedef.MsgDef,
) -> String {
  "\{value_prefix(t)}_\{suffix.to_lower()}_\{value_prefix(m.variant)}_of_args"
}
