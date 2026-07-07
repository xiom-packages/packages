# Frames

> Design stage — specification only.

Once a connection is open, all communication is carried in WebSocket frames. The `frame` module provides a **contract-checked codec** that decodes raw bytes into a typed `Frame` and encodes a `Frame` back to bytes, with explicit payload-size limits enforced at the boundary. Every frame carries a `fin` bit, an opcode, a mask flag, and a payload; the decoder validates each field before the frame is allowed to progress.

Opcodes are modeled as a closed `Opcode` enum in `opcode.xi`: the data opcodes `Text` and `Binary`, the `Continuation` opcode for fragmented messages, and the control opcodes `Close`, `Ping`, and `Pong`. Reserved opcode ranges are rejected outright. Classification helpers (`opcode_is_control`, `opcode_is_data`) let the connection loop route control frames immediately while buffering data frames for reassembly.

Masking follows RFC 6455 strictly: client-to-server frames **must** be masked and server-to-client frames **must not** be masked. The codec enforces this direction rule as a contract, so a mis-masked frame is a protocol error rather than silently accepted data. Fragmentation is handled by requiring that a fragmented message is a single initial data frame followed by zero or more `Continuation` frames with `fin` set on the last, and that control frames are never fragmented and never interleaved incorrectly.

Above the raw codec, `message.xi` assembles fragments into a high-level `Message` (`Text` or `Binary`) and attaches a monotonic sequence number for reconnect recovery. Contract hotspots are frame length limits, opcode validity, the masking direction rule, and fragmentation ordering — all checked before any handler sees the payload.
