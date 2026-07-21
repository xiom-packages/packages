# AUDIT — xiom-miniaudio Compiler Gaps

> **Binding strategy:** Due to compiler gaps listed below, miniaudio is bound via a
> flat-ABI C bridge (`bridge/xiom_ma_bridge.c`) rather than direct `extern "C"` to
> the native miniaudio API. The bridge exposes int64_t opaque handles and flat
> primitive parameters — no struct passing, no callbacks cross the FFI boundary.

---

## Active Gaps (require compiler work to eliminate the C bridge)

### GAP-MA-01 — Struct return by value from `extern "C"`

- **What:** `ma_device_config_init()`, `ma_engine_config_init()`, etc. return C
  structs by value. XIOM's `extern "C"` ABI currently supports only scalar types
  (`Int`, `Int32`, `Float32`, `Float64`, `Str`, `*T`) as return values.
- **Impact:** Cannot call any `_init()` or config factory function directly.
- **Workaround:** C bridge allocates and initializes configs internally.
- **Minimal repro:**
  ```c
  // C side
  typedef struct { int x; float y; } Foo;
  Foo make_foo(void);  // returns struct by value
  ```
  ```xiom
  extern "C" { fn make_foo() -> Int }  // FAILS: struct-by-value not representable
  ```
- **Spec reference:** AI_CONTEXT.md L509 (`extern "C"`) — no struct ABI defined.

### GAP-MA-02 — C function pointers / callbacks

- **What:** The device API requires a data callback:
  `void callback(ma_device*, void*, const void*, ma_uint32)`.
  XIOM cannot pass an XIOM function reference as a C function pointer.
- **Impact:** `ma_device` low-level API is unusable. Cannot register `dataCallback`,
  `notificationCallback`, or `stopCallback` from XIOM.
- **Workaround:** C bridge uses the engine API which manages the device callback
  internally; no user callback crosses the FFI boundary.
- **Minimal repro:**
  ```xiom
  extern "C" {
    fn set_callback(cb: fn(Int) -> Int)  // FAILS: fn type not representable as C ptr
  }
  ```
- **Spec reference:** No XIOM-to-C function pointer lowering defined.

### GAP-MA-03 — Struct field access (layout / offset)

- **What:** Miniaudio objects are transparent structs. To configure playback
  format, channel count, or device ID, the caller must write to struct fields
  (e.g. `config.playback.format = ma_format_f32`). XIOM has no `struct.field`
  syntax for `extern "C"` memory nor `offsetof` / pointer-arithmetic primitives.
- **Impact:** Cannot set or read any struct member from XIOM.
- **Workaround:** Configuration parameters are passed as flat function arguments
  to the C bridge, which sets the struct fields internally.
- **Minimal repro:**
  ```xiom
  extern "C" { fn get_config() -> Int }
  fn main() {
    let ptr = unsafe { get_config() }
    // NO WAY to write to ptr+4 or ptr.field_name
  }
  ```

### GAP-MA-04 — `sizeof()` operator

- **What:** To allocate memory for opaque/transparent C structs via `xiom_alloc`,
  XIOM needs the size of the C type. No `sizeof()` or compile-time size
  constant mechanism exists in `extern "C"` blocks.
- **Impact:** Cannot allocate `ma_device`, `ma_context`, `ma_decoder`, etc.
  from XIOM.
- **Workaround:** All allocation happens inside the C bridge; XIOM only sees
  int64_t handles.
- **Minimal repro:**
  ```xiom
  extern "C" { fn xiom_alloc(size: Int) -> Int }
  fn main() {
    let buf = unsafe { xiom_alloc(/* sizeof(ma_device) = ??? */) }
  }
  ```

### GAP-MA-05 — Pointer-to-struct type distinction

- **What:** `extern "C"` pointer types are `*UInt8` or raw `Int`. There is no
  way to declare `*ma_device` vs `*ma_engine` as distinct pointer types.
  This loses type safety at the FFI boundary.
- **Impact:** API misuse (passing a waveform handle where an engine handle is
  expected) cannot be caught by the type checker.
- **Workaround:** Wrapper functions in `miniaudio.xi` use `pub type` aliases
  (`EngineHandle = Int`) but these provide only documentation-level distinction.

---

## Resolved / Non-Issues

| Gap | Status |
|-----|--------|
| `extern "C" { }` blocks (`GAP-2`) | CLOSED (xiomc v0.33.0) |
| `pub const` declarations (`GAP-3`) | CLOSED |
| `requires:` / `ensures:` contracts (`GAP-4`) | CLOSED |
| Cross-module `use xiom.*` resolution | RESOLVED |
| `defer` statement for cleanup | WORKS — used in demo |
| `Result[T, Str]` with `?` propagation | WORKS — used in safe wrappers |
| `as` type casts (`Int` <-> `Int32`, `Int` <-> `Float32`) | WORKS |

---

## Bridge Compilation

The C bridge must be compiled alongside `miniaudio.c` and linked into the XIOM
binary. A minimal build invocation (after placing `miniaudio.h` in the bridge dir):

```powershell
# Windows (MSVC)
cl /c /O2 /I. bridge\xiom_ma_bridge.c /Fo:xiom_ma_bridge.obj
xiomc --c-source xiom_ma_bridge.obj --link miniaudio demo_miniaudio.xi
```

```bash
# Linux/macOS
cc -c -O2 -Ibridge bridge/xiom_ma_bridge.c -o xiom_ma_bridge.o
xiomc --c-source xiom_ma_bridge.o --link miniaudio demo_miniaudio.xi
```

> **Note:** `miniaudio.h` is a single-header library. The bridge `#include`s it
> with `#define MINIAUDIO_IMPLEMENTATION` before the include, so a separate
> `miniaudio.c` is **not** required — the implementation is compiled into the
> bridge object file.

---

## Summary

| Gap | Description | Severity | Blocks |
|-----|-------------|----------|--------|
| GAP-MA-01 | Struct return by value | High | All `_init()` / config factory calls |
| GAP-MA-02 | C function pointers | High | Device callback registration |
| GAP-MA-03 | Struct field access | High | All struct configuration |
| GAP-MA-04 | `sizeof()` operator | Medium | Heap allocation of C structs |
| GAP-MA-05 | Typed struct pointers | Low | FFI type safety |

**All 5 gaps are worked around by the C bridge.** Eliminating any of GAP-MA-01
through GAP-MA-04 would allow progressively moving logic from C into XIOM.
