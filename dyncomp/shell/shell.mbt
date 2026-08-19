///| The floor under a wasm-gc page that hosts bundles.
///
/// Three things, and each was two copies before: building a live guest instance,
/// keeping the utility CSS in step with the views a bundle just brought, and the
/// bar a bundle arrives through. Each host still writes its own `mount` and
/// re-exports its own entry points — a page should depend on ONE package and get
/// everything, so those one-line forwards stay where a page can reach them.

// --- building an instance ---------------------------------------------------

///|
/// Build a guest instance the way a page places one.
///
/// A named configuration goes through `make_init` and everything else through
/// the bare constructor with whatever arguments were validated. Standard
/// components never reach here — they are compiled in, and a host builds them
/// directly.
///
/// This is the `MakeInstance` both `dyncomp/ui` and `dyncomp/storybook` ask a
/// host for, and it is one function rather than two so that a card in a gallery
/// shows exactly what the editor would have placed.
pub fn make_instance(
  ref_ : @registry.ComponentRef,
  init : String,
  args : Map[String, @tutuca.Value],
) -> @tutuca.Value? {
  if init == "" {
    @dhw.make_instance(ref_.module_, ref_.name, args~)
  } else {
    @dhw.make_init(ref_.module_, ref_.name, init)
  }
}

// --- margaui class publishing -----------------------------------------------

///|
/// The mounted app whose classes get compiled. One live app per wasm instance is
/// the premise the exported entry points already rest on, so this is a module
/// ref rather than something a caller threads through.
let live_app : Ref[@app.App[@wdom.WasmNode]?] = { val: None }

///|
/// Tell this package which app to compile classes from. A host calls it once,
/// at mount, before the first `refresh_margaui`.
pub fn set_live_app(app : @app.App[@wdom.WasmNode]) -> Unit {
  live_app.val = Some(app)
}

///|
/// Compile the page's utility-class set to CSS in MoonBit (via the
/// `marianoguerra/tailwindcss` port) and inject it as `<style id="margaui-css">`.
///
/// Called at mount and again after every bundle load, because a bundle brings
/// its own views and therefore its own utility classes. Skipping the second call
/// is not a subtle bug: the guest renders completely unstyled, which reads as a
/// broken component rather than a missing stylesheet.
///
/// The page should pre-place an empty `<style id="margaui-css">` early in
/// `<head>` so the upsert keeps it ahead of any lazily-loaded palette `<link>`.
pub fn refresh_margaui() -> Unit {
  guard live_app.val is Some(app) else { return }
  let css = @css.compile_margaui(app.scope.comps.collect_classes()) catch {
    err => {
      @tutuca.warn("margaui compile failed: \{err}")
      return
    }
  }
  @wglue.inject_style(@wglue.document(), "margaui-css", css)
}

// --- the loader bar ---------------------------------------------------------

///|
/// What happened to a load, for a host that has bookkeeping of its own.
///
/// The bar knows how to fetch an archive and nothing about what a load MEANS: to
/// the universal host a finished load may be the last one a saved session was
/// waiting for, and to the storybook it is a reason to recompile the stylesheet.
/// Neither belongs in a loader.
pub(all) enum LoaderEvent {
  /// A load was asked for. The URL, or "" for a file dropped on the page —
  /// which has no name the page could fetch again, and saying so is better than
  /// pretending.
  Started(String)
  /// A bundle registered (or hot-swapped), named by its module.
  Loaded(String)
  /// It did not, in the refusal's own words.
  Failed(String)
} derive(Eq, @debug.Debug)

///|
fn ignore_event(_e : LoaderEvent, _ctx : &@tutuca.Ctx) -> Unit {

}

