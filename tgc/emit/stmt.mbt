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
//
// Statements accumulate into an `Array[@wast.Node]` rather than into a text
// buffer. The shape is the same shape it was; what is gone is the indentation
// bookkeeping and the escaping, and what is new is that every node knows where
// in the card it came from.

///|
/// Bind a value to a fresh local and abandon the transition if it has none.
///
/// This pair — `let t = e` then `if t == null { return null }` — is the single
/// most repeated thing in the emitters, because it IS the two-nulls rule: a
/// runtime operation with no answer for its arguments returns null, and a
/// transition with no answer does not happen. Writing it once is the only
/// change; `tgc/1` wrote both lines at nineteen sites.
fn hold(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  value : @wast.Node,
) -> String {
  let t = ctx.temp()
  out.push(b.bind(t, value))
  // …unless the thing cannot answer nothing. The vocabulary says which: a
  // constructor's result is `tg_val` and an operation's is `tg_val?`, and that
  // difference IS the two-nulls rule written in the types. Checking anyway
  // emitted a branch that could not be taken after every literal in every card.
  if !never_null(value) {
    out.push(b.if_(b.is_null(b.var_(t)), [b.ret(Some(b.null_()))]))
  }
  t
}

///|
/// Whether a value is a call to a vocabulary function that cannot answer null.
fn never_null(value : @wast.Node) -> Bool {
  guard value.it is Call(callee, _) else { return false }
  guard callee.it is Var(name) else { return false }
  for f in @abi.vocab() {
    if f.name == name {
      return match f.results {
        [Nullable(_)] => false
        [_] => true
        _ => false
      }
    }
  }
  false
}

///|
fn emit_stmts(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  stmts : Array[@tscript.Stmt],
) -> Unit raise Refused {
  for s in stmts {
    emit_stmt(ctx, b, out, s)
  }
}

