// Shell half of `tutuca storybook`: resolve a pre-built gallery bundle, then
// either copy it (--out) or serve it over HTTP. The pure @cli package decides
// the flags (storybook.mbt); this file does the filesystem + socket I/O only.
//
// A bundle is whatever a build script wrote: an index.html and a wasm module
// beside it. This repo's own is assembled into dist/storybook by
// `moon run --target native cmd/dev -- dist`; a downstream project's is
// whatever `build.mjs` produced (`tutuca new-storybook`). The server knows
// nothing about either — it is a static file server with a sanity check.

///|
/// Candidate bundle locations when no `dir` is passed, in priority order:
/// the cwd-relative "storybook" (running from inside dist/) and "dist/storybook"
/// (running from the repo root).
let bundle_candidates : Array[String] = ["storybook", "dist/storybook"]

///|
/// True when `dir` looks like a built gallery bundle: an `index.html` with at
/// least one `.wasm` module beside it.
///
/// Two markers rather than one filename. The old check was for
/// `storybook_wasm.wasm` — the name THIS repo's demo host happens to compile
/// to — which meant a downstream bundle, whose module is named after its own
/// page package, could not be served by the command written for it. Checking
/// markers rather than the bare directory still keeps the source `storybook/`
/// package dir from matching when serving from the repo root: it has neither.
async fn is_bundle(dir : String) -> Bool noraise {
  let has_index = @fs.exists("\{dir}/index.html") catch { _ => false }
  if !has_index {
    return false
  }
  let names = @fs.readdir(dir) catch { _ => return false }
  for n in names {
    if n.has_suffix(".wasm") {
      return true
    }
  }
  false
}

///|
/// Resolve the bundle directory: an explicit `dir` (must be a bundle), else the
/// first candidate that is one. None means "not found".
async fn resolve_bundle(dir : String) -> String? noraise {
  if dir != "" {
    return if is_bundle(dir) { Some(dir) } else { None }
  }
  for cand in bundle_candidates {
    if is_bundle(cand) {
      return Some(cand)
    }
  }
  None
}

///|
/// Content type for a bundle file by extension. Keeps .wasm and .mjs correct so
/// the module + streaming instantiation work.
fn content_type_of(path : String) -> String {
  if path.has_suffix(".html") {
    "text/html; charset=utf-8"
  } else if path.has_suffix(".mjs") || path.has_suffix(".js") {
    "text/javascript; charset=utf-8"
  } else if path.has_suffix(".wasm") {
    "application/wasm"
  } else if path.has_suffix(".css") {
    "text/css; charset=utf-8"
  } else if path.has_suffix(".json") {
    "application/json"
  } else if path.has_suffix(".svg") {
    "image/svg+xml"
  } else {
    "application/octet-stream"
  }
}

///|
/// The path portion before any query string.
fn strip_query(path : String) -> String {
  let sb = StringBuilder()
  for ch in path {
    if ch == '?' {
      break
    }
    sb.write_char(ch)
  }
  sb.to_string()
}

///|
async fn serve_file(conn : @http.ServerConnection, full_path : String) -> Unit {
  let file = @fs.open(full_path, mode=ReadOnly)
  defer file.close()
  conn
  ..send_response(200, "OK", extra_headers={
    "Content-Type": content_type_of(full_path),
    "Content-Length": file.size().to_string(),
  })
  ..write_reader(file)
  .end_response()
}

///|
async fn serve_404(conn : @http.ServerConnection) -> Unit {
  conn
  ..send_response(404, "Not Found", extra_headers={
    "Content-Type": "text/html",
  })
  ..write_string("<!doctype html><title>404</title><h1>Not Found</h1>")
  .end_response()
}

