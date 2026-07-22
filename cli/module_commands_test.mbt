// Module-command engine tests: a programmatic ModuleDef drives the wired
// get/list/examples/show/render/lint commands through plan_with_module.

///|
priv struct CardState {
  title : String
  sheet : Map[String, @tutuca.Value]
} derive(ToJson, FromJson)

///|
priv struct ItemState {
  label : String
} derive(ToJson, FromJson)

///|
fn demo_module(bad_provide? : Bool = false) -> @component.ModuleDef {
  let provide : Map[String, String] = { "active": ".sheet" }
  if bad_provide {
    provide["broken"] = "not a field!"
  }
  let card = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div class=\"card\"><h2><x text=\".title\"></x></h2><x render=\".item\"></x></div>",
      ),
    },
    name="Card",
    init=CardState::{ title: "untitled", sheet: Map([]) },
    specs={ "item": @component.FieldSpec::comp("Item") },
    update=(s : CardState, msg, _ctx) => {
      match msg {
        Receive("rename", [Str(t)]) => Some({ ..s, title: t })
        _ => None
      }
    },
    provide~,
  )
  let item = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<span><x text=\".label\"></x></span>",
      ),
    },
    name="Item",
    init=ItemState::{ label: "hi" },
  )
  @component.ModuleDef::new(name="demo", components=[card, item], examples=[
    {
      component: "Card",
      title: "basic",
      args: { "title": Str("Hello") },
      view: None,
    },
    { component: "Item", title: "plain", args: Map([]), view: None },
  ])
}

///|
fn run(argv : Array[String], m : @component.ModuleDef) -> Emit {
  match @cli.plan_with_module(argv, Some(m)) {
    Done(emit) => emit
    _ => { out: "", err: "unexpected outcome", exit_code: 99 }
  }
}

///|
test "get summarizes the module" {
  let e = run(["get"], demo_module())
  assert_eq(e.exit_code, 0)
  assert_true(e.out.contains("module demo"))
  assert_true(e.out.contains("components: 2 (Card, Item)"))
  assert_true(e.out.contains("examples: 2"))
}

///|
test "list respects --limit and signals truncation" {
  let e = run(["list", "--limit=1"], demo_module())
  assert_eq(e.out, "Card\n… truncated\n")
  let all = run(["list"], demo_module())
  assert_eq(all.out, "Card\nItem\n")
}

///|
test "a non-integer --limit is a usage error, not a silent no-op" {
  let e = run(["list", "--limit=abc"], demo_module())
  assert_eq(e.exit_code, 1)
  assert_true(e.err.contains("--limit expects an integer, got 'abc'"))
  let spaced = run(["list", "--limit", "1x"], demo_module())
  assert_eq(spaced.exit_code, 1)
  assert_true(spaced.err.contains("--limit expects an integer, got '1x'"))
}

///|
test "examples filters by the component-name positional" {
  let e = run(["examples", "Card"], demo_module())
  assert_eq(e.out, "Card — basic\n")
}

///|
test "show documents fields, views, provides and handlers" {
  let e = run(["show", "Card"], demo_module())
  assert_true(e.out.contains("# Card"))
  assert_true(e.out.contains("title: text = untitled"))
  assert_true(e.out.contains("item: comp(Item) = null"))
  assert_true(e.out.contains("views: main"))
  assert_true(e.out.contains("provide: active = .sheet"))
  assert_true(e.out.contains("handlers: update"))
  assert_false(e.out.contains("# Item")) // filtered
}

///|
test "render mounts each example headlessly and cleans the output" {
  let e = run(["render", "Card"], demo_module())
  assert_eq(e.exit_code, 0)
  assert_true(e.out.contains("## Card — basic"))
  assert_true(e.out.contains("<h2>Hello</h2>"))
  // FComp default rendered through the real resolver, metas/stamps stripped
  assert_true(e.out.contains("<span>hi</span>"))
  assert_false(e.out.contains("§"))
  assert_false(e.out.contains("data-cid"))
}

///|
test "lint reports bad provide shapes with exit code 2" {
  let clean = run(["lint"], demo_module())
  assert_eq(clean.exit_code, 0)
  assert_eq(clean.out, "no findings\n")
  let dirty = run(["lint"], demo_module(bad_provide=true))
  assert_eq(dirty.exit_code, 2)
  assert_true(dirty.out.contains("PROVIDE_NOT_ADDRESSABLE Card.provide.broken"))
}

