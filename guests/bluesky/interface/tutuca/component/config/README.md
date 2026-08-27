What the HOST decided this bundle's variables are: the manifest's declared
defaults with the host's bindings applied.

The answer to "this component would work anywhere, if somebody told it
where". `guests/mastodon` is the worked example: the same six components
read mastodon.social or hachyderm.io depending on two strings, and neither
the wasm nor the views change between them.

NOT authority. These values are the host's own, handed over deliberately —
reading one gives a guest nothing it could not have been shipped as a
constant. What the values reach is decided elsewhere: a view can name an
`origin` variable, and the external-URL allowance it spends is the host's,
made by binding it.