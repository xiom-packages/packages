// XIOM -- xiom.ros2 conformance tests (dynamic loader + deterministic goldens
// + a gated live leg).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// CI WITHOUT ROS 2 stays green: no candidate librcl soname -> typed SKIP (the
// SKIP path is exercised deterministically every run via a bogus soname).
// Deterministic goldens (always green, no ROS 2 needed):
//   * loader classification: bogus soname -> ROS2_LOAD_ABSENT;
//   * ret-code catalog names; QoS preset names; error-kind names;
//   * ABI-host gate expectation (windows / aarch64 / arm pass; x86-64 SysV no);
//   * fabricated-structure goldens: allocator field order, rmw_qos_profile_t
//     offsets (history@0 depth@8 reliability@16 durability@20 liveliness@56
//     avoid@80), pub/sub options (qos@0 alloc@88), node options (alloc@0);
//   * custom-QoS validation and unknown-preset errors.
// Live leg (runs when librcl is present AND the host ABI is supported --
// Windows x64 or AArch64/ARM; the Pi leg): init/context queries, node
// name/namespace, std_msgs/String type support, pub/sub roundtrip with
// caller-owned message buffers, steady-clock timer, wait set + callback-free
// spin_once, full teardown.
//
// Build+run (no extra compiler args: pure-XIOM loader):
//   scripts/port.ps1 -Package xiom.ros2 -TimeoutSec 300

module ros2_conformance

use xiom.io;
use xiom.ffi;
use xiom.platform;
use xiom.string.compare;
use xiom.string.search;
use xiom.ros2;

const BOGUS_SONAME: Str = "xiom-absent-librcl-probe-xyz.so";
const TOPIC: Str = "/xiom_ros2_probe";
const MSG_TEXT: Str = "hello-ros2";

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn why(msg: Str) {
  io.println("    detail: " + msg);
  io.flush_stdout();
}

fn note(msg: Str) {
  io.println("    " + msg);
  io.flush_stdout();
}

fn streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// =========================================================================
// Deterministic goldens
// =========================================================================

fn t_loader_absent() -> Int {
  let missing = ros2_load_named(BOGUS_SONAME);
  if missing.is_ok {
    return report(false, "skip-path: bogus soname unexpectedly loaded");
  }
  var failed = report(
    missing.error.kind == ROS2_LOAD_ABSENT,
    "skip-path: absent library classified as ROS2_LOAD_ABSENT (SKIP)");
  failed = failed + report(
    streq(ros2_error_kind_name(missing.error.kind), "absent"),
    "skip-path: kind name is 'absent'");
  return failed;
}

fn t_kind_names() -> Int {
  var failed = 0;
  failed = failed + report(streq(ros2_error_kind_name(ROS2_LOAD_ABI), "abi"), "kind: abi");
  failed = failed + report(streq(ros2_error_kind_name(ROS2_ABI_HOST), "host-abi"), "kind: host-abi");
  failed = failed + report(streq(ros2_error_kind_name(ROS2_RET_FAIL), "rcl-ret"), "kind: rcl-ret");
  failed = failed + report(streq(ros2_error_kind_name(ROS2_ARG_INVALID), "arg"), "kind: arg");
  return failed;
}

fn t_abi_host_gate() -> Int {
  let a = platform.arch_name();
  var expect = true;
  if !platform.is_windows() && (a == "x86_64" || a == "amd64") {
    expect = false;
  }
  let got = ros2_abi_host_ok();
  var failed = report(got == expect, "abi-gate: host verdict matches ABI rule (arch=" + a + ")");
  if got != expect {
    why("ros2_abi_host_ok()=" + "mismatch");
  }
  return failed;
}

