///|
/// Property names that exist on DOM nodes but whose setters misbehave for our
/// purposes (mirrors preact/src/diff/props.js setProperty). Forces
/// set_attribute.
fn never_assign(name : String) -> Bool {
  name
  is ("width"
  | "height"
  | "href"
  | "list"
  | "form"
  | "tabIndex"
  | "download"
  | "rowSpan"
  | "colSpan"
  | "role"
  | "popover")
}

///|
/// IDL property names whose reflected attribute is named differently; needed
/// when removal goes through the property path so the attribute is dropped
/// too.
fn prop_attr_name(name : String) -> String {
  match name {
    "className" => "class"
    "htmlFor" => "for"
    _ => name
  }
}

///|
/// Route a single attribute. Borrowed from preact: prefer IDL property
/// assignment when the name exists on the node (it reflects to the
/// attribute), otherwise use set_attribute. Lowercase HTML attributes whose
/// IDL property is camelCase (`tabindex` → `tabIndex`, `readonly` →
/// `readOnly`, …) fail the `has_property` check and fall through to
/// set_attribute, which is the correct path. `value : None` is the JS
/// `undefined` (removal).
fn[N : DomNode] set_prop(
  node : N,
  name : String,
  value : AttrValue?,
  namespaced : Bool,
) -> Unit {
  if name == "dangerouslySetInnerHTML" {
    match value {
      None => node.replace_children()
      Some(v) => {
        // JS reads value.__html ?? "" — a non-Html value yields "".
        let html = if v is Html(html) { html } else { "" }
        // Skip the re-parse when the markup is identical (preact does the
        // same).
        if html != node.get_inner_html() {
          node.set_inner_html(html)
        }
      }
    }
    return
  }
  // Structured values are properties by definition — assign without the
  // `name in node` gate. JS routes them through the gate, but that only
  // differs pre-upgrade or on authoring mistakes (a list bound to a plain
  // attribute): here the object property is always assigned, which also
  // spares memdom a custom-element registry.
  if value is Some(Data(_) as v) {
    ignore(node.set_property(name, v))
    return
  }
  let uses_prop = !namespaced && !never_assign(name) && node.has_property(name)
  if uses_prop && value is Some(v) {
    if node.set_property(name, v) {
      return
    }
  }
  // `data-*` / `aria-*` preserve a literal "false" since it's semantically
  // distinct from the attribute being absent; everything else removes.
  let false_removes = value is Some(Bool(false)) &&
    !(name.get_char(4) is Some('-'))
  if value is None || false_removes {
    if uses_prop {
      // Reset the live IDL state first — remove_attribute alone can't clear
      // non-reflected properties like `value` / `checked` — then drop the
      // attribute too, since reflected properties (`className`, `id`, …)
      // would otherwise keep an empty attribute that a fresh render of the
      // same vnode never creates.
      ignore(node.set_property(name, Str("")))
      node.remove_attribute(prop_attr_name(name))
    } else {
      node.remove_attribute(name)
    }
  } else if value is Some(v) {
    node.set_attribute(name, v.to_attr_string())
  }
}

///|
fn[N : DomNode] apply_properties(
  node : N,
  props : Map[String, AttrValue],
) -> Unit {
  let namespaced = is_namespaced(node)
  for name, value in props {
    set_prop(node, name, Some(value), namespaced)
  }
}

///|
/// `value` and `checked` must be applied AFTER siblings/children, so that
/// (a) <input min=… max=… value=…> clamps the value against the final range,
/// (b) <select><option> diff completes before we tell the select which
///     option should be selected.
fn[N : DomNode] apply_value_last(node : N, value : AttrValue?) -> Unit {
  // <progress value=0> via the IDL setter is treated as indeterminate;
  // force the attribute path so the bar shows 0% instead of unknown.
  let progress_zero = match value {
    None => true
    Some(Num(d)) => d == 0.0
    _ => false
  }
  if node.tag_name() == "PROGRESS" && progress_zero {
    node.remove_attribute("value")
  } else {
    set_prop(node, "value", value, is_namespaced(node))
  }
}

///|
fn[N : DomNode] append_child_nodes(
  parent : N,
  childs : Array[Vdom],
  opts : RenderOpts[N],
) -> Unit {
  for child in childs {
    parent.append_child(to_dom(child, opts))
  }
}

///|
/// Create a fresh DOM subtree for a vnode.
pub fn[N : DomNode] to_dom(vnode : Vdom, opts : RenderOpts[N]) -> N {
  let doc = opts.document
  match vnode {
    Text(s) => doc.create_text(s)
    Comment(s) => doc.create_comment(s)
    Fragment(childs) => {
      let frag = doc.create_fragment()
      append_child_nodes(frag, childs, opts)
      frag
    }
    Node(el) => {
      let ns = effective_ns(el, opts)
      // h() uppercases all-lowercase HTML tags for cheap identity
      // comparisons. When the inherited namespace says we're really inside
      // SVG/MathML, undo that normalization so creation uses the spec-cased
      // local name (`rect`, not `RECT`). Mixed-case tags (linearGradient,
      // foreignObject) are already preserved by h() and pass through here
      // untouched.
      let tag = if ns is Some(_) && el.tag == el.tag.to_upper() {
        el.tag.to_lower()
      } else {
        el.tag
      }
      // `is` opts customised built-in elements (e.g. <button is="x-cool">).
      // Must be passed at construction time; set_attribute later does NOT
      // upgrade.
      let is_attr = match el.attrs.get("is") {
        Some(v) => Some(v.to_attr_string())
        None => None
      }
      let node = doc.create_element(tag, ns, is_attr)
      let c_opts = child_opts(el, ns, opts)
      if el.attrs.contains("value") || el.attrs.contains("checked") {
        let namespaced = is_namespaced(node)
        for name, value in el.attrs {
          if name != "value" && name != "checked" {
            set_prop(node, name, Some(value), namespaced)
          }
        }
        append_child_nodes(node, el.childs, c_opts)
        if el.attrs.get("value") is Some(v) {
          apply_value_last(node, Some(v))
        }
        if el.attrs.get("checked") is Some(c) {
          set_prop(node, "checked", Some(c), false)
        }
      } else {
        apply_properties(node, el.attrs)
        append_child_nodes(node, el.childs, c_opts)
      }
      node
    }
  }
}
