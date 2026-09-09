///|
fn render_with_scope_comp() -> @component.Component {
  render_with_scope_component(initial={ text: "Hello", }, bind_with=e => {
    match e {
      EnrichScope =>
        Some((s, _stack) => {
          "len": Num(s.text.length().to_double()),
          "upper": Str(s.text.to_upper()),
        })
    }
  })
}

///|
pub fn render_with_scope_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="render-with-scope",
    components=[render_with_scope_comp()],
    examples=[
      {
        component: "RenderWithScope",
        title: "Default",
        args: Map([]),
        view: None,
      },
      {
        component: "RenderWithScope",
        title: "Custom Text",
        args: { "text": Str("Tutuca") },
        view: None,
      },
    ],
  )
}

///|
/// `enrich` inside a loop MUTATES the binds map it is handed — the return
/// value is Unit. Setting `binds["count"]` makes `@count` readable in the row.
fn list_filter_enrich_comp() -> @component.Component {
  list_filter_enrich_component(
    initial={ items: [], query: "", },
    when=w => {
      match w {
        FilterItem =>
          Some((s, _key, value, _iter, _stack) => {
            match value {
              Str(item) => item.to_lower().contains(s.query.to_lower())
              _ => true
            }
          })
      }
    },
    enrich=e => {
      match e {
        EnrichItem =>
          Some((_s, binds, _key, value, _iter, _stack) => {
            match value {
              Str(item) => binds["count"] = Num(item.length().to_double())
              _ => ()
            }
          })
      }
    },
  )
}

///|
pub fn list_filter_enrich_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="list-filter-enrich",
    components=[list_filter_enrich_comp()],
    examples=[
      {
        component: "ListFilterEnrich",
        title: "Default",
        args: { "items": List(items()) },
        view: None,
      },
    ],
  )
}

///|
/// `@loop-with="get_iter_data"` runs ONCE before the loop and its `iter_data` is
/// handed to every when / enrich call. `queryLower` is lowercased once
/// instead of per item, and `totalChars` is summed over the WHOLE sequence,
/// before any filtering.
fn list_filter_enrich_with_comp() -> @component.Component {
  list_filter_enrich_with_component(
    initial={ items: [], query: "", },
    loop_with=l => {
      match l {
        GetIterData =>
          Some((s, seq, _ctx) => {
            let mut total = 0
            for item in seq.list() {
              match item {
                Str(v) => total += v.length()
                _ => ()
              }
            }
            @component.LoopWith::new(
              iter_data=Map({
                "totalChars": Num(total.to_double()),
                "queryLower": Str(s.query.to_lower()),
              }),
            )
          })
      }
    },
    when=w => {
      match w {
        FilterItem =>
          Some((_s, _key, value, iter, _stack) => {
            match (value, iter) {
              (Str(item), Map(iter_data)) =>
                match iter_data.get("queryLower") {
                  Some(Str(q)) => item.to_lower().contains(q)
                  _ => true
                }
              _ => true
            }
          })
      }
    },
    enrich=e => {
      match e {
        EnrichItem =>
          Some((_s, binds, _key, value, iter, _stack) => {
            match (value, iter) {
              (Str(item), Map(iter_data)) => {
                binds["count"] = Num(item.length().to_double())
                binds["total"] = iter_data.get("totalChars").unwrap_or(Null)
              }
              _ => ()
            }
          })
      }
    },
  )
}

///|
pub fn list_filter_enrich_with_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="list-filter-enrich-with",
    components=[list_filter_enrich_with_comp()],
    examples=[
      {
        component: "ListFilterEnrichWith",
        title: "Default",
        args: { "items": List(items()) },
        view: None,
      },
    ],
  )
}