///|
test "--json produces structured output for every module command" {
  // get
  let g = run(["get", "--json"], demo_module())
  assert_eq(g.exit_code, 0)
  guard @json.parse(g.out) is Object(gj)
  @debug.assert_eq(gj.get("module"), Some(Json::string("demo")))
  guard gj.get("counts") is Some(Object(counts))
  @debug.assert_eq(counts.get("examples"), Some(Json::number(2)))
  // list (with truncation flag)
  let l = run(["list", "--limit=1", "--json"], demo_module())
  guard @json.parse(l.out) is Object(lj)
  @debug.assert_eq(lj.get("truncated"), Some(Json::boolean(true)))
  guard lj.get("components") is Some(Array(comps)) && comps.length() == 1
  // examples
  let e = run(["examples", "--json"], demo_module())
  guard @json.parse(e.out) is Object(ej)
  guard ej.get("examples") is Some(Array(exs)) && exs.length() == 2
  // show — fields/views/provide/handlers surfaced structurally
  let s = run(["show", "Card", "--json"], demo_module())
  guard @json.parse(s.out) is Object(sj)
  guard sj.get("components") is Some(Array(scomps))
  guard scomps[0] is Object(card)
  @debug.assert_eq(card.get("name"), Some(Json::string("Card")))
  guard card.get("fields") is Some(Object(fields))
  guard fields.get("title") is Some(Object(title))
  @debug.assert_eq(title.get("kind"), Some(Json::string("text")))
  // render — html carried per example
  let r = run(["render", "Card", "--json"], demo_module())
  guard @json.parse(r.out) is Object(rj)
  guard rj.get("examples") is Some(Array(rexs))
  guard rexs[0] is Object(rex)
  guard rex.get("html") is Some(String(html))
  assert_true(html.contains("<h2>Hello</h2>"))
  // lint — findings array + exit code preserved across formats
  let dirty = run(["lint", "--json"], demo_module(bad_provide=true))
  assert_eq(dirty.exit_code, 2)
  guard @json.parse(dirty.out) is Object(dj)
  guard dj.get("findings") is Some(Array(finds))
  assert_true(finds.length() > 0)
}

///|
test "lint flags @on handlers that don't resolve, allows declared ones" {
  // onGood is a declared swap handler (bare-name Input-dispatched); onTypo
  // and onRecv resolve to nothing. The component deliberately has NO update
  // fn — with one, any bare name may be handled and the check is skipped.
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><button @on.click=\"onGood\">ok</button><button @on.click=\"onTypo\">bad</button><button @on.click=\"onRecv\">recv</button></div>",
      ),
    },
    name="Btns",
    init=BtnsState::{ n: 0 },
    swap={ "onGood": (_s : BtnsState, _args, _ctx) => None },
  )
  let m = @component.ModuleDef::new(name="btns", components=[comp], examples=[])
  let e = run(["lint"], m)
  assert_eq(e.exit_code, 2)
  assert_true(e.out.contains("INPUT_HANDLER_NOT_IMPLEMENTED Btns/main"))
  assert_true(e.out.contains("onTypo"))
  assert_true(e.out.contains("onRecv"))
  assert_false(e.out.contains("onGood")) // the declared swap handler passes
}

///|
priv struct BtnsState {
  n : Int
} derive(ToJson, FromJson)

///|
test "lint checks field and method references in views" {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x text=\".missing\"></x><span :class=\"$isOn\"></span><p @show=\".count\"><x text=\"$label\"></x></p></div>",
      ),
    },
    name="Vals",
    init=ItemState::{ label: "x" },
    compute={ "count": (_s : ItemState, _args) => Num(1) },
  )
  let m = @component.ModuleDef::new(name="vals", components=[comp], examples=[])
  let e = run(["lint"], m)
  assert_eq(e.exit_code, 2)
  // .missing: neither field nor method
  assert_true(e.out.contains("FIELD_VAL_NOT_DEFINED Vals/main"))
  // $isOn: not a method; did-you-mean is not required here
  assert_true(e.out.contains("METHOD_VAL_NOT_DEFINED Vals/main"))
  // @show=".count" reads a field, but count is a method
  assert_true(e.out.contains("FIELD_VAL_IS_METHOD Vals/main"))
  assert_true(e.out.contains("use '$count'"))
  // $label calls a method, but label is a field
  assert_true(e.out.contains("METHOD_VAL_IS_FIELD Vals/main"))
}

