// Spec for tutuca's template-AST layer and its
// attribute layer. READONLY by convention: concrete public
// data types plus `declare` stubs for every function/method. Implement the
// declares in separate files; this file and the anode *_test.mbt suites
// define the contract.
//
// Scope: parse-only. No render stack, continuation frames, or event-path
// reconstruction (those are render territory). Fragment parsing is provided by html_adapter.mbt
// (parse_fragment) on top of moonbit-community/html.

// ---------------------------------------------------------------------------
// Namespaces and parse-time diagnostics

///|
/// Non-HTML element namespace; None on DomData means HTML (the plain
/// createElement convention rather than createElementNS).
pub(all) enum Ns {
  Svg
  MathML
} derive(Debug, Eq)

///|
/// Where a value string failed to parse (the "bad-value" roles).
/// Anode/attr-level roles carry their slot; value-layer failures (macro vars,
/// handler names, predicates) arrive via @tscript.ParseCtx.issues and are
/// wrapped as ValueIssue.
pub(all) enum BadValueRole {
  XOp(op~ : String)
  Attr(name~ : String)
  Directive(name~ : String)
  IfDirective(name~ : String)
  ValueIssue(@tscript.IssueRole)
} derive(Debug, Eq)

///|
/// Parse-time issues surfaced through ParseHandler::on_parse_issue (JS
/// ParseContext.onParseIssue kinds). The base handler warns; the linter's
/// collector turns them into lint findings.
pub(all) enum ParseIssue {
  UnknownDirective(name~ : String, value~ : String)
  UnknownXOp(name~ : String, value~ : String)
  UnknownXAttr(op~ : String, name~ : String, value~ : String)
  XOpIgnoresChildren(op~ : String)
  BadValue(role~ : BadValueRole, value~ : String)
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Attribute layer (parse side)

///|
/// `@if.<name>` conditional attribute with optional `@then`/`@else` branches
/// (None = the not-set sentinel).
pub(all) struct IfAttr {
  name : String
  cond_val : @tutuca.Val
  mut then_val : @tutuca.Val?
  mut else_val : @tutuca.Val?
} derive(Debug)

///|
/// One parsed attribute of a DynAttrs element.
pub(all) enum AttrItem {
  /// Dynamic `:attr` (or macro attr): value evaluated per render.
  Plain(name~ : String, val~ : @tutuca.Val)
  /// Constant attribute (plain HTML attr, data-eid, setDataAttr insertions).
  ConstA(name~ : String, val~ : @tutuca.Val)
  /// `@dangerouslysetinnerhtml` (None val = failed parse, attr kept).
  RawHtml(val~ : @tutuca.Val?)
  /// `@setinnermd`: a markdown source string (None val = failed parse, same
  /// sentinel convention as `RawHtml`).
  ///
  /// Its own variant rather than a flag on `RawHtml` because the two differ in
  /// the only way that matters here: raw HTML is a capability a host grants
  /// (`SanitizerConfig.raw_markup`), while markdown has no way to reach the DOM
  /// except through a node builder that consults the sanitizer for every
  /// element and every attribute value. Pass 1 refuses the first by default and
  /// never refuses the second — which it cannot express if they share a case.
  RawMarkdown(val~ : @tutuca.Val?)
  /// `@setinnerhtml`: an HTML source string (None val = failed parse, same
  /// sentinel convention as `RawHtml`).
  ///
  /// The safe half of `RawHtml`, and a separate case for the same reason
  /// `RawMarkdown` is one. `RawHtml` reaches the DOM as markup — `set_prop`
  /// hands it to `set_inner_html` — so the only lever a host has over it is
  /// whether to permit the construct, which is what `raw_markup` is. This
  /// reaches the DOM only through `@markup.html_nodes`, which asks the
  /// sanitizer about every element and every attribute value it builds, so
  /// there is nothing here for a host to grant and Pass 1 never refuses it.
  /// One variant for both would make that difference inexpressible.
  SafeHtml(val~ : @tutuca.Val?)
  /// `@setinnersvg`: an SVG source string (None val = failed parse, same
  /// sentinel convention as `RawHtml`).
  ///
  /// Not a flag on `SafeHtml`, because the two differ before the sanitizer ever
  /// sees them: the payload is parsed in a different insertion mode, and the
  /// namespace that comes out of that decides which half of a
  /// namespace-qualified config applies. `svg("script")` and `html("script")`
  /// are different entries.
  SafeSvg(val~ : @tutuca.Val?)
  If(IfAttr)
} derive(Debug)

///|
/// An element's parsed attributes: fully-constant attrs collapse to an
/// evaluated map (ConstAttrs), anything dynamic keeps the item list
/// (DynAttrs). @tutuca.Lit doubles as the constant scalar type.
pub(all) enum Attrs {
  ConstAttrs(Map[String, @tutuca.Lit])
  DynAttrs(Array[AttrItem])
} derive(Debug)

///|
/// The representation an item list calls for: a list nothing made dynamic
/// (a non-constant `Plain`, a `RawHtml`, a `RawMarkdown`, an `If`) collapses to the evaluated
/// ConstAttrs map, anything else keeps the items. The parser and `h` share
/// this so a compiled tree cannot disagree with a parsed one.
declare pub fn attrs_of_items(items : Array[AttrItem]) -> Attrs

///|
declare pub fn Attrs::is_constant(self : Attrs) -> Bool

///|
/// Insert/overwrite a data-* attribute on attr containers.
declare fn Attrs::set_data_attr(
  self : Attrs,
  key : String,
  val : @tutuca.Lit,
) -> Unit

///|
/// Macro-call attrs become SOURCE STRINGS keyed by name:
/// values round-trip through the value layer's original-syntax Show.
declare fn Attrs::to_macro_vars(self : Attrs) -> Map[String, String]

///|
/// Node kinds a directive attribute can wrap the element with.
pub(all) enum WrapperKind {
  Show
  Hide
  Each
  Scope
  PushView
} derive(Debug, Eq)

///|
/// Wrapper descriptor produced by attribute parsing, in OUTERMOST-FIRST order
/// (the first directive in source order wraps outermost). The three extras
/// are only set for Each (from @enrich-with / @when / @loop-with).
pub(all) struct WrapperAttr {
  kind : WrapperKind
  raw : String
  val : @tutuca.Val?
  mut enrich_with_val : @tutuca.Val?
  mut when_val : @tutuca.Val?
  mut loop_with_val : @tutuca.Val?
} derive(Debug)

///|
/// Result of parsing an element's attribute list (the
/// [pAttrs, wrapperAttrs, textChild] tuple; wrappers is empty instead of null).
pub(all) struct AttrParseResult {
  attrs : Attrs
  wrappers : Array[WrapperAttr]
  text_child : @tutuca.Val?
  bind : BindData?
} derive(Debug)

///|
/// A pending `@bind` found by the HTML parser. The view generator resolves it
/// against the component schema and fills `event.binding`; keeping the source
/// value here lets that pass reject anything other than a direct state field.
pub(all) struct BindData {
  target : @tutuca.Val
  property : String
  event : NodeEvent
} derive(Debug)

///|
/// The checked coercion attached to the setter event synthesized for
/// `@bind`. Runtime dispatch uses it to reject invalid browser values before
/// they can reach a generated field mutator.
pub(all) enum BindCoercion {
  /// Parsed but not schema-checked. Runtime dispatch rejects it; viewgen
  /// replaces it with one of the concrete cases below.
  BindPending
  BindString
  BindBool
  BindInt(width~ : Int, signed~ : Bool)
  BindDouble
} derive(Debug, Eq)

///|
/// Parse an ordered attribute list (as delivered by the HTML parser).
/// `parse_all` is the macro-call mode: every `:attr` value parses with the
/// widest grammar instead of the text grammar.
declare fn parse_attributes(
  attrs : Array[(String, String)],
  px : ParseContext,
  parse_all? : Bool = false,
) -> AttrParseResult

///|
/// Event handlers registered on an element (data only, the
/// runtime modifier wrappers are out of scope). `id` round-trips through the
/// element's data-eid attribute.
pub(all) struct NodeEvents {
  id : Int
  handlers : Array[NodeEvent]
} derive(Debug)

///|
/// One `@on.<name>+mod+...` handler (minus compiled modifiers).
pub(all) struct NodeEvent {
  name : String
  handler : @tscript.HandlerParse
  modifiers : Array[String]
  mut binding : BindCoercion?
} derive(Debug)

// ---------------------------------------------------------------------------
// AST (the BaseNode class hierarchy as an enum; payload structs are
// reference types, so tree/registry aliasing matches the object graph)

///|
pub(all) struct TextData {
  mut val : String
} derive(Debug)

///|
pub(all) struct DomData {
  tag : String // lowercase for HTML; SVG camelCase preserved
  attrs : Attrs
  childs : Array[ANode]
  ns : Ns?
  /// Which render-time rules this element's attribute NAMES could concern, or
  /// `None` until something has looked.
  ///
  /// A memo, not a parse result, and anode neither fills it nor reads it:
  /// deciding it needs the name tables in `vdom/filter`, which anode must not
  /// import (see `sinks/moon.pkg` for why the type lives in a package of its
  /// own). `render` fills it the first time it builds this element and every
  /// later render reads it — see `render/render.mbt`.
  ///
  /// Safe to memo because it is a fact about NAMES, and an element's attribute
  /// names never change after it is parsed. The one thing that edits `attrs`
  /// afterwards is `set_data_attr`, whose four callers all write a `data-*`
  /// name — `data-vid`, `data-cid`, `data-nid` — and no rule looks at those.
  /// `sink_hints_test.mbt` holds that.
  mut sink_hints : @sinks.SinkHints?
  bind : BindData?
} derive(Debug)

///|
pub(all) struct FragmentData {
  childs : Array[ANode]
} derive(Debug)

///|
/// `<x text=...>` / `@text` output node. node_id is None for the `@text`
/// directive's child (built with a null nodeId, unregistered).
pub(all) struct RenderTextData {
  node_id : Int?
  val : @tutuca.Val
} derive(Debug)

///|
/// `<x render="...">`: renders the component the value resolves to.
/// view_val is the parsed `as=` view selector (None when absent).
pub(all) struct RenderData {
  node_id : Int
  val : @tutuca.Val
  view_val : @tutuca.Val?
} derive(Debug)

///|
/// `<x render-it>`: renders the current item; carries no value of its own.
pub(all) struct RenderItData {
  node_id : Int
  view_val : @tutuca.Val?
} derive(Debug)

///|
/// Shared payload of the value-carrying wrappers (Show/Hide/PushView/Scope).
/// node_id is Some only when the node registers in ParseContext.nodes
/// (Scope always; Show/Hide only in their <x>-extra-attr form).
pub(all) struct WrapData {
  node_id : Int?
  val : @tutuca.Val
  mut node : ANode
} derive(Debug)

///|
/// `<x slot="name">` inside a macro call body.
pub(all) struct SlotData {
  name : String
  mut node : ANode
} derive(Debug)

///|
/// Iteration spec shared by `@each` and `<x render-each>` (evaluation
/// deferred to the renderer).
pub(all) struct IterInfo {
  val : @tutuca.Val
  mut when_val : @tutuca.Val?
  mut loop_with_val : @tutuca.Val?
  mut enrich_with_val : @tutuca.Val?
} derive(Debug)

///|
pub(all) struct EachData {
  node_id : Int
  iter_info : IterInfo
  mut node : ANode
  /// Marker for the linter: this Each is `<x render-each>` sugar and has no
  /// wrapper-attr record to check instead.
  mut from_render_each : Bool
} derive(Debug)

///|
/// A macro call site (`<x:name ...>`), expanded later by compile(scope).
/// attrs are source strings (see Attrs::to_macro_vars); data_attrs collected
/// via set_data_attr are replayed onto the expansion.
pub(all) struct MacroData {
  name : String
  attrs : Map[String, String]
  slots : Map[String, ANode]
  px : ParseContext
  mut node : ANode?
  data_attrs : Map[String, @tutuca.Lit]
}

///|
/// Prints everything but px (the parse-context back-reference would cycle).
declare pub impl Debug for MacroData

///|
/// The template AST. One variant per BaseNode subclass.
pub(all) enum ANode {
  Text(TextData)
  Comment(TextData) // same payload/behavior as Text
  Dom(DomData)
  Fragment(FragmentData)
  RenderText(RenderTextData)
  Render(RenderData)
  RenderIt(RenderItData)
  Show(WrapData)
  Hide(WrapData)
  PushView(WrapData)
  Slot(SlotData)
  Scope(WrapData)
  Each(EachData)
  MacroCall(MacroData)
} derive(Debug)

///|
/// True for Text/Comment whose text is only spaces/tabs/newlines/CRs.
declare pub fn ANode::is_whitespace(self : ANode) -> Bool

///|
declare pub fn ANode::has_newline(self : ANode) -> Bool

///|
/// Visit this node's immediate structural children in source order. Keeping
/// this package-internal makes the variant-to-child mapping one fact shared by
/// tree walkers without exposing traversal mechanics as public API.
declare fn ANode::for_each_child(self : ANode, visit : (ANode) -> Unit) -> Unit

///|
/// Replace a whitespace-only Text/Comment's text (whitespace condensing).
declare fn ANode::condense_whitespace(
  self : ANode,
  replacement? : String = "",
) -> Unit

///|
/// Stamp a data-* attribute on the node's rendered output carrier(s):
/// Dom → own attrs, Fragment → every child, wrappers → inner node,
/// MacroCall → recorded and replayed on the expansion; render/text nodes
/// produce no element of their own and ignore it.
declare fn ANode::set_data_attr(
  self : ANode,
  key : String,
  val : @tutuca.Lit,
) -> Unit

///|
/// Put `node` inside this wrapper variant (Show/Hide/PushView/Scope/Slot/Each).
/// Scope additionally stamps data-nid on the wrapped node.
declare fn ANode::wrap_node(self : ANode, node : ANode) -> Unit

///|
/// Collect the class names a margaui-style scanner can see: literal `class="…"`
/// values split on whitespace, plus — for dynamic `:class` and
/// `@if.class`/`@then`/`@else` — only the literal fragments (Const values
/// and the Const parts of template strings). Call on COMPILED views so
/// macro-expanded classes are included; runtime-composed class strings are
/// invisible.
declare pub fn ANode::collect_classes(self : ANode, into : Set[String]) -> Unit

///|
/// Whether anything in this tree sets markup directly
/// (`@dangerouslysetinnerhtml`). Call on COMPILED views. A host that
/// compiles markup it did not write asks this before rendering it, because
/// the directive's value is a runtime expression: allowing the construct is
/// the only decision available ahead of time.
declare pub fn ANode::has_raw_html(self : ANode) -> Bool

///|
/// Collect every `$name` this tree calls — in attributes (plain, `@if`
/// branches, `@dangerouslysetinnerhtml`), in `@text` / `<x render>` values, in
/// the Show/Hide/PushView/Scope wrappers, and in an `@each`'s
/// `@when`/`@loop-with`/`@enrich-with` — plus the ones nested inside a `$'…'`
/// template or a predicate's arguments.
///
/// Purely syntactic: it says what the template NAMES, not what answers. A layer
/// that knows which names a component declares (the dyncomp host does, from its
/// manifest) is what turns that into a diagnostic. Call on COMPILED views, so a
/// macro's body is walked as its expansion.
///
/// `@on` handlers are NOT here — attribute parsing registers those on the
/// ParseContext rather than in the tree. Use `View::collect_method_names` to
/// get both halves.
declare pub fn ANode::collect_method_names(
  self : ANode,
  into : Set[String],
) -> Unit

///|
/// `ANode::collect_method_names` over this view's compiled tree AND the `@on`
/// handlers its parse registered — the whole of what one view calls.
declare pub fn View::collect_method_names(
  self : View,
  into : Set[String],
) -> Unit

///|
/// A single child stays bare; several become a Fragment.
declare fn maybe_fragment(childs : Array[ANode]) -> ANode

// ---------------------------------------------------------------------------
// Builders (build.mbt): hyperscript-shaped constructors over the types above,
// with the rarely-set fields as optional arguments. Each one returns the value
// the parser builds for the same markup — they are what `tutuca gen-views`
// emits, and what a hand-written view or test should use.

///|
/// `Const(lit=LStr(s), from_macro=false)`, the constant a plain attribute
/// value or a literal handler argument parses to.
declare pub fn const_str(s : String) -> @tutuca.Val

///|
declare pub fn const_num(n : Double) -> @tutuca.Val

///|
declare pub fn const_bool(b : Bool) -> @tutuca.Val

///|
declare pub fn const_null() -> @tutuca.Val

///|
/// A plain HTML attribute: `ConstA` with a constant string.
declare pub fn attr(name : String, value : String) -> AttrItem

///|
declare pub fn attr_num(name : String, value : Double) -> AttrItem

///|
/// A valueless boolean attribute (`disabled`, `checked`, …).
declare pub fn attr_bool(name : String, value : Bool) -> AttrItem

///|
/// `ConstA` with a value built by hand — the escape hatch for a constant that
/// came from a macro variable (`from_macro=true`).
declare pub fn attr_val(name : String, val : @tutuca.Val) -> AttrItem

///|
/// The `data-eid` stamp that ties an element to its NodeEvents entry.
declare pub fn eid(id : Int) -> AttrItem

///|
/// A dynamic `:attr`, evaluated per render (`Plain`).
declare pub fn dyn_attr(name : String, val : @tutuca.Val) -> AttrItem

///|
/// `@if.<name>` with its optional `@then` / `@else` values.
declare pub fn if_attr(
  name : String,
  cond : @tutuca.Val,
  then_val? : @tutuca.Val,
  else_val? : @tutuca.Val,
) -> AttrItem

///|
/// `@dangerouslysetinnerhtml` (None val = the failed-parse sentinel).
declare pub fn raw_html(val? : @tutuca.Val) -> AttrItem

///|
/// An element. The attribute list decides the representation exactly as the
/// parser does — `attrs_of_items` is the one implementation of that rule — so
/// a caller never names ConstAttrs or DynAttrs.
declare pub fn h(
  tag : String,
  attrs : Array[AttrItem],
  childs : Array[ANode],
  ns? : Ns,
) -> ANode

///|
declare pub fn text(val : String) -> ANode

///|
declare pub fn comment(val : String) -> ANode

///|
declare pub fn frag(childs : Array[ANode]) -> ANode

///|
/// `<x text=…>` / `@text` output. `id` is unset for the `@text` directive's
/// child, which registers no node of its own.
declare pub fn dyn_text(val : @tutuca.Val, id? : Int) -> ANode

///|
/// `<x render=…>`, with the optional `as=` view selector.
declare pub fn render(id : Int, val : @tutuca.Val, view? : @tutuca.Val) -> ANode

///|
/// `<x render-it>`, with the optional `as=` view selector.
declare pub fn render_it(id : Int, view? : @tutuca.Val) -> ANode

///|
/// `@show`; `id` is set only in the `<x show=…>` form, which registers.
declare pub fn show(val : @tutuca.Val, node : ANode, id? : Int) -> ANode

///|
declare pub fn hide(val : @tutuca.Val, node : ANode, id? : Int) -> ANode

///|
declare pub fn push_view(val : @tutuca.Val, node : ANode, id? : Int) -> ANode

///|
/// A loop-less `@enrich-with` frame. Always registers, hence the plain id.
declare pub fn scope(id : Int, val : @tutuca.Val, node : ANode) -> ANode

///|
declare pub fn slot(name : String, node : ANode) -> ANode

///|
/// `@each` / `<x render-each>`; the three extras come from `@when`,
/// `@loop-with` and `@enrich-with` on the same element.
declare pub fn each(
  id : Int,
  val : @tutuca.Val,
  node : ANode,
  when_val? : @tutuca.Val,
  loop_with_val? : @tutuca.Val,
  enrich_with_val? : @tutuca.Val,
  from_render_each? : Bool,
) -> ANode

///|
/// One `@on.<name>+mod+…` handler.
declare pub fn on(
  name : String,
  handler : @tutuca.Val,
  args? : Array[@tutuca.Val],
  modifiers? : Array[String],
  binding? : BindCoercion,
) -> NodeEvent

///|
/// Normalize insignificant whitespace between element children:
/// leading/trailing whitespace is dropped; an interior whitespace run with a
/// newline collapses to a single space, or to nothing between two block-level
/// elements. Whitespace-only Comments participate exactly like Text (they
/// share the Text payload and behavior).
declare pub fn condense_childs_whites(childs : Array[ANode]) -> Array[ANode]

// ---------------------------------------------------------------------------
// Parse context (subclass hooks become a trait)

///|
/// Extension hooks fired during parsing (ParseContext method overrides).
/// Defaults: warn on parse issues, stay silent otherwise — so a live app's
/// context behaves like the default and the linter overrides both.
pub(open) trait ParseHandler {
  fn on_parse_issue(Self, ParseIssue, String?) -> Unit = _
  fn on_attributes(Self, AttrParseResult, Bool, String) -> Unit = _
}

///|
impl ParseHandler with fn on_parse_issue(_self, issue, current_tag) {
  let tag = current_tag.unwrap_or("?")
  @tutuca.warn("tutuca parse issue in <\{tag}>: \{Repr(issue)}")
}

///|
impl ParseHandler with fn on_attributes(_self, _result, _is_macro_call, _tag) {

}

///|
/// The default handler used when none is given.
pub(all) struct WarnHandler {}

///|
pub impl ParseHandler for WarnHandler

///|
/// Per-macro-expansion state (px.frame).
pub(all) struct MacroFrame {
  macro_name : String
  macro_vars : Map[String, String]
  macro_slots : Map[String, ANode]
}

///|
/// Parse-time registries and state. nodes/events/macro_nodes are shared
/// across enter_macro (same arrays), so node ids stay globally sequential.
pub struct ParseContext {
  nodes : Array[ANode]
  events : Array[NodeEvents]
  macro_nodes : Array[ANode]
  parent : ParseContext?
  frame : MacroFrame?
  /// The `$$name` table this parse runs against — what the HOST bound, not
  /// anything the parsed source can add to.
  ///
  /// Context-wide rather than per-frame, which is the opposite of `macro_vars`
  /// and for the opposite reason: a macro frame exists to scope the CALLER's
  /// arguments to one expansion, and there is nothing to scope here — every
  /// frame in one parse is looking at the same host's decision. `enter_macro`
  /// therefore inherits it.
  ///
  /// Mutable and empty by default so `ParseContext::new` keeps its signature:
  /// whoever holds the config sets it before parsing, which is `View`.
  mut config_vars : Map[String, String]
  /// Created lazily on the first value-parse call (keeps value-free parsing
  /// independent of the value layer's constructor).
  mut val_ctx : @tscript.ParseCtx?
  mut current_tag : String?
  handler : &ParseHandler
}

///|
declare pub fn ParseContext::new(
  handler? : &ParseHandler,
  config_vars? : Map[String, String],
) -> ParseContext

///|
/// New context for expanding macro `name`: shared registries and handler,
/// fresh frame and value ParseCtx (with the frame's macro vars), self as parent.
declare pub fn ParseContext::enter_macro(
  self : ParseContext,
  name : String,
  vars : Map[String, String],
  slots : Map[String, ANode],
) -> ParseContext

///|
declare fn ParseContext::is_inside_macro(
  self : ParseContext,
  name : String,
) -> Bool

///|
/// Allocate the next NodeEvents id (first event attr on an element).
declare fn ParseContext::register_events(self : ParseContext) -> NodeEvents

///|
/// Build a MacroCall from a call site's parsed attrs and children: `<x slot>`
/// children become named slots, remaining non-whitespace children fill the
/// default `_` slot (one shared array, aliased with the fragment's).
declare fn ParseContext::new_macro_node(
  self : ParseContext,
  name : String,
  m_attrs : Map[String, String],
  childs : Array[ANode],
) -> ANode

///|
/// Expand every MacroCall registered during parsing (macro_nodes may grow
/// while compiling nested macros — index loop, not iterator).
declare pub fn ParseContext::compile(
  self : ParseContext,
  scope : &MacroScope,
) -> Unit raise MacroError

///|
/// Raised on recursive macro expansion (direct or indirect).
pub suberror MacroError {
  RecursiveMacro(String)
}

///|
/// A macro definition: default vars plus the raw template to expand.
pub(all) struct Macro {
  defaults : Map[String, String]
  raw_view : String
}

///|
declare pub fn Macro::expand(self : Macro, px : ParseContext) -> ANode

///|
/// Macro lookup environment.
pub(open) trait MacroScope {
  fn lookup_macro(Self, String) -> Macro?
}

///|
/// A named template (parse side: no render). compile() parses the
/// raw view, stamps data-cid/data-vid and expands macros.
pub(all) struct View {
  name : String
  raw_view : String
  style : String
  /// What `$$name` resolves to when this view is parsed — the host's table,
  /// carried here rather than on `ParseContext` because `Component::compile`
  /// builds the context and knows nothing about any of this. `parse_source`
  /// moves it across.
  config_vars : Map[String, String]
  mut anode : ANode?
  mut ctx : ParseContext?
  /// How to turn `raw_view` into a tree — `None` for a view that already IS
  /// one (`View::from_ir`), where `compile` only stamps the component id.
  ///
  /// A function slot rather than the `ir : Bool` it replaced, and that is the
  /// whole point: with a flag, `compile` named `ANode::parse` on the branch it
  /// did not take, so every program that compiled a view linked the HTML
  /// parser whether it could reach it or not. Only `View::new` names the
  /// parser now, so a program that never calls it does not carry one — worth
  /// 195 KB of a 439 KB ahead-of-time wasm bundle (44%), measured in
  /// benchmarks/OPTIMIZATIONS.md.
  parse : ((View, ParseContext, &MacroScope, @tutuca.Lit?) -> Unit raise MacroError)?
}

///|
/// Rebuild the compile context of an ahead-of-time compiled view: `nodes` is
/// recovered from `root`, `events` is the generator's table in registration
/// order.
declare fn ParseContext::from_ir(
  root : ANode,
  events : Array[NodeEvents],
) -> ParseContext

///|
/// One NodeEvents per handler list, id = position (the id `register_events`
/// would have handed out, and the one elements carry in data-eid).
declare pub fn events_of(
  handlers : Array[Array[NodeEvent]],
) -> Array[NodeEvents]

///|
/// A view whose tree was compiled ahead of time (`tutuca gen-views`). Stamps
/// data-vid and runs the constant-subtree optimization; `compile` then only
/// stamps the adopting component's data-cid.
declare pub fn View::from_ir(
  name : String,
  root : ANode,
  handlers : Array[Array[NodeEvent]],
  style? : String,
) -> View

///|
declare pub fn View::new(
  name : String,
  raw_view? : String = "No View Defined",
  style? : String = "",
  config_vars? : Map[String, String],
) -> View

///|
declare pub fn View::compile(
  self : View,
  ctx : ParseContext,
  scope : &MacroScope,
  cid? : @tutuca.Lit,
) -> Unit raise MacroError

// ---------------------------------------------------------------------------
// Parse entry points

///|
/// Parse a template string into an AST: empty input yields
/// Comment("Empty View in ANode.parse"); a single root parses directly;
/// several roots are whitespace-condensed into a fragment. None only when a
/// single root is an `<x>` op whose value failed to parse.
declare pub fn ANode::parse(html : String, px : ParseContext) -> ANode?
