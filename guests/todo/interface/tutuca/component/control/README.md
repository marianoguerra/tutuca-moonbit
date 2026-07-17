Framework services available to a running handler. Calls are buffered by
the host and applied through the dispatching handler's context when
`handle-event` returns (tutuca ctx.bubble / ctx.send / ctx.request).
`log` is immediate and always legal.