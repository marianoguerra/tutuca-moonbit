// What the validator admits, what it refuses, and what it writes back.

///|
/// The surviving declaration list, or `"-"` when nothing survived.
fn kept(policy : @css.CssPolicy, src : String) -> String {
  match policy.declarations(src).css {
    Some(text) => text
    None => "-"
  }
}

///|
/// The drops, one per line, in the wording a host would show.
fn drops(policy : @css.CssPolicy, src : String) -> String {
  let out = policy.declarations(src).dropped.map(d => d.to_string())
  if out.is_empty() {
    "(none)"
  } else {
    out.join("\n")
  }
}

///|
/// One value's answer, or `"-"` when it did not survive.
fn shown(v : String?) -> String {
  match v {
    Some(text) => text
    None => "-"
  }
}

///|
fn payload() -> @css.CssPolicy {
  @css.CssPolicy::payload()
}

///|
fn app() -> @css.CssPolicy {
  @css.CssPolicy::app()
}

///|
fn constant() -> @css.CssPolicy {
  { level: Constant, overlay: false, url: FragmentOnly, stylesheet: false, }
}

// ---------------------------------------------------------------------------
// The normalization phase.
// ---------------------------------------------------------------------------

///|
/// A backslash anywhere refuses the whole list, and this is the case that says
/// why the refusal is not paranoia.
///
/// `mizchi/css/token` does not decode escapes: it drops the backslash and keeps
/// the next raw character, so `\75 rl(` reaches a name comparison as
/// `Ident("75") Whitespace Function("rl")` and nothing in the token stream says
/// `url`. Every browser reads it as `url(`. A validator that tokenized and then
/// compared function names would have admitted this.
test "an escaped url() is refused, and would have been invisible to a name check" {
  inspect(kept(payload(), "background-image:\\75 rl(#a)"), content="-")
  inspect(
    drops(payload(), "background-image:\\75 rl(#a)"),
    content="declaration: a backslash escape, which no level admits",
  )
  // The same for the fully-padded hex form, and for an escaped ordinary
  // character, which is the spelling a fuzzer finds first.
  inspect(kept(payload(), "color:\\000072ed"), content="-")
  inspect(kept(payload(), "colo\\72:red"), content="-")
  // And on a value that would otherwise be fine, so the refusal is about the
  // backslash and not about the declaration.
  inspect(kept(payload(), "color:red"), content="color:red")
  inspect(kept(payload(), "color:re\\64"), content="-")
}

///|
/// The token shapes where a recovery rule would decide the meaning are refused
/// whole, rather than skipped.
///
/// Each of these is a place two parsers can disagree, which is the only thing
/// this phase is trying to avoid. A `}` is also the brace breakout
/// `Component::compile_style` is open to — though it is not what makes the
/// output safe, since nothing unparsed is ever forwarded.
test "malformed shapes drop the whole list" {
  inspect(
    drops(payload(), "color:\"un\nterminated\""),
    content="declaration: malformed (unterminated string)",
  )
  inspect(
    drops(payload(), "color:red}html{color:blue"),
    content="declaration: malformed (a brace in a declaration list)",
  )
  inspect(
    drops(payload(), "color:red<!--"),
    content="declaration: malformed (<!-- or --> in a value)",
  )
  inspect(
    drops(payload(), "@import \"evil.css\""),
    content="declaration: malformed (@import)",
  )
  inspect(
    drops(payload(), "color:rgb(0,0,0"),
    content="declaration: malformed (unclosed ()",
  )
  inspect(
    drops(payload(), "color:rgb(0,0,0))"),
    content="declaration: malformed (unbalanced ))",
  )
}

///|
/// A comment is not a way to smuggle anything: the tokenizer drops it, and
/// what is left is the same declaration.
test "comments are removed rather than reasoned about" {
  inspect(kept(payload(), "color/**/:/**/red"), content="color:red")
  inspect(
    kept(payload(), "color:red/* ; background:lime */"),
    content="color:red",
  )
}

// ---------------------------------------------------------------------------
// Re-emission.
// ---------------------------------------------------------------------------

