// The baseline, which is applied whatever else a config says.

///|
/// The elements the spec calls XSS-unsafe, in the namespaces anode can
/// express.
///
/// This exact list and no editorializing on it: `base`, `embed`, `frame`,
/// `iframe`, `object`, `script`, and SVG's `use` — which is here because
/// `<use href="…">` pulls in a subtree from elsewhere, the same capability as
/// an include.
pub let unsafe_elements : Array[ElementName] = [
  html("base"),
  html("embed"),
  html("frame"),
  html("iframe"),
  html("object"),
  html("script"),
  svg("use"),
]

///|
/// An event-handler content attribute, by the `on` prefix.
///
/// The spec enumerates them (`onafterprint`, `onbeforeinput`, …). A prefix test
/// is a superset of that enumeration and cannot fall behind it as the platform
/// adds handlers, which for a REMOVE rule is the safe direction to be wrong in.
/// No non-handler attribute in HTML, SVG or MathML begins with `on`.
pub fn is_event_handler_attr(name : String) -> Bool {
  name is ['o' | 'O', 'n' | 'N', _, ..]
}

///|
/// Whether the baseline alone refuses this element, whatever a config says.
fn is_unsafe_element(key : String) -> Bool {
  unsafe_element_keys.contains(key)
}

///|
let unsafe_element_keys : @set.Set[String] = @set.Set::from_array(
  unsafe_elements.map(ElementName::key),
)

///|
/// The config a host gets by asking for nothing: the empty config.
///
/// The BASELINE is not in here, and that is the spec's shape rather than an
/// omission. Safety in the Sanitizer API comes from the entry point, not from
/// the config: `setHTML()` applies unsafe-removal on top of whatever config it
/// is handed, so a config that allows `script` still does not get `script`.
/// `Sanitizer` here has only the safe entry point — there is no
/// `setHTMLUnsafe` analogue and no reason to build one for a host rendering
/// views it did not write — so the baseline is unconditional and a config's
/// job is only to narrow further.
///
/// What this is NOT is the spec's *default configuration*, which is a large
/// allow-list of elements with per-element attributes. That list is worth
/// having and is not transcribed yet: it has to come from the specification
/// text rather than a summary of it, because an allow-list that quietly lost an
/// entry is a component that mysteriously fails to render, and one that quietly
/// gained an entry is a hole. Until then a host that wants an allow-list
/// supplies one and gets `validate()` to keep it honest.
pub fn SanitizerConfig::default() -> SanitizerConfig {
  SanitizerConfig::empty()
}

///|
/// The baseline as a sanitizer: everything except the unsafe elements, the
/// event handlers, comments, `data-*` and raw markup.
///
/// Constructed directly rather than through `new`, because the empty config
/// cannot be invalid and this way the constructor's `raise` does not
/// propagate to every caller that wants the default.
pub fn Sanitizer::default() -> Sanitizer {
  {
    allow_elements: None,
    remove_elements: @set.Set::from_array([]),
    replace_with_children: @set.Set::from_array([]),
    allow_attributes: None,
    remove_attributes: @set.Set::from_array([]),
    // Kept — see `Sanitizer::new`. The baseline is the unsafe elements and the
    // event handlers, and nothing else.
    comments: true,
    data_attributes: false,
    raw_markup: false,
  }
}
