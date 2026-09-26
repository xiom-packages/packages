# xiom.usb

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM USB descriptor-stream codec for a documented subset:
> device, configuration, interface, endpoint and string descriptors parsed
> into a hierarchy with parent links, plus raw-preserved device-qualifier,
> BOS and device-capability descriptors and a canonical emitter.
> **Deps:** `xiom.std` only. The library module uses `xiom.string` and
> `xiom.string.builder`; the tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

## What it is

`xiom.usb` parses a USB descriptor stream (the flat sequence of
self-describing descriptors a device returns for a descriptor dump) into a
flat `Usb` store of parallel vectors with parent links:
device -> configurations -> interfaces -> endpoints, plus a
string-descriptor pool. Every descriptor keeps its absolute byte span, so
unknown or deliberately uninterpreted descriptors (device qualifier, BOS,
device capabilities, class-specific types) are preserved raw and can be
re-emitted verbatim. `usb_emit` rebuilds the canonical stream for a parsed
store; parsing a canonical stream and emitting it again is byte-identical.

Structured descriptors are validated strictly: exact per-type lengths,
configuration `wTotalLength` covering its children exactly, interfaces
inside a configuration, endpoints inside an interface, and the endpoint
count never exceeding the interface's `bNumEndpoints` claim (fewer is a
documented tolerance). String descriptors are UTF-16LE decoded to printable
ASCII with a documented replacement policy: units `0x0020..0x007E` map to
themselves, every other unit becomes `?`.

## API

| Function | Returns | Description |
|---|---|---|
| `usb_parse(data)` | `Result[Usb, Str]` | Validate a descriptor stream into a flat store. |
| `usb_emit(data, u)` | `Result[Vec[UInt8], Str]` | Rebuild the canonical stream for a parsed store. |

Descriptor spans:

| Function | Returns | Description |
|---|---|---|
| `usb_descriptor_count(u)` | `Int` | Number of descriptors (structured plus raw). |
| `usb_descriptor_type/length/offset(u, i)` | `Int` | Header field / absolute offset; `-1` out of range. |
| `usb_descriptor_bytes(data, u, i)` | `Result[Vec[UInt8], Str]` | Copy descriptor `i`'s bytes (header included). |

Device:

| Function | Returns | Description |
|---|---|---|
| `usb_has_device(u)` | `Bool` | Stream contained a DEVICE descriptor. |
| `usb_device_bcd_usb/class/subclass/protocol/max_packet0/vendor/product/bcd_device/imanufacturer/iproduct/iserial/num_configurations(u)` | `Int` | DEVICE fields; `-1` when absent. |

Configuration and interface:

| Function | Returns | Description |
|---|---|---|
| `usb_configuration_count(u)` | `Int` | Number of CONFIGURATION descriptors. |
| `usb_configuration_total_length/num_interfaces/value/istring/attributes/max_power(u, c)` | `Int` | CONFIGURATION fields (`max_power` in 2 mA units). |
| `usb_configuration_interface_count(u, c)` | `Int` | Interfaces actually present in configuration `c`. |
| `usb_interface_count(u)` | `Int` | Number of INTERFACE descriptors. |
| `usb_interface_configuration/number/alternate/endpoint_claim/endpoint_count/unlisted_endpoints/class/subclass/protocol/istring(u, i)` | `Int` | INTERFACE fields and endpoint-count accounting. |

Endpoint and string:

| Function | Returns | Description |
|---|---|---|
| `usb_endpoint_count(u)` | `Int` | Number of ENDPOINT descriptors. |
| `usb_endpoint_interface/address/attributes/max_packet/interval(u, e)` | `Int` | ENDPOINT fields. |
| `usb_endpoint_count_for_interface(u, i)` | `Int` | Endpoints owned by interface `i`. |
| `usb_find_endpoint(u, i, address)` | `Int` | First endpoint of `i` with that address, or `-1`. |
| `usb_string_count(u)` | `Int` | String-pool entries (stream order). |
| `usb_string_index/text/replacements(u, i)` | `Int` / `Str` / `Int` | Pool entry `i` (bStringIndex, decoded text, replaced-unit count). |
| `usb_string_present(u, sid)` | `Bool` | A pool entry with bStringIndex `sid` exists. |
| `usb_string(u, sid)` | `Result[Str, Str]` | Decoded text by bStringIndex. |

