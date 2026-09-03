// Per-construct schema components (scalar, object, array, enum, const,
// combinator, conditional, not, boolean, $ref) and the Inspector from-data
// builders that instantiate them. Split from schema.mbt; same package.

///|
impl Composite for SchemaScalarState with fn items(self) {
  self.items
}

///|
impl Composite for SchemaScalarState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for SchemaScalarState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for SchemaScalarState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for SchemaScalarState with fn with_current_page(self, p) {
  { ..self, currentPage: p, }
}

///|
impl Composite for SchemaObjectState with fn items(self) {
  self.items
}

///|
impl Composite for SchemaObjectState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for SchemaObjectState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for SchemaObjectState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for SchemaObjectState with fn with_current_page(self, p) {
  { ..self, currentPage: p, }
}

///|
impl Composite for SchemaArrayState with fn items(self) {
  self.items
}

///|
impl Composite for SchemaArrayState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for SchemaArrayState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for SchemaArrayState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for SchemaArrayState with fn with_current_page(self, p) {
  { ..self, currentPage: p, }
}

///|
impl Composite for SchemaEnumState with fn items(self) {
  self.items
}

///|
impl Composite for SchemaEnumState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for SchemaEnumState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for SchemaEnumState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for SchemaEnumState with fn with_current_page(self, p) {
  { ..self, currentPage: p, }
}

///|
impl Composite for SchemaCombinatorState with fn items(self) {
  self.items
}

///|
impl Composite for SchemaCombinatorState with fn is_expanded(self) {
  self.isExpanded
}

///|
impl Composite for SchemaCombinatorState with fn per_page(self) {
  self.itemsPerPage
}

///|
impl Composite for SchemaCombinatorState with fn current_page(self) {
  self.currentPage
}

///|
impl Composite for SchemaCombinatorState with fn with_current_page(self, p) {
  { ..self, currentPage: p, }
}

///|
/// Primitive type(s): string / number / integer / boolean / null / multi-type.
fn schema_scalar_comp() -> @component.Component {
  schema_scalar_component(
    initial={ ..SchemaScalarState::zero(), itemsPerPage: 10, },
    update=(s, msg, _ctx) => composite_update(s, msg),
    compute=m => {
      match m {
        ArrowText => Some(composite_arrow_text)
        IsItemsEmpty => Some(composite_is_items_empty)
        ShowPagination => Some(composite_show_pagination)
        CannotPrevPage => Some(composite_cannot_prev_page)
        CannotNextPage => Some(composite_cannot_next_page)
        PageIndicatorText => Some(composite_page_indicator_text)
        TypeText => Some((s, _args, _stack) => Str(s.typeLabel))
        CountText => Some((_s, _args, _stack) => Str(""))
      }
    },
    loop_with=l => {
      match l {
        GetPageRange => Some(composite_page_range)
      }
    },
  )
}

///|
fn Inspector::schema_scalar_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(display_type(m, "any")),
    "badges": List(collect_badges(m)),
    "items": List(self.collect_extras(m, "scalar")),
  }
  schema_meta_into(args, m)
  self.make_("SchemaScalar", args~)
}

///|
/// Object schema: property rows (with required markers) plus object-specific
/// branches (additionalProperties / patternProperties / propertyNames).
fn schema_object_comp() -> @component.Component {
  schema_object_component(
    initial={ ..SchemaObjectState::zero(), itemsPerPage: 10, },
    update=(s, msg, _ctx) => composite_update(s, msg),
    compute=m => {
      match m {
        ArrowText => Some(composite_arrow_text)
        IsItemsEmpty => Some(composite_is_items_empty)
        ShowPagination => Some(composite_show_pagination)
        CannotPrevPage => Some(composite_cannot_prev_page)
        CannotNextPage => Some(composite_cannot_next_page)
        PageIndicatorText => Some(composite_page_indicator_text)
        TypeText => Some((s, _args, _stack) => Str(s.typeLabel))
        CountText =>
          Some((s, _args, _stack) => {
            let n = s.items.length()
            Str(if n > 0 { "{\{n}}" } else { "" })
          })
      }
    },
    loop_with=l => {
      match l {
        GetPageRange => Some(composite_page_range)
      }
    },
  )
}

