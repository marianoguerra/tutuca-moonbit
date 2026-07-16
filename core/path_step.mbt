// One interpreter for addressing steps over the PathNode primitives, so step
// semantics (especially SeqAccessStep's live key resolution) are identical
// for every trait implementation.

///|
/// Resolve a field-referenced key against a node NOW: read key_field, ask the
/// scalar for its key form.
fn live_key(node : &PathNode, key_field : String) -> PathKey? {
  match node.field(key_field) {
    Some(k) => k.as_key()
    None => None
  }
}

///|
pub fn step_get(node : &PathNode, step : Step) -> &PathNode? {
  match step {
    FieldStep(name) => node.field(name)
    SeqStep(field~, key~) | EachRenderItStep(field~, key~) =>
      match node.field(field) {
        Some(seq) => seq.item(key)
        None => None
      }
    SeqAccessStep(seq_field~, key_field~) =>
      match live_key(node, key_field) {
        Some(key) =>
          match node.field(seq_field) {
            Some(seq) => seq.item(key)
            None => None
          }
        None => None
      }
    BindStep(..) | ScopeBindStep(..) | EachBindStep(..) => Some(node) // frame-only: addresses nothing
  }
}

///|
/// Rebuild one seq level: new seq with `key` replaced, then a new node with
/// the seq field replaced (both COW per the trait contract).
fn put_seq(
  node : &PathNode,
  field : String,
  key : PathKey,
  child : &PathNode,
) -> &PathNode? {
  match node.field(field) {
    Some(seq) =>
      match seq.with_item(key, child) {
        Some(new_seq) => node.with_field(field, new_seq)
        None => None
      }
    None => None
  }
}

///|
pub fn step_put(node : &PathNode, step : Step, child : &PathNode) -> &PathNode? {
  match step {
    FieldStep(name) => node.with_field(name, child)
    SeqStep(field~, key~) | EachRenderItStep(field~, key~) =>
      put_seq(node, field, key, child)
    SeqAccessStep(seq_field~, key_field~) =>
      match live_key(node, key_field) {
        Some(key) => put_seq(node, seq_field, key, child)
        None => None
      }
    BindStep(..) | ScopeBindStep(..) | EachBindStep(..) => Some(child) // frame-only: the new value passes through
  }
}

///|
/// Freeze a field-resolved key against `node` as it is now (JS Step.pinKey):
/// SeqAccessStep becomes a literal-key SeqStep; every other step (and an
/// unresolvable key) pins to itself.
fn step_pin(step : Step, node : &PathNode) -> Step {
  match step {
    SeqAccessStep(seq_field~, key_field~) =>
      match live_key(node, key_field) {
        Some(key) => SeqStep(field=seq_field, key~)
        None => step
      }
    _ => step
  }
}

///|
/// The compact/dispatch projection of one step (JS toAbstractPathStep):
/// EachRenderItStep abstracts to a plain SeqStep; None drops the step — no
/// current variant is dropped, the hook exists for future frame-only steps.
fn step_to_abstract(step : Step) -> Step? {
  match step {
    EachRenderItStep(field~, key~) => Some(SeqStep(field~, key~))
    BindStep(..) | ScopeBindStep(..) | EachBindStep(..) => None // frame-only steps are dropped from the dispatch path
    _ => Some(step)
  }
}

///|
/// Generic {field, key?} descriptor (JS Step.toKey). SeqAccessStep reports
/// its seq field with no key — the key is live and unknown without a value;
/// dropping the step instead would shift the indices of later keys.
fn step_to_key(step : Step) -> StepKey? {
  match step {
    FieldStep(name) => Some({ field: name, key: None })
    SeqStep(field~, key~) | EachRenderItStep(field~, key~) =>
      Some({ field, key: Some(key) })
    SeqAccessStep(seq_field~, key_field=_) =>
      Some({ field: seq_field, key: None })
    BindStep(..) | ScopeBindStep(..) | EachBindStep(..) => None // frame-only: no field to report
  }
}

///|
/// Key a step with the si/sk an `§Each§` meta carried (JS Step.withIndex /
/// withKey, used by event reconstruction's applyKey): a plain field access
/// under a keyed meta addresses the keyed item. Steps that carry their own
/// key (or no field) are returned unchanged.
pub fn step_with_key(step : Step, key : PathKey) -> Step {
  match step {
    FieldStep(f) => SeqStep(field=f, key~)
    _ => step
  }
}