///|
/// The output is generated from values, never copied from the input.
///
/// This is the property the whole design rests on, and it is the inverse of the
/// rule `docs/sanitizer.md` argues for HTML: a CSS value reaches the browser as
/// a string the browser parses either way, so emitting our own canonical form
/// removes the chance that our parse and theirs disagreed rather than adding a
/// second parse.
test "values are re-emitted canonically" {
  inspect(kept(payload(), "COLOR : #FFF"), content="color:#fff")
  inspect(kept(payload(), "margin:  0px   4px"), content="margin:0px 4px")
  inspect(kept(payload(), "opacity:0.50"), content="opacity:0.5")
  inspect(kept(payload(), "width:100.0%"), content="width:100%")
  inspect(kept(payload(), "line-height:1.5"), content="line-height:1.5")
  inspect(
    kept(payload(), "color:rgb(0 0 0 / 50%)"),
    content="color:rgb(0 0 0 / 50%)",
  )
  inspect(
    kept(payload(), "width:calc(100% - 2rem)"),
    content="width:calc(100% - 2rem)",
  )
  // A trailing semicolon is not a drop, and neither is an empty one.
  inspect(kept(payload(), "color:red;;"), content="color:red")
  inspect(drops(payload(), "color:red;;"), content="(none)")
}

///|
/// A hex colour is checked for length and hex-ness, not merely for starting
/// with `#`.
test "a hash is a colour or it is nothing" {
  inspect(kept(payload(), "color:#1da1f2"), content="color:#1da1f2")
  inspect(kept(payload(), "color:#abcd"), content="color:#abcd")
  inspect(kept(payload(), "color:#12345"), content="-")
  inspect(kept(payload(), "color:#gggggg"), content="-")
}

///|
/// A unit outside the closed set drops the declaration.
test "units are a closed set" {
  inspect(kept(payload(), "width:10px"), content="width:10px")
  inspect(kept(payload(), "width:10VH"), content="width:10vh")
  inspect(kept(payload(), "width:10furlongs"), content="-")
}

///|
/// A number that would not survive the round trip is refused rather than
/// rounded, because a canonical emitter that changes a value is worse than one
/// that drops it.
test "numbers past Int range are refused" {
  inspect(kept(app(), "z-index:2147483647"), content="z-index:2147483647")
  inspect(kept(app(), "z-index:99999999999"), content="-")
}

// ---------------------------------------------------------------------------
// url() and the UrlRule.
// ---------------------------------------------------------------------------

///|
/// `NoUrl` refuses every `url()`, whatever it points at, and the property
/// carrying it survives if the rest of it does.
test "NoUrl refuses url() by the value, not by the property" {
  let p : @css.CssPolicy = {
    level: Computed,
    overlay: false,
    url: NoUrl,
    stylesheet: false,
  }
  inspect(kept(p, "background:#fff"), content="background:#fff")
  inspect(kept(p, "background:url(\"https://evil.test/p\")"), content="-")
  inspect(kept(p, "fill:#1da1f2"), content="fill:#1da1f2")
  inspect(kept(p, "fill:url(#grad)"), content="-")
  inspect(kept(p, "cursor:pointer"), content="cursor:pointer")
}

///|
/// `FragmentOnly` is what makes an SVG subset worth having.
///
/// `fill: url(#grad)` is how SVG points at a gradient it defined itself. It
/// fetches nothing — the target is an element already in the document — and
/// refusing it refuses ordinary artwork, which is why the switch exists
/// separately from the level.
test "FragmentOnly admits a fragment and nothing else" {
  inspect(kept(payload(), "fill:url(#grad)"), content="fill:url(\"#grad\")")
  inspect(
    kept(payload(), "clip-path:url(#c)"),
    content="-", // clip-path is an overlay property, and payload() has overlay off
  )
  inspect(
    kept(payload(), "marker-end:url(#arrow)"),
    content="marker-end:url(\"#arrow\")",
  )
  inspect(
    kept(payload(), "background-image:url(\"https://evil.test/p\")"),
    content="-",
  )
  inspect(
    kept(payload(), "background-image:url(\"//evil.test/p\")"),
    content="-",
  )
  inspect(kept(payload(), "background-image:url(\"/local.png\")"), content="-")
}

///|
/// `Screened` settles a fragment here and hands everything else back for the
/// caller's own scheme rule, rather than growing a second one.
test "Screened collects the URLs it did not settle" {
  let r = app().declarations(
    "background-image:url(\"/logo.png\");fill:url(#g);border-image-source:url(\"https://cdn.test/x.png\")",
    screen=_ => true,
  )
  inspect(
    r.css.unwrap(),
    content=(
      #|background-image:url("/logo.png");fill:url("#g");border-image-source:url("https://cdn.test/x.png")
    ),
  )
  inspect(r.screened_urls.join(" "), content="/logo.png https://cdn.test/x.png")
}

