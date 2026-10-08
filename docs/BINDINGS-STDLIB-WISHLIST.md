# Bindings-lane stdlib wishlist (xiom-packages bindings lane)

Stdlib asks collected while building the FFI/binding packages. Companion:
`docs/BINDINGS-COMPILER-FINDINGS.md` (defects, not asks).

Format mirrors the shared `docs/STDLIB-WISHLIST.md`:
`| Date | Need | Why (requesters) | Local workaround today | Status |`

| Date | Need | Why (requesters) | Local workaround today | Status |
|---|---|---|---|---|
| 2026-10-08 | `xiom.io.fs`: file delete/remove (`fs_delete`/`fs_remove`) | the `xiom.sqlite` file-backed conformance check has to leave `sqlite_conformance_tmp.db` behind after `close`; any binding suite that creates artifacts has the same gap | none: reset-on-open protocol + gitignored temp files | **DELIVERED (stdlib 0.64.2): `fs_remove(path) -> Result[Unit, Str]` (plus `remove_file`).** Converged with the shared wishlist's 2026-10-05 row (requesters `xiom.static`/`xiom.kv`). `xiom.sqlite` will adopt `fs_remove` for its temp db in its next touch (deferred: no drive-by edits to a published package) |
| 2026-10-08 | `xiom.ffi`: an out-param slot helper | every C binding needs `T**`/`int*` out-params (`sqlite3_open`, `sdl3` window size, `glfw` version, `raylib`...) | package-local `Vec[UInt8]` slots read byte-wise (sqlite/sdl3/glfw/raylib) | **LARGELY PRE-EXISTING:** `xiom.ffi` already ships `SafePtr` (`safe_ptr_alloc` + typed `safe_ptr_read/write_u16/u32/i64/f32/f64` + `safe_ptr_free`) and `FFIBuffer` (`buffer_new/write/read`). The real gap is documentation: the `xiom.ffi.dl` smoke note + a short "out-param recipe" would have saved the byte-assembly workaround. Down-graded to a docs ask; no new API strictly needed. NOTE: packages whose FFI module is named `...ffi` cannot import `xiom.ffi` (alias shadowing, finding B-07) -- name the module differently if you want those helpers |
| 2026-10-08 | `xiom.ffi`: make `free` guard-aware, or document the confinement rule loudly | `ffi.alloc` + `ffi.free` inside a confined block spins the guard heap (compiler finding B-05; STILL OPEN at v0.64.1; watchdog-verified) | avoid malloc/free inside confined blocks entirely (XIOM-owned buffers) | open (pairs with B-05; stdlib + compiler lanes) |
| 2026-10-08 | `xiom.ffi.dl` docs: correct the stale Int-to-pointer-cast warning | the stdlib smoke test said casts were "broken in this build", deterring the fn-pointer idiom the bindings lane depends on | verified-by-probe: `dl_open` + `dl_sym` + `addr as fn(..) -> T` work | **DELIVERED (stdlib 0.64.2): `dl.xi` note now reads "the Int-to-pointer cast used to be broken; on v0.64.0 the typed ..."** |
| 2026-10-08 | `xiom.vec`: zeroed/`with_len` constructor for `Vec[UInt8]` | out-param slots and FFI fill-buffers need a push loop (8 pushes per slot) | `while i < n { v.push(0 as UInt8); }` | open (no `with_len`/`zeroed`/`filled` found in `xiom.collections`, stdlib 0.64.2; mitigated by `SafePtr`/`FFIBuffer` for pointers, still useful for Vec-based buffers) |

## Stdlib response check (2026-10-08)

- stdlib **0.64.2** is released (pin v0.64.1; registry publish queue recorded
  in the stdlib repo). Verified in `E:\xiom-lang\stdlib`:
  - `xiom.io.fs.fs_remove` exists (W-1 delivered; also serves the shared
    wishlist's 2026-10-05 row).
  - `dl.xi` stale cast warning corrected (W-4 delivered).
  - `xiom.ffi` `SafePtr`/`FFIBuffer` typed slot helpers pre-existed (W-2
    re-scoped to a docs ask).
  - No `Vec.with_len`/`zeroed` (W-5 open); guard-aware `free` not present
    (W-3 open, compiler-side B-05 still open at v0.64.1).
- The bindings suites are unaffected by the 0.64.2 stdlib (spot-checked via
  `port.ps1` for `xiom.glfw` and `xiom.sqlite` after the recon; see
  `BINDINGS-SESSION.md`).
