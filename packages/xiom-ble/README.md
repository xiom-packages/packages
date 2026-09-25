# xiom.ble

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM Bluetooth Low Energy advertising-data codec: a flat
> sequence of AD structures (one length byte, one AD type byte, `length - 1`
> data bytes) with typed builders and decoders for the common AD types, a
> 31-byte legacy validator and a deterministic error catalog. Legacy
> advertising payloads only.
> **Deps:** `xiom.std` only. The library module uses `xiom.string`; the
> tests add `xiom.test`, `xiom.io`, `xiom.string.compare` and
> `xiom.encoding.hex`. No FFI, no C, no new dependencies.

## What it is

`xiom.ble` encodes and decodes the payload of a legacy BLE advertising
packet. On the air that payload is a flat sequence of **AD structures**:

```
+--------+--------+-------------------+
| length |  type  |  data (length-1)  |  ...
+--------+--------+-------------------+
```

The `length` byte counts the type byte plus the data, so an AD structure is
`length + 1` bytes in total. `ble_parse` walks a buffer until it ends and
returns an `AdList` index holding the AD type and the absolute data span of
every structure; unknown AD types are preserved verbatim, so a packet can be
inspected and rebuilt without knowing every type. The typed builders
(`ble_ad_flags`, `ble_ad_name_complete`, `ble_ad_service_uuid16`, ...)
produce one complete structure each, with the length byte recomputed from the
payload; `ble_append_structure`, `ble_append_ad` and `ble_build_from`
concatenate them; `ble_validate` additionally enforces the 31-byte legacy
advertising limit.

Multi-byte AD fields are little-endian on the air; the decoders return plain
`Int`s in host read order (for example `ble_decode_uuid16(&[0x0d, 0x18])`
returns `0x180D` = `6157`). Names are handled as raw bytes: the codec never
guesses an encoding.

## Install / use

```
xiom pkg install xiom.ble@0.1.0
```

```xi
use xiom.ble;
```

## Quick start

```xi
use xiom.ble;
use xiom.io;
use xiom.convert;

// 1. Build: concatenate complete AD structures from the typed builders.
var payload = Vec[UInt8].new();
let flags = ble_ad_flags(6);                     // 02 01 06
match flags {
  Ok(v) => { ble_append_structure(&mut payload, &v); },
  Err(e) => { io.println("flags: " + e); },
}
let name = ble_ad_name_complete("Xiom Sensor");  // length-prefixed name
match name {
  Ok(v) => { ble_append_structure(&mut payload, &v); },
  Err(e) => { io.println("name: " + e); },
}
let tx = ble_ad_tx_power(-4);                    // 02 0A FC
match tx {
  Ok(v) => { ble_append_structure(&mut payload, &v); },
  Err(e) => { io.println("tx power: " + e); },
}

// 2. Validate the 31-byte legacy limit before putting it on air.
let va = ble_validate(&payload);
if !va.is_ok { io.println("not legacy-advertisable: " + va.error); }

// 3. Parse it back.
let r = ble_parse(&payload);
match r {
  Ok(l) => {
    io.println("AD structures: " + int_to_string(ble_count(&l)));
    let i = ble_find(&l, 9);                     // Complete Local Name
    if i >= 0 {
      let d = ble_data(&payload, &l, i);
      if d.is_ok {
        let bytes: Vec[UInt8] = d.value;
        io.println("name bytes: " + int_to_string(bytes.len()));
      }
    }
  },
  Err(e) => { io.println("parse error: " + e); },
}
```

## API summary

All functions are free functions in module `xiom.ble` (no self methods).

### Structure index

| Function | Returns | Description |
|---|---|---|
| `ble_parse(data)` | `Result[AdList, Str]` | Walk a payload until `data` ends; index types and data spans. |
| `ble_count(l)` | `Int` | Number of parsed AD structures. |
| `ble_type(l, i)` | `Int` | AD type of entry `i`; `-1` when out of range. |
| `ble_find(l, ad_type)` | `Int` | First entry with `ad_type`; `-1` when absent. |
| `ble_has(l, ad_type)` | `Bool` | True when at least one entry has `ad_type`. |
| `ble_data(data, l, i)` | `Result[Vec[UInt8], Str]` | Copy the data bytes of entry `i` out of `data`. |
| `ble_ad_size(l, i)` | `Int` | Encoded size of entry `i`; `-1` when out of range. |
| `ble_total_length(l)` | `Int` | Total encoded size of every parsed entry. |

### Typed data decoders

| Function | Returns | Description |
|---|---|---|
| `ble_decode_flags(payload)` | `Result[Int, Str]` | Flags byte (0x01), 1 byte, 0..255. |
| `ble_decode_tx_power(payload)` | `Result[Int, Str]` | TX power (0x0A), 1 signed byte, -128..127 dBm. |
| `ble_decode_uuid16(payload)` | `Result[Int, Str]` | 16-bit UUID (0x02/0x03), 2 LE bytes. |
| `ble_decode_uuid32(payload)` | `Result[Int, Str]` | 32-bit UUID (0x04/0x05), 4 LE bytes. |
| `ble_decode_manufacturer_id(payload)` | `Result[Int, Str]` | Company id (0xFF), first 2 LE bytes. |
| `ble_decode_slave_interval(payload)` | `Result[Vec[Int], Str]` | 0x12, 4 LE bytes, `[min, max]` in 1.25 ms units. |

### Builders (one complete AD structure each)

