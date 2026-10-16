# xiom.epos -- roadmap

## 0.1.0 (shipped in-lane)

Closed-SDK loader slice: multi-soname, SKIP-safe, typed 179/179 declared
surface (177 `VCS_*` + 2 Linux-layer helpers), flat outcomes, suite SKIP x2 +
present x2 on v0.64.5.  See SPEC.md.

## 0.2 candidates (priority order)

1. **Linux lane**: `libEposCmd.so` binding with the LP64 `long` variants
   (SPEC delta D1); extend the Linux-layer helpers (`CreateCommunication` /
   `DeleteCommunication`) to a real exercised path; platform row
   `linux-x64`.
2. **Hardware bring-up suite (gated)**: an opt-in, device-gated test that
   opens a real EPOS4 (USB / CANopen), runs enable -> profile position ->
   wait -> disable, stores nothing.  Gated on `EPOS_DEVICE=1`-style opt-in so
   CI stays SKIP-safe.
3. **Selection helper process**: a tiny helper binary that performs
   device-name/port/baudrate enumeration in a short-lived child process
   (D4 workaround) with typed results over stdout.
4. **Object-dictionary ergonomics**: typed `epos_set_object_bytes` helpers
   (u8/u16/u32/i32/UInt64 packers into a slot) so callers stop hand-packing.
5. **Error-code tables**: once the official documentation PDF is obtainable
   from a permitted host, add a documented error-code cluster
   (`EPOS_ERR_*`) for `VCS_GetErrorInfo` lookups.
6. **Newer header revisions**: re-measure the declared cluster against a
   newer public header snapshot (post-6.6 API additions) and record SPEC
   deltas; the loader/counts are generated from the name list, so extension
   is mechanical.

## Non-goals

* Vendoring any part of the closed SDK (doctrine, PROVENANCE sec. 1).
* 32-bit Windows targets in 0.1.0 (`EposCmd.dll` stays a declared candidate).
