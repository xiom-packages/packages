# xiom.ulid -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.ulid`, version `0.1.0`).
Module: `src/ulid.xi` (`module xiom.ulid`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`). No FFI.

## 1. Scope

A pure-XIOM ULID codec over the layout of the ULID specification: a 128-bit
value made of a 48-bit Unix millisecond timestamp (most significant) followed
by 80 bits of randomness, rendered as 26 Crockford base32 characters.
Ten free functions:

```xi
pub fn ulid_alphabet() -> Str
pub fn ulid_encode(timestamp: Int, rand_hi: Int, rand_lo: Int) -> Result[Str, Str]
pub fn ulid_timestamp(s: Str) -> Result[Int, Str]
pub fn ulid_random_hi(s: Str) -> Result[Int, Str]
pub fn ulid_random_lo(s: Str) -> Result[Int, Str]
pub fn ulid_is_valid(s: Str) -> Bool
pub fn ulid_canonical(s: Str) -> Result[Str, Str]
pub fn ulid_compare(a: Str, b: Str) -> Result[Int, Str]
pub fn ulid_equal(a: Str, b: Str) -> Result[Bool, Str]
pub fn ulid_monotonic_ok(prev: Str, next: Str) -> Result[Bool, Str]
```

The package never generates randomness and never reads the clock; the caller
supplies the timestamp and the two 40-bit randomness halves, so all functions
are deterministic. Decoding is component-wise (three accessors) rather than a
struct or tuple return: this keeps every value inside `Int` and matches the
flat free-function style of the v0.61.3 package family.

## 2. Non-goals

- **No randomness generation**: no RNG, no entropy source, no CSPRNG wrapper.
- **No clock access**: timestamps are caller-supplied; no `now()` helper.
- **No ULID parsing from other formats**: no 16-byte binary view, no hex, no
  UUID, no base32 without the ULID field split, no custom-alphabet support.
- **No other codecs**: base32 in general is `xiom.base32`'s job; this package
  implements the ULID-specific Crockford text only.
- **No streaming/incremental API** and no generation/registry loop.
- **No semantic guarantees**: uniqueness, collision resistance and security
  are the caller's responsibility.
- FFI, file I/O, registry integration.

## 3. Alphabet

ULID uses Crockford base32: 32 characters in value order, excluding the
ambiguous letters I, L, O and U.

| Value | Character | Value | Character | Value | Character | Value | Character |
|---|---|---|---|---|---|---|---|
| 0 | `0` | 8 | `8` | 16 | `G` | 24 | `R` |
| 1 | `1` | 9 | `9` | 17 | `H` | 25 | `S` |
| 2 | `2` | 10 | `A` | 18 | `J` | 26 | `T` |
| 3 | `3` | 11 | `B` | 19 | `K` | 27 | `V` |
| 4 | `4` | 12 | `C` | 20 | `M` | 28 | `W` |
| 5 | `5` | 13 | `D` | 21 | `N` | 29 | `X` |
| 6 | `6` | 14 | `E` | 22 | `P` | 30 | `Y` |
| 7 | `7` | 15 | `F` | 23 | `Q` | 31 | `Z` |

`ulid_alphabet()` returns the 32 characters in value order as one string:
`0123456789ABCDEFGHJKMNPQRSTVWXYZ`.

Decoding folds lowercase `a`..`z` to the same values as `A`..`Z`
(case-insensitive). The ambiguous letters `I`, `L`, `O`, `U` and their
lowercase forms `i`, `l`, `o`, `u` are **rejected** with
`ulid: invalid character`; they are not folded to `1`/`0`. Any other byte,
including whitespace and punctuation, is an invalid character.

## 4. Bit layout and encoding

The 128 bits are laid out most significant first:

```
bits 127..80 (48 bits)   Unix timestamp in milliseconds
bits  79..40 (40 bits)   randomness, high half  (rand_hi)
bits  39..0  (40 bits)   randomness, low half   (rand_lo)
```

The 26 characters carry 130 bits (26 x 5), so the value is padded on the left
with two zero bits; equivalently the 48-bit timestamp is left-padded to 50
bits, and the first character holds timestamp bits 47..45 and is therefore one
of `0`..`7` for every valid ULID.

```
characters 0..9   (50 bits)  timestamp (48 bits + 2 zero pad bits)
characters 10..17 (40 bits)  rand_hi
characters 18..25 (40 bits)  rand_lo
```

Encoding is big-endian base32 digit extraction with powers of two (no bitwise
shifts in v0.61.3):

- character `i` (0..9) = `(timestamp / 2^(45 - 5i)) % 32`
- character `10 + j` (0..7) = `(rand_hi / 2^(35 - 5j)) % 32`
- character `18 + k` (0..7) = `(rand_lo / 2^(35 - 5k)) % 32`

Decoding is the inverse Horner fold, `v = v * 32 + digit`, over each segment
(timestamp: characters 0..9 into an accumulator below 2^50; each randomness
half: 8 characters into an accumulator below 2^40).

Pinned vectors (computed with an independent arbitrary-precision reference
implementation and cross-checked against the ULID specification's published
example `01ARZ3NDEKTSV4RRFFQ69G5FAV`, timestamp 1469922850259):

| timestamp | rand_hi | rand_lo | ULID |
|---|---|---|---|
| `0` | `0` | `0` | `00000000000000000000000000` |
| `1` | `0` | `0` | `00000000010000000000000000` |
| `0` | `1` | `0` | `00000000000000000100000000` |
| `0` | `0` | `1` | `00000000000000000000000001` |
| `1469922850259` | `921107718639` | `797035380059` | `01ARZ3NDEKTSV4RRFFQ69G5FAV` |
| `1700000000000` | `4886718345` | `654570336784` | `01HF7YAT0004HMASW9K1KPXCGG` |
| `281474976710655` | `0` | `0` | `7ZZZZZZZZZ0000000000000000` |
| `0` | `1099511627775` | `0` | `0000000000ZZZZZZZZ00000000` |
| `0` | `0` | `1099511627775` | `000000000000000000ZZZZZZZZ` |
| `281474976710655` | `1099511627775` | `1099511627775` | `7ZZZZZZZZZZZZZZZZZZZZZZZZZ` |

## 5. Validation and decoding rules

Every decoding/validating function first runs the same validation pass; the
first applicable rule below wins, in this order:

1. **Length**: the byte length must be exactly 26; otherwise
   `Err("ulid: expected 26 characters")`.
2. **Alphabet**: every byte is mapped through the Crockford table; the first
   byte outside the accepted set (including `I`, `L`, `O`, `U` in either case)
   yields `Err("ulid: invalid character")`. The scan is left to right over all
   26 bytes.
3. **Overflow (130-bit guard)**: the 10-character timestamp field is folded
   into a 50-bit value; if it exceeds `2^48 - 1 = 281474976710655`, the
   26-character text overflows the 128-bit ULID space and yields
   `Err("ulid: overflow")`. This is exactly the case where the first character
   is `8`..`Z` (or `8`..`z`) instead of `0`..`7`.

After validation succeeds:

- timestamp = fold of characters 0..9 (48 bits);
- rand_hi = fold of characters 10..17 (40 bits);
- rand_lo = fold of characters 18..25 (40 bits).

`ulid_encode` validates its numeric inputs instead: `timestamp` must be in
`0..2^48 - 1`, `rand_hi` and `rand_lo` each in `0..2^40 - 1`.

`ulid_canonical` re-emits validated input with every character mapped to its
Crockford value and back to the uppercase alphabet, so the output is
`ulid_encode(timestamp(s), rand_hi(s), rand_lo(s))` and
`ulid_canonical(ulid_canonical(s))` equals `ulid_canonical(s)`.

## 6. API contract

| Function | Input | Returns | Errors |
|---|---|---|---|
| `ulid_alphabet()` | none | `"0123456789ABCDEFGHJKMNPQRSTVWXYZ"` | none |
| `ulid_encode(timestamp, rand_hi, rand_lo)` | `Int` timestamp `0..2^48-1`, two `Int` halves `0..2^40-1` | `Ok(text)`, canonical 26-character uppercase text | `timestamp out of range`, `randomness out of range` |
| `ulid_timestamp(s)` | any `Str` | `Ok(Int)` 48-bit timestamp | validation errors |
| `ulid_random_hi(s)` | any `Str` | `Ok(Int)` high 40 randomness bits | validation errors |
| `ulid_random_lo(s)` | any `Str` | `Ok(Int)` low 40 randomness bits | validation errors |
| `ulid_is_valid(s)` | any `Str` | `Bool`, true iff validation passes | none |
| `ulid_canonical(s)` | any `Str` | `Ok(Str)` canonical uppercase form | validation errors |
| `ulid_compare(a, b)` | any two `Str` | `Ok(-1)` / `Ok(0)` / `Ok(1)` over `(timestamp, rand_hi, rand_lo)` | validation error of the first invalid argument (`a` before `b`) |
| `ulid_equal(a, b)` | any two `Str` | `Ok(Bool)`, decoded-value equality (case-insensitive) | validation error of the first invalid argument |
| `ulid_monotonic_ok(prev, next)` | any two `Str` | `Ok(true)` iff `next` is strictly greater than `prev` | validation error of the first invalid argument |

Invariants:

- `ulid_encode(t, h, l)` is `Ok` exactly when the three components are in
  range; the output is always 26 uppercase characters whose first character is
  `0`..`7`, and `ulid_timestamp` / `ulid_random_hi` / `ulid_random_lo` return
  `t` / `h` / `l` on it.
- `ulid_is_valid(s)` is true exactly when the component accessors return `Ok`.
- `ulid_compare` is a total order on valid ULIDs; `ulid_equal(a, b)` is
  `Ok(true)` exactly when `ulid_compare(a, b)` is `Ok(0)`.
- `ulid_monotonic_ok(prev, next)` is `Ok(true)` exactly when
  `ulid_compare(prev, next)` is `Ok(-1)`: within one millisecond the 80-bit
  randomness must be strictly greater (the ULID specification's monotonic
  factory increments the least significant bit with carrying).
- For canonical uppercase text, `ulid_compare` agrees in sign with
  `xiom.string.compare.str_compare` (fixed-length Crockford base32 is
  order-preserving).

## 7. Error catalog

Every error message starts with the literal prefix `ulid: `. Messages are
static strings (no numbers are formatted into them).

| Message | Raised by | Trigger |
|---|---|---|
| `ulid: expected 26 characters` | all decoding/validating functions | `s.len() != 26` |
| `ulid: invalid character` | all decoding/validating functions | a byte outside `0-9A-Za-z` minus `I/L/O/U` (either case) |
| `ulid: overflow` | all decoding/validating functions | the 130-bit text exceeds `2^128 - 1` (timestamp field > `2^48 - 1`, first character `8`..`Z`) |
| `ulid: timestamp out of range` | `ulid_encode` | `timestamp < 0` or `timestamp > 2^48 - 1` |
| `ulid: randomness out of range` | `ulid_encode` | `rand_hi` or `rand_lo` outside `0..2^40 - 1` |

Examples by message:

- expected 26 characters: `""`, 25 zeros, 27 zeros.
- invalid character: any ULID with `I`, `L`, `O`, `U`, `i`, `l`, `o`, `u`, `!`,
  `-`, a space, or a non-ASCII byte such as `é`; the byte length must still be
  26 for this message (otherwise the length error wins).
- overflow: `"8" + 25 zeros`, `"9" + 25 zeros`, 26 x `Z`, 26 x `z`.
- timestamp out of range: `ulid_encode(-1, 0, 0)`,
  `ulid_encode(281474976710656, 0, 0)`.
- randomness out of range: `ulid_encode(0, -1, 0)`,
  `ulid_encode(0, 1099511627776, 0)`, `ulid_encode(0, 0, -1)`,
  `ulid_encode(0, 0, 1099511627776)`.

Validation precedence is fixed: length, then the first invalid character
(left to right), then overflow. For example
`"8" + 24 zeros + "!"` reports `ulid: invalid character`, not overflow, while
`"8" + 25 zeros` reports `ulid: overflow`.

## 8. Test plan

`tests/test_conformance.xi` (module `ulid_tests`) runs 18 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). All `Str` equality goes through
`xiom.string.compare.str_compare` via the local `streq` helper (BUG 17
discipline). Pinned vectors were computed with an independent
arbitrary-precision reference implementation (PowerShell bigint) and
cross-checked against the ULID specification's published example and its
monotonic example pair.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | alphabet | exact 32-character string, no `I`/`L`/`O`/`U`, no lowercase |
| t2 | encode pinned | zero, single-bit timestamp/rand_hi/rand_lo, spec example, middle vector |
| t3 | encode boundaries | max timestamp `7ZZZZZZZZZ...`, max rand_hi, max rand_lo, max ULID `7` + 25 x `Z` |
| t4 | encode errors | negative/over-max timestamp; negative/over-max randomness halves; boundary OK |
| t5 | decode pinned | component values for zero, single-bit, max and spec vectors |
| t6 | case handling | lowercase/mixed decode identically; `ulid_canonical` folds to uppercase; `ulid_equal` across case |
| t7 | wrong length | `""`, 25 and 27 characters are `ulid: expected 26 characters` from every accessor |
| t8 | invalid characters | `I`/`L`/`O`/`U` either case, `!`, `-`, space and `é` are `ulid: invalid character` |
| t9 | overflow | first character `8`, `9`, `Z`, `z` are `ulid: overflow`; `7` + 25 x `Z` is the max valid ULID |
| t10 | is_valid | true for valid canonical/lowercase/boundary forms; false for every error kind |
| t11 | compare | timestamp, then rand_hi, then rand_lo ordering; case-insensitive; Err precedence; lexicographic agreement |
| t12 | equal | decoded-value equality across case; false for differing values; Err propagation |
| t13 | monotonicity | spec pair `...MMVRZ` -> `...MMVS0` true, reverse false, equal false, smaller randomness false, timestamp wins; Err propagation |
| t14 | round-trip | pinned boundaries plus a 200-case pseudo-random component sweep |
| t15 | canonical | identity on canonical, uppercase fold, length/character/overflow errors propagated |
| t16 | alphabet sweep | every alphabet character is accepted and decodes to its value at the last position |
| t17 | validation order | length beats characters; characters beat overflow; `7` + 25 x `Z` remains valid |
| t18 | determinism | repeated encode/canonical/compare agree; accessors agree with `ulid_is_valid` |

Scripted expectation from the repository root:

```
& .\scripts\port.ps1 -Package xiom.ulid
# port: PASS (passed=18 failed=0 program_exit=0 exit=0)
```

## 9. Known limitations

- **No RNG and no clock** (section 2): callers own both, and uniqueness is the
  caller's responsibility.
- **Randomness enters/leaves as two 40-bit halves**: there is no uint128,
  byte-vector or hex view of the 128 bits.
- **Strict input**: 26 characters, alphabet only, `I`/`L`/`O`/`U` rejected
  rather than folded; no whitespace, hyphens, braces or prefixes.
- **Overflow rejected**: the largest valid ULID is
  `7ZZZZZZZZZZZZZZZZZZZZZZZZZ`; all larger 26-character texts fail with
  `ulid: overflow`.
- **In-memory, O(1)**: no streaming, no binary/hex/UUID conversions.
- **Static error strings**: messages carry no offending-position detail and no
  byte value.

## 10. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no structs, no
  `Vec[StructType]`, no `Vec[fn]` dispatch.
- `Ok`/`Err` for the `Result`-returning functions are constructed only in the
  leaf helpers `_ok_str`, `_err_str`, `_ok_int`, `_err_int`, `_ok_bool`,
  `_err_bool`.
- Bytes read via `xiom.string.byte_at` are always widened with
  `(x as Int) & 0xFF` before comparison or arithmetic (`_byte_at_i`).
- No bitwise shifts: the 130-bit padded text is split with powers of two
  (division and modulo) and folded back with `acc * 32 + digit`; the largest
  power used is 2^45, well inside `Int`.
- `Str` output is built once with `xiom.string.builder.sb_to_str` from a
  `Vec[UInt8]` that only ever contains ASCII alphabet bytes (no NUL).
- No `==` on `Str` values anywhere: the module reports validation through a
  private `_error_of(s) -> Str` that returns `""` or a message, and the tests
  route every comparison through `str_compare`.
- Imports: `xiom.string` and `xiom.string.builder` only; the tests
  additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.
