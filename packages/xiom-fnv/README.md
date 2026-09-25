# xiom.fnv

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI), Int-only implementation of FNV-1 and
> FNV-1a in 32-bit and 64-bit widths, as one-shot functions and as an
> explicit-state incremental API.
> **Deps:** `xiom.std` only. The library module imports `xiom.string`
> (for the hex display helpers); the tests use `xiom.test`, `xiom.io` and
> `xiom.string`.

## What it is

`xiom.fnv` implements the Fowler/Noll/Vo non-cryptographic hash family
exactly as published at <https://www.isthe.com/chongo/tech/comp/fnv/>
(CC0 public domain), for byte buffers (`Vec[UInt8]`):

- `fnv1_32`, `fnv1a_32` -- 32-bit variants, result in `[0, 2^32 - 1]`;
- `fnv1_64`, `fnv1a_64` -- 64-bit variants, result as a signed Int whose
  bit pattern is the unsigned 64-bit hash;
- `fnv1_32_init/update/finalize` and the three sibling triples -- the
  same four algorithms over an explicit state Int;
- `fnv_offset_basis32/64`, `fnv_prime32/64` -- the specification
  constants;
- `fnv_hex32`, `fnv_hex64` -- lowercase hexadecimal for unsigned display
  (8 and 16 digits).

Every one-shot function is a thin wrapper over the same byte loop the
incremental `update` uses, so "hash the whole buffer" and "hash the
buffer in chunks" cannot drift. All four functions are pinned against
the official FNV reference vectors (`test_fnv.c` in the `lcn2/fnv` repo)
for `""`, `"a"`, `"fo"`, `"foo"`, `"foob"`, `"fooba"`, `"foobar"`, and
against the published zero-hash challenge solutions; see `SPEC.md` for
the full tables.

## Install / use

```
xiom pkg install xiom.fnv@0.1.0     # consumer
xiom pkg publish                    # maintainer (needs XIOM_REGISTRY_TOKEN)
```

Then import the module:

```xi
use xiom.fnv;
```

## Quick start

```xi
use xiom.fnv;
use xiom.io;
use xiom.string;

// Build the classic "foobar" buffer.
var data = Vec[UInt8].new();
var text = "foobar";
var i = 0;
while i < text.len() {
  data.push(string.byte_at(text, i));
  i = i + 1;
}

io.println(fnv_hex32(fnv1_32(&data)));    // 31f0b262
io.println(fnv_hex32(fnv1a_32(&data)));   // bf9cf968
io.println(fnv_hex64(fnv1_64(&data)));    // 340d8765a4dda9c2
io.println(fnv_hex64(fnv1a_64(&data)));   // 85944171f73967e8
```

`io.println` accepts the `Str` directly; use `xiom.convert.int_to_string`
if you need the signed decimal value of a 32-bit result.

### Incremental hashing

```xi
use xiom.fnv;

var head = Vec[UInt8].new();   // caller-supplied first chunk
var tail = Vec[UInt8].new();   // caller-supplied second chunk

var h: Int = fnv1a_32_init();
h = fnv1a_32_update(h, &head);
h = fnv1a_32_update(h, &tail);
let digest: Int = fnv1a_32_finalize(h);
// digest == fnv1a_32(whole_buffer)
```

`update` returns the new state; the caller threads it explicitly. FNV
defines no output transformation, so `finalize` is the identity and the
one-shot functions could equally be written as `finalize(update(init,
data))`.

## API summary

All functions are free functions in module `xiom.fnv`.

### Constants

| Function | Returns | Value |
|---|---|---|
| `fnv_offset_basis32()` | `Int` | `2166136261` (`0x811C9DC5`) |
| `fnv_prime32()` | `Int` | `16777619` (`0x01000193`) |
| `fnv_offset_basis64()` | `Int` | `-3750763034362895579` (unsigned `0xCBF29CE484222325`) |
| `fnv_prime64()` | `Int` | `1099511628211` (`0x00000100000001B3`) |

### One-shot

