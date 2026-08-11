///| Blackbox tests over the decisions.
///
/// These are the executable half of SECURITY.md. Where that document says a
/// bundle can reach something or cannot, this is where the claim either holds
/// or stops compiling.

///|
fn parsed(html : String) -> @anode.ANode {
  let px = @anode.ParseContext::new()
  @anode.ANode::parse(html, px).unwrap()
}

///|
fn shown(refusals : Array[Refusal]) -> Array[String] {
  refusals.map(r => r.to_string())
}

///|
/// The default, and the tier the whole design is FOR: a runtime-extensible
/// catalog is only interesting if a bundle nobody vetted is usable at it.
test "an untrusted bundle gets no capabilities and ships no CSS" {
  let p = Policy::untrusted()
  debug_inspect(p.tier, content="Untrusted")
  debug_inspect(p.grants, content="[]")
  debug_inspect(
    shown(p.check_style("Counter", ".counter { color: red }")),
    content=(
      #|["Counter: this host takes no CSS from a bundle; style with the host's utility classes instead"]
    ),
  )
  // ...but an empty style is fine, which is what every sample guest ships
  debug_inspect(p.check_style("Counter", ""), content="[]")
}

///|
/// An ungranted capability refuses the BUNDLE rather than degrading it. The
/// alternative — hand it over and answer with a zero — produces a component
/// that appears to work and is quietly wrong.
test "an ungranted capability refuses, and says which and why" {
  let p = Policy::untrusted()
  let asked : Array[CapabilityReq] = [
    { cap: CapClock, reason: "stamps each entry" },
    { cap: CapTimer, reason: "" },
  ]
  debug_inspect(
    shown(p.check_capabilities(asked)),
    content=(
      #|[
      #|  "this host does not grant cap-clock (asked for it to: stamps each entry)",
      #|  "this host does not grant cap-timer",
      #|]
    ),
  )
  assert_false(p.grants_all(asked))
  // a bundle that asked for nothing always passes
  assert_true(p.grants_all([]))
}

///|
/// A person saying yes gets the clock and ids, and still not a timer: a bundle
/// that wants to wake itself up is asking for something nobody can
/// meaningfully consent to in one dialog.
test "the tiers grant capabilities deliberately" {
  let clock : Array[CapabilityReq] = [{ cap: CapClock, reason: "" }]
  let timer : Array[CapabilityReq] = [{ cap: CapTimer, reason: "" }]
  assert_false(Policy::untrusted().grants_all(clock))
  assert_true(Policy::granted().grants_all(clock))
  assert_false(Policy::granted().grants_all(timer))
  assert_true(Policy::system().grants_all(timer))
}

///|
/// Untrusted means the wasm guest cannot turn its described DOM into a browser
/// fetch. Sink NAMES are rejected because their values may be dynamic and
/// unknowable until render.
test "untrusted views cannot name direct browser network or CSS sinks" {
  let p = Policy::untrusted()
  for
    pair in [
      ("<a href=\"/leave\">go</a>", "attribute 'href'"),
      ("<img :src=\".avatar\" />", "attribute 'src'"),
      (
        "<svg><circle fill=\"url(https://attacker.test/pixel)\"></circle></svg>",
        "attribute 'fill'",
      ),
      ("<button is=\"x-fetching-button\">go</button>", "may not use 'is'"),
      ("<style>.x{background:url(/pixel)}</style>", "may not create <style>"),
      (
        "<svg><animate attributeName=\"href\" to=\"https://attacker.test\"></animate></svg>",
        "may not create <animate>",
      ),
      ("<div @setinnermd=\".body\"></div>", "may not render runtime Markdown"),
      (
        "<div class=\"bg-[url(https://attacker.test/pixel)]\"></div>", "bracketed arbitrary utility classes",
      ),
    ] {
    let (view, needle) = pair
    let messages = shown(p.check_view("Guest/main", parsed(view)))
    assert_true(messages.any(message => message.contains(needle)))
  }
}

///|
/// A macro body belongs to the host definition, but slot contents belong to
/// the caller. They are a historically easy traversal gap, so hold this
/// authority check against them explicitly.
test "untrusted network checks reach macro slots" {
  let refusals = shown(
    Policy::untrusted().check_view(
      "Guest/main",
      parsed("<x:card><a href=\"https://attacker.test\">go</a></x:card>"),
    ),
  )
  assert_true(refusals.any(message => message.contains("attribute 'href'")))
}

