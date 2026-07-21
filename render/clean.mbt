// Presentation cleanup for headless/serialized output (JS renderToString's
// cleanAttrs pass + the meta strip tests do by regex): drop the renderer's
// §…§ boundary metas and internal data-* stamps, keeping user content only.

///|
fn is_internal_attr(name : String) -> Bool {
  name == "data-nid" ||
  name == "data-cid" ||
  name == "data-eid" ||
  name == "data-vid" ||
  name == "data-si" ||
  name == "data-sk"
}

///|
fn is_meta_comment(text : String) -> Bool {
  text.length() > 0 && text[0] is '§'
}

///|
/// A copy of `v` without §…§ meta comments or internal data-* attributes —
/// for `tutuca render`-style output and snapshot-friendly HTML. Regular
/// comments and user data-* attributes survive.
pub fn clean_vdom(v : @vdom.Vdom) -> @vdom.Vdom? {
  match v {
    Comment(text) => if is_meta_comment(text) { None } else { Some(v) }
    Text(_) => Some(v)
    Fragment(childs) => {
      let out : Array[@vdom.Vdom] = []
      for c in childs {
        match clean_vdom(c) {
          Some(cc) => out.push(cc)
          None => ()
        }
      }
      Some(@vdom.fragment(out))
    }
    Node(el) => {
      let attrs : Map[String, @vdom.AttrValue] = Map([])
      for name, av in el.attrs {
        if !is_internal_attr(name) {
          attrs[name] = av
        }
      }
      let childs : Array[@vdom.Vdom] = []
      for c in el.childs {
        match clean_vdom(c) {
          Some(cc) => childs.push(cc)
          None => ()
        }
      }
      Some(@vdom.h(el.tag, attrs~, childs~, key?=el.key, ns?=el.ns))
    }
  }
}
