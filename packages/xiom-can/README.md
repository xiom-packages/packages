# xiom.can

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM classic CAN 2.0A/2.0B frame codec: 11-bit and 29-bit
> identifiers, DLC 0..8, remote (RTR) frames, validation, structural
> equality and a fixed 16-byte container codec.
> **Deps:** `xiom.std` only. The library module is dependency-free (no `use`
> at all); the tests use `xiom.test`, `xiom.io`, `xiom.string`,
> `xiom.string.compare` and `xiom.encoding.hex` from it. No FFI.

## What it is

`xiom.can` models one classic CAN 2.0 frame as the plain `CanFrame` struct
(identifier, extended flag, RTR flag, DLC, payload) and encodes it to, or
decodes it from, a fixed 16-byte container. It handles both identifier
formats (11-bit CAN 2.0A and 29-bit CAN 2.0B), data length codes 0..8,
remote transmission request frames, and validates every invariant before a
frame is used or written.

The container layout follows the field order of the classic SocketCAN
`can_frame` (ID word, DLC, three reserved bytes, eight data bytes) with the
multi-byte fields fixed to big-endian, so the byte representation is
platform-neutral:

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | CAN ID word, big-endian: bit 31 EFF (`extended`), bit 30 RTR, bit 29 error-frame flag (rejected), bits 28..0 identifier |
| 4 | 1 | DLC, 0..8 |
| 5 | 3 | reserved, must be 0 |
| 8 | 8 | data, bytes beyond the DLC must be 0 |

Only the canonical form is accepted by `can_decode`: a data frame carries
exactly `dlc` payload bytes and a remote frame carries none, so every
accepted container round-trips byte-for-byte.

## API

| Function | Returns | Description |
|---|---|---|
| `can_max_id(extended)` | `Int` | Largest identifier of the type: 2047 or 536870911. |
| `can_id_ok(id, extended)` | `Bool` | Identifier range check by type. |
| `can_id_word(f)` | `Int` | Raw ID word of a frame (bit 31 EFF, bit 30 RTR, bits 28..0 id). |
| `can_encoded_size()` | `Int` | Container size in bytes (16). |
| `can_validate(f)` | `Result[Unit, Str]` | Full frame validation; `Ok(())` for a canonical frame. |
| `can_new(id, extended, rtr, dlc, data)` | `Result[CanFrame, Str]` | Build any frame from its five fields (validated). |
| `can_data_frame(id, extended, data)` | `Result[CanFrame, Str]` | Build a data frame; DLC becomes `data.len()`. |
| `can_remote_frame(id, extended, dlc)` | `Result[CanFrame, Str]` | Build a remote frame (no data, DLC is the requested length). |
| `can_encode(f)` | `Result[Vec[UInt8], Str]` | Encode a frame to its 16-byte container. |
| `can_encode_into(out, f)` | `Result[Unit, Str]` | Append the container to `out`; `out` is untouched on `Err`. |
| `can_decode(bytes)` | `Result[CanFrame, Str]` | Decode the first 16 bytes of `bytes` (extra bytes ignored). |
| `can_is_extended(f)` | `Bool` | Frame uses a 29-bit identifier. |
| `can_is_remote(f)` | `Bool` | Frame is a remote transmission request. |
| `can_payload_len(f)` | `Int` | Payload byte count (0 for a remote frame). |
| `can_data_get(f, i)` | `Int` | Payload byte `i` widened to 0..255, or -1 when out of range. |
| `can_equal(a, b)` | `Bool` | Structural equality of all five fields. |

## Error model

Every failure is `Err(Str)` with a deterministic `can: ` message; the full
catalog and the exact check order live in SPEC.md.

| Condition | Error text |
|---|---|
| `id < 0` | `can: negative identifier` |
| Standard frame with `id > 2047` | `can: identifier exceeds standard range` |
| Extended frame with `id > 536870911` | `can: identifier exceeds extended range` |
| Payload longer than 8 bytes | `can: payload exceeds 8 bytes` |
| DLC outside 0..8 | `can: invalid dlc` |
| Remote frame with bytes in `data` | `can: remote frame carries data` |
| Data frame with `data.len() != dlc` | `can: data length does not match dlc` |
| `can_decode`: buffer shorter than 16 bytes | `can: truncated frame` |
| `can_decode`: ID-word bit 29 set | `can: error frame flag set` |
| `can_decode`: reserved byte 5, 6 or 7 nonzero | `can: nonzero reserved byte` |
| `can_decode`: data frame, byte past the DLC nonzero | `can: nonzero padding byte` |
| `can_decode`: remote frame, any data byte nonzero | `can: nonzero rtr data byte` |

`can_encode_into` validates before writing, so an `Err` leaves `out` exactly
as it was. `can_decode` checks truncation first and `can_encode`/`can_validate`
report the identifier error before the payload/DLC/data errors.

## Usage

```xi
use xiom.can;
use xiom.io;
use xiom.encoding.hex;

// Build a standard 2.0A data frame: identifier 0x123, payload DE AD.
var payload = Vec[UInt8].new();
payload.push(222 as UInt8);   // 0xDE
payload.push(173 as UInt8);   // 0xAD
let built = can_data_frame(291, false, &payload);
match built {
  Ok(f) => {
    io.println("dlc = " + xiom.convert.int_to_string(f.dlc));   // dlc = 2
    let e = can_encode(&f);
    if e.is_ok {
      let bytes: Vec[UInt8] = e.value;
      io.println(hex.hex_encode(&bytes));
      // 0000012302000000dead000000000000
    }
  },
  Err(m) => { io.println("build error: " + m); },
}

// Decode a remote 2.0B container back into a frame.
let src = hex.hex_decode("dfffffff000000000000000000000000");
match src {
  Ok(bytes) => {
    let d = can_decode(&bytes);
    if d.is_ok {
      let f: CanFrame = d.value;
      io.println("id = " + xiom.convert.int_to_string(f.id));    // id = 536870911
      io.println("dlc = " + xiom.convert.int_to_string(f.dlc));   // dlc = 0
    }
  },
  Err(_) => {},
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.can
```

Expected: the section-4 namespace check passes, 22 `[PASS]` lines, and a
final `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Classic CAN 2.0 only.** No CAN-FD: payloads are at most 8 bytes and DLC
  values above 8 are rejected.
- **No bus or socket I/O.** The package never touches a CAN controller, a
  socket or a file; it converts between `CanFrame` values and in-memory
  byte containers. It also does not model bit timing, CRC, bit stuffing,
  acknowledgement or arbitration, and it has no timestamps.
- **Error frames are rejected.** The CAN ID word only carries the EFF and
  RTR flags; bit 29 (the SocketCAN error-frame flag) is an error.
- **Strict canonical form.** `can_decode` refuses containers with nonzero
  reserved bytes, unused high identifier bits on a standard frame, nonzero
  padding beyond the DLC or nonzero data bytes on a remote frame. Real bus
  captures and OS structs that leave padding uninitialized must be cleaned
  up by the caller first. Data frames must carry exactly `dlc` bytes.
- **Fixed byte order.** The 16-byte container is big-endian regardless of
  the host; it is a serialization format, not a raw `struct can_frame`
  memory image.
- `can_new` accepts an explicit DLC that may disagree with the payload; the
  mismatch is then reported by `can_validate`/`can_encode`, while
  `can_data_frame` derives the DLC from the payload.
- Not thread-safe; `CanFrame` is a plain value type with no interior state.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
