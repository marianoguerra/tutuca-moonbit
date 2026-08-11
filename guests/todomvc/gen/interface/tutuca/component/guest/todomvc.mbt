///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// TodoMVC as a `tutuca:component` guest: add, toggle, edit in place, delete,
/// toggle-all, filter, clear-completed, count-left — the canonical list, with
/// nothing left out because it was awkward.
///
/// It exists to answer one question the sibling `todo` guest cannot: what
/// belongs in the DECLARED state and what belongs to the guest alone. The
/// items and the current filter are declared, so the host projects them,
/// compares them, migrates them across a hot swap, and generates `setFilter` —
/// which is why no handler here answers that name. The draft, the row being
/// edited and the text being typed into it are NOT declared: they are what
/// this component is doing rather than what it holds, and the host has no
/// business rendering a form over them. They survive a reload anyway, because
/// `persist` writes them and the host stores the bytes without reading them.
///
/// Its static declaration and view live beside the module; sdk.mbt does the ABI.

///|
priv struct MvcItem {
  text : String
  done : Bool
}

///|
priv struct TodoMvc {
  /// DECLARED. The list itself, in the order it was typed.
  items : Array[MvcItem]
  /// DECLARED: "all" / "active" / "completed". The host generates `setFilter`
  /// from it, so the three filter buttons need no guest code.
  filter : String
  /// The rest is this guest's own: what is half-typed, which row is open for
  /// editing, and what is in that row's box.
  draft : String
  editing : Int
  edit_text : String
}

///|
/// The item list as the view iterates it.
///
/// `editing` rides with each row because `@each` takes a FIELD and not a
/// method — a method result has no addressable path, so nothing could be
/// dispatched against it — and comparing an index inside a view is not
/// something the template language does. It is DERIVED on every read, so it
/// cannot disagree with `editing`, and a write that carries a stale one is
/// ignored by `items_of` below.
fn TodoMvc::items_value(self : TodoMvc) -> @values.Value {
  let l = @values.list_new()
  for i, it in self.items {
    let m = @values.map_new()
    @values.map_set(m, "text", @values.Value::Text(it.text))
    @values.map_set(m, "done", @values.Value::Boolean(it.done))
    @values.map_set(m, "editing", @values.Value::Boolean(i == self.editing))
    @values.list_push(l, @values.Value::Map(m))
  }
  @values.Value::List(l)
}

