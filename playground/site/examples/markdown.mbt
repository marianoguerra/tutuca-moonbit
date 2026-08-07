// A live markdown editor: source on the left, rendered output on the right,
// and NOTHING between them but `@setinnermd`.
//
// The directive is the whole example. `:value` / `@on.input` keep `source` in
// step with the textarea the ordinary way (see text_input); `@setinnermd`
// parses that string on every render, sanitizes the result against the app's
// sanitizer, and replaces the preview pane's CHILDREN with described nodes.
// `set_inner_html` is never called, so the browser never re-parses a string
// this code produced — there is no second parse to disagree with the first.
// See docs/sanitizer.md.
//
// The starting document is half feature tour, half attack list. Edit either
// half: everything in the first renders, and nothing in the second executes.
// The point worth taking away is that they go through the SAME sanitizer that
// judges every other node in the tree — there is no markdown-specific
// allow-list to fall behind, and no permission a host has to remember to
// withhold.
//
// One case is worth watching in a devtools inspector rather than on the page.
// `[x](java&#9;script:…)` written as a markdown DESTINATION keeps its href,
// because nothing on that path decodes the entity: the scheme stays the literal
// `java&#9;script`, which navigates nowhere, and the value reaches the DOM
// through `setAttribute`, where entities do not exist. Serialize the sanitized
// tree back to HTML text instead and the browser's parser decodes it on the way
// back in — `java\tscript:` → `javascript:` → it fires. That one input is the
// whole argument for building nodes, and there is a test on it in
// `vdom/filter/markdown/markdown_test.mbt`.

///|
/// Everything the renderer supports, then everything it refuses.
let sample : String =
  #|# Live markdown
  #|
  #|Type on the left. This pane is **described nodes**, not `innerHTML` —
  #|*emphasis*, ~~strikethrough~~, `inline code`, and a [link](https://moonbitlang.com "MoonBit").
  #|
  #|## Lists
  #|
  #|- unordered, tight
  #|- with `code` and **bold**
  #|
  #|1. ordered
  #|2. also ordered
  #|
  #|- [x] task lists are GFM
  #|- [ ] and the checkbox is disabled
  #|
  #|## Blocks
  #|
  #|> A blockquote, which can hold
  #|> its own **blocks**.
  #|
  #|```moonbit
  #|fn main {
  #|  println("fenced code keeps its language as a class")
  #|}
  #|```
  #|
  #|| feature   | left | center | right |
  #||-----------|:-----|:------:|------:|
  #|| tables    | yes  |  yes   |   yes |
  #|| alignment | via  | inline | style |
  #|
  #|Footnotes work too.[^1]
  #|
  #|[^1]: And collect into a section at the end.
  #|
  #|---
  #|
  #|## Now the dangerous half
  #|
  #|Nothing below executes. It fails in two different ways, and both are worth
  #|seeing — some of it VANISHES, and some of it stays on the page as visible
  #|characters.
  #|
  #|An opener the block parser recognises becomes an element, gets a verdict from
  #|the sanitizer, and is dropped — with a line in the app's report log
  #|(`App::take_filter_reports()`). One it does not recognise never becomes an
  #|element at all: it lands as a TEXT node, which is why you can read it below.
  #|Text reaches the DOM through `createTextNode` and can never be parsed as
  #|markup, so there is nothing to report and nothing to run.
  #|
  #|A raw script block. This one is TEXT — you can read it, and that is the
  #|point: it is characters, not an element, and characters do not run:
  #|
  #|<script>alert('script block')</script>
  #|
  #|An SVG script, which is a DIFFERENT element from the one above — element
  #|identity is namespace-qualified, and reading that off a summary instead of
  #|the spec is how this one got missed the first time:
  #|
  #|<svg><script>alert('svg script')</script></svg>
  #|
  #|An iframe, which the block parser DOES recognise — so it becomes an element,
  #|gets a verdict, and vanishes with a line in the report log:
  #|
  #|<iframe src="https://example.com"></iframe>
  #|
  #|An event handler, dropped by NAME whatever its value:
  #|
  #|<div onclick="alert('handler')">click me — nothing happens</div>
  #|
  #|A `javascript:` URL. The link keeps its words and loses its destination,
  #|because a denied value drops the ATTRIBUTE, not the element:
  #|[looks like a link](javascript:alert('url'))
  #|
  #|Case is normalized before the scheme is read, so this is denied too:
  #|[looks harmless](JaVaScRiPt:alert('case'))
  #|
  #|The classic entity obfuscation, as raw HTML. The parser decodes `&#9;` to a
  #|tab, the tab is stripped, and what is left reads as `javascript:`:
  #|
  #|<div><a href="java&#9;script:alert('entity')">also denied</a></div>
  #|
  #|`data:` splits by attribute. A same-origin document is denied on a link:
  #|[data url](data:text/html,<script>alert('data')</script>)
  #|
  #|...and allowed on an image, because that is ordinary:
  #|
  #|![a real data-url image](data:image/svg+xml,%3Csvg%20xmlns%3D%22http%3A%2F%2Fwww.w3.org%2F2000%2Fsvg%22%20width%3D%2224%22%20height%3D%2224%22%3E%3Ccircle%20cx%3D%2212%22%20cy%3D%2212%22%20r%3D%2210%22%20fill%3D%22%232563eb%22%2F%3E%3C%2Fsvg%3E)
  #|
  #|A `<base>` tag, which would retarget every relative URL on this page. The
  #|spec leaves it to the config layer; tutuca refuses it outright:
  #|
  #|<base href="https://example.com/">
  #|
  #|And a bare inline tag, which never becomes markup at all — it is text, and
  #|renders as the characters you typed: <span style="color:red">not red</span>
  #|

///|
fn build() -> @component.ModuleDef {
  let editor = md_preview_component(init=MdPreviewState::{ source: sample })
  @component.ModuleDef::new(
    name="markdown",
    components=[editor],
    examples=[
      { component: "MdPreview", title: "Default", args: Map([]), view: None },
    ],
  )
}
