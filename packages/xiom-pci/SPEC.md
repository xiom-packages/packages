# xiom.pci -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.pci`, version `0.1.0`).
Module: `src/pci.xi` (`module xiom.pci`).
Depends on `xiom.std`; the library module imports nothing from it (every name
it returns is a literal). Tests additionally use `xiom.test`, `xiom.io`,
`xiom.string.compare` and `xiom.encoding.hex`.

## 1. Scope

A pure-XIOM (no FFI) codec for one PCI function's 256-byte configuration
space:

- `pci_parse` copies the 256 bytes and indexes the capability list when the
  status word declares one;
- accessors for identification (vendor/device, class/subclass/revision, prog
  IF), the command/status words with documented bit predicates (I/O space,
  memory space, bus master, SERR#, interrupt disable; capability list,
  66 MHz, fast back-to-back, interrupt status, master data parity error),
  cache line size, latency timer, header type (bit 7 multi-function plus the
  documented header kinds 0x00/0x01/0x02), and BIST;
- type-0 BAR0..BAR5: raw register, kind (memory/I/O), memory type
  (32/64-bit/reserved), 64-bit/upper-half predicates, masked base address
  (I/O drops bits 1..0, memory drops bits 3..0, a 64-bit memory BAR adds the
  next slot's upper 32 bits) and a lowest-set-bit size proxy;
- type-0 extras: CardBus CIS pointer, subsystem vendor/device ID, expansion
  ROM BAR (enable flag, masked address);
- type-1 PCI-to-PCI bridge: primary/secondary/subordinate bus numbers,
  secondary status, I/O (4 KiB granularity) and memory/prefetchable
  (1 MiB granularity) window bases and limits, bridge control raw;
- capability walk from status bit 4: parallel id/offset/span columns in walk
  order with pointer range/alignment checks, loop/duplicate detection, and
  documented subsets for PM (0x01), MSI (0x05) and PCIe (0x10); unknown
  capability IDs stay preserved raw and readable through generic readers;
- `pci_build_type0` writes a canonical type-0 header (no capability list);
- documented `pci_class_name`, `pci_header_kind_name` and `pci_cap_name`
  partial name tables and a deterministic `Err(Str)` catalog.

All APIs are buffer-in / buffer-out: nothing touches OS device I/O.

## 2. Non-goals

- **No OS/device I/O.** The codec never writes to or reads from real
  configuration space; it only decodes bytes the caller supplies.
- **No MSI-X table parsing.** Capability ID 0x11 is not interpreted (it is
  preserved raw like any unknown ID); the MSI-X table/BIR region is never
  followed.
- **No PCIe extended configuration space.** Bytes 256..4095 are out of
  scope; only the first 256 bytes of a function are modeled.
- **No class-code registry** beyond the `pci_class_name` table in section 8.
- **No CardBus (kind 0x02) register decoding.** Kind 0x02 is recognized and
  its slot 0 (socket/ExCA base) is still decodable as a BAR, but the
  CardBus-specific header registers are not interpreted.
- **No 64-bit bridge window upper registers.** The prefetchable base/limit
  upper 32-bit registers (0x28/0x2C) and the 32-bit I/O upper 16-bit
  registers (0x30/0x32) are not combined into the decoded windows.
- **No BAR sizing probe.** A saved configuration space cannot contain a
  probed size unless the caller saved a sizing value; see section 5.
- No FFI, no registry integration, no thread safety.

## 3. Configuration-space layout (256 bytes)

| Offset | Size | Field | Decoded by |
|---|---|---|---|
| 0x00 | 2 | vendor ID (LE16) | `pci_vendor_id` |
| 0x02 | 2 | device ID (LE16) | `pci_device_id` |
| 0x04 | 2 | command (LE16) | `pci_command`, bit predicates |
| 0x06 | 2 | status (LE16) | `pci_status`, bit predicates |
| 0x08 | 1 | revision ID | `pci_revision_id` |
| 0x09 | 1 | programming interface | `pci_prog_if` |
| 0x0A | 1 | sub-class code | `pci_subclass` |
| 0x0B | 1 | base class code | `pci_class_code`, `pci_class_name` |
| 0x0C | 1 | cache line size | `pci_cache_line_size` |
| 0x0D | 1 | latency timer | `pci_latency_timer` |
| 0x0E | 1 | header type | `pci_header_type`, `pci_header_kind`, `pci_multifunction` |
| 0x0F | 1 | BIST | `pci_bist` |
| 0x10..0x27 | 24 | BAR0..BAR5 (type 0) | BAR accessors (section 5) |
| 0x28 | 4 | CardBus CIS (type 0) | `pci_cardbus_cis` |
| 0x2C/0x2E | 2+2 | subsystem vendor/device ID (type 0) | `pci_subsystem_vendor_id`, `pci_subsystem_device_id` |
| 0x30 | 4 | expansion ROM BAR (type 0) | `pci_expansion_rom_*` |
| 0x18 | 1 | primary bus (type 1) | `pci_bridge_primary_bus` |
| 0x19 | 1 | secondary bus (type 1) | `pci_bridge_secondary_bus` |
| 0x1A | 1 | subordinate bus (type 1) | `pci_bridge_subordinate_bus` |
| 0x1C/0x1D | 1+1 | I/O base/limit (type 1) | `pci_bridge_io_base/_limit` |
| 0x1E | 2 | secondary status (type 1) | `pci_bridge_secondary_status` |
| 0x20/0x22 | 2+2 | memory base/limit (type 1) | `pci_bridge_memory_base/_limit` |
| 0x24/0x26 | 2+2 | prefetchable base/limit (type 1) | `pci_bridge_prefetchable_base/_limit` |
| 0x38 | 4 | expansion ROM BAR (type 1) | `pci_expansion_rom_*` |
| 0x3E | 2 | bridge control (type 1) | `pci_bridge_control` |
| 0x34 | 1 | capability pointer (kinds 0x00/0x01) | `pci_parse` walk |
| 0x40..0xFF | 192 | capability list region | section 6 |

The implementation stores the whole 256-byte block verbatim (`raw`) and
decodes on demand, so every accessor is a pure function of the stored bytes.
Type-1 0x3E..0x3F is only exposed as bridge control for kind 0x01; for type-0
those bytes are Min_Gnt/Max_Lat and are not exposed.

### 3.1 Header type

`pci_header_type` returns 0x00..0xFF raw. Bit 7 is the multi-function flag
(`pci_multifunction`, documented value 0x80 when set on a type-0 function);
`pci_header_kind` returns the low seven bits:

| Kind | Meaning | Decoded |
|---|---|---|
| 0x00 | type-0 device | BAR0..5, CIS, subsystem, expansion ROM |
| 0x01 | PCI-to-PCI bridge | BAR0/1, bus numbers, windows, bridge control |
| 0x02 | CardBus bridge | slot 0 only; no CardBus registers (non-goal) |
| other | unknown | nothing kind-specific; raw bytes stay readable |

### 3.2 Command and status bits

| Word | Bit | Predicate |
|---|---|---|
| command | 0 | `pci_command_io_enabled` |
| command | 1 | `pci_command_memory_enabled` |
| command | 2 | `pci_command_bus_master_enabled` |
| command | 8 | `pci_command_serr_enabled` |
| command | 10 | `pci_command_interrupt_disabled` |
| status | 3 | `pci_status_interrupt_pending` |
| status | 4 | `pci_has_capability_list` |
| status | 5 | `pci_status_66mhz_capable` |
| status | 7 | `pci_status_fast_back_to_back` |
| status | 8 | `pci_status_master_data_parity_error` |

Bits are extracted arithmetically (`(v / 2^k) % 2 == 1`); no shift or
large-mask operation is used (section 13).

## 4. Population rule

`pci_is_populated` is true when the vendor ID is **not** 0xFFFF, the standard
"no device" encoding. A vendor ID of 0x0000 is unusual but counts as
populated. `pci_parse` never rejects 0xFFFF: an empty slot is valid
configuration space. A hand-built function whose raw buffer is shorter than
256 bytes is "not populated" and every scalar accessor returns -1 (or false).

## 5. BAR decoding (type-0 layout)

Slot validity follows the header kind: all six slots on kind 0x00, slots 0..1
on kind 0x01 (0x18..0x27 are bridge registers there), slot 0 on kind 0x02,
none on any other kind. `pci_bar_raw(f, i)` on an invalid slot returns -1.

Flag bit 0 selects the kind:

| `pci_bar_kind` | bit 0 | Meaning |
|---|---|---|
| 0 | 0 | memory space |
| 1 | 1 | I/O space |

Memory type bits 1..2 (`pci_bar_memory_type`):

| Value | Meaning |
|---|---|
| 0 | 32-bit memory decode |
| 2 | 64-bit memory decode (the next slot holds bits 63..32) |
| 1, 3 | reserved (reported raw, masked like a 32-bit memory BAR) |

Base-address masking (`pci_bar_address`, arithmetic only):

- I/O BAR: `raw - raw % 4` (bits 1..0, including the reserved bit 1, drop).
- Memory BAR: `raw - raw % 16` (bits 3..0 drop: bit 0 is the kind, bits 1..2
  the type, bit 3 the prefetchable flag).
- 64-bit memory BAR: `(raw - raw % 16) + upper * 2^32`, where `upper` is the
  next slot's raw value; slot 5 has no next slot, so a 64-bit type there
  decodes its low half only (documented edge).

`pci_bar_is_64` is true for a memory slot with type bits 2. `pci_bar_is_upper`
is true when slot `i >= 1` and slot `i - 1` is 64-bit; the upper half is not
an independent BAR, so `pci_bar_address` and `pci_bar_size` return -1 for it
(its raw value stays readable).

### 5.1 Size proxy (power-of-two behavior)

`pci_bar_size` returns the **lowest set bit** of the masked base address: the
largest power of two that divides it. Properties, all documented:

- the result is always 0 or a power of two (never any other value);
- an unassigned BAR (address 0) returns 0;
- on a saved **sizing value** (the value read back after writing all ones, in
  which every address bit above the size is 0) the lowest set bit is exactly
  the probed size; on a live base address it is the address **alignment**, a
  lower bound on the size;
- the lowest set bit is computed with divisor/modulo arithmetic
  (`while v % (a * 2) == 0 { a = a * 2 }`), never with shifts, so values with
  bit 31 set are exact (the compiler miscompiles `& 0xFF` on such operands);
- a 64-bit address with bit 63 set comes out negative (two's complement) and
  its lowest set bit is still exact; the doubling stops at 2^62, so the
  two's-complement minimum (-2^63) reports 2^62.

## 6. Capability walk

The walk runs only when status bit 4 is set **and** the header kind is 0x00
or 0x01 (both use the pointer at 0x34). For kind 0x02 and unknown kinds the
walk is skipped and the three capability columns stay empty, even though
`pci_has_capability_list` still reports the raw status bit.

Pointer rules:

- the first pointer and every next pointer must be in **0x40..0xFF** and a
  **multiple of 4**, else `pci: bad capability pointer`;
- next pointers must be **strictly increasing**: a pointer that is not
  greater than the current offset (a self-loop, a backward pointer, or any
  pointer that would revisit an earlier capability) is `pci: capability
  loop`; the finite increasing walk therefore always terminates.

Each capability gets three parallel columns:

- `pci_cap_id(i)` - the ID byte at the pointer;
- `pci_cap_offset(i)` - the pointer;
- `pci_cap_span(i)` - the distance to the next capability, or 256 - offset
  for the last one (a bounded region, not a guaranteed register-block size).

`pci_cap_count` is the minimum of the three column lengths (equal after a
parse). `pci_cap_find(id)` returns the first entry in walk order, -1 when
absent. Unknown capability IDs are preserved: `pci_cap_read_u8/u16/u32(f, i,
rel)` read little-endian fields at `rel` bytes from a capability header,
bounded by its span.

### 6.1 Documented capability subsets

| ID | Capability | Fields decoded |
|---|---|---|
| 0x01 | Power Management | version = PMC (LE16 at rel 2) bits 2..0; PMCSR (LE16 at rel 4) |
| 0x05 | MSI | message control (LE16 at rel 2; bit 7 = 64-bit); message address = LE32 at rel 4 (plus LE32 at rel 8 when 64-bit); message data = LE16 at rel 8 (32-bit) or rel 12 (64-bit) |
| 0x10 | PCI Express | version = capability register (LE16 at rel 2) bits 3..0; device capabilities (LE32 at rel 4) |

Every subset accessor returns -1 when the index is out of range, the ID does
not match, or the span does not cover the field; `pci_cap_msi_64bit` returns
false in those cases. All other IDs (including 0x09 vendor-specific and 0x11
MSI-X) are raw-preserved through the generic readers and the raw buffer.

## 7. Dynamic-validation rules

- `pci_parse`: `data.len()` must be at least 256 -> `pci: truncated config
  space`; the first 256 bytes are copied and any extra bytes are ignored.
- Capability pointers: 0x40..0xFF, multiple of 4 -> `pci: bad capability
  pointer`; strictly increasing -> `pci: capability loop` (section 6).
- Vendor ID 0xFFFF is **not** an error; it is the documented population rule
  (section 4).
- BAR sizes are powers of two by construction (section 5.1); no other size
  value is ever returned.
- A parsed function always has `raw.len() == 256` and three equal-length
  capability columns.

## 8. Documented name tables

`pci_class_name(code)` (partial table; every other code returns ""):

| Code | Name | Code | Name |
|---|---|---|---|
| 0x00 | Unclassified | 0x0B | Processor |
| 0x01 | Mass storage controller | 0x0C | Serial bus controller |
| 0x02 | Network controller | 0x0D | Wireless controller |
| 0x03 | Display controller | 0x0E | Intelligent controller |
| 0x04 | Multimedia controller | 0x0F | Satellite communications controller |
| 0x05 | Memory controller | 0x10 | Encryption controller |
| 0x06 | Bridge | 0x11 | Signal processing controller |
| 0x07 | Communication controller | 0x12 | Processing accelerators |
| 0x08 | Generic system peripheral | 0x13 | Non-Essential Instrumentation |
| 0x09 | Input device controller | 0x40 | Coprocessor |
| 0x0A | Docking station | 0xFF | Unassigned class |

`pci_header_kind_name(kind)`: 0 = "device", 1 = "bridge", 2 = "cardbus",
anything else "".

`pci_cap_name(id)`: 0x01 = "Power Management", 0x05 = "MSI",
0x10 = "PCI Express", anything else "".

## 9. Builder rules and canonical output

`pci_build_type0(cfg)` validates in this order (first failure wins):

1. `cfg.bars.len() != 6` -> `pci: bar count`;
2. the six 16-bit words (vendor, device, command, status, subsystem vendor,
   subsystem device) outside 0..65535 -> `pci: bad word field`;
3. the seven 8-bit fields (revision, prog IF, subclass, class code, cache
   line size, latency timer, BIST) outside 0..255 -> `pci: bad byte field`;
4. BAR0..BAR5 in order, then CardBus CIS and expansion ROM, outside
   0..2^32-1 -> `pci: bad dword field`;
5. status bit 4 set -> `pci: capability list bit set` (the canonical builder
   emits no capability list, so 0x34 would be 0 and the claim would be
   inconsistent).

Canonical output (exactly 256 bytes, all values raw, no masking applied):

| Offset | Bytes written |
|---|---|
| 0x00..0x0F | vendor/device/command/status LE16, revision/prog IF/subclass/class, cache line, latency, header type (0x80 if multi-function else 0x00), BIST |
| 0x10..0x27 | the six BAR values as LE32 |
| 0x28 | CardBus CIS as LE32 |
| 0x2C/0x2E | subsystem vendor/device IDs as LE16 |
| 0x30 | expansion ROM BAR as LE32 |
| 0x34..0xFF | all zero (capability pointer 0, no interrupt line/pin/Min_Gnt/Max_Lat, no capabilities) |

`pci_serialize(f)` returns a copy of the stored raw bytes; for a parsed
function `pci_serialize(pci_parse(x).value)` equals the first 256 bytes of
`x` exactly (round-trip).

## 10. API signatures

All functions are free functions in module `xiom.pci` (no self methods):

```xi
pub type PciFunction = {
  raw: Vec[UInt8];
  cap_ids: Vec[Int];
  cap_offsets: Vec[Int];
  cap_spans: Vec[Int];
}

pub type PciType0Config = {
  vendor_id: Int; device_id: Int; command: Int; status: Int;
  revision_id: Int; prog_if: Int; subclass: Int; class_code: Int;
  cache_line_size: Int; latency_timer: Int; bist: Int;
  multifunction: Bool; bars: Vec[Int];
  cardbus_cis: Int; subsystem_vendor_id: Int; subsystem_device_id: Int;
  expansion_rom: Int;
}

pub fn pci_parse(data: &Vec[UInt8]) -> Result[PciFunction, Str]
pub fn pci_serialize(f: &PciFunction) -> Vec[UInt8]
pub fn pci_raw_byte(f: &PciFunction, off: Int) -> Int
pub fn pci_is_populated(f: &PciFunction) -> Bool

pub fn pci_vendor_id(f: &PciFunction) -> Int
pub fn pci_device_id(f: &PciFunction) -> Int
pub fn pci_command(f: &PciFunction) -> Int
pub fn pci_status(f: &PciFunction) -> Int
pub fn pci_revision_id(f: &PciFunction) -> Int
pub fn pci_prog_if(f: &PciFunction) -> Int
pub fn pci_subclass(f: &PciFunction) -> Int
pub fn pci_class_code(f: &PciFunction) -> Int
pub fn pci_cache_line_size(f: &PciFunction) -> Int
pub fn pci_latency_timer(f: &PciFunction) -> Int
pub fn pci_header_type(f: &PciFunction) -> Int
pub fn pci_bist(f: &PciFunction) -> Int
pub fn pci_header_kind(f: &PciFunction) -> Int
pub fn pci_multifunction(f: &PciFunction) -> Bool

pub fn pci_command_io_enabled(f: &PciFunction) -> Bool
pub fn pci_command_memory_enabled(f: &PciFunction) -> Bool
pub fn pci_command_bus_master_enabled(f: &PciFunction) -> Bool
pub fn pci_command_serr_enabled(f: &PciFunction) -> Bool
pub fn pci_command_interrupt_disabled(f: &PciFunction) -> Bool
pub fn pci_has_capability_list(f: &PciFunction) -> Bool
pub fn pci_status_66mhz_capable(f: &PciFunction) -> Bool
pub fn pci_status_fast_back_to_back(f: &PciFunction) -> Bool
pub fn pci_status_interrupt_pending(f: &PciFunction) -> Bool
pub fn pci_status_master_data_parity_error(f: &PciFunction) -> Bool

pub fn pci_class_name(code: Int) -> Str
pub fn pci_header_kind_name(kind: Int) -> Str
pub fn pci_cap_name(id: Int) -> Str

pub fn pci_bar_raw(f: &PciFunction, i: Int) -> Int
pub fn pci_bar_kind(f: &PciFunction, i: Int) -> Int
pub fn pci_bar_memory_type(f: &PciFunction, i: Int) -> Int
pub fn pci_bar_is_64(f: &PciFunction, i: Int) -> Bool
pub fn pci_bar_is_upper(f: &PciFunction, i: Int) -> Bool
pub fn pci_bar_address(f: &PciFunction, i: Int) -> Int
pub fn pci_bar_size(f: &PciFunction, i: Int) -> Int

pub fn pci_cardbus_cis(f: &PciFunction) -> Int
pub fn pci_subsystem_vendor_id(f: &PciFunction) -> Int
pub fn pci_subsystem_device_id(f: &PciFunction) -> Int
pub fn pci_expansion_rom_raw(f: &PciFunction) -> Int
pub fn pci_expansion_rom_enabled(f: &PciFunction) -> Bool
pub fn pci_expansion_rom_address(f: &PciFunction) -> Int

pub fn pci_bridge_primary_bus(f: &PciFunction) -> Int
pub fn pci_bridge_secondary_bus(f: &PciFunction) -> Int
pub fn pci_bridge_subordinate_bus(f: &PciFunction) -> Int
pub fn pci_bridge_secondary_status(f: &PciFunction) -> Int
pub fn pci_bridge_io_is_32bit(f: &PciFunction) -> Bool
pub fn pci_bridge_io_base(f: &PciFunction) -> Int
pub fn pci_bridge_io_limit(f: &PciFunction) -> Int
pub fn pci_bridge_memory_base(f: &PciFunction) -> Int
pub fn pci_bridge_memory_limit(f: &PciFunction) -> Int
pub fn pci_bridge_prefetchable_base(f: &PciFunction) -> Int
pub fn pci_bridge_prefetchable_limit(f: &PciFunction) -> Int
pub fn pci_bridge_control(f: &PciFunction) -> Int

pub fn pci_cap_count(f: &PciFunction) -> Int
pub fn pci_cap_id(f: &PciFunction, i: Int) -> Int
pub fn pci_cap_offset(f: &PciFunction, i: Int) -> Int
pub fn pci_cap_span(f: &PciFunction, i: Int) -> Int
pub fn pci_cap_find(f: &PciFunction, id: Int) -> Int
pub fn pci_cap_read_u8(f: &PciFunction, i: Int, rel: Int) -> Int
pub fn pci_cap_read_u16(f: &PciFunction, i: Int, rel: Int) -> Int
pub fn pci_cap_read_u32(f: &PciFunction, i: Int, rel: Int) -> Int
pub fn pci_cap_pm_version(f: &PciFunction, i: Int) -> Int
pub fn pci_cap_pm_control(f: &PciFunction, i: Int) -> Int
pub fn pci_cap_msi_control(f: &PciFunction, i: Int) -> Int
pub fn pci_cap_msi_64bit(f: &PciFunction, i: Int) -> Bool
pub fn pci_cap_msi_address(f: &PciFunction, i: Int) -> Int
pub fn pci_cap_msi_data(f: &PciFunction, i: Int) -> Int
pub fn pci_cap_pcie_version(f: &PciFunction, i: Int) -> Int
pub fn pci_cap_pcie_device_caps(f: &PciFunction, i: Int) -> Int

pub fn pci_build_type0(cfg: &PciType0Config) -> Result[Vec[UInt8], Str]
```

## 11. Semantics of the accessors

- **Scalar accessors** are O(1) and return -1 when `raw.len() < 256`; the
  Bool predicates return false and `pci_serialize` still returns the stored
  bytes.
- **`pci_header_kind`** strips bit 7 (`header_type >= 128` -> subtract 128);
  `pci_multifunction` is `header_type >= 128`.
- **BAR accessors** gate on slot validity for the header kind (section 5)
  and on `raw.len() >= 256`. `pci_bar_kind` returns 0/1, `pci_bar_memory_type`
  returns 0/1/2/3 for memory slots and -1 for I/O, `pci_bar_address` returns
  the masked address, `pci_bar_size` the lowest set bit (0 when unassigned).
  A 64-bit address with bit 63 set comes out negative, and -1 is also the
  invalid-index sentinel (documented collision in that one case).
- **Type-0 extras** return -1 outside kind 0x00; `pci_expansion_rom_*` also
  accept kind 0x01 (0x38). `pci_expansion_rom_address` masks bit 0 and the
  reserved bits 10..1 (`v - v % 2048`).
- **Bridge accessors** return -1 (false for `pci_bridge_io_is_32bit`) outside
  kind 0x01. Decoded windows are `(raw / 16) * 4096` (I/O, 4 KiB
  granularity) and `(raw / 16) * 1048576` (memory and prefetchable, 1 MiB
  granularity); the low flag nibble is ignored as documented, and the 64-bit
  upper registers are not combined.
- **Capability accessors** are O(1). `pci_cap_count` minimizes the three
  column lengths; `pci_cap_id/offset/span(-1..count)` return -1 out of range;
  `pci_cap_find` scans in walk order. Generic readers and subset accessors
  bound `rel + width` by the capability span and by the 256-byte space, and
  return -1 (false for the 64-bit predicate) when any check fails.

## 12. Error string catalog

| Condition | Error text |
|---|---|
| `pci_parse`: `data.len() < 256` | `pci: truncated config space` |
| Capability first/next pointer outside 0x40..0xFF or not a multiple of 4 | `pci: bad capability pointer` |
| Capability next pointer not greater than the current offset (self-loop, backward pointer, duplicate revisit) | `pci: capability loop` |
| `pci_build_type0`: `bars.len() != 6` | `pci: bar count` |
| Builder 16-bit field outside 0..65535 | `pci: bad word field` |
| Builder 8-bit field outside 0..255 | `pci: bad byte field` |
| Builder 32-bit field outside 0..2^32-1 | `pci: bad dword field` |
| Builder `status` bit 4 set | `pci: capability list bit set` |

Validation order is documented in sections 6, 7 and 9. No other condition
produces an error; malformed-but-readable values (reserved BAR types, unknown
header kinds, unknown capability IDs, vendor 0xFFFF) are decoded or preserved
raw instead.

## 13. Bit arithmetic for v0.61.3

`&` on operands with bit 31 set miscompiles in this compiler, so the module
never uses bitwise AND on 32-bit values, never shifts, and never writes a
large mask constant:

- field extraction uses division/modulo (`(v / 2^k) % 2`, `/ 16`, `% 2048`);
- flag masking uses subtraction (`v - v % 16`);
- little-endian packing uses `_byte_at`'s per-byte `% 256` loop;
- byte reads are widened with `(v[pos] as Int) & 0xFF`, which is safe because
  a UInt8 is 0..255 (the xiom.gpt/xiom.tlv precedent).

## 14. Complexity

| Operation | Complexity |
|---|---|
| `pci_parse` (256-byte copy plus the walk) | O(256 + capabilities) |
| `pci_serialize` | O(raw length) |
| Every scalar/bit/BAR/bridge/type-0 accessor | O(1) |
| `pci_bar_size` | O(1) (at most 63 modulus steps) |
| `pci_cap_id/offset/span/count` | O(1) |
| `pci_cap_find` | O(capabilities) |
| `pci_cap_read_*`, subset accessors | O(1) |
| `pci_build_type0` | O(256) |

## 15. Test plan

`tests/test_conformance.xi` (`module pci_tests`, 18 named checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per check and returns the failure
count). Fixtures are assembled byte by byte from a zero-filled 256-byte
space:

- type-0 fixture: vendor 0x1234 / device 0x5678, class 0x03, command 0x0407
  (I/O + memory + bus master + interrupt disable), status 0x00B0 (capability
  list + 66 MHz + fast back-to-back), BAR0 = prefetchable 32-bit memory at
  0xFE000000 (raw 0xFE000008), BAR1 = I/O at 0xE000, subsystem 0x103C:0x1234,
  expansion ROM 0xC0000005, capability chain 0x01 -> 0x05 at 0x40/0x50 (PM
  version 3, PMCSR 8; MSI 64-bit enable, address 0xFEE00000, data 0x0041);
- type-1 fixture: primary/secondary/subordinate 0/1/2, I/O window
  raw 0x10/0x20, memory window 0x1010/0x1020, prefetchable window
  0x2020/0x2030, expansion ROM 0xC0000805 at 0x38, bridge control 0x0040,
  BAR0 I/O at 0xE000, no capability list.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | identification | vendor/device/revision/prog IF/subclass/class/cache/latency/BIST/header type/kind/multifunction/command/status and population |
| t2 | bit predicates | all five command bits and all five status bits in one fixture |
| t3 | name tables | pinned class names, unknown/out-of-range class codes, header-kind names, cap names |
| t4 | BAR decode | BAR0 memory (kind/type/address/size), BAR1 I/O, zero BAR, out-of-range guards |
| t5 | 64-bit BAR | BAR2/BAR3 pair: type 2, is_64, is_upper, 2^32 address and size, upper-half -1s |
| t6 | masks/reserved | I/O low-bit masking, reserved type 3, zero size for zero address |
| t7 | type-0 extras | CIS, subsystem IDs, expansion ROM on kind 0 vs kind 1 and kind guard |
| t8 | capability index | count/ids/offsets/spans/find/order and out-of-range guards |
| t9 | PM subset | version/PMCSR, generic u8/u16/u32 reads, span and ID guards |
| t10 | MSI subset | 64-bit control/address/data and a 32-bit variant at the same offsets |
| t11 | PCIe subset | version, device capabilities, span, wrong-ID guards |
| t12 | parse errors | short buffer, pointer 0/0x3C/0x41, unaligned/far next, self-loop, backward loop, late-start loop, valid chain |
| t13 | kinds/gating | kind 0x02 and unknown kind skip the walk (and expose no/slot-0 BARs), 0x80 is multi-function with the walk intact, status bit 4 clear skips a garbage pointer |
| t14 | population | vendor 0xFFFF unpopulated, vendor 0 populated, short hand-built raw is defensive |
| t15 | builder | exact canonical bytes, multifunction header, build -> parse accessors, serialize round-trip |
| t16 | builder errors | bar count, word/byte/dword ranges, capability-list status bit |
| t17 | round-trips | serialize(parse(fixture)) byte-identical for all three fixtures, raw byte guards |
| t18 | bridge | bus numbers, status, decoded windows at 4 KiB/1 MiB granularity, bridge control, 32-bit I/O flag, BAR slot gating, kind guards |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.pci
```

Last verified: compiler 0.61.3,
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## 16. Known limitations

- **One function per parse.** A multi-function device needs one `pci_parse`
  call per function selector; function numbers do not appear in the 256-byte
  block.
- **No live sizing.** `pci_bar_size` is the lowest set bit of the stored
  value (alignment); it equals the true size only for saved sizing values.
- **Signed 64-bit edges.** A BAR or MSI address with bit 63 set comes out
  negative; `pci_bar_size` still reports its exact power-of-two divisor
  (capped at 2^62), and -1 collides with the invalid-index sentinel for the
  all-ones address.
- **Strictly increasing capability chains.** A legal-but-unsorted chain
  (next pointer below the current offset) is rejected as
  `pci: capability loop`; spans are only meaningful for increasing chains.
- **Capability spans are bounded regions.** The last capability's span runs
  to 256; the true register-block length of an unknown capability is not
  known.
- **Bridge windows are low-part only.** 64-bit prefetchable and 32-bit I/O
  upper registers are not combined; CardBus (kind 0x02) header registers are
  not decoded.
- **No MSI-X.** IDs above the documented table (including 0x11) are
  preserved raw and not interpreted.
- **No extended configuration space.** Bytes beyond 256 are ignored.
- **Name tables are partial** (class codes 0x00..0x13/0x40/0xFF; capability
  IDs 0x01/0x05/0x10 only).
- Not thread-safe; `PciFunction` is a plain value type holding one raw byte
  vector plus three capability vectors (no `Vec` of structs).

## 17. Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_fn`,
  `_err_fn`, `_ok_bytes`, `_err_bytes`; every other function returns through
  one of them.
- Every byte read is widened with `(v[pos] as Int) & 0xFF`; UInt8 values are
  never compared against Int constants without widening.
- Flag/type extraction and masking are arithmetic only (section 13); no
  shift operator and no large mask constant appears in the module.
- Vec fields are bound to typed locals (`let raw: Vec[UInt8] = f.raw;`)
  before indexing or passing by reference (never `&f.raw`).
- The module performs no string comparison at all; class/capability/kind
  names are literals and the tests compare through
  `xiom.string.compare.str_compare` (BUG 17 discipline).
- All `&mut Vec[UInt8]` helpers take the mutable reference at the top-level
  builder; nested helpers receive the existing reference (aiff/tar
  precedent), which also avoids the advisory E001 warning.
- **Malformed bracket audit:** both `.xi` files were grep-audited for
  `Vec<` / `Result<` after writing; every occurrence uses `Vec[...]` /
  `Result[...]` and the suite compiles with no warnings.
