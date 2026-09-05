///|
/// A component from a real kit, converted, compiled, and asked what it is.
///
/// `Hole` is the universal holder from `demo/universal/std` — the one every
/// cell contains and every placed component sits in. It is here rather than a
/// written-for-the-test card because its ids are frozen public API with a
/// second host on the other end, and because it turns on the four constructs
/// nobody had RUN: a protocol declaration, a qualified handler whose whole
/// body is a null write, a computed role id carrying `::` and `@` through a
/// notation where both mean something, and a `+` that asks rather than acts.
test "the universal holder converts, compiles, and keeps its vocabulary" {
  let card =
    #|spec:
    #|  /// A thing that holds one component, or nothing.
    #|  protocol Holder = "tutuca.dev/universal/Holder@1":
    #|    message hold(Any)
    #|    message empty
    #|    express intent addRequested(Bool)
    #|    property filled :: Bool
    #|
    #|  /// A component that can draw its own settings.
    #|  protocol Editable = "tutuca.dev/universal/Editable@1":
    #|    view editor
    #|
    #|  /// The universal holder: what a `+` is, and what every cell contains.
    #|  Hole ~root:
    #|    implements Holder
    #|    implements Editable
    #|    /// What this holds, or nothing, which is what draws the `+`.
    #|    field child :: Any
    #|    /// Whether what it holds draws its own settings.
    #|    field editable :: Bool
    #|    /// Whether this ONE cell is showing its child's settings.
    #|    field configuring :: Bool
    #|    property filled :: Bool ~public
    #|    property Holder::filled = filled
    #|    view Editable::editor = chrome
    #|    message Holder::hold(Any)
    #|    message Holder::empty
    #|    express intent Holder::addRequested(Bool)
    #|
    #|logic:
    #|  Hole:
    #|    /// Whether something is here, which is also what decides the `+`.
    #|    property filled :: Bool:
    #|      get: it.child != none
    #|
    #|    /// Hold this. The page builds the instance and hands it over.
    #|    receive Holder::hold(inst):
    #|      it.child := inst
    #|      it.editable := false
    #|
    #|    /// Empty it again, which gives the `+` back rather than deleting.
    #|    receive Holder::empty:
    #|      it.child := none
    #|      it.editable := false
    #|
    #|    /// The `+` was clicked. It ASKS rather than placing anything.
    #|    receive add(ctrl :: Bool):
    #|      ask("Holder::addRequested", ctrl)
    #|
    #|    receive toggle_config:
    #|      it.configuring := !it.configuring
    #|
    #|    /// What the child is drawn under. Empty means "whatever is pushed
    #|    /// from above", so a cell follows the page without being told.
    #|    compute child_view():
    #|      if it.configuring
    #|      | "tutuca.dev/universal/Editable@1::editor"
    #|      | ""
    #|
    #|view:
    #|  Hole:
    #|    @div(~class: "tut-hole flex items-center justify-center w-full"){
    #|      @render(it.child)
    #|    }
    #|
    #|  Hole.chrome:
    #|    @div(~class: "tut-chrome"){
    #|      @button(~class: "tut-x", ~on_click: toggle_config){x}
    #|      @show(it.filled){
    #|        @div(~push_view: child_view()){@render(it.child)}
    #|      }
    #|    }
  let out = @emit.compile(card, name="std")
  assert_eq(out.component, "Hole")
  assert_eq(out.fields, ["child", "editable", "configuring"])
  // every handler compiled: a refusal here is behaviour that would be missing
  // from a component that still renders
  assert_eq(out.refusals.map(r => r.name), [])
  assert_true(out.wasm.length() > 100, msg="\{out.wasm.length()} bytes")
}
