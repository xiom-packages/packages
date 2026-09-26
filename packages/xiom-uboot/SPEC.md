# xiom.uboot -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.uboot`, version `0.1.0`).
Module: `src/uboot.xi` (`module xiom.uboot`).
Depends on `xiom.std` (`xiom.string`: `byte_at`; `Str::from_utf8` is a
compiler builtin). Tests additionally use `xiom.test`, `xiom.io`,
`xiom.string.compare` and `xiom.encoding.hex`.

## 1. Scope

A pure-XIOM (no FFI) structural codec for the U-Boot **legacy** image format
(the fixed 64-byte `image_header_t`, the `ih_` struct):

- `uboot_parse_header` decodes and validates a 64-byte header from any
  buffer of at least 64 bytes without inspecting the payload;
- `uboot_parse` parses a full image and additionally requires the declared
  data size to fit the buffer;
- O(1) accessors for every field: magic, both CRCs, timestamp, data size,
  load address, entry point, the four id bytes with their documented names,
  the decoded name, and the data span (`uboot_data_offset`,
  `uboot_data_end`, `uboot_data_bytes`);
- CRC-32 helpers: `uboot_crc32`, `uboot_crc32_range`, `uboot_header_crc_ok`,
  `uboot_data_crc_ok`;
- FIT detection (`uboot_is_fit`) with an explicit rejection error;
- `uboot_build` writes a canonical image (64-byte header + payload) with the
  size derived from the payload and both CRCs recomputed.

All APIs are buffer-in / buffer-out: nothing touches the filesystem.

## 2. Non-goals

- **No FIT images.** The flattened image tree magic `d00dfeed` is detected
  by `uboot_is_fit` and rejected by both parsers with
  "uboot: FIT image not supported". No FIT structure is parsed or built.
- **No payload decompression or compression.** `ih_comp` is only an id; the
  data bytes are opaque and are written verbatim.
- **No multi-image semantics.** `IH_TYPE_MULTI` (id 4) is a name in the
  table only; the payload of a multi-image file is not split or indexable.
- **No image length cross-checks beyond the data span.** U-Boot's optional
  `ih_size` padding rules, `mkimage -T` checks, and "size includes the
  header" quirks are out of scope.
- **No CRC enforcement on parse.** Mismatches are reported only by the
  explicit helpers.
- **No name transcoding.** The name field is printable ASCII only (section
  4.1).
- No FFI, no registry integration, no thread safety.

## 3. Byte layout

The legacy image is the header followed by the payload; the header is
exactly 64 bytes and every multi-byte integer is big-endian.

| Offset | Size | Field | Rule |
|---|---|---|---|
| 0 | 4 | `ih_magic` | Must be `27 05 19 56` (0x27051956). |
| 4 | 4 | `ih_hcrc` | Raw BE32; see section 5. |
| 8 | 4 | `ih_time` | Raw BE32 creation timestamp (no epoch policy). |
| 12 | 4 | `ih_size` | BE32 payload size in bytes. |
| 16 | 4 | `ih_load` | Raw BE32 load address. |
| 20 | 4 | `ih_ep` | Raw BE32 entry point address. |
| 24 | 4 | `ih_dcrc` | Raw BE32 payload CRC-32; see section 5. |
| 28 | 1 | `ih_os` | OS id byte (0..255). |
| 29 | 1 | `ih_arch` | Architecture id byte (0..255). |
| 30 | 1 | `ih_type` | Image type id byte (0..255). |
| 31 | 1 | `ih_comp` | Compression id byte (0..255). |
| 32 | 32 | `ih_name` | NUL-padded printable ASCII (section 4.1). |
| 64 | `ih_size` | payload | Opaque data bytes. |

The header has no offset, alignment, version or length field of its own:
the payload always starts at absolute offset 64. `uboot_header_size()` and
`uboot_data_offset()` both return 64.

All 32-bit fields are accumulated arithmetically (`v = v * 256 + byte`) into
a signed 64-bit `Int`, so their full unsigned range `0..2^32-1` is
representable and no value ever has bit 63 set.

## 4. Text and id policy

### 4.1 Name field

Decoding (`uboot_parse` / `uboot_parse_header` / `uboot_name`):

