// Spec for the port of tutuca's template-AST layer (src/anode.js) and its
// attribute layer (src/attribute.js). READONLY by convention: concrete public
// data types plus `declare` stubs for every function/method. Implement the
// declares in separate files; this file and the anode *_test.mbt suites
// define the contract.
//
// Scope: parse-only. No render(stack, rx), no Renderer, no compileModifiers
// runtime, no toPathStep/resolveDynProducer (event-path reconstruction is
// render territory). Fragment parsing is provided by html_adapter.mbt
// (parse_fragment) on top of moonbit-community/html.

// ---------------------------------------------------------------------------
// Namespaces and parse-time diagnostics

///|
/// Non-HTML element namespace; None on DomData means HTML (mirrors the JS
/// `namespace = null` convention for createElement vs createElementNS).
pub(all) enum Ns {
  Svg
  MathML
} derive(Debug, Eq)

///|
/// Where a value string failed to parse (JS onParseIssue "bad-value" roles).
/// Anode/attr-level roles carry their slot; value-layer failures (macro vars,
/// handler names, predicates) arrive via @tutuca.ParseCtx.issues and are
/// wrapped as ValueIssue.
pub(all) enum BadValueRole {
  XOp(op~ : String)
  Attr(name~ : String)
  Directive(name~ : String)
  IfDirective(name~ : String)
  ValueIssue(@tutuca.IssueRole)
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

///|
/// Still-valid syntax that the linter nudges away from (JS onDeprecatedSyntax;
/// the runtime handler stays silent).
pub(all) enum DeprecatedSyntax {
  // TEMPORARY (JS note dated 2026-07-08): bare `show`/`hide`/`when`/`loop-with`
  // attrs on <x> ops are the legacy spelling of the `@`-prefixed directives.
  BareXDirective(op~ : String, name~ : String)
} derive(Debug, Eq)

// ---------------------------------------------------------------------------
// Attribute layer (port of src/attribute.js, parse side)

///|
/// `@if.<name>` conditional attribute with optional `@then`/`@else` branches
/// (None = JS NOT_SET_VAL sentinel).
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
  /// `@dangerouslysetinnerhtml` (None val = failed parse, JS keeps the attr).
  RawHtml(val~ : @tutuca.Val?)
  If(IfAttr)
} derive(Debug)

///|
/// An element's parsed attributes: fully-constant attrs collapse to an
/// evaluated map (JS ConstAttrs), anything dynamic keeps the item list
/// (JS DynAttrs). @tutuca.Lit doubles as the constant scalar type.
pub(all) enum Attrs {
  ConstAttrs(Map[String, @tutuca.Lit])
  DynAttrs(Array[AttrItem])
} derive(Debug)

///|
declare pub fn Attrs::is_constant(self : Attrs) -> Bool

///|
/// Insert/overwrite a data-* attribute (JS setDataAttr on attr containers).
declare pub fn Attrs::set_data_attr(
  self : Attrs,
  key : String,
  val : @tutuca.Lit,
) -> Unit

///|
/// Macro-call attrs become SOURCE STRINGS keyed by name (JS toMacroVars):
/// values round-trip through the value layer's original-syntax Show.
declare pub fn Attrs::to_macro_vars(self : Attrs) -> Map[String, String]

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
/// Result of parsing an element's attribute list (JS AttrParser.parse's
/// [pAttrs, wrapperAttrs, textChild] tuple; wrappers is empty instead of null).
pub(all) struct AttrParseResult {
  attrs : Attrs
  wrappers : Array[WrapperAttr]
  text_child : @tutuca.Val?
} derive(Debug)

///|
/// Parse an ordered attribute list (as delivered by the HTML parser).
/// `parse_all` is the macro-call mode: every `:attr` value parses with the
/// widest grammar (JS parseMacroAttr) instead of the text grammar.
declare pub fn parse_attributes(
  attrs : Array[(String, String)],
  px : ParseContext,
  parse_all? : Bool = false,
) -> AttrParseResult

///|
/// Event handlers registered on an element (JS NodeEvents; data only, the
/// runtime modifier wrappers are out of scope). `id` round-trips through the
/// element's data-eid attribute.
pub(all) struct NodeEvents {
  id : Int
  handlers : Array[NodeEvent]
} derive(Debug)

