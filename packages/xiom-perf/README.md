# xiom.perf

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.2` on the XIOM registry.
> **Scope:** pure-XIOM read-only STRUCTURE parser for Linux `perf.data`
> files (magic `PERFILE2`): file header, feature sections, attrs records,
> the record stream and typed record payloads.
> **Deps:** `xiom.std` only. The library module imports
> `xiom.convert.int` (decimal byte offsets in error messages); the tests use
> `xiom.test`, `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex` from
> it. No FFI.

## What it is

`xiom.perf` parses the structural layer of a Linux `perf.data` file:
the fixed 104-byte header (magic, size, attr_size, the attrs/data/
event_types `perf_file_section` descriptors, 256-bit feature bitmap), the
feature section descriptors that follow the data section, every
`perf_event_attr` record (with its ids descriptor), and the data section's
event record stream. Every parsed value is an offset/size pair into the
caller's byte buffer; nothing is copied wholesale and nothing is written.

`perf_parse` validates the magic (little-endian `PERFILE2`; the
byte-swapped big-endian form is recognized and rejected), header size,
`attr_size`, all section spans, every attr record and ids span, every
record header (`size >= 8`, whole record inside the data section) and every
feature descriptor. The record stream is then indexed and decoded on
demand.

Typed decoders cover MMAP, MMAP2, COMM, FORK, EXIT, LOST, READ, THROTTLE,
UNTHROTTLE, SAMPLE, SWITCH, SWITCH_CPU_WIDE, AUX, ITRACE_START,
LOST_SAMPLES, NAMESPACES, KSYMBOL, BPF_EVENT, ID_INDEX and the header
BUILD_ID record. SAMPLE payloads are reconstructed from a selected attr's
`sample_type` (IDENTIFIER, IP, TID, TIME, ADDR, ID, STREAM_ID, CPU, PERIOD
and the first READ value), skipping the documented variable-size fields in
between. Non-SAMPLE records can have their `sample_id_all` identity tail
(TID, TIME, ID, STREAM_ID, CPU, IDENTIFIER) decoded from the end of the
record. Feature payload decoders cover build_id (count + records), the
string features (hostname, osrelease, version, arch), the cmdline string
list and cpu_topology (cores/threads lists plus core_id/socket_id entries).

No samples are interpreted semantically, no callchains or register frames
are expanded, and no PMU or kernel state is touched.

## API

| Function | Returns | Description |
|---|---|---|
| `perf_parse(data)` | `Result[PerfFile, Str]` | Validate and index the whole structure. |
| `perf_variant(data)` | `Int` | `PERF_VARIANT_LE` / `_BE` / `_UNKNOWN` from the magic. |
| `perf_header_size(f)` / `perf_attr_size(f)` | `Int` | Header scalars. |
| `perf_section_field(f, field)` | `Result[Int, Str]` | attrs/data/event_types section offset/size. |
| `perf_feature_present(f, feat)` | `Bool` | One feature bit. |
| `perf_feature_count(f)` / `perf_feature_bit(f, i)` | `Int` / `Result[Int, Str]` | Present features in bit order. |
| `perf_feature_section_field(f, feat, field)` | `Result[Int, Str]` | Feature payload offset/size. |
| `perf_feature_bytes(data, f, feat)` | `Result[Vec[UInt8], Str]` | Raw feature payload copy. |
| `perf_attr_count(f)` | `Int` | Number of attrs records. |
| `perf_attr_field(f, i, field)` | `Result[Int, Str]` | One `PERF_ATTR_FIELD_*` field. |
| `perf_attr_flag(f, i, bit)` | `Result[Bool, Str]` | One `PERF_ATTR_FLAG_*` bit. |
| `perf_attr_ids_count(f, i)` / `perf_attr_id(data, f, i, k)` | `Result[Int, Str]` | Id array size and values. |
| `perf_attr_ids_section_field(f, i, field)` | `Result[Int, Str]` | Id array offset/size. |
| `perf_record_count(f)` | `Int` | Number of records. |
| `perf_record_field(f, i, field)` | `Result[Int, Str]` | type/misc/offset/size/payload offset/size. |
| `perf_record_misc_is(data, f, i, cpumode)` | `Result[Bool, Str]` | Record cpumode test. |
| `perf_record_type_name(t)` | `Str` | `MMAP`, `SAMPLE`, ... or `UNKNOWN`. |
| `perf_mmap_field` / `perf_mmap2_field` | `Result[Int, Str]` | MMAP / MMAP2 payload fields. |
| `perf_comm_field` | `Result[Int, Str]` | COMM pid/tid/text span. |
| `perf_fork_field` / `perf_exit_field` | `Result[Int, Str]` | FORK / EXIT pid/ppid/tid/ptid/time. |
| `perf_lost_field` / `perf_read_field` | `Result[Int, Str]` | LOST / READ payload fields. |
| `perf_throttle_field` / `perf_unthrottle_field` | `Result[Int, Str]` | THROTTLE / UNTHROTTLE fields. |
| `perf_switch_field` | `Result[Int, Str]` | SWITCH and SWITCH_CPU_WIDE fields. |
| `perf_aux_field` / `perf_itrace_start_field` | `Result[Int, Str]` | AUX / ITRACE_START fields. |
| `perf_lost_samples_field` | `Result[Int, Str]` | LOST_SAMPLES count. |
| `perf_namespaces_field` | `Result[Int, Str]` | NAMESPACES fields incl. per-entry dev/ino. |
| `perf_ksymbol_field` / `perf_bpf_field` | `Result[Int, Str]` | KSYMBOL / BPF_EVENT fields. |
| `perf_id_index_count` / `perf_id_index_entry_field` | `Result[Int, Str]` | ID_INDEX entries. |
| `perf_build_id_field(data, f, i, bid_size, field)` | `Result[Int, Str]` | Header BUILD_ID record with caller-supplied id width. |
| `perf_sample_field(data, f, i, attr_index, field)` | `Result[Int, Str]` | SAMPLE field reconstructed from `sample_type`. |
| `perf_sample_id_tail_field(data, f, i, attr_index, field)` | `Result[Int, Str]` | `sample_id_all` tail of a non-SAMPLE record. |
| `perf_feature_string_field(data, f, feat, sel)` | `Result[Int, Str]` | hostname/osrelease/version/arch string span. |
| `perf_feature_cmdline_count` / `perf_feature_cmdline_field` | `Result[Int, Str]` | cmdline string list. |
| `perf_feature_topo_count` / `perf_feature_topo_string_field` | `Result[Int, Str]` | cpu_topology cores/threads lists. |
| `perf_feature_cpu_entry_count` / `perf_feature_cpu_entry_field` | `Result[Int, Str]` | cpu_topology core_id/socket_id entries. |
| `perf_feature_build_id_count` / `perf_feature_build_id_field` | `Result[Int, Str]` | BUILD_ID feature count and records. |
| `perf_span_bytes(data, off, size)` / `perf_span_str(data, off, size)` | `Result[.., Str]` | Bounds-checked span copies. |

Errors are deterministic `"perf: ..."` strings; see SPEC.md for the full
catalog and the exact validation order.

## Usage

```xi
use xiom.perf;
use xiom.io;
use xiom.convert.int;

