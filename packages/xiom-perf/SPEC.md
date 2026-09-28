# xiom.perf -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.perf`, version `0.1.0`).
Module: `src/perf.xi` (`module xiom.perf`).
Depends on `xiom.std`; the library module imports `xiom.convert.int` (for
decimal byte offsets in error messages). The tests add `xiom.test`,
`xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`. No FFI.

## Scope

A pure-XIOM (no FFI) read-only STRUCTURE parser for the on-disk
`perf.data` file written by the Linux `perf` tool (magic `PERFILE2`):

- `perf_parse` validates and reads the fixed header, the attrs section,
  the data-section record stream and the feature section descriptors, and
  returns a `PerfFile` index (scalars + flat parallel vectors);
- bytes are never copied wholesale: every parsed value is an offset/size
  pair into the caller's `Vec[UInt8]`, and accessors return computed
  values or spans;
- typed payload decoders for the documented record subset and for the
  documented feature payload subset (see the byte-level tables below);
- SAMPLE payloads are reconstructed by walking the selected attr's
  `sample_type` in kernel emission order, skipping the documented
  variable-size fields in between;
- `sample_id_all` identity tails on non-SAMPLE records are decoded from
  the end of the record;
- deterministic `Err(Str)` messages for malformed input (see the catalog).

## Non-goals

- Semantic sample interpretation: no symbolization, callchain expansion,
  register/stack decoding, time conversion, or memory-access analysis.
- Auxiliary trace payloads: AUX/AUXTRACE data is exposed as raw spans only.
- Writing, rewriting or building perf.data files (read-only package).
- Big-endian files: recognized and rejected (little-endian primary only).
- pipe-mode (`perf_pipe_file_header`) streams: not parsed; a pipe stream
  fails the fixed-header validation.
- Compressed (`PERF_RECORD_COMPRESSED*`) content: records are indexed, the
  compressed payload is not decompressed.
- Kernel/user address resolution and per-CPU merge; records are returned
  in file order, not timestamp order.

## File layout

```
+----------------------------+ offset 0
| perf_file_header, 104 B    |
+----------------------------+ attrs.offset
| attrs section              |   attr_size-byte records:
|   perf_event_attr          |     attr (attr.size bytes)
|   {ids.offset, ids.size}   |     ids perf_file_section (16 B)
+----------------------------+ data.offset
| data section               |   packed perf_event records
+----------------------------+ data.offset + data.size
| feature section descriptors|   one 16-byte {offset,size} per set bit,
|   (increasing bit order)   |   in kernel HEADER_* bit order (1..31)
+----------------------------+
| feature payloads           |   anywhere in the file; pointed to by
|                            |   the descriptors (this package's fixtures
|                            |   place them right after the descriptors)
+----------------------------+
```

Implementation reads the feature descriptors starting at
`data.offset + data.size` for every set feature bit in increasing order
(bits 1..31); bit 0 (`HEADER_RESERVED`) and reserved bits >= 32 are
ignored and no descriptor is expected for them.

## Fixed header (104 bytes, all little-endian)

| Offset | Size | Field | Handling |
|---|---|---|---|
| 0 | 8 | magic `"PERFILE2"` | validated; byte-swapped `"2ELIFREP"` rejected as BE |
| 8 | 8 | `size` | must be >= 104; larger values accepted, trailing bytes ignored |
| 16 | 8 | `attr_size` | attrs record stride; 64..65536 and a multiple of 8 |
| 24 | 8 | `attrs.offset` | section span validated against the buffer |
| 32 | 8 | `attrs.size` | must be a multiple of `attr_size` |
| 40 | 8 | `data.offset` | section span validated |
| 48 | 8 | `data.size` | |
| 56 | 8 | `event_types.offset` | span validated (contents not parsed) |
| 64 | 8 | `event_types.size` | |
| 72 | 32 | feature bitmap | 4 raw u64 words; bit F = word `F/64`, bit `F%64` |

## Feature bits (kernel `HEADER_*` enum order)

The bitmap is the `perf_file_header` flags bitset; bit positions are the
kernel enum values, not sequential convenience numbers.

