# Stdlib wishlist -- what the package ecosystem wants from `xiom.std`

Shared coordination file between the **packages session** (this repo) and the
**stdlib session** (`E:\xiom-lang\stdlib`). Packages and agents report gaps
while building; the packages coordinator appends them here; the stdlib
session reads this file and grows the stdlib in its own lane. Nothing here
is a gate -- it is a prioritized idea dump so stdlib and packages grow
hand to hand.

Contracts (both lanes):

- A wishlist item is **not** a request to break the stdlib; it is evidence
  that N packages re-implemented the same helper. `Count` shows how many
  packages currently carry a local copy.
- New package module names must stay unique across **both** trees: the
  packages side runs `scripts/namespace-check.ps1 -Module <name>` (it scans
  the stdlib namespaces and every package manifest). The stdlib side
  cross-checks against `docs/PACKAGE-NAMESPACES.txt` (a generated snapshot,
  refreshed at every wrap -- run `scripts/export-namespaces.ps1`).
- When the stdlib ships one of these, the stdlib session may note it in the
  `Status` column; packages can then drop their local copies at their next
  touch (never as a drive-by refactor of a green package).

Format: `| Date | Need | Why (requesters) | Local workaround today | Status |`

## Open items

| Date | Need | Why (requesters) | Local workaround today | Status |
|---|---|---|---|---|
| 2026-09-27 | `xiom.checksum`: crc32 (reflected 0xEDB88320), crc8 (poly 0x07 + others), crc7 (x^7+x^3+1), crc24 (OpenPGP), ones-complement internet checksum (incl. ICMPv6 pseudo-header), adler32 | ~8 packages re-implement: `png` (crc32), `flac` (crc8), `i2c` (PEC crc8), `sd` (crc7), `pgp` (crc24), `multicast` (IGMP/MLD), `pcf`-era packages | private `_crc*` helpers per package, tableless bit loops | open |
| 2026-09-27 | `xiom.bitstream`: MSB/LSB-first bit reader+writer with word sizes 1..64 | `spi` (word 4..16, LSB/MSB), `uart` (frame bits), `eeprom` (Microwire opcode bits), `sd` (bit-built registers), `flac` (UTF-8 coded numbers), `gpio` (line flags), `interrupt` (IDT/GIC bitfields), `flash` (status/SFDP bits) | per-package bit loops over `Vec[UInt8]` | open |
| 2026-09-27 | `xiom.varint`: LEB128 + zigzag for 32/64-bit | `avro` (zigzag), `orc` (protobuf wire subset), `thrift` compact-style helpers | private `_uvarint`/`_zigzag` in each package | open |
| 2026-09-27 | `xiom.bytes.cursor`: bounds-checked read cursor over `&Vec[UInt8]` with offset reporting | nearly every codec builds `_Cursor`/`_Acc`/`_Reader` (jpeg `_Acc`, ldap, snmp, orc, pgp, bonjour, `pki` DER walker, `apple` struct readers, `flash` LE readers...) | private cursor structs with duplicated bounds checks | open |
| 2026-09-27 | `xiom.encoding.base64`: encode/decode + line wrapping | `pgp` (ASCII armor), `pem` | private base64 in each | open |
| 2026-09-27 | `xiom.string.utf8`: strict UTF-8 validation and NUL-free `Str` construction (`bytes_to_str_checked`) | `mkv`, `flac`, `png`, `meteorology`, `pgp`, `ldap` -- every codec that turns wire bytes into `Str` must re-validate because `sb_to_str` aborts on 0x00 | per-package `_valid_text`/`_printable` helpers | open |
| 2026-09-27 | `xiom.text.scan`: digit-run parsing (with bounds), case-insensitive ASCII compare, keyword tables | `upnp` (`_digits_value`, `_str_eq_ci`), `meteorology`, `rtc`, `coverage`, `nats` (capped decimal parser with overflow guard), `geology` (offset-carrying tokens), `l10n-currency` (`_matches_ci_at`), `biology` (offset line scanner) | private helpers; `str_compare` only does exact compare | open |
| 2026-09-27 | `xiom.float`: IEEE-754 float32/float64 encode/decode and Int<->Float64 bitcast (without `Vec[Float64]`) | `avro` (float/double raw octets), `mkv` (EBML floats as fixed-point), `amqp` (raw 32-bit patterns), `orc` (statistics) | integer fixed-point workarounds, raw octets | open (compiler-dependent, see COMPILER-FINDINGS) |
| 2026-09-27 | `xiom.time.civil`: civil date <-> days-since-epoch, leap-year rules, ISO weekday | `rtc`, `tzif`, `duration`, `coverage`?, `pki` (UTCTime/GeneralizedTime digit-pair parsing) | private integer math in `rtc` | open |
| 2026-09-27 | `xiom.net.addr`: IPv4/IPv6 parse+render, pseudo-header assembly | `multicast`, `dns`, `bonjour`, `snmp` | per-package packing helpers | open |
| 2026-09-27 | `xiom.bcd`: two-digit BCD pack/unpack with nibble validation | `rtc` (DS1307/PCF8563), `eeprom` (density tables) | private in `rtc` | open |
| 2026-09-27 | `xiom.math.int`: `div_ceil`, half-away-from-zero rounding, fixed-point scaling helpers | `adc` (rounding), `mkv` (milli-units), `coverage` (floor percents), `geology` (div/pad), `l10n-currency` (half-away rounding), `interrupt` (floor-div/remainder) | private expressions everywhere | open |
| 2026-09-27 | `xiom.buf.writer`: append helpers with capacity/length bookkeeping for parallel-Vec models | every codec's `_Acc` struct, `biology` (19-vector `BioBatch`), `geology` (`RowParse` carriers), `flash` (cat/zeros) (see trap 16: parallel Vecs must never drift) | per-package atomic push helpers | open |
| 2026-09-27 | `xiom.result`: ergonomic construction for struct-payload `Result`s (per-type leaf constructors; maybe `map`/`?`) | `nats` (leaf `Ok`/`Err` per payload type: `Vec[UInt8]`, `Int`, `Bool`, `NatsOp`, `(Int,Int)`), `i2c` (`_ok_*`/`_err_*` leaves), plus every wave-36 package (`pki`, `apple`, `merkle`, `interrupt`, `flash`, `gpio`, `geology`, `l10n-currency`) | one `_ok_*`/`_err_*` leaf per payload type per package (trap 6) | open |
| 2026-09-27 | `xiom.serialize.json`: raw-byte, format-preserving JSON key lookup (boundary-checked key spans, scalar values) | `nats` (INFO/CONNECT key lookups; `xiom.serialize.json` round-trips and cannot do raw-byte lookups) | private key-span scanner in `nats` | open |
| 2026-09-27 | Core decimal formatting usable from dependency-free library modules (`int_to_string` without an import, zero-padded width, simple `Str` interpolation) | `i2c` re-implemented `_dec` because importing `xiom.convert.int.int_to_string` breaks the zero-import style of codec modules; `geology` `_pad3`; `apple` finds `use xiom.convert.itos; itos.itos(n)` awkward; `pki`/`interrupt`/`flash`/`biology` build every error with `+` chains of `int_to_string` | private `_dec`/`_pad*` per dependency-free package | open |
| 2026-09-27 | `xiom.test.bytes`: conformance fixture builders (`bytes_of`/`bytes_equal`/`cat`/`bin`) plus hex-expectation helpers | `nats`, `gpio`, `flash`, `l10n-currency`, `interrupt` (hand-rolled fixtures + `xiom.encoding.hex`), repeated across most wave suites | per-suite private fixture helpers | open |
| 2026-09-27 | `xiom.encoding.hex`: byte<->hex encode/decode with zero-padded output | `pki`, `apple`, `gpio`, `flash`, `merkle` (all hand-rolled `_hex*`/`hb` helpers; `int_to_hex` does not pad) | private hex helpers per package | open |
| 2026-09-27 | `xiom.string.cstr`: NUL-padded fixed-size C-string field decode/encode (trim at first NUL, never build past it) + length validator | `gpio` (`_cstr32`/`_put_cstr32`), `apple` (`_scan_cstr`) | private cstr helpers per package | open |
| 2026-09-27 | `xiom.encoding.le`: unsigned LE16/24/32/64 + BE readers/writers over `Vec[UInt8]` with bounds and range errors | `flash` (`_le32`, 24-bit pointers), `apple` (`_rdu`), `gpio` (`_u32_le`/`_u64_le`), `interrupt` (LE MMIO words) | explicit byte composition per package | open |
| 2026-09-27 | `xiom.bits.u32`: proven unsigned 32/64-bit word ops (rotr/shr/and/not, safe bit-get) that avoid the bit-31 masks | `merkle` (SHA-256 `rotr32`/`and32` via the `(a+b-(a^b))/2` identity), `interrupt`/`gpio`/`apple` (bitfield extraction) | divisor/modulo arithmetic per package | open |
| 2026-09-27 | `xiom.hash.sha256`: pure-XIOM, byte-native SHA-256 (`hash.sha256(&Vec[UInt8]) -> Vec[UInt8]`) | `merkle` (hand-rolled FIPS 180-4, ~250 lines; `xiom.crypto.sha256` is FFI-backed, `xiom.crypto.sha` is legacy `Vec[Int]`) | internal `_sha256` in `merkle` | open |
| 2026-09-27 | `xiom.l10n.iso4217`: ISO 4217 data module with a compilable table | `l10n-currency` (165-row table compiled into comparison chains because module-level table initializers mis-materialize on v0.61.3) | chained comparisons + accessor switch | open |
| 2026-09-27 | `xiom.string.bytes`: `str_bytes(s) -> Vec[UInt8]`, `sb_push_range(sb, s, start, end)`, `str_find(s, needle, from) -> Int` (no Option) | `gpio` (`byte_at` loops), `biology` (offset line scanner `_line_at`), `geology` (`_find_sub`), `pki` (dotted-OID rendering), `l10n-currency` (`_matches_ci_at`) | per-package byte loops over `str_compare`/`byte_at` | open |
| 2026-09-27 | `xiom.err.at`: standard offset-carrying error idiom (`err_at(label, off, msg)`) | `gpio`, `interrupt`, `biology`, `pki`, `geology` (every error rebuilt via `+` chains of `int_to_string`) | per-package `_err_at`/`_range_err` helpers | open |

