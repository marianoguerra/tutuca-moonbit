// Expressions.
//
// Every one of them compiles to a single Wax instruction that leaves a
// `&jv_value` — which is why there is no statement sink here and no temporaries
// to name: an argument list is `tc_args2(a, b)`, a conditional is an `if` in a
// value position, and the whole tree nests.
//
// What is not here is a type. `tscript/check` has already checked the body
// against the schema and reported what disagrees, so a generator that inferred
// types a second time would be a second checker with a second opinion. What
// runs instead is one dispatch on the value's own kind, in
// `runtime/runtime.wax`, which is what the language says a value means.

///|
/// What an expression is compiled AGAINST.
priv struct ECtx {
  g : Gen
  /// The local holding the state this expression reads `.field` from. A
  /// handler's body reads the SUCCESSOR (`t`), a `requires` reads the state as
  /// it arrived (`s`), and both are just a name here.
  state : String
  /// The declaration's parameters, by position in the incoming argument list.
  params : Map[String, Int]
  /// The render-time bindings that arrive as ARGUMENTS, by position.
  ///
  /// A handler is handed none. A declaration reached through the Alter
  /// namespace is handed the row: `@key`, `@value` and `@iter`, which
  /// `component/instance.mbt` passes positionally to a `@when` and an `enrich`
  /// alike — at different offsets, because an enricher is also handed the binds
  /// it is extending. Empty for everything else, which is what makes `@name`
  /// still a refusal in a transition.
  binds : Map[String, Int]
  /// The local holding the binds an `enrich` body WRITES, when there is one.
  ///
  /// `@tag = str @value` is an assignment to a binding rather than to state,
  /// and the map it writes into is what the declaration answers with. `None`
  /// for everything that is not an enricher, which is what makes `@tag = …` a
  /// refusal in a handler.
  bind_local : String?
  /// The local holding that list, a `&?pv_vector` of `&jv_value`.
  args : String
  /// The kind and name a refusal is reported against.
  kind : String
  name : String
  /// Set when the body reaches `@cur`, so the local it lives in is declared
  /// only for a body that has one. An unused local is a lint, and a lint in
  /// generated code is a thing nobody can act on.
  mut uses_target : Bool
  /// Set when a body writes `new <Component>`, so the transition declares the
  /// second local that says WHICH component the target's arguments are for.
  mut uses_child : Bool
}

///|
fn ECtx::bail(
  self : ECtx,
  reason : String,
  span : @tscript.Span,
) -> Unit raise Bail {
  self.g.refuse(self.kind, self.name, reason, span)
  raise Bail(reason)
}

///|
/// One expression, as an instruction leaving a cell pointer.
fn ECtx::expr(self : ECtx, e : @tscript.Expr) -> @abi.I raise Bail {
  match e {
    ELit(lit~, ..) =>
      match lit {
        LNull => call("tc_null", [])
        LBool(b) => call("tc_bool", [i32c(if b { 1 } else { 0 })])
        LNum(x) => call("tc_num", [fconst(self.g.pool, x)])
        LStr(s) => text_const(self.g.pool, s)
      }
    ETpl(parts~, ..) => {
      // `$'…'` is a fold of `concat`, left to right, starting from the empty
      // string — the same shape the interpreter builds and the same one the
      // views interpolate with.
      let mut acc = text_const(self.g.pool, "")
      for p in parts {
        acc = match p {
          TText(t) => call("tc_tpl_concat", [acc, text_const(self.g.pool, t)])
          TExpr(sub) => call("tc_tpl_concat", [acc, self.expr(sub)])
        }
      }
      acc
    }
    ERead(place~, span~) => self.read(place, span)
    EName(name~, span~) => {
      match self.params.get(name) {
        Some(i) => return call("tc_arg_at", [get(self.args), i32c(i)])
        None => ()
      }
      match self.g.callables.get(name) {
        Some(_) =>
          return call(callable_fn(self.g, name), [get(self.state), nullref()])
        None => ()
      }
      self.bail(
        "`" +
        name +
        "` is neither a parameter of this declaration nor a compute, pred or invariant this card declares",
        span,
      )
      call("tc_null", [])
    }
    EApp(name~, args~, span~) => self.apply(name, args, span)
    EUnary(op~, operand~, ..) =>
      match op {
        UNot => call("tc_not", [self.expr(operand)])
        UNeg => call("tc_neg", [self.expr(operand)])
      }
    EIf(cond~, then_~, else_~, ..) =>
      if_val(jv_, self.truthy(cond), [self.expr(then_)], [self.expr(else_)])
    EChain(family~, ops~, operands~, span~) =>
      self.chain(family, ops, operands, span)
    EMethod(name~, span~) => {
      self.bail(
        "`$" +
        name +
        "` is answered by the render stack, and a handler runs after one — call `" +
        name +
        "` bare instead",
        span,
      )
      call("tc_null", [])
    }
    // The handler-side twin of a view's `*name`. A compiled card DOES have a
    // scope to read now: the host resolves this component's declared lookups
    // before it enters the guest and `control.lookup` reads one of the
    // answers, which is the one import that answers rather than acting.
    //
    // A name the manifest declares no lookup for comes back nil, and the
    // checker has already said so — which is why there is nothing to bail on
    // here.
    EDyn(name~, ..) => {
      self.g.uses_lookup = true
      call("tc_lookup", [text_const_str(self.g.pool, name)])
    }
    // Both sigils are substituted into VIEW markup, and a card's block is
    // compiled once with no call site and no host around it. The checker
    // refuses them first; this is the same sentence where the code is emitted.
    EMacroVar(name~, span~) => {
      self.bail(
        "`^" +
        name +
        "` is a macro argument, and a block has no macro slots — read it in the view and pass it in",
        span,
      )
      call("tc_null", [])
    }
    EConfigVar(name~, span~) => {
      self.bail(
        "`$$" +
        name +
        "` is a value the host bound, and a block is compiled ahead of any host — read it in the view and pass it in",
        span,
      )
      call("tc_null", [])
    }
    ERef(span~, ..) => {
      self.bail(
        "`&.place` denotes a POSITION rather than a value, and `sendAt`'s first argument is the only place one can be written",
        span,
      )
      call("tc_null", [])
    }
  }
}

