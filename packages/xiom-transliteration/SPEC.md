# xiom.transliteration -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.transliteration` (`src/transliteration.xi`). Pure XIOM, no FFI.

## 1. Scope

UTF-8 to ASCII transliteration plus slug generation, all free functions:

- `translit_is_ascii(s) -> Bool` -- a byte-level ASCII test;
- `translit_to_ascii(s) -> Str` -- decode UTF-8, map known codepoints to
  ASCII replacements, pass ASCII through, drop unmapped codepoints, pass
  invalid bytes through one at a time;
- `translit_slug(s) -> Str` -- `translit_to_ascii` + lowercase + dash runs.

Every function is infallible: it returns `Bool`/`Str` and never reports
errors. The transform is intentionally lossy and documented as such.

## 2. Non-goals

- Full Unicode/CLDR transliteration: only the curated 359-entry table in
  section 5 is mapped.
- Standard romanization conformance (ISO 9, ELOT 743, ALA-LC, BGN/PCGN):
  the scheme is self-consistent but not certified against any standard.
- Reversibility: transliteration is many-to-one (`æ`, `ä` and `a` all
  produce `a`).
- NFC/NFD normalization, case folding beyond ASCII `A-Z -> a-z`, locale
  awareness.
- Error reporting: no `Result`, no replacement character, no validation.
- Any FFI, file I/O, or registry integration.

## 3. Data model

1. **Encoding.** `Str` is treated as a UTF-8 byte buffer (RFC 3629). The
   input is decoded codepoint by codepoint; output is assembled from the
   replacements and from the original bytes that pass through.
2. **ASCII.** A byte `< 0x80` is emitted unchanged and never looked up in
   the table (this includes ASCII control bytes; NUL cannot occur in a `Str`
   built with `Str::from_utf8`, which truncates at the first NUL).
3. **Codepoint domain.** A codepoint is the decoded Int value of a valid
   UTF-8 sequence. Non-ASCII codepoints are looked up in the table; a hit
   emits the replacement, a miss emits nothing (the codepoint is dropped).
4. **Empty input.** `""` is valid input: `translit_is_ascii("")` is `true`,
   `translit_to_ascii("")` and `translit_slug("")` are `""`.

## 4. Decoding rules

Decoding follows the manual RFC 3629 recipe (no stdlib decoder is used):

| Lead byte | Sequence length | Codepoint assembly |
|---|---|---|
| `0xxxxxxx` (0x00-0x7F) | 1 | the byte itself |
| `110xxxxx` (0xC0-0xDF) | 2 | `((b0 & 0x1F) << 6) \| (b1 & 0x3F)` |
| `1110xxxx` (0xE0-0xEF) | 3 | `((b0 & 0x0F) << 12) \| ((b1 & 0x3F) << 6) \| (b2 & 0x3F)` |
| `11110xxx` (0xF0-0xF7) | 4 | `((b0 & 0x07) << 18) \| ((b1 & 0x3F) << 12) \| ((b2 & 0x3F) << 6) \| (b3 & 0x3F)` |
| anything else | 1 | invalid -- byte passes through |

A sequence is **valid** only when all of the following hold; otherwise the
byte at the current position is emitted unchanged and the scan advances by
exactly one byte ("invalid sequences pass through one byte at a time"):

1. every continuation byte matches `10xxxxxx`;
2. the sequence is not truncated at end of string;
3. the codepoint is not overlong (2-byte `>= 0x80`, 3-byte `>= 0x800`,
   4-byte `>= 0x10000`);
4. the codepoint is not a surrogate (U+D800-U+DFFF);
5. the codepoint is `<= 0x10FFFF`.

Consequences: a stray continuation byte, a lone lead byte, overlong forms
(`C0 AF`), surrogates (`ED A0 80`) and `F8`-`FF` bytes all pass through
byte-exact and are never consumed as part of a mapping.

## 5. Table format and coverage

The table is two parallel vectors built once per `translit_to_ascii` call by
`_tl_fill(keys: &mut Vec[Int], vals: &mut Vec[Str])`:

- `keys[i]`: the codepoint as an `Int` (`0 <= cp <= 0x10FFFF`);
- `vals[i]`: the replacement as a `Str` (ASCII, 1-4 bytes).

