# xiom.pci

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM PCI configuration-space codec for one function's
> 256-byte block: identification, command/status bits, type-0 BARs,
> type-1 bridge windows, the capability-list walk and a canonical type-0
> builder.
> **Deps:** `xiom.std` only. The library module imports nothing from it (all
> names it returns are literals); the tests use `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

## What it is

`xiom.pci` decodes the standard 256-byte PCI configuration space of a single
function: vendor/device and class bytes, the command/status words with
documented bit predicates (I/O space, memory space, bus master, SERR#,
interrupt disable; capability list, 66 MHz, fast back-to-back, interrupt
status, parity error), cache line size, latency timer, header type (bit 7
multi-function plus kinds 0x00/0x01/0x02) and BIST.

Type-0 functions get BAR0..BAR5 decoding: raw register, memory vs I/O kind,
32/64-bit memory type, masked base address (a 64-bit memory BAR combines the
next slot's upper half) and a lowest-set-bit size proxy (always 0 or a power
of two). The CardBus CIS pointer, subsystem vendor/device IDs and expansion
ROM BAR round out the type-0 header. Type-1 PCI-to-PCI bridges get their
primary/secondary/subordinate bus numbers, secondary status, I/O (4 KiB
granularity) and memory/prefetchable (1 MiB granularity) window bases and
limits, and bridge control.

The capability walk starts from status bit 4, follows the pointer chain at
0x34 and records parallel id/offset/span columns in walk order. Pointers must
be 0x40..0xFF and aligned to 4; next pointers must be strictly increasing, so
loops and duplicate revisits are reported as `pci: capability loop`. PM
(0x01), MSI (0x05) and PCIe (0x10) have documented field accessors; every
other ID (including MSI-X) stays preserved raw and readable through the
generic `pci_cap_read_u8/u16/u32` readers.

`pci_build_type0` writes a canonical 256-byte type-0 header with no
capability list, and `pci_serialize(pci_parse(x).value)` reproduces the first
256 bytes of `x` exactly.

## API

| Function | Returns | Description |
|---|---|---|
| `pci_parse(data)` | `Result[PciFunction, Str]` | Copy 256 bytes and walk the capability list (kinds 0x00/0x01, status bit 4). |
| `pci_serialize(f)` | `Vec[UInt8]` | Exact copy of the stored raw bytes. |
| `pci_raw_byte(f, off)` | `Int` | Byte at `off` (0..255), or -1 out of range. |
| `pci_is_populated(f)` | `Bool` | Vendor ID != 0xFFFF (documented population rule). |
| `pci_vendor_id` / `pci_device_id` | `Int` | Identification words. |
| `pci_command` / `pci_status` | `Int` | Raw words; five bit predicates each. |
| `pci_revision_id` / `pci_prog_if` / `pci_subclass` / `pci_class_code` | `Int` | Class bytes. |
| `pci_cache_line_size` / `pci_latency_timer` / `pci_bist` | `Int` | Header bytes. |
| `pci_header_type` / `pci_header_kind` / `pci_multifunction` | `Int`/`Int`/`Bool` | Header byte, kind (bit 7 stripped) and bit 7 flag. |
| `pci_class_name(code)` / `pci_header_kind_name(kind)` / `pci_cap_name(id)` | `Str` | Documented partial name tables. |
| `pci_bar_raw(f, i)` | `Int` | Raw 32-bit BAR slot (kind-gated: 0..5 / 0..1 / slot 0 / none). |
| `pci_bar_kind(f, i)` | `Int` | 0 = memory, 1 = I/O, -1 invalid. |
| `pci_bar_memory_type(f, i)` | `Int` | 0 = 32-bit, 2 = 64-bit, 1/3 reserved, -1 I/O. |
| `pci_bar_is_64` / `pci_bar_is_upper` | `Bool` | 64-bit decode; upper half of the previous slot. |
| `pci_bar_address(f, i)` | `Int` | Base address with flag bits masked off. |
| `pci_bar_size(f, i)` | `Int` | Lowest set bit of the address (0 or a power of two). |
| `pci_cardbus_cis` / `pci_subsystem_vendor_id` / `pci_subsystem_device_id` | `Int` | Type-0 fields. |
| `pci_expansion_rom_raw` / `_enabled` / `_address` | `Int`/`Bool`/`Int` | Expansion ROM BAR (kind 0 at 0x30, kind 1 at 0x38). |
| `pci_bridge_primary_bus` / `_secondary_bus` / `_subordinate_bus` / `_secondary_status` / `_control` | `Int` | Type-1 fields, raw. |
| `pci_bridge_io_base` / `_io_limit` | `Int` | I/O window, 4 KiB granularity. |
| `pci_bridge_memory_base` / `_memory_limit` | `Int` | Memory window, 1 MiB granularity. |
| `pci_bridge_prefetchable_base` / `_prefetchable_limit` | `Int` | Prefetchable window, 1 MiB granularity. |
| `pci_bridge_io_is_32bit(f)` | `Bool` | I/O base bit 0 (32-bit I/O indicator). |
| `pci_cap_count` / `pci_cap_id` / `pci_cap_offset` / `pci_cap_span` / `pci_cap_find` | `Int` | Capability columns in walk order. |
| `pci_cap_read_u8` / `_u16` / `_u32` | `Int` | Span-bounded little-endian reads at `rel` from a capability header. |
| `pci_cap_pm_version` / `_pm_control` | `Int` | PM (0x01) subset. |
| `pci_cap_msi_control` / `_msi_64bit` / `_msi_address` / `_msi_data` | `Int`/`Bool`/`Int`/`Int` | MSI (0x05) subset. |
| `pci_cap_pcie_version` / `_pcie_device_caps` | `Int` | PCIe (0x10) subset. |
| `pci_build_type0(cfg)` | `Result[Vec[UInt8], Str]` | Canonical 256-byte type-0 header (no capability list). |

Errors: `pci: truncated config space`, `pci: bad capability pointer`,
`pci: capability loop`, `pci: bar count`, `pci: bad word field`,
`pci: bad byte field`, `pci: bad dword field`,
`pci: capability list bit set` (see SPEC.md for exact conditions).

## Usage

```xi
use xiom.pci;
use xiom.io;