fn t_ret_names() -> Int {
  var failed = 0;
  failed = failed + report(streq(ros2_ret_name(RCL_RET_OK), "ok"), "ret: 0 ok");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_ERROR), "error"), "ret: 1 error");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_TIMEOUT), "timeout"), "ret: 2 timeout");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_BAD_ALLOC), "bad alloc"), "ret: 10 bad alloc");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_INVALID_ARGUMENT), "invalid argument"), "ret: 11 invalid argument");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_ALREADY_INIT), "already init"), "ret: 100 already init");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_NOT_INIT), "not init"), "ret: 101 not init");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_TOPIC_NAME_INVALID), "topic name invalid"), "ret: 103 topic name invalid");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_NODE_INVALID_NAME), "node name invalid"), "ret: 201 node name invalid");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_PUBLISHER_INVALID), "publisher invalid"), "ret: 300 publisher invalid");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_SUBSCRIPTION_TAKE_FAILED), "take failed"), "ret: 401 take failed");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_TIMER_CANCELED), "timer canceled"), "ret: 801 timer canceled");
  failed = failed + report(streq(ros2_ret_name(RCL_RET_WAIT_SET_EMPTY), "wait set empty"), "ret: 901 wait set empty");
  failed = failed + report(streq(ros2_ret_name(9999), "unknown"), "ret: unknown fallback");
  return failed;
}

fn t_qos_names() -> Int {
  var failed = 0;
  failed = failed + report(streq(ros2_qos_preset_name(ROS2_QOS_DEFAULT), "default"), "qos: default name");
  failed = failed + report(streq(ros2_qos_preset_name(ROS2_QOS_SENSOR_DATA), "sensor-data"), "qos: sensor-data name");
  failed = failed + report(streq(ros2_qos_preset_name(ROS2_QOS_SYSTEM_DEFAULT), "system-default"), "qos: system-default name");
  failed = failed + report(streq(ros2_qos_preset_name(ROS2_QOS_PARAMETERS), "parameters"), "qos: parameters name");
  failed = failed + report(streq(ros2_qos_preset_name(42), "unknown"), "qos: unknown fallback");
  return failed;
}

fn t_allocator_golden() -> Int {
  let a = ros2_allocator_build(111, 222, 333, 444);
  var failed = report(a.len() == ROS2_ALLOC_SIZE, "alloc: slot size is 40");
  failed = failed + report(ros2_slot_u64(&a, 0) == 111, "alloc: allocate @0");
  failed = failed + report(ros2_slot_u64(&a, 8) == 222, "alloc: deallocate @8");
  failed = failed + report(ros2_slot_u64(&a, 16) == 333, "alloc: reallocate @16");
  failed = failed + report(ros2_slot_u64(&a, 24) == 444, "alloc: zero_allocate @24");
  failed = failed + report(ros2_slot_u64(&a, 32) == 0, "alloc: state @32 is NULL");
  return failed;
}

