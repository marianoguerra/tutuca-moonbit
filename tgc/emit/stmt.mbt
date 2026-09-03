// Statements.
//
// A transition works on `f`, a copy of the state's slot array, and answers it
// or null. Null is "the transition did not happen", and it is the answer to
// every operation that had none — which is why the checks are here, at the
// statement, rather than threaded through every operand.
//
// EFFECTS ARE NOT BUFFERED HERE. They are `tut` imports, and the host brackets
// the call: an effect performed before a statement that abandons is discarded
// with the transition. Putting the buffer host-side rather than guest-side is
// the same decision the old contract made about `control.*`, kept for the same
// reason — it is the host that knows when the call ended.

///|
fn emit_stmts(
  ctx : Ctx,
  src : Src,
  stmts : Array[@tscript.Stmt],
) -> Unit raise Refused {
  for s in stmts {
    emit_stmt(ctx, src, s)
  }
}

///|
fn emit_stmt(ctx : Ctx, src : Src, stmt : @tscript.Stmt) -> Unit raise Refused {
  match stmt {
    SAssign(place~, op~, value~, ..) => emit_assign(ctx, src, place, op, value)
    SMethod(place~, call~, args~, ..) =>
      emit_method(ctx, src, place, call, args)
    SEffect(name~, args~, route~, ..) =>
      emit_effect(ctx, src, name, args, route)
    SIf(cond~, then_~, else_~, ..) => {
      let c = emit_expr(ctx, src, cond)
      let cv = ctx.temp()
      src.line("let \{cv} = \{c};")
      // A condition with no answer abandons rather than being read as false.
      src.line("if \{cv} == null { return null; }")
      src.open("if tg_truthy(\{cv}) != 0 {")
      emit_stmts(ctx, src, then_)
      if else_.length() == 0 {
        src.close("}")
      } else {
        src.close("} else {")
        src.depth = src.depth + 1
        emit_stmts(ctx, src, else_)
        src.depth = src.depth - 1
        src.line("}")
      }
    }
    SNew(ty~, ..) => emit_new(ctx, src, ty)
  }
}

///|
/// `new T` — the one binding a handler owns.
///
/// Nothing is BUILT here. It opens an argument map and remembers which type it
/// is for; writes to `cur` accumulate into it; and a sibling component is made
/// at the first READ of `cur`. That is the last moment the arguments can still
/// change and the first moment they are all in.
///
/// The zero is resolved and built at COMPILE time — it is a property of the
/// declared type and the type is written in the source — so a `new` naming a
/// type the card does not declare is refused when it compiles rather than
/// abandoned when it runs.
fn emit_new(ctx : Ctx, src : Src, ty : @tscript.TyRef) -> Unit raise Refused {
  match @check.resolve_ty_ref(ctx.comp.def, ty) {
    Some(TyRecord(name)) => {
      guard ctx.comp.def.user_ty(name) is Some(u) && u.kind is URecord(fields) else {
        raise Refused(
          "`new \{name}` names a record this component does not declare",
        )
      }
      let parts = []
      for f in fields {
        parts.push("tg_entry_of(\{wax_str(f.name)}, \{zero_expr(f.ty)})")
      }
      let body = if parts.length() == 0 {
        "tg_map([tg_entries| null; 0])"
      } else {
        "tg_map([tg_entries| " + parts.join(", ") + "])"
      }
      src.line("cur = \{body};")
      ctx.cur = CurRecord
    }
    // A sibling starts EMPTY rather than at its zero: `<Sib>_make_fields` fills
    // each slot from the argument map or the declared zero, so filling them
    // here would be the same table written twice.
    Some(TyComp(Some(name))) => {
      guard ctx.comp.siblings.contains(name) else {
        raise Refused(
          "`new \{name}` names a component this card does not declare beside it",
        )
      }
      src.line("cur = tg_map([tg_entries| null; 0]);")
      ctx.cur = CurComp(name)
    }
    // A SIBLING is not a type of this component's, so the type resolver does
    // not know it — `state Swatch` beside `state Palette` is a second
    // component, and which names are components is a fact about the FILE.
    _ =>
      if ctx.comp.siblings.contains(ty.name) {
        src.line("cur = tg_map([tg_entries| null; 0]);")
        ctx.cur = CurComp(ty.name)
      } else {
        raise Refused(
          "`new \{ty.name}` names neither a record this component declares nor a " +
          "component declared beside it",
        )
      }
  }
}