// space: the 256-byte configuration space of one function.
let r = pci_parse(&space);
if r.is_ok {
  let f: PciFunction = r.value;
  if pci_is_populated(&f) {
    io.println("vendor " + xiom.convert.int_to_string(pci_vendor_id(&f)));
    if pci_bar_kind(&f, 0) == 0 {
      io.println("BAR0 address " + xiom.convert.int_to_string(pci_bar_address(&f, 0)));
      io.println("BAR0 size    " + xiom.convert.int_to_string(pci_bar_size(&f, 0)));
    }
    let n: Int = pci_cap_count(&f);
    var i = 0;
    while i < n {
      io.println("cap " + xiom.convert.int_to_string(pci_cap_id(&f, i)));
      i = i + 1;
    }
  }
} else {
  io.println("parse error: " + r.error);
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.pci
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **One function per parse.** Function numbers are not part of the 256-byte
  block; call `pci_parse` once per function of interest.
- **No live sizing.** `pci_bar_size` is the lowest set bit of the saved
  value; it is the true size only for saved sizing values, otherwise the
  address alignment.
- **Strictly increasing capability chains.** An unsorted chain is rejected
  as `pci: capability loop`; spans are only meaningful for increasing chains.
- **Bounded capability spans.** The last capability's span runs to byte 256;
  the true register-block length of an unknown capability is unknown.
- **Bridge windows are low-part only.** 64-bit prefetchable and 32-bit I/O
  upper registers are not combined. CardBus (kind 0x02) header registers are
  not decoded (its slot 0 is still readable as a BAR).
- **No MSI-X table parsing** and no PCIe extended configuration space; IDs
  outside the documented table stay raw.
- **Partial name tables.** Class codes 0x00..0x13/0x40/0xFF, capability IDs
  0x01/0x05/0x10, nothing more.
- Not thread-safe; `PciFunction` is a plain value type (one raw byte vector
  plus three capability vectors, no `Vec` of structs).

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
