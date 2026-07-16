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
} derive(Debug)

///|
fn value_repr(v : Value) -> ValueRepr {
  match v {
    Null => RNull
    Bool(b) => RBool(b)
    Num(n) => RNum(n)
    Str(s) => RStr(s)
    List(a) => RList(a.map(value_repr))
    Map(m) => {
      let out : Map[String, ValueRepr] = {}
      for k, x in m {
        out[k] = value_repr(x)
      }
      RMap(out)
    }
    Fn(_) => RFn
    Obj(o) => RObj(o.obj_debug())
  }
}

///|
pub impl Debug for Value with fn to_repr(self) {
  to_repr(value_repr(self))
}
