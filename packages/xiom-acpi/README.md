# xiom.acpi

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM ACPI table-layer codec: RSDP (revision 0/2), the
> 36-byte SDT header, and RSDT (u32) / XSDT (u64) table-chain walking and
> canonical building.
> **Deps:** `xiom.std` only. The library module imports `xiom.string`; the
> tests use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex` from it. No FFI.

## What it is

`xiom.acpi` parses the ACPI table layer, which is little-endian:

- the **RSDP** (`"RSD PTR "`) at revision 0 (20 bytes) or revision 2
  (36 bytes, adding the length, XSDT address and extended checksum);
- the **36-byte SDT header** shared by every ACPI table (signature, length,
  revision, checksum, OEMID, OEM table ID, OEM revision, creator ID and
  creator revision);
- the **RSDT** (u32 entries) and **XSDT** (u64 entries) address arrays that
  chain the tables together.

`acpi_rsdp_parse` validates an RSDP (signature, base checksum, revision,
OEMID printability, and for revision 2 the length and extended checksum).
`acpi_walk_rsdt` / `acpi_walk_xsdt` / `acpi_tables_from_rsdp` walk a chain
over a caller-supplied buffer and resolve every entry to a validated span:
4-byte alignment, a 36-byte header inside the buffer, a printable
signature, length >= 36 inside the buffer, and a valid table checksum. The
result is a flat `AcpiTableSet` of parallel vectors (no `Vec[StructType]`);
zero entries are skipped, duplicate signatures are tolerated, and
`acpi_find_table` returns the first match in walk order. The builders emit
canonical bytes with computed checksums.

## API

| Function | Returns | Description |
|---|---|---|
| `acpi_rsdp_parse(data)` | `Result[AcpiRsdp, Str]` | Parse and validate the RSDP at offset 0. |
| `acpi_rsdp_revision(r)` | `Int` | RSDP revision (`0` or `2`). |
| `acpi_rsdp_length(r)` | `Int` | `20` (rev 0) or the stored length field (rev 2). |
| `acpi_rsdp_rsdt_address(r)` | `Int` | RSDT address (u32). |
| `acpi_rsdp_xsdt_address(r)` | `Int` | XSDT address (u64); `0` for revision 0. |
| `acpi_rsdp_oem_id(r)` | `Vec[UInt8]` | Copy of the six raw OEMID bytes. |
| `acpi_walk_rsdt(data, offset)` | `Result[AcpiTableSet, Str]` | Walk an RSDT rooted at `offset`. |
| `acpi_walk_xsdt(data, offset)` | `Result[AcpiTableSet, Str]` | Walk an XSDT rooted at `offset`. |
| `acpi_tables_from_rsdp(data, r)` | `Result[AcpiTableSet, Str]` | Walk the chain selected by a parsed RSDP. |
| `acpi_table_count(t)` | `Int` | Number of resolved tables. |
| `acpi_table_offset(t, i)` | `Int` | Absolute buffer offset, or `-1`. |
| `acpi_table_length(t, i)` | `Int` | Declared length, or `-1`. |
| `acpi_table_revision(t, i)` | `Int` | Header revision, or `-1`. |
| `acpi_table_signature(t, i)` | `Int` | Packed signature, or `-1`. |
| `acpi_find_table(t, sig)` | `Int` | First table with `sig`; `-1` when absent. |
| `acpi_table_signature_bytes(data, t, i)` | `Result[Vec[UInt8], Str]` | Copy of the four signature bytes. |
| `acpi_table_oem_id(data, t, i)` | `Result[Vec[UInt8], Str]` | Copy of the six OEMID bytes. |
| `acpi_table_oem_table_id(data, t, i)` | `Result[Vec[UInt8], Str]` | Copy of the eight OEM table ID bytes. |
| `acpi_table_creator_id(data, t, i)` | `Result[Vec[UInt8], Str]` | Copy of the four creator ID bytes. |
| `acpi_table_oem_revision(data, t, i)` | `Int` | OEM revision (u32), or `-1`. |
| `acpi_table_creator_revision(data, t, i)` | `Int` | Creator revision (u32), or `-1`. |
| `acpi_table_body_offset(data, t, i)` | `Int` | Offset of byte 36, or `-1`. |
| `acpi_table_body_length(t, i)` | `Int` | `length - 36`, or `-1`. |
| `acpi_table_span_ok(data, t, i)` | `Bool` | Recorded span fits `data`. |
| `acpi_table_body(data, t, i)` | `Result[Vec[UInt8], Str]` | Copy of the body bytes. |
| `acpi_sum8(data, offset, length)` | `Int` | Byte sum mod 256, or `-1` out of bounds. |
| `acpi_checksum_valid(data, offset, length)` | `Bool` | Range sums to 0 mod 256. |
| `acpi_range_printable(data, offset, length)` | `Bool` | Range exists and is printable ASCII. |
| `acpi_signature_value(s)` | `Int` | Packed u32 of a four-character signature, or `-1`. |
| `acpi_build_table(sig, revision, oem_id, oem_table_id, oem_revision, creator_id, creator_revision, body)` | `Result[Vec[UInt8], Str]` | Canonical 36-byte header + body. |
| `acpi_build_rsdt(entries, oem_id, oem_table_id, creator_id, creator_revision)` | `Result[Vec[UInt8], Str]` | Canonical RSDT with u32 entries. |
| `acpi_build_xsdt(entries, oem_id, oem_table_id, creator_id, creator_revision)` | `Result[Vec[UInt8], Str]` | Canonical XSDT with u64 entries. |
| `acpi_build_rsdp(revision, rsdt_address, xsdt_address, oem_id)` | `Result[Vec[UInt8], Str]` | Canonical 20- or 36-byte RSDP. |

Public constants: `ACPI_RSDP_MIN_LEN` (20), `ACPI_RSDP_REV2_LEN` (36),
`ACPI_SDT_HEADER_LEN` (36), `ACPI_RSDT_SIG` and `ACPI_XSDT_SIG` (packed
signatures).

Errors: `acpi: buffer too short`, `acpi: bad rsdp signature`,
`acpi: bad rsdp checksum`, `acpi: unsupported rsdp revision`,
`acpi: rsdp oem id not printable`, `acpi: bad rsdp length`,
`acpi: bad rsdp extended checksum`, `acpi: no table root`,
`acpi: bad root signature`, `acpi: table address out of range`,
`acpi: table address not aligned`, `acpi: table header out of range`,
`acpi: table signature not printable`, `acpi: table length out of range`,
`acpi: bad table checksum`, `acpi: rsdt length misaligned`,
`acpi: xsdt length misaligned`, `acpi: index out of range`,
`acpi: table span out of bounds`, `acpi: bad signature text`,
`acpi: bad oem id text`, `acpi: bad oem table id text`,
`acpi: bad creator id text`, `acpi: bad revision`, `acpi: bad oem revision`,
`acpi: bad creator revision`, `acpi: table too large`,
`acpi: entry address out of range`, `acpi: rsdp revision must be 0 or 2`,
`acpi: rsdp address out of range`, `acpi: rsdp revision 0 has no xsdt`
(see SPEC.md for the exact conditions and check order).

## Usage

Walk a chain that is already in memory:

```xi
use xiom.acpi;
use xiom.io;