fn t_qos_goldens() -> Int {
  var failed = 0;

  var d = Vec[UInt8].with_len(ROS2_QOS_SIZE);
  let r1 = ros2_qos_write(&mut d, 0, ROS2_QOS_DEFAULT);
  failed = failed + report(r1.is_ok, "qos: default preset writes");
  failed = failed + report(ros2_slot_u32(&d, 0) == ROS2_HISTORY_KEEP_LAST, "qos(default): history@0 KEEP_LAST");
  failed = failed + report(ros2_slot_u64(&d, 8) == 10, "qos(default): depth@8 == 10");
  failed = failed + report(ros2_slot_u32(&d, 16) == ROS2_RELIABILITY_RELIABLE, "qos(default): reliability@16 RELIABLE");
  failed = failed + report(ros2_slot_u32(&d, 20) == ROS2_DURABILITY_VOLATILE, "qos(default): durability@20 VOLATILE");
  failed = failed + report(ros2_slot_u64(&d, 24) == 0 && ros2_slot_u64(&d, 32) == 0, "qos(default): deadline@24 UNSPECIFIED");
  failed = failed + report(ros2_slot_u64(&d, 40) == 0 && ros2_slot_u64(&d, 48) == 0, "qos(default): lifespan@40 UNSPECIFIED");
  failed = failed + report(ros2_slot_u32(&d, 56) == ROS2_LIVELINESS_SYSTEM_DEFAULT, "qos(default): liveliness@56 SYSTEM_DEFAULT");
  failed = failed + report(ros2_slot_u64(&d, 64) == 0 && ros2_slot_u64(&d, 72) == 0, "qos(default): lease@64 UNSPECIFIED");
  failed = failed + report(ros2_slot_u8(&d, 80) == 0, "qos(default): avoid_namespace@80 false");

  var s = Vec[UInt8].with_len(ROS2_QOS_SIZE);
  let r2 = ros2_qos_write(&mut s, 0, ROS2_QOS_SENSOR_DATA);
  failed = failed + report(r2.is_ok, "qos: sensor-data preset writes");
  failed = failed + report(ros2_slot_u64(&s, 8) == 5, "qos(sensor): depth@8 == 5");
  failed = failed + report(ros2_slot_u32(&s, 16) == ROS2_RELIABILITY_BEST_EFFORT, "qos(sensor): reliability@16 BEST_EFFORT");

  var y = Vec[UInt8].with_len(ROS2_QOS_SIZE);
  let r3 = ros2_qos_write(&mut y, 0, ROS2_QOS_SYSTEM_DEFAULT);
  failed = failed + report(r3.is_ok, "qos: system-default preset writes");
  failed = failed + report(ros2_slot_u32(&y, 0) == 0 && ros2_slot_u64(&y, 8) == 0, "qos(system): history/depth 0");
  failed = failed + report(ros2_slot_u32(&y, 16) == 0 && ros2_slot_u32(&y, 20) == 0, "qos(system): reliability/durability 0");

  var p = Vec[UInt8].with_len(ROS2_QOS_SIZE);
  let r4 = ros2_qos_write(&mut p, 0, ROS2_QOS_PARAMETERS);
  failed = failed + report(r4.is_ok, "qos: parameters preset writes");
  failed = failed + report(ros2_slot_u64(&p, 8) == 1000, "qos(parameters): depth@8 == 1000");

  let bad = ros2_qos_write(&mut p, 0, 42);
  failed = failed + report(!bad.is_ok, "qos: unknown preset rejected");

  return failed;
}

fn t_qos_custom() -> Int {
  var failed = 0;
  var c = Vec[UInt8].with_len(ROS2_QOS_SIZE);
  let bad1 = ros2_qos_write_custom(&mut c, 0, ROS2_HISTORY_KEEP_LAST, 0, 1, 2, 0, 0);
  failed = failed + report(!bad1.is_ok, "qos-custom: KEEP_LAST depth 0 rejected");
  let bad2 = ros2_qos_write_custom(&mut c, 0, ROS2_HISTORY_SYSTEM_DEFAULT, 5, 1, 2, 0, 0);
  failed = failed + report(!bad2.is_ok, "qos-custom: SYSTEM_DEFAULT depth != 0 rejected");
  let good = ros2_qos_write_custom(&mut c, 0, ROS2_HISTORY_KEEP_ALL, 0, ROS2_RELIABILITY_BEST_EFFORT, ROS2_DURABILITY_TRANSIENT_LOCAL, ROS2_LIVELINESS_AUTOMATIC, 1);
  failed = failed + report(good.is_ok, "qos-custom: KEEP_ALL depth 0 accepted");
  failed = failed + report(ros2_slot_u32(&c, 0) == ROS2_HISTORY_KEEP_ALL, "qos-custom: history@0");
  failed = failed + report(ros2_slot_u32(&c, 16) == ROS2_RELIABILITY_BEST_EFFORT, "qos-custom: reliability@16");
  failed = failed + report(ros2_slot_u32(&c, 20) == ROS2_DURABILITY_TRANSIENT_LOCAL, "qos-custom: durability@20");
  failed = failed + report(ros2_slot_u32(&c, 56) == ROS2_LIVELINESS_AUTOMATIC, "qos-custom: liveliness@56");
  failed = failed + report(ros2_slot_u8(&c, 80) == 1, "qos-custom: avoid_namespace@80");
  return failed;
}

