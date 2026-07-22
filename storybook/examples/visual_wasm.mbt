// Port of docs/examples/visual-wasm.js — a visual editor for WebAssembly
// modules. The largest example: ~75 components, most produced by FACTORIES
// (instr / type / instrImmInt), dispatched through lookup tables, with recursive
// Block/Loop/If nesting and per-component editor/compact views.
//
// PORT PATTERNS (all seen in earlier examples, at scale here):
//   - factories = plain functions returning components (json, tree)
//   - a `reg` map for mutual recursion and lookup-table dispatch (json)
//   - self-replacement handlers: setType / selectInstructionById return a fresh
//     instance of a DIFFERENT component type — the `swap` bucket (see json.mbt)
//   - `^handler`/`^onadd` macro indirection (todo-macros)
//   - editor/compact named views, `:style="$'…'"` (styles, multiple-views)
//
// PORT DIVERGENCES:
//   1. The picker's `selectInstructionById(target)` reads `target.dataset.value`
//      off the raw DOM element — which the value layer does not expose. Ported
//      to pass the loop's `@value` (the instruction id) directly, so no DOM
//      object is needed. The click handler is `selectInstructionById @value`.
//   2. This required implementing `insertInItemsAt` (the generated list-insert
//      mutator, which was missing) in the runtime — see component/component.mbt.
//   3. Self-replacing instances (types, pickers) declare their replacement
//      handlers in the `swap` bucket, closing over the `reg` for lookup.

///|
/// name -> Component, for the lookup-table dispatch and mutual recursion.
priv struct VwReg {
  comps : Map[String, @component.Component]
}

///|
fn VwReg::get(self : VwReg, name : String) -> @component.Component? {
  self.comps.get(name)
}

///|
/// Set `editing` to true on a value if it has that field, else return it
/// unchanged. JS: `v.setEditing ? v.setEditing(true) : v`.
fn vw_with_editing(v : @tutuca.Value) -> @tutuca.Value {
  match v {
    Obj(o) =>
      match o.obj_with_field("editing", Bool(true)) {
        Some(nv) => nv
        None => v
      }
    _ => v
  }
}

///|
fn vw_int_arg(args : Array[@tutuca.Value], i : Int) -> Int {
  match args.get(i) {
    Some(Num(n)) => n.to_int()
    _ => 0
  }
}

///|
/// A fresh picker instance (its swap handler is part of the component).
fn vw_make_picker(reg : VwReg) -> @tutuca.Value {
  match reg.get("InstructionPicker") {
    Some(c) => c.make(Map([]))
    None => Null
  }
}

///|
/// A fresh value-type instance (TypeI32...F64) — each type component carries
/// its own `setType` swap handler.
fn vw_make_type(reg : VwReg, cname : String) -> @tutuca.Value {
  match reg.get(cname) {
    Some(c) => c.make(Map([]))
    None => Null
  }
}

///|
/// Insert a fresh picker into an item list before index i (the `addItemAt`
/// body, shared by every container).
fn vw_insert_picker(
  reg : VwReg,
  items : Array[@tutuca.Value],
  i : Int,
) -> Array[@tutuca.Value] {
  let out = items.copy()
  let at = @cmp.minimum(@cmp.maximum(0, i), out.length())
  out.insert(at, vw_make_picker(reg))
  out
}

// ─── Factories ───────────────────────────────────────────────────────────────

///|
priv struct VwEmptyState {} derive(ToJson, FromJson)

///|
/// A leaf instruction: renders its label, no state.
fn vw_instr(name : String, label : String) -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view="<span class=\"instr\">\{label}</span>",
      ),
    },
    name~,
    init=VwEmptyState::{  },
  )
}

///|
priv struct VwImmState {
  value : Int
  rawValue : String
} derive(ToJson, FromJson)