///|
test "lint flags unknown dynamic bindings, event modifiers and handler args" {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x text=\"*missing\"></x><button @on.click+shift=\"go value wat\">x</button></div>",
      ),
    },
    name="Dyns",
    init=DynsState::{ sheet: Map([]) },
    swap={ "go": (_s : DynsState, _args, _ctx) => None },
    provide={ "active": ".sheet" },
  )
  let m = @component.ModuleDef::new(name="dyns", components=[comp], examples=[])
  let e = run(["lint"], m)
  assert_eq(e.exit_code, 2)
  assert_true(e.out.contains("DYN_VAL_NOT_DEFINED Dyns/main"))
  // +shift is not a click modifier (only ctrl/cmd/meta/alt)
  assert_true(e.out.contains("UNKNOWN_EVENT_MODIFIER Dyns/main"))
  // `value` is a known handler arg, `wat` is not
  assert_true(e.out.contains("UNKNOWN_HANDLER_ARG_NAME Dyns/main"))
  assert_true(e.out.contains("'wat'"))
  assert_false(e.out.contains("'value'"))
}

///|
test "lint hints unreferenced declarations and warns constant conditions" {
  // INPUT_HANDLER_NOT_REFERENCED is gone by construction: `update` is one
  // opaque pattern match, so declared-but-unreferenced input names are
  // unknowable. The alter-bucket hint survives (when/enrich/enrich_scope/
  // loop_with are name-keyed).
  let comp = @component.component(
    views={
      "main": @anode.View::new("main", raw_view="<div @show=\"'yes'\">hi</div>"),
    },
    name="Hints",
    init=BtnsState::{ n: 0 },
    when={ "unusedAlter": (_s : BtnsState, _k, _v, _iter) => true },
  )
  let m = @component.ModuleDef::new(name="hints", components=[comp], examples=[])
  let e = run(["lint"], m)
  // warnings/hints only: exit code stays 0 (JS hasErrors ? 2 : 0)
  assert_eq(e.exit_code, 0)
  assert_true(e.out.contains("CONSTANT_CONDITION (warning) Hints/main"))
  assert_true(e.out.contains("ALT_HANDLER_NOT_REFERENCED (hint) Hints"))
}

///|
test "lint flags render-it outside a loop and scoped-style leaks" {
  let comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<div><x render-it></x></div>",
        style="@keyframes spin { from { opacity: 0 } } body { margin: 0 }",
      ),
    },
    name="Loops",
    init=BtnsState::{ n: 0 },
  )
  let m = @component.ModuleDef::new(name="loops", components=[comp], examples=[])
  let e = run(["lint"], m)
  assert_eq(e.exit_code, 2)
  assert_true(e.out.contains("RENDER_IT_OUTSIDE_OF_LOOP Loops/main"))
  assert_true(e.out.contains("TOP_LEVEL_AT_RULE_IN_SCOPED_STYLE Loops/main"))
  assert_true(e.out.contains("GLOBAL_SELECTOR_IN_SCOPED_STYLE Loops/main"))
  // inside an @each the same render-it is fine
  let ok_comp = @component.component(
    views={
      "main": @anode.View::new(
        "main",
        raw_view="<ul><li @each=\".items\"><x render-it></x></li></ul>",
      ),
    },
    name="Loops",
    init=LoopsState::{ items: [] },
  )
  let m2 = @component.ModuleDef::new(name="loops2", components=[ok_comp], examples=[])
  let e2 = run(["lint"], m2)
  assert_false(e2.out.contains("RENDER_IT_OUTSIDE_OF_LOOP"))
}

///|
test "non-module commands and help fall back to the plain dispatcher" {
  let help = run(["get", "-h"], demo_module())
  assert_eq(help.exit_code, 0)
  assert_true(help.out.has_prefix("get: Summarize"))
  let unknown = run(["frobnicate"], demo_module())
  assert_true(unknown.exit_code != 0)
  // and with no module, module commands still stub (unchanged behavior)
  match @cli.plan(["get", "./m.js"]) {
    Done(e) => assert_true(e.err.contains("not implemented"))
    _ => fail("unexpected outcome")
  }
}

///|
priv struct DynsState {
  sheet : Map[String, @tutuca.Value]
} derive(ToJson, FromJson)

///|
priv struct LoopsState {
  items : Array[@tutuca.Value]
} derive(ToJson, FromJson)
