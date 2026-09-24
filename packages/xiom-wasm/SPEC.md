# xiom.wasm -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.wasm`, version `0.1.0`).
Module: `src/wasm.xi` (`module xiom.wasm`).
Depends on `xiom.std` (`xiom.string.builder`).

## Scope

A pure-XIOM (no FFI) structural reader for the WebAssembly binary format:

- magic + version detection (`wasm_is_module`);
- unsigned LEB128 u32 decoding with exact offset reporting
  (`wasm_leb_u32`);
- the canonical section-id -> name table (`wasm_section_name`);
- a section walk producing parallel id/offset/size vectors
  (`wasm_parse_sections`);
- export-name extraction from section 7 (`wasm_export_names`).

The reader knows where sections start and end and can list a module's
export names. It does not know what any bytes inside a section *mean*
beyond the export-entry container.

## Non-goals

- **Validation.** No type checking, instruction decoding, control-flow
  analysis, index-space checking, section-order/uniqueness enforcement or
  count-vs-content reconciliation.
- **Codegen or execution.** The module never emits or runs WebAssembly.
- Import names, custom-section names, start function resolution, memory/
  table limits, name section contents.
- Recursive composition (`WasmSections` contains only ids/offsets/sizes).
- UTF-8 validation of export names (bytes are copied verbatim).
- Streaming: the reader works on an in-memory `Vec[UInt8]`.
- Canonical-form enforcement: non-minimal LEB128 encodings are accepted.

## Header

A module starts with 8 bytes:

| Bytes | Value | Meaning |
|---|---|---|
| 0..3 | `00 61 73 6D` | magic `\0asm` |
| 4..7 | `01 00 00 00` | version 1 (little-endian u32) |

`wasm_is_module` accepts exactly this prefix; trailing section bytes are
ignored. The classification used by `wasm_parse_sections` is:

| Condition | Result |
|---|---|
| fewer than 4 bytes, or magic ok but fewer than 8 bytes | `Err("wasm: truncated header")` |
| 4+ bytes with the wrong magic | `Err("wasm: bad magic")` |
| magic ok, 8+ bytes, version != 1 | `Err("wasm: bad version")` |
| magic + version 1 | walk |

## LEB128 rules (unsigned u32)

`wasm_leb_u32(data, off)` decodes the maximum of 5 bytes:

- each byte carries 7 payload bits, least-significant group first;
- bit 7 (`0x80`) is the continuation flag; the last byte has it clear;
- the 5th byte may carry at most payload bits 0..3, so its mask `0xF0`
  must be zero. A continuation flag on the 5th byte would request a 6th
  byte and is an overflow.

Pinned encodings:

| Value | Bytes | bytes consumed |
|---|---|---|
| 0 | `00` | 1 |
| 1 | `01` | 1 |
| 42 | `2a` | 1 |
| 127 | `7f` | 1 |
| 128 | `80 01` | 2 |
| 129 | `81 01` | 2 |
| 255 | `ff 01` | 2 |
| 300 | `ac 02` | 2 |
| 624485 | `e5 8e 26` | 3 |
| 0 (non-minimal) | `80 80 80 80 00` | 5 |
| 4294967295 (u32 max) | `ff ff ff ff 0f` | 5 |

Error conditions:

| Input | Result |
|---|---|
| `off < 0` | `Err("wasm: negative offset")` |
| `off >= data.len()` | `Err("wasm: truncated leb128")` |
| encoding starts at `off` but a continuation byte has no successor | `Err("wasm: truncated leb128")` |
| 5th byte mask `0xF0` non-zero (continuation or bits above bit 31) | `Err("wasm: leb128 overflow")` |

On success the returned offset points just past the last consumed byte and
is always `<= data.len()`.

## Section table

Sections follow the header immediately. Each section is:

```
[id byte][size LEB128 u32][payload of `size` bytes]
```

| Id | Name | Id | Name |
|---|---|---|---|
| 0 | `custom` | 7 | `export` |
| 1 | `type` | 8 | `start` |
| 2 | `import` | 9 | `element` |
| 3 | `function` | 10 | `code` |
| 4 | `table` | 11 | `data` |
| 5 | `memory` | 12 | `datacount` |
| 6 | `global` | other | `unknown` |

