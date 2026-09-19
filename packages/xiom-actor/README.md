# xiom.actor

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** Actor model runtime for message-passing concurrency with supervision.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `actor/actor` | Actor runtime with mailbox dispatch |
| `actor/mailbox` | Bounded message queues for actor communication |
| `actor/system` | Actor lifecycle, supervision, and system registry |
| `actor/select` | Selective receive over multiple mailboxes |
