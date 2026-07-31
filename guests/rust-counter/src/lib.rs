//! A tutuca:component guest in Rust: opaque native state + tutuca view
//! strings, implementing the same WIT as guests/counter with zero tutuca
//! code. Handlers are functional (self in, self out); the host renders the
//! views and drives everything.

// The repo's ONE WIT source (see guests/guests.mjs) — guests keep no copy, so
// a guest cannot silently implement a different contract than the host.
wit_bindgen::generate!({
    path: "../../dyncomp/wit",
    world: "dynamic-component",
});

use exports::tutuca::component::guest::{
    Bucket, ComponentDef, Constraint, FieldDef, Guest, GuestInstance, Instance, Manifest, NamedDoc,
    RequestResult, TyDef, TyKind, ViewDef,
};
use tutuca::component::control::{self, RequestOpts};
use tutuca::component::values::Value;

struct Component;

impl Guest for Component {
    type Instance = Counter;

    fn get_manifest() -> Manifest {
        Manifest {
            api_version: 3,
            module_name: "rustcounterlib".into(),
            doc: "The polyglot proof: the same contract, in Rust, with no tutuca code.".into(),
            version: "0.3.0".into(),
            homepage: "".into(),
            authors: vec![],
            // It asks the host for nothing — no clock, no randomness, no timer.
            capabilities: vec![],
            components: vec![ComponentDef {
                name: "Counter".into(),
                doc: "A number with buttons that raise and lower it.".into(),
                keywords: vec!["counter".into(), "number".into(), "rust".into()],
                category: "input".into(),
                message_docs: vec![
                    NamedDoc {
                        name: "inc".into(),
                        doc: "Add one.".into(),
                    },
                    NamedDoc {
                        name: "dec".into(),
                        doc: "Subtract one.".into(),
                    },
                    NamedDoc {
                        name: "double".into(),
                        doc: "Ask the host to double the count.".into(),
                    },
                    NamedDoc {
                        name: "label".into(),
                        doc: "The count as a sentence, for a view.".into(),
                    },
                ],
                views: vec![ViewDef {
                    name: "main".into(),
                    // margaui (daisyUI) classes, matching the universal demo's
                    // styling; the "rust" badge marks this as the Rust guest
                    html: r#"<div class="card bg-base-100 border border-base-300 shadow-sm counter">
  <div class="card-body gap-2 items-center p-4">
    <span class="badge badge-sm badge-warning">rust</span>
    <div class="join">
      <button class="btn btn-sm join-item dec" @on.click="dec">−</button>
      <span class="btn btn-sm join-item no-animation pointer-events-none count" @text=".count"></span>
      <button class="btn btn-sm join-item inc" @on.click="inc">+</button>
    </div>
    <button class="btn btn-sm btn-secondary double" @on.click="double">double</button>
    <span class="text-sm opacity-70 label" @text="$label"></span>
  </div>
</div>"#
                        .into(),
                }],
                // The declared state. The host builds a schema from it, and
                // with it come equality, the JSON projection and the
                // generated `setCount` mutator — none of them written here.
                types: vec![TyDef {
                    kind: TyKind::TyFloat,
                    elem: None,
                    items: vec![],
                    name: "".into(),
                    members: vec![],
                }],
                fields: vec![FieldDef {
                    name: "count".into(),
                    ty: 0,
                    doc: "The current value.".into(),
                    required: false,
                    constraint: Some(Constraint {
                        min: Some(-1000.0),
                        max: Some(1000.0),
                        min_len: None,
                        max_len: None,
                        pattern: "".into(),
                        format: "".into(),
                        enum_json: "".into(),
                        default_json: "".into(),
                    }),
                }],
                handlers: vec!["inc".into(), "dec".into(), "double".into()],
                receives: vec!["init".into()],
                bubbles: vec![],
                responses: vec!["double".into()],
                methods: vec!["label".into()],
                whens: vec![],
                requests: vec![],
                inits: vec![],
                // styling is entirely margaui (daisyUI) classes; no fallback CSS
                style: "".into(),
            }],
        }
    }

    /// This bundle serves no requests of its own; "double" is the host's.
    fn handle_request(name: String, _args: Vec<Value>) -> RequestResult {
        RequestResult::Err(Value::Text(format!("rustcounterlib: no request {name}")))
    }
}

pub struct Counter {
    count: f64,
}

impl Counter {
    fn next(count: f64) -> Option<Instance> {
        Some(Instance::new(Counter { count }))
    }
}

impl GuestInstance for Counter {
    fn new(_component: String, args: Vec<(String, Value)>) -> Self {
        let mut count = 0.0;
        for (name, v) in args {
            if name == "count" {
                if let Value::Number(n) = v {
                    count = n;
                }
            }
        }
        Counter { count }
    }

    fn get_field(&self, name: String) -> Option<Value> {
        match name.as_str() {
            "count" => Some(Value::Number(self.count)),
            _ => None,
        }
    }

    fn seq_entries(&self) -> Option<Vec<(String, Value)>> {
        None
    }

    fn handle_event(&self, b: Bucket, name: String, args: Vec<Value>) -> Option<Instance> {
        match (b, name.as_str()) {
            (Bucket::Input, "inc") => Counter::next(self.count + 1.0),
            (Bucket::Input, "dec") => Counter::next(self.count - 1.0),
            (Bucket::Input, "double") => {
                control::request(
                    "double",
                    &[Value::Number(self.count)],
                    &RequestOpts {
                        on_ok: None,
                        on_error: None,
                        on_res: None,
                        live_path: false,
                    },
                );
                None
            }
            (Bucket::Response, "double") => match args.first() {
                Some(Value::Number(n)) => Counter::next(*n),
                _ => None,
            },
            _ => None,
        }
    }

    fn call_method(&self, name: String, _args: Vec<Value>) -> Value {
        match name.as_str() {
            "label" => Value::Text(format!("rust count is {}", self.count)),
            _ => Value::Nil,
        }
    }

    fn with_field(&self, name: String, v: Value) -> Option<Instance> {
        match (name.as_str(), v) {
            ("count", Value::Number(n)) => Counter::next(n),
            _ => None,
        }
    }
}

export!(Component);