///|
fn emit_stmt(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  stmt : @tscript.Stmt,
) -> Unit raise Refused {
  match stmt {
    SAssign(place~, op~, value~, ..) =>
      emit_assign(ctx, b, out, place, op, value)
    SMethod(place~, call~, args~, ..) =>
      emit_method(ctx, b, out, place, call, args)
    SEffect(name~, args~, route~, ..) =>
      emit_effect(ctx, b, out, name, args, route)
    SIf(cond~, then_~, else_~, span~) => {
      let c = emit_expr(ctx, b, out, cond)
      // A condition with no answer abandons rather than being read as false.
      let cv = hold(ctx, b, out, c)
      let then_nodes : Array[@wast.Node] = []
      emit_stmts(ctx, b, then_nodes, then_)
      let cond_node = b.made(
        Bin(Ne, b.rt("tg_truthy", [b.var_(cv)]), b.int_(0)),
      )
      if else_.length() == 0 {
        out.push(at(b, span, b.if_(cond_node, then_nodes)))
      } else {
        let else_nodes : Array[@wast.Node] = []
        emit_stmts(ctx, b, else_nodes, else_)
        out.push(at(b, span, b.if_(cond_node, then_nodes, else_=else_nodes)))
      }
    }
    SNew(ty~, ..) => emit_new(ctx, b, out, ty)
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
fn emit_new(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  ty : @tscript.TyRef,
) -> Unit raise Refused {
  match @check.resolve_ty_ref(ctx.comp.def, ty) {
    Some(TyRecord(name)) => {
      guard ctx.comp.def.user_ty(name) is Some(u) && u.kind is URecord(fields) else {
        raise Refused(
          "`new \{name}` names a record this component does not declare",
        )
      }
      let parts : Array[@wast.Node] = []
      for f in fields {
        parts.push(b.rt("tg_entry_of", [b.str_(f.name), zero_node(b, f.ty)]))
      }
      out.push(b.set(b.var_("cur"), b.rt("tg_map", [b.entries_of(parts)])))
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
      out.push(b.set(b.var_("cur"), b.rt("tg_map", [b.entries_of([])])))
      ctx.cur = CurComp(name)
    }
    // A SIBLING is not a type of this component's, so the type resolver does
    // not know it — `state Swatch` beside `state Palette` is a second
    // component, and which names are components is a fact about the FILE.
    _ =>
      if ctx.comp.siblings.contains(ty.name) {
        out.push(b.set(b.var_("cur"), b.rt("tg_map", [b.entries_of([])])))
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
  b : B,
  out : Array[@wast.Node],
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
    let t = hold(ctx, b, out, emit_expr(ctx, b, out, value))
    out.push(
      b.set(
        b.var_("cur"),
        b.rt("with_member", [b.var_("cur"), b.str_(field), b.var_(t)]),
      ),
    )
    out.push(b.if_(b.is_null(b.var_("cur")), [b.ret(Some(b.null_()))]))
    return
  }
  // Writing a BINDING rather than a field: an enricher's whole job.
  if place.root is PBind(bname) && ctx.binds is Some(bind) {
    guard place.steps.length() == 0 else {
      raise Refused(
        "`@\{bname}` is a binding, and a binding has no path into it",
      )
    }
    guard op is ASet else {
      raise Refused("`@\{bname}` is written, not accumulated into")
    }
    let t = hold(ctx, b, out, emit_expr(ctx, b, out, value))
    out.push(
      b.set(
        b.var_(bind),
        b.rt("with_member", [b.var_(bind), b.str_(bname), b.var_(t)]),
      ),
    )
    out.push(b.if_(b.is_null(b.var_(bind)), [b.ret(Some(b.null_()))]))
    return
  }
  let slot = state_slot(ctx, place)
  let v = hold(ctx, b, out, emit_expr(ctx, b, out, value))

  // The current value of the PLACE, which `+=` needs and `=` does not.
  let combined = match op {
    ASet => b.var_(v)
    AAdd | ASub => {
      let current = read_place(ctx, b, out, place)
      let fname = if op is AAdd { "op_add" } else { "op_sub" }
      let t = hold(ctx, b, out, b.rt(fname, [current, b.var_(v)]))
      b.var_(t)
    }
  }
  // An `Int` field truncates AT ITS ASSIGNMENT SITES, which is where the
  // interpreter does it too and what the corpus pins.
  let stored = truncated(ctx, b, out, place, combined)
  write_place(ctx, b, out, place, slot, stored)
}

///|
/// Whether this place lands in an `Int` field, and the truncation if it does.
fn truncated(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  place : @tutuca.Place,
  value : @wast.Node,
) -> @wast.Node {
  guard place.root is PState(name) else { return value }
  // Only a whole field is known to be an Int; a step into one lands somewhere
  // the declared type of the FIELD does not describe.
  guard place.steps.length() == 0 else { return value }
  guard ctx.comp.def.field(name) is Some(f) else { return value }
  guard f.ty is TyInt(..) else { return value }
  b.var_(hold(ctx, b, out, b.rt("trunc", [value])))
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
    // `cur.rows.push x`. `cur` is a value being built, not a place with a slot,
    // and the write that matters (`cur.<name> = …`) never reaches here.
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
  b : B,
  out : Array[@wast.Node],
  place : @tutuca.Place,
) -> @wast.Node raise Refused {
  ignore(out)
  let mut acc = emit_root(ctx, b, out, place.root)
  for step in place.steps {
    acc = match step {
      PField(name) => b.rt("member", [acc, b.str_(name)])
      PIndex(key) => b.rt("item", [acc, emit_expr(ctx, b, out, key)])
    }
  }
  acc
}

///|
/// Write a value back through a path.
///
/// A path write is a read down and a rebuild up, because every collection here
/// is immutable: `.a[k].b = x` reads `.a`, reads `[k]`, rebuilds the record with
/// `b`, rebuilds the collection with `k`, and writes the field. The old contract
/// refused this shape outright; the cost of having it is this function, and the
/// reason it is affordable is that the collections already share what they do
/// not change.
fn write_place(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  place : @tutuca.Place,
  slot : Int,
  value : @wast.Node,
) -> Unit raise Refused {
  let cell = b.made(Index(b.var_("f"), b.int_(slot)))
  if place.steps.length() == 0 {
    out.push(b.set(cell, value))
    return
  }
  // Read every intermediate container, outermost first.
  let containers : Array[@wast.Node] = [cell]
  let keys : Array[(Bool, @wast.Node)] = []
  for i, step in place.steps {
    let holder = containers[i]
    match step {
      PField(name) => {
        keys.push((true, b.str_(name)))
        if i + 1 < place.steps.length() {
          containers.push(b.rt("member", [holder, b.str_(name)]))
        }
      }
      PIndex(key) => {
        let k = hold(ctx, b, out, emit_expr(ctx, b, out, key))
        keys.push((false, b.var_(k)))
        if i + 1 < place.steps.length() {
          containers.push(b.rt("item", [holder, b.var_(k)]))
        }
      }
    }
  }
  // Rebuild innermost first.
  let mut carried = value
  for i in 0..<keys.length() {
    let at_i = keys.length() - 1 - i
    let (is_member, key) = keys[at_i]
    let holder = containers[at_i]
    let fname = if is_member { "with_member" } else { "with_item" }
    carried = b.var_(hold(ctx, b, out, b.rt(fname, [holder, key, carried])))
  }
  out.push(b.set(b.made(Index(b.var_("f"), b.int_(slot))), carried))
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
  b : B,
  out : Array[@wast.Node],
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
  let parts : Array[@wast.Node] = [read_place(ctx, b, out, place)]
  for a in args {
    parts.push(b.var_(hold(ctx, b, out, emit_expr(ctx, b, out, a))))
  }
  let res = hold(ctx, b, out, b.rt(fname, parts))
  write_place(ctx, b, out, place, slot, b.var_(res))
}

///|
/// An effect.
///
/// Each is one `tut` import, so a card that sends imports `eff_send` and a card
/// that does not imports nothing — the module's import section is a true
/// statement about what it does, which is the property the whole format keeps.
fn emit_effect(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  name : String,
  args : Array[@tutuca.Expr],
  route : Array[@tutuca.Leg],
) -> Unit raise Refused {
  // Whether the first argument NAMES a question, which is what separates
  // `ask 'save' x` from `ask x` — one raises a named intent and the other hands
  // the running one on. `tscript` decides it, because the decision is the
  // language's rather than this backend's.
  let named_question = @tscript.ask_names_a_question(args)
  // Which argument, if any, NAMES the message rather than valuing one. It is a
  // slot of syntax, not an expression: `send flash` and `send Bus::notify`
  // write a name where a value would go, and reading either as a value refuses
  // the whole effect over a name the checker already resolved.
  let name_at = message_arg(name, ctx.kind, named_question)
  let vals : Array[@wast.Node] = []
  for i, a in args {
    // A `&.place` is an address, not a value. `sendAt` reifies its first
    // argument below; evaluating it here would refuse the whole effect.
    if name == "sendAt" && i == 0 {
      vals.push(b.rt("tg_null", []))
      continue
    }
    // The WIRE name, resolved the way `tscript/check` resolves it: an
    // `import protocol "example/Bus@1" as Bus` makes `Bus::notify` a local
    // spelling of a name the host knows by its id, and a card author writing
    // the id out by hand is the thing the alias exists to avoid.
    if name_at is Some(at_i) && i == at_i && a is EName(name=n, ..) {
      guard ctx.comp.def.operation_name(n) is Some(wire) else {
        raise Refused(
          "`\{n}` uses a protocol name this component did not import",
        )
      }
      vals.push(b.rt("tg_str", [b.str_(wire)]))
      continue
    }
    vals.push(b.var_(hold(ctx, b, out, emit_expr(ctx, b, out, a))))
  }
  let route_code = b.int_(route_of(route))
  match name {
    "drop" => out.push(b.rt("eff_drop", []))
    "fail" =>
      out.push(
        b.rt("eff_fail", [
          if vals.length() >= 1 {
            vals[0]
          } else {
            b.rt("tg_null", [])
          },
        ]),
      )
    "send" => {
      guard vals.length() >= 1 else {
        raise Refused("`send` needs a message name")
      }
      out.push(
        b.rt("eff_send", [b.rt("display", [vals[0]]), tail_vals(b, vals, 1)]),
      )
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
        out.push(
          b.rt("eff_answer", [
            if vals.length() >= 1 {
              vals[0]
            } else {
              b.rt("tg_null", [])
            },
          ]),
        )
      } else {
        guard vals.length() >= 1 else {
          raise Refused("a `reply` in a receive body names the reply")
        }
        out.push(
          b.rt("eff_reply", [b.rt("display", [vals[0]]), tail_vals(b, vals, 1)]),
        )
      }
    "ask" | "notify" =>
      // A BARE ask re-dispatches the question already in hand: the message that
      // arrived becomes the question, which is exactly what forwarding means.
      // An empty argument list is how the runtime says "the ones that arrived",
      // so it is empty rather than a copy of them — a copy would be the same
      // values under a claim that the sender re-stated them.
      if named_question {
        out.push(
          b.rt("eff_\{name}", [
            b.rt("display", [vals[0]]),
            tail_vals(b, vals, 1),
            route_code,
          ]),
        )
      } else {
        out.push(b.rt("eff_forward", [tail_vals(b, vals, 0), route_code]))
      }
    "forward" =>
      out.push(b.rt("eff_forward", [tail_vals(b, vals, 0), route_code]))
    "sendAt" => {
      guard args.length() >= 2 && args[0] is ERef(place~, ..) else {
        raise Refused("`sendAt` takes a place and then a message name")
      }
      // The place is REIFIED rather than read: `vals` above evaluated every
      // argument, and the first one is not a value.
      let path = emit_path(ctx, b, out, place)
      out.push(
        b.rt("eff_send_at", [
          path,
          b.rt("display", [vals[1]]),
          tail_vals(b, vals, 2),
        ]),
      )
    }
    _ => raise Refused("no effect called `\{name}`")
  }
}

///|
/// Which argument names the message, for the effects that name one.
///
/// The same table `tscript/check` keeps, and it has to be: a name this refuses
/// to resolve is a name the checker already passed, so the two disagreeing
/// would be a card that checks and does not compile.
///
/// `reply` is the one that depends on WHERE it is written — in a `receive` body
/// the replier names the reply, in an `answer` body the walk addresses it and
/// the argument is the value. A bare `ask` names nothing: the question is the
/// message that arrived.
fn message_arg(
  effect : String,
  kind : @tscript.DeclKind,
  named_question : Bool,
) -> Int? {
  match effect {
    "send" => Some(0)
    "sendAt" => Some(1)
    "reply" => if kind is DAnswer { None } else { Some(0) }
    "ask" | "notify" => if named_question { Some(0) } else { None }
    _ => None
  }
}

///|
/// The tail of an effect's arguments, as a `tg_vals`.
///
/// An array LITERAL now, where `tgc/1` allocated a local and wrote each slot on
/// its own line. The values are already held in locals, so nothing about the
/// evaluation order changes; what changes is that the array is one node.
fn tail_vals(b : B, vals : Array[@wast.Node], from : Int) -> @wast.Node {
  if vals.length() - from <= 0 {
    return b.rt("tg_no_args", [])
  }
  let items : Array[@wast.Node] = []
  for i in from..<vals.length() {
    items.push(vals[i])
  }
  b.vals_of(items)
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
/// on every dispatch", which is what makes it follow a moving selection, and the
/// host's path has no step that says so — `core.Step::SeqAccessStep` exists but
/// nothing carries it across this boundary. Freezing the key would be a
/// different path that looks like this one, so it is refused rather than
/// approximated.
fn emit_path(
  ctx : Ctx,
  b : B,
  out : Array[@wast.Node],
  place : @tutuca.Place,
) -> @wast.Node raise Refused {
  guard place.root is PState(root) else {
    raise Refused(
      "`sendAt` addresses this component's own subtree, so its place starts at a field",
    )
  }
  let steps : Array[@wast.Node] = []
  let mut pending : String? = Some(root)
  for step in place.steps {
    match step {
      PField(name) => {
        if pending is Some(f) {
          steps.push(b.rt("mk_step_field", [b.str_(f)]))
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
        let t = hold(ctx, b, out, emit_expr(ctx, b, out, key))
        steps.push(b.rt("mk_step_key", [b.str_(f), b.var_(t)]))
        pending = None
      }
    }
  }
  if pending is Some(f) {
    steps.push(b.rt("mk_step_field", [b.str_(f)]))
  }
  b.rt("tg_list", [b.vals_of(steps)])
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
