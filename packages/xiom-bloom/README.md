# xiom.bloom

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** a Bloom filter over a flat `Vec[UInt8]`: construction from
> `(m, k)`, double-hashed insert/contains, `clear`, set-bit count, an integer
> false-positive estimate, strict serialization and equal-shape union /
> intersection helpers.
> **Deps:** `xiom.std` only (the module imports `xiom.string` for byte
> access; the tests add `xiom.test`, `xiom.io` and `xiom.string.compare`).
> No FFI.

## What it is

`xiom.bloom` is a classic Bloom filter with all-integer math:

- **Flat storage.** `m` bits live in `ceil(m / 8)` bytes of one
  `Vec[UInt8]`; bit `j` is bit `j % 8` of byte `j / 8`, least significant
  first. No per-entry objects.
- **Double hashing.** Two stable 32-bit hashes -- `bloom_hash1` (FNV-1a)
  and `bloom_hash2` (an independent multiplicative mixing hash) -- produce
  `k` probe indexes as `(h1 + i * h2) mod m`. Negative `Int` hash arguments
  are accepted and wrapped with floor semantics.
- **Integer statistics.** `bloom_set_count` counts set bits and
  `bloom_fp_permille` turns the fill ratio `X / m` into the standard
  `1000 * (X / m)^k` false-positive estimate, rounded to the nearest
  permille with the exact evaluation documented in `SPEC.md`.
- **Strict codec.** Version-1 serialization validates the version byte, the
  bit length, the hash count, the declared payload length, truncation,
  trailing bytes and dirty padding; every error has a pinned message.
- **Set algebra.** `bloom_union` is the exact bitwise OR of equal-shape
  filters. `bloom_intersection` is the bitwise AND and is an approximation
  of set intersection: it can report extra false positives.

Errors are deterministic `Err(Str)` values. No floats, no file IO, no
cryptographic claims. See `SPEC.md` for the full contract, the bit and byte
layouts, and the hash constants.

## API

| Function | Returns | Description |
|---|---|---|
| `bloom_max_bits()` | `Int` | Largest accepted `m` (2^30 bits). |
| `bloom_max_hashes()` | `Int` | Largest accepted `k` (1024). |
| `bloom_version()` | `Int` | Serialization version (1). |
| `bloom_header_len()` | `Int` | Serialized header size (11 bytes). |
| `bloom_new(m, k)` | `Result[BloomFilter, Str]` | Zeroed filter; validates `m` and `k`. |
| `bloom_m(bf)` / `bloom_k(bf)` | `Int` | Declared bits / probes. |
| `bloom_byte_len(bf)` | `Int` | Payload bytes, `ceil(m / 8)`. |
| `bloom_hash1(s)` | `Int` | FNV-1a 32-bit over UTF-8 bytes. |
| `bloom_hash2(s)` | `Int` | Independent 32-bit mixing hash. |
| `bloom_derive_index(bf, h1, h2, i)` | `Result[Int, Str]` | `(h1 + i*h2) mod m`; errors on `i` outside `0..k-1`. |
| `bloom_insert(&mut bf, h1, h2)` | `Unit` | Set the `k` derived bits. |
| `bloom_contains(bf, h1, h2)` | `Bool` | All `k` bits set? (probabilistic true). |
| `bloom_add_str(&mut bf, s)` | `Unit` | Hash `s` with both hashes and insert. |
| `bloom_has_str(bf, s)` | `Bool` | Hash `s` with both hashes and query. |
| `bloom_clear(&mut bf)` | `Unit` | Zero every bit; keeps `m`/`k`. |
| `bloom_set_count(bf)` | `Int` | Number of set bits (0..m). |
| `bloom_is_empty(bf)` | `Bool` | No bit set. |
| `bloom_fp_permille(bf)` | `Int` | Estimated false-positive rate, 0..1000. |
| `bloom_equal(a, b)` | `Bool` | Same `m`, `k` and payload bytes. |
| `bloom_to_bytes(bf)` | `Vec[UInt8]` | Serialize (format version 1). |
| `bloom_from_bytes(data)` | `Result[BloomFilter, Str]` | Parse with strict validation. |
| `bloom_union(a, b)` | `Result[BloomFilter, Str]` | Exact bitwise OR; equal shapes only. |
| `bloom_intersection(a, b)` | `Result[BloomFilter, Str]` | Bitwise AND (approximate); equal shapes only. |

