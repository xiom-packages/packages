# xiom.crc -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.crc`, version `0.1.0`).
Module: `src/crc.xi` (`module xiom.crc`).
Depends on `xiom.std`; the library module imports nothing (the tests import
stdlib modules).

## Scope

A pure-XIOM (no FFI), bitwise, table-free CRC engine:

- `crc_compute`: the generic Rocksoft / CRC-RevEng parameter tuple
  `(width, poly, init, refin, refout, xorout)` over `Vec[UInt8]`;
- `crc_matches`: verification shorthand for a parameter tuple plus an
  expected value;
- five named presets with published check values: `crc32_ieee`, `crc32c`,
  `crc16_ccitt_false`, `crc16_arc`, `crc8`.

## Non-goals

- CRC-64, CRC-24, CRC-12, CRC-10, CRC-5 and any width other than exactly
  8, 16 or 32 (invalid widths return 0 by contract).
- Lookup-table, slicing-by-N, CLMUL or SIMD implementations; a table is a
  performance optimization only (and module-level `[256]` tables are
  mis-materialized by the v0.61.3 compiler -- see the compiler notes).
- Streaming/incremental update objects (`update`/`finalize`): the input is
  a fully materialized `Vec[UInt8]`.
- Cryptographic integrity or authenticity. CRCs detect accidental
  corruption; they are not MACs.
- Error types for invalid parameters: invalid `width` returns 0 and
  out-of-range parameter bits are masked away.

## Parameter model

Definitions for a width `w` in {8, 16, 32}:

- `mask = 2^w - 1`;
- `trunc(v) = v mod 2^w` (the caller guarantees `v >= 0`);
- `reflect_w(v)` reverses the low `w` bits of `v`: bit `k` moves to bit
  `w - 1 - k`. Computed bit-by-bit:
  `out = 0; w times { out = out * 2 + (v & 1); v = v >> 1; }`.

`crc_compute(data, w, poly, init, refin, refout, xorout)`:

1. If `w` is not 8, 16 or 32, return 0 immediately.
2. Let `p = trunc(poly)` and `reg = trunc(init)`.
3. **refin = false** (normal / MSB-first):

   ```
   for each byte b of data, in order:
     reg = reg XOR (b * 2^(w - 8))
     repeat 8 times:
       if reg >= 2^(w - 1):
         reg = trunc((reg * 2) XOR p)
       else:
         reg = trunc(reg * 2)
   ```

4. **refin = true** (reflected / LSB-first): start from the reflected
   register and use the reflected polynomial `rpoly = reflect_w(p)`:

   ```
   reg = reflect_w(trunc(init))
   for each byte b of data, in order:
     reg = reg XOR b
     repeat 8 times:
       if reg is odd:
         reg = (reg >> 1) XOR rpoly
       else:
         reg = reg >> 1
   ```

5. If `refout != refin`, apply `reg = reflect_w(reg)`.
6. Return `reg XOR trunc(xorout)`.

Every intermediate value is a non-negative `Int` below `2^w`: the
reflected loop never needs an explicit truncation (both XOR operands are
below `2^w`), and the normal loop truncates arithmetically after each
shift. The result always lies in `[0, 2^w - 1]`.

### Reflection rules (summary)

| Rule | Statement |
|---|---|
| `poly` is always given in normal (MSB-first) form | The reflected form is derived internally only when `refin` is true. |
| `refin` selects the processing direction | LSB-first + reflected poly, or MSB-first + normal poly. |
| `init` is also reflected for `refin = true` | This is the standard register semantics; it is what makes CRC-16/RIELLO (init `0xB2AA`) match its catalogue value `0x63D0`. |
| `refout` matters only when it differs from `refin` | `refout == refin` outputs the register as-is; `refout != refin` reflects it before `xorout`. |
| `xorout` is always applied last | After any output reflection. |

Reflected-polynomial worked examples (all covered by tests):