| Bit | Name | Payload decoder |
|---|---|---|
| 0 | `HEADER_RESERVED` | always cleared; ignored |
| 1 | `PERF_FEATURE_TRACING_DATA` | raw span only |
| 2 | `PERF_FEATURE_BUILD_ID` | count + records (below) |
| 3 | `PERF_FEATURE_HOSTNAME` | `perf_header_string` |
| 4 | `PERF_FEATURE_OSRELEASE` | `perf_header_string` |
| 5 | `PERF_FEATURE_VERSION` | `perf_header_string` |
| 6 | `PERF_FEATURE_ARCH` | `perf_header_string` |
| 7 | `PERF_FEATURE_NRCPUS` | raw span only |
| 8 | `PERF_FEATURE_CPUDESC` | raw span only |
| 9 | `PERF_FEATURE_CPUID` | raw span only |
| 10 | `PERF_FEATURE_TOTAL_MEM` | raw span only |
| 11 | `PERF_FEATURE_CMDLINE` | string list (below) |
| 12 | `PERF_FEATURE_EVENT_DESC` | raw span only |
| 13 | `PERF_FEATURE_CPU_TOPOLOGY` | cores/threads lists + cpu entries |
| 14 | `PERF_FEATURE_NUMA_TOPOLOGY` | presence only |
| 15..31 | BRANCH_STACK, PMU_MAPPINGS, GROUP_DESC, AUXTRACE, STAT, CACHE, SAMPLE_TIME, MEM_TOPOLOGY, CLOCKID, DIR_FORMAT, BPF_PROG_INFO, BPF_BTF, COMPRESSED, CPU_PMU_CAPS, CLOCK_DATA, HYBRID_TOPOLOGY, PMU_CAPS | presence + raw span only |

`perf_feature_count`/`perf_feature_bit` enumerate the present features in
increasing bit order; `perf_feature_section_field` returns the
descriptor's offset/size; `perf_feature_bytes` copies the payload.

### Feature payload shapes implemented

`perf_header_string` (hostname/osrelease/version/arch, and every
string-list element):

| Offset | Size | Field |
|---|---|---|
| 0 | 4 | `len` (includes the terminating NUL) |
| 4 | len | bytes |

CMD `perf_header_string_list` (cmdline): `u32 nr`, then `nr`
`perf_header_string` records back to back.

CPU topology (revision 2): `cores` string list, `threads` string list,
then `nr_cpus_avail` entries of `{core_id u32, socket_id u32}`. The entry
count is computed as `(payload_size - lists_size) / 8`; revision-3
(trailing die data) is not decoded and is ignored.

BUILD_ID feature (as specified for this package): `u32 count`, then
`count` records of `{pid u32, build_id bytes}` with a caller-supplied
build-id width (`perf_feature_build_id_field(..., bid_size, ...)`, 1..64).
The records must fit the payload or the call fails with
`perf: build_id feature truncated`.

## Attrs section

Records are `attr_size` bytes apart starting at `attrs.offset`; the count
is `attrs.size / attr_size`. At each record offset:

| Offset | Size | Field |
|---|---|---|
| 0 | `attr.size` | `perf_event_attr`; validated `64 <= attr.size`, `attr.size + 16 <= attr_size` |
| `attr.size` | 8 | ids section offset (u64) |
| `attr.size + 8` | 8 | ids section size (u64) |

The ids section points at an array of u64 ids (`size / 8` entries, id `k`
at `offset + 8k`).

### perf_event_attr fields (little-endian; fields read as 0 past `attr.size`)

| Offset | Size | Field | Readable when `attr.size >=` |
|---|---|---|---|
| 0 | 4 | type | 4 |
| 4 | 4 | size | 8 |
| 8 | 8 | config | 16 |
| 16 | 8 | sample_period / sample_freq | 24 |
| 24 | 8 | sample_type | 32 |
| 32 | 8 | read_format | 40 |
| 40 | 8 | flag word | 48 |
| 48 | 4 | wakeup_events (watermark when the flag is set) | 52 |
| 52 | 4 | bp_type | 56 |
| 56 | 8 | config1 | 64 |
| 64 | 8 | config2 | 72 |
| 72 | 8 | branch_sample_type | 80 |
| 80 | 8 | sample_regs_user | 88 |
| 88 | 4 | sample_stack_user | 92 |
| 92 | 4 | clockid | 96 |
| 96 | 8 | sample_regs_intr | 104 |
| 104 | 4 | aux_watermark | 108 |

Size revisions: VER0 64, VER1 72, VER2 80, VER3 96, VER4 104, VER5 112,
VER6 120, VER7 128, VER8 136 (constants exported).

