// The seam nothing was asserting: what the lowering PRINTS has to parse as
// the notation it printed for.
//
// Every other test here asserts that the output contains an expected
// substring, which is the printer checked against itself — and text can read
// perfectly and not parse. `tgc/emit`'s `split` makes this exact call, so
// this is not a new contract; it is the one that already exists, one layer up,
// asserted where a failure names the lowering rather than the splitter.

///|
/// Lower a source and split what comes out.
///
/// Splitting is the FIRST thing the consumer does and not the last: it finds
/// the blocks and does not read what is in them, so a value it cannot parse
/// surfaces one layer further on. The compiling half of this seam is asserted
/// in `tgc/emit`, against the reader that does parse them.
fn splits(src : String) -> String {
  let out = lower_text(src)
  if out.reports.length() > 0 {
    return "lowering: " + out.reports[0].message
  }
  let _ = @viewfile.split_file(out.text, name="T") catch {
    e => return "splitting: " + e.message()
  }
  "ok"
}

///|
test "a write in an event option" {
  inspect(
    splits(
      (
        #|spec:
        #|  T:
        #|    field text :: String
        #|view:
        #|  T:
        #|    @input(~value: it.text, ~on_input: it.text := e.value){}
        #|
      ),
    ),
    content="ok",
  )
}

///|
test "a compute called inside a string template" {
  inspect(
    splits(
      (
        #|spec:
        #|  T:
        #|    field on :: Bool
        #|logic:
        #|  T:
        #|    compute mode(): if it.on | "wrap" | "nowrap"
        #|    compute style(): @str{flex-wrap:@(mode())}
        #|view:
        #|  T:
        #|    @div(~style: style()){x}
        #|
      ),
    ),
    content="ok",
  )
}

///|
test "a conditional attribute value" {
  inspect(
    splits(
      (
        #|spec:
        #|  T:
        #|    field on :: Bool
        #|view:
        #|  T:
        #|    @div(~style: if it.on | "a" | "b"){x}
        #|
      ),
    ),
    content="ok",
  )
}

///|
test "rendering the loop's own item" {
  inspect(
    splits(
      (
        #|spec:
        #|  T:
        #|    field cells :: List.of(Any)
        #|view:
        #|  T:
        #|    @div{
        #|      @each(cell in it.cells){
        #|        @div(~class: "wrap"){
        #|          @render(cell)
        #|        }
        #|      }
        #|    }
        #|
      ),
    ),
    content="ok",
  )
}
