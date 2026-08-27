///| The spec's validity relation, which is the part of the config model that is
/// easiest to skip and hardest to notice missing.
///
/// A config that breaks one of these rules does not describe one sanitizer, and
/// two implementations reading it would disagree about what it permits. Since
/// the whole reason to port the spec's shape rather than invent an allowlist is
/// that the same config can later be handed to a real `Element.setHTML()`, a
/// config this package accepts and the platform rejects would give that away.

///|
fn errs(cfg : SanitizerConfig) -> Array[String] {
  cfg.validate().map(ConfigError::to_string)
}

///|
test "the empty config is valid, and so is the default" {
  debug_inspect(errs(SanitizerConfig::empty()), content="[]")
  debug_inspect(errs(SanitizerConfig::default()), content="[]")
}

///|
test "an allow list and a remove list are mutually exclusive" {
  debug_inspect(
    errs({
      ..SanitizerConfig::empty(),
      elements: Some([ElementRule::of(html("div"))]),
      remove_elements: Some([html("script")]),
      attributes: Some(["class"]),
      remove_attributes: Some(["style"]),
    }),
    content=(
      #|[
      #|  "config sets both elements and remove_elements; the spec allows one or the other",
      #|  "config sets both attributes and remove_attributes; the spec allows one or the other",
      #|]
    ),
  )
}

///|
test "duplicates and overlaps" {
  debug_inspect(
    errs({
      ..SanitizerConfig::empty(),
      elements: Some([
        ElementRule::of(html("div")),
        ElementRule::of(html("DIV")),
      ]),
      replace_with_children_elements: Some([
        html("div"),
        html("span"),
        html("span"),
      ]),
    }),
    content=(
      #|[
      #|  "elements lists 'div' twice",
      #|  "replace_with_children_elements lists 'span' twice",
      #|  "'div' is in replace_with_children_elements and in elements",
      #|]
    ),
  )
}

///|
/// With a global allowlist, an element rule may only NARROW it — an element
/// that removes something never globally allowed is saying nothing, and an
/// element that allows something already global is saying it twice. Both are
/// mistakes worth surfacing rather than tolerating.
test "per-element rules against the global lists" {
  debug_inspect(
    errs({
      ..SanitizerConfig::empty(),
      elements: Some([
        {
          elem: html("a"),
          attributes: Some(["class"]),
          remove_attributes: Some(["title"]),
        },
        {
          elem: html("p"),
          attributes: None,
          remove_attributes: Some(["href"]),
        },
      ]),
      attributes: Some(["class", "title"]),
    }),
    content=(
      #|[
      #|  "element 'a' sets both attributes and remove_attributes",
      #|  "element 'a' allows 'class', which is already globally allowed",
      #|  "element 'p' removes 'href', which the global attributes list does not allow",
      #|]
    ),
  )
}

///|
/// `dataAttributes` says the same thing a `data-*` entry in a list says, so the
/// two together are a config whose author meant one of them. With a global
/// remove list it cannot be written at all — defined, not merely true, since
/// `false` there would read as meaningful and is not.
test "dataAttributes interacts with every list" {
  debug_inspect(
    errs({
      ..SanitizerConfig::empty(),
      attributes: Some(["data-role"]),
      data_attributes: Some(true),
    }),
    content=(
      #|["'data-role' is listed while data_attributes is true; the two disagree"]
    ),
  )
  debug_inspect(
    errs({
      ..SanitizerConfig::empty(),
      remove_attributes: Some(["style"]),
      data_attributes: Some(false),
    }),
    content=(
      #|["data_attributes cannot be set alongside a global remove_attributes"]
    ),
  )
}

///|
/// An invalid config is a mistake in the HOST, not something a guest can
/// provoke, so it fails at construction rather than degrading into a sanitizer
/// that permits more than its author meant.
test "an invalid config does not compile into a sanitizer" {
  let bad : SanitizerConfig = {
    ..SanitizerConfig::empty(),
    elements: Some([ElementRule::of(html("div"))]),
    remove_elements: Some([html("script")]),
  }
  let e : InvalidConfig = @test.expect_error(() => Sanitizer::new(bad) |> ignore)
  inspect(
    e.to_string(),
    content="config sets both elements and remove_elements; the spec allows one or the other",
  )
}