| Normal poly | Width | Reflected poly | Preset |
|---|---|---|---|
| `0x04C11DB7` | 32 | `0xEDB88320` | CRC-32/IEEE |
| `0x1EDC6F41` | 32 | `0x82F63B78` | CRC-32C |
| `0x1021` | 16 | `0x8408` | CCITT / KERMIT / RIELLO |
| `0x8005` | 16 | `0xA001` | CRC-16/ARC, MODBUS |
| `0x07` | 8 | `0xE0` | CRC-8 |
| `0x31` | 8 | `0x8C` | CRC-8/MAXIM-DOW |

### Masking

`poly`, `init` and `xorout` are truncated to `w` bits (`trunc`), so
oversized inputs reduce silently: with `w = 8`, `poly = 0x107` behaves as
`0x07`; with `w = 16`, `init = 0x1B2AA` behaves as `0xB2AA`. The
parameters must be non-negative; negative values are outside the
documented contract.

## Presets

| Function | Width | Poly | Init | refin | refout | xorout | Check (`"123456789"`) | Empty input |
|---|---|---|---|---|---|---|---|---|
| `crc8` | 8 | `0x07` | `0x00` | false | false | `0x00` | `0xF4` (244) | 0 |
| `crc16_ccitt_false` | 16 | `0x1021` | `0xFFFF` | false | false | `0x0000` | `0x29B1` (10673) | `0xFFFF` (65535) |
| `crc16_arc` | 16 | `0x8005` | `0x0000` | true | true | `0x0000` | `0xBB3D` (47933) | 0 |
| `crc32_ieee` | 32 | `0x04C11DB7` | `0xFFFFFFFF` | true | true | `0xFFFFFFFF` | `0xCBF43926` (3421780262) | 0 |
| `crc32c` | 32 | `0x1EDC6F41` | `0xFFFFFFFF` | true | true | `0xFFFFFFFF` | `0xE3069283` (3808858755) | 0 |

The empty-input value is `init XOR xorout` in the register orientation
selected by `refin`/`refout`; for all five presets above it is either 0 or
the init itself, as tabulated.

## Additional catalogued `crc_compute` vectors

All check values are for `"123456789"` and match the published CRC
catalogue (cross-checked against an independent implementation):

| Name | Width | Poly | Init | refin | refout | xorout | Check | Decimal |
|---|---|---|---|---|---|---|---|---|
| CRC-16/KERMIT | 16 | `0x1021` | `0x0000` | true | true | `0x0000` | `0x2189` | 8585 |
| CRC-16/XMODEM | 16 | `0x1021` | `0x0000` | false | false | `0x0000` | `0x31C3` | 12739 |
| CRC-16/MODBUS | 16 | `0x8005` | `0xFFFF` | true | true | `0x0000` | `0x4B37` | 19255 |
| CRC-16/RIELLO | 16 | `0x1021` | `0xB2AA` | true | true | `0x0000` | `0x63D0` | 25552 |
| CRC-16/GENIBUS | 16 | `0x1021` | `0xFFFF` | false | false | `0xFFFF` | `0xD64E` | 54862 |
| CRC-8/MAXIM-DOW | 8 | `0x31` | `0x00` | true | true | `0x00` | `0xA1` | 161 |
| CRC-8/ROHC | 8 | `0x07` | `0xFF` | true | true | `0x00` | `0xD0` | 208 |
| CRC-8/ITU | 8 | `0x07` | `0x00` | false | false | `0x55` | `0xA1` | 161 |
| CRC-32/JAMCRC | 32 | `0x04C11DB7` | `0xFFFFFFFF` | true | true | `0x00000000` | `0x340BC6D9` | 873187033 |
| CRC-32/BZIP2 | 32 | `0x04C11DB7` | `0xFFFFFFFF` | false | false | `0xFFFFFFFF` | `0xFC891918` | 4236843288 |
| CRC-32/MPEG-2 | 32 | `0x04C11DB7` | `0xFFFFFFFF` | false | false | `0x00000000` | `0x0376E6E7` | 58124007 |
| CRC-32/POSIX | 32 | `0x04C11DB7` | `0x00000000` | false | false | `0xFFFFFFFF` | `0x765E7680` | 1985902208 |

