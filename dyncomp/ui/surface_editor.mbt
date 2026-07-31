///| The editor: the one component that owns the document.
///
/// Every handler here does the same three things — read the surface out of
/// `doc`, apply a `SurfaceOp` batch, write it back and rebuild — because that
/// is the only way a change is allowed to happen. A handler that edited the
/// tree directly would be a second way to change a layout, and the second way
/// is the one an agent cannot use.

///|
/// Where a new node goes: inside the selection when it can hold children,
/// beside it when it cannot.
///
/// The alternative — refusing to add a node while a Slot is selected — is
/// technically defensible and practically infuriating, because "selected" after
/// placing a component is always the slot you just filled.
fn insert_parent(s : @surface.Surface, selected : String) -> String {
  guard s.node(selected) is Some(n) else { return s.root }
  if n.kind.is_container() {
    return selected
  }
  match s.parent_of(selected) {
    Some(p) => p
    None => s.root
  }
}

///|
/// Apply a batch and rebuild everything that reads the document.
///
/// A refused batch changes NOTHING and says why — `apply` is atomic, so there
/// is no half-edited layout to reconcile, and the status line is where the
/// reason goes because a person who clicked a button is owed an answer.
fn UniversalUi::edit(
  self : UniversalUi,
  state : SurfaceEditorState,
  ops : Array[@surface.SurfaceOp],
  select? : String = "",
  ok? : String = "",
  slots? : Map[String, @tutuca.Value]? = None,
) -> SurfaceEditorState? {
  let before = surface_of(state.doc)
  // From the TREE, not from a map kept beside it: a placed component that was
  // USED has a successor in the tree, and the copy is one update behind (see
  // `live_slots`). Rebuilding from the stale one is what would quietly revert
  // a half-filled form the moment somebody moved the box holding it.
  //
  // `slots~` is for the one caller that knows better — `place`, which has an
  // instance the tree has never seen.
  let slots = match slots {
    Some(given) => given
    None => slots_of_tree(state.tree)
  }
  match @surface.apply(before, ops) {
    Err(errors) => {
      let shown = errors.map(e => "\{e.pointer}: \{e.message}").join("; ")
      Some({ ..state, status: shown })
    }
    Ok(after) => {
      // "" means "work it out": keep the selection when the batch left it
      // standing, and fall back to the root when it did not. An editor with no
      // selection has no settings panel and nowhere to add to.
      let selected = if select != "" {
        select
      } else if after.node(state.selected) is Some(_) {
        state.selected
      } else {
        after.root
      }
      // Instances the document no longer binds are dropped here, which is the
      // one place that knows both what was removed and what is live. They are
      // dropped by NOT being rebuilt into the tree, which is also the only
      // place they were.
      let live : Map[String, @tutuca.Value] = Map([])
      for pair in after.bindings() {
        if slots.get(pair.0) is Some(inst) {
          live[pair.0] = inst
        }
      }
      Some({
        ..state,
        doc: doc_of(after),
        tree: self.build_tree(after, live, selected),
        settings: self.settings_for(after, selected),
        selected,
        status: ok,
      })
    }
  }
}

///|
/// A layout property, decoded from what a control handed back.
///
/// The panel bubbles text because that is what a `<select>` and an `<input>`
/// produce; the vocabulary is `dyncomp/surface`'s, so the decoding is here and
/// not there — `apply_props` then validates it properly and refuses what this
/// let through.
fn prop_value(prop : String, raw : String) -> @tutuca.Value {
  match prop {
    "gap" | "padding" | "colSpan" | "rowSpan" =>
      Num(@string.parse_double(raw) catch { _ => 0.0 })
    "wrap" => Bool(raw == "true")
    "columns" | "rows" => {
      let tracks : Array[@tutuca.Value] = []
      for part in raw.split(" ") {
        let t = part.trim(chars=" ").to_owned()
        if t != "" {
          tracks.push(Str(t))
        }
      }
      List(tracks)
    }
    _ => Str(raw)
  }
}

