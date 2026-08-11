///| Registration-time authority checks for views from an untrusted bundle.
///
/// The Sanitizer API model answers whether a NAME is safe to put in a DOM
/// tree. This answers a narrower dyncomp question: whether that name gives a
/// guest a browser-managed route out of its wasm sandbox. Values may be
/// dynamic, so sink attributes are refused by name instead of trying to
/// validate only the literals visible now.

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
/// Tailwind/margaui bracket syntax is guest-authored CSS, including url(...).
fn has_arbitrary_css(val : @tutuca.Val) -> Bool {
  fn fragment_is_arbitrary(s : String) -> Bool {
    s.contains("[") || s.contains("]")
  }

  match val {
    Const(lit=LStr(s), ..) => fragment_is_arbitrary(s)
    StrTpl(parts) =>
      parts.any(part => {
        part is Some(Const(lit=LStr(s), ..)) && fragment_is_arbitrary(s)
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
  out : Array[Refusal],
  sanitizer_allows_raw_markup : Bool,
) -> Unit {
  fn check_name(name : String) {
    let lower = name.to_lower()
    if lower == "is" {
      out.push(
        refusal(
          where_,
          "untrusted views may not use 'is' on <\{d.tag}>; customized built-in elements run host-registered code",
        ),
      )
    } else if untrusted_sink_attr(lower) {
      out.push(
        refusal(
          where_,
          "untrusted views may not use network/CSS sink attribute '\{name}' on <\{d.tag}>",
        ),
      )
    }
  }

  fn check_class(val : @tutuca.Val) {
    if has_arbitrary_css(val) {
      out.push(
        refusal(
          where_, "untrusted views may not use bracketed arbitrary utility classes; they are guest-authored CSS",
        ),
      )
    }
  }

  match d.attrs {
    ConstAttrs(attrs) =>
      for name, lit in attrs {
        check_name(name)
        if name.to_lower() == "class" && class_lit_has_arbitrary_css(lit) {
          out.push(
            refusal(
              where_, "untrusted views may not use bracketed arbitrary utility classes; they are guest-authored CSS",
            ),
          )
        }
      }
    DynAttrs(items) =>
      for item in items {
        match item {
          Plain(name~, val~) | ConstA(name~, val~) => {
            check_name(name)
            if name.to_lower() == "class" {
              check_class(val)
            }
          }
          If(attr) => {
            check_name(attr.name)
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
              refusal(
                where_, "untrusted views may not render runtime Markdown because it can synthesize network-bearing elements",
              ),
            )
          // Avoid duplicating the baseline sanitizer's refusal. If a host
          // loosens that sanitizer, Untrusted still cannot use the construct:
          // its dynamic payload could synthesize every sink checked here.
          RawHtml(_) =>
            if sanitizer_allows_raw_markup {
              out.push(
                refusal(
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
  out : Array[Refusal],
  sanitizer_allows_raw_markup : Bool,
) -> Unit {
  match node {
    Dom(d) => {
      if untrusted_sink_element(d.tag) {
        out.push(
          refusal(
            where_,
            "untrusted views may not create <\{d.tag}> because it can load or synthesize external content",
          ),
        )
      }
      check_untrusted_attrs(where_, d, out, sanitizer_allows_raw_markup)
      for child in d.childs {
        visit_untrusted_view(where_, child, out, sanitizer_allows_raw_markup)
      }
    }
    Fragment(d) =>
      for child in d.childs {
        visit_untrusted_view(where_, child, out, sanitizer_allows_raw_markup)
      }
    Show(d) | Hide(d) | PushView(d) | Scope(d) =>
      visit_untrusted_view(where_, d.node, out, sanitizer_allows_raw_markup)
    Slot(d) =>
      visit_untrusted_view(where_, d.node, out, sanitizer_allows_raw_markup)
    Each(d) =>
      visit_untrusted_view(where_, d.node, out, sanitizer_allows_raw_markup)
    // The macro body belongs to its host-side definition. Slots belong to the
    // guest call site and must be checked even though the generic child walker
    // deliberately does not traverse them.
    MacroCall(d) =>
      for _, slot in d.slots {
        visit_untrusted_view(where_, slot, out, sanitizer_allows_raw_markup)
      }
    Text(_) | Comment(_) | RenderText(_) | Render(_) | RenderIt(_) => ()
  }
}

///|
fn Policy::check_untrusted_view_authority(
  self : Policy,
  where_ : String,
  tree : @anode.ANode,
) -> Array[Refusal] {
  if self.tier != Untrusted {
    return []
  }
  let out : Array[Refusal] = []
  visit_untrusted_view(where_, tree, out, self.sanitizer.raw_markup)
  out
}