## Quick start

```xi
use xiom.bloom;
use xiom.io;

let r = bloom_new(1000, 4);
if r.is_ok {
  var f: BloomFilter = r.value;
  bloom_add_str(&mut f, "alice");
  bloom_add_str(&mut f, "bob");

  io.println(bloom_has_str(&f, "alice"));    // true
  io.println(bloom_has_str(&f, "carol"));    // usually false (probabilistic)
  io.println(bloom_set_count(&f));           // 8 for two distinct inserts
  io.println(bloom_fp_permille(&f));         // estimate, small at this fill

  let bytes = bloom_to_bytes(&f);
  let back = bloom_from_bytes(&bytes);       // Ok, bloom_equal(f, parsed)
}
```

Lower-level use with explicit hashes:

```xi
let h1 = bloom_hash1("order:4711");
let h2 = bloom_hash2("order:4711");
bloom_insert(&mut f, h1, h2);
if bloom_contains(&f, h1, h2) { /* definitely inserted */ }
```

## Error model

`bloom_new` and `bloom_from_bytes` reuse one validation order
(`m <= 0`, `k <= 0`, `m` above 2^30, `k` above 1024); `bloom_derive_index`
rejects only a bad probe ordinal; union/intersection require both filters to
have the same `m` and `k`. The full catalog with exact strings:

| Message | Condition |
|---|---|
| `bloom: m must be positive` | `m <= 0` |
| `bloom: k must be positive` | `k <= 0` |
| `bloom: m exceeds maximum` | `m > 2^30` |
| `bloom: k exceeds maximum` | `k > 1024` |
| `bloom: hash index out of range` | `i < 0` or `i >= k` in `bloom_derive_index` |
| `bloom: truncated buffer` | buffer shorter than the header or the declared payload |
| `bloom: unsupported version` | version byte is not `1` |
| `bloom: byte length mismatch` | declared payload length differs from `ceil(m / 8)` |
| `bloom: trailing bytes` | buffer longer than header + declared payload |
| `bloom: padding not zero` | a bit at position `>= m` is set |
| `bloom: union size mismatch` | union inputs differ in `m` or `k` |
| `bloom: intersection size mismatch` | intersection inputs differ in `m` or `k` |

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.bloom
```

Expected: the section-4 namespace check passes, 25 `[PASS]` lines, and a
final `port: PASS (passed=25 failed=0 program_exit=0 exit=0)`. The suite
pins both hash functions against published FNV-1a vectors and fixed mixing
vectors, the serialization layout byte-for-byte, every error message, and
the false-positive estimate at 0 / 500 / 250 / 1000 permille.

## Limitations

- **Probabilistic.** `true` is not proof of membership; false positives are
  inherent. The permille estimate is an approximation, not a bound.
- **No deletion.** Removing a key requires rebuilding the filter from the
  retained keys; there is no insert counter either, so the error estimate
  is inferred from the observed fill (`X / m`).
- **Shape-locked algebra.** Union and intersection require identical `m`
  and `k`. Intersection is the bitwise AND and only approximates the
  intersection of the two key sets.
- **Bounded sizes.** `m <= 2^30` bits (128 MiB) and `k <= 1024` probes;
  `bloom_new` allocates and zeroes the whole payload up front.
- **Non-cryptographic hashes.** An adversary can force collisions; do not
  use membership as a security check.
- **Value types, no locking.** Not thread-safe by themselves and not
  optimized for concurrent mutation.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