///|
/// An instruction with an immediate integer operand (local.get 3, i32.const 42).
fn vw_instr_imm(name : String, label : String) -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view="<div class=\"flex gap-3 items-baseline instr-imm\"><span>\{label}</span>" +
          "<input class=\"input px-1 py-0 m-0 h-auto input-ghost font-mono text-blue-400 imm\" :value=\".value\" :style=\"$'width: {$getInputWidth}; outline: none'\" @on.input=\"$setFromRawValue value\" /></div>",
      ),
    },
    name~,
    init=VwImmState::{ value: 0, rawValue: "0" },
    mutate={
      "setFromRawValue": (s : VwImmState, args) => {
        let raw = match args {
          [Str(t), ..] => t
          _ => ""
        }
        let parsed : Int? = Some(@string.parse_int(raw)) catch { _ => None }
        match parsed {
          Some(v) => { value: v, rawValue: raw }
          None => { ..s, rawValue: raw }
        }
      },
    },
    compute={
      "getInputWidth": (s : VwImmState, _args) => {
        Str("\{s.rawValue.length() + 2}em")
      },
    },
  )
}

///|
/// A value type (i32/i64/f32/f64). Its editor's `setType` self-replaces with
/// the chosen type through the `swap` bucket (a fresh instance of the picked
/// type component).
fn vw_type(reg : VwReg, name : String, label : String) -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view="<span class=\"font-italic text-amber-400 type\">\{label}</span>",
      ),
      "editor": @anode.View::new(
        "editor",
        raw_view="<select class=\"select select-ghost px-0 font-italic text-amber-400 type-select\" @on.input=\"setType value\">" +
          "<option value=\"i32\">i32</option><option value=\"i64\">i64</option>" +
          "<option value=\"f32\">f32</option><option value=\"f64\">f64</option></select>",
      ),
    },
    name~,
    init=VwEmptyState::{  },
    swap={
      "setType": (_s : VwEmptyState, args, _ctx) => {
        let id = match args {
          [Str(t), ..] => t
          _ => ""
        }
        Some(vw_make_type(reg, type_comp_name(id)))
      },
    },
  )
}

///|
fn type_comp_name(type_id : String) -> String {
  match type_id {
    "i32" => "TypeI32"
    "i64" => "TypeI64"
    "f32" => "TypeF32"
    "f64" => "TypeF64"
    _ => "TypeI32"
  }
}

// ─── Instruction data tables ─────────────────────────────────────────────────

///|
/// (constName, wasm label) for every plain (operand-less) instruction.
fn vw_plain_instrs() -> Array[(String, String)] {
  [
    ("Br", "br"),
    ("BrIf", "br_if"),
    ("Nop", "nop"),
    ("Drop", "drop"),
    ("I32Add", "i32.add"),
    ("I32Sub", "i32.sub"),
    ("I32Mul", "i32.mul"),
    ("I32DivS", "i32.div_s"),
    ("I32DivU", "i32.div_u"),
    ("I32Eq", "i32.eq"),
    ("I32Ne", "i32.ne"),
    ("I32GtS", "i32.gt_s"),
    ("I32GeS", "i32.ge_s"),
    ("I32LtS", "i32.lt_s"),
    ("I32LeS", "i32.le_s"),
    ("I32GtU", "i32.gt_u"),
    ("I32GeU", "i32.ge_u"),
    ("I32LtU", "i32.lt_u"),
    ("I32LeU", "i32.le_u"),
    ("I64Add", "i64.add"),
    ("I64Sub", "i64.sub"),
    ("I64Mul", "i64.mul"),
    ("I64DivS", "i64.div_s"),
    ("I64DivU", "i64.div_u"),
    ("I64Eq", "i64.eq"),
    ("I64Ne", "i64.ne"),
    ("I64GtS", "i64.gt_s"),
    ("I64GeS", "i64.ge_s"),
    ("I64LtS", "i64.lt_s"),
    ("I64LeS", "i64.le_s"),
    ("I64GtU", "i64.gt_u"),
    ("I64GeU", "i64.ge_u"),
    ("I64LtU", "i64.lt_u"),
    ("I64LeU", "i64.le_u"),
    ("F32Add", "f32.add"),
    ("F32Sub", "f32.sub"),
    ("F32Mul", "f32.mul"),
    ("F32Div", "f32.div"),
    ("F32Eq", "f32.eq"),
    ("F32Ne", "f32.ne"),
    ("F32Gt", "f32.gt"),
    ("F32Ge", "f32.ge"),
    ("F32Lt", "f32.lt"),
    ("F32Le", "f32.le"),
    ("F64Add", "f64.add"),
    ("F64Sub", "f64.sub"),
    ("F64Mul", "f64.mul"),
    ("F64Div", "f64.div"),
    ("F64Eq", "f64.eq"),
    ("F64Ne", "f64.ne"),
    ("F64Gt", "f64.gt"),
    ("F64Ge", "f64.ge"),
    ("F64Lt", "f64.lt"),
    ("F64Le", "f64.le"),
  ]
}

