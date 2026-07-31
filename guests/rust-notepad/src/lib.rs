//! A tutuca:component guest in Rust: opaque native state + tutuca view
//! strings, implementing the same WIT as guests/counter with zero tutuca
//! code. Handlers are functional (self in, self out); the host renders the
//! views and drives everything.
//!
//! A tabbed notepad rather than another counter, because a counter never has
//! to answer the two questions the contract's newer halves exist for: what a
//! component keeps that its declared fields do not name (which tab you were
//! looking at), and how it comes back after the page goes away.

// The repo's ONE WIT source (see guests/guests.mjs) — guests keep no copy, so
// a guest cannot silently implement a different contract than the host.
wit_bindgen::generate!({
    path: "../../dyncomp/wit",
    world: "dynamic-component",
});

use exports::tutuca::component::guest::{
    Bucket, ComponentDef, Constraint, FieldDef, Guest, GuestInstance, InitDef, Instance, Manifest,
    NamedDoc, RequestResult, TyDef, TyKind, ViewDef,
};
use tutuca::component::values::{self, Value};

struct Component;

/// Indices into the component's type table (WIT has no recursive types, so a
/// compound names its parts by index).
const TY_FLOAT: u32 = 1;
const TY_TAB: u32 = 2;
const TY_TABS: u32 = 3;

impl Guest for Component {
    type Instance = Notepad;

    fn get_manifest() -> Manifest {
        Manifest {
            api_version: 4,
            module_name: "rustnotepadlib".into(),
            doc: "The polyglot proof: the same contract, in Rust, with no tutuca code.".into(),
            version: "0.4.0".into(),
            homepage: "".into(),
            authors: vec![],
            // It asks the host for nothing — no clock, no randomness, no timer.
            capabilities: vec![],
            components: vec![ComponentDef {
                name: "Notepad".into(),
                doc: "Notes in tabs: add one, rename it, type in it, throw it away.".into(),
                keywords: vec![
                    "notes".into(),
                    "notepad".into(),
                    "tabs".into(),
                    "text".into(),
                    "rust".into(),
                ],
                category: "editor".into(),
                message_docs: vec![
                    NamedDoc {
                        name: "addTab".into(),
                        doc: "Start a new note and open it.".into(),
                    },
                    NamedDoc {
                        name: "removeAt".into(),
                        doc: "Throw away the note at an index.".into(),
                    },
                    NamedDoc {
                        name: "renameSelected".into(),
                        doc: "Rename the open note.".into(),
                    },
                    NamedDoc {
                        name: "edit".into(),
                        doc: "Replace the open note's text.".into(),
                    },
                    NamedDoc {
                        name: "summary".into(),
                        doc: "How many notes there are, and how long this one is.".into(),
                    },
                    NamedDoc {
                        name: "tabName".into(),
                        doc: "The open note's name, for the rename box.".into(),
                    },
                    NamedDoc {
                        name: "content".into(),
                        doc: "The open note's text, for the textarea.".into(),
                    },
                ],
                views: vec![ViewDef {
                    name: "main".into(),
                    // margaui (daisyUI) classes, matching the universal demo's
                    // styling; the "rust" badge marks this as the Rust guest.
                    //
                    // `setSelected` is NOT a handler this guest implements: it
                    // is the mutator the declared `selected` field implies, so
                    // switching tabs is the host writing a field through
                    // with-field and never reaching guest logic at all.
                    html: r#"<div class="card bg-base-100 border border-base-300 shadow-sm w-96 notepad">
  <div class="card-body gap-2 p-4">
    <div class="flex items-center gap-2">
      <span class="badge badge-sm badge-warning">rust</span>
      <span class="text-xs opacity-70 grow summary" @text="$summary"></span>
      <button class="btn btn-xs btn-primary add-tab" @on.click="addTab">+ note</button>
    </div>
    <div role="tablist" class="tabs tabs-box tabs-xs">
      <span class="flex items-center" @each=".tabs">
        <button role="tab" @on.click="setSelected @key"
                @if.class="@value.active" @then="'tab tab-active notepad-tab'" @else="'tab notepad-tab'"
                @text="@value.name"></button>
        <button class="btn btn-ghost btn-xs btn-circle drop-tab" @on.click="removeAt @key">&#10005;</button>
      </span>
    </div>
    <input class="input input-bordered input-xs w-full rename" placeholder="note name"
           :value="$tabName" @on.input="renameSelected value" />
    <textarea class="textarea textarea-bordered w-full h-40 note-body" placeholder="type here&#8230;"
              :value="$content" @on.input="edit value"></textarea>
  </div>
</div>"#
                        .into(),
                }],
                // The declared state. The host builds a schema from it, and
                // with it come equality, the JSON projection and the generated
                // `setSelected` mutator — none of them written here.
                types: vec![
                    TyDef {
                        kind: TyKind::TyText,
                        elem: None,
                        items: vec![],
                        name: "".into(),
                        members: vec![],
                    },
                    TyDef {
                        kind: TyKind::TyFloat,
                        elem: None,
                        items: vec![],
                        name: "".into(),
                        members: vec![],
                    },
                    TyDef {
                        kind: TyKind::TyRecord,
                        elem: None,
                        items: vec![],
                        name: "note-tab".into(),
                        members: vec![],
                    },
                    TyDef {
                        kind: TyKind::TyList,
                        elem: Some(TY_TAB),
                        items: vec![],
                        name: "".into(),
                        members: vec![],
                    },
                ],
                fields: vec![
                    FieldDef {
                        name: "tabs".into(),
                        ty: TY_TABS,
                        doc: "The notes, in the order they were started.".into(),
                        required: false,
                        constraint: None,
                    },
                    FieldDef {
                        name: "selected".into(),
                        ty: TY_FLOAT,
                        doc: "Which note is open, by index.".into(),
                        required: false,
                        constraint: Some(Constraint {
                            min: Some(0.0),
                            max: None,
                            min_len: None,
                            max_len: None,
                            pattern: "".into(),
                            format: "".into(),
                            enum_json: "".into(),
                            default_json: "".into(),
                        }),
                    },
                ],
                // `setSelected` is absent on purpose: the `selected` field
                // implies it, and the host answers it through `with_field`.
                handlers: vec![
                    "addTab".into(),
                    "removeAt".into(),
                    "renameSelected".into(),
                    "edit".into(),
                ],
                receives: vec!["init".into()],
                bubbles: vec![],
                responses: vec![],
                methods: vec!["summary".into(), "tabName".into(), "content".into()],
                whens: vec![],
                requests: vec![],
                inits: vec![InitDef {
                    name: "scratch".into(),
                    args_json: r#"{"tabs":[{"name":"scratch","content":"notes go here"},{"name":"todo","content":""}],"selected":0}"#
                        .into(),
                    doc: "Two notes, one of them already written in.".into(),
                }],
                // styling is entirely margaui (daisyUI) classes; no fallback CSS
                style: "".into(),
            }],
        }
    }

