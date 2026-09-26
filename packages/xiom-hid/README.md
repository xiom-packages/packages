# xiom.hid

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM USB HID report-descriptor parsing, validation and
> canonical emission for a documented item subset.
> **Deps:** `xiom.std` only. The library module is dependency-free (no stdlib
> imports, no FFI); the tests use `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.encoding.hex` from it.

## What it is

`xiom.hid` decodes a USB HID report descriptor (HID 1.11 section 6.2.2) into
a flat, self-contained item store and can re-emit the descriptor
byte-for-byte. Each item keeps its type (main / global / local / long), its
tag, its data width, the unsigned little-endian data value, the raw long-item
payload, its collection nesting depth, the Push/Pop balance after it, and the
Usage Page in effect. Accessors expose the unsigned value, the per-width
signed interpretation (as used by Logical/Physical Minimum and Maximum), the
nibble-signed interpretation (as used by Unit Exponent), collection kinds,
usage IDs and Usage Pages. `hid_parse` validates the stream (truncation,
reserved size/type/tag, Push/Pop balance, collection balance and the
collection depth cap) and returns deterministic `Err(Str)` messages for every
malformed shape; `hid_emit` rebuilds the canonical bytes from the store alone.

## API

| Function | Returns | Description |
|---|---|---|
| `hid_parse(data)` | `Result[HidDescriptor, Str]` | Parse and validate a report descriptor; flat self-contained item store. |
| `hid_emit(d)` | `Result[Vec[UInt8], Str]` | Emit the canonical bytes of a parsed store (byte-identical input round-trip). |
| `hid_max_collection_depth()` | `Int` | Documented collection nesting cap (32). |
| `hid_item_count(d)` | `Int` | Number of items (short and long). |
| `hid_item_type(d, i)` | `Int` | `HID_TYPE_MAIN` / `_GLOBAL` / `_LOCAL` / `_LONG`; `-1` out of range. |
| `hid_item_tag(d, i)` | `Int` | bTag (or bLongItemTag); `-1` out of range. |
| `hid_item_size(d, i)` | `Int` | Data-byte count (0/1/2) or long bDataSize; `-1` out of range. |
| `hid_item_data(d, i)` | `Int` | Unsigned little-endian data value; `0` out of range/long. |
| `hid_item_data_signed(d, i)` | `Int` | Sign-extended per width (-128..127, -32768..32767); `0` out of range/long. |
| `hid_item_data_nibble_signed(d, i)` | `Int` | Nibble-signed low 4 bits (-8..7, Unit Exponent); `0` out of range/long. |
| `hid_item_data_bytes(d, i)` | `Result[Vec[UInt8], Str]` | Copy of the item's data bytes (short: width bytes; long: payload). |
| `hid_item_bytes(d, i)` | `Result[Vec[UInt8], Str]` | Copy of the whole encoded item (prefix + data). |
| `hid_item_depth(d, i)` | `Int` | Enclosing collection count; `-1` out of range. |
| `hid_item_stack(d, i)` | `Int` | Push/Pop balance after the item; `-1` out of range. |
| `hid_item_collection_kind(d, i)` | `Int` | Collection data value (0 Physical ... 6 Usage Modifier); `-1` not a Collection. |
| `hid_item_usage(d, i)` | `Int` | Usage ID of a Usage/Usage Minimum/Usage Maximum item; `-1` otherwise. |
| `hid_item_usage_page(d, i)` | `Int` | Usage Page in effect for the item (Push/Pop aware); `0` out of range. |

Tag and type constants (`HID_TYPE_*`, `HID_MAIN_*`, `HID_GLOBAL_*`,
`HID_LOCAL_*`, `HID_LONG_ITEM_PREFIX`) are exported for building and
inspecting items.

Errors: `hid: truncated item`, `hid: truncated long item`,
`hid: reserved item size`, `hid: reserved item type`, `hid: reserved item
tag`, `hid: pop without push`, `hid: end collection without collection`,
`hid: collection nesting exceeds limit of 32`, `hid: unterminated
collection`, `hid: unbalanced push`, `hid: item index out of range`,
`hid: invalid store` (see SPEC.md for the exact conditions).

## Usage

```xi
use xiom.hid;
use xiom.io;
use xiom.convert;

// A two-item stream: Usage Page (Generic Desktop) = 05 01, Usage X = 09 30.
var raw = Vec[UInt8].new();
raw.push(5 as UInt8);  raw.push(1 as UInt8);   // 0x05 0x01
raw.push(9 as UInt8);  raw.push(48 as UInt8);  // 0x09 0x30
let parsed = hid_parse(&raw);
match parsed {
  Ok(d) => {
    io.println("items: " + convert.int_to_string(hid_item_count(&d)));
    // "items: 2"
    io.println("usage: " + convert.int_to_string(hid_item_usage(&d, 1)));
    // "usage: 48"
    io.println("page:  " + convert.int_to_string(hid_item_usage_page(&d, 1)));
    // "page:  1"
    let back = hid_emit(&d);
    if back.is_ok {
      io.println("round-trips: " + convert.int_to_string(back.value.len()));
      // "round-trips: 4"
    }
  },
  Err(e) => { io.println("parse error: " + e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.hid
```

Expected: the section-4 namespace check passes, 16 `[PASS]` lines, and a
final `port: PASS (passed=16 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Documented subset only.** Exactly the tags listed in SPEC.md are
  accepted; reserved tags and the reserved short item type (bType = 3
  outside the 0xFE long prefix) are rejected rather than preserved.
- **No 4-byte short items.** The HID bSize = 3 form (4 data bytes) is
  outside the subset (`hid: reserved item size`); only 0/1/2-byte short
  payloads and long items are supported.
- **No report-field assembly.** No report bit offsets, no field extraction,
  no logical/physical scaling, no report ID semantics beyond recording the
  Report ID item.
- **No usage tables.** Usage IDs and Usage Pages are raw numbers; no
  name resolution.
- **Push/Pop is only balanced and page-tracked.** The stored bytes are not
  replayed against a full global item state machine (Report Size/Count/...
  are recorded, not assembled).
- **Long items are opaque.** Their tag and payload are preserved verbatim
  and never interpreted.
- **No HID device IO.** This is a pure in-memory codec; it never touches a
  device or a transport.
- The store is a plain value type built from parallel vectors; callers can
  corrupt its invariants by hand, and `hid_emit` rejects such stores with
  `hid: invalid store` instead of repairing them.
- Not thread-safe; `HidDescriptor` is a plain value type.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