// `bytes` holds the whole perf.data file.
let parsed = perf_parse(&bytes);
if parsed.is_ok {
  let f: PerfFile = parsed.value;
  io.println("records: " + int_to_string(perf_record_count(&f)));

  // First attr's sample_type drives SAMPLE reconstruction.
  let n = perf_record_count(&f);
  var i = 0;
  while i < n {
    let t = perf_record_field(&f, i, PERF_REC_FIELD_TYPE);
    if t.is_ok {
      let ty: Int = t.value;
      if ty == PERF_RECORD_SAMPLE {
        let ip = perf_sample_field(&bytes, &f, i, 0, PERF_SAMPLE_FIELD_IP);
        if ip.is_ok {
          io.println("sample ip: " + int_to_string(ip.value));
        }
      }
      if ty == PERF_RECORD_COMM {
        let off = perf_comm_field(&bytes, &f, i, PERF_COMM_FIELD_COMM_OFFSET);
        let len = perf_comm_field(&bytes, &f, i, PERF_COMM_FIELD_COMM_SIZE);
        if off.is_ok && len.is_ok {
          let text = perf_span_str(&bytes, off.value, len.value);
          if text.is_ok {
            io.println("comm: " + text.value);
          }
        }
      }
    }
    i = i + 1;
  }
}

// Feature section access.
if perf_feature_present(&f, PERF_FEATURE_HOSTNAME) {
  let s = perf_feature_string_field(&bytes, &f, PERF_FEATURE_HOSTNAME, PERF_STRING_FIELD_TEXT_OFFSET);
  // ...
}
```

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.perf
```

Expected: the section-4 namespace check passes, 20 `[PASS]` lines, and a
final `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Structure only.** Sample values are raw integers, not interpreted
  (no symbolization, callchain expansion, register decoding or time
  conversion).
- **Little-endian only.** A big-endian magic is recognized and rejected
  with a dedicated error; 32-bit producer files are layout-identical (all
  header fields are u64) and parse normally.
- **Narrowed record coverage.** TEXT_POKE, CGROUP and AUX_OUTPUT_HW_ID are
  indexed and named but their payloads are only exposed as raw spans;
  grouped READ/read_format output is rejected.
- **Build-id width is caller-supplied.** The 20/24/32-byte id field is not
  self-describing; the older documented `pid + build_id + filename` shape
  is implemented (modern perf's extra u8 size field is not).
- **Feature descriptors are read in increasing bit order** directly after
  the data section, as perf's shipped format documentation describes.
- **cpu_topology revision 2** (cores/threads lists + core_id/socket_id
  entries); the later die revision is ignored.
- 64-bit fields are raw two's complement: bit 63 set decodes as a negative
  `Int`, and negative offsets/sizes/counts are rejected with their byte
  offset in the error text.
- `PerfFile` is a plain value type; not thread-safe.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
