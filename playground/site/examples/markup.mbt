// Two panes of markup that the app did not write, and nothing between them and
// the DOM but `@setinnerhtml` and `@setinnersvg`.
//
// The markdown example next door makes the same argument about a source
// language. This one makes it about markup itself, which is the harder case and
// the one people reach for `@dangerouslysetinnerhtml` to solve. The payload is
// parsed ONCE, walked into described nodes, and every element and every
// attribute value is judged by the app's own sanitizer on the way out.
// `set_inner_html` is never called, so the browser never re-parses a string
// this code produced — there is no second parse to disagree with the first.
// See docs/sanitizer.md.
//
// Neither directive takes a permission, and that is not a shortcut. The
// dangerous one needs `raw_markup` because its FALLBACK is `set_inner_html`:
// mount an app without the filter and the payload goes to the browser
// unexamined. These two fail closed — no filter, empty element — so there is no
// unchecked path for a host to permit.
//
// Edit either pane. Everything above each rule renders; nothing below it does.
//
// Two cases are worth opening devtools for rather than reading on the page.
// The SVG `<animate>` is the subtle one: it is refused as an ELEMENT, not for
// anything in its value, because SMIL writes `href` in the browser after every
// check has already run — the `href` the URL rule inspected is not the one that
// would navigate. And `style` is dropped, which is the one rule these two have
// that `@dangerouslysetinnerhtml` does not: `url(…)` is a request to an origin
// the payload chose, and nothing here parses CSS to tell a background image
// from a beacon.

///|
/// Ordinary document markup, then everything the sanitizer takes back.
let html_sample : String =
  #|<h2>Markup, sanitized</h2>
  #|<p>
  #|  This pane is <b>described nodes</b>, not <code>innerHTML</code>. Tables,
  #|  lists and links all survive, and a relative
  #|  <a href="/docs">link</a> keeps its destination.
  #|</p>
  #|<table>
  #|  <tr><th>parsed</th><th>once</th></tr>
  #|  <tr><td>built</td><td>as nodes</td></tr>
  #|</table>
  #|
  #|<hr>
  #|
  #|<!-- Everything below is refused. Each drop is a line in the app's report
  #|     log (App::take_filter_reports()). -->
  #|
  #|<script>alert('script')</script>
  #|
  #|<iframe src="https://example.com"></iframe>
  #|
  #|<div onclick="alert('handler')">an on* handler, dropped by NAME</div>
  #|
  #|<p>A javascript: URL. The link keeps its words and loses its destination,
  #|  because a denied value drops the ATTRIBUTE, not the element:
  #|  <a href="javascript:alert('url')">looks like a link</a></p>
  #|
  #|<p>The classic entity obfuscation. This is a real HTML parser, so it decodes
  #|  &amp;#9; to a tab before anything reads the scheme, and the tab is then
  #|  stripped the way a browser strips it:
  #|  <a href="java&#9;script:alert('entity')">also denied</a></p>
  #|
  #|<style>body { display: none }</style>
  #|
  #|<p style="position:fixed;inset:0;background:url(https://example.com/beacon)">
  #|  A style attribute, dropped for the same reason as the block above.
  #|</p>
  #|
  #|<base href="https://example.com/">

///|
/// A bare SVG fragment — no `<svg>` root of its own, because the directive
/// supplies the context. That is the whole difference from `@setinnerhtml`.
let svg_sample : String =
  #|<circle cx="60" cy="60" r="52" fill="#dbeafe" stroke="#2563eb" stroke-width="2"/>
  #|<lineargradient id="g"><stop offset="0" stop-color="#2563eb"/></lineargradient>
  #|<rect x="30" y="46" width="60" height="28" rx="6" fill="#2563eb"/>
  #|<text x="60" y="65" text-anchor="middle" fill="#fff" font-size="11">safe</text>
  #|
  #|<!-- Refused below. -->
  #|
  #|<script>alert('svg script')</script>
  #|
  #|<use href="#g"/>
  #|
  #|<a href="/ok">
  #|  <animate attributeName="href" to="javascript:alert('smil')"/>
  #|</a>
  #|
  #|<circle cx="10" cy="10" r="4" style="fill:url(https://example.com/beacon)"/>

///|
fn build() -> @component.ModuleDef {
  let editor = markup_preview_component(
    init=MarkupPreviewState::{ html: html_sample, svg: svg_sample },
  )
  @component.ModuleDef::new(
    name="markup",
    components=[editor],
    examples=[
      { component: "MarkupPreview", title: "Default", args: Map([]), view: None },
    ],
  )
}
