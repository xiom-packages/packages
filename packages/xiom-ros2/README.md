# xiom.ros2

> **Status:** `incubating` -- delivered (rcl loader surface, 82/82 x2 on the
> v0.64.5 pin); publish pending lane batch/scope.
> **Scope:** ROS 2 client-library (rcl) bindings via dynamic loading.
> **Deps:** stdlib; **no build-time link** -- resolves the system librcl at
> run time (typed SKIP when absent).

## What this is

Pure-XIOM bindings for the ROS 2 C client library (`rcl`): init/shutdown,
context, node, publisher, subscription, clock, timers, wait sets and a
callback-free spin, plus rosidl type-support resolution. The package ships
zero C sources and links nothing at build time -- every entry point is
resolved from `librcl.so` / `rcl.dll` / `librcl.dylib` through `xiom.ffi.dl`
(the `xiom.ssl`/`xiom.openssl` pattern).

## Quickstart

```xiom
use xiom.ros2;

pub fn main() -> Int {
  let lr = ros2_load();
  if !lr.is_ok {
    // No ROS 2 here: typed SKIP (kind == ROS2_LOAD_ABSENT).
    return 0;
  }
  let lib = lr.value;
  let cr = ros2_context_init(&lib, -1);      // default domain
  if !cr.is_ok { return 1; }
  let ctx = cr.value;
  let nr = ros2_node_init(&lib, &ctx, "talker", "/demo");
  if !nr.is_ok { return 1; }
  let node = nr.value;
  let ts = ros2_typesupport_std_msgs_string();   // std_msgs/String handle
  if ts.is_ok {
    let pr = ros2_publisher_init(&lib, &node, "/chatter", ts.value.addr, ROS2_QOS_DEFAULT);
    // ros2_publish(&lib, &p, msg_ptr)  -- caller-owned message buffer
  }
  var ig1 = ros2_node_fini(&lib, &node);
  var ig2 = ros2_context_shutdown(&lib, &ctx);
  var ig3 = ros2_context_fini(&lib, &ctx);
  var ig4 = ros2_close(&lib);
  return 0;
}
```

Subscriptions are polled: `ros2_take` returns `Ok(false)` when nothing is
available and `Ok(true)` after filling a caller-owned message buffer.
`ros2_spin_once` waits on subscription/timer slot addresses and reports what
fired (`Ros2SpinResult`); message extraction stays with the caller (there is
no callback bridging in the FFI yet -- see ROADMAP v0.3.0).

## Requirements (run-time leg)

- **Windows x64 / AArch64-Linux (Pi)**: supported live hosts.
  - Windows: install ROS 2 and run its `setup.ps1` so the prefix lib dir is
    on `PATH` (`rcl.dll`).
  - Linux: source `/opt/ros/<distro>/setup.bash` before running (the ament
    prefix lib dir carries `librcl.so`).
  - x86-64 Linux (System V): refused **typed** (`ROS2_ABI_HOST`) -- the
    by-value `rcl_allocator_t` channel is not expressible there; the suite
    reports SKIP on those hosts (documented in SPEC section 3).
- **No ROS 2 installed**: every entry point returns the typed
  `ROS2_LOAD_ABSENT` classification and the suite prints SKIP lines (green).
- ABI layouts are pinned to rcl rolling `e5754f0d` / rmw `4158e1ed` /
  rcutils `0f55f24e` (version matrix + re-carve procedure in
  SPEC.md/PROVENANCE.md). Humble's missing `rcl_timer_init2` is handled by
  a loader fallback.

## Docs

| File | What |
|------|------|
| `SPEC.md` | declared surface, ABI channel + layout pin, contracts, gates |
| `ROADMAP.md` | delivered state + next phases (callbacks, services, actions) |
| `AUDIT.md` | probes, oracle semantics, suite evidence, **coverage table** |
| `PROVENANCE.md` | upstream clones (Apache-2.0), what was taken, nothing vendored |
| `tests/test_conformance.xi` | 82 checks: deterministic goldens + gated live arm |

```powershell
.\scripts\port.ps1 -Package xiom.ros2 -TimeoutSec 300
```