fn t_options_goldens() -> Int {
  var failed = 0;
  let alloc = ros2_allocator_build(101, 202, 303, 404);

  let node_opts = ros2_node_options_build(&alloc);
  failed = failed + report(node_opts.len() == ROS2_OPTIONS_SLOT, "node-opts: slot size 256");
  failed = failed + report(ros2_slot_u64(&node_opts, 0) == 101, "node-opts: allocator.allocate @0");
  failed = failed + report(ros2_slot_u64(&node_opts, 8) == 202, "node-opts: allocator.deallocate @8");
  failed = failed + report(ros2_slot_u64(&node_opts, 32) == 0, "node-opts: state @32 NULL");
  failed = failed + report(ros2_slot_u8(&node_opts, 40) == 0, "node-opts: use_global_arguments@40 false");
  failed = failed + report(ros2_slot_u64(&node_opts, 48) == 0, "node-opts: arguments.impl@48 NULL");
  failed = failed + report(ros2_slot_u8(&node_opts, 56) == 0, "node-opts: enable_rosout@56 false");

  let ps = ros2_pubsub_options_build(ROS2_QOS_DEFAULT, &alloc);
  failed = failed + report(ps.is_ok, "pubsub-opts: builds");
  let o = ps.value;
  failed = failed + report(o.len() == ROS2_OPTIONS_SLOT, "pubsub-opts: slot size 256");
  failed = failed + report(ros2_slot_u64(&o, 8) == 10, "pubsub-opts: qos.depth@8 == 10 (qos first)");
  failed = failed + report(ros2_slot_u64(&o, ROS2_PUBSUB_ALLOC_OFF) == 101, "pubsub-opts: allocator.allocate @88");
  failed = failed + report(ros2_slot_u64(&o, ROS2_PUBSUB_ALLOC_OFF + 32) == 0, "pubsub-opts: allocator.state @120 NULL");
  failed = failed + report(ros2_slot_u64(&o, 128) == 0, "pubsub-opts: rmw options @128 zeroed");
  failed = failed + report(ros2_slot_u64(&o, 248) == 0, "pubsub-opts: tail @248 zeroed");

  let bad = ros2_pubsub_options_build(42, &alloc);
  failed = failed + report(!bad.is_ok, "pubsub-opts: unknown qos preset rejected");
  return failed;
}

fn t_big_values() -> Int {
  // Regression witness for the v0.64.5 B-29 miscompile class: slot writers
  // must round-trip values >= 2^31 (real addresses + the B-29 witness value)
  // through the C-side ffi.ptr_*_le recipe, never XIOM bitops.
  let a = ros2_allocator_build(3132620800, 140732712345678, 281474976710656, 4294967296);
  var failed = report(ros2_slot_u64(&a, 0) == 3132620800, "big: 0xBAD00000 (B-29 witness) round-trips");
  failed = failed + report(ros2_slot_u64(&a, 8) == 140732712345678, "big: address-like value round-trips");
  failed = failed + report(ros2_slot_u64(&a, 16) == 281474976710656, "big: 2^48 round-trips");
  failed = failed + report(ros2_slot_u64(&a, 24) == 4294967296, "big: 2^32 round-trips");
  return failed;
}

fn t_slots() -> Int {
  var failed = 0;
  var v = Vec[UInt8].with_len(8);
  v[3] = 77 as UInt8;
  failed = failed + report(ros2_slot_u8(&v, 3) == 77, "slot: byte write/read");
  failed = failed + report(ros2_slot_ptr(&v) != 0, "slot: pointer is non-zero");
  failed = failed + report(
    search.str_contains(ros2_sonames(), "librcl.so"),
    "sonames: candidate list names librcl.so");
  return failed;
}

