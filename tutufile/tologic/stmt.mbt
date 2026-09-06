// Statements, read into `@tscript.Stmt`.
//
// `binds` is the names this body has bound so far: an enricher's `tag = …`
// makes `tag` a BINDING, so a later line reading it reads the bind and not a
// free name. The map is the scope, and it grows as the body is read.

///|
/// The statements of a block.
pub fn read_stmts(
  groups : Array[@ast.Node],
  binds : Map[String, String],
) -> Array[@tscript.Stmt] raise @sh.ExError {
  let out = []
  for g in groups {
    if read_stmt(g, binds) is Some(s) {
      out.push(s)
    }
  }
  out
}

///|
/// An enricher's body: every line binds a name to a value.
pub fn read_binds(
  groups : Array[@ast.Node],
) -> Array[@tscript.Stmt] raise @sh.ExError {
  let binds : Map[String, String] = Map([])
  let out = []
  for g in groups {
    guard g.it is Group(parts) else { continue }
    let at = @sh.find_op(parts, ["="])
    guard at is Some(i) && parts[0].it is Id(name) else {
      raise @sh.ExError(
        message="an enricher binds names to values",
        help="write `<name> = <value>`",
        span=@sh.span_of(g),
      )
    }
    let span = @sh.span_of(g)
    let value = @sh.to_expr(@sh.read_ex(parts[i + 1:]), ctx(binds), span)
    out.push(
      @tscript.SAssign(
        place={ root: @tutuca.PBind(name), steps: [], span: sp(span), },
        op=@tscript.ASet,
        value~,
        span=sp(span),
      ),
    )
    binds[name] = name
  }
  out
}

///|
/// The scope a statement's expressions are read in.
fn ctx(binds : Map[String, String]) -> @sh.ExCtx {
  let with_ = Map([])
  for k, v in binds {
    with_[k] = v
  }
  @sh.ExCtx::in_body(with_)
}

///|
/// One statement, or None for a line that holds nothing.
fn read_stmt(
  group : @ast.Node,
  binds : Map[String, String],
) -> @tscript.Stmt? raise @sh.ExError {
  guard group.it is Group(parts) && parts.length() > 0 else { return None }
  let span = @sh.span_of(group)
  // An `if` STATEMENT takes one arm or two. One is the shape a statement often
  // has and a value never can: a conditional write with nothing to do
  // otherwise.
  if parts[0].it is Id("if") && parts[parts.length() - 1].it is Alts(arms) {
    guard arms.length() is (1 | 2) else {
      raise @sh.ExError(
        message="an `if` takes one arm or two, and this has \{arms.length()}",
        help="write `if <cond> | <then>`, or `if <cond> | <then> | <else>`",
        span~,
      )
    }
    let cond = @sh.to_expr(
      @sh.read_ex(parts[1:parts.length() - 1]),
      ctx(binds),
      span,
    )
    let then_ = arm(arms[0], binds)
    let else_ = if arms.length() == 2 { arm(arms[1], binds) } else { [] }
    return Some(@tscript.SIf(cond~, then_~, else_~, span=sp(span)))
  }
  match @sh.find_op(parts, [":=", "+=", "-=", "*=", "/="]) {
    Some(at) => {
      let op : @tscript.AssignOp = match parts[at].it {
        Op("+=") => @tscript.AAdd
        Op("-=") => @tscript.ASub
        _ => @tscript.ASet
      }
      // `*=` and `/=` have no operator of their own in the script language:
      // they are the write with the arithmetic done first, which is what the
      // block language spelled and what the runtime has.
      let place = place_of(
        @sh.to_expr(@sh.read_ex(parts[:at]), ctx(binds), span),
        span,
      )
      let value = @sh.to_expr(@sh.read_ex(parts[at + 1:]), ctx(binds), span)
      let value = match parts[at].it {
        Op("*=") | Op("/=") =>
          @tutuca.Expr::app(
            if parts[at].it is Op("*=") {
              "*"
            } else {
              "/"
            },
            [@tutuca.Expr::ERead(place~, span=sp(span)), value],
            span=sp(span),
          )
        _ => value
      }
      Some(@tscript.SAssign(place~, op~, value~, span=sp(span)))
    }
    None => Some(call_stmt(@sh.read_ex(parts[:]), binds, span))
  }
}

