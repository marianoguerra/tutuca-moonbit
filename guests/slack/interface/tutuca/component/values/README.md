Dynamic values crossing the boundary. WIT has no recursive types, so
scalars travel inline and compounds are u64 handles into a host-side
arena, read/built through this interface. Handles are only valid for the
duration of the current host->guest call: read handles go stale when the
call returns, and freshly built handles must be handed back to the host
(in a return value or an import argument) within the same call.
`instance` payloads are guest-instance handles (see `guest.instance`),
used for nested same-bundle child components.