## Compiler-shaped requests routed to `docs/COMPILER-FINDINGS.md`

Items that only the compiler can fix (e.g. `&mut Int` write-through,
`Vec[Float64]`, bitcast) are tracked there; this file lists the stdlib-side
unit that would consume the fix.

## Changelog

- 2026-09-27: file created; seeded from waves 18-35 findings (coordinator
  summary of local `_crc*`, `_Cursor`, bit-loop, varint and UTF-8 helpers
  that repeat across packages).
- 2026-09-27: wave-34 straggler reports appended (`i2c`, `nats`):
  result-constructor ergonomics, raw-byte JSON key lookup, zero-import int
  formatting, conformance byte fixtures; `nats` added to `xiom.text.scan`.
- 2026-09-27: wave-36 reports appended (9 of 10: `pki`, `merkle`, `apple`,
  `geology`, `biology`, `l10n-currency`, `gpio`, `interrupt`, `flash`;
  `tls` pending): new rows for `encoding.hex`, `string.cstr`,
  `encoding.le`, `bits.u32`, `hash.sha256`, `l10n.iso4217`,
  `string.bytes`, `err.at`; requesters extended on `bitstream`,
  `bytes.cursor`, `math.int`, `text.scan`, `time.civil`, `buf.writer`,
  `result`, `test.bytes`, and the convert-ergonomics row.
