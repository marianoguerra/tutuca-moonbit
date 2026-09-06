// A type annotation, read out of the shrubbery it is written in.
//
// Unresolved, exactly as the block front end leaves one: `RawTy` carries the
// NAME and the resolution happens once, later, where the file's own `struct`
// and `enum` declarations are in hand.

///|
/// `List.of(String)`, `maybe(Int)`, `Instance.of(P && Q)` — a type as written.
fn ty_of(ex : @sh.Ex, at : Span) -> RawTy raise DefError {
  match ex {
    EName(n) => RNamed(name=n, args=[], span=at)
    ECall(EMember(EName("List"), "of"), args) =>
      RNamed(name="Array", args=[one_ty(args, "List.of", at)], span=at)
    ECall(EMember(EName("Set"), "of"), args) =>
      RNamed(name="Set", args=[one_ty(args, "Set.of", at)], span=at)
    ECall(EMember(EName("Map"), "of"), args) => {
      let pos = @sh.positional_args(args)
      guard pos.length() == 2 else {
        raise Syntax(
          msg="`Map.of` takes a key type and a value type — write `Map.of(String, V)`",
          span=at,
        )
      }
      RNamed(name="Map", args=[ty_of(pos[0], at), ty_of(pos[1], at)], span=at)
    }
    ECall(EMember(EName("Tuple"), "of"), args) => {
      let out : Array[RawTy] = []
      for p in @sh.positional_args(args) {
        out.push(ty_of(p, at))
      }
      RTuple(out, at)
    }
    ECall(EMember(EName("Instance"), "of"), args) => {
      let pos = @sh.positional_args(args)
      guard pos.length() == 1 else {
        raise Syntax(
          msg="`Instance.of` takes one component or protocol set — write `Instance.of(Legend)` or `Instance.of(P && Q)`",
          span=at,
        )
      }
      match pos[0] {
        EBin("&&", _, _) =>
          RNamed(
            name="Instance",
            args=[RProtocolSet(protocol_set(pos[0], at), at)],
            span=at,
          )
        other => RNamed(name="Instance", args=[ty_of(other, at)], span=at)
      }
    }
    ECall(EName("maybe"), args) => ROpt(one_ty(args, "maybe", at), at)
    _ =>
      raise Syntax(
        msg="this is not a type — a type is a name, or one of `List.of`, `Map.of`, `Set.of`, `Tuple.of`, `Instance.of`, `maybe`",
        span=at,
      )
  }
}

///|
fn one_ty(
  args : Array[@sh.Arg],
  what : String,
  at : Span,
) -> RawTy raise DefError {
  let pos = @sh.positional_args(args)
  guard pos.length() == 1 else {
    raise Syntax(msg="`\{what}` takes one type — write `\{what}(T)`", span=at)
  }
  ty_of(pos[0], at)
}

///|
/// `P && Q` — the protocols an instance is constrained by.
fn protocol_set(ex : @sh.Ex, at : Span) -> Array[(String, Span)] raise DefError {
  match ex {
    EBin("&&", a, b) => {
      let out = protocol_set(a, at)
      for p in protocol_set(b, at) {
        out.push(p)
      }
      out
    }
    EName(n) => [(n, at)]
    _ =>
      raise Syntax(
        msg="a protocol set is names joined with `&&` — write `Instance.of(P && Q)`",
        span=at,
      )
  }
}
