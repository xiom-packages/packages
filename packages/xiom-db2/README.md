# xiom.db2

> **Status:** `incubating` -- conformance-tested (22/22); published at `v0.1.2` on the XIOM registry.
> **Scope:** IBM Db2 DRDA / DSS wire **structure** codec. DSS frames, DDM
> codepoints and parameters, SQLCARD and SQLDTA decoding; decode-only.
> **Deps:** `xiom.std` only. No FFI, no sockets, no EBCDIC conversion.

## What it is

A pure-XIOM structural codec for the DRDA wire format used by IBM Db2 (LUW,
z/OS, i) over TCP port 50000. It turns in-memory byte buffers -- as they
would arrive from any transport -- into typed structures, and rejects
malformed input with deterministic errors carrying byte offsets.

Implemented:

- **DSS frame envelope**: 2-byte big-endian length (includes the 6-byte
  header), magic `0xD0`, format byte (chain flags + DSS type nibble),
  2-byte correlation id, plus `db2_frames_assemble`, which concatenates
  chained frames into message payloads and enforces same-correlation
  chains;
- **DDM structures** inside a frame: `[length:2][codepoint:2][payload]`,
  with the extended 4/6/8-byte length forms (`0x8008`/`0x800A`/`0x800C`)
  and the layer-B streaming marker (`0x8004`) rejected with dedicated
  errors; unknown codepoints are preserved raw;
- **codepoint tables**: exchange (EXCSAT), security (ACCSEC, SECCHK),
  access (ACCRDB, OPNQRY, CLSQRY, ...), SQL (EXCSQLSTT, PRPSQLSTT,
  EXCSQLIMM, ...) and the SQL/FD:OCA data codepoints, with
  `db2_cp_name`, `db2_cp_known` and category predicates;
- **typed decoders** for `SRVNAM`/`EXTNAM`/`PRDID`/`RDBNAM` character data
  (printable ASCII decoded; anything else -- EBCDIC in particular -- kept
  raw and flagged opaque), VCM length-prefixed strings, `SECMEC` u16 lists
  and `TYPDEFNAM` names (with the QTDSQLX86/370/400 byte-order mapping);
- **reply structures**: SQLCARD (SQLCA SQLCODE / SQLSTATE / SQLERRD update
  count / SQLWARN and the VCM message text in both platform byte orders)
  and SQLDTA / SQLDTARD FD:OCA descriptors and rows with per-column null
  indicators.

## API sketch

```xi
use xiom.db2;

var r = db2_reader_new(bytes);
let fr = db2_frame_parse(&mut r);           // -> Result[Db2Frame, Str]
let msgs = db2_frames_assemble(bytes);      // chain-aware assembly
let ddms = db2_ddms_parse(fr.value.payload); // flat DDM list
let card = db2_sqlcard_parse(card_payload, db2_byteorder_little());
let row  = db2_sqldta_parse(dta_payload);   // FD:OCA row with nulls
```

The full surface (readers, codepoint accessors, text/VCM/SECMEC decoders,
descriptor and row decoders, error strings) is specified in SPEC.md.

## Tests

```
& .\scripts\port.ps1 -Package xiom.db2     # from the repo root
```

Expected tail: `port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.
Every frame, descriptor and card in the suite is built synthetically
in-test from hex literals; there is no network and no external data.

## Honest boundaries

- Decode-only: there is no encoder. The writers live in the tests as
  byte builders.
- No EBCDIC conversion: `db2_text_ascii` flags non-printable payloads as
  opaque and preserves their raw bytes; it never guesses a code page.
- The porting mandate's codepoint list disagreed with both verified
  sources (Apache Derby and pydrda) in several places; the verified values
  are implemented and every delta is recorded in SPEC.md.
- Layer-B streaming (`0x8004`) and the DSS length-continuation bit
  (`0x8000`) are recognized and rejected; reassembling a >32 KB EXTDTA /
  QRYDTA stream is out of scope.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