///|
/// One `@on.<name>+mod+...` handler (JS NodeEvent, minus compiled modifiers).
pub(all) struct NodeEvent {
  name : String
  handler : @tutuca.HandlerParse
  modifiers : Array[String]
} derive(Debug)

// ---------------------------------------------------------------------------
// AST (port of the BaseNode class hierarchy as an enum; payload structs are
// reference types, so tree/registry aliasing matches the JS object graph)

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
} derive(Debug)

///|
pub(all) struct FragmentData {
  childs : Array[ANode]
} derive(Debug)

///|
/// `<x text=...>` / `@text` output node. node_id is None for the `@text`
/// directive's child (JS constructs it with a null nodeId, unregistered).
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
/// Iteration spec shared by `@each` and `<x render-each>` (JS IterInfo,
/// evaluation deferred to the renderer).
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
/// The template AST. One variant per JS BaseNode subclass.
pub(all) enum ANode {
  Text(TextData)
  Comment(TextData) // JS CommentNode extends TextNode: same payload/behavior
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
  /// optimize() marker: subtree is constant, render result may be cached.
  RenderOnce(RenderOnceData)
} derive(Debug)

///|
/// A constant subtree marked for render-result memoization (JS
/// RenderOnceNode). `id` is a process-global marker identity assigned at
/// optimize time; the renderer keys its cache on it (JS memoizes on the
/// node instance instead). Tests must not assert absolute ids.
pub(all) struct RenderOnceData {
  node : ANode
  id : Int
} derive(Debug)

///|
/// True for Text/Comment whose text is only spaces/tabs/newlines/CRs.
declare pub fn ANode::is_whitespace(self : ANode) -> Bool

///|
declare pub fn ANode::has_newline(self : ANode) -> Bool

///|
/// Replace a whitespace-only Text/Comment's text (whitespace condensing).
declare pub fn ANode::condense_whitespace(
  self : ANode,
  replacement? : String = "",
) -> Unit

///|
declare pub fn ANode::is_constant(self : ANode) -> Bool

///|
/// Stamp a data-* attribute on the node's rendered output carrier(s):
/// Dom → own attrs, Fragment → every child, wrappers → inner node,
/// MacroCall → recorded and replayed on the expansion; render/text nodes
/// produce no element of their own and ignore it.
declare pub fn ANode::set_data_attr(
  self : ANode,
  key : String,
  val : @tutuca.Lit,
) -> Unit

///|
/// Put `node` inside this wrapper variant (Show/Hide/PushView/Scope/Slot/Each).
/// Scope additionally stamps data-nid on the wrapped node.
declare pub fn ANode::wrap_node(self : ANode, node : ANode) -> Unit

///|
/// Recursively replace constant subtrees with RenderOnce markers (in place
/// for children; use optimize_node for the root).
declare pub fn ANode::optimize(self : ANode) -> Unit

///|
/// Collect the class names a margaui-style scanner can see (the port of JS
/// ParseCtxClassSetCollector, src/util/parsectx.js): literal `class="…"`
/// values split on whitespace, plus — for dynamic `:class` and
/// `@if.class`/`@then`/`@else` — only the literal fragments (Const values
/// and the Const parts of template strings). Call on COMPILED views so
/// macro-expanded classes are included; runtime-composed class strings are
/// invisible (JS handles those with a never-rendered decoy view).
declare pub fn ANode::collect_classes(self : ANode, into : Set[String]) -> Unit

///|
/// optimize() for a tree root: returns RenderOnce(node) when the whole node
/// is constant, else optimizes in place and returns it.
declare pub fn optimize_node(node : ANode) -> ANode

///|
/// A single child stays bare; several become a Fragment (JS maybeFragment).
declare pub fn maybe_fragment(childs : Array[ANode]) -> ANode

///|
/// Normalize insignificant whitespace between element children:
/// leading/trailing whitespace is dropped; an interior whitespace run with a
/// newline collapses to a single space, or to nothing between two block-level
/// elements. Whitespace-only Comments participate exactly like Text (JS
/// CommentNode inherits TextNode's behavior).
declare pub fn condense_childs_whites(childs : Array[ANode]) -> Array[ANode]