    /// This bundle serves no requests of its own.
    fn handle_request(name: String, _args: Vec<Value>) -> RequestResult {
        RequestResult::Err(Value::Text(format!("rustnotepadlib: no request {name}")))
    }
}

#[derive(Clone)]
pub struct Tab {
    name: String,
    content: String,
}

pub struct Notepad {
    tabs: Vec<Tab>,
    /// Which tab is open. Kept in range by everything that can move it, so no
    /// reader has to bounds-check the answer.
    selected: usize,
}

impl Notepad {
    fn next(tabs: Vec<Tab>, selected: usize) -> Option<Instance> {
        let selected = clamp(selected, tabs.len());
        Some(Instance::new(Notepad { tabs, selected }))
    }

    fn open(&self) -> Option<&Tab> {
        self.tabs.get(self.selected)
    }

    /// The declared `tabs` field, as the view iterates it.
    ///
    /// `active` rides with each tab rather than being compared in the view,
    /// because `@each` takes a FIELD and not a method (a method result has no
    /// addressable path, so nothing could be dispatched against it). It is
    /// DERIVED on every read — `selected` said a second way — so the two
    /// cannot drift, and a write that carries a stale one is simply ignored.
    fn tabs_value(&self) -> Value {
        let list = values::list_new();
        for (i, tab) in self.tabs.iter().enumerate() {
            let m = values::map_new();
            values::map_set(m, "name", &Value::Text(tab.name.clone()));
            values::map_set(m, "content", &Value::Text(tab.content.clone()));
            values::map_set(m, "active", &Value::Boolean(i == self.selected));
            values::list_push(list, &Value::Map(m));
        }
        Value::List(list)
    }
}