- bytes 32..63 are scanned in order; the first `0x00` terminates the name;
- every byte before the terminator must be in `0x20..0x7E`; any other byte
  (including `0x01..0x1F` and `0x7F..0xFF`) is rejected with
  "uboot: bad image name";
- when no NUL is present the whole 32 bytes form the name (a full
  32-character name);
- bytes after the first NUL are ignored and may hold any value, so a
  non-canonical tail still parses.

Encoding (`uboot_build`): every byte of `h.name` must be in `0x20..0x7E`
and the string must be at most 32 characters ("uboot: bad image name"
otherwise). The bytes are written at offset 32 and the remainder of the
field is zero-filled; a 32-character name leaves no NUL terminator. The
empty name is legal.

### 4.2 Id name tables (partial)

The parsers accept every id in `0..255` and preserve it; the builders accept
every id in `0..255`. The name accessors consult these **partial** tables,
and any id outside a table is reported as `"unknown"`:

| Table | Known ids |
|---|---|
| OS | 0 `invalid`, 1 `openbsd`, 3 `freebsd`, 5 `linux`, 6 `vxworks` |
| Architecture | 2 `arm`, 3 `i386`, 5 `mips`, 6 `mips64`, 7 `ppc`, 22 `aarch64` |
| Image type | 1 `standalone`, 2 `kernel`, 3 `ramdisk`, 4 `multi`, 5 `firmware`, 6 `script`, 8 `filesystem`, 14 `kernel-noload` |
| Compression | 0 `none`, 1 `gzip`, 2 `bzip2`, 3 `lzma`, 5 `lzo`, 6 `lz4`, 9 `zstd` |

The tables are deliberately small and pinned by this package's brief; they
are not a claim to enumerate every U-Boot id. Unknown ids round-trip through
parse and build unchanged.

## 5. CRC-32 policy

The module implements the standard CRC-32 locally (IEEE 802.3 / zlib /
PKZIP): reflected polynomial `0xEDB88320`, init `0xFFFFFFFF`, reflected
input/output, final xor `0xFFFFFFFF`. It is table-free and bitwise; the
check value for `"123456789"` is `0xCBF43926` = 3421780262 and the empty
buffer is 0. Every intermediate register stays in `0..2^32-1`, so the only
bitwise operations are `>> 1` and `& 1` on values whose bit 63 is clear.

- Both parsers copy the stored CRC fields raw and **never** reject or report
  a mismatch. The caller verifies explicitly:
- `uboot_header_crc_ok` recomputes the CRC over the 64 header bytes at
  offset 0 **with the 4 `ih_hcrc` bytes (offset 4..7) treated as zero** (the
  U-Boot rule that the field is not part of its own computation) and
  compares it with the stored value; it returns `false` when the buffer is
  shorter than 64 bytes;
- `uboot_data_crc_ok` recomputes the CRC over the `ih_size` bytes at offset
  64 (no zeroing) and compares it with the stored value; it returns `false`
  when `ih_size` is negative (only possible on a hand-built header) or the
  span does not fit the buffer, so a header-only buffer fails whenever
  `ih_size > 0`;
- `uboot_build` computes the data CRC over the payload and patches offset 24,
  then computes the header CRC with its own field still zero and patches
  offset 4.

## 6. Validation order

`uboot_parse_header` (first failure wins):

1. `data.len() < 64` -> `uboot: truncated header`.
2. The first four bytes are `d00dfeed` -> `uboot: FIT image not supported`.
3. The first four bytes are anything else but `27051956` -> `uboot: bad magic`.
4. A name byte before the NUL outside `0x20..0x7E` -> `uboot: bad image name`.

`uboot_parse` (first failure wins):

1. `data.len() < 64` -> `uboot: truncated header`.
2. The first four bytes are `d00dfeed` -> `uboot: FIT image not supported`.
3. The first four bytes are anything else but `27051956` -> `uboot: bad magic`.
4. `ih_size > data.len() - 64` -> `uboot: truncated data`.
5. Then the same name validation as `uboot_parse_header` (step 4 there).

Bytes after `64 + ih_size` are ignored, so a longer buffer is accepted by
both parsers. A header-only 64-byte buffer parses via `uboot_parse_header`
even when `ih_size` is nonzero.

