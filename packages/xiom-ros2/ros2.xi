// XIOM -- xiom.ros2: ROS 2 client-library (rcl) bindings via dynamic loader.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN DECISION (robotics sector): **system-library path**, not vendored --
// the xiom.ssl/xiom.openssl pattern applied to ROS 2's rcl. A ROS 2 install
// is a large, distro-versioned runtime (rcl + rmw + DDS); the loader tries
// the common librcl sonames in order and the suite reports SKIP when none is
// present, so CI without ROS 2 stays green. Nothing is vendored and no C is
// shipped: all entry points are fn-pointer casts over `xiom.ffi.dl`.
//
// All XIOM `unsafe`/FFI lives in this single module (G5). Out-parameters are
// XIOM-owned zeroed slots (`Vec[UInt8].with_len`), read byte-indexed
// (B-24 discipline); handles and resolved symbols are Ints.
//
// Classification:
//   ROS2_LOAD_ABSENT -> no candidate librcl soname loaded -> SKIP
//   ROS2_LOAD_ABI    -> a candidate loaded but entry points are missing -> FAIL
//   ROS2_ABI_HOST    -> host ABI cannot pass by-value aggregates (see below)
//   operational failures -> typed Ros2Error { kind, ret, message }
//
// ABI channel (probe evidence: docs/repro/bindings-pilot/ros2-abi/):
//   * rcl takes `rcl_allocator_t` BY VALUE in rcl_init_options_init,
//     rcl_clock_init, rcl_timer_init(2), rcl_wait_set_init. XIOM record
//     by-value through an fn-cast call FAULTS at v0.64.5 (B-33 finding), so
//     every by-value parameter is passed with the **pointer-pretend** shape:
//     the fn-cast declares the parameter as `*UInt8` and receives the address
//     of an XIOM-owned 40-byte allocator slot. That is exactly what the MS
//     x64 and AAPCS64 ABIs do for >16-byte aggregates (by reference to a
//     caller copy); it was verified locally against a real DLL for the exact
//     1/2/3/7/9-argument shapes used below (165/17036/969/2166/8186 exact).
//     x86-64 System V (Linux x86-64) passes such aggregates in MEMORY class
//     instead -> typed ROS2_ABI_HOST refusal at load; live legs are Windows
//     x64 (MS ABI) and AArch64/ARM (AAPCS by-ref copy, to re-verify on the Pi).
//   * Slot I/O uses the xiom.ffi C-side byte helpers (ptr_write/read_*_le):
//     XIOM `>>`/`&`/`/` miscompile Int values >= 2^31 on this pin (B-29), so
//     real addresses are never split with bitops.
//   * Struct-returning helpers (rcl_get_zero_initialized_*,
//     rcl_*_get_default_options, rcl_get_error_string) are NOT called: zero
//     initialization is by construction (zeroed slots) and option structs
//     are fabricated from the pinned headers.
//
// ABI layout pin (PROVENANCE.md): rcl rolling @ e5754f0d, rmw @ 4158e1ed,
// rcutils @ 0f55f24e. Transcribed offsets (x64, all targets): allocator =
// 5 pointers @0 {allocate, deallocate, reallocate, zero_allocate, state};
// rmw_qos_profile_t = 88 bytes {history i32 @0, depth u64 @8, reliability
// i32 @16, durability i32 @20, deadline {u64,u64} @24, lifespan @40,
// liveliness i32 @56, lease {u64,u64} @64, avoid_namespace u8 @80};
// pub/sub options = {qos @0, allocator @88, rmw options zeroed}; node
// options = {allocator @0, rest zeroed}. Verified across humble/jazzy/
// rolling header diffs (qos-first order holds; wait-set layout identical).
//
// Surface (SPEC.md): loader, context, node, publisher, subscription, clock,
// timers, wait sets, callback-free spin, type-support resolution.
// Callback bridging does not exist in the FFI (lane survey: no shipped
// package passes an XIOM function pointer to C), so subscriptions are
// polled via rcl_take on caller-owned message buffers, timers are created
// with a NULL callback (rcl documents "no callback is fired ... this
// function should still be called" for rcl_timer_call), and spin_once
// waits + reports which entities fired instead of dispatching callbacks.

module xiom.ros2

use xiom.ffi.dl;
use xiom.ffi;
use xiom.platform;

// =========================================================================
// Classification and error kinds
// =========================================================================

pub const ROS2_LOAD_ABSENT: Int = 0;   // no candidate loaded -> SKIP
pub const ROS2_LOAD_ABI: Int = 1;      // entry points missing -> FAIL
pub const ROS2_ABI_HOST: Int = 2;      // host ABI cannot pass by-value aggregates
pub const ROS2_RET_FAIL: Int = 3;      // rcl returned a non-OK ret code
pub const ROS2_ARG_INVALID: Int = 4;   // invalid local argument

// =========================================================================
// rcl_ret_t catalog (oracle: rcl/types.h = rmw/ret_types.h + rcl 1XX-9XX)
// =========================================================================

pub const RCL_RET_OK: Int = 0;
pub const RCL_RET_ERROR: Int = 1;
pub const RCL_RET_TIMEOUT: Int = 2;
pub const RCL_RET_UNSUPPORTED: Int = 3;
pub const RCL_RET_BAD_ALLOC: Int = 10;
pub const RCL_RET_INVALID_ARGUMENT: Int = 11;
pub const RCL_RET_INCORRECT_RMW_IMPLEMENTATION: Int = 12;
pub const RCL_RET_ALREADY_INIT: Int = 100;
pub const RCL_RET_NOT_INIT: Int = 101;
pub const RCL_RET_MISMATCHED_RMW_ID: Int = 102;
pub const RCL_RET_TOPIC_NAME_INVALID: Int = 103;
pub const RCL_RET_SERVICE_NAME_INVALID: Int = 104;
pub const RCL_RET_UNKNOWN_SUBSTITUTION: Int = 105;
pub const RCL_RET_ALREADY_SHUTDOWN: Int = 106;
pub const RCL_RET_NOT_FOUND: Int = 107;
pub const RCL_RET_NODE_INVALID: Int = 200;
pub const RCL_RET_NODE_INVALID_NAME: Int = 201;
pub const RCL_RET_NODE_INVALID_NAMESPACE: Int = 202;
pub const RCL_RET_PUBLISHER_INVALID: Int = 300;
pub const RCL_RET_SUBSCRIPTION_INVALID: Int = 400;
pub const RCL_RET_SUBSCRIPTION_TAKE_FAILED: Int = 401;
pub const RCL_RET_TIMER_INVALID: Int = 800;
pub const RCL_RET_TIMER_CANCELED: Int = 801;
pub const RCL_RET_WAIT_SET_INVALID: Int = 900;
pub const RCL_RET_WAIT_SET_EMPTY: Int = 901;
pub const RCL_RET_WAIT_SET_FULL: Int = 902;

// =========================================================================
// QoS constants (oracle: rmw/types.h enums + qos_profiles.h presets)
// =========================================================================

pub const ROS2_QOS_DEFAULT: Int = 0;         // KEEP_LAST 10 RELIABLE VOLATILE
pub const ROS2_QOS_SENSOR_DATA: Int = 1;     // KEEP_LAST 5 BEST_EFFORT VOLATILE
pub const ROS2_QOS_SYSTEM_DEFAULT: Int = 2;  // all SYSTEM_DEFAULT / 0
pub const ROS2_QOS_PARAMETERS: Int = 3;      // KEEP_LAST 1000 RELIABLE VOLATILE

pub const ROS2_HISTORY_SYSTEM_DEFAULT: Int = 0;
pub const ROS2_HISTORY_KEEP_LAST: Int = 1;
pub const ROS2_HISTORY_KEEP_ALL: Int = 2;
pub const ROS2_HISTORY_UNKNOWN: Int = 3;

pub const ROS2_RELIABILITY_SYSTEM_DEFAULT: Int = 0;
pub const ROS2_RELIABILITY_RELIABLE: Int = 1;
pub const ROS2_RELIABILITY_BEST_EFFORT: Int = 2;
pub const ROS2_RELIABILITY_UNKNOWN: Int = 3;

pub const ROS2_DURABILITY_SYSTEM_DEFAULT: Int = 0;
pub const ROS2_DURABILITY_TRANSIENT_LOCAL: Int = 1;
pub const ROS2_DURABILITY_VOLATILE: Int = 2;
pub const ROS2_DURABILITY_UNKNOWN: Int = 3;

pub const ROS2_LIVELINESS_SYSTEM_DEFAULT: Int = 0;
pub const ROS2_LIVELINESS_AUTOMATIC: Int = 1;
pub const ROS2_LIVELINESS_MANUAL_BY_TOPIC: Int = 3;
pub const ROS2_LIVELINESS_UNKNOWN: Int = 4;

// =========================================================================
// Clock constants (oracle: rcl/time.h rcl_clock_type_t)
// =========================================================================

pub const RCL_CLOCK_UNINITIALIZED: Int = 0;
pub const RCL_ROS_TIME: Int = 1;
pub const RCL_SYSTEM_TIME: Int = 2;
pub const RCL_STEADY_TIME: Int = 3;

// =========================================================================
// Layout constants (transcribed; see header)
// =========================================================================

/// sizeof(rcl_allocator_t) = 5 pointers.
pub const ROS2_ALLOC_SIZE: Int = 40;
/// sizeof(rmw_qos_profile_t).
pub const ROS2_QOS_SIZE: Int = 88;
/// Offset of `allocator` inside rcl_publisher_options_t /
/// rcl_subscription_options_t (qos is first).
pub const ROS2_PUBSUB_ALLOC_OFF: Int = 88;
/// Slot capacity for option structs (actual <= 160).
pub const ROS2_OPTIONS_SLOT: Int = 256;
/// Slot capacity for the wait set struct (actual 104).
pub const ROS2_WAIT_SET_SLOT: Int = 128;
/// Slot capacity for the context struct (actual 24).
pub const ROS2_CONTEXT_SLOT: Int = 64;
/// Slot capacity for node (16), publisher/subscription/timer (8), clock (40),
/// init options (8): 64 covers all fixed-size handles used here.
pub const ROS2_HANDLE_SLOT: Int = 64;
/// Slot for one u64 out-value.
pub const ROS2_OUT_SLOT: Int = 8;

