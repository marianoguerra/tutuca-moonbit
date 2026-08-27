// The messages a component declares, as a generator of dispatches.
//
// The other half of what a spec block says. `state` gives the values a
// component holds and `handle` gives the ones it answers — and a `MsgDef`
// carries `payload : Array[StateTy]`, which is the same declared-type
// vocabulary `value_of` already walks. So a well-typed dispatch costs nothing
// beyond naming the bucket.
//
// This is the seam the runtime schema cannot serve: `@core.SchemaInfo` carries
// `receives` and `intents` as bare `Array[String]`, with the payload types
// dropped, so a generator built by reflecting off a mounted component could
// name a message but never call it correctly.

///|
/// Which channel a dispatch goes down.
///
/// A message is addressed and an intent is routed, and the difference decides
/// what a walk does with it — so a property that means to exercise one says
/// which rather than drawing from both and hoping.
pub(all) enum Bucket {
  /// `receive` — a message the component answers where it arrives.
  BReceive
  /// `intent` — a request that travels a route.
  BIntent
  /// Either, drawn in proportion to how many of each the spec declares.
  BEither
} derive(Eq, @debug.Debug)

///|
/// One dispatch the component declares it answers, with arguments at their
/// declared types.
///
/// `None` when the bucket is empty — a component that declares no `intent` has
/// no intent to generate, and answering with a made-up name would test the
/// unhandled path while claiming to test the handled one.
pub fn dispatch_of(
  def : @statedef.StateDef,
  bucket? : Bucket = BEither,
  depth? : Int = MAX_DEPTH,
) -> @gen.Gen[@component.Dispatch]? {
  let choices : Array[@gen.Gen[@component.Dispatch]] = []
  if bucket is (BReceive | BEither) {
    for m in def.receive {
      choices.push(
        args_of(def, m, depth).fmap(a => {
          (Receive(m.name, a) : @component.Dispatch)
        }),
      )
    }
  }
  if bucket is (BIntent | BEither) {
    for m in def.intent {
      choices.push(
        args_of(def, m, depth).fmap(a => {
          (Intent(m.name, a) : @component.Dispatch)
        }),
      )
    }
  }
  if choices.is_empty() {
    return None
  }
  // Uniform over the DECLARATIONS rather than over the two buckets: a
  // component with six receives and one intent should mostly be sent
  // receives, because that is the traffic it was written for.
  Some(@gen.one_of(choices))
}

///|
/// A sequence of dispatches — the unit a stateful property quantifies over.
///
/// A single dispatch tests a transition; a sequence tests the component, and
/// only a sequence finds the bug that needs two steps to reach. The empty
/// sequence is included, because "the state a component starts in already
/// breaks an invariant" is a real failure and the shortest one.
pub fn script_of(
  def : @statedef.StateDef,
  bucket? : Bucket = BEither,
  len? : @gen.Gen[Int] = @gen.int_range(0, 8),
  depth? : Int = MAX_DEPTH,
) -> @gen.Gen[Array[@component.Dispatch]]? {
  guard dispatch_of(def, bucket~, depth~) is Some(one) else { return None }
  Some(len.bind(n => one.array_with_size(n)))
}

///|
/// Shrink a dispatch sequence toward the shortest one that still fails.
///
/// Length first, then position: drop the tail, then drop each single step.
/// Written for `@qc.forall_shrink`, and it is what makes a failure readable —
/// a component that breaks on the fourth of eight random messages reports the
/// one message that did it rather than the eight that were sent.
///
/// The ARGUMENTS are deliberately not shrunk. A shorter script is what a
/// reader reproduces by hand; a smaller `Int` inside step three of five is
/// not, and mixing the two makes the search spend its budget on the half that
/// does not help.
pub fn shrink_script(
  script : Array[@component.Dispatch],
) -> Iter[Array[@component.Dispatch]] {
  let out : Array[Array[@component.Dispatch]] = []
  let n = script.length()
  if n == 0 {
    return out.iter()
  }
  // Halves first: the fastest way down from a long script.
  let mut cut = n / 2
  while cut > 0 {
    out.push(script[0:cut].to_owned())
    cut = cut / 2
  }
  // Then each single step removed, which is what isolates the culprit once
  // the halving has stopped helping.
  for i in 0..<n {
    let without : Array[@component.Dispatch] = []
    for j, d in script {
      if j != i {
        without.push(d)
      }
    }
    out.push(without)
  }
  out.iter()
}

///|
/// One message's arguments, at the types it declares them.
fn args_of(
  def : @statedef.StateDef,
  m : @statedef.MsgDef,
  depth : Int,
) -> @gen.Gen[Array[@tutuca.Value]] {
  if m.payload.is_empty() {
    return @gen.pure([])
  }
  @gen.flatten_array(m.payload.map(t => value_of(def, t, depth~)))
}

///|
/// The dispatches a PROTOCOL obliges the component to answer.
///
/// The distinction is worth a second function: `dispatch_of` draws from what
/// this component happens to declare, and this draws from what its contract
/// says every implementor must. A component that conforms should answer the
/// second set as readily as the first, and a property that sends it is testing
/// the protocol rather than the component.
///
/// `None` when the component declares no such protocol, or when the protocol
/// obliges no messages at all.
pub fn protocol_dispatch_of(
  def : @statedef.StateDef,
  protocol_id : String,
  depth? : Int = MAX_DEPTH,
) -> @gen.Gen[@component.Dispatch]? {
  let choices : Array[@gen.Gen[@component.Dispatch]] = []
  for p in def.protocols {
    if p.id != protocol_id {
      continue
    }
    for m in p.handle_message {
      choices.push(
        args_of(def, m, depth).fmap(a => {
          (Receive(m.name, a) : @component.Dispatch)
        }),
      )
    }
    for m in p.handle_intent {
      choices.push(
        args_of(def, m, depth).fmap(a => {
          (Intent(m.name, a) : @component.Dispatch)
        }),
      )
    }
  }
  if choices.is_empty() {
    return None
  }
  Some(@gen.one_of(choices))
}