///|
/// The unquoted non-fragment form of `url()` is refused, and this is the one
/// decision here that costs an author something.
///
/// css-syntax-3 gives it its own token type with its own escaping and
/// whitespace rules, which `mizchi/css/token` does not implement — so it
/// arrives as a run of delimiters and identifiers that would have to be
/// reassembled by guessing at rules the tokenizer did not apply. Reassembling a
/// URL and hoping the browser agrees is exactly the mistake this package exists
/// not to make.
test "an unquoted url() is refused unless it is a fragment" {
  fn open_(src : String) -> String {
    match app().declarations(src, screen=_ => true).css {
      Some(text) => text
      None => "-"
    }
  }

  inspect(open_("background-image:url(/logo.png)"), content="-")
  inspect(
    open_("background-image:url(\"/logo.png\")"),
    content=(
      #|background-image:url("/logo.png")
    ),
  )
  inspect(
    open_("fill:url(#g)"),
    content=(
      #|fill:url("#g")
    ),
  )
}

///|
/// The scheme rule belongs to the caller, and `screen` is where it plugs in.
///
/// This package does not judge a scheme — `@filter.url_value_allowed` already
/// does, and two URL rules that could disagree would be one too many. What it
/// DOES do is fail closed: `screen` defaults to refusing, so a caller that asks
/// for `Screened` and passes nothing behaves as `NoUrl` rather than admitting
/// an unchecked URL. That default is the whole reason this is a callback and
/// not a list handed back afterwards for someone to remember to check.
test "Screened refuses by default, and defers to the caller when asked" {
  // Nothing passed: the URL does not survive, and says so.
  inspect(
    drops(app(), "background-image:url(\"https://cdn.test/x.png\")"),
    content="background-image: url(https://cdn.test/x.png) is not admitted",
  )
  // A caller's rule that says no.
  let denied = app().declarations(
    "background-image:url(\"javascript:alert(1)\")",
    screen=t => !(t is [.. "javascript:", ..]),
  )
  inspect(denied.css is None, content="true")
  inspect(denied.dropped.length(), content="1")
  // The same rule, on a URL it allows.
  let allowed = app().declarations("background-image:url(\"/logo.png\")", screen=t => {
    !(t is [.. "javascript:", ..])
  })
  inspect(allowed.screened_urls.join(" "), content="/logo.png")
  inspect(allowed.dropped.length(), content="0")
}

// ---------------------------------------------------------------------------
// The overlay switch.
// ---------------------------------------------------------------------------

///|
/// Overlay is clickjacking, not script, and no scheme check sees it.
///
/// `position:fixed; inset:0; opacity:0` is an invisible sheet over the whole
/// page, and every click on it belongs to whoever wrote the payload.
test "overlay off keeps a payload inside its box" {
  inspect(kept(payload(), "position:fixed"), content="-")
  inspect(kept(payload(), "inset:0"), content="-")
  inspect(kept(payload(), "z-index:9999"), content="-")
  inspect(kept(payload(), "transform:translate(-100px,0)"), content="-")
  inspect(
    drops(payload(), "position:fixed;inset:0;opacity:0"),
    content=(
      #|position: can overlay the page, and overlay is off
      #|inset: can overlay the page, and overlay is off
    ),
  )
  // `opacity` is not an overlay property: on its own it hides the payload's own
  // content and nothing else.
  inspect(kept(payload(), "opacity:0"), content="opacity:0")
  // And the app's own values keep all of it.
  inspect(kept(app(), "position:fixed"), content="position:fixed")
  inspect(
    kept(app(), "transform:translate(-100px,0)"),
    content="transform:translate(-100px,0)",
  )
}

///|
/// A transform function is gated wherever it appears, not only on `transform`,
/// so a property that happens to accept one cannot be a way around the switch.
test "the transform functions follow the switch, not the property" {
  inspect(kept(payload(), "width:calc(2px * 3)"), content="width:calc(2px * 3)")
  inspect(kept(payload(), "width:translate(2px)"), content="-")
  inspect(kept(app(), "width:translate(2px)"), content="width:translate(2px)")
}

