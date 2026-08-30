// A writable property draws what its BACKING FIELD may hold.
//
// The report this is from: `property { reading : String { get .view set .view } }`
// over `where view is one of ["main", "format"]` drew arbitrary strings, and
// the runtime declined every one of them — 16 of 40 steps spent proving the
// domain works, and the two values that exercise the component never drawn.

///|
fn plan_of(spec : String, source : @fuzz.Source) -> @fuzz.Plan {
  let comp = @component.Component::for_type(
    views={ "main": @anode.View::new("main", raw_view="<div></div>") },
    name="Widget",
    schema=@component.SchemaInfo::new(name="Widget", fingerprint="w", fields=[]),
    spec~,
  )
  @fuzz.Plan::of_component(comp, source~).unwrap()
}

///|
test "a property backed by a domained field draws inside the domain" {
  let plan = plan_of(
    (
      #|state Widget {
      #|  view : String
      #|  where view is one of ["main", "format"]
      #|  property { reading : String { get .view set .view } }
      #|}
    ),
    Properties,
  )
  let script = plan.script(seed=1, steps=40)
  assert_true(script.length() > 0)
  let mut inside = 0
  for a in script {
    match a {
      SetProperty("reading", Str(v)) =>
        if v == "main" || v == "format" {
          inside = inside + 1
        }
      _ => ()
    }
  }
  // Most of the run lands in the domain. Not all of it, deliberately: the
  // out-of-domain draw is what tests the refusal, which is the same balance
  // `setView` itself draws at.
  assert_true(inside * 2 > script.length())
}

///|
test "a property with a script body still draws its type" {
  // Nothing names a field, so there is nothing to narrow by and arbitrary is
  // the honest answer.
  let plan = plan_of(
    (
      #|state Widget {
      #|  view : String
      #|  where view is one of ["main", "format"]
      #|  property { reading : String { get set } }
      #|}
    ),
    Properties,
  )
  let script = plan.script(seed=1, steps=20)
  assert_true(script.length() > 0)
}
