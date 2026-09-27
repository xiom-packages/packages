# xiom.db2 -- Specification

Status: `implemented` (harness-green with compiler v0.61.3; not published).
Manifest: `package.xi` (`xiom.db2`, version `0.1.0`).
Module: `src/db2.xi` (`module xiom.db2`).
Depends on `xiom.std`. The library module imports `xiom.string`,
`xiom.string.builder`, `xiom.string.compare` and `xiom.convert`; the tests
add `xiom.test`, `xiom.io` and `xiom.encoding.hex`. No FFI.

## Scope

A decode-only structural codec for the IBM Db2 DRDA wire format:

- DSS (Data Stream Structure) frame envelope, chain flags and correlation
  ids, multi-frame message assembly;
- DDM (Distributed Data Management) structures inside a frame, in the
  2-byte and extended 4/6/8-byte length forms;
- codepoint tables (exchange, security, access, SQL, FD:OCA data), with
  unknown codepoints preserved raw;
- typed decoders for common parameter payloads (character data, VCM,
  SECMEC, TYPDEFNAM);
- SQLCARD (SQLCA) and SQLDTA / SQLDTARD FD:OCA row structures;
- deterministic `Err(Str)` diagnostics with byte offsets on every failure.

## Non-goals

- Transports: sockets, TLS, DNS, connection lifecycles, timeouts; the
  codec operates on complete in-memory byte buffers.
- EBCDIC conversion: character payloads that are not printable ASCII are
  preserved raw and flagged opaque; no code-page is guessed.
- Encryption / authentication: security tokens (`SECTKN`) and the
  encrypted security mechanisms are carried as opaque bytes only.
- Layer-B streaming (DDM length marker `0x8004`) and DSS length
  continuation (`0x8000` in the 2-byte DSS length) for EXTDTA / QRYDTA
  payloads larger than one DSS: recognized, rejected with dedicated
  errors, not reassembled.
- An encoder: the module decodes; the only writers are the tests' byte
  builders.
- SQL text analysis, FD:OCA triplet interpretation beyond type/length,
  server-side behavior.

## Verification sources

The byte layouts and codepoint values were verified against two
independent implementations before being implemented here:

- Apache Derby (Apache-2.0), `org.apache.derby.impl.drda`:
  `DDMReader.readDssHeader`, `DDMReader.readLengthAndCodePoint`,
  `DssConstants`, `CodePoint`.
- pydrda (MIT), `drda/ddm.py` and `drda/codepoint.py`, a pure-Python Db2
  client that talks to real servers.

Where the porting mandate's codepoint list disagreed with both, the
verified value is implemented; see "Mandate reconciliation" below.

## DSS frame

Header (6 bytes), all multi-byte integers big-endian:

| Offset | Size | Field | Meaning |
|---|---|---|---|
| 0 | 2 | length | total DSS length including this header (min 6, max 32767) |
| 2 | 1 | magic | always `0xD0` |
| 3 | 1 | format | flags (high nibble) + DSS type (low nibble) |
| 4 | 2 | correlation id | ties requests to replies |

Format byte:

| Bit | Mask | Meaning |
|---|---|---|
| 7 | `0x80` | reserved, must be 0 (rejected) |
| 6 | `0x40` | chained: another DSS follows this one |
| 5 | `0x20` | continue on error (only meaningful when chained) |
| 4 | `0x10` | next chained DSS has the same correlation id |
| 0-3 | `0x0F` | DSS type: 1 request, 2 reply, 3 object, 4 communications, 5 request-without-reply |

Validation performed by `db2_frame_parse`, in order (each error carries
the byte offset):

1. 6 header bytes present, else `db2: truncated input at offset N`;
2. length bit `0x8000` clear, else `db2: continued (large) DSS length
   0xNNNN not supported by db2_frame_parse at offset N`;
3. length >= 6, else `db2: DSS length N below minimum 6 at offset N`;
4. length fits the buffer, else `db2: DSS length N overruns buffer (M
   bytes remain) at offset N`;
5. magic `0xD0`, else `db2: bad DSS magic 0xNN at offset N (expected
   0xD0)`;
6. format bit `0x80` clear, else `db2: DSS format bit 0x80 set at offset
   N`;
7. an unchained DSS must not set `0x10` or `0x20`, else `db2:
   same-correlation bit set on unchained DSS at offset N` / `db2:
   continue-on-error bit set on unchained DSS at offset N`.

Unknown DSS type nibbles are accepted and named `UNKNOWN`; the frame
keeps the raw format byte.

### Note on a conflicting third-party description