///|
/// Add a node, and select it.
///
/// Selecting the new one is the difference between "add a grid, now click it,
/// now set its columns" and "add a grid, set its columns" — and the same
/// reasoning puts a placed component's slot under the cursor afterwards.
fn UniversalUi::add_node(
  self : UniversalUi,
  state : SurfaceEditorState,
  kind : @surface.NodeKind,
) -> SurfaceEditorState? {
  let s = surface_of(state.doc)
  let parent = insert_parent(s, state.selected)
  // The id `apply` will mint, which is knowable because a surface's counter is
  // part of its state rather than global.
  let new_id = "n\{s.next_id}"
  self.edit(
    state,
    [AddNode(parent~, index=-1, kind~, props=Map([]))],
    select=new_id,
    ok="added \{kind.to_string()} \{new_id}",
  )
}

///|
fn UniversalUi::editor_comp(self : UniversalUi) -> @component.Component {
  // The non-slot half of the starting state. The four `component` fields
  // (`tree`, `settings`, `palette`, `form`) are NOT here and cannot be: a
  // component-typed field takes its value from construction args, never from
  // `init` — the framework either auto-constructs a named slot or leaves a
  // bare one null. `editor_seed` is what fills them, through `args` for a
  // mount and `slot_args` for a parent that holds one.
  let s = @surface.Surface::new("main")
  surface_editor_component(
    init={
      ..SurfaceEditorState::zero(),
      doc: doc_of(s),
      selected: s.root,
      status: "pick a component to place",
    },
    update=(state, msg, ctx) => {
      match SurfaceEditorMsg::from_dispatch(msg) {
        Some(AddStack) => return self.add_node(state, Stack)
        Some(AddGrid) => return self.add_node(state, Grid)
        Some(AddBox) => return self.add_node(state, Box)
        Some(AddSlot) => return self.add_node(state, Slot)
        Some(RemoveNode) =>
          return self.edit(
            state,
            [RemoveNode(id=state.selected)],
            ok="removed \{state.selected}",
          )
        Some(ExportDoc) =>
          return Some({
            ..state,
            transfer: state.doc.to_json().stringify(),
            showTransfer: true,
            status: "exported — copy it, or paste one over it and import",
          })
        Some(SetTransfer(text)) => return Some({ ..state, transfer: text })
        Some(ImportDoc) => {
          // An import is the only way a malformed document reaches the editor,
          // so it is the only place that has to survive one.
          let parsed = @json.parse(state.transfer) catch {
            _ => return Some({ ..state, status: "import: not JSON" })
          }
          guard @surface.Surface::from_json(parsed) is Some(imported) else {
            return Some({
              ..state,
              status: "import: not a surface (no root, or a child that does not exist)",
            })
          }
          // The instances do NOT come with it: a document holds references,
          // and the host builds what they name. Importing therefore gives the
          // layout back and leaves the slots empty, which is honest — the
          // alternative is silently showing someone else's state.
          let empty : Map[String, @tutuca.Value] = Map([])
          return Some({
            ..state,
            doc: doc_of(imported),
            selected: imported.root,
            tree: self.build_tree(imported, empty, imported.root),
            settings: self.settings_for(imported, imported.root),
            showTransfer: false,
            status: "imported \{imported.nodes.length()} nodes; slots are empty until they are filled again",
          })
        }
        Some(Unknown(_, _)) | None => ()
      }
      match SurfaceEditorReceive::from_dispatch(msg) {
        // A bundle loaded, so the catalog changed under whatever the palette
        // is showing. Re-running the search is cheaper than telling a person
        // to retype it.
        Some(CatalogChanged(module_)) => {
          let query = state.palette.field("query").str()
          return Some({
            ..state,
            palette: self.palette_for(query),
            status: "loaded \{module_}",
          })
        }
        // A session coming back: the document, and the live instances the
        // shell rebuilt for the slots that hold them. The editor treats it
        // exactly like an import that DID have its instances — same document
        // path, same rebuild — because "where did this come from" is the
        // shell's question and not this component's.
        Some(RestoreSession(payload)) => {
          guard @surface.Surface::from_json(payload.field("doc").to_json())
            is Some(imported) else {
            return Some({ ..state, status: "could not restore the last layout" })
          }
          let slots : Map[String, @tutuca.Value] = Map([])
          if payload.field("slots") is Map(m) {
            for id, inst in m {
              if inst is Obj(_) {
                slots[id] = inst
              }
            }
          }
          let filled = slots.length()
          return Some({
            ..state,
            doc: doc_of(imported),
            selected: imported.root,
            tree: self.build_tree(imported, slots, imported.root),
            settings: self.settings_for(imported, imported.root),
            form: Null,
            status: "restored \{imported.nodes.length()} nodes, \{filled} of them filled",
          })
        }
        Some(Unknown(_, _)) | None => ()
      }
      match msg {
        Bubble("nodePicked", [Str(id), ..]) => {
          let s = surface_of(state.doc)
          ctx.stop_propagation()
          Some({
            ..state,
            selected: id,
            tree: self.build_tree(s, slots_of_tree(state.tree), id),
            settings: self.settings_for(s, id),
          })
        }
        Bubble("propChanged", [Str(prop), Str(raw), ..]) => {
          ctx.stop_propagation()
          let props : Map[String, @tutuca.Value] = Map([])
          props[prop] = prop_value(prop, raw)
          self.edit(state, [SetProps(id=state.selected, props~)])
        }
        Bubble("queryChanged", [Str(q), ..]) => {
          ctx.stop_propagation()
          Some({ ..state, palette: self.palette_for(q) })
        }
        Bubble("componentPicked", [Str(module_), Str(name), ..]) => {
          ctx.stop_propagation()
          // Picking opens the form rather than placing immediately: a
          // component with required arguments cannot be placed without them,
          // and one without any still deserves the chance to say so.
          match self.registry.describe({ module_, name }) {
            Some(d) =>
              Some({
                ..state,
                form: self.form_for(d),
                status: "fill in \{d.ref_.to_id()} and place it",
              })
            None =>
              Some({ ..state, status: "no such component: \{module_}/\{name}" })
          }
        }
        Bubble("cancelForm", _) =>
          Some({ ..state, form: Null, status: "cancelled" })
        Bubble("submitForm", [Str(module_), Str(name), Str(init), List(fields)]) => {
          ctx.stop_propagation()
          self.place(state, ctx, { module_, name }, init, fields)
        }
        _ => None
      }
    },
  )
}

