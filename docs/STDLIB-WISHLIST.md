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
| 2026-09-27 | `xiom.checksum`: crc32 (reflected 0xEDB88320), crc8 (poly 0x07 + others), crc7 (x^7+x^3+1), crc24 (OpenPGP), crc32c (Castagnoli 0x82F63B78 + LevelDB rotation mask), ones-complement internet checksum (incl. ICMPv6 pseudo-header), adler32 | ~11 packages re-implement: `png` (crc32), `flac` (crc8), `i2c` (PEC crc8), `sd` (crc7), `pgp` (crc24), `multicast` (IGMP/MLD), `proxy` (CRC32C TLV), `leveldb` (masked CRC32C log/block trailers), `git2` (reflected IEEE CRC-32 for pack idx -- absent from `xiom.hash.crc` families), `badger` (CRC32C), `pcf`-era packages | private `_crc*` helpers per package, tableless bit loops | open |
| 2026-09-27 | `xiom.bitstream`: MSB/LSB-first bit reader+writer with word sizes 1..64 | `spi` (word 4..16, LSB/MSB), `uart` (frame bits), `eeprom` (Microwire opcode bits), `sd` (bit-built registers), `flac` (UTF-8 coded numbers), `gpio` (line flags), `interrupt` (IDT/GIC bitfields), `flash` (status/SFDP bits) | per-package bit loops over `Vec[UInt8]` | open |
| 2026-09-27 | `xiom.varint`: LEB128 + zigzag for 32/64-bit | `avro` (zigzag), `orc` (protobuf wire subset), `thrift` compact-style helpers, `pulsar` (protobuf varint with 10-byte/overflow rejection), `leveldb` (LEB128 u32/u64 with consumed counts and signed-range rejection), `bitcoin` (CompactSize + legacy varint); `audio-meta` (MIDI MSB-first 7-bit varlen -- LEB128 does not cover it) | private `_uvarint`/`_zigzag` in each package | open |
| 2026-09-27 | `xiom.bytes.cursor`: bounds-checked read cursor over `&Vec[UInt8]` with offset reporting | nearly every codec builds `_Cursor`/`_Acc`/`_Reader` (jpeg `_Acc`, ldap, snmp, orc, pgp, bonjour, `pki` DER walker, `apple` struct readers, `flash` LE readers...) | private cursor structs with duplicated bounds checks | open |
| 2026-09-27 | `xiom.encoding.base64`: encode/decode + line wrapping | `pgp` (ASCII armor), `pem` | private base64 in each | open |
| 2026-09-27 | `xiom.string.utf8`: strict UTF-8 validation and NUL-free `Str` construction (`bytes_to_str_checked`) | `mkv`, `flac`, `png`, `meteorology`, `pgp`, `ldap`, `ethereum` (ABI bytes stay byte-oriented), `tor` (printable-ASCII converter), `ssh2` (byte output), `cassandra` (strict NUL rejection for `[string]`/`[long string]` payloads), `expat` (`Str::from_utf8` silently truncates at 0x00 -- kills UTF-16 input and makes NUL behavior untestable), `windows`, `etcd`, `pdf`, `monitoring` (unescape must avoid NUL) -- every codec that turns wire bytes into `Str` must re-validate because `sb_to_str` aborts on 0x00 | per-package `_valid_text`/`_printable` helpers | open |
| 2026-09-27 | `xiom.text.scan`: digit-run parsing (with bounds), case-insensitive ASCII compare, keyword tables | `upnp` (`_digits_value`, `_str_eq_ci`), `meteorology`, `rtc`, `coverage`, `nats` (capped decimal parser with overflow guard), `geology` (offset-carrying tokens), `l10n-currency` (`_matches_ci_at`), `biology` (offset line scanner), `oauth` (percent/param scan offsets), `expat` (`_find` because `index_of` returns Option and needs a non-empty needle), `l10n-phone` (case-insensitive match-at-offset), `db2` (opaque-text scanning) | private helpers; `str_compare` only does exact compare | open |
| 2026-09-27 | `xiom.float`: IEEE-754 float32/float64 encode/decode and Int<->Float64 bitcast (without `Vec[Float64]`) | `avro` (float/double raw octets), `mkv` (EBML floats as fixed-point), `amqp` (raw 32-bit patterns), `orc` (statistics), `parquet` (doubles as raw 64-bit patterns), `monitoring` (no scalar parser accepting `+Inf`/`-Inf`/`NaN` with offsets -- local value grammar) | integer fixed-point workarounds, raw octets | open -- 2026-10-03: `Vec[Float64]` WORKS on v0.62.2; the IEEE/bitcast half is still missing (`xiom.num.float.float_bits`/`bits_to_float` are documented stubs; probe `docs/repro/float-vec`, `bad=2`) |
| 2026-09-27 | `xiom.time.civil`: civil date <-> days-since-epoch, leap-year rules, ISO weekday | `rtc`, `tzif`, `duration`, `coverage`?, `pki` (UTCTime/GeneralizedTime digit-pair parsing), `logging` (RFC 3339 split fields), `l10n-date` (JDN + Gregorian/Julian conversion), `l10n-time` (wall-clock `TimeOfDay` model absent) | private integer math in `rtc` and the wave-41 l10n packages | open |
| 2026-09-27 | `xiom.net.addr`: IPv4/IPv6 parse+render (inet_pton-like), pseudo-header assembly | `multicast`, `dns`, `bonjour`, `snmp`, `proxy` (v1 TCP4/TCP6 text forms) | per-package packing helpers | open |
| 2026-09-27 | `xiom.bcd`: two-digit BCD pack/unpack with nibble validation | `rtc` (DS1307/PCF8563), `eeprom` (density tables) | private in `rtc` | open |
| 2026-09-27 | `xiom.math.int`: `div_ceil`, half-away-from-zero rounding, fixed-point scaling helpers, integer `isqrt`, gcd/checked arithmetic | `adc` (rounding), `mkv` (milli-units), `coverage` (floor percents), `geology` (div/pad), `l10n-currency` (half-away rounding), `interrupt` (floor-div/remainder), `aviation` (local Newton `_isqrt` for ground-speed magnitude), `l10n-unit` (gcd, checked mul/div/add/sub), `dimred` (scaled div-round / mul-div, no integer sqrt), `l10n-date` (floor div/mod for negative Int), `l10n-time` (`_pad2` zero-pad), `lockfree` (saturating / CAS-range helpers) | private expressions everywhere | open |
| 2026-09-27 | `xiom.buf.writer`: append helpers with capacity/length bookkeeping for parallel-Vec models | every codec's `_Acc` struct, `biology` (19-vector `BioBatch`), `geology` (`RowParse` carriers), `flash` (cat/zeros), `memcached`/`ssh2`/`tor`/`mongo` (byte appends and span copies) (see trap 16: parallel Vecs must never drift) | per-package atomic push helpers | open |
| 2026-09-27 | `xiom.result`: ergonomic construction for struct-payload `Result`s (per-type leaf constructors; maybe `map`/`?`) | `nats` (leaf `Ok`/`Err` per payload type: `Vec[UInt8]`, `Int`, `Bool`, `NatsOp`, `(Int,Int)`), `i2c` (`_ok_*`/`_err_*` leaves), every wave-36 package (`pki`, `apple`, `merkle`, `interrupt`, `flash`, `gpio`, `geology`, `l10n-currency`), wave-37 (`ethereum` 12 helpers, `ssh2` 54 in src + 14 test helpers, `memcached`, `mongo`, `zigbee`), wave-38 (`dac`, `wireless`, `logging`, `proxy`, `bitcoin`, `timer`), wave-39 (`mssql` 22 leaf pairs, `l10n-unit`), wave-40 (`parquet`, `pdf`, `etcd`, `windows`, `perf`, `geography`, `dynamo`, `keymgmt`, `auth`, `monitoring`, wave-41 (`semaphore`, `l10n-time`, `dimred`, `lockfree`, `hashchain`), wave-42 (all 10), wave-43 (all 10)) | one `_ok_*`/`_err_*` leaf per payload type per package (trap 6) | open |
| 2026-09-27 | `xiom.serialize.json`: raw-byte, format-preserving JSON key lookup (boundary-checked key spans, scalar values) | `nats` (INFO/CONNECT key lookups; `xiom.serialize.json` round-trips and cannot do raw-byte lookups), `oauth` (bounded escape-aware token-response lookup), `dynamo` (AttributeValue/item scanner with offset errors), `keymgmt` (JWK scanner with member offsets, duplicate and NUL/surrogate rejection); `vault` (`json_number(Float64)` DOM unusable under no-Vec[Float64]; flat integer/string scanner needed); `elastic` (flat subset scan for response envelopes); `cloudlog` (flat JSON-subset codec with byte-offset errors) | private key-span scanners per package | open |
| 2026-09-27 | Core decimal formatting usable from dependency-free library modules (`int_to_string` without an import, zero-padded width, simple `Str` interpolation, `Int`/char code -> single-char `Str`) | `i2c` re-implemented `_dec` because importing `xiom.convert.int.int_to_string` breaks the zero-import style of codec modules; `geology` `_pad3`; `apple` finds `use xiom.convert.itos; itos.itos(n)` awkward; `pki`/`interrupt`/`flash`/`biology` build every error with `+` chains of `int_to_string`; `tor`/`oauth` flag the canonical-path ambiguity (trap 17 names `xiom.convert.int`, the actual module is `xiom.convert`); `wireless`/`bitcoin`/`logging` want core Int->Str; `aviation` decoded callsigns with `string.str_slice` per character, `l10n-time` (`_pad2`), `l10n-name` (`Char -> Str` via `convert.tostring`) | private `_dec`/`_pad*`/`str_slice` per dependency-free package | open |
| 2026-09-27 | `xiom.test.bytes`: conformance fixture builders (`bytes_of`/`bytes_equal`/`cat`/`bin`) plus hex-expectation helpers | `nats`, `gpio`, `flash`, `l10n-currency`, `interrupt`, `tls`, `mongo`, `memcached`, `ssh2`, `tor`, `zigbee` (hand-rolled fixtures + `xiom.encoding.hex`), repeated across most wave suites | per-suite private fixture helpers | open |
| 2026-09-27 | `xiom.encoding.hex`: byte<->hex encode/decode with zero-padded output | `pki`, `apple`, `gpio`, `flash`, `merkle` (all hand-rolled `_hex*`/`hb` helpers; `int_to_hex` does not pad) | private hex helpers per package | open |
| 2026-09-27 | `xiom.string.cstr`: NUL-padded fixed-size C-string field decode/encode (trim at first NUL, never build past it) + length validator | `gpio` (`_cstr32`/`_put_cstr32`), `apple` (`_scan_cstr`) | private cstr helpers per package | open |
| 2026-09-27 | `xiom.encoding.le`: unsigned LE16/24/32/64 + BE readers/writers over `Vec[UInt8]` with bounds and range errors | `flash` (`_le32`, 24-bit pointers), `apple` (`_rdu`), `gpio` (`_u32_le`/`_u64_le`), `interrupt` (LE MMIO words), `tls` (`_read_u16/u24/u32` BE), `ssh2` (`_read_u32`, BE writers), `tor` (`_u16`/`_u32`), `mongo` (`_read_u32/i32/i64`), `memcached` (u64 CAS/delta), `ethereum` (`_be_byte`/`_push_be`), `zigbee` (`_le16`), `windows`, `perf`, `etcd`, `parquet` (explicit byte composition for every field), `inference` (Int64 LE), `video`, `audio-meta` | explicit byte composition per package; `image` re-derives `_le16`/`_le32`/`_be16`/`_be32` (+ packers) for BMP/PPM | open |
| 2026-09-27 | `xiom.bits.u32`: proven unsigned 32/64-bit word ops (rotr/shr/and/not, safe bit-get) that avoid the bit-31 masks | `merkle` (SHA-256 `rotr32`/`and32` via the `(a+b-(a^b))/2` identity), `interrupt`/`gpio`/`apple` (bitfield extraction), `memcached` (sign-safe flag/length decode) | divisor/modulo arithmetic per package | open |
| 2026-09-27 | `xiom.hash.sha256`: pure-XIOM, byte-native SHA-256 (`hash.sha256(&Vec[UInt8]) -> Vec[UInt8]`) | `merkle` (hand-rolled FIPS 180-4, ~250 lines; `xiom.crypto.sha256` is FFI-backed, `xiom.crypto.sha` is legacy `Vec[Int]`), `badger` (whole-file checksum; `xiom.crypto.hash.crypto_hash_sha256` and `xiom.crypto.sha.sha256` fail to LINK on v0.61.3: `undefined symbol: xiom_sha256_hash` -- local pure-XIOM SHA-256 written and KAT-verified), `hashchain` (`xiom.crypto.sha256` fails to link on v0.62.0/v0.62.1: `undefined symbol: xiom_sha256_hash`; merkle-style private SHA-256 mirrored) | internal `_sha256` per package | open -- re-verified 2026-10-03 on v0.62.2: still `lld-link: undefined symbol: xiom_sha256_hash` (packet `docs/repro/crypto-link`) |
| 2026-09-27 | `xiom.l10n.iso4217`: ISO 4217 data module with a compilable table | `l10n-currency` (165-row table compiled into comparison chains because module-level table initializers mis-materialize on v0.61.3) | chained comparisons + accessor switch | open -- 2026-10-03: simple `[N]Int` const tables are CORRECT; `Str`/struct const tables still mis-materialize (`docs/repro/const-tables`), so the runtime builder stays |
| 2026-09-27 | `xiom.string.bytes`: `str_bytes(s) -> Vec[UInt8]`, `sb_push_range(sb, s, start, end)`, `str_find(s, needle, from) -> Int` (no Option) | `gpio` (`byte_at` loops), `biology` (offset line scanner `_line_at`), `geology` (`_find_sub`), `pki` (dotted-OID rendering), `l10n-currency` (`_matches_ci_at`), `locale` (`index_of_byte`/`last_index_of_byte`) | per-package byte loops over `str_compare`/`byte_at` | open |
| 2026-09-27 | `xiom.err.at`: standard offset-carrying error idiom (`err_at(label, off, msg)`) | `gpio`, `interrupt`, `biology`, `pki`, `geology`, `tls`, `ssh2`, `tor`, `mongo`, `oauth` (every error rebuilt via `+` chains of `int_to_string`; `tls` also wants a typed `ErrAt { code, offset }`) | per-package `_err_at`/`_range_err` helpers | open |
| 2026-09-27 | `xiom.vec.bytes`: `Vec[UInt8]` structural ops (non-copying slice/view, pop/truncate, extend/append, prefix/tail replace, equality and suffix match) | `ssh2` (`_span_eq2`/`_push_vec`/`_copy_span`), `tor` (`_copy_span`), `mongo` (`_push_range`, `_scan_cstring`), `memcached` (CRLF/line splitter), `nlp` (`_copy_prefix`/`_drop_last`/`_replace_tail`), `zigbee` (`_copy8`/`_copy_span`), `tls` (offset/length views), `dimred` (no pre-sized fill/zeros constructor), `semaphore` (mirrored `Vec[Int]` FIFO queue); `video` (slice/span copy) | per-package byte loops over parallel Vecs | open |
| 2026-09-27 | `xiom.core.uint64`: unsigned 64-bit integer or checked `u64 <-> Int` converters | `memcached` (wire CAS/delta/initial are u64; `Int` forces an explicit 2^63-1 rejection ceiling), `bitcoin` (services/nonce raw 8-byte LE; CompactSize capped at INT64_MAX), `pulsar` (full protobuf u64 range unrepresentable, reader fails closed at 2^63), `bolt` (FNV-1a-64 wrap arithmetic), `git2` (pack/idx 64-bit offsets and sizes), `badger` (version/id/size fields), `mssql`/`mysql`/`db2` (u64 wire fields with bit 63 set rejected), `parquet`, `perf`, `etcd`, `windows` (u64 fields carried as raw patterns) | reject above `2^63-1`, document the ceiling | open |
| 2026-09-27 | `xiom.test.dispatch`: trap-safe conformance runner (no indexed `Vec[fn]`, no `Vec[TestResult]` struct vector) | `zigbee` (26 checks unrolled in `main`), `interrupt` (t1..t20 unrolled), `ssh2` (14 duplicated `err_*_is` test helpers), `wireless` (31->33 unrolled), `logging` (22 unrolled), `l10n-unit` (no Result/error assertion helpers), wave-41 (`l10n-date`, `l10n-time`, `semaphore`, `config`, `lockfree`), wave-42 (all 10), wave-43 (all 10) | every suite unrolls its checks and hand-rolls per-test error helpers | open |
| 2026-09-27 | `xiom.bits.wrapping`: trusted 64-bit wrapping multiply and bitwise AND/XOR on high-bit values | `bolt` (FNV-1a-64 via an 8-step arithmetic XOR loop), `leveldb`/`proxy` (CRC32C bit loops), `merkle` (SHA-256 word ops), `pulsar` (varint `*128` weights), `bitcoin` (u64 helpers), `lockfree` (wrap-safe tag+index packing, unmasked i64 counters) | arithmetic identities plus divisor/modulo extraction everywhere | open |
| 2026-09-27 | `xiom.tlv`: offset-carrying TLV walker (1-byte id + 1-byte length, semantic-length validation, raw unknown preservation) | `proxy` (PROXY v2 TLVs), `wireless` (802.11 information elements) | per-package cursor loops | open |
| 2026-09-27 | `xiom.time.iso8601` field-level use: an offset-carrying RFC 3339 checker exposing parsed fields | `logging` (RFC 5424 TIMESTAMP; the stdlib helper was not usable at the required granularity) | local RFC 3339 parser in `logging` | open |
| 2026-09-27 | `xiom.encoding.base58` / `xiom.encoding.bech32` / compression reuse: the standalone packages and stdlib modules exist (`xiom-base58`, `xiom-bech32`, `xiom.compress.zlib/deflate/huffman/lz77`, `xiom.hash.adler`) but package-local modules cannot import them (`port.ps1` compiles package-local + stdlib only) | `bitcoin` duplicated Base58/Bech32 in-package; `git2` shipped its own DEFLATE (stored/fixed/dynamic, PNG precedent) | in-package reimplementation | open |
| 2026-09-27 | `xiom.containers.map`: generic keyed map/hash with delete and iteration | `cache` (LRU/LFU/CLOCK/TTL hand-build separate-chaining indexes over parallel Vecs), `pulsar`/`oauth`/`nats` key lookups | per-package hand-rolled hash tables and linear scans | open |
| 2026-09-27 | `xiom.string.digits`: digit-string grouping (3-from-the-right), mask-last-N, digit-run scanning with offsets | `l10n-phone` (`_group3`, mask, `byte_at` scan; `format.number` cannot carry leading digits or extensions) | hand-rolled `str_slice`/`str_repeat` loops | open |
| 2026-09-27 | `xiom.encoding.ebcdic`: EBCDIC cp037/cp500 text codec | `db2` (SRVNAM/RDBNAM/TYPDEFNAM from real Db2 are opaque without it) | payloads flagged opaque | open |
| 2026-09-27 | `xiom.io`: `flush_stdout()` is not durable on abnormal exit -- redirected stdout loses buffered output when the program crashes | `mysql` (runtime diagnosis blind during the Vec-cap crash hunt; had to log via `io.write_file`), `perf` (access-violation crash lost buffered stdout; per-line flush needed to localize) | write progress with `io.write_file` | open |
| 2026-09-27 | `xiom.math.rational`: gcd, ratio type, checked mul/div/add/sub overflow helpers, big-integer for exact conversion factors | `l10n-unit` (exact eV `1602176634/10^28` needs a denominator beyond Int64; local `_gcd_abs`/`Ratio`/`_mul_div`) | local rational helpers, documented approximations for eV/pi | open |
| 2026-09-27 | Manifest `categories` must use the registry's fixed vocabulary (unknown values are ignored with a publish warning) | `zigbee` (`protocol` ignored), `zookeeper` (none declared), `dimred` (`math` ignored on the 0.1.0 publish; manifest corrected to `ai-ml`+`data` for its next bump); repo-wide normalization pass pending | publish succeeds with warnings | done 2026-10-03 -- wave-56 sweep normalized all 90 mixed manifests to the 16-token vocabulary; 0 unknown tokens remain |
| 2026-09-27 | `xiom.asn1`: DER/BER TLV walker with byte offsets and length rules | `pki` (local DER walker), `keymgmt` (local PKCS#8/SPKI TLV walker; depending on `xiom.pki` would break the std-only dep contract) | per-package TLV walkers | open |
| 2026-09-27 | `xiom.encoding.utf16`: UTF-16LE/BE decode/encode with surrogate policy | `windows` (registry key/value names; local implementation with lone-surrogate U+FFFD policy) | local UTF-16 helpers | open |
| 2026-09-28 | `str_eq(a, b) -> Bool`: a core `Str` equality convenience safe for `Vec[Str]` elements (BUG 17) | every wave-41 package (`l10n-date`, `l10n-time`, `l10n-address`, `l10n-name`, `locale`, `config`, plus tests in `semaphore`/`lockfree`/`hashchain`/`dimred`, wave-42 `linter`/`clustering`/`forkjoin`/`barrier`/`executor`) wraps `str_compare`; raw `==` is miscompiled and unusable | local `_streq`/`vec_eq` wrappers | open (nice-to-have) -- raw `==` NOT reproduced as a trap on v0.62.2 (`docs/repro/str-vec-eq`, `bad=0`); wrappers simplify at next touch |
| 2026-09-28 | ASCII-only text helpers: case folding (lower/upper/title), `SP\|TAB`-scoped trim, single-character `Str` building ergonomics (`Char -> Str`) | `locale` (tag casing; Unicode-oriented `str_lower/upper` unsuitable), `config` (value trimming), `l10n-name` (initials via UTF-8 leading-byte arithmetic) | private helpers per package | open |
| 2026-09-28 | `xiom.vec.str`: `Vec[Str]` contains / index-of / element-wise equality helpers | `locale` (`_vec_has`), `config` (`vec_eq` in tests); wave-50: `terraform`, `chef`, `k8s` | per-package loops over `str_compare` | open |
| 2026-09-28 | `xiom.sync` semaphore: blocking counting-semaphore primitive beside atomics/barrier/channel/condvar/mutex/rwlock | `semaphore` (package fills the semantic slot with a driver-based deterministic model; the real primitive belongs in `xiom.sync`) | deterministic state machine in-package | open |
| 2026-09-28 | Hardened byte access: an Int-returning / pre-widening `byte_at` wrapper (or fixed intrinsic) so parsers stop copying `(x as Int) & 0xFF` | `config`, `l10n-time`, `l10n-date`, `locale`, `semaphore` (`byte_at` comparisons at >=128 still miscompile) | local `_byte` helpers at every read site | resolved on v0.62.2 -- battery `bad=0` (2026-10-03); helpers simplify at next touch |
| 2026-09-29 | `xiom.math.fixedpoint`: scaled/fixed-point primitives -- round-half-away `div_round`, overflow-guarded `mul_div`, integer `isqrt`, fixed-point `ln`/`exp`, scaled distance/argmin, `Vec[Int]` zeros/fill/sum | every wave-42 numeric package (`feature`, `loss`, `ensemble`, `clustering`; `dimred`/`l10n-number` before them) re-derives these | per-package private helpers | open |
| 2026-09-29 | `xiom.rand.state`: free-function bounded RNG over explicit state (`lcg_next(state)`, `uniform_below(state, n)`, seeded shuffle) | `ensemble` (MINSTD re-implemented locally; `xiom.rand` is global-state + Float64 outputs); `data` (pinned Park-Miller MINSTD + Fisher-Yates shuffle re-implemented for reproducibility); `ml` (seeded MCMC state) | private `_lcg_step` per package | open |
| 2026-09-29 | Work-stealing deque / fork-join primitives (owner LIFO + thief FIFO, Chase-Lev-style) | `forkjoin` (deterministic model fills the semantic slot; `xiom.sync` has no deque), `executor` | model-only deque in-package | open |
| 2026-09-29 | `xiom.convert.serial`: RFC 1982 serial-number wrap-safe compare/add helpers + reusable big-endian `Int` <-> bytes append/read over `Vec[UInt8]` | `streaming` (16/32-bit wrap arithmetic; BE helpers copied from `ntp`/`packet`), siblings `rtc`/`srt` | local `_be_*` / wrap helpers | open |
| 2026-09-29 | `xiom.semver`: `x.y.z` parse + comparator ranges (`>=`/`^`/`~`) with leading-zero/component-bound rules | `plugin` (dependency constraint resolution) | hand-rolled `_semver_parse`/`_ver_cmp3`/`_check_constraint` | open |
| 2026-09-29 | `xiom.string.xml`: XML/entity escaping (`& < > " '`, NUL policy) | `charts` (SVG emitter; `xiom.string.escape` is C-style only) | local `chart_escape` | open |
| 2026-09-29 | `xiom.text.pos`: byte-offset -> 1-based line/column + non-trapping byte peeker with sentinel | `parsing`, `diagrams` (lexer positions; `byte_at` traps out of range) | local `_line_col`/`_peek`/`_Lex` | open |
| 2026-09-29 | ASCII identifier predicates + strict quoted-string codec with explicit escape mapping | `diagrams` (DOT ids/strings; `str_escape`/`str_unescape` are C-style and lenient) | local `_is_id_byte`/`dot_escape`/`dot_unescape` | open |
| 2026-09-29 | Ordered dedup/membership over `Vec[Str]` with byte-exact compare (`str_eq`, vector index-of) | `parsing` (expected-set dedup), `plugin`/`messaging`/`cancel`/`stm` (membership scans; `xiom.string.index_of` is haystack-only) | linear `str_compare` scans per package | open |
| 2026-09-29 | Slot pool / free-list over parallel primitive vectors (alloc/release, generation handles) | `countdown` (256 handles / 512 waiters; `xiom.collect.objectpool` is struct-oriented) | local LIFO free heads | open |
| 2026-09-29 | Deterministic tick-driven latch/countdown + cancellation-token primitives (reason codes, propagation, fan-out waiters) | `countdown`, `cancel` (`xiom.sync`/`xiom.async` are thread/clock-backed) | hand-rolled state machines | open |
| 2026-09-29 | Tree/AST traversal toolkit (node-pool model, pre/post-order walks, spans/diagnostics) | `ast` (package is the gap) | package-local model | open |
| 2026-09-29 | `xiom.string.builder.sb_push_int` INT_MIN defect: negates in place and emits just `-` | `charts` (worked around with `int_to_string`) | avoid builder for Int | open (stdlib defect) |
| 2026-09-30 | `xiom.string` suffix/byte helpers: replace-trailing-suffix, drop-last-byte, ASCII token classifiers + phonotactic predicates (CVC, double-consonant, vowel count, all-lower/all-upper/capitalized) | `lemmatization` (rule tables), `wallet` (structural validators) | package-local helpers | open |
| 2026-09-30 | `Vec[Str]` fresh-copy/clone + BUG-17-safe equality/index-of usable from libraries | `layers`, `wallet`, `messaging`, `cancel`, `parsing`, `stm` (all hand-roll `streq` over `str_compare`) | per-package `streq` + typed-local scans | open |
| 2026-09-30 | Ordered string->string map with first-introduction order + per-key provenance (overlay/merge semantics) | `layers` (layer stack / FlatMap fold) | parallel-vector state fold | open |
| 2026-09-30 | Sentinel-prefix classifier/extractor for `Str` values (replace/append/delete markers) | `layers` (merge sentinels) | `_kind_of`/`_payload_of` | open |
| 2026-09-30 | Integer/fixed-point statistics: average-tie ranks, Wilcoxon/chi-square/sign statistics, discrete critical-value tables, KAT-stable seeded LCG | `stats-tests`, `stats-ml`, `randomforest` (`xiom.stats.*` is Float64-only; no pinned PRNG) | hand-rolled, scale 1e-4 | open |
| 2026-09-30 | ML metric primitives: confusion matrix, per-class/macro P/R/F1, Cohen's kappa, ROC sweep + trapezoid AUC, calibration bins | `stats-ml` | hand-rolled basis-point arithmetic | open |
| 2026-09-30 | Sorted-unique insert / distinct extraction over `Vec[Int]` | `stats-ml` (ROC thresholds), `randomforest` (split candidates) | hand-rolled insertion/dedup loops | open |
| 2026-09-30 | Signed checked arithmetic (`add/sub/mul/div` with overflow detection, INT64_MIN-safe) | `smartcontract` (VM opcodes), `wallet` (balance guards), `countdown` | hand-rolled `_*_overflows` + guards | open |
| 2026-09-30 | `xiom.convert.parse.parse_int` rejects magnitude 2^63 -> `INT64_MIN` unparseable | `smartcontract` (operand parser) | negative-accumulating decimal parser | open (convert defect) |
| 2026-09-30 | Safe amortized string builder ( `sb_to_str` aborts on 0x00 / O(n^2) `str_concat` accumulation) + `str_spaces(n)` | `formatter-fw` (renderer), `randomforest`/`stats-ml` (dumps) | `Str` concatenation | open |
| 2026-09-30 | `Vec` truncation/drop-last discipline (`pop` returns Option, no void truncate) | `formatter-fw` (stacks), `randomforest` (frames); wave-50: `parser-fw` (no usable truncate for backtracking), `jit-fw` (no total pop) | length-driven pushes/pops | open |
| 2026-09-30 | Decision-tree/forest primitives (histograms, Gini, threshold search) + pinned integer PRNG API | `randomforest`, `boosting` (placeholder) | hand-rolled CART + MINSTD | open |
| 2026-09-30 | `xiom.string.index_of`/`str_contains` empty-needle defect: runtime contract violation when `substr` is empty despite `str_contains` ensuring empty matches | `compliance` (predicate engine), any caller | short-circuit empty operands before calling | **FIXED 2026-10-01** (stdlib lane: preconditions removed from `index_of`/`str_index_of`/`str_replace_all`, certain-true empty-needle ensures added; probe `p_empty_needle_contracts.xi` RED -> GREEN; `str_split` delimiter precondition stays) |
| 2026-09-30 | Allocation-free line accessors (`str_line_at`, newline index) over a `Str` | `consensus` (trace store), `macro`, `legacy-proto` | single `Str` + `Vec[Int]` offsets, `str_slice` | open |
| 2026-09-30 | Integer `min`/`max` helpers | `consensus` (commit bound), `boosting` | inline comparisons | open |
| 2026-09-30 | Keyed FIFO/mailbox/bounded-queue primitives + `vec_remove_at`/`pop_at` | `actor` (mailboxes, ready queue), `discovery` | rebuild-in-place helpers | open |
| 2026-09-30 | Stable argmax over an external key with index result + FIFO tie-break | `actor` (priority pick) | `_pick_index` scan | open |
| 2026-09-30 | Ordered event log + subscription cursors (sequence-numbered change feed) | `discovery` (watches), `messaging` | hand-rolled log + cursors | open |
| 2026-09-30 | Composite-key lookup over parallel vectors (name/address/port) | `discovery`, `layers` | `_index_of` scans | open |
| 2026-09-30 | Non-aborting structured assertion catalog with expected/actual records (8+ kinds) | `itest`, `stub` (`xiom.test` asserts abort via panic) | `_record_failure` + kind catalog | open |
| 2026-09-30 | Flat segmented-slice view over a shared `Vec` (start+count handles) | `itest` (step dep slices), `ast` | tail-relocation on add | open |
| 2026-09-30 | Fixed-point checked MSE accumulation over scaled integer vectors | `boosting`, `stats-ml` | `_mse_res` with overflow guards | open |
| 2026-10-01 | Saturating Int arithmetic (`add`/`sub`/`mul` clamping at MIN/MAX) on the module face | `defi`, `geom3d`, `svm`, `mechanics`, `materials`, `chaincrypto` (`xiom.convert.saturating_*` exists but pulls a heavy import) | per-package `_sat_*` helpers | open |
| 2026-10-01 | Pinned rounding helpers: `div_round` (half away from zero) and `div_ceil` (toward zero) over signed ints | `geom3d`, `svm`, `defi`, `materials`, `boosting` | hand-rolled `q`/`r` forms per package | open |
| 2026-10-01 | Fixed-point scale-once multiply kernels (`mul(a,b,scale)`, sums) with overflow guards | `geom3d`, `materials`, `mechanics`, `boosting` | `_mul`/`_sum*_scale` helpers | open |
| 2026-10-01 | Fixed-point trigonometry (sin/cos with range reduction) and Newton `isqrt` (usable without the `xiom.math` barrel) | `geom3d` (rotations, ray math), `defi` (`_defi_isqrt`) | degree-11 Taylor + Newton | open |
| 2026-10-01 | `Vec[Int]`/typed-vector copy helper (no `Vec.clone`) | `exchanger`, `chaincrypto`, `actor`, `itest` | `_copy_ints` loops | open |
| 2026-10-01 | Linear interpolation over an ordered (tick, value) table | `materials` (temperature scaling), `discovery` | index-walk loops | open |
| 2026-10-01 | Group-by-key fold with running aggregate (OHLCV-style buckets, top-N depth) | `exchanger` (candles, depth), `stats-ml` (bins) | `_xchg_candles`/`_xchg_depth_side` | open |
| 2026-10-02 | `xiom.math.fixed`: integer/fixed-point transcendentals (`exp`, `sigmoid`, `tanh`, `softmax`) with documented error bounds | `activation`, `neural`, `boosting`, `ensemble`, `inference` (every ML package re-rolls them) | local rational/exp-identity approximations | open |
| 2026-10-02 | Fixed-point softmax normalize-to-exact-sum utility (floor + residue-to-max rule) | `activation`, `neural` | per-package floor/residue loops | open |
| 2026-10-02 | Bit-set union/intersection/subset over integer sets for dataflow fixes | `analyzer` (dominators/liveness), `compiler-ish` packages | flat 0/1 `Vec[Int]` matrices, O(n^2) memory | open |
| 2026-10-02 | Borrowed `Str` slice/view type (allocation-free substring) | `context` (hot lookups allocate per `str_slice`), `parsing`, `diagrams` | `str_slice` copies (malloc per call) | open |
| 2026-10-02 | Dependency-free `Vec[UInt8]` -> `Str` builder (no FFI malloc/memcpy path) | `text-markup` (canonical emitter), `context`, `encoder` packages | `Str` concatenation (quadratic) or FFI-backed builder | open |
| 2026-10-02 | `Vec[T].pop()` Option discipline ergonomics: element-returning `last`/`peek` without `match` | `analyzer` (stacks/queues), `chaincore`, `formatter-fw` | index cursors (`sp`/`head`) over append-only Vecs | open |
| 2026-10-02 | `xiom.compress.zip`: ZIP container read/write (local headers, central directory, EOCD, name handling, CRC32 + deflate) | `docx`, `pptx`, `xlsx` (all three hand-rolled the container: CRC via `gzip_crc32`, deflate via `xiom.compress.deflate`) | per-package `_zip_*` builders/parsers | open |
| 2026-10-02 | `xiom.compress.deflate` dynamic-Huffman read path (block type 2, repeat codes 16/17/18) + public length/distance tables | `docx`, `pptx`, `xlsx` (`deflate_decompress_capped` rejects dynamic blocks, so real third-party Office files are unreadable; each package duplicated the RFC 1951 tables into a stored+fixed fallback inflater) | local fallback inflater + documented limitation | open |
| 2026-10-02 | Neutral CRC32 surface outside the gzip container returning an LE-push-friendly `Int` | `docx`, `pptx`, `xlsx` (`gzip_crc32` returns `UInt32`; safe byte serialization needed the `xiom.packet` cast pattern) | `as Int` + arithmetic LE packing | open |
| 2026-10-02 | Pure-XIOM Keccak-256/SHA-3 (`keccak256`, `keccak256_hex`) | `web3` (stdlib has no Keccak/SHA-3; Keccak-f[1600] implemented and KAT-verified in-package, 242 lines) | in-package `keccak.xi` | open |
| 2026-10-02 | `xiom.crypto.hash._u64_lshr`/`_u64_shr` defect at `n = 63` (divides by `_pow2(63)` = `Int64_MIN`, quotient flips sign; `Int64_MIN` -> 3 instead of 1) | `web3` (Keccak divergence localized to `rotl(C[1], 1)`; empty/`abc`/`eth` vectors failed until fixed) | in-package copy special-cases `n == 63` | open (stdlib defect) |
| 2026-10-02 | Integer fixed-point math: `log2` and statistics (mean, least-squares slope) over scaled `Int` without `Vec[Float64]` | `climate` (`xiom.math` drags extern-C libm; `xiom.stats` regression is `&Vec[Float64]`-only) | 16-segment piecewise-linear log2 + integer least-squares | open |
| 2026-10-02 | Strict bounded `str_to_int` (reject empty/oversized/invalid fields, no silent zero) | `training` (hand-rolled digit loop to avoid `Vec[Str]` and parser strictness uncertainty) | local parse loop | open |
| 2026-10-02 | XML tokenizer layer (tags, quote-aware attributes, comments/PIs, entity/char-ref decode, UTF-8 code-point encode) | `docx`, `xlsx` (`xiom.string.xml` request covers escaping only; both packages hand-rolled the subset) | local scanners per package | open |
| 2026-10-02 | UTF-8 code-point iteration over `Str` byte offsets + code-point-vector -> `Str` builder | `l10n-unicode` (hand-rolled decode/validate with `& 0xFF` widening; `sb_to_str` after manual encoding) | local UTF-8 helpers | open |
| 2026-10-02 | `xiom.binary`: bounds-checked byte reader/writer (LE/BE 16/24/32/64), printable-ASCII/FourCC prefix -> `Str`, byte-span copy | `audio-meta` (MIDI/MOD/tracker headers), `video` (RIFF/AVI), `image`, `docker` (digests), `inference` (binary model dump) -- every binary package re-derives these | per-package `_le*/_be*` readers | open |
| 2026-10-02 | `xiom.string.from_bytes_span`: NUL-free `Str` from an arbitrary validated byte SPAN (not NUL-terminated) | `audio-meta` (names shorter than buffer), `saml` (base64/XML spans), `video` (FOURCC/stream names) | prefix-until-NUL policy / manual truncation | open |
| 2026-10-02 | `xiom.tables`: runtime string table (blob + monotone `Vec[Int]` offsets) with lookup/dedup | `docker` (names/refs), `audio-meta` (registry), `helm` (keys), `web3` (hex/addresses); wave-52: `cloud`, `aws`, `k8s` (descriptor tables) | per-module blob+offset helpers | open |
| 2026-10-02 | `xiom.graph.topo`: deterministic smallest-index-first topological sort over parallel edge vectors + cycle report | `docker` (compose service order); `ansible` (group closure/depth -- also see the closure row) | hand-rolled Kahn in-package | open |
| 2026-10-02 | `xiom.template`: action-based template engine (dotted paths, if/else/end) usable from dependency-free modules | `helm` (Go-template subset hand-rolled, ~350 lines), `formatter-fw` | local bounded renderer | open |
| 2026-10-02 | `xiom.crypto.gf256` / Shamir: GF(256) mul/inv/div + split/combine helpers | `vault` (unseal; `xiom.crypto.curves` is ECC only) | local ~150-line GF(256) + Lagrange | open |
| 2026-10-02 | Integer quantization/rescale + fixed-point `log2` + integer statistics: shift-quantize/dequantize with documented error bound and auto-shift, round-half-away rescale (negative-safe), fixed-point `log2`, mean/least-squares slope over scaled `Int` | `inference` (quantize/dequantize), `climate` (log2, slope), `ml` (normal equations), `deep` (requantization), `video` (rescale) | per-package helpers | open |
| 2026-10-02 | `xiom.crypto`/`xiom.crypto.hash` SHA-256/HMAC **linkability**: source ships but `lld-link: undefined symbol: xiom_sha256_hash` from a package on v0.62.2 | `aws` (SigV4; hand-rolled KAT-pinned SHA-256/HMAC), `saml` (hand-rolled earlier) | per-package crypto copies | open (stdlib defect/link) -- 2026-10-05 (v0.63.1): same class as the runtime-link AOT discovery gap; with `XIOM_RUNTIME_DIR=<stdlib>\runtime` both probes link and `sha256_hex` returns the NIST KAT `ba7816bf...15ad`; fix expected in the next archive (sha256_sw.c now compiled; sha256_sw.h verified in the install); then retire the `aws`/`saml` hand-rolled copies |
| 2026-10-02 | `xiom.hash`: allocation-free FNV-1a over `Str` (byte-wise) + masked 32-bit combine helper | `jit-fw` (`fnv1a32` needs `&Vec[UInt8]`; `djb2` hashes Char code points); artifact-cache keys | local FNV-1a over `byte_at` + masked combine | open |
| 2026-10-02 | ASCII byte classifiers returning `Bool` (`is_digit`/`is_space`/`is_alpha` over bytes or widened `Int`) | `elastic` (JSON scanner), `chef` (target parsing), `translate` (token shaping), `cfn`; wave 54: `xml2` (trim/byte-set helpers) | widened `Int` range compares at each site | open |
| 2026-10-02 | Delimiter helpers: substring before/after delimiter and split-into-offsets over a `Str` (no `Vec[Str]`) | `chef` (`type[name]` targets), `k8s` (comma/`=` splitting; `str_split` returns `Vec[Str]`), `cfn` | byte-wise scans per package | open |
| 2026-10-02 | `xiom.graph` closure/reachability/depth over parallel-vector edges with caller depth budgets | `ansible` (group closure/depth; `xiom.collect.graph`/`dag` are struct-node shaped, banned) | hand-rolled `_group_contains`/`_group_depth`/`_group_reaches` | open |
| 2026-10-02 | Glob/fnmatch + bounded regex subset primitives (byte-safe, step-capped) | `salt` (hand-rolled glob O(n*m) + regex subset with a 65536-step fail-closed cap), `consul` (prefix/word helpers) | byte loops over `byte_at`/`str_slice` | open |
| 2026-10-02 | `Str -> Str` ordered map/table type | `puppet` (scopes/hiera/hash-merge use parallel `Vec[Str]` pairs; `xiom.collect.stringmap` is Str->Int only), `helm` | parallel pair vecs | open |
| 2026-10-02 | Span / byte-slice API for `Str` (validated subranges, no copy) | `consul` (private `ConsulSpan{start;size}` + `sb_to_str`), `puppet`, `audio-meta` | private span structs per package | open |
| 2026-10-02 | Strict integer parsing with caller-relocatable error offsets (18+ digit cap, no silent zero) | `cloudlog` (`_cl_scan_int`), `training`, `translate` | hand-rolled digit scanners | open |
| 2026-10-02 | Encoding codecs: RFC 4648 base32 (canonical unpadded lowercase) + percent-encoder preserving `/` with uppercase hex | `i2p` (base32 KAT-pinned local), `gcp` (GCS object paths) | hand-rolled codecs | open |
| 2026-10-02 | Boolean `str_eq(a, b) -> Bool` | every package (hand-rolls `str_compare(a,b) == 0`; called out by `cloud`, `aws`, `k8s`) | `str_compare ... == 0` at each site | open |
| 2026-10-02 | Contract-usable math predicates: `is_finite` / `is_nan`, plus `reciprocal` | `control`, `sensor` (NaN/Inf domains are unassertable; guarded `1.0 / x` trips verifier X7004) | local guards; clauses left solver-unproven | open |
| 2026-10-02 | Quaternion algebra (`multiply`/`normalize`/`from_euler`/`rotate`) | `sensor` (hand-rolled Hamilton product) | in-package implementation | open |
| 2026-10-03 | `xiom.encoding.percent`: strict decode with caller-relocatable error offsets and NUL rejection | `curl` (`percent_decode` returns offset-less errors and truncates a decoded `%00` via `from_cstring`) | byte-wise decoder in-package | open |
| 2026-10-03 | Offset-carrying search (`find_from`, `Int` with -1 sentinel) over `Str` | `curl`, `xml2` (`str_index_of` has no `from`), `consul`, `chef`, `cfn` | local `_find_*` helpers | open |
| 2026-10-03 | Keyed/comparator sort over parallel vectors (produce an index permutation, not a `Vec[T]` sort) | `xml2` (attribute indices), `rocksdb` (LSM ordering), `docker` | insertion sort + order vector | open |
| 2026-10-03 | Bit-array/Bloom helper + 32-bit mixing hash usable from library modules | `rocksdb` (SST Bloom shape, `_rocksdb_hash32`) | local bit set + FNV-1a | open |

| 2026-10-05 | HTTP-date pair: RFC 1123/7231 formatter from epoch + public IMF-fixdate parser | `xiom.static` (Last-Modified / If-Modified-Since), PULSE ops docs; `strftime` hardcodes `%H/%M/%S` to "00" and lacks `%a/%b`; the parser is private in `cookie.xi` | hand-rolled formatting (see the `xiom.static` brief) | open |
| 2026-10-05 | Path safety: cross-platform lexical child-containment (`path_within(root, child)`), Windows-aware `is_absolute`, both-separator join | `xiom.static` (traversal guard; `io.join_paths`/`io.is_absolute` are `/`-only), PULSE server file paths | manual `..`/colon/backslash guards | open |
| 2026-10-05 | `xiom.io.fs` remove parity: `fs_remove` / `fs_remove_dir` | `xiom.static` and `xiom.kv` tests + any package doing file fixtures; `fs` has write/read but no remove (only `io.remove_file`) | `io.remove_file` from the `io` module | open |
| 2026-10-05 | Concrete stdio `Read` implementation of `read_exact` (streaming reads) | `xiom.static` (large assets), `xiom.kv` (segment scans); `read_exact` is interface-only (`io.xi:481`), `fs_read_range` returns whole buffers with Int32 offsets | chunked `fs_read_range` | open |

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
- 2026-09-27: wave-36 reports appended (all 10: `pki`, `merkle`, `apple`,
  `geology`, `biology`, `l10n-currency`, `gpio`, `interrupt`, `flash`,
  `tls`): new rows for `encoding.hex`, `string.cstr`, `encoding.le`,
  `bits.u32`, `hash.sha256`, `l10n.iso4217`, `string.bytes`, `err.at`;
  requesters extended on `bitstream`, `bytes.cursor`, `math.int`,
  `text.scan`, `time.civil`, `buf.writer`, `result`, `test.bytes`, and the
  convert-ergonomics row.
- 2026-09-27: wave-37 reports appended (all 10: `zigbee`, `ethereum`,
  `ssh2`, `tor`, `memcached`, `mongo`, `oauth`, `nlp`, `zookeeper`,
  `cassandra`): new rows for `vec.bytes`, `core.uint64`, `test.dispatch`;
  requesters extended on `encoding.le`, `result`, `test.bytes`, `err.at`,
  `bits.u32`, `string.utf8`, `serialize.json`, `text.scan`, `buf.writer`,
  and the convert-ergonomics row.
- 2026-09-27: wave-38 reports appended (all 10: `bitcoin`, `proxy`,
  `pulsar`, `bolt`, `wireless`, `leveldb`, `logging`, `dac`, `timer`,
  `aviation`): new rows for `bits.wrapping`, `tlv`, `time.iso8601` and
  the base58/bech32 reuse gap; requesters extended on `varint`,
  `checksum`, `net.addr`, `result`, `core.uint64`, `test.dispatch`,
  `time.civil`, `math.int` (`isqrt`), and the convert-ergonomics row.
- 2026-09-27: wave-39 reports appended (all 10: `git2`, `mysql`,
  `mssql`, `db2`, `expat`, `zkp`, `cache`, `l10n-phone`, `l10n-unit`,
  `badger`; `badger` subsequently rewritten to upstream v1.6.2 layouts):
  new rows for `containers.map`, `string.digits`, `encoding.ebcdic`,
  io-flush durability, `math.rational`, registry categories, and the
  module-reuse gap extended to compression; requesters extended on
  `string.utf8`, `checksum`, `core.uint64`, `text.scan`, `math.int`,
  `result`, `test.dispatch`, `hash.sha256`.
- 2026-09-27: wave-40 reports appended (all 10: `parquet`, `pdf`, `etcd`,
  `windows`, `perf`, `geography`, `dynamo`, `keymgmt`, `auth`,
  `monitoring`; plus parallel-lane `inline-asm`, `pool`, `backoff`, `tap`
  restyle integrated after): new rows for `asn1` and `encoding.utf16`;
  requesters extended on `core.uint64`, `encoding.le`, `serialize.json`,
  `string.utf8`, `float`, `result`, `io`.
- 2026-09-28: wave-41 reports appended (all 10: `l10n-date`, `l10n-time`,
  `l10n-address`, `l10n-name`, `locale`, `dimred`, `semaphore`,
  `lockfree`, `hashchain`, `config`): new rows for `str_eq`, ASCII
  case/trim helpers, `vec.str`, a `xiom.sync` semaphore, and a hardened
  byte accessor; requesters extended on `time.civil`, `math.int`,
  `hash.sha256`, `result`, `test.dispatch`, `string.bytes`, `vec.bytes`,
  `bits.wrapping` and the convert-ergonomics row. Note: the sessions were
  paused mid-wave by a runtime event at 22:33Z and resumed at ~23:08Z;
  all ten landed green on the installed v0.62.1 (most also forced-green
  on the pinned repo-release v0.62.0).
- 2026-09-29: wave-42 reports appended (all 10: `feature`, `loss`,
  `ensemble`, `streaming`, `linter`, `lexer-fw`, `clustering`, `barrier`,
  `forkjoin`, `executor`; plus the parallel lane's `sectest`, `mock`,
  `pwm`, rescue-integrated after the v0.62.1 pin bump): new rows for
  `math.fixedpoint`, `rand.state`, work-stealing deques, and
  `convert.serial`; requesters extended on `str_eq`, `result` and
  `test.dispatch`. All under the v0.62.1 pin (byte-at trap still live).
- 2026-09-29: wave-43 reports appended (all 10: `cancel`, `stm`,
  `worker`, `messaging`, `plugin`, `countdown`, `diagrams`, `charts`,
  `parsing`, `ast`; the last four built by Agent Manager sessions, the
  rest by background `task` porters; all integrated with port x2 + trap-14
  verification). New rows for `xiom.semver`, `xiom.string.xml`,
  `xiom.text.pos` (offset->line/col + non-trapping peeker), ASCII
  identifier/strict quoted-string codecs, ordered `Vec[Str]` dedup, slot
  pools over parallel vectors, deterministic latch/cancellation
  primitives, AST traversal, and the `sb_push_int` INT_MIN defect;
  requesters extended on `result` and `test.dispatch`. All green on the
  installed v0.62.1.
- 2026-09-30: wave-44 reports appended (all 10: `lemmatization`, `layers`,
  `macro`, `stub`, `stats-tests`, `stats-ml`, `wallet`, `randomforest`,
  `smartcontract`, `formatter-fw`; 6 task/4 AM lanes, all port x2 +
  trap-14 verified, records `incubating`, published in `eco-v0.1.23/.24`
  (+`formatter-fw` 0.1.1 module-normalization republish in
  `eco-v0.1.25`)). `macro`/`stub` final reports were lost to the
  2026-09-30 PC shutdowns (their files were verified green instead). New
  rows: suffix/byte string helpers, `Vec[Str]` clone/equality, ordered
  keyed maps with provenance, merge sentinels, integer/fixed-point
  statistics + pinned LCG, ML metrics, sorted-unique inserts, signed
  checked arithmetic, `parse_int` INT64_MIN defect, safe amortized string
  builder + `str_spaces`, `Vec` truncate discipline, decision-tree
  primitives. All green on v0.62.2.
- 2026-09-30: wave-45 reports appended (all 10: `consensus`, `discovery`,
  `actor`, `itest`, `codegen-fw`, `compliance`, `legacy-proto`,
  `environment`, `boosting`, `optimizer-fw`; 5 task lanes + 2 AM lanes +
  1 task re-dispatch + 1 task resume after output-limit crashes; all
  port x2 + trap-14 verified, records `incubating`, published in
  `eco-v0.1.26`). New rows: empty-needle `str_contains` defect,
  allocation-free line accessors, Int min/max, keyed FIFO/mailbox,
  stable argmax, ordered event log + cursors, composite-key lookup,
  non-aborting assertion catalog, flat segmented slices, fixed-point
  MSE. Compiler side: `Vec[Str].push(s)` mis-lowering recorded in
  `docs/COMPILER-FINDINGS.md` (third v0.62.2 issue).
- 2026-10-01: wave-46 reports appended (all 10: `chaincore`,
  `chaincrypto`, `defi`, `exchanger`, `geom3d`, `svm`, `nft`,
  `mechanics`, `materials`, `chromatography`; 6 task + 3 AM lanes + 1
  AM->task re-dispatch after an output-limit crash; all port x2 +
  trap-14 verified, records `incubating`, published in `eco-v0.1.27`
  together with the pending `sectest`/`mock`/`pwm` (allowlist 432 ->
  445)). New rows: saturating Int arithmetic, pinned rounding helpers,
  fixed-point multiply kernels, fixed-point trig + isqrt, typed-vector
  copy, table interpolation, group-by-key folds. Compiler side: the
  fourth v0.62.2 finding (`&mut Int` write drop) recorded in
  `docs/COMPILER-FINDINGS.md`.
- 2026-10-02: wave-47 reports appended (all 10: `activation`, `neural`,
  `tensor`, `analyzer`, `autoscale`, `context`, `metadata`, `imaging`,
  `text-markup`, `microscopy`; 6 task + 4 AM lanes, all port x2 +
  trap-14 verified -- `text-markup` had two `Vec<UInt8>` mixed-bracket
  spellings fixed and re-gated; records `incubating`, published in
  `eco-v0.1.28`). New rows: `xiom.math.fixed` transcendentals, exact-sum
  softmax helper, bit-set dataflow primitives, borrowed Str views,
  dependency-free `Vec[UInt8]`->`Str` builder, `Vec.pop` ergonomics.
  Compiler side: `&mut Int` narrowing (`&mut Struct` field writes DO
  propagate) added to the findings.
- 2026-10-02: wave-48 reports appended (all 10: `climate`, `nuclear`,
  `training`, `web3`, `l10n-unicode`, `docx`, `pptx`, `xlsx`, `image`,
  `data`; 6 task + 4 AM lanes, all port x2 + trap-14 verified, records
  `incubating`, published in `eco-v0.1.29`; allowlist 455 -> 465). New
  rows: `compress.zip` container, deflate dynamic-Huffman read path +
  public tables, neutral CRC32, pure Keccak-256, the `_u64_lshr` n=63
  defect, fixed-point log2 + integer statistics, strict bounded
  `str_to_int`, XML tokenizer, UTF-8 code-point iteration/building;
  requesters extended on `rand.state` (`data`) and `encoding.le`
  (`image`). Compiler side: type laxness beyond brackets (`pptx`) and
  the v0.62.2 const-array probe (`l10n-unicode`, simple `[N]Int` shapes
  now correct) recorded in `docs/COMPILER-FINDINGS.md`.
- 2026-10-02: wave-49 reports appended (all 10: `deep`, `ml`, `saml`,
  `helm`, `audio-meta`, `docker`, `inference`, `serverless`, `video`,
  `vault`; 6 task + 4 AM lanes; `deep`/`ml` first attempts aborted
  silently and passed on a `variant: low` files-first retry; all port
  x2 + trap-14 verified, records `incubating`, published in
  `eco-v0.1.30` after two `oidc_token_expired` reruns; allowlist
  465 -> 475). New rows: `xiom.binary`, `xiom.string.from_bytes_span`,
  `xiom.tables`, `xiom.graph.topo`, `xiom.template`,
  `xiom.crypto.gf256`/Shamir, integer quantization/rescale + fixed-point
  `log2` + integer statistics; requesters extended on `varint`
  (`audio-meta`), `serialize.json` (`vault`), `encoding.le`
  (`inference`/`video`/`audio-meta`), `vec.bytes` (`video`),
  `rand.state` (`ml`). Note: the base64 row is stale -- stdlib now ships
  `xiom.encoding.base64` + `crypto_hash_sha256` (saml verified).
  Compiler side: child->parent module import and nominal
  module-qualified type identity rows added; trap-14 widened to full
  angle brackets in parameter positions (`video`); `--emit-ir`
  sibling-module limitation; expat/nbt silent `-1` resolved as a
  sweep-harness cross-kill race (not a compiler issue).
- 2026-10-02: wave-50 reports appended (all 10: `translate`, `parser-fw`,
  `jit-fw`, `terraform`, `k8s`, `cfn`, `ansible`, `chef`, `elastic`,
  `aws`; 6 task + 4 AM lanes; `elastic` hit its output limit with zero
  files and was stopped + re-dispatched as a `variant: low` files-first
  task, green on retry; all port x2 + trap-14 verified, records
  `incubating`, published in `eco-v0.1.31` on the first run; allowlist
  475 -> 485; note: the `parser-fw`/`jit-fw` manifests used an unknown
  category token -> registry `categories: []`). New rows: stdlib crypto
  linkability defect (`xiom_sha256_hash` undefined), `xiom.hash`
  FNV-1a over `Str` + masked combine, ASCII byte classifiers, delimiter
  helpers, graph closure/depth; requesters extended on `vec.str`, `Vec`
  truncation, `serialize.json` and `graph.topo`. Compiler side: bare
  `loop` return typing, arity asymmetry (missing args accepted), and the
  stdlib crypto link failure recorded in `docs/COMPILER-FINDINGS.md`.
- 2026-10-02: wave-51 reports appended (all 8: `puppet`, `azure`, `gcp`,
  `salt`, `cloudlog`, `consul`, `i2p`, `phaser`; 5 task + 3 AM lanes,
  all port x2 + trap-14 verified, records `incubating`, published in
  `eco-v0.1.32` on the first run; allowlist 485 -> 493; category note:
  `phaser` shipped an unknown category token -> registry
  `categories: []`). New rows: glob/fnmatch + bounded regex,
  `Str -> Str` map, span/byte-slice API, strict integer parsing with
  relocatable offsets, base32 + percent-encoder; `serialize.json`
  requesters extended (`cloudlog`). Stdlib side: the crypto linkability
  repro packet now lives in `docs/repro/crypto-link/` (exact symbols,
  call shapes, KATs, retirement plan) for fix-first.
- 2026-10-02: wave-52 reports appended (growth: `cloud` 26/26 published
  in `eco-v0.1.33`; promotion prep: `json` 44/44 with 15 contracts,
  `control` 32/32 with 58 clauses, `sensor` 38/38 with 28 clauses --
  stages stay `ported` until the first promotion wave after Tier-2
  maintenance). New rows: boolean `str_eq`, contract-usable
  `is_finite`/`is_nan` + `reciprocal`, quaternion algebra; `xiom.tables`
  requesters extended (`cloud`, `aws`, `k8s`). Hardening found real
  legacy defects in `json` (0.05 parsed as 0.5, stringify recursion,
  exponent hang, partial writes, non-atomic merge) plus two compiler
  findings filed as Open rows: match-bound enum payload mutations
  silently dropped, and aggregate-payload `derive[Clone]` corruption
  (`0xC000001D`). Contract verification evidence for all three
  candidates: annotated + runtime-checked, 0/101 solver-proven on
  v0.62.2 (encoding gaps documented in `docs/COMPILER-FINDINGS.md`;
  scalar-only probes 2/2 and 4/4 proven).
- 2026-10-03: wave-54/55 reports appended (34 category fixes + 24-package
  legacy bracket repair + `curl`/`xml2`/`rocksdb` growth published in
  `eco-v0.1.34`; `firebird`/`oracle` from the parallel lane verified and
  integrated, publish pending owner scope). New rows:
  `xiom.encoding.percent` strict decode, offset-carrying `find_from`,
  keyed sort over parallel vectors, bit-array/Bloom + 32-bit mixing
  hash; ASCII-classifier requesters extended (`xml2`). Note: the wave's
  cross-lane flake was the `port.ps1` watchdog's global `a.exe` sweep
  (fixed `07301ee6`), not a compiler defect.