///|
/// (constName, label) for the immediate-int and const instructions.
fn vw_imm_instrs() -> Array[(String, String)] {
  [
    ("I32Const", "i32.const"),
    ("I64Const", "i64.const"),
    ("F32Const", "f32.const"),
    ("F64Const", "f64.const"),
    ("LocalGet", "local.get"),
    ("LocalSet", "local.set"),
    ("LocalTee", "local.tee"),
    ("GlobalGet", "global.get"),
    ("GlobalSet", "global.set"),
  ]
}

///|
/// wasm label -> the const name that builds it, for the picker's dispatch.
fn vw_id_to_name() -> Map[String, String] {
  let m : Map[String, String] = Map([])
  for p in vw_plain_instrs() {
    m[p.1] = p.0
  }
  for p in vw_imm_instrs() {
    m[p.1] = p.0
  }
  // the control-flow containers are also pickable by label
  m["block"] = "Block"
  m["loop"] = "Loop"
  m["if"] = "If"
  m
}

///|
/// The category -> instruction-id lists (the radio filter groups).
fn vw_categories() -> Map[String, Array[String]] {
  {
    "i32": [
      "i32.add", "i32.const", "i32.div_s", "i32.div_u", "i32.eq", "i32.ge_s", "i32.ge_u",
      "i32.gt_s", "i32.gt_u", "i32.le_s", "i32.le_u", "i32.lt_s", "i32.lt_u", "i32.mul",
      "i32.ne", "i32.sub",
    ],
    "i64": [
      "i64.add", "i64.const", "i64.div_s", "i64.div_u", "i64.eq", "i64.ge_s", "i64.ge_u",
      "i64.gt_s", "i64.gt_u", "i64.le_s", "i64.le_u", "i64.lt_s", "i64.lt_u", "i64.mul",
      "i64.ne", "i64.sub",
    ],
    "f32": [
      "f32.add", "f32.const", "f32.div", "f32.eq", "f32.ge", "f32.gt", "f32.le",
      "f32.lt", "f32.mul", "f32.ne", "f32.sub",
    ],
    "f64": [
      "f64.add", "f64.const", "f64.div", "f64.eq", "f64.ge", "f64.gt", "f64.le",
      "f64.lt", "f64.mul", "f64.ne", "f64.sub",
    ],
    "control": ["block", "br", "br_if", "drop", "if", "loop", "nop"],
    "vars": ["global.get", "global.set", "local.get", "local.set", "local.tee"],
  }
}

///|
fn vw_all_ids() -> Array[String] {
  let ids : Array[String] = []
  for p in vw_plain_instrs() {
    ids.push(p.1)
  }
  for p in vw_imm_instrs() {
    ids.push(p.1)
  }
  // the control-flow containers are pickable too (this port makes block/loop/if
  // selectable from the default 'all' list, where the JS only exposed them under
  // the 'control' category)
  ids.push("block")
  ids.push("loop")
  ids.push("if")
  ids.sort_by((a, b) => a.lexical_compare(b))
  ids
}

// ─── Container components ─────────────────────────────────────────────────────

///|
priv struct VwTypesState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)

///|
fn vw_types_comp(reg : VwReg) -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="flex gap-3 types"><x render-each=".items"></x></div>
        ),
      ),
      "editor": @anode.View::new(
        "editor",
        raw_view=(
          #|<div class="flex items-center types-editor">
          #|  <div class="flex items-center group type-entry" @each=".items">
          #|    <button class="btn btn-xs btn-soft btn-circle btn-success mx-3 add-at" @on.click="$addItemAt @key">+</button>
          #|    <x render-it as="editor"></x>
          #|    <button class="btn btn-xs btn-soft btn-circle btn-error max-sm:opacity-100 opacity-0 group-hover:opacity-100 rm" @on.click="$removeInItemsAt @key">⛔</button>
          #|  </div>
          #|  <button class="btn btn-xs btn-soft btn-circle btn-success mx-3 append" @on.click="$appendItem">+</button>
          #|</div>
        ),
      ),
    },
    name="Types",
    init=VwTypesState::{ items: [] },
    mutate={
      "addItemAt": (s : VwTypesState, args) => {
        let items = s.items.copy()
        let at = @cmp.minimum(
          @cmp.maximum(0, vw_int_arg(args, 0)),
          items.length(),
        )
        items.insert(at, vw_make_type(reg, "TypeI32"))
        { items, }
      },
      "appendItem": (s : VwTypesState, _args) => {
        items: s.items + [vw_make_type(reg, "TypeI32")],
      },
    },
  )
}

