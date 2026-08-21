# xiom-upnp

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** UPnP/SSDP device discovery and control point.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `ssdp` | SSDP discovery via multicast and unicast responses. |
| `discovery` | Device/service search and notification handling. |
| `control-point` | Control point invoking actions on devices. |
| `soap` | SOAP encoding/decoding for UPnP control messages. |
| `igd` | Internet Gateway Device port mapping support. |