///|
/// Validate the filled-in form, build the instance, and bind it into a slot.
///
/// Three ways this fails and each says something different: the schema refuses
/// the arguments (per-field, back into the form), the host cannot build the
/// component (the bridge's problem, into the status line), or there is nowhere
/// to put it (the editor's, and it fixes that by adding a slot rather than
/// complaining).
fn UniversalUi::place(
  self : UniversalUi,
  state : SurfaceEditorState,
  ctx : &@tutuca.Ctx,
  ref_ : @registry.ComponentRef,
  init : String,
  fields : Array[@tutuca.Value],
) -> SurfaceEditorState? {
  guard self.registry.describe(ref_) is Some(d) else {
    return Some({ ..state, status: "no such component: \{ref_.to_id()}" })
  }
  // A named fixture is the guest's own answer to "what arguments", so it wins
  // over the blank form it was offered beside.
  let args = if init != "" {
    Map([])
  } else {
    match d.coerce_args(form_args(fields)) {
      Ok(a) => a
      Err(errors) => {
        let by_pointer : Map[String, @tutuca.Value] = Map([])
        for e in errors {
          by_pointer[e.pointer] = Str(e.message)
        }
        ctx.send_at_path(ctx.path().concat([FieldStep("form")]), "showErrors", [
          Map(by_pointer),
        ])
        return Some({ ..state, status: "check the highlighted fields" })
      }
    }
  }
  guard (self.make)(ref_, init, args) is Some(instance) else {
    return Some({ ..state, status: "could not build \{ref_.to_id()}" })
  }
  // Where it goes: the selected slot if one is selected, otherwise a fresh
  // slot under whatever can hold it.
  let s = surface_of(state.doc)
  let (ops, target) = match s.node(state.selected) {
    Some(n) if n.kind is Slot => ([], state.selected)
    _ => {
      let parent = insert_parent(s, state.selected)
      let id = "n\{s.next_id}"
      (
        [
          (
            AddNode(parent~, index=-1, kind=Slot, props=Map([])) :
            @surface.SurfaceOp),
        ],
        id,
      )
    }
  }
  let binding : @surface.Binding = {
    module_: ref_.module_,
    name: ref_.name,
    init,
    args,
  }
  let all = ops.copy()
  all.push(BindInstance(id=target, binding=Some(binding)))
  let slots = slots_of_tree(state.tree)
  slots[target] = instance
  let next = { ..state, form: Null }
  self.edit(
    next,
    all,
    select=target,
    ok="placed \{ref_.to_id()}",
    slots=Some(slots),
  )
}

