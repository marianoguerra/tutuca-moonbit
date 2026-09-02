// Val evaluation and Value runtime semantics (eval side +
// PREDICATES table + immutable `is`). Implements the declares in spec.mbt.

///|
/// Structural equality over our Value shapes. NaN equals
/// NaN (Object.is); Fn values compare by reference.
///
/// The identity fast path is not just an optimization of the common case: the
/// runtime shares structure aggressively (copy-on-write spines, the value
/// stash restoring Obj/Fn by reference), so most comparisons of a rebuilt
/// tree against its predecessor meet the SAME object a level or two down.
/// Answering those in O(1) is what keeps an equality check over a 1000-item
/// list proportional to what actually changed. It agrees with the arms below
/// everywhere, NaN included.
pub impl Eq for Value with fn equal(self, other) {
  if physical_equal(self, other) {
    return true
  }
  match (self, other) {
    (Null, Null) => true
    (Bool(a), Bool(b)) => a == b
    (Num(a), Num(b)) => a == b || (a != a && b != b)
    (Str(a), Str(b)) => a == b
    (List(a), List(b)) => {
      if a.length() != b.length() {
        return false
      }
      for i in 0..<a.length() {
        if !(a[i] == b[i]) {
          return false
        }
      }
      true
    }
    (Map(a), Map(b)) => {
      if a.length() != b.length() {
        return false
      }
      for k, v in a {
        match b.get(k) {
          Some(v2) => if !(v == v2) { return false }
          None => return false
        }
      }
      true
    }
    (Fn(a), Fn(b)) => physical_equal(a, b)
    (Obj(a), Obj(b)) => a.eq(b)
    _ => false
  }
}

///|
/// size_of: `.size` (immutable collections) or `.length` (string/array).
///
/// A custom collection answers too, through `size`. An
/// instance that is NOT a sequence still answers None, which is the honest
/// reading: a component has fields, not a size.
pub fn size_of(v : Value) -> Int? {
  match v {
    Str(s) => Some(s.length())
    List(a) => Some(a.length())
    Map(m) => Some(m.length())
    Obj(o) => o.size()
    _ => None
  }
}

///|
/// Truthiness for unsized values; sized values are truthy when non-empty.
fn pred_truthy(v : Value) -> Bool {
  match size_of(v) {
    Some(n) => n > 0
    None =>
      match v {
        Null => false
        Bool(b) => b
        Num(n) => n != 0.0 && n == n
        Fn(_) => true
        // Str/List/Map are sized and handled above.
        _ => true
      }
  }
}

///|
/// Truthiness: Null/false/0/NaN/"" are false; lists, maps and functions
/// are always true. The `truthy?` predicate differs on
/// purpose: it treats empty collections as falsy (see `pred_truthy`).
pub fn Value::is_truthy(self : Value) -> Bool {
  match self {
    Null => false
    Bool(b) => b
    Num(n) => n != 0.0 && n == n // 0 and NaN are falsy
    Str(s) => s != ""
    List(_) | Map(_) | Fn(_) | Obj(_) => true
  }
}

///|
/// `${v}` template-interpolation semantics. Approximations: List joins
/// elements with ","; Map and Fn render as opaque markers
/// ("[object Object]" / function source are not worth mirroring).
pub fn Value::to_display_string(self : Value) -> String {
  match self {
    Null => "null"
    Bool(b) => if b { "true" } else { "false" }
    Num(n) => num_source(n)
    Str(s) => s
    // Join semantics: null elements become "", the rest String()-coerce.
    List(items) => items.map(i => tpl_piece(i)).join(",")
    Map(_) => "[object]"
    Fn(_) => "[function]"
    Obj(o) => o.debug()
  }
}

///|
fn lit_value(lit : Lit) -> Value {
  match lit {
    LNull => Null
    LBool(b) => Bool(b)
    LNum(n) => Num(n)
    LStr(s) => Str(s)
  }
}

///|
/// Number formatting for `${n}` / toString: integral doubles print with
/// no fractional part.
fn num_source(n : Double) -> String {
  if n != n {
    return "NaN"
  }
  if n == n.floor() && n.abs() < 9.0e15 {
    n.to_int64().to_string()
  } else {
    n.to_string()
  }
}

///|
/// One template piece in StrTpl.eval's join: null turns
/// into "" and String()-coercion applies to the rest.
fn tpl_piece(v : Value) -> String {
  match v {
    Null => ""
    _ => v.to_display_string()
  }
}

