# xiom.interrupt

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.2` on the XIOM registry.
> **Scope:** pure-XIOM *structure* codecs for interrupt controller tables
> and registers: x86 IDT gate descriptors / IDTR and ARM GICv2 distributor
> register decode plus IRQ ID classification. No device access, no MMIO
> writes, no registration or dispatch, no FFI.
> **Deps:** `xiom.std` only. The library module uses `xiom.string` and
> `xiom.convert.int`; the tests add `xiom.test`, `xiom.io`,
> `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.interrupt` answers the *shape* questions about interrupt controller
structures. Every function reads a caller-supplied `Vec[UInt8]` and decodes
or validates it; nothing touches hardware.

**x86 IDT side.** `x86_idt_gate32_decode` / `x86_idt_gate64_decode` decode
the 8-byte and 16-byte IDT gate descriptors: the split offset fields
(low/mid, plus high for the 64-bit form), the code selector, the IST index
(64-bit only), and the type/attribute byte split by divisor/modulo into
gate type (0xE interrupt / 0xF trap, plus the legacy 0x5/0x6/0x7 forms),
DPL 0-3, the P present bit and the S storage-segment bit. Decoders reject
short blocks and reserved fields set (byte 4 of the 32-bit form; IST bits
7:3 and bytes 12..16 of the 64-bit form). `x86_idt_gate_valid` is the
present-bit validation gate: present, not storage, nonzero selector, type
0xE or 0xF. `x86_idtr32_decode` / `x86_idtr64_decode` read the 6-byte and
10-byte IDTR base/limit, and `x86_idtr_entry_count` derives the descriptor
count when the limit is a whole multiple of the descriptor size.
`x86_idt_gate32_join` / `x86_idt_gate64_join` assemble offsets from split
fields; `x86_idt_gate32_offset_parts` / `x86_idt_gate64_offset_parts`
extract them back exactly (two's complement).

`x86_vector_name` names vectors 0-21 (DE, DB, NMI, BP, OF, BR, UD, NM, DF,
CSO, TS, NP, SS, GP, PF, MF, AC, MC, XM, VE, CP), reports `RESERVED` for 15
and 22-31 and `USER` for 32-255; `x86_vector_has_error_code` flags the
error-code-pushing exceptions (8, 10-14, 17, 21).

**GIC side.** `gicd_word` reads any 32-bit distributor register word.
`gicd_ctlr_decode` and `gicd_typer_decode` decode GICD_CTLR (group
enables, security-extension bits, ARE, DS, nASSGIreq, RWP) and GICD_TYPER
(ITLinesNumber, CPUNumber, SecurityExtn, MBIS, LSPI, ESPI range) and
return `Err` when a reserved bit of the documented layout is set.
`gic_max_interrupts`, `gic_max_spi_count`, `gic_highest_valid_id` and
`gic_cpu_count` implement the GICv2 arithmetic, including the 1020
interrupt cap for ITLinesNumber 31.

`gicd_bitmap_offset` / `gicd_bitmap_bit` / `gicd_bitmap_span` /
`gicd_bitmap_word_count` cover the GICD_IGROUPR (ID 0 upward) and
GICD_ISENABLER / ICENABLER / ISPENDR / ICPENDR (SPI 32 upward) bitmaps,
including the different word indexing of the group bitmap and rejection of
impossible bitmap sizes. `gicd_group_bit` is the group-bit convenience
wrapper. `gicd_priority` reads one GICD_IPRIORITYR byte per IRQ;
`gicd_target` reads one GICD_ITARGETSR byte and reports `writable: false`
for SGI 0-15 / PPI 16-31 (read-only in GICv2).

`gic_irq_class` classifies IDs: SGI 0-15, PPI 16-31, SPI 32-1019,
reserved 1020-1023, ESPI 4096-5119 (note-level) and invalid elsewhere,
with `gic_is_sgi` / `gic_is_ppi` / `gic_is_spi` / `gic_is_espi` and
`gic_irq_in_range(typer, irq)`.

## API

| Function | Returns | Description |
|---|---|---|
| `x86_idt_gate32_decode(data, off)` | `Result[X86IdtGate, Str]` | Decode an 8-byte 32-bit IDT gate. |
| `x86_idt_gate64_decode(data, off)` | `Result[X86IdtGate, Str]` | Decode a 16-byte 64-bit IDT gate. |
| `x86_idt_gate32_build(...)` | `Result[Vec[UInt8], Str]` | Build a canonical 32-bit gate. |
| `x86_idt_gate64_build(...)` | `Result[Vec[UInt8], Str]` | Build a canonical 64-bit gate. |
| `x86_idt_gate32_join(lo, mid)` | `Int` | Assemble a 32-bit target offset. |
| `x86_idt_gate64_join(lo, mid, high)` | `Int` | Assemble a 64-bit target offset. |
| `x86_idt_gate32_offset_parts(off)` | `Vec[Int]` | `[low16, mid16]`. |
| `x86_idt_gate64_offset_parts(off)` | `Vec[Int]` | `[low16, mid16, high32]`. |
| `x86_idt_gate_valid(g)` | `Bool` | Present/interrupt-or-trap/selector validation. |
| `x86_idt_gate_is_interrupt(g)` / `_is_trap(g)` | `Bool` | Type 0xE / 0xF. |
| `x86_idt_gate_target_offset(g)` | `Int` | Assembled handler offset. |
| `x86_idt_gate_selector(g)` / `_ist(g)` / `_type(g)` / `_dpl(g)` | `Int` | Record fields. |
| `x86_idt_gate_present(g)` / `_storage(g)` / `_long_mode(g)` | `Bool` | Record flags. |
| `x86_idtr32_decode(data, off)` / `x86_idtr64_decode(data, off)` | `Result[X86Idtr, Str]` | Decode the IDTR. |
| `x86_idtr32_build(limit, base)` / `x86_idtr64_build(limit, base)` | `Result[Vec[UInt8], Str]` | Build the IDTR. |
| `x86_idtr_limit(r)` / `_base(r)` / `_span(r)` / `_entry_count(r)` | `Int` | IDTR accessors. |
| `x86_idtr_long_mode(r)` | `Bool` | 64-bit form flag. |
| `x86_vector_name(v)` / `_class(v)` | `Str` | Mnemonic / class. |
| `x86_vector_has_error_code(v)` | `Bool` | Error-code-pushing exceptions. |
| `gicd_word(data, off)` | `Result[Int, Str]` | Any 32-bit distributor register word. |
| `gicd_ctlr_decode(data, off)` | `Result[GicdCtlr, Str]` | GICD_CTLR, strict reserved bits. |
| `gicd_ctlr_reserved_bits(raw)` | `Int` | Mask of forbidden set bits. |
| `gicd_ctlr_enable_mask(c)` | `Int` | Packed group-enable bits 0-3. |
| `gicd_typer_decode(data, off)` | `Result[GicdTyper, Str]` | GICD_TYPER, strict bit 9. |
| `gicd_typer_reserved_bits(typer)` | `Int` | Bit 9 (512) or 0. |
| `gic_max_interrupts(typer)` / `gic_max_spi_count(typer)` / `gic_highest_valid_id(typer)` / `gic_cpu_count(typer)` | `Int` | GICv2 TYPER arithmetic. |
| `gic_has_security_extensions(typer)` / `gic_has_mbis(typer)` / `gic_has_lpis(typer)` / `gic_has_espis(typer)` | `Bool` | TYPER flag bits. |
| `gic_espi_range(typer)` / `gic_espi_max_id(typer)` | `Int` | GICv3.1 ESPI range (note-level). |
| `gic_irq_in_range(typer, irq)` | `Bool` | ID within the SGI/PPI/SPI range. |
| `gicd_bitmap_offset(base, irq)` | `Result[Int, Str]` | Word offset of an IRQ bit. |
| `gicd_bitmap_bit(data, base, irq)` | `Result[Bool, Str]` | Extract an IRQ bitmap bit. |
| `gicd_group_bit(data, irq)` | `Result[Bool, Str]` | GICD_IGROUPR bit (covers SGI/PPI). |
| `gicd_bitmap_word_count(base, irq)` | `Result[Int, Str]` | Words needed to cover an IRQ. |
| `gicd_bitmap_span(data, base, words)` | `Result[Int, Str]` | Validate a bitmap block span. |
| `gicd_priority(data, irq)` / `gicd_priority_offset(irq)` | `Result[Int, Str]` | GICD_IPRIORITYR byte. |
| `gicd_target(data, irq)` / `gicd_target_offset(irq)` | `Result[GicdTarget, Str]` / `Result[Int, Str]` | GICD_ITARGETSR byte. |
| `gicd_target_writable(irq)` | `Bool` | False for SGI/PPI. |
| `gicd_typer2_decode(data, off)` | `Result[GicdTyper2, Str]` | GICD_TYPER2, note-level. |
| `gic_irq_class(irq)` / `gic_espi_class(irq)` | `Str` | ID classification. |
| `gic_is_sgi(irq)` / `gic_is_ppi(irq)` / `gic_is_spi(irq)` / `gic_is_espi(irq)` | `Bool` | ID predicates. |

Errors: see the catalog in SPEC.md. Every message carries the byte offset
it was detected at (or the register offset for the IRQ-based helpers).

## Usage

```xi
use xiom.interrupt;
use xiom.io;
use xiom.convert;

