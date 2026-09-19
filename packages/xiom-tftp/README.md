# xiom.tftp

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** TFTP client/server for trivial file transfer.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `tftp-client` | TFTP client for reading and writing remote files. |
| `tftp-server` | TFTP server handling read and write requests. |
| `packet` | TFTP packet encode/decode (RRQ, WRQ, DATA, ACK). |
| `transfer` | Retransmission and windowed transfer logic. |
| `options` | RFC 2347 options like blksize and timeout. |