///|
fn vw_block_type_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="flex gap-1 block-type">
          #|  <span class="font-mono text-gray-400 br">[</span><x render=".args"></x>
          #|  <span class="font-mono text-gray-400 br">] → [</span><x render=".returns"></x><span class="font-mono text-gray-400 br">]</span>
          #|</div>
        ),
      ),
      "editor": @anode.View::new(
        "editor",
        raw_view=(
          #|<div class="flex gap-1 items-center block-type-editor">
          #|  <span class="font-mono text-gray-400 br">[</span><x render=".args" as="editor"></x>
          #|  <span class="font-mono text-gray-400 br">] → [</span><x render=".returns" as="editor"></x><span class="font-mono text-gray-400 br">]</span>
          #|</div>
        ),
      ),
    },
    name="BlockType",
    init=VwEmptyState::{  },
    specs={
      "args": @component.FieldSpec::comp("Types"),
      "returns": @component.FieldSpec::comp("Types"),
    },
  )
}

///|
/// The body shared by Block / Loop / Func: a header (expand/edit toggles + block
/// type), the read-only item list, and the editing item list (via the macro).
fn vw_blocklike_view(keyword : String) -> String {
  "<section class=\"border-l border-l-gray-400 pl-3 ml-3 flex flex-col gap-3 blocklike \{keyword}\">" +
  "<div class=\"flex gap-3 items-center group header\">" +
  "<x:btn-toggle-expand></x:btn-toggle-expand>" +
  "<span class=\"text-sm text-gray-400 kw\">\{keyword}</span>" +
  "<div @hide=\".editing\"><x render=\".blockType\"></x></div>" +
  "<x:btn-toggle-edit></x:btn-toggle-edit>" +
  "</div>" +
  "<div @show=\".editing\"><x render=\".blockType\" as=\"editor\"></x></div>" +
  "<div class=\"flex flex-col gap-3 ro-items\" @show=\"$expandedAndReadOnly\"><x render-each=\".items\"></x></div>" +
  "<x:items-editing></x:items-editing>" +
  "</section>"
}

///|
/// The state Block / Loop / Func share; `blockType` (and Func's `locals`) are
/// component slots declared via `specs`, not state fields.
priv struct VwContainerState {
  items : Array[@tutuca.Value]
  expanded : Bool
  editing : Bool
} derive(ToJson, FromJson)

///|
fn vw_container_mutate(
  reg : VwReg,
) -> Map[String, (VwContainerState, Array[@tutuca.Value]) -> VwContainerState] {
  {
    "addItemAt": (s, args) => {
      ..s,
      items: vw_insert_picker(reg, s.items, vw_int_arg(args, 0)),
    },
    "appendItem": (s, _args) => { ..s, items: s.items + [vw_make_picker(reg)] },
  }
}

///|
fn vw_container_compute() -> Map[
  String,
  (VwContainerState, Array[@tutuca.Value]) -> @tutuca.Value,
] {
  {
    "expandedAndEditing": (s, _args) => Bool(s.expanded && s.editing),
    "expandedAndReadOnly": (s, _args) => Bool(s.expanded && !s.editing),
  }
}

///|
fn vw_container_init() -> VwContainerState {
  { items: [], expanded: true, editing: false }
}

///|
fn vw_block_comp(reg : VwReg) -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new("main", raw_view=vw_blocklike_view("block")),
      "compact": @anode.View::new(
        "compact",
        raw_view="<section class=\"compact\">block ...</section>",
      ),
    },
    name="Block",
    init=vw_container_init(),
    specs={ "blockType": @component.FieldSpec::comp("BlockType") },
    mutate=vw_container_mutate(reg),
    compute=vw_container_compute(),
  )
}