### attr flag bits (`perf_attr_flag`)

| Bit | Name | Bit | Name |
|---|---|---|---|
| 0 | DISABLED | 19 | EXCLUDE_HOST |
| 1 | INHERIT | 20 | EXCLUDE_GUEST |
| 2 | PINNED | 21 | EXCLUDE_CALLCHAIN_KERNEL |
| 3 | EXCLUSIVE | 22 | EXCLUDE_CALLCHAIN_USER |
| 4 | EXCLUDE_USER | 23 | MMAP2 |
| 5 | EXCLUDE_KERNEL | 24 | COMM_EXEC |
| 6 | EXCLUDE_HV | 25 | USE_CLOCKID |
| 7 | EXCLUDE_IDLE | 26 | CONTEXT_SWITCH |
| 8 | MMAP | 27 | WRITE_BACKWARD |
| 9 | COMM | 28 | NAMESPACES |
| 10 | FREQ | 29 | KSYMBOL |
| 11 | INHERIT_STAT | 30 | BPF_EVENT |
| 12 | ENABLE_ON_EXEC | 31 | AUX_OUTPUT |
| 13 | TASK | 32 | CGROUP |
| 14 | WATERMARK | 33 | TEXT_POKE |
| 15 | PRECISE_IP (2 bits, 15-16) | 34 | BUILD_ID |
| 17 | MMAP_DATA | 35 | INHERIT_THREAD |
| 18 | SAMPLE_ID_ALL | 36 | REMOVE_ON_EXEC |
| | | 37 | SIGTRAP |

### sample_type and read_format (kernel bit values)

`PERF_SAMPLE_*`: IP 1, TID 2, TIME 4, ADDR 8, ID 16, STREAM_ID 32, CPU 64,
PERIOD 128, READ 256, CALLCHAIN 512, RAW 1024, BRANCH_STACK 2048,
REGS_USER 4096, STACK_USER 8192, WEIGHT 16384, DATA_SRC 32768,
IDENTIFIER 65536, TRANSACTION 131072, REGS_INTR 262144, PHYS_ADDR 524288,
AUX 1048576, CGROUP 2097152, DATA_PAGE_SIZE 4194304, CODE_PAGE_SIZE
8388608, WEIGHT_STRUCT 16777216.

`PERF_FORMAT_*`: TOTAL_TIME_ENABLED 1, TOTAL_TIME_RUNNING 2, ID 4,
GROUP 8, LOST 16.

## Data section: event records

Record header (8 bytes): `type u32`, `misc u16`, `size u16`; `size`
includes the header. The walk is exact: records are packed from
`data.offset` to `data.offset + data.size`; every record must have
`size >= 8` and lie entirely inside the section. There is no reordering.

Misc bits: cpumode mask 7 (UNKNOWN 0, KERNEL 1, USER 2, HYPERVISOR 3,
GUEST_KERNEL 4, GUEST_USER 5), MMAP_DATA/COMM_EXEC/FORK_EXEC 1<<12,
SWITCH_OUT 1<<13, SWITCH_OUT_PREEMPT/EXACT_IP 1<<14, EXT_RESERVED 1<<15.

### Record types and payloads

