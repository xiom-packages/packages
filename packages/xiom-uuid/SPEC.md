# xiom.uuid -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.uuid` (`src/uuid.xi`). Pure XIOM, no FFI.

## 1. Scope

Canonical RFC 4122 UUID text handling for raw 16-byte vectors:

- `uuid_format` -- 16 bytes to lowercase `8-4-4-4-12` text,
- `uuid_parse` -- canonical text to 16 bytes,
- `uuid_is_valid` -- infallible `Bool` wrapper around the parser,
- `uuid_v4_from` -- 16 caller-supplied bytes to v4 text (bit rules forced),
- `uuid_version` -- version nibble of a valid UUID,
- `uuid_variant_ok` -- RFC 4122 variant-bit check for a valid UUID.

The package never generates randomness and never reads the clock; the
caller supplies the bytes for v4 construction, so all functions are
deterministic.

## 2. Non-goals

- UUID generation: no RNG, no entropy source, no clock/node/MAC input.
- Time-based versions: no v1/v6/v7 layouts, no monotonic or sortable IDs.
- Alternate encodings: no braces, no `urn:uuid:`, no base64/hex-without-
  hyphens, no Microsoft GUID mixed-endian (`Data1/2/3` little-endian)
  layout, no brace/uppercase output.
- UUID semantics beyond the bits: no identity, ordering or uniqueness
  guarantees, no database integration.
- FFI, file I/O, registry integration.

## 3. Format grammar

Canonical text (the only form produced or accepted):

