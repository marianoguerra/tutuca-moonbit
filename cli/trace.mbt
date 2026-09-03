// `tutuca trace` — reading and shortening an execution trace.
//
// One command over one file, and the flags say what to do to it. No
// subcommands, for the reason `dispatch.mbt` states: there is one command set
// and no module concept.
//
// Only the operations that need nothing but the file. Trimming and relocating
// are transforms over what is written down; REBASING is not — it means running
// the app to find out what state a prefix produced, and a native CLI does not
// have the user's compiled components. It is deliberately absent rather than
// half-present.
//
// Pure like the rest of cli/: this turns SOURCE TEXT into OUTPUT TEXT. The
// shell (cmd/tutuca) reads the file and writes the result, the same split
// `gen` uses.

///|
/// What to do to the trace.
pub(all) enum TraceOp {
  /// Say what is in it. The default, because a file somebody was handed is a
  /// file they want to know about before they change it.
  Info
  /// Keep the first `at` events.
  Trim(at~ : Int)
  /// Cut it down to one subtree, and rewrite every address to suit.
  Relocate(place~ : String, compact~ : Bool)
} derive(Debug, Eq)

///|
pub(all) struct TracePlan {
  path : String
  op : TraceOp
  /// Where to write; `None` is stdout.
  out : String?
} derive(Debug, Eq)

///|
pub(all) struct TraceResult {
  /// The file to write, or `None` for an operation that only reports.
  file : String?
  report : String
  /// What the operation could not carry across. Warnings beside a result and
  /// not an error instead of one: a relocated trace missing something is
  /// usually missing something that did not matter, and it is still worth
  /// having.
  diagnostics : Array[String]
} derive(Debug, Eq)

///|
/// One line per fact, which is what `info` is for: a file somebody was handed,
/// summarized before they act on it.
fn trace_report(t : @trace.Trace) -> String {
  let sb = StringBuilder()
  fn line(k : String, v : String) -> Unit {
    sb.write_string("\{k}: \{v}\n")
  }

  if t.origin.component != "" {
    line("component", t.origin.component)
  }
  if t.origin.module_ != "" {
    line("module", t.origin.module_)
  }
  if t.origin.example != "" {
    line("example", t.origin.example)
  }
  if t.origin.fingerprint != "" {
    line("shape", t.origin.fingerprint)
  }
  line("events", t.events.length().to_string())
  line("inputs", t.input_count().to_string())
  line("turns", t.turns().length().to_string())
  if !t.relocated_from.is_empty() {
    line("relocated from", t.relocated_from.map(p => p.label()).join(" > "))
  }
  if t.compacted {
    line("compacted", "yes — this trace can no longer be relocated")
  }
  // The places, with how much of the recording is about each: what a reader
  // picks a `--at` from, and the reason `info` is worth running before
  // `--at` rather than guessing at an address.
  let counts : Map[String, Int] = Map([])
  for e in t.events {
    let k = e.at.label()
    counts[k] = counts.get(k).unwrap_or(0) + 1
  }
  sb.write_string("places:\n")
  for place in t.places() {
    let label = place.label()
    let shown = if label == "" { "(root)" } else { label }
    let n = counts.get(label).unwrap_or(0)
    let mountable = @trace.cut_root(t.root, place) is Some(Object(_))
    sb.write_string(
      "  \{shown}  \{n} event" +
      (if n == 1 { "" } else { "s" }) +
      (if mountable { "" } else { "  (not a component)" }) +
      "\n",
    )
  }
  sb.to_string()
}

///|
/// Read a trace, do the thing, hand back what to write and what to say.
pub fn trace_apply(
  plan : TracePlan,
  source : String,
) -> Result[TraceResult, ErrShape] {
  // `Trim` never parses an event body, which is the point of it: slicing lines
  // cannot fail on an event kind a newer runtime wrote, so a trace this build
  // does not fully understand can still be shortened.
  if plan.op is Trim(at~) {
    let (headers, events) = @trace.split_lines(source) catch {
      e =>
        return Err(
          err(
            CODE_INTERNAL,
            "\{plan.path}: \{e.message()}",
            hint="a trace is JSONL: a header line, a root line, then one line per event",
          ),
        )
    }
    if at < 0 {
      return Err(
        err(
          CODE_USAGE_BAD_FLAG_VALUE,
          "--trim takes a count, not \{at}",
          hint="`--trim 0` keeps the initial state and no events",
        ),
      )
    }
    let kept = if at >= events.length() {
      events
    } else {
      events[0:at].to_owned()
    }
    let sb = StringBuilder()
    for l in headers {
      sb.write_string(l)
      sb.write_string("\n")
    }
    for l in kept {
      sb.write_string(l)
      sb.write_string("\n")
    }
    return Ok({
      file: Some(sb.to_string()),
      report: "kept \{kept.length()} of \{events.length()} events\n",
      diagnostics: [],
    })
  }
  let t = @trace.from_jsonl(source) catch {
    e =>
      return Err(
        err(
          CODE_INTERNAL,
          "\{plan.path}: \{e.message()}",
          hint="a trace is JSONL: a header line, a root line, then one line per event",
        ),
      )
  }
  match plan.op {
    Info => Ok({ file: None, report: trace_report(t), diagnostics: [], })
    // Handled above, and matched here so the compiler holds this exhaustive
    // rather than a `_` that would swallow a case added later.
    Trim(_) => Ok({ file: None, report: "", diagnostics: [], })
    Relocate(place~, compact~) => {
      let at = @trace.parse_place(place) catch {
        e =>
          return Err(
            err(
              CODE_USAGE_BAD_FLAG_VALUE,
              e.message(),
              hint="an address is written like `.rows[1].body` — run `tutuca trace <file>` to see the ones this trace touched",
            ),
          )
      }
      let (cut, gaps) = t.relocate(at)
      let out = if compact { cut.compact() } else { cut }
      Ok({
        file: Some(out.to_jsonl()),
        report: trace_report(out),
        diagnostics: gaps.map(g => g.message()),
      })
    }
  }
}

