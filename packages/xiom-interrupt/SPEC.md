# xiom.interrupt -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3;
20/20 conformance checks; not published).
Manifest: `package.xi` (`xiom.interrupt`, version `0.1.0`).
Module: `src/interrupt.xi` (`module xiom.interrupt`).
Depends on `xiom.std` (`xiom.string`, `xiom.convert.int`); tests add
`xiom.test`, `xiom.io`, `xiom.string.compare`, `xiom.encoding.hex`.

## Scope

Pure-XIOM (no FFI) *structure* codecs for interrupt controller tables and
registers. Every entry point reads a caller-supplied `Vec[UInt8]`; the
module never performs MMIO, registration, dispatch or any other device
access.

- x86 IDT gate descriptors, 32-bit (8-byte) and 64-bit (16-byte) forms:
  split offset fields, selector, IST, type/attribute byte, reserved-field
  rejection, canonical builders, offset join/split helpers;
- IDTR base/limit decode and encode for 32-bit and 64-bit modes;
- architectural vector names, classes and error-code classification for
  vectors 0..255;
- ARM GICv2 distributor register decode from a little-endian register
  image: GICD_CTLR, GICD_TYPER, the five bitmap families, per-IRQ
  GICD_IPRIORITYR and GICD_ITARGETSR bytes;
- IRQ ID classification (SGI 0-15, PPI 16-31, SPI 32-1019, reserved
  1020-1023) and the highest valid ID derived from ITLinesNumber;
- clearly marked note-level GICv3 / GICv3.1 extras (LSPI, MBIS, ESPI
  range, GICD_TYPER2) that are documented as limited.

## Non-goals

- Device access, MMIO mapping, writes, masking, dispatch, priorities
  policy or nested interrupt handling.
- GICv3+ redistributors (GICR), ITS/GITS, LPI property/penalty tables,
  IROUTER, affinity routing, CPU interface (ICC_*), GICD_ICFGR,
  GICD_SGIR, GICD_ISACTIVER/ICACTIVER.
- x86 gate *semantics*: the module validates that a gate is structurally
  usable (present, interrupt/trap type, nonzero selector) but does not
  model privilege transitions, TSS/IST stack loading or interrupt
  dispatch.
- Task gates (0x5) and legacy 16-bit gates (0x6/0x7) are decoded, not
  treated as valid delivery gates.
- Interrupt numbers above 1023 other than the ESPI note window, and no
  interrupt-ID-to-device (DT/ACPI `interrupts`) mapping.
- Concurrency, caching, endianness other than little-endian register
  images.

## x86: IDT gate descriptors

### 32-bit gate (8 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | target offset bits 15:0 (little-endian) |
| 2 | 2 | code segment selector (little-endian) |
| 4 | 1 | reserved, must be 0 |
| 5 | 1 | type/attribute byte |
| 6 | 2 | target offset bits 31:16 (little-endian) |

Reserved rule: byte 4 nonzero is rejected with
`interrupt: idt gate32 reserved byte invalid at offset N`.

`target_offset = join(offset_low, offset_mid)`; the result is 0..2^32-1.

### 64-bit gate (16 bytes)

| Offset | Size | Field |
|---|---|---|
| 0 | 2 | target offset bits 15:0 |
| 2 | 2 | code segment selector |
| 4 | 1 | IST index bits 2:0; bits 7:3 reserved |
| 5 | 1 | type/attribute byte |
| 6 | 2 | target offset bits 31:16 |
| 8 | 4 | target offset bits 63:32 |
| 12 | 4 | reserved, must be 0 |

Reserved rules: bits 7:3 of byte 4 set is rejected with
`interrupt: idt gate64 ist/reserved byte invalid at offset N`; bytes
12..16 nonzero is rejected with
`interrupt: idt gate64 reserved tail invalid at offset N`.

`target_offset = join(offset_low, offset_mid, offset_high)`. A 64-bit
address with bit 63 set is held as the same negative two's-complement
`Int` (see Policies).

### Type/attribute byte (offset 5, both forms)

Extraction is divisor/modulo on the byte value `attr` (0..255):

