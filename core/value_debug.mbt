// Debug rendering for Value via a parallel derivable shape (the MacroData
// pattern in anode): Fn carries a function and cannot derive, so it renders
// as the opaque RFn.

///|
priv enum ValueRepr {
  RNull
  RBool(Bool)
  RNum(Double)
  RStr(String)
  RList(Array[ValueRepr])
  RMap(Map[String, ValueRepr])
  RFn
  RObj(String)
  RInt(Int64)
  RBin(Bytes)
  RInstant(Int64, Int)
} derive(Debug)

///|
fn value_repr(v : Value) -> ValueRepr {
  match v {
    Null => RNull
    Bool(b) => RBool(b)
    Num(n) => RNum(n)
    Str(s) => RStr(s)
    Int(i) => RInt(i)
    Bin(b) => RBin(b)
    Instant(secs~, nanos~) => RInstant(secs, nanos)
    List(a) => RList(a.map(value_repr))
    Map(m) => {
      let out : Map[String, ValueRepr] = Map([])
      for k, x in m {
        out[k] = value_repr(x)
      }
      RMap(out)
    }
    Fn(_) => RFn
    Obj(o) => RObj(o.debug())
  }
}

///|
pub impl Debug for Value with fn to_repr(self) {
  Repr(value_repr(self))
}
