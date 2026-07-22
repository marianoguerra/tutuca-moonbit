// Minimal embedding shell: argv -> plan_with_module -> stdout/stderr/exit.
// (The full-featured shell with feedback/stdin lives in cmd/main.)

///|
extern "c" fn process_exit(code : Int) = "exit"

///|
fn put(s : String) -> Unit {
  // println is the only stdout primitive here; drop one trailing newline
  if s.has_suffix("\n") {
    println(s[0:s.length() - 1].to_owned())
  } else {
    println(s)
  }
}

///|
fn main {
  let argv = @env.args().iter().drop(1).to_array()
  match @cli.plan_with_module(argv, Some(@counterlib.module_def())) {
    Done(emit) => {
      if emit.out != "" {
        put(emit.out)
      }
      if emit.err != "" {
        put(emit.err)
      }
      process_exit(emit.exit_code)
    }
    Feedback(_, ..) => {
      println("feedback is not supported by this demo binary")
      process_exit(1)
    }
    InstallSkill(_, ..) => {
      println("install-skill is not supported by this demo binary")
      process_exit(1)
    }
    ServeStorybook(_, ..) => {
      println("storybook is not supported by this demo binary")
      process_exit(1)
    }
    GenViews(_, ..) => {
      println("gen-views is not supported by this demo binary")
      process_exit(1)
    }
    Watch(_, ..) => {
      println("watch is not supported by this demo binary")
      process_exit(1)
    }
  }
}
