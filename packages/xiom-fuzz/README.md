# xiom.fuzz

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** deterministic byte and string mutation for fuzzing: a seeded
> generator plus flip/insert/delete/duplicate operators and a multi-step
> driver.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at` and
> `xiom.string.builder`). Tests additionally use `xiom.test`, `xiom.io`,
> `xiom.string` and `xiom.string.compare`.

## Scope

`xiom.fuzz` produces mutated variants of a byte buffer or string from a
recorded seed. Everything is deterministic: `(data, seed, mutations)` always
produces the same bytes, on every run and platform, so any sample is
replayable from its seed. There is no clock, environment, file or OS
randomness anywhere in the module.

This package is the **mutation engine only**. It does not run a fuzz loop, keep
a corpus, schedule inputs or measure coverage -- callers own the target
harness (see Limitations).

| Type | Fields | Meaning |
|---|---|---|
| `FuzzRng` | `state: Int` | Generator state; always in `[1, 2^31 - 1]`. |

## API

| Function | Returns | Description |
|---|---|---|
| `fuzz_rng_new(seed)` | `FuzzRng` | Fresh generator; any Int seed (sign included). |
| `fuzz_next(r)` | `Int` | Next draw in `[0, 2^31 - 1]`; advances `r`. |
| `fuzz_flip_byte(data, seed)` | `Vec[UInt8]` | XORs one byte with a non-zero mask; same length; empty stays empty. |
| `fuzz_flip_bit(data, seed)` | `Vec[UInt8]` | Toggles one bit of one byte; same length; empty stays empty. |
| `fuzz_insert_byte(data, seed)` | `Vec[UInt8]` | Inserts one byte at a derived position in `0..=len`; length +1; empty grows to 1. |
| `fuzz_delete_byte(data, seed)` | `Vec[UInt8]` | Deletes one byte at a derived position; length -1; empty stays empty. |
| `fuzz_duplicate_range(data, seed)` | `Vec[UInt8]` | Duplicates a derived non-empty subrange at a derived position; grows; empty stays empty. |
| `fuzz_mutate(data, seed, mutations)` | `Vec[UInt8]` | Applies `mutations` steps (op and per-step seed derived from `seed + i`); `mutations <= 0` = unchanged copy. |
| `fuzz_mutate_str(s, seed, mutations)` | `Str` | `fuzz_mutate` over the UTF-8 bytes of `s`, materialized back to `Str`; **byte-level**, may not be valid UTF-8. |

All mutators return a fresh `Vec[UInt8]`; the input is never modified. Exact
position/mask/length derivations and the `fuzz_mutate` op-selection rule are
pinned in `SPEC.md`.

## Usage

```xi
use xiom.fuzz;
use xiom.io; use xiom.core;

fn main() -> Int {
  var seed_bytes = Vec[UInt8].new();
  seed_bytes.push(0x46 as UInt8); // "F"
  seed_bytes.push(0x55 as UInt8); // "U"
  seed_bytes.push(0x5A as UInt8); // "Z"
  seed_bytes.push(0x5A as UInt8); // "Z"

  var i = 0;
  while i < 8 {
    let sample = fuzz_mutate(&seed_bytes, 20260923 + i, 4);
    io.println("sample " + core.to_string(i) + " len " + core.to_string(sample.len()));
    i = i + 1;
  }
  return 0;
}
```

The same `seed` and `mutations` replay a sample exactly; feed the bytes to a
target decoder/parser and treat crashes or hangs as findings.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.fuzz
```

Expected tail: 22 `[PASS]` lines, `xiom.fuzz: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Mutation only.** No test-case generation from scratch, no grammar-aware
  mutation, no structure-aware operators (lengths, checksums, magic values).
- **No corpus runner or scheduler.** No seed corpus storage, minimisation,
  queue, parallel execution or time limits; callers own the fuzz loop.
- **Not coverage-guided.** There is no instrumentation, feedback or
  evolutionary selection; the driver is seed-driven and blind.
- **No target execution.** The package never calls into a target; it only
  transforms bytes.
- **Byte-level Str mutation.** `fuzz_mutate_str` does not validate UTF-8 and
  can return invalid sequences; for text targets prefer explicit encoding
  handling at the call site.
- **Deterministic test-grade PRNG.** Not cryptographic, no distribution
  proofs; the mixer is the same 31-bit scramble as `xiom.property`.
- **Unbounded growth.** Deletes are one byte at a time but inserts and
  duplicates grow by at least one per step, so long runs on the same buffer
  can grow without limit unless the caller re-seeds or truncates.

See `SPEC.md` for the pinned PRNG recipe, per-operation derivation, the
`fuzz_mutate` op-selection rule and the full test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
