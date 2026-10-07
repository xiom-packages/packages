# xiom.rpm -- Specification

Version: 0.1.2 (stable; published on the XIOM registry).
Module: `src/rpm.xi` (`module xiom.rpm`).
Depends on `xiom.std` (`xiom.string`); the tests additionally use
`xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
`xiom.encoding.hex`.

## Scope

A pure-XIOM (no FFI), read-only parser for the two structural layers every
RPM file starts with:

- `rpm_parse_lead` parses and validates the 96-byte program lead;
- `rpm_parse_header` parses one generic header structure at an absolute
  offset: magic word, reserved bytes, index-entry count, data-store size,
  the 16-byte index entries and the data store;
- `rpm_parse` ties them together: lead, signature header (validated
  structurally and skipped), main header;
- `rpm_validate` performs the same walk plus per-entry bounds and NUL
  checks and returns `Ok(())` or a deterministic `Err(Str)`;
- `rpm_header_count`, `rpm_header_store_len`, the entry-field accessors,
  `rpm_header_find`, `rpm_header_has_tag`, `rpm_header_tag_type`,
  `rpm_header_tag_str`, `rpm_header_tag_int`,
  `rpm_header_tag_str_array_count`, `rpm_header_tag_str_array_at` read the
  parsed header back;
- `rpm_get_name/version/release/summary/license/group/os/arch/
  payload_compressor/buildtime` read the common tags of a parsed package;
- `rpm_is_rpm`, `rpm_lead_arch_name`, `rpm_lead_type_name` and
  `rpm_lead_os_name` are the lead-level probes and name maps.

## Non-goals

- Writing, editing, re-serializing or signing RPM files.
- Payload decoding: the compressed cpio archive after the main header is
  neither located accessibly nor decompressed.
- Signature semantics: the signature header is skipped structurally; its
  tags (digests, GPG material, sizes) are not decoded or verified.
- Dependency resolution, file lists, scriptlets, changelogs or any
  tag beyond the ten named scalar getters.
- Legacy or non-standard header versions (only version 1), non-big-endian
  encodings, and the pre-RPM-3 "old" lead-direct layouts.
- Checksum or UTF-8 validation of stored strings.

## Byte-level layout

### Program lead (96 bytes, little-endian-free: all numbers big-endian)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | magic | `ED AB EE DB` |
| 4 | 1 | major | lead version major (3 in classic files) |
| 5 | 1 | minor | lead version minor (0) |
| 6 | 2 | type | 0 binary, 1 source |
| 8 | 2 | archnum | legacy architecture family number |
| 10 | 66 | name | NUL-terminated; a missing NUL yields all 66 bytes |
| 76 | 2 | osnum | 1 = Linux |
| 78 | 2 | signature_type | 5 = header signature |
| 80 | 16 | reserved | skipped, not validated |

`rpm_parse_lead` does not require the trailing reserved area or any field
except the magic to be meaningful; `major`/`minor` are returned raw.

### Header structure

Parsed at any absolute offset `off`; the signature header sits at offset 96
and the main header immediately after the signature header.

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 3 | magic | `8E AD E8` |
| 3 | 1 | version | `01`; any other value is `rpm: bad header version` |
| 4 | 4 | reserved | skipped (not required to be zero) |
| 8 | 4 | entry count | big-endian 32-bit |
| 12 | 4 | store size | bytes of data store, big-endian 32-bit |
| 16 | `count` x 16 | index entries | see below |
| 16 + `count`*16 | `store_size` | data store | raw bytes |

The prefix is `RPM_HEADER_PREFIX` = 16 bytes; one index entry is
`RPM_INDEX_ENTRY_SIZE` = 16 bytes. Every number in the header is
big-endian.

**Fidelity note (brief vs on-disk layout).** The port brief described the
header as "magic `8E AD E8 01`, 8 reserved bytes, index-entry count,
data-store size". The on-disk RPM layout is a 4-byte magic word (the three
magic bytes plus the version byte), then **4** reserved bytes -- i.e. 8
bytes from the start of the magic to the end of the reserved area, then the
entry count and store size. This parser follows the on-disk layout (16-byte
prefix) so that real RPM header structures parse; the tests pin the prefix
at 16 bytes and pin the reserved bytes at offsets 4..7.

### Index entry (16 bytes)

| Offset | Size | Field | Notes |
|---|---|---|---|
| 0 | 4 | tag | big-endian; see the tag table |
| 4 | 4 | type | `RPM_TYPE_*` |
| 8 | 4 | offset | relative to the start of the data store |
| 12 | 4 | count | number of elements |

`rpm_parse_header` copies every entry verbatim into the flat
`RpmHeader.tags` vector (stride `RPM_HDR_STRIDE` = 4). A header with
`count` = 0 and `store_size` = 0 is valid and yields an empty index and an
empty store.

### Data-store types

| Value | Constant | Meaning | `count` |
|---|---|---|---|
| 0 | `RPM_TYPE_NULL` | no data | 0 |
| 1 | `RPM_TYPE_CHAR` | single bytes | number of bytes |
| 4 | `RPM_TYPE_INT32` | signed big-endian 32-bit values | number of ints |
| 6 | `RPM_TYPE_STRING` | one NUL-terminated string | 1 |
| 8 | `RPM_TYPE_STRING_ARRAY` | `count` NUL-terminated strings | number of strings |

Accessor semantics for these types:

- `rpm_header_tag_int`: INT32 values are sign-extended (`0x80000000` reads
  `-2147483648`); CHAR yields the first byte (0..255); NULL and all other
  types yield `-1`.
- `rpm_header_tag_str`: STRING reads the NUL-terminated string; a
  STRING_ARRAY reads its first element; NULL yields `""`; all other types
  yield `""`. An unterminated string is returned up to the end of the store
  (lenient); `rpm_validate` is the strict path that requires the NUL.
- `rpm_header_tag_str_array_count` returns the entry's raw count field for
  STRING_ARRAY entries only; `rpm_header_tag_str_array_at` walks the
  NUL-separated run and returns element `idx` (or `""`).
- Unknown types (BIN(7), INT16(3), INT8(5), I18NSTRING(9), ...) are carried
  structurally; the typed accessors return `-1` / `""` for them.
  `rpm_validate` does not reject them, because real RPM files contain them.

### Tags with named getters

| Constant | Value | Type on the wire | Getter |
|---|---|---|---|
| `RPM_TAG_NAME` | 1000 | STRING | `rpm_get_name` |
| `RPM_TAG_VERSION` | 1001 | STRING | `rpm_get_version` |
| `RPM_TAG_RELEASE` | 1002 | STRING | `rpm_get_release` |
| `RPM_TAG_SUMMARY` | 1004 | STRING (modern: I18NSTRING) | `rpm_get_summary` |
| `RPM_TAG_BUILDTIME` | 1006 | INT32 | `rpm_get_buildtime` |
| `RPM_TAG_LICENSE` | 1014 | STRING | `rpm_get_license` |
| `RPM_TAG_GROUP` | 1016 | STRING (modern: I18NSTRING) | `rpm_get_group` |
| `RPM_TAG_OS` | 1021 | STRING | `rpm_get_os` |
| `RPM_TAG_ARCH` | 1022 | STRING | `rpm_get_arch` |
| `RPM_TAG_PAYLOADCOMPRESSOR` | 1125 | STRING | `rpm_get_payload_compressor` |

Modern RPM files usually store SUMMARY and GROUP as I18NSTRING(9); the
named getters return `""` for those, and `rpm_header_tag_str` on tag 1004
does the same. Use `rpm_header_tag_type` to detect it.

### Architecture number map

`rpm_lead_arch_name` maps the legacy lead `archnum` to the canonical family
name: 0 noarch, 1 i386 (the whole x86 family incl. x86_64), 2 alpha,
3 sparc, 4 mips, 5 ppc, 6 m68k, 7 sgi, 8 rs6000, 9 ia64, 10 mipsel,
11 mips64, 12 arm, 13 m68kmint, 14 s390, 15 s390x, 16 ppc64, 17 sh,
18 xtensa, 19 aarch64, 20 mipsr6, 21 mipsr6el, anything else `"unknown"`.
`rpm_lead_type_name`: 0 `"binary"`, 1 `"source"`, else `"unknown"`.
`rpm_lead_os_name`: 1 `"linux"`, else `"unknown"`.

## Validation order and error catalog

`rpm_parse_lead`:

1. `data.len() < 96` -> `rpm: truncated lead`
2. first four bytes != `ED AB EE DB` -> `rpm: bad lead magic`

`rpm_parse_header(data, off)`:

1. `off < 0` or `off + 16 > data.len()` -> `rpm: truncated header`
2. bytes `off..off+3` != `8E AD E8` -> `rpm: bad header magic`
3. byte `off+3` != `01` -> `rpm: bad header version`
4. `count > (data.len() - (off+16)) / 16` -> `rpm: truncated index`
5. `store_size > data.len() - store_start` ->
   `rpm: truncated store`

`rpm_parse`:

1. lead errors as above;
2. `_header_span_checked(data, 96)` fails (the signature header at offset
   96 is not a well-formed header structure) -> `rpm: bad signature header`;
3. main header parsed with `rpm_parse_header`, surfacing its errors
   (`rpm: truncated header`, `rpm: bad header magic`,
   `rpm: bad header version`, `rpm: truncated index`,
   `rpm: truncated store`).

`rpm_validate` runs the same three steps, then walks every main-header
index entry in order:

1. tags vector not a whole number of entries -> `rpm: bad index entry`
   (unreachable from parsed bytes; a defensive guard);
2. `offset < 0` or `offset > store.len()` -> `rpm: tag out of range`;
3. CHAR: `count > store.len() - offset` -> `rpm: tag out of range`;
4. INT32: `count > (store.len() - offset) / 4` -> `rpm: tag out of range`;
5. STRING: `offset >= store.len()` -> `rpm: tag out of range`; no NUL in
   `[offset, store.len())` -> `rpm: string missing NUL`;
6. STRING_ARRAY: fewer NUL bytes in `[offset, store.len())` than `count` ->
   `rpm: string missing NUL`;
7. NULL and unknown types: only the offset check applies.

The payload region after the main header is not part of validation: a file
may end exactly at the last store byte.

## Accessor behavior summary

| Accessor | Absent tag | Wrong type | Out-of-store span |
|---|---|---|---|
| `rpm_header_count` | n/a (drift -> `-1`) | n/a | n/a |
| `rpm_header_find` | `-1` | n/a | n/a |
| `rpm_header_has_tag` | `false` | n/a | n/a |
| `rpm_header_tag_type` | `-1` | n/a | n/a |
| `rpm_header_tag_str` | `""` | `""` (NULL -> `""`) | `""` |
| `rpm_header_tag_int` | `-1` | `-1` (NULL -> `-1`) | `-1` |
| `rpm_header_tag_str_array_count` | `-1` | `-1` | raw count is still returned |
| `rpm_header_tag_str_array_at` | `""` | `""` | `""` |

`Str` results are read values: compare them with
`xiom.string.compare.str_compare`, never with `==` (compiler trap BUG-17).

## Test plan (`tests/test_conformance.xi`, 19 checks)

Every byte buffer is hand-built in the test file with `Vec[UInt8].push`; no
external `.rpm` files are used. The synthetic main header carries 14 index
entries over a 91-byte store: the ten common tags, a CHAR probe (tag 1126),
a two-element STRING_ARRAY (tag 1005), a NULL entry (tag 9999) and a
PACKAGER STRING (tag 1015).

1. lead magic probe: full 96-byte lead true; empty, 3-byte and
   header-magic-only buffers false; each corrupted magic byte false.
2. lead fields: major 3, minor 2, type 1, archnum 16, name `pkg-1.0-1`,
   osnum 1, signature_type 5; trailer reserved bytes zero.
3. lead rejection: 95-byte and empty buffers -> `rpm: truncated lead`; each
   of the four magic bytes wrong -> `rpm: bad lead magic`.
4. the full archnum/type/os map including out-of-range values -> `unknown`.
5. header prefix bytes pinned (magic, version, zero reserved, count 14,
   store 91, first entry bytes), 14 parsed entries, pinned
   tag/type/offset/count for entries 0, 4, 11 and 12.
6. STRING lookup for all nine string tags plus tag 1015; absent tags `""`;
   `has_tag` true/false.
7. INT32 1700000000; CHAR 99; NULL -> `-1`; INT32 read as string and STRING
   read as int -> `""` / `-1`; sign extension `0x80000000` ->
   -2147483648.
8. package getters on a full synthetic file, lead fields, 14 entries.
9. absent tags: no entry, type `-1`, int `-1`, string `""`, array count
   `-1`.
10. empty header (count 0, store 0) parses, validates and yields empty
    lookups for a whole file too.
11. truncation: 8- and 15-byte prefixes -> `rpm: truncated header`; index
    cut -> `rpm: truncated index`; store cut -> `rpm: truncated store`;
    negative and past-end offsets -> `rpm: truncated header`.
12. wrong header magic (bytes 0 and 2) and version 2; a bad signature
    header makes `rpm_parse`/`rpm_validate` return
    `rpm: bad signature header`.
13. a header appended after three junk bytes parses at absolute offset 3
    with correct entries.
14. STRING_ARRAY: count 2, first-element rendering, both elements,
    out-of-range index, non-array tag; a declared count beyond the
    terminated run renders `""` and keeps the raw count.
15. out-of-store spans clamp to `""` / `-1`; an INT32 span that exactly
    fits is read.
16. `rpm_validate`: unknown type 9 accepted; INT32 span beyond the store ->
    `rpm: tag out of range`; STRING without NUL -> `rpm: string missing
    NUL` while the lenient accessor still renders `"abc"`; STRING_ARRAY
    with too few NULs -> `rpm: string missing NUL`; STRING offset at the
    end of the store -> `rpm: tag out of range`.
17. entry accessor ranges (`-1` / past-end) and the tags-drift guard
    (a hand-built `RpmHeader` with a 1-slot tags vector reports `-1` /
    `""` from every accessor).
18. lead name edges: a 66-byte field without NUL, a leading NUL (empty
    name) and an embedded NUL (`"ab\0d"` reads `"ab"`).
19. whole-file validation: lead cut, bad lead magic, signature cut, main
    header cut, index cut and one-byte store cut each return their
    documented error.

## Contracts (batch #37 hardening pass, 2026-10-07)

Runtime-checkable `ensures:` clauses added to `src/rpm.xi` in the batch #37
hardening pass (compiler v0.64.0; no version bump here -- `package.xi` stays
at 0.1.1 and the coordinator applies the 0.1.2 bump at integration). 61
clauses over the 31 public entry points, in source order:
2/2/2/2/2/2/2/2/2/1/2/2/2/2/2/1/2/2/2/2/3/2/2/2/2/2/2/2/2/2/2 (the plan
header's "59" was stale arithmetic; the per-function lines sum to 61). All
clauses are `ensures:` only (no `requires:`), so the accepted-input domain is
unchanged. Two consecutive `& .\scripts\port.ps1 -Package xiom.rpm
-TimeoutSec 60` runs ended `port: PASS (passed=19 failed=0 program_exit=0
exit=0)` with the clauses active (9.52 s and 9.18 s); the 19-check
conformance suite exercises every entry point and no clause trapped, so none
was dropped. The plan had no probe-gated items.

`xiom-verify src\rpm.xi --check` under v0.64.0 reports 8 proven / 0 violated
/ 56 unknown / 29 errors. The 8 "proven" verdicts are the two sentinel
clauses of each of the four entry-field accessors, but no clause here is
claimed Z3-provable: those queries run under the emitter's skipped-axiom
assumption set, where a sibling contract is asserted as a `forall` that
quantifies over its own `result` (e.g. `forall h i result. i < 0 => result ==
-1`), which is unsatisfiable by itself -- so the `unsat` answers are vacuous,
not sound proofs. The 29 errors are the known SMT emitter bug on private
helpers (`_byte`, `_u16be`, `_cstr`, `_err_lead`, `_err_header`,
`_header_magic_code`, `_header_span_checked`, `_entry_field`); the tool
itself marks them "not a proof failure of the code under test". The remaining
56 obligations are X7007 skips (unresolved operand sorts, `field access
'.header' on non-datatype receiver`, unsupported expression). Every clause is
runtime-checked by the v0.64.0 evaluator on every call.
`xiom_verify_output.smt2` was deleted by literal path.

Clause-family limits (per the batch plan): no raw tag-value range claims
(hand-built headers may hold arbitrary Ints, so `rpm_header_tag_int` and
`rpm_get_buildtime` only claim the `-1` sentinel); no `Ok`/`Err` payload
reads on any `Result`; no `Str` equality (BUG 17); no vector indexing; no
module constants in clauses (16/96/128 and the numeric tag ids are inline
literals). All shapes hold for hand-built `RpmLead` / `RpmHeader` /
`RpmPackage` values, including the tags-vector drift case
(`rpm_header_count` = -1 makes every entry accessor return -1 and every
lookup return -1 / ""). The only cross-calls in clauses are
`rpm_header_count` and `rpm_header_find`: both are non-re-entrant (count
reads only `h.tags.len()`; find calls nothing public upward), and the getter
clauses pass the by-value struct field `p.header`.

| Entry point | Clause(s) added | Class |
|---|---|---|
| `rpm_is_rpm` | `data.len() < 4 => !result`; `result => data.len() >= 4` | runtime-checked (Vec length + Bool) |
| `rpm_parse_lead` | `data.len() < 96 => result is Err`; `result is Ok => data.len() >= 96` | runtime-checked (Vec length + Result tag) |
| `rpm_lead_arch_name` | `archnum < 0 \|\| archnum > 21 => result.len() == 7`; `result.len() >= 2` | runtime-checked (Str length; "sh" is the shortest name) |
| `rpm_lead_type_name` | `ptype != 0 && ptype != 1 => result.len() == 7`; `result.len() >= 6` | runtime-checked (Str length) |
| `rpm_lead_os_name` | `osnum != 1 => result.len() == 7`; `osnum == 1 => result.len() == 5` | runtime-checked (Str length) |
| `rpm_parse_header` | `off < 0 => result is Err`; `result is Ok => data.len() >= off + 16` | runtime-checked (Vec length + Result tag) |
| `rpm_parse` | `data.len() < 96 => result is Err`; `result is Ok => data.len() >= 128` | runtime-checked (Vec length + Result tag) |
| `rpm_validate` | `data.len() < 96 => result is Err`; `result is Ok => data.len() >= 128` | runtime-checked (Vec length + Result tag) |
| `rpm_header_count` | `result == -1 \|\| result * 4 == h.tags.len()`; `result >= -1` | runtime-checked (field read) |
| `rpm_header_store_len` | `result == h.store.len()` | runtime-checked (field read) |
| `rpm_header_entry_tag` | `i < 0 => result == -1`; `i >= rpm_header_count(h) => result == -1` | runtime-checked (scalar sentinel pair; see the verifier note) |
| `rpm_header_entry_type` | `i < 0 => result == -1`; `i >= rpm_header_count(h) => result == -1` | runtime-checked (scalar sentinel pair; see the verifier note) |
| `rpm_header_entry_offset` | `i < 0 => result == -1`; `i >= rpm_header_count(h) => result == -1` | runtime-checked (scalar sentinel pair; see the verifier note) |
| `rpm_header_entry_count` | `i < 0 => result == -1`; `i >= rpm_header_count(h) => result == -1` | runtime-checked (scalar sentinel pair; see the verifier note) |
| `rpm_header_find` | `result >= -1`; `result >= 0 => result < rpm_header_count(h)` | runtime-checked (cross-call) |
| `rpm_header_has_tag` | `result == (rpm_header_find(h, tag) >= 0)` | runtime-checked (cross-call) |
| `rpm_header_tag_type` | `rpm_header_find(h, tag) < 0 => result == -1`; `result != -1 => rpm_header_find(h, tag) >= 0` | runtime-checked (cross-call) |
| `rpm_header_tag_str` | `rpm_header_find(h, tag) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(h, tag) >= 0` | runtime-checked (cross-call + Str length) |
| `rpm_header_tag_int` | `rpm_header_find(h, tag) < 0 => result == -1`; `result != -1 => rpm_header_find(h, tag) >= 0` | runtime-checked (cross-call) |
| `rpm_header_tag_str_array_count` | `rpm_header_find(h, tag) < 0 => result == -1`; `result != -1 => rpm_header_find(h, tag) >= 0` | runtime-checked (cross-call) |
| `rpm_header_tag_str_array_at` | `idx < 0 => result.len() == 0`; `rpm_header_find(h, tag) < 0 => result.len() == 0`; `result.len() > 0 => idx >= 0` | runtime-checked (cross-call + Str length) |
| `rpm_get_name` | `rpm_header_find(p.header, 1000) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(p.header, 1000) >= 0` | runtime-checked (struct-field cross-call) |
| `rpm_get_version` | `rpm_header_find(p.header, 1001) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(p.header, 1001) >= 0` | runtime-checked (struct-field cross-call) |
| `rpm_get_release` | `rpm_header_find(p.header, 1002) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(p.header, 1002) >= 0` | runtime-checked (struct-field cross-call) |
| `rpm_get_summary` | `rpm_header_find(p.header, 1004) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(p.header, 1004) >= 0` | runtime-checked (struct-field cross-call) |
| `rpm_get_license` | `rpm_header_find(p.header, 1014) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(p.header, 1014) >= 0` | runtime-checked (struct-field cross-call) |
| `rpm_get_group` | `rpm_header_find(p.header, 1016) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(p.header, 1016) >= 0` | runtime-checked (struct-field cross-call) |
| `rpm_get_os` | `rpm_header_find(p.header, 1021) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(p.header, 1021) >= 0` | runtime-checked (struct-field cross-call) |
| `rpm_get_arch` | `rpm_header_find(p.header, 1022) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(p.header, 1022) >= 0` | runtime-checked (struct-field cross-call) |
| `rpm_get_payload_compressor` | `rpm_header_find(p.header, 1125) < 0 => result.len() == 0`; `result.len() > 0 => rpm_header_find(p.header, 1125) >= 0` | runtime-checked (struct-field cross-call) |
| `rpm_get_buildtime` | `rpm_header_find(p.header, 1006) < 0 => result == -1`; `result != -1 => rpm_header_find(p.header, 1006) >= 0` | runtime-checked (struct-field cross-call) |
