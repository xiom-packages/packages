# xiom.ascii85 -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.ascii85`, version `0.1.0`).
Module: `src/ascii85.xi` (`module xiom.ascii85`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`). No FFI.

## 1. Scope

Four free functions over `Vec[UInt8]` and `Str`:

```xi
pub fn a85_encode(data: &Vec[UInt8]) -> Str
pub fn a85_decode(text: Str) -> Result[Vec[UInt8], Str]
pub fn a85_is_valid(text: Str) -> Bool
pub fn a85_max_decoded_len(chars: Int) -> Int
```

All scanning is byte-wise via `xiom.string.byte_at`. Every raw byte is
widened with `(x as Int) & 0xFF` before comparisons or arithmetic. Encoding
performs one final allocation per result `Str`
(`xiom.string.builder.sb_to_str`). Complexity is O(n) for every function.

## 2. Alphabet

ASCII85 (Adobe Base85) uses a 85-character alphabet:

```
!  "  #  $  %  &  '  (  )  *  +  ,  -  .  /  0  1  2  3  4
5  6  7  8  9  :  ;  <  =  >  ?  @  A  B  C  D  E  F  G  H
I  J  K  L  M  N  O  P  Q  R  S  T  U  V  W  X  Y  Z  [  \  ]
^  _  `  a  b  c  d  e  f  g  h  i  j  k  l  m  n  o  p  q  r
s  t  u
```

Digit value = byte - 33 (`!` = 0, `u` = 84). `z` (122) is not a digit; it is
the four-zero-byte group shorthand handled by the decoder. Bytes below 33,
above 117 and the interior byte `~` (126) are invalid characters.

## 3. Encoding rules

Input is consumed in 4-byte big-endian groups; the 32-bit value is written as
5 base-85 digits, most significant first.

- **Full group** (4 bytes): 5 characters.
- **All-zero group** (a full group whose value is 0): the single character
  `z`.
- **Final partial group** of `n` bytes (1..3): the group is zero-padded to 4
  bytes internally, the 5-character encoding is computed, and only the first
  `n + 1` characters are emitted. Examples: `M` -> `9``, `Ma` -> `9jn`,
  `Man` -> `9jqo`; `Man ` -> `9jqo^`.
- **Empty input**: `""`.
- The encoder emits **no** `<~`/`~>` delimiters and **no** line wrapping; it
  is total (no error case) and does not validate its input.

Pinned vectors (cross-checked against an independent ASCII85 implementation):

| Bytes | ASCII85 |
|---|---|
| `4d616e20` (`Man `) | `9jqo^` |
| `73757265` (`sure`) | `F*2M7` |
| `48656c6c6f2c20576f726c6421` (`Hello, World!`) | `87cURD_*#4DfTZ)+T` |
| `00000000` | `z` |
| `0000000000000000` | `zz` |
| `00000001` | `!!!!"` |
| `ffffffff` | `s8W-!` |
| `00` / `0000` / `000000` | `!!` / `!!!` / `!!!!` |
| `ff` / `ffff` / `ffffff` | `rr` / `s8N` / `s8W*` |

## 4. Decoding rules

1. **Whitespace** TAB (9), LF (10), VT (11), FF (12), CR (13) and space (32)
   is ignored anywhere in the input.
2. **Delimiters**: after skipping surrounding whitespace, one optional
   leading `<~` and one optional trailing `~>` are stripped. They are
   independent: both, either, or neither may be present. A `~` that is not
   part of a stripped trailing `~>` is an invalid character.
3. **Groups** are accumulated digit by digit. Five digits form one 32-bit
   big-endian value and emit 4 bytes; the accumulator then resets.
4. **`z`** is legal only at a group boundary (no digits accumulated) and
   emits four zero bytes. Anywhere else it is `Err("ascii85: z inside
   group")`.
5. **Final partial group** of 2..4 characters: the accumulated value is
   padded with the maximum digit `u` (84) for each missing digit, then the
   top `chars - 1` bytes of the 32-bit value are emitted (1..3 bytes). This
   is the standard decoder rule that makes canonical partial tails decode to
   the original bytes.
6. **Single leftover character**: `Err("ascii85: incomplete group")`. Unlike
   some implementations, a lone trailing character is never silently
   dropped.
7. **Empty input** (including only whitespace and/or delimiters) yields
   `Ok(empty)`.
8. Decoded bytes are never UTF-8 validated; callers holding `Str` values use
   their own UTF-8 boundary.

## 5. Overflow

A 5-digit group can represent values up to `85^5 - 1 = 4437053124`, which
exceeds `2^32 - 1 = 4294967295`. Any group whose value is greater than
`0xFFFFFFFF` is `Err("ascii85: value overflows 32 bits")`; the same check is
applied to a partial group after the implicit `u` padding.

- `s8W-!` is exactly `0xFFFFFFFF` and decodes to `ffffffff` (the largest
  valid group).
- `s8W-"` is `0x100000000` and overflows.
- `uuuuu` is `85^5 - 1` and overflows.
- `s8W-` (4 characters) pads to `4294967379` and overflows; `uuuu` pads to
  `4437053124` and overflows.

## 6. Error catalog

All decode errors start with the literal prefix `ascii85: `; they are
produced only by `a85_decode` (and therefore by `a85_is_valid` returning
`false`).

| Message | Trigger |
|---|---|
| `ascii85: invalid character` | Byte outside `!`..`u` (including an interior `~`). |
| `ascii85: z inside group` | `z` after one or more digits of an unfinished group. |
| `ascii85: incomplete group` | Exactly one character left in the final group. |
| `ascii85: value overflows 32 bits` | Group value > `0xFFFFFFFF` (partial groups after `u` padding). |

## 7. Test plan

`tests/test_conformance.xi` (module `ascii85_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Expected byte vectors are built with the stdlib
`xiom.encoding.hex` decoder; all `Str` equality uses
`xiom.string.compare.str_compare`. Pinned vectors were cross-checked against
an independent ASCII85 implementation.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | encode full-group vectors | `Man ` -> `9jqo^`, `sure` -> `F*2M7`, `Hello, World!` -> `87cURD_*#4DfTZ)+T`, empty -> `""` |
| t2 | encode partial groups | `4d` -> `9``, `4d61` -> `9jn`, `4d616e` -> `9jqo`, high bytes `ff`/`ffff`/`ffffff` -> `rr`/`s8N`/`s8W*` |
| t3 | encode zero groups and extremes | `00`/`0000`/`000000` -> `!!`/`!!!`/`!!!!`; 4/8 zero bytes -> `z`/`zz`; `00000001` -> `!!!!"`; `ffffffff` -> `s8W-!` |
| t4 | decode full groups | inverse of t1 plus `!!!!!`, `!!!!"`, `s8W-!` -> `ffffffff` |
| t5 | decode partial groups | `9`` -> `4d`; `9j` -> `4d`; `9jn` -> `4d61`; `9jqo` -> `4d616e`; `rr`/`s8N`/`s8W*`; `9`P.n` -> `4d000000` |
| t6 | `z` at group boundaries | `z`, `zz`, `z9jqo^`, `9jqo^z`, `z!<N?+z`, `<~z~>` |
| t7 | misplaced `z` | `9jzqo`, `9z`, `!!!!z`, `z9jz`, `9jqz^` -> `ascii85: z inside group` |
| t8 | whitespace ignored | space/tab/LF anywhere plus VT/FF/CR around a full group |
| t9 | optional delimiters and empty input | `<~9jqo^~>`, `9jqo^~>`, `<~9jqo^`, nested whitespace; `""`, `~>`, `<~`, `"   "` -> `Ok(empty)` |
| t10 | round-trip 0..8 bytes | deterministic bytes incl. >= 0x80 |
| t11 | pinned short vectors | 8-byte sequence -> `#:r_qS&"+m`; zero-group vector -> `z!<N?+z`; empty -> `""`; round-trips |
| t12 | 64-byte pinned buffer | length 80, `a85_is_valid`, round-trip |
| t13 | invalid characters | `~`, `{`, `\|`, `}`, `é`, control `0x0F` -> `ascii85: invalid character` |
| t14 | single leftover char | `9`, `z9`, `9jqo^9`, `zz!` -> `ascii85: incomplete group`; `9j` -> `4d` contrast |
| t15 | 32-bit overflow | `uuuuu`, `s8W-"`, `s8W-`, `uuuu` -> overflow; `s8W-!` -> `ffffffff` |
| t16 | `is_valid` | true for valid/empty/delimited input; false for `9`, `9jzqo`, `uuuuu`, `9jqo~` |
| t17 | `max_decoded_len` | 0 and negative -> 0; 1..8 -> 1,2,3,4,4,5,6,7; 64 -> 52; 80 -> 64 |
| t18 | unicode bytes | `68c3a96c6c6f20f09f9880` -> `BZ$fcCi:HcT9t-`; round-trip |
| t19 | exhaustive 1-byte | all 256 values encode to exactly 2 chars and round-trip |
| t20 | 2-byte round-trips + bound | all 256 `(b, 0x80)` pairs; for lengths 0..40 the decoded size never exceeds `a85_max_decoded_len(encoded length)` |

## 8. Known limitations

- **No delimiter emission and no wrapping**: the encoder output is a single
  unbroken string without `<~`/`~>`; the decoder accepts but never requires
  them.
- **No `y` fold-spaces** (`btoa` extension): `y` is an ordinary digit.
- **Non-canonical forms decode**: `!!!!!` is a valid all-zero group and a
  partial tail is padded with `u`, so non-canonical encodings decode to the
  same bytes as their canonical form. The decoder does not enforce the
  encoder's `z`/truncation canonical form.
- **Strict single-character rule**: a lone trailing character is an `Err`
  even though some decoders drop it.
- **No streaming/incremental API** and no `Str` convenience helpers; all
  values are in-memory.
- **No UTF-8 validation** of decoded bytes.

## 9. Compiler / stdlib notes

The implementation follows the proven v0.61.3 package idioms:

- Free functions only; no methods, no lambdas, no `Vec[StructType]`, no
  `Vec[fn]` dispatch.
- `Ok`/`Err` for the `Result`-returning functions are constructed only in
  the leaf helpers `_ok_bytes`/`_err_bytes`.
- Bytes read from `Vec[UInt8]` or `byte_at` are always widened with
  `(x as Int) & 0xFF`; `Int` values read from `Vec[Int]` are bound with an
  explicit `let v: Int = ...`.
- 32-bit words are built and split with multiplication/division
  (`b0 * 16777216 + b1 * 65536 + b2 * 256 + b3`) rather than shifts on a
  value with the high bit set.
- No `==` on `Str` values anywhere (tests route every comparison through
  `str_compare`, BUG 17).