| Field | Bits | Extraction | Meaning |
|---|---|---|---|
| gate type | 3:0 | `attr % 16` | 0xE interrupt gate, 0xF trap gate; 0x5 task, 0x6/0x7 legacy 16-bit forms decode as-is |
| S storage | 4 | `(attr / 16) % 2` | 1 = storage segment (never a real IDT gate) |
| DPL | 6:5 | `(attr / 32) % 4` | 0..3 |
| P present | 7 | `(attr / 128) % 2` | 1 = present |

### Usability rule

`x86_idt_gate_valid(g)` is true when: present **and** not a storage
segment **and** selector nonzero **and** gate type is 0xE or 0xF. A
present gate with a NULL selector is structurally decodable but not
usable, and reports `false`.

### Builders

`x86_idt_gate32_build(target_offset, code_selector, gate_type, dpl,
present, storage_segment)` emits the canonical 8 bytes;
`x86_idt_gate64_build(...)` adds `ist_index`. Domains:
target offset 0..4294967295 (32-bit) / non-negative (64-bit, canonical
addresses do not set bit 63), selector 0..65535, gate type 0..15, DPL
0..3, IST 0..7. Out-of-domain inputs return the errors listed in the
catalog.

### Offset helpers

| Helper | Result |
|---|---|
| `x86_idt_gate32_join(lo, mid)` | `lo + mid * 65536` |
| `x86_idt_gate64_join(lo, mid, high)` | `lo + mid * 65536 + high * 4294967296` |
| `x86_idt_gate32_offset_parts(off)` | `[low16, mid16]` |
| `x86_idt_gate64_offset_parts(off)` | `[low16, mid16, high32]` |

Splitting is exact two's complement: splitting `-1` yields
`[65535, 65535, 4294967295]`, the same bytes the hardware stores.

## x86: IDTR

| Mode | Length | Layout |
|---|---|---|
| 32-bit | 6 bytes | [0:2] limit, [2:6] base (u32) |
| 64-bit | 10 bytes | [0:2] limit, [2:10] base (u64 bit pattern) |

- `x86_idtr_span(r)` = `limit + 1`.
- `x86_idtr_entry_count(r)` = `(limit + 1) / 16` in long mode,
  `(limit + 1) / 8` otherwise; `-1` when the span is not a whole
  multiple of the descriptor size (a malformed IDTR).
- Builders reject limit > 65535 and out-of-range bases (negative 64-bit
  base).

## x86: vectors

| Vector(s) | Name | Class | Error code |
|---|---|---|---|
| 0 | DE | exception | no |
| 1 | DB | exception | no |
| 2 | NMI | exception | no |
| 3 | BP | exception | no |
| 4 | OF | exception | no |
| 5 | BR | exception | no |
| 6 | UD | exception | no |
| 7 | NM | exception | no |
| 8 | DF | exception | yes |
| 9 | CSO (obsolete coprocessor segment overrun) | exception | no |
| 10 | TS | exception | yes |
| 11 | NP | exception | yes |
| 12 | SS | exception | yes |
| 13 | GP | exception | yes |
| 14 | PF | exception | yes |
| 15 | RESERVED | reserved | no |
| 16 | MF | exception | no |
| 17 | AC | exception | yes |
| 18 | MC | exception | no |
| 19 | XM | exception | no |
| 20 | VE | exception | no |
| 21 | CP | exception | yes |
| 22-31 | RESERVED | reserved | no |
| 32-255 | USER | user | no |

Out-of-range values return `""` (name) / `"invalid"` (class) and
`false` (error code).

## GICv2: distributor register map

Offsets are byte offsets from the distributor base; all registers are
little-endian. The module's register image is a plain `Vec[UInt8]`;
the caller decides whether the image is a snapshot, a synthetic test
block or an actual mapped window.