///|
/// The GENERATED mutators, as dispatches with arguments at the declared types.
///
/// The other half of a component's alphabet, and the half a spec block never
/// spells out: every field brings `setX` / `resetX` / `xLen`, a `Bool` brings
/// `toggleX`, a list and a map bring the `In…At` family, a set brings the
/// membership verbs. A caller who sends only the declared messages is testing
/// the handlers somebody wrote and none of the ones the field kinds wrote.
///
/// They are worth generating for one reason above the rest. An `invariant` is
/// checked after a generated mutator exactly as it is after a hand-written
/// handler — "a generated mutator: after the successor is built" — and a
/// mutator takes an arbitrary value. So `setValues []` is the shortest input
/// that tries to drive a component through its own invariant, and no handler
/// anybody wrote will produce it.
///
/// The NAMES come from `@component.schema_mutators`, which is the table the
/// runtime itself installs: a name this package guessed and the runtime does
/// not have would send a message nothing answers, and look like a passing
/// test. The ARGUMENTS come from the declaration, because that table holds
/// functions and not types.
pub fn mutator_dispatch_of(
  def : @statedef.StateDef,
  depth? : Int = MAX_DEPTH,
) -> @gen.Gen[@component.Dispatch]? {
  let installed = @component.schema_mutators(@info.schema_info(def))
  let choices : Array[@gen.Gen[@component.Dispatch]] = []
  for name, args in mutator_args(def, depth~) {
    // Dropped rather than sent: the join with the runtime's own table is what
    // keeps this from drifting into names nothing answers. `mutator_names`
    // below is the test that the drift never goes the other way.
    if !installed.contains(name) {
      continue
    }
    choices.push(args.fmap(a => (Receive(name, a) : @component.Dispatch)))
  }
  if choices.is_empty() {
    return None
  }
  Some(@gen.one_of(choices))
}

///|
/// Every generated mutator this schema implies, with its arguments.
///
/// Mirrors `component/component.mbt`'s `gen_mutators` arm for arm — the shape
/// of the table is the same, and only the direction differs: that one builds
/// what a name DOES, this builds what it TAKES.
pub fn mutator_args(
  def : @statedef.StateDef,
  depth? : Int = MAX_DEPTH,
) -> Map[String, @gen.Gen[Array[@tutuca.Value]]] {
  let out : Map[String, @gen.Gen[Array[@tutuca.Value]]] = Map([])
  let none : @gen.Gen[Array[@tutuca.Value]] = @gen.pure([])
  for f in def.fields {
    let one = value_of(def, f.ty, depth~).fmap(v => [v])
    out[@tutuca.mutator_name("set", f.name)] = one
    out[@tutuca.mutator_name("reset", f.name)] = none
    out[f.name + "Len"] = none
    match @info.ty_info(def, f.ty).kind() {
      FBool => out[@tutuca.mutator_name("toggle", f.name)] = none
      FSet => {
        // A member, as the string the set is keyed by. Drawn from the declared
        // members when the set is closed, so a `Set[Priority]` is exercised
        // with the enum's own cases rather than with strings it never holds.
        let m = member_of(def, f.ty).fmap(v => [v])
        for verb in ["addIn", "deleteIn", "removeIn", "hasIn", "toggleIn"] {
          out[@tutuca.mutator_name(verb, f.name)] = m
        }
      }
      FList | FMap | FOMap => {
        let elem = f.ty.elem().unwrap_or(TAny)
        // A list is keyed by position and a map by name, which is the same
        // split `mutator_key` makes: `Num` becomes an index, `Str` a key. Both
        // draw OUT of range as well as in — a delete at 99 is the case that
        // decides whether a copy-on-write path answers the original.
        let key = if @info.ty_info(def, f.ty).kind() is FList {
          @gen.int_range(-1, 5).fmap(n => (Num(n.to_double()) : @tutuca.Value))
        } else {
          @gen.one_of_array(["k0", "k1", "absent"]).fmap(s => {
            (Str(s) : @tutuca.Value)
          })
        }
        let v = value_of(def, elem, depth~)
        out[@tutuca.mutator_name("pushIn", f.name)] = v.fmap(x => [x])
        let keyed = @gen.liftA2((k, x) => [k, x], key, v)
        out[@tutuca.mutator_name("insertIn", f.name) + "At"] = keyed
        out[@tutuca.mutator_name("setIn", f.name) + "At"] = keyed
        for verb in ["deleteIn", "removeIn"] {
          out[@tutuca.mutator_name(verb, f.name) + "At"] = key.fmap(k => [k])
        }
      }
      _ => ()
    }
  }
  out
}

///|
/// A member of a set field, as the string the set is keyed by.
fn member_of(
  def : @statedef.StateDef,
  ty : @statedef.StateTy,
) -> @gen.Gen[@tutuca.Value] {
  let members : Array[String] = match ty {
    TFlags(n) =>
      match def.user_ty(n) {
        Some({ kind: UEnum(ms), .. }) => ms.map(m => m.1)
        _ => []
      }
    _ => []
  }
  if members.is_empty() {
    // An OPEN set takes any string, and one it does not hold is as much a
    // member to test with as one it does.
    return @gen.one_of_array(["a", "b", "c", "absent"]).fmap(s => {
      (Str(s) : @tutuca.Value)
    })
  }
  @gen.one_of_array(members.map(m => (Str(m) : @tutuca.Value)))
}
