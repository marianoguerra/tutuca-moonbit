// The report, as the JSON a page or a build step reads.
//
// Every scene carries its HTML, its state, its styles and its trace WHETHER OR
// NOT it asserted anything, and that is what makes the block worth writing
// before you know the answers: a scene with no `expect` is a drive, and this
// is what you look at afterwards.

///|
pub fn report_json(results : Array[SceneResult]) -> Json {
  let scenes : Map[String, Json] = Map([])
  let mut ok = true
  let mut ran = 0
  let mut failed = 0
  for r in results {
    if !r.ok {
      ok = false
      failed = failed + 1
    }
    ran = ran + 1
    scenes[r.name] = scene_json(r)
  }
  Json::object({
    "ok": Json::boolean(ok),
    "ran": Json::number(ran.to_double()),
    "failed": Json::number(failed.to_double()),
    "scenes": Json::object(scenes),
  })
}

///|
fn scene_json(r : SceneResult) -> Json {
  let m : Map[String, Json] = {
    "ok": Json::boolean(r.ok),
    "component": Json::string(r.component),
    "html": Json::string(r.html),
    "state": r.state.to_json(),
    "styles": Json::string(r.styles),
    "activity": Json::array(r.activity),
    "refusals": Json::array(r.refusals.map(Json::string)),
    "log": Json::array(r.log.map(Json::string)),
    "steps": Json::array(r.steps.map(step_json)),
  }
  // Only when there is one: a scene that ran has no error, and an empty string
  // beside every scene is a key a reader has to learn to ignore.
  if r.error != "" {
    m["error"] = Json::string(r.error)
  }
  Json::object(m)
}

///|
fn step_json(s : StepResult) -> Json {
  let m : Map[String, Json] = {
    "at": Json::number(s.at.to_double()),
    "ok": Json::boolean(s.ok),
  }
  match s.got {
    Some(v) => m["got"] = v.to_json()
    None => ()
  }
  match s.want {
    Some(v) => m["want"] = v.to_json()
    None => ()
  }
  if s.why != "" {
    m["why"] = Json::string(s.why)
  }
  m |> Json::object
}
