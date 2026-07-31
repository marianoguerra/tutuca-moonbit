///| The catalog across every loaded bundle, and search over it.
///
/// Keyed by MODULE name rather than by bundle, because that is the unit the
/// rest of the system already treats as identity: loading a module that is
/// already registered is a hot swap, and the registry has to answer with the
/// new components the moment it happens.

///|
pub struct Registry {
  by_module : Map[String, @dyncomp.Bundle]
  /// Insertion order, so a palette lists modules the way they were loaded
  /// rather than the way a hash landed. A re-registered module keeps its
  /// place: a hot swap should not make a palette jump.
  order : Array[String]
}

///|
pub fn Registry::new() -> Registry {
  { by_module: Map([]), order: [] }
}

///|
/// Take a loaded bundle into the catalog, replacing any earlier one under the
/// same module name (a hot swap).
pub fn Registry::register(self : Registry, bundle : @dyncomp.Bundle) -> Unit {
  let name = bundle.module_name()
  if !self.by_module.contains(name) {
    self.order.push(name)
  }
  self.by_module[name] = bundle
}

///|
/// Drop a module from the catalog. The bundle itself is the host's to release.
pub fn Registry::forget(self : Registry, module_ : String) -> Unit {
  if self.by_module.remove(module_) is _ {
    self.order.retain(m => m != module_)
  }
}

///|
pub fn Registry::modules(self : Registry) -> Array[String] {
  self.order.copy()
}

///|
/// Every component of every module, in load order and then declaration order.
pub fn Registry::all(self : Registry) -> Array[Descriptor] {
  let out : Array[Descriptor] = []
  for module_ in self.order {
    guard self.by_module.get(module_) is Some(bundle) else { continue }
    for name in bundle.component_names() {
      if describe(bundle, name) is Some(d) {
        out.push(d)
      }
    }
  }
  out
}

///|
/// One component, or None if no loaded module declares it.
pub fn Registry::describe(self : Registry, ref_ : ComponentRef) -> Descriptor? {
  guard self.by_module.get(ref_.module_) is Some(bundle) else { return None }
  describe(bundle, ref_.name)
}

///|
/// A match, with why it matched.
///
/// `why` is not decoration. A search a person cannot explain is a search they
/// stop trusting, and a language model handed a ranked list with no reasons
/// has to take the order on faith — this is what lets both see that "counter"
/// hit a keyword rather than a stray word in a field's doc.
pub(all) struct Hit {
  descriptor : Descriptor
  score : Int
  why : Array[String]
}

///|
/// Weights, stated once and in one place so the ranking is arguable rather
/// than emergent. The order is the claim: what a component is CALLED beats
/// what it is filed under, which beats what it happens to mention.
const NAME_EXACT : Int = 100

///|
const NAME_PART : Int = 40

///|
const KEYWORD : Int = 30

///|
const CATEGORY : Int = 15

///|
const DOC : Int = 10

///|
const MODULE_PART : Int = 8

///|
/// A field or message name. Low because it is the most incidental kind of
/// match — every component with a `count` field answers "count" — but not
/// zero, because "which component has a `draft` field" is a real question.
const MEMBER : Int = 4

///|
fn lower(s : String) -> String {
  s.to_lower()
}

///|
/// Query terms: lowercased, split on whitespace, empties dropped. Deliberately
/// not stemmed and not fuzzy — a catalog is small, the terms are chosen by
/// someone who can retype them, and an unexplainable near-match is worse here
/// than a miss.
fn terms(query : String) -> Array[String] {
  let out : Array[String] = []
  for part in query.split(" ") {
    let t = lower(part.trim(chars=" ").to_owned())
    if t != "" {
      out.push(t)
    }
  }
  out
}

///|
fn score_one(d : Descriptor, ts : Array[String]) -> (Int, Array[String]) {
  let mut score = 0
  let why : Array[String] = []
  let name = lower(d.ref_.name)
  let module_ = lower(d.ref_.module_)
  let doc = lower(d.doc)
  let category = lower(d.category)
  for t in ts {
    if name == t {
      score = score + NAME_EXACT
      why.push("name is \"\{t}\"")
    } else if name.contains(t) {
      score = score + NAME_PART
      why.push("name contains \"\{t}\"")
    }
    let mut hit_keyword = false
    for k in d.keywords {
      if !hit_keyword && lower(k).contains(t) {
        hit_keyword = true
        score = score + KEYWORD
        why.push("keyword \"\{k}\"")
      }
    }
    if category != "" && category.contains(t) {
      score = score + CATEGORY
      why.push("category \"\{d.category}\"")
    }
    if doc.contains(t) {
      score = score + DOC
      why.push("described as containing \"\{t}\"")
    }
    if module_.contains(t) {
      score = score + MODULE_PART
      why.push("module \"\{d.ref_.module_}\"")
    }
    // Members are counted ONCE per term however many match: a component with
    // eight fields mentioning the word is not eight times as relevant as one
    // with a single field named exactly it.
    let mut hit_member = false
    for f in d.schema.fields {
      if !hit_member &&
        (
          lower(f.name).contains(t) ||
          lower(field_doc_of(d, f.name)).contains(t)
        ) {
        hit_member = true
        score = score + MEMBER
        why.push("field \"\{f.name}\"")
      }
    }
    if !hit_member {
      for m in d.messages {
        if !hit_member &&
          (lower(m.name).contains(t) || lower(m.doc).contains(t)) {
          hit_member = true
          score = score + MEMBER
          why.push("\{m.bucket} \"\{m.name}\"")
        }
      }
    }
  }
  (score, why)
}

///|
fn field_doc_of(d : Descriptor, name : String) -> String {
  match d.field_docs.get(name) {
    Some(fd) => fd.doc
    None => ""
  }
}

///|
/// Rank the catalog against a query.
///
/// An EMPTY query returns the whole catalog in load order rather than nothing,
/// because that is what a palette opens with — "show me everything" is the
/// commonest search there is.
pub fn Registry::search(
  self : Registry,
  query : String,
  limit? : Int = 20,
) -> Array[Hit] {
  let all = self.all()
  let ts = terms(query)
  if ts.is_empty() {
    let out : Array[Hit] = []
    for d in all {
      if out.length() >= limit {
        break
      }
      out.push({ descriptor: d, score: 0, why: [] })
    }
    return out
  }
  let hits : Array[Hit] = []
  for d in all {
    let (score, why) = score_one(d, ts)
    if score > 0 {
      hits.push({ descriptor: d, score, why })
    }
  }
  // Sort by score, and by the catalog's own order within a tie — `all()` is
  // already in load-then-declaration order, so a stable sort is what keeps two
  // equally good matches from swapping between calls.
  let sorted = hits.copy()
  sorted.sort_by((a, b) => b.score - a.score)
  let out : Array[Hit] = []
  for h in sorted {
    if out.length() >= limit {
      break
    }
    out.push(h)
  }
  out
}

///|
/// A search result as the agent layer returns it: enough to choose from, not
/// the whole descriptor. `ui_search_components` hands back a list of these and
/// `ui_describe_component` opens one — which is the split that keeps a search
/// over a large catalog from filling a context window.
pub fn Hit::to_json(self : Hit) -> Json {
  Json::object({
    "module": Json::string(self.descriptor.ref_.module_),
    "name": Json::string(self.descriptor.ref_.name),
    "summary": Json::string(self.descriptor.summary()),
    "category": Json::string(self.descriptor.category),
    "score": Json::number(self.score.to_double()),
    "why": Json::array(self.why.map(w => Json::string(w))),
  })
}
