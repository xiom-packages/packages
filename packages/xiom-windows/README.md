# xiom.windows

Pure-XIOM, read-only **structure** parser for Windows Registry hive files
(REGF). No FFI, no registry API access, no hive writes.

> **Status:** `incubating` -- implemented, harness-green with compiler
> v0.61.3 (`port: PASS (passed=25 failed=0 program_exit=0 exit=0)`),
> not published.
> **Scope:** base block, hbin blocks, cell table (allocated and
> free/deleted cells), nk/vk/sk records, lf/lh/li/ri subkey lists, db big
> data, a BFS key-tree walk, key/value accessors, case-insensitive path
> resolution.

## Usage

```xi
use xiom.io; use xiom.windows;

let r = regf_parse(&hive_bytes);
if r.is_ok {
  let f: RegfHive = r.value;
  io.println(regf_file_name(&f));
  let nk = regf_key_count(&f);
  let vk = regf_value_count(&f);
  // Key 0 is the root; children and values are reached by walk index:
  let nr = regf_key_name(&f, 0);
  if nr.is_ok {
    io.println(nr.value);
  }
  let path = regf_path_resolve(&f, "Software");
  if path.is_ok {
    // walk index of the Software key
  }
  let dword = regf_value_dword(&hive_bytes, &f, 0);
}
```

Pointers on the API shape:

- `RegfHive` stores scalars and **flat parallel `Vec` tables**; raw bytes
  stay in the buffer passed to `regf_parse`. Byte-level accessors
  (`regf_value_data`, `regf_value_dword`, `regf_value_qword`,
  `regf_value_str`, `regf_value_multi_str`) take that buffer back.
- Keys are numbered in BFS order from the root (walk index 0). A key's
  children are `regf_key_subkey(f, i, 0..regf_key_subkey_count(f, i))`;
  its values are `regf_key_value(f, i, 0..regf_key_value_count(f, i))`.
- Names are decoded at parse time: ASCII ("compressed") names directly,
  UTF-16LE names to UTF-8. Non-ASCII bytes in a compressed name, lone
  surrogates and code unit 0 decode to U+FFFD, so parsed names never
  contain a NUL byte.
- `Str` values read from tables must be compared with
  `regf_name_equal` (or `xiom.string.compare.str_compare`), never with
  `==` (BUG 17: `==` on a `Str` read from a `Vec` lowers to a pointer
  comparison).

## Honest scope

- **Structure only.** The parser assigns no semantic meaning to key or
  value names and no side effects; REG_* data is exposed raw and decoded
  only by the documented accessors (DWORD/DWORD_BIG_ENDIAN, QWORD,
  SZ/EXPAND_SZ, MULTI_SZ).
- **Read-only, in-memory.** Parsing works on a `Vec[UInt8]`; there is no
  streaming, no file I/O, no write path and no cell allocation.
- **No log replay.** Transaction log hives (`file_type == 1`) parse only
  as their on-disk structure; sequence-number mismatches are reported as
  a warning state, not repaired.
- **Deleted content is exposed, not interpreted.** Free cells are listed
  in the cell table with `regf_cell_allocated == 0` and a best-effort
  signature tag (`regf_cell_kind`), so a deleted nk remains visible; its
  record is not parsed. Free cells are never walked.
- **Cell offsets are hive-bins-relative u32 values.** Offsets with the
  top bit set other than the all-ones sentinel are rejected; no negative
  offset arithmetic is attempted.
- **Descriptor bytes are not interpreted:** `sk` cells are validated and
  their span/refcount/flags exposed; the security descriptor itself is
  opaque bytes.
- **Vectors without `Vec[StructType]`:** tables are parallel vectors; a
  record's fields are read through the `REGF_*_FIELD_*` selectors.

See `SPEC.md` for byte-level layouts, validation order and the full error
catalog (every structural error carries the offending byte offset).

## Build and test

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.windows
```

The conformance suite (`tests/test_conformance.xi`, 25 named tests) builds
a 28672-byte synthetic hive in-test (base block, three hbins, six keys,
six values covering inline DWORD, direct QWORD, REG_SZ, REG_MULTI_SZ,
REG_BINARY and a 16345-byte db big-data value, lf/li/ri subkey lists, an
sk cell and a deleted nk cell) and mutates it for the malformed-input
cases. Fixture bytes are assembled in the test file, independent of
`src/windows.xi`.
