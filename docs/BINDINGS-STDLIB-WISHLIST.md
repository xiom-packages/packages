# Bindings-lane stdlib wishlist (xiom-packages bindings lane)

Stdlib asks collected while building the FFI/binding packages (`xiom.sqlite`
pilot) on the pinned toolchain. Companion file:
`docs/BINDINGS-COMPILER-FINDINGS.md` (defects, not asks).

Format mirrors the shared `docs/STDLIB-WISHLIST.md`:
`| Date | Need | Why (requesters) | Local workaround today | Status |`

| Date | Need | Why (requesters) | Local workaround today | Status |
|---|---|---|---|---|
| 2026-10-08 | `xiom.io.fs`: file delete/remove (`fs_delete`/`fs_remove`) | the `xiom.sqlite` file-backed conformance check has to leave `sqlite_conformance_tmp.db` behind after `close` (no API can remove it); any binding suite that creates artifacts (dbs, log files, extracted fixtures) has the same gap -- the bindings lane will need it again for sdl3/opengl probes | none: name files with a reset-on-open protocol and keep them gitignored; put scratch in the OS temp dir when persistence across runs is not needed | open |
| 2026-10-08 | `xiom.ffi`: an out-param slot helper (`OutSlot`, or `out_slot(n)` + typed `read_i64`/`write_i64`) | every C binding needs `T**`/`int*` out-params (`sqlite3_open`, `sqlite3_prepare_v2`, SDL/GL query APIs next). Today the caller allocates an XIOM `Vec[UInt8]`, pushes 8 zero bytes, passes `as_mut_ptr()`, then reassembles the little-endian value byte-by-byte (private helper in `packages/xiom-sqlite/src/ffi.xi`) | manual `Vec[UInt8]` + `read_u64_le` helper (package-local) | open |
| 2026-10-08 | `xiom.ffi`: make `free` guard-aware, or document the confinement rule loudly | `ffi.alloc` + `ffi.free` inside a confined block spins the guard heap on v0.64.0 (compiler finding B-05: `xiom_guard_alloc` vs libc `free` mismatch). The stdlib module docs currently do not warn; a fixed pair or an explicit "never free inside an unsafe block" note (plus a guard-aware `raw_free`) would remove a silent hard-hang trap for all bindings | avoid malloc/free entirely inside confined blocks (XIOM-owned buffers); module-local `extern "C" { fn malloc/free }` pairs also avoid it | open |
| 2026-10-08 | `xiom.ffi.dl` docs: correct the stale Int-to-pointer-cast warning | the stdlib smoke test (`tests/smoke/smoke_ffi2.xi`) says Int-to-pointer casts are broken "in this build", which deters the exact pattern the bindings lane needs: on v0.64.0, `let f = addr as fn(..) -> T;` inside `unsafe` then calling `f(...)` works and is the enabler for SKIP-style probes (load a DLL at runtime, call only if present). A documented typed-call idiom (or a `dl_call*` helper) would let sdl3/opengl stay port.ps1-clean without C bridges | verified-by-probe: `dl_open` + `dl_sym` + fn-pointer cast work in pure XIOM (bindings scratch probes, 2026-10-08); no local code needed once docs stop warning against it | open |
| 2026-10-08 | `xiom.vec`: zeroed/`with_len` constructor for `Vec[UInt8]` | out-param slots and FFI fill-buffers currently need a push loop (8 pushes per slot in `xiom.sqlite`); `Vec[UInt8].with_len(n)` (zeroed, len == capacity) would remove boilerplate now and for the sdl3/opengl loaders | `while i < n { v.push(0 as UInt8); ... }` per allocation | open |

Notes:

- Items are evidence-driven: W-1/W-2 were hit while building `xiom.sqlite`
  0.2.0; W-3/W-4 block the remaining pilot packages (sdl3/opengl).
- No item asks to break an existing API; the two `xiom.ffi` items are
  additive (helper + docs), plus one behavior decision (guard-aware free)
  that the compiler/stdlib lanes own together.