///|
/// The bar, wired to the bridge.
///
/// `samples` are bundles to offer as buttons; empty draws none. `show_url` adds
/// the URL box. `notify` is where a host does whatever a load means to it, and
/// it receives the `&Ctx` because some of that reaches back into the tree — the
/// universal host answers the last resumed load by bubbling a whole restored
/// page.
///
/// Whatever is above also hears `catalogChanged` as a bubble, which is the part
/// every host needs and none of them can skip.
pub fn loader_bar_comp(
  samples? : Array[LoaderBarSample] = [],
  show_url? : Bool = false,
  status? : String = "",
  notify? : (LoaderEvent, &@tutuca.Ctx) -> Unit = ignore_event,
) -> @component.Component {
  loader_bar_component(init={ status, url: "", showUrl: show_url, samples }, update=(
    s,
    msg,
    ctx,
  ) => {
    match LoaderBarMsg::from_dispatch(msg) {
      // The payload is a `Value` rather than a `String` because the button
      // reads `@value.url` out of the loop rather than naming a literal — the
      // generator types a loop-sourced argument as `any`, which is the honest
      // answer for something the schema cannot see through.
      Some(LoadSample(Str(url))) => {
        notify(Started(url), ctx)
        @dhw.load_url(ctx.path(), url) |> ignore
        return Next({ ..s, url, status: "loading \{url}…" })
      }
      // The name was claimed, and a payload that is not a URL is not a load.
      Some(LoadSample(_)) => return Unchanged
      Some(TypeUrl(url)) => return Next({ ..s, url, })
      Some(LoadUrl) => {
        let url = s.url.trim().to_owned()
        if url == "" {
          return Next({ ..s, status: "nothing to load" })
        }
        notify(Started(url), ctx)
        @dhw.load_url(ctx.path(), url) |> ignore
        return Next({ ..s, status: "loading \{url}…" })
      }
      Some(Unknown(_, _)) | None => ()
    }
    match LoaderBarReceive::from_dispatch(msg) {
      // A dropped file: the payload is the list of descriptors the drop event
      // carried, and the id names the file the browser still holds. No
      // page-level JS is involved — this is an ordinary handler.
      Some(FilesDropped(files)) => {
        guard files is List(items) else { return Unchanged }
        let mut any = false
        for f in items {
          match f.field("id") {
            Num(id) => {
              any = true
              @dhw.load_dropped(ctx.path(), id.to_int()) |> ignore
            }
            _ => ()
          }
        }
        // A drop that carried no file at all is not a load, and telling
        // somebody it is loading would be a lie that never resolves.
        guard any else { return Unchanged }
        notify(Started(""), ctx)
        Next({ ..s, status: "loading…" })
      }
      Some(DyncompLoaded(module_name)) => {
        LoaderBarIntent::CatalogChanged(module_name).dispatch(ctx)
        notify(Loaded(module_name), ctx)
        Next({ ..s, status: "loaded \{module_name}" })
      }
      // The refusal's own words: "this host takes no CSS from a bundle", "no
      // such component". A generic sentence here would throw away the one
      // thing a person can act on.
      Some(DyncompError(why)) => {
        notify(Failed(why), ctx)
        Next({ ..s, status: why })
      }
      // The merged `Receive` now carries this component's own VIEW names as
      // well as the schema's, so `Unknown` no longer covers everything this
      // match has nothing to say about. They are answered by the Input match
      // beside this one, and task 19 folds the two into one.
      _ => Unhandled
    }
  })
}

///|
/// Services a demo PAGE offers to whatever it hosts.
///
/// `double` is the one `guests/counter` calls (`control.request "double"`),
/// and it is here to demonstrate the seam rather than because doubling is
/// interesting: it is a guest asking the page for something it cannot compute
/// for itself. A bundle that serves a request of the same NAME answers its own
/// components first — the counter's `triple` is served by its own bundle and
/// never reaches this map.
///
/// In the shell because both demo pages need exactly it, and had it twice: the
/// universal host to show the seam, the storybook because a card whose button
/// does nothing is a card that lies about the component. The two pages are
/// deliberately different from each other, which is a statement about what
/// they SHOW — not a reason for the sample service behind them to be written
/// out twice.
/// A LIST per name, because the `lex` leg WALKS: a declining handler hands the
/// intent to the next one in the scope chain rather than having to answer.
/// These two decline on a bad argument — see `Pass` below, which is the answer
/// v1 had no word for.
pub fn sample_host_intents() -> Map[String, Array[@component.IntentFn]] {
  {
    "double": [
      IntentFn((call, answer) => {
        match call.args {
          [Num(n)] => answer(Ok(Num(n * 2.0)))
          // NOT `Failed`. This handler cannot answer a call shaped like that,
          // and saying so is different from saying the doubling went wrong —
          // `Pass` lets the walk try the next handler, and if none answers the
          // sender hears `doubleUnhandled` rather than a made-up error. A
          // `RequestFn` had to respond, so v1 could only invent one.
          _ => answer(Pass)
        }
      }),
    ],
    // `roll` is what `examples/dyncomp-dice`'s die calls, and it is the sharper
    // demonstration of the same seam: the counter could compute `double`
    // itself and asks as a courtesy, while the die CANNOT make a number. The
    // world imports no WASI, and the die deliberately declares no
    // `cap-random` — a bundle that asks for a capability is a bundle some
    // pages cannot run, and asking through `control.request` needs no grant
    // because it is not ambient authority. The page answers one question,
    // once, and may decline.
    "roll": [
      IntentFn((call, answer) => {
        match call.args {
          [Num(faces)] => {
            let n = faces.to_int()
            if n < 2 {
              // A REAL failure: the call is shaped right and the request is
              // impossible. `Failed`, not `Pass` — no other handler is going
              // to make a one-sided die either.
              answer(Failed(Str("roll: a die needs at least two faces")))
            } else {
              let face = (next_u32() % n.reinterpret_as_uint()).reinterpret_as_int() +
                1
              answer(Ok(Num(face.to_double())))
            }
          }
          _ => answer(Pass)
        }
      }),
    ],
  }
}