// ---------------------------------------------------------------------------
// Parse context (port of JS ParseContext; subclass hooks become a trait)

///|
/// Extension hooks fired during parsing (JS ParseContext method overrides).
/// Defaults: warn on parse issues, stay silent otherwise — so a live app's
/// context behaves like the JS base class and the linter overrides all three.
pub(open) trait ParseHandler {
  fn on_parse_issue(Self, ParseIssue, String?) -> Unit = _
  fn on_deprecated_syntax(Self, DeprecatedSyntax, String?) -> Unit = _
  fn on_attributes(Self, AttrParseResult, Bool, String) -> Unit = _
}

///|
impl ParseHandler with fn on_parse_issue(_self, issue, current_tag) {
  let tag = current_tag.unwrap_or("?")
  println("tutuca parse issue in <\{tag}>: \{to_repr(issue)}")
}

///|
impl ParseHandler with fn on_deprecated_syntax(_self, _syntax, _current_tag) {

}

///|
impl ParseHandler with fn on_attributes(_self, _result, _is_macro_call, _tag) {

}

///|
/// The default handler used when none is given (JS base ParseContext).
pub(all) struct WarnHandler {}

///|
pub impl ParseHandler for WarnHandler

///|
/// Per-macro-expansion state (JS px.frame).
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
  /// Created lazily on the first value-parse call (keeps value-free parsing
  /// independent of the value layer's constructor).
  mut val_ctx : @tutuca.ParseCtx?
  mut current_tag : String?
  cache_const_nodes : Bool
  handler : &ParseHandler
}

///|
/// `cache_const_nodes=false` skips the constant-subtree optimization, which
/// the ahead-of-time generator needs: RenderOnce ids are process-global
/// renderer memo keys, so they must be minted at load time, not baked in.
declare pub fn ParseContext::new(
  handler? : &ParseHandler,
  cache_const_nodes? : Bool,
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
declare pub fn ParseContext::is_inside_macro(
  self : ParseContext,
  name : String,
) -> Bool

///|
/// Allocate the next NodeEvents id (first event attr on an element).
declare pub fn ParseContext::register_events(self : ParseContext) -> NodeEvents

///|
/// Build a MacroCall from a call site's parsed attrs and children: `<x slot>`
/// children become named slots, remaining non-whitespace children fill the
/// default `_` slot (one shared array, matching the JS aliasing).
declare pub fn ParseContext::new_macro_node(
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
/// Macro lookup environment (JS scope.lookupMacro).
pub(open) trait MacroScope {
  fn lookup_macro(Self, String) -> Macro?
}

///|
/// A named template (JS View, parse side: no render). compile() parses the
/// raw view, stamps data-cid/data-vid, expands macros, and — when the context
/// allows — optimizes constant subtrees.
pub(all) struct View {
  name : String
  raw_view : String
  style : String
  mut anode : ANode?
  mut ctx : ParseContext?
  /// Built by `View::from_ir` from an ahead-of-time compiled tree: there is
  /// no source to parse, so `compile` only stamps the component id.
  ir : Bool
}

///|
/// Rebuild the compile context of an ahead-of-time compiled view: `nodes` is
/// recovered from `root`, `events` is the generator's table in registration
/// order. Call before the tree is optimized.
declare pub fn ParseContext::from_ir(
  root : ANode,
  events : Array[NodeEvents],
) -> ParseContext

///|
/// A view whose tree was compiled ahead of time (`tutuca gen-views`). Stamps
/// data-vid and runs the constant-subtree optimization; `compile` then only
/// stamps the adopting component's data-cid.
declare pub fn View::from_ir(
  name : String,
  root : ANode,
  ctx : ParseContext,
  style? : String,
) -> View

///|
declare pub fn View::new(
  name : String,
  raw_view? : String = "No View Defined",
  style? : String = "",
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
/// Parse a template string into an AST (JS ANode.parse): empty input yields
/// Comment("Empty View in ANode.parse"); a single root parses directly;
/// several roots are whitespace-condensed into a fragment. None only when a
/// single root is an `<x>` op whose value failed to parse (JS returns null).
declare pub fn ANode::parse(html : String, px : ParseContext) -> ANode?
