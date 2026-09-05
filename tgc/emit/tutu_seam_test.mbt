///|
/// What the lowering PRINTS has to compile as the notation it printed for.
///
/// The lowering's own tests assert that its output contains an expected
/// substring, which is the printer checked against itself — and text can read
/// perfectly and not parse. This is the assertion that catches that: it hands
/// the lowered text to the reader that reads attribute values, which is the
/// layer where a spelling the author never wrote turns up as their error.
test "a `.tutu` view compiles, value by value" {
  let cases = [
    // a write in an event option, which the migration guide's own table shows
    (
      "a write in an event",
      (
        #|spec:
        #|  T:
        #|    field text :: String
        #|view:
        #|  T ~root:
        #|    @input(~value: it.text, ~on_input: it.text := e.value){}
      ),
    ),
    // a compute called inside a string template
    (
      "a compute in a template",
      (
        #|spec:
        #|  T:
        #|    field on :: Bool
        #|logic:
        #|  T:
        #|    compute mode(): if it.on | "wrap" | "nowrap"
        #|    compute style(): @str{flex-wrap:@(mode())}
        #|view:
        #|  T ~root:
        #|    @div(~style: style()){x}
      ),
    ),
    // a conditional attribute value, which the old notation spells with
    // `@if.<attr>` because a bound value cannot carry an `if`
    (
      "a conditional attribute",
      (
        #|spec:
        #|  T:
        #|    field on :: Bool
        #|view:
        #|  T ~root:
        #|    @div(~style: if it.on | "a" | "b"){x}
      ),
    ),
    // rendering the loop's own item from inside a wrapper element
    (
      "rendering the loop's item",
      (
        #|spec:
        #|  T:
        #|    field cells :: List.of(Any)
        #|view:
        #|  T ~root:
        #|    @div{
        #|      @each(cell in it.cells){
        #|        @div(~class: "wrap"){
        #|          @render(cell)
        #|        }
        #|      }
        #|    }
      ),
    ),
  ]
  let failed = []
  for c in cases {
    let (name, src) = c
    let _ = @emit.compile(src, name="t") catch {
      e => {
        failed.push(name + ": " + e.message())
        continue
      }
    }
  }
  @debug.assert_eq(failed, [])
}