`wasm_parse_sections` records every section in file order:

- `ids[i]` -- the raw id byte (0..255, recorded verbatim; unknown ids are
  accepted and appear as-is);
- `offsets[i]` -- absolute offset of the first payload byte (the byte
  after the size LEB128);
- `sizes[i]` -- declared payload size in bytes.

A section is accepted when `offset + size <= data.len()`; the payload may
be empty (`size == 0`) and may end exactly at EOF. Sections are not
required to be ordered, unique or known.

## Export entries

Section 7's payload is:

```
[count LEB u32]
  entry * count
entry = [name: len LEB u32 + UTF-8 bytes][kind byte][index LEB u32]
```

`wasm_export_names` finds the first section 7 and collects the `name`
strings in entry order (kind and index are consumed but discarded; the
kind byte is not validated). With no section 7 the result is an empty
`Vec[Str]`; an empty payload (`size == 0`) or `count == 0` is likewise
empty. The declared `count` is authoritative: exactly that many entries
are read and any payload bytes left over are `Err("wasm: trailing export
bytes")`. Entry bytes may not run past the declared payload end, and a
name byte `0x00` is rejected (`Str` is NUL-terminated on this platform);
a length/index LEB128 that crosses the boundary is rejected (see
catalog).

## API signatures

```xi
pub type WasmSections = { ids: Vec[Int]; offsets: Vec[Int]; sizes: Vec[Int]; }

pub fn wasm_is_module(data: &Vec[UInt8]) -> Bool
pub fn wasm_leb_u32(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str]
pub fn wasm_section_name(id: Int) -> Str
pub fn wasm_parse_sections(data: &Vec[UInt8]) -> Result[WasmSections, Str]
pub fn wasm_export_names(data: &Vec[UInt8]) -> Result[Vec[Str], Str]
```

## Error string catalog

| Error text | Raised by | Condition |
|---|---|---|
| `wasm: truncated header` | `wasm_parse_sections`, `wasm_export_names` | fewer than 8 bytes (including fewer than 4, or a valid 4-byte magic alone) |
| `wasm: bad magic` | `wasm_parse_sections`, `wasm_export_names` | first 4 bytes differ from `00 61 73 6D` |
| `wasm: bad version` | `wasm_parse_sections`, `wasm_export_names` | version bytes differ from `01 00 00 00` |
| `wasm: truncated leb128` | `wasm_leb_u32` and propagated by `wasm_parse_sections` / `wasm_export_names` | encoding starts in range but runs past the end of `data` |
| `wasm: leb128 overflow` | `wasm_leb_u32` and propagated | 5th byte continues the sequence or carries bits above bit 31 |
| `wasm: negative offset` | `wasm_leb_u32` | `off < 0` |
| `wasm: truncated section` | `wasm_parse_sections` | declared payload extends past the end of `data` |
| `wasm: truncated export` | `wasm_export_names` | an export entry (name, kind or index) runs past the declared section payload, or the declared count needs more entries than the payload holds |
| `wasm: trailing export bytes` | `wasm_export_names` | payload bytes remain after the declared export count is parsed |
| `wasm: nul in export name` | `wasm_export_names` | an export-name byte is `0x00` (unrepresentable in the NUL-terminated `Str`) |

All messages are static uppercase-lowercase ASCII literals prefixed with
`wasm: `; tests pin them with `str_compare`.

## Semantics and guarantees

- `wasm_is_module` never touches bytes past the 8-byte header and accepts
  any valid prefix of a module.
- `wasm_leb_u32` returns value in `0..4294967295` and an offset not past
  `data.len()`; non-minimal encodings are accepted (structure-only).
- `wasm_parse_sections` performs no I/O and allocates three vectors
  proportional to the section count.
- `wasm_export_names` returns a fresh `Vec[Str]`; each name is a fresh
  `Str` built with `xiom.string.builder.sb_to_str` (one allocation per
  name, bytes verbatim, no UTF-8 validation).
