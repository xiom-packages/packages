# xiom.roman -- specification

Version: 0.1.0 (incubating). Pure XIOM, no FFI, no floating point. All
functions are free functions; the module depends on `xiom.string` from
`xiom.std` only.

## 1. Symbols

The numeral alphabet is the seven ASCII letters `I`, `V`, `X`, `L`, `C`, `D`,
`M`; input accepts both cases (mixed case included) and is byte-oriented.

| Symbol | I | V | X | L | C | D | M |
|---|---|---|---|---|---|---|---|
| Value | 1 | 5 | 10 | 50 | 100 | 500 | 1000 |

There are exactly six subtractive pairs, formed by a unit/precision symbol
placed immediately before the next two symbols up: `IV` (4), `IX` (9),
`XL` (40), `XC` (90), `CD` (400), `CM` (900). Any other adjacency is not
Roman: `IL`, `IC`, `XD`, `XM` are all invalid.

## 2. Canonical grammar

The canonical language for values 1..3999 is

```
numeral   := thousands hundreds tens ones          (the product is non-empty)
thousands := "M"{0,3}
hundreds  := "CM" | "CD" | "D"? "C"{0,3}
tens      := "XC" | "XL" | "L"? "X"{0,3}
ones      := "IX" | "IV" | "V"? "I"{0,3}
```

equivalently, the regular expression

```
M{0,3}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})
```

with a non-empty match and a value in 1..3999. This grammar implies every
validation rule used below:

- `M` repeats at most three times and only at the front;
- `D`, `L` and `V` occur at most once each;
- `I`, `X` and `C` repeat at most three times, and each only inside its own
  position (ones, tens, hundreds);
- the six subtractive pairs above, and no others, may appear at the boundary
  of their position group;
- the longest canonical numeral is `MMMDCCCLXXXVIII` (3888, 15 bytes).

## 3. Evaluation

`roman_parse` evaluates a symbol string right to left: a symbol whose value is
strictly less than the value of the symbol to its right is subtracted,
otherwise it is added. On the canonical language this is exact; e.g.
`MCMXCIV` is `M` (+1000), `C` before `M` (-100), `M` (+1000), `X` before `C`
(-10), `C` (+100), `I` before `V` (-1), `V` (+5) = 1994.

## 4. `roman_parse(s: Str) -> Result[Int, Str]`

Algorithm, in order (first error wins):

1. `s` is empty -> `Err("roman: empty input")`.
2. Left-to-right byte validation: the first byte that is not one of the seven
   symbols in either case -> `Err("roman: invalid character: <c>")`, where
   `<c>` is that byte verbatim.
3. Evaluate the numeral as in section 3 -> `total`.
4. `total` outside 1..3999 -> `Err("roman: out of range")`.
5. Canonicalize: `c = roman_format_value(total)` (section 5). If `s` equals
   `c` ignoring ASCII case -> `Ok(total)`; otherwise ->
   `Err("roman: not canonical")`.

Because step 5 compares against the canonical spelling, parsing is
case-insensitive but not permissive: every accepted input lowercases to the
unique canonical form of its value. `III` parses (additive within the
grammar), `IIII` does not; `IV` parses (subtractive), `IL` does not.

Examples: `("MCMXCIV")` -> `Ok(1994)`; `("iv")` -> `Ok(4)`;
`("McMxCiv")` -> `Ok(1994)`; `("IIII")` -> `Err("roman: not canonical")`;
`("VX")` -> `Err("roman: not canonical")`;
`("MMMM")` -> `Err("roman: out of range")`; `("")` ->
`Err("roman: empty input")`; `("A")` ->
`Err("roman: invalid character: A")`.

Complexity: O(len(s)) time, O(1) extra space.

## 5. `roman_format(n: Int) -> Result[Str, Str]`

`n` outside 1..3999 -> `Err("roman: out of range")`. Otherwise the value is
emitted greedily by the descending ladder

`1000 M, 900 CM, 500 D, 400 CD, 100 C, 90 XC, 50 L, 40 XL, 10 X, 9 IX, 5 V,
4 IV, 1 I`,

which yields the unique uppercase subtractive form. Examples: `(1)` ->
`Ok("I")`; `(1994)` -> `Ok("MCMXCIV")`; `(3888)` ->
`Ok("MMMDCCCLXXXVIII")`; `(3999)` -> `Ok("MMMCMXCIX")`; `(0)` and `(4000)`
-> `Err("roman: out of range")`. Complexity: O(len(result)).

## 6. `roman_is_canonical(s: Str) -> Bool`