// ---------------------------------------------------------------------------
// Functions.
// ---------------------------------------------------------------------------

///|
/// The function table is an allow-list, and the absences are the point.
test "only the listed functions survive" {
  inspect(
    kept(payload(), "color:color-mix(in srgb,red,blue)"),
    content="color:color-mix(in srgb,red,blue)",
  )
  inspect(
    kept(payload(), "background:linear-gradient(red,blue)"),
    content="background:linear-gradient(red,blue)",
  )
  inspect(
    kept(payload(), "width:clamp(1rem,5vw,3rem)"),
    content="width:clamp(1rem,5vw,3rem)",
  )
  // Named, because reading the list should answer the question.
  inspect(
    drops(payload(), "width:attr(data-w)"),
    content="width: attr() is not admitted",
  )
  inspect(
    drops(payload(), "width:expression(alert(1))"),
    content="width: expression() is not admitted",
  )
  inspect(
    drops(payload(), "background-image:image-set(\"a.png\" 1x)"),
    content="background-image: image-set() is not admitted",
  )
  inspect(
    drops(payload(), "background-image:element(#x)"),
    content="background-image: element() is not admitted",
  )
}

///|
/// `var()` is the classic hole, and it is closed at the DEFINITION site.
///
/// A custom property's value is arbitrary tokens per the spec, substituted
/// without being re-checked, so `--x: url(evil)` followed by
/// `background-image: var(--x)` is the whole attack. The definition is the only
/// place a token can enter, so that is where the same value grammar is applied.
test "a custom property cannot smuggle what its level refuses" {
  inspect(
    kept(payload(), "--brand:#1da1f2;color:var(--brand)"),
    content="--brand:#1da1f2;color:var(--brand)",
  )
  inspect(
    drops(
      payload(),
      "--x:url(\"https://evil.test/p\");background-image:var(--x)",
    ),
    content=(
      #|--x: url(https://evil.test/p) is not admitted
    ),
  )
  inspect(
    kept(
      payload(),
      "--x:url(\"https://evil.test/p\");background-image:var(--x)",
    ),
    content="background-image:var(--x)",
  )
  // The name's case is preserved, because a custom property's name is
  // case-SENSITIVE where every other name in CSS is not.
  inspect(
    kept(payload(), "--Brand:red;color:var(--Brand)"),
    content="--Brand:red;color:var(--Brand)",
  )
}

///|
/// `!important` beats the host's own scoped rules for that element, which for a
/// value the host did not write is the wrong way round. No level admits it and
/// no switch turns it on.
test "!important is refused at every level" {
  inspect(
    drops(payload(), "color:red!important"),
    content="color: !important is not admitted",
  )
  inspect(
    drops(app(), "color:red !important"),
    content="color: !important is not admitted",
  )
  inspect(
    kept(app(), "color:red!important;text-align:left"),
    content="text-align:left",
  )
}

// ---------------------------------------------------------------------------
// The levels.
// ---------------------------------------------------------------------------

///|
/// `Deny` is `without_css`, as a level.
test "Deny admits nothing" {
  inspect(kept(@css.CssPolicy::deny(), "color:red"), content="-")
  inspect(shown(@css.CssPolicy::deny().value("fill", "#fff")), content="-")
}

///|
/// `Constant` is paint and typography with no function anywhere, and idents are
/// held against the generated per-property keyword table.
///
/// That table is CSS CORRECTNESS rather than safety — an identifier cannot
/// fetch, execute or move anything — but a small subset a host can read is
/// exactly what this level is for, so here it refuses.
test "Constant is a small, exactly specified subset" {
  inspect(kept(constant(), "text-align:left"), content="text-align:left")
  inspect(kept(constant(), "fill:#1da1f2"), content="fill:#1da1f2")
  inspect(
    kept(constant(), "color:rebeccapurple"),
    content="color:rebeccapurple",
  )
  inspect(kept(constant(), "font-size:14px"), content="font-size:14px")
  // No function, of any kind.
  inspect(
    drops(constant(), "color:rgb(0,0,0)"),
    content="color: rgb() is not admitted",
  )
  inspect(
    drops(constant(), "width:calc(1px + 1px)"),
    content="width: not a property this level admits",
  )
  // No layout.
  inspect(
    drops(constant(), "display:flex"),
    content="display: not a property this level admits",
  )
  inspect(
    drops(constant(), "margin:0"),
    content="margin: not a property this level admits",
  )
  // No string, and no custom property to read one back with.
  inspect(
    drops(constant(), "font-family:\"Arial\""),
    content="font-family: not a property this level admits",
  )
  inspect(
    drops(constant(), "--x:red"),
    content="--x: not a property this level admits",
  )
  // The keyword table refusing a keyword that belongs to another property.
  inspect(kept(constant(), "text-align:justify"), content="text-align:justify")
  inspect(kept(constant(), "text-align:flex-start"), content="-")
  // A CSS-wide keyword works on anything.
  inspect(kept(constant(), "color:inherit"), content="color:inherit")
}

