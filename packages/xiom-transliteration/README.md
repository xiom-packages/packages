# xiom.transliteration

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** UTF-8 to ASCII transliteration for Latin, Greek, and Cyrillic
> text, plus ASCII slug generation.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string` and
> `xiom.string.builder`). Tests additionally use `xiom.test`, `xiom.io` and
> `xiom.string.compare`.

## What it is

`xiom.transliteration` decodes UTF-8 codepoints and maps them through a
curated codepoint -> ASCII replacement table. Every function is a free
function `Str -> Str`, scans the input byte-wise and is infallible -- dropped
codepoints and invalid bytes are never reported:

- **diacritics and extended Latin**: `ä -> a`, `é -> e`, `ñ -> n`, `ç -> c`,
  `ø -> o`, `æ -> ae`, `ß -> ss`, `œ -> oe`, `š -> s`, `ž -> z`, `ł -> l`,
  `đ -> d`, ... (Latin-1 Supplement letters and the complete Latin
  Extended-A block);
- **Greek**: `α -> a`, ..., `ω -> o`, `θ -> th`, `χ -> ch`, `ψ -> ps`,
  `ξ -> x`, `η -> e`, `υ -> y`, `φ -> ph`, `ς -> s`;
- **Cyrillic**: `а -> a`, ..., `я -> ya`, `ж -> zh`, `х -> kh`, `ц -> ts`,
  `ч -> ch`, `ш -> sh`, `щ -> shch`, `ы -> y`, `э -> e`, `ю -> yu` (hard and
  soft signs are omitted);
- **punctuation and NBSP**: curly quotes -> `'` / `"`, en/em dash -> `-`,
  ellipsis -> `...`, NBSP -> one space;
- **pass-through / drop**: ASCII bytes pass through unchanged; a codepoint
  with no table entry is dropped; a byte sequence that is not valid UTF-8
  passes through one byte at a time, byte-exact.

The exact decode rules, the table format and the per-function semantics are
pinned in `SPEC.md` and covered by the 20-check conformance suite.

## API

| Function | Returns | Description |
|---|---|---|
| `translit_is_ascii(s)` | `Bool` | True when every byte of `s` is < 0x80 (the empty string is ASCII). |
| `translit_to_ascii(s)` | `Str` | Decode UTF-8; map known codepoints through the table; pass ASCII through; drop unmapped codepoints; pass invalid bytes through one at a time. |
| `translit_slug(s)` | `Str` | `translit_to_ascii(s)`, lowercased, non-alphanumeric runs -> one `-`, leading/trailing `-` trimmed; `""` when nothing survives. |

## Table coverage (359 mappings)

| Block | Range | Entries | Examples |
|---|---|---|---|
| Latin-1 Supplement letters | U+00C0-U+00FF (all letters; excludes the signs `×`/`÷`) | 62 | `é->e`, `ä->a`, `ö->o`, `å->a`, `ñ->n`, `ç->c`, `ø->o`, `æ->ae`, `œ->oe`, `ß->ss`, `þ->th` |
| Latin Extended-A | U+0100-U+017F (complete block) | 128 | `š->s`, `ž->z`, `ł->l`, `đ->d`, `ý->y` |
| Greek | U+0386-U+03CE (letters + accented forms) | 69 | `α->a`, `θ->th`, `χ->ch`, `ψ->ps`, `ξ->x`, `η->e`, `υ->y`, `φ->ph`, `ς->s` |
| Cyrillic | U+0400-U+045F core block + U+0490/U+0491 | 92 | `а->a`, `ж->zh`, `х->kh`, `ц->ts`, `ч->ch`, `ш->sh`, `щ->shch`, `ы->y`, `э->e`, `ю->yu`, `я->ya` |
| Punctuation + NBSP | U+00A0, U+2013/2014, U+2018/2019, U+201C/201D, U+2026 | 8 | `'` `"` `-` `...`, NBSP -> space |

All 359 keys are distinct; the mapping is a single curated scheme (not a
standard romanization).

## Usage

```xi
use xiom.transliteration;
use xiom.io;

fn main() -> Int {
  io.println(translit_to_ascii("Zürich – naïve “café”")); // Zurich - naive "cafe"
  io.println(translit_to_ascii("Москва, Ελλάδα"));        // Moskva, Ellada
  io.println(translit_slug("Café Münster"));              // cafe-munster
  io.println(translit_is_ascii("plain"));                 // true
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.transliteration
```

Expected tail: 20 `[PASS]` lines, `xiom.transliteration: all tests passed`,
then `port: PASS (passed=20 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Curated table subset, not full Unicode CLDR transliteration.** 359
  codepoints are mapped. This is not ISO 9, ELOT 743 or ALA-LC conformance;
  it is one documented, self-consistent scheme (e.g. `х->kh`, `η->e`,
  `φ->ph`, `ё->yo`).
- **Unmapped codepoints are dropped.** Emoji, CJK, Arabic, Hebrew,
  Devanagari, symbols and every script outside Latin/Greek/Cyrillic coverage
  disappear from the output (there is no replacement character and no error
  channel). The transform is intentionally lossy.
- **Invalid UTF-8 passes through.** Bytes that do not form a valid UTF-8
  sequence are copied byte-exact, so the output can itself be invalid UTF-8
  if the input was.
- **Cyrillic `ъ`/`ь` are omitted** (they map to the empty string), matching
  common simplified transliteration.
- **No normalization.** Precomposed characters are mapped; combining marks
  (NFD input) have no entries and are dropped.
- **No context sensitivity.** Each codepoint maps independently; the Greek
  final sigma works because `ς` (U+03C2) has its own entry.
- **Punctuation is limited** to the characters listed above; other quotes,
  dashes and symbols are dropped.
- **Linear scans.** The table is rebuilt per `translit_to_ascii` call and
  scanned linearly per non-ASCII codepoint: O(n * 359) worst case.
- No streaming variant; the whole `Str` is processed in memory.

See `SPEC.md` for the decode rules, the table format and the full test plan.
License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
