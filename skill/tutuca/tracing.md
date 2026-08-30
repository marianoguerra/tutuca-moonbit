# Tutuca — Tracing

Read this file when recording what an app did, saving that recording, running
it back, or building a devtool over one.

A trace is **the state a component tree started in, plus every message and
intent that crossed the runtime afterwards**. The transactor has always had an
observer channel, but a subscription is not something you can keep: it cannot
be saved, handed to someone else, or run again. A trace can.

## The shape of one

```
{"tutucaTrace":1,"origin":{…},"relocatedFrom":[]}
{"root":{"$component":"TodoApp",…}}
{"seq":1,"turn":1,"at":[],"send":"init","args":[]}
```

JSONL: a header line, the initial state on its own line, then one line per
event. The root is its own line because it is the one thing in the file that
can be megabytes; the events are lines because a recorder can then append
rather than buffer, and every shortening operation is a line operation.

An `Event` carries `seq`, `turn`, `walk`, `parent`, `at` (a `Place`), `op`, and
`input`. Two of those decide everything a rerun does:

- **`input`** — whether a rerun FEEDS this event. A derived event is what the
  app did ABOUT an input, and a rerun does it again; feeding one would make it
  happen twice.
- **`turn`** — everything pushed between two drains shares one. One DOM event
  with two handlers is one turn, and a rerun that settled between them would
  render twice where the recording rendered once.

`op` is five cases: `Send`, `Intent`, `Offered`, `Answer`, `Refused`. `Answer`
is an input — nothing inside the tree can recompute what a host said, and the
same question asked twice may get two different answers.

## Recording

Install a recorder on the transactor. There are three, and they differ only in
what they keep.

```moonbit nocheck
// nocheck: `app` is the reader's own mounted app
// Everything, held in memory until somebody takes it.
let rec = @trace.TraceRecorder::new(root=app.root_value().to_component_json())
app.transactor.set_recorder(rec)
// … drive the app …
let t = rec.take()          // a snapshot, not a stop: recording continues
```

- `TraceRecorder::new(root~, origin?, sink?, keep_after?)` — with a `sink` it
  writes JSONL lines as they happen and holds nothing, so a long session costs
  constant memory. `keep_after` records the state each handler produced: worth
  having in a devtool, not worth the size in a long session, off by default.
- `RingRecorder::new(turns~, snapshot~, …)` — a flight recorder, the last N
  turns. When it drops a turn it rebases onto a fresh snapshot, so what it
  holds is always a COMPLETE recording and never a suffix of one.
- `ScopedRecorder::new(at~, root~, …)` — everything at or below one `Place`.
  This is what makes "record only this part" mean something when the parts are
  not separate apps: a gallery is ONE transactor with everything mounted under
  it, so narrowing a recording is done by keeping less, as it happens.

Put `NullRecorder` back when you stop. The default records nothing and costs
nothing; leaving a live recorder installed is still recording.

```moonbit nocheck
// nocheck: `app` is the reader's own mounted app
app.transactor.set_recorder(@transactor.NullRecorder::{  })
```

Refusals arrive on a separate channel — `rec.watch_refusals()` returns an
unsubscribe, and `rec.stop_watching_refusals()` is the idempotent version for a
panel whose start and stop are two different buttons.

## Saving and loading

```moonbit nocheck
// nocheck: `t` is the reader's own recording
let text = t.to_jsonl()             // the file
let back = @trace.from_jsonl(text)  // raises TraceError
```

`TraceError` carries a **line number** in every case, because the file is
routinely a hundred thousand lines and "expected an object" with no position in
it is a sentence nobody can act on. Show `e.message()`.

`Trace::to_json` / `from_json` are the whole recording as one value, beside the
line format rather than instead of it: a snapshot test and a clipboard both
want one value, and neither wants to be appended to.

## Shortening one

Four operations, all pure — a `Trace` in, a `Trace` out, never an app.

| | |
| --- | --- |
| `t.prefix(n)` | the first `n` events. The cheapest: a prefix of a recording is a recording, because the state it starts from has not changed. |
| `t.rebase(at~, root~)` | replace the first `n` events with the state they produced. `at` rounds FORWARD to a turn boundary — half a turn is not a thing that happened. `root` is the snapshot you replayed to; this package cannot compute it, because computing it means running the app. |
| `t.relocate(place)` | everything the subtree at `place` saw, with `place` as the new root. Answers `(Trace, Array[Gap])`. |
| `t.compact()` | drop the derived events. Smaller, and the trade is explicit: a compacted trace can no longer be relocated. |

`relocate` promotes a derived event that lands inside the cut to an **input**: a
message a parent sent into the subtree is not the subtree's own doing, and after
the cut there is no parent left to send it. What it could not carry across comes
back as `Gap`s — an unanswered intent, a name read from an ancestor — reported
beside the result rather than failing instead of one. A relocated trace missing
something is usually missing something that did not matter.