///|
/// Autonomous custom elements stay usable. Ordinary values and structured
/// properties are intentionally preserved; only customized built-ins and
/// browser-native sinks are removed from the untrusted surface.
test "untrusted views retain autonomous custom elements" {
  let view = parsed(
    "<x-picker :items=\".items\" mode=\"compact\" class=\"flex gap-2\"></x-picker>",
  )
  debug_inspect(
    Policy::untrusted().check_view("Guest/main", view),
    content="[]",
  )
}

///|
/// A Granted/System bundle was vouched for as app code. It keeps the normal
/// render-time URL filtering and may use the richer DOM/CSS surface.
test "trusted tiers retain network and CSS-capable view syntax" {
  let view = parsed(
    "<section style=\"background:url(/trusted)\"><a href=\"/ok\">ok</a><div @setinnermd=\".body\"></div></section>",
  )
  debug_inspect(
    Policy::granted().check_view("Trusted/main", view),
    content="[]",
  )
  debug_inspect(Policy::system().check_view("Trusted/main", view), content="[]")
}

///|
/// Kept rather than dropped, so a refusal can say WHICH one — a dropped name
/// would make a bundle asking for something unrecognized look like a bundle
/// asking for nothing.
test "a capability this host has never heard of is refused by name" {
  let asked : Array[CapabilityReq] = [
    { cap: Capability::parse("cap-teleport"), reason: "" },
  ]
  debug_inspect(asked[0].cap, content="CapUnknown(\"cap-teleport\")")
  debug_inspect(
    shown(Policy::system().check_capabilities(asked)),
    content=(
      #|["this host does not grant cap-teleport"]
    ),
  )
}

///|
/// Raw markup is refused because its value is an expression and by render time
/// the markup is in the document. Everything else in a view is DESCRIBED and so
/// inspectable before it runs — which is what the rest of the sanitizer is
/// about.
test "a view that sets markup directly is refused at every tier" {
  let raw = parsed("<div @dangerouslysetinnerhtml=\".payload\"></div>")
  for p in [Policy::untrusted(), Policy::granted(), Policy::system()] {
    debug_inspect(
      shown(p.check_view("Sneaky/main", raw)),
      content=(
        #|["Sneaky/main: <div> sets markup directly (@dangerouslysetinnerhtml), which cannot be checked before it renders (at div)"]
      ),
    )
  }
  // an ordinary view, however deep the construct would have been, passes
  let fine = parsed(
    "<div><ul><li @each=\".items\" @text=\"@value\"></li></ul><button @on.click=\"go\">go</button></div>",
  )
  debug_inspect(Policy::untrusted().check_view("Ok/main", fine), content="[]")
}

///|
/// A host can hand a policy its own sanitizer. The tier constructors are the
/// baseline, and stay that way.
test "a policy carries a sanitizer a host can replace" {
  let raw = parsed("<div @dangerouslysetinnerhtml=\".payload\"></div>")
  let strict = Policy::untrusted()
  assert_false(strict.allows_raw_markup())
  assert_true(strict.check_view("Sneaky/main", raw).length() == 1)

  // Loosened: the construct passes registration. Only safe because
  // `@markup.filter_for` gives this policy the markup filter — see the test
  // for that pairing in vdom/filter/markup.
  let configured_untrusted = strict.with_sanitizer({
    ..@sanitize.SanitizerConfig::empty(),
    raw_markup: Some(true),
  })
  assert_false(configured_untrusted.allows_raw_markup())
  assert_true(
    shown(configured_untrusted.check_view("No/main", raw)).any(message => {
      message.contains("may not render runtime HTML")
    }),
  )

  let loose = Policy::granted().with_sanitizer({
    ..@sanitize.SanitizerConfig::empty(),
    raw_markup: Some(true),
  })
  assert_true(loose.allows_raw_markup())
  debug_inspect(loose.check_view("Ok/main", raw), content="[]")

  // Everything else about the policy is untouched — it is the same policy with
  // a different sanitizer, not a different tier.
  debug_inspect(loose.tier, content="Granted")
  assert_true(loose.allow_custom_css)
  // ...and the baseline still holds inside it: permitting raw markup is not
  // permitting a script.
  debug_inspect(
    shown(
      loose.check_view("Sneaky/main", parsed("<div><script></script></div>")),
    ),
    content=(
      #|["Sneaky/main: <script> is not allowed (at div>script)"]
    ),
  )
}

