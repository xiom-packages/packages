// XIOM -- xiom.perf: Linux perf.data structure parser (read-only)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Scope: a read-only STRUCTURE parser for the on-disk `perf.data` file
// produced by the Linux `perf` tool (magic "PERFILE2"). Callers pass the
// whole file as a byte vector; every parsed value is an offset/size pair (a
// span) into that buffer. Nothing is written, no samples are interpreted
// semantically, and no PMU or kernel state is touched.
//
// Implemented layers, all little-endian (LE is the primary and only
// supported byte order; a big-endian magic is recognized and rejected):
//   * file header (104 bytes): magic "PERFILE2", size u64, attr_size u64,
//     the attrs / data / event_types perf_file_section descriptors (offset
//     u64, size u64 each) and a 256-bit feature bitmap (4 u64 words,
//     feature bit F = word F/64, bit F%64).
//   * feature section descriptors: for every set feature bit (1..31, the
//     kernel HEADER_* enum order) a perf_file_section follows the data
//     section; it points at that feature's payload elsewhere in the file.
//   * attrs section: attr_size-byte records, each holding a
//     perf_event_attr (its own size field in 64..attr_size-16) followed by
//     the {offset, size} descriptor of its u64 id array.
//   * perf_event_attr fields: type, size, config, sample_period/sample_freq,
//     sample_type, read_format, the 38 flag bits, wakeup_events/watermark,
//     bp_type, config1, config2, branch_sample_type, sample_regs_user,
//     sample_stack_user, clockid, sample_regs_intr, aux_watermark. Fields
//     past the record's own size read as 0 (the kernel zero-pads).
//   * data section: a stream of perf_event_header records (type u32, misc
//     u16, size u16; size includes the 8-byte header). Every record is
//     header-validated at parse time (size >= 8, whole record inside the
//     data section) and indexed by absolute offset/size.
//   * typed payload decoders for MMAP, LOST, COMM, EXIT, THROTTLE,
//     UNTHROTTLE, FORK, READ, SAMPLE, MMAP2, AUX, ITRACE_START,
//     LOST_SAMPLES, SWITCH, SWITCH_CPU_WIDE, NAMESPACES, KSYMBOL, BPF_EVENT,
//     ID_INDEX and the header BUILD_ID record, plus record type names for
//     the whole PERF_RECORD_* range.
//   * SAMPLE reconstruction driven by the selected attr's sample_type:
//     IDENTIFIER, IP, TID, TIME, ADDR, ID, STREAM_ID, CPU, PERIOD and the
//     first READ value; intervening CALLCHAIN, RAW, BRANCH_STACK, REGS_USER,
//     STACK_USER, WEIGHT, DATA_SRC, TRANSACTION, REGS_INTR, PHYS_ADDR, AUX,
//     CGROUP and page size fields are skipped using their documented
//     variable sizes.
//   * sample_id tails on non-SAMPLE records when attr.sample_id_all is set:
//     TID, TIME, ID, STREAM_ID, CPU and IDENTIFIER appended after the
//     payload in that fixed order (the tail is read from the end of the
//     record, so no per-record payload knowledge is required).
//   * feature payload decoders: build_id (count + records), the
//     perf_header_string features (hostname, osrelease, version, arch), the
//     cmdline string list, cpu_topology (sibling cores/threads string lists
//     plus per-cpu core_id/socket_id entries) and raw payload copies for
//     every other present feature.
//
// Documented corrections to the port brief (see SPEC.md):
//   * the feature bitmap uses the kernel HEADER_* enum bit positions
//     (BUILD_ID 2, HOSTNAME 3, OSRELEASE 4, VERSION 5, ARCH 6, NRCPUS 7,
//     CPUDESC 8, CPUID 9, TOTAL_MEM 10, CMDLINE 11, EVENT_DESC 12,
//     CPU_TOPOLOGY 13, NUMA_TOPOLOGY 14, ...) rather than the brief's
//     shorthand bit values 1/2/4/8/16/32/64.
//   * read_format bits are the kernel values: TOTAL_TIME_ENABLED 1,
//     TOTAL_TIME_RUNNING 2, ID 4, GROUP 8, LOST 16.
//   * PERF_RECORD_AUX_OUTPUT_HW_ID is 21 (not 22); ID_INDEX is 69 and the
//     header BUILD_ID record is 67 in the 64+ perf user range (not 23/24).
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no Vec[StructType];
//     attrs and records are flat parallel Vec fields.
//   * Ok/Err construction is confined to the tiny leaf helpers below.
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before entering Int arithmetic.
//   * Vec[Int] element reads are bound to typed locals.
//   * 64-bit fields use the xiom.pack overflow-safe shape: the low seven
//     bytes accumulate with a `place` factor and the top byte is applied
//     separately, so the raw 64-bit pattern is exact (bit 63 set decodes as
//     a negative Int). Every offset/size/count that decodes negative is
//     rejected with its byte offset in the error text.
//   * flag tests use arithmetic bit extraction, never `&`, because bitwise
//     operations on values with bit 31 set are miscompiled in v0.61.3.
//   * errors carry byte offsets as decimal text (xiom.convert.int).
// See SPEC.md for the byte layout tables, validation order, error catalog
// and test plan.

module xiom.perf

use xiom.convert.int;

// --------------------------------------------------
//  Public constants: file header
// --------------------------------------------------

// "PERFILE2" as stored little-endian, byte 0 = 'P'.
pub const PERF_MAGIC0: Int = 80;
pub const PERF_MAGIC1: Int = 69;
pub const PERF_MAGIC2: Int = 82;
pub const PERF_MAGIC3: Int = 70;
pub const PERF_MAGIC4: Int = 73;
pub const PERF_MAGIC5: Int = 76;
pub const PERF_MAGIC6: Int = 69;
pub const PERF_MAGIC7: Int = 50;

// The same value's bytes as they appear in a big-endian file: "2ELIFREP".
pub const PERF_MAGIC_BE0: Int = 50;
pub const PERF_MAGIC_BE1: Int = 69;
pub const PERF_MAGIC_BE2: Int = 76;
pub const PERF_MAGIC_BE3: Int = 73;
pub const PERF_MAGIC_BE4: Int = 70;
pub const PERF_MAGIC_BE5: Int = 82;
pub const PERF_MAGIC_BE6: Int = 69;
pub const PERF_MAGIC_BE7: Int = 80;

// Fixed header geometry: 8 magic + 3 u64 + 3 sections (16 each) + 32 flags.
pub const PERF_HEADER_MAGIC_SIZE: Int = 8;
pub const PERF_HEADER_FLAGS_OFFSET: Int = 72;
pub const PERF_HEADER_MIN_SIZE: Int = 104;
pub const PERF_FEATURE_WORDS: Int = 4;
pub const PERF_FEATURE_BITS: Int = 256;

// perf_event_attr size revisions (PERF_ATTR_SIZE_VER*).
pub const PERF_ATTR_SIZE_VER0: Int = 64;
pub const PERF_ATTR_SIZE_VER1: Int = 72;
pub const PERF_ATTR_SIZE_VER2: Int = 80;
pub const PERF_ATTR_SIZE_VER3: Int = 96;
pub const PERF_ATTR_SIZE_VER4: Int = 104;
pub const PERF_ATTR_SIZE_VER5: Int = 112;
pub const PERF_ATTR_SIZE_VER6: Int = 120;
pub const PERF_ATTR_SIZE_VER7: Int = 128;
pub const PERF_ATTR_SIZE_VER8: Int = 136;
pub const PERF_FILE_ATTR_IDS_SIZE: Int = 16;
pub const PERF_ATTR_SIZE_MAX: Int = 65536;

// perf_file_section selector values for perf_section_field.
pub const PERF_SECTION_ATTRS_OFFSET: Int = 0;
pub const PERF_SECTION_ATTRS_SIZE: Int = 1;
pub const PERF_SECTION_DATA_OFFSET: Int = 2;
pub const PERF_SECTION_DATA_SIZE: Int = 3;
pub const PERF_SECTION_EVENT_TYPES_OFFSET: Int = 4;
pub const PERF_SECTION_EVENT_TYPES_SIZE: Int = 5;
pub const PERF_SECTION_FIELD_COUNT: Int = 6;

// perf_variant results.
pub const PERF_VARIANT_LE: Int = 0;
pub const PERF_VARIANT_BE: Int = 1;
pub const PERF_VARIANT_UNKNOWN: Int = 2;

// --------------------------------------------------
//  Public constants: feature bits (kernel HEADER_* enum)
// --------------------------------------------------

pub const PERF_FEATURE_RESERVED: Int = 0;
pub const PERF_FEATURE_TRACING_DATA: Int = 1;
pub const PERF_FEATURE_BUILD_ID: Int = 2;
pub const PERF_FEATURE_HOSTNAME: Int = 3;
pub const PERF_FEATURE_OSRELEASE: Int = 4;
pub const PERF_FEATURE_VERSION: Int = 5;
pub const PERF_FEATURE_ARCH: Int = 6;
pub const PERF_FEATURE_NRCPUS: Int = 7;
pub const PERF_FEATURE_CPUDESC: Int = 8;
pub const PERF_FEATURE_CPUID: Int = 9;
pub const PERF_FEATURE_TOTAL_MEM: Int = 10;
pub const PERF_FEATURE_CMDLINE: Int = 11;
pub const PERF_FEATURE_EVENT_DESC: Int = 12;
pub const PERF_FEATURE_CPU_TOPOLOGY: Int = 13;
pub const PERF_FEATURE_NUMA_TOPOLOGY: Int = 14;
pub const PERF_FEATURE_BRANCH_STACK: Int = 15;
pub const PERF_FEATURE_PMU_MAPPINGS: Int = 16;
pub const PERF_FEATURE_GROUP_DESC: Int = 17;
pub const PERF_FEATURE_AUXTRACE: Int = 18;
pub const PERF_FEATURE_STAT: Int = 19;
pub const PERF_FEATURE_CACHE: Int = 20;
pub const PERF_FEATURE_SAMPLE_TIME: Int = 21;
pub const PERF_FEATURE_MEM_TOPOLOGY: Int = 22;
pub const PERF_FEATURE_CLOCKID: Int = 23;
pub const PERF_FEATURE_DIR_FORMAT: Int = 24;
pub const PERF_FEATURE_BPF_PROG_INFO: Int = 25;
pub const PERF_FEATURE_BPF_BTF: Int = 26;
pub const PERF_FEATURE_COMPRESSED: Int = 27;
pub const PERF_FEATURE_CPU_PMU_CAPS: Int = 28;
pub const PERF_FEATURE_CLOCK_DATA: Int = 29;
pub const PERF_FEATURE_HYBRID_TOPOLOGY: Int = 30;
pub const PERF_FEATURE_PMU_CAPS: Int = 31;
pub const PERF_FEATURE_LAST: Int = 32;

// perf_feature_section_field selector values.
pub const PERF_FEATURE_FIELD_OFFSET: Int = 0;
pub const PERF_FEATURE_FIELD_SIZE: Int = 1;
pub const PERF_FEATURE_FIELD_COUNT: Int = 2;

// perf_feature_string_field selector values (single perf_header_string).
pub const PERF_STRING_FIELD_LEN: Int = 0;
pub const PERF_STRING_FIELD_TEXT_OFFSET: Int = 1;
pub const PERF_STRING_FIELD_TEXT_SIZE: Int = 2;
pub const PERF_STRING_FIELD_COUNT: Int = 3;

// perf_feature_topo_count / perf_feature_topo_string_field list selectors.
pub const PERF_TOPO_LIST_CORES: Int = 0;
pub const PERF_TOPO_LIST_THREADS: Int = 1;
pub const PERF_TOPO_LIST_COUNT: Int = 2;

// perf_feature_cpu_entry_field selector values.
pub const PERF_CPU_ENTRY_FIELD_CORE_ID: Int = 0;
pub const PERF_CPU_ENTRY_FIELD_SOCKET_ID: Int = 1;
pub const PERF_CPU_ENTRY_FIELD_COUNT: Int = 2;

// perf_feature_build_id_field selector values.
pub const PERF_FBI_FIELD_PID: Int = 0;
pub const PERF_FBI_FIELD_RECORD_OFFSET: Int = 1;
pub const PERF_FBI_FIELD_BUILD_ID_OFFSET: Int = 2;
pub const PERF_FBI_FIELD_BUILD_ID_SIZE: Int = 3;
pub const PERF_FBI_FIELD_COUNT: Int = 4;

// Build-id width limits accepted by the build-id decoders.
pub const PERF_BUILD_ID_MIN: Int = 1;
pub const PERF_BUILD_ID_MAX: Int = 64;

// --------------------------------------------------
//  Public constants: perf_event_attr
// --------------------------------------------------

// perf_attr_field selector values.
pub const PERF_ATTR_FIELD_TYPE: Int = 0;
pub const PERF_ATTR_FIELD_SIZE: Int = 1;
pub const PERF_ATTR_FIELD_CONFIG: Int = 2;
pub const PERF_ATTR_FIELD_SAMPLE_PERIOD: Int = 3;
pub const PERF_ATTR_FIELD_SAMPLE_TYPE: Int = 4;
pub const PERF_ATTR_FIELD_READ_FORMAT: Int = 5;
pub const PERF_ATTR_FIELD_FLAGS: Int = 6;
pub const PERF_ATTR_FIELD_WAKEUP_EVENTS: Int = 7;
pub const PERF_ATTR_FIELD_BP_TYPE: Int = 8;
pub const PERF_ATTR_FIELD_CONFIG1: Int = 9;
pub const PERF_ATTR_FIELD_CONFIG2: Int = 10;
pub const PERF_ATTR_FIELD_BRANCH_SAMPLE_TYPE: Int = 11;
pub const PERF_ATTR_FIELD_SAMPLE_REGS_USER: Int = 12;
pub const PERF_ATTR_FIELD_SAMPLE_STACK_USER: Int = 13;
pub const PERF_ATTR_FIELD_CLOCKID: Int = 14;
pub const PERF_ATTR_FIELD_SAMPLE_REGS_INTR: Int = 15;
pub const PERF_ATTR_FIELD_AUX_WATERMARK: Int = 16;
pub const PERF_ATTR_FIELD_COUNT: Int = 17;