| Function | Returns | Description |
|---|---|---|
| `fnv1_32(data)` | `Int` | FNV-1, 32-bit; result in `[0, 2^32 - 1]`. |
| `fnv1a_32(data)` | `Int` | FNV-1a, 32-bit; result in `[0, 2^32 - 1]`. |
| `fnv1_64(data)` | `Int` | FNV-1, 64-bit; signed two's-complement view. |
| `fnv1a_64(data)` | `Int` | FNV-1a, 64-bit; signed two's-complement view. |

Empty input yields the offset basis for the width.

### Incremental (`<v>` in `1_32`, `1a_32`, `1_64`, `1a_64`)

| Function | Returns | Description |
|---|---|---|
| `fnv_<v>_init()` | `Int` | The offset basis for the variant. |
| `fnv_<v>_update(state, data)` | `Int` | Continue the hash; returns the new state. |
| `fnv_<v>_finalize(state)` | `Int` | The identity for FNV; completes the init/update/finalize shape. |

### Unsigned display

| Function | Returns | Description |
|---|---|---|
| `fnv_hex32(value)` | `Str` | 8 lowercase hex digits of `value mod 2^32`. |
| `fnv_hex64(value)` | `Str` | 16 lowercase hex digits of the 64-bit pattern. |

## Numeric model

- **32-bit:** the state is always a non-negative `Int` in
  `[0, 2^32)`. The multiply `state * 16777619` is exact in Int
  (`(2^32 - 1) * 16777619 < 2^63`) and is wrapped with `% 2^32`.
- **64-bit:** the state is an `Int` whose two's-complement bit pattern
  is the unsigned 64-bit hash. Values at or above `2^63` are therefore
  negative, which is why the empty-input result is
  `-3750763034362895579` rather than `14695981039346656037`.
- **Wrapping without BigInt or bit tricks:** the 64-bit multiply uses a
  16-bit limb split (`_mul64` in `src/fnv.xi`); the prime
  `1099511628211 = 256 * 2^32 + 435` is distributed over four limbs and
  carries are propagated column by column. Every intermediate stays
  below `2^27`, so the modular result is exact in Int with no reliance
  on compiler overflow behavior. The per-byte XOR only touches the low
  octet and is computed arithmetically, so no bitwise operator ever sees
  a value with bit 31 or 63 set. `SPEC.md` carries the full bounds proof.
- **Hex helpers** accept any `Int`: `fnv_hex32` reduces modulo `2^32`
  first; `fnv_hex64` renders the full 64-bit pattern. `fnv_hex64(-1)` is
  `"ffffffffffffffff"`.

## Error model

There are no errors, by construction:

- every public function is total and returns its result directly -- no
  `Result`, no `Err(Str)` catalog, no panics, no allocation failures;
- any `Int` is a valid 32-bit state (reduced modulo `2^32` by `_mul32`)
  and a valid 64-bit state (its two's-complement pattern); any
  `Vec[UInt8]`, including the empty vector and high-bit bytes, is a valid
  input;
- empty input is not an error: it returns the offset basis, exactly as
  the specification prescribes;
- hash collisions are inherent to any hash function and are not
  reported; this package makes no collision or cryptographic claim.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.fnv
```

Expected: the section-4 namespace check passes, 19 `[PASS]` lines, and a
final `port: PASS (passed=19 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Not cryptographic.** FNV is a fast, simple non-cryptographic hash:
  it is trivially forgeable, provides no authentication, and must not be
  used for signatures, MACs, password hashing or adversarial collision
  resistance.
- **Only 32-bit and 64-bit, only FNV-1 and FNV-1a.** No 128/256-bit
  variants, no FNV-0, no xor-folding to non-power-of-two sizes, no
  seeded variant.
- **No streaming object.** The incremental API is explicit state Ints
  threaded by the caller; there is no hasher handle, no struct, no
  `update`-in-place call.
- **Not optimized.** The 64-bit path spends a limb decomposition plus a
  four-column multiply per byte to keep every intermediate provably in
  range for compiler v0.61.3. It is correct and portable, not fast.
- **Signed display for 64-bit results.** The functions return the signed
  two's-complement `Int`; use `fnv_hex64` (or document your own
  unsigned conversion) when the decimal value must be in
  `[0, 2^64)`.
- **Fixed offset bases.** Callers who need a custom initial state can
  pass it to `update` directly, but there is no keyed or seeded wrapper.
- No FFI, no `extern "C"` blocks, no unsafe code.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
