// Observer records as data: the labels a devtool prints and the JSON a host
// posts across a boundary.
//
// The JSON half is new because it could not exist before. A record's `before`
// and `after` are the leaf values a handler read and returned — which, for
// every component in the tree, is an instance — and `Value::to_json` flattened
// an instance to `null`. A record therefore serialized as a name, a path, and
// two nulls: everything except the state change it exists to describe. With
// `Obj::schema` an instance projects to its declared fields, so this is
// the whole record.
//
// It writes the ADDRESS twice, and both are load-bearing. `path` is the label a
// person reads; `pathKeys` is the structure a consumer filters, groups or
// relocates on, and a reader handed only the label would have to parse prose to
// get it back. `walk` and `parent` are the causal links: without them a cascade
// of twelve sends from one click is twelve unrelated rows.

///|
pub fn ObserveMatch::label(self : ObserveMatch) -> String {
  match self {
    Exact => "exact"
    NoHandler => "none"
  }
}

///|
/// The three words a reader sees: the bucket's, or `answer`.
///
/// An answer is dispatched as an ordinary `Receive` and a handler cannot tell
/// it from a parent's message — that is the claim, so `bucket` must not know.
/// An INSPECTOR needs to, and this is the one place that folds the two things
/// the record holds into the one word it shows.
pub fn ObserveRecord::kind_label(self : ObserveRecord) -> String {
  if self.is_answer {
    "answer"
  } else {
    self.bucket.label()
  }
}

///|
/// A record as JSON.
///
/// `path` is the readable label (`todos.items[1].title`) and `pathKeys` the same
/// address as structure, because a consumer that shows one usually filters on
/// the other. `after` is absent — not null — when the handler made no change,
/// which is the distinction the whole no-op path turns on; `walk` and `parent`
/// are absent when there is nothing to point at.
///
/// `kind` is the bucket's word, except for an answer, which says so: those are
/// the three words a reader has always seen, now derived from the two things
/// the record actually holds rather than from a third enum that folded them.
/// `origin` is beside it, and says who raised the dispatch.
pub fn ObserveRecord::to_json(self : ObserveRecord) -> Json {
  let obj : Map[String, Json] = {
    "origin": Json::string(self.origin.label()),
    "kind": Json::string(self.kind_label()),
    "name": Json::string(self.name),
    "matched": Json::string(self.matched.label()),
    "path": Json::string(@tutuca.step_keys_label(self.path_keys)),
    "pathKeys": Json::array(self.path_keys.map(k => k.to_json())),
    "seq": Json::number(self.seq.to_double()),
    "args": Json::array(self.args.map(a => a.to_json())),
  }
  // Absent rather than 0, so a reader can tell "belongs to no walk" from a walk
  // whose id happens to be small, and a message's line stays as short as a
  // message is simple.
  if self.walk != 0 {
    obj["walk"] = Json::number(self.walk.to_double())
  }
  if self.parent_seq != 0 {
    obj["parent"] = Json::number(self.parent_seq.to_double())
  }
  match self.before {
    Some(b) => obj["before"] = b.to_json()
    None => ()
  }
  match self.after {
    Some(a) => obj["after"] = a.to_json()
    None => ()
  }
  Json::object(obj)
}
