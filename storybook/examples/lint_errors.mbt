// Port of docs/examples/lint-errors.js — components with INTENTIONAL lint
// errors for the linter demo (and the port's semantic-lint fixture; see
// lint_errors_test.mbt). The JS sections whose rules are statically
// impossible in MoonBit are dropped: ASYNC_HANDLER, UNKNOWN_COMPONENT_SPEC_KEY,
// COMP_FIELD_BAD_SHAPE, FIELD_NAME_RESERVED_BY_RECORD, SUGGEST_BINDING_MEMBER
// and the object-shaped LOOKUP_BAD_SHAPE (LookupSpec is typed — only a
// malformed target string remains, which is LOOKUP_TARGET_MALFORMED).
//
// Typed-state divergence: `update` is one opaque pattern match, so the linter
// can no longer enumerate input-handler names — INPUT_HANDLER_NOT_REFERENCED
// and INPUT_HANDLER_FOR_INPUT_HANDLER_METHOD are catalog-only and dropped
// here. LintDemo deliberately has NO `update` fn: that is the only case where
// bare-name references stay checkable, so `doClick` (a $-callable referenced
// bare) still yields INPUT_HANDLER_METHOD_FOR_INPUT_HANDLER, and the
// unimplemented `doKeyDown` bare references now yield
// INPUT_HANDLER_NOT_IMPLEMENTED.

///|
priv struct LintDemoState {
  count : Int
  items : Array[@tutuca.Value]
  kind : String
  isOpen : Bool
  child : @tutuca.Value
} derive(ToJson, FromJson)

