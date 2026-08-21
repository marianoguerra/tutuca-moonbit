// One interpreter for addressing steps over the value accessors, so step
// semantics (especially SeqAccessStep's live key resolution) are written once
// instead of at every call site that walks a path.

///|
/// Resolve a field-referenced key against a node NOW: read key_field, ask the
/// scalar for its key form.
fn live_key(node : Value, key_field : String) -> PathKey? {
  node.field(key_field).as_key()
}

///|
pub fn step_get(node : Value, step : Step) -> Value? {
  match step {
    FieldStep(name) => node.field_opt(name)
    SeqStep(field~, key~) | EachRenderItStep(field~, key~) =>
      node.field(field).item_opt(key)
    SeqAccessStep(seq_field~, key_field~) =>
      match live_key(node, key_field) {
        Some(key) => node.field(seq_field).item_opt(key)
        None => None
      }
    BindStep(..) | ScopeBindStep(..) | EachBindStep(..) => Some(node) // frame-only: addresses nothing
  }
}

///|
/// Rebuild one seq level: new seq with `key` replaced, then a new node with
/// the seq field replaced (both COW per the accessors' identity contract).
fn put_seq(
  node : Value,
  field : String,
  key : PathKey,
  child : Value,
) -> Value? {
  match node.field_opt(field) {
    Some(seq) =>
      match seq.with_item_opt(key, child) {
        Some(new_seq) => node.with_field_opt(field, new_seq)
        None => None
      }
    None => None
  }
}

///|
fn step_put(node : Value, step : Step, child : Value) -> Value? {
  match step {
    FieldStep(name) => node.with_field_opt(name, child)
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
/// Freeze a field-resolved key against `node` as it is now:
/// SeqAccessStep becomes a literal-key SeqStep; every other step (and an
/// unresolvable key) pins to itself.
fn step_pin(step : Step, node : Value) -> Step {
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
/// The compact/dispatch projection of one step:
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
/// Generic {field, key?} descriptor. SeqAccessStep reports
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
/// Key a step with the si/sk an `§Each§` meta carried (used by event
/// reconstruction's applyKey): a plain field access
/// under a keyed meta addresses the keyed item. Steps that carry their own
/// key (or no field) are returned unchanged.
pub fn step_with_key(step : Step, key : PathKey) -> Step {
  match step {
    FieldStep(f) => SeqStep(field=f, key~)
    _ => step
  }
}