///|
/// `.field = e`, `+=`, `-=`, and the same through a path.
fn emit_assign(
  ctx : Ctx,
  src : Src,
  place : @tutuca.Place,
  op : @tscript.AssignOp,
  value : @tutuca.Expr,
) -> Unit raise Refused {
  // Writing into `cur`: what a `new` opened, one member at a time.
  if place.root is PTarget {
    guard place.steps is [PField(field)] else {
      raise Refused("`cur` is written one member at a time: `cur.<name> = …`")
    }
    guard !(ctx.cur is CurNone) else {
      raise Refused(
        "`cur` has no `new` before it, so there is nothing to write into",
      )
    }
    guard op is ASet else {
      raise Refused("`cur.\{field}` is written, not accumulated into")
    }
    let rv = emit_expr(ctx, src, value)
    let t = ctx.temp()
    src.line("let \{t} = \{rv};")
    src.line("if \{t} == null { return null; }")
    src.line("cur = with_member(cur, \{wax_str(field)}, \{t});")
    src.line("if cur == null { return null; }")
    return
  }
  // Writing a BINDING rather than a field: an enricher's whole job.
  if place.root is PBind(bname) && ctx.binds is Some(b) {
    guard place.steps.length() == 0 else {
      raise Refused(
        "`@\{bname}` is a binding, and a binding has no path into it",
      )
    }
    guard op is ASet else {
      raise Refused("`@\{bname}` is written, not accumulated into")
    }
    let rv = emit_expr(ctx, src, value)
    let t = ctx.temp()
    src.line("let \{t} = \{rv};")
    src.line("if \{t} == null { return null; }")
    src.line("\{b} = with_member(\{b}, \{wax_str(bname)}, \{t});")
    src.line("if \{b} == null { return null; }")
    return
  }
  let slot = state_slot(ctx, place)
  let rhs = emit_expr(ctx, src, value)
  let v = ctx.temp()
  src.line("let \{v} = \{rhs};")
  src.line("if \{v} == null { return null; }")

  // The current value of the PLACE, which `+=` needs and `=` does not.
  let current = read_place(ctx, src, place)
  let combined = match op {
    ASet => v
    AAdd | ASub => {
      let t = ctx.temp()
      let fname = if op is AAdd { "op_add" } else { "op_sub" }
      src.line("let \{t} = \{fname}(\{current}, \{v});")
      src.line("if \{t} == null { return null; }")
      t
    }
  }
  // An `Int` field truncates AT ITS ASSIGNMENT SITES, which is where the
  // interpreter does it too and what the corpus pins.
  let stored = truncated(ctx, src, place, combined)
  write_place(ctx, src, place, slot, stored)
}

///|
/// Whether this place lands in an `Int` field, and the truncation if it does.
fn truncated(
  ctx : Ctx,
  src : Src,
  place : @tutuca.Place,
  value : String,
) -> String {
  guard place.root is PState(name) else { return value }
  // Only a whole field is known to be an Int; a step into one lands somewhere
  // the declared type of the FIELD does not describe.
  guard place.steps.length() == 0 else { return value }
  guard ctx.comp.def.field(name) is Some(f) else { return value }
  guard f.ty is TyInt(..) else { return value }
  let t = ctx.temp()
  src.line("let \{t} = trunc(\{value});")
  src.line("if \{t} == null { return null; }")
  t
}

///|
/// The slot a place ultimately writes.
fn state_slot(ctx : Ctx, place : @tutuca.Place) -> Int raise Refused {
  match place.root {
    PState(name) =>
      match ctx.comp.field_index(name) {
        Some(i) => i
        None =>
          raise Refused(
            "`.\{name}` is not a declared field of \{ctx.comp.name}",
          )
      }
    PParam(name) =>
      raise Refused("`\{name}` is a parameter, and a parameter is not a place")
    PBind(name) =>
      raise Refused(
        "`@\{name}` is a render binding, and a handler is handed no row",
      )
    // A whole-`cur` place, which only a collection method could ask for —
    // `cur.rows.push x`. `cur` is a value being built, not a place with a
    // slot, and the write that matters (`cur.<name> = …`) never reaches here.
    PTarget =>
      raise Refused(
        "`cur` is a value being built, and a collection inside one is written " +
        "before it is pushed rather than through it",
      )
  }
}