| Offset | Register | Content |
|---|---|---|
| 0x000 | GICD_CTLR | control |
| 0x004 | GICD_TYPER | type |
| 0x00C | GICD_TYPER2 | GICv3.1 type 2 (note-level) |
| 0x080 | GICD_IGROUPR | group bitmap, ID 0 upward |
| 0x100 | GICD_ISENABLER | set-enable bitmap, SPI 32 upward |
| 0x180 | GICD_ICENABLER | clear-enable bitmap, SPI 32 upward |
| 0x200 | GICD_ISPENDR | set-pending bitmap, SPI 32 upward |
| 0x280 | GICD_ICPENDR | clear-pending bitmap, SPI 32 upward |
| 0x400 | GICD_IPRIORITYR | one priority byte per IRQ |
| 0x800 | GICD_ITARGETSR | one CPU target byte per IRQ |
| -- | GICD_SIZE = 0x10000 | documented distributor aperture (constant only) |

### GICD_CTLR (0x000)

| Bit | Field | Decoded name |
|---|---|---|
| 0 | EnableGrp0 | `enable_grp0` |
| 1 | EnableGrp1 | `enable_grp1` |
| 2 | EnableGrp1S | `enable_grp1s` |
| 3 | EnableGrp1NS | `enable_grp1ns` |
| 4 | ARE_S (secure view) | `are_s` |
| 5 | ARE_NS | `are_ns` |
| 6 | DS (GICv3.x) | `disable_security` |
| 8 | nASSGIreq (GICv4.1) | `nassgi_req` |
| 31 | RWP | `rwp` |

Reserved for this layout: bit 7 and bits 9..30. `gicd_ctlr_decode`
rejects a word with any of them set; `gicd_ctlr_reserved_bits(raw)`
returns the mask (0 when clean). Bits 2/3 are only meaningful when
security extensions exist; bit 8 is a GICv4.1 field. The decoder exposes
them without enforcing a version.

### GICD_TYPER (0x004)

| Bits | Field | Use |
|---|---|---|
| 4:0 | ITLinesNumber | total = 32*(N+1); if N == 31 the documented total is 1020 |
| 7:5 | CPUNumber | `cpu_count` = CPUNumber + 1 (1..8) |
| 8 | ESPI (GICv3.1) | `espi`, gates the ESPI range field |
| 9 | reserved | strict decode rejects it (`gicd_typer_reserved_bits` = 512) |
| 10 | SecurityExtn | `security_extn` |
| 16 | MBIS (GICv3) | `mbis` |
| 17 | LSPI (GICv3) | `lspi` |
| 31:27 | ESPI range (GICv3.1) | `espi_range` = (field + 1) * 32 when bit 8, else 0 |

Derived values:

| Function | Value |
|---|---|
| `gic_max_interrupts(typer)` | 32*(N+1), capped to 1020 when N == 31 |
| `gic_max_spi_count(typer)` | `gic_max_interrupts - 32` |
| `gic_highest_valid_id(typer)` | `gic_max_interrupts - 1` (31, 127, ..., 1019) |
| `gic_cpu_count(typer)` | CPUNumber + 1 |
| `gic_has_security_extensions(typer)` | bit 10 |
| `gic_has_mbis(typer)` / `gic_has_lpis(typer)` | bit 16 / bit 17 |
| `gic_has_espis(typer)` | bit 8 |
| `gic_espi_range(typer)` | 0 when bit 8 is clear, else (bits[31:27] + 1) * 32 |
| `gic_espi_max_id(typer)` | 4096 + range - 1, or -1 when the ESPI bit is clear |
| `gic_irq_in_range(typer, irq)` | `0 <= irq <= gic_highest_valid_id(typer)`; ESPI IDs are outside this check |

Bit 9 is the only bit rejected, because every other undefined bit has
been reassigned by later GIC revisions; a forward-compatible read uses
`gicd_word` plus the bit helpers above.

### Bitmap register families

| Base | Family | First ID | Word for ID |
|---|---|---|---|
| 0x080 | GICD_IGROUPR | 0 (SGI/PPI included) | `ID / 32` |
| 0x100 | GICD_ISENABLER | 32 | `(ID - 32) / 32` |
| 0x180 | GICD_ICENABLER | 32 | `(ID - 32) / 32` |
| 0x200 | GICD_ISPENDR | 32 | `(ID - 32) / 32` |
| 0x280 | GICD_ICPENDR | 32 | `(ID - 32) / 32` |

Word byte offset = `base + 4 * word`. Within the 32-bit word, the bit
for `ID` is `ID % 32`; its byte is `word + (ID % 32) / 8` and its bit in
that byte is `(ID % 32) % 8`.