The `db2-node` project's protocol notes describe the format byte as bit 0
chained (`0x01`), bit 1 continue-on-error (`0x02`), bit 2 same
correlation (`0x04`) and bits 3-4 type, which is self-inconsistent with
its own DSS type values and contradicts both Derby and pydrda. This codec
implements the Derby/pydrda layout above, which matches real Db2 traffic.

### Multi-frame assembly (`db2_frames_assemble`)

- frames are parsed in order; consecutive frames whose chained flag is
  set concatenate into one message payload;
- when a chained frame has the same-correlation flag, the next frame's
  correlation id must equal it, else `db2: correlation id N changed
  mid-chain (expected M) at offset K`;
- a final chained frame without a successor is `db2: chained DSS has no
  following frame at offset N`;
- `Db2Messages.correlations[i]` / `types[i]` come from the first frame of
  message i; `frame_counts[i]` counts its frames; `consumed` is the total
  number of input bytes used.

## DDM structures

Inside a DSS payload, DDMs repeat. The wire order is **length then
codepoint** (Derby `readLengthAndCodePoint` reads `ddmScalarLen` first;
pydrda `parse_reply` reads the 2-byte length first):

Short form:

| Part | Size | Value |
|---|---|---|
| length | 2 | total length including this 4-byte header; >= 4 |
| codepoint | 2 | command / parameter / data code |
| payload | length-4 | structure body |

Extended form: the 2-byte length carries the `0x8000` marker plus the
number of extended length bytes; the extended length follows the
codepoint:

| Marker | Layout | Extended value | Payload |
|---|---|---|---|
| `0x8008` | length(2) + cp(2) + total(4) | u32 total, includes the 8-byte header | total-8 |
| `0x800A` | length(2) + cp(2) + total(6) | u48 total, includes the 10-byte header | total-10 |
| `0x800C` | length(2) + cp(2) + total(8) | u64 total, includes the 12-byte header; top bit must be clear | total-12 |
| `0x8004` | length(2) + cp(2) + stream | layer-B streaming, no inline length | rejected |

Rejections (all with offsets): invalid extended marker
(`db2: invalid extended DDM length marker 0xNNNN at offset N`), streaming
form, truncated extended length, an 8-byte value with the top bit set
(`db2: extended DDM length exceeds signed range at offset N`), a total
below the header size, and overruns.

### Advisory long-length table (`db2_cp_is_long_length`)

The mandate asks for a table of the "four-byte-length set (SQLDTA-style)".
The wire always signals the form in the length marker, so the decoder
never needs the table; it is advisory and used by `db2_ddm_read_as` when a
caller wants to enforce an expectation. The FD:OCA-bearing codepoints
peers commonly write in the extended form:

| Codepoint | Name |
|---|---|
| `0x2408` | SQLCARD |
| `0x2411` | SQLDARD |
| `0x2412` | SQLDTA |
| `0x2413` | SQLDTARD |
| `0x2414` | SQLSTT |
| `0x241A` | QRYDSC |
| `0x241B` | QRYDTA |
| `0x2450` | SQLATTR |
| `0x146C` | EXTDTA |

Unknown codepoints are always preserved raw in `Db2Ddm.payload` and are
returned with `db2_cp_name == ""`.

## Codepoint tables (implemented subset)

Commands:

| Code | Name | Meaning |
|---|---|---|
| `0x1041` | EXCSAT | exchange server attributes |
| `0x106D` | ACCSEC | access security |
| `0x106E` | SECCHK | security check |
| `0x2001` | ACCRDB | access relational database |
| `0x2002` | BGNBND | begin package bind |
| `0x2004` | BNDSQLSTT | bind SQL statement |
| `0x2005` | CLSQRY | close query |
| `0x2006` | CNTQRY | continue query |
| `0x2007` | DRPPKG | drop package |
| `0x2008` | DSCSQLSTT | describe SQL statement |
| `0x2009` | ENDBND | end package bind |
| `0x200A` | EXCSQLIMM | execute SQL immediately |
| `0x200B` | EXCSQLSTT | execute SQL statement |
| `0x200C` | OPNQRY | open query |
| `0x200D` | PRPSQLSTT | prepare SQL statement |
| `0x200E` | RDBCMM | commit |
| `0x200F` | RDBRLLBCK | rollback |
| `0x2010` | REBIND | rebind package |
| `0x2012` | DSCRDBTBL | describe RDB table |
| `0x2014` | EXCSQLSET | execute SQL set |
| `0x1055`, `0x1069`, `0x106F` | SYNCCTL, SYNCRSY, SYNCLOG | sync point commands |

Parameters:

| Code | Name |
|---|---|
| `0x002F` | TYPDEFNAM |
| `0x0035` | TYPDEFOVR |
| `0x112E` | PRDID |
| `0x1147` | SRVCLSNM |
| `0x115A` | SRVRLSLV |
| `0x115E` | EXTNAM |
| `0x116D` | SRVNAM |
| `0x11A0` | USRID (mandate: USERID) |
| `0x11A1` | PASSWORD |
| `0x11A2` | SECMEC |
| `0x11A4` | SECCHKCD |
| `0x11DC` | SECTKN |
| `0x1404` | MGRLVLLS |
| `0x2105` | RDBCMTOK |
| `0x2109` | PKGID |
| `0x210D` | PKGCNSTKN |
| `0x210F` | RDBACCCL |
| `0x2110` | RDBNAM |
| `0x2113` | PKGNAMCSN |
| `0x2114` | QRYBLKSZ |
| `0x2116` | RTNSQLDA |
| `0x2120` / `0x2121` | STTSTRDEL / STTDECDEL |
| `0x2124` | SQLSTT(?) -- mandate-listed, unverified (see below) |
| `0x2135` | CRRTKN |
| `0x2140` | MAXRSLCNT |
| `0x2141` | MAXBLKEXT |
| `0x2146` | TYPSQLDA |
| `0x2148` | RTNEXTDTA |
| `0x214B` | DYNDTAFMT |
| `0x215B` | QRYINSID |
| `0x215D` | QRYCLSIMP |

SQL / FD:OCA data and reply messages:

| Code | Name |
|---|---|
| `0x0010` | FDODSC |
| `0x146C` | EXTDTA |
| `0x147A` | FDODTA |
| `0x2408` | SQLCARD |
| `0x240B` | SQLCINRD |
| `0x240E` | SQLRSLRD |
| `0x2411` | SQLDARD |
| `0x2412` | SQLDTA |
| `0x2413` | SQLDTARD |
| `0x2414` | SQLSTT |
| `0x2419` | SQLSTTVRB |
| `0x241A` | QRYDSC |
| `0x241B` | QRYDTA |
| `0x2450` | SQLATTR |
| `0x1443`, `0x14AC` | EXCSATRD, ACCSECRD |
| `0x1219` | SECCHKRM |
| `0x2201` | ACCRDBRM |
| `0x2205`, `0x220B`, `0x220C` | OPNQRYRM, ENDQRYRM, ENDUOWRM |
| `0x2211`, `0x2213`, `0x2218`, `0x221A` | RDBNFNRM, SQLERRRM, RDBUPDRM, RDBAFLRM |
| `0x124C`, `0x1254` | SYNTAXRM, CMDCHKRM |

### Mandate reconciliation

The porting mandate's numeric list disagreed with Derby and pydrda (which
agree with each other) in these places; the verified value is implemented
and covered by tests:

| Codepoint | Mandate value | Implemented | Note |
|---|---|---|---|
| EXCSQLSTT | `0x2005` | `0x200B` | `0x2005` is CLSQRY |
| OPNQRY | `0x2008` | `0x200C` | `0x2008` is DSCSQLSTT |
| ENDBND | `0x2003` | `0x2009` | `0x2003` is unassigned in both sources |
| CLSQRY | `0x200C` | `0x2005` | see above |
| DSCRDBTBL | `0x2007` | `0x2012` | `0x2007` is DRPPKG |
| DSCSQLSTT | `0x2004` | `0x2008` | `0x2004` is BNDSQLSTT |
| RDBACCCL | `0x2114` | `0x210F` | `0x2114` is QRYBLKSZ (mandate itself notes the ambiguity) |
| FDODSC | `0x002C` | `0x0010` | `0x002C` is not a defined DDM codepoint |
| SQLDTARD | `0x2411` | `0x2413` | `0x2411` is SQLDARD |
| SQLSTT parameter | `0x2124` | exposed as `db2_cp_sqlstt_parameter()` | not corroborated by either source; preserved raw, named `SQLSTT(?)` |
| USERID | `0x11A0` | `0x11A0` (named USRID) | same value, Derby name |
| QRYBLKSZ | `0x2114` | `0x2114` | verified |

## Typed parameter decoders

Character data (`SRVNAM`, `EXTNAM`, `PRDID`, `RDBNAM`, `USRID`,
`PASSWORD`, ...): the payload is the string bytes with no length prefix
(the DDM length delimits it). `db2_text_ascii` decodes only printable
ASCII (`0x20..0x7E`); any other byte leaves `text == ""`, `ascii == false`
and the raw bytes in `bytes` (EBCDIC is opaque by design).
`db2_text_nul_terminated` stops at the first `0x00` (the "NUL-ish" string
convention, e.g. TYPDEFNAM values). `db2_text_trimmed` strips trailing
spaces.

