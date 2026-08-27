// Reusable display +
// transform for the transaction-observer "Activity" feature
// (`@transactor.Transactor::observe`). Host-agnostic: a host wires its own
// `observe(...)` subscription, converts each `ObserveRecord` with
// `Inspector::record_to_entry`, and sends the entry to an ActivityLog (its
// `appendEntry` receive handler prepends and caps the list).
//
// Deviations:
// - `ObserveRecord` has no wall-clock timestamp (only `seq`), so the entry's
//   `time` column defaults to `#seq`; pass `time~` to override.
// - `ObserveRecord` has no separate handlerName, so the "actual handler that
//   ran" label is always empty.

///|
/// Newest-first cap for an activity log (see ActivityLog `appendEntry`).
let activity_cap : Int = 50

///|
/// One row of dispatch activity. Pure display: a host builds these from
/// observer records via `record_to_entry`, prebuilding the `before`/`after`
/// value inspectors so no functions or paths are ever stored in state.
/// `after` is Null (and hidden) for the outgoing side of a request.
///
/// The state and the views live in activity.html.
fn activity_entry_comp() -> @component.Component {
  activity_entry_component(init={
    ..ActivityEntryState::zero(),
    hasAfter: true,
  })
}

///|
/// A bounded, newest-first, scrollable list of ActivityEntry rows.
/// `appendEntry` (a receive handler dispatched from a host's observer
/// subscription) prepends the entry and
/// caps the list. Renders an empty hint until the first entry lands.
fn activity_log_comp() -> @component.Component {
  activity_log_component(update=(s, msg, _ctx) => {
    match ActivityLogReceive::from_dispatch(msg) {
      Some(AppendEntry(entry)) => {
        let out : Array[@tutuca.Value] = [entry]
        for i, e in s.events {
          if i >= activity_cap - 1 {
            break
          }
          out.push(e)
        }
        Next({ events: out, hasEvents: true, })
      }
      Some(Unknown(_, _)) | None => Unhandled
    }
  })
}

///|
/// Join a record's path keys into a readable label, e.g. "value.rows[1]".
/// A host may slice the prefix first. The rendering itself is `@tutuca`'s, so
/// a log line and a printed `Path` agree.
pub fn path_keys_label(path_keys : Array[@tutuca.StepKey]) -> String {
  @tutuca.step_keys_label(path_keys)
}

///|
/// Turn an observer record into an ActivityEntry instance.
/// `inspect` builds the before/after value views (defaults to the plain data
/// inspector). `path_label` and `time` default to the full path label and
/// `#seq`.
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
    None => Null
  }
  let after = match record.after {
    Some(a) => inspect_fn(a)
    None => Null
  }
  let seq = record.seq
  self.make_("ActivityEntry", args={
    "kind": Str(record.kind.label()),
    "name": Str(record.name),
    "handlerName": Str(""),
    "matched": Str(record.matched.label()),
    "pathLabel": Str(path_label.unwrap_or(path_keys_label(record.path_keys))),
    "time": Str(time.unwrap_or("#\{seq}")),
    "before": before,
    "after": after,
    "hasAfter": Bool(has_after),
  })
}