///|
fn read_place(
  ctx : Ctx,
  src : Src,
  place : @tutuca.Place,
) -> String raise Refused {
  let mut acc = emit_root(ctx, src, place.root)
  for step in place.steps {
    acc = match step {
      PField(name) => "member(\{acc}, \{wax_str(name)})"
      PIndex(key) => "item(\{acc}, \{emit_expr(ctx, src, key)})"
    }
  }
  acc
}

///|
/// Write a value back through a path.
///
/// A path write is a read down and a rebuild up, because every collection here
/// is immutable: `.a[k].b = x` reads `.a`, reads `[k]`, rebuilds the record with
/// `b`, rebuilds the collection with `k`, and writes the field. The old
/// contract refused this shape outright; the cost of having it is this
/// function, and the reason it is affordable is that the collections already
/// share what they do not change.
fn write_place(
  ctx : Ctx,
  src : Src,
  place : @tutuca.Place,
  slot : Int,
  value : String,
) -> Unit raise Refused {
  if place.steps.length() == 0 {
    src.line("f[\{slot}] = \{value};")
    return
  }
  // Read every intermediate container, outermost first.
  let containers = ["f[\{slot}]"]
  let keys = []
  for i, step in place.steps {
    let holder = containers[i]
    match step {
      PField(name) => {
        keys.push(("member", wax_str(name)))
        if i + 1 < place.steps.length() {
          containers.push("member(\{holder}, \{wax_str(name)})")
        }
      }
      PIndex(key) => {
        let k = ctx.temp()
        src.line("let \{k} = \{emit_expr(ctx, src, key)};")
        src.line("if \{k} == null { return null; }")
        keys.push(("item", k))
        if i + 1 < place.steps.length() {
          containers.push("item(\{holder}, \{k})")
        }
      }
    }
  }
  // Rebuild innermost first.
  let mut carried = value
  for i in 0..<keys.length() {
    let at = keys.length() - 1 - i
    let (kind, key) = keys[at]
    let holder = containers[at]
    let t = ctx.temp()
    let call = if kind == "member" {
      "with_member(\{holder}, \{key}, \{carried})"
    } else {
      "with_item(\{holder}, \{key}, \{carried})"
    }
    src.line("let \{t} = \{call};")
    src.line("if \{t} == null { return null; }")
    carried = t
  }
  src.line("f[\{slot}] = \{carried};")
}

///|
/// A collection mutator on a place.
///
/// The canonical seven. `tscript` parses four more spellings — `clear`,
/// `delete`, `set`, `removeAt` — that no backend has ever implemented, so there
/// is no behaviour here to leave out, and refusing them by name is more honest
/// than compiling something plausible.
fn emit_method(
  ctx : Ctx,
  src : Src,
  place : @tutuca.Place,
  call : String,
  args : Array[@tutuca.Expr],
) -> Unit raise Refused {
  let fname = match call {
    "push" => "coll_push"
    "insertAt" => "coll_insert_at"
    "setAt" => "coll_set_at"
    "deleteAt" => "coll_delete_at"
    "add" => "coll_add"
    "remove" => "coll_remove"
    "toggle" => "coll_toggle"
    "clear" | "delete" | "set" | "removeAt" =>
      raise Refused(
        "`\{call}` is parsed as a collection method and no backend has ever " +
        "implemented it, so there is no behaviour to compile",
      )
    _ => raise Refused("no collection method called `\{call}`")
  }
  let slot = state_slot(ctx, place)
  let current = read_place(ctx, src, place)
  let parts = [current]
  for a in args {
    let v = emit_expr(ctx, src, a)
    let t = ctx.temp()
    src.line("let \{t} = \{v};")
    src.line("if \{t} == null { return null; }")
    parts.push(t)
  }
  let out = ctx.temp()
  src.line("let \{out} = \{fname}(" + parts.join(", ") + ");")
  src.line("if \{out} == null { return null; }")
  write_place(ctx, src, place, slot, out)
}