// =========================================================================
// Types
// =========================================================================

/// A typed ros2 failure: load classification or operational error.
pub type Ros2Error = {
  kind: Int;
  ret: Int;
  message: Str;
}

/// One loaded librcl and its resolved entry points plus the C-runtime
/// companion used to fabricate the documented default allocator.
/// Owned by the caller; release with `ros2_close`.
pub type Ros2Library = {
  handle: Int;
  soname: Str;
  libc_handle: Int;
  libc_soname: Str;
  has_timer_init2: Bool;
  p_rcl_init: Int;
  p_rcl_shutdown: Int;
  p_rcl_context_fini: Int;
  p_rcl_context_is_valid: Int;
  p_rcl_context_get_instance_id: Int;
  p_rcl_context_get_domain_id: Int;
  p_rcl_init_options_init: Int;
  p_rcl_init_options_set_domain_id: Int;
  p_rcl_init_options_fini: Int;
  p_rcl_node_init: Int;
  p_rcl_node_fini: Int;
  p_rcl_node_get_name: Int;
  p_rcl_node_get_namespace: Int;
  p_rcl_publisher_init: Int;
  p_rcl_publisher_fini: Int;
  p_rcl_publish: Int;
  p_rcl_subscription_init: Int;
  p_rcl_subscription_fini: Int;
  p_rcl_take: Int;
  p_rcl_clock_init: Int;
  p_rcl_clock_fini: Int;
  p_rcl_clock_get_now: Int;
  p_rcl_timer_init: Int;
  p_rcl_timer_init2: Int;
  p_rcl_timer_fini: Int;
  p_rcl_timer_call: Int;
  p_rcl_timer_is_ready: Int;
  p_rcl_timer_get_period: Int;
  p_rcl_timer_get_time_until_next_call: Int;
  p_rcl_timer_reset: Int;
  p_rcl_timer_cancel: Int;
  p_rcl_timer_is_canceled: Int;
  p_rcl_wait_set_init: Int;
  p_rcl_wait_set_fini: Int;
  p_rcl_wait_set_clear: Int;
  p_rcl_wait_set_resize: Int;
  p_rcl_wait_set_add_subscription: Int;
  p_rcl_wait_set_add_timer: Int;
  p_rcl_wait_set_is_valid: Int;
  p_rcl_wait: Int;
  p_malloc: Int;
  p_realloc: Int;
  p_calloc: Int;
  p_free: Int;
}

/// An initialized rcl context (rcl_context_t in an XIOM-owned slot).
pub type Ros2Context = {
  slot: Vec[UInt8];
}

/// A ROS node (rcl_node_t slot; valid while the context lives).
pub type Ros2Node = {
  slot: Vec[UInt8];
}

/// A publisher (rcl_publisher_t slot; owned options are consumed at init).
pub type Ros2Publisher = {
  slot: Vec[UInt8];
}

/// A subscription (rcl_subscription_t slot).
pub type Ros2Subscription = {
  slot: Vec[UInt8];
}

/// A clock (rcl_clock_t slot; must outlive timers created on it).
pub type Ros2Clock = {
  slot: Vec[UInt8];
}

/// A timer; `own_clock` is non-empty when ros2_timer_init created a private
/// steady clock (fini releases it with the timer).
pub type Ros2Timer = {
  slot: Vec[UInt8];
  own_clock: Vec[UInt8];
}

/// A wait set (rcl_wait_set_t slot).
pub type Ros2WaitSet = {
  slot: Vec[UInt8];
}

/// A resolved rosidl type support: `addr` is the
/// rosidl_message_type_support_t* handle; `handle` keeps the producing
/// library loaded.
pub type Ros2TypeSupport = {
  addr: Int;
  handle: Int;
  soname: Str;
}

/// Callback-free spin outcome for one spin_once call.
pub type Ros2SpinResult = {
  sub_fired: Vec[Bool];
  timer_fired: Vec[Bool];
  timed_out: Bool;
  wait_ret: Int;
}

// =========================================================================
// Slot helpers (XIOM-owned zeroed buffers; byte-indexed, B-24 discipline)
// =========================================================================

/// n zero bytes in an XIOM-owned slot.
/// Complexity: O(n).
fn slot(n: Int) -> Vec[UInt8]
  requires: n > 0
  requires: n <= 65536
{
  return Vec[UInt8].with_len(n);
}