// attr flags bit indexes (the u64 flag word at attr offset 40).
pub const PERF_ATTR_FLAG_DISABLED: Int = 0;
pub const PERF_ATTR_FLAG_INHERIT: Int = 1;
pub const PERF_ATTR_FLAG_PINNED: Int = 2;
pub const PERF_ATTR_FLAG_EXCLUSIVE: Int = 3;
pub const PERF_ATTR_FLAG_EXCLUDE_USER: Int = 4;
pub const PERF_ATTR_FLAG_EXCLUDE_KERNEL: Int = 5;
pub const PERF_ATTR_FLAG_EXCLUDE_HV: Int = 6;
pub const PERF_ATTR_FLAG_EXCLUDE_IDLE: Int = 7;
pub const PERF_ATTR_FLAG_MMAP: Int = 8;
pub const PERF_ATTR_FLAG_COMM: Int = 9;
pub const PERF_ATTR_FLAG_FREQ: Int = 10;
pub const PERF_ATTR_FLAG_INHERIT_STAT: Int = 11;
pub const PERF_ATTR_FLAG_ENABLE_ON_EXEC: Int = 12;
pub const PERF_ATTR_FLAG_TASK: Int = 13;
pub const PERF_ATTR_FLAG_WATERMARK: Int = 14;
pub const PERF_ATTR_FLAG_PRECISE_IP: Int = 15;
pub const PERF_ATTR_FLAG_MMAP_DATA: Int = 17;
pub const PERF_ATTR_FLAG_SAMPLE_ID_ALL: Int = 18;
pub const PERF_ATTR_FLAG_EXCLUDE_HOST: Int = 19;
pub const PERF_ATTR_FLAG_EXCLUDE_GUEST: Int = 20;
pub const PERF_ATTR_FLAG_EXCLUDE_CALLCHAIN_KERNEL: Int = 21;
pub const PERF_ATTR_FLAG_EXCLUDE_CALLCHAIN_USER: Int = 22;
pub const PERF_ATTR_FLAG_MMAP2: Int = 23;
pub const PERF_ATTR_FLAG_COMM_EXEC: Int = 24;
pub const PERF_ATTR_FLAG_USE_CLOCKID: Int = 25;
pub const PERF_ATTR_FLAG_CONTEXT_SWITCH: Int = 26;
pub const PERF_ATTR_FLAG_WRITE_BACKWARD: Int = 27;
pub const PERF_ATTR_FLAG_NAMESPACES: Int = 28;
pub const PERF_ATTR_FLAG_KSYMBOL: Int = 29;
pub const PERF_ATTR_FLAG_BPF_EVENT: Int = 30;
pub const PERF_ATTR_FLAG_AUX_OUTPUT: Int = 31;
pub const PERF_ATTR_FLAG_CGROUP: Int = 32;
pub const PERF_ATTR_FLAG_TEXT_POKE: Int = 33;
pub const PERF_ATTR_FLAG_BUILD_ID: Int = 34;
pub const PERF_ATTR_FLAG_INHERIT_THREAD: Int = 35;
pub const PERF_ATTR_FLAG_REMOVE_ON_EXEC: Int = 36;
pub const PERF_ATTR_FLAG_SIGTRAP: Int = 37;
pub const PERF_ATTR_FLAG_COUNT: Int = 38;

// attr event types (subset).
pub const PERF_TYPE_HARDWARE: Int = 0;
pub const PERF_TYPE_SOFTWARE: Int = 1;
pub const PERF_TYPE_TRACEPOINT: Int = 2;
pub const PERF_TYPE_HW_CACHE: Int = 3;
pub const PERF_TYPE_RAW: Int = 4;
pub const PERF_TYPE_BREAKPOINT: Int = 5;

// --------------------------------------------------
//  Parsed file index
// --------------------------------------------------

