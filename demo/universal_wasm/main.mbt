///| Universal wasm-component host: the wasm counterpart of the JS "universal"
/// app (../../docs/src/universal.js), styled with margaui utility classes.
///
/// Layout: a root shell (drop zone + status) renders one builtin ComponentList
/// — a flexbox canvas with a settings gear (layout controls) and an "add"
/// button. Each add appends a ComponentPicker; picking a component replaces
/// the picker with that component in place.
///
/// Message lifecycle (mirrors the parent app + its ComponentSelector):
///   ComponentList.onAdd            -> request "componentPicker"
///   .response."componentPicker"    -> append the picker, forward "init" to it
///     ComponentPicker.receive.init -> request "listComponents"
///     .response."listComponents"   -> build ComponentEntry rows into .items
///   click a row -> ComponentEntry bubbles "componentSelected" [module, name]
///     ComponentPicker.bubble       -> make_instance, set .selected (replaces
///                                     the picker chrome with the component)
///   drop a bundle -> shell.dyncompLoaded -> ComponentList.refresh
///                     -> re-init each picker so its list reflects the new bundle
///
/// The two request handlers ("listComponents", "componentPicker") are the
/// feature: one returns the registered components, the other hands back an
/// instance of the picker (which fetches the list itself, on init).

///|
fn main {

}

// --- ComponentEntry: one selectable row ---------------------------------

///|
fn component_entry_comp() -> @component.Component {
  @component.component(
    name="ComponentEntry",
    view=(
      #|<li class="cursor-pointer rounded-lg px-3 py-2 hover:bg-base-300 flex items-center gap-2" @on.click="onSelect">
      #|  <span class="badge badge-sm badge-ghost">wasm</span>
      #|  <span class="text-sm" @text=".label"></span>
      #|</li>
    ),
    fields={
      "module": @component.FieldSpec::of_default(Str("")),
      "name": @component.FieldSpec::of_default(Str("")),
      "label": @component.FieldSpec::of_default(Str("")),
    },
    input={
      "onSelect": (inst, _args, ctx) => {
        ctx.bubble("componentSelected", [inst.get("module"), inst.get("name")])
        Some(inst)
      },
    },
    // used by the picker's @when filter (called with the search text after the
    // dropped this-slot arg, like the parent app's matchesFilter)
    methods={
      "containsText": (inst, args) => {
        match (inst.get("label"), args) {
          (Str(label), [Str(q)]) => Bool(label.contains(q))
          _ => Bool(false)
        }
      },
    },
  )
}

// --- ComponentPicker: selector that replaces itself with the pick --------

///|
fn component_picker_comp(entry : @component.Component) -> @component.Component {
  @component.component(
    name="ComponentPicker",
    view=(
      // once .selected is set, the picker chrome is hidden and only the
      // chosen component renders — the picker "replaces itself"
      #|<div class="w-full">
      #|  <div class="card bg-base-100 border border-base-300 shadow-sm" @hide="truthy? .selected">
      #|    <div class="card-body gap-2 p-3">
      #|      <input class="input input-bordered input-sm w-full" placeholder="Filter components…" :value=".filterText" @on.input="$setFilterText value" />
      #|      <p class="text-sm italic opacity-60" @show="empty? .items">No components yet — drop a <code class="font-mono">.tutuca.tar.gz</code> bundle.</p>
      #|      <ul class="menu menu-sm bg-base-100 rounded-box p-0" @hide="empty? .items"><x render-each=".items" @when="matchesFilter"></x></ul>
      #|    </div>
      #|  </div>
      #|  <div @show="truthy? .selected"><x render=".selected"></x></div>
      #|</div>
    ),
    fields={
      "filterText": @component.FieldSpec::of_default(Str("")),
      "items": @component.FieldSpec::of_default(List([])),
      "selected": @component.FieldSpec::of_default(Null),
    },
    receive={
      // fetch the list of registered components on init (forwarded here when
      // the picker is added to a list)
      "init": (inst, _args, ctx) => {
        ctx.request("listComponents", [], @tutuca.RequestOpts::new())
        Some(inst)
      },
    },
    response={
      // args = [result, error]; turn the result rows into ComponentEntry
      // instances (mirrors entries_from_response in the parent's request demo)
      "listComponents": (inst, args, _ctx) => {
        match args {
          [res, _err] => Some(entries_from_list(inst, entry, res))
          _ => None
        }
      },
      // the chosen component's instance came back — swap it in for the picker
      "makeComponent": (inst, args, _ctx) => {
        match args {
          [res, _err] =>
            match res {
              Null => None
              v => Some(inst.set("selected", v))
            }
          _ => None
        }
      },
    },
    bubble={
      // a row was clicked: request its instance (builtin or guest); the
      // response swaps it in for the picker chrome
      "componentSelected": (inst, args, ctx) => {
        ctx.stop_propagation()
        match args {
          [Str(m), Str(n)] => {
            ctx.request(
              "makeComponent",
              [Str(m), Str(n)],
              @tutuca.RequestOpts::new(),
            )
            Some(inst)
          }
          _ => None
        }
      },
    },
    alter={
      // @when predicate for render-each: [key, value, iter_data]; keep rows
      // whose entry's containsText method matches the filter text
      "matchesFilter": (inst, args) => {
        match (inst.get("filterText"), args) {
          (Str(q), [_key, item, ..]) =>
            if q == "" {
              Bool(true)
            } else {
              match item {
                Obj(o) =>
                  match o.obj_field("containsText") {
                    Some(Fn(f)) => f([Null, Str(q)])
                    _ => Bool(true)
                  }
                _ => Bool(true)
              }
            }
          _ => Bool(true)
        }
      },
    },
  )
}

