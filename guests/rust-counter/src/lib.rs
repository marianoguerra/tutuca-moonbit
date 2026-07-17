//! A tutuca:component guest in Rust: opaque native state + tutuca view
//! strings, implementing the same WIT as guests/counter with zero tutuca
//! code. Handlers are functional (self in, self out); the host renders the
//! views and drives everything.

wit_bindgen::generate!({
    path: "wit",
    world: "dynamic-component",
});

use exports::tutuca::component::guest::{
    Bucket, ComponentDef, DomEvent, Guest, GuestInstance, Instance, InstanceBorrow, Manifest,
    ViewDef,
};
use tutuca::component::control;
use tutuca::component::values::Value;

struct Component;

impl Guest for Component {
    type Instance = Counter;

    fn get_manifest() -> Manifest {
        Manifest {
            api_version: 1,
            module_name: "rustcounterlib".into(),
            components: vec![ComponentDef {
                name: "Counter".into(),
                views: vec![ViewDef {
                    name: "main".into(),
                    html: r#"<div class="counter">
  <button class="dec" @on.click="dec">-</button>
  <span class="count" @text=".count"></span>
  <button class="inc" @on.click="inc">+</button>
  <button class="double" @on.click="double">double</button>
  <span class="label" @text="$label"></span>
</div>"#
                        .into(),
                }],
                input_handlers: vec!["inc".into(), "dec".into(), "double".into()],
                receive_handlers: vec!["init".into()],
                response_handlers: vec!["double".into()],
                method_names: vec!["label".into()],
                style: ".counter { display: inline-flex; gap: 0.5em; }".into(),
            }],
        }
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

    fn handle_event(
        &self,
        b: Bucket,
        name: String,
        _event: Option<DomEvent>,
        args: Vec<Value>,
    ) -> Option<Instance> {
        match (b, name.as_str()) {
            (Bucket::Input, "inc") => Counter::next(self.count + 1.0),
            (Bucket::Input, "dec") => Counter::next(self.count - 1.0),
            (Bucket::Input, "double") => {
                control::request("double", &[Value::Number(self.count)]);
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

    fn eq(&self, other: InstanceBorrow<'_>) -> bool {
        self.count == other.get::<Counter>().count
    }

    fn to_json(&self) -> String {
        format!("{{\"count\": {}}}", self.count)
    }
}

export!(Component);