True exactly when `roman_parse(s)` succeeds **and** `s` is byte-for-byte the
uppercase canonical form of the parsed value (equivalently:
`roman_format(roman_parse(s)) == s` with a case-sensitive `==`, or "the input
is already uppercase canonical"). Consequences: `"IV"` and `"XIV"` are true;
`"IIII"`, `"VX"`, `"IL"`, `"XD"`, `"MMMM"`, `"iv"`, `"mcmxciv"`, `""` and
`"MCMXCIV "` are false. Complexity: O(len(s)).

## 7. `roman_max() -> Int`

Returns `3999`, the largest representable value (`"MMMCMXCIX"`). Total,
O(1).

## 8. Error catalog

Every failure is `Err`, with messages prefixed `roman: `. Precedence is the
order below.

| Condition | Message |
|---|---|
| `s` is empty (`roman_parse`) | `roman: empty input` |
| first byte that is not `I,V,X,L,C,D,M` (either case) | `roman: invalid character: <c>` |
| evaluated value outside 1..3999 (`roman_parse`) | `roman: out of range` |
| valid letters, in range, non-canonical spelling | `roman: not canonical` |
| `n` outside 1..3999 (`roman_format`) | `roman: out of range` |

`roman_is_canonical` and `roman_max` never fail.

## 9. Test plan (tests/test_conformance.xi, 16 checks)

| # | Name | Expectation |
|---|---|---|
| t1 | parse known values | `I`/`IV`/`IX`/`XIV`/`XL`/`XC`/`CD`/`CM`/`MCMXCIV`=1994/`MMMCMXCIX`=3999 |
| t2 | additive forms | `II`/`III`/`VIII`/`LX`/`CLX` and 3888 = `MMMDCCCLXXXVIII` |
| t3 | lowercase/mixed | `i`/`iv`/`ix`/`xiv`/`mcmxciv`/`mmmcmxcix`/`McMxCiv` all parse |
| t4 | format table (12) | 1,2,3,4,5,9,14,40,90,400,900,1994 format exactly and round-trip |
| t5 | format boundaries | 1 -> `I`, 3999 -> `MMMCMXCIX`, both round-trip |
| t6 | format range | 0, -1, 4000, 10000 are Err; message is `roman: out of range` |
| t7 | parse range | `MMMM`, `MMMMM`, `MMMMCMXCIX` are Err |
| t8 | parse empty | `""` Err(`roman: empty input`); blank `" "` Err |
| t9 | invalid letters | `A`,`Z`,`a`,`z`,`Q`,`123`,`"I V"` are Err |
| t10 | invalid placements | `IIII`,`VX`,`IL`,`XD`,`MMMM`,`VIV`,`IIX`,`IC`,`XM` are Err |
| t11 | canonical true | `I`,`IV`,`XIV`,`MCMXCIV`,`MMMCMXCIX`,`MMMDCCCLXXXVIII` |
| t12 | canonical false | `IIII`,`iv`,`mcmxciv`,`VX`,`IL`,`MMMM`,`""`,`"MCMXCIV "` |
| t13 | max pinned | `roman_max() == 3999`; 3999 <-> `MMMCMXCIX`; 3998 -> `MMMCMXCVIII` |
| t14 | round-trip loop | `parse(format(n)) == n` for every n in 1..50 |
| t15 | error catalog | exact messages for empty/invalid character/range/not canonical |
| t16 | format samples | 49, 944, 1066, 2024, 3888 format exactly and round-trip |

Every test folds its sub-checks into one `assert(cond, name)` and `main`
returns the number of failing checks (0 = green). `port.ps1` must end
`port: PASS (passed=16 failed=0 program_exit=0 exit=0)`.

## 10. Compiler / stdlib notes (XIOM v0.61.3)

- Free functions only; no `self` methods, no lambdas, no `Vec[StructType]`.
- `Ok`/`Err` are constructed only in the leaf helpers `_roman_parse_ok`,
  `_roman_parse_err`, `_roman_format_ok` and `_roman_format_err`;
  constructing results inline in a larger function miscompiles on this
  compiler.
- Byte classification uses `xiom.string.byte_at` against `UInt8` ASCII
  constants only; no widening comparisons on `UInt8`.
- `Str` values are compared only with `xiom.string.str_compare` (never `==`).
- Matches over `Result` are exhaustive (`Ok`/`Err`); no `mut` patterns.
- `use` statements end with `;`, `module` does not.

## 11. Known limitations

- Standard range 1..3999 only: no vinculum/overline notation for 4000 and
  above, no zero (`nulla`).
- Canonical spelling only: arbitrary additive spellings (`IIII`, `VIIII`) are
  errors, not alternative readings.
- ASCII only: no Unicode Roman numeral characters, no overline combining
  marks; input bytes are matched exactly.
- Parsing is byte-oriented and locale-free; there is no optional-argument or
  clock-face mode.
- `roman_is_canonical` is case-sensitive by design: lowercase input is never
  canonical, even when its value parses.