///|
/// Tightening is the other direction, and the one a host reaching for an
/// allow-list wants.
test "a policy can be tightened with an allow-list" {
  let p = Policy::untrusted().with_sanitizer({
    ..@sanitize.SanitizerConfig::empty(),
    elements: Some([
      @sanitize.ElementRule::of(@sanitize.html("div")),
      @sanitize.ElementRule::of(@sanitize.html("span")),
    ]),
  })
  debug_inspect(
    p.check_view("Ok/main", parsed("<div><span></span></div>")),
    content="[]",
  )
  debug_inspect(
    shown(p.check_view("No/main", parsed("<div><p></p></div>"))),
    content=(
      #|["No/main: <p> is not allowed (at div>p)"]
    ),
  )
}

///|
/// An invalid config is a programming error in the HOST — the one party who can
/// read the message and fix it — so it raises rather than degrading.
test "an invalid sanitizer config is refused loudly" {
  let bad : @sanitize.SanitizerConfig = {
    ..@sanitize.SanitizerConfig::empty()
    // the spec's own validity relation: allow xor remove
    ,
    elements: Some([@sanitize.ElementRule::of(@sanitize.html("div"))]),
    remove_elements: Some([@sanitize.html("span")]),
  }
  try Policy::untrusted().with_sanitizer(bad) catch {
    e =>
      inspect(
        @sanitize.InvalidConfig::to_string(e),
        content=(
          #|config sets both elements and remove_elements; the spec allows one or the other
        ),
      )
  } noraise {
    _ => fail("an invalid config must not build a policy")
  }
}

///|
/// What the sanitizer catches that the `has_raw_html` predicate before it did
/// not: an unsafe element, an event-handler attribute, and — the one that was a
/// live gap — either of those inside a macro call's slot, which
/// `ANode::for_each_child` never visits. See SECURITY.md §3.
test "the sanitizer refuses more than raw markup" {
  let p = Policy::untrusted()
  debug_inspect(
    shown(p.check_view("Sneaky/main", parsed("<div><script></script></div>"))),
    content=(
      #|["Sneaky/main: <script> is not allowed (at div>script)"]
    ),
  )
  debug_inspect(
    shown(
      p.check_view("Sneaky/main", parsed("<div onclick=\"alert(1)\"></div>")),
    ),
    content=(
      #|["Sneaky/main: attribute 'onclick' is not allowed on <div> (at div)"]
    ),
  )
  debug_inspect(
    shown(
      p.check_view(
        "Sneaky/main",
        parsed("<x:card><iframe src=\"evil\"></iframe></x:card>"),
      ),
    ),
    content=(
      #|[
      #|  "Sneaky/main: <iframe> is not allowed (at iframe)",
      #|  "Sneaky/main: untrusted views may not use network/CSS sink attribute 'src' on <iframe>",
      #|]
    ),
  )
}

///|
/// Not a security boundary — a bundle with no authority cannot do harm with a
/// big manifest — but an availability one. The host parses every view and
/// compiles every component before it renders anything.
test "quotas bound what a host will parse before it renders" {
  let p = Policy::untrusted()
  let ok : BundleFacts = {
    components: 4,
    max_views: 3,
    max_view_bytes: 2000,
    max_style_bytes: 0,
    max_types: 12,
  }
  debug_inspect(p.check_quotas(ok), content="[]")
  let bomb : BundleFacts = {
    components: 10000,
    max_views: 3,
    max_view_bytes: 40_000_000,
    max_style_bytes: 0,
    max_types: 12,
  }
  debug_inspect(
    shown(p.check_quotas(bomb)),
    content=(
      #|[
      #|  "too many components: 10000 (the limit is 128)",
      #|  "too many bytes in one view: 40000000 (the limit is 262144)",
      #|]
    ),
  )
}

///|
/// Generous on purpose: these catch a runaway, not an author. A real component
/// has a handful of views and a dozen types.
test "the default quotas are orders of magnitude clear of real use" {
  let q = Quotas::default()
  let realistic : BundleFacts = {
    components: 8,
    max_views: 4,
    max_view_bytes: 8000,
    max_style_bytes: 1200,
    max_types: 20,
  }
  debug_inspect(Policy::granted().check_quotas(realistic), content="[]")
  assert_true(q.max_components >= 100)
  assert_true(q.max_view_bytes >= 100000)
}