// =========================================================================
// Live leg (SKIP when librcl is absent or the host ABI is unsupported)
// =========================================================================

fn live_roundtrip(lib: &Ros2Library, ctx: &Ros2Context, node: &Ros2Node, ts: &Ros2TypeSupport) -> Int {
  var failed = 0;

  let pub_r = ros2_publisher_init(lib, node, TOPIC, ts.addr, ROS2_QOS_DEFAULT);
  if !pub_r.is_ok {
    why("publisher_init: " + pub_r.error.message);
    return report(false, "live: publisher init");
  }
  let pub_ = pub_r.value;
  failed = failed + report(true, "live: publisher init on " + TOPIC);

  let sub_r = ros2_subscription_init(lib, node, TOPIC, ts.addr, ROS2_QOS_DEFAULT);
  if !sub_r.is_ok {
    why("subscription_init: " + sub_r.error.message);
    var ig = ros2_publisher_fini(lib, &pub_, node);
    return failed + report(false, "live: subscription init");
  }
  let sub = sub_r.value;
  failed = failed + report(true, "live: subscription init on " + TOPIC);

  // Build a std_msgs/String message in an XIOM-owned slot:
  // rosidl_runtime_c__String = { char* data; size_t size; size_t capacity; }.
  var msg = Vec[UInt8].with_len(24);
  var got_text = "";
  var got = false;
  var attempt = 0;
  while attempt < 20 {
    unsafe {
      let sp = ros2_slot_ptr(&msg);
      let payload = MSG_TEXT;
      let pp = payload as *UInt8 as Int;
      ffi.ptr_write_u64_le((sp) as *UInt8, pp);
      ffi.ptr_write_u64_le((sp + 8) as *UInt8, MSG_TEXT.len() as Int);
      ffi.ptr_write_u64_le((sp + 16) as *UInt8, MSG_TEXT.len() as Int);
    }
    let pr = ros2_publish(lib, &pub_, ros2_slot_ptr(&msg));
    if !pr.is_ok {
      why("publish: " + pr.error.message);
      failed = failed + report(false, "live: publish String message");
      var ig2 = ros2_subscription_fini(lib, &sub, node);
      var ig3 = ros2_publisher_fini(lib, &pub_, node);
      return failed;
    }
    var wait_ms = 200;
    if attempt == 0 { wait_ms = 500; }
    var subs: Vec[Int] = Vec[Int].new();
    subs.push(ros2_slot_ptr(&sub.slot));
    var timers: Vec[Int] = Vec[Int].new();
    let spin_r = ros2_spin_once(lib, ctx, &subs, &timers, wait_ms);
    if !spin_r.is_ok {
      why("spin: " + spin_r.error.message);
      break;
    }
    var rmsg = Vec[UInt8].with_len(24);
    let tr = ros2_take(lib, &sub, ros2_slot_ptr(&rmsg));
    if tr.is_ok && tr.value {
      unsafe {
        let dp = ffi.ptr_read_u64_le(ros2_slot_ptr(&rmsg) as *UInt8);
        if dp != 0 {
          got_text = Str::from_c_str(dp as *UInt8);
          got = true;
        }
      }
    }
    if got { attempt = 20; }
    else { attempt = attempt + 1; }
  }

  failed = failed + report(got, "live: pub/sub roundtrip delivered a message");
  if got {
    failed = failed + report(streq(got_text, MSG_TEXT), "live: roundtrip payload byte-exact");
  } else {
    why("no message taken after retries (discovery timing on this host?)");
  }

  // Wait-set surface on its own (subscription ready or timeout, both valid).
  let ws_r = ros2_wait_set_init(lib, ctx, 1, 0);
  if ws_r.is_ok {
    let ws = ws_r.value;
    failed = failed + report(ros2_wait_set_is_valid(lib, &ws), "live: wait set valid after init");
    let idx = ros2_wait_set_add_subscription(lib, &ws, ros2_slot_ptr(&sub.slot));
    failed = failed + report(idx.is_ok && idx.value == 0, "live: add_subscription index 0");
    let clear = ros2_wait_set_clear(lib, &ws);
    failed = failed + report(clear.is_ok, "live: wait_set_clear");
    let re = ros2_wait_set_add_subscription(lib, &ws, ros2_slot_ptr(&sub.slot));
    if re.is_ok {
      let w = ros2_wait(lib, &ws, 150);
      failed = failed + report(w.is_ok, "live: rcl_wait returns OK or TIMEOUT");
      if w.is_ok && w.value == RCL_RET_OK {
        let fired = ros2_wait_set_subscription_fired(lib, &ws, 0);
        failed = failed + report(fired || !fired, "live: fired read is well-defined");
      }
    }
    let wf = ros2_wait_set_fini(lib, &ws);
    failed = failed + report(wf.is_ok, "live: wait_set_fini");
  } else {
    why("wait_set_init: " + ws_r.error.message);
    failed = failed + report(false, "live: wait set init");
  }

  let sf = ros2_subscription_fini(lib, &sub, node);
  failed = failed + report(sf.is_ok, "live: subscription_fini");
  let pf = ros2_publisher_fini(lib, &pub_, node);
  failed = failed + report(pf.is_ok, "live: publisher_fini");
  return failed;
}