///|
/// An effect.
///
/// Each is one `tut` import, so a card that sends imports `eff_send` and a card
/// that does not imports nothing — the module's import section is a true
/// statement about what it does, which is the property the whole format keeps.
fn emit_effect(
  ctx : Ctx,
  src : Src,
  name : String,
  args : Array[@tutuca.Expr],
  route : Array[@tutuca.Leg],
) -> Unit raise Refused {
  // Whether the first argument NAMES a question, which is what separates
  // `ask 'save' x` from `ask x` — one raises a named intent and the other hands
  // the running one on. `tscript` decides it, because the decision is the
  // language's rather than this backend's.
  let named_question = @tscript.ask_names_a_question(args)
  let vals = []
  for i, a in args {
    // A `&.place` is an address, not a value. `sendAt` reifies its first
    // argument below; evaluating it here would refuse the whole effect.
    if name == "sendAt" && i == 0 {
      vals.push("tg_null()")
      continue
    }
    let v = emit_expr(ctx, src, a)
    let t = ctx.temp()
    src.line("let \{t} = \{v};")
    src.line("if \{t} == null { return null; }")
    vals.push(t)
  }
  let route_code = route_of(route)
  match name {
    "drop" => src.line("eff_drop();")
    "fail" => {
      let v = if vals.length() >= 1 { vals[0] } else { "tg_null()" }
      src.line("eff_fail(\{v});")
    }
    "send" => {
      guard vals.length() >= 1 else {
        raise Refused("`send` needs a message name")
      }
      let rest = vals_array(src, ctx, vals, 1)
      src.line("eff_send(display(\{vals[0]}), \{rest});")
    }
    // ONE WORD, TWO OPERATIONS, and the body is what says which.
    //
    // In an `answer` body a `reply` is the WALK's answer and carries a value:
    // its raiser asked a question and declared arms for it, so the runtime
    // derives the name (`<name>Ok`). In a `receive` body the sender declared no
    // arms, so the replier names the reply and the sender handles it like any
    // other message. The corpus records both as `reply`, which is right — it is
    // one word in the language — and they are two runtime calls.
    "reply" =>
      if ctx.kind is DAnswer {
        let v = if vals.length() >= 1 { vals[0] } else { "tg_null()" }
        src.line("eff_answer(\{v});")
      } else {
        guard vals.length() >= 1 else {
          raise Refused("a `reply` in a receive body names the reply")
        }
        let rest = vals_array(src, ctx, vals, 1)
        src.line("eff_reply(display(\{vals[0]}), \{rest});")
      }
    "ask" | "notify" =>
      // A BARE ask re-dispatches the question already in hand: the message that
      // arrived becomes the question, which is exactly what forwarding means.
      // An empty argument list is how the runtime says "the ones that arrived",
      // so it is empty rather than a copy of them — a copy would be the same
      // values under a claim that the sender re-stated them.
      if named_question {
        let rest = vals_array(src, ctx, vals, 1)
        src.line("eff_\{name}(display(\{vals[0]}), \{rest}, \{route_code});")
      } else {
        let all = vals_array(src, ctx, vals, 0)
        src.line("eff_forward(\{all}, \{route_code});")
      }
    "forward" => {
      let rest = vals_array(src, ctx, vals, 0)
      src.line("eff_forward(\{rest}, \{route_code});")
    }
    "sendAt" => {
      guard args.length() >= 2 && args[0] is ERef(place~, ..) else {
        raise Refused("`sendAt` takes a place and then a message name")
      }
      // The place is REIFIED rather than read: `vals` above evaluated every
      // argument, and the first one is not a value.
      let path = emit_path(ctx, src, place)
      let name_v = vals[1]
      let rest = vals_array(src, ctx, vals, 2)
      src.line("eff_send_at(\{path}, display(\{name_v}), \{rest});")
    }
    _ => raise Refused("no effect called `\{name}`")
  }
}