## 7. Builder rules and canonical output

`uboot_build(h, payload)` validates in this order: `time` in `0..2^32-1` ->
`uboot: bad timestamp`; `load` in `0..2^32-1` -> `uboot: bad address`; `ep`
in `0..2^32-1` -> `uboot: bad address`; each id in `0..255` ->
`uboot: bad id`; `payload.len() <= 2^32-1` -> `uboot: data too large`; the
name (section 4.1) -> `uboot: bad image name`.

Written layout, in order:

| Output | Value |
|---|---|
| offset 0 | fixed magic `27051956` |
| offset 4 | 0 (placeholder), patched last |
| offset 8 | `h.time` |
| offset 12 | `payload.len()` |
| offset 16 | `h.load` |
| offset 20 | `h.ep` |
| offset 24 | 0 (placeholder), patched after the payload |
| offsets 28..31 | `h.os`, `h.arch`, `h.image_type`, `h.comp` |
| offsets 32..63 | `h.name` bytes, then NUL padding |
| offset 64 | `payload` verbatim |
| image length | `64 + payload.len()` |

`h.magic`, `h.hcrc`, `h.dcrc` and `h.size` are ignored: the builder always
writes the canonical magic, derives the size from the payload, and
recomputes both CRCs.

## 8. API signatures

All functions are free functions in module `xiom.uboot` (no self methods):

```xi
pub type UbootHeader = {
  magic: Int; hcrc: Int; time: Int; size: Int; load: Int; ep: Int;
  dcrc: Int; os: Int; arch: Int; image_type: Int; comp: Int; name: Str;
}

pub fn uboot_header_size() -> Int
pub fn uboot_data_offset() -> Int
pub fn uboot_is_fit(data: &Vec[UInt8]) -> Bool
pub fn uboot_parse_header(data: &Vec[UInt8]) -> Result[UbootHeader, Str]
pub fn uboot_parse(data: &Vec[UInt8]) -> Result[UbootHeader, Str]
pub fn uboot_magic(h: &UbootHeader) -> Int
pub fn uboot_timestamp(h: &UbootHeader) -> Int
pub fn uboot_data_size(h: &UbootHeader) -> Int
pub fn uboot_load_addr(h: &UbootHeader) -> Int
pub fn uboot_entry_point(h: &UbootHeader) -> Int
pub fn uboot_header_crc(h: &UbootHeader) -> Int
pub fn uboot_data_crc(h: &UbootHeader) -> Int
pub fn uboot_os(h: &UbootHeader) -> Int
pub fn uboot_os_name(h: &UbootHeader) -> Str
pub fn uboot_arch(h: &UbootHeader) -> Int
pub fn uboot_arch_name(h: &UbootHeader) -> Str
pub fn uboot_image_type(h: &UbootHeader) -> Int
pub fn uboot_image_type_name(h: &UbootHeader) -> Str
pub fn uboot_compression(h: &UbootHeader) -> Int
pub fn uboot_compression_name(h: &UbootHeader) -> Str
pub fn uboot_name(h: &UbootHeader) -> Str
pub fn uboot_data_end(h: &UbootHeader) -> Int
pub fn uboot_data_bytes(data: &Vec[UInt8], h: &UbootHeader) -> Result[Vec[UInt8], Str]
pub fn uboot_crc32(data: &Vec[UInt8]) -> Int
pub fn uboot_crc32_range(data: &Vec[UInt8], start: Int, count: Int) -> Int
pub fn uboot_header_crc_ok(data: &Vec[UInt8], h: &UbootHeader) -> Bool
pub fn uboot_data_crc_ok(data: &Vec[UInt8], h: &UbootHeader) -> Bool
pub fn uboot_build(h: &UbootHeader, payload: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
```

## 9. Semantics of the accessors

- All header readers are O(1) and infallible: they return the raw parsed
  field (`uboot_magic`, `uboot_timestamp`, `uboot_data_size`,
  `uboot_load_addr`, `uboot_entry_point`, `uboot_header_crc`,
  `uboot_data_crc`, `uboot_os`, `uboot_arch`, `uboot_image_type`,
  `uboot_compression`, `uboot_name`).