///|
fn Inspector::schema_object_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let required : Array[@tutuca.Value] = match m.get("required") {
    Some(List(r)) => r
    _ => []
  }
  let items : Array[@tutuca.Value] = []
  match m.get("properties") {
    Some(Map(props)) =>
      for k, v in props {
        items.push(
          self.make_("SchemaProperty", args={
            "key": Str(k),
            "required": Bool(required.contains(Str(k))),
            "child": self.classify_schema(v),
          }),
        )
      }
    _ => ()
  }
  match m.get("patternProperties") {
    Some(Map(pats)) =>
      for pat, v in pats {
        items.push(
          self.schema_branch(
            "/\{pat}/",
            self.classify_schema(v),
            label_class="text-secondary",
          ),
        )
      }
    _ => ()
  }
  match m.get("additionalProperties") {
    Some(Map(_) as ap) =>
      items.push(
        self.schema_branch(
          "additional properties",
          self.classify_schema(ap),
          label_class="text-secondary",
        ),
      )
    _ => ()
  }
  match m.get("propertyNames") {
    Some(pn) =>
      items.push(
        self.schema_branch(
          "property names",
          self.classify_schema(pn),
          label_class="text-secondary",
        ),
      )
    None => ()
  }
  items.append(self.collect_extras(m, "object"))
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(display_type(m, "object")),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaObject", args~)
}

///|
/// Array schema: a single `items` schema, or a positional `prefixItems`
/// tuple, plus `contains` and array constraints (as badges).
fn schema_array_comp() -> @component.Component {
  schema_array_component(
    initial={ ..SchemaArrayState::zero(), itemsPerPage: 10, },
    update=(s, msg, _ctx) => composite_update(s, msg),
    compute=m => {
      match m {
        ArrowText => Some(composite_arrow_text)
        IsItemsEmpty => Some(composite_is_items_empty)
        ShowPagination => Some(composite_show_pagination)
        CannotPrevPage => Some(composite_cannot_prev_page)
        CannotNextPage => Some(composite_cannot_next_page)
        PageIndicatorText => Some(composite_page_indicator_text)
        TypeText => Some((s, _args, _stack) => Str(s.typeLabel))
        CountText =>
          Some((s, _args, _stack) => {
            let n = s.items.length()
            Str(if n > 0 { "[\{n}]" } else { "" })
          })
      }
    },
    loop_with=l => {
      match l {
        GetPageRange => Some(composite_page_range)
      }
    },
  )
}

///|
fn Inspector::schema_array_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let items : Array[@tutuca.Value] = []
  let prefix_items : Array[@tutuca.Value]? = match m.get("prefixItems") {
    Some(List(p)) => Some(p)
    _ => None
  }
  let is_tuple = prefix_items is Some(_)
  // Inline a bare primitive item type into the label ("array of string")
  // instead of an expandable `items` row.
  let inline_type : String? = if !is_tuple && !(m.get("items") is Some(List(_))) {
    simple_scalar_type(m.get("items"))
  } else {
    None
  }
  match prefix_items {
    Some(ps) =>
      for i, s in ps {
        items.push(self.schema_branch("item \{i}", self.classify_schema(s)))
      }
    None => ()
  }
  match m.get("items") {
    // draft-07 tuple form
    Some(List(ss)) =>
      for i, s in ss {
        items.push(self.schema_branch("item \{i}", self.classify_schema(s)))
      }
    Some(s) =>
      if inline_type is None {
        items.push(self.schema_branch("items", self.classify_schema(s)))
      }
    None => ()
  }
  match m.get("contains") {
    Some(c) =>
      items.push(self.schema_branch("contains", self.classify_schema(c)))
    None => ()
  }
  items.append(self.collect_extras(m, "array"))
  let type_label = if is_tuple {
    "tuple"
  } else {
    match inline_type {
      Some(t) => "array of \{t}"
      None => display_type(m, "array")
    }
  }
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(type_label),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaArray", args~)
}

///|
/// Enumerated allowed values — each rendered with the value inspector.
fn schema_enum_comp() -> @component.Component {
  schema_enum_component(
    initial={ ..SchemaEnumState::zero(), itemsPerPage: 10, },
    update=(s, msg, _ctx) => composite_update(s, msg),
    compute=m => {
      match m {
        ArrowText => Some(composite_arrow_text)
        IsItemsEmpty => Some(composite_is_items_empty)
        ShowPagination => Some(composite_show_pagination)
        CannotPrevPage => Some(composite_cannot_prev_page)
        CannotNextPage => Some(composite_cannot_next_page)
        PageIndicatorText => Some(composite_page_indicator_text)
        TypeText => Some((s, _args, _stack) => Str(s.typeLabel))
        CountText =>
          Some((s, _args, _stack) => {
            let n = s.items.length()
            Str(if n > 0 { "(\{n})" } else { "" })
          })
      }
    },
    loop_with=l => {
      match l {
        GetPageRange => Some(composite_page_range)
      }
    },
  )
}

