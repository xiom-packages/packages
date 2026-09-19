# xiom.pop3

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** POP3 client/server for retrieving mail from a mailbox.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `pop3-client` | POP3 client for listing, fetching, and deleting messages. |
| `pop3-server` | POP3 server exposing a mailbox over the wire. |
| `message` | Message retrieval and header/body separation. |
| `auth` | USER/PASS and APOP authentication. |