///|
/// The i32 condition an `if`, an `and` or a `requires` branches on.
fn ECtx::truthy(self : ECtx, e : @tscript.Expr) -> @abi.I raise Bail {
  ne(call("tc_truthy", [self.expr(e)]), i32c(0))
}

///|
/// Reading what is at a place.
fn ECtx::read(
  self : ECtx,
  place : @tscript.Place,
  span : @tscript.Span,
) -> @abi.I raise Bail {
  match place.root {
    PState(name) =>
      match self.g.index.get(name) {
        Some(_) => {
          // …but not INTO a child. See `refuse_into_child`.
          self.refuse_into_child(name, place.steps, span)
          // Down through the steps, one `tc_step` each. A step that addresses
          // nothing reads null and the rest read null off that, which is
          // `Path::lookup` answering None at the first unresolvable step.
          self.walk(
            call("tc_get", [get(self.state), text_const_str(self.g.pool, name)]),
            place.steps,
          )
        }
        None => {
          self.bail("this card's state declares no field `" + name + "`", span)
          call("tc_null", [])
        }
      }
    PParam(name) =>
      match self.params.get(name) {
        Some(i) =>
          self.walk(call("tc_arg_at", [get(self.args), i32c(i)]), place.steps)
        None => {
          self.bail(
            "`" + name + "` is not a parameter of this declaration",
            span,
          )
          call("tc_null", [])
        }
      }
    // `@cur` is the ONE binding a compiled handler owns: `new` writes it and
    // nothing else can. Reading it before a `new` has made one fails the
    // transition rather than reading null, which is `read_place`'s rule and
    // the reason the local is nullable.
    PBind(name) if name == @tscript.target_bind => {
      self.uses_target = true
      // A PENDING child is materialized HERE, at the first read, because that
      // is the last moment its arguments can still be added to and the first
      // moment they are all in. `new` builds nothing; it puts an empty
      // ordered map in the target and remembers which component the map is
      // arguments FOR, and `@cur.text = .draft` accumulates into it.
      //
      // Materializing rebinds the target to the TOKEN and clears the marker,
      // so pushing `@cur` twice pushes one child rather than making two.
      //
      // A card that writes no `new <Component>` emits none of this: the
      // marker local does not exist, and neither does the branch.
      let read = if self.uses_child {
        if_val(
          jv_,
          ges(get(child_local), i32c(0)),
          [
            set(
              target_local,
              call("tc_child_of", [get(child_local), get(target_local)]),
            ),
            set(child_local, i32c(-1)),
            call("tc_target", [get(target_local)]),
          ],
          [call("tc_target", [get(target_local)])],
        )
      } else {
        call("tc_target", [get(target_local)])
      }
      self.walk(read, place.steps)
    }
    // The row a `@when` filter or an enricher is called about. These DO arrive
    // at a compiled declaration — `component/instance.mbt` passes them
    // positionally through `call-method` — so the only thing that was ever
    // missing is knowing which position each one is at.
    PBind(name) if self.binds.get(name) is Some(i) =>
      self.walk(call("tc_arg_at", [get(self.args), i32c(i)]), place.steps)
    // Anything else an enricher can see it wrote, or was handed. A name nobody
    // bound reads null, which is what an unresolved binding reads as
    // everywhere else in a slot.
    PBind(name) if self.bind_local is Some(b) =>
      self.walk(
        call("tc_step_field", [get(b), text_const_str(self.g.pool, name)]),
        place.steps,
      )
    PBind(name) => {
      self.bail(
        "`@" +
        name +
        "` is a binding the render stack provides, and a compiled handler runs outside one",
        span,
      )
      call("tc_null", [])
    }
  }
}