let r = acpi_rsdp_parse(&firmware);           // RSDP at offset 0
match r {
  Ok(p) => {
    io.println("RSDP revision: " + xiom.convert.int_to_string(acpi_rsdp_revision(&p)));
    let w = acpi_tables_from_rsdp(&firmware, &p);
    if w.is_ok {
      let tables: AcpiTableSet = w.value;
      io.println("tables: " + xiom.convert.int_to_string(acpi_table_count(&tables)));
      let i = acpi_find_table(&tables, "FACP");
      if i >= 0 {
        io.println("FACP length: " + xiom.convert.int_to_string(acpi_table_length(&tables, i)));
        let body = acpi_table_body(&firmware, &tables, i);
        if body.is_ok {
          io.println("FACP body bytes: " + xiom.convert.int_to_string(body.value.len()));
        }
      }
    }
  },
  Err(e) => { io.println("RSDP error: " + e); },
}
```

Build a canonical revision 0 chain (RSDP + RSDT + one FACP-like table):

```xi
use xiom.acpi;

var body = Vec[UInt8].new();
body.push(0 as UInt8);
body.push(1 as UInt8);      // ... the rest of the table body

// The table sits at offset 60: 20-byte RSDP + 40-byte RSDT.
let table = acpi_build_table("FACP", 5, "XIOM", "XIOMPKG", 1, "XIOM", 65536, &body);
var entries = Vec[Int].new();
entries.push(60);
let rsdt = acpi_build_rsdt(&entries, "XIOM", "XIOMPKG", "XIOM", 65536);
let rsdp = acpi_build_rsdp(0, 20, 0, "XIOM");
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.acpi
```

Expected: the section-4 namespace check passes, 18 `[PASS]` lines, and a
final `port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Table bodies are opaque.** No AML/DSDT interpretation, no FACS/SLIC
  semantics, no FADT field decoding: the codec stops at the SDT header.
- **No firmware quirks beyond the documented ones.** The RSDP is expected
  at offset 0 (no 16-byte-aligned search over memory ranges); a bad table
  checksum is an error (no tolerated-checksum heuristic); a revision 2
  RSDP with XSDT address 0 falls back to the RSDT (documented).
- **4-byte alignment.** Every root and entry address must be 4-byte
  aligned. ACPI 6.x recommends 8-byte alignment for 64-bit tables; that is
  not enforced.
- **Zero entries are skipped**, not terminated on: an RSDT/XSDT is walked
  to the end of its entry area.
- **u64 addresses above 2^63-1** are held as negative two's-complement
  `Int` values and are rejected as out of range; the builders cannot emit
  them either.
- **Duplicate signatures are tolerated**; `acpi_find_table` returns the
  first match in walk order.
- OEMID / OEM table ID / creator ID printability is not enforced while
  walking (only signatures are); `acpi_range_printable` is provided, and
  the builders enforce printability for their textual inputs.
- The accessors need the original buffer: `AcpiTableSet` stores offsets
  and lengths, not copies. `AcpiRsdp` copies its OEMID bytes.
- Not thread-safe; both result types are plain values.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