Rules enforced:

- only the five bases above are accepted
  (`interrupt: unknown distributor bitmap base N`);
- IDs must be 0..1019 (`outside the GICv2 range 0..1019`); the
  enable/pending families reject IDs below 32 (`is an SGI/PPI; bitmap
  base B covers SPIs only`) because GICD_ISENABLER0 starts at SPI 32;
- a bitmap block can never need more than 32 words (1024 bits vs. 1020
  IDs), so `gicd_bitmap_span` rejects `word_count` outside 1..32 as
  `interrupt: impossible bitmap size N words at base B`;
- a word that does not fit the supplied block is a short-block error
  carrying the byte offset, the required size and the block size.

### GICD_IPRIORITYR (0x400)

One byte per IRQ: `offset = 0x400 + ID`, ID 0..1019. `gicd_priority`
returns the raw 8-bit byte; the number of *implemented* priority bits is
implementation-defined (a GICv2 implementation may implement only the
top 5 bits, for example) and is not inferred. Bytes >= 128 are returned
as 128..255 (the decoder widens the unsigned byte correctly).

### GICD_ITARGETSR (0x800)

One byte per IRQ: `offset = 0x800 + ID`, ID 0..1019. `gicd_target`
returns `GicdTarget{ irq, targets, writable }`. `writable` is false for
SGI 0-15 and PPI 16-31 (read-only in GICv2) and true for SPIs;
`gicd_target_writable(irq)` exposes the same predicate. The raw byte is
returned for read-only IDs too, since the memory image still contains a
value.

### IRQ ID classification

| ID range | `gic_irq_class` | Predicate |
|---|---|---|
| < 0 | invalid | all predicates false |
| 0-15 | SGI | `gic_is_sgi` |
| 16-31 | PPI | `gic_is_ppi` |
| 32-1019 | SPI | `gic_is_spi` |
| 1020-1023 | reserved | all predicates false (1022 is `GIC_SPURIOUS_INTID`) |
| 4096-5119 | ESPI (GICv3.1 note-level) | `gic_is_espi` |
| everything else | invalid | all predicates false |

`gic_espi_class(irq)` returns `"ESPI"` only inside 4096-5119 and
`"invalid"` otherwise.

### GICv3 / GICv3.1 note-level extras (limited)

Documented as limited: the following are decoded because they sit in
registers this module already reads, but no version negotiation or full
GICv3.1 semantics are claimed.

- `GICD_TYPER` bit 8 (`espi`) and bits 31:27 (`espi_range`,
  `gic_espi_range`, `gic_espi_max_id`) — the number of 32-ID extended
  SPI blocks advertised in the 4096+ window;
- `GICD_TYPER` bit 16 (`mbis`) and bit 17 (`lspi`);
- `GICD_TYPER2` at offset 0x00C: `vid` (bits 4:0), `vil` (bit 7),
  `nassgi_cap` (bit 8), exposed raw and with **no** reserved-bit
  enforcement;
- `gic_is_espi` / `gic_espi_class` treat 4096-5119 as the ESPI window
  without checking `GICD_TYPER` bit 8; callers that need that
  confirmation must check `gic_has_espis(typer)` themselves.

## Data conventions

- **Little-endian, arithmetic only.** Every multi-byte field is
  extracted by `value = sum(byte[i] * 256^i)`; packing is the inverse.
  No `&`/`>>` masking is used on values that may have bit 31 set
  (compiler v0.61.3 miscompiles those), and every bit probe goes through
  byte extraction first (`_byte_of`, `_word_bit`). This is exact for
  negative two's-complement values.
- **Signed two's-complement bit patterns.** A u32 with bit 31 set is
  returned as the same negative `Int` (e.g. `0x80000003` decodes as
  `-2147483645`, and `gicd_ctlr_reserved_bits` still sees it correctly).
  A 64-bit address above 2^63-1 is likewise negative. Builders reject
  negative inputs for 64-bit addresses, so emitted bytes are canonical.
- **Errors carry offsets.** Every message begins with `interrupt: ` and
  names the byte offset (register images) or the IRQ ID (bitmap/priority/
  target helpers) where the problem was detected.