Pinned secondary vectors (independent implementation, then verified twice
through this engine):

| Input | `crc32_ieee` | `crc32c` | `crc16_ccitt_false` | `crc16_arc` | `crc8` |
|---|---|---|---|---|---|
| `"a"` | 3904355907 | 3251651376 | 40311 | 59585 | 32 |
| `ff 00 80 7f 01` | 852721342 | 3296080556 | 30911 | 3316 | 84 |
| 300 bytes, byte `k` = `k % 256` | 985464046 | 1108128698 | 43353 | 50424 | 102 |

The 300-byte CRC-32 value 985464046 is independently pinned by the
`xiom.packet` suite against zlib, so it doubles as an external cross-check.

## API signatures

```xi
pub fn crc_compute(data: &Vec[UInt8], width: Int, poly: Int, init: Int, refin: Bool, refout: Bool, xorout: Int) -> Int
pub fn crc_matches(data: &Vec[UInt8], width: Int, poly: Int, init: Int, refin: Bool, refout: Bool, xorout: Int, expected: Int) -> Bool
pub fn crc32_ieee(data: &Vec[UInt8]) -> Int
pub fn crc32c(data: &Vec[UInt8]) -> Int
pub fn crc16_ccitt_false(data: &Vec[UInt8]) -> Int
pub fn crc16_arc(data: &Vec[UInt8]) -> Int
pub fn crc8(data: &Vec[UInt8]) -> Int
```

No `pub type` is exported; the module has no state and no struct types.

## Semantics

- `crc_compute`: the generic algorithm above. Returns the checksum in
  `[0, 2^width - 1]` as a non-negative `Int`; returns 0 when `width` is not
  in {8, 16, 32}. An empty `data` still applies `init`, `refout` and
  `xorout`, so it returns the empty-input value pinned above.
- `crc_matches`: `true` iff `crc_compute` with the same first seven
  arguments equals `expected`. No separate validation:
  `crc_matches(data, 7, ..., expected = 0)` is `true` because
  `crc_compute` returns 0 for the invalid width.
- Presets: thin wrappers over `crc_compute` with the exact table above; no
  independent logic, so the generic engine and the presets cannot drift.
- Errors: there are none. Invalid widths produce 0; out-of-range parameter
  bits are masked. Nothing panics and nothing allocates.

## Complexity

| Operation | Complexity |
|---|---|
| `crc_compute` | O(8 * data.len()) time = O(data.len()), O(1) space |
| `crc_matches` | same as `crc_compute` |
| each preset | same as `crc_compute` |
| internal reflect | O(width) |

## Test plan

`tests/test_conformance.xi` (`module crc_tests`, 20 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line, and
returns the failure count). Coverage:

1. CRC-32/IEEE check value `0xCBF43926` (3421780262);
2. CRC-32C check value `0xE3069283` (3808858755);
3. CRC-16/CCITT-FALSE check value `0x29B1` (10673);
4. CRC-16/ARC check value `0xBB3D` (47933);
5. CRC-8 check value `0xF4` (244);
6. empty input per preset (0 / 0 / 65535 / 0 / 0);
7. single byte `"a"` per preset (3904355907 / 3251651376 / 40311 /
   59585 / 32);
8. high-bit bytes `ff 00 80 7f 01` per preset (852721342 / 3296080556 /
   30911 / 3316 / 84);
9. `crc_compute` width validation: 7, 64, 0 and 24 return 0; 8, 16 and 32
   compute non-zero;
10. `crc_compute` with the preset parameter tuples equals every preset
    wrapper (including the empty input);