Raw-preserved descriptors:

| Function | Returns | Description |
|---|---|---|
| `usb_raw_count/type/length/offset(u, i)` | `Int` | Raw list entry fields; `-1` out of range. |
| `usb_raw_bytes(data, u, i)` | `Result[Vec[UInt8], Str]` | Copy a raw descriptor's bytes. |
| `usb_raw_find(u, desc_type)` | `Int` | First raw ordinal of a type, or `-1`. |
| `usb_qualifier_present(u)`, `usb_qualifier_bcd_usb/class/subclass/protocol/max_packet0/num_configs(data, u)` | `Bool` / `Int` | DEVICE_QUALIFIER header fields. |
| `usb_bos_present(u)`, `usb_bos_total_length/num_capabilities(data, u)` | `Bool` / `Int` | BOS header fields. |
| `usb_capability_count(u)`, `usb_capability_type/length/bytes(...)` | `Int` / `Result` | DEVICE_CAPABILITY spans and type. |

Errors: `usb: truncated descriptor header`, `usb: bad descriptor length`,
`usb: truncated descriptor`, `usb: duplicate device descriptor`,
`usb: bad device descriptor length`, `usb: bad configuration descriptor
length`, `usb: bad interface descriptor length`, `usb: bad endpoint
descriptor length`, `usb: bad string descriptor length`, `usb:
configuration total length out of range`, `usb: configuration total length
mismatch`, `usb: interface outside configuration`, `usb: endpoint outside
interface`, `usb: endpoint count exceeds interface claim`, `usb: string
index out of range`, `usb: descriptor index out of range`, `usb:
descriptor span out of bounds`, `usb: raw index out of range`, `usb: raw
span out of bounds`, `usb: string index not found`, `usb: invalid store`
(see SPEC.md for the exact conditions).

## Usage

```xi
use xiom.usb;
use xiom.io;
use xiom.convert;

let dump = /* device + configuration + interface + endpoints + strings */;
let r = usb_parse(&dump);
match r {
  Ok(u) => {
    if usb_has_device(&u) {
      io.println("vendor: " + convert.int_to_string(usb_device_vendor(&u)));
    }
    let c = usb_configuration_count(&u);
    var i = 0;
    while i < c {
      io.println("config " + convert.int_to_string(i) + " total " + convert.int_to_string(usb_configuration_total_length(&u, i)));
      i = i + 1;
    }
    let s = usb_string(&u, usb_device_iproduct(&u));
    if s.is_ok {
      io.println("product: " + s.value);
    }
    let e = usb_emit(&dump, &u);   // canonical bytes
  },
  Err(msg) => { io.println("usb: " + msg); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.usb
```

Expected: the namespace check passes, 20 `[PASS]` lines, and a final
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Documented subset only.** HID report descriptors, class-specific
  descriptor semantics and transfers/speed negotiation are not interpreted;
  class-specific/unknown types are preserved raw.
- **String decoding is lossy by design.** Non-ASCII UTF-16LE units become
  `?`; `usb_emit` re-encodes the decoded ASCII, so a stream containing
  non-ASCII strings is canonicalized (count the replacements through
  `usb_string_replacements`).
- **Configuration coverage is exact.** `wTotalLength` must tile exactly
  from the configuration header to its end; a stream whose declared total
  disagrees with its children is rejected.
- **Claims are only partly enforced.** `bNumEndpoints` is an upper bound
  for the parsed endpoints (fewer is tolerated); `bNumConfigurations` and
  `bNumInterfaces` are exposed but not enforced (partial dumps and
  alternate settings).
- **No builder from scratch.** `usb_emit` requires a store produced by
  `usb_parse` and the parse buffer, because descriptors are stored as
  spans.
- `Usb` is a plain value type built from parallel vectors; callers can
  corrupt its invariants, and `usb_emit` rejects such stores
  (`usb: invalid store`) instead of repairing them.
- Not thread-safe; single-pass in-memory parsing only.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