///|
/// Turn the "listComponents" result (rows of {module, name, label}) into
/// ComponentEntry instances seeded into the picker's `items`.
fn entries_from_list(
  inst : @component.Instance,
  entry : @component.Component,
  res : @tutuca.Value,
) -> @component.Instance {
  let items : Array[@tutuca.Value] = match res {
    List(rows) =>
      rows.map(row => {
        match row {
          Map(m) =>
            entry
            .make({
              "module": m.get("module").unwrap_or(Str("")),
              "name": m.get("name").unwrap_or(Str("")),
              "label": m.get("label").unwrap_or(Str("")),
            })
            .to_value()
          _ => Null
        }
      })
    _ => []
  }
  inst.set("items", List(items))
}

// --- ComponentList: the builtin flexbox canvas ---------------------------

///|
fn component_list_comp() -> @component.Component {
  @component.component(
    name="ComponentList",
    view=(
      // the gear (layout) and + (add) are subtle ghost icon buttons pinned to
      // the canvas corners via daisyUI's indicator; the canvas content is the
      // indicator's normal child
      #|<section class="indicator w-full">
      #|  <button class="indicator-item indicator-top indicator-start btn btn-sm btn-ghost btn-circle" title="Layout settings" @on.click="$toggleShowSettings">
      #|    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"></path></svg>
      #|  </button>
      #|  <button class="indicator-item indicator-top indicator-end btn btn-sm btn-ghost btn-circle" title="Add component" @on.click="onAdd">
      #|    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="12" y1="5" x2="12" y2="19"></line><line x1="5" y1="12" x2="19" y2="12"></line></svg>
      #|  </button>
      #|  <div class="w-full flex flex-col gap-3 pt-6 min-h-[5rem]">
      #|    <div class="card bg-base-100 border border-base-300 p-3" @show=".showSettings">
      #|      <div class="flex flex-wrap gap-3 items-end">
      #|        <label class="flex flex-col gap-1"><span class="text-xs opacity-70">direction</span>
      #|          <select class="select select-bordered select-sm" :value=".dir" @on.input="$setDir value">
      #|            <option value="row">row</option><option value="column">column</option><option value="row-reverse">row-reverse</option><option value="column-reverse">column-reverse</option>
      #|          </select></label>
      #|        <label class="flex flex-col gap-1"><span class="text-xs opacity-70">justify</span>
      #|          <select class="select select-bordered select-sm" :value=".justify" @on.input="$setJustify value">
      #|            <option value="flex-start">flex-start</option><option value="center">center</option><option value="flex-end">flex-end</option><option value="space-between">space-between</option><option value="space-around">space-around</option>
      #|          </select></label>
      #|        <label class="flex flex-col gap-1"><span class="text-xs opacity-70">align</span>
      #|          <select class="select select-bordered select-sm" :value=".align" @on.input="$setAlign value">
      #|            <option value="stretch">stretch</option><option value="flex-start">flex-start</option><option value="center">center</option><option value="flex-end">flex-end</option>
      #|          </select></label>
      #|        <label class="flex flex-col gap-1"><span class="text-xs opacity-70">gap (px)</span>
      #|          <input type="number" class="input input-bordered input-sm w-20" :value=".gap" @on.input="$setGap valueAsInt" /></label>
      #|        <label class="flex items-center gap-2 cursor-pointer"><span class="text-xs opacity-70">wrap</span>
      #|          <input type="checkbox" class="checkbox checkbox-sm" :checked=".wrap" @on.input="$toggleWrap" /></label>
      #|      </div>
      #|    </div>
      #|    <p class="text-sm italic opacity-60" @show="empty? .entries">Empty canvas — ⚙ to change the layout, ＋ to add a component.</p>
      #|    <div class="items-start" :style="$flexStyle"><x render-each=".entries"></x></div>
      #|  </div>
      #|</section>
    ),
    fields={
      "entries": @component.FieldSpec::of_default(List([])),
      "showSettings": @component.FieldSpec::of_default(Bool(false)),
      "dir": @component.FieldSpec::of_default(Str("row")),
      "justify": @component.FieldSpec::of_default(Str("flex-start")),
      "align": @component.FieldSpec::of_default(Str("stretch")),
      "gap": @component.FieldSpec::of_default(Num(12)),
      "wrap": @component.FieldSpec::of_default(Bool(true)),
    },
    input={
      // append a fresh picker: request one, seed + init it in the response
      "onAdd": (inst, _args, ctx) => {
        ctx.request("componentPicker", [], @tutuca.RequestOpts::new())
        Some(inst)
      },
    },
    response={
      "componentPicker": (inst, args, ctx) => {
        match args {
          [picker, _err] => {
            let entries = match inst.get("entries") {
              List(a) => a.copy()
              _ => []
            }
            entries.push(picker)
            let idx = entries.length() - 1
            // let the new picker fetch its component list (on init)
            ctx.send_at_path(
              ctx.path().concat([SeqStep(field="entries", key=KInt(idx))]),
              "init",
              [],
            )
            Some(inst.set("entries", List(entries)))
          }
          _ => None
        }
      },
    },
    receive={
      // a bundle loaded: re-init each picker so its list includes it
      "refresh": (inst, _args, ctx) => {
        let entries = match inst.get("entries") {
          List(a) => a
          _ => []
        }
        for i in 0..<entries.length() {
          ctx.send_at_path(
            ctx.path().concat([SeqStep(field="entries", key=KInt(i))]),
            "init",
            [],
          )
        }
        Some(inst)
      },
    },
    methods={
      // per-instance flexbox style from the settings fields (see visual_wasm
      // getInputWidth precedent for a method returning a CSS string)
      "flexStyle": (inst, _args) => {
        let dir = match inst.get("dir") {
          Str(s) => s
          _ => "row"
        }
        let justify = match inst.get("justify") {
          Str(s) => s
          _ => "flex-start"
        }
        let align = match inst.get("align") {
          Str(s) => s
          _ => "stretch"
        }
        let gap = match inst.get("gap") {
          Num(n) => n.to_int()
          _ => 12
        }
        let wrap = match inst.get("wrap") {
          Bool(false) => "nowrap"
          _ => "wrap"
        }
        Str(
          "display:flex;flex-direction:\{dir};gap:\{gap}px;justify-content:\{justify};align-items:\{align};flex-wrap:\{wrap}",
        )
      },
    },
  )
}