///|
fn vw_loop_comp(reg : VwReg) -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new("main", raw_view=vw_blocklike_view("loop")),
      "compact": @anode.View::new(
        "compact",
        raw_view="<section class=\"compact\">loop ...</section>",
      ),
    },
    name="Loop",
    init=vw_container_init(),
    specs={ "blockType": @component.FieldSpec::comp("BlockType") },
    mutate=vw_container_mutate(reg),
    compute=vw_container_compute(),
  )
}

///|
fn vw_func_comp(reg : VwReg) -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section class="border-l border-l-gray-400 ml-1 pl-3 flex flex-col gap-3 blocklike func">
          #|  <div class="flex gap-3 items-center group header">
          #|    <x:btn-toggle-expand></x:btn-toggle-expand>
          #|    <span class="text-sm text-gray-400 kw">func</span>
          #|    <div @hide=".editing"><x render=".blockType"></x></div>
          #|    <x:btn-toggle-edit></x:btn-toggle-edit>
          #|  </div>
          #|  <div @show=".editing"><x render=".blockType" as="editor"></x></div>
          #|  <div class="flex gap-3 ml-3 items-baseline locals" @show=".expanded">
          #|    <span class="text-sm text-gray-400 kw">locals</span>
          #|    <div @hide=".editing"><x render=".locals"></x></div>
          #|    <div @show=".editing"><x render=".locals" as="editor"></x></div>
          #|  </div>
          #|  <div class="flex flex-col gap-3 ro-items" @show="$expandedAndReadOnly"><x render-each=".items"></x></div>
          #|  <x:items-editing></x:items-editing>
          #|</section>
        ),
      ),
    },
    name="Func",
    init=vw_container_init(),
    specs={
      "blockType": @component.FieldSpec::comp("BlockType"),
      "locals": @component.FieldSpec::comp("Types"),
    },
    mutate=vw_container_mutate(reg),
    compute=vw_container_compute(),
  )
}

///|
priv struct VwIfState {
  thn : Array[@tutuca.Value]
  else_ : Array[@tutuca.Value]
  expanded : Bool
  editingIf : Bool
  editingThn : Bool
  editingElse : Bool
} derive (
  ToJson(fields(else_(rename="else"))),
  FromJson(fields(else_(rename="else"))),
)

///|
fn vw_if_comp(reg : VwReg) -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section class="border-l border-l-gray-400 pl-3 ml-3 flex flex-col gap-3 blocklike if">
          #|  <div class="flex gap-3 items-center group header">
          #|    <x:btn-toggle-expand></x:btn-toggle-expand>
          #|    <span class="text-sm text-gray-400 kw">if</span>
          #|    <div @hide=".editingIf"><x render=".blockType"></x></div>
          #|    <x:btn-toggle-edit :value=".editingIf" :handler="$toggleEditingIf"></x:btn-toggle-edit>
          #|  </div>
          #|  <div @show=".editingIf"><x render=".blockType" as="editor"></x></div>
          #|  <div class="border-l border-l-gray-400 pl-3 ml-3" @show=".expanded">
          #|    <div class="flex gap-3 items-center group header">
          #|      <span class="text-sm text-slate-400 kw">then</span>
          #|      <x:btn-toggle-edit :value=".editingThn" :handler="$toggleEditingThn"></x:btn-toggle-edit>
          #|    </div>
          #|    <div class="my-3 pl-3 flex flex-col gap-3 ro-thn" @hide=".editingThn"><x render-each=".thn"></x></div>
          #|    <x:items-editing :showval=".editingThn" :items=".thn" :onadd="$addThnAt" :onremove="$removeInThnAt" :onappend="$appendInThn"></x:items-editing>
          #|    <div class="flex gap-3 items-center group header">
          #|      <span class="text-sm text-slate-400 kw">else</span>
          #|      <x:btn-toggle-edit :value=".editingElse" :handler="$toggleEditingElse"></x:btn-toggle-edit>
          #|    </div>
          #|    <div class="my-3 pl-3 flex flex-col gap-3 ro-else" @hide=".editingElse"><x render-each=".else"></x></div>
          #|    <x:items-editing :showval=".editingElse" :items=".else" :onadd="$addElseAt" :onremove="$removeInElseAt" :onappend="$appendInElse"></x:items-editing>
          #|    <span class="text-sm text-slate-400 kw">end</span>
          #|  </div>
          #|</section>
        ),
      ),
      "compact": @anode.View::new(
        "compact",
        raw_view="<section class=\"compact\">if ...</section>",
      ),
    },
    name="If",
    init=VwIfState::{
      thn: [],
      else_: [],
      expanded: true,
      editingIf: false,
      editingThn: false,
      editingElse: false,
    },
    specs={ "blockType": @component.FieldSpec::comp("BlockType") },
    mutate={
      "addThnAt": (s : VwIfState, args) => {
        ..s,
        thn: vw_insert_picker(reg, s.thn, vw_int_arg(args, 0)),
      },
      "appendInThn": (s : VwIfState, _args) => {
        ..s,
        thn: s.thn + [vw_make_picker(reg)],
      },
      "addElseAt": (s : VwIfState, args) => {
        ..s,
        else_: vw_insert_picker(reg, s.else_, vw_int_arg(args, 0)),
      },
      "appendInElse": (s : VwIfState, _args) => {
        ..s,
        else_: s.else_ + [vw_make_picker(reg)],
      },
    },
  )
}

