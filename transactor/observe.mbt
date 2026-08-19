// Observer records as data: the labels a devtool prints and the JSON a host
// posts across a boundary.
//
// The JSON half is new because it could not exist before. A record's `before`
// and `after` are the leaf values a handler read and returned — which, for
// every component in the tree, is an instance — and `Value::to_json` flattened
// an instance to `null`. A record therefore serialized as a name, a path, and
// two nulls: everything except the state change it exists to describe. With
// `Obj::obj_schema` an instance projects to its declared fields, so this is
// the whole record.

///|
pub fn ObserveKind::label(self : ObserveKind) -> String {
  match self {
    Receive => "receive"
    Intent => "intent"
    Answer => "answer"
  }
}

///|
/// The kind a dispatch through `bucket` is observed as.
///
/// `Answer` is the one kind with no bucket behind it: an answer is dispatched
/// as an ordinary `Receive` and a handler cannot tell it from a parent's
/// message, so the two enums are not the same enum. Every bucket has exactly
/// one kind, and this is where that is said.
pub fn ObserveKind::of_bucket(bucket : @tutuca.HandlerBucket) -> ObserveKind {
  match bucket {
    Receive => Receive
    Intent => Intent
  }
}

///|
pub fn ObserveMatch::label(self : ObserveMatch) -> String {
  match self {
    Exact => "exact"
    NoHandler => "none"
  }
}

///|
/// A record as JSON.
///
/// `path` is the readable label (`todos.items[1].title`) rather than the step
/// structure: a consumer of this is showing it, and the structure is still on
/// the record for one that is not. `after` is absent — not null — when the
/// handler made no change, which is the distinction the whole no-op path turns
/// on.
pub fn ObserveRecord::to_json(self : ObserveRecord) -> Json {
  let obj : Map[String, Json] = {
    "kind": Json::string(self.kind.label()),
    "name": Json::string(self.name),
    "matched": Json::string(self.matched.label()),
    "path": Json::string(@tutuca.step_keys_label(self.path_keys)),
    "seq": Json::number(self.seq.to_double()),
    "args": Json::array(self.args.map(a => a.to_json())),
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
