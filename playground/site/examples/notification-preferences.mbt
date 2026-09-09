fn build() -> @component.ModuleDef {
  notification_preferences_module()
}

///|
pub fn notification_preferences_module() -> @component.ModuleDef {
  @component.ModuleDef::new(
    name="notification-preferences",
    components=[
      notification_preferences_component(
        initial=NotificationPreferencesState::fresh(),
      ),
    ],
    examples=[
      {
        component: "NotificationPreferences",
        title: "Notification preferences",
        args: Map([]),
        view: None,
      },
      {
        component: "NotificationPreferences",
        title: "Email enabled",
        args: notification_preferences_init_args("email enabled").unwrap(),
        view: None,
      },
    ],
  )
}