///|
fn lint_demo_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div>
          #|  <p>Lint Errors Demo - check the lint output</p>
          #|
          #|  <!-- RENDER_IT_OUTSIDE_OF_LOOP: render-it without @each -->
          #|  <x render-it></x>
          #|
          #|  <!-- UNKNOWN_EVENT_MODIFIER: +badmod is not a known modifier -->
          #|  <button @on.click+badmod="doKeyDown">bad modifier</button>
          #|
          #|  <!-- UNKNOWN_HANDLER_ARG_NAME: unknownArg is not recognized -->
          #|  <button @on.click="doKeyDown unknownArg event">unknown arg</button>
          #|
          #|  <!-- INPUT_HANDLER_METHOD_FOR_INPUT_HANDLER (hint): doClick is a
          #|       method referenced bare; the port's Input dispatch falls back to
          #|       methods, so this is a nudge to '$doClick', not an error -->
          #|  <button @on.click="doClick">method as handler</button>
          #|
          #|  <!-- INPUT_HANDLER_METHOD_NOT_IMPLEMENTED + INPUT_HANDLER_FOR_INPUT_HANDLER_METHOD:
          #|       doKeyDown is input but referenced as method (with $) -->
          #|  <button @on.keydown="$doKeyDown">handler as method</button>
          #|
          #|  <!-- FIELD_VAL_NOT_DEFINED: .missing is not defined -->
          #|  <p :title=".missing">undefined field</p>
          #|
          #|  <!-- FIELD_VAL_IS_METHOD: .doClick names a method — use $doClick -->
          #|  <p :title=".doClick">field is a method</p>
          #|
          #|  <!-- METHOD_VAL_IS_FIELD: $count names a field — use .count -->
          #|  <p :title="$count">method is a field</p>
          #|
          #|  <!-- METHOD_VAL_NOT_DEFINED: neither a method nor a field -->
          #|  <p :title="$noSuchMethod">undefined method</p>
          #|
          #|  <!-- DYN_VAL_NOT_DEFINED: *missingDyn is not provided or looked up -->
          #|  <p :title="*missingDyn">undefined dynamic</p>
          #|
          #|  <!-- UNKNOWN_COMPONENT_NAME -->
          #|  <button @on.click="doKeyDown UnknownComp">unknown comp</button>
          #|
          #|  <!-- ALT_HANDLER_NOT_DEFINED: myEnrich is not defined in alter -->
          #|  <div @enrich-with="myEnrich">undefined alter handler</div>
          #|
          #|  <!-- ALT_HANDLER_NOT_DEFINED x3: undefined @when / @enrich-with / @loop-with -->
          #|  <ul @each=".items" @when="myWhen" @enrich-with="myLoopEnrich" @loop-with="myLoopWith">
          #|    <li><x render-it></x></li>
          #|  </ul>
          #|
          #|  <!-- UNKNOWN_MACRO_ARG: extra is not declared in the macro defaults -->
          #|  <x:labeled label="'ok'" extra="'oops'"></x:labeled>
          #|
          #|  <!-- UNKNOWN_DIRECTIVE: @bogus is not a known directive -->
          #|  <div @bogus="oops">unknown directive</div>
          #|
          #|  <!-- UNKNOWN_X_OP: bogus is not a known <x> op -->
          #|  <x bogus="oops"></x>
          #|
          #|  <!-- UNKNOWN_X_ATTR: bogus is not a known attribute on <x render-each> -->
          #|  <x render-each=".items" bogus="nope"></x>
          #|
          #|  <!-- X_OP_IGNORES_CHILDREN: <x render> ignores its children -->
          #|  <x render=".child"><p>hi</p></x>
          #|
          #|  <!-- DEPRECATED_BARE_X_DIRECTIVE: bare 'show' on an <x> op is the
          #|       legacy spelling of '@show' -->
          #|  <ul @each=".items"><x render-it show=".isOpen"></x></ul>
          #|
          #|  <!-- UNKNOWN_X_OP + MAYBE_DROP_AT_PREFIX: @text as the op is unknown;
          #|       hint suggests dropping the @ -->
          #|  <x @text=".count"></x>
          #|
          #|  <!-- MAYBE_ADD_AT_PREFIX: 'show' written as a plain attribute -->
          #|  <div show=".isOpen">missing @ on host directive</div>
          #|
          #|  <!-- BAD_VALUE on attr: '.123bad' is not a valid identifier -->
          #|  <p :title=".123bad">bad attr value</p>
          #|
          #|  <!-- BAD_VALUE on directive: '@text=""' has no parseable value -->
          #|  <p @text="">bad directive value</p>
          #|
          #|  <!-- BAD_VALUE on x-op -->
          #|  <x render=".123bad"></x>
          #|
          #|  <!-- BAD_VALUE on macro var: '^undefined' isn't declared -->
          #|  <p :title="^undefined">bad macro var</p>
          #|
          #|  <!-- BINDING_MEMBER_TOO_DEEP: only one member read on a binding -->
          #|  <ul>
          #|    <li @each=".items" @text="@value.a.b"></li>
          #|  </ul>
          #|
          #|  <!-- UNSUPPORTED_EXPR_SYNTAX (ternary) -->
          #|  <p :class=".isOpen ? 'on' : 'off'">ternary in :class</p>
          #|
          #|  <!-- UNSUPPORTED_EXPR_SYNTAX (comparison) -->
          #|  <p :class=".kind === 'foo'">comparison in :class</p>
          #|
          #|  <!-- UNSUPPORTED_EXPR_SYNTAX (logical) -->
          #|  <p :class=".isOpen && .kind">logical in :class</p>
          #|
          #|  <!-- UNSUPPORTED_EXPR_SYNTAX (call-with-args) -->
          #|  <p :class="$doClick 'foo'">call-with-args in :class</p>
          #|
          #|  <!-- REDUNDANT_TEMPLATE_STRING: a single {expr} is just the expr -->
          #|  <p :title="$'{.count}'">redundant template in :title</p>
          #|  <p :class="$'{.kind}'">redundant template in :class</p>
          #|
          #|  <!-- PLACEHOLDERLESS_TEMPLATE_STRING: no dynamic parts -->
          #|  <p :title="$'plain text'">placeholderless template</p>
          #|
          #|  <!-- CONSTANT_CONDITION: a non-boolean literal never changes -->
          #|  <p @show="'yes'">constant string condition</p>
          #|
          #|  <!-- DUPLICATE_ATTR_DEFINITION: "class" set by :class AND @if.class
          #|       (the literal+@if pair alone is the port's allowed fallback idiom) -->
          #|  <div class="literal" :class=".kind" @if.class=".isOpen" @then="'on'" @else="'off'">
          #|    duplicate class
          #|  </div>
          #|
          #|  <!-- IF_NO_BRANCH_SET: @if.class without @then or @else -->
          #|  <div @if.class=".isOpen">if without then or else</div>
          #|
          #|  <p @text=".count">0</p>
          #|</div>
        ),
      ),
    },
    name="LintDemo",
    init=LintDemoState::{
      count: 0,
      items: [],
      kind: "",
      isOpen: false,
      child: Null,
    },
    mutate={ "doClick": (s : LintDemoState, _args) => s },
    when={
      // ALT_HANDLER_NOT_REFERENCED: defined here but never used in a view
      "unusedAlter": (_s : LintDemoState, _key, _value, _iter) => true,
    },
    provide={
      // PROVIDE_NOT_ADDRESSABLE: a provide must be a field (.f) or
      // seq-access (.s[.k]) path — it doubles as a render-target / teleport
      // path, so a method ($doClick) is rejected.
      "badProvide": "$doClick",
    },
    lookup={
      // DYN_ALIAS_NOT_REFERENCED: declared but never read as *unusedDyn
      "unusedDyn": { source: "Theme.color", default: Some("'gray'") },
      // LOOKUP_TARGET_MALFORMED: target must be "Producer.provideName"
      "badTarget": { source: "NoDotHere", default: None },
    },
  )
}