///|
/// `Computed` adds layout and the functions, and relaxes the ident check.
///
/// The relaxation is deliberate: the generated table unions grammars across
/// every level of every spec and still cannot know about the vendor keyword a
/// real page uses, and an identifier is inert. What holds the line at this
/// level is the property list, the function table and the `UrlRule` — none of
/// which an identifier can reach.
test "Computed admits layout and relaxes the keyword table" {
  inspect(kept(payload(), "display:flex"), content="display:flex")
  inspect(kept(payload(), "gap:0.5rem"), content="gap:0.5rem")
  inspect(
    kept(payload(), "font-family:\"Helvetica Neue\",sans-serif"),
    content=(
      #|font-family:"Helvetica Neue",sans-serif
    ),
  )
  inspect(kept(payload(), "display:-webkit-box"), content="display:-webkit-box")
  // Still not a property no level admits.
  inspect(
    drops(payload(), "content:\"x\""),
    content="content: not a property this level admits",
  )
  inspect(
    drops(payload(), "behavior:url(#x)"),
    content="behavior: not a property this level admits",
  )
}

// ---------------------------------------------------------------------------
// One value at a time.
// ---------------------------------------------------------------------------

///|
/// A presentation attribute is one value, so there is nothing to keep half of.
///
/// This is the entry point that widens what an SVG payload may carry: `fill`
/// and `stroke` are refused BY NAME for an untrusted guest today
/// (`tgc/policy/view_authority.mbt`) because a dynamic value could have
/// been a `url()`. With a value rule there is nothing to guess.
test "one value at a time, for a presentation attribute" {
  inspect(shown(payload().value("fill", "#1da1f2")), content="#1da1f2")
  inspect(
    shown(payload().value("fill", "url(#grad)")),
    content=(
      #|url("#grad")
    ),
  )
  inspect(
    shown(payload().value("fill", "url(\"https://evil.test/p\")")),
    content="-",
  )
  inspect(
    shown(payload().value("stroke", "currentcolor")),
    content="currentcolor",
  )
  // A semicolon in a presentation attribute is not a declaration list; it is
  // somebody trying to make one.
  inspect(shown(payload().value("fill", "red;background:url(#x)")), content="-")
  // A property no level admits refuses whatever the value is.
  inspect(shown(payload().value("content", "\"x\"")), content="-")
}

///|
/// The GFM table case, which is the reason `Build` carries two sanitizers
/// today: `style="text-align:left"` is written by `build.mbt` itself, and
/// narrowing CSS at the filter took the column alignment with it.
///
/// Under a value rule the question stops being who wrote it. The alignment
/// validates at the smallest level there is.
test "the alignment a GFM table writes survives at every level" {
  for policy in [constant(), payload(), app()] {
    inspect(kept(policy, "text-align:left"), content="text-align:left")
    inspect(kept(policy, "text-align:center"), content="text-align:center")
    inspect(kept(policy, "text-align:right"), content="text-align:right")
  }
}

// ---------------------------------------------------------------------------
// Caps.
// ---------------------------------------------------------------------------

///|
/// Generous by design, in the same register as `Policy::check_quotas`: they
/// catch a runaway, not an author.
test "the caps bound the work rather than the author" {
  let long = StringBuilder()
  for i = 0; i < 200; i = i + 1 {
    long.write_string("color:red;")
  }
  let r = payload().declarations(long.to_string())
  inspect(
    r.dropped.map(d => d.to_string()).join("\n"),
    content="declaration: over a size cap",
  )
  // Nesting, which is where a small input can cost a lot of work.
  inspect(
    kept(
      payload(),
      "width:calc(calc(calc(calc(calc(calc(calc(calc(calc(1px)))))))))",
    ),
    content="-",
  )
}