// First gate of a long-mode IDT: 16 raw bytes from memory.
let r = x86_idt_gate64_decode(&idt_bytes, 0);
match r {
  Ok(g) => {
    io.println("handler: " + convert.int_to_string(x86_idt_gate_target_offset(&g)));
    io.println("ist:     " + convert.int_to_string(x86_idt_gate_ist(&g)));
    if x86_idt_gate_valid(&g) {
      io.println("usable gate on selector " + convert.int_to_string(x86_idt_gate_selector(&g)));
    }
  },
  Err(e) => { io.println(e); },
}

// Vector 13 is #GP and pushes an error code; vector 13's mnemonic is "GP".
io.println(x86_vector_name(13) + " error-code vector: " +
           convert.int_to_string(x86_vector_has_error_code(13)));
```

```xi
// GICv2 distributor block? decode TYPER and probe an enable bit.
let wr = gicd_word(&dist, GICD_TYPER);
match wr {
  Ok(typer) => {
    io.println("highest ID: " + convert.int_to_string(gic_highest_valid_id(typer)));
    io.println("CPUs:       " + convert.int_to_string(gic_cpu_count(typer)));
    let eb = gicd_bitmap_bit(&dist, GICD_ISENABLER, 32);
    match eb {
      Ok(on) => { if on { io.println("SPI 32 enabled"); } },
      Err(e) => { io.println(e); },
    }
  },
  Err(e) => { io.println(e); },
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.interrupt
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No device access.** The distributor/IDT buffers are synthetic
  register images; nothing is mapped, read or written. This is a codec,
  not a driver: no registration, masking, dispatch or re-entrancy policy.
- **GICv2 focus.** The distributor register map is GICv2
  (ARM IHI 0048B). GICv3.1 bits are decoded only as clearly marked
  note-level extras (GICD_TYPER bit 8 + [31:27], GICD_TYPER2, ESPI IDs)
  and no version negotiation is performed.
- **GICv3+ structures out of scope:** redistributors (GICR), ITS/GITS,
  LPI property/penalty tables, IROUTER and affinity routing, the CPU
  interface (ICC_*), and GICD_ICFGR config registers.
- **No SPI config/edge-level decode** (GICD_ICFGR), no SGI generation
  (GICD_SGIR), no active/pending state beyond the ISPENDR/ICPENDR bitmaps.
- **Reserved-bit strictness is layout-scoped.** GICD_CTLR rejects bit 7
  and bits 9..30; GICD_TYPER rejects only bit 9 (every other undefined
  bit is revision-dependent and read leniently via `gicd_word`).
- **x86 gate types are decoded, not executed.** Legacy 16-bit/task gates
  (0x5/0x6/0x7) decode but `x86_idt_gate_valid` only accepts 0xE/0xF.
  Gate builders reject negative 64-bit targets (bit 63 set), so
  non-canonical addresses cannot be emitted; decoding such a pattern
  yields the same negative two's-complement `Int`.
- **Priority width is raw.** GICD_IPRIORITYR is returned as the raw 8-bit
  byte; the number of implemented priority bits is implementation-defined
  and is not inferred.
- **No concurrency guarantees.** All values are plain data built from
  caller buffers; nothing is shared or synchronized.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
