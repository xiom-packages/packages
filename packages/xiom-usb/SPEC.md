# xiom.usb -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.usb`, version `0.1.0`).
Module: `src/usb.xi` (`module xiom.usb`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`); tests add
`xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`.
No FFI.

## Scope

A pure-XIOM (no FFI) codec for USB descriptor streams (USB 2.0 and the
USB 3.x BOS subset):

- `usb_parse` validates a descriptor stream and returns a flat `Usb` store
  of parallel vectors with parent links (device -> configurations ->
  interfaces -> endpoints) plus a string-descriptor pool and a raw-
  preserved descriptor list;
- accessors report device fields, configuration count/fields, interface
  fields, endpoint fields by interface, strings by bStringIndex, global
  descriptor spans and raw-preserved header fields;
- `usb_emit` re-serializes a parsed store as the canonical stream,
  byte-identical to the input for canonical input;
- deterministic `Err(Str)` messages for every malformed shape.

## Non-goals

- HID report descriptor interpretation.
- Class-specific descriptor semantics (CS_INTERFACE, CS_ENDPOINT, HID
  descriptors, ...): such descriptors are preserved raw and never
  interpreted.
- Transfers, speed negotiation, enumeration state machines, control
  requests.
- Device-tree-style schema validation of vendor-specific fields beyond the
  documented subset.
- Building a stream from scratch without a parse: the emitter works from a
  parsed store and the parse buffer (spans, not copies).
- Incremental/streaming parsing; the whole stream is an in-memory
  `Vec[UInt8]`.
- Multiple device descriptors per stream (a second DEVICE is an error).

## Byte-level layout

Every descriptor starts with the generic 2-byte header:

| Offset | Field | Notes |
|---|---|---|
| 0 | bLength | total size including the header, `>= 2` |
| 1 | bDescriptorType | selects the descriptor kind |

Type codes used by the structured subset:

| Code | Descriptor | Length |
|---|---|---|
| 0x01 | DEVICE | exactly 18 |
| 0x02 | CONFIGURATION | exactly 9 |
| 0x03 | STRING | even, `>= 4` |
| 0x04 | INTERFACE | exactly 9 |
| 0x05 | ENDPOINT | exactly 7 |

Raw-preserved types (span + header accessors only):

| Code | Descriptor | Documented header fields |
|---|---|---|
| 0x06 | DEVICE_QUALIFIER | bcdUSB (2), bDeviceClass (4), bDeviceSubClass (5), bDeviceProtocol (6), bMaxPacketSize0 (7), bNumConfigurations (8) |
| 0x0F | BOS | wTotalLength (2, LE), bNumDeviceCaps (4) |
| 0x10 | DEVICE_CAPABILITY | bDevCapabilityType (2) |
| other | unknown | none (raw span only) |

Offsets in the table are relative to the descriptor's bLength byte. All
multi-byte fields are little-endian.

### DEVICE (0x01, 18 bytes)

| Offset | Size | Field |
|---|---|---|
| 2 | 2 | bcdUSB |
| 4 | 1 | bDeviceClass |
| 5 | 1 | bDeviceSubClass |
| 6 | 1 | bDeviceProtocol |
| 7 | 1 | bMaxPacketSize0 |
| 8 | 2 | idVendor |
| 10 | 2 | idProduct |
| 12 | 2 | bcdDevice |
| 14 | 1 | iManufacturer |
| 15 | 1 | iProduct |
| 16 | 1 | iSerialNumber |
| 17 | 1 | bNumConfigurations |

### CONFIGURATION (0x02, 9 bytes)

| Offset | Size | Field |
|---|---|---|
| 2 | 2 | wTotalLength |
| 4 | 1 | bNumInterfaces |
| 5 | 1 | bConfigurationValue |
| 6 | 1 | iConfiguration |
| 7 | 1 | bmAttributes |
| 8 | 1 | bMaxPower (2 mA units) |

`wTotalLength` counts the configuration descriptor plus every child
descriptor up to the next configuration-level descriptor; see Semantics.

### INTERFACE (0x04, 9 bytes)

| Offset | Size | Field |
|---|---|---|
| 2 | 1 | bInterfaceNumber |
| 3 | 1 | bAlternateSetting |
| 4 | 1 | bNumEndpoints (the endpoint claim) |
| 5 | 1 | bInterfaceClass |
| 6 | 1 | bInterfaceSubClass |
| 7 | 1 | bInterfaceProtocol |
| 8 | 1 | iInterface |

### ENDPOINT (0x05, 7 bytes)

| Offset | Size | Field |
|---|---|---|
| 2 | 1 | bEndpointAddress |
| 3 | 1 | bmAttributes |
| 4 | 2 | wMaxPacketSize |
| 6 | 1 | bInterval |

### STRING (0x03, even bLength >= 4)

| Offset | Size | Field |
|---|---|---|
| 2 | 2 | bStringIndex (a UTF-16LE code unit) |
| 4 | bLength - 4 | UTF-16LE text code units |

Non-goal: the language ID descriptor (bStringIndex 0) is not special-cased;
it decodes under the same policy (a single-LANGID descriptor yields empty
text, additional LANGID units become `?`).

## API signatures

All functions are free functions in module `xiom.usb` (no self methods):

```xi
pub type Usb = { /* 43 flat fields; see src/usb.xi */ }

pub fn usb_parse(data: &Vec[UInt8]) -> Result[Usb, Str]
pub fn usb_emit(data: &Vec[UInt8], u: &Usb) -> Result[Vec[UInt8], Str]

pub fn usb_descriptor_count(u: &Usb) -> Int
pub fn usb_descriptor_type(u: &Usb, i: Int) -> Int
pub fn usb_descriptor_length(u: &Usb, i: Int) -> Int
pub fn usb_descriptor_offset(u: &Usb, i: Int) -> Int
pub fn usb_descriptor_bytes(data: &Vec[UInt8], u: &Usb, i: Int) -> Result[Vec[UInt8], Str]

pub fn usb_has_device(u: &Usb) -> Bool
pub fn usb_device_bcd_usb(u: &Usb) -> Int
pub fn usb_device_class(u: &Usb) -> Int
pub fn usb_device_subclass(u: &Usb) -> Int
pub fn usb_device_protocol(u: &Usb) -> Int
pub fn usb_device_max_packet0(u: &Usb) -> Int
pub fn usb_device_vendor(u: &Usb) -> Int
pub fn usb_device_product(u: &Usb) -> Int
pub fn usb_device_bcd_device(u: &Usb) -> Int
pub fn usb_device_imanufacturer(u: &Usb) -> Int
pub fn usb_device_iproduct(u: &Usb) -> Int
pub fn usb_device_iserial(u: &Usb) -> Int
pub fn usb_device_num_configurations(u: &Usb) -> Int

pub fn usb_configuration_count(u: &Usb) -> Int
pub fn usb_configuration_total_length(u: &Usb, c: Int) -> Int
pub fn usb_configuration_num_interfaces(u: &Usb, c: Int) -> Int
pub fn usb_configuration_value(u: &Usb, c: Int) -> Int
pub fn usb_configuration_istring(u: &Usb, c: Int) -> Int
pub fn usb_configuration_attributes(u: &Usb, c: Int) -> Int
pub fn usb_configuration_max_power(u: &Usb, c: Int) -> Int
pub fn usb_configuration_interface_count(u: &Usb, c: Int) -> Int

pub fn usb_interface_count(u: &Usb) -> Int
pub fn usb_interface_configuration(u: &Usb, i: Int) -> Int
pub fn usb_interface_number(u: &Usb, i: Int) -> Int
pub fn usb_interface_alternate(u: &Usb, i: Int) -> Int
pub fn usb_interface_endpoint_claim(u: &Usb, i: Int) -> Int
pub fn usb_interface_endpoint_count(u: &Usb, i: Int) -> Int
pub fn usb_interface_unlisted_endpoints(u: &Usb, i: Int) -> Int
pub fn usb_interface_class(u: &Usb, i: Int) -> Int
pub fn usb_interface_subclass(u: &Usb, i: Int) -> Int
pub fn usb_interface_protocol(u: &Usb, i: Int) -> Int
pub fn usb_interface_istring(u: &Usb, i: Int) -> Int

pub fn usb_endpoint_count(u: &Usb) -> Int
pub fn usb_endpoint_interface(u: &Usb, e: Int) -> Int
pub fn usb_endpoint_address(u: &Usb, e: Int) -> Int
pub fn usb_endpoint_attributes(u: &Usb, e: Int) -> Int
pub fn usb_endpoint_max_packet(u: &Usb, e: Int) -> Int
pub fn usb_endpoint_interval(u: &Usb, e: Int) -> Int
pub fn usb_endpoint_count_for_interface(u: &Usb, i: Int) -> Int
pub fn usb_find_endpoint(u: &Usb, i: Int, address: Int) -> Int

pub fn usb_string_count(u: &Usb) -> Int
pub fn usb_string_index(u: &Usb, i: Int) -> Int
pub fn usb_string_text(u: &Usb, i: Int) -> Str
pub fn usb_string_replacements(u: &Usb, i: Int) -> Int
pub fn usb_string_present(u: &Usb, sid: Int) -> Bool
pub fn usb_string(u: &Usb, sid: Int) -> Result[Str, Str]

pub fn usb_raw_count(u: &Usb) -> Int
pub fn usb_raw_type(u: &Usb, i: Int) -> Int
pub fn usb_raw_length(u: &Usb, i: Int) -> Int
pub fn usb_raw_offset(u: &Usb, i: Int) -> Int
pub fn usb_raw_bytes(data: &Vec[UInt8], u: &Usb, i: Int) -> Result[Vec[UInt8], Str]
pub fn usb_raw_find(u: &Usb, desc_type: Int) -> Int

pub fn usb_qualifier_present(u: &Usb) -> Bool
pub fn usb_qualifier_bcd_usb(data: &Vec[UInt8], u: &Usb) -> Int
pub fn usb_qualifier_class(data: &Vec[UInt8], u: &Usb) -> Int
pub fn usb_qualifier_subclass(data: &Vec[UInt8], u: &Usb) -> Int
pub fn usb_qualifier_protocol(data: &Vec[UInt8], u: &Usb) -> Int
pub fn usb_qualifier_max_packet0(data: &Vec[UInt8], u: &Usb) -> Int
pub fn usb_qualifier_num_configs(data: &Vec[UInt8], u: &Usb) -> Int

pub fn usb_bos_present(u: &Usb) -> Bool
pub fn usb_bos_total_length(data: &Vec[UInt8], u: &Usb) -> Int
pub fn usb_bos_num_capabilities(data: &Vec[UInt8], u: &Usb) -> Int
pub fn usb_capability_count(u: &Usb) -> Int
pub fn usb_capability_type(data: &Vec[UInt8], u: &Usb, k: Int) -> Int
pub fn usb_capability_length(u: &Usb, k: Int) -> Int
pub fn usb_capability_bytes(data: &Vec[UInt8], u: &Usb, k: Int) -> Result[Vec[UInt8], Str]
```

The `Usb` fields are public for inspection but are implementation details;
callers should prefer the accessors.

Raw header-field accessors need `data` because raw descriptors are stored
as spans. They return `-1` when the descriptor is absent, shorter than the
documented header, or the span does not fit `data`.

## Semantics

### Parsing and validation order

`usb_parse(data)` walks descriptors from offset 0, one `bLength` step at a
time. For each descriptor, in order:

1. fewer than 2 remaining bytes -> `usb: truncated descriptor header`;
2. `bLength < 2` -> `usb: bad descriptor length`;
3. `pos + bLength > data.len()` -> `usb: truncated descriptor`;
4. configuration closure: an open configuration is closed when the cursor
   reaches exactly its declared end; a descriptor starting past that end is
   `usb: configuration total length mismatch`;
5. a child descriptor that would spill past the open configuration's
   declared end -> `usb: configuration total length mismatch`;
6. a CONFIGURATION descriptor while a configuration is still open ->
   `usb: configuration total length mismatch` (the open total never closed
   exactly);
7. the descriptor is recorded in the global vectors;
8. type-specific checks and field extraction (below).

Then, after the walk, the string-index bounds pass runs in a fixed order:
device `iManufacturer`, `iProduct`, `iSerialNumber`; then every
configuration's `iConfiguration` in stream order; then every interface's
`iInterface` in stream order. A nonzero index that has no matching
STRING descriptor in the pool is `usb: string index out of range`
(index 0 means "no string" and is always valid). An empty buffer is a
valid empty store, and descriptors after a device-only stream are not
required.

Type-specific parse order:

| Type | Checks |
|---|---|
| DEVICE | a second DEVICE -> `usb: duplicate device descriptor`; `bLength != 18` -> `usb: bad device descriptor length`; fields read |
| CONFIGURATION | `bLength != 9` -> `usb: bad configuration descriptor length`; `wTotalLength < 9` or `pos + wTotalLength > data.len()` -> `usb: configuration total length out of range`; opens the configuration context |
| INTERFACE | `bLength != 9` -> `usb: bad interface descriptor length`; no open configuration -> `usb: interface outside configuration`; resets the per-interface endpoint counter |
| ENDPOINT | `bLength != 7` -> `usb: bad endpoint descriptor length`; no open interface -> `usb: endpoint outside interface`; parsed count exceeding the claim -> `usb: endpoint count exceeds interface claim` |
| STRING | odd `bLength` or `bLength < 4` -> `usb: bad string descriptor length`; the payload decodes to a pool entry |
| other | appended to the raw-preserved list |

Because descriptors tile the stream contiguously by construction, exact
`wTotalLength` coverage means the last child ends exactly at
`configuration start + wTotalLength`; a stream whose children end early
followed by another descriptor is reported by the context check of that
descriptor (e.g. an interface outside a configuration).

### String decoding policy

A STRING payload holds `(bLength - 4) / 2` text code units after the
bStringIndex unit. Each unit is mapped independently:

- `0x0020` through `0x007E` -> the identical ASCII byte;
- every other unit (control bytes, NUL, `>= 0x0080`, and each half of a
  surrogate pair separately) -> `?` (0x3F).

`usb_string_replacements(u, i)` counts those replacements per code unit, so
a surrogate pair contributes 2. The decoded text never contains a NUL byte,
which is what lets `xiom.string.builder.sb_to_str` be used safely.

### Endpoint claim tolerance

`usb_parse` requires `parsed endpoints <= bNumEndpoints` for each
interface; a stream with fewer endpoints than claimed is accepted and
`usb_interface_unlisted_endpoints` reports the difference. This is the
documented tolerance: endpoints may legitimately be omitted from a partial
dump, but a stream that lists more endpoints than the interface claims is
rejected.

### Other documented tolerances

- `bNumConfigurations` is exposed but not enforced against the number of
  parsed configurations (device-only dumps parse).
- `bNumInterfaces` is exposed but not enforced against the number of parsed
  interface descriptors (alternate settings share an interface number).
- Unknown descriptor types are preserved raw, never rejected.
- The LANGID string descriptor (index 0) is parsed like any other string.
- `usb_emit` preserves the stored `bNumEndpoints` claim even when it
  exceeds the parsed endpoint count.

### Accessor conventions

- Counts and scalar accessors return `-1` for an out-of-range index;
  `usb_string_text` returns `""`; `usb_has_device`/`usb_qualifier_present`/
  `usb_bos_present`/`usb_string_present` return `Bool`.
- `usb_string(u, sid)` looks up the pool by bStringIndex and returns
  `Err("usb: string index not found")` when absent (including index 0 when
  no descriptor declares it).
- `usb_descriptor_bytes`/`usb_raw_bytes` report
  `usb: descriptor index out of range` / `usb: raw index out of range` for a
  bad index and `usb: descriptor span out of bounds` /
  `usb: raw span out of bounds` when the recorded span does not fit the
  buffer passed in.
- `usb_capability_type`/`usb_capability_bytes` are indexed over
  DEVICE_CAPABILITY raw descriptors only; a bad `k` reports `-1` / a raw
  index error.

## Canonical form

`usb_emit(data, u)` writes:

1. the DEVICE descriptor (18 bytes) when present;
2. every configuration in stored order; for each, its CONFIGURATION
   descriptor with `wTotalLength` recomputed as
   `9 + 9 * emitted interfaces + 7 * emitted endpoints`, then its
   interfaces in stored order, each INTERFACE descriptor followed by that
   interface's ENDPOINT descriptors in stored order;
3. the string pool in stored order, each as
   `bLength = 4 + 2 * text_len`, type 3, the bStringIndex unit, then the
   decoded text as UTF-16LE units;
4. every raw-preserved descriptor in recorded order, copied verbatim from
   `data`.

Stored scalar fields (`bNumInterfaces`, `bConfigurationValue`,
`iConfiguration`, `bmAttributes`, `bMaxPower`, the interface fields, the
endpoint fields, `bNumEndpoints`) are preserved; only `wTotalLength` and
the string lengths are recomputed.

For an input that is already in this order, `usb_parse` then `usb_emit` is
byte-identical. In particular the documented canonical fixture (device,
configuration, interface, two endpoints, two ASCII strings) round-trips
exactly. Non-canonical inputs (raw descriptors placed earlier, class-
specific descriptors inside a configuration, non-ASCII strings) parse fine
and are canonicalized: raw descriptors move to the end, configuration
totals shrink to the emitted children, and replaced string units are
re-encoded as `?`.

`usb_emit` refuses a store whose parallel vectors have drifted apart,
whose referenced descriptors are missing or mistyped, whose spans do not
fit `data`, whose parent indexes are out of range, whose parsed endpoint
count exceeds a claim, or whose scalar fields are outside their byte/word
ranges: `usb: invalid store`. An empty store emits zero bytes.

## Error string catalog

| Condition | Error text |
|---|---|
| `usb_parse`: remaining bytes < 2 | `usb: truncated descriptor header` |
| `usb_parse`: `bLength < 2` | `usb: bad descriptor length` |
| `usb_parse`: `pos + bLength` past the buffer | `usb: truncated descriptor` |
| `usb_parse`: second DEVICE descriptor | `usb: duplicate device descriptor` |
| `usb_parse`: DEVICE `bLength != 18` | `usb: bad device descriptor length` |
| `usb_parse`: CONFIGURATION `bLength != 9` | `usb: bad configuration descriptor length` |
| `usb_parse`: INTERFACE `bLength != 9` | `usb: bad interface descriptor length` |
| `usb_parse`: ENDPOINT `bLength != 7` | `usb: bad endpoint descriptor length` |
| `usb_parse`: STRING odd `bLength` or `< 4` | `usb: bad string descriptor length` |
| `usb_parse`: `wTotalLength < 9` or beyond the buffer | `usb: configuration total length out of range` |
| `usb_parse`: child spills past / configuration never closes / second configuration while open | `usb: configuration total length mismatch` |
| `usb_parse`: INTERFACE with no open configuration | `usb: interface outside configuration` |
| `usb_parse`: ENDPOINT with no open interface | `usb: endpoint outside interface` |
| `usb_parse`: parsed endpoints exceed the claim | `usb: endpoint count exceeds interface claim` |
| `usb_parse`: nonzero string index not in the pool | `usb: string index out of range` |
| `usb_descriptor_bytes`: bad index | `usb: descriptor index out of range` |
| `usb_descriptor_bytes`: span outside `data` | `usb: descriptor span out of bounds` |
| `usb_raw_bytes` / `usb_capability_bytes`: bad index | `usb: raw index out of range` |
| `usb_raw_bytes` / `usb_capability_bytes`: span outside `data` | `usb: raw span out of bounds` |
| `usb_string`: no pool entry with that bStringIndex | `usb: string index not found` |
| `usb_emit`: drifted or malformed store | `usb: invalid store` |

When several problems coexist, the first one in the documented order wins
(e.g. a duplicate DEVICE is reported before its length check, a malformed
configuration total before any of its children).

## Complexity

| Operation | Complexity |
|---|---|
| `usb_parse` | O(data.len()) |
| `usb_emit` | O(stream size + configurations x interfaces + interfaces x endpoints) |
| counts and index accessors | O(1) |
| `usb_configuration_interface_count` | O(interfaces) |
| `usb_interface_endpoint_count` / `usb_endpoint_count_for_interface` | O(endpoints) |
| `usb_find_endpoint` | O(endpoints) |
| `usb_raw_find` / capability accessors | O(raw descriptors) |
| `usb_string` / `usb_string_present` | O(pool) |
| `usb_descriptor_bytes` / `usb_raw_bytes` | O(descriptor length) |

## Documented decisions (summary)

1. A stream is a complete dump; the parser validates hierarchy, coverage
   and string-index bounds, and tolerates partial endpoint lists and
   unlisted configurations/interfaces.
2. Unknown descriptor types are first-class raw data, so class-specific
   descriptors never break a parse and always re-emit.
3. String decoding is intentionally lossy (printable ASCII only) and the
   replacement count is part of the API, so callers can detect loss.
4. The emitter is canonicalizing, not preserving: descriptor order and
   recomputed totals follow the rules above.
5. `usb_emit` takes the parse buffer because the store holds spans for raw
   descriptors and checks decoded-string length consistency against the
   recorded bLength.

## Test plan

`tests/test_conformance.xi` (`module usb_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Fixtures are hand-built hex literals:

- canonical 78-byte stream: DEVICE (`bcdUSB` 0x0200, vendor 0x1234,
  product 0x5678, `bcdDevice` 0x0100, iManufacturer 1, iProduct 2, one
  configuration), CONFIGURATION (total 32, value 1, attributes 0x80, max
  power 0x32), INTERFACE 0 alt 0 (claim 2, class 8, subclass 6, protocol
  0x50), endpoint 0x81 and endpoint 0x02 (bulk, 512 bytes, interval 0),
  STRING 1 "ACME" and STRING 2 "Widget";
- device-only stream (bNumConfigurations 1, no configuration);
- device with iProduct 2 but no STRING 2;
- device plus raw DEVICE_QUALIFIER, BOS and one DEVICE_CAPABILITY;
- device with iProduct 1 plus a STRING whose units are 'A', U+00E9,
  U+0009, U+D83D, U+DE00.

1. device fields are pinned (all 12);
2. configuration fields are pinned (total/num interfaces/value/istring/
   attributes/max power/actual interface count, out-of-range `-1`);
3. interface fields are pinned (configuration ordinal, number, alt, claim,
   actual count, unlisted, class/subclass/protocol/istring);
4. endpoint fields by interface (address, attributes, max packet,
   interval, ownership, `usb_find_endpoint`);
5. string pool: two entries, bStringIndex, decoded text, replacements,
   `usb_string` by index, missing index and out-of-range pool accessors;
6. canonical round-trip: parse -> emit is byte-identical (78 bytes) and
   reparse keeps the fields;
7. raw spans: three raw descriptors with pinned types/offsets/lengths,
   `usb_raw_find`, raw bytes, out-of-range error;
8. qualifier/BOS/capability header fields and byte-exact raw round-trip;
9. replacement fixture: text "A????", 4 replacements, lookup by index;
10. global descriptor spans: count 7, pinned types/lengths/offsets,
    descriptor bytes, out-of-range and short-buffer errors;
11. truncated header / bad bLength / truncated descriptor;
12. wrong per-type lengths (device 17, duplicate device, config 8,
    interface 8, endpoint 6, string 3 and string 2);
13. `wTotalLength` out of range (below 9, beyond the buffer) and mismatch
    (child spill);
14. interface outside configuration; endpoint outside interface;
15. endpoint claim: exceed is rejected; claim 3 with 2 endpoints is
    tolerated (claim/count/unlisted accessors) and round-trips;
16. string index bounds: missing device string and missing configuration
    string;
17. empty stream parses to an empty store (all counts zero, accessors
    `-1`/empty, empty emit);
18. device-only dump parses (`bNumConfigurations` not enforced) and
    round-trips;
19. emitter guards: short buffer, drifted interface vector, out-of-range
    raw reference are `usb: invalid store`; the good store still emits;
20. aggregate counts agree with the fixture (endpoint claims, actual
    counts, endpoint packet fields).

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.usb
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- The documented subset only; class-specific and unknown descriptors are
  never interpreted.
- No builder API from scratch: `usb_emit` requires a `usb_parse` store and
  the original buffer.
- String decoding replaces non-ASCII and cannot recover the original
  UTF-16LE units from the store (only from the source span).
- The raw header accessors do not validate the raw descriptor's type
  semantics beyond presence and length.
- `bNumConfigurations`/`bNumInterfaces` are not enforced; a dump cut in
  the middle of a configuration is rejected only by the coverage rules.
- `Usb` is a plain value type built from parallel vectors; callers can
  corrupt its invariants, and `usb_emit` rejects such stores instead of
  repairing them.
- Spans and decoded texts are tied to the parse buffer; accessors and the
  emitter need that buffer to stay alive.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_usb`/`_err_usb`/`_ok_bytes`/`_err_bytes`/`_ok_str`/`_err_str`
  (constructing struct payloads such as `Result[Usb, Str]` directly in
  other functions miscompiles).
- Vector-of-struct is avoided entirely: the store is 43 flat scalar/vector
  fields, each push mirrored on every sibling vector, and `usb_emit`
  refuses drifted stores (`usb: invalid store`).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF`; all
  little-endian packing is arithmetic (`_u_byte` extracts the byte by
  division/modulo with two's-complement correction), so values with bit 31
  set pack correctly.
- Every `Vec[Int]` element read is bound to a typed local; Str values read
  from `Vec[Str]` are bound to typed locals and compared through
  `xiom.string.compare.str_compare` (BUG 17: `==` on a `Vec`-sourced Str
  lowers to a pointer comparison).
- Decoded strings never contain `0x00`, so
  `xiom.string.builder.sb_to_str` never sees a NUL byte.
- `usb_emit`'s well-formedness guard checks decoded text length against
  the recorded bLength before iterating (`str_len` on a typed local is
  exact on this compiler).
- All parameter type brackets are `Vec[...]` / `Result[...]`; a grep audit
  for `Vec\s*<` / `Result\s*<` after the final green run found none (the
  v0.61.3 compiler accepts malformed angle-bracket parameter types
  silently).
- The package declares no `extern "C"` blocks (no FFI).