// --- root shell ----------------------------------------------------------

///|
fn universal_shell_comp() -> @component.Component {
  @component.component(
    name="UniversalWasm",
    view=(
      #|<div class="min-h-screen bg-base-200 text-base-content p-4 flex flex-col gap-3">
      #|  <div class="rounded-box border-2 border-dashed border-base-300 bg-base-100 p-4 text-center opacity-70" data-droptarget="tutuca-wasm-component">
      #|    Drop a <code class="font-mono">.tutuca.tar.gz</code> bundle to register its wasm components
      #|  </div>
      #|  <p class="text-sm opacity-70" @text=".status"></p>
      #|  <x render=".list"></x>
      #|</div>
    ),
    fields={
      "status": @component.FieldSpec::of_default(
        Str(
          "drop a .tutuca.tar.gz bundle, then “+ Add component” to place it",
        ),
      ),
      "list": @component.FieldSpec::comp("ComponentList"),
    },
    receive={
      "dyncompLoaded": (inst, args, ctx) => {
        let module_name = match args {
          [Str(s)] => s
          _ => "?"
        }
        ctx.send_at_path(ctx.path().concat([FieldStep("list")]), "refresh", [])
        Some(
          inst.set(
            "status",
            Str("loaded \{module_name} — add a component to place it"),
          ),
        )
      },
      "dyncompError": (inst, args, _ctx) => {
        let msg = match args {
          [Str(s)] => s
          _ => "unknown error"
        }
        Some(inst.set("status", Str("load failed: \{msg}")))
      },
    },
  )
}