- The four name readers (`uboot_os_name`, `uboot_arch_name`,
  `uboot_image_type_name`, `uboot_compression_name`) consult the partial
  tables of section 4.2 and return `"unknown"` for any id outside them (they
  never fail and never return `""`).
- `uboot_name` returns the decoded name, `""` for an all-NUL field.
- `uboot_data_end(h)` is `64 + h.size`, computed arithmetically; for a
  parsed header it equals the end of the data span.
- `uboot_data_bytes` copies `[64, 64 + h.size)` into a fresh vector; it
  returns `Err("uboot: truncated data")` when `h.size` is negative or the
  span does not fit `data` (including any buffer shorter than 64 bytes).
- `uboot_crc32_range` returns `-1` for a negative `start`/`count` or a span
  that does not fit; a zero-length span at `data.len()` returns `0`.
- `uboot_header_crc_ok` / `uboot_data_crc_ok` are boolean and
  bounds-checked; they are the only places a CRC mismatch is reported.
- `uboot_is_fit` is a 4-byte prefix check (false for shorter buffers); it is
  detection only and never parses FIT.
- `uboot_build` derives every field it ignores (section 7).

## 10. Error string catalog

| Condition | Error text |
|---|---|
| Buffer shorter than 64 bytes | `uboot: truncated header` |
| First four bytes `d00dfeed` | `uboot: FIT image not supported` |
| First four bytes neither legacy nor FIT magic | `uboot: bad magic` |
| `64 + ih_size` exceeds the buffer (`uboot_parse`, `uboot_data_bytes`) | `uboot: truncated data` |
| Name byte outside `0x20..0x7E` before the NUL; build name longer than 32 chars or non-printable | `uboot: bad image name` |
| Build `time` outside `0..2^32-1` | `uboot: bad timestamp` |
| Build `load` or `ep` outside `0..2^32-1` | `uboot: bad address` |
| Build id byte outside `0..255` | `uboot: bad id` |
| Build payload longer than `2^32-1` bytes | `uboot: data too large` |

## 11. Complexity

| Operation | Complexity |
|---|---|
| `uboot_header_size`, `uboot_data_offset`, `uboot_is_fit` | O(1) |
| `uboot_parse`, `uboot_parse_header` | O(1) |
| All header/id/name accessors | O(1) |
| `uboot_data_bytes` | O(ih_size) |
| `uboot_crc32` | O(data.len()) |
| `uboot_crc32_range` | O(count) |
| `uboot_header_crc_ok` | O(1) |
| `uboot_data_crc_ok` | O(ih_size) |
| `uboot_build` | O(payload.len()) |

## 12. Test plan

