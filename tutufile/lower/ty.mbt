// A type annotation, printed back into the spelling the state parser reads.
//
// The annotation constructors are ordinary calls to the expression reader, so
// there is no second grammar here — only the table that says `List.of(T)` is
// how `Array[T]` is written now.

///|
/// Print a type annotation as the state parser spells it.
pub fn print_ty(ex : Ex) -> String raise ExError {
  match ex {
    EName(n) => n
    ECall(EMember(EName("List"), "of"), args) =>
      "Array[" + print_ty_arg(args, "List.of") + "]"
    ECall(EMember(EName("Set"), "of"), args) =>
      "Set[" + print_ty_arg(args, "Set.of") + "]"
    ECall(EMember(EName("Instance"), "of"), args) =>
      "Instance[" + print_instance_arg(args) + "]"
    ECall(EMember(EName("Map"), "of"), args) => print_map_ty(args)
    ECall(EMember(EName("Tuple"), "of"), args) => print_tuple_ty(args)
    ECall(EName("maybe"), args) => print_ty_arg(args, "maybe") + "?"
    _ =>
      raise ExError(
        message="this is not a type",
        help="a type is a name, or one of `List.of`, `Map.of`, `Set.of`, `Tuple.of`, `Instance.of`, `maybe`",
        span=@report.Span::at(0),
      )
  }
}

///|
fn print_ty_arg(args : Array[Arg], what : String) -> String raise ExError {
  let pos = positional(args)
  guard pos.length() == 1 else {
    raise ExError(
      message="`\{what}` takes one type",
      help="write `\{what}(T)`",
      span=@report.Span::at(0),
    )
  }
  print_ty(pos[0])
}

///|
fn print_map_ty(args : Array[Arg]) -> String raise ExError {
  let pos = positional(args)
  guard pos.length() == 2 else {
    raise ExError(
      message="`Map.of` takes a key type and a value type",
      help="write `Map.of(String, V)` — a map's key is a string",
      span=@report.Span::at(0),
    )
  }
  "Map[" + print_ty(pos[0]) + ", " + print_ty(pos[1]) + "]"
}

///|
fn print_tuple_ty(args : Array[Arg]) -> String raise ExError {
  let pos = positional(args)
  let parts = []
  for p in pos {
    parts.push(print_ty(p))
  }
  "(" + parts.join(", ") + ")"
}

///|
/// `Instance.of(Name)`, or `Instance.of(P && Q)` for a protocol set.
fn print_instance_arg(args : Array[Arg]) -> String raise ExError {
  let pos = positional(args)
  guard pos.length() == 1 else {
    raise ExError(
      message="`Instance.of` takes one component or protocol set",
      help="write `Instance.of(Legend)` or `Instance.of(P && Q)`",
      span=@report.Span::at(0),
    )
  }
  match pos[0] {
    EBin("&&", _, _) => "protocol " + protocol_set(pos[0])
    other => print_ty(other)
  }
}

///|
fn protocol_set(ex : Ex) -> String raise ExError {
  match ex {
    EBin("&&", a, b) => protocol_set(a) + " & " + protocol_set(b)
    EName(n) => n
    _ =>
      raise ExError(
        message="a protocol set is names joined with `&&`",
        help="write `Instance.of(P && Q)`",
        span=@report.Span::at(0),
      )
  }
}