```
xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

- exactly 36 bytes,
- hyphens at zero-based byte positions 8, 13, 18 and 23,
- every other byte a hex digit `[0-9A-Fa-f]`; case is not significant on
  input, output is lowercase,
- group lengths 8-4-4-4-12, mapping to bytes `0..3`, `4..5`, `6..7`,
  `8..9`, `10..15` of the 16-byte vector, most significant hex digit
  first,
- no surrounding whitespace, braces or `urn:` prefix (wrong length or
  non-hex bytes reject).

`uuid_format` accepts exactly 16 bytes (`Err` otherwise); `uuid_parse`
accepts exactly 36 characters (`Err` otherwise).

## 4. Bit-level rules

Byte numbering is zero-based over the 16-byte vector.

- **Version nibble** -- `(bytes[6] >> 4) & 0x0F`, reported by
  `uuid_version`. Any value `0..15` is structurally valid; `uuid_v4_from`
  forces `4`.
- **Variant bits** -- the two most significant bits of `bytes[8]`,
  reported by `uuid_variant_ok`. RFC 4122 layout is `10xxxxxx`
  (`(bytes[8] & 0xC0) == 0x80`); `uuid_v4_from` forces `10`.
- **`uuid_v4_from` transform** -- for each byte `v` of the input:
  - `i == 6`: `v = (v & 0x0F) | 0x40`
  - `i == 8`: `v = (v & 0x3F) | 0x80`
  - all other bytes: copied verbatim.
  The transformed vector is then formatted by `uuid_format`, so the
  output is always 36 lowercase characters and always parses back to the
  transformed bytes.
- Example: input bytes `0x00..0x0F` => `00010203-0405-4607-8809-0a0b0c0d0e0f`.

## 5. Error catalog

Every error message starts with `uuid: `. Messages are static strings
(there is no formatting of numbers into messages).

| Message | Function | Condition |
|---|---|---|
| `uuid: expected 16 bytes` | `uuid_format`, `uuid_v4_from` | `bytes.len() != 16` |
| `uuid: expected 36 characters` | `uuid_parse` | `s.len() != 36` |
| `uuid: invalid hyphen placement` | `uuid_parse` | position 8/13/18/23 holds a non-hyphen byte |
| `uuid: invalid hex digit` | `uuid_parse` | any other position holds a non-hex byte |
| `uuid: invalid UUID` | `uuid_version`, `uuid_variant_ok` | `uuid_parse(s)` is `Err` |

`uuid_is_valid` has no error channel: it returns `false` exactly when
`uuid_parse` would return `Err`.

## 6. API signatures

```xi
pub fn uuid_format(bytes: &Vec[UInt8]) -> Result[Str, Str]
pub fn uuid_parse(s: Str) -> Result[Vec[UInt8], Str]
pub fn uuid_is_valid(s: Str) -> Bool
pub fn uuid_v4_from(rand: &Vec[UInt8]) -> Result[Str, Str]
pub fn uuid_version(s: Str) -> Result[Int, Str]
pub fn uuid_variant_ok(s: Str) -> Result[Bool, Str]
```

Complexity: every function is O(s.len()) in the input, bounded by the
fixed 36/16-element sizes; `uuid_is_valid`, `uuid_version` and
`uuid_variant_ok` delegate to `uuid_parse`.

## 7. Test plan

`tests/test_conformance.xi` (module `uuid_tests`) runs 18 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | format known bytes | `0x00..0x0F`, all-`FF` and `550e8400-...` vectors |
| t2 | format wrong lengths | 0, 15, 17 bytes are `Err` |
| t3 | parse/format round-trip | low, high (`>= 0x80`) and patterned vectors survive `parse(format(x)) == x` |
| t4 | parse uppercase | upper and mixed-case hex parse to the same bytes |
| t5 | parse bad hyphens | missing, displaced and extra hyphens are `Err` |
| t6 | parse non-hex | `g`, `z`, space, `_` in hex slots are `Err` |
| t7 | parse braces/urn | `{...}`, `urn:uuid:...`, trailing space are `Err` |
| t8 | parse wrong lengths | empty, 35 and 37 characters are `Err` |
| t9 | is_valid true | canonical, uppercase, all-zero, all-`f` |
| t10 | is_valid false | hyphenless, braced, non-hex, short, `+` |
| t11 | v4 bit rules | `v4_from(0x00..0x0F)` is exactly `00010203-0405-4607-8809-0a0b0c0d0e0f`; byte 6 high nibble 4, byte 8 top bits 10 |
| t12 | v4 wrong lengths | 0, 15, 17 bytes are `Err` |
| t13 | v4 parse-back | output is valid, version 4, RFC variant, parses to the transformed bytes |
| t14 | version nibble | 4, 0, 15, 1 from crafted inputs; malformed is `Err` |
| t15 | variant true | `550e8400-...`, v4 output and `b809` byte-8 forms |
| t16 | variant false | `0809`, all-zero, `c716`, `f716` byte-8 forms |
| t17 | version/variant errors | malformed and empty inputs are `Err` |
| t18 | determinism | `v4_from`, `format`, `parse` are equal on repeated identical input |

All `Str` equality in the suite goes through `str_compare` via the local
`streq` helper, so BUG 17 (`==` on `Str` values read from `Vec[Str]`
elements lowers to a pointer comparison) cannot apply. Expected byte
vectors are decoded with the stdlib `xiom.encoding.hex` module,
independently of the module under test.

## 8. Known limitations

- No randomness source; `uuid_v4_from` is only as random as the caller's
  16 bytes.
- v4 only; no time-based (`v1`/`v6`/`v7`) construction or inspection.
- Canonical hyphenated form only; no braces, URN, compact 32-hex or GUID
  mixed-endian input/output.
- Structural validation: any version nibble parses; variant bits are
  reported, not enforced, by `uuid_parse`.
- Static error strings: error messages carry no offending-position detail.

## 9. Compiler / stdlib notes

- v0.61.3: no methods, no lambdas, no `Vec[StructType]`; every function is
  free and every loop is `while`-based.
- All `Ok`/`Err` construction is confined to the leaf helpers
  `_ok_str`, `_err_str`, `_ok_bytes`, `_err_bytes`, `_ok_int`, `_err_int`,
  `_ok_bool`, `_err_bool` (constructing Results in larger functions
  miscompiles).
- Every byte read goes through `_byte_at_i` (`(string.byte_at(s, i) as
  Int) & 0xFF`), so no `UInt8` value is ever compared against an integer
  literal (including literals `>= 128`). `uuid_format` and `uuid_v4_from`
  copy bytes through `(v as Int) & 0xFF` before any arithmetic.
- The module never compares `Str` values. `Str` output is built once with
  `xiom.string.builder.sb_to_str`.
- Imports: `xiom.string` and `xiom.string.builder` only; the tests
  additionally use `xiom.test`, `xiom.io`, `xiom.string.compare` and
  `xiom.encoding.hex`.
