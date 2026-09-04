///| Registration-time authority checks for views from an untrusted bundle.
///
/// The Sanitizer API model answers whether a NAME is safe to put in a DOM
/// tree. This answers a narrower dynamic-component question: whether that name gives a
/// guest a browser-managed route out of its wasm sandbox. Values may be
/// dynamic, so sink attributes are refused by name instead of trying to
/// validate only the literals visible now.
///
/// The one place that generalizes is the external-URL allowance, and it does
/// not break the rule so much as find the part of a value that IS static: a
/// URL's origin, when the view writes it as a literal. `external_url.mbt`
/// owns that rule; this file owns where it applies.

///|
/// Whether this attribute name is a CSS VALUE rather than a value of its own.
///
/// `style` is a declaration list. Every other name here is an SVG presentation
/// attribute: `<circle fill="red">` sets the `fill` PROPERTY, with the same
/// grammar it has in a stylesheet, which is why `fill="url(…)"` is a fetch and
/// `fill="red"` is a colour. The set is asked of the generated property table
/// rather than listed, so a property that becomes a presentation attribute is
/// covered without anyone noticing.
///
/// These are accepted for the CONSTANT case, because `anode/sanitize/css` can
/// tell a colour from a fetch. See `check_untrusted_attrs`.
fn css_sink_attr(name : String) -> Bool {
  name == "style" || @safecss.css_properties.contains(name)
}

///|
fn untrusted_sink_attr(name : String) -> Bool {
  match name.to_lower() {
    // Browser navigation and subresource fetches.
    "action"
    | "archive"
    | "background"
    | "code"
    | "codebase"
    | "data"
    | "dynsrc"
    | "formaction"
    | "href"
    | "imagesrcset"
    | "lowsrc"
    | "manifest"
    | "ping"
    | "poster"
    | "src"
    | "srcset"
    | "xlink:href"
    // CSS accepts url(...) in each of these SVG/HTML presentation sinks.
    | "background-image"
    | "clip-path"
    | "cursor"
    | "fill"
    | "filter"
    | "list-style"
    | "list-style-image"
    | "marker"
    | "marker-end"
    | "marker-mid"
    | "marker-start"
    | "mask"
    | "stroke"
    | "style" => true
    _ => false
  }
}

///|
/// The two places a URL is worth the argument, and the only two the
/// external-URL allowance reopens: a picture and a link.
///
/// Everything else on `untrusted_sink_attr` stays refused with the allowance
/// in place, and the list is short for a reason rather than for tidiness. An
/// `<iframe src>` is a document with its own script; a `<form action>` sends
/// what a person typed; `srcset` is a list, which is a rule with a parser in
/// it; the CSS sinks are a stylesheet's worth of surface behind one attribute.
/// A host that wants any of those wants a tier, not an allowance.
fn external_url_attr(tag : String, attr : String) -> Bool {
  (tag == "img" && attr == "src") || (tag == "a" && attr == "href")
}

///|
fn untrusted_sink_element(tag : String) -> Bool {
  match tag.to_lower() {
    // Embedded CSS and metadata/resource loaders.
    "applet"
    | "link"
    | "meta"
    | "style"
    // SMIL can assign a URL-bearing attribute after registration-time and
    // render-time attribute filters have both run.
    | "animate"
    | "animatemotion"
    | "animatetransform"
    | "set" => true
    _ => false
  }
}

///|
/// Why this CSS-valued attribute is refused, or `None` when it is not.
///
/// Two ways to fail. The value is not a literal, so nothing can read it; or it
/// is, and the policy did not admit what it says. The second carries the
/// validator's own reason, because "your `fill` was refused" and "your `fill`
/// pointed at another origin" are different things for an author to be told.
fn css_refusal(attr : String, val : @tutuca.Expr, policy : Policy) -> String? {
  let text = match val {
    ELit(lit=LStr(s), ..) => s
    // A number or a boolean in a CSS attribute is not CSS. Refused with the
    // same message as an expression, since neither is a value this can read.
    _ =>
      return Some(
        "a CSS value must be a literal here, since nothing checks it later",
      )
  }
  let result = if attr == "style" {
    policy.sanitizer.css.declarations(text)
  } else {
    policy.sanitizer.css.value_checked(attr, text)
  }
  if result.css is Some(_) && result.dropped.is_empty() {
    return None
  }
  match result.dropped.get(0) {
    Some(drop) => Some(drop.to_string())
    None => Some("no declaration survived")
  }
}

///|
/// Tailwind/margaui bracket syntax is guest-authored CSS, including url(...).
fn has_arbitrary_css(val : @tutuca.Expr) -> Bool {
  fn fragment_is_arbitrary(s : String) -> Bool {
    s.contains("[") || s.contains("]")
  }

  match val {
    ELit(lit=LStr(s), ..) => fragment_is_arbitrary(s)
    ETpl(parts~, ..) =>
      parts.any(part => {
        match part {
          TText(text~, ..) => fragment_is_arbitrary(text)
          TExpr(inner) => has_arbitrary_css(inner)
        }
      })
    _ => false
  }
}