///|
/// A handler nothing answers: warn and hand back `this` unchanged.
///
/// A view's `@when` / `@enrich-with` /
/// `@loop-with` names are generated into an enum the author matches
/// exhaustively, so a name NOBODY wired is a build error now. What is left is
/// the case the enum cannot rule out — an arm that answers `None`, meaning
/// "another bucket serves this", where no other bucket does. That is a real
/// mistake worth reporting rather than a shape the engine has to tolerate.
fn mk_404_handler(name : String) -> Value {
  Fn(args => {
    // The same silence `Path::update` reports for a dispatch, one layer out: a
    // name a view wrote and no bucket answers. There is no state in hand here —
    // a 404 is built where the name resolves, which is before anything is asked
    // of a component — so the record says `Null` rather than inventing one.
    if refusing() {
      refuse({
        code: NoHandler,
        asked: name,
        rule: "",
        sentence: "",
        state: Null,
        path: Path::new(),
      })
    } else {
      warn("handler not found \{Repr(name)}")
    }
    args.get(0).unwrap_or(Null)
  })
}

///|
/// Reading what is AT a place.
///
/// The root read differs by whether there are steps below it, and that is not
/// an accident: `.name` with nothing under it is a virtual MEMBER read, which a
/// declared getter may answer by computing; `.seq[...]` reaches the STORAGE,
/// because indexing into whatever a getter returned is not what was written.
fn read_place(place : Place, stack : &Stack) -> Value {
  // `.seq[.key]` is the one indexed shape a slot can spell, and it goes through
  // the shared item lookup — which is what makes a custom collection readable
  // here. Both halves read storage.
  if ERead(place~, span=place.span).as_seq_access() is Some((seq, key)) {
    return match stack.lookup_storage(key).as_key() {
      Some(k) => stack.lookup_storage(seq).item(k)
      None => Null
    }
  }
  let mut cur = match place.root {
    PState(name) =>
      if place.steps.is_empty() {
        stack.lookup_member(name)
      } else {
        stack.lookup_storage(name)
      }
    PBind(name) => stack.lookup_bind(name)
    // A parameter is a body's, and a body runs after the render stack rather
    // than on it. Nothing here has one to hand back.
    PParam(_) => Null
  }
  for step in place.steps {
    cur = match step {
      // Bindings hold maps (`@value`), component instances (iterating a seq of
      // components, e.g. `@text="@value.title"` on a seq of components), or
      // whatever @enrich-with set. A member read off anything else is Null
      // (get/property fallback).
      PField(prop) =>
        match cur {
          Map(m) => m.get(prop).unwrap_or(Null)
          Obj(o) => o.field(prop).unwrap_or(Null)
          _ => Null
        }
      PIndex(idx) =>
        match idx.eval(stack).as_key() {
          Some(k) => cur.item(k)
          None => Null
        }
    }
  }
  cur
}

///|
/// A chain folds LEFT into applications of the operator's own name.
///
/// The operator words ARE the builtin names (`and`, `is`, `<`, `implies`), so
/// there is no second table to keep in step. Arithmetic has no builtin and
/// therefore answers `Null` here, which is the same answer every unresolved
/// name gives — the slot vocabulary is what evaluates, and `+` was never part
/// of it (see `Rules::unlowerable`).
fn eval_chain(
  ops : Array[String],
  operands : Array[Expr],
  span : Span,
  stack : &Stack,
) -> Value {
  guard operands.get(0) is Some(first) else { return Null }
  let mut acc = first
  for i, op in ops {
    guard operands.get(i + 1) is Some(rhs) else { break }
    acc = EApp(name=op, args=[acc, rhs], span~)
  }
  acc.eval(stack)
}

