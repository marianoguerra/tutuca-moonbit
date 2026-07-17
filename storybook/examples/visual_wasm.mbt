// Port of docs/examples/visual-wasm.js — a visual editor for WebAssembly
// modules. The largest example: ~75 components, most produced by FACTORIES
// (instr / type / instrImmInt), dispatched through lookup tables, with recursive
// Block/Loop/If nesting and per-component editor/compact views.
//
// PORT PATTERNS (all seen in earlier examples, at scale here):
//   - factories = plain functions returning components (json, tree)
//   - a `reg` map for mutual recursion and lookup-table dispatch (json)
//   - self-replacement handlers: setType / selectInstructionById return a fresh
//     instance of a DIFFERENT component type (json's JsonSelector)
//   - `^handler`/`^onadd` macro indirection (todo-macros)
//   - editor/compact named views, `:style="$'…'"` (styles, multiple-views)
//
// TWO PORT DIVERGENCES:
//   1. The picker's `selectInstructionById(target)` reads `target.dataset.value`
//      off the raw DOM element — which the value layer does not expose. Ported
//      to pass the loop's `@value` (the instruction id) directly, so no DOM
//      object is needed. The click handler is `selectInstructionById @value`.
//   2. This required implementing `insertInItemsAt` (the generated list-insert
//      mutator, which was missing) in the runtime — see component/component.mbt.

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
fn VwReg::make_(
  self : VwReg,
  name : String,
  args? : Map[String, @tutuca.Value] = {},
) -> @tutuca.Value {
  match self.comps.get(name) {
    Some(c) => c.make(args).to_value()
    None => Null
  }
}

