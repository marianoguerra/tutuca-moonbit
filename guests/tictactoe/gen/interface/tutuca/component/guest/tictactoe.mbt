///| HANDWRITTEN (not wit-bindgen output, unlike the sibling ffi/top files —
/// regeneration must not touch it; see ../../../../../README.md).
///
/// Tic-tac-toe. What it is here to show is a guest owning a COLLECTION the
/// host iterates: the board is a declared list, the view walks it with `@each`,
/// and each square dispatches back with its own index. The counter shows a
/// scalar and the calculator shows a private half; this shows the shape a host
/// can loop over.
///
/// Everything else about the game is derived. Whose turn it is, whether
/// somebody has won, and which line they won on are all functions of the board,
/// so none of them is stored — a stored turn is a second answer to a question
/// the board already answers, and the two can disagree.

///|
/// The board, and nothing else.
///
/// Nine squares, each `""`, `"X"` or `"O"`. The winner is not here and the
/// turn is not here, on purpose: both are computable, and state that can be
/// computed is state that can be WRONG.
priv struct Game {
  squares : Array[String]
}

///|
fn Game::empty() -> Game {
  { squares: Array::make(9, "") }
}

///|
/// The three-in-a-rows, as index triples. Eight of them, written out rather
/// than generated: the list is short, fixed, and read by two functions that
/// both want it exactly like this.
fn lines() -> Array[Array[Int]] {
  [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8], // rows
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8], // columns
    [0, 4, 8],
    [2, 4, 6], // diagonals
  ]
}

///|
/// Who has won, and on which line. `("", [])` for a game still going or drawn.
fn Game::winner(self : Game) -> (String, Array[Int]) {
  for line in lines() {
    let a = self.squares[line[0]]
    if a != "" && self.squares[line[1]] == a && self.squares[line[2]] == a {
      return (a, line)
    }
  }
  ("", [])
}

///|
/// How many squares are taken. X plays on the even counts, so this is also
/// whose turn it is.
fn Game::taken(self : Game) -> Int {
  let mut n = 0
  for s in self.squares {
    if s != "" {
      n = n + 1
    }
  }
  n
}

///|
/// Whose turn it is. X goes first, so an even number of moves means X.
fn Game::turn(self : Game) -> String {
  if self.taken() % 2 == 0 {
    "X"
  } else {
    "O"
  }
}

///|
fn Game::over(self : Game) -> Bool {
  self.winner().0 != "" || self.taken() == 9
}

///|
/// The board after playing `at`, or None when that is not a move: an occupied
/// square, an index off the board, or a game that is already finished.
///
/// Refusing rather than ignoring is what keeps the board the only state: a
/// move that half-happened would need something else to remember that it did.
fn Game::play(self : Game, at : Int) -> Game? {
  if at < 0 || at >= 9 {
    return None
  }
  if self.squares[at] != "" || self.over() {
    return None
  }
  let squares = self.squares.copy()
  squares[at] = self.turn()
  Some({ squares, })
}

// --- the contract -----------------------------------------------------------

///|
/// The declared `squares` field, as the view iterates it.
///
/// Each square is a MAP rather than a string, and `win` rides with it rather
/// than being asked for in the view, because `@each` takes a FIELD and not a
/// method: a method result has no addressable path, so nothing could be
/// dispatched against it and no conditional could read it. (The same reason
/// the Rust guest's tabs carry `active`.)
///
/// `win` is DERIVED on every read — the board said a second way — so the two
/// cannot drift, and a write that carries a stale one is simply ignored.
impl DynComponent for Game with fn get_field(self, name) {
  match name {
    "squares" => {
      let (_, line) = self.winner()
      let h = @values.list_new()
      for i, s in self.squares {
        let m = @values.map_new()
        @values.map_set(m, "mark", @values.Value::Text(s))
        @values.map_set(m, "win", @values.Value::Boolean(line.contains(i)))
        @values.list_push(h, @values.Value::Map(m))
      }
      Some(@values.Value::List(h))
    }
    _ => None
  }
}

///|
impl DynComponent for Game with fn handle(self, bucket, name, args) {
  guard bucket is INPUT else { return None }
  match name {
    // The loop `@key` a per-square handler carries. It arrives as a number
    // because a list's key is its index.
    "play" =>
      match args {
        [@values.Value::Number(n), ..] =>
          match self.play(n.to_int()) {
            Some(next) => Some(next as &DynComponent)
            // Not a move. Answering None leaves the board alone, which is what
            // clicking a taken square should do.
            None => None
          }
        _ => None
      }
    "reset" => Some(Game::empty() as &DynComponent)
    _ => None
  }
}

///|
impl DynComponent for Game with fn call_method(self, name, _args) {
  match name {
    // The one line above the board: whose turn, who won, or nobody.
    "status" => {
      let (who, _) = self.winner()
      if who != "" {
        return @values.Value::Text("\{who} wins")
      }
      if self.taken() == 9 {
        return @values.Value::Text("a draw")
      }
      @values.Value::Text("\{self.turn()} to play")
    }
    _ => @values.Value::Nil
  }
}

