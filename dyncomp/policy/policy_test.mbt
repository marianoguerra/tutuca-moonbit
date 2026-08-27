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
test "an untrusted bundle allows no external URLs and ships no CSS" {
  let p = Policy::untrusted()
  debug_inspect(p.tier, content="Untrusted")
  assert_false(p.allows_external_urls)
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
/// Untrusted means the wasm guest cannot turn its described DOM into a browser
/// fetch. Sink NAMES are rejected because their values may be dynamic and
/// unknowable until render.
test "untrusted views cannot name direct browser network or CSS sinks" {
  let p = Policy::untrusted()
  for
    pair in [
      // The two the external-URL allowance would reopen say so; every other
      // sink names no allowance, because none of them has one.
      ("<a href=\"/leave\">go</a>", "'href' on <a>: this host does not allow"),
      ("<img :src=\".avatar\" />", "'src' on <img>: this host does not allow"),
      ("<iframe src=\"https://x.test/\"></iframe>", "attribute 'src'"),
      ("<form action=\"/pay\"></form>", "attribute 'action'"),
      (
        "<svg><circle fill=\"url(https://attacker.test/pixel)\"></circle></svg>",
        "'fill' on <circle>",
      ),
      ("<button is=\"x-fetching-button\">go</button>", "may not use 'is'"),
      ("<style>.x{background:url(/pixel)}</style>", "may not create <style>"),
      (
        "<svg><animate attributeName=\"href\" to=\"https://attacker.test\"></animate></svg>",
        "may not create <animate>",
      ),
      ("<div @setinnermd=\".body\"></div>", "may not render runtime Markdown"),
      // Safe by construction for a plain app — Pass 1 never refuses either —
      // and still refused here, because this tier is about a narrower thing
      // than XSS. An `<img src>` the sanitizer is happy with is a GET to an
      // origin the guest chose, from the host's page, and a runtime payload can
      // synthesize every sink the list above refuses by name.
      ("<div @setinnerhtml=\".body\"></div>", "may not render runtime HTML"),
      ("<svg @setinnersvg=\".chart\"></svg>", "may not render runtime SVG"),
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
/// What an untrusted guest may now paint with, which before this was nothing.
///
/// `style` and the SVG presentation attributes were refused BY NAME, because a
/// value may be dynamic and nothing could tell a colour from a fetch.
/// `anode/sanitize/css` can, so a CONSTANT value is read: the guest gets colour,
/// type and layout, and does not get a fetch, an overlay, a `<style>` block or
/// `!important`.
///
/// A DYNAMIC value stays refused, and that is not caution. `check_view` runs at
/// registration; the dyncomp host installs `@filter.Baseline`, which carries no
/// CSS rule; so there is nothing downstream that would look at what this pass
/// cannot see. Admitting it here would be admitting it unchecked.
test "untrusted views may state a constant style" {
  let p = Policy::untrusted()
  // Admitted.
  for
    view in [
      "<div style=\"color:#1da1f2;text-align:center\"></div>", "<div style=\"display:flex;gap:0.5rem;padding:4px\"></div>",
      "<svg><circle fill=\"#1da1f2\" stroke=\"currentcolor\"></circle></svg>",
      // A fragment reference to the guest's own gradient fetches nothing.
       "<svg><circle fill=\"url(#grad)\"></circle></svg>",
    ] {
    inspect(
      shown(p.check_view("Guest/main", parsed(view))).join("\n"),
      content="",
    )
  }
  // Refused, one reason each.
  for
    pair in [
      // Egress.
      (
        "<div style=\"background-image:url(&quot;https://attacker.test/p&quot;)\"></div>",
        "url(https://attacker.test/p) is not admitted",
      ),
      // Clickjacking, which no scheme check sees.
      (
        "<div style=\"position:fixed;inset:0;opacity:0\"></div>", "can overlay the page",
      ),
      // Beating the host's own scoped rules.
      (
        "<div style=\"color:red!important\"></div>", "!important is not admitted",
      ),
      // The escape class, which is why the value is re-emitted rather than
      // approved.
      ("<div style=\"background-image:\\75 rl(#a)\"></div>", "backslash escape"),
      // And a value nothing here can read.
      (
        "<div :style=\".theme\"></div>", "must be a literal here, since nothing checks it later",
      ),
    ] {
    let (view, needle) = pair
    let messages = shown(p.check_view("Guest/main", parsed(view)))
    assert_true(messages.any(message => message.contains(needle)))
  }
}

///|
/// A macro body belongs to the host definition, but slot contents belong to
/// the caller. They are an easy traversal gap, so hold this
/// authority check against them explicitly.
test "untrusted network checks reach macro slots" {
  let refusals = shown(
    Policy::untrusted().check_view(
      "Guest/main",
      parsed("<x:card><a href=\"https://attacker.test\">go</a></x:card>"),
    ),
  )
  assert_true(refusals.any(message => message.contains("'href' on <a>")))
  // The safe markup directives too. A slot is guest markup wherever it ends up,
  // and a directive hidden one level down is exactly the shape this walk has
  // been wrong about before.
  let nested = shown(
    Policy::untrusted().check_view(
      "Guest/main",
      parsed(
        "<x:card><div @setinnerhtml=\".body\"></div><svg @setinnersvg=\".chart\"></svg></x:card>",
      ),
    ),
  )
  assert_true(nested.any(message => message.contains("runtime HTML")))
  assert_true(nested.any(message => message.contains("runtime SVG")))
}

///|
/// Above the Untrusted tier there is nothing to refuse. This is the difference
/// between the safe directives and `@dangerouslysetinnerhtml`, which a
/// `Granted` policy still refuses unless the host also set `raw_markup` — there
/// is no permission here to have forgotten, because there is no unchecked path
/// to permit.
test "the safe markup directives need no grant above the untrusted tier" {
  for p in [Policy::granted(), Policy::system()] {
    debug_inspect(
      shown(
        p.check_view("Guest/main", parsed("<div @setinnerhtml=\".b\"></div>")),
      ),
      content="[]",
    )
    debug_inspect(
      shown(
        p.check_view("Guest/main", parsed("<svg @setinnersvg=\".c\"></svg>")),
      ),
      content="[]",
    )
    // The dangerous one, under the same policy, for contrast.
    assert_true(
      shown(
        p.check_view(
          "Guest/main",
          parsed("<div @dangerouslysetinnerhtml=\".b\"></div>"),
        ),
      ).length() ==
      1,
    )
  }
}

///|
/// The other half of a macro call, and the half that had nothing looking at
/// it: the ARGUMENTS. A body is host text, but `^name` in that body is the
/// caller's string, and the caller is the guest — so an argument reaches a
/// sink through markup this check never sees.
///
/// A host with no macros is not exposed to this at all: `<x:card>` renders
/// nothing unless a macro named `card` is in scope. That is what makes it a
/// gap in the walk rather than a hole under everyone.
test "untrusted macro arguments cannot carry a URL or arbitrary CSS" {
  let p = Policy::untrusted()
  for
    pair in [
      (
        "<x:card icon=\"https://attacker.test/pixel.png\"></x:card>", "may not pass 'icon' to <x:card>",
      ),
      ("<x:card go=\"/logout\"></x:card>", "may not pass 'go' to <x:card>"),
      (
        "<x:card go=\"//attacker.test/pixel\"></x:card>", "may not pass 'go' to <x:card>",
      ),
      (
        "<x:card go=\"java\tscript:alert(1)\"></x:card>", "may not pass 'go' to <x:card>",
      ),
      (
        "<x:card cls=\"bg-[url(https://attacker.test/p)]\"></x:card>", "bracketed arbitrary utility classes",
      ),
    ] {
    let (view, needle) = pair
    let messages = shown(p.check_view("Guest/main", parsed(view)))
    assert_true(messages.any(message => message.contains(needle)))
  }
  // An argument that is not a URL is not a URL: a macro takes ordinary strings
  // and this rule is not allowed to make that awkward.
  debug_inspect(
    p.check_view(
      "Guest/main",
      parsed(
        "<x:card title=\"Ratio 1/2\" tone=\"muted\" cls=\"flex gap-2\"></x:card>",
      ),
    ),
    content="[]",
  )
}

///|
/// The allowance a picture needs. What it buys is exactly two attributes, and
/// what it charges for them is that the ORIGIN is in the view: a literal the
/// host can read in the bundle in front of it, rather than a string the guest
/// assembles once it is running.
test "allowing external URLs opens img src and a href, with the origin pinned" {
  let p = Policy::untrusted().allowing_external_urls(["https://cdn.bsky.app"])
  for
    view in [
      // A constant, and the shape a real one has: literal through the '/' that
      // ends the authority, dynamic from there.
      "<img src=\"https://cdn.bsky.app/img/avatar/plain/x@jpeg\" />", "<img :src=\"$'https://cdn.bsky.app/img/avatar/plain/{.did}/{.cid}@jpeg'\" />",
      "<a :href=\"$'https://cdn.bsky.app/profile/{.handle}'\">profile</a>",
      // A trailing slash on the host's entry, or none, is the same origin.
       "<img src=\"https://CDN.BSKY.APP/img/x.png\" />",
    ] {
    debug_inspect(p.check_view("Guest/main", parsed(view)), content="[]")
  }
  for
    pair in [
      // The origin is the guest's to choose: the whole thing it may not be.
      ("<img :src=\".avatar\" />", "must BEGIN with a literal absolute URL"),
      ("<img :src=\"$'https://{.host}/x.png'\" />", "does not pin an origin"),
      // Literal, but it stops before the authority is over, so an
      // interpolation is still choosing the host.
      (
        "<img :src=\"$'https://cdn.bsky.app{.path}'\" />", "does not pin an origin",
      ),
      // Userinfo: `cdn.bsky.app` to a prefix comparison, `attacker.test` to a
      // browser.
      (
        "<img src=\"https://cdn.bsky.app@attacker.test/p.png\" />", "does not pin an origin",
      ),
      // Pinned, and pinned somewhere this host did not agree to.
      (
        "<img src=\"https://attacker.test/p.png\" />", "is not an origin this host allows",
      ),
      // Same-origin is not "external" and is not what was allowed: a relative
      // URL is a request to the HOST, with the host's cookies on it.
      ("<a href=\"/logout\">out</a>", "'/logout' does not pin an origin"),
      // The allowance is two attributes on two elements. It is not a mood.
      ("<iframe src=\"https://cdn.bsky.app/x\"></iframe>", "attribute 'src'"),
      ("<img srcset=\"https://cdn.bsky.app/x 1x\" />", "attribute 'srcset'"),
      ("<a ping=\"https://cdn.bsky.app/x\">go</a>", "attribute 'ping'"),
      (
        "<div style=\"background:url(https://cdn.bsky.app/x)\"></div>", "'style' on <div>",
      ),
    ] {
    let (view, needle) = pair
    let messages = shown(p.check_view("Guest/main", parsed(view)))
    assert_true(messages.any(message => message.contains(needle)))
  }
}

///|
/// The list and the allowance are one decision, so one call makes both.
test "allowing external URLs is a decision a host makes deliberately" {
  assert_false(Policy::untrusted().allows_external_urls)
  let p = Policy::untrusted().allowing_external_urls(["https://cdn.bsky.app/"])
  assert_true(p.allows_external_urls)
  debug_inspect(
    p.external_origins,
    content=(
      #|["https://cdn.bsky.app"]
    ),
  )
  // Everything else about the policy is untouched.
  debug_inspect(p.tier, content="Untrusted")
  assert_false(p.allow_custom_css)
}

///|
/// An empty list is the widest form the allowance has: any `https://` origin,
/// and still no origin the guest computes.
test "allowing external URLs with no origins still refuses http and a computed host" {
  let p = Policy::untrusted().allowing_external_urls([])
  debug_inspect(
    p.check_view(
      "Guest/main",
      parsed("<img :src=\"$'https://cdn.anywhere.test/{.p}'\" />"),
    ),
    content="[]",
  )
  for
    pair in [
      ("<img src=\"http://cdn.anywhere.test/p.png\" />", "is not https"),
      ("<img :src=\".avatar\" />", "must BEGIN with a literal absolute URL"),
    ] {
    let (view, needle) = pair
    assert_true(
      shown(p.check_view("Guest/main", parsed(view))).any(message => {
        message.contains(needle)
      }),
    )
  }
}

///|
/// An origin list that does not describe origins is a mistake in the HOST, and
/// the host is the one party here who can read a message and fix it.
test "an origin a host cannot have meant is refused loudly" {
  for
    bad in [
      "cdn.bsky.app", // no scheme
       "ftp://cdn.bsky.app", // not a fetch a page makes
       "https://", // no authority
       "https://cdn.bsky.app@evil.test", // userinfo
    ] {
    try Policy::untrusted().allowing_external_urls([bad]) catch {
      e => assert_true(InvalidOrigin::to_string(e).contains(bad))
    } noraise {
      _ => fail("expected \{bad} to be refused")
    }
  }
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
  // `@markdown.filter_for` gives this policy the markup filter — see the test
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

///|
/// `parsed`, with a config table — the shape `register_bundle` gives both the
/// view it renders and the shadow tree it screens.
fn parsed_with(html : String, config : Map[String, String]) -> @anode.ANode {
  let px = @anode.ParseContext::new(config_vars=config)
  @anode.ANode::parse(html, px).unwrap()
}

///|
/// The point of the whole mechanism: the origin is still a literal, and still
/// settled before anything renders — it is just a literal the HOST wrote.
test "a bound config origin pins a sink the same way a written one does" {
  let p = Policy::untrusted().with_config([
    ("mediaOrigin", origin("https://files.hachyderm.io")),
  ])
  // Binding it allowed it: one call, one decision.
  assert_true(p.allows_external_urls)
  debug_inspect(
    p.external_origins,
    content=(
      #|["https://files.hachyderm.io"]
    ),
  )
  let cfg = p.view_config()
  // Normalized through the `/` that ends the authority, which is what makes
  // the template pin rather than merely start with the right characters.
  debug_inspect(
    cfg.get("mediaOrigin"),
    content=(
      #|Some("https://files.hachyderm.io/")
    ),
  )
  for
    html in [
      (
        #|<img :src="$'{$$mediaOrigin}{.avatarPath}'">
      ),
      (
        #|<a :href="$'{$$mediaOrigin}{.profilePath}'"></a>
      ),
      // The slash written in the view rather than carried by the value: the
      // literal head arrives in two pieces and `pinned_prefix` joins them.
      (
        #|<img :src="$'{$$mediaOrigin}cache/{.avatarPath}'">
      ),
    ] {
    debug_inspect(
      shown(p.check_view("Status/main", parsed_with(html, cfg))),
      content="[]",
    )
  }
}

///|
/// The hole this design exists to not have: a bundle that could point a sink
/// at an origin its OWN manifest named would make the rule decorative.
test "an unbound config origin reaches the guest and never a view" {
  // No `with_config` at all: `register_bundle` still hands the guest the
  // manifest's default, but `view_config` is empty, so the name resolves to
  // nothing and the view says so.
  let p = Policy::untrusted()
  debug_inspect(p.view_config(), content="{}")
  let px = @anode.ParseContext::new()
  let tree = @anode.ANode::parse(
    (
      #|<img :src="$'{$$mediaOrigin}{.avatarPath}'">
    ),
    px,
  ).unwrap()
  // The name resolved to nothing, so the template carries a hole where its
  // origin would be — and the sink is refused on the ordinary ground, because
  // a host that bound no origin allowed no external URL either.
  debug_inspect(
    shown(p.check_view("Status/main", tree)),
    content=(
      #|["Status/main: untrusted views may not use 'src' on <img>: this host does not allow external URLs in views"]
    ),
  )
}

///|
/// The reason `view_config` is a subset rather than the whole table.
test "a text config variable cannot become an origin" {
  let p = Policy::untrusted().with_config([
    ("instanceName", text("hachyderm.io")),
    ("mediaOrigin", origin("https://files.hachyderm.io")),
  ])
  let cfg = p.view_config()
  // Bound, readable by the guest, absent from what a view can name.
  assert_true(p.config.contains("instanceName"))
  assert_true(!cfg.contains("instanceName"))
  // So a view that tries to build an origin out of it gets the same answer as
  // one that tried to build an origin out of a field: the literal head stops
  // at `https://`, which pins nothing.
  let px = @anode.ParseContext::new(config_vars=cfg)
  let tree = @anode.ANode::parse(
    (
      #|<img :src="$'https://{$$instanceName}/{.avatarPath}'">
    ),
    px,
  ).unwrap()
  debug_inspect(
    shown(p.check_view("Status/main", tree)),
    content=(
      #|["Status/main: untrusted views may not use 'src' on <img>: 'https://' does not pin an origin: the literal has to run through the '/' that ends the authority, as in $'https://cdn.example/{.path}'"]
    ),
  )
}

///|
/// A config origin is checked by exactly the rules a written one is, because
/// it goes through exactly the same function.
test "a config value cannot smuggle an origin past origin_of" {
  for
    bad in [
      // userinfo: `attacker.test` to a browser, `files.hachyderm.io` to
      // anything comparing prefixes.
      "https://files.hachyderm.io@attacker.test/",
      // not https, and not http either.
       "ftp://files.hachyderm.io/",
      // no scheme at all.
       "files.hachyderm.io",
      // an authority the browser's normalization would re-read.
       "https://files.hachyderm.io\\@attacker.test/",
      // no authority.
       "https://",
    ] {
    let refused = try {
      Policy::untrusted().with_config([("mediaOrigin", origin(bad))]) |> ignore
      false
    } catch {
      InvalidConfig(_) => true
    }
    assert_true(refused)
  }
}

///|
/// A path in a bound origin is dropped rather than honored, exactly as it is
/// in `allowing_external_urls`: `/public/../private/key` is a URL to
/// `/private/key`, so a path prefix is not a boundary.
test "a path in a bound origin is dropped, not honored" {
  let p = Policy::untrusted().with_config([
    ("mediaOrigin", origin("https://files.hachyderm.io/public/")),
  ])
  debug_inspect(
    p.view_config().get("mediaOrigin"),
    content=(
      #|Some("https://files.hachyderm.io/")
    ),
  )
}

///|
/// The type is stated twice on purpose, and this is the case that needs it:
/// without the host's half, a manifest could declare `origin` for a variable
/// the host bound as prose and turn a string into a network grant.
test "a bound value carries its own type, and a bad one is loud" {
  let refused = try {
    Policy::untrusted().with_config([
      ("retries", { ty: TyNumber, value: "a lot" }),
      ("verbose", { ty: TyBool, value: "yes" }),
    ])
    |> ignore
    ""
  } catch {
    InvalidConfig(_) as e => e.to_string()
  }
  debug_inspect(
    refused,
    content=(
      #|"bad config bindings: 'retries' is a number, and 'a lot' does not read as one; 'verbose' is a bool, so it is 'true' or 'false', not 'yes'"
    ),
  )
}

///|
/// `pinned_prefix` reads the whole template head, so a literal head split
/// across parts still pins.
test "a literal head split across parts still pins" {
  let p = Policy::untrusted().allowing_external_urls(["https://cdn.example"])
  // Two literal parts and then a field: the head is `https://cdn.example/`,
  // whose authority is closed, so nothing interpolated after it can re-point
  // the request.
  debug_inspect(
    shown(
      p.check_view(
        "C/main",
        parsed_with(
          (
            #|<img :src="$'{$$o}/{.path}'">
          ),
          { "o": "https://cdn.example" },
        ),
      ),
    ),
    content="[]",
  )
  // And the run stops where the parts stop being literal: a field FIRST means
  // the guest is still choosing the host.
  debug_inspect(
    shown(
      p.check_view(
        "C/main",
        parsed_with(
          (
            #|<img :src="$'{.host}/{$$o}/x.png'">
          ),
          { "o": "https://cdn.example" },
        ),
      ),
    ),
    content=(
      #|["C/main: untrusted views may not use 'src' on <img>: the value must BEGIN with a literal absolute URL, as in $'https://cdn.example/{.path}', so the origin is settled by the view rather than computed at render"]
    ),
  )
}

///|
/// Binding is granting, but only for what was bound: the rest of the origin
/// rule is untouched.
test "a config origin does not widen anything else" {
  let p = Policy::untrusted().with_config([
    ("mediaOrigin", origin("https://files.hachyderm.io")),
  ])
  let cfg = p.view_config()
  debug_inspect(
    shown(
      p.check_view(
        "S/main",
        (
          #|<img src="https://attacker.test/p.png">
        )
        |> parsed_with(cfg),
      ),
    ),
    content=(
      #|["S/main: untrusted views may not use 'src' on <img>: 'https://attacker.test' is not an origin this host allows (https://files.hachyderm.io)"]
    ),
  )
  // Still two attributes on two elements. Still not a mood.
  debug_inspect(
    shown(
      p.check_view(
        "S/main",
        (
          #|<iframe :src="$'{$$mediaOrigin}{.path}'"></iframe>
        )
        |> parsed_with(cfg),
      ),
    ),
    content=(
      #|[
      #|  "S/main: <iframe> is not allowed (at iframe)",
      #|  "S/main: untrusted views may not use network/CSS sink attribute 'src' on <iframe>",
      #|]
    ),
  )
}

///|
/// The events a parse registered, for the event-path checks below. The same
/// shadow-parse shape `screen_view` uses: the tree and the events come from
/// one ParseContext, so a test checks what a host would actually see.
fn parsed_events(html : String) -> Array[@anode.NodeEvents] {
  let px = @anode.ParseContext::new()
  let _ = @anode.ANode::parse(html, px)
  px.events
}

///|
/// The safe profile is the default in EVERY tier constructor, because views
/// are data here whoever shipped them (SECURITY.md §9): an off-list traversal
/// step is ambient authority no guest declared.
test "an off-list event path refuses the bundle at registration" {
  debug_inspect(Policy::untrusted().event_paths, content="Safe")
  debug_inspect(Policy::granted().event_paths, content="Safe")
  debug_inspect(Policy::system().event_paths, content="Safe")
  let p = Policy::system()
  // The line SECURITY.md §9 exists for: target is fine, ownerDocument is
  // where it leaves, and the leaf is a number that converts cleanly.
  debug_inspect(
    shown(
      p.check_event_paths(
        "Guest/main",
        parsed_events(
          "<button @on.click=\"go e.target.ownerDocument.defaultView.localStorage.length\">x</button>",
        ),
      ),
    ),
    content=(
      #|["Guest/main: this host's event-path policy refuses 'ownerDocument' (at 1) in 'e.target.ownerDocument.defaultView.localStorage.length'; an event path may only go through target/currentTarget/relatedTarget/detail/dataset/dataTransfer — ask the host with an intent instead"]
    ),
  )
}

///|
test "paths the safe profile permits refuse nothing, at any tier" {
  fn clean(p : Policy) -> Unit raise {
    debug_inspect(
      p.check_event_paths(
        "Guest/main",
        parsed_events(
          "<input @on.input=\"set e.value\"><button @on.click=\"pick e.target.dataset.rowId\">r</button><button @on.click=\"zoom e.detail.a.b.c\">z</button>",
        ),
      ),
      content="[]",
    )
  }

  clean(Policy::untrusted())
  clean(Policy::granted())
  clean(Policy::system())
}

///|
test "a host may open its page's event paths deliberately" {
  let open = Policy::untrusted().with_open_event_paths()
  debug_inspect(open.event_paths, content="Open")
  debug_inspect(
    shown(
      open.check_event_paths(
        "Guest/main",
        parsed_events(
          "<button @on.click=\"go e.target.form.action\">x</button>",
        ),
      ),
    ),
    content="[]",
  )
}