///|
/// A value, then one `tc_step` per path step.
fn ECtx::walk(
  self : ECtx,
  root : @abi.I,
  steps : Array[@tscript.PathStep],
) -> @abi.I raise Bail {
  let mut acc = root
  for st in steps {
    acc = match st {
      // The two steps differ in what an absence MEANS, and it is the one place
      // a path can abandon a transition. `.a.b` on a value with no `b` reads
      // null; `.a[k]` with no `k` FAILS, because reading past the end of a list
      // is the case "failure is no change" exists for.
      PField(f) => call("tc_step_field", [acc, text_const_str(self.g.pool, f)])
      PIndex(e) => call("tc_step_index", [acc, self.expr(e)])
    }
  }
  acc
}

///|
/// A name applied to arguments: a reading builtin, or one of this card's own
/// `compute` / `pred` / `invariant` declarations.
fn ECtx::apply(
  self : ECtx,
  name : String,
  args : Array[@tscript.Expr],
  span : @tscript.Span,
) -> @abi.I raise Bail {
  match self.g.callables.get(name) {
    Some(_) => {
      let cells = []
      for a in args {
        cells.push(self.expr(a))
      }
      return call(callable_fn(self.g, name), [get(self.state), arg_list(cells)])
    }
    None => ()
  }
  let cells = []
  for a in args {
    cells.push(self.expr(a))
  }
  match (name, cells.length()) {
    // `min`, `max` and `clamp` are calls now rather than an `if` around a
    // spliced comparison. That was a real bug and not only a size: the
    // argument's instruction tree appeared in both the condition and a branch
    // — three times for `clamp` — so it was evaluated more than once, and only
    // purity kept the answer right.
    ("min", 2) => call("tc_min", [cells[0], cells[1]])
    ("max", 2) => call("tc_max", [cells[0], cells[1]])
    ("clamp", 3) => call("tc_clamp", [cells[0], cells[1], cells[2]])
    // Both read a string as well as a number, and neither has an answer for
    // anything else — `tc_num_cast` is the language's arm, including the "no
    // answer" that abandons the transition rather than reading null. Saying so is what
    // pulls `parse_num.wax` into the module; a card that never converts one
    // carries no parser.
    ("int", 1) => {
      self.g.uses_num = true
      call("tc_int", [cells[0]])
    }
    ("num", 1) => {
      self.g.uses_num = true
      call("tc_num_cast", [cells[0]])
    }
    ("str", 1) => call("tc_str", [cells[0]])
    // `truthy?` and `falsy?` are `pred_truthy`, NOT plain truthiness: the
    // predicates treat an empty collection as falsy and `if` does not. Both
    // exist because the difference is deliberate — `core/value_builtin.mbt`
    // says so, and the corpus catches getting it wrong.
    ("truthy?", 1) => call("tc_bool", [call("tc_pred_truthy", [cells[0]])])
    ("falsy?", 1) =>
      call("tc_bool", [eq(call("tc_pred_truthy", [cells[0]]), i32c(0))])
    ("null?", 1) => call("tc_bool", [call("tc_is_null", [cells[0]])])
    ("empty?", 1) => call("tc_empty", [cells[0]])
    ("len", 1) => call("tc_len", [cells[0]])
    ("has", 2) => call("tc_has", [cells[0], cells[1]])
    ("contains", 2) => call("tc_contains", [cells[0], cells[1]])
    ("lower", 1) => call("tc_lower_case", [cells[0]])
    ("upper", 1) => call("tc_upper_case", [cells[0]])
    ("trim", 1) => call("tc_trim", [cells[0]])
    _ => {
      self.bail(
        match @tscript.script_builtin(name) {
          Some(n) if n != cells.length() =>
            "`" +
            name +
            "` takes " +
            n.to_string() +
            " argument(s), and this call passes " +
            cells.length().to_string()
          Some(_) =>
            "`" +
            name +
            "` is a reading builtin this generator does not compile yet"
          None =>
            "`" +
            name +
            "` is not a builtin and not a compute, pred or invariant this card declares"
        },
        span,
      )
      call("tc_null", [])
    }
  }
}