| Function | AD type | Description |
|---|---|---|
| `ble_ad(ad_type, payload)` | any | Generic structure; length recomputed. |
| `ble_ad_flags(flags)` | 0x01 | Flags byte 0..255. |
| `ble_ad_name_short(name)` | 0x08 | Shortened Local Name (1..254 bytes). |
| `ble_ad_name_complete(name)` | 0x09 | Complete Local Name (1..254 bytes). |
| `ble_ad_tx_power(dbm)` | 0x0A | TX power -128..127 dBm. |
| `ble_ad_service_uuid16(uuid, complete)` | 0x02/0x03 | 16-bit service UUID, LE. |
| `ble_ad_service_uuid32(uuid, complete)` | 0x04/0x05 | 32-bit service UUID, LE. |
| `ble_ad_service_uuid128(uuid, complete)` | 0x06/0x07 | 128-bit UUID, 16 bytes verbatim (on-air order). |
| `ble_ad_slave_interval(min_units, max_units)` | 0x12 | Connection interval range, 6..3200 units. |
| `ble_ad_service_data16(uuid, payload)` | 0x16 | 16-bit UUID then service data. |
| `ble_ad_manufacturer(id, payload)` | 0xFF | Company id then manufacturer data. |

`complete` selects the "complete" type (`true`, odd type) or the "incomplete"
type (`false`, even type): 0x03/0x02, 0x05/0x04, 0x07/0x06.

### Composition and validation

| Function | Returns | Description |
|---|---|---|
| `ble_append_structure(out, ad)` | `Unit` | Append a complete structure verbatim (no re-validation). |
| `ble_append_ad(out, ad_type, payload)` | `Result[Unit, Str]` | Append one validated structure; `out` unchanged on `Err`. |
| `ble_build_from(types, payloads)` | `Result[Vec[UInt8], Str]` | Build a whole payload from parallel vectors. |
| `ble_legacy_limit()` | `Int` | The legacy advertising payload limit, 31 bytes. |
| `ble_validate(data)` | `Result[Unit, Str]` | Parse and enforce the 31-byte legacy limit. |

## Error model

Every failure is a `Result` with a fixed `"ble: ..."` message; there are no
panics and no silent truncation. The catalog:

| Error text | Condition |
|---|---|
| `ble: zero-length AD structure` | A length byte is 0 (padding is not supported). |
| `ble: truncated AD structure` | A length byte is present but the buffer ends before the type byte. |
| `ble: AD length overruns buffer` | The type byte is present but fewer than `length - 1` data bytes remain. |
| `ble: index out of range` | `ble_data` entry index < 0 or >= `ble_count(l)`. |
| `ble: data out of bounds` | Recorded span does not fit the buffer passed to `ble_data`. |
| `ble: AD type out of range` | `ad_type` outside 0..255. |
| `ble: flags out of range` | Flags outside 0..255. |
| `ble: empty local name` | Empty name passed to a name builder. |
| `ble: name too long` | Name longer than 254 bytes. |
| `ble: TX power out of range` | dBm outside -128..127. |
| `ble: UUID out of range` | 16-bit UUID outside 0..65535 or 32-bit UUID outside 0..4294967295. |
| `ble: 128-bit UUID must be 16 bytes` | 128-bit UUID slice length != 16. |
| `ble: connection interval out of range` | Interval unit outside 6..3200 (7.5 ms..4 s). |
| `ble: connection interval min above max` | `min > max` in a range (build or decode). |
| `ble: manufacturer ID out of range` | Company id outside 0..65535. |
| `ble: payload too large` | Generic payload > 254 bytes, or service/manufacturer payload > 252 bytes. |
| `ble: types/payloads length mismatch` | `ble_build_from` vectors differ in length. |
| `ble: wrong data length` | A typed decoder received a payload of the wrong width. |
| `ble: payload exceeds 31-byte legacy limit` | `ble_validate` on a structurally valid payload longer than 31 bytes. |

`ble_parse` reports structural errors in wire order: the first malformed
structure fails the whole parse, and no partial list is returned.
`ble_append_ad` and the builders validate everything before emitting bytes;
`ble_append_ad` leaves `out` byte-for-byte unchanged on `Err`. `ble_type` and
`ble_ad_size` report out-of-range indices as `-1` (no error channel).

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ble
```

Expected: the namespace check passes, 20 `[PASS]` lines, and a final
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Legacy advertising only.** The 31-byte limit is checked by
  `ble_validate`; the builders themselves do not enforce it, so structures
  can be inspected or combined beyond 31 bytes (extended advertising is out
  of scope).
- **No zero-length padding.** A zero length byte is an error, not padding;
  buffers must contain only real AD structures.
- **Codec only.** No HCI commands, no sockets/radios, no scanning,
  connection management, GATT, pairing or security. This package turns bytes
  into structures and back.
- **Names are bytes.** `ble_ad_name_*` copies the `Str` bytes verbatim and
  the decoder layer returns raw bytes; there is no UTF-8 validation or
  `Str` reconstruction, and no duplicate-type merging or canonical ordering.
- **128-bit UUIDs are caller-ordered.** The 16 bytes are copied verbatim in
  on-air (little-endian) order; the codec does not reverse them.
- **Interval units are 1.25 ms.** `ble_ad_slave_interval` takes units of
  1.25 ms in the spec range 6..3200 and does not convert to milliseconds.
- **One encoding channel.** All errors are `Str` messages; the codec has no
  typed error enum.
- Not thread-safe; `AdList` is a plain value type that stores offsets into
  the parse buffer, so `ble_data` needs that same buffer (or one holding at
  least the recorded spans).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