- **Strict on decode, raw escape hatch.** `gicd_ctlr_decode`,
  `gicd_typer_decode`, the IDT decoders and the IDTR decoders reject
  malformed shapes; `gicd_word` reads any 4-byte register word for
  callers that need a lenient, forward-compatible read.
- **Flat data.** No struct owns a buffer; `X86IdtGate`, `X86Idtr`,
  `GicdCtlr`, `GicdTyper`, `GicdTyper2` and `GicdTarget` are plain
  value types built from the decoded fields.

## Error catalog

x86:

```
interrupt: idt gate32 block out of range at offset N (need 8 bytes, have Y)
interrupt: idt gate32 reserved byte invalid at offset N
interrupt: idt gate64 block out of range at offset N (need 16 bytes, have Y)
interrupt: idt gate64 ist/reserved byte invalid at offset N
interrupt: idt gate64 reserved tail invalid at offset N
interrupt: idt gate32 target offset out of range
interrupt: idt gate32 selector out of range
interrupt: idt gate32 gate type out of range
interrupt: idt gate32 dpl out of range
interrupt: idt gate64 target offset out of range
interrupt: idt gate64 selector out of range
interrupt: idt gate64 ist index out of range
interrupt: idt gate64 gate type out of range
interrupt: idt gate64 dpl out of range
interrupt: idtr32 block out of range at offset N (need 6 bytes, have Y)
interrupt: idtr64 block out of range at offset N (need 10 bytes, have Y)
interrupt: idtr32 limit out of range
interrupt: idtr32 base out of range
interrupt: idtr64 limit out of range
interrupt: idtr64 base out of range
```

GIC:

```
interrupt: distributor register out of range at offset N (need 4 bytes, have Y)
interrupt: distributor ctlr reserved bits set invalid at offset N
interrupt: distributor typer reserved bit 9 set invalid at offset N
interrupt: unknown distributor bitmap base N
interrupt: irq N outside the GICv2 range 0..1019
interrupt: irq N is an SGI/PPI; bitmap base B covers SPIs only
interrupt: distributor bitmap word out of range at offset N (need 4 bytes, have Y)
interrupt: distributor bitmap block out of range at offset N (need X bytes, have Y)
interrupt: impossible bitmap size N words at base B
interrupt: distributor priority byte out of range at offset N (need 1 byte, have Y)
interrupt: distributor target byte out of range at offset N (need 1 byte, have Y)
```

When `need` is 1 the message uses the singular `1 byte`; otherwise
`X bytes`.

## Public API

