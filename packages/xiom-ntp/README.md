# xiom-ntp

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** NTP client/server for network time synchronization.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `ntp-client` | NTP client querying time from servers. |
| `ntp-server` | NTP server serving time to clients. |
| `packet` | NTP packet encode/decode of timestamps and fields. |
| `clock` | Offset/delay computation and local clock discipline. |
| `stratum` | Stratum and peer hierarchy management. |