///|
/// The tail of an effect's arguments, as a `tg_vals`.
fn vals_array(src : Src, ctx : Ctx, vals : Array[String], from : Int) -> String {
  let n = vals.length() - from
  if n <= 0 {
    return "tg_no_args()"
  }
  let a = ctx.temp()
  src.line("let \{a} = [tg_vals| null; \{n}];")
  for i in 0..<n {
    src.line("\{a}[\{i}] = \{vals[from + i]};")
  }
  a
}

///|
/// A route, as the one integer the host reads it back from.
///
/// Written RESOLVED — a bare `ask` is `dyn lex` — because the default route is
/// exactly the kind of thing two backends can agree to disagree about while
/// every case with an explicit route passes. `tscript/conformance` records it
/// resolved for the same reason.
fn route_of(route : Array[@tutuca.Leg]) -> Int {
  if route.length() == 0 {
    return ROUTE_DYN_LEX
  }
  if route.length() == 1 {
    return if route[0] is Dyn { ROUTE_DYN } else { ROUTE_LEX }
  }
  if route[0] is Dyn {
    ROUTE_DYN_LEX
  } else {
    ROUTE_LEX_DYN
  }
}

///|
const ROUTE_DYN : Int = 1

///|
const ROUTE_LEX : Int = 2

///|
const ROUTE_DYN_LEX : Int = 3

///|
const ROUTE_LEX_DYN : Int = 4

///|
/// A `&.place`, reified as the path a host walks.
///
/// The walk is done HERE, at compile time, and the corpus pins what it means. A
/// `PIndex` attaches to the field before it — `.a[k]` is one keyed step, not a
/// field step and an index — and a `PField` closes the pending one first.
///
/// A key READ FROM LIVE STATE is refused. `&.panes[.sel]` means "re-read `.sel`
/// on every dispatch", which is what makes it follow a moving selection, and
/// the host's path has no step that says so — `core.Step::SeqAccessStep` exists
/// but nothing carries it across this boundary. Freezing the key would be a
/// different path that looks like this one, so it is refused rather than
/// approximated.
fn emit_path(
  ctx : Ctx,
  src : Src,
  place : @tutuca.Place,
) -> String raise Refused {
  guard place.root is PState(root) else {
    raise Refused(
      "`sendAt` addresses this component's own subtree, so its place starts at a field",
    )
  }
  let steps = []
  let mut pending : String? = Some(root)
  for step in place.steps {
    match step {
      PField(name) => {
        if pending is Some(f) {
          steps.push("mk_step_field(\{wax_str(f)})")
        }
        pending = Some(name)
      }
      PIndex(key) => {
        guard pending is Some(f) else {
          raise Refused("`sendAt` cannot index the same field twice in a row")
        }
        guard !reads_state(key) else {
          raise Refused(
            "`sendAt` with a key read from live state means \"re-read it on every " +
            "dispatch\", and the host's path has no step that says so — a literal " +
            "or a parameter key compiles",
          )
        }
        let k = emit_expr(ctx, src, key)
        let t = ctx.temp()
        src.line("let \{t} = \{k};")
        src.line("if \{t} == null { return null; }")
        steps.push("mk_step_key(\{wax_str(f)}, \{t})")
        pending = None
      }
    }
  }
  if pending is Some(f) {
    steps.push("mk_step_field(\{wax_str(f)})")
  }
  let a = ctx.temp()
  src.line("let \{a} = [tg_vals| null; \{steps.length()}];")
  for i, e in steps {
    src.line("\{a}[\{i}] = \{e};")
  }
  "tg_list(\{a})"
}

///|
/// Whether an expression reads the component's own state.
fn reads_state(e : @tutuca.Expr) -> Bool {
  match e {
    ERead(place~, ..) | ERef(place~, ..) => place.root is PState(_)
    EApp(args~, ..) => args.iter().any(reads_state)
    EChain(operands~, ..) => operands.iter().any(reads_state)
    EUnary(operand~, ..) => reads_state(operand)
    EIf(cond~, then_~, else_~, ..) =>
      reads_state(cond) || reads_state(then_) || reads_state(else_)
    ETpl(parts~, ..) =>
      parts
      .iter()
      .any(p => {
        match p {
          TExpr(inner) => reads_state(inner)
          TText(..) => false
        }
      })
    _ => false
  }
}
