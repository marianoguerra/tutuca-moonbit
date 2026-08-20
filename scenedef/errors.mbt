// What a bad test block says out loud.
//
// Every one of these names the scene and, where there is one, the step — a
// block is a list, and a sentence with no position in it is one an author has
// to go looking for the meaning of. `at` is 0-based because that is what the
// block is indexed by, and the message says "step 3" meaning `steps[3]`.

///|
pub fn SceneError::message(self : SceneError) -> String {
  match self {
    NotJson(m) => "test block: not valid JSON (\{m})"
    NotScenes =>
      "test block: expected an object of named scenes, e.g. { \"it counts\": { \"steps\": [] } }"
    SceneNotObject(n) =>
      "test block: scene `\{n}` is not an object — a scene is { \"steps\": [ … ] }"
    NoSteps(n) =>
      "test block: scene `\{n}` declares no `steps`; a scene that drives nothing has nothing to say"
    StepNotObject(scene~, at~) => at_(scene, at) + "is not an object"
    NoVerb(scene~, at~, suggestion~) =>
      at_(scene, at) +
      "names no verb — a step is one of `click`, `type`, `key`, `check`, `fire`, `drag`, `send` or `expect`" +
      (match suggestion {
        Some(s) => ", so did you mean `\{s}`?"
        None => ""
      })
    TwoVerbs(scene~, at~, first~, second~) =>
      at_(scene, at) +
      "names both `\{first}` and `\{second}`; a step is one verb, and an object's keys have no order to decide which happens first"
    MissingKey(scene~, at~, verb~, key~) =>
      at_(scene, at) + "`\{verb}` needs a `\{key}`"
    BadType(scene~, at~, key~, want~, got~) =>
      at_(scene, at) + "`\{key}` should be \{want}, but this is \{got}"
    NoSuchReader(scene~, at~, reader~, suggestion~) =>
      at_(scene, at) +
      "nothing reads `\{reader}`" +
      (match suggestion {
        Some(s) => " — did you mean `\{s}`?"
        None =>
          "; the readers are text, texts, attr, prop, value, checked, count, state, html, renders and refused"
      })
    BadSelector(scene~, at~, sel~, why~) =>
      at_(scene, at) + "`\{sel}` is not a selector this can mean: \{why}"
    BadPlace(scene~, at~, place~, why~) =>
      at_(scene, at) + "`\{place}` is not a place: \{why}"
    NotContainable(scene~, at~, reader~) =>
      at_(scene, at) +
      "`contains` reads a string, and `\{reader}` does not answer one — say `is` and mean it exactly"
    BadIntent(scene~, name~, why~) =>
      "test block: scene `\{scene}`'s intent `\{name}`: \{why}"
  }
}

///|
/// The position prefix every step-level message opens with.
///
/// `at == -1` is a fact about the scene rather than about a step — `args` and
/// `intents` are read before the list is — and then the step half is left off
/// rather than printed as a position that does not exist.
fn at_(scene : String, at : Int) -> String {
  if at < 0 {
    "test block: scene `\{scene}`: "
  } else {
    "test block: scene `\{scene}`, step \{at}: "
  }
}

///|
pub impl Show for SceneError with fn output(self, logger) {
  logger.write_string(self.message())
}
