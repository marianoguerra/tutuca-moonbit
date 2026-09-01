///| What a value looks like on its way INTO a guest.
///
/// Whitebox, because the two encoders are private and the claim is about them
/// rather than about anything a caller can reach: everything downstream — the
/// guest's own state, what a read hands back, whether `<x render>` has an
/// instance to draw — follows from whether a handle or a copy of some fields
/// crossed here.

///|
/// A stand-in for a guest instance: the one field `child_json` looks for.
priv struct FakeChild {
  handle : Int
}

///|
impl @tutuca.Obj for FakeChild with fn obj_field(self, name) {
  if name == @dyncomp.handle_field {
    Some(Num(self.handle.to_double()))
  } else {
    None
  }
}

///|
fn child(handle : Int) -> @tutuca.Value {
  Obj(FakeChild::{ handle, })
}

///|
/// A constructor's arguments carry the HANDLE, not the instance's fields.
///
/// `Value::to_json` has no form for an `Obj`, so it writes what the object
/// HOLDS — which for an instance is a copy of its state under a name that no
/// longer refers to it. A guest handed that stores a map, answers reads with a
/// map, and a hole declared to hold a component draws nothing at all.
test "an instance in a constructor's args crosses as its handle" {
  inspect(
    map_json({ "child": child(7), "kept": Str("beside it") }),
    content=(
      #|{"child":{"$dyn":{"handle":7}},"kept":"beside it"}
    ),
  )
}

///|
/// The same for a message's arguments, at any depth — a holder is as likely to
/// be filled by `hold(instance)` as by a constructor.
test "an instance in a message's args crosses as its handle" {
  inspect(
    args_json([child(3), Str("x"), List([child(4)])]),
    content=(
      #|[{"$dyn":{"handle":3}},"x",[{"$dyn":{"handle":4}}]]
    ),
  )
}
