# xiom-snmp

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** SNMP agent/manager for network device monitoring.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `snmp-agent` | SNMP agent serving device object state. |
| `snmp-manager` | SNMP manager issuing get, set, and walk. |
| `oid` | Object identifier handling and tree traversal. |
| `mib` | MIB definition registry and value access. |
| `trap` | Trap and notification send/receive. |