11. CRC-16/KERMIT (8585) and XMODEM (12739);
12. CRC-16/MODBUS (19255) and RIELLO (25552, reflected non-trivial init);
13. CRC-16/GENIBUS (54862), CRC-8/MAXIM-DOW (161), ROHC (208), ITU (161);
14. CRC-32/JAMCRC (873187033), BZIP2 (4236843288), MPEG-2 (58124007),
    POSIX (1985902208);
15. refout rule as a property: `refout != refin` equals a test-local
    independent 16-bit reversal applied to the non-reflected result (with
    the plain result pinned to 10673);
16. xorout rule as a property: `crc_compute(..., xorout = X)` equals
    `crc_compute(..., xorout = 0) XOR X` (8-bit and 32-bit), and the
    32-bit xorout-0 result equals the complement of `crc32_ieee`;
17. masking rule: oversized `poly`/`init`/`xorout` reduce to the same
    results (16-bit and 8-bit, including a reflected RIELLO init);
18. `crc_matches` true on the check value and false on an off-by-one
    expected value, for 32-, 16- and 8-bit parameters;
19. determinism: repeated calls and a separately built identical buffer
    agree; a shifted 300-byte buffer produces a different CRC-32;
20. 300-byte pattern (byte `k` = `k % 256`) pinned per preset: 985464046 /
    1108128698 / 43353 / 50424 / 102.

Test-fixture notes: `bytes_of` builds `Vec[UInt8]` with
`xiom.string.byte_at`; `high_bytes` pushes `255, 0, 128, 127, 1`; the
tests compare only `Int`/`Bool` values, so BUG 17 (`==` on `Str` read from
a `Vec`) is never reachable. The 300-byte buffer and its CRC-32 match the
`xiom.packet` suite's independently zlib-pinned vector.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.crc
```

Last verified: compiler 0.61.3, twice in a row,
`port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Bitwise, table-free: 8 bit-steps per byte, roughly an order of magnitude
  slower than a `[256]` table. Intentional (see compiler notes), not a
  candidate for tuning inside this package.
- No widths other than 8, 16 and 32; no CRC-64.
- No streaming API and no one-shot ``init``/``update``/``finalize`` split.
- Parameters must be non-negative; masking is silent (no diagnostics).
- No way to distinguish "invalid width" from "valid width whose checksum
  happens to be 0" in `crc_compute`'s return value; callers who need that
  distinction must validate `width` themselves (as the tests do).
- Not a cryptographic hash and not an authenticity mechanism.

## Compiler / stdlib notes for v0.61.3

- Free functions only: no methods, lambdas or `Vec[fn]` dispatch. The
  module has no struct types and never constructs `Ok`/`Err`.
- The register stays an `Int` below `2^width` using arithmetic truncation
  (`% 256`, `% 65536`, `% 4294967296`). Bitwise AND is used only with
  small masks (`& 1`, `& 255`): v0.61.3 miscompiles AND on operands with
  bit 31 set (BUG 25 #7, documented in `xiom.bits.bitwise` and
  `xiom.collect.bitmap`), so a 32-bit mask is never the right operand of
  `&`. The top-bit test is the comparison `reg >= 0x80000000`.
- `%` on non-negative `Int` is the proven truncation in this compiler
  (the `xiom.packet` u32 packing uses `% 256` / `/ 256` throughout), and
  `^`, `>>`, `<<` and comparison on such values are exercised by the
  `xiom.compress.gzip` CRC-32 and the stdlib bit handlers.
- The reflected polynomial and reflected `init` are built with the
  multiplication/addition form of reflection (`out * 2 + (v & 1)`) to
  stay within the operators already proven in the stdlib.
- The tests avoid `Str` equality entirely and never borrow a local mutably,
  so neither BUG 17 nor the advisory E001 borrow pattern is reachable.
- The package declares no `extern "C"` blocks (no FFI).
