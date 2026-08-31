///|
test "protocols resolve by canonical id and validate a complete implementation" {
  let defs = @statedef.parse_state(
    (
      #|protocol Lifecycle = "tutuca.dev/std/Lifecycle@1" {
      #|  handle { message { init, deinit } intent { resume, suspend } }
      #|  express { message { didInit } intent { requestResume } }
      #|  property { active: Bool }
      #|  view { display }
      #|  provide { lifecycleState: String }
      #|  lookup { clock: Int }
      #|}
      #|state Screen implements Lifecycle {
      #|  active: Bool
      #|  provide { Lifecycle::lifecycleState = .active }
      #|  lookup { Lifecycle::clock = 0 }
      #|  property {
      #|    active: Bool { get .active }
      #|    Lifecycle::active = active
      #|  }
      #|  view { Lifecycle::display = main }
      #|}
      #|handle Screen {
      #|  message { Lifecycle::init, Lifecycle::deinit }
      #|  intent { Lifecycle::resume, Lifecycle::suspend }
      #|}
      #|express Screen {
      #|  message { Lifecycle::didInit }
      #|  intent { Lifecycle::requestResume }
      #|}
    ),
  )
  let def = defs[0]
  assert_eq(def.implements, ["tutuca.dev/std/Lifecycle@1"])
  assert_eq(def.protocols[0].views, ["display"])
  assert_eq(def.property_bindings[0].protocol_id, "tutuca.dev/std/Lifecycle@1")
  let validation = @statedef.validate_protocols(defs)
  assert_true(validation.mode is Strict)
  assert_eq(validation.diagnostics.length(), 0)
}

///|
test "properties distinguish public operations from backing fields" {
  let def = @statedef.parse_state(
      (
        #|protocol Adjustable = "example/Adjustable@1" {
        #|  property { value: Int set, label: String }
        #|}
        #|state Dial implements Adjustable {
        #|  raw: Int
        #|  text: String
        #|  dirty: Bool
        #|  property {
        #|    pub value: Int { get .raw set .raw }
        #|    label: String { get .text }
        #|    percentage: Int { get set }
        #|    Adjustable::value = value
        #|    Adjustable::label = label
        #|  }
        #|}
      ),
    )[0]
  assert_eq(def.properties.length(), 3)
  assert_true(def.properties[0].writable)
  assert_true(def.properties[0].public_)
  assert_false(def.properties[1].public_)
  assert_eq(def.properties[0].getter, Some(".raw"))
  assert_eq(def.properties[0].setter, Some(".raw"))
  assert_true(def.properties[2].getter is None)
  assert_true(def.properties[2].setter is None)
  assert_true(def.protocols[0].properties[0].writable)
  let validation = @statedef.validate_protocols([def])
  assert_true(validation.mode is Strict)
  assert_eq(validation.diagnostics.length(), 0)
}

///|
test "an imported protocol keeps compilation gradual until its declaration is present" {
  let defs = @statedef.parse_state(
    (
      #|import protocol "example/ListItem@1" as ListItem
      #|state Row implements ListItem { label: String }
    ),
  )
  let validation = @statedef.validate_protocols(defs)
  assert_true(validation.mode is Gradual)
  assert_eq(validation.diagnostics.length(), 1)
  assert_true(validation.diagnostics[0].code is ProtocolUnresolved)
  assert_false(validation.diagnostics[0].error)
}

///|
test "protocol-qualified component slots retain every constraint id" {
  let def = @statedef.parse_state(
      (
        #|import protocol "example/ListItem@1" as ListItem
        #|import protocol "example/Editable@2" as Editable
        #|state List { rows: Array[Component[protocol ListItem & Editable]] }
      ),
    )[0]
  assert_true(
    def.fields[0].ty
    is TList(TCompProtocols(["example/ListItem@1", "example/Editable@2"])),
  )
}

///|
test "raw receive and intent declarations have no compatibility path" {
  for word in ["receive", "intent"] {
    let failed = try {
      @statedef.parse_state("state X {}\n\{word} { old }") |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(failed)
  }
}
