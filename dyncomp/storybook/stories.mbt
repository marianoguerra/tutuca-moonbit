// What a storybook of dynamic components shows, and where it comes from.
//
// Nowhere in this file is there a list of stories. A `.tutuca.tar.gz` carries a
// manifest that already declares what its components are and what named
// `inits` each one ships — and a named initial state is exactly a story. So the
// gallery is a projection of the catalog rather than a document beside it, and
// a bundle nobody wrote for this page still has stories the moment it loads.

///|
/// One card's worth: a component, and ONE configuration of it.
pub(all) struct Story {
  ref_ : @registry.ComponentRef
  /// The manifest `init` this is built from, or "" for the component's own
  /// defaults.
  init : String
  /// What the card is called. The component's name, and the configuration's
  /// when there is one.
  title : String
  /// The `init`'s own sentence when it has one, the component's otherwise. An
  /// `init` says WHEN to prefer it, which is the more useful half on a card
  /// that is already showing what it looks like.
  doc : String
  /// The arguments the configuration carried, as JSON. Empty for the defaults
  /// story, which carried none.
  args : String
} derive(Eq)

///|
/// Every story in a catalog, in catalog order.
///
/// Each component gets its declared configurations AND a `defaults` one. The
/// default is not redundant: it is the state a host places when a person picks
/// the component out of a palette, so it is the configuration most people will
/// actually meet first, and a component whose defaults are unusable should say
/// so on a card rather than in a bug report.
pub fn stories_of(registry : @registry.Registry) -> Array[Story] {
  let out : Array[Story] = []
  for d in registry.all() {
    out.push({
      ref_: d.ref_,
      init: "",
      title: d.ref_.name,
      doc: d.doc,
      args: "",
    })
    for i in d.inits {
      out.push({
        ref_: d.ref_,
        init: i.name,
        title: "\{d.ref_.name} · \{i.name}",
        doc: if i.doc == "" {
          d.doc
        } else {
          i.doc
        },
        args: args_json(i.args),
      })
    }
  }
  out
}

///|
/// A configuration's arguments, as the JSON a person can read and copy back
/// into a manifest. Sorted, because a map's iteration order is not a fact
/// about the bundle and a card that reshuffles between reloads looks broken.
pub fn args_json(args : Map[String, @tutuca.Value]) -> String {
  if args.is_empty() {
    return ""
  }
  let keys = args.keys().collect()
  keys.sort()
  let out : Map[String, Json] = Map([])
  for k in keys {
    out[k] = args.get(k).unwrap_or(Null).to_json()
  }
  Json::object(out).stringify(indent=2)
}

///|
/// One sidebar entry: a component, and how many stories it has.
pub(all) struct NavEntry {
  ref_ : @registry.ComponentRef
  count : Int
} derive(Eq)

///|
/// The sidebar, in the same order the cards are in. Built from the stories
/// rather than from the catalog a second time, so an entry claiming three
/// stories is an entry with three cards under it by construction.
pub fn nav_of(stories : Array[Story]) -> Array[NavEntry] {
  let out : Array[NavEntry] = []
  for s in stories {
    let mut found = false
    for i, e in out {
      if e.ref_ == s.ref_ {
        out[i] = { ..e, count: e.count + 1, }
        found = true
        break
      }
    }
    if !found {
      out.push({ ref_: s.ref_, count: 1, })
    }
  }
  out
}
