// The converter, over the file the migration page works through.
//
// The assertion that means something is `@equiv.compare`: what was printed is
// compared against the file it was printed FROM, by what the pipeline reads out
// of each. A snapshot of the text would pin the converter's formatting and say
// nothing about whether the conversion is sound.

///|
let guarded : String =
  #|<script type="tutuca/spec">
  #|  /// A counter with a rule.
  #|  state Guarded {
  #|    /// How far it has counted.
  #|    n: Int
  #|
  #|    /// True while there is room left.
  #|    pred room
  #|      format $'the counter is full at {.n}' { .n < 3 }
  #|  }
  #|</script>
  #|
  #|<script type="tutuca/script">
  #|  /// Count one more, while there is room.
  #|  receive bump requires room {
  #|    .n += 1
  #|  }
  #|</script>
  #|
  #|<script type="tutuca/fixtures">
  #|{
  #|  "nearly full": {
  #|    "value": { "n": 2 },
  #|    "doc": "One press from the rule declining."
  #|  }
  #|}
  #|</script>
  #|
  #|<script type="tutuca/test">
  #|{
  #|  "the guard stops it at three": {
  #|    "steps": [
  #|      { "click": "button" },
  #|      { "expect": "text", "at": "output", "is": "3" },
  #|      { "expect": "log", "contains": "does not hold" }
  #|    ]
  #|  }
  #|}
  #|</script>
  #|
  #|<template id="Guarded">
  #|  <div>
  #|    <button @on.click="bump">+</button>
  #|    <output @text=".n"></output>
  #|  </div>
  #|</template>
  #|

///|
test "a card converts, and what comes out means what went in" {
  let got = convert(guarded, name="Guarded")
  @debug.assert_eq(got.refusals, [])
  let diffs = @equiv.compare(guarded, got.text, name="Guarded")
  @debug.assert_eq(diffs.map(d => d.line()), [])
}

///|
/// What the conversion looks like, so a reader can see the notation rather than
/// only that it verified.
test "the file it writes" {
  let got = convert(guarded, name="Guarded")
  inspect(
    got.text,
    content=(
      #|spec:
      #|  /// A counter with a rule.
      #|  Guarded:
      #|    /// How far it has counted.
      #|    field n :: Int
      #|
      #|    /// True while there is room left.
      #|    pred room:
      #|      ~format: @str{the counter is full at @(it.n)}
      #|      (it.n < 3)
      #|
      #|logic:
      #|  Guarded:
      #|    /// Count one more, while there is room.
      #|    receive bump:
      #|      ~requires: room
      #|      it.n += 1
      #|
      #|view:
      #|  Guarded:
      #|    @div{
      #|      @button(~on_click: bump){+}
      #|      @output{@(it.n)}
      #|    }
      #|
      #|fixtures:
      #|  "nearly full":
      #|    ~doc: "One press from the rule declining."
      #|    it.n = 2
      #|
      #|tests:
      #|  "the guard stops it at three":
      #|    click("button")
      #|    expect text("output") == "3"
      #|    expect log contains "does not hold"
      #|
    ),
  )
}

///|
/// A literal `@` in element content, which had no working spelling until
/// `marianoguerra/shrubbery@0.1.1`.
///
/// The spelling is `@"…"` over the WHOLE text run, not `@@` and not a
/// per-character `@"@"`. `@@` is a read error in the reference implementation
/// too; the per-character form parses but splits one text node into three and
/// eats the spaces around itself. Before 0.1.1 the wrong spelling did not merely
/// fail — it stranded the body's tokens and sent recovery into a loop that
/// segfaulted the reader, which is why this file used to hold a guard refusing
/// every `@` the converter had not written itself.
test "a literal `@` in text converts and reads back as itself" {
  let html =
    #|<script type="tutuca/spec">
    #|  state Card { n: Int }
    #|</script>
    #|<template id="Card">
    #|  <p>write to me @ home</p>
    #|</template>
    #|
  let got = convert(html, name="Card")
  @debug.assert_eq(got.refusals, [])
  assert_true(got.text.contains("@\"write to me @ home\""))
  let diffs = @equiv.compare(html, got.text, name="Card")
  @debug.assert_eq(diffs.map(d => d.line()), [])
}