///|
/// The inverse: a host list of {text, done} maps back into items. Both a fresh
/// instance (constructor args, including what a hot swap or a field-restore
/// hands back) and a `with_field` write arrive in this shape.
fn items_of(h : UInt64) -> Array[MvcItem] {
  let items : Array[MvcItem] = []
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
/// A successor with the same everything except what is named. MoonBit has no
/// record update across a `&DynComponent`, so this is the one place the five
/// fields are listed and every handler below reads as the change it makes.
fn TodoMvc::changed(
  self : TodoMvc,
  items? : Array[MvcItem]? = None,
  filter? : String? = None,
  draft? : String? = None,
  editing? : Int? = None,
  edit_text? : String? = None,
) -> &DynComponent {
  (
    {
      items: items.unwrap_or(self.items),
      filter: filter.unwrap_or(self.filter),
      draft: draft.unwrap_or(self.draft),
      editing: editing.unwrap_or(self.editing),
      edit_text: edit_text.unwrap_or(self.edit_text),
    } : TodoMvc)
  as &DynComponent
}

///|
/// The loop `@key` a per-row handler carries, as an index.
fn key_index(args : Array[@values.Value]) -> Int? {
  match args {
    [@values.Value::Number(n), ..] => Some(n.to_int())
    _ => None
  }
}

///|
fn text_arg(args : Array[@values.Value]) -> String? {
  match args {
    [@values.Value::Text(s), ..] => Some(s)
    _ => None
  }
}

///|
impl DynComponent for TodoMvc with fn get_field(self, name) {
  match name {
    "items" => Some(self.items_value())
    "filter" => Some(@values.Value::Text(self.filter))
    _ => None
  }
}

///|
/// The declared fields, written through. `filter` is here rather than in
/// `handle` because the host's generated `setFilter` is what the three filter
/// buttons call — a handler of the same name would be that assignment written
/// twice, and would win over the mutator besides.
impl DynComponent for TodoMvc with fn with_field(self, name, v) {
  match (name, v) {
    ("items", @values.Value::List(h)) =>
      Some(self.changed(items=Some(items_of(h))))
    ("filter", @values.Value::Text(f)) =>
      if f == "all" || f == "active" || f == "completed" {
        Some(self.changed(filter=Some(f)))
      } else {
        // A filter nobody defined would hide every row and look like data
        // loss, so it is refused: the host reads None as "unchanged".
        None
      }
    _ => None
  }
}

///|
impl DynComponent for TodoMvc with fn handle(self, bucket, name, args) {
  guard bucket is INPUT else { return Unhandled }
  match name {
    "typeDraft" =>
      match text_arg(args) {
        Some(s) => Changed(self.changed(draft=Some(s)))
        None => Unchanged
      }
    // The Enter key on the new-todo box (`@on.keydown+send="addOnEnter isSend"`)
    // and the Add button reach the same place.
    "addOnEnter" =>
      match args {
        [@values.Value::Boolean(true), ..] => handled(self.add_draft())
        _ => Unchanged
      }
    "add" => handled(self.add_draft())
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
    // The classic chevron: everything on, unless everything already is.
    "toggleAll" => {
      let all_done = self.items.length() > 0 &&
        self.items.filter(it => !it.done).length() == 0
      let items = self.items.map(it => {
        ({ text: it.text, done: !all_done } : MvcItem)
      })
      Changed(self.changed(items=Some(items)))
    }
    "clearCompleted" =>
      Changed(self.changed(items=Some(self.items.filter(it => !it.done))))
    // Editing in place: open the row, type into it, and either commit or
    // abandon. Committing an empty row DELETES it, which is what TodoMVC
    // specifies and what a person emptying a box means.
    "startEdit" =>
      match key_index(args) {
        Some(i) =>
          if i >= 0 && i < self.items.length() {
            Changed(
              self.changed(editing=Some(i), edit_text=Some(self.items[i].text)),
            )
          } else {
            Unchanged
          }
        None => Unchanged
      }
    "typeEdit" =>
      match text_arg(args) {
        Some(s) => Changed(self.changed(edit_text=Some(s)))
        None => Unchanged
      }
    "commitEdit" => handled(self.commit_edit())
    "cancelEdit" =>
      if self.editing < 0 {
        Unchanged
      } else {
        Changed(self.changed(editing=Some(-1), edit_text=Some("")))
      }
    _ => Unhandled
  }
}

///|
fn TodoMvc::add_draft(self : TodoMvc) -> &DynComponent? {
  let text = self.draft.trim(chars=" ").to_owned()
  guard text != "" else { return None }
  let items = self.items.copy()
  items.push({ text, done: false })
  Some(self.changed(items=Some(items), draft=Some("")))
}

///|
fn TodoMvc::toggle_at(self : TodoMvc, i : Int) -> &DynComponent? {
  guard i >= 0 && i < self.items.length() else { return None }
  let items = self.items.copy()
  let it = items[i]
  items[i] = { text: it.text, done: !it.done }
  Some(self.changed(items=Some(items)))
}

///|
fn TodoMvc::remove_at(self : TodoMvc, i : Int) -> &DynComponent? {
  guard i >= 0 && i < self.items.length() else { return None }
  let items = self.items.copy()
  items.remove(i) |> ignore
  // A row that disappears takes the edit box with it, and a row that shifts up
  // takes the cursor's index with it.
  let editing = if self.editing == i {
    -1
  } else if self.editing > i {
    self.editing - 1
  } else {
    self.editing
  }
  Some(self.changed(items=Some(items), editing=Some(editing)))
}

///|
fn TodoMvc::commit_edit(self : TodoMvc) -> &DynComponent? {
  guard self.editing >= 0 && self.editing < self.items.length() else {
    return None
  }
  let text = self.edit_text.trim(chars=" ").to_owned()
  if text == "" {
    return self.remove_at(self.editing)
  }
  let items = self.items.copy()
  items[self.editing] = { text, done: items[self.editing].done }
  Some(self.changed(items=Some(items), editing=Some(-1), edit_text=Some("")))
}

///|
/// The render-time reads, plus the `@when` filter.
///
/// `matchesFilter` is what makes the three filters cost no state: the view
/// iterates every item and this answers, per item, whether the filter lets it
/// through — so an item's `@key` stays its index in the WHOLE list and the
/// per-row handlers keep working while a filter is on.
impl DynComponent for TodoMvc with fn call_method(self, name, args) {
  match name {
    "draft" => @values.Value::Text(self.draft)
    "editText" => @values.Value::Text(self.edit_text)
    "countLeft" => {
      let left = self.items.filter(it => !it.done).length()
      @values.Value::Text(
        if left == 1 {
          "1 item left"
        } else {
          "\{left} items left"
        },
      )
    }
    // What "clear done" is for; a view hides the button with `empty? $done`.
    "done" => {
      let l = @values.list_new()
      for it in self.items {
        if it.done {
          @values.list_push(l, @values.Value::Text(it.text))
        }
      }
      @values.Value::List(l)
    }
    "matchesFilter" =>
      match args {
        // (key, item, iter-data) — the item is the map `items_value` built
        [_, @values.Value::Map(mh), ..] => {
          let done = match @values.map_get(mh, "done") {
            Some(@values.Value::Boolean(b)) => b
            _ => false
          }
          @values.Value::Boolean(
            match self.filter {
              "active" => !done
              "completed" => done
              _ => true
            },
          )
        }
        _ => @values.Value::Boolean(true)
      }
    _ => @values.Value::Nil
  }
}

// --- persistence -------------------------------------------------------------

///|
/// Everything, as UTF-8 JSON: the declared half AND the half only this guest
/// knows about. That second half is the reason this component persists at all
/// — the host could rebuild the items and the filter on its own, but not the
/// sentence you were halfway through typing.
impl DynComponent for TodoMvc with fn persist(self) {
  let items : Array[Json] = self.items.map(it => {
    ({ "text": Json::string(it.text), "done": Json::boolean(it.done) } : Json)
  })
  bytes_of(
    (
      {
        "v": Json::number(1),
        "items": Json::array(items),
        "filter": Json::string(self.filter),
        "draft": Json::string(self.draft),
        "editing": Json::number(self.editing.to_double()),
        "editText": Json::string(self.edit_text),
      } : Json).stringify(),
  )
}

///|
/// The inverse. None refuses the bytes — a version this guest no longer reads,
/// or text that is not the JSON it wrote — and the host then rebuilds from the
/// declared fields, which keeps the list and loses the typing.
fn restore_todomvc(state : FixedArray[Byte]) -> &DynComponent? {
  let text = text_of(state)
  guard text != "" else { return None }
  let parsed = @json.parse(text) catch { _ => return None }
  guard parsed is Object(m) else { return None }
  guard m.get("v") is Some(Number(1, ..)) else { return None }
  let str_at = (key : String) => {
    match m.get(key) {
      Some(String(s)) => s
      _ => ""
    }
  }
  let items : Array[MvcItem] = []
  if m.get("items") is Some(Array(entries)) {
    for e in entries {
      guard e is Object(im) else { continue }
      let text = match im.get("text") {
        Some(String(s)) => s
        _ => ""
      }
      items.push({ text, done: im.get("done") is Some(True) })
    }
  }
  let editing = match m.get("editing") {
    Some(Number(n, ..)) => n.to_int()
    _ => -1
  }
  let filter = match str_at("filter") {
    "active" => "active"
    "completed" => "completed"
    _ => "all"
  }
  Some(
    (
      {
        items,
        filter,
        draft: str_at("draft"),
        editing: if editing >= 0 && editing < items.length() {
          editing
        } else {
          -1
        },
        edit_text: str_at("editText"),
      } : TodoMvc)
    as &DynComponent,
  )
}

///|
fn make_todomvc(args : Array[(String, @values.Value)]) -> &DynComponent {
  let mut items : Array[MvcItem] = []
  let mut filter = "all"
  for arg in args {
    let (name, v) = arg
    match (name, v) {
      // hot-swap migration and a field-restore both hand the declared fields
      // back as constructor args
      ("items", @values.Value::List(h)) => items = items_of(h)
      ("filter", @values.Value::Text(f)) =>
        if f == "active" || f == "completed" {
          filter = f
        }
      _ => ()
    }
  }
  ({ items, filter, draft: "", editing: -1, edit_text: "" } : TodoMvc)
  as &DynComponent
}

///|
fn dyn_module() -> DynModule {
  module_def([dyn_comp("TodoMvc", make_todomvc, restore=restore_todomvc)])
}