fn wr_u64(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: off + 8 <= buf.len()
{
  // C-side byte handling (xiom.ffi recipe): XIOM `>>`/`&` miscompiles Int
  // values >= 2^31 on the v0.64.5 pin (B-29) -- real addresses MUST NOT be
  // split with bitops here.
  unsafe {
    ffi.ptr_write_u64_le(&buf[off] as *UInt8, v);
  }
}

fn wr_u32(buf: &mut Vec[UInt8], off: Int, v: Int)
  requires: off >= 0
  requires: off + 4 <= buf.len()
{
  unsafe {
    ffi.ptr_write_u32_le(&buf[off] as *UInt8, v);
  }
}

/// Byte-indexed little-endian u64 read from an owned slot (public: it is the
/// documented way consumers probe fabricated option slots). C-side load
/// (B-29: no XIOM bitops on values >= 2^31).
/// Complexity: O(1).
pub fn ros2_slot_u64(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off + 8 <= buf.len()
{
  unsafe {
    return ffi.ptr_read_u64_le(&buf[off] as *UInt8);
  }
}

/// Byte-indexed little-endian u32 read from an owned slot.
/// Complexity: O(1).
pub fn ros2_slot_u32(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off + 4 <= buf.len()
{
  unsafe {
    return ffi.ptr_read_u32_le(&buf[off] as *UInt8);
  }
}

/// Byte-indexed u8 read from an owned slot.
/// Complexity: O(1).
pub fn ros2_slot_u8(buf: &Vec[UInt8], off: Int) -> Int
  requires: off >= 0
  requires: off < buf.len()
{
  unsafe {
    return ffi.ptr_read_u8(&buf[off] as *UInt8);
  }
}

/// Address of an XIOM-owned slot as an Int (for handle vectors handed to
/// ros2_spin_once).
/// Complexity: O(1).
pub fn ros2_slot_ptr(v: &Vec[UInt8]) -> Int
  requires: v.len() > 0
{
  unsafe { return &v[0] as *UInt8 as Int; }
}

/// Local Int-to-Str (lane pattern: avoids cross-module convert resolution
/// traps inside confined modules; BINDINGS-COMPILER-FINDINGS).
/// Complexity: O(digits).
fn int_to_str(n: Int) -> Str
  requires: true
{
  if n == 0 { return "0"; }
  var num = n;
  var neg = false;
  if num < 0 { neg = true; num = 0 - num; }
  var out = "";
  while num > 0 {
    let d = num % 10;
    var ds = "0";
    if d == 1 { ds = "1"; }
    elif d == 2 { ds = "2"; }
    elif d == 3 { ds = "3"; }
    elif d == 4 { ds = "4"; }
    elif d == 5 { ds = "5"; }
    elif d == 6 { ds = "6"; }
    elif d == 7 { ds = "7"; }
    elif d == 8 { ds = "8"; }
    elif d == 9 { ds = "9"; }
    out = ds + out;
    num = num / 10;
  }
  if neg { return "-" + out; }
  return out;
}

/// Normalize a raw register value holding a 32-bit rcl_ret_t. Identity on
/// purpose: x64/AArch64 32-bit register writes zero-extend, and masking with
/// `& 0xFFFFFFFF` would hit the B-29 miscompile for values >= 2^31.
/// Complexity: O(1).
fn ret_of(raw: Int) -> Int
  requires: true
{
  return raw;
}

fn make_err(kind: Int, ret: Int, message: Str) -> Ros2Error
  requires: kind >= 0
  requires: message.len() > 0
{
  return Ros2Error{ kind: kind; ret: ret; message: message };
}

/// Typed operational failure from a ret code.
/// Complexity: O(len).
fn ret_err(op: Str, ret: Int) -> Ros2Error
  requires: op.len() > 0
{
  return Ros2Error{
    kind: ROS2_RET_FAIL;
    ret: ret;
    message: op + " failed: " + ros2_ret_name(ret) + " (" + int_to_str(ret) + ")",
  };
}

// =========================================================================
// Human names (pure; suite asserts the catalog)
// =========================================================================

/// Human name for an rcl_ret_t value; "unknown" otherwise.
/// Complexity: O(1).
pub fn ros2_ret_name(ret: Int) -> Str
  requires: true
{
  if ret == RCL_RET_OK { return "ok"; }
  if ret == RCL_RET_ERROR { return "error"; }
  if ret == RCL_RET_TIMEOUT { return "timeout"; }
  if ret == RCL_RET_UNSUPPORTED { return "unsupported"; }
  if ret == RCL_RET_BAD_ALLOC { return "bad alloc"; }
  if ret == RCL_RET_INVALID_ARGUMENT { return "invalid argument"; }
  if ret == RCL_RET_INCORRECT_RMW_IMPLEMENTATION { return "incorrect rmw implementation"; }
  if ret == RCL_RET_ALREADY_INIT { return "already init"; }
  if ret == RCL_RET_NOT_INIT { return "not init"; }
  if ret == RCL_RET_MISMATCHED_RMW_ID { return "mismatched rmw id"; }
  if ret == RCL_RET_TOPIC_NAME_INVALID { return "topic name invalid"; }
  if ret == RCL_RET_SERVICE_NAME_INVALID { return "service name invalid"; }
  if ret == RCL_RET_UNKNOWN_SUBSTITUTION { return "unknown substitution"; }
  if ret == RCL_RET_ALREADY_SHUTDOWN { return "already shutdown"; }
  if ret == RCL_RET_NOT_FOUND { return "not found"; }
  if ret == RCL_RET_NODE_INVALID { return "node invalid"; }
  if ret == RCL_RET_NODE_INVALID_NAME { return "node name invalid"; }
  if ret == RCL_RET_NODE_INVALID_NAMESPACE { return "node namespace invalid"; }
  if ret == RCL_RET_PUBLISHER_INVALID { return "publisher invalid"; }
  if ret == RCL_RET_SUBSCRIPTION_INVALID { return "subscription invalid"; }
  if ret == RCL_RET_SUBSCRIPTION_TAKE_FAILED { return "take failed"; }
  if ret == RCL_RET_TIMER_INVALID { return "timer invalid"; }
  if ret == RCL_RET_TIMER_CANCELED { return "timer canceled"; }
  if ret == RCL_RET_WAIT_SET_INVALID { return "wait set invalid"; }
  if ret == RCL_RET_WAIT_SET_EMPTY { return "wait set empty"; }
  if ret == RCL_RET_WAIT_SET_FULL { return "wait set full"; }
  return "unknown";
}

/// Human name for a load-classification kind.
/// Complexity: O(1).
pub fn ros2_error_kind_name(kind: Int) -> Str
  requires: true
{
  if kind == ROS2_LOAD_ABSENT { return "absent"; }
  if kind == ROS2_LOAD_ABI { return "abi"; }
  if kind == ROS2_ABI_HOST { return "host-abi"; }
  if kind == ROS2_RET_FAIL { return "rcl-ret"; }
  if kind == ROS2_ARG_INVALID { return "arg"; }
  return "unknown";
}

/// Human name for a QoS preset id.
/// Complexity: O(1).
pub fn ros2_qos_preset_name(id: Int) -> Str
  requires: true
{
  if id == ROS2_QOS_DEFAULT { return "default"; }
  if id == ROS2_QOS_SENSOR_DATA { return "sensor-data"; }
  if id == ROS2_QOS_SYSTEM_DEFAULT { return "system-default"; }
  if id == ROS2_QOS_PARAMETERS { return "parameters"; }
  return "unknown";
}

// =========================================================================
// ABI host gate
// =========================================================================

/// Whether this host's C ABI passes >16-byte aggregates by reference to a
/// copy (MS x64 / AArch64 / ARM), which is what the pointer-pretend channel
/// needs. x86-64 System V (non-Windows) fails the gate: such aggregates are
/// MEMORY class there.
/// Complexity: O(1).
pub fn ros2_abi_host_ok() -> Bool
  requires: true
{
  if platform.is_windows() { return true; }
  let a = platform.arch_name();
  if a == "x86_64" { return false; }
  if a == "amd64" { return false; }
  return true;
}

// =========================================================================
// Pure builders (fabrication of the documented default structures)
// =========================================================================

/// Build the documented default allocator (rcutils/allocator.h: wraps
/// malloc/free/realloc/calloc with `state = NULL`) from four addresses.
/// Complexity: O(1).
pub fn ros2_allocator_build(a_malloc: Int, a_free: Int, a_realloc: Int, a_calloc: Int) -> Vec[UInt8]
  requires: a_malloc != 0
  requires: a_free != 0
  requires: a_realloc != 0
  requires: a_calloc != 0
{
  var buf = slot(ROS2_ALLOC_SIZE);
  wr_u64(&mut buf, 0, a_malloc);
  wr_u64(&mut buf, 8, a_free);
  wr_u64(&mut buf, 16, a_realloc);
  wr_u64(&mut buf, 24, a_calloc);
  wr_u64(&mut buf, 32, 0);
  return buf;
}

/// Write an rmw_qos_profile_t into `buf` at `off` for a preset id.
/// deadline/lifespan/liveliness-lease stay RMW_DURATION_UNSPECIFIED {0,0}.
/// Complexity: O(1).
pub fn ros2_qos_write(buf: &mut Vec[UInt8], off: Int, qos_id: Int) -> Result[Unit, Str]
  requires: off >= 0
  requires: off + ROS2_QOS_SIZE <= buf.len()
{
  var history = ROS2_HISTORY_SYSTEM_DEFAULT;
  var depth = 0;
  var reliability = ROS2_RELIABILITY_SYSTEM_DEFAULT;
  var durability = ROS2_DURABILITY_SYSTEM_DEFAULT;
  if qos_id == ROS2_QOS_DEFAULT {
    history = ROS2_HISTORY_KEEP_LAST; depth = 10;
    reliability = ROS2_RELIABILITY_RELIABLE; durability = ROS2_DURABILITY_VOLATILE;
  } elif qos_id == ROS2_QOS_SENSOR_DATA {
    history = ROS2_HISTORY_KEEP_LAST; depth = 5;
    reliability = ROS2_RELIABILITY_BEST_EFFORT; durability = ROS2_DURABILITY_VOLATILE;
  } elif qos_id == ROS2_QOS_SYSTEM_DEFAULT {
    history = ROS2_HISTORY_SYSTEM_DEFAULT; depth = 0;
    reliability = ROS2_RELIABILITY_SYSTEM_DEFAULT; durability = ROS2_DURABILITY_SYSTEM_DEFAULT;
  } elif qos_id == ROS2_QOS_PARAMETERS {
    history = ROS2_HISTORY_KEEP_LAST; depth = 1000;
    reliability = ROS2_RELIABILITY_RELIABLE; durability = ROS2_DURABILITY_VOLATILE;
  } else {
    return Err("qos: unknown preset " + int_to_str(qos_id));
  }
  wr_u32(buf, off + 0, history);
  wr_u64(buf, off + 8, depth);
  wr_u32(buf, off + 16, reliability);
  wr_u32(buf, off + 20, durability);
  wr_u32(buf, off + 56, ROS2_LIVELINESS_SYSTEM_DEFAULT);
  buf[off + 80] = 0 as UInt8;
  return Ok(());
}

/// Write an explicit QoS block (custom policies). deadline/lifespan/lease
/// stay UNSPECIFIED; `avoid_namespace` 0/1.
/// Complexity: O(1).
pub fn ros2_qos_write_custom(
  buf: &mut Vec[UInt8], off: Int, history: Int, depth: Int,
  reliability: Int, durability: Int, liveliness: Int, avoid_namespace: Int
) -> Result[Unit, Str]
  requires: off >= 0
  requires: off + ROS2_QOS_SIZE <= buf.len()
  requires: history >= 0
  requires: depth >= 0
{
  if history == 0 && depth != 0 {
    return Err("qos: SYSTEM_DEFAULT history requires depth 0");
  }
  if history == 1 && depth == 0 {
    return Err("qos: KEEP_LAST requires depth > 0");
  }
  wr_u32(buf, off + 0, history);
  wr_u64(buf, off + 8, depth);
  wr_u32(buf, off + 16, reliability);
  wr_u32(buf, off + 20, durability);
  wr_u32(buf, off + 56, liveliness);
  buf[off + 80] = (avoid_namespace & 255) as UInt8;
  return Ok(());
}

/// Fabricate rcl_node_options_t: allocator @0, everything else zeroed
/// (use_global_arguments=false, enable_rosout=false, empty arguments).
/// Complexity: O(1).
pub fn ros2_node_options_build(alloc: &Vec[UInt8]) -> Vec[UInt8]
  requires: alloc.len() >= ROS2_ALLOC_SIZE
{
  var buf = slot(ROS2_OPTIONS_SLOT);
  var i = 0;
  while i < ROS2_ALLOC_SIZE {
    buf[i] = alloc[i];
    i = i + 1;
  }
  return buf;
}

/// Fabricate rcl_publisher_options_t or rcl_subscription_options_t (same
/// leading layout): qos @0, allocator @88, rmw options zeroed.
/// Complexity: O(1).
pub fn ros2_pubsub_options_build(qos_id: Int, alloc: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  requires: alloc.len() >= ROS2_ALLOC_SIZE
{
  var buf = slot(ROS2_OPTIONS_SLOT);
  let q = ros2_qos_write(&mut buf, 0, qos_id);
  if !q.is_ok { return Err(q.error); }
  var i = 0;
  while i < ROS2_ALLOC_SIZE {
    buf[ROS2_PUBSUB_ALLOC_OFF + i] = alloc[i];
    i = i + 1;
  }
  return Ok(buf);
}

// =========================================================================
// Loader (multi-soname)
// =========================================================================

fn sym_or(handle: Int, name: Str) -> Result[Int, Str]
  requires: handle != 0
  requires: name.len() > 0
{
  let a = dl.dl_sym(handle, name);
  if !a.is_ok { return Err(name + ": " + a.error); }
  return Ok(a.value);
}

fn fail_load(handle: Int, message: Str) -> Result[Ros2Library, Ros2Error]
  requires: handle != 0
  requires: message.len() > 0
{
  var ig = dl.dl_close(handle);
  return Err(Ros2Error{ kind: ROS2_LOAD_ABI; ret: -1; message: message });
}

fn fail_load2(handle: Int, chandle: Int, message: Str) -> Result[Ros2Library, Ros2Error]
  requires: handle != 0
  requires: chandle != 0
  requires: message.len() > 0
{
  var ig1 = dl.dl_close(chandle);
  var ig2 = dl.dl_close(handle);
  return Err(Ros2Error{ kind: ROS2_LOAD_ABI; ret: -1; message: message });
}

/// Soname candidates tried in order (message text).
/// Complexity: O(1).
pub fn ros2_sonames() -> Str
  requires: true
{
  return "librcl.so, rcl.dll, librcl.dylib";
}

fn try_load(soname: Str) -> Result[Ros2Library, Ros2Error]
  requires: soname.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    // Not this candidate: report ABSENT so the caller can try the next one.
    return Err(Ros2Error{ kind: ROS2_LOAD_ABSENT; ret: -1; message: h.error });
  }
  let handle: Int = h.value;

  if !ros2_abi_host_ok() {
    var ig0 = dl.dl_close(handle);
    return Err(Ros2Error{
      kind: ROS2_ABI_HOST; ret: -1;
      message: "librcl loaded but host ABI cannot pass by-value aggregates "
        + "(x86-64 System V); supported live hosts: Windows x64, AArch64/ARM",
    });
  }

  let n01 = sym_or(handle, "rcl_init");
  if !n01.is_ok { return fail_load(handle, n01.error); }
  let n02 = sym_or(handle, "rcl_shutdown");
  if !n02.is_ok { return fail_load(handle, n02.error); }
  let n03 = sym_or(handle, "rcl_context_fini");
  if !n03.is_ok { return fail_load(handle, n03.error); }
  let n04 = sym_or(handle, "rcl_context_is_valid");
  if !n04.is_ok { return fail_load(handle, n04.error); }
  let n05 = sym_or(handle, "rcl_context_get_instance_id");
  if !n05.is_ok { return fail_load(handle, n05.error); }
  let n06 = sym_or(handle, "rcl_context_get_domain_id");
  if !n06.is_ok { return fail_load(handle, n06.error); }
  let n07 = sym_or(handle, "rcl_init_options_init");
  if !n07.is_ok { return fail_load(handle, n07.error); }
  let n08 = sym_or(handle, "rcl_init_options_set_domain_id");
  if !n08.is_ok { return fail_load(handle, n08.error); }
  let n09 = sym_or(handle, "rcl_init_options_fini");
  if !n09.is_ok { return fail_load(handle, n09.error); }
  let n10 = sym_or(handle, "rcl_node_init");
  if !n10.is_ok { return fail_load(handle, n10.error); }
  let n11 = sym_or(handle, "rcl_node_fini");
  if !n11.is_ok { return fail_load(handle, n11.error); }
  let n12 = sym_or(handle, "rcl_node_get_name");
  if !n12.is_ok { return fail_load(handle, n12.error); }
  let n13 = sym_or(handle, "rcl_node_get_namespace");
  if !n13.is_ok { return fail_load(handle, n13.error); }
  let n14 = sym_or(handle, "rcl_publisher_init");
  if !n14.is_ok { return fail_load(handle, n14.error); }
  let n15 = sym_or(handle, "rcl_publisher_fini");
  if !n15.is_ok { return fail_load(handle, n15.error); }
  let n16 = sym_or(handle, "rcl_publish");
  if !n16.is_ok { return fail_load(handle, n16.error); }
  let n17 = sym_or(handle, "rcl_subscription_init");
  if !n17.is_ok { return fail_load(handle, n17.error); }
  let n18 = sym_or(handle, "rcl_subscription_fini");
  if !n18.is_ok { return fail_load(handle, n18.error); }
  let n19 = sym_or(handle, "rcl_take");
  if !n19.is_ok { return fail_load(handle, n19.error); }
  let n20 = sym_or(handle, "rcl_clock_init");
  if !n20.is_ok { return fail_load(handle, n20.error); }
  let n21 = sym_or(handle, "rcl_clock_fini");
  if !n21.is_ok { return fail_load(handle, n21.error); }
  let n22 = sym_or(handle, "rcl_clock_get_now");
  if !n22.is_ok { return fail_load(handle, n22.error); }
  let n23 = sym_or(handle, "rcl_timer_init");
  if !n23.is_ok { return fail_load(handle, n23.error); }
  let n24 = sym_or(handle, "rcl_timer_fini");
  if !n24.is_ok { return fail_load(handle, n24.error); }
  let n25 = sym_or(handle, "rcl_timer_call");
  if !n25.is_ok { return fail_load(handle, n25.error); }
  let n26 = sym_or(handle, "rcl_timer_is_ready");
  if !n26.is_ok { return fail_load(handle, n26.error); }
  let n27 = sym_or(handle, "rcl_timer_get_period");
  if !n27.is_ok { return fail_load(handle, n27.error); }
  let n28 = sym_or(handle, "rcl_timer_get_time_until_next_call");
  if !n28.is_ok { return fail_load(handle, n28.error); }
  let n29 = sym_or(handle, "rcl_timer_reset");
  if !n29.is_ok { return fail_load(handle, n29.error); }
  let n30 = sym_or(handle, "rcl_timer_cancel");
  if !n30.is_ok { return fail_load(handle, n30.error); }
  let n31 = sym_or(handle, "rcl_timer_is_canceled");
  if !n31.is_ok { return fail_load(handle, n31.error); }
  let n32 = sym_or(handle, "rcl_wait_set_init");
  if !n32.is_ok { return fail_load(handle, n32.error); }
  let n33 = sym_or(handle, "rcl_wait_set_fini");
  if !n33.is_ok { return fail_load(handle, n33.error); }
  let n34 = sym_or(handle, "rcl_wait_set_clear");
  if !n34.is_ok { return fail_load(handle, n34.error); }
  let n35 = sym_or(handle, "rcl_wait_set_resize");
  if !n35.is_ok { return fail_load(handle, n35.error); }
  let n36 = sym_or(handle, "rcl_wait_set_add_subscription");
  if !n36.is_ok { return fail_load(handle, n36.error); }
  let n37 = sym_or(handle, "rcl_wait_set_add_timer");
  if !n37.is_ok { return fail_load(handle, n37.error); }
  let n38 = sym_or(handle, "rcl_wait_set_is_valid");
  if !n38.is_ok { return fail_load(handle, n38.error); }
  let n39 = sym_or(handle, "rcl_wait");
  if !n39.is_ok { return fail_load(handle, n39.error); }

  // Optional: rcl_timer_init2 (Iron+). Humble only ships rcl_timer_init.
  var has2 = false;
  var n23b: Int = 0;
  let t2 = dl.dl_sym(handle, "rcl_timer_init2");
  if t2.is_ok {
    has2 = true;
    n23b = t2.value;
  }

  // C-runtime companion: the documented default allocator wraps
  // malloc/free/realloc/calloc (rcutils/src/allocator.c).
  var chandle: Int = 0;
  var cname: Str = "";
  let c1 = dl.dl_open("ucrtbase.dll");
  if c1.is_ok { chandle = c1.value; cname = "ucrtbase.dll"; }
  if chandle == 0 {
    let c2 = dl.dl_open("msvcrt.dll");
    if c2.is_ok { chandle = c2.value; cname = "msvcrt.dll"; }
  }
  if chandle == 0 {
    let c3 = dl.dl_open("libc.so.6");
    if c3.is_ok { chandle = c3.value; cname = "libc.so.6"; }
  }
  if chandle == 0 {
    let c4 = dl.dl_open("libc.so");
    if c4.is_ok { chandle = c4.value; cname = "libc.so"; }
  }
  if chandle == 0 {
    var ig1 = dl.dl_close(handle);
    return Err(Ros2Error{
      kind: ROS2_LOAD_ABI; ret: -1;
      message: "librcl loaded but no C-runtime companion (tried ucrtbase.dll, msvcrt.dll, libc.so.6, libc.so)",
    });
  }

  let c01 = sym_or(chandle, "malloc");
  if !c01.is_ok { return fail_load2(handle, chandle, c01.error); }
  let c02 = sym_or(chandle, "free");
  if !c02.is_ok { return fail_load2(handle, chandle, c02.error); }
  let c03 = sym_or(chandle, "realloc");
  if !c03.is_ok { return fail_load2(handle, chandle, c03.error); }
  let c04 = sym_or(chandle, "calloc");
  if !c04.is_ok { return fail_load2(handle, chandle, c04.error); }

  return Ok(Ros2Library{
    handle: handle;
    soname: soname;
    libc_handle: chandle;
    libc_soname: cname;
    has_timer_init2: has2;
    p_rcl_init: n01.value;
    p_rcl_shutdown: n02.value;
    p_rcl_context_fini: n03.value;
    p_rcl_context_is_valid: n04.value;
    p_rcl_context_get_instance_id: n05.value;
    p_rcl_context_get_domain_id: n06.value;
    p_rcl_init_options_init: n07.value;
    p_rcl_init_options_set_domain_id: n08.value;
    p_rcl_init_options_fini: n09.value;
    p_rcl_node_init: n10.value;
    p_rcl_node_fini: n11.value;
    p_rcl_node_get_name: n12.value;
    p_rcl_node_get_namespace: n13.value;
    p_rcl_publisher_init: n14.value;
    p_rcl_publisher_fini: n15.value;
    p_rcl_publish: n16.value;
    p_rcl_subscription_init: n17.value;
    p_rcl_subscription_fini: n18.value;
    p_rcl_take: n19.value;
    p_rcl_clock_init: n20.value;
    p_rcl_clock_fini: n21.value;
    p_rcl_clock_get_now: n22.value;
    p_rcl_timer_init: n23.value;
    p_rcl_timer_init2: n23b;
    p_rcl_timer_fini: n24.value;
    p_rcl_timer_call: n25.value;
    p_rcl_timer_is_ready: n26.value;
    p_rcl_timer_get_period: n27.value;
    p_rcl_timer_get_time_until_next_call: n28.value;
    p_rcl_timer_reset: n29.value;
    p_rcl_timer_cancel: n30.value;
    p_rcl_timer_is_canceled: n31.value;
    p_rcl_wait_set_init: n32.value;
    p_rcl_wait_set_fini: n33.value;
    p_rcl_wait_set_clear: n34.value;
    p_rcl_wait_set_resize: n35.value;
    p_rcl_wait_set_add_subscription: n36.value;
    p_rcl_wait_set_add_timer: n37.value;
    p_rcl_wait_set_is_valid: n38.value;
    p_rcl_wait: n39.value;
    p_malloc: c01.value;
    p_realloc: c03.value;
    p_calloc: c04.value;
    p_free: c02.value;
  });
}

/// Load an explicitly named librcl build (bogus names exercise the
/// ABSENT/SKIP classification deterministically on any host).
/// Complexity: O(symbols).
pub fn ros2_load_named(soname: Str) -> Result[Ros2Library, Ros2Error]
  requires: soname.len() > 0
{
  return try_load(soname);
}

/// Load the first available librcl from the common sonames: Linux
/// `librcl.so`, Windows `rcl.dll`, macOS `librcl.dylib`. A ROS 2 install
/// also needs its prefix lib dir on the loader search path (Windows: the
/// setup.ps1 PATH entry; Linux: source /opt/ros/<distro>/setup.bash).
/// Complexity: O(candidates * symbols).
pub fn ros2_load() -> Result[Ros2Library, Ros2Error]
  requires: true
{
  let c1 = try_load("librcl.so");
  if c1.is_ok { return Ok(c1.value); }
  if c1.error.kind != ROS2_LOAD_ABSENT { return Err(c1.error); }

  let c2 = try_load("rcl.dll");
  if c2.is_ok { return Ok(c2.value); }
  if c2.error.kind != ROS2_LOAD_ABSENT { return Err(c2.error); }

  let c3 = try_load("librcl.dylib");
  if c3.is_ok { return Ok(c3.value); }
  if c3.error.kind != ROS2_LOAD_ABSENT { return Err(c3.error); }

  return Err(Ros2Error{
    kind: ROS2_LOAD_ABSENT; ret: -1;
    message: "ros2: no librcl candidate found (tried " + ros2_sonames() + ")",
  });
}

/// Release the library handles (allocator companion first, then librcl).
/// Complexity: O(1).
pub fn ros2_close(lib: &Ros2Library) -> Result[Unit, Str]
  requires: lib.handle != 0
  requires: lib.libc_handle != 0
{
  let rc2 = dl.dl_close(lib.libc_handle);
  let rc1 = dl.dl_close(lib.handle);
  if !rc2.is_ok { return Err(rc2.error); }
  if !rc1.is_ok { return Err(rc1.error); }
  return Ok(());
}

// =========================================================================
// Context (rcl_init / rcl_shutdown / fini / queries)
// =========================================================================

/// Create the default allocator slot from the library's C-runtime companion.
/// Complexity: O(1).
fn alloc_from_lib(lib: &Ros2Library) -> Vec[UInt8]
  requires: lib.p_malloc != 0
{
  return ros2_allocator_build(lib.p_malloc, lib.p_free, lib.p_realloc, lib.p_calloc);
}

/// Initialize rcl and return the context. `domain_id < 0` keeps the default
/// domain; >= 0 calls rcl_init_options_set_domain_id (0..232 valid).
/// Complexity: O(1) beyond rcl.
pub fn ros2_context_init(lib: &Ros2Library, domain_id: Int) -> Result[Ros2Context, Ros2Error]
  requires: lib.handle != 0
{
  let alloc = alloc_from_lib(lib);
  var opts = slot(ROS2_HANDLE_SLOT);
  var ctx = slot(ROS2_CONTEXT_SLOT);

  // ABI: by-value allocator via pointer-pretend.
  unsafe {
    let f = lib.p_rcl_init_options_init as fn(*UInt8, *UInt8) -> Int;
    let rc0 = ret_of(f(&opts[0] as *UInt8, &alloc[0] as *UInt8));
    if rc0 != RCL_RET_OK {
      return Err(ret_err("rcl_init_options_init", rc0));
    }
  }
  if domain_id >= 0 {
    unsafe {
      let f = lib.p_rcl_init_options_set_domain_id as fn(*UInt8, Int) -> Int;
      let rc1 = ret_of(f(&opts[0] as *UInt8, domain_id));
      if rc1 != RCL_RET_OK {
        return Err(ret_err("rcl_init_options_set_domain_id", rc1));
      }
    }
  }
  unsafe {
    let f = lib.p_rcl_init as fn(Int, Int, *UInt8, *UInt8) -> Int;
    let rc2 = ret_of(f(0, 0, &opts[0] as *UInt8, &ctx[0] as *UInt8));
    if rc2 != RCL_RET_OK {
      let e = ret_err("rcl_init", rc2);
      return Err(e);
    }
  }
  unsafe {
    let f = lib.p_rcl_init_options_fini as fn(*UInt8) -> Int;
    let rc3 = ret_of(f(&opts[0] as *UInt8));
    if rc3 != RCL_RET_OK {
      var ig = shutdown_raw(lib, &ctx);
      return Err(ret_err("rcl_init_options_fini", rc3));
    }
  }
  return Ok(Ros2Context{ slot: ctx });
}

fn shutdown_raw(lib: &Ros2Library, ctx: &Vec[UInt8]) -> Int
  requires: ctx.len() >= ROS2_CONTEXT_SLOT
{
  unsafe {
    let f = lib.p_rcl_shutdown as fn(*UInt8) -> Int;
    return ret_of(f(&ctx[0] as *UInt8));
  }
}

/// rcl_shutdown: invalidates the context; entities must be finied first.
/// Complexity: O(1).
pub fn ros2_context_shutdown(lib: &Ros2Library, ctx: &Ros2Context) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
{
  let rc = shutdown_raw(lib, &ctx.slot);
  if rc != RCL_RET_OK { return Err(ret_err("rcl_shutdown", rc)); }
  return Ok(());
}

/// rcl_context_fini: release the context (call after shutdown + entity fini).
/// Complexity: O(1).
pub fn ros2_context_fini(lib: &Ros2Library, ctx: &Ros2Context) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
{
  unsafe {
    let f = lib.p_rcl_context_fini as fn(*UInt8) -> Int;
    let rc = ret_of(f(&ctx.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_context_fini", rc)); }
    return Ok(());
  }
}

/// Whether the context is currently valid.
/// Complexity: O(1).
pub fn ros2_context_is_valid(lib: &Ros2Library, ctx: &Ros2Context) -> Bool
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
{
  // C bool read as UInt8: low byte only (no mask on possibly-large values).
  unsafe {
    let f = lib.p_rcl_context_is_valid as fn(*UInt8) -> UInt8;
    return (f(&ctx.slot[0] as *UInt8) as Int) != 0;
  }
}

/// Context instance id (0 when invalid).
/// Complexity: O(1).
pub fn ros2_context_instance_id(lib: &Ros2Library, ctx: &Ros2Context) -> Int
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
{
  unsafe {
    let f = lib.p_rcl_context_get_instance_id as fn(*UInt8) -> Int;
    return f(&ctx.slot[0] as *UInt8);
  }
}

/// Context domain id.
/// Complexity: O(1).
pub fn ros2_context_domain_id(lib: &Ros2Library, ctx: &Ros2Context) -> Result[Int, Ros2Error]
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
{
  var out = slot(ROS2_OUT_SLOT);
  unsafe {
    let f = lib.p_rcl_context_get_domain_id as fn(*UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&ctx.slot[0] as *UInt8, &out[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_context_get_domain_id", rc)); }
  }
  return Ok(ros2_slot_u64(&out, 0));
}

// =========================================================================
// Node
// =========================================================================

/// Create a node. Empty namespace means "/" (rcl default). The node does not
/// consume global CLI arguments and does not create /rosout (documented
/// fabrication defaults: use_global_arguments=false, enable_rosout=false).
/// Complexity: O(1) beyond rcl.
pub fn ros2_node_init(lib: &Ros2Library, ctx: &Ros2Context, name: Str, namespace: Str) -> Result[Ros2Node, Ros2Error]
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
  requires: name.len() > 0
{
  let alloc = alloc_from_lib(lib);
  let opts = ros2_node_options_build(&alloc);
  var node = slot(ROS2_HANDLE_SLOT);
  var ns = namespace;
  if namespace.len() == 0 { ns = "/"; }
  unsafe {
    let f = lib.p_rcl_node_init as fn(*UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(
      &node[0] as *UInt8, name as *UInt8, ns as *UInt8,
      &ctx.slot[0] as *UInt8, &opts[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_node_init", rc)); }
  }
  return Ok(Ros2Node{ slot: node });
}

/// Finalize the node.
/// Complexity: O(1).
pub fn ros2_node_fini(lib: &Ros2Library, node: &Ros2Node) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_node_fini as fn(*UInt8) -> Int;
    let rc = ret_of(f(&node.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_node_fini", rc)); }
    return Ok(());
  }
}

/// Node name ("name" when the handle is invalid).
/// Complexity: O(len).
pub fn ros2_node_name(lib: &Ros2Library, node: &Ros2Node) -> Str
  requires: lib.handle != 0
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_node_get_name as fn(*UInt8) -> *UInt8;
    let p = f(&node.slot[0] as *UInt8);
    if p as Int == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

/// Node namespace ("/" when the handle is invalid).
/// Complexity: O(len).
pub fn ros2_node_namespace(lib: &Ros2Library, node: &Ros2Node) -> Str
  requires: lib.handle != 0
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_node_get_namespace as fn(*UInt8) -> *UInt8;
    let p = f(&node.slot[0] as *UInt8);
    if p as Int == 0 { return ""; }
    return Str::from_c_str(p);
  }
}

// =========================================================================
// Type support (rosidl message handles)
// =========================================================================

/// Resolve a rosidl type-support handle by loading `soname` and calling the
/// getter symbol (e.g. `...__std_msgs__msg__String` in
/// `libstd_msgs__rosidl_typesupport_c.so`). The library stays loaded while
/// the returned handle lives; release with `ros2_typesupport_close`.
/// Complexity: O(1) beyond dl.
pub fn ros2_typesupport_resolve(soname: Str, symbol: Str) -> Result[Ros2TypeSupport, Ros2Error]
  requires: soname.len() > 0
  requires: symbol.len() > 0
{
  let h = dl.dl_open(soname);
  if !h.is_ok {
    return Err(Ros2Error{ kind: ROS2_LOAD_ABSENT; ret: -1; message: h.error });
  }
  let handle: Int = h.value;
  let s = dl.dl_sym(handle, symbol);
  if !s.is_ok {
    var ig = dl.dl_close(handle);
    return Err(Ros2Error{ kind: ROS2_LOAD_ABI; ret: -1; message: s.error });
  }
  var addr: Int = 0;
  unsafe {
    let f = s.value as fn() -> Int;
    addr = f();
  }
  if addr == 0 {
    var ig2 = dl.dl_close(handle);
    return Err(Ros2Error{
      kind: ROS2_LOAD_ABI; ret: -1;
      message: symbol + " returned NULL type support",
    });
  }
  return Ok(Ros2TypeSupport{ addr: addr; handle: handle; soname: soname });
}

/// Convenience: std_msgs/String type support from the common typesupport
/// sonames. Used by the live leg (Pi) for a full pub/sub roundtrip.
/// Complexity: O(candidates * dl).
pub fn ros2_typesupport_std_msgs_string() -> Result[Ros2TypeSupport, Ros2Error]
  requires: true
{
  let sym = "rosidl_typesupport_c__get_message_type_support_handle__std_msgs__msg__String";
  let c1 = ros2_typesupport_resolve("libstd_msgs__rosidl_typesupport_c.so", sym);
  if c1.is_ok { return Ok(c1.value); }
  if c1.error.kind != ROS2_LOAD_ABSENT { return Err(c1.error); }
  let c2 = ros2_typesupport_resolve("std_msgs__rosidl_typesupport_c.dll", sym);
  if c2.is_ok { return Ok(c2.value); }
  if c2.error.kind != ROS2_LOAD_ABSENT { return Err(c2.error); }
  let c3 = ros2_typesupport_resolve("libstd_msgs__rosidl_typesupport_c.dylib", sym);
  if c3.is_ok { return Ok(c3.value); }
  if c3.error.kind != ROS2_LOAD_ABSENT { return Err(c3.error); }
  return Err(Ros2Error{
    kind: ROS2_LOAD_ABSENT; ret: -1;
    message: "ros2: no std_msgs/String typesupport candidate found",
  });
}

/// Release a resolved type support's library (only when no live entities
/// still reference the handle).
/// Complexity: O(1).
pub fn ros2_typesupport_close(ts: &Ros2TypeSupport) -> Result[Unit, Str]
  requires: ts.handle != 0
{
  return dl.dl_close(ts.handle);
}

// =========================================================================
// Publisher
// =========================================================================

/// Create a publisher with a QoS preset (ROS2_QOS_*).
/// Complexity: O(1) beyond rcl.
pub fn ros2_publisher_init(
  lib: &Ros2Library, node: &Ros2Node, topic: Str, ts_addr: Int, qos_id: Int
) -> Result[Ros2Publisher, Ros2Error]
  requires: lib.handle != 0
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
  requires: topic.len() > 0
  requires: ts_addr != 0
{
  let alloc = alloc_from_lib(lib);
  let opts_r = ros2_pubsub_options_build(qos_id, &alloc);
  if !opts_r.is_ok {
    return Err(make_err(ROS2_ARG_INVALID, -1, opts_r.error));
  }
  let opts = opts_r.value;
  var pub_slot = slot(ROS2_HANDLE_SLOT);
  unsafe {
    let f = lib.p_rcl_publisher_init as fn(*UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(
      &pub_slot[0] as *UInt8, &node.slot[0] as *UInt8, ts_addr as *UInt8,
      topic as *UInt8, &opts[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_publisher_init", rc)); }
  }
  return Ok(Ros2Publisher{ slot: pub_slot });
}

/// Create a publisher with an explicit QoS block (see ros2_qos_write_custom).
/// Complexity: O(1) beyond rcl.
pub fn ros2_publisher_init_qos(
  lib: &Ros2Library, node: &Ros2Node, topic: Str, ts_addr: Int,
  history: Int, depth: Int, reliability: Int, durability: Int, liveliness: Int
) -> Result[Ros2Publisher, Ros2Error]
  requires: lib.handle != 0
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
  requires: topic.len() > 0
  requires: ts_addr != 0
{
  let alloc = alloc_from_lib(lib);
  var opts = slot(ROS2_OPTIONS_SLOT);
  let q = ros2_qos_write_custom(&mut opts, 0, history, depth, reliability, durability, liveliness, 0);
  if !q.is_ok { return Err(make_err(ROS2_ARG_INVALID, -1, q.error)); }
  var i = 0;
  while i < ROS2_ALLOC_SIZE {
    opts[ROS2_PUBSUB_ALLOC_OFF + i] = alloc[i];
    i = i + 1;
  }
  var pub_slot = slot(ROS2_HANDLE_SLOT);
  unsafe {
    let f = lib.p_rcl_publisher_init as fn(*UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(
      &pub_slot[0] as *UInt8, &node.slot[0] as *UInt8, ts_addr as *UInt8,
      topic as *UInt8, &opts[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_publisher_init", rc)); }
  }
  return Ok(Ros2Publisher{ slot: pub_slot });
}

/// Finalize the publisher (the node must still be valid).
/// Complexity: O(1).
pub fn ros2_publisher_fini(lib: &Ros2Library, pub_: &Ros2Publisher, node: &Ros2Node) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: pub_.slot.len() >= ROS2_HANDLE_SLOT
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_publisher_fini as fn(*UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&pub_.slot[0] as *UInt8, &node.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_publisher_fini", rc)); }
    return Ok(());
  }
}

/// Publish a caller-serialized message (pointer to the typesupport-specific
/// message struct; the caller owns the buffer).
/// Complexity: O(1).
pub fn ros2_publish(lib: &Ros2Library, pub_: &Ros2Publisher, msg_ptr: Int) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: pub_.slot.len() >= ROS2_HANDLE_SLOT
  requires: msg_ptr != 0
{
  unsafe {
    let f = lib.p_rcl_publish as fn(*UInt8, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&pub_.slot[0] as *UInt8, msg_ptr as *UInt8, 0 as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_publish", rc)); }
    return Ok(());
  }
}

// =========================================================================
// Subscription
// =========================================================================

fn subscription_init_common(
  lib: &Ros2Library, node: &Ros2Node, topic: Str, ts_addr: Int, opts: &Vec[UInt8], opname: Str
) -> Result[Ros2Subscription, Ros2Error]
  requires: lib.handle != 0
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
  requires: opts.len() >= ROS2_OPTIONS_SLOT
  requires: opname.len() > 0
{
  var sub_slot = slot(ROS2_HANDLE_SLOT);
  unsafe {
    let f = lib.p_rcl_subscription_init as fn(*UInt8, *UInt8, *UInt8, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(
      &sub_slot[0] as *UInt8, &node.slot[0] as *UInt8, ts_addr as *UInt8,
      topic as *UInt8, &opts[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err(opname, rc)); }
  }
  return Ok(Ros2Subscription{ slot: sub_slot });
}

/// Create a subscription with a QoS preset.
/// Complexity: O(1) beyond rcl.
pub fn ros2_subscription_init(
  lib: &Ros2Library, node: &Ros2Node, topic: Str, ts_addr: Int, qos_id: Int
) -> Result[Ros2Subscription, Ros2Error]
  requires: lib.handle != 0
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
  requires: topic.len() > 0
  requires: ts_addr != 0
{
  let alloc = alloc_from_lib(lib);
  let opts_r = ros2_pubsub_options_build(qos_id, &alloc);
  if !opts_r.is_ok {
    return Err(make_err(ROS2_ARG_INVALID, -1, opts_r.error));
  }
  let opts = opts_r.value;
  return subscription_init_common(lib, node, topic, ts_addr, &opts, "rcl_subscription_init");
}

/// Create a subscription with an explicit QoS block.
/// Complexity: O(1) beyond rcl.
pub fn ros2_subscription_init_qos(
  lib: &Ros2Library, node: &Ros2Node, topic: Str, ts_addr: Int,
  history: Int, depth: Int, reliability: Int, durability: Int, liveliness: Int
) -> Result[Ros2Subscription, Ros2Error]
  requires: lib.handle != 0
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
  requires: topic.len() > 0
  requires: ts_addr != 0
{
  let alloc = alloc_from_lib(lib);
  var opts = slot(ROS2_OPTIONS_SLOT);
  let q = ros2_qos_write_custom(&mut opts, 0, history, depth, reliability, durability, liveliness, 0);
  if !q.is_ok { return Err(make_err(ROS2_ARG_INVALID, -1, q.error)); }
  var i = 0;
  while i < ROS2_ALLOC_SIZE {
    opts[ROS2_PUBSUB_ALLOC_OFF + i] = alloc[i];
    i = i + 1;
  }
  return subscription_init_common(lib, node, topic, ts_addr, &opts, "rcl_subscription_init");
}

/// Finalize the subscription.
/// Complexity: O(1).
pub fn ros2_subscription_fini(lib: &Ros2Library, sub: &Ros2Subscription, node: &Ros2Node) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: sub.slot.len() >= ROS2_HANDLE_SLOT
  requires: node.slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_subscription_fini as fn(*UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&sub.slot[0] as *UInt8, &node.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_subscription_fini", rc)); }
    return Ok(());
  }
}

/// Take one message into a caller-owned buffer: Ok(true) = message taken,
/// Ok(false) = nothing available (RCL_RET_SUBSCRIPTION_TAKE_FAILED).
/// Complexity: O(1).
pub fn ros2_take(lib: &Ros2Library, sub: &Ros2Subscription, msg_ptr: Int) -> Result[Bool, Ros2Error]
  requires: lib.handle != 0
  requires: sub.slot.len() >= ROS2_HANDLE_SLOT
  requires: msg_ptr != 0
{
  unsafe {
    let f = lib.p_rcl_take as fn(*UInt8, *UInt8, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&sub.slot[0] as *UInt8, msg_ptr as *UInt8, 0 as *UInt8, 0 as *UInt8));
    if rc == RCL_RET_OK { return Ok(true); }
    if rc == RCL_RET_SUBSCRIPTION_TAKE_FAILED { return Ok(false); }
    return Err(ret_err("rcl_take", rc));
  }
}

// =========================================================================
// Clock
// =========================================================================

/// Initialize a clock (RCL_STEADY_TIME / RCL_SYSTEM_TIME / RCL_ROS_TIME).
/// Complexity: O(1) beyond rcl.
pub fn ros2_clock_init(lib: &Ros2Library, clock_type: Int) -> Result[Ros2Clock, Ros2Error]
  requires: lib.handle != 0
  requires: clock_type >= 0
  requires: clock_type <= 3
{
  let alloc = alloc_from_lib(lib);
  var clk = slot(ROS2_HANDLE_SLOT);
  // ABI: by-value allocator via pointer-pretend (3-arg shape probe-verified).
  unsafe {
    let f = lib.p_rcl_clock_init as fn(Int, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(clock_type, &clk[0] as *UInt8, &alloc[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_clock_init", rc)); }
  }
  return Ok(Ros2Clock{ slot: clk });
}

/// Finalize the clock.
/// Complexity: O(1).
pub fn ros2_clock_fini(lib: &Ros2Library, clock: &Ros2Clock) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: clock.slot.len() >= ROS2_HANDLE_SLOT
{
  return clock_fini_raw(lib, &clock.slot);
}

fn clock_fini_raw(lib: &Ros2Library, clock_slot: &Vec[UInt8]) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: clock_slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_clock_fini as fn(*UInt8) -> Int;
    let rc = ret_of(f(&clock_slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_clock_fini", rc)); }
    return Ok(());
  }
}

/// Current time of the clock in nanoseconds (signed, rcl_time_point_value_t).
/// Complexity: O(1).
pub fn ros2_clock_now_ns(lib: &Ros2Library, clock: &Ros2Clock) -> Result[Int, Ros2Error]
  requires: lib.handle != 0
  requires: clock.slot.len() >= ROS2_HANDLE_SLOT
{
  var out = slot(ROS2_OUT_SLOT);
  unsafe {
    let f = lib.p_rcl_clock_get_now as fn(*UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&clock.slot[0] as *UInt8, &out[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_clock_get_now", rc)); }
  }
  return Ok(ros2_slot_u64(&out, 0));
}

// =========================================================================
// Timer (NULL callback by design: rcl documents no callback is fired and
// "this function should still be called" for rcl_timer_call)
// =========================================================================

/// Create a timer with a private steady clock. `period_ms` in milliseconds
/// (1 ms minimum). The timer owns its clock; free it with ros2_timer_fini.
/// Complexity: O(1) beyond rcl.
pub fn ros2_timer_init(lib: &Ros2Library, ctx: &Ros2Context, period_ms: Int, autostart: Bool) -> Result[Ros2Timer, Ros2Error]
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
  requires: period_ms > 0
{
  let clk_r = ros2_clock_init(lib, RCL_STEADY_TIME);
  if !clk_r.is_ok { return Err(clk_r.error); }
  let clk = clk_r.value;
  let t_r = timer_init_with_clock_raw(lib, ctx, &clk.slot, period_ms, autostart);
  if !t_r.is_ok {
    var ig = ros2_clock_fini(lib, &clk);
    return Err(t_r.error);
  }
  return Ok(Ros2Timer{ slot: t_r.value; own_clock: clk.slot });
}

/// Create a timer on a caller-owned clock (the clock must outlive the timer).
/// Complexity: O(1) beyond rcl.
pub fn ros2_timer_init_with_clock(
  lib: &Ros2Library, ctx: &Ros2Context, clock: &Ros2Clock, period_ms: Int, autostart: Bool
) -> Result[Ros2Timer, Ros2Error]
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
  requires: clock.slot.len() >= ROS2_HANDLE_SLOT
  requires: period_ms > 0
{
  let t_r = timer_init_with_clock_raw(lib, ctx, &clock.slot, period_ms, autostart);
  if !t_r.is_ok { return Err(t_r.error); }
  var empty_clock = Vec[UInt8].new();
  return Ok(Ros2Timer{ slot: t_r.value; own_clock: empty_clock });
}

fn timer_init_with_clock_raw(
  lib: &Ros2Library, ctx: &Ros2Context, clock_slot: &Vec[UInt8], period_ms: Int, autostart: Bool
) -> Result[Vec[UInt8], Ros2Error]
  requires: lib.handle != 0
  requires: clock_slot.len() >= ROS2_HANDLE_SLOT
  requires: period_ms > 0
{
  let alloc = alloc_from_lib(lib);
  var timer = slot(ROS2_HANDLE_SLOT);
  let period_ns = period_ms * 1000000;
  var start: Int = 0;
  if autostart { start = 1; }
  if lib.has_timer_init2 {
    // ABI: by-value allocator at slot 6 via pointer-pretend (7-arg probe).
    unsafe {
      let f = lib.p_rcl_timer_init2 as fn(*UInt8, *UInt8, *UInt8, Int, Int, *UInt8, Int) -> Int;
      let rc = ret_of(f(
        &timer[0] as *UInt8, &clock_slot[0] as *UInt8, &ctx.slot[0] as *UInt8,
        period_ns, 0, &alloc[0] as *UInt8, start));
      if rc != RCL_RET_OK { return Err(ret_err("rcl_timer_init2", rc)); }
    }
  } else {
    // Humble fallback: rcl_timer_init (allocator at slot 6 of 6; autostart
    // is implicit true in that ABI).
    unsafe {
      let f = lib.p_rcl_timer_init as fn(*UInt8, *UInt8, *UInt8, Int, Int, *UInt8) -> Int;
      let rc = ret_of(f(
        &timer[0] as *UInt8, &clock_slot[0] as *UInt8, &ctx.slot[0] as *UInt8,
        period_ns, 0, &alloc[0] as *UInt8));
      if rc != RCL_RET_OK { return Err(ret_err("rcl_timer_init", rc)); }
    }
  }
  return Ok(timer);
}

/// Finalize the timer (releases its private clock when it owns one).
/// Complexity: O(1).
pub fn ros2_timer_fini(lib: &Ros2Library, timer: &Ros2Timer) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: timer.slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_timer_fini as fn(*UInt8) -> Int;
    let rc = ret_of(f(&timer.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_timer_fini", rc)); }
  }
  if timer.own_clock.len() >= ROS2_HANDLE_SLOT {
    return clock_fini_raw(lib, &timer.own_clock);
  }
  return Ok(());
}

/// Trigger the timer's call accounting (NULL callback: state only).
/// Complexity: O(1).
pub fn ros2_timer_call(lib: &Ros2Library, timer: &Ros2Timer) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: timer.slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_timer_call as fn(*UInt8) -> Int;
    let rc = ret_of(f(&timer.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_timer_call", rc)); }
    return Ok(());
  }
}

/// Whether the timer's period has elapsed (and it is not canceled).
/// Complexity: O(1).
pub fn ros2_timer_is_ready(lib: &Ros2Library, timer: &Ros2Timer) -> Bool
  requires: lib.handle != 0
  requires: timer.slot.len() >= ROS2_HANDLE_SLOT
{
  var out = slot(ROS2_OUT_SLOT);
  unsafe {
    let f = lib.p_rcl_timer_is_ready as fn(*UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&timer.slot[0] as *UInt8, &out[0] as *UInt8));
    if rc != RCL_RET_OK { return false; }
  }
  return ros2_slot_u8(&out, 0) != 0;
}

/// Timer period in nanoseconds.
/// Complexity: O(1).
pub fn ros2_timer_period_ns(lib: &Ros2Library, timer: &Ros2Timer) -> Result[Int, Ros2Error]
  requires: lib.handle != 0
  requires: timer.slot.len() >= ROS2_HANDLE_SLOT
{
  var out = slot(ROS2_OUT_SLOT);
  unsafe {
    let f = lib.p_rcl_timer_get_period as fn(*UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&timer.slot[0] as *UInt8, &out[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_timer_get_period", rc)); }
  }
  return Ok(ros2_slot_u64(&out, 0));
}

/// Nanoseconds until the next due call (negative when overdue).
/// Complexity: O(1).
pub fn ros2_timer_time_until_next_call_ns(lib: &Ros2Library, timer: &Ros2Timer) -> Result[Int, Ros2Error]
  requires: lib.handle != 0
  requires: timer.slot.len() >= ROS2_HANDLE_SLOT
{
  var out = slot(ROS2_OUT_SLOT);
  unsafe {
    let f = lib.p_rcl_timer_get_time_until_next_call as fn(*UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&timer.slot[0] as *UInt8, &out[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_timer_get_time_until_next_call", rc)); }
  }
  return Ok(ros2_slot_u64(&out, 0));
}

/// Reset the timer's call time to now.
/// Complexity: O(1).
pub fn ros2_timer_reset(lib: &Ros2Library, timer: &Ros2Timer) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: timer.slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_timer_reset as fn(*UInt8) -> Int;
    let rc = ret_of(f(&timer.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_timer_reset", rc)); }
    return Ok(());
  }
}

/// Cancel the timer (rcl_timer_call then fails with TIMER_CANCELED).
/// Complexity: O(1).
pub fn ros2_timer_cancel(lib: &Ros2Library, timer: &Ros2Timer) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: timer.slot.len() >= ROS2_HANDLE_SLOT
{
  unsafe {
    let f = lib.p_rcl_timer_cancel as fn(*UInt8) -> Int;
    let rc = ret_of(f(&timer.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_timer_cancel", rc)); }
    return Ok(());
  }
}

/// Whether the timer is canceled.
/// Complexity: O(1).
pub fn ros2_timer_is_canceled(lib: &Ros2Library, timer: &Ros2Timer) -> Bool
  requires: lib.handle != 0
  requires: timer.slot.len() >= ROS2_HANDLE_SLOT
{
  var out = slot(ROS2_OUT_SLOT);
  unsafe {
    let f = lib.p_rcl_timer_is_canceled as fn(*UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&timer.slot[0] as *UInt8, &out[0] as *UInt8));
    if rc != RCL_RET_OK { return false; }
  }
  return ros2_slot_u8(&out, 0) != 0;
}

// =========================================================================
// Wait set
// =========================================================================

/// Initialize a wait set sized for `n_subs` subscriptions and `n_timers`
/// timers (guard conditions/clients/services/events stay 0).
/// Complexity: O(1) beyond rcl.
pub fn ros2_wait_set_init(lib: &Ros2Library, ctx: &Ros2Context, n_subs: Int, n_timers: Int) -> Result[Ros2WaitSet, Ros2Error]
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
  requires: n_subs >= 0
  requires: n_timers >= 0
  requires: n_subs + n_timers > 0
{
  let alloc = alloc_from_lib(lib);
  var ws = slot(ROS2_WAIT_SET_SLOT);
  // ABI: by-value allocator at slot 9 via pointer-pretend (9-arg probe).
  unsafe {
    let f = lib.p_rcl_wait_set_init as fn(*UInt8, Int, Int, Int, Int, Int, Int, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(
      &ws[0] as *UInt8, n_subs, 0, n_timers, 0, 0, 0,
      &ctx.slot[0] as *UInt8, &alloc[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_wait_set_init", rc)); }
  }
  return Ok(Ros2WaitSet{ slot: ws });
}

/// Finalize the wait set.
/// Complexity: O(1).
pub fn ros2_wait_set_fini(lib: &Ros2Library, ws: &Ros2WaitSet) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: ws.slot.len() >= ROS2_WAIT_SET_SLOT
{
  unsafe {
    let f = lib.p_rcl_wait_set_fini as fn(*UInt8) -> Int;
    let rc = ret_of(f(&ws.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_wait_set_fini", rc)); }
    return Ok(());
  }
}

/// Clear all entities from the wait set.
/// Complexity: O(1).
pub fn ros2_wait_set_clear(lib: &Ros2Library, ws: &Ros2WaitSet) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: ws.slot.len() >= ROS2_WAIT_SET_SLOT
{
  unsafe {
    let f = lib.p_rcl_wait_set_clear as fn(*UInt8) -> Int;
    let rc = ret_of(f(&ws.slot[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_wait_set_clear", rc)); }
    return Ok(());
  }
}

/// Resize the wait set.
/// Complexity: O(1) beyond rcl.
pub fn ros2_wait_set_resize(lib: &Ros2Library, ws: &Ros2WaitSet, n_subs: Int, n_timers: Int) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: ws.slot.len() >= ROS2_WAIT_SET_SLOT
  requires: n_subs >= 0
  requires: n_timers >= 0
{
  unsafe {
    let f = lib.p_rcl_wait_set_resize as fn(*UInt8, Int, Int, Int, Int, Int, Int) -> Int;
    let rc = ret_of(f(&ws.slot[0] as *UInt8, n_subs, 0, n_timers, 0, 0, 0));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_wait_set_resize", rc)); }
    return Ok(());
  }
}

/// Add a subscription slot address; returns its index (0-based).
/// Complexity: O(1).
pub fn ros2_wait_set_add_subscription(lib: &Ros2Library, ws: &Ros2WaitSet, sub_ptr: Int) -> Result[Int, Ros2Error]
  requires: lib.handle != 0
  requires: ws.slot.len() >= ROS2_WAIT_SET_SLOT
  requires: sub_ptr != 0
{
  var idx = slot(ROS2_OUT_SLOT);
  unsafe {
    let f = lib.p_rcl_wait_set_add_subscription as fn(*UInt8, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&ws.slot[0] as *UInt8, sub_ptr as *UInt8, &idx[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_wait_set_add_subscription", rc)); }
  }
  return Ok(ros2_slot_u64(&idx, 0));
}

/// Add a timer slot address; returns its index (0-based).
/// Complexity: O(1).
pub fn ros2_wait_set_add_timer(lib: &Ros2Library, ws: &Ros2WaitSet, timer_ptr: Int) -> Result[Int, Ros2Error]
  requires: lib.handle != 0
  requires: ws.slot.len() >= ROS2_WAIT_SET_SLOT
  requires: timer_ptr != 0
{
  var idx = slot(ROS2_OUT_SLOT);
  unsafe {
    let f = lib.p_rcl_wait_set_add_timer as fn(*UInt8, *UInt8, *UInt8) -> Int;
    let rc = ret_of(f(&ws.slot[0] as *UInt8, timer_ptr as *UInt8, &idx[0] as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_wait_set_add_timer", rc)); }
  }
  return Ok(ros2_slot_u64(&idx, 0));
}

/// Wait for readiness: Ok(ret) with ret RCL_RET_OK (something ready) or
/// RCL_RET_TIMEOUT; Err for other codes.
/// Complexity: O(1) beyond rcl.
pub fn ros2_wait(lib: &Ros2Library, ws: &Ros2WaitSet, timeout_ms: Int) -> Result[Int, Ros2Error]
  requires: lib.handle != 0
  requires: ws.slot.len() >= ROS2_WAIT_SET_SLOT
  requires: timeout_ms >= 0
{
  let timeout_ns = timeout_ms * 1000000;
  unsafe {
    let f = lib.p_rcl_wait as fn(*UInt8, Int) -> Int;
    let rc = ret_of(f(&ws.slot[0] as *UInt8, timeout_ns));
    if rc == RCL_RET_OK || rc == RCL_RET_TIMEOUT { return Ok(rc); }
    return Err(ret_err("rcl_wait", rc));
  }
}

/// Whether the subscription at `index` is ready after an rcl_wait
/// (reads the NULL-able pointer slot; false for out-of-range index).
/// Complexity: O(1).
pub fn ros2_wait_set_subscription_fired(lib: &Ros2Library, ws: &Ros2WaitSet, index: Int) -> Bool
  requires: lib.handle != 0
  requires: ws.slot.len() >= ROS2_WAIT_SET_SLOT
  requires: index >= 0
{
  let cap = ros2_slot_u64(&ws.slot, 8);
  if index >= cap { return false; }
  let arr = ros2_slot_u64(&ws.slot, 0);
  if arr == 0 { return false; }
  unsafe {
    return ffi.ptr_read_u64_le((arr + index * 8) as *UInt8) != 0;
  }
}

/// Whether the timer at `index` is ready after an rcl_wait.
/// Complexity: O(1).
pub fn ros2_wait_set_timer_fired(lib: &Ros2Library, ws: &Ros2WaitSet, index: Int) -> Bool
  requires: lib.handle != 0
  requires: ws.slot.len() >= ROS2_WAIT_SET_SLOT
  requires: index >= 0
{
  let cap = ros2_slot_u64(&ws.slot, 40);
  if index >= cap { return false; }
  let arr = ros2_slot_u64(&ws.slot, 32);
  if arr == 0 { return false; }
  unsafe {
    return ffi.ptr_read_u64_le((arr + index * 8) as *UInt8) != 0;
  }
}

/// Whether the wait set handle is valid.
/// Complexity: O(1).
pub fn ros2_wait_set_is_valid(lib: &Ros2Library, ws: &Ros2WaitSet) -> Bool
  requires: lib.handle != 0
  requires: ws.slot.len() >= ROS2_WAIT_SET_SLOT
{
  unsafe {
    let f = lib.p_rcl_wait_set_is_valid as fn(*UInt8) -> UInt8;
    return (f(&ws.slot[0] as *UInt8) as Int) != 0;
  }
}

// =========================================================================
// Callback-free spin
// =========================================================================

/// One callback-free spin: wait on the given subscription/timer slot
/// addresses for up to `timeout_ms`, report which fired, and run
/// rcl_timer_call on fired timers (NULL-callback timers advance state).
/// The caller extracts messages afterwards with ros2_take on its own
/// message buffers. `subs`/`timers` are slot addresses (see ros2_slot_ptr).
/// Complexity: O(n) beyond rcl.
pub fn ros2_spin_once(
  lib: &Ros2Library, ctx: &Ros2Context, subs: &Vec[Int], timers: &Vec[Int], timeout_ms: Int
) -> Result[Ros2SpinResult, Ros2Error]
  requires: lib.handle != 0
  requires: ctx.slot.len() >= ROS2_CONTEXT_SLOT
  requires: timeout_ms >= 0
{
  if subs.len() + timers.len() == 0 {
    return Err(make_err(ROS2_ARG_INVALID, RCL_RET_WAIT_SET_EMPTY, "spin: no subscriptions or timers given"));
  }
  let ws_r = ros2_wait_set_init(lib, ctx, subs.len(), timers.len());
  if !ws_r.is_ok { return Err(ws_r.error); }
  let ws = ws_r.value;

  var i = 0;
  while i < subs.len() {
    let a = ros2_wait_set_add_subscription(lib, &ws, subs[i]);
    if !a.is_ok {
      var ig = ros2_wait_set_fini(lib, &ws);
      return Err(a.error);
    }
    i = i + 1;
  }
  i = 0;
  while i < timers.len() {
    let a = ros2_wait_set_add_timer(lib, &ws, timers[i]);
    if !a.is_ok {
      var ig2 = ros2_wait_set_fini(lib, &ws);
      return Err(a.error);
    }
    i = i + 1;
  }

  let w = ros2_wait(lib, &ws, timeout_ms);
  if !w.is_ok {
    var ig3 = ros2_wait_set_fini(lib, &ws);
    return Err(w.error);
  }
  let wait_ret = w.value;
  var timed_out = false;
  if wait_ret == RCL_RET_TIMEOUT { timed_out = true; }

  var sub_out: Vec[Bool] = Vec[Bool].new();
  i = 0;
  while i < subs.len() {
    var f: Bool = false;
    if !timed_out { f = ros2_wait_set_subscription_fired(lib, &ws, i); }
    sub_out.push(f);
    i = i + 1;
  }
  var timer_out: Vec[Bool] = Vec[Bool].new();
  i = 0;
  while i < timers.len() {
    var f: Bool = false;
    if !timed_out {
      f = ros2_wait_set_timer_fired(lib, &ws, i);
      if f {
        // Dispatch state on a fired timer via its slot address.
        let t = ros2_timer_call_ptr(lib, timers[i]);
        if !t.is_ok {
          var ig4 = ros2_wait_set_fini(lib, &ws);
          return Err(t.error);
        }
      }
    }
    timer_out.push(f);
    i = i + 1;
  }

  var fin = ros2_wait_set_fini(lib, &ws);
  if !fin.is_ok { return Err(fin.error); }
  return Ok(Ros2SpinResult{
    sub_fired: sub_out;
    timer_fired: timer_out;
    timed_out: timed_out;
    wait_ret: wait_ret;
  });
}

/// rcl_timer_call by raw slot address (internal spin helper; exposed for
/// advanced consumers that hold slot addresses).
/// Complexity: O(1).
pub fn ros2_timer_call_ptr(lib: &Ros2Library, timer_ptr: Int) -> Result[Unit, Ros2Error]
  requires: lib.handle != 0
  requires: timer_ptr != 0
{
  unsafe {
    let f = lib.p_rcl_timer_call as fn(*UInt8) -> Int;
    let rc = ret_of(f(timer_ptr as *UInt8));
    if rc != RCL_RET_OK { return Err(ret_err("rcl_timer_call", rc)); }
    return Ok(());
  }
}