/// Parsed perf.data header, feature sections, attrs and record index.
///
/// Scalar fields mirror the fixed 104-byte header. `feature_words` holds
/// the four raw u64 words of the 256-bit feature bitmap (bit F is word
/// F/64, bit F%64). `feat_bits`/`feat_offsets`/`feat_sizes` describe the
/// present features in increasing bit order: feat_bits[i] is a
/// PERF_FEATURE_* bit, feat_offsets[i]/feat_sizes[i] the perf_file_section
/// of its payload. Attr and record tables are flat and parallel: attr i is
/// attr_types[i], attr_sizes[i], ..., attr_aux_watermarks[i],
/// attr_id_offsets[i], attr_id_sizes[i]; record i is rec_types[i],
/// rec_miscs[i], rec_offsets[i] (absolute offset of the 8-byte header),
/// rec_sizes[i] (header included). The vectors never drift.
pub type PerfFile = {
  header_size: Int;
  attr_size: Int;
  attrs_offset: Int;
  attrs_size: Int;
  data_offset: Int;
  data_size: Int;
  event_types_offset: Int;
  event_types_size: Int;
  feature_words: Vec[Int];
  feat_bits: Vec[Int];
  feat_offsets: Vec[Int];
  feat_sizes: Vec[Int];
  attr_types: Vec[Int];
  attr_sizes: Vec[Int];
  attr_configs: Vec[Int];
  attr_sample_periods: Vec[Int];
  attr_sample_types: Vec[Int];
  attr_read_formats: Vec[Int];
  attr_flags: Vec[Int];
  attr_wakeup_events: Vec[Int];
  attr_bp_types: Vec[Int];
  attr_config1s: Vec[Int];
  attr_config2s: Vec[Int];
  attr_branch_sample_types: Vec[Int];
  attr_sample_regs_users: Vec[Int];
  attr_sample_stack_users: Vec[Int];
  attr_clockids: Vec[Int];
  attr_sample_regs_intrs: Vec[Int];
  attr_aux_watermarks: Vec[Int];
  attr_id_offsets: Vec[Int];
  attr_id_sizes: Vec[Int];
  rec_types: Vec[Int];
  rec_miscs: Vec[Int];
  rec_offsets: Vec[Int];
  rec_sizes: Vec[Int];
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[PerfFile, Str].
fn _ok_file(v: PerfFile) -> Result[PerfFile, Str] {
  return Ok(v);
}

// Err(m) for Result[PerfFile, Str].
fn _err_file(m: Str) -> Result[PerfFile, Str] {
  return Err(m);
}

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[Int], Str].
fn _ok_ints(v: Vec[Int]) -> Result[Vec[Int], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Int], Str].
fn _err_ints(m: Str) -> Result[Vec[Int], Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// --------------------------------------------------
//  Public constants: sample_type and read_format
// --------------------------------------------------

pub const PERF_SAMPLE_IP: Int = 1;
pub const PERF_SAMPLE_TID: Int = 2;
pub const PERF_SAMPLE_TIME: Int = 4;
pub const PERF_SAMPLE_ADDR: Int = 8;
pub const PERF_SAMPLE_ID: Int = 16;
pub const PERF_SAMPLE_STREAM_ID: Int = 32;
pub const PERF_SAMPLE_CPU: Int = 64;
pub const PERF_SAMPLE_PERIOD: Int = 128;
pub const PERF_SAMPLE_READ: Int = 256;
pub const PERF_SAMPLE_CALLCHAIN: Int = 512;
pub const PERF_SAMPLE_RAW: Int = 1024;
pub const PERF_SAMPLE_BRANCH_STACK: Int = 2048;
pub const PERF_SAMPLE_REGS_USER: Int = 4096;
pub const PERF_SAMPLE_STACK_USER: Int = 8192;
pub const PERF_SAMPLE_WEIGHT: Int = 16384;
pub const PERF_SAMPLE_DATA_SRC: Int = 32768;
pub const PERF_SAMPLE_IDENTIFIER: Int = 65536;
pub const PERF_SAMPLE_TRANSACTION: Int = 131072;
pub const PERF_SAMPLE_REGS_INTR: Int = 262144;
pub const PERF_SAMPLE_PHYS_ADDR: Int = 524288;
pub const PERF_SAMPLE_AUX: Int = 1048576;
pub const PERF_SAMPLE_CGROUP: Int = 2097152;
pub const PERF_SAMPLE_DATA_PAGE_SIZE: Int = 4194304;
pub const PERF_SAMPLE_CODE_PAGE_SIZE: Int = 8388608;
pub const PERF_SAMPLE_WEIGHT_STRUCT: Int = 16777216;

// sample_type bit indexes (log2 of the values above).
const PERF_SAMPLE_BIT_IP: Int = 0;
const PERF_SAMPLE_BIT_TID: Int = 1;
const PERF_SAMPLE_BIT_TIME: Int = 2;
const PERF_SAMPLE_BIT_ADDR: Int = 3;
const PERF_SAMPLE_BIT_ID: Int = 4;
const PERF_SAMPLE_BIT_STREAM_ID: Int = 5;
const PERF_SAMPLE_BIT_CPU: Int = 6;
const PERF_SAMPLE_BIT_PERIOD: Int = 7;
const PERF_SAMPLE_BIT_READ: Int = 8;
const PERF_SAMPLE_BIT_CALLCHAIN: Int = 9;
const PERF_SAMPLE_BIT_RAW: Int = 10;
const PERF_SAMPLE_BIT_BRANCH_STACK: Int = 11;
const PERF_SAMPLE_BIT_REGS_USER: Int = 12;
const PERF_SAMPLE_BIT_STACK_USER: Int = 13;
const PERF_SAMPLE_BIT_WEIGHT: Int = 14;
const PERF_SAMPLE_BIT_DATA_SRC: Int = 15;
const PERF_SAMPLE_BIT_IDENTIFIER: Int = 16;
const PERF_SAMPLE_BIT_TRANSACTION: Int = 17;
const PERF_SAMPLE_BIT_REGS_INTR: Int = 18;
const PERF_SAMPLE_BIT_PHYS_ADDR: Int = 19;
const PERF_SAMPLE_BIT_AUX: Int = 20;
const PERF_SAMPLE_BIT_CGROUP: Int = 21;
const PERF_SAMPLE_BIT_DATA_PAGE_SIZE: Int = 22;
const PERF_SAMPLE_BIT_CODE_PAGE_SIZE: Int = 23;
const PERF_SAMPLE_BIT_WEIGHT_STRUCT: Int = 24;

// read_format bit values.
pub const PERF_FORMAT_TOTAL_TIME_ENABLED: Int = 1;
pub const PERF_FORMAT_TOTAL_TIME_RUNNING: Int = 2;
pub const PERF_FORMAT_ID: Int = 4;
pub const PERF_FORMAT_GROUP: Int = 8;
pub const PERF_FORMAT_LOST: Int = 16;

// perf_sample_field selector values.
pub const PERF_SAMPLE_FIELD_IDENTIFIER: Int = 0;
pub const PERF_SAMPLE_FIELD_IP: Int = 1;
pub const PERF_SAMPLE_FIELD_PID: Int = 2;
pub const PERF_SAMPLE_FIELD_TID: Int = 3;
pub const PERF_SAMPLE_FIELD_TIME: Int = 4;
pub const PERF_SAMPLE_FIELD_ADDR: Int = 5;
pub const PERF_SAMPLE_FIELD_ID: Int = 6;
pub const PERF_SAMPLE_FIELD_STREAM_ID: Int = 7;
pub const PERF_SAMPLE_FIELD_CPU: Int = 8;
pub const PERF_SAMPLE_FIELD_PERIOD: Int = 9;
pub const PERF_SAMPLE_FIELD_READ_VALUE: Int = 10;
pub const PERF_SAMPLE_FIELD_COUNT: Int = 11;

// --------------------------------------------------
//  Public constants: records and misc flags
// --------------------------------------------------

pub const PERF_RECORD_MMAP: Int = 1;
pub const PERF_RECORD_LOST: Int = 2;
pub const PERF_RECORD_COMM: Int = 3;
pub const PERF_RECORD_EXIT: Int = 4;
pub const PERF_RECORD_THROTTLE: Int = 5;
pub const PERF_RECORD_UNTHROTTLE: Int = 6;
pub const PERF_RECORD_FORK: Int = 7;
pub const PERF_RECORD_READ: Int = 8;
pub const PERF_RECORD_SAMPLE: Int = 9;
pub const PERF_RECORD_MMAP2: Int = 10;
pub const PERF_RECORD_AUX: Int = 11;
pub const PERF_RECORD_ITRACE_START: Int = 12;
pub const PERF_RECORD_LOST_SAMPLES: Int = 13;
pub const PERF_RECORD_SWITCH: Int = 14;
pub const PERF_RECORD_SWITCH_CPU_WIDE: Int = 15;
pub const PERF_RECORD_NAMESPACES: Int = 16;
pub const PERF_RECORD_KSYMBOL: Int = 17;
pub const PERF_RECORD_BPF_EVENT: Int = 18;
pub const PERF_RECORD_CGROUP: Int = 19;
pub const PERF_RECORD_TEXT_POKE: Int = 20;
pub const PERF_RECORD_AUX_OUTPUT_HW_ID: Int = 21;
pub const PERF_RECORD_USER_TYPE_START: Int = 64;
pub const PERF_RECORD_HEADER_ATTR: Int = 64;
pub const PERF_RECORD_HEADER_EVENT_TYPE: Int = 65;
pub const PERF_RECORD_HEADER_TRACING_DATA: Int = 66;
pub const PERF_RECORD_HEADER_BUILD_ID: Int = 67;
pub const PERF_RECORD_FINISHED_ROUND: Int = 68;
pub const PERF_RECORD_ID_INDEX: Int = 69;
pub const PERF_RECORD_AUXTRACE_INFO: Int = 70;
pub const PERF_RECORD_AUXTRACE: Int = 71;
pub const PERF_RECORD_AUXTRACE_ERROR: Int = 72;
pub const PERF_RECORD_THREAD_MAP: Int = 73;
pub const PERF_RECORD_CPU_MAP: Int = 74;
pub const PERF_RECORD_STAT_CONFIG: Int = 75;
pub const PERF_RECORD_STAT: Int = 76;
pub const PERF_RECORD_STAT_ROUND: Int = 77;
pub const PERF_RECORD_EVENT_UPDATE: Int = 78;
pub const PERF_RECORD_TIME_CONV: Int = 79;
pub const PERF_RECORD_HEADER_FEATURE: Int = 80;
pub const PERF_RECORD_COMPRESSED: Int = 81;
pub const PERF_RECORD_FINISHED_INIT: Int = 82;
pub const PERF_RECORD_COMPRESSED2: Int = 83;

pub const PERF_RECORD_HEADER_SIZE: Int = 8;

// perf_record_field selector values.
pub const PERF_REC_FIELD_TYPE: Int = 0;
pub const PERF_REC_FIELD_MISC: Int = 1;
pub const PERF_REC_FIELD_OFFSET: Int = 2;
pub const PERF_REC_FIELD_SIZE: Int = 3;
pub const PERF_REC_FIELD_PAYLOAD_OFFSET: Int = 4;
pub const PERF_REC_FIELD_PAYLOAD_SIZE: Int = 5;
pub const PERF_REC_FIELD_COUNT: Int = 6;

// perf_event_header.misc bits.
pub const PERF_RECORD_MISC_CPUMODE_MASK: Int = 7;
pub const PERF_RECORD_MISC_CPUMODE_UNKNOWN: Int = 0;
pub const PERF_RECORD_MISC_KERNEL: Int = 1;
pub const PERF_RECORD_MISC_USER: Int = 2;
pub const PERF_RECORD_MISC_HYPERVISOR: Int = 3;
pub const PERF_RECORD_MISC_GUEST_KERNEL: Int = 4;
pub const PERF_RECORD_MISC_GUEST_USER: Int = 5;
pub const PERF_RECORD_MISC_MMAP_DATA: Int = 4096;
pub const PERF_RECORD_MISC_COMM_EXEC: Int = 4096;
pub const PERF_RECORD_MISC_FORK_EXEC: Int = 4096;
pub const PERF_RECORD_MISC_SWITCH_OUT: Int = 8192;
pub const PERF_RECORD_MISC_SWITCH_OUT_PREEMPT: Int = 16384;
pub const PERF_RECORD_MISC_EXACT_IP: Int = 16384;
pub const PERF_RECORD_MISC_EXT_RESERVED: Int = 32768;

// MMAP payload fields.
pub const PERF_MMAP_FIELD_PID: Int = 0;
pub const PERF_MMAP_FIELD_TID: Int = 1;
pub const PERF_MMAP_FIELD_ADDR: Int = 2;
pub const PERF_MMAP_FIELD_LEN: Int = 3;
pub const PERF_MMAP_FIELD_PGOFF: Int = 4;
pub const PERF_MMAP_FIELD_FILENAME_OFFSET: Int = 5;
pub const PERF_MMAP_FIELD_FILENAME_SIZE: Int = 6;
pub const PERF_MMAP_FIELD_COUNT: Int = 7;

// MMAP2 payload fields.
pub const PERF_MMAP2_FIELD_PID: Int = 0;
pub const PERF_MMAP2_FIELD_TID: Int = 1;
pub const PERF_MMAP2_FIELD_ADDR: Int = 2;
pub const PERF_MMAP2_FIELD_LEN: Int = 3;
pub const PERF_MMAP2_FIELD_PGOFF: Int = 4;
pub const PERF_MMAP2_FIELD_MAJ: Int = 5;
pub const PERF_MMAP2_FIELD_MIN: Int = 6;
pub const PERF_MMAP2_FIELD_INO: Int = 7;
pub const PERF_MMAP2_FIELD_INO_GENERATION: Int = 8;
pub const PERF_MMAP2_FIELD_PROT: Int = 9;
pub const PERF_MMAP2_FIELD_FLAGS: Int = 10;
pub const PERF_MMAP2_FIELD_FILENAME_OFFSET: Int = 11;
pub const PERF_MMAP2_FIELD_FILENAME_SIZE: Int = 12;
pub const PERF_MMAP2_FIELD_COUNT: Int = 13;

// COMM payload fields.
pub const PERF_COMM_FIELD_PID: Int = 0;
pub const PERF_COMM_FIELD_TID: Int = 1;
pub const PERF_COMM_FIELD_COMM_OFFSET: Int = 2;
pub const PERF_COMM_FIELD_COMM_SIZE: Int = 3;
pub const PERF_COMM_FIELD_COUNT: Int = 4;

// FORK/EXIT payload fields.
pub const PERF_TASK_FIELD_PID: Int = 0;
pub const PERF_TASK_FIELD_PPID: Int = 1;
pub const PERF_TASK_FIELD_TID: Int = 2;
pub const PERF_TASK_FIELD_PTID: Int = 3;
pub const PERF_TASK_FIELD_TIME: Int = 4;
pub const PERF_TASK_FIELD_COUNT: Int = 5;

// LOST payload fields.
pub const PERF_LOST_FIELD_ID: Int = 0;
pub const PERF_LOST_FIELD_LOST: Int = 1;
pub const PERF_LOST_FIELD_COUNT: Int = 2;

// READ payload fields.
pub const PERF_READ_FIELD_PID: Int = 0;
pub const PERF_READ_FIELD_TID: Int = 1;
pub const PERF_READ_FIELD_VALUE: Int = 2;
pub const PERF_READ_FIELD_TIME_ENABLED: Int = 3;
pub const PERF_READ_FIELD_TIME_RUNNING: Int = 4;
pub const PERF_READ_FIELD_ID: Int = 5;
pub const PERF_READ_FIELD_COUNT: Int = 6;

// THROTTLE/UNTHROTTLE payload fields.
pub const PERF_THROTTLE_FIELD_TIME: Int = 0;
pub const PERF_THROTTLE_FIELD_ID: Int = 1;
pub const PERF_THROTTLE_FIELD_STREAM_ID: Int = 2;
pub const PERF_THROTTLE_FIELD_COUNT: Int = 3;

// SWITCH/SWITCH_CPU_WIDE payload fields.
pub const PERF_SWITCH_FIELD_NEXT_PREV_PID: Int = 0;
pub const PERF_SWITCH_FIELD_NEXT_PREV_TID: Int = 1;
pub const PERF_SWITCH_FIELD_COUNT: Int = 2;

// AUX payload fields.
pub const PERF_AUX_FIELD_AUX_OFFSET: Int = 0;
pub const PERF_AUX_FIELD_AUX_SIZE: Int = 1;
pub const PERF_AUX_FIELD_FLAGS: Int = 2;
pub const PERF_AUX_FIELD_COUNT: Int = 3;

// ITRACE_START payload fields.
pub const PERF_ITRACE_FIELD_PID: Int = 0;
pub const PERF_ITRACE_FIELD_TID: Int = 1;
pub const PERF_ITRACE_FIELD_COUNT: Int = 2;

// LOST_SAMPLES payload fields.
pub const PERF_LOST_SAMPLES_FIELD_LOST: Int = 0;
pub const PERF_LOST_SAMPLES_FIELD_COUNT: Int = 1;

// NAMESPACES payload fields.
pub const PERF_NS_FIELD_PID: Int = 0;
pub const PERF_NS_FIELD_TID: Int = 1;
pub const PERF_NS_FIELD_NR_NAMESPACES: Int = 2;
pub const PERF_NS_FIELD_ENTRY_DEV: Int = 3;
pub const PERF_NS_FIELD_ENTRY_INO: Int = 4;
pub const PERF_NS_FIELD_COUNT: Int = 5;

// KSYMBOL payload fields.
pub const PERF_KSYMBOL_FIELD_ADDR: Int = 0;
pub const PERF_KSYMBOL_FIELD_LEN: Int = 1;
pub const PERF_KSYMBOL_FIELD_KSYM_TYPE: Int = 2;
pub const PERF_KSYMBOL_FIELD_FLAGS: Int = 3;
pub const PERF_KSYMBOL_FIELD_NAME_OFFSET: Int = 4;
pub const PERF_KSYMBOL_FIELD_NAME_SIZE: Int = 5;
pub const PERF_KSYMBOL_FIELD_COUNT: Int = 6;

// BPF_EVENT payload fields.
pub const PERF_BPF_FIELD_TYPE: Int = 0;
pub const PERF_BPF_FIELD_FLAGS: Int = 1;
pub const PERF_BPF_FIELD_ID: Int = 2;
pub const PERF_BPF_FIELD_COUNT: Int = 3;

// ID_INDEX payload fields.
pub const PERF_IDX_ENTRY_FIELD_ID: Int = 0;
pub const PERF_IDX_ENTRY_FIELD_IDX: Int = 1;
pub const PERF_IDX_ENTRY_FIELD_CPU: Int = 2;
pub const PERF_IDX_ENTRY_FIELD_TID: Int = 3;
pub const PERF_IDX_ENTRY_FIELD_COUNT: Int = 4;
pub const PERF_IDX_ENTRY_SIZE: Int = 32;

// BUILD_ID record payload fields.
pub const PERF_BD_FIELD_PID: Int = 0;
pub const PERF_BD_FIELD_BUILD_ID_OFFSET: Int = 1;
pub const PERF_BD_FIELD_BUILD_ID_SIZE: Int = 2;
pub const PERF_BD_FIELD_FILENAME_OFFSET: Int = 3;
pub const PERF_BD_FIELD_FILENAME_SIZE: Int = 4;
pub const PERF_BD_FIELD_COUNT: Int = 5;

// --------------------------------------------------
//  Internal byte and bit helpers
// --------------------------------------------------

// "perf: <msg> at <off>" -- structural errors carry their byte offset.
fn _at(msg: Str, off: Int) -> Str {
  return "perf: " + msg + " at " + int_to_base(off, 10);
}

// Byte at `pos`, widened to 0..255; the caller guarantees the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Raw little-endian field of `size` (1..8) bytes at `off`.
//
// For size 8 the raw two's-complement 64-bit pattern is returned: the low
// seven bytes accumulate with a `place` factor and the top byte is applied
// separately, so no intermediate overflows and bit 63 set decodes as a
// negative Int. The caller guarantees off + size <= data.len().
fn _rdu(data: &Vec[UInt8], off: Int, size: Int) -> Int {
  var nlow = size;
  if size == 8 { nlow = 7; }
  var low: Int = 0;
  var place: Int = 1;
  var i = 0;
  while i < nlow {
    let b = _byte(data, off + i);
    low = low + b * place;
    place = place * 256;
    i = i + 1;
  }
  if size == 8 {
    let top = _byte(data, off + 7);
    if top < 128 {
      return low + top * place;
    }
    let t = top - 128;
    let hi = low + t * place;
    return hi + (0 - 9223372036854775807 - 1);
  }
  return low;
}

// Bit `bit` (0..63) of the raw two's-complement pattern of `v`.
// Arithmetic only: `&` on values with bit 31 set miscompiles in v0.61.3.
// Bits 62 and 63 are handled separately because place * 2 overflows there.
fn _bit_at(v: Int, bit: Int) -> Bool {
  if bit == 63 {
    return v < 0;
  }
  if bit == 62 {
    var t = v;
    if t < 0 {
      t = t - (0 - 9223372036854775807 - 1);
    }
    return (t / 4611686018427387904) % 2 == 1;
  }
  var place: Int = 1;
  var i = 0;
  while i < bit {
    place = place * 2;
    i = i + 1;
  }
  let mod = place * 2;
  var r = v % mod;
  if r < 0 { r = r + mod; }
  if r >= place {
    return true;
  }
  return false;
}

// Population count of the raw 64-bit pattern of `v`.
fn _popcount64(v: Int) -> Int {
  var q = v;
  var n = 0;
  var i = 0;
  while i < 64 {
    var r = q % 2;
    if r < 0 { r = r + 2; }
    if r == 1 { n = n + 1; }
    q = (q - r) / 2;
    i = i + 1;
  }
  return n;
}

// True when [off, off + size) lies inside the buffer. Negative values fail.
fn _span_ok(data: &Vec[UInt8], off: Int, size: Int) -> Bool {
  if off < 0 { return false; }
  if size < 0 { return false; }
  if off > data.len() { return false; }
  if size > data.len() - off { return false; }
  return true;
}

// _span_ok as a Result[Unit, Str] for parse-stage checks.
fn _check_span(data: &Vec[UInt8], off: Int, size: Int) -> Result[Unit, Str] {
  if !_span_ok(data, off, size) {
    return _err_unit("perf: span out of bounds");
  }
  return _ok_unit();
}

// Little-endian field of `size` bytes at `base + off`, or 0 when the attr
// record's own size does not cover that field (the kernel zero-pads).
fn _attr_f(data: &Vec[UInt8], base: Int, asize: Int, off: Int, size: Int) -> Int {
  if asize >= off + size {
    return _rdu(data, base + off, size);
  }
  return 0;
}

// True when `misc` selects `cpumode` (low three bits).
fn _cpumode_is(misc: Int, cpumode: Int) -> Bool {
  var r = misc % 8;
  if r < 0 { r = r + 8; }
  return r == cpumode;
}

// True when the first 8 bytes are the little-endian PERFILE2 magic.
fn _magic_le(data: &Vec[UInt8]) -> Bool {
  if _byte(data, 0) != PERF_MAGIC0 { return false; }
  if _byte(data, 1) != PERF_MAGIC1 { return false; }
  if _byte(data, 2) != PERF_MAGIC2 { return false; }
  if _byte(data, 3) != PERF_MAGIC3 { return false; }
  if _byte(data, 4) != PERF_MAGIC4 { return false; }
  if _byte(data, 5) != PERF_MAGIC5 { return false; }
  if _byte(data, 6) != PERF_MAGIC6 { return false; }
  if _byte(data, 7) != PERF_MAGIC7 { return false; }
  return true;
}

// True when the first 8 bytes are the big-endian byte-swapped magic.
fn _magic_be(data: &Vec[UInt8]) -> Bool {
  if _byte(data, 0) != PERF_MAGIC_BE0 { return false; }
  if _byte(data, 1) != PERF_MAGIC_BE1 { return false; }
  if _byte(data, 2) != PERF_MAGIC_BE2 { return false; }
  if _byte(data, 3) != PERF_MAGIC_BE3 { return false; }
  if _byte(data, 4) != PERF_MAGIC_BE4 { return false; }
  if _byte(data, 5) != PERF_MAGIC_BE5 { return false; }
  if _byte(data, 6) != PERF_MAGIC_BE6 { return false; }
  if _byte(data, 7) != PERF_MAGIC_BE7 { return false; }
  return true;
}

// True when feature bit `feat` is set in the 256-bit bitmap.
fn _feat_present(f: &PerfFile, feat: Int) -> Bool {
  if feat < 0 { return false; }
  if feat >= PERF_FEATURE_BITS { return false; }
  let w: Int = f.feature_words[feat / 64];
  return _bit_at(w, feat % 64);
}

// Present-feature index of `feat`, or -1 when absent.
fn _feat_index(f: &PerfFile, feat: Int) -> Int {
  var i = 0;
  while i < f.feat_bits.len() {
    let b: Int = f.feat_bits[i];
    if b == feat { return i; }
    i = i + 1;
  }
  return -1;
}

// --------------------------------------------------
//  Parse stages
// --------------------------------------------------

// Magic validation. The little-endian PERFILE2 magic is accepted; the
// byte-swapped big-endian form is recognized and rejected explicitly; any
// other byte pattern is a bad magic.
fn _read_magic(data: &Vec[UInt8], f: &mut PerfFile) -> Result[Unit, Str] {
  if data.len() < PERF_HEADER_MAGIC_SIZE {
    return _err_unit("perf: truncated magic");
  }
  if !_magic_le(data) {
    if _magic_be(data) {
      return _err_unit("perf: big-endian perf.data not supported");
    }
    return _err_unit("perf: bad magic");
  }
  return _ok_unit();
}

// Fixed header fields: size, attr_size, the three perf_file_sections and
// the 256-bit feature bitmap. Validates the header size, attr_size, every
// section span and attrs.size % attr_size == 0.
fn _read_header(data: &Vec[UInt8], f: &mut PerfFile) -> Result[Unit, Str] {
  if data.len() < PERF_HEADER_MIN_SIZE {
    return _err_unit("perf: truncated header");
  }
  let hs = _rdu(data, 8, 8);
  if hs < PERF_HEADER_MIN_SIZE {
    return _err_unit(_at("bad header size", 8));
  }
  let asz = _rdu(data, 16, 8);
  if asz < PERF_ATTR_SIZE_VER0 {
    return _err_unit(_at("bad attr size", 16));
  }
  if asz > PERF_ATTR_SIZE_MAX {
    return _err_unit(_at("bad attr size", 16));
  }
  if asz % 8 != 0 {
    return _err_unit(_at("bad attr size", 16));
  }
  let attrs_o = _rdu(data, 24, 8);
  let attrs_sz = _rdu(data, 32, 8);
  let data_o = _rdu(data, 40, 8);
  let data_sz = _rdu(data, 48, 8);
  let et_o = _rdu(data, 56, 8);
  let et_sz = _rdu(data, 64, 8);
  let c1 = _check_span(data, attrs_o, attrs_sz);
  if !c1.is_ok {
    return _err_unit("perf: attrs section out of bounds");
  }
  let c2 = _check_span(data, data_o, data_sz);
  if !c2.is_ok {
    return _err_unit("perf: data section out of bounds");
  }
  let c3 = _check_span(data, et_o, et_sz);
  if !c3.is_ok {
    return _err_unit("perf: event_types section out of bounds");
  }
  if attrs_sz % asz != 0 {
    return _err_unit("perf: attrs section size not a multiple of attr_size");
  }
  f.header_size = hs;
  f.attr_size = asz;
  f.attrs_offset = attrs_o;
  f.attrs_size = attrs_sz;
  f.data_offset = data_o;
  f.data_size = data_sz;
  f.event_types_offset = et_o;
  f.event_types_size = et_sz;
  var w = 0;
  while w < PERF_FEATURE_WORDS {
    f.feature_words.push(_rdu(data, PERF_HEADER_FLAGS_OFFSET + w * 8, 8));
    w = w + 1;
  }
  return _ok_unit();
}

// Attrs section: attrs_size / attr_size records of attr_size bytes each.
// Each record starts with a perf_event_attr whose own size must be at least
// PERF_ATTR_SIZE_VER0 and leave room for the trailing {offset, size} ids
// descriptor (16 bytes). Fields past the attr's own size read as 0.
fn _read_attrs(data: &Vec[UInt8], f: &mut PerfFile) -> Result[Unit, Str] {
  let count = f.attrs_size / f.attr_size;
  var i = 0;
  while i < count {
    let eoff = f.attrs_offset + i * f.attr_size;
    let asize = _rdu(data, eoff + 4, 4);
    if asize < PERF_ATTR_SIZE_VER0 {
      return _err_unit(_at("bad attr record size", eoff));
    }
    if asize + PERF_FILE_ATTR_IDS_SIZE > f.attr_size {
      return _err_unit(_at("bad attr record size", eoff));
    }
    let atype = _rdu(data, eoff, 4);
    let aconfig = _attr_f(data, eoff, asize, 8, 8);
    let aperiod = _attr_f(data, eoff, asize, 16, 8);
    let ast = _attr_f(data, eoff, asize, 24, 8);
    let arf = _attr_f(data, eoff, asize, 32, 8);
    let afl = _attr_f(data, eoff, asize, 40, 8);
    let aw = _attr_f(data, eoff, asize, 48, 4);
    let abp = _attr_f(data, eoff, asize, 52, 4);
    let ac1 = _attr_f(data, eoff, asize, 56, 8);
    let ac2 = _attr_f(data, eoff, asize, 64, 8);
    let abr = _attr_f(data, eoff, asize, 72, 8);
    let aru = _attr_f(data, eoff, asize, 80, 8);
    let asu = _attr_f(data, eoff, asize, 88, 4);
    let acl = _attr_f(data, eoff, asize, 92, 4);
    let ari = _attr_f(data, eoff, asize, 96, 8);
    let aaw = _attr_f(data, eoff, asize, 104, 4);
    let idoff = _rdu(data, eoff + asize, 8);
    let idsz = _rdu(data, eoff + asize + 8, 8);
    let cs = _check_span(data, idoff, idsz);
    if !cs.is_ok {
      return _err_unit(_at("ids section out of bounds", eoff + asize));
    }
    f.attr_types.push(atype);
    f.attr_sizes.push(asize);
    f.attr_configs.push(aconfig);
    f.attr_sample_periods.push(aperiod);
    f.attr_sample_types.push(ast);
    f.attr_read_formats.push(arf);
    f.attr_flags.push(afl);
    f.attr_wakeup_events.push(aw);
    f.attr_bp_types.push(abp);
    f.attr_config1s.push(ac1);
    f.attr_config2s.push(ac2);
    f.attr_branch_sample_types.push(abr);
    f.attr_sample_regs_users.push(aru);
    f.attr_sample_stack_users.push(asu);
    f.attr_clockids.push(acl);
    f.attr_sample_regs_intrs.push(ari);
    f.attr_aux_watermarks.push(aaw);
    f.attr_id_offsets.push(idoff);
    f.attr_id_sizes.push(idsz);
    i = i + 1;
  }
  return _ok_unit();
}

// Data section: a packed stream of perf_event_header records. Every record
// must have size >= 8 (the header itself) and lie entirely inside the data
// section; the walk is exact (it ends at data_offset + data_size).
fn _read_records(data: &Vec[UInt8], f: &mut PerfFile) -> Result[Unit, Str] {
  let end = f.data_offset + f.data_size;
  var pos = f.data_offset;
  while pos < end {
    if end - pos < PERF_RECORD_HEADER_SIZE {
      return _err_unit(_at("truncated record", pos));
    }
    let rtype = _rdu(data, pos, 4);
    let rmisc = _rdu(data, pos + 4, 2);
    let rsize = _rdu(data, pos + 6, 2);
    if rsize < PERF_RECORD_HEADER_SIZE {
      return _err_unit(_at("bad record size", pos));
    }
    if rsize > end - pos {
      return _err_unit(_at("oversized record", pos));
    }
    f.rec_types.push(rtype);
    f.rec_miscs.push(rmisc);
    f.rec_offsets.push(pos);
    f.rec_sizes.push(rsize);
    pos = pos + rsize;
  }
  return _ok_unit();
}

// Feature descriptors: starting right after the data section, one
// perf_file_section per set feature bit in increasing kernel HEADER_* bit
// order (bits 1..31). Each descriptor's {offset, size} must address a span
// inside the buffer (a zero-size payload is allowed).
fn _read_features(data: &Vec[UInt8], f: &mut PerfFile) -> Result[Unit, Str] {
  var pos = f.data_offset + f.data_size;
  var feat = 1;
  while feat < PERF_FEATURE_LAST {
    if _feat_present(f, feat) {
      if pos < 0 || pos > data.len() || data.len() - pos < PERF_FILE_ATTR_IDS_SIZE {
        return _err_unit("perf: feature sections out of bounds");
      }
      let off = _rdu(data, pos, 8);
      let sz = _rdu(data, pos + 8, 8);
      if !_span_ok(data, off, sz) {
        return _err_unit(_at("feature section out of bounds", pos));
      }
      f.feat_bits.push(feat);
      f.feat_offsets.push(off);
      f.feat_sizes.push(sz);
      pos = pos + PERF_FILE_ATTR_IDS_SIZE;
    }
    feat = feat + 1;
  }
  return _ok_unit();
}

// --------------------------------------------------
//  Parse
// --------------------------------------------------

/// Parse a perf.data file header, attrs, record stream and feature sections.
///
/// Validates, in order: magic (little-endian PERFILE2; the byte-swapped
/// big-endian magic is recognized and rejected), header length and size,
/// attr_size, the attrs/data/event_types section spans, the attrs records
/// (each attr's own size and its ids descriptor), every record header in the
/// data section, and the feature section descriptors. On success the
/// returned PerfFile indexes everything; bytes stay in `data`.
/// Err(m) with a "perf: " message on malformed input; no partial file is
/// returned. Complexity: O(data.len() + attrs + records + features).
pub fn perf_parse(data: &Vec[UInt8]) -> Result[PerfFile, Str] {
  var f = PerfFile{
    header_size: 0;
    attr_size: 0;
    attrs_offset: 0;
    attrs_size: 0;
    data_offset: 0;
    data_size: 0;
    event_types_offset: 0;
    event_types_size: 0;
    feature_words: Vec[Int].new();
    feat_bits: Vec[Int].new();
    feat_offsets: Vec[Int].new();
    feat_sizes: Vec[Int].new();
    attr_types: Vec[Int].new();
    attr_sizes: Vec[Int].new();
    attr_configs: Vec[Int].new();
    attr_sample_periods: Vec[Int].new();
    attr_sample_types: Vec[Int].new();
    attr_read_formats: Vec[Int].new();
    attr_flags: Vec[Int].new();
    attr_wakeup_events: Vec[Int].new();
    attr_bp_types: Vec[Int].new();
    attr_config1s: Vec[Int].new();
    attr_config2s: Vec[Int].new();
    attr_branch_sample_types: Vec[Int].new();
    attr_sample_regs_users: Vec[Int].new();
    attr_sample_stack_users: Vec[Int].new();
    attr_clockids: Vec[Int].new();
    attr_sample_regs_intrs: Vec[Int].new();
    attr_aux_watermarks: Vec[Int].new();
    attr_id_offsets: Vec[Int].new();
    attr_id_sizes: Vec[Int].new();
    rec_types: Vec[Int].new();
    rec_miscs: Vec[Int].new();
    rec_offsets: Vec[Int].new();
    rec_sizes: Vec[Int].new();
  };
  let r1 = _read_magic(data, &mut f);
  if !r1.is_ok { return _err_file(r1.error); }
  let r2 = _read_header(data, &mut f);
  if !r2.is_ok { return _err_file(r2.error); }
  let r3 = _read_attrs(data, &mut f);
  if !r3.is_ok { return _err_file(r3.error); }
  let r4 = _read_records(data, &mut f);
  if !r4.is_ok { return _err_file(r4.error); }
  let r5 = _read_features(data, &mut f);
  if !r5.is_ok { return _err_file(r5.error); }
  return _ok_file(f);
}

// --------------------------------------------------
//  Header accessors
// --------------------------------------------------

/// The header's `size` field (104 for current files; larger values are
/// accepted and their trailing bytes ignored). Complexity: O(1).
pub fn perf_header_size(f: &PerfFile) -> Int {
  return f.header_size;
}

/// The header's `attr_size`: the byte stride of one attrs-section record
/// (perf_event_attr + ids descriptor). Complexity: O(1).
pub fn perf_attr_size(f: &PerfFile) -> Int {
  return f.attr_size;
}

/// Field `field` (a PERF_SECTION_* selector) of the fixed header's
/// attrs/data/event_types perf_file_sections. Err("perf: bad field
/// selector") for an unknown selector. Complexity: O(1).
pub fn perf_section_field(f: &PerfFile, field: Int) -> Result[Int, Str] {
  if field == PERF_SECTION_ATTRS_OFFSET {
    return _ok_int(f.attrs_offset);
  }
  if field == PERF_SECTION_ATTRS_SIZE {
    return _ok_int(f.attrs_size);
  }
  if field == PERF_SECTION_DATA_OFFSET {
    return _ok_int(f.data_offset);
  }
  if field == PERF_SECTION_DATA_SIZE {
    return _ok_int(f.data_size);
  }
  if field == PERF_SECTION_EVENT_TYPES_OFFSET {
    return _ok_int(f.event_types_offset);
  }
  if field == PERF_SECTION_EVENT_TYPES_SIZE {
    return _ok_int(f.event_types_size);
  }
  return _err_int("perf: bad field selector");
}

/// Byte-order variant of a buffer, from its first 8 bytes:
/// PERF_VARIANT_LE (PERFILE2 in LE byte order), PERF_VARIANT_BE (the
/// byte-swapped form) or PERF_VARIANT_UNKNOWN (anything else, including
/// buffers shorter than 8 bytes). Complexity: O(1).
pub fn perf_variant(data: &Vec[UInt8]) -> Int {
  if data.len() < PERF_HEADER_MAGIC_SIZE {
    return PERF_VARIANT_UNKNOWN;
  }
  if _magic_le(data) {
    return PERF_VARIANT_LE;
  }
  if _magic_be(data) {
    return PERF_VARIANT_BE;
  }
  return PERF_VARIANT_UNKNOWN;
}

// --------------------------------------------------
//  Feature presence accessors
// --------------------------------------------------

/// True when feature bit `feat` (a PERF_FEATURE_* constant) is set in the
/// header's 256-bit bitmap. Bits outside 0..255 are false. Complexity: O(1).
pub fn perf_feature_present(f: &PerfFile, feat: Int) -> Bool {
  return _feat_present(f, feat);
}

/// Number of present features in the parsed file. Complexity: O(1).
pub fn perf_feature_count(f: &PerfFile) -> Int {
  return f.feat_bits.len();
}

/// Feature bit of present-feature index `i` (0..perf_feature_count), in
/// increasing bit order. Err("perf: index out of range") otherwise.
/// Complexity: O(1).
pub fn perf_feature_bit(f: &PerfFile, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.feat_bits.len() {
    return _err_int("perf: index out of range");
  }
  let v: Int = f.feat_bits[i];
  return _ok_int(v);
}

/// Field `field` (PERF_FEATURE_FIELD_OFFSET or PERF_FEATURE_FIELD_SIZE) of
/// the perf_file_section of feature `feat`. Err("perf: feature not
/// present") when the bit is clear, Err("perf: bad field selector")
/// otherwise. Complexity: O(features).
pub fn perf_feature_section_field(f: &PerfFile, feat: Int, field: Int) -> Result[Int, Str] {
  let idx = _feat_index(f, feat);
  if idx < 0 {
    return _err_int("perf: feature not present");
  }
  if field == PERF_FEATURE_FIELD_OFFSET {
    let v: Int = f.feat_offsets[idx];
    return _ok_int(v);
  }
  if field == PERF_FEATURE_FIELD_SIZE {
    let v: Int = f.feat_sizes[idx];
    return _ok_int(v);
  }
  return _err_int("perf: bad field selector");
}

// --------------------------------------------------
//  Attr accessors
// --------------------------------------------------

/// Number of attrs-section records. Complexity: O(1).
pub fn perf_attr_count(f: &PerfFile) -> Int {
  return f.attr_types.len();
}

/// Field `field` (a PERF_ATTR_FIELD_* selector) of attr `i`. Fields that
/// the attr's own size does not cover read as 0 (kernel zero-padding
/// convention). Err("perf: index out of range") for a bad `i` and
/// Err("perf: bad field selector") for an unknown selector. Complexity:
/// O(1).
pub fn perf_attr_field(f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.attr_types.len() {
    return _err_int("perf: index out of range");
  }
  if field == PERF_ATTR_FIELD_TYPE {
    let v: Int = f.attr_types[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_SIZE {
    let v: Int = f.attr_sizes[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_CONFIG {
    let v: Int = f.attr_configs[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_SAMPLE_PERIOD {
    let v: Int = f.attr_sample_periods[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_SAMPLE_TYPE {
    let v: Int = f.attr_sample_types[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_READ_FORMAT {
    let v: Int = f.attr_read_formats[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_FLAGS {
    let v: Int = f.attr_flags[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_WAKEUP_EVENTS {
    let v: Int = f.attr_wakeup_events[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_BP_TYPE {
    let v: Int = f.attr_bp_types[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_CONFIG1 {
    let v: Int = f.attr_config1s[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_CONFIG2 {
    let v: Int = f.attr_config2s[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_BRANCH_SAMPLE_TYPE {
    let v: Int = f.attr_branch_sample_types[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_SAMPLE_REGS_USER {
    let v: Int = f.attr_sample_regs_users[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_SAMPLE_STACK_USER {
    let v: Int = f.attr_sample_stack_users[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_CLOCKID {
    let v: Int = f.attr_clockids[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_SAMPLE_REGS_INTR {
    let v: Int = f.attr_sample_regs_intrs[i];
    return _ok_int(v);
  }
  if field == PERF_ATTR_FIELD_AUX_WATERMARK {
    let v: Int = f.attr_aux_watermarks[i];
    return _ok_int(v);
  }
  return _err_int("perf: bad field selector");
}

/// True when bit `bit` (a PERF_ATTR_FLAG_* constant, 0..63) is set in attr
/// `i`'s flag word. Err("perf: index out of range") for a bad `i`,
/// Err("perf: bad attr flag bit") for a bit outside 0..63. Complexity: O(1).
pub fn perf_attr_flag(f: &PerfFile, i: Int, bit: Int) -> Result[Bool, Str] {
  if i < 0 || i >= f.attr_types.len() {
    return _err_bool("perf: index out of range");
  }
  if bit < 0 || bit > 63 {
    return _err_bool("perf: bad attr flag bit");
  }
  let fl: Int = f.attr_flags[i];
  return _ok_bool(_bit_at(fl, bit));
}

/// Number of u64 ids recorded for attr `i` (ids descriptor size / 8).
/// Err("perf: index out of range") for a bad `i`. Complexity: O(1).
pub fn perf_attr_ids_count(f: &PerfFile, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.attr_types.len() {
    return _err_int("perf: index out of range");
  }
  let v: Int = f.attr_id_sizes[i];
  return _ok_int(v / 8);
}

/// Field `field` (PERF_FEATURE_FIELD_OFFSET or PERF_FEATURE_FIELD_SIZE) of
/// attr `i`'s ids perf_file_section. Complexity: O(1).
pub fn perf_attr_ids_section_field(f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.attr_types.len() {
    return _err_int("perf: index out of range");
  }
  if field == PERF_FEATURE_FIELD_OFFSET {
    let v: Int = f.attr_id_offsets[i];
    return _ok_int(v);
  }
  if field == PERF_FEATURE_FIELD_SIZE {
    let v: Int = f.attr_id_sizes[i];
    return _ok_int(v);
  }
  return _err_int("perf: bad field selector");
}

/// Id `k` (0-based, u64) of attr `i`. Err("perf: index out of range") for a
/// bad `i` or `k`. Complexity: O(1).
pub fn perf_attr_id(data: &Vec[UInt8], f: &PerfFile, i: Int, k: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.attr_types.len() {
    return _err_int("perf: index out of range");
  }
  let cnt: Int = f.attr_id_sizes[i] / 8;
  if k < 0 || k >= cnt {
    return _err_int("perf: index out of range");
  }
  let base: Int = f.attr_id_offsets[i];
  return _ok_int(_rdu(data, base + k * 8, 8));
}

// --------------------------------------------------
//  Record accessors
// --------------------------------------------------

/// Number of records in the data section. Complexity: O(1).
pub fn perf_record_count(f: &PerfFile) -> Int {
  return f.rec_types.len();
}

/// Field `field` (a PERF_REC_FIELD_* selector) of record `i`:
/// type, misc, absolute offset of the record header, total size (header
/// included), payload offset and payload size. Err("perf: index out of
/// range") for a bad `i`, Err("perf: bad field selector") otherwise.
/// Complexity: O(1).
pub fn perf_record_field(f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.rec_types.len() {
    return _err_int("perf: index out of range");
  }
  if field == PERF_REC_FIELD_TYPE {
    let v: Int = f.rec_types[i];
    return _ok_int(v);
  }
  if field == PERF_REC_FIELD_MISC {
    let v: Int = f.rec_miscs[i];
    return _ok_int(v);
  }
  if field == PERF_REC_FIELD_OFFSET {
    let v: Int = f.rec_offsets[i];
    return _ok_int(v);
  }
  if field == PERF_REC_FIELD_SIZE {
    let v: Int = f.rec_sizes[i];
    return _ok_int(v);
  }
  if field == PERF_REC_FIELD_PAYLOAD_OFFSET {
    let v: Int = f.rec_offsets[i];
    return _ok_int(v + PERF_RECORD_HEADER_SIZE);
  }
  if field == PERF_REC_FIELD_PAYLOAD_SIZE {
    let v: Int = f.rec_sizes[i];
    return _ok_int(v - PERF_RECORD_HEADER_SIZE);
  }
  return _err_int("perf: bad field selector");
}

/// True when `misc` (record i's misc field) selects cpumode `cpumode`
/// (a PERF_RECORD_MISC_*_KERNEL/USER/HYPERVISOR constant). The check uses
/// the low three bits (PERF_RECORD_MISC_CPUMODE_MASK). Complexity: O(1).
pub fn perf_record_misc_is(data: &Vec[UInt8], f: &PerfFile, i: Int, cpumode: Int) -> Result[Bool, Str] {
  let r = perf_record_field(f, i, PERF_REC_FIELD_MISC);
  if !r.is_ok { return _err_bool(r.error); }
  let m: Int = r.value;
  return _ok_bool(_cpumode_is(m, cpumode));
}

/// Name of a PERF_RECORD_* type value; "UNKNOWN" for values this package
/// does not document. Complexity: O(1).
pub fn perf_record_type_name(t: Int) -> Str {
  if t == PERF_RECORD_MMAP { return "MMAP"; }
  if t == PERF_RECORD_LOST { return "LOST"; }
  if t == PERF_RECORD_COMM { return "COMM"; }
  if t == PERF_RECORD_EXIT { return "EXIT"; }
  if t == PERF_RECORD_THROTTLE { return "THROTTLE"; }
  if t == PERF_RECORD_UNTHROTTLE { return "UNTHROTTLE"; }
  if t == PERF_RECORD_FORK { return "FORK"; }
  if t == PERF_RECORD_READ { return "READ"; }
  if t == PERF_RECORD_SAMPLE { return "SAMPLE"; }
  if t == PERF_RECORD_MMAP2 { return "MMAP2"; }
  if t == PERF_RECORD_AUX { return "AUX"; }
  if t == PERF_RECORD_ITRACE_START { return "ITRACE_START"; }
  if t == PERF_RECORD_LOST_SAMPLES { return "LOST_SAMPLES"; }
  if t == PERF_RECORD_SWITCH { return "SWITCH"; }
  if t == PERF_RECORD_SWITCH_CPU_WIDE { return "SWITCH_CPU_WIDE"; }
  if t == PERF_RECORD_NAMESPACES { return "NAMESPACES"; }
  if t == PERF_RECORD_KSYMBOL { return "KSYMBOL"; }
  if t == PERF_RECORD_BPF_EVENT { return "BPF_EVENT"; }
  if t == PERF_RECORD_CGROUP { return "CGROUP"; }
  if t == PERF_RECORD_TEXT_POKE { return "TEXT_POKE"; }
  if t == PERF_RECORD_AUX_OUTPUT_HW_ID { return "AUX_OUTPUT_HW_ID"; }
  if t == PERF_RECORD_HEADER_ATTR { return "HEADER_ATTR"; }
  if t == PERF_RECORD_HEADER_EVENT_TYPE { return "HEADER_EVENT_TYPE"; }
  if t == PERF_RECORD_HEADER_TRACING_DATA { return "HEADER_TRACING_DATA"; }
  if t == PERF_RECORD_HEADER_BUILD_ID { return "HEADER_BUILD_ID"; }
  if t == PERF_RECORD_FINISHED_ROUND { return "FINISHED_ROUND"; }
  if t == PERF_RECORD_ID_INDEX { return "ID_INDEX"; }
  if t == PERF_RECORD_AUXTRACE_INFO { return "AUXTRACE_INFO"; }
  if t == PERF_RECORD_AUXTRACE { return "AUXTRACE"; }
  if t == PERF_RECORD_AUXTRACE_ERROR { return "AUXTRACE_ERROR"; }
  if t == PERF_RECORD_THREAD_MAP { return "THREAD_MAP"; }
  if t == PERF_RECORD_CPU_MAP { return "CPU_MAP"; }
  if t == PERF_RECORD_STAT_CONFIG { return "STAT_CONFIG"; }
  if t == PERF_RECORD_STAT { return "STAT"; }
  if t == PERF_RECORD_STAT_ROUND { return "STAT_ROUND"; }
  if t == PERF_RECORD_EVENT_UPDATE { return "EVENT_UPDATE"; }
  if t == PERF_RECORD_TIME_CONV { return "TIME_CONV"; }
  if t == PERF_RECORD_HEADER_FEATURE { return "HEADER_FEATURE"; }
  if t == PERF_RECORD_COMPRESSED { return "COMPRESSED"; }
  if t == PERF_RECORD_FINISHED_INIT { return "FINISHED_INIT"; }
  if t == PERF_RECORD_COMPRESSED2 { return "COMPRESSED2"; }
  return "UNKNOWN";
}

// --------------------------------------------------
//  Record payload helpers
// --------------------------------------------------

// Fixed payload field `off..off+size` of record `i`, which must be of type
// `want`. Errors: bad record index, type mismatch, payload out of bounds.
fn _rec_fixed(data: &Vec[UInt8], f: &PerfFile, i: Int, want: Int, off: Int, size: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.rec_types.len() {
    return _err_int("perf: record index out of range");
  }
  let rt: Int = f.rec_types[i];
  if rt != want {
    return _err_int("perf: record type mismatch");
  }
  let roff: Int = f.rec_offsets[i];
  let rsize: Int = f.rec_sizes[i];
  if off < 0 || size < 0 {
    return _err_int("perf: record payload out of bounds");
  }
  if off + size > rsize - PERF_RECORD_HEADER_SIZE {
    return _err_int("perf: record payload out of bounds");
  }
  return _ok_int(_rdu(data, roff + PERF_RECORD_HEADER_SIZE + off, size));
}

// Absolute offset of the variable-length tail of record `i` that starts
// `prefix` bytes into the payload.
fn _rec_rest_off(f: &PerfFile, i: Int, want: Int, prefix: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.rec_types.len() {
    return _err_int("perf: record index out of range");
  }
  let rt: Int = f.rec_types[i];
  if rt != want {
    return _err_int("perf: record type mismatch");
  }
  let roff: Int = f.rec_offsets[i];
  let rsize: Int = f.rec_sizes[i];
  if prefix < 0 || prefix > rsize - PERF_RECORD_HEADER_SIZE {
    return _err_int("perf: record payload out of bounds");
  }
  return _ok_int(roff + PERF_RECORD_HEADER_SIZE + prefix);
}

// Length of the variable-length tail of record `i` that starts `prefix`
// bytes into the payload.
fn _rec_rest_size(f: &PerfFile, i: Int, want: Int, prefix: Int) -> Result[Int, Str] {
  let o = _rec_rest_off(f, i, want, prefix);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let rsize: Int = f.rec_sizes[i];
  return _ok_int(rsize - PERF_RECORD_HEADER_SIZE - prefix);
}

// --------------------------------------------------
//  Record payload decoders
// --------------------------------------------------

/// Field `field` (a PERF_MMAP_FIELD_* selector) of MMAP record `i`.
/// Payload: pid u32, tid u32, addr u64, len u64, pgoff u64, filename bytes.
/// Err("perf: record type mismatch") for other record types and the usual
/// index/bounds/selector errors. Complexity: O(1).
pub fn perf_mmap_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_MMAP_FIELD_PID {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP, 0, 4);
  }
  if field == PERF_MMAP_FIELD_TID {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP, 4, 4);
  }
  if field == PERF_MMAP_FIELD_ADDR {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP, 8, 8);
  }
  if field == PERF_MMAP_FIELD_LEN {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP, 16, 8);
  }
  if field == PERF_MMAP_FIELD_PGOFF {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP, 24, 8);
  }
  if field == PERF_MMAP_FIELD_FILENAME_OFFSET {
    return _rec_rest_off(f, i, PERF_RECORD_MMAP, 32);
  }
  if field == PERF_MMAP_FIELD_FILENAME_SIZE {
    return _rec_rest_size(f, i, PERF_RECORD_MMAP, 32);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_MMAP2_FIELD_* selector) of MMAP2 record `i`.
/// Payload: pid u32, tid u32, addr u64, len u64, pgoff u64, maj u32, min
/// u32, ino u64, ino_generation u64, prot u32, flags u32, filename bytes.
/// PROT is the protection flags field, FLAGS the mmap flags field.
/// Complexity: O(1).
pub fn perf_mmap2_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_MMAP2_FIELD_PID {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 0, 4);
  }
  if field == PERF_MMAP2_FIELD_TID {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 4, 4);
  }
  if field == PERF_MMAP2_FIELD_ADDR {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 8, 8);
  }
  if field == PERF_MMAP2_FIELD_LEN {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 16, 8);
  }
  if field == PERF_MMAP2_FIELD_PGOFF {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 24, 8);
  }
  if field == PERF_MMAP2_FIELD_MAJ {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 32, 4);
  }
  if field == PERF_MMAP2_FIELD_MIN {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 36, 4);
  }
  if field == PERF_MMAP2_FIELD_INO {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 40, 8);
  }
  if field == PERF_MMAP2_FIELD_INO_GENERATION {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 48, 8);
  }
  if field == PERF_MMAP2_FIELD_PROT {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 56, 4);
  }
  if field == PERF_MMAP2_FIELD_FLAGS {
    return _rec_fixed(data, f, i, PERF_RECORD_MMAP2, 60, 4);
  }
  if field == PERF_MMAP2_FIELD_FILENAME_OFFSET {
    return _rec_rest_off(f, i, PERF_RECORD_MMAP2, 64);
  }
  if field == PERF_MMAP2_FIELD_FILENAME_SIZE {
    return _rec_rest_size(f, i, PERF_RECORD_MMAP2, 64);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_COMM_FIELD_* selector) of COMM record `i`.
/// Payload: pid u32, tid u32, comm bytes (not NUL-terminated; the record
/// size delimits them). Complexity: O(1).
pub fn perf_comm_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_COMM_FIELD_PID {
    return _rec_fixed(data, f, i, PERF_RECORD_COMM, 0, 4);
  }
  if field == PERF_COMM_FIELD_TID {
    return _rec_fixed(data, f, i, PERF_RECORD_COMM, 4, 4);
  }
  if field == PERF_COMM_FIELD_COMM_OFFSET {
    return _rec_rest_off(f, i, PERF_RECORD_COMM, 8);
  }
  if field == PERF_COMM_FIELD_COMM_SIZE {
    return _rec_rest_size(f, i, PERF_RECORD_COMM, 8);
  }
  return _err_int("perf: bad field selector");
}

// Shared FORK/EXIT field reader.
fn _task_field(data: &Vec[UInt8], f: &PerfFile, i: Int, want: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_TASK_FIELD_PID {
    return _rec_fixed(data, f, i, want, 0, 4);
  }
  if field == PERF_TASK_FIELD_PPID {
    return _rec_fixed(data, f, i, want, 4, 4);
  }
  if field == PERF_TASK_FIELD_TID {
    return _rec_fixed(data, f, i, want, 8, 4);
  }
  if field == PERF_TASK_FIELD_PTID {
    return _rec_fixed(data, f, i, want, 12, 4);
  }
  if field == PERF_TASK_FIELD_TIME {
    return _rec_fixed(data, f, i, want, 16, 8);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_TASK_FIELD_* selector) of FORK record `i`:
/// pid, ppid, tid, ptid (u32 each) and time (u64). Complexity: O(1).
pub fn perf_fork_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  return _task_field(data, f, i, PERF_RECORD_FORK, field);
}

/// Field `field` (a PERF_TASK_FIELD_* selector) of EXIT record `i`.
/// Complexity: O(1).
pub fn perf_exit_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  return _task_field(data, f, i, PERF_RECORD_EXIT, field);
}

/// Field `field` (a PERF_LOST_FIELD_* selector) of LOST record `i`:
/// id u64, lost u64. Complexity: O(1).
pub fn perf_lost_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_LOST_FIELD_ID {
    return _rec_fixed(data, f, i, PERF_RECORD_LOST, 0, 8);
  }
  if field == PERF_LOST_FIELD_LOST {
    return _rec_fixed(data, f, i, PERF_RECORD_LOST, 8, 8);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_READ_FIELD_* selector) of READ record `i`, using
/// attr `attr_index`'s read_format to locate the optional fields. PID/TID
/// are the fixed u32 pair; VALUE, TIME_ENABLED, TIME_RUNNING and ID follow
/// the read_format bits. GROUP read formats are recognized and rejected
/// (their variable-length member values are not decoded).
/// Complexity: O(1).
pub fn perf_read_field(data: &Vec[UInt8], f: &PerfFile, i: Int, attr_index: Int, field: Int) -> Result[Int, Str] {
  if attr_index < 0 || attr_index >= f.attr_types.len() {
    return _err_int("perf: attr index out of range");
  }
  if field == PERF_READ_FIELD_PID {
    return _rec_fixed(data, f, i, PERF_RECORD_READ, 0, 4);
  }
  if field == PERF_READ_FIELD_TID {
    return _rec_fixed(data, f, i, PERF_RECORD_READ, 4, 4);
  }
  if field == PERF_READ_FIELD_VALUE {
    return _rec_fixed(data, f, i, PERF_RECORD_READ, 8, 8);
  }
  let rf: Int = f.attr_read_formats[attr_index];
  if _bit_at(rf, 3) {
    return _err_int("perf: grouped read format not supported");
  }
  var off = 16;
  if field == PERF_READ_FIELD_TIME_ENABLED {
    if !_bit_at(rf, 0) {
      return _err_int("perf: read field not present in read_format");
    }
    return _rec_fixed(data, f, i, PERF_RECORD_READ, off, 8);
  }
  if _bit_at(rf, 0) {
    off = off + 8;
  }
  if field == PERF_READ_FIELD_TIME_RUNNING {
    if !_bit_at(rf, 1) {
      return _err_int("perf: read field not present in read_format");
    }
    return _rec_fixed(data, f, i, PERF_RECORD_READ, off, 8);
  }
  if _bit_at(rf, 1) {
    off = off + 8;
  }
  if field == PERF_READ_FIELD_ID {
    if !_bit_at(rf, 2) {
      return _err_int("perf: read field not present in read_format");
    }
    return _rec_fixed(data, f, i, PERF_RECORD_READ, off, 8);
  }
  return _err_int("perf: bad field selector");
}

// Shared THROTTLE/UNTHROTTLE field reader.
fn _throttle_field(data: &Vec[UInt8], f: &PerfFile, i: Int, want: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_THROTTLE_FIELD_TIME {
    return _rec_fixed(data, f, i, want, 0, 8);
  }
  if field == PERF_THROTTLE_FIELD_ID {
    return _rec_fixed(data, f, i, want, 8, 8);
  }
  if field == PERF_THROTTLE_FIELD_STREAM_ID {
    return _rec_fixed(data, f, i, want, 16, 8);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_THROTTLE_FIELD_* selector) of THROTTLE record
/// `i`: time u64, id u64, stream_id u64. Complexity: O(1).
pub fn perf_throttle_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  return _throttle_field(data, f, i, PERF_RECORD_THROTTLE, field);
}

/// Field `field` (a PERF_THROTTLE_FIELD_* selector) of UNTHROTTLE record
/// `i`. Complexity: O(1).
pub fn perf_unthrottle_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  return _throttle_field(data, f, i, PERF_RECORD_UNTHROTTLE, field);
}

/// Field `field` (a PERF_SWITCH_FIELD_* selector) of SWITCH or
/// SWITCH_CPU_WIDE record `i`: next_prev_pid u32, next_prev_tid u32. For
/// SWITCH_CPU_WIDE, next_prev_pid holds the CPU. Complexity: O(1).
pub fn perf_switch_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.rec_types.len() {
    return _err_int("perf: record index out of range");
  }
  let rt: Int = f.rec_types[i];
  if rt != PERF_RECORD_SWITCH && rt != PERF_RECORD_SWITCH_CPU_WIDE {
    return _err_int("perf: record type mismatch");
  }
  if field == PERF_SWITCH_FIELD_NEXT_PREV_PID {
    return _rec_fixed(data, f, i, rt, 0, 4);
  }
  if field == PERF_SWITCH_FIELD_NEXT_PREV_TID {
    return _rec_fixed(data, f, i, rt, 4, 4);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_AUX_FIELD_* selector) of AUX record `i`:
/// aux_offset u64, aux_size u64, flags u64. Complexity: O(1).
pub fn perf_aux_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_AUX_FIELD_AUX_OFFSET {
    return _rec_fixed(data, f, i, PERF_RECORD_AUX, 0, 8);
  }
  if field == PERF_AUX_FIELD_AUX_SIZE {
    return _rec_fixed(data, f, i, PERF_RECORD_AUX, 8, 8);
  }
  if field == PERF_AUX_FIELD_FLAGS {
    return _rec_fixed(data, f, i, PERF_RECORD_AUX, 16, 8);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_ITRACE_FIELD_* selector) of ITRACE_START record
/// `i`: pid u32, tid u32. Complexity: O(1).
pub fn perf_itrace_start_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_ITRACE_FIELD_PID {
    return _rec_fixed(data, f, i, PERF_RECORD_ITRACE_START, 0, 4);
  }
  if field == PERF_ITRACE_FIELD_TID {
    return _rec_fixed(data, f, i, PERF_RECORD_ITRACE_START, 4, 4);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_LOST_SAMPLES_FIELD_* selector) of LOST_SAMPLES
/// record `i`: lost u64. Complexity: O(1).
pub fn perf_lost_samples_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_LOST_SAMPLES_FIELD_LOST {
    return _rec_fixed(data, f, i, PERF_RECORD_LOST_SAMPLES, 0, 8);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_NS_FIELD_* selector) of NAMESPACES record `i`.
/// Payload: pid u32, tid u32, nr_namespaces u64, then nr_namespaces x
/// {dev u64, ino u64}. ENTRY_DEV/ENTRY_INO take the entry index as `entry`.
/// Complexity: O(1).
pub fn perf_namespaces_field(data: &Vec[UInt8], f: &PerfFile, i: Int, entry: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_NS_FIELD_PID {
    return _rec_fixed(data, f, i, PERF_RECORD_NAMESPACES, 0, 4);
  }
  if field == PERF_NS_FIELD_TID {
    return _rec_fixed(data, f, i, PERF_RECORD_NAMESPACES, 4, 4);
  }
  if field == PERF_NS_FIELD_NR_NAMESPACES {
    return _rec_fixed(data, f, i, PERF_RECORD_NAMESPACES, 8, 8);
  }
  if field == PERF_NS_FIELD_ENTRY_DEV || field == PERF_NS_FIELD_ENTRY_INO {
    let nr = _rec_fixed(data, f, i, PERF_RECORD_NAMESPACES, 8, 8);
    if !nr.is_ok {
      return _err_int(nr.error);
    }
    let n: Int = nr.value;
    if entry < 0 || entry >= n {
      return _err_int("perf: index out of range");
    }
    if field == PERF_NS_FIELD_ENTRY_DEV {
      return _rec_fixed(data, f, i, PERF_RECORD_NAMESPACES, 16 + entry * 16, 8);
    }
    return _rec_fixed(data, f, i, PERF_RECORD_NAMESPACES, 24 + entry * 16, 8);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_KSYMBOL_FIELD_* selector) of KSYMBOL record `i`.
/// Payload: address u64, len u32, ksym_type u16, flags u16, name bytes.
/// Complexity: O(1).
pub fn perf_ksymbol_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_KSYMBOL_FIELD_ADDR {
    return _rec_fixed(data, f, i, PERF_RECORD_KSYMBOL, 0, 8);
  }
  if field == PERF_KSYMBOL_FIELD_LEN {
    return _rec_fixed(data, f, i, PERF_RECORD_KSYMBOL, 8, 4);
  }
  if field == PERF_KSYMBOL_FIELD_KSYM_TYPE {
    return _rec_fixed(data, f, i, PERF_RECORD_KSYMBOL, 12, 2);
  }
  if field == PERF_KSYMBOL_FIELD_FLAGS {
    return _rec_fixed(data, f, i, PERF_RECORD_KSYMBOL, 14, 2);
  }
  if field == PERF_KSYMBOL_FIELD_NAME_OFFSET {
    return _rec_rest_off(f, i, PERF_RECORD_KSYMBOL, 16);
  }
  if field == PERF_KSYMBOL_FIELD_NAME_SIZE {
    return _rec_rest_size(f, i, PERF_RECORD_KSYMBOL, 16);
  }
  return _err_int("perf: bad field selector");
}

/// Field `field` (a PERF_BPF_FIELD_* selector) of BPF_EVENT record `i`:
/// type u16, flags u8 (pad u8), id u32. Complexity: O(1).
pub fn perf_bpf_field(data: &Vec[UInt8], f: &PerfFile, i: Int, field: Int) -> Result[Int, Str] {
  if field == PERF_BPF_FIELD_TYPE {
    return _rec_fixed(data, f, i, PERF_RECORD_BPF_EVENT, 0, 2);
  }
  if field == PERF_BPF_FIELD_FLAGS {
    return _rec_fixed(data, f, i, PERF_RECORD_BPF_EVENT, 2, 1);
  }
  if field == PERF_BPF_FIELD_ID {
    return _rec_fixed(data, f, i, PERF_RECORD_BPF_EVENT, 4, 4);
  }
  return _err_int("perf: bad field selector");
}

/// Number of entries in ID_INDEX record `i` (the u64 nr payload word).
/// A count with bit 63 set is rejected with its byte offset.
/// Complexity: O(1).
pub fn perf_id_index_count(data: &Vec[UInt8], f: &PerfFile, i: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.rec_types.len() {
    return _err_int("perf: record index out of range");
  }
  let rt: Int = f.rec_types[i];
  if rt != PERF_RECORD_ID_INDEX {
    return _err_int("perf: record type mismatch");
  }
  let roff: Int = f.rec_offsets[i];
  let rsize: Int = f.rec_sizes[i];
  if rsize - PERF_RECORD_HEADER_SIZE < 8 {
    return _err_int("perf: record payload out of bounds");
  }
  let off = roff + PERF_RECORD_HEADER_SIZE;
  let nr = _rdu(data, off, 8);
  if nr < 0 {
    return _err_int(_at("negative id_index count", off));
  }
  return _ok_int(nr);
}

/// Field `field` (a PERF_IDX_ENTRY_FIELD_* selector) of entry `k` of
/// ID_INDEX record `i`: id u64, idx u64, cpu u64, tid u64.
/// Complexity: O(1).
pub fn perf_id_index_entry_field(data: &Vec[UInt8], f: &PerfFile, i: Int, k: Int, field: Int) -> Result[Int, Str] {
  let c = perf_id_index_count(data, f, i);
  if !c.is_ok {
    return _err_int(c.error);
  }
  let n: Int = c.value;
  if k < 0 || k >= n {
    return _err_int("perf: index out of range");
  }
  var off = -1;
  if field == PERF_IDX_ENTRY_FIELD_ID { off = 0; }
  if field == PERF_IDX_ENTRY_FIELD_IDX { off = 8; }
  if field == PERF_IDX_ENTRY_FIELD_CPU { off = 16; }
  if field == PERF_IDX_ENTRY_FIELD_TID { off = 24; }
  if off < 0 {
    return _err_int("perf: bad field selector");
  }
  let roff: Int = f.rec_offsets[i];
  let rsize: Int = f.rec_sizes[i];
  let poff = roff + PERF_RECORD_HEADER_SIZE + 8 + k * PERF_IDX_ENTRY_SIZE + off;
  if poff + 8 > roff + rsize {
    return _err_int("perf: record payload out of bounds");
  }
  return _ok_int(_rdu(data, poff, 8));
}

/// Field `field` (a PERF_BD_FIELD_* selector) of header BUILD_ID record
/// `i`. The build-id width is not self-describing on disk, so the caller
/// supplies it (`bid_size`, 1..64; 20 for a SHA1 id, 24 for perf's padded
/// 20-byte default struct, 32 for a SHA256 id). Payload layout implemented:
/// pid u32 at 0, build_id[bid_size] at 4, filename bytes to the end.
/// Complexity: O(1).
pub fn perf_build_id_field(data: &Vec[UInt8], f: &PerfFile, i: Int, bid_size: Int, field: Int) -> Result[Int, Str] {
  if bid_size < PERF_BUILD_ID_MIN || bid_size > PERF_BUILD_ID_MAX {
    return _err_int("perf: bad build id size");
  }
  if i < 0 || i >= f.rec_types.len() {
    return _err_int("perf: record index out of range");
  }
  let rt: Int = f.rec_types[i];
  if rt != PERF_RECORD_HEADER_BUILD_ID {
    return _err_int("perf: record type mismatch");
  }
  let roff: Int = f.rec_offsets[i];
  let rsize: Int = f.rec_sizes[i];
  let psize = rsize - PERF_RECORD_HEADER_SIZE;
  if psize < 4 + bid_size {
    return _err_int("perf: record payload out of bounds");
  }
  if field == PERF_BD_FIELD_PID {
    return _ok_int(_rdu(data, roff + PERF_RECORD_HEADER_SIZE, 4));
  }
  if field == PERF_BD_FIELD_BUILD_ID_OFFSET {
    return _ok_int(roff + PERF_RECORD_HEADER_SIZE + 4);
  }
  if field == PERF_BD_FIELD_BUILD_ID_SIZE {
    return _ok_int(bid_size);
  }
  if field == PERF_BD_FIELD_FILENAME_OFFSET {
    return _ok_int(roff + PERF_RECORD_HEADER_SIZE + 4 + bid_size);
  }
  if field == PERF_BD_FIELD_FILENAME_SIZE {
    return _ok_int(psize - 4 - bid_size);
  }
  return _err_int("perf: bad field selector");
}

// --------------------------------------------------
//  SAMPLE reconstruction
// --------------------------------------------------

// Size in bytes of the identity sample_id fields selected by sample_type
// (TID, TIME, ID, STREAM_ID, CPU and IDENTIFIER; 8 bytes each).
fn _sample_id_size(st: Int) -> Int {
  var n = 0;
  if _bit_at(st, PERF_SAMPLE_BIT_TID) { n = n + 1; }
  if _bit_at(st, PERF_SAMPLE_BIT_TIME) { n = n + 1; }
  if _bit_at(st, PERF_SAMPLE_BIT_ID) { n = n + 1; }
  if _bit_at(st, PERF_SAMPLE_BIT_STREAM_ID) { n = n + 1; }
  if _bit_at(st, PERF_SAMPLE_BIT_CPU) { n = n + 1; }
  if _bit_at(st, PERF_SAMPLE_BIT_IDENTIFIER) { n = n + 1; }
  return n * 8;
}

// Walk a SAMPLE payload in kernel emission order and return the payload
// offset of field `want` (a PERF_SAMPLE_BIT_* index), validating that every
// field up to it (and the wanted field itself) fits in `psize` bytes after
// absolute payload start `base`. Variable-size fields (CALLCHAIN, RAW,
// BRANCH_STACK, REGS_*, STACK_USER) are skipped using their documented
// sizes. GROUP read formats cannot be skipped past and are rejected.
fn _sample_off(data: &Vec[UInt8], base: Int, psize: Int, st: Int, rf: Int, rgu: Int, rgi: Int, want: Int) -> Result[Int, Str] {
  var off = 0;
  if _bit_at(st, PERF_SAMPLE_BIT_IDENTIFIER) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_IDENTIFIER { return _ok_int(off); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_IP) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_IP { return _ok_int(off); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_TID) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_TID { return _ok_int(off); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_TIME) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_TIME { return _ok_int(off); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_ADDR) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_ADDR { return _ok_int(off); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_ID) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_ID { return _ok_int(off); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_STREAM_ID) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_STREAM_ID { return _ok_int(off); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_CPU) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_CPU { return _ok_int(off); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_PERIOD) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_PERIOD { return _ok_int(off); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_READ) {
    var rsz = 8;
    if _bit_at(rf, 0) { rsz = rsz + 8; }
    if _bit_at(rf, 1) { rsz = rsz + 8; }
    if _bit_at(rf, 3) {
      if want == PERF_SAMPLE_BIT_READ {
        return _ok_int(off);
      }
      return _err_int("perf: grouped read format not supported");
    }
    if _bit_at(rf, 2) { rsz = rsz + 8; }
    if _bit_at(rf, 4) { rsz = rsz + 8; }
    if off + rsz > psize { return _err_int("perf: sample payload truncated"); }
    if want == PERF_SAMPLE_BIT_READ { return _ok_int(off); }
    off = off + rsz;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_CALLCHAIN) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    let nr = _rdu(data, base + off, 8);
    if nr < 0 { return _err_int("perf: sample payload truncated"); }
    let total = 8 + nr * 8;
    if off + total > psize { return _err_int("perf: sample payload truncated"); }
    off = off + total;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_RAW) {
    if off + 4 > psize { return _err_int("perf: sample payload truncated"); }
    let rs = _rdu(data, base + off, 4);
    let total = 4 + rs;
    if off + total > psize { return _err_int("perf: sample payload truncated"); }
    off = off + total;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_BRANCH_STACK) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    let nr = _rdu(data, base + off, 8);
    if nr < 0 { return _err_int("perf: sample payload truncated"); }
    let total = 8 + nr * 24;
    if off + total > psize { return _err_int("perf: sample payload truncated"); }
    off = off + total;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_REGS_USER) {
    let total = 8 + _popcount64(rgu) * 8;
    if off + total > psize { return _err_int("perf: sample payload truncated"); }
    off = off + total;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_STACK_USER) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    let ss = _rdu(data, base + off, 8);
    if ss < 0 { return _err_int("perf: sample payload truncated"); }
    let total = 8 + ss + 8;
    if off + total > psize { return _err_int("perf: sample payload truncated"); }
    off = off + total;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_WEIGHT) || _bit_at(st, PERF_SAMPLE_BIT_WEIGHT_STRUCT) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_DATA_SRC) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_TRANSACTION) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_REGS_INTR) {
    let total = 8 + _popcount64(rgi) * 8;
    if off + total > psize { return _err_int("perf: sample payload truncated"); }
    off = off + total;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_PHYS_ADDR) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_AUX) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_CGROUP) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_DATA_PAGE_SIZE) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    off = off + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_CODE_PAGE_SIZE) {
    if off + 8 > psize { return _err_int("perf: sample payload truncated"); }
    off = off + 8;
  }
  return _err_int("perf: sample field not present in sample_type");
}

// Map a PERF_SAMPLE_FIELD_* selector to its sample_type bit index, or -1.
fn _sample_bit_of(field: Int) -> Int {
  var bit = -1;
  if field == PERF_SAMPLE_FIELD_IDENTIFIER { bit = PERF_SAMPLE_BIT_IDENTIFIER; }
  if field == PERF_SAMPLE_FIELD_IP { bit = PERF_SAMPLE_BIT_IP; }
  if field == PERF_SAMPLE_FIELD_PID { bit = PERF_SAMPLE_BIT_TID; }
  if field == PERF_SAMPLE_FIELD_TID { bit = PERF_SAMPLE_BIT_TID; }
  if field == PERF_SAMPLE_FIELD_TIME { bit = PERF_SAMPLE_BIT_TIME; }
  if field == PERF_SAMPLE_FIELD_ADDR { bit = PERF_SAMPLE_BIT_ADDR; }
  if field == PERF_SAMPLE_FIELD_ID { bit = PERF_SAMPLE_BIT_ID; }
  if field == PERF_SAMPLE_FIELD_STREAM_ID { bit = PERF_SAMPLE_BIT_STREAM_ID; }
  if field == PERF_SAMPLE_FIELD_CPU { bit = PERF_SAMPLE_BIT_CPU; }
  if field == PERF_SAMPLE_FIELD_PERIOD { bit = PERF_SAMPLE_BIT_PERIOD; }
  if field == PERF_SAMPLE_FIELD_READ_VALUE { bit = PERF_SAMPLE_BIT_READ; }
  return bit;
}

/// Field `field` (a PERF_SAMPLE_FIELD_* selector) of SAMPLE record `i`,
/// reconstructed from attr `attr_index`'s sample_type (callers normally
/// pass the first attr, index 0). Returns IP, IDENTIFIER, PID, TID, TIME,
/// ADDR, ID, STREAM_ID, CPU, PERIOD or the first READ value as raw LE
/// integers. Err("perf: sample field not present in sample_type") when the
/// attr's sample_type bit is clear. Complexity: O(sample_type fields).
pub fn perf_sample_field(data: &Vec[UInt8], f: &PerfFile, i: Int, attr_index: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.rec_types.len() {
    return _err_int("perf: record index out of range");
  }
  let rt: Int = f.rec_types[i];
  if rt != PERF_RECORD_SAMPLE {
    return _err_int("perf: record type mismatch");
  }
  if attr_index < 0 || attr_index >= f.attr_types.len() {
    return _err_int("perf: attr index out of range");
  }
  let bit = _sample_bit_of(field);
  if bit < 0 {
    return _err_int("perf: bad field selector");
  }
  let st: Int = f.attr_sample_types[attr_index];
  if !_bit_at(st, bit) {
    return _err_int("perf: sample field not present in sample_type");
  }
  let rf: Int = f.attr_read_formats[attr_index];
  let rgu: Int = f.attr_sample_regs_users[attr_index];
  let rgi: Int = f.attr_sample_regs_intrs[attr_index];
  let roff: Int = f.rec_offsets[i];
  let rsize: Int = f.rec_sizes[i];
  let psize = rsize - PERF_RECORD_HEADER_SIZE;
  let poff = roff + PERF_RECORD_HEADER_SIZE;
  let o = _sample_off(data, poff, psize, st, rf, rgu, rgi, bit);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let rel: Int = o.value;
  if field == PERF_SAMPLE_FIELD_PID {
    return _ok_int(_rdu(data, poff + rel, 4));
  }
  if field == PERF_SAMPLE_FIELD_TID {
    return _ok_int(_rdu(data, poff + rel + 4, 4));
  }
  if field == PERF_SAMPLE_FIELD_CPU {
    return _ok_int(_rdu(data, poff + rel, 4));
  }
  return _ok_int(_rdu(data, poff + rel, 8));
}

/// Field `field` (a PERF_SAMPLE_FIELD_* selector) of the sample_id tail of
/// non-SAMPLE record `i`, using attr `attr_index`. When an attr sets
/// sample_id_all, identity fields selected by its sample_type are appended
/// after the type-specific payload in the fixed order TID, TIME, ID,
/// STREAM_ID, CPU, IDENTIFIER (8 bytes each); the tail is decoded from the
/// end of the record. Err("perf: sample_id_all not set") when the attr's
/// flag is clear, Err("perf: sample_id tail is empty") when the
/// sample_type selects no identity field, and
/// Err("perf: sample_id tail not applicable to SAMPLE records") for SAMPLE
/// records (their identity fields are interleaved by perf_sample_field).
/// Complexity: O(1).
pub fn perf_sample_id_tail_field(data: &Vec[UInt8], f: &PerfFile, i: Int, attr_index: Int, field: Int) -> Result[Int, Str] {
  if i < 0 || i >= f.rec_types.len() {
    return _err_int("perf: record index out of range");
  }
  let rt: Int = f.rec_types[i];
  if rt == PERF_RECORD_SAMPLE {
    return _err_int("perf: sample_id tail not applicable to SAMPLE records");
  }
  if attr_index < 0 || attr_index >= f.attr_types.len() {
    return _err_int("perf: attr index out of range");
  }
  let fl: Int = f.attr_flags[attr_index];
  if !_bit_at(fl, PERF_ATTR_FLAG_SAMPLE_ID_ALL) {
    return _err_int("perf: sample_id_all not set");
  }
  let bit = _sample_bit_of(field);
  if bit < 0 {
    return _err_int("perf: bad field selector");
  }
  let st: Int = f.attr_sample_types[attr_index];
  if !_bit_at(st, bit) {
    return _err_int("perf: sample_id field not present in sample_type");
  }
  let tail = _sample_id_size(st);
  if tail == 0 {
    return _err_int("perf: sample_id tail is empty");
  }
  let roff: Int = f.rec_offsets[i];
  let rsize: Int = f.rec_sizes[i];
  if rsize - PERF_RECORD_HEADER_SIZE < tail {
    return _err_int("perf: sample_id tail out of bounds");
  }
  var pos = roff + rsize - tail;
  if _bit_at(st, PERF_SAMPLE_BIT_TID) {
    if bit == PERF_SAMPLE_BIT_TID {
      if field == PERF_SAMPLE_FIELD_TID {
        return _ok_int(_rdu(data, pos + 4, 4));
      }
      return _ok_int(_rdu(data, pos, 4));
    }
    pos = pos + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_TIME) {
    if bit == PERF_SAMPLE_BIT_TIME { return _ok_int(_rdu(data, pos, 8)); }
    pos = pos + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_ID) {
    if bit == PERF_SAMPLE_BIT_ID { return _ok_int(_rdu(data, pos, 8)); }
    pos = pos + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_STREAM_ID) {
    if bit == PERF_SAMPLE_BIT_STREAM_ID { return _ok_int(_rdu(data, pos, 8)); }
    pos = pos + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_CPU) {
    if bit == PERF_SAMPLE_BIT_CPU { return _ok_int(_rdu(data, pos, 4)); }
    pos = pos + 8;
  }
  if _bit_at(st, PERF_SAMPLE_BIT_IDENTIFIER) {
    if bit == PERF_SAMPLE_BIT_IDENTIFIER { return _ok_int(_rdu(data, pos, 8)); }
    pos = pos + 8;
  }
  return _err_int("perf: sample_id field not present in sample_type");
}

// --------------------------------------------------
//  Span copies
// --------------------------------------------------

/// Copy the `size` bytes at `off` out of the buffer.
/// Err("perf: span out of bounds") when the span leaves the buffer; a
/// zero-size span at data.len() is allowed. Complexity: O(size).
pub fn perf_span_bytes(data: &Vec[UInt8], off: Int, size: Int) -> Result[Vec[UInt8], Str] {
  if !_span_ok(data, off, size) {
    return _err_bytes("perf: span out of bounds");
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < size {
    out.push(data[off + i]);
    i = i + 1;
  }
  return _ok_bytes(out);
}

/// Copy the `size` bytes at `off` out of the buffer as a Str (raw bytes; no
/// encoding validation). Err("perf: span out of bounds") when the span
/// leaves the buffer. Complexity: O(size).
pub fn perf_span_str(data: &Vec[UInt8], off: Int, size: Int) -> Result[Str, Str] {
  let br = perf_span_bytes(data, off, size);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let b: Vec[UInt8] = br.value;
  return _ok_str(Str::from_utf8(b));
}

// --------------------------------------------------
//  Feature payload helpers
// --------------------------------------------------

// Absolute offset of feature `feat`'s payload.
fn _feat_off(f: &PerfFile, feat: Int) -> Result[Int, Str] {
  let idx = _feat_index(f, feat);
  if idx < 0 {
    return _err_int("perf: feature not present");
  }
  let v: Int = f.feat_offsets[idx];
  return _ok_int(v);
}

// Size of feature `feat`'s payload.
fn _feat_size(f: &PerfFile, feat: Int) -> Result[Int, Str] {
  let idx = _feat_index(f, feat);
  if idx < 0 {
    return _err_int("perf: feature not present");
  }
  let v: Int = f.feat_sizes[idx];
  return _ok_int(v);
}

// Skip one perf_header_string_list ({nr u32, nr x {len u32, len bytes}})
// that starts at `pos` and must end at or before `end`; returns the offset
// just past the list.
fn _strlist_skip(data: &Vec[UInt8], pos: Int, end: Int) -> Result[Int, Str] {
  if pos < 0 || end < pos || end - pos < 4 {
    return _err_int("perf: string list out of bounds");
  }
  let nr = _rdu(data, pos, 4);
  var p = pos + 4;
  var i = 0;
  while i < nr {
    if p > end || end - p < 4 {
      return _err_int("perf: string list out of bounds");
    }
    let ln = _rdu(data, p, 4);
    let np = p + 4 + ln;
    if np > end {
      return _err_int("perf: string list out of bounds");
    }
    p = np;
    i = i + 1;
  }
  return _ok_int(p);
}

// Element count (the u32 nr word) of a perf_header_string_list at `pos`.
fn _strlist_count(data: &Vec[UInt8], pos: Int, end: Int) -> Result[Int, Str] {
  if pos < 0 || end < pos || end - pos < 4 {
    return _err_int("perf: string list out of bounds");
  }
  return _ok_int(_rdu(data, pos, 4));
}

// Offset of record `k` of a perf_header_string_list at `pos`.
fn _strlist_rec(data: &Vec[UInt8], pos: Int, end: Int, k: Int) -> Result[Int, Str] {
  let c = _strlist_count(data, pos, end);
  if !c.is_ok {
    return _err_int(c.error);
  }
  let nr: Int = c.value;
  if k < 0 || k >= nr {
    return _err_int("perf: index out of range");
  }
  var p = pos + 4;
  var i = 0;
  while i < k {
    if p > end || end - p < 4 {
      return _err_int("perf: string list out of bounds");
    }
    let ln = _rdu(data, p, 4);
    let np = p + 4 + ln;
    if np > end {
      return _err_int("perf: string list out of bounds");
    }
    p = np;
    i = i + 1;
  }
  return _ok_int(p);
}

// Field `sel` (a PERF_STRING_FIELD_* selector) of one perf_header_string
// record at `rec` whose containing payload ends at `end`. The stored `len`
// includes the terminating NUL.
fn _str_rec_field(data: &Vec[UInt8], rec: Int, end: Int, sel: Int) -> Result[Int, Str] {
  if rec < 0 || end < rec || end - rec < 4 {
    return _err_int("perf: feature payload out of bounds");
  }
  let ln = _rdu(data, rec, 4);
  if sel == PERF_STRING_FIELD_LEN {
    return _ok_int(ln);
  }
  if sel == PERF_STRING_FIELD_TEXT_OFFSET {
    return _ok_int(rec + 4);
  }
  if sel == PERF_STRING_FIELD_TEXT_SIZE {
    if rec + 4 + ln > end {
      return _err_int("perf: feature payload out of bounds");
    }
    return _ok_int(ln);
  }
  return _err_int("perf: bad field selector");
}

/// Copy the whole payload of feature `feat` out of the buffer.
/// Err("perf: feature not present") when its bit is clear and
/// Err("perf: span out of bounds") when the descriptor points outside the
/// buffer. Complexity: O(size).
pub fn perf_feature_bytes(data: &Vec[UInt8], f: &PerfFile, feat: Int) -> Result[Vec[UInt8], Str] {
  let o = _feat_off(f, feat);
  if !o.is_ok {
    return _err_bytes(o.error);
  }
  let s = _feat_size(f, feat);
  if !s.is_ok {
    return _err_bytes(s.error);
  }
  let off: Int = o.value;
  let sz: Int = s.value;
  return perf_span_bytes(data, off, sz);
}

/// Field `sel` (a PERF_STRING_FIELD_* selector) of the single
/// perf_header_string payload of feature `feat`. Intended for HOSTNAME,
/// OSRELEASE, VERSION and ARCH; any feature whose payload is one
/// perf_header_string works. Err("perf: feature not present") when the bit
/// is clear. Complexity: O(1).
pub fn perf_feature_string_field(data: &Vec[UInt8], f: &PerfFile, feat: Int, sel: Int) -> Result[Int, Str] {
  let o = _feat_off(f, feat);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let s = _feat_size(f, feat);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let off: Int = o.value;
  let end = off + s.value;
  return _str_rec_field(data, off, end, sel);
}

/// Number of strings in the CMDLINE feature's perf_header_string_list.
/// Err("perf: feature not present") when its bit is clear. Complexity O(1).
pub fn perf_feature_cmdline_count(data: &Vec[UInt8], f: &PerfFile) -> Result[Int, Str] {
  let o = _feat_off(f, PERF_FEATURE_CMDLINE);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let s = _feat_size(f, PERF_FEATURE_CMDLINE);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let off: Int = o.value;
  return _strlist_count(data, off, off + s.value);
}

/// Field `sel` (a PERF_STRING_FIELD_* selector) of CMDLINE string `k`.
/// Each element is a perf_header_string (u32 len including the NUL, then
/// the bytes). Complexity: O(k string lengths).
pub fn perf_feature_cmdline_field(data: &Vec[UInt8], f: &PerfFile, k: Int, sel: Int) -> Result[Int, Str] {
  let o = _feat_off(f, PERF_FEATURE_CMDLINE);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let s = _feat_size(f, PERF_FEATURE_CMDLINE);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let off: Int = o.value;
  let end = off + s.value;
  let r = _strlist_rec(data, off, end, k);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _str_rec_field(data, r.value, end, sel);
}

/// Count of strings in the CPU_TOPOLOGY sibling list `list_idx`
/// (PERF_TOPO_LIST_CORES or PERF_TOPO_LIST_THREADS).
/// Err("perf: bad field selector") for any other list. Complexity: O(cores).
pub fn perf_feature_topo_count(data: &Vec[UInt8], f: &PerfFile, list_idx: Int) -> Result[Int, Str] {
  if list_idx != PERF_TOPO_LIST_CORES && list_idx != PERF_TOPO_LIST_THREADS {
    return _err_int("perf: bad field selector");
  }
  let o = _feat_off(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let s = _feat_size(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let off: Int = o.value;
  let end = off + s.value;
  var pos = off;
  if list_idx == PERF_TOPO_LIST_THREADS {
    let sk = _strlist_skip(data, pos, end);
    if !sk.is_ok {
      return _err_int(sk.error);
    }
    pos = sk.value;
  }
  return _strlist_count(data, pos, end);
}

/// Field `sel` (a PERF_STRING_FIELD_* selector) of string `k` of the
/// CPU_TOPOLOGY sibling list `list_idx` (PERF_TOPO_LIST_CORES or
/// PERF_TOPO_LIST_THREADS). Complexity: O(k string lengths).
pub fn perf_feature_topo_string_field(data: &Vec[UInt8], f: &PerfFile, list_idx: Int, k: Int, sel: Int) -> Result[Int, Str] {
  if list_idx != PERF_TOPO_LIST_CORES && list_idx != PERF_TOPO_LIST_THREADS {
    return _err_int("perf: bad field selector");
  }
  let o = _feat_off(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let s = _feat_size(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let off: Int = o.value;
  let end = off + s.value;
  var pos = off;
  if list_idx == PERF_TOPO_LIST_THREADS {
    let sk = _strlist_skip(data, pos, end);
    if !sk.is_ok {
      return _err_int(sk.error);
    }
    pos = sk.value;
  }
  let r = _strlist_rec(data, pos, end, k);
  if !r.is_ok {
    return _err_int(r.error);
  }
  return _str_rec_field(data, r.value, end, sel);
}

// Offset just past the CPU_TOPOLOGY cores and threads string lists: the
// start of the per-cpu {core_id u32, socket_id u32} entries.
fn _topo_after_lists(data: &Vec[UInt8], f: &PerfFile) -> Result[Int, Str] {
  let o = _feat_off(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let s = _feat_size(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let off: Int = o.value;
  let end = off + s.value;
  let c = _strlist_skip(data, off, end);
  if !c.is_ok {
    return _err_int(c.error);
  }
  let t = _strlist_skip(data, c.value, end);
  if !t.is_ok {
    return _err_int(t.error);
  }
  return _ok_int(t.value);
}

/// Number of per-cpu {core_id, socket_id} entries in the CPU_TOPOLOGY
/// payload (revision 2; the later die revision is not decoded and any
/// trailing bytes are ignored). Complexity: O(cores + threads).
pub fn perf_feature_cpu_entry_count(data: &Vec[UInt8], f: &PerfFile) -> Result[Int, Str] {
  let p = _topo_after_lists(data, f);
  if !p.is_ok {
    return _err_int(p.error);
  }
  let s = _feat_size(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let o = _feat_off(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let end = o.value + s.value;
  let base: Int = p.value;
  if end < base {
    return _err_int("perf: feature payload out of bounds");
  }
  return _ok_int((end - base) / 8);
}

/// Field `field` (PERF_CPU_ENTRY_FIELD_CORE_ID or
/// PERF_CPU_ENTRY_FIELD_SOCKET_ID) of CPU_TOPOLOGY entry `k`.
/// Complexity: O(cores + threads).
pub fn perf_feature_cpu_entry_field(data: &Vec[UInt8], f: &PerfFile, k: Int, field: Int) -> Result[Int, Str] {
  if field != PERF_CPU_ENTRY_FIELD_CORE_ID && field != PERF_CPU_ENTRY_FIELD_SOCKET_ID {
    return _err_int("perf: bad field selector");
  }
  let c = perf_feature_cpu_entry_count(data, f);
  if !c.is_ok {
    return _err_int(c.error);
  }
  let n: Int = c.value;
  if k < 0 || k >= n {
    return _err_int("perf: index out of range");
  }
  let p = _topo_after_lists(data, f);
  if !p.is_ok {
    return _err_int(p.error);
  }
  let s = _feat_size(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let o = _feat_off(f, PERF_FEATURE_CPU_TOPOLOGY);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let end = o.value + s.value;
  let eoff: Int = p.value + k * 8;
  if eoff + 8 > end {
    return _err_int("perf: feature payload out of bounds");
  }
  if field == PERF_CPU_ENTRY_FIELD_CORE_ID {
    return _ok_int(_rdu(data, eoff, 4));
  }
  return _ok_int(_rdu(data, eoff + 4, 4));
}

/// Number of records in the BUILD_ID feature payload: a u32 count followed
/// by that many records of {pid u32, build_id bytes}. The build-id width is
/// caller-supplied to perf_feature_build_id_field. Complexity: O(1).
pub fn perf_feature_build_id_count(data: &Vec[UInt8], f: &PerfFile) -> Result[Int, Str] {
  let o = _feat_off(f, PERF_FEATURE_BUILD_ID);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let s = _feat_size(f, PERF_FEATURE_BUILD_ID);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let off: Int = o.value;
  let sz: Int = s.value;
  if sz < 4 {
    return _err_int("perf: build_id feature truncated");
  }
  return _ok_int(_rdu(data, off, 4));
}

/// Field `field` (a PERF_FBI_FIELD_* selector) of BUILD_ID feature record
/// `k`, whose record stride is 4 + `bid_size` (`bid_size` 1..64: 20 for a
/// SHA1 id, 24 for perf's padded 20-byte default, 32 for a SHA256 id).
/// Err("perf: bad build id size") for an out-of-range width and
/// Err("perf: build_id feature truncated") when the declared records do not
/// fit the payload. Complexity: O(1).
pub fn perf_feature_build_id_field(data: &Vec[UInt8], f: &PerfFile, k: Int, bid_size: Int, field: Int) -> Result[Int, Str] {
  if bid_size < PERF_BUILD_ID_MIN || bid_size > PERF_BUILD_ID_MAX {
    return _err_int("perf: bad build id size");
  }
  let c = perf_feature_build_id_count(data, f);
  if !c.is_ok {
    return _err_int(c.error);
  }
  let n: Int = c.value;
  if k < 0 || k >= n {
    return _err_int("perf: index out of range");
  }
  let o = _feat_off(f, PERF_FEATURE_BUILD_ID);
  if !o.is_ok {
    return _err_int(o.error);
  }
  let s = _feat_size(f, PERF_FEATURE_BUILD_ID);
  if !s.is_ok {
    return _err_int(s.error);
  }
  let off: Int = o.value;
  let sz: Int = s.value;
  let stride = 4 + bid_size;
  if 4 + n * stride > sz {
    return _err_int("perf: build_id feature truncated");
  }
  let rec = off + 4 + k * stride;
  if field == PERF_FBI_FIELD_PID {
    return _ok_int(_rdu(data, rec, 4));
  }
  if field == PERF_FBI_FIELD_RECORD_OFFSET {
    return _ok_int(rec);
  }
  if field == PERF_FBI_FIELD_BUILD_ID_OFFSET {
    return _ok_int(rec + 4);
  }
  if field == PERF_FBI_FIELD_BUILD_ID_SIZE {
    return _ok_int(bid_size);
  }
  return _err_int("perf: bad field selector");
}
