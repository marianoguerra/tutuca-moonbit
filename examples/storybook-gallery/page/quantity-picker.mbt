///|
pub fn quantity_picker_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="quantity-picker",
    components=[quantity_picker_component(initial=QuantityPickerState::fresh())],
    examples=[
      {
        component: "QuantityPicker",
        title: "Quantity picker",
        args: Map([]),
        view: None,
      },
      {
        component: "QuantityPicker",
        title: "Maximum quantity",
        args: quantity_picker_init_args("maximum").unwrap(),
        view: None,
      },
    ],
  )
}