///|
/// Two or more operands joined by operators of one family.
fn ECtx::chain(
  self : ECtx,
  family : @tscript.OpFamily,
  ops : Array[String],
  operands : Array[@tscript.Expr],
  span : @tscript.Span,
) -> @abi.I raise Bail {
  match family {
    FCompare => {
      let a = self.expr(operands[0])
      let b = self.expr(operands[1])
      match ops[0] {
        "is" => call("tc_bool", [call("tc_eq", [a, b])])
        "is not" => call("tc_bool", [eq(call("tc_eq", [a, b]), i32c(0))])
        "<" => call("tc_bool", [lts(call("tc_cmp", [a, b]), i32c(0))])
        "<=" => call("tc_bool", [les(call("tc_cmp", [a, b]), i32c(0))])
        ">" => call("tc_bool", [gts(call("tc_cmp", [a, b]), i32c(0))])
        ">=" => call("tc_bool", [ges(call("tc_cmp", [a, b]), i32c(0))])
        other => {
          self.bail("unknown comparison `" + other + "`", span)
          call("tc_null", [])
        }
      }
    }
    // `a implies b` is `(not a) or b`, and it is written out that way rather
    // than desugared into a chain so the short circuit is the same one.
    FImplies =>
      if_val(
        jv_,
        self.truthy(operands[0]),
        [call("tc_bool", [self.truthy(operands[1])])],
        [call("tc_bool", [i32c(1)])],
      )
    FLogic => {
      let mut acc = self.expr(operands[0])
      for i, op in ops {
        let rhs = operands[i + 1]
        acc = match op {
          "and" =>
            if_val(
              jv_,
              ne(call("tc_truthy", [acc]), i32c(0)),
              [call("tc_bool", [self.truthy(rhs)])],
              [call("tc_bool", [i32c(0)])],
            )
          _ =>
            if_val(
              jv_,
              ne(call("tc_truthy", [acc]), i32c(0)),
              [call("tc_bool", [i32c(1)])],
              [call("tc_bool", [self.truthy(rhs)])],
            )
        }
      }
      acc
    }
    FAdd | FMul => {
      let mut acc = self.expr(operands[0])
      for i, op in ops {
        let rhs = self.expr(operands[i + 1])
        acc = match op {
          "+" => call("tc_add", [acc, rhs])
          "-" => call("tc_sub", [acc, rhs])
          "*" => call("tc_mul", [acc, rhs])
          "/" => call("tc_div", [acc, rhs])
          "mod" => call("tc_mod", [acc, rhs])
          other => {
            self.bail("unknown operator `" + other + "`", span)
            call("tc_null", [])
          }
        }
      }
      acc
    }
  }
}

///|
/// The wasm function one of this card's callables compiles to.
///
/// Qualified by component when the file declares several — two of them can each
/// declare a `compute total`, and a module cannot hold two `cm_total`. For a
/// card with one component this is `cm_<name>`, exactly as it always was.
fn callable_fn(g : Gen, name : String) -> String {
  g.sym("cm_", name)
}

///|
/// A `list<value>` built out of already-compiled cells.
///
/// A `pv_push` fold rather than the `tc_args1..4` family, which caps a call at
/// four arguments and a `send` at four payload values. The fold
/// has no arity to run out of, and it is the same shape `const_value`'s `List`
/// arm already builds a literal with. `tc_args1..4` stay in the runtime: they
/// are what a hand-written escape reaches for, where a fold would be four lines.
fn arg_list(cells : Array[@abi.I]) -> @abi.I {
  // Null rather than an empty vector, because "no arguments" allocates nothing
  // and every reader of an argument list is already nullable.
  if cells.is_empty() {
    return nullref()
  }
  let mut acc = call("pv_empty", [])
  for c in cells {
    acc = call("pv_push", [acc, c])
  }
  acc
}
