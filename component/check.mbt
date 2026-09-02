// The name-wiring checks: what a component published, what it asked for, and
// whether the two can find each other.
//
// They live here rather than in `lint` for the reason `lint/spec.mbt` gives —
// a component-model rule needs the component layer, which lint does not
// import. lint owns the CODES and the wording; this owns the walk.
//
// Every one of them answers a question `compile()` deliberately does not: a
// bad declaration is dropped there rather than raised, because what is wrong
// with it is a finding with a name and a place to point at, and a component
// whose views are otherwise fine should still render while the list is read.

///|
fn name_finding(
  code : @lint.LintCode,
  level : @lint.LintLevel,
  info : Array[(String, String)],
) -> @lint.Finding {
  { code, level, info, location: None, suggestion: None, }
}

///|
/// Check every component registered in this scope and the scopes below it.
///
/// Run it after `compile_all`: the checks read the COMPILED `provide` and
/// `lookup`, and half of what they report is precisely the difference between
/// what was written and what survived compilation.
pub fn ComponentStack::check_names(
  self : ComponentStack,
) -> Array[@lint.Finding] {
  let out : Array[@lint.Finding] = []
  for _, comp in self.by_name {
    comp.check_provides(out)
    comp.check_lookups(out)
    comp.check_event_handlers(out)
    match comp.scope {
      Some(inner) => out.append(inner.check_names())
      None => ()
    }
  }
  out
}

///|
/// What this component publishes: addressable values, and types that are
/// `"self"`.
fn Component::check_provides(
  self : Component,
  out : Array[@lint.Finding],
) -> Unit {
  for pname, src in self.raw_provide {
    // `"self"` is the only value an uppercase key can take, which is what
    // makes a published type a component by construction. `provide_kind`
    // (`spec.mbt`) is where that rule lives; `compile` drops what it calls
    // malformed and this is where the same reading is said out loud.
    match provide_kind(pname, src~) {
      ProvideSelfType => continue
      ProvideBadType => {
        out.push(
          name_finding(ProvideTypeBadShape, Error, [
            ("comp", self.name),
            ("name", pname),
            ("value", src),
          ]),
        )
        continue
      }
      ProvideValue => ()
    }
    // Present in what was written and absent from what compiled means the
    // value did not parse as an addressable path.
    if !self.provide.contains(pname) {
      out.push(
        name_finding(ProvideNotAddressable, Error, [
          ("comp", self.name),
          ("name", pname),
          ("value", src),
        ]),
      )
    }
  }
}

///|
/// What this component's COMPILED views put in an `@on` position.
///
/// The generator refuses a `$name` there while compiling a view file
/// (`METHOD_IN_EVENT`). A view that arrives at RUNTIME never meets it — a
/// macro expanded by `ComponentStack`, a guest's manifest — so the same rule
/// runs here, over the tree the expander actually produced, and reports rather
/// than raises for the reason this file's header gives.
///
/// The rule itself is `@anode.NodeEvent::method_in_event`: one expander, one
/// refusal, read by both checkers.
fn Component::check_event_handlers(
  self : Component,
  out : Array[@lint.Finding],
) -> Unit {
  for _, view in self.views {
    guard view.ctx is Some(ctx) else { continue }
    for hit in @anode.methods_in_events(ctx.events) {
      out.push(
        name_finding(MethodInEventPosition, Error, [
          ("comp", self.name),
          ("name", hit.0),
          ("site", hit.1),
        ]),
      )
    }
  }
}

///|
/// What this component asks for, and whether its scope can supply it.
fn Component::check_lookups(
  self : Component,
  out : Array[@lint.Finding],
) -> Unit {
  guard self.scope is Some(scope) else { return }
  for spec in self.raw_lookup {
    let name = spec.name
    if @tutuca.is_type_name(name) {
      if scope.lookup_component(name) is None {
        let closest = @lint.closest_name(name, scope.component_names())
        out.push(
          name_finding(UnknownComponentName, Error, [
            ("comp", self.name),
            ("name", name),
            ("closest", closest.unwrap_or("")),
          ]),
        )
      }
      continue
    }
    if !scope.has_provider(name) && scope.lookup_path(name) is None {
      // Whether a provider is actually ABOVE this component when it renders is
      // a runtime fact no checker can settle, so a declared default makes this
      // advice rather than an error: the default is what every read gets, and
      // saying so is the useful part.
      let has_default = spec.default is Some(_)
      out.push(
        name_finding(LookupNoProvider, if has_default { Hint } else { Error }, [
          ("comp", self.name),
          ("name", name),
          ("hasDefault", if has_default { "true" } else { "false" }),
        ]),
      )
    }
  }
}

///|
/// Every name registered along this chain, innermost first — the candidate
/// list a "did you mean" is drawn from.
pub fn ComponentStack::component_names(self : ComponentStack) -> Array[String] {
  let out : Array[String] = []
  for frame = Some(self) {
    match frame {
      Some(s) => {
        for n, _ in s.by_name {
          out.push(n)
        }
        continue s.parent
      }
      None => break
    }
  }
  out
}