///|
fn Inspector::schema_enum_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let members : Array[@tutuca.Value] = match m.get("enum") {
    Some(List(e)) => e
    _ => []
  }
  let items = members.map(v => self.inspect_value(v))
  items.append(self.collect_extras(m, "enum"))
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str("enum"),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaEnum", args~)
}

///|
/// A single constant value — terminal, rendered inline.
fn schema_const_comp() -> @component.Component {
  schema_const_component()
}

///|
/// Combinator: allOf / anyOf / oneOf, subschemas listed without keys.
fn schema_combinator_comp() -> @component.Component {
  schema_combinator_component(
    initial={ ..SchemaCombinatorState::zero(), itemsPerPage: 10, },
    update=(s, msg, _ctx) => composite_update(s, msg),
    compute=m => {
      match m {
        ArrowText => Some(composite_arrow_text)
        IsItemsEmpty => Some(composite_is_items_empty)
        ShowPagination => Some(composite_show_pagination)
        CannotPrevPage => Some(composite_cannot_prev_page)
        CannotNextPage => Some(composite_cannot_next_page)
        PageIndicatorText => Some(composite_page_indicator_text)
        TypeText => Some((s, _args, _stack) => Str(s.typeLabel))
        CountText =>
          Some((s, _args, _stack) => {
            let n = s.items.length()
            Str(if n > 0 { "(\{n})" } else { "" })
          })
      }
    },
    loop_with=l => {
      match l {
        GetPageRange => Some(composite_page_range)
      }
    },
  )
}

///|
fn Inspector::schema_combinator_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let items : Array[@tutuca.Value] = []
  let mut kind = ""
  for k in ["allOf", "anyOf", "oneOf"] {
    if m.get(k) is Some(List(subs)) {
      if kind == "" {
        kind = k
      }
      for s in subs {
        items.push(self.classify_schema(s))
      }
    }
  }
  items.append(self.collect_extras(m, "combinator"))
  let args : Map[String, @tutuca.Value] = {
    "typeLabel": Str(combinator_phrasing(kind)),
    "badges": List(collect_badges(m)),
    "items": List(items),
  }
  schema_meta_into(args, m)
  self.make_("SchemaCombinator", args~)
}

///|
/// Conditional applicator: if / then / else as three labeled regions.
fn schema_conditional_comp() -> @component.Component {
  schema_conditional_component()
}

///|
fn Inspector::schema_conditional_from(
  self : Inspector,
  m : Map[String, @tutuca.Value],
) -> @tutuca.Value {
  let node = (k : String) => {
    match m.get(k) {
      Some(s) => self.classify_schema(s)
      None => Null
    }
  }
  let args : Map[String, @tutuca.Value] = {
    "ifNode": node("if"),
    "thenNode": node("then"),
    "elseNode": node("else"),
  }
  schema_meta_into(args, m)
  self.make_("SchemaConditional", args~)
}

///|
/// Negation: the value must NOT match the wrapped schema.
fn schema_not_comp() -> @component.Component {
  schema_not_component()
}

///|
/// Boolean schemas: `true` accepts any value, `false` accepts none.
fn schema_boolean_comp() -> @component.Component {
  schema_boolean_component(initial={ value: true, }, compute=m => {
    match m {
      Text =>
        Some((s, _args, _stack) => {
          Str(
            if s.value {
              "any value (true)"
            } else {
              "no value allowed (false)"
            },
          )
        })
      CssClass =>
        Some((s, _args, _stack) => {
          let color = if s.value { "text-success" } else { "text-error" }
          Str("font-mono text-sm leading-tight italic schema-boolean \{color}")
        })
    }
  })
}

///|
/// A `$ref`. Rendered as a label only — never resolved/followed, so recursive
/// schemas (`{ "$ref": "#" }`) cannot loop.
fn schema_ref_comp() -> @component.Component {
  schema_ref_component()
}