///|
/// The editor's module: the seven components, with the editor as its root.
///
/// `registry` and `make` are what the shell supplies — the catalog to search,
/// and the one thing a backend-agnostic package cannot do, which is build a
/// real guest instance.
pub fn universal_module(
  registry : @registry.Registry,
  make : MakeInstance,
) -> @component.ModuleDef {
  let ui : UniversalUi = { registry, make, comps: Map([]) }
  // Leaves first, and not for tidiness: the editor's `init` builds a tree, a
  // settings panel and a palette out of them, so `comps` has to hold them by
  // the time `editor_comp` runs.
  let leaves = [
    surface_node_comp(),
    node_settings_comp(),
    palette_row_comp(),
    component_palette_comp(),
    schema_field_comp(),
    schema_form_comp(),
  ]
  for c in leaves {
    ui.comps[c.name] = c
  }
  let editor = ui.editor_comp()
  ui.comps[editor.name] = editor
  @component.ModuleDef::new(name="universalui", components=[editor] + leaves)
}

///|
/// The construction arguments an editor needs: an empty surface, the tree it
/// renders to, its settings panel, and a palette already showing the catalog.
///
/// This exists because a `component`-typed field takes its value from args
/// rather than from `init`. A mount passes these as `args`; a parent holding
/// an `editor: surface-editor` slot passes them as that slot's `slot_args`.
pub fn editor_seed(
  registry : @registry.Registry,
  make : MakeInstance,
  module_ : @component.ModuleDef,
) -> Map[String, @tutuca.Value] {
  let ui : UniversalUi = { registry, make, comps: Map([]) }
  for c in module_.components {
    ui.comps[c.name] = c
  }
  let s = @surface.Surface::new("main")
  let empty : Map[String, @tutuca.Value] = Map([])
  {
    "doc": doc_of(s),
    "selected": Str(s.root),
    "tree": ui.build_tree(s, empty, s.root),
    "settings": ui.settings_for(s, s.root),
    "palette": ui.palette_for(""),
    "form": Null,
    "status": Str("pick a component to place"),
    "transfer": Str(""),
    "showTransfer": Bool(false),
  }
}

///|
/// The editor's module and the arguments its root is built with — what both
/// shells (the test harness and the wasm page) start from.
pub fn seeded_editor(
  registry : @registry.Registry,
  make : MakeInstance,
) -> (@component.ModuleDef, Map[String, @tutuca.Value]) {
  let module_ = universal_module(registry, make)
  (module_, editor_seed(registry, make, module_))
}