///|
priv struct VwSectionState {
  id : Int
  name : String
  items : Array[@tutuca.Value]
  expanded : Bool
  defaultItem : @tutuca.Value
} derive(ToJson, FromJson)

///|
fn vw_section_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section class="flex flex-col gap-3 wasm-section">
          #|  <p class="flex gap-3 items-center header">
          #|    <x:btn-toggle-expand></x:btn-toggle-expand>
          #|    <span class="sec-name" @text=".name"></span>
          #|    <button class="btn btn-xs btn-soft btn-primary add-default" @on.click="$addDefaultItem">+</button>
          #|  </p>
          #|  <div class="flex flex-col gap-3 ml-2 sec-items" @show=".expanded"><x render-each=".items"></x></div>
          #|</section>
        ),
      ),
    },
    name="Section",
    init=VwSectionState::{
      id: 0,
      name: "Section",
      items: [],
      expanded: true,
      defaultItem: Null,
    },
    mutate={
      "addDefaultItem": (s : VwSectionState, _args) => {
        ..s,
        items: s.items + [vw_with_editing(s.defaultItem)],
      },
    },
  )
}

///|
priv struct VwMemoryState {
  n : Int
  m : Int
} derive(ToJson, FromJson)

///|
fn vw_int_value(args : Array[@tutuca.Value], fallback : Int) -> Int {
  match args {
    [Str(t), ..] => {
      let parsed : Int? = Some(@string.parse_int(t)) catch { _ => None }
      match parsed {
        Some(n) => n
        None => fallback
      }
    }
    [Num(d), ..] => d.to_int()
    _ => fallback
  }
}

///|
fn vw_memory_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div class="flex gap-3 items-center memory">
          #|  <label class="input input-ghost outline-0 items-baseline h-auto">Pages
          #|    <input class="px-1 py-0 m-0 h-auto w-auto font-mono text-blue-400 n" type="number" :value=".n" @on.input="$setNFromString value" /></label>
          #|  <label class="input input-ghost outline-0 items-baseline h-auto">Max Pages
          #|    <input class="px-1 py-0 m-0 h-auto w-auto font-mono text-blue-400 m" type="number" :value=".m" @on.input="$setMFromString value" /></label>
          #|</div>
        ),
      ),
    },
    name="Memory",
    init=VwMemoryState::{ n: 1, m: 1 },
    mutate={
      "setNFromString": (s : VwMemoryState, args) => {
        ..s,
        n: vw_int_value(args, s.n),
      },
      "setMFromString": (s : VwMemoryState, args) => {
        ..s,
        m: vw_int_value(args, s.m),
      },
    },
  )
}

///|
fn vw_module_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<section class="flex flex-col gap-3 module">
          #|  <x render=".mem"></x>
          #|  <x render=".func"></x>
          #|</section>
        ),
      ),
    },
    name="Module",
    init=VwEmptyState::{  },
    specs={
      "mem": @component.FieldSpec::comp("Section", args={
        "id": Num(5),
        "name": Str("Memory"),
      }),
      "func": @component.FieldSpec::comp("Section", args={
        "id": Num(3),
        "name": Str("Functions"),
      }),
    },
  )
}