///|
impl DynComponent for Game with fn with_field(_self, name, v) {
  match (name, v) {
    // A host writing the board — the generated `setSquares`, or a restore from
    // the declared fields. Whatever arrives is normalized to nine squares of
    // `X` / `O` / blank, because the board is the ONLY state and a malformed
    // one would make every derived answer nonsense.
    ("squares", @values.Value::List(h)) => {
      let squares = Array::make(9, "")
      let len = @values.list_len(h)
      for i in 0U..<len {
        if i >= 9 {
          break
        }
        // Both spellings arrive here: the map the view iterates (which is what
        // a host writing back what it read hands over), and the bare mark a
        // person or a tool would type into a generated form.
        let mark = match @values.list_get(h, i) {
          @values.Value::Text(s) => s
          @values.Value::Map(m) =>
            match @values.map_get(m, "mark") {
              Some(@values.Value::Text(s)) => s
              _ => ""
            }
          _ => ""
        }
        if mark == "X" || mark == "O" {
          squares[i.reinterpret_as_int()] = mark
        }
      }
      Some(({ squares, } : Game) as &DynComponent)
    }
    _ => None
  }
}

///|
/// A board out of construction arguments. Everything is derived from it, so
/// this is the whole constructor — and it goes through `with_field`'s
/// normalization for the same reason it exists.
fn make_game(args : Array[(String, @values.Value)]) -> &DynComponent {
  let start = Game::empty()
  for arg in args {
    let (name, v) = arg
    if name == "squares" {
      match (start as &DynComponent).with_field("squares", v) {
        Some(g) => return g
        None => ()
      }
    }
  }
  start as &DynComponent
}

// --- the view ---------------------------------------------------------------

///|
/// The board is a `@each` over the DECLARED list, so the host does the looping
/// and each square dispatches with its own `@key`. The winning line is read off
/// `@value.win` rather than asked for per square: a `$method` takes no
/// arguments in a conditional slot, and one that did would silently render
/// nothing at all.
///
/// The status sits UNDER the board, beside the reset. The card is given a
/// width because the row below the board is `justify-between`: without one the
/// card shrinks to the board, and two items that do not fit get pulled apart
/// until the text wraps one letter per line.
fn game_view() -> String {
  (
    #|<div class="card card-border bg-base-100 border-base-300 shadow-sm w-64 tictactoe">
    #|  <div class="card-body gap-3 p-4 items-center">
    #|    <div class="grid grid-cols-3 gap-1.5 board">
    #|      <button @each=".squares" @on.click="play @key"
    #|              @if.class="@value.win"
    #|              @then="'btn btn-success size-16 text-3xl font-bold square'"
    #|              @else="'btn btn-soft size-16 text-3xl font-bold square'"
    #|              @text="@value.mark"></button>
    #|    </div>
    #|    <div class="flex items-center justify-between gap-3 w-full">
    #|      <span class="text-sm font-medium opacity-70 whitespace-nowrap status" @text="$status"></span>
    #|      <button class="btn btn-xs btn-ghost reset" @on.click="reset">new game</button>
    #|    </div>
    #|  </div>
    #|</div>
  )
}

///|
fn game_def() -> ComponentDef {
  component_def(
    "TicTacToe",
    doc="Noughts and crosses on a three-by-three board, for two people sharing a screen.",
    keywords=[
      "game", "tictactoe", "noughts", "crosses", "board", "two-player", "play",
    ],
    category="game",
    message_docs=[
      { name: "play", doc: "Take the square at an index." },
      { name: "reset", doc: "Clear the board and start again." },
      { name: "status", doc: "Whose turn it is, or who won." },
    ],
    views=[{ name: "main", html: game_view() }],
    // ONE declared field, and everything else is a function of it. A stored
    // turn or a stored winner would be a second answer to a question the board
    // already answers, and two answers can disagree.
    types=[
      { kind: TY_TEXT, elem: None, items: [], name: "", members: [] },
      { kind: TY_RECORD, elem: None, items: [], name: "square", members: [] },
      { kind: TY_LIST, elem: Some(1), items: [], name: "", members: [] },
    ],
    fields=[
      field(
        "squares",
        2,
        doc="The nine squares, left to right and top to bottom: each a mark (\"X\", \"O\" or blank) and whether it is part of the winning line.",
        constraint=Some({ ..no_limits(), min_len: Some(9), max_len: Some(9) }),
      ),
    ],
    handlers=["play", "reset"],
    receives=["init"],
    methods=["status"],
    inits=[
      {
        name: "nearly-won",
        args_json: "{\"squares\": [\"X\", \"X\", \"\", \"O\", \"O\", \"\", \"\", \"\", \"\"]}",
        doc: "One move from a win, for looking at the winning line.",
      },
    ],
  )
}

///|
fn dyn_module() -> DynModule {
  module_def(
    "gameslib",
    // No `persist`: the board IS the declared field, so the host projects it
    // and constructs from it, and a `persist` here would be that one list
    // written a second time. That is the other half of the persistence
    // contract, and saying nothing is the right way to say it.
    [dyn_comp(game_def(), make_game)],
    doc="Small games, as loadable components.",
    version="0.4.0",
    // It asks for nothing — not even randomness: X always goes first, and both
    // players are at the same screen.
    capabilities=[],
  )
}