```xi
pub type X86IdtGate = {
  target_offset: Int; code_selector: Int; ist_index: Int;
  gate_type: Int; dpl: Int; present: Bool; storage_segment: Bool;
  long_mode: Bool;
}
pub type X86Idtr = { limit: Int; base: Int; long_mode: Bool; }
pub type GicdCtlr = {
  enable_grp0: Bool; enable_grp1: Bool; enable_grp1s: Bool;
  enable_grp1ns: Bool; are_s: Bool; are_ns: Bool;
  disable_security: Bool; nassgi_req: Bool; rwp: Bool; raw: Int;
}
pub type GicdTyper = {
  it_lines_number: Int; cpu_count: Int; espi: Bool; espi_range: Int;
  security_extn: Bool; mbis: Bool; lspi: Bool; max_interrupts: Int;
  raw: Int;
}
pub type GicdTyper2 = { vid: Int; vil: Bool; nassgi_cap: Bool; raw: Int; }
pub type GicdTarget = { irq: Int; targets: Int; writable: Bool; }

pub fn x86_idt_gate32_decode(data: &Vec[UInt8], offset: Int) -> Result[X86IdtGate, Str]
pub fn x86_idt_gate64_decode(data: &Vec[UInt8], offset: Int) -> Result[X86IdtGate, Str]
pub fn x86_idt_gate32_build(target_offset: Int, code_selector: Int, gate_type: Int, dpl: Int, present: Bool, storage_segment: Bool) -> Result[Vec[UInt8], Str]
pub fn x86_idt_gate64_build(target_offset: Int, code_selector: Int, ist_index: Int, gate_type: Int, dpl: Int, present: Bool, storage_segment: Bool) -> Result[Vec[UInt8], Str]
pub fn x86_idt_gate32_join(offset_low: Int, offset_mid: Int) -> Int
pub fn x86_idt_gate64_join(offset_low: Int, offset_mid: Int, offset_high: Int) -> Int
pub fn x86_idt_gate32_offset_parts(target_offset: Int) -> Vec[Int]
pub fn x86_idt_gate64_offset_parts(target_offset: Int) -> Vec[Int]
pub fn x86_idt_gate_target_offset(g: &X86IdtGate) -> Int
pub fn x86_idt_gate_selector(g: &X86IdtGate) -> Int
pub fn x86_idt_gate_ist(g: &X86IdtGate) -> Int
pub fn x86_idt_gate_type(g: &X86IdtGate) -> Int
pub fn x86_idt_gate_dpl(g: &X86IdtGate) -> Int
pub fn x86_idt_gate_present(g: &X86IdtGate) -> Bool
pub fn x86_idt_gate_storage(g: &X86IdtGate) -> Bool
pub fn x86_idt_gate_long_mode(g: &X86IdtGate) -> Bool
pub fn x86_idt_gate_is_interrupt(g: &X86IdtGate) -> Bool
pub fn x86_idt_gate_is_trap(g: &X86IdtGate) -> Bool
pub fn x86_idt_gate_valid(g: &X86IdtGate) -> Bool
pub fn x86_idtr32_decode(data: &Vec[UInt8], offset: Int) -> Result[X86Idtr, Str]
pub fn x86_idtr64_decode(data: &Vec[UInt8], offset: Int) -> Result[X86Idtr, Str]
pub fn x86_idtr32_build(limit: Int, base: Int) -> Result[Vec[UInt8], Str]
pub fn x86_idtr64_build(limit: Int, base: Int) -> Result[Vec[UInt8], Str]
pub fn x86_idtr_limit(r: &X86Idtr) -> Int
pub fn x86_idtr_base(r: &X86Idtr) -> Int
pub fn x86_idtr_long_mode(r: &X86Idtr) -> Bool
pub fn x86_idtr_span(r: &X86Idtr) -> Int
pub fn x86_idtr_entry_count(r: &X86Idtr) -> Int
pub fn x86_vector_name(v: Int) -> Str
pub fn x86_vector_class(v: Int) -> Str
pub fn x86_vector_has_error_code(v: Int) -> Bool

pub fn gicd_word(data: &Vec[UInt8], offset: Int) -> Result[Int, Str]
pub fn gicd_ctlr_decode(data: &Vec[UInt8], offset: Int) -> Result[GicdCtlr, Str]
pub fn gicd_ctlr_reserved_bits(raw: Int) -> Int
pub fn gicd_ctlr_enable_mask(c: &GicdCtlr) -> Int
pub fn gicd_typer_decode(data: &Vec[UInt8], offset: Int) -> Result[GicdTyper, Str]
pub fn gicd_typer_reserved_bits(typer: Int) -> Int
pub fn gic_max_interrupts(typer: Int) -> Int
pub fn gic_max_spi_count(typer: Int) -> Int
pub fn gic_highest_valid_id(typer: Int) -> Int
pub fn gic_cpu_count(typer: Int) -> Int
pub fn gic_has_security_extensions(typer: Int) -> Bool
pub fn gic_has_mbis(typer: Int) -> Bool
pub fn gic_has_lpis(typer: Int) -> Bool
pub fn gic_has_espis(typer: Int) -> Bool
pub fn gic_espi_range(typer: Int) -> Int
pub fn gic_espi_max_id(typer: Int) -> Int
pub fn gic_irq_in_range(typer: Int, irq: Int) -> Bool
pub fn gicd_bitmap_offset(base: Int, irq: Int) -> Result[Int, Str]
pub fn gicd_bitmap_bit(data: &Vec[UInt8], base: Int, irq: Int) -> Result[Bool, Str]
pub fn gicd_group_bit(data: &Vec[UInt8], irq: Int) -> Result[Bool, Str]
pub fn gicd_bitmap_word_count(base: Int, highest_irq: Int) -> Result[Int, Str]
pub fn gicd_bitmap_span(data: &Vec[UInt8], base: Int, word_count: Int) -> Result[Int, Str]
pub fn gicd_priority_offset(irq: Int) -> Result[Int, Str]
pub fn gicd_priority(data: &Vec[UInt8], irq: Int) -> Result[Int, Str]
pub fn gicd_target_offset(irq: Int) -> Result[Int, Str]
pub fn gicd_target(data: &Vec[UInt8], irq: Int) -> Result[GicdTarget, Str]
pub fn gicd_target_writable(irq: Int) -> Bool
pub fn gicd_typer2_decode(data: &Vec[UInt8], offset: Int) -> Result[GicdTyper2, Str]
pub fn gic_irq_class(irq: Int) -> Str
pub fn gic_espi_class(irq: Int) -> Str
pub fn gic_is_sgi(irq: Int) -> Bool
pub fn gic_is_ppi(irq: Int) -> Bool
pub fn gic_is_spi(irq: Int) -> Bool
pub fn gic_is_espi(irq: Int) -> Bool
```