///|
let trace_help : String =
  #|tutuca trace <file> [--trim <n>] [--at <place>] [--compact] [-o <file>]
  #|
  #|  Reads an execution trace — the state a component tree started in, plus
  #|  every message and intent that crossed the runtime afterwards.
  #|
  #|  With no flags it says what is in one: which component, how many events,
  #|  how many of those a rerun would feed, and every address the recording
  #|  touched. Run this before --at; the places it lists are the ones there is
  #|  anything to cut to.
  #|
  #|    --trim <n>     Keep the first n events.
  #|
  #|                   Slices lines and never reads an event, so a trace
  #|                   holding a kind this build has never heard of shortens
  #|                   just the same.
  #|
  #|    --at <place>   Cut it down to one subtree and rewrite every address to
  #|                   suit, so `.rows[1]` becomes the root.
  #|
  #|                   What a parent sent INTO that subtree survives as an
  #|                   input: after the cut there is no parent left to send it.
  #|                   What the subtree did for itself stays derived, because a
  #|                   rerun does it again. Anything the cut could not carry
  #|                   across is reported rather than dropped in silence.
  #|
  #|    --compact      Also drop the derived events. Smaller, and the trade is
  #|                   explicit: the result can no longer be relocated, because
  #|                   nothing is left to say what crossed into a subtree.
  #|
  #|  What is NOT here is rebasing — replacing a prefix with the state it
  #|  produced. That means running the app, and a CLI does not have your
  #|  compiled components; `@trace.Trace::rebase` is the same operation from a
  #|  `moon test` block, where one is mounted.
  #|
  #|  Examples:
  #|    tutuca trace app.trace.jsonl
  #|    tutuca trace app.trace.jsonl --trim 40 -o short.trace.jsonl
  #|    tutuca trace app.trace.jsonl --at ".rows[1]" -o row.trace.jsonl

///|
fn run_trace(args : Array[String], opts : GlobalOpts) -> Outcome {
  let parsed = match parse_flags(args, command_spec("trace")) {
    Ok(p) => p
    Err(e) => return Done(error_emit(opts, e))
  }
  if parsed.bool("help") || opts.help {
    return Done({ out: trace_help, err: "", exit_code: 0, })
  }
  guard parsed.positionals is [path, ..] else {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MISSING_ARGUMENT,
          "trace requires a .trace.jsonl file",
          hint="`tutuca trace app.trace.jsonl` says what is in one",
        ),
      ),
    )
  }
  let trim = parsed.str("trim")
  let at = parsed.str("at")
  // Two operations on one file is not one operation. Refused rather than
  // ordered by some rule nobody wrote down: trimming and then relocating is a
  // different trace from relocating and then trimming.
  if trim is Some(_) && at is Some(_) {
    return Done(
      error_emit(
        opts,
        err(
          CODE_USAGE_MUTUALLY_EXCLUSIVE,
          "--trim and --at are two operations, so they cannot be asked for at once",
          hint="run one, then the other on its output — the order changes the answer",
        ),
      ),
    )
  }
  let op : TraceOp = match (trim, at) {
    (Some(n), _) =>
      Trim(
        at=@string.parse_int(n) catch {
          _ =>
            return Done(
              error_emit(
                opts,
                err(
                  CODE_USAGE_BAD_FLAG_VALUE,
                  "--trim takes a number of events, not `\{n}`",
                  hint="`tutuca trace <file>` says how many there are",
                ),
              ),
            )
        },
      )
    (_, Some(p)) => Relocate(place=p, compact=parsed.bool("compact"))
    _ => Info
  }
  Trace(opts, plan={ path, op, out: parsed.str("out"), })
}