VCM (`db2_vcm_read`): 2-byte big-endian length then that many bytes,
decoded like `db2_text_ascii`; on overrun the error is `db2: truncated
VCM at offset N`. Used inside SQLCARD's diagnostic group.

SECMEC (`db2_secmec_parse`): one or more 2-byte big-endian security
mechanism values; an odd payload length is `db2: odd SECMEC payload
length N at offset 0`. Names: 1 DCESEC, 3 USRIDPWD, 4 USRIDONL,
5 USRIDNWPWD, 6 USRSBSPWD, 7 USRENCPWD, 8 USRSSBPWD, 9 EUSRIDPWD,
10 EUSRIDNWPWD.

TYPDEFNAM byte order (`db2_tydefnam_byteorder`): QTDSQLX86 -> little
(1), QTDSQL370 / QTDSQL400 -> big (0), anything else unknown (-1).
SQLCODE and SQLERRD are interpreted in this order.

## SQLCARD (SQLCA reply data)

`db2_sqlcard_parse(payload, byteorder)`:

- payload `[0xFF]` alone: the "no SQLCA" form -> `present == false`;
- otherwise byte 0 is the SQLCAGRP flag and must be `0x00`
  (`db2: SQLCARD group flag 0xNN invalid at offset 0`), then:

| Offset | Size | Field |
|---|---|---|
| 0 | 1 | SQLCAGRP flag (`0x00`) |
| 1 | 4 | SQLCODE, signed, platform byte order |
| 5 | 5 | SQLSTATE (ASCII) |
| 10 | 8 | SQLERRPROC |
| 18 | 1 | SQLCAXGRP flag |
| 19 | 24 | SQLERRD: 6 x i32 platform order (update count = SQLERRD[2]) |
| 43 | 11 | SQLWARN |

Byte 18 `0x00` means the extended group is present (fixed size 54);
`0xFF` means it is absent (fixed size 19). Any other value is
`db2: SQLCARD extended group flag 0xNN invalid at offset 18`.

After the fixed part the SQLDIAGGRP fields are read as VCMs, in order:
SQLRDBNAM, SQLERRMSGC, SQLERRMSGS. The message is SQLERRMSGC when
non-empty, otherwise SQLERRMSGS; `message_bytes` preserves it raw.
Remaining bytes (including the trailing `0xFF` SQLDIAGGRP marker some
peers send) are preserved in `diag_tail`. A short fixed part is `db2:
SQLCARD too short (N bytes, need 19/54) at offset 0`; a missing or
truncated VCM propagates `db2: truncated VCM at offset N`.

The 54-byte fixed layout and the VCM trailer follow pydrda's SQLCARD
reader (which in turn matches observed Db2 traffic); it is the strongest
cross-checked description available to this port.

## SQLDTA / SQLDTARD (FD:OCA rows)

`db2_sqldta_parse(payload)` walks the payload as a flat DDM list, finds
FDODSC (`0x0010`) and FDODTA (`0x147A`), then decodes:

FDODSC payload:

| Part | Size | Value |
|---|---|---|
| descriptor length | 1 | bytes from offset 0 to the end of the descriptor block |
| marker | 2 | `0x76 0xD0` |
| triplets | 3 x count | 1-byte type + 2-byte big-endian length |
| trailer | rest | preserved raw (e.g. `06 71 E4 D0 00 01`) |

A triplet length of `0x3FFF` marks a variable-length column. Errors:
`db2: FDODSC descriptor too short (N bytes) at offset 0`, `db2: FDODSC
descriptor length N invalid at offset 0`, `db2: FDODSC marker 0xNNNN
(expected 0x76D0) at offset 1`, `db2: FDODSC triplet bytes N not a
multiple of 3 at offset 0`.

FDODTA payload: for each descriptor triplet, in order:

- 1-byte null indicator: `0x00` = value present, `0xFF` = SQL NULL;
  anything else is `db2: invalid FDODTA null indicator N at offset N`;
- fixed-length triplet: exactly that many bytes;
- variable-length triplet (`0x3FFF`): 2-byte big-endian length then that
  many bytes.

Truncation inside a fixed value is `db2: truncated FDODTA value at offset
N`; the row reports `col_count`, the parallel `null_flags` / `values`
vectors and `consumed` bytes. Missing nested codepoints are `db2: SQLDTA
missing FDODSC at offset 0` / `db2: SQLDTA missing FDODTA at offset 0`.

