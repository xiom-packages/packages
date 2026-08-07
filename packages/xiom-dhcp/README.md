# xiom-dhcp

> **Status:** PLACEHOLDER — reserved, spec pending. No implementation yet.
> **Scope:** DHCP client/server for dynamic IP address assignment.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `dhcp-client` | DHCP client for discover, offer, request, and renew. |
| `dhcp-server` | DHCP server leasing addresses on a subnet. |
| `packet` | DHCP packet encode/decode of the fixed and option fields. |
| `option` | DHCP option parsing for routers, DNS, and lease time. |
| `lease` | Lease database with expiry and reuse management. |