`tests/test_conformance.xi` (`module uboot_tests`, 16 named checks; the
hello-style `main` prints `[PASS]`/`[FAIL]` per check and returns the failure
count). The gzip fixture is assembled byte by byte and its CRCs were computed
by an independent table-driven script (whose `"123456789"` check value is
3421780262), so the parser is exercised against bytes the module did not
produce. Coverage:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | gzip fixture | 80-byte fixture parses; every raw field, all four id names, the name, both CRCs and the span accessors are pinned; both CRC helpers verify |
| t2 | canonical rebuild | `uboot_build` of the parsed fixture is byte-identical to the 80 pinned bytes |
| t3 | shape errors | 63-byte buffer, zero-length buffer, corrupted magic and `d00dfeed` prefix rejected by both parsers with exact messages |
| t4 | data span | declared size 17 with 16 payload bytes, 64-byte header-only buffer and `0xFFFFFFFF` size fail `uboot_parse`; `uboot_parse_header` accepts them; trailing bytes after the span are ignored |
| t5 | name policy | `0x1F` and `0x7F` inside the name rejected; bytes after the NUL ignored; a 32-character name fills the field (byte 63 is the last character) |
| t6 | id pass-through | `vxworks`/`aarch64`/`kernel-noload`/`zstd` map to names; ids 200/99/77/4 parse, round-trip and report `"unknown"` |
| t7 | CRC-32 values | `"123456789"` = 3421780262, empty = 0, range guards return -1, fixture data CRC equals the payload span CRC |
| t8 | header CRC | fixture verifies; the CRC equals the CRC of the header with `ih_hcrc` zeroed; changing the timestamp breaks only the header CRC and never the parse |
| t9 | data CRC | header-only buffer fails; a flipped payload byte breaks only the data CRC; `uboot_data_bytes` copies the exact 16 payload bytes or fails on a short buffer |
| t10 | builder errors | negative and `2^32` timestamps/addresses, id -1/256, a 33-character name and a `0x1F` name are rejected with exact messages |
| t11 | derived fields | a header with bogus magic/hcrc/dcrc/size builds the canonical magic, payload-derived size and recomputed CRCs; an empty payload yields 64 bytes, size 0 and data CRC 0 |
| t12 | 300-byte round trip | 300-byte payload with `0xC0000000`-range addresses: length 364, span exact, rebuild byte-identical |
| t13 | span accessors | `uboot_header_size()`/`uboot_data_offset()` are 64, `uboot_data_end` is 64 + size, oversized spans are rejected |
| t14 | id tables | every documented id maps to its pinned name; unlisted neighbours (os 2, arch 4, type 7, comp 4) are `"unknown"` |
| t15 | FIT detection | `uboot_is_fit` true only for the exact 4-byte magic; both parsers report `uboot: FIT image not supported` |
| t16 | name padding | `"AB"` occupies bytes 32..33 with 34..63 zero; an empty name zero-fills all 32 bytes |

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.uboot
```

Last verified: compiler 0.61.3,
`port: PASS (passed=16 failed=0 program_exit=0 exit=0)`.

## 13. Known limitations

- **Legacy format only.** FIT (`d00dfeed`) is detected and rejected, not
  parsed; there is no new-format, `ih_` v2 or external-data support.
- **No (de)compression and no multi-image handling.** The payload is opaque;
  `IH_TYPE_MULTI` payloads cannot be indexed.
- **Partial id tables.** Unknown ids survive round trips but are named
  `"unknown"`.
- **CRCs are opt-in.** Both parsers return whatever is stored; callers must
  invoke the verification helpers to detect corruption.
- **ASCII-only names.** Non-printable bytes are rejected on parse and cannot
  be represented by the builder; there is no charset transcoding.
- **Raw addresses and timestamps.** No relocation, memory-model or epoch
  interpretation.
- **No image-level checks.** Header/payload consistency beyond the declared
  data span (padding, trailing data, `mkimage` policy) is not enforced.
- Not thread-safe; `UbootHeader` is a flat scalar value type holding no
  vectors.

## 14. Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_header`,
  `_err_header`, `_ok_bytes`, `_err_bytes`; every other function returns
  through one of them. `uboot_parse` reuses `uboot_parse_header`'s Result
  directly (no constructor in the wrapper).
- Every byte read is widened with `(data[pos] as Int) & 0xFF`; UInt8 values
  are never compared against Int constants without widening.
- Big-endian words are accumulated arithmetically (`v = v * 256 + byte`);
  writes go through an arithmetic byte extractor (`_be_byte`), so values with
  bit 31 set (e.g. `0x80008000`) never touch a sign bit or a large mask.
- CRC-32 is table-free and bitwise; every register stays in `0..2^32-1`, so
  the only bitwise operations are `>> 1` and `& 1` on values whose bit 63 is
  clear; no sign-bit-set value is masked or shifted.
- The builder patches both CRCs through single compute-and-patch helpers
  (`_seal_crc`, `_seal_header_crc`) so the mutable reference is never held
  across two borrows of the same buffer.
- Internal validation helpers return `""` (or `true`) rather than a Result
  when the error message is the only payload; Result payloads for the struct
  and the byte vector stay in the leaf constructors.
- Str values read from struct fields are bound to typed locals; the module
  performs no `==` on Str values at all. The tests use
  `xiom.string.compare.str_compare` and typed locals for every Vec read.
- All `&mut Vec[UInt8]` calls pass `&mut` at the call site; nested helpers
  receive the existing reference (gpt/tar/aiff precedent).
- **Malformed bracket audit:** `Vec<` / `Result<` were grep-audited in both
  files after writing (parameter and return positions); zero occurrences.
