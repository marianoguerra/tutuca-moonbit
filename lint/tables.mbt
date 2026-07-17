// WHATWG HTML §13 spec-derived data tables (tools/core/htmllinter-tables.js).
// All sets are lowercase except the SVG/MathML camel maps, which preserve case
// because they exist precisely to detect case-correction by the parser.

///|
let void_elements : Set[String] = Set::from_array([
  "area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source",
  "track", "wbr",
])

///|
let raw_text_elements : Set[String] = Set::from_array([
  "script", "style", "iframe", "noembed", "noframes", "noscript", "xmp", "plaintext",
])

///|
/// §13.2.4.2 "Special" — trimmed of document-only entries (html, head, body,
/// frame, frameset).
let special_elements : Set[String] = Set::from_array([
  "address", "applet", "area", "article", "aside", "base", "basefont", "bgsound",
  "blockquote", "br", "button", "caption", "center", "col", "colgroup", "dd", "details",
  "dir", "div", "dl", "dt", "embed", "fieldset", "figcaption", "figure", "footer",
  "form", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hgroup", "hr", "iframe",
  "img", "input", "keygen", "li", "link", "listing", "main", "marquee", "menu", "meta",
  "nav", "noembed", "noframes", "noscript", "object", "ol", "p", "param", "plaintext",
  "pre", "script", "search", "section", "select", "source", "style", "summary", "table",
  "tbody", "td", "template", "textarea", "tfoot", "th", "thead", "title", "tr", "track",
  "ul", "wbr", "xmp",
])

///|
/// §13.2.5 — participate in the active-formatting list / adoption agency.
let formatting_elements : Set[String] = Set::from_array([
  "a", "b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong",
  "tt", "u",
])

///|
/// "have an element in scope" boundary elements (§13.2.4.2 default set).
let scope_default : Set[String] = Set::from_array([
  "applet", "caption", "html", "table", "td", "th", "marquee", "object", "select",
  "template",
])

///|
let scope_button : Set[String] = Set::from_array([
  "applet", "caption", "html", "table", "td", "th", "marquee", "object", "select",
  "template", "button",
])

///|
let scope_table : Set[String] = Set::from_array(["html", "table", "template"])

///|
/// Lowercased integration-point names (foreign frames store lowercased names).
let mathml_text_integration_point_names : Set[String] = Set::from_array([
  "mi", "mo", "mn", "ms", "mtext",
])

///|
let svg_html_integration_point_names : Set[String] = Set::from_array([
  "foreignobject", "desc", "title",
])

///|
/// §13.2.6.5 — SVG element names the parser case-corrects; anything else
/// with uppercase gets lowercased.
let standard_svg_camel_elements : Set[String] = Set::from_array([
  "altGlyph", "altGlyphDef", "altGlyphItem", "animateColor", "animateMotion", "animateTransform",
  "clipPath", "feBlend", "feColorMatrix", "feComponentTransfer", "feComposite", "feConvolveMatrix",
  "feDiffuseLighting", "feDisplacementMap", "feDistantLight", "feDropShadow", "feFlood",
  "feFuncA", "feFuncB", "feFuncG", "feFuncR", "feGaussianBlur", "feImage", "feMerge",
  "feMergeNode", "feMorphology", "feOffset", "fePointLight", "feSpecularLighting",
  "feSpotLight", "feTile", "feTurbulence", "foreignObject", "glyphRef", "linearGradient",
  "radialGradient", "textPath",
])

///|
let standard_svg_camel_attrs : Array[String] = [
  "attributeName", "attributeType", "baseFrequency", "baseProfile", "calcMode", "clipPathUnits",
  "diffuseConstant", "edgeMode", "filterUnits", "glyphRef", "gradientTransform",
  "gradientUnits", "kernelMatrix", "kernelUnitLength", "keyPoints", "keySplines",
  "keyTimes", "lengthAdjust", "limitingConeAngle", "markerHeight", "markerUnits",
  "markerWidth", "maskContentUnits", "maskUnits", "numOctaves", "pathLength", "patternContentUnits",
  "patternTransform", "patternUnits", "pointsAtX", "pointsAtY", "pointsAtZ", "preserveAlpha",
  "preserveAspectRatio", "primitiveUnits", "refX", "refY", "repeatCount", "repeatDur",
  "requiredExtensions", "requiredFeatures", "specularConstant", "specularExponent",
  "spreadMethod", "startOffset", "stdDeviation", "stitchTiles", "surfaceScale", "systemLanguage",
  "tableValues", "targetX", "targetY", "textLength", "viewBox", "xChannelSelector",
  "yChannelSelector", "zoomAndPan",
]

///|
let mathml_camel_attrs : Array[String] = ["definitionURL"]

///|
/// lowercased name → canonical camelCase form (built once).
let svg_attr_lowercase_to_camel : Map[String, String] = {
  let m : Map[String, String] = {}
  for camel in standard_svg_camel_attrs {
    m[camel.to_lower()] = camel
  }
  m
}

///|
let mathml_attr_lowercase_to_camel : Map[String, String] = {
  let m : Map[String, String] = {}
  for camel in mathml_camel_attrs {
    m[camel.to_lower()] = camel
  }
  m
}

///|
/// §13.2.6.5 HTML breakout from foreign content.
let foreign_breakout_tags : Set[String] = Set::from_array([
  "b", "big", "blockquote", "body", "br", "center", "code", "dd", "div", "dl", "dt",
  "em", "embed", "h1", "h2", "h3", "h4", "h5", "h6", "head", "hr", "i", "img", "li",
  "listing", "menu", "meta", "nobr", "ol", "p", "pre", "ruby", "s", "small", "span",
  "strong", "strike", "sub", "sup", "table", "tt", "u", "ul", "var",
])

///|
/// Tags that close a <select> when opened in select mode.
let select_breakout_tags : Set[String] = Set::from_array([
  "input", "keygen", "textarea", "select",
])

///|
let table_scope_tags : Set[String] = Set::from_array([
  "caption", "colgroup", "thead", "tbody", "tfoot", "tr", "td", "th", "table",
])

///|
let table_body_cell_tags : Set[String] = Set::from_array(["td", "th"])

///|
/// Table-structural start tags that end the current caption/cell and
/// reprocess in the table (§13.2.6.4.11 "in caption", §13.2.6.4.15 "in
/// cell") — the same list in both modes.
let caption_cell_breakout_tags : Set[String] = Set::from_array([
  "caption", "col", "colgroup", "tbody", "td", "tfoot", "th", "thead", "tr",
])

///|
/// §13.2.6.4.7 "generate implied end tags": these pop silently, without
/// HTML_UNCLOSED_BEFORE_END.
let implied_end_tags : Set[String] = Set::from_array([
  "dd", "dt", "li", "optgroup", "option", "p", "rb", "rp", "rt", "rtc",
])