///|
fn class_lit_has_arbitrary_css(lit : @tutuca.Lit) -> Bool {
  lit is LStr(s) && (s.contains("[") || s.contains("]"))
}

///|
fn check_untrusted_attrs(
  where_ : String,
  d : @anode.DomData,
  out : Array[Rejection],
  policy : Policy,
) -> Unit {
  let tag = d.tag.to_lower()
  // `vals` is what the attribute would set — one expression usually, two for
  // an `@if.` attribute, and a `None` for a branch that sets nothing. The sink
  // rule never needed them (a name is a name); the external-URL rule does,
  // being a rule about where the value POINTS, read off the literal part of
  // it. See external_url.mbt.
  fn check_name(name : String, vals : Array[@tutuca.Expr?]) {
    let lower = name.to_lower()
    if lower == "is" {
      out.push(
        rejection(
          where_,
          "untrusted views may not use 'is' on <\{d.tag}>; customized built-in elements run host-registered code",
        ),
      )
    } else if untrusted_sink_attr(lower) {
      if external_url_attr(tag, lower) {
        for val in vals {
          guard val is Some(v) else { continue }
          if policy.external_url_refusal(v) is Some(why) {
            out.push(
              rejection(
                where_,
                "untrusted views may not use '\{name}' on <\{d.tag}>: \{why}",
              ),
            )
          }
        }
      } else if css_sink_attr(lower) {
        // A CSS-valued attribute is read rather than refused — but only when
        // the view STATES the value, which is the same shape the external-URL
        // rule reads an origin off. A dynamic one stays refused,
        // and the reason is not caution: `check_view` runs at registration and
        // the host installs `@filter.Baseline`, which carries no CSS
        // rule, so there is nothing downstream that would ever look at the
        // value this pass could not see. Admitting it here would be admitting
        // it unchecked.
        for val in vals {
          guard val is Some(v) else { continue }
          match css_refusal(lower, v, policy) {
            Some(why) =>
              out.push(
                rejection(
                  where_,
                  "untrusted views may not use '\{name}' on <\{d.tag}>: \{why}",
                ),
              )
            None => ()
          }
        }
      } else {
        out.push(
          rejection(
            where_,
            "untrusted views may not use network/CSS sink attribute '\{name}' on <\{d.tag}>",
          ),
        )
      }
    }
  }

  fn check_class(val : @tutuca.Expr) {
    if has_arbitrary_css(val) {
      out.push(
        rejection(
          where_, "untrusted views may not use bracketed arbitrary utility classes; they are guest-authored CSS",
        ),
      )
    }
  }

  match d.attrs {
    ConstAttrs(attrs) =>
      for name, lit in attrs {
        // A constant attribute IS a pinned value, which is the case the
        // external-URL rule is friendliest to; it reaches the same rule as
        // the dynamic one by wearing the shape the rule reads.
        check_name(name, [Some(@tutuca.Expr::lit(lit))])
        if name.to_lower() == "class" && class_lit_has_arbitrary_css(lit) {
          out.push(
            rejection(
              where_, "untrusted views may not use bracketed arbitrary utility classes; they are guest-authored CSS",
            ),
          )
        }
      }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name~, val~) | ConstA(name~, val~) => {
            check_name(name, [Some(val)])
            if name.to_lower() == "class" {
              check_class(val)
            }
          }
          If(attr) => {
            // Both branches are the attribute, so both have to be a URL this
            // host would allow; an unset branch sets nothing.
            check_name(attr.name, [attr.then_val, attr.else_val])
            if attr.name.to_lower() == "class" {
              match attr.then_val {
                Some(val) => check_class(val)
                None => ()
              }
              match attr.else_val {
                Some(val) => check_class(val)
                None => ()
              }
            }
          }
          RawMarkdown(_) =>
            out.push(
              rejection(
                where_, "untrusted views may not render runtime Markdown because it can synthesize network-bearing elements",
              ),
            )
          // The same rejection, for the same reason, and it is worth saying why
          // "but the sanitizer checks every element it builds" is not an
          // answer here. It is the answer for a plain app, and it is why Pass 1
          // waves these through. This walk is about something narrower: an
          // `<img src>` the sanitizer is perfectly happy with is still a GET to
          // an origin the guest chose, from the host's page, and the whole
          // point of the Untrusted tier is that the guest does not get to make
          // that request. Every sink this file refuses by name is a sink a
          // runtime payload can synthesize, so the payload has to go.
          SafeHtml(_) =>
            out.push(
              rejection(
                where_, "untrusted views may not render runtime HTML because it can synthesize network-bearing elements",
              ),
            )
          SafeSvg(_) =>
            out.push(
              rejection(
                where_, "untrusted views may not render runtime SVG because it can synthesize network-bearing elements",
              ),
            )
          // Avoid duplicating the baseline sanitizer's rejection. If a host
          // loosens that sanitizer, Untrusted still cannot use the construct:
          // its dynamic payload could synthesize every sink checked here.
          RawHtml(_) =>
            if policy.sanitizer.raw_markup {
              out.push(
                rejection(
                  where_, "untrusted views may not render runtime HTML because it can synthesize network-bearing elements",
                ),
              )
            }
        }
      }
  }
}