///|
/// Call `setEditing(true)` on a value if that mutator exists (i.e. the component
/// has an `editing` bool field), else return it unchanged. JS:
/// `v.setEditing ? v.setEditing(true) : v`.
fn vw_with_editing(v : @tutuca.Value) -> @tutuca.Value {
  match v {
    Obj(o) =>
      match o.obj_field("setEditing") {
        Some(Fn(f)) => f([Bool(true)])
        _ => v
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
/// Insert a fresh picker into a list field before index i (the `addItemAt`
/// body, shared by every container).
fn vw_insert_picker(
  reg : VwReg,
  inst : @component.Instance,
  field : String,
  i : Int,
) -> @tutuca.Value {
  let items = match inst.get(field) {
    List(a) => a.copy()
    _ => []
  }
  let at = @cmp.minimum(@cmp.maximum(0, i), items.length())
  items.insert(at, reg.make_("InstructionPicker"))
  inst.set(field, List(items)).to_value()
}

///|
fn vw_append_picker(
  reg : VwReg,
  inst : @component.Instance,
  field : String,
) -> @tutuca.Value {
  let items = match inst.get(field) {
    List(a) => a.copy()
    _ => []
  }
  items.push(reg.make_("InstructionPicker"))
  inst.set(field, List(items)).to_value()
}

// ─── Factories ───────────────────────────────────────────────────────────────

///|
/// A leaf instruction: renders its label, no state.
fn vw_instr(name : String, label : String) -> @component.Component {
  @component.component(name~, view="<span class=\"instr\">\{label}</span>")
}

///|
/// An instruction with an immediate integer operand (local.get 3, i32.const 42).
fn vw_instr_imm(name : String, label : String) -> @component.Component {
  @component.component(
    name~,
    view="<div class=\"flex gap-3 items-baseline instr-imm\"><span>\{label}</span>" +
      "<input class=\"input px-1 py-0 m-0 h-auto input-ghost font-mono text-blue-400 imm\" :value=\".value\" :style=\"$'width: {$getInputWidth}; outline: none'\" @on.input=\"$setFromRawValue value\" /></div>",
    fields={
      "value": @component.FieldSpec::of_default(Num(0)),
      "rawValue": @component.FieldSpec::of_default(Str("0")),
    },
    methods={
      "setFromRawValue": (inst, args) => {
        let s = match args {
          [Str(s), ..] => s
          _ => ""
        }
        let parsed : Int? = Some(@string.parse_int(s)) catch { _ => None }
        match parsed {
          Some(v) =>
            inst
            .set("rawValue", Str(s))
            .set("value", Num(v.to_double()))
            .to_value()
          None => inst.set("rawValue", Str(s)).to_value()
        }
      },
      "getInputWidth": (inst, _args) => {
        let n = match inst.get("rawValue") {
          Str(s) => s.length()
          _ => 1
        }
        Str("\{n + 2}em")
      },
    },
  )
}

///|
/// A value type (i32/i64/f32/f64). `setType` self-replaces with the chosen type.
fn vw_type(reg : VwReg, name : String, label : String) -> @component.Component {
  @component.component(
    name~,
    view="<span class=\"font-italic text-amber-400 type\">\{label}</span>",
    views={
      "editor": "<select class=\"select select-ghost px-0 font-italic text-amber-400 type-select\" @on.input=\"setType value\">" +
      "<option value=\"i32\">i32</option><option value=\"i64\">i64</option>" +
      "<option value=\"f32\">f32</option><option value=\"f64\">f64</option></select>",
    },
    input={
      "setType": (inst, args, _ctx) => {
        let id = match args {
          [Str(s), ..] => s
          _ => ""
        }
        match reg.get(type_comp_name(id)) {
          Some(c) => Some(c.make({}))
          None => Some(inst)
        }
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
  let m : Map[String, String] = {}
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
fn vw_types_comp(reg : VwReg) -> @component.Component {
  @component.component(
    name="Types",
    view=(
      #|<div class="flex gap-3 types"><x render-each=".items"></x></div>
    ),
    views={
      "editor": (
        #|<div class="flex items-center types-editor">
        #|  <div class="flex items-center group type-entry" @each=".items">
        #|    <button class="btn btn-xs btn-soft btn-circle btn-success mx-3 add-at" @on.click="$addItemAt @key">+</button>
        #|    <x render-it as="editor"></x>
        #|    <button class="btn btn-xs btn-soft btn-circle btn-error max-sm:opacity-100 opacity-0 group-hover:opacity-100 rm" @on.click="$removeInItemsAt @key">⛔</button>
        #|  </div>
        #|  <button class="btn btn-xs btn-soft btn-circle btn-success mx-3 append" @on.click="$appendItem">+</button>
        #|</div>
      ),
    },
    fields={ "items": @component.FieldSpec::of_default(List([])) },
    methods={
      "addItemAt": (inst, args) => {
        let items = match inst.get("items") {
          List(a) => a.copy()
          _ => []
        }
        let at = @cmp.minimum(
          @cmp.maximum(0, vw_int_arg(args, 0)),
          items.length(),
        )
        items.insert(at, reg.make_("TypeI32"))
        inst.set("items", List(items)).to_value()
      },
      "appendItem": (inst, _args) => {
        let items = match inst.get("items") {
          List(a) => a.copy()
          _ => []
        }
        items.push(reg.make_("TypeI32"))
        inst.set("items", List(items)).to_value()
      },
    },
  )
}

///|
fn vw_block_type_comp() -> @component.Component {
  @component.component(
    name="BlockType",
    view=(
      #|<div class="flex gap-1 block-type">
      #|  <span class="font-mono text-gray-400 br">[</span><x render=".args"></x>
      #|  <span class="font-mono text-gray-400 br">] → [</span><x render=".returns"></x><span class="font-mono text-gray-400 br">]</span>
      #|</div>
    ),
    views={
      "editor": (
        #|<div class="flex gap-1 items-center block-type-editor">
        #|  <span class="font-mono text-gray-400 br">[</span><x render=".args" as="editor"></x>
        #|  <span class="font-mono text-gray-400 br">] → [</span><x render=".returns" as="editor"></x><span class="font-mono text-gray-400 br">]</span>
        #|</div>
      ),
    },
    fields={
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
fn vw_container_methods(reg : VwReg) -> Map[String, @component.MethodFn] {
  {
    "expandedAndEditing": (inst, _args) => {
      Bool(
        inst.get("expanded") is Bool(true) && inst.get("editing") is Bool(true),
      )
    },
    "expandedAndReadOnly": (inst, _args) => {
      Bool(
        inst.get("expanded") is Bool(true) &&
        !(inst.get("editing") is Bool(true)),
      )
    },
    "addItemAt": (inst, args) => {
      vw_insert_picker(reg, inst, "items", vw_int_arg(args, 0))
    },
    "appendItem": (inst, _args) => vw_append_picker(reg, inst, "items"),
  }
}

///|
fn vw_container_fields() -> Map[String, @component.FieldSpec] {
  {
    "items": @component.FieldSpec::of_default(List([])),
    "blockType": @component.FieldSpec::comp("BlockType"),
    "expanded": @component.FieldSpec::of_default(Bool(true)),
    "editing": @component.FieldSpec::of_default(Bool(false)),
  }
}

///|
fn vw_block_comp(reg : VwReg) -> @component.Component {
  @component.component(
    name="Block",
    view=vw_blocklike_view("block"),
    views={ "compact": "<section class=\"compact\">block ...</section>" },
    fields=vw_container_fields(),
    methods=vw_container_methods(reg),
  )
}

///|
fn vw_loop_comp(reg : VwReg) -> @component.Component {
  @component.component(
    name="Loop",
    view=vw_blocklike_view("loop"),
    views={ "compact": "<section class=\"compact\">loop ...</section>" },
    fields=vw_container_fields(),
    methods=vw_container_methods(reg),
  )
}

///|
fn vw_func_comp(reg : VwReg) -> @component.Component {
  let fields = vw_container_fields()
  fields["locals"] = @component.FieldSpec::comp("Types")
  @component.component(
    name="Func",
    view=(
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
    fields~,
    methods=vw_container_methods(reg),
  )
}

///|
fn vw_if_comp(reg : VwReg) -> @component.Component {
  @component.component(
    name="If",
    view=(
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
    views={ "compact": "<section class=\"compact\">if ...</section>" },
    fields={
      "thn": @component.FieldSpec::of_default(List([])),
      "else": @component.FieldSpec::of_default(List([])),
      "blockType": @component.FieldSpec::comp("BlockType"),
      "expanded": @component.FieldSpec::of_default(Bool(true)),
      "editingIf": @component.FieldSpec::of_default(Bool(false)),
      "editingThn": @component.FieldSpec::of_default(Bool(false)),
      "editingElse": @component.FieldSpec::of_default(Bool(false)),
    },
    methods={
      "addThnAt": (inst, args) => {
        vw_insert_picker(reg, inst, "thn", vw_int_arg(args, 0))
      },
      "appendInThn": (inst, _args) => vw_append_picker(reg, inst, "thn"),
      "addElseAt": (inst, args) => {
        vw_insert_picker(reg, inst, "else", vw_int_arg(args, 0))
      },
      "appendInElse": (inst, _args) => vw_append_picker(reg, inst, "else"),
    },
  )
}

///|
fn vw_section_comp() -> @component.Component {
  @component.component(
    name="Section",
    view=(
      #|<section class="flex flex-col gap-3 wasm-section">
      #|  <p class="flex gap-3 items-center header">
      #|    <x:btn-toggle-expand></x:btn-toggle-expand>
      #|    <span class="sec-name" @text=".name"></span>
      #|    <button class="btn btn-xs btn-soft btn-primary add-default" @on.click="$addDefaultItem">+</button>
      #|  </p>
      #|  <div class="flex flex-col gap-3 ml-2 sec-items" @show=".expanded"><x render-each=".items"></x></div>
      #|</section>
    ),
    fields={
      "id": @component.FieldSpec::of_default(Num(0)),
      "name": @component.FieldSpec::of_default(Str("Section")),
      "items": @component.FieldSpec::of_default(List([])),
      "expanded": @component.FieldSpec::of_default(Bool(true)),
      "defaultItem": @component.FieldSpec::of_default(Null),
    },
    methods={
      "addDefaultItem": (inst, _args) => {
        let items = match inst.get("items") {
          List(a) => a.copy()
          _ => []
        }
        items.push(vw_with_editing(inst.get("defaultItem")))
        inst.set("items", List(items)).to_value()
      },
    },
  )
}

///|
fn vw_memory_comp() -> @component.Component {
  @component.component(
    name="Memory",
    view=(
      #|<div class="flex gap-3 items-center memory">
      #|  <label class="input input-ghost outline-0 items-baseline h-auto">Pages
      #|    <input class="px-1 py-0 m-0 h-auto w-auto font-mono text-blue-400 n" type="number" :value=".n" @on.input="$setNFromString value" /></label>
      #|  <label class="input input-ghost outline-0 items-baseline h-auto">Max Pages
      #|    <input class="px-1 py-0 m-0 h-auto w-auto font-mono text-blue-400 m" type="number" :value=".m" @on.input="$setMFromString value" /></label>
      #|</div>
    ),
    fields={
      "n": @component.FieldSpec::of_default(Num(1)),
      "m": @component.FieldSpec::of_default(Num(1)),
    },
    methods={
      "setNFromString": (inst, args) => vw_set_int(inst, "n", args),
      "setMFromString": (inst, args) => vw_set_int(inst, "m", args),
    },
  )
}

///|
fn vw_set_int(
  inst : @component.Instance,
  field : String,
  args : Array[@tutuca.Value],
) -> @tutuca.Value {
  match args {
    [Str(s), ..] => {
      let parsed : Int? = Some(@string.parse_int(s)) catch { _ => None }
      match parsed {
        Some(n) => inst.set(field, Num(n.to_double())).to_value()
        None => inst.to_value()
      }
    }
    [Num(n), ..] => inst.set(field, Num(n)).to_value()
    _ => inst.to_value()
  }
}

///|
fn vw_module_comp() -> @component.Component {
  @component.component(
    name="Module",
    view=(
      #|<section class="flex flex-col gap-3 module">
      #|  <x render=".mem"></x>
      #|  <x render=".func"></x>
      #|</section>
    ),
    fields={
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
  let methods : Map[String, @component.MethodFn] = {}
  let cats = vw_categories()
  for r in radios {
    let section = r.0
    methods["setCurrent" + cap(section)] = (inst, _args) => {
      let list = if section == "all" {
        vw_all_ids()
      } else {
        cats.get(section).unwrap_or([])
      }
      inst
      .set("currentSection", Str(section))
      .set("instructions", List(list.map(s => Str(s))))
      .to_value()
    }
    methods["currentIs" + cap(section)] = (inst, _args) => {
      Bool(inst.get("currentSection") is Str(s) && s == section)
    }
  }
  @component.component(
    name="InstructionPicker",
    view="<section class=\"flex flex-col gap-3 w-xl picker\">" +
      "<input type=\"search\" class=\"input w-full outline-0 filter\" placeholder=\"Filter instructions\" :value=\".filter\" @on.input=\"$setFilter value\" />" +
      "<div class=\"flex gap-3 text-xs justify-between radios\">\{radio_html.to_string()}</div>" +
      "<div class=\"flex flex-col gap-1 max-h-[25vh] overflow-y-auto instr-list\">" +
      // DIVERGENCE: pass @value (the id) directly instead of reading it off the
      // DOM target, which the value layer does not expose.
      "<button class=\"btn btn-block pick\" @each=\".instructions\" @loop-with=\"loopWith\" @when=\"whenMatch\" :data-value=\"@value\" @on.click=\"selectInstructionById @value\"><x text=\"@value\"></x></button>" +
      "</div></section>",
    fields={
      "currentSection": @component.FieldSpec::of_default(Str("all")),
      "instructions": @component.FieldSpec::of_default(
        List(vw_all_ids().map(s => Str(s))),
      ),
      "filter": @component.FieldSpec::of_default(Str("")),
    },
    methods~,
    input={
      "selectInstructionById": (inst, args, _ctx) => {
        let id = match args {
          [Str(s), ..] => s
          _ => ""
        }
        match vw_id_to_name().get(id) {
          Some(cname) =>
            match reg.get(cname) {
              Some(c) => Some(vw_instance_with_editing(c.make({})))
              None => Some(inst)
            }
          None => Some(inst)
        }
      },
    },
    alter={
      "loopWith": (inst, _args) => {
        let f = match inst.get("filter") {
          Str(s) => s.to_lower()
          _ => ""
        }
        Map({ "iterData": Map({ "filter": Str(f) }) })
      },
      "whenMatch": (_inst, args) => {
        match args {
          [_key, Str(val), Map(idata), ..] =>
            match idata.get("filter") {
              Some(Str(f)) => Bool(val.to_lower().contains(f))
              _ => Bool(true)
            }
          _ => Bool(true)
        }
      },
    },
  )
}

///|
/// Enter edit mode if this component has an `editing` field (JS's
/// `comp.setEditing ? comp.setEditing(true) : comp`).
fn vw_instance_with_editing(inst : @component.Instance) -> @component.Instance {
  match inst.get("editing") {
    Bool(_) => inst.set("editing", Bool(true))
    _ => inst
  }
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
      defaults: {},
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
  let reg = VwReg::{ comps: {} }
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
      { component: "Module", title: "Empty Module", args: {}, view: None },
      {
        component: "InstructionPicker",
        title: "Instruction Picker",
        args: {},
        view: None,
      },
    ],
  )
}
