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
| 2026-09-27 | `xiom.bitstream`: MSB/LSB-first bit reader+writer with word sizes 1..64 | `spi` (word 4..16, LSB/MSB), `uart` (frame bits), `eeprom` (Microwire opcode bits), `sd` (bit-built registers), `flac` (UTF-8 coded numbers) | per-package bit loops over `Vec[UInt8]` | open |
| 2026-09-27 | `xiom.varint`: LEB128 + zigzag for 32/64-bit | `avro` (zigzag), `orc` (protobuf wire subset), `thrift` compact-style helpers | private `_uvarint`/`_zigzag` in each package | open |
| 2026-09-27 | `xiom.bytes.cursor`: bounds-checked read cursor over `&Vec[UInt8]` with offset reporting | nearly every codec builds `_Cursor`/`_Acc`/`_Reader` (jpeg `_Acc`, ldap, snmp, orc, pgp, bonjour...) | private cursor structs with duplicated bounds checks | open |
| 2026-09-27 | `xiom.encoding.base64`: encode/decode + line wrapping | `pgp` (ASCII armor), `pem` | private base64 in each | open |
| 2026-09-27 | `xiom.string.utf8`: strict UTF-8 validation and NUL-free `Str` construction (`bytes_to_str_checked`) | `mkv`, `flac`, `png`, `meteorology`, `pgp`, `ldap` -- every codec that turns wire bytes into `Str` must re-validate because `sb_to_str` aborts on 0x00 | per-package `_valid_text`/`_printable` helpers | open |
| 2026-09-27 | `xiom.text.scan`: digit-run parsing (with bounds), case-insensitive ASCII compare, keyword tables | `upnp` (`_digits_value`, `_str_eq_ci`), `meteorology`, `rtc`, `coverage` | private helpers; `str_compare` only does exact compare | open |
| 2026-09-27 | `xiom.float`: IEEE-754 float32/float64 encode/decode and Int<->Float64 bitcast (without `Vec[Float64]`) | `avro` (float/double raw octets), `mkv` (EBML floats as fixed-point), `amqp` (raw 32-bit patterns), `orc` (statistics) | integer fixed-point workarounds, raw octets | open (compiler-dependent, see COMPILER-FINDINGS) |
| 2026-09-27 | `xiom.time.civil`: civil date <-> days-since-epoch, leap-year rules, ISO weekday | `rtc`, `tzif`, `duration`, `coverage`? | private integer math in `rtc` | open |
| 2026-09-27 | `xiom.net.addr`: IPv4/IPv6 parse+render, pseudo-header assembly | `multicast`, `dns`, `bonjour`, `snmp` | per-package packing helpers | open |
| 2026-09-27 | `xiom.bcd`: two-digit BCD pack/unpack with nibble validation | `rtc` (DS1307/PCF8563), `eeprom` (density tables) | private in `rtc` | open |
| 2026-09-27 | `xiom.math.int`: `div_ceil`, half-away-from-zero rounding, fixed-point scaling helpers | `adc` (rounding), `mkv` (milli-units), `coverage` (floor percents) | private expressions everywhere | open |
| 2026-09-27 | `xiom.buf.writer`: append helpers with capacity/length bookkeeping for parallel-Vec models | every codec's `_Acc` struct (see trap 16: parallel Vecs must never drift) | per-package atomic push helpers | open |

## Compiler-shaped requests routed to `docs/COMPILER-FINDINGS.md`

Items that only the compiler can fix (e.g. `&mut Int` write-through,
`Vec[Float64]`, bitcast) are tracked there; this file lists the stdlib-side
unit that would consume the fix.

## Changelog

- 2026-09-27: file created; seeded from waves 18-35 findings (coordinator
  summary of local `_crc*`, `_Cursor`, bit-loop, varint and UTF-8 helpers
  that repeat across packages).
