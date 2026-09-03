// The admission table, asked of every form in every position.
//
// A table test rather than a case per rule, because what this file is for is
// the shape of the answer as a whole: which forms a slot admits used to be
// two tables in two functions that disagreed, and the way to notice that is to
// see all of it at once.

///|
/// Every position, in the order the snapshot lists them.
fn positions() -> Array[(String, @core.Position)] {
  [
    ("condition", PosCondition),
    ("event", PosEvent),
    ("trigger", PosTrigger),
    ("text", PosText),
    ("component", PosComponent),
    ("sequence", PosSequence),
    ("provide", PosProvide),
    ("field", PosField),
    ("event-arg", PosEventArg),
    ("macro-attr", PosMacroAttr),
    ("body", PosBody),
  ]
}

///|
/// One expression per form the AST has, named as an author would write it.
fn forms() -> Array[(String, @core.Expr)] {
  let field = @core.Expr::field("count")
  [
    ("'text'", @core.Expr::lit(LStr("text"))),
    (
      "$'a{.b}'",
      @core.Expr::tpl([
        TText(text="a", from_macro=false),
        TExpr(@core.Expr::field("b")),
      ]),
    ),
    ("$'literal'", @core.Expr::tpl([TText(text="literal", from_macro=false)])),
    (".count", field),
    ("@value", @core.Expr::bind("value")),
    ("@value.title", @core.Expr::bind_member("value", "title")),
    (".rows[.key]", @core.Expr::seq_access("rows", "key")),
    ("*theme", @core.Expr::dyn_("theme")),
    ("$total", @core.Expr::method_("total")),
    ("bare", @core.Expr::name("bare")),
    ("Uppercase", @core.Expr::type_name("Cell")),
    ("truthy? .count", @core.Expr::app("truthy?", [field])),
    ("e.value", @core.Expr::event_path(["value"])),
    (
      ".a.b",
      ERead(
        place={ root: PState("a"), steps: [PField("b")], span: @core.no_span, },
        span=@core.no_span,
      ),
    ),
    (
      "param.x",
      ERead(
        place={ root: PParam("p"), steps: [PField("x")], span: @core.no_span, },
        span=@core.no_span,
      ),
    ),
    (
      "&.rows[.k]",
      ERef(
        place={
          root: PState("rows"),
          steps: [PIndex(@core.Expr::field("k"))],
          span: @core.no_span,
        },
        span=@core.no_span,
      ),
    ),
    ("^macroVar", EMacroVar(name="title", span=@core.no_span)),
    ("host.configVar", EConfigVar(name="host", span=@core.no_span)),
    ("not .count", EUnary(op=UNot, operand=field, span=@core.no_span)),
    ("-.count", EUnary(op=UNeg, operand=field, span=@core.no_span)),
    (
      "a and b",
      EChain(
        family=FLogic,
        ops=["and"],
        operands=[field, field],
        span=@core.no_span,
      ),
    ),
    (
      "a + b",
      EChain(
        family=FAdd,
        ops=["+"],
        operands=[field, field],
        span=@core.no_span,
      ),
    ),
    (
      "if c { a } else { b }",
      EIf(cond=field, then_=field, else_=field, span=@core.no_span),
    ),
  ]
}

///|
/// Left-align `s` in `width` columns.
fn pad(s : String, width : Int) -> String {
  let b = StringBuilder()
  b.write_string(s)
  for _ in s.length()..<width {
    b.write_char(' ')
  }
  b.to_string()
}

///|
/// How one answer prints: `.` admitted, `-` not in this position's set, and
/// the sentence itself when there is one.
fn admission_cell(a : @core.Admission) -> String {
  match a {
    Admitted => "."
    NotHere => "-"
    Refused(_) => "!"
  }
}

///|
test "the admission table, every form against every position" {
  let out = StringBuilder()
  let heads = positions().map(p => p.0)
  out.write_string(pad("form", 22) + heads.join(" ") + "\n")
  for form in forms() {
    out.write_string(pad(form.0, 22))
    let cells = positions().map(p => admission_cell(form.1.admitted_in(p.1)))
    for i, cell in cells {
      out.write_string(pad(cell, heads[i].length()) + " ")
    }
    out.write_string("\n")
  }
  inspect(
    out.to_string(),
    content=(
      #|form                  condition event trigger text component sequence provide field event-arg macro-attr body
      #|'text'                .         -     -       .    -         -        -       .     .         .          .    
      #|$'a{.b}'              !         -     -       .    -         -        -       -     -         .          .    
      #|$'literal'            .         -     -       .    -         -        -       .     .         .          .    
      #|.count                .         -     -       .    .         .        .       .     .         .          .    
      #|@value                .         -     -       .    -         -        -       -     .         .          .    
      #|@value.title          .         -     -       .    -         -        -       -     .         .          .    
      #|.rows[.key]           -         -     -       -    .         -        .       .     -         .          .    
      #|*theme                .         -     -       .    .         .        -       -     .         .          .    
      #|$total                .         .     .       .    -         -        -       .     .         .          .    
      #|bare                  -         .     .       -    -         -        -       -     .         .          .    
      #|Uppercase             -         -     -       -    -         -        -       -     -         -          .    
      #|truthy? .count        .         -     -       -    -         -        -       -     -         -          .    
      #|e.value               -         -     -       -    -         -        -       -     .         -          .    
      #|.a.b                  !         !     !       !    !         !        !       !     !         !          .    
      #|param.x               !         !     !       !    !         !        !       !     !         !          .    
      #|&.rows[.k]            !         !     !       !    !         !        !       !     !         !          .    
      #|^macroVar             -         -     -       -    -         -        -       -     -         -          .    
      #|host.configVar        -         -     -       -    -         -        -       -     -         -          .    
      #|not .count            .         -     -       -    -         -        -       -     -         -          .    
      #|-.count               !         !     !       !    !         !        !       !     !         !          .    
      #|a and b               .         -     -       -    -         -        -       -     -         -          .    
      #|a + b                 !         !     !       !    !         !        !       !     !         !          .    
      #|if c { a } else { b } !         !     !       !    !         !        !       !     !         !          .    
      #|
    ),
  )
}

///|
test "a refusal carries the sentence that names what to write instead" {
  // The sentences are the contract: they are what an author reads, and each
  // names the thing to write in place of what was written.
  let said : Array[String] = []
  for form in forms() {
    if form.1.admitted_in(PosCondition) is Refused(why) {
      said.push(form.0 + " → " + why)
    }
  }
  inspect(
    said.join("\n"),
    content=(
      #|$'a{.b}' → a template is text, and a condition is not text
      #|.a.b → a slot reads one level, so `.a.b` has nothing to look in — render the child as a component, or name the read with a `compute`
      #|param.x → `p` is a parameter, and a slot has none
      #|&.rows[.k] → `&` names a position, and a slot reads values
      #|-.count → a slot has no arithmetic — name the value with a `compute`
      #|a + b → `+` is not a slot operator
      #|if c { a } else { b } → a slot has no `if` — `@show` / `@hide` ARE the choice, and a value that picks between two needs `@if.<attr>` with `@then` / `@else`
    ),
  )
}

///|
test "a body admits every form the grammar can build" {
  // The block language is what the AST was written for, so nothing is refused
  // there — the slot positions are the ones with a table.
  for form in forms() {
    assert_true(form.1.admitted_in(PosBody) is Admitted)
  }
}