///|
priv struct VwPickerState {
  currentSection : String
  instructions : Array[@tutuca.Value]
  filter : String
} derive(ToJson, FromJson)

///|
/// The instruction picker: filter, category radios, and the pick list.
/// `selectInstructionById` (the self-replacement) is a `swap` handler that
/// answers with a fresh instance of the picked instruction component;
/// everything same-type is typed state.
fn vw_picker_comp(reg : VwReg) -> @component.Component {
  // (section, handler, radio color class, label class) — colors/label classes
  // mirror the per-radio margaui classes in the JS original.
  let radios : Array[(String, String, String, String)] = [
    ("all", "$setCurrentAll", "radio-success", "flex gap-2"),
    ("i32", "$setCurrentI32", "radio-info", "flex gap-2"),
    ("i64", "$setCurrentI64", "radio-info", "flex gap-2 text-xs"),
    ("f32", "$setCurrentF32", "radio-primary", "flex gap-2 text-xs"),
    ("f64", "$setCurrentF64", "radio-primary", "flex gap-2 text-xs"),
    ("control", "$setCurrentControl", "radio-error", "flex gap-2 text-xs"),
    ("vars", "$setCurrentVars", "radio-warning", "flex gap-2 text-xs"),
  ]
  let radio_html = StringBuilder()
  for r in radios {
    radio_html.write_string(
      "<label class=\"\{r.3} radio-label\"><input type=\"radio\" class=\"radio \{r.2} radio-xs r-\{r.0}\" @on.input=\"\{r.1}\" /> \{r.0}</label>",
    )
  }
  let mutate : Map[
    String,
    (VwPickerState, Array[@tutuca.Value]) -> VwPickerState,
  ] = Map([])
  let compute : Map[
    String,
    (VwPickerState, Array[@tutuca.Value]) -> @tutuca.Value,
  ] = Map([])
  let cats = vw_categories()
  for r in radios {
    let section = r.0
    mutate["setCurrent" + cap(section)] = (s, _args) => {
      let list = if section == "all" {
        vw_all_ids()
      } else {
        cats.get(section).unwrap_or([])
      }
      {
        ..s,
        currentSection: section,
        instructions: list.map(x => (Str(x) : @tutuca.Value)),
      }
    }
    compute["currentIs" + cap(section)] = (s, _args) => {
      Bool(s.currentSection == section)
    }
  }
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view="<section class=\"flex flex-col gap-3 w-xl picker\">" +
          "<input type=\"search\" class=\"input w-full outline-0 filter\" placeholder=\"Filter instructions\" :value=\".filter\" @on.input=\"$setFilter value\" />" +
          "<div class=\"flex gap-3 text-xs justify-between radios\">\{radio_html.to_string()}</div>" +
          "<div class=\"flex flex-col gap-1 max-h-[25vh] overflow-y-auto instr-list\">" +
          // DIVERGENCE: pass @value (the id) directly instead of reading it off the
          // DOM target, which the value layer does not expose.
          "<button class=\"btn btn-block pick\" @each=\".instructions\" @loop-with=\"loopWith\" @when=\"whenMatch\" :data-value=\"@value\" @on.click=\"selectInstructionById @value\"><x text=\"@value\"></x></button>" +
          "</div></section>",
      ),
    },
    name="InstructionPicker",
    init=VwPickerState::{
      currentSection: "all",
      instructions: vw_all_ids().map(x => (Str(x) : @tutuca.Value)),
      filter: "",
    },
    mutate~,
    compute~,
    loop_with={
      "loopWith": (s : VwPickerState, _seq, _ctx) => {
        @component.LoopWith::new(
          iter_data=Map({ "filter": Str(s.filter.to_lower()) }),
        )
      },
    },
    when={
      "whenMatch": (_s : VwPickerState, _key, value, iter) => {
        match (value, iter) {
          (Str(v), Map(idata)) =>
            match idata.get("filter") {
              Some(Str(f)) => v.to_lower().contains(f)
              _ => true
            }
          _ => true
        }
      },
    },
    swap={
      "selectInstructionById": (_s : VwPickerState, args, _ctx) => {
        let id = match args {
          [Str(t), ..] => t
          _ => ""
        }
        match vw_id_to_name().get(id) {
          Some(cname) =>
            match reg.get(cname) {
              Some(c) => Some(vw_with_editing(c.make(Map([]))))
              None => None
            }
          None => None
        }
      },
    },
  )
}

