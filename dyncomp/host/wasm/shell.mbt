///| A reusable host shell for dynamic bundles: a load button, a status
/// line, and slots for a Counter and a Pair from the loaded module. Used
/// by demo/dyncomp_wasm as the whole app and by demo/storybook_wasm as a
/// story pane — load completion routes back here via ctx.path(), so the
/// shell works mounted anywhere in a tree.
///
/// Reloading an already-loaded module hot-swaps it: the counter's state
/// migrates into the fresh bundle through its JSON projection.

///|
pub fn shell_module(bundle_url~ : String) -> @component.ModuleDef {
  let shell = @component.component(
    name="DynShell",
    view=(
      #|<div class="dyncomp-demo">
      #|  <button class="load" @on.click="load">load counter bundle</button>
      #|  <p class="status" @text=".status"></p>
      #|  <div class="slot-box"><x render=".slot"></div>
      #|  <ul class="seq"><li @each=".slot" @text="@value"></li></ul>
      #|  <div class="pair-box"><x render=".pair"></div>
      #|</div>
    ),
    style=(
      #|.dyncomp-demo { font-family: sans-serif; max-width: 30rem; }
      #|.dyncomp-demo .status { color: #666; min-height: 1.2em; }
      #|.dyncomp-demo .slot-box { margin-top: 1rem; }
      #|.dyncomp-demo .seq { display: inline-flex; gap: 0.3em; list-style: none; padding: 0; color: #669; }
    ),
    fields={
      "status": @component.FieldSpec::of_default(Str("no bundle loaded")),
      "slot": @component.FieldSpec::of_default(Null),
      "pair": @component.FieldSpec::of_default(Null),
    },
    input={
      "load": (inst, _args, ctx) => {
        let _ = load_from(ctx.path(), bundle_url)
        Some(inst.set("status", Str("loading \{bundle_url} ...")))
      },
    },
    receive={
      "dyncompLoaded": (inst, args, _ctx) => {
        let module_name = match args {
          [Str(s)] => s
          _ => return Some(inst.set("status", Str("loaded: bad args")))
        }
        // hot-swap: migrate the mounted counter's state into the fresh
        // bundle instead of resetting it
        let (counter, migrated) = match inst.get("slot") {
          Obj(_) as old => (migrate_instance(module_name, "Counter", old), true)
          _ =>
            (
              make_instance(module_name, "Counter", args={ "count": Num(5) }),
              false,
            )
        }
        let pair = make_instance(module_name, "Pair")
        match (counter, pair) {
          (Some(c), Some(p)) => {
            let status = if migrated {
              "reloaded \{module_name}: counter state migrated"
            } else {
              "loaded \{module_name}: Counter + Pair mounted"
            }
            Some(inst.set("slot", c).set("pair", p).set("status", Str(status)))
          }
          _ =>
            Some(inst.set("status", Str("\{module_name}: missing components")))
        }
      },
      "dyncompError": (inst, args, _ctx) => {
        let msg = match args {
          [Str(s)] => s
          _ => "unknown error"
        }
        Some(inst.set("status", Str("load failed: \{msg}")))
      },
    },
  )
  @component.ModuleDef::new(name="dyncompshell", components=[shell])
}

///|
/// The request handlers the shell's guests use; register into the host
/// app's scope at mount.
pub fn shell_request_handlers() -> Map[String, @component.RequestFn] {
  {
    "double": RequestFn((args, respond) => {
      match args {
        [Num(n)] => respond(Ok(Num(n * 2.0)))
        _ => respond(Err(Str("double: expected one number")))
      }
    }),
  }
}