///|
/// Assemble the module: the components + the two request handlers the feature
/// adds. "listComponents" returns the registered components; "componentPicker"
/// hands back a picker instance.
fn universal_module() -> @component.ModuleDef {
  let entry = component_entry_comp()
  let picker = component_picker_comp(entry)
  let list = component_list_comp()
  let shell = universal_shell_comp()
  let requests : Map[String, @component.RequestFn] = {
    "listComponents": RequestFn((_args, respond) => {
      // the builtin flex list is always available (module "builtin"); the rest
      // are the components of loaded guest bundles
      let rows : Array[@tutuca.Value] = [
        Map({
          "module": Str("builtin"),
          "name": Str("ComponentList"),
          "label": Str("Flex list (builtin)"),
        }),
      ]
      for pair in @dhw.loaded_components() {
        let (m, n) = pair
        rows.push(
          Map({ "module": Str(m), "name": Str(n), "label": Str("\{m} / \{n}") }),
        )
      }
      respond(Ok(List(rows)))
    }),
    "componentPicker": RequestFn((_args, respond) => {
      respond(Ok(picker.make({}).to_value()))
    }),
    // create a component instance by (module, name): builtins natively, guest
    // components through the dyncomp bridge
    "makeComponent": RequestFn((args, respond) => {
      match args {
        [Str(m), Str(n)] =>
          if m == "builtin" {
            match n {
              "ComponentList" => respond(Ok(list.make({}).to_value()))
              _ => respond(Err(Str("unknown builtin \{n}")))
            }
          } else {
            match @dhw.make_instance(m, n) {
              Some(v) => respond(Ok(v))
              None => respond(Err(Str("could not make \{m}/\{n}")))
            }
          }
        _ => respond(Err(Str("makeComponent: expected [module, name]")))
      }
    }),
  }
  @component.ModuleDef::new(
    name="universalwasm",
    components=[shell, list, picker, entry],
    requests~,
  )
}

// --- margaui class publishing -------------------------------------------

///|
let app_ref : Ref[@app.App[@wdom.WasmNode]?] = { val: None }

///|
/// Publish the app's utility-class set to globalThis.__tutuca_classes for the
/// page's applyMargaui() to compile (mirrors demo/storybook_wasm). Called at
/// mount and again (via the exported refresh_classes) after a bundle loads, so
/// guest-view classes get compiled too.
fn publish_classes() -> Unit {
  guard app_ref.val is Some(app) else { return }
  let arr = @core.new_array()
  for c in app.scope.comps.collect_classes() {
    let _ = arr._call("push", [@core.any(c)])
  }
  @core.global_this()._set("__tutuca_classes", arr)
}

///|
/// Re-publish classes after a guest bundle registers (the loader re-runs
/// applyMargaui afterward). Exported.
pub fn refresh_classes() -> Unit {
  publish_classes()
}

// --- lifecycle exports ---------------------------------------------------

///|
pub fn mount() -> Unit {
  guard @wglue.mount_in(universal_module(), "UniversalWasm") is Some(app) else {
    return
  }
  app_ref.val = Some(app)
  // host-provided request services a dropped guest may call (e.g. "double",
  // used by the sample counter). The picker/list requests are in the module.
  app.scope.register_request_handlers(@dhw.shell_request_handlers())
  @dhw.set_app(app, @wglue.document())
  publish_classes()
}

///|
pub fn on_event(ev : @core.Any) -> Unit {
  @wglue.on_event(ev)
}

///|
pub fn dyncomp_on_loaded(
  load_id : Int,
  bundle_id : Int,
  manifest_json : String,
) -> Unit {
  @dhw.on_loaded(load_id, bundle_id, manifest_json)
}

///|
pub fn dyncomp_on_load_error(load_id : Int, msg : String) -> Unit {
  @dhw.on_load_error(load_id, msg)
}

///|
/// Root state as display text, for inspection/automated verification.
pub fn state_json() -> String {
  guard @dhw.app_root_value() is Some(v) else { return "null" }
  v.to_display_string()
}