///|
pub fn Val::eval(self : Val, stack : &Stack) -> Value {
  match self {
    ELit(lit~, ..) => lit_value(lit)
    // The one case that reads something outside the value language. The stack
    // decides what a segment means; this only says which segments were written.
    EEventPath(segments~, ..) => stack.lookup_event_path(segments)
    ETpl(parts~, ..) => {
      let buf = StringBuilder()
      for part in parts {
        match part {
          TText(text~, ..) => buf.write_string(text)
          TExpr(v) => buf.write_string(tpl_piece(v.eval(stack)))
        }
      }
      Str(buf.to_string())
    }
    // `and` / `or` before the table, and this is not an optimization. A
    // `Builtin`'s `apply` takes arguments that are ALREADY evaluated, so a row
    // cannot decline to look at its second one — and the compiled backend
    // emits `&&` / `||`, which does. Answering them here is what keeps
    // `and (truthy? .items) ($firstLabel)` from calling the compute on an
    // empty list in one backend and not the other.
    EApp(name="and", args~, ..) if args.length() == 2 =>
      Bool(args[0].eval(stack).is_truthy() && args[1].eval(stack).is_truthy())
    EApp(name="or", args~, ..) if args.length() == 2 =>
      Bool(args[0].eval(stack).is_truthy() || args[1].eval(stack).is_truthy())
    // The parser only builds an `App` whose name resolves and whose argument
    // count matches, so the lookup here cannot fail on anything it produced.
    // It can still miss for an `App` built by hand or decoded from an IR
    // module written by an older generator, and `Null` is the honest answer
    // there — the same one an unresolved name gives everywhere else.
    EApp(name~, args~, ..) =>
      match builtin(name) {
        Some(b) if b.arity == args.length() =>
          (b.apply)(args.map(a => a.eval(stack)))
        _ => Null
      }
    EName(name~, ..) => stack.lookup_bare(name)
    // An Uppercase name parses (a handler arg may be written as one, and the
    // linter reads them) but resolves to nothing: a type is not a Value, so
    // there is nothing for a stack to hand back.
    ETypeName(..) => Null
    EDyn(name~, ..) => stack.lookup_dynamic(name)
    // `$name` in a value slot: the stack invokes and returns the result.
    EMethod(name~, ..) => stack.lookup_method(name)
    ERead(place~, ..) => read_place(place, stack)
    EChain(ops~, operands~, span~, ..) => eval_chain(ops, operands, span, stack)
    EUnary(op~, operand~, ..) =>
      match op {
        UNot => Bool(!operand.eval(stack).is_truthy())
        // The one arithmetic the slot vocabulary can do, and only because it
        // needs no builtin: negating a number is a fact about the number.
        UNeg =>
          match operand.eval(stack) {
            Num(n) => Num(-n)
            _ => Null
          }
      }
    EIf(cond~, then_~, else_~, ..) =>
      if cond.eval(stack).is_truthy() {
        then_.eval(stack)
      } else {
        else_.eval(stack)
      }
    // The three forms a VALUE position refuses at parse time (`Position`), and
    // therefore three that can only be reached by an expression built by hand
    // or decoded from an older IR. `Null` with a word, rather than a silent
    // hole: a `^name` outside a macro frame and a `&place` outside `sendAt`
    // are mistakes worth hearing about.
    EMacroVar(name~, ..) => {
      warn("`^\{name}` has no macro frame to resolve against here")
      Null
    }
    EConfigVar(name~, ..) => {
      warn("`$$\{name}` was not substituted before this was evaluated")
      Null
    }
    ERef(place~, ..) => {
      warn("`&\{place.to_source()}` names a position, and this is a value")
      Null
    }
  }
}

///|
/// Evaluate in a HANDLER position: `@on`'s name, and the three render-time
/// directives' (`@when`, `@enrich-with`, `@loop-with`).
///
/// A separate entry rather than a case on the value, which is what the retired
/// `HandlerNamespace` was: the same bare name means "a parameter" in a body and
/// "the thing to run" here, and which one it means is a fact about the position
/// it was written in. So the position asks, and the name carries nothing.
pub fn Val::eval_as_handler(self : Val, stack : &Stack) -> Value {
  match self {
    // The raw function, for the dispatch machinery to call with event args.
    EMethod(name~, ..) => stack.lookup_storage(name)
    EName(name~, ..) =>
      match stack.lookup_trigger(name) {
        Null => mk_404_handler(name)
        handler => handler
      }
    _ => self.eval(stack)
  }
}

///|
pub fn Val::to_path_item(self : Val) -> Step? {
  if self.as_field() is Some(name) {
    return Some(FieldStep(name))
  }
  if self.as_seq_access() is Some((seq, key)) {
    return Some(SeqAccessStep(seq_field=seq, key_field=key))
  }
  None
}

///|
pub fn Val::is_literal(self : Val) -> Bool {
  match self {
    ELit(..) => true
    // Every part a plain constant, none bound from a macro variable (the
    // macro placeholder is real in the body even when it resolved constant).
    ETpl(parts~, ..) =>
      parts
      .iter()
      .all(p => {
        match p {
          TText(from_macro~, ..) => !from_macro
          // A null part is the hole a placeholder that did not parse leaves
          // (`tscript/parse.mbt`), and a template with a hole in it is not a
          // hand-written literal — which is what kept the old `None` part out
          // of this answer.
          TExpr(ELit(lit=LNull, ..)) => false
          TExpr(ELit(from_macro~, ..)) => !from_macro
          TExpr(_) => false
        }
      })
    _ => false
  }
}
