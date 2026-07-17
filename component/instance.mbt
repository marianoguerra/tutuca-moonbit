// The Value-backed Instance: COW fields + pre-bound method/handler wrapping
// (the JS Record-with-prototype-symbol, minus runtime classes).

///|
/// Dispatch/handler args carry no this-slot by the time they reach methods;
/// Fn-convention callers (call_handler) prepend one — drop it.
fn drop_this(args : Array[@tutuca.Value]) -> Array[@tutuca.Value] {
  if args.length() > 0 {
    args[1:].to_owned()
  } else {
    []
  }
}

///|
pub fn Instance::get(self : Instance, name : String) -> @tutuca.Value {
  self.fields.get(name).unwrap_or(Null)
}

///|
pub fn Instance::set(
  self : Instance,
  name : String,
  v : @tutuca.Value,
) -> Instance {
  match self.comp.fields.get(name) {
    Some(spec) => {
      let fields = self.fields.copy()
      fields[name] = spec.coerce_or_default(v)
      { comp: self.comp, fields }
    }
    None => self
  }
}

///|
pub fn Instance::to_value(self : Instance) -> @tutuca.Value {
  Obj(self)
}

///|
pub impl @tutuca.Obj for Instance with fn component_id(self) {
  Some(self.comp.id)
}

///|
pub impl @tutuca.Obj for Instance with fn obj_field(self, name) {
  match self.fields.get(name) {
    Some(v) => Some(v)
    // methods surface as self-pre-bound Fns (JS prototype lookup); callers
    // use the Fn convention (element 0 = this), which the binding drops
    None =>
      match self.comp.methods.get(name) {
        Some(m) => Some(Fn(args => m(self, drop_this(args))))
        None => None
      }
  }
}

///|
pub impl @tutuca.Obj for Instance with fn obj_with_field(self, name, v) {
  if self.comp.fields.contains(name) {
    Some(self.set(name, v).to_value())
  } else {
    None
  }
}

///|
pub impl @tutuca.Obj for Instance with fn obj_render_handler(self, name, ns) {
  let m : MethodFn? = match ns {
    Alter =>
      match self.comp.alter.get(name) {
        Some(h) => Some(h)
        None => self.comp.methods.get(name)
      }
    Input => self.comp.methods.get(name)
  }
  match m {
    Some(f) => Fn(args => f(self, drop_this(args)))
    None => Null
  }
}

///|
pub impl @tutuca.Obj for Instance with fn obj_handler(self, bucket, name) {
  let bucket_map : Map[String, InstanceHandler] = match bucket {
    Receive => self.comp.receive
    Input => self.comp.input
    Bubble => self.comp.bubble
    Response => self.comp.response
  }
  match bucket_map.get(name) {
    Some(h) =>
      Some(
        Handler((args, ctx) => {
          match h(self, args, ctx) {
            Some(inst) => Some(inst.to_value() as &@tutuca.PathNode)
            None => None
          }
        }),
      )
    None =>
      // Pre-app-loop convenience (flagged deviation): Input dispatch falls
      // back to methods so `$setTitle 'x'`-style input works; the DOM
      // InputEvent layer revisits this (JS routes those through the stack).
      if bucket is Input {
        match self.comp.methods.get(name) {
          Some(m) =>
            Some(
              Handler((args, _ctx) => {
                match m(self, args) {
                  Obj(_) as nv => Some(nv as &@tutuca.PathNode)
                  _ => None
                }
              }),
            )
          None => None
        }
      } else {
        None
      }
  }
}

///|
pub impl @tutuca.Obj for Instance with fn obj_eq(self, other) {
  if other.component_id() != Some(self.comp.id) {
    return false
  }
  for k, v in self.fields {
    if other.obj_field(k) != Some(v) {
      return false
    }
  }
  true
}

///|
pub impl @tutuca.Obj for Instance with fn obj_debug(self) {
  "\{self.comp.name}\{to_repr(self.fields).to_string()}"
}