/// An index that is always a tab, or 0 for a notepad with none.
fn clamp(i: usize, len: usize) -> usize {
    if len == 0 {
        0
    } else if i >= len {
        len - 1
    } else {
        i
    }
}

/// The loop `@key` a per-item handler carries, as an index.
fn key_index(args: &[Value]) -> Option<usize> {
    match args.first() {
        Some(Value::Number(n)) if *n >= 0.0 => Some(*n as usize),
        _ => None,
    }
}

fn text_arg(args: &[Value]) -> Option<String> {
    match args.first() {
        Some(Value::Text(s)) => Some(s.clone()),
        _ => None,
    }
}

/// The host's list-of-maps, back into tabs. Both a fresh instance (constructor
/// args, including the ones a hot swap or a field-restore hands back) and a
/// `with_field` write arrive in this shape.
fn tabs_of(handle: u64) -> Vec<Tab> {
    let mut out = Vec::new();
    for i in 0..values::list_len(handle) {
        let Value::Map(m) = values::list_get(handle, i) else {
            continue;
        };
        let name = match values::map_get(m, "name") {
            Some(Value::Text(s)) => s,
            _ => String::new(),
        };
        let content = match values::map_get(m, "content") {
            Some(Value::Text(s)) => s,
            _ => String::new(),
        };
        out.push(Tab { name, content });
    }
    out
}

// --- persistence -------------------------------------------------------------
//
// The format is this guest's own business: the host stores the bytes and hands
// them back without looking. Length-prefixed rather than JSON because a note is
// arbitrary text — escaping is where a hand-rolled format goes wrong, and a
// byte count cannot be confused by anything the text contains.
//
//   tutuca-notepad/1\n<selected>\n<tab count>\n
//   then per tab: <name bytes>\n<name><content bytes>\n<content>

const PERSIST_TAG: &str = "tutuca-notepad/1";

fn persist_bytes(state: &Notepad) -> Vec<u8> {
    let mut out = String::new();
    out.push_str(PERSIST_TAG);
    out.push('\n');
    out.push_str(&state.selected.to_string());
    out.push('\n');
    out.push_str(&state.tabs.len().to_string());
    out.push('\n');
    for tab in &state.tabs {
        out.push_str(&tab.name.len().to_string());
        out.push('\n');
        out.push_str(&tab.name);
        out.push_str(&tab.content.len().to_string());
        out.push('\n');
        out.push_str(&tab.content);
    }
    out.into_bytes()
}

/// A reader over the bytes above. Every step can fail, and every failure means
/// the same thing: this is not what this version wrote, so refuse it and let
/// the host rebuild from the declared fields instead.
struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}

impl<'a> Reader<'a> {
    fn line(&mut self) -> Option<&'a str> {
        let end = self.bytes.get(self.at..)?.iter().position(|b| *b == b'\n')? + self.at;
        let s = std::str::from_utf8(&self.bytes[self.at..end]).ok()?;
        self.at = end + 1;
        Some(s)
    }

    fn count(&mut self) -> Option<usize> {
        self.line()?.parse::<usize>().ok()
    }

    /// A length-prefixed run of text. The count is BYTES, so a note full of
    /// emoji reads back exactly as it was written.
    fn chunk(&mut self) -> Option<String> {
        let len = self.count()?;
        let end = self.at.checked_add(len)?;
        if end > self.bytes.len() {
            return None;
        }
        let s = std::str::from_utf8(&self.bytes[self.at..end]).ok()?.to_string();
        self.at = end;
        Some(s)
    }
}

fn restore_bytes(state: &[u8]) -> Option<Notepad> {
    let mut r = Reader {
        bytes: state,
        at: 0,
    };
    if r.line()? != PERSIST_TAG {
        return None;
    }
    let selected = r.count()?;
    let count = r.count()?;
    let mut tabs = Vec::with_capacity(count);
    for _ in 0..count {
        let name = r.chunk()?;
        let content = r.chunk()?;
        tabs.push(Tab { name, content });
    }
    let selected = clamp(selected, tabs.len());
    Some(Notepad { tabs, selected })
}

impl GuestInstance for Notepad {
    fn new(_component: String, args: Vec<(String, Value)>) -> Self {
        let mut tabs = Vec::new();
        let mut selected = 0usize;
        for (name, v) in args {
            match (name.as_str(), v) {
                ("tabs", Value::List(h)) => tabs = tabs_of(h),
                ("selected", Value::Number(n)) if n >= 0.0 => selected = n as usize,
                _ => {}
            }
        }
        // A notepad with no notes has nothing to type in, so a fresh one comes
        // with the first note already open.
        if tabs.is_empty() {
            tabs.push(Tab {
                name: "note 1".into(),
                content: String::new(),
            });
        }
        let selected = clamp(selected, tabs.len());
        Notepad { tabs, selected }
    }

    /// Bytes back into an instance. `component` is checked rather than assumed:
    /// a bundle can declare several, and bytes one of them wrote say nothing
    /// about another.
    fn restore(component: String, state: Vec<u8>) -> Option<Instance> {
        if component != "Notepad" {
            return None;
        }
        restore_bytes(&state).map(Instance::new)
    }

    fn get_field(&self, name: String) -> Option<Value> {
        match name.as_str() {
            "tabs" => Some(self.tabs_value()),
            "selected" => Some(Value::Number(self.selected as f64)),
            _ => None,
        }
    }

    fn seq_entries(&self) -> Option<Vec<(String, Value)>> {
        None
    }

    fn handle_event(&self, b: Bucket, name: String, args: Vec<Value>) -> Option<Instance> {
        // There is no "setSelected" case: `selected` is a declared field, so
        // the host generates the mutator and writes it through `with_field`.
        // A handler here would be the same assignment written twice.
        if !matches!(b, Bucket::Input) {
            return None;
        }
        match name.as_str() {
            "addTab" => {
                let mut tabs = self.tabs.clone();
                tabs.push(Tab {
                    name: format!("note {}", tabs.len() + 1),
                    content: String::new(),
                });
                let last = tabs.len() - 1;
                Notepad::next(tabs, last)
            }
            // Removing the open note opens the one before it, which is where a
            // person's attention already is; removing the last one leaves an
            // empty notepad rather than refusing.
            "removeAt" => {
                let i = key_index(&args)?;
                if i >= self.tabs.len() {
                    return None;
                }
                let mut tabs = self.tabs.clone();
                tabs.remove(i);
                let selected = if self.selected > i {
                    self.selected - 1
                } else {
                    self.selected
                };
                Notepad::next(tabs, selected)
            }
            "renameSelected" => {
                let name = text_arg(&args)?;
                let mut tabs = self.tabs.clone();
                let tab = tabs.get_mut(self.selected)?;
                tab.name = name;
                Notepad::next(tabs, self.selected)
            }
            "edit" => {
                let content = text_arg(&args)?;
                let mut tabs = self.tabs.clone();
                let tab = tabs.get_mut(self.selected)?;
                tab.content = content;
                Notepad::next(tabs, self.selected)
            }
            _ => None,
        }
    }

    fn call_method(&self, name: String, _args: Vec<Value>) -> Value {
        match name.as_str() {
            "summary" => {
                let chars = self.open().map(|t| t.content.chars().count()).unwrap_or(0);
                Value::Text(format!(
                    "{} note{} · {} character{}",
                    self.tabs.len(),
                    if self.tabs.len() == 1 { "" } else { "s" },
                    chars,
                    if chars == 1 { "" } else { "s" },
                ))
            }
            "tabName" => Value::Text(self.open().map(|t| t.name.clone()).unwrap_or_default()),
            "content" => Value::Text(self.open().map(|t| t.content.clone()).unwrap_or_default()),
            _ => Value::Nil,
        }
    }

    fn with_field(&self, name: String, v: Value) -> Option<Instance> {
        match (name.as_str(), v) {
            ("tabs", Value::List(h)) => Notepad::next(tabs_of(h), self.selected),
            ("selected", Value::Number(n)) if n >= 0.0 => {
                Notepad::next(self.tabs.clone(), n as usize)
            }
            _ => None,
        }
    }

    /// Everything, including which tab is open — the half `tabs` does not say,
    /// and the half a person notices is missing.
    fn persist(&self) -> Vec<u8> {
        persist_bytes(self)
    }
}

export!(Component);