///|
/// And a stylesheet's own at-rules pass through untouched: CSS is emitted
/// verbatim, so `@media` is `@media`.
test "a CSS at-rule converts" {
  let html =
    #|<script type="tutuca/spec">
    #|  state Card { n: Int }
    #|</script>
    #|<style>@media (min-width: 40em) { .a { color: red; } }</style>
    #|<template id="Card">
    #|  <p>x</p>
    #|</template>
    #|
  let got = convert(html, name="Card")
  @debug.assert_eq(got.refusals, [])
  assert_true(got.text.contains("@media (min-width: 40em)"))
  let diffs = @equiv.compare(html, got.text, name="Card")
  @debug.assert_eq(diffs.map(d => d.line()), [])
}

///|
/// Every `.html` this file converts, as one corpus.
///
/// It is a PRODUCED corpus, which is the point. `tutufile/lower`'s
/// `roundtrip_test.mbt` asserts the same two properties over three `.tutu`
/// sources written by hand beside the assertion — the properties are right and
/// the corpus is imagined, which is the shape that let `print_macro` and the
/// `ty` fixtures pass while being wrong. What this converter emits is not
/// written by whoever is asserting it, so it grows as the converter's coverage
/// does and it holds the constructs the corpus actually contains.
fn produced() -> Array[(String, String)] {
  let out = []
  for
    c in [("guarded", guarded), ("at sign", with_at), ("at rule", with_at_rule)] {
    let (name, html) = c
    let got = convert(html, name="Card")
    if got.refusals.is_empty() {
      out.push((name, got.text))
    }
  }
  out
}

///|
let with_at : String =
  #|<script type="tutuca/spec">
  #|  state Card { n: Int }
  #|</script>
  #|<template id="Card">
  #|  <p>write to me @ home</p>
  #|</template>
  #|

///|
let with_at_rule : String =
  #|<script type="tutuca/spec">
  #|  state Card { n: Int }
  #|</script>
  #|<style>@media (min-width: 40em) { .a { color: red; } }</style>
  #|<template id="Card">
  #|  <p>x</p>
  #|</template>
  #|

///|
test "what the converter writes reproduces its own input" {
  let broken = []
  for c in produced() {
    let (name, src) = c
    let parsed = @shrub.parse(src) catch {
      e => {
        broken.push(name + ": parse: " + e.diagnostic().kind.code())
        continue
      }
    }
    if @shrub.to_source(parsed.root()) != src {
      broken.push(name + ": to_source differs from what was written")
    }
  }
  @debug.assert_eq(broken, [])
  // and the corpus is not empty, or the loop above asserts nothing
  assert_eq(produced().length(), 3)
}

///|
test "and re-formatting what it writes reads back to the same tree" {
  let broken = []
  for c in produced() {
    let (name, src) = c
    let first = @shrub.parse(src) catch {
      e => {
        broken.push(name + ": parse: " + e.diagnostic().kind.code())
        continue
      }
    }
    let written = @shrub.write(first.root(), style=Pretty, width=Some(0))
    let second = @shrub.parse(written) catch {
      e => {
        broken.push(name + ": reparse: " + e.diagnostic().kind.code())
        continue
      }
    }
    if first.root().canonical() != second.root().canonical() {
      broken.push(name + ": the re-formatted tree is not the same tree")
    }
  }
  @debug.assert_eq(broken, [])
}

///|
/// The spaces around a hole, which `equiv` cannot see.
///
/// `<span>a <x text=".n"></x> b</span>` has the text nodes `"a "` and `" b"`,
/// and those spaces are what the page renders between the words. The inline
/// form used to trim each printed child before joining, which ate them — and
/// nothing caught it, because `equiv` compares trees modulo whitespace by
/// design (see `tutufile/equiv/moon.pkg`). A check whose subject is one step
/// away from what breaks; this is the assertion that is not.
test "the spaces around a hole survive" {
  let html =
    #|<script type="tutuca/spec">
    #|  state Card { n: Int }
    #|</script>
    #|<template id="Card">
    #|  <span>a <x text=".n"></x> b</span>
    #|</template>
    #|
  let got = convert(html, name="Card")
  @debug.assert_eq(got.refusals, [])
  assert_true(got.text.contains("@span{a @(it.n) b}"))
  assert_false(got.text.contains("@span{a@(it.n)b}"))
}

///|
/// And a text run that holds an owned character keeps its own spacing too,
/// because it is written whole rather than pieced together.
test "a literal `@` keeps the text around it" {
  let html =
    #|<script type="tutuca/spec">
    #|  state Card { n: Int }
    #|</script>
    #|<template id="Card">
    #|  <p>a@b</p>
    #|</template>
    #|
  let got = convert(html, name="Card")
  @debug.assert_eq(got.refusals, [])
  assert_true(got.text.contains("@p{@\"a@b\"}"))
}
