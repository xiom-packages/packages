# ptr-cast -- Int <-> pointer cast fidelity (B-25, v0.64.4)

Found while building xiom.dx12 0.4.0 command recording: handing a COM
object handle read from a C out-param back to a `*UInt8` parameter failed
with `E_INVALIDARG` because the XIOM `Int as *UInt8` cast does **not**
preserve the integer value.

C host: `ptrhost.c` (`pt_see_ptr` reports the address C receives for a
pointer argument; `pt_see_int` reports the value C receives for an Int64
argument).  Probe: `probe.xi`.

## Run

```
. scripts\xiom.ps1
$tool = Resolve-XiomToolchain; $env:XIOM_STDLIB = $tool.Stdlib
& $tool.Xiom --run <abs>\probe.xi --c-source <abs>\ptrhost.c
```

## Result (2026-10-13, v0.64.4, RTX 3070 Ti host)

```
=== B-25 ptr-cast probe (v0.64.4) ===
true_ptr   = 2939462325200
int_param  = 2939462325200     <- Int64 param: value-preserving
cast_ptr   = 2939462295776     <- Int as *UInt8: NOT the same address
int-param path: FIDELITY OK (pointer -> Int -> Int64 preserves)
cast path: LOSSY -- Int as *UInt8 does NOT preserve the value (B-25)
```

Second witness (xiom.dx12 0.4.0 recording attempt): an object handle read
from an out-slot (`alloc=2942876542816`) cast with `as *UInt8` arrived in
C as `2942909369856`, and the D3D12 call returned E_INVALIDARG.

- **Int-typed C parameters preserve values** (pointer -> `as Int` ->
  `Int64` param round-trips exactly).  This is the marshaling every
  generated wrapper's `obj: Int` receiver uses, and why the dx12 surface
  works.
- **`Int as *UInt8` is not value-preserving** on this pin: the casted
  pointer differs by a heap-dependent amount from the integer value (the
  value appears to be materialized into compiler-managed memory rather
  than reinterpreted).

## Impact

- Any XIOM code that converts an integer handle to a raw pointer for a C
  call is affected (e.g. the stdlib `xiom.ffi.c` idiom `strlen(ptr as
  *UInt8)` where `ptr: Int`).
- Bindings-side workaround (shipped in xiom.dx12 0.4.0): COM object
  parameters are typed `Int` in the generated surface (C side `void*`,
  the proven-faithful path), and bridge helpers take handles as `int64`
  and cast in C.

Filed with the compiler as B-25 (2026-10-13) as the C-boundary
consequence of the documented B-20 int-to-ptr sanitization; relayed as
INFORMATIONAL (no fix requested -- the bindings surface now avoids the
cast entirely).