///|
fn cap(s : String) -> String {
  if s.length() == 0 {
    s
  } else {
    s[0:1].to_owned().to_upper() + s[1:].to_owned()
  }
}

// ─── Macros ──────────────────────────────────────────────────────────────────

///|
fn vw_macros() -> Map[String, @anode.Macro] {
  {
    "btn-toggle-expand": {
      defaults: Map([]),
      raw_view: "<button class=\"toggle-expand\" @if.class=\".expanded\" @then=\"'btn btn-xs btn-soft btn-primary btn-circle on'\" @else=\"'btn btn-xs btn-soft btn-success btn-circle off'\" @on.click=\"$toggleExpanded\">" +
      "<span @show=\".expanded\">▽</span><span @hide=\".expanded\">▷</span></button>",
    },
    "btn-toggle-edit": {
      defaults: { "value": ".editing", "handler": "$toggleEditing" },
      raw_view: "<button class=\"toggle-edit\" @if.class=\"^value\" @then=\"'btn btn-xs btn-soft btn-primary btn-circle on'\" @else=\"'btn btn-xs btn-soft btn-success btn-circle max-sm:opacity-100 opacity-0 group-hover:opacity-100 off'\" @on.click=\"^handler\">" +
      "<span @show=\"^value\">🔒</span><span @hide=\"^value\">✏️</span></button>",
    },
    "items-editing": {
      defaults: {
        "showval": "$expandedAndEditing",
        "items": ".items",
        "onadd": "$addItemAt",
        "onremove": "$removeInItemsAt",
        "onappend": "$appendItem",
      },
      raw_view: "<div class=\"flex flex-col gap-3 editing-items\" @show=\"^showval\">" +
      "<div class=\"flex flex-col gap-3 editing-item\" @each=\"^items\">" +
      "<div><button class=\"btn btn-xs btn-soft btn-circle btn-success add-at\" @on.click=\"^onadd @key InstructionPicker\">+</button></div>" +
      "<div class=\"flex gap-5 items-center\"><button class=\"btn btn-xs btn-soft btn-circle btn-error rm\" @on.click=\"^onremove @key\">⛔</button><x render-it as=\"compact\"></x></div>" +
      "</div>" +
      "<button class=\"btn btn-xs btn-soft btn-circle btn-success append\" @on.click=\"^onappend InstructionPicker\">+</button>" +
      "</div>",
    },
  }
}

// ─── Module assembly ─────────────────────────────────────────────────────────

///|
pub fn visual_wasm_module() -> @component.ModuleDef {
  let reg = VwReg::{ comps: Map([]) }
  let comps : Array[@component.Component] = []
  fn add(c : @component.Component) -> @component.Component {
    reg.comps[c.name] = c
    comps.push(c)
    c
  }

  // types
  add(vw_type(reg, "TypeI32", "i32")) |> ignore
  add(vw_type(reg, "TypeI64", "i64")) |> ignore
  add(vw_type(reg, "TypeF32", "f32")) |> ignore
  add(vw_type(reg, "TypeF64", "f64")) |> ignore
  // instructions from the data tables
  for p in vw_plain_instrs() {
    add(vw_instr(p.0, p.1)) |> ignore
  }
  for p in vw_imm_instrs() {
    add(vw_instr_imm(p.0, p.1)) |> ignore
  }
  // containers (registered before use is fine — resolution is at render time)
  add(vw_types_comp(reg)) |> ignore
  add(vw_block_type_comp()) |> ignore
  add(vw_block_comp(reg)) |> ignore
  add(vw_loop_comp(reg)) |> ignore
  add(vw_if_comp(reg)) |> ignore
  add(vw_func_comp(reg)) |> ignore
  add(vw_section_comp()) |> ignore
  add(vw_memory_comp()) |> ignore
  add(vw_module_comp()) |> ignore
  add(vw_picker_comp(reg)) |> ignore
  @component.ModuleDef::new(
    name="visual-wasm",
    components=comps,
    macros=vw_macros(),
    examples=[
      { component: "Module", title: "Empty Module", args: Map([]), view: None },
      {
        component: "InstructionPicker",
        title: "Instruction Picker",
        args: Map([]),
        view: None,
      },
    ],
  )
}
