// Component definitions (JS Component + the component() builder from oo.js).

///|
let comp_id_counter : Ref[Int] = { val: 0 }

///|
fn next_comp_id() -> Int {
  comp_id_counter.val = comp_id_counter.val + 1
  comp_id_counter.val
}

///|
fn cap_first(s : String) -> String {
  if s.length() == 0 {
    return s
  }
  let head = s[0:1]
  let tail = s[1:]
  head.to_owned().to_upper() + tail.to_owned()
}

///|
priv struct EmptyScope {}

///|
impl @anode.MacroScope for EmptyScope with fn lookup_macro(_self, _name) {
  None
}

///|
/// Generated per-field mutators (oo.js ClassBuilder), JS camelCase names so
/// views port verbatim: set/update/reset/toggle/len/pushIn/setInAt/updateInAt/
/// deleteInAt/removeInAt/insertInAt for list/map/omap, and addIn/deleteIn/
/// removeIn/hasIn/toggleIn for sets. getInAt is the only deferred accessor.
fn gen_mutators(
  fields : Map[String, FieldSpec],
  into : Map[String, MethodFn],
) -> Unit {
  for name, spec in fields {
    let u = cap_first(name)
    into["set" + u] = (inst, args) => {
      inst.set(name, args.get(0).unwrap_or(Null)).to_value()
    }
    into["reset" + u] = (inst, _args) => inst.set(name, spec.default).to_value()
    // the update fn is a plain lambda: it receives ONLY the current value
    into["update" + u] = (inst, args) => {
      match args {
        [Fn(f), ..] => inst.set(name, f([inst.get(name)])).to_value()
        _ => inst.to_value()
      }
    }
    into[name + "Len"] = (inst, _args) => {
      match @tutuca.size_of(inst.get(name)) {
        Some(n) => Num(n.to_double())
        None => Null
      }
    }
    match spec.kind {
      FBool =>
        into["toggle" + u] = (inst, _args) => {
          match inst.get(name) {
            Bool(b) => inst.set(name, Bool(!b)).to_value()
            _ => inst.to_value()
          }
        }
      // Set fields (JS FieldSet.extendProtoForType): membership mutators over
      // the Map-backed set (key = member display string, value Bool(true)).
      FSet => {
        into["addIn" + u] = (inst, args) => {
          match (inst.get(name), args) {
            (Map(m), [v, ..]) => {
              let out = m.copy()
              out[v.to_display_string()] = Bool(true)
              inst.set(name, Map(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
        // JS deleteIn<X> and removeIn<X> alias the same delete (oo.js
        // extendDeleteInAt, called with the bare uname for sets).
        let delete_member = (inst : Instance, args : Array[@tutuca.Value]) => {
          match (inst.get(name), args) {
            (Map(m), [v, ..]) => {
              let out = m.copy()
              out.remove(v.to_display_string()) |> ignore
              inst.set(name, Map(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
        into["deleteIn" + u] = delete_member
        into["removeIn" + u] = delete_member
        into["hasIn" + u] = (inst, args) => {
          match (inst.get(name), args) {
            (Map(m), [v, ..]) => Bool(m.contains(v.to_display_string()))
            _ => Bool(false)
          }
        }
        into["toggleIn" + u] = (inst, args) => {
          match (inst.get(name), args) {
            (Map(m), [v, ..]) => {
              let key = v.to_display_string()
              let out = m.copy()
              if out.contains(key) {
                out.remove(key) |> ignore
              } else {
                out[key] = Bool(true)
              }
              inst.set(name, Map(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
      }
      FList | FMap | FOMap => {
        into["pushIn" + u] = (inst, args) => {
          match (inst.get(name), args) {
            (List(a), [v, ..]) => {
              let out = a.copy()
              out.push(v)
              inst.set(name, List(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
        // JS FieldList.insertIn<X>At(i, v): insert v BEFORE index i (oo.js:221).
        // List-only in JS; harmless on the (currently absent) map case.
        into["insertIn" + u + "At"] = (inst, args) => {
          match (inst.get(name), args) {
            (List(a), [Num(i), v, ..]) => {
              let out = a.copy()
              let at = i.to_int()
              if at >= 0 && at <= out.length() {
                out.insert(at, v)
              } else {
                out.push(v)
              }
              inst.set(name, List(out)).to_value()
            }
            _ => inst.to_value()
          }
        }
        into["setIn" + u + "At"] = (inst, args) => seq_set(inst, name, args)
        into["updateIn" + u + "At"] = (inst, args) => {
          seq_update(inst, name, args)
        }
        // JS names these deleteIn<X>At / removeIn<X>At for KEYED fields:
        // extendProtoForKeyed passes `${uname}At` into extendDeleteInAt
        // (src/oo.js:201). The bare deleteIn<X> / removeIn<X> spelling is the
        // SET-field variant, generated in the FSet arm above. Views like
        // `$removeInItemsAt @key` (docs/examples/todo.js, json.js) depend on it.
        into["deleteIn" + u + "At"] = (inst, args) => {
          seq_delete(inst, name, args)
        }
        into["removeIn" + u + "At"] = (inst, args) => {
          seq_delete(inst, name, args)
        }
      }
      _ => ()
    }
  }
}

///|
fn seq_set(
  inst : Instance,
  field : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match (inst.get(field), args) {
    (List(a), [Num(i), v, ..]) => {
      let idx = i.to_int()
      if idx >= 0 && idx < a.length() {
        let out = a.copy()
        out[idx] = v
        inst.set(field, List(out)).to_value()
      } else {
        inst.to_value()
      }
    }
    (Map(m), [Str(k), v, ..]) => {
      let out = m.copy()
      out[k] = v
      inst.set(field, Map(out)).to_value()
    }
    _ => inst.to_value()
  }
}

///|
fn seq_update(
  inst : Instance,
  field : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match (inst.get(field), args) {
    (List(a), [Num(i), Fn(f), ..]) => {
      let idx = i.to_int()
      if idx >= 0 && idx < a.length() {
        seq_set(inst, field, [Num(i), f([a[idx]])])
      } else {
        inst.to_value()
      }
    }
    (Map(m), [Str(k), Fn(f), ..]) =>
      match m.get(k) {
        Some(cur) => seq_set(inst, field, [Str(k), f([cur])])
        None => inst.to_value()
      }
    _ => inst.to_value()
  }
}

///|
fn seq_delete(
  inst : Instance,
  field : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match (inst.get(field), args) {
    (List(a), [Num(i), ..]) => {
      let idx = i.to_int()
      if idx >= 0 && idx < a.length() {
        let out = a.copy()
        let _ = out.remove(idx)
        inst.set(field, List(out)).to_value()
      } else {
        inst.to_value()
      }
    }
    (Map(m), [Str(k), ..]) => {
      let out = m.copy()
      out.remove(k)
      inst.set(field, Map(out)).to_value()
    }
    _ => inst.to_value()
  }
}

///|
pub fn component(
  name~ : String,
  view~ : String,
  style? : String = "",
  common_style? : String = "",
  global_style? : String = "",
  views? : Map[String, String] = Map([]),
  view_styles? : Map[String, String] = Map([]),
  fields? : Map[String, FieldSpec] = Map([]),
  input? : Map[String, InstanceHandler] = Map([]),
  receive? : Map[String, InstanceHandler] = Map([]),
  bubble? : Map[String, InstanceHandler] = Map([]),
  response? : Map[String, InstanceHandler] = Map([]),
  alter? : Map[String, MethodFn] = Map([]),
  methods? : Map[String, MethodFn] = Map([]),
  provide? : Map[String, String] = Map([]),
  lookup? : Map[String, LookupSpec] = Map([]),
) -> Component {
  let vs : Map[String, @anode.View] = {
    "main": @anode.View::new("main", raw_view=view, style~),
  }
  for vname, raw in views {
    vs[vname] = @anode.View::new(
      vname,
      raw_view=raw,
      style=view_styles.get(vname).unwrap_or(""),
    )
  }
  let all_methods : Map[String, MethodFn] = Map([])
  gen_mutators(fields, all_methods)
  for k, m in methods {
    all_methods[k] = m // user methods win over generated mutators
  }
  {
    id: next_comp_id(),
    name,
    views: vs,
    common_style,
    global_style,
    fields,
    input,
    receive,
    bubble,
    response,
    alter,
    methods: all_methods,
    raw_provide: provide,
    raw_lookup: lookup,
    provide: Map([]),
    lookup: Map([]),
    scope: None,
  }
}

///|
pub fn Component::for_type(
  name~ : String,
  view~ : String,
  style? : String = "",
  views? : Map[String, String] = Map([]),
  provide? : Map[String, String] = Map([]),
  lookup? : Map[String, LookupSpec] = Map([]),
) -> Component {
  component(name~, view~, style~, views~, provide~, lookup~)
}

///|
pub fn Component::get_view(self : Component, name : String?) -> @anode.View? {
  self.views.get(name.unwrap_or("main"))
}

///|
fn split_source(s : String) -> (String, String)? {
  for i in 0..<s.length() {
    if s[i] is '.' {
      let a = s[0:i]
      let b = s[i + 1:]
      if a.length() > 0 && b.length() > 0 {
        return Some((a.to_owned(), b.to_owned()))
      }
      return None
    }
  }
  None
}

///|
pub fn Component::compile(self : Component) -> Unit raise {
  let scope_obj : &@anode.MacroScope = match self.scope {
    Some(s) => s as &@anode.MacroScope
    None => EmptyScope::{  }
  }
  for _, view in self.views {
    view.compile(
      @anode.ParseContext::new(),
      scope_obj,
      cid=LNum(self.id.to_double()),
    )
  }
  for pname, src in self.raw_provide {
    match @tutuca.parse_provide(src, @tutuca.ParseCtx::new()) {
      Some(val) =>
        self.provide[pname] = {
          name: pname,
          val,
          key: { comp: self.id, name: pname },
        }
      None => () // bad shape dropped silently (linter territory)
    }
  }
  for lname, spec in self.raw_lookup {
    match split_source(spec.source) {
      Some((comp_name, provide_name)) => {
        let default_val : @tutuca.Val? = match spec.default {
          Some(d) => @tutuca.parse_field(d, @tutuca.ParseCtx::new())
          None => None
        }
        self.lookup[lname] = {
          name: lname,
          comp_name,
          provide_name,
          default_val,
          producer_key: Pending,
        }
      }
      None => ()
    }
  }
}

///|
pub fn Component::make(
  self : Component,
  args : Map[String, @tutuca.Value],
) -> Instance {
  let fields : Map[String, @tutuca.Value] = Map([])
  for name, spec in self.fields {
    let v = match args.get(name) {
      Some(given) => spec.coerce_or_default(given)
      None =>
        match spec.kind {
          // component-typed default: made through the registration scope
          FComp(comp~, args~) =>
            match self.scope {
              Some(s) =>
                match s.lookup_component(comp) {
                  Some(child) => child.make(args).to_value()
                  None => Null
                }
              None => Null
            }
          _ => spec.default
        }
    }
    fields[name] = v
  }
  { comp: self, fields }
}

///|
pub fn Component::compile_style(self : Component) -> String {
  let sb = StringBuilder()
  if self.common_style != "" {
    sb <+ "[data-cid=\"\{self.id}\"]{\{self.common_style}}\n"
  }
  if self.global_style != "" {
    sb <+ "\{self.global_style}\n"
  }
  for vname, view in self.views {
    if view.style != "" {
      sb <+ "[data-cid=\"\{self.id}\"][data-vid=\"\{vname}\"]{\{view.style}}\n"
    }
  }
  sb.to_string()
}
