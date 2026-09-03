// The name-wiring checks: what a component published, what it asked for, and
// whether the two can find each other.
//
// Each case is a declaration that COMPILES — none of these stop a component
// from rendering — and is nevertheless wrong in a way only the scope can see.

///|
priv struct ChkState {
  n : Int
}

///|
impl @tutuca.Fields for ChkState with fn schema() {
  @tutuca.SchemaInfo::new(fingerprint="chk_state", fields=[
    @tutuca.FieldInfo::new("n", TyInt(width=32, signed=true)),
  ])
}

///|
impl @tutuca.Fields for ChkState with fn encode(s) {
  { "n": Num(s.n.to_double()) }
}

///|
impl @tutuca.Fields for ChkState with fn decode(f) {
  guard f.get("n") is Some(Num(v)) else { return None }
  Some({ n: v.to_int(), })
}

///|
fn chk_comp(
  name : String,
  provide? : Map[String, String] = Map([]),
  lookup? : Array[@component.LookupSpec] = [],
  view? : String = "<div></div>",
) -> @component.Component {
  @component.component(
    views={ "main": @anode.View::new("main", raw_view=view) },
    name~,
    initial=ChkState::{ n: 0, },
    provide~,
    lookup~,
  )
}

///|
/// The findings for one registered set, by code name.
fn chk_findings(
  comps : Array[@component.Component],
) -> Array[(String, String, String)] raise {
  let scope = @component.ComponentStack::new()
  scope.register_components(comps)
  scope.compile_all()
  scope
  .check_names()
  .map(f => {
    let level = match f.level {
      Error => "error"
      Warn => "warn"
      Hint => "hint"
    }
    let name = f.info.fold(init="", (acc, kv) => {
      if kv.0 == "name" {
        kv.1
      } else {
        acc
      }
    })
    (@lint.lint_code_name(f.code), level, name)
  })
}

///|
test "a provide that is not addressable is reported, not raised" {
  // `$doIt` is a method call: it has no path, so it cannot be the target a
  // `<x render="*bad">` resumes at. compile() drops it silently and
  // this is where that is said.
  let fs = chk_findings([
    chk_comp("Solo", provide={ "bad": "$doIt", "ok": ".n" }),
  ])
  assert_true(fs.contains(("PROVIDE_NOT_ADDRESSABLE", "error", "bad")))
  assert_false(fs.iter().any(f => f.2 == "ok"))
}

///|
test "a published type that is not \"self\" is reported" {
  // An uppercase name publishes a component, and `"self"` is the only thing
  // one can be — which is what makes a published type a component by
  // construction rather than by trusting an expression.
  let fs = chk_findings([
    chk_comp("Solo", provide={ "Cell": ".n", "Good": "self" }),
  ])
  assert_true(fs.contains(("PROVIDE_TYPE_BAD_SHAPE", "error", "Cell")))
  assert_false(fs.iter().any(f => f.2 == "Good"))
}

///|
test "two producers of one name are valid: render ancestry shadows nearest" {
  // The provider is selected from the live render stack, so two declarations
  // are not ambiguous. The innermost rendered provider wins.
  let fs = chk_findings([
    chk_comp("Left", provide={ "items": ".n" }),
    chk_comp("Right", provide={ "items": ".n" }),
  ])
  assert_false(fs.iter().any(f => f.2 == "items"))
}

///|
test "a lookup with no provider: error without a default, hint with one" {
  // Whether a provider is ABOVE the consumer when it renders is a runtime
  // fact. Whether one is REGISTERED at all is not, and that is where this
  // stops.
  let fs = chk_findings([
    chk_comp("Solo", lookup=[
      @component.lookup_name("orphan"),
      @component.lookup_or("themed", "'gray'"),
    ]),
  ])
  assert_true(fs.contains(("LOOKUP_NO_PROVIDER", "error", "orphan")))
  assert_true(fs.contains(("LOOKUP_NO_PROVIDER", "hint", "themed")))
}

///|
test "a lookup whose provider is registered is silent" {
  let fs = chk_findings([
    chk_comp("Producer", provide={ "items": ".n" }),
    chk_comp("Consumer", lookup=[@component.lookup_name("items")]),
  ])
  assert_false(fs.iter().any(f => f.0 == "LOOKUP_NO_PROVIDER"))
}

///|
test "an uppercase lookup naming no registered component is reported" {
  let fs = chk_findings([
    chk_comp("Cell"),
    chk_comp("Solo", lookup=[
      @component.lookup_name("Cell"),
      @component.lookup_name("Celll"),
    ]),
  ])
  assert_true(fs.contains(("UNKNOWN_COMPONENT_NAME", "error", "Celll")))
  assert_false(fs.iter().any(f => f.2 == "Cell"))
}

///|
test "a `$name` in an event position is refused for a view compiled at runtime" {
  // The generator refuses this while compiling a view FILE
  // (`METHOD_IN_EVENT`). A view that arrives at runtime — a macro this stack
  // expanded, a guest's manifest — never meets the generator, and the rule is
  // one rule: `@anode.NodeEvent::method_in_event`, read by both checkers.
  //
  // Refused because a handler name and a `$name` are the SAME dispatch: both
  // are pushed as a `Receive` of that string, so the sigil claims a
  // distinction that does not exist.
  let fs = chk_findings([
    chk_comp("Solo", view="<button @on.click=\"$inc\">go</button>"),
  ])
  assert_true(fs.contains(("METHOD_IN_EVENT", "error", "inc")))
  // A bare name in the same position is the spelling that works.
  let ok = chk_findings([
    chk_comp("Solo", view="<button @on.click=\"inc\">go</button>"),
  ])
  assert_false(ok.iter().any(f => f.0 == "METHOD_IN_EVENT"))
}