- A malformed export entry aborts the whole call with `Err`; no partial
  name list is returned.

## Complexity

| Operation | Complexity |
|---|---|
| `wasm_is_module` | O(1) |
| `wasm_leb_u32` | O(1) (at most 5 bytes) |
| `wasm_section_name` | O(1) |
| `wasm_parse_sections` | O(sections) time and allocation |
| `wasm_export_names` | O(section count + total export bytes) |

## Test plan

`tests/test_conformance.xi` (`module wasm_tests`, 22 named tests; `main`
prints `[PASS]`/`[FAIL]` per test, a summary line, and returns the failure
count). Coverage:

1. `wasm_is_module` true for the bare header, a full hand-built module and
   a header with trailing bytes;
2. `wasm_is_module` false for empty, 4-byte, 7-byte, bad-magic and
   bad-version inputs;
3. LEB128 single-byte values 0, 1, 42, 127;
4. LEB128 two-byte values 128, 129, 255, 300;
5. LEB128 three-byte 624485, 5-byte maximum 4294967295 and a non-minimal
   5-byte zero;
6. LEB128 at a non-zero offset in a stream (value and next-offset pins);
7. LEB128 truncation errors (empty, lone continuation, four continuation
   bytes, offset past end) and the negative-offset error;
8. LEB128 overflow errors (5th byte `0x10`, 5th byte `0x7f`, 6-byte
   sequence);
9. `wasm_section_name` for ids 0..12;
10. `wasm_section_name` for 13, 31, 255 and -1;
11. section walk on the hand-built module: ids `[1,3,7]`, offsets
    `[10,17,21]`, sizes `[5,2,21]`;
12. header-only module: three empty vectors;
13. custom (id 0) + unknown (id 31) + data (id 11) zero-size sections,
    payloads ending at EOF (offsets `[10,13,15]`, sizes `[1,0,0]`);
14. multi-byte section size LEB (130) on a 141-byte module;
15. truncated sections: id-only, short payload, truncated size LEB,
    overflow size LEB, declared u32-max payload;
16. header error texts for truncation, bad magic and bad version;
17. export names of the hand-built module, in order, including `π`;
18. no export section: header-only and type-only modules -> empty list;
19. malformed export entries: short name, missing kind byte, truncated
    index LEB, overflow index LEB, truncated second entry, trailing bytes
    after the declared count, NUL byte in a name;
20. export index LEB crossing the declared payload boundary into the next
    section, plus propagated section errors (truncated section, bad
    magic);
21. multi-byte name-length LEB (130) and multi-byte index LEB (300);
22. empty export payload (size 0) and `count == 0` both yield an empty
    name list.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.wasm
```

Last verified: compiler 0.61.3,
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Structure-only: accepts semantically invalid modules (wrong indices,
  bad instruction bytes, missing code section, duplicate/ordering
  violations) as long as the container is well-formed.
- Non-minimal LEB128 encodings are accepted and reported with the full
  byte count consumed.
- Unknown section ids are recorded verbatim.
- Only the first export section is read.
- Export kind and index are consumed but not returned or validated.
- Export names are not UTF-8 validated.
- `WasmSections` offsets/sizes are only meaningful for the exact buffer
  passed to `wasm_parse_sections`.
- Not thread-safe; all values are plain copyable types.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_pair`/`_err_pair`/`_ok_sections`/`_err_sections`/`_ok_names`/
  `_err_names` (constructing Results directly in other functions
  miscompiles in this compiler).
- Byte widening goes through `(x as Int) & 0xFF`; a bare `as Int` on a
  `UInt8` that carries high bit patterns miscompiles (packet/msgpack
  precedent).
- Match arms are exhaustive over `Result`; nested matches are used so no
  variable is assigned across a match arm boundary.
- No function mixes a `&local` call with a later `&mut local` call
  (advisory E001); every library helper takes `&Vec[UInt8]` and no
  library function takes `&mut`.
- Str materialization from bytes uses the stdlib
  `xiom.string.builder.sb_to_str` (single allocation, ownership
  transfer); the package declares no `extern "C"` blocks (no FFI).