Every `keys.push` is immediately followed by the matching `vals.push` in the
source, so index `i` always describes one mapping. Lookup is a linear scan
that copies the value into a typed local (`let v: Str = vals[i];`) and
returns it; values are never compared with `==` (BUG 17). 359 mappings, all
keys distinct:

| Block | Coverage | Entries | Scheme |
|---|---|---|---|
| Latin-1 Supplement letters | U+00C0-U+00FF, all letters (the signs U+00D7 `×` and U+00F7 `÷` are unmapped) | 62 | diacritic -> base letter; `Æ->AE/ae`, `Œ->OE/oe`, `ß->ss`, `Þ/þ->Th/th`, `Ð/ð->D/d` |
| Latin Extended-A | U+0100-U+017F, complete | 128 | diacritic -> base letter (`Š->S`, `ł->l`, `Đ->D`, ...) |
| Greek | U+0386-U+03CE letters and accented forms | 69 | `Η/η->E/e`, `Θ/θ->Th/th`, `Ξ/ξ->X/x`, `Υ/υ->Y/y`, `Φ/φ->Ph/ph`, `Χ/χ->Ch/ch`, `Ψ/ψ->Ps/ps`, `Ω/ω->O/o`, `ς->s`; accented vowels map to the base Latin vowel |
| Cyrillic | U+0400-U+045F core block, selected extensions (Ђ, Ѓ, Є, І, Ї, Ј, Љ, Њ, Ћ, Ќ, Ў, Џ and lowercase), U+0490/U+0491 | 92 | `Ж/ж->Zh/zh`, `Х/х->Kh/kh`, `Ц/ц->Ts/ts`, `Ч/ч->Ch/ch`, `Ш/ш->Sh/sh`, `Щ/щ->Shch/shch`, `Ы/ы->Y/y`, `Э/э->E/e`, `Ю/ю->Yu/yu`, `Я/я->Ya/ya`; `Ъ/ъ` and `Ь/ь` map to `""` (omitted) |
| Punctuation + NBSP | U+00A0, U+2013, U+2014, U+2018, U+2019, U+201C, U+201D, U+2026 | 8 | NBSP -> one space; en/em dash -> `-`; curly single quotes -> `'`; curly double quotes -> `"`; ellipsis -> `...` |

Any other codepoint (including `×`, `÷`, emoji, CJK, Arabic, Hebrew,
Devanagari and combining marks) is unmapped and therefore dropped.

## 6. Per-function rules

### 6.1 `translit_is_ascii(s) -> Bool`

| Situation | Result |
|---|---|
| every byte `< 0x80` (including `""`) | `true` |
| any byte `>= 0x80` | `false` |

No decoding is performed: a string made of invalid UTF-8 bytes is "not
ASCII" exactly when at least one byte is `>= 0x80`.

### 6.2 `translit_to_ascii(s) -> Str`

Single left-to-right pass:

| Situation | Output |
|---|---|
| byte `< 0x80` | the byte itself |
| valid codepoint with a table entry | the replacement, verbatim (1-4 ASCII bytes) |
| valid codepoint without a table entry | nothing (dropped) |
| invalid byte | the byte itself; advance one byte |

Worked examples:

| Input | Output |
|---|---|
| `"café"` | `"cafe"` |
| `"straße"` | `"strasse"` |
| `"Ελλάδα"` | `"Ellada"` |
| `"жук"` | `"zhuk"` |
| `"‘q’ “r” a–b c…"` | `"'q' \"r\" a-b c..."` |
| `"a<NBSP>b"` (built) | `"a b"` |
| `"a中b"` | `"ab"` |
| lone `0xE9` byte | lone `0xE9` byte (unchanged) |

### 6.3 `translit_slug(s) -> Str`

`translit_to_ascii(s)` -> ASCII lowercase (`str_lower`) -> single pass with a
pending-separator flag:

| Situation | Output |
|---|---|
| ASCII letter `a-z` or digit `0-9` after lowercasing | the byte itself |
| run of any other byte (punctuation, space, kept-through invalid bytes) | one `-`, only between two kept bytes |
| run at the start or end | dropped (leading/trailing `-` trimmed) |

Worked examples:

| Input | Output |
|---|---|
| `"Café Münster"` | `"cafe-munster"` |
| `"Hello World"` | `"hello-world"` |
| `"a   b"` | `"a-b"` |
| `"  über  "` | `"uber"` |
| `"C++ & Rust"` | `"c-rust"` |
| `"Track 2"` | `"track-2"` |
| `"!!!"`, `"…"`, `" — "`, `"中"`, `""` | `""` |

## 7. API signatures

```xi
pub fn translit_is_ascii(s: Str) -> Bool
pub fn translit_to_ascii(s: Str) -> Str
pub fn translit_slug(s: Str) -> Str
```

Complexity: `translit_is_ascii` is O(s.len()); `translit_to_ascii` is
O(s.len() * 359) worst case (table rebuild + linear scan per non-ASCII
codepoint); `translit_slug` delegates plus O(s.len()).

## 8. Test plan

`tests/test_conformance.xi` (module `transliteration_tests`) runs 20 named
checks through `assert(cond, "name")`, one `fn` per check, and `main`
returns the failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | is_ascii | ASCII true; é, Greek, Cyrillic and invalid lead byte false (6.1) |
| t2 | café / Ångström | é->e, Å->A, ö->o |
| t3 | Zürich / über | ü->u |
| t4 | niño / España | ñ->n, ç->c (both cases) |
| t5 | æon / œuvre | æ->ae, œ->oe (both cases) |
| t6 | straße | ß->ss |
| t7 | Škoda / Łódź / Đorđe / žlutý | š, ž, ł, đ, ý |
| t8 | Ελλάδα / θάλασσα / ψυχή / Ξάνθη | Ελλάδα->Ellada, θ->th, ψ->ps, ξ->x |
| t9 | Ελλάς / Ωμέγα / Άλφα / Νίκη | final sigma ς->s, accents, uppercase, φ->ph |
| t10 | Москва / жук / я / Я | а->a ... я->ya |
| t11 | Щука / Харьков / Царь / Ёлка | щ->shch, х->kh, ц->ts, ь omitted, ё->yo |
| t12 | `'`/`"` curly quotes | U+2018/2019 and U+201C/201D |
| t13 | en/em dash, ellipsis | U+2013/2014 -> `-`, U+2026 -> `...` |
| t14 | NBSP | U+00A0 -> one ASCII space (built from bytes) |
| t15 | unmapped dropped | CJK, `✓`, 4-byte emoji, `→` all removed |
| t16 | invalid UTF-8 | truncated 3-byte, invalid continuation, overlong C0 AF, lone 0xE9; valid `é` still maps around them (4) |
| t17 | empty input | `true` / `""` / `""` (3.4) |
| t18 | slug basics | diacritics transliterate then lowercase (6.3) |
| t19 | slug runs/edges | separator runs -> one `-`, edges trimmed, all-separator -> `""` |
| t20 | slug punctuation | punctuation-only -> `""`; digits preserved; `C++ & Rust` -> `c-rust` |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17). Raw invalid bytes are built with `Vec[UInt8]` + `Str::from_utf8`,
since source literals cannot spell every byte.

## 9. Known limitations

- 359-entry curated subset; no CLDR/ISO/ELOT conformance.
- Unmapped codepoints are dropped with no error channel and no replacement
  character.
- Invalid UTF-8 passes through, so output may be invalid UTF-8.
- Cyrillic `ъ`/`ь` are omitted.
- No normalization; combining marks (NFD) are dropped.
- No context sensitivity beyond per-codepoint entries.
- Punctuation coverage is limited to the eight listed codepoints.

## 10. Compiler / stdlib notes

No compiler workarounds were required beyond the documented v0.61.3 idioms:
free functions only, byte-wise scanning via `xiom.string.byte_at`,
`(byte as Int) & 0xFF` guards (never a UInt8 comparison against a literal
>= 128), output accumulated in `Vec[UInt8]` with
`xiom.string.builder.sb_push_str` / `sb_to_str`, table values read into typed
locals and never compared with `==`, and no `Vec[StructType]` (the table is
two parallel `Vec`s). The module imports `xiom.string` and
`xiom.string.builder`; the tests import `xiom.string.compare` as well.