///|
/// A page's own PRNG, for `roll` above.
///
/// The HOST's entropy, not the guest's, and that is the whole point of the die:
/// this is the thing a sandboxed bundle has no way to reach. xorshift32 rather
/// than anything stronger because a demo die needs a different face each time
/// and nothing more; a page that needed unpredictability an attacker cannot
/// reproduce would reach for the platform's own generator here.
let seed : Ref[UInt] = { val: 0x9E3779B9 }

///|
fn next_u32() -> UInt {
  let mut x = seed.val
  x = x ^ (x << 13)
  x = x ^ (x >> 17)
  x = x ^ (x << 5)
  // 0 is xorshift's fixed point: it would give the same face forever.
  seed.val = if x == 0 { 0x9E3779B9 } else { x }
  seed.val
}

///|
/// The origins a demo page lets the bundles it SHIPS load a picture from.
///
/// Still `untrusted` — no clock, no timer, no entropy, no CSS of the bundle's
/// own — plus `cap-external-urls` for these five hosts and nothing else. It is
/// here beside `sample_host_requests` and for the same reason: both pages ship
/// the same archives, so both have to answer the same question, and two copies
/// of an answer about the network are two copies that can drift apart.
///
/// Why each one is on the list, since a list nobody can read back is a list
/// nobody can shorten:
///
/// - `cdn.bsky.app` — every picture the bluesky reader draws: an avatar, a
///   profile banner, an attached image's thumbnail.
/// - `bsky.app` — where its links go: a profile, a hashtag, a permalink.
/// - `ca.slack-edge.com`, `avatars.slack-edge.com`, `secure.gravatar.com` — the
///   three hosts a Slack profile picture actually comes from.
///
/// The mastodon reader is NOT on this list, and that is the change config vars
/// made rather than an omission: it names no origin of its own any more, so
/// there is no origin here to permit. `trusting_manifest_config` is what
/// answers for it — see below.
///
/// What granting them costs is written out in `dyncomp/SECURITY.md` §3, and the
/// short version is that an image is a GET the guest chose: an allowed origin
/// is an origin that can be told this page loaded something. That is why the
/// list is origins a person can check against the views rather than the empty
/// list, which would mean every `https://` origin there is.
///
/// A page that hosts bundles it did NOT ship should not copy this. It should
/// decide, per bundle, which is what the capability is for.
///
/// `trusting_manifest_config` is here for the same reason the list is: these
/// pages ship the archives they load, so "the default in the manifest" and
/// "what this page decided" are one sentence, and writing the mastodon
/// reader's two origins out again in host code would only be a chance to
/// disagree with them. A page loading bundles it did not ship binds with
/// `with_config` instead — deciding per bundle is the whole point.
pub fn sample_policy() -> @policy.Policy {
  @policy.Policy::untrusted()
  .trusting_manifest_config()
  .allowing_external_urls([
    "https://cdn.bsky.app", "https://bsky.app", "https://ca.slack-edge.com", "https://avatars.slack-edge.com",
    "https://secure.gravatar.com",
  ]) catch {
    // Unreachable: every entry above is a literal origin. Refusing to grant is
    // the safe half of the answer anyway — the bundles that wanted it stop
    // loading, and they say why.
    _ => @policy.Policy::untrusted()
  }
}
