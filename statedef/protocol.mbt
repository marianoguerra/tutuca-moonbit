// Static protocol validation. Runtime uses the same ProtocolIssueCode enum;
// this layer adds source spans and severity, which have no meaning after load.

///|
fn protocol_same(a : ProtocolDef, b : ProtocolDef) -> Bool {
  a.handle_message == b.handle_message &&
  a.handle_intent == b.handle_intent &&
  a.express_message == b.express_message &&
  a.express_intent == b.express_intent &&
  a.properties == b.properties &&
  a.views == b.views &&
  a.provides == b.provides &&
  a.lookups == b.lookups
}

///|
pub fn validate_protocols(defs : Array[StateDef]) -> ProtocolValidation {
  let catalog : Map[String, ProtocolDef] = Map([])
  let diagnostics : Array[ProtocolDiagnostic] = []
  let add = (
    code : @tutuca.ProtocolIssueCode,
    def : StateDef,
    id : String,
    member_name : String,
    message : String,
    error : Bool,
    span : Span,
  ) => {
    diagnostics.push({
      code,
      component: def.component,
      protocol_id: id,
      member_name,
      message,
      error,
      span,
    })
  }
  for def in defs {
    for p in def.protocols {
      match catalog.get(p.id) {
        None => catalog[p.id] = p
        Some(first) if protocol_same(first, p) => ()
        Some(_) =>
          add(
            ProtocolDefinitionConflict,
            def,
            p.id,
            "",
            "protocol `\{p.id}` has incompatible declarations",
            true,
            p.span,
          )
      }
    }
  }
  for def in defs {
    for id in def.implements {
      guard catalog.get(id) is Some(p) else {
        add(
          ProtocolUnresolved,
          def,
          id,
          "",
          "protocol `\{id}` is not present in this compilation batch; its implementation is checked at runtime",
          false,
          no_span,
        )
        continue
      }
      for m in p.handle_message {
        let wire = id + "::" + m.name
        if !def.receive
          .iter()
          .any(x => x.name == wire && x.payload == m.payload) {
          add(
            ProtocolMemberMissing,
            def,
            id,
            m.name,
            "missing handled message `\{m.name}`",
            true,
            p.span,
          )
        }
      }
      for m in p.handle_intent {
        let wire = id + "::" + m.name
        if !def.intent.iter().any(x => x.name == wire && x.payload == m.payload) {
          add(
            ProtocolMemberMissing,
            def,
            id,
            m.name,
            "missing handled intent `\{m.name}`",
            true,
            p.span,
          )
        }
      }
      for m in p.express_message {
        let wire = id + "::" + m.name
        if !def.express_message
          .iter()
          .any(x => x.name == wire && x.payload == m.payload) {
          add(
            ProtocolExpressionUndeclared,
            def,
            id,
            m.name,
            "missing expressed message `\{m.name}`",
            true,
            p.span,
          )
        }
      }
      for m in p.express_intent {
        let wire = id + "::" + m.name
        if !def.express_intent
          .iter()
          .any(x => x.name == wire && x.payload == m.payload) {
          add(
            ProtocolExpressionUndeclared,
            def,
            id,
            m.name,
            "missing expressed intent `\{m.name}`",
            true,
            p.span,
          )
        }
      }
      check_bindings(
        def,
        p,
        "property",
        p.properties.map(x => x.name),
        def.property_bindings,
        ProtocolPropertyMissing,
        add,
      )
      check_bindings(
        def,
        p,
        "view",
        p.views,
        def.view_bindings,
        ProtocolViewMissing,
        add,
      )
      check_bindings(
        def,
        p,
        "provide",
        p.provides.map(x => x.name),
        def.provide_bindings,
        ProtocolProvideMissing,
        add,
      )
      check_bindings(
        def,
        p,
        "lookup",
        p.lookups.map(x => x.name),
        def.lookup_bindings,
        ProtocolLookupMissing,
        add,
      )
      check_property_types(def, p, add)
    }
  }
  { mode: if diagnostics.is_empty() { Strict } else { Gradual }, diagnostics, }
}

///|
fn check_property_types(
  def : StateDef,
  protocol : ProtocolDef,
  add : (
    @tutuca.ProtocolIssueCode,
    StateDef,
    String,
    String,
    String,
    Bool,
    Span,
  ) -> Unit,
) -> Unit {
  for property in protocol.properties {
    for b in def.property_bindings {
      if b.protocol_id == protocol.id && b.member_name == property.name {
        match def.properties.iter().find_first(p => p.name == b.source) {
          None =>
            add(
              ProtocolPropertyMissing,
              def,
              protocol.id,
              property.name,
              "property `\{property.name}` binds missing local property `\{b.source}`",
              true,
              b.span,
            )
          Some(implementation) if implementation.ty != property.ty =>
            add(
              ProtocolPropertyType,
              def,
              protocol.id,
              property.name,
              "property `\{property.name}` requires \{property.ty.show_source()}, but `\{b.source}` is \{implementation.ty.show_source()}",
              true,
              b.span,
            )
          Some(implementation) if property.writable && !implementation.writable =>
            add(
              ProtocolPropertyType,
              def,
              protocol.id,
              property.name,
              "property `\{property.name}` is writable, but `\{b.source}` is read-only",
              true,
              b.span,
            )
          Some(_) => ()
        }
      }
    }
  }
}

///|
fn check_bindings(
  def : StateDef,
  protocol : ProtocolDef,
  section : String,
  names : Array[String],
  bindings : Array[ProtocolBinding],
  code : @tutuca.ProtocolIssueCode,
  add : (
    @tutuca.ProtocolIssueCode,
    StateDef,
    String,
    String,
    String,
    Bool,
    Span,
  ) -> Unit,
) -> Unit {
  for name in names {
    if !bindings
      .iter()
      .any(b => b.protocol_id == protocol.id && b.member_name == name) {
      add(
        code,
        def,
        protocol.id,
        name,
        "missing \{section} implementation `\{name}`",
        true,
        protocol.span,
      )
    }
  }
}
