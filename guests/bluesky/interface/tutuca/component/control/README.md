Framework services available to a running handler. Calls are buffered by
the host and applied through the dispatching handler's context when
`handle-message` / `handle-intent` returns (tutuca ctx.send / ctx.intent).
`log` is immediate and always legal.