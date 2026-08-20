///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// The todo guest module: a single `tutuca:component` with opaque native
/// state (a list of items + a draft string), styled with margaui utility
/// classes. Mirrors guests/counter — one struct implementing `DynComponent`
/// plus a `dyn_module()` factory — but exercises per-item events: the host
/// renders `<li @each=".items">` and forwards the loop `@key` (and the input
/// `value`/`isSend`) as handler args, so a single opaque instance handles
/// toggle/remove/add without nested children.
///
/// Its static declaration and view live beside the module; sdk.mbt does the ABI.

///|
priv struct TodoItem {
  text : String
  done : Bool
}

///|
priv struct Todo {
  items : Array[TodoItem]
  draft : String
}

///|
/// A list Value of {text, done} maps for the host to iterate with @each.
fn Todo::items_value(self : Todo) -> @values.Value {
  let l = @values.list_new()
  for it in self.items {
    let m = @values.map_new()
    @values.map_set(m, "text", @values.Value::Text(it.text))
    @values.map_set(m, "done", @values.Value::Boolean(it.done))
    @values.list_push(l, @values.Value::Map(m))
  }
  @values.Value::List(l)
}

///|
/// Parse a loop @key arg (a list index) into an Int; tolerate Number or Text.
fn key_index(args : Array[@values.Value]) -> Int? {
  // an @each over a list field passes the loop index as a Number
  match args {
    [@values.Value::Number(n), ..] => Some(n.to_int())
    _ => None
  }
}

///|
impl DynComponent for Todo with fn get_field(self, name) {
  match name {
    "draft" => Some(@values.Value::Text(self.draft))
    "items" => Some(self.items_value())
    _ => None
  }
}

///|
impl DynComponent for Todo with fn handle(self, bucket, name, args) {
  guard bucket is RECEIVE else { return Unhandled }
  match name {
    // There is no "setDraft" case: `draft` is a declared field, so the host
    // generates `setDraft` from the schema and writes it through `with_field`
    // below. A handler here would be the same assignment written twice.
    // Add button, or Enter in the input via `addOnEnter isSend`
    "add" => handled(self.add_draft())
    "addOnEnter" =>
      match args {
        [@values.Value::Boolean(true), ..] => handled(self.add_draft())
        _ => Unchanged
      }
    // `@on.input="toggleAt @key"` / `@on.click="removeAt @key"` carry the
    // loop index (see key_index)
    "toggleAt" =>
      match key_index(args) {
        Some(i) => handled(self.toggle_at(i))
        None => Unchanged
      }
    "removeAt" =>
      match key_index(args) {
        Some(i) => handled(self.remove_at(i))
        None => Unchanged
      }
    "clearDone" => {
      let kept = self.items.filter(it => !it.done)
      Changed({ items: kept, draft: self.draft } as &DynComponent)
    }
    _ => Unhandled
  }
}

///|
fn Todo::add_draft(self : Todo) -> &DynComponent? {
  let text = self.draft.trim(chars=" ").to_owned()
  guard text != "" else { return None }
  let items = self.items.copy()
  items.push({ text, done: false })
  Some({ items, draft: "" } as &DynComponent)
}

///|
fn Todo::toggle_at(self : Todo, i : Int) -> &DynComponent? {
  guard i >= 0 && i < self.items.length() else { return None }
  let items = self.items.copy()
  let it = items[i]
  items[i] = { text: it.text, done: !it.done }
  Some({ items, draft: self.draft } as &DynComponent)
}

///|
fn Todo::remove_at(self : Todo, i : Int) -> &DynComponent? {
  guard i >= 0 && i < self.items.length() else { return None }
  let items = self.items.copy()
  items.remove(i) |> ignore
  Some({ items, draft: self.draft } as &DynComponent)
}

///|
/// `$summary` — a render-time view method (count of done / total).
impl DynComponent for Todo with fn call_method(self, name, _args) {
  match name {
    "summary" => {
      let total = self.items.length()
      let done = self.items.filter(it => it.done).length()
      @values.Value::Text("Todo — \{done}/\{total} done")
    }
    _ => @values.Value::Nil
  }
}

///|
/// The COW write-through every declared field needs: it is what the host's
/// generated mutators (`setDraft`, `pushInItems`, `removeInItemsAt`, …) write
/// through, and what a host path writes through to reach this instance.
impl DynComponent for Todo with fn with_field(self, name, v) {
  match (name, v) {
    ("draft", @values.Value::Text(s)) =>
      Some({ items: self.items, draft: s } as &DynComponent)
    ("items", @values.Value::List(h)) =>
      Some({ items: items_of(h), draft: self.draft } as &DynComponent)
    _ => None
  }
}

///|
/// The inverse of `items_value`: a host list of {text, done} maps back into
/// items. Both a fresh instance (constructor args, including the ones hot-swap
/// migration hands back) and a `with_field` write arrive in this shape.
fn items_of(h : UInt64) -> Array[TodoItem] {
  let items : Array[TodoItem] = []
  for i in 0U..<@values.list_len(h) {
    match @values.list_get(h, i) {
      @values.Value::Map(mh) => {
        let text = match @values.map_get(mh, "text") {
          Some(@values.Value::Text(t)) => t
          _ => ""
        }
        let done = match @values.map_get(mh, "done") {
          Some(@values.Value::Boolean(b)) => b
          _ => false
        }
        items.push({ text, done })
      }
      _ => ()
    }
  }
  items
}

///|
/// The whole state as UTF-8 JSON — the bytes the host stores and hands back.
///
/// This guest persists even though its fields would project fine, and the
/// reason is `draft`: a task half-typed is state a person would be annoyed to
/// lose, and it is exactly the kind of thing a guest knows to keep and a host
/// cannot. The format is this guest's own business; the host never looks in.
impl DynComponent for Todo with fn persist(self) {
  let items : Array[Json] = self.items.map(it => {
    ({ "text": Json::string(it.text), "done": Json::boolean(it.done) } : Json)
  })
  bytes_of(
    (
      {
        "v": Json::number(1),
        "draft": Json::string(self.draft),
        "items": Json::array(items),
      } : Json).stringify(),
  )
}

///|
/// The inverse. None refuses the bytes — a version this guest no longer reads,
/// or text that is not the JSON it wrote — and the host then rebuilds from the
/// declared fields instead, which loses the draft and nothing else.
fn restore_todo(state : FixedArray[Byte]) -> &DynComponent? {
  let text = text_of(state)
  guard text != "" else { return None }
  let parsed = @json.parse(text) catch { _ => return None }
  guard parsed is Object(m) else { return None }
  guard m.get("v") is Some(Number(1, ..)) else { return None }
  let draft = match m.get("draft") {
    Some(String(s)) => s
    _ => ""
  }
  let items : Array[TodoItem] = []
  if m.get("items") is Some(Array(entries)) {
    for e in entries {
      guard e is Object(im) else { continue }
      let text = match im.get("text") {
        Some(String(s)) => s
        _ => ""
      }
      let done = im.get("done") is Some(True)
      items.push({ text, done })
    }
  }
  Some(({ items, draft } : Todo) as &DynComponent)
}

///|
fn make_todo(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut draft = ""
  let mut items : Array[TodoItem] = []
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      ("draft", @values.Value::Text(s)) => draft = s
      // hot-swap migration hands the declared fields back as args
      ("items", @values.Value::List(h)) => items = items_of(h)
      _ => ()
    }
  }
  ({ items, draft } : Todo) as &DynComponent
}

///|
fn dyn_module() -> DynModule {
  module_def([dyn_comp("Todo", make_todo, restore=restore_todo)])
}