///|
fn visit_untrusted_view(
  where_ : String,
  node : @anode.ANode,
  out : Array[Rejection],
  policy : Policy,
) -> Unit {
  match node {
    Dom(d) => {
      if untrusted_sink_element(d.tag) {
        out.push(
          rejection(
            where_,
            "untrusted views may not create <\{d.tag}> because it can load or synthesize external content",
          ),
        )
      }
      check_untrusted_attrs(where_, d, out, policy)
      for child in d.childs {
        visit_untrusted_view(where_, child, out, policy)
      }
    }
    Fragment(d) =>
      for child in d.childs {
        visit_untrusted_view(where_, child, out, policy)
      }
    Show(d) | Hide(d) | PushView(d) | Scope(d) =>
      visit_untrusted_view(where_, d.node, out, policy)
    Slot(d) => visit_untrusted_view(where_, d.node, out, policy)
    Each(d) => visit_untrusted_view(where_, d.node, out, policy)
    // The macro body belongs to its host-side definition, and this walk keeps
    // its hands off it: the body is the host's own markup, and a host that
    // registered a macro vouched for what is in it.
    //
    // What the GUEST supplies to that body is a different thing, and both
    // halves of it are here. Slots are subtrees and are checked as any other
    // guest markup would be, even though the generic child walker deliberately
    // does not traverse them. Arguments are strings the body substitutes
    // wherever `^name` appears — a sink included — so each is judged for the
    // worst place it could land.
    MacroCall(d) => {
      for name, raw in d.attrs {
        if policy.macro_arg_refusal(raw) is Some(why) {
          out.push(
            rejection(
              where_,
              "untrusted views may not pass '\{name}' to <x:\{d.name}>: \{why}",
            ),
          )
        }
      }
      for _, slot in d.slots {
        visit_untrusted_view(where_, slot, out, policy)
      }
    }
    Text(_) | Comment(_) | RenderText(_) | Render(_) | RenderIt(_) => ()
  }
}

///|
fn Policy::check_untrusted_view_authority(
  self : Policy,
  where_ : String,
  tree : @anode.ANode,
) -> Array[Rejection] {
  if self.tier != Untrusted {
    return []
  }
  let out : Array[Rejection] = []
  visit_untrusted_view(where_, tree, out, self)
  out
}

///|
/// Whether an `@on` argument's `e.<path>` may go where it says, under this
/// policy's event-path profile.
///
/// The SAFE profile is the default here — in every tier, because views are
/// data whoever shipped them, and an off-list traversal step is ambient
/// authority no guest declared (SECURITY.md §9). A rejection names the step and
/// its index, so a guest author is told "not allowed to go that far" rather
/// than "wrong from the start", and points at the intent channel, which is
/// the way to ask the host for what a path must not take.
///
/// This runs at REGISTRATION, over the same shadow parse `screen_view`
/// lints: refusing here means a bundle that would silently read `Null` every
/// dispatch never renders at all. The runtime resolver holds the SAME profile
/// (the bridge hands it to its app), which is the second fence, not a
/// disagreement waiting to happen.
pub fn Policy::check_event_paths(
  self : Policy,
  where_ : String,
  events : Array[@anode.NodeEvents],
) -> Array[Rejection] {
  if self.event_paths is Open {
    return []
  }
  let out : Array[Rejection] = []
  for ev in events {
    for h in ev.handlers {
      for arg in h.handler.args {
        guard arg is EEventPath(segments~, ..) else { continue }
        guard @eventpath.EventPathProfile::allows(Safe, segments)
          is BadStep(step~, index~) else {
          continue
        }
        out.push(
          rejection(
            where_,
            "this host's event-path policy refuses '\{step}' (at \{index}) in 'e." +
            segments.join(".") +
            "'; an event path may only go through target/currentTarget/relatedTarget/detail/dataset/dataTransfer — ask the host with an intent instead",
          ),
        )
      }
    }
  }
  out
}

///|
/// The same policy, with guest-supplied views' event paths OPENED.
///
/// The deliberate counterpart to the safe default: a host that decides its
/// page has no authority worth fencing — or that vouches for its bundles the
/// way an author vouches for their own views — says so HERE rather than by
/// editing the allowlist. Like every loosening in this file, it applies to
/// loads, so bundles already registered keep the answer they were screened
/// under.
pub fn Policy::with_open_event_paths(self : Policy) -> Policy {
  { ..self, event_paths: Open, }
}