| Value | Name | Payload implemented |
|---|---|---|
| 1 | MMAP | pid u32, tid u32, addr u64, len u64, pgoff u64, filename[] |
| 2 | LOST | id u64, lost u64 |
| 3 | COMM | pid u32, tid u32, comm[] (size-delimited, not NUL-terminated) |
| 4 | EXIT | pid, ppid, tid, ptid (u32 each), time u64 |
| 5 | THROTTLE | time u64, id u64, stream_id u64 |
| 6 | UNTHROTTLE | time u64, id u64, stream_id u64 |
| 7 | FORK | pid, ppid, tid, ptid (u32 each), time u64 |
| 8 | READ | pid u32, tid u32, then read_format fields (below) |
| 9 | SAMPLE | sample_type-driven (below) |
| 10 | MMAP2 | pid, tid, addr u64, len u64, pgoff u64, maj u32, min u32, ino u64, ino_generation u64, prot u32, flags u32, filename[] |
| 11 | AUX | aux_offset u64, aux_size u64, flags u64 |
| 12 | ITRACE_START | pid u32, tid u32 |
| 13 | LOST_SAMPLES | lost u64 |
| 14 | SWITCH | next_prev_pid u32, next_prev_tid u32 |
| 15 | SWITCH_CPU_WIDE | next_prev_pid u32 (the CPU), next_prev_tid u32 |
| 16 | NAMESPACES | pid u32, tid u32, nr u64, entries of {dev u64, ino u64} |
| 17 | KSYMBOL | address u64, len u32, ksym_type u16, flags u16, name[] |
| 18 | BPF_EVENT | type u16, flags u8, pad u8, id u32 |
| 19 | CGROUP | raw span only |
| 20 | TEXT_POKE | raw span only |
| 21 | AUX_OUTPUT_HW_ID | raw span only |
| 64 | HEADER_ATTR | raw span only |
| 65 | HEADER_EVENT_TYPE | raw span only |
| 66 | HEADER_TRACING_DATA | raw span only |
| 67 | HEADER_BUILD_ID | pid u32, build_id[bid_size], filename[] (caller-supplied width 1..64) |
| 68 | FINISHED_ROUND | no payload |
| 69 | ID_INDEX | nr u64, entries of {id u64, idx u64, cpu u64, tid u64} (32 B each) |
| 70..83 | AUXTRACE_INFO, AUXTRACE, AUXTRACE_ERROR, THREAD_MAP, CPU_MAP, STAT_CONFIG, STAT, STAT_ROUND, EVENT_UPDATE, TIME_CONV, HEADER_FEATURE, COMPRESSED, FINISHED_INIT, COMPRESSED2 | raw span only |

Every other type value walks as a record (size-validated) and is named
`UNKNOWN`.

### READ payload (`perf_read_field`)

`pid u32` at 0, `tid u32` at 4, then the read_format-driven values:
`value u64` at 8; `time_enabled u64` at 16 when TOTAL_TIME_ENABLED;
`time_running u64` after it when TOTAL_TIME_RUNNING; `id u64` after those
when ID. GROUP read formats are recognized and rejected (their
variable-length member values are not decoded). Reading a field whose
read_format bit is clear is
`Err("perf: read field not present in read_format")`.

### SAMPLE reconstruction (`perf_sample_field`)

Fields are emitted in this fixed kernel order; the walker accumulates the
documented sizes and returns the requested field:

| sample_type bit | Payload size | Notes |
|---|---|---|
| IDENTIFIER (1<<16) | 8 | first when present |
| IP (1<<0) | 8 | |
| TID (1<<1) | 8 | pid u32 + tid u32 |
| TIME (1<<2) | 8 | |
| ADDR (1<<3) | 8 | |
| ID (1<<4) | 8 | |
| STREAM_ID (1<<5) | 8 | |
| CPU (1<<6) | 8 | cpu u32 + res u32 |
| PERIOD (1<<7) | 8 | |
| READ (1<<8) | read_format-driven | first value @ offset; GROUP returns the count word |
| CALLCHAIN (1<<9) | 8 + nr*8 | skipped |
| RAW (1<<10) | 4 + size | skipped |
| BRANCH_STACK (1<<11) | 8 + nr*24 | skipped |
| REGS_USER (1<<12) | 8 + popcount(sample_regs_user)*8 | skipped |
| STACK_USER (1<<13) | 8 + size + 8 | skipped |
| WEIGHT (1<<14) / WEIGHT_STRUCT (1<<24) | 8 | one weight word, skipped |
| DATA_SRC (1<<15) | 8 | skipped |
| TRANSACTION (1<<17) | 8 | skipped |
| REGS_INTR (1<<18) | 8 + popcount(sample_regs_intr)*8 | skipped |
| PHYS_ADDR (1<<19) | 8 | skipped |
| AUX (1<<20) | 8 | skipped |
| CGROUP (1<<21) | 8 | skipped |
| DATA_PAGE_SIZE (1<<22) | 8 | skipped |
| CODE_PAGE_SIZE (1<<23) | 8 | skipped |

Decoded field selectors: IDENTIFIER, IP, PID, TID, TIME, ADDR, ID,
STREAM_ID, CPU, PERIOD, READ_VALUE. A selector whose bit is clear is
`Err("perf: sample field not present in sample_type")`; every skipped
field must fit the record payload or the call fails with
`perf: sample payload truncated`; a GROUP read format before a later
requested field is `Err("perf: grouped read format not supported")`.

### sample_id tails (`perf_sample_id_tail_field`)

