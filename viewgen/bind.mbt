// Schema-aware lowering for `@bind`.

///|
fn lower_binds(
  views : Array[CompiledView],
  def : @statedef.StateDef?,
) -> Unit raise GenError {
  for view in views {
    lower_bind_node(view.root, view.raw.name, def, false)
    for events in view.events {
      for handler in events.handlers {
        if handler.binding is Some(_) {
          let mut count = 0
          for h in events.handlers {
            if h.name == handler.name {
              count = count + 1
            }
          }
          if count > 1 {
            raise InvalidBind(
              view=view.raw.name,
              reason="conflicts with an explicit `@on.\{handler.name}` handler on the same element",
            )
          }
        }
      }
    }
  }
}

///|
fn lower_bind_node(
  node : @anode.ANode,
  view : String,
  def : @statedef.StateDef?,
  in_loop : Bool,
) -> Unit raise GenError {
  match node {
    Dom(d) => {
      if d.bind is Some(bind) {
        lower_bind(d, bind, view, def, in_loop)
      }
      for child in d.childs {
        lower_bind_node(child, view, def, in_loop)
      }
    }
    Fragment(d) =>
      for child in d.childs {
        lower_bind_node(child, view, def, in_loop)
      }
    Show(d) | Hide(d) | PushView(d) | Scope(d) =>
      lower_bind_node(d.node, view, def, in_loop)
    Slot(d) => lower_bind_node(d.node, view, def, in_loop)
    Each(d) => lower_bind_node(d.node, view, def, true)
    MacroCall(d) =>
      if d.node is Some(n) {
        lower_bind_node(n, view, def, in_loop)
      }
    Text(_) | Comment(_) | RenderText(_) | Render(_) | RenderIt(_) => ()
  }
}

///|
fn lower_bind(
  dom : @anode.DomData,
  bind : @anode.BindData,
  view : String,
  def : @statedef.StateDef?,
  in_loop : Bool,
) -> Unit raise GenError {
  if in_loop {
    raise InvalidBind(
      view~,
      reason="cannot target loop-item state; bind a direct component field outside `@each`",
    )
  }
  guard bind.target is Field(field_name) else {
    raise InvalidBind(
      view~,
      reason="needs a direct state field such as `.name`",
    )
  }
  guard def is Some(schema) else {
    raise InvalidBind(
      view~,
      reason="needs a `<script type=\"tutuca/spec\">` schema to determine its coercion",
    )
  }
  guard schema.member_ty(field_name) is Some(member_ty) else {
    let schema_name = if schema.component == "" {
      "component"
    } else {
      schema.component
    }
    raise UnknownStateField(
      view~,
      name=field_name,
      scope="the \{schema_name} state",
      suggestion=@statedef.nearest(
        field_name,
        schema.fields.map(f => f.name) + schema.properties.map(p => p.name),
      ),
    )
  }
  if schema.property(field_name) is Some(p) && !p.writable {
    raise InvalidBind(view~, reason="targets read-only property .\{field_name}")
  }
  let input_type = bind_input_type(dom.attrs)
  guard input_type is StaticBindAttr(typ) else {
    raise InvalidBind(
      view~,
      reason="cannot use a dynamic `:type`; the input kind must be statically known",
    )
  }
  let kind : @anode.BindCoercion = match member_ty {
    TText =>
      if dom.tag == "textarea" {
        BindString
      } else if dom.tag == "select" {
        if has_attr(dom.attrs, "multiple") {
          raise InvalidBind(
            view~,
            reason="does not support a multiple `<select>`",
          )
        }
        BindString
      } else if dom.tag == "input" && string_input_types.contains(typ) {
        BindString
      } else {
        raise InvalidBind(
          view~,
          reason="cannot bind String to `<\{dom.tag}>`" + input_suffix(typ),
        )
      }
    TBool =>
      if dom.tag == "input" && typ == "checkbox" {
        BindBool
      } else {
        raise InvalidBind(
          view~,
          reason="can bind Bool only to `<input type=\"checkbox\">`",
        )
      }
    TInt(width~, signed~) =>
      if dom.tag == "input" && (typ == "number" || typ == "range") {
        BindInt(width~, signed~)
      } else {
        raise InvalidBind(
          view~,
          reason="can bind integer fields only to `<input type=\"number\">` or `<input type=\"range\">`",
        )
      }
    TFloat =>
      if dom.tag == "input" && (typ == "number" || typ == "range") {
        BindDouble
      } else {
        raise InvalidBind(
          view~,
          reason="can bind Double only to `<input type=\"number\">` or `<input type=\"range\">`",
        )
      }
    other =>
      raise InvalidBind(
        view~,
        reason="does not support \{other.show_source()}; supported fields are String, Bool, integer scalars, and Double",
      )
  }
  if attr_count(dom.attrs, bind.property) > 1 {
    raise InvalidBind(
      view~,
      reason="conflicts with an explicit `:\{bind.property}`/`\{bind.property}` attribute",
    )
  }
  bind.event.binding = Some(kind)
}

///|
priv enum BindAttrValue {
  StaticBindAttr(String)
  DynamicBindAttr
}

///|
let string_input_types : Set[String] = Set::from_array([
  "", "text", "search", "email", "url", "tel", "password", "date", "month", "week",
  "time", "datetime-local", "color",
])

///|
fn bind_input_type(attrs : @anode.Attrs) -> BindAttrValue {
  match attrs {
    ConstAttrs(m) =>
      match m.get("type") {
        Some(LStr(s)) => StaticBindAttr(s.to_lower())
        _ => StaticBindAttr("")
      }
    DynAttrs(items) => {
      for item in items {
        match item {
          Plain(name="type", val=Const(lit=LStr(s), ..))
          | ConstA(name="type", val=Const(lit=LStr(s), ..)) =>
            return StaticBindAttr(s.to_lower())
          Plain(name="type", ..) => return DynamicBindAttr
          _ => ()
        }
      }
      StaticBindAttr("")
    }
  }
}

///|
fn has_attr(attrs : @anode.Attrs, wanted : String) -> Bool {
  attr_count(attrs, wanted) > 0
}

///|
fn attr_count(attrs : @anode.Attrs, wanted : String) -> Int {
  match attrs {
    ConstAttrs(m) => if m.contains(wanted) { 1 } else { 0 }
    DynAttrs(items) => {
      let mut n = 0
      for item in items {
        match item {
          Plain(name~, ..) | ConstA(name~, ..) if name == wanted => n = n + 1
          If(a) if a.name == wanted => n = n + 1
          _ => ()
        }
      }
      n
    }
  }
}

///|
fn input_suffix(typ : String) -> String {
  if typ == "" {
    ""
  } else {
    " with type `\{typ}`"
  }
}