///|
priv struct HtmlLintDemoState {
  count : Int
} derive(ToJson, FromJson)

///|
fn html_lint_demo_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new(
        "main",
        raw_view=(
          #|<div>
          #|  <p>HTML structural lint errors — check the lint output</p>
          #|  <MyTag>camelcase tag</MyTag>
          #|  <svg width="20" height="20"><myShape></myShape></svg>
          #|  <table><div>foster-parented</div></table>
          #|  <table>plain text inside table</table>
          #|  <select><li>not allowed</li></select>
          #|  <br></br>
          #|  <form><input><form><input></form></form>
          #|  <a href="#"><a href="#">nested anchor</a></a>
          #|  <p><b><i>misnested</b></i></p>
          #|  <article>oops</span></article>
          #|  <section><span>still open</section>
          #|  <div class="a" class="b">duplicate attr</div>
          #|  <div></div class="foo">
          #|  <div></div/>
          #|  <input value=>
          #|  <![CDATA[unexpected]]>
          #|  <!badmarkup>
          #|  <svg viewbox="0 0 10 10"></svg>
          #|  <math definitionurl="x"></math>
          #|  <p @text=".count">0</p>
          #|</div>
        ),
      ),
    },
    name="HtmlLintDemo",
    init=HtmlLintDemoState::{ count: 0 },
  )
}

///|
priv struct ScopedStyleDemoState {
  count : Int
} derive(ToJson, FromJson)

///|
fn scoped_style_demo_comp() -> @component.Component {
  @component.component(
    compiled_views={
      "main": @anode.View::new("main", raw_view="<p @text=\".count\">0</p>"),
    },
    name="ScopedStyleDemo",
    init=ScopedStyleDemoState::{ count: 0 },
    // commonStyle/style are wrapped in a component-scoped selector, so
    // top-level CSS lands inside a style-rule block where it is invalid or
    // dead. Both belong in globalStyle (injected verbatim).
    common_style=(
      #|/* TOP_LEVEL_AT_RULE_IN_SCOPED_STYLE: @keyframes can't be nested */
      #|@keyframes spin { from { transform: rotate(0); } to { transform: rotate(360deg); } }
      #|/* GLOBAL_SELECTOR_IN_SCOPED_STYLE: leading body becomes a dead descendant */
      #|body { margin: 0; }
    ),
  )
}

///|
pub fn lint_errors_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="lint-errors",
    components=[
      lint_demo_comp(),
      html_lint_demo_comp(),
      scoped_style_demo_comp(),
    ],
    macros={
      "labeled": {
        defaults: { "label": "'hi'" },
        raw_view: "<span @text=\"^label\"></span>",
      },
    },
    examples=[
      {
        component: "LintDemo",
        title: "AST lint errors",
        args: Map([]),
        view: None,
      },
      {
        component: "HtmlLintDemo",
        title: "HTML structural lint errors",
        args: Map([]),
        view: None,
      },
      {
        component: "ScopedStyleDemo",
        title: "Scoped-style top-level CSS errors",
        args: Map([]),
        view: None,
      },
    ],
  )
}