## Public constants

```
X86_IDT_GATE32_LEN 8      X86_IDT_GATE64_LEN 16
X86_IDTR32_LEN 6          X86_IDTR64_LEN 10
X86_IDT_VECTOR_COUNT 256  X86_IDT_TYPE_TASK32 5
X86_IDT_TYPE_INT16 6      X86_IDT_TYPE_TRAP16 7
X86_IDT_TYPE_INTERRUPT 14 X86_IDT_TYPE_TRAP 15
X86_IDT_DPL_MAX 3         X86_IDT_IST_MAX 7

GICD_CTLR 0x000           GICD_TYPER 0x004
GICD_TYPER2 0x00C         GICD_IGROUPR 0x080
GICD_ISENABLER 0x100      GICD_ICENABLER 0x180
GICD_ISPENDR 0x200        GICD_ICPENDR 0x280
GICD_IPRIORITYR 0x400     GICD_ITARGETSR 0x800
GICD_SIZE 0x10000
GIC_SGI_COUNT 16          GIC_PPI_COUNT 16
GIC_FIRST_SPI 32          GIC_MAX_INTID 1019
GIC_SPURIOUS_INTID 1022   ESPI_BASE_INTID 4096
GIC_ESPI_COUNT 1024       GIC_MAX_BITMAP_WORDS 32
```

## Conformance coverage

`tests/test_conformance.xi` (20 checks, all synthetic buffers built
in-test):

1. gate32 decode of a present interrupt gate (offset assembly, fields);
2. gate32 attribute matrix (P/S/DPL/type, legacy 0x6, `valid` rules);
3. gate32 error catalog (short block, bad offset, reserved byte);
4. gate64 decode (0x112345678, IST 3, trap, present);
5. gate64 error catalog (short block, IST/reserved byte, reserved tail);
6. gate32 builder bytes, round-trip, five builder errors;
7. gate64 builder bytes, round-trip, five builder errors;
8. join/parts helpers incl. two's-complement `-1` extraction;
9. IDTR32 round-trip, odd limit, errors;
10. IDTR64 round-trip, 64-bit high base bit pattern, errors;
11. GICD_CTLR fields, reserved mask, RWP bit-31 value;
12. GICD_TYPER fields, SPI/CPU arithmetic, 1020 cap, LSPI/MBIS/ESPI,
    bit-9 rejection;
13. bitmap offsets/bits and their error catalog, including IGROUPR
    word-0 vs. SPI bitmap word indexing;
14. group bit (SGI/PPI/SPI), word counts, spans, impossible sizes;
15. GICD_IPRIORITYR offsets and bytes (>= 128 widened), errors;
16. GICD_ITARGETSR offsets, targets, SGI/PPI read-only rule, errors;
17. IRQ classification boundaries 15/16/31/32/1019/1020/1023/4096/5119;
18. GICD_TYPER2 note-level decode and errors;
19. vector names 0-21, RESERVED/USER/out-of-range, classes, error codes;
20. public constants and NULL-selector `valid` rule.

Expected harness output: 20 `[PASS]` lines and
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.