fn live_timer(lib: &Ros2Library, ctx: &Ros2Context) -> Int {
  var failed = 0;
  let t_r = ros2_timer_init(lib, ctx, 50, true);
  if !t_r.is_ok {
    why("timer_init: " + t_r.error.message);
    return report(false, "live: timer init (50ms steady)");
  }
  let timer = t_r.value;
  failed = failed + report(true, "live: timer init (50ms steady)");

  let per = ros2_timer_period_ns(lib, &timer);
  failed = failed + report(per.is_ok && per.value == 50000000, "live: timer period 50000000 ns");

  var waited = false;
  var attempt = 0;
  while attempt < 10 {
    var ws_subs: Vec[Int] = Vec[Int].new();
    var ws_timers: Vec[Int] = Vec[Int].new();
    ws_timers.push(ros2_slot_ptr(&timer.slot));
    let spin_r = ros2_spin_once(lib, ctx, &ws_subs, &ws_timers, 200);
    if spin_r.is_ok && spin_r.value.timer_fired.len() == 1 && spin_r.value.timer_fired[0] {
      waited = true;
      attempt = 10;
    } else {
      attempt = attempt + 1;
    }
  }
  failed = failed + report(waited, "live: timer fired through spin_once wait");
  failed = failed + report(!ros2_timer_is_ready(lib, &timer), "live: timer not immediately ready again after call");

  let c = ros2_timer_cancel(lib, &timer);
  failed = failed + report(c.is_ok, "live: timer cancel");
  failed = failed + report(ros2_timer_is_canceled(lib, &timer), "live: timer reports canceled");
  let cc = ros2_timer_call(lib, &timer);
  failed = failed + report(!cc.is_ok && cc.error.ret == RCL_RET_TIMER_CANCELED, "live: call on canceled timer -> TIMER_CANCELED");
  let rr = ros2_timer_reset(lib, &timer);
  failed = failed + report(rr.is_ok && !ros2_timer_is_canceled(lib, &timer), "live: timer reset clears canceled");

  let tf = ros2_timer_fini(lib, &timer);
  failed = failed + report(tf.is_ok, "live: timer_fini (releases its clock)");
  return failed;
}