For non-SAMPLE records, when the selected attr's flag word has
SAMPLE_ID_ALL (bit 18) set, the identity subset of `sample_type` is
appended after the type-specific payload in this fixed order: TID (8),
TIME (8), ID (8), STREAM_ID (8), CPU (8), IDENTIFIER (8). The tail size is
the sum of the selected 8-byte fields and the tail is read from the end of
the record (`record_offset + record_size - tail_size`), so no
per-record payload size is needed. PID/TID share the TID slot.

## Validation order and error catalog

`perf_parse` checks in this order and returns the first error; the buffer
is never partially accepted:

| # | Condition | Error text |
|---|---|---|
| 1 | buffer shorter than 8 bytes | `perf: truncated magic` |
| 2 | neither LE nor BE magic | `perf: bad magic` |
| 3 | byte-swapped BE magic | `perf: big-endian perf.data not supported` |
| 4 | buffer shorter than 104 bytes | `perf: truncated header` |
| 5 | header `size` < 104 | `perf: bad header size at 8` |
| 6 | `attr_size` < 64, > 65536, or not a multiple of 8 | `perf: bad attr size at 16` |
| 7 | attrs span outside the buffer | `perf: attrs section out of bounds` |
| 8 | data span outside the buffer | `perf: data section out of bounds` |
| 9 | event_types span outside the buffer | `perf: event_types section out of bounds` |
| 10 | `attrs.size % attr_size != 0` | `perf: attrs section size not a multiple of attr_size` |
| 11 | attr record's `size` < 64 or `size + 16 > attr_size` | `perf: bad attr record size at <off>` |
| 12 | ids span outside the buffer | `perf: ids section out of bounds at <off>` |
| 13 | fewer than 8 bytes left in the data section | `perf: truncated record at <off>` |
| 14 | record `size` < 8 | `perf: bad record size at <off>` |
| 15 | record extends past the data section | `perf: oversized record at <off>` |
| 16 | feature descriptor list truncated | `perf: feature sections out of bounds` |
| 17 | feature payload span outside the buffer | `perf: feature section out of bounds at <off>` |

Accessor errors: `perf: index out of range`, `perf: record index out of
range`, `perf: attr index out of range`, `perf: bad field selector`,
`perf: record type mismatch`, `perf: record payload out of bounds`,
`perf: bad attr flag bit`, `perf: feature not present`,
`perf: feature payload out of bounds`, `perf: string list out of bounds`,
`perf: build_id feature truncated`, `perf: bad build id size`,
`perf: negative id_index count at <off>`, `perf: sample field not present
in sample_type`, `perf: sample payload truncated`, `perf: grouped read
format not supported`, `perf: sample_id_all not set`, `perf: sample_id
field not present in sample_type`, `perf: sample_id tail not applicable to
SAMPLE records`, `perf: sample_id tail out of bounds`, `perf: span out of
bounds`.

## Complexity

| Operation | Complexity |
|---|---|
| `perf_parse` | O(data.len() + attrs + records + features) |
| header/attr/record field accessors | O(1) |
| `perf_sample_field` / `perf_sample_id_tail_field` | O(sample_type fields) |
| feature section/bit lookups | O(present features) |
| feature string/list walks | O(k string lengths) |
| `perf_span_bytes` | O(size) |

## Test plan

`tests/test_conformance.xi` (`module perf_tests`, 20 named tests; `main`
prints `[RUN]`/`[PASS]`/`[FAIL]` per test, flushes, and returns the
failure count). Fixtures are assembled byte by byte in the test file,
independent of `src/perf.xi`:

1. minimal 104-byte file: header fields, empty tables, LE variant;
2. bad magic, BE magic (recognized), truncated magic/header;
3. header sizes, section spans and attrs length alignment;
4. attr: every field, flag bits, ids array, selector errors;
5. attr size 64: present fields read, later fields are 0, size/ids errors;
6. record walk: 7 records with offsets/sizes, type names, misc;
7. MMAP and MMAP2 payloads decode field by field;
8. COMM pid/tid/text span decode;
9. FORK and EXIT pid/ppid/tid/ptid/time decode;
10. LOST/READ/THROTTLE/SWITCH/AUX/ITRACE/LOST_SAMPLES/NAMESPACES/KSYMBOL/
    BPF payloads;