QRYDTA (`0x241B`) uses the same FD:OCA data model; `RDBAFLRM` carries the
access-failure diagnostics and is named but not decoded. QRYDTA payloads
larger than one DSS arrive as layer-B streams (`0x8004`), which this
module rejects rather than reassembles.

## Error catalog

All messages are prefixed `db2:`; the offset is the failing read's byte
position within the buffer given to that reader (frame offsets are
absolute in the input buffer; DDM/descriptor/card offsets are relative to
the payload passed in).

| Template | Trigger |
|---|---|
| `truncated input at offset N` | reader underrun |
| `negative read length N at offset N` | internal guard |
| `truncated DSS header` -> truncation | fewer than 6 header bytes |
| `continued (large) DSS length 0xNNNN not supported by db2_frame_parse at offset N` | `0x8000` length bit |
| `DSS length N below minimum 6 at offset N` | short length |
| `DSS length N overruns buffer (M bytes remain) at offset N` | length past end |
| `bad DSS magic 0xNN at offset N (expected 0xD0)` | magic mismatch |
| `DSS format bit 0x80 set at offset N` | reserved bit |
| `same-correlation bit set on unchained DSS at offset N` | flag misuse |
| `continue-on-error bit set on unchained DSS at offset N` | flag misuse |
| `correlation id N changed mid-chain (expected M) at offset K` | assembly check |
| `chained DSS has no following frame at offset N` | assembly check |
| `truncated DDM length at offset N` | DDM underrun |
| `truncated DDM codepoint at offset N` | DDM underrun |
| `DDM length N below minimum 4 at offset N` | short DDM |
| `DDM length N overruns buffer (M bytes remain) at offset N` | DDM past end |
| `invalid extended DDM length marker 0xNNNN at offset N` | bad marker |
| `layer-B streaming DDM length 0x8004 not supported for codepoint 0xNNNN at offset N` | streaming form |
| `truncated extended DDM length at offset N` | ext underrun |
| `extended DDM length exceeds signed range at offset N` | u64 top bit |
| `extended DDM length N below header size M at offset N` | short ext total |
| `DDM 0xNNNN is not in extended length form at offset N` | `db2_ddm_read_as(true)` |
| `DDM 0xNNNN is unexpectedly in extended length form at offset N` | `db2_ddm_read_as(false)` |
| `truncated VCM at offset N` | VCM underrun |
| `odd SECMEC payload length N at offset 0` | SECMEC odd bytes |
| `FDODSC descriptor too short (N bytes) at offset 0` | < 3 bytes |
| `FDODSC descriptor length N invalid at offset 0` | out of range |
| `FDODSC marker 0xNNNN (expected 0x76D0) at offset 1` | bad marker |
| `FDODSC triplet bytes N not a multiple of 3 at offset 0` | bad length |
| `SQLDTA missing FDODSC at offset 0` | no descriptor |
| `SQLDTA missing FDODTA at offset 0` | no data |
| `invalid FDODTA null indicator N at offset N` | bad indicator |
| `truncated FDODTA value at offset N` | value past payload |
| `empty SQLCARD at offset 0` | zero-length payload |
| `SQLCARD group flag 0xNN invalid at offset 0` | bad flag |
| `SQLCARD too short (N bytes, need 19) at offset 0` | < 19 bytes |
| `SQLCARD too short (N bytes, need 54) at offset 0` | extended group truncated |
| `SQLCARD extended group flag 0xNN invalid at offset 18` | bad xgrp flag |

## Complexity and limits

| Function | Complexity |
|---|---|
| `db2_frame_parse` | O(payload) |
| `db2_frames_assemble` | O(input) |
| `db2_ddm_read` / `db2_ddms_parse` | O(length) |
| `db2_fdodsc_parse` / `db2_fdodta_parse` / `db2_sqldta_parse` | O(payload) |
| `db2_sqlcard_parse` | O(payload) |
| codepoint accessors / names / predicates | O(1) |

Values must fit the signed 64-bit platform `Int`; the 8-byte extended DDM
length form with the top bit set is rejected rather than wrapped.

## v0.61.3 notes

- free functions only; flat and parallel vectors, never
  `Vec[StructType]`; struct fields are never passed as `&struct.field`
  where a `&Vec[UInt8]` parameter is expected;
- Ok/Err construction is confined to leaf helpers;
- every byte read is widened with `(b as Int) & 0xFF`;
- big-endian composition uses explicit byte multiplication;
- `Str` output is collected in a `Vec[UInt8]` and materialized with
  `sb_to_str` only after the bytes were validated NUL-free (opaque text
  never reaches it);
- `&mut Int` out-parameters are avoided (readers return values).