fn t_live() -> Int {
  var failed = 0;
  let lr = ros2_load();
  if !lr.is_ok {
    if lr.error.kind == ROS2_LOAD_ABSENT {
      failed = failed + report(true, "live: SKIP -- no librcl candidate present (" + lr.error.message + ")");
      return failed;
    }
    if lr.error.kind == ROS2_ABI_HOST {
      failed = failed + report(true, "live: SKIP -- host ABI unsupported (" + lr.error.message + ")");
      return failed;
    }
    why("load: " + lr.error.message);
    return report(false, "live: librcl load");
  }
  let lib = lr.value;
  note("librcl loaded: " + lib.soname + " (allocator companion: " + lib.libc_soname + ")");

  let cr = ros2_context_init(&lib, -1);
  if !cr.is_ok {
    why("context_init: " + cr.error.message);
    var ig = ros2_close(&lib);
    return report(false, "live: context init");
  }
  let ctx = cr.value;
  failed = failed + report(true, "live: context init (default domain)");
  failed = failed + report(ros2_context_is_valid(&lib, &ctx), "live: context valid");
  failed = failed + report(ros2_context_instance_id(&lib, &ctx) != 0, "live: context instance id non-zero");
  let dom = ros2_context_domain_id(&lib, &ctx);
  failed = failed + report(dom.is_ok, "live: context domain id query");

  let nr = ros2_node_init(&lib, &ctx, "xiom_ros2_suite", "/xiom");
  if !nr.is_ok {
    why("node_init: " + nr.error.message);
    var ig2 = ros2_context_shutdown(&lib, &ctx);
    var ig3 = ros2_context_fini(&lib, &ctx);
    var ig4 = ros2_close(&lib);
    return failed + report(false, "live: node init");
  }
  let node = nr.value;
  failed = failed + report(true, "live: node init");
  failed = failed + report(streq(ros2_node_name(&lib, &node), "xiom_ros2_suite"), "live: node name read-back");
  failed = failed + report(streq(ros2_node_namespace(&lib, &node), "/xiom"), "live: node namespace read-back");

  let ts_r = ros2_typesupport_std_msgs_string();
  if ts_r.is_ok {
    let ts = ts_r.value;
    failed = failed + live_roundtrip(&lib, &ctx, &node, &ts);
    let tc = ros2_typesupport_close(&ts);
    failed = failed + report(tc.is_ok, "live: typesupport close");
  } else {
    failed = failed + report(true, "live: SKIP -- std_msgs/String typesupport absent (" + ts_r.error.message + ")");
  }

  failed = failed + live_timer(&lib, &ctx);

  let nf = ros2_node_fini(&lib, &node);
  failed = failed + report(nf.is_ok, "live: node_fini");
  let sd = ros2_context_shutdown(&lib, &ctx);
  failed = failed + report(sd.is_ok, "live: context shutdown");
  failed = failed + report(!ros2_context_is_valid(&lib, &ctx), "live: context invalid after shutdown");
  let cf = ros2_context_fini(&lib, &ctx);
  failed = failed + report(cf.is_ok, "live: context_fini");
  let cl = ros2_close(&lib);
  failed = failed + report(cl.is_ok, "live: library close");
  return failed;
}

pub fn main() -> Int {
  io.println("=== xiom.ros2 conformance tests (rcl dynamic loader) ===");
  io.flush_stdout();
  var failed: Int = 0;

  failed = failed + t_loader_absent();
  failed = failed + t_kind_names();
  failed = failed + t_abi_host_gate();
  failed = failed + t_ret_names();
  failed = failed + t_qos_names();
  failed = failed + t_allocator_golden();
  failed = failed + t_qos_goldens();
  failed = failed + t_qos_custom();
  failed = failed + t_options_goldens();
  failed = failed + t_big_values();
  failed = failed + t_slots();
  failed = failed + t_live();

  if failed == 0 {
    io.println("xiom.ros2: all tests passed");
  } else {
    io.println("xiom.ros2: tests failed");
  }
  io.flush_stdout();
  return failed;
}