///|
fn arm(
  node : @ast.Node,
  binds : Map[String, String],
) -> Array[@tscript.Stmt] raise @sh.ExError {
  guard node.it is Block(gs) else { return [] }
  read_stmts(gs, binds)
}

///|
/// A statement that is a call: a collection operation on a place, or an effect.
fn call_stmt(
  ex : @sh.Ex,
  binds : Map[String, String],
  span : @report.Span,
) -> @tscript.Stmt raise @sh.ExError {
  // `drop` and `stop` take no arguments and are written bare.
  if ex is EName(word) && @tscript.effect_min_arity(word) is Some(_) {
    return @tscript.SEffect(name=word, args=[], route=[], span=sp(span))
  }
  guard ex is ECall(callee, args) else {
    raise @sh.ExError(
      message="a statement is a write, a collection operation or an effect",
      help="a bare value does nothing — write `it.x := <value>` to keep it",
      span~,
    )
  }
  let pos = @sh.positional_args(args)
  match callee {
    // An effect: `send("flash", it.msg)`, `ask("save", ~route: lex)`.
    EName(verb) => {
      guard @tscript.effect_min_arity(verb) is Some(_) else {
        raise @sh.ExError(
          message="`\{verb}` is not an effect",
          help="the effects are `send`, `ask`, `notify`, `reply`, `fail`, `forward` and `drop`",
          span~,
        )
      }
      let out = []
      for a in pos {
        out.push(@sh.to_expr(a, ctx(binds), span))
      }
      let (verb, out) = match kw(args, "to") {
        // `send("flash", ~to: it.status)` is the addressed send, whose first
        // argument is the PLACE in the block language.
        Some(place) => {
          let head = [@sh.to_expr(place, ctx(binds), span)]
          for a in out {
            head.push(a)
          }
          ("sendAt", head)
        }
        None => (verb, out)
      }
      @tscript.SEffect(name=verb, args=out, route=route_of(args), span=sp(span))
    }
    // A collection operation: `it.items.push(v)`.
    EMember(recv, op) => {
      let place = place_of(@sh.to_expr(recv, ctx(binds), span), span)
      let out = []
      for a in pos {
        out.push(@sh.to_expr(a, ctx(binds), span))
      }
      @tscript.SMethod(place~, call=op, args=out, span=sp(span))
    }
    _ =>
      raise @sh.ExError(
        message="only a name or a place can be called as a statement",
        help="write `send(…)`, `ask(…)`, or `it.<field>.<operation>(…)`",
        span~,
      )
  }
}

///|
/// A `~name:` argument of a call, if it has one.
fn kw(args : Array[@sh.Arg], name : String) -> @sh.Ex? {
  for a in args {
    if a is AKw(k, v) && k == name {
      return Some(v)
    }
  }
  None
}

///|
/// `~route: lex` / `~route: [lex, dyn]` — the legs, in the order written.
fn route_of(args : Array[@sh.Arg]) -> Array[@tutuca.Leg] raise @sh.ExError {
  let out = []
  match kw(args, "route") {
    Some(EName(one)) => out.push(leg(one))
    Some(EList(many)) =>
      for e in many {
        guard e is EName(n) else {
          raise @sh.ExError(
            message="a route is a list of legs",
            help="write `~route: [lex, dyn]`",
            span=@report.Span::at(0),
          )
        }
        out.push(leg(n))
      }
    Some(_) =>
      raise @sh.ExError(
        message="a route is a leg or a list of legs",
        help="the legs are `dyn` and `lex`",
        span=@report.Span::at(0),
      )
    None => ()
  }
  out
}

///|
fn leg(word : String) -> @tutuca.Leg raise @sh.ExError {
  match word {
    "dyn" => Dyn
    "lex" => Lex
    _ =>
      raise @sh.ExError(
        message="`\{word}` is not a route leg",
        help="the legs are `dyn` and `lex`",
        span=@report.Span::at(0),
      )
  }
}

///|
/// The place an expression names, for the statements that write one.
fn place_of(
  e : @tutuca.Expr,
  span : @report.Span,
) -> @tutuca.Place raise @sh.ExError {
  guard e is ERead(place~, ..) else {
    raise @sh.ExError(
      message="this is not a place",
      help="a write names `it.<field>`, or a binding an enricher put in scope",
      span~,
    )
  }
  place
}
