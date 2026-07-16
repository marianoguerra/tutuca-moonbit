// Port of src/components/tutuca/activity-inspector.js — reusable display +
// transform for the transaction-observer "Activity" feature
// (`@transactor.Transactor::observe`). Host-agnostic: a host wires its own
// `observe(...)` subscription, converts each `ObserveRecord` with
// `Inspector::record_to_entry`, and sends the entry to an ActivityLog (its
// `appendEntry` receive handler prepends and caps the list).
//
// Port deviations from the JS original:
// - `ObserveRecord` has no wall-clock timestamp (only `seq`), so the entry's
//   `time` column defaults to `#seq`; pass `time~` to override.
// - `ObserveRecord` has no separate handlerName, so the "actual handler that
//   ran" label is always empty (JS only showed it when it differed anyway).

///|
/// Newest-first cap for an activity log (see ActivityLog `appendEntry`).
let activity_cap : Int = 50

///|
/// One row of dispatch activity. Pure display: a host builds these from
/// observer records via `record_to_entry`, prebuilding the `before`/`after`
/// value inspectors so no functions or paths are ever stored in state.
/// `after` is Null (and hidden) for the outgoing side of a request.
fn activity_entry_comp() -> @component.Component {
  @component.component(
    name="ActivityEntry",
    fields={
      "kind": @component.FieldSpec::of_default(Str("")),
      "name": @component.FieldSpec::of_default(Str("")),
      "handlerName": @component.FieldSpec::of_default(Str("")),
      "matched": @component.FieldSpec::of_default(Str("")),
      "pathLabel": @component.FieldSpec::of_default(Str("")),
      "time": @component.FieldSpec::of_default(Str("")),
      "before": @component.FieldSpec::of_default(Null),
      "after": @component.FieldSpec::of_default(Null),
      "hasAfter": @component.FieldSpec::of_default(Bool(true)),
    },
    view=(
      #|<div class="rounded border border-base-content/15 p-2 text-sm flex flex-col gap-1 activity-entry">
      #|  <div class="flex items-center gap-2 flex-wrap">
      #|    <span title="How this was dispatched: receive (send), bubble, response, input, or request" class="badge badge-sm badge-neutral entry-kind" @text=".kind"></span>
      #|    <span title="Message name dispatched — for a DOM input, the event type (click, input, change, keydown, …)" class="font-mono font-semibold entry-name" @text=".name"></span>
      #|    <span title="Actual handler that ran — shown only when it differs from the name" class="text-xs opacity-60 font-mono" @show="truthy? .handlerName" @text=".handlerName"></span>
      #|    <span title="Path to the target component" class="text-xs opacity-40 font-mono entry-path" @text=".pathLabel"></span>
      #|    <span title="Handler resolution — exact: matched by name · unknown: $unknown fallback · none: no handler (no-op)" class="badge badge-xs badge-ghost entry-matched" @show="truthy? .matched" @text=".matched"></span>
      #|    <span title="When this event ran" class="ml-auto text-xs opacity-40 font-mono tabular-nums entry-time" @text=".time"></span>
      #|  </div>
      #|  <div class="flex gap-3 items-start font-mono text-xs">
      #|    <div class="flex-1 min-w-0">
      #|      <div class="opacity-50" title="Target state before the handler ran">before</div>
      #|      <x render=".before"></x>
      #|    </div>
      #|    <div class="flex-1 min-w-0" @show=".hasAfter">
      #|      <div class="opacity-50" title="Target state after the handler ran">after</div>
      #|      <x render=".after"></x>
      #|    </div>
      #|  </div>
      #|</div>
    ),
  )
}

///|
/// A bounded, newest-first, scrollable list of ActivityEntry rows.
/// `appendEntry` (a receive handler — JS had it as a method, but here it is
/// dispatched from a host's observer subscription) prepends the entry and
/// caps the list. Renders an empty hint until the first entry lands.
fn activity_log_comp() -> @component.Component {
  @component.component(
    name="ActivityLog",
    fields={
      "events": @component.FieldSpec::of_default(List([])),
      "hasEvents": @component.FieldSpec::of_default(Bool(false)),
    },
    receive={
      "appendEntry": (inst, args, _ctx) => {
        guard args is [entry, ..] else { return None }
        let events = match inst.get("events") {
          List(a) => a
          _ => []
        }
        let out : Array[@tutuca.Value] = [entry]
        for i, e in events {
          if i >= activity_cap - 1 {
            break
          }
          out.push(e)
        }
        Some(inst.set("events", List(out)).set("hasEvents", Bool(true)))
      },
    },
    view=(
      #|<div class="p-3 flex flex-col gap-2 max-h-[60vh] overflow-y-auto activity-log">
      #|  <div class="text-xs opacity-40 empty-hint" @hide=".hasEvents">
      #|    No activity yet — interact with the component.
      #|  </div>
      #|  <x render-each=".events"></x>
      #|</div>
    ),
  )
}

///|
/// Join a record's path keys into a readable label, e.g. "value.rows[1]".
/// A host may slice the prefix first.
pub fn path_keys_label(path_keys : Array[@tutuca.StepKey]) -> String {
  path_keys
  .map(k => {
    match k.key {
      Some(pk) => "\{k.field}[\{fmt_path_key(pk)}]"
      None => k.field
    }
  })
  .join(".")
}

///|
fn observe_kind_label(kind : @transactor.ObserveKind) -> String {
  match kind {
    Receive => "receive"
    Input => "input"
    Bubble => "bubble"
    Response => "response"
    Request => "request"
  }
}

///|
fn observe_match_label(m : @transactor.ObserveMatch) -> String {
  match m {
    Exact => "exact"
    Unknown => "unknown"
    NoHandler => "none"
  }
}

///|
/// A value → view function bound to a component registry: a component
/// instance renders its field → value rows (InstanceInspector); any other
/// value falls back to the plain data inspector (JS makeInspect).
pub fn Inspector::make_inspect(
  self : Inspector,
  comps : @component.Components,
) -> (@tutuca.Value) -> @tutuca.Value {
  v => self.inspect_value_as_instance(v, comps.get_comp_for(v))
}

///|
/// Turn an observer record into an ActivityEntry instance (JS recordToEntry).
/// `inspect` builds the before/after value views (see `make_inspect`;
/// defaults to the plain data inspector). `path_label` and `time` default to
/// the full path label and `#seq`.
pub fn Inspector::record_to_entry(
  self : Inspector,
  record : @transactor.ObserveRecord,
  inspect? : (@tutuca.Value) -> @tutuca.Value,
  path_label? : String,
  time? : String,
) -> @tutuca.Value {
  let inspect_fn = match inspect {
    Some(f) => f
    None => (v : @tutuca.Value) => self.inspect_value(v)
  }
  let has_after = record.after is Some(_)
  let before = match record.before {
    Some(b) => inspect_fn(b)
    None => @tutuca.Value::Null
  }
  let after = match record.after {
    Some(a) => inspect_fn(a)
    None => @tutuca.Value::Null
  }
  let seq = record.seq
  self.make_("ActivityEntry", args={
    "kind": Str(observe_kind_label(record.kind)),
    "name": Str(record.name),
    "handlerName": Str(""),
    "matched": Str(observe_match_label(record.matched)),
    "pathLabel": Str(path_label.unwrap_or(path_keys_label(record.path_keys))),
    "time": Str(time.unwrap_or("#\{seq}")),
    "before": before,
    "after": after,
    "hasAfter": Bool(has_after),
  })
}