///|
/// Route one request to a file under `base`, or a 404.
async fn respond(
  base : String,
  request : @http.Request,
  conn : @http.ServerConnection,
) -> Unit {
  guard request.meth is Get else { return }
  let rel0 = strip_query(request.path)
  let rel = if rel0 == "/" || rel0 == "" { "/index.html" } else { rel0 }
  let full = base + rel
  if is_regular_file(full) {
    serve_file(conn, full)
  } else {
    serve_404(conn)
  }
}

///|
/// True when `path` exists and is a regular file. Any fs error (missing path,
/// permission) is treated as "not a servable file" so the request 404s rather
/// than 500s.
async fn is_regular_file(path : String) -> Bool noraise {
  (@fs.exists(path) && !(@fs.kind(path) is Directory)) catch {
    _ => false
  }
}

///|
/// Best-effort 500 so a handler failure surfaces instead of an empty reply.
async fn serve_error(
  conn : @http.ServerConnection,
  msg : String,
) -> Unit noraise {
  conn.send_response(500, "Internal Server Error", extra_headers={
    "Content-Type": "text/plain; charset=utf-8",
  }) catch {
    _ => return
  }
  conn.write_string("storybook serve error: \{msg}\n") catch {
    _ => return
  }
  conn.end_response() catch {
    _ => return
  }
}

///|
/// Bind a server on 127.0.0.1:port, falling back to an OS-chosen free port when
/// the requested one is taken.
async fn bind_server(port : Int) -> @http.Server {
  Server(@socket.Addr::parse("127.0.0.1:\{port}")) catch {
    _ => Server(@socket.Addr::parse("127.0.0.1:0"))
  }
}

///|
/// Recursively copy the bundle directory `base` into `target`.
async fn copy_tree(base : String, target : String) -> Unit {
  if !@fs.exists(target) {
    @fs.mkdir(target, recursive=true)
  }
  let dir = @fs.opendir(base)
  defer dir.close()
  for name in dir.read_all() {
    let src = "\{base}/\{name}"
    let dst = "\{target}/\{name}"
    if @fs.kind(src) is Directory {
      copy_tree(src, dst)
    } else {
      @fs.write_file(dst, @fs.read_file(src), create_mode=CreateOrTruncate)
    }
  }
}

///|
/// Serve or copy the storybook bundle.
async fn run_serve_storybook(
  opts : @cli.GlobalOpts,
  dir : String,
  port : Int,
  out : String?,
) -> Unit noraise {
  let base = match resolve_bundle(dir) {
    Some(b) => b
    None => {
      let where_ = if dir != "" { "'\{dir}'" } else { "dist/storybook" }
      emit_and_exit(
        @cli.error_emit(
          opts,
          @cli.err(
            @cli.CODE_INTERNAL,
            "no storybook bundle found at \{where_}",
            hint="a bundle is a directory with an index.html and a .wasm beside it; build one with your project's build script (`tutuca new-storybook` writes one), or in this repo with `moon run --target native cmd/dev -- dist`",
          ),
        ),
      )
      return
    }
  }
  match out {
    Some(target) => {
      copy_tree(base, target) catch {
        e =>
          emit_and_exit(
            @cli.error_emit(
              opts,
              @cli.err(@cli.CODE_INTERNAL, "failed to copy bundle: \{e}"),
            ),
          )
      }
      emit_and_exit({
        out: "Copied storybook bundle to \{target}\n",
        err: "",
        exit_code: 0,
      })
    }
    None =>
      try {
        let server = bind_server(port) catch {
          e => {
            emit_and_exit(
              @cli.error_emit(
                opts,
                @cli.err(@cli.CODE_INTERNAL, "failed to start server: \{e}"),
              ),
            )
            return
          }
        }
        println("tutuca storybook serving \{base} at http://\{server.addr}/")
        println(
          "open it in a browser with JS String Builtins (e.g. Chrome); Ctrl-C to stop",
        )
        server.run_forever((request, _body, conn) => {
          respond(base, request, conn) catch {
            e => serve_error(conn, "\{e}")
          }
        })
      } catch {
        e => println("storybook server stopped: \{e}")
      }
  }
}
