The three ambient facts a component cannot compute for itself: what time it
is, an unpredictable number, and a fresh name. Each one is a CAPABILITY the
manifest requests and the host grants (`capability-req`); an ungranted call
traps rather than returning a plausible lie.

Deliberately NOT `wasi:clocks` + `wasi:random`. Three reasons, in order:
the world imports no WASI and adding it drags preview2 shims into the
browser; a real monotonic clock is the primitive a timing side channel is
built from, and the coarsened one below is not; and an ambient clock makes
a dispatch unreplayable, which contradicts "the host is the framework".