# xiom.uart

> **Status:** PLACEHOLDER -- reserved, spec pending. No implementation yet.
> **Scope:** UART serial communication with baud-rate, framing, and buffered I/O.
> **Deps:** stdlib; may wrap C (FFI).

## Libs inventory

| Lib | Description |
|-----|-------------|
| `config` | Baud rate and framing configuration. |
| `tx` | Transmit path with FIFO management. |
| `rx` | Receive path with line buffering. |
| `flow` | Hardware flow-control signaling. |
| `errors` | Framing/overrun error reporting. |
