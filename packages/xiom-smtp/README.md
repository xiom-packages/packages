# xiom.smtp

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** SMTP client/server for sending and relaying email.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `smtp-client` | SMTP client for sending messages to a relay or mailbox. |
| `smtp-server` | SMTP server accepting and relaying inbound mail. |
| `message` | Email message construction and envelope handling. |
| `mime` | MIME parsing and encoding of multipart content. |
| `auth` | AUTH PLAIN, LOGIN, and CRAM-MD5 authentication. |
