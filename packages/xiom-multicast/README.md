# xiom.multicast

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** IP multicast send/receive with group membership management.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `socket` | Multicast socket setup and address binding. |
| `sender` | Multicast sending with TTL and loop control. |
| `receiver` | Multicast group join and datagram reception. |
| `group` | Group membership and interface management. |
| `igmp` | IGMP membership reporting for routers. |
