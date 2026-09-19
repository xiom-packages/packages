# xiom.imap

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** IMAP client/server for mailbox access and synchronization.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `imap-client` | IMAP client with folder, message, and flag operations. |
| `imap-server` | IMAP server with mailbox and message store. |
| `mailbox` | Mailbox/folder hierarchy and message sequence handling. |
| `idle` | IDLE push notifications for new mail. |
| `search` | Server-side search and fetch criteria. |