11. SAMPLE: IP/TID/TIME/ADDR/ID/STREAM_ID/CPU/PERIOD/READ reconstructed;
12. SAMPLE with IDENTIFIER first, CALLCHAIN skip and READ id/time flags;
13. sample_id tails: pid/tid/time/cpu/identifier after the payload;
14. ID_INDEX entries and BUILD_ID records with 20/32-byte ids;
15. features: build_id, strings, cmdline list, cpu_topology and errors;
16. feature descriptors: truncated array, bad payload span, presence/selector
    errors;
17. record walk rejects size < 8, oversized and truncated trailing bytes;
18. 64-bit fields: bit 63 decodes raw; negative offsets/counts rejected
    with offsets;
19. two attrs at stride 152 with independent ids sections;
20. span copies and feature byte accessors: bounds and empty results.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.perf
```

Last verified: compiler 0.61.3,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Documented corrections to the port brief

- The feature bitmap uses the kernel `HEADER_*` enum bit positions
  (BUILD_ID 2, HOSTNAME 3, OSRELEASE 4, VERSION 5, ARCH 6, NRCPUS 7,
  CPUDESC 8, CPUID 9, TOTAL_MEM 10, CMDLINE 11, EVENT_DESC 12,
  CPU_TOPOLOGY 13, NUMA_TOPOLOGY 14, ...) rather than the brief's shorthand
  bit values 1/2/4/8/16/32/64.
- `read_format` bits are the kernel values (TOTAL_TIME_ENABLED 1,
  TOTAL_TIME_RUNNING 2, ID 4, GROUP 8, LOST 16), not 1/2/4/8.
- `PERF_RECORD_AUX_OUTPUT_HW_ID` is 21 (not 22); `PERF_RECORD_ID_INDEX` is
  69 and the header BUILD_ID record is 67 in the 64+ perf-record user
  range (not 23/24).
- The attrs stride is `header.attr_size`, and each entry is
  `perf_event_attr` (its own `size` bytes) followed by the 16-byte ids
  descriptor; ids live at record offset + `attr.size`.

## Known limitations

- **Modern build-id record variant.** perf's newer
  `perf_record_header_build_id` adds a u8 size field after the pid (with
  the `PERF_RECORD_MISC_BUILD_ID_SIZE` misc flag) and a fixed-width data
  array; this parser implements the documented `pid + build_id +
  filename` shape with a caller-supplied width. Files written by newer
  perf may need a different interpretation of that record.
- **BUILD_ID feature shape.** The brief specifies `count + records`
  (`{pid, build_id}`); perf's shipped format documentation describes a
  sequence of header-ful `build_id_event` records instead. This package
  implements the brief's shape (documented above), so its feature decoder
  is narrowed to that layout.
- **Feature descriptor order.** Descriptors are read sequentially in
  increasing bit order directly after the data section, as the shipped
  format documentation describes.
- **cpu_topology revision 3** (dies) is ignored; trailing bytes do not
  extend the entry count beyond `remaining / 8`.
- **Grouped read formats** are rejected; only single-counter READ values
  are decoded.
- **TEXT_POKE / CGROUP / AUX_OUTPUT_HW_ID payloads** are raw spans.
- **No unsigned 64-bit type**: bit 63 set decodes as a negative Int, and
  such values are rejected wherever an offset/size/count is expected.
- **Pipe-mode streams** and compressed payloads are not parsed.
- `PerfFile` is a plain value type; not thread-safe.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the tiny leaf helpers
  `_ok_file`/`_err_file`/`_ok_unit`/`_err_unit`/`_ok_int`/`_err_int`/
  `_ok_bool`/`_err_bool`/`_ok_str`/`_err_str`/`_ok_ints`/`_err_ints`/
  `_ok_bytes`/`_err_bytes` (constructing Results directly in other
  functions miscompiles).
- Every `Vec[UInt8]` byte read is widened with `(b as Int) & 0xFF` before
  entering Int arithmetic; `Vec[Int]` element reads are bound to typed
  locals.
- 64-bit decoding uses the xiom.pack shape (low seven bytes accumulate
  with a `place` factor, the top byte is applied separately).
- Bit tests use arithmetic extraction, never `&`, on values with bit 31
  set; bits 62/63 are handled separately because `place * 2` overflows.
- The package declares no `extern "C"` blocks (no FFI).
- The build-id width is a caller parameter because the on-disk field is
  not self-describing.