`Place` is an address: `.rows[1].body`. `parse_place` reads one, `label()`
writes one, and `strip_prefix` / `under` move an address down and back up.

## Running one back

Two doors, and which you want depends on whether you own the app.

**`Player` — it mounts its own app**, on the in-memory DOM. This is the
`moon test` door and the one a regression test uses.

```moonbit nocheck
// nocheck: `t` and `scope` are the reader's own
// the one-liner: mount, feed everything, answer the state it reached
let got = @replay.replay(t, scope)

// or step through it
let p = @replay.mount(t, scope)
p.step()        // one whole TURN — the natural step
p.step_event()  // one event, for a viewer's slider
p.run()
inspect(p.html(), content="…")   // cid-normalised, so it compares
p.destroy()
```

**`Driver` — it feeds a transactor you already have.** No app, no DOM, no
mounting: the caller mounted it and the caller renders it. This is how a
recording replays into something already on screen.

```moonbit nocheck
// nocheck: `t`, `app` and `at` are the reader's own
let d = @replay.Driver::new(t, app.transactor, base=at)
d.step()
d.run()
d.stop()        // puts back the recorder it displaced
```

`base` is where the recording's root sits in the tree being fed. A recording cut
to `.rows[0]` addresses its events relative to that; the app it is fed into calls
the same component `.s3.rows[0]`, so every address is re-prefixed on the way in.
Use `Place([])` when the recording IS the tree.

`verify` defaults to whether the aim is narrow enough for a comparison to mean
anything — on under a `base`, off at the root of a tree that holds other things.
At a bare root, everything else sharing the transactor dispatches too, and
holding that against the recording reports a divergence on a rerun that did
nothing wrong.

### What a rerun refuses

- `UnknownVersion` — a reader that does not know a version REFUSES rather than
  guessing, because the failure it would otherwise produce is a replay that
  diverges for a reason nobody can find.
- `RootUnbuildable` — the snapshot names a component this scope cannot build.
- `ShapeChanged` — the component's fields have moved since. This is the one that
  turns "it replays wrong", which could be anything, into "the component
  changed", which is one thing. Never swallow it.
- `Diverged(at~, want~, got~)` — the app dispatched something else, somewhere
  else. Only DERIVED events are compared, and only names and addresses: argument
  values would report a rounding difference as a behavioural change.

`@replay.root_for(t, scope)` applies the first three on their own, for a caller
that is not mounting.

### Intent answers

A rerun answers intents with what the host said last time — `Answers`, per
OCCURRENCE rather than per name, so a host that declined the first time and
answered the second replays as that. `Player` installs this itself.

Driving a shared transactor, install it only around the push and the settle, and
put the live host back:

```moonbit nocheck
// nocheck: `tx` and `recorded` are the reader's own
let live = tx.intents()
tx.set_intents(recorded)
tx.settle() |> ignore
tx.set_intents(live)
```

Narrow on purpose: `Answers` hands out one walk's replies per ask, in order, so
a recorded host left installed while anything ELSE raises an intent spends the
recording's answers on questions it was not answering.

## Files

`@files.FileService` is where a recording goes and where one comes from.

```moonbit nocheck
// nocheck: `svc`, `t`, `file_id`, `load` and `show` are the reader's own
svc.save_text(name=@files.trace_filename("counter"), mime=@files.TRACE_MIME, t.to_jsonl())
svc.read_text(id=file_id, then=r => match r {
  Ok(text) => load(@trace.from_jsonl(text))
  Err(why) => show(why)
})
```

Saving is synchronous and one-way. Reading is neither — the viewer picks the
file, the read is asynchronous, and on wasm-gc a closure cannot cross into JS,
so the answer comes back through a continuation parked on the MoonBit side and
resumed by the page. `id` is the integer a dropped or picked file's descriptor
carries; the `File` itself is a browser object and never becomes a `Value`.

- `@files.MemFiles::new()` — records what was saved, answers reads from a table
  you fill with `provide`. The whole round trip under `moon test`.
- `@fileswasm.browser_files()` — a real download and a real read. The page must
  supply the `tfiles` import namespace and forward an `on_file_text` export, or
  a picked file is read and never delivered.

## The CLI

```sh
tutuca trace app.trace.jsonl                       # what is in it
tutuca trace app.trace.jsonl --trim 40 -o short.jsonl
tutuca trace app.trace.jsonl --at ".rows[1]" -o row.jsonl
```

`--trim` slices lines and never reads an event, so a trace holding an event kind
this build has never heard of shortens just the same. `--at` relocates, and
`--compact` also drops the derived events.

Rebasing is deliberately absent: it means running the app to find out what state
a prefix produced, and a native CLI does not have your compiled components. Use
`Trace::rebase` from a `moon test` block, where one is mounted.

## See also

- [testing.md](./testing.md) — the in-memory `@harness` a rerun's DOM is read
  through, and `Transactor::observe` for watching without recording.
- [storybook.md](./storybook.md) — the Trace tab: recording the gallery,
  cutting a recording to a component, and replaying it into a story.
