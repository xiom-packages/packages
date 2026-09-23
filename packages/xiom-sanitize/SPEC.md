# xiom.sanitize -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.sanitize` (`src/sanitize.xi`). Pure XIOM, no FFI.

## 1. Scope

Byte-oriented sanitizers for untrusted input, all free functions
`Str -> Str`:

- replace or drop control characters (`sanitize_control_chars`),
- drop non-ASCII bytes (`sanitize_ascii`),
- normalize space/tab whitespace (`sanitize_whitespace`),
- filter against an allow list (`sanitize_keep`),
- clean one filename component (`sanitize_filename`),
- extract ASCII digits (`sanitize_numeric`),
- build slugs (`sanitize_slug`).

Every function is infallible: it returns `Str` and never reports errors.
Sanitizing is not validating -- an empty or non-numeric result is legal.

## 2. Non-goals

- Unicode-aware processing: no NFC/NFD, no case folding beyond ASCII
  `A-Z -> a-z`, no character classes beyond `[A-Za-z0-9]`.
- Locale awareness of any kind.
- Validation/error reporting: no `Result`, no rejection, no length limits.
- Path handling: `sanitize_filename` cleans one component, it does not
  resolve, reject, or detect traversal, reserved device names or separators
  beyond replacing them.
- HTML/SQL/URL/JSON escaping (see `xiom.escape`).
- Any FFI, file I/O, or registry integration.

## 3. Shared model

1. **Encoding.** `Str` is treated as a UTF-8 byte buffer. All scanning is
   byte-wise. Functions either pass a byte through, replace it, or drop it;
   no function rewrites a multi-byte sequence, so non-ASCII bytes survive
   intact where documented. A function that drops bytes can truncate a
   multi-byte character and emit invalid UTF-8.
2. **Byte classes.**
   - ASCII digit: `0x30-0x39`.
   - ASCII letter: `0x41-0x5A` or `0x61-0x7A`; alphanumeric = digit or letter.
   - Control byte: `0x00-0x1F` or `0x7F` (DEL). LF (`0x0A`) and TAB (`0x09`)
     are control bytes but are named exceptions where stated.
   - Whitespace (for `sanitize_whitespace` only): space (`0x20`) and TAB
     (`0x09`). CR (`0x0D`) is NOT whitespace here.
3. **Non-ASCII.** For filtering rules, every byte >= `0x80` is "not
   alphanumeric" and is dropped unless the rule says otherwise.
4. **Empty input.** The empty string is valid input for every function; only
   `sanitize_filename` substitutes `_` for an empty result.
5. **NUL is not representable.** `Str::from_utf8` truncates at the first NUL
   byte (`[65, 0, 66]` becomes `"A"`), so a constructed `Str` cannot carry
   `0x00`. Rule 4.1 still lists `0x00`, but the suite exercises `0x01`-`0x1F`
   instead (see section 7).

## 4. Per-function rules

### 4.1 `sanitize_control_chars(s, replacement) -> Str`

| Input byte | Output |
|---|---|
| `0x09` TAB | the byte itself (exception) |
| `0x0A` LF | the byte itself (exception) |
| `0x00-0x08`, `0x0B-0x1F` | `replacement`, verbatim (0, 1 or many bytes) |
| `0x7F` DEL | `replacement`, verbatim |
| everything else (incl. `>= 0x80`) | the byte itself |

`replacement` is never interpreted: `""` deletes the control byte, `"<X>"`
inserts three bytes per control byte.

### 4.2 `sanitize_ascii(s) -> Str`

| Input byte | Output |
|---|---|
| `0x00-0x7F` (incl. control bytes) | the byte itself |
| `>= 0x80` | dropped |

### 4.3 `sanitize_whitespace(s) -> Str`

Single left-to-right pass with a pending-run flag; whitespace = space or TAB.

| Situation | Output |
|---|---|
| run of spaces/tabs between two ordinary bytes | one space (`0x20`) |
| run immediately before LF | dropped entirely (LF is emitted) |
| run at the start of the string | dropped (leading trim) |
| run at the end of the string | dropped (trailing trim) |
| run at the start of a line, i.e. right after LF | one space |
| LF | emitted unchanged |
| every other byte (incl. CR, >= 0x80) | emitted unchanged |

Worked examples:

| Input | Output |
|---|---|
| `"  hello   world  "` | `"hello world"` |
| `"line1   \nline2"` | `"line1\nline2"` |
| `"a\t \t\nb"` | `"a\nb"` |
| `"a  \n  b"` | `"a\n b"` |
| `"   "` | `""` |
| `""` | `""` |

### 4.4 `sanitize_keep(s, allow) -> Str`

| Input byte | Output |
|---|---|
| `[A-Za-z0-9]` | the byte itself |
| any byte occurring in `allow` | the byte itself |
| everything else (incl. `>= 0x80` not in `allow`) | dropped |

Membership in `allow` is byte-wise; a multi-byte character in `allow` permits
each of its UTF-8 bytes individually.

### 4.5 `sanitize_filename(s) -> Str`

Two phases:

1. **Map.** Each of `<` `>` `:` `"` `/` `\` `|` `?` `*` and every control
   byte (`0x00-0x1F` and `0x7F`) becomes `_` (`0x5F`); every other byte
   (including `>= 0x80`) passes through.
2. **Trim.** Leading and trailing space (`0x20`) and dot (`0x2E`) bytes are
   removed.
3. **Fallback.** If nothing remains, the result is `"_"`.

Runs of `_` are NOT collapsed; `_` is not in the trim set.

| Input | Output |
|---|---|
| `"a\\b:c*d"` | `"a_b_c_d"` |
| `"a<b>c?d\|e\"f/g"` | `"a_b_c_d_e_f_g"` |
| `"a\tb\nc"` | `"a_b_c"` |
| `"report.txt..."` | `"report.txt"` |
| `"  name . "` | `"name"` |
| `".hidden"` | `"hidden"` |
| `"///"` | `"___"` |
| `"..."`, `""`, `"   "` | `"_"` |

### 4.6 `sanitize_numeric(s) -> Str`

| Input byte | Output |
|---|---|
| `0x30-0x39` | the byte itself |
| everything else (signs, `.`, separators, spaces, `>= 0x80`) | dropped |

The result is not validated as a number: it may be empty or contain leading
zeros. No sign is preserved (callers that need signs must handle them before
sanitizing).

### 4.7 `sanitize_slug(s) -> Str`

Single pass with a pending-separator flag:

| Situation | Output |
|---|---|
| ASCII letter | lowercased (`A-Z -> a-z`) and emitted |
| ASCII digit | emitted |
| run of non-alphanumeric bytes (incl. `>= 0x80`) | one `-` (`0x2D`), and only between two kept bytes |
| leading/trailing separator runs | dropped (no edge `-`) |

Worked examples:

| Input | Output |
|---|---|
| `"Hello World"` | `"hello-world"` |
| `"a..b--c"` | `"a-b-c"` |
| `"--a-b--"` | `"a-b"` |
| `"Café au lait"` | `"caf-au-lait"` |
| `"naïve"` | `"na-ve"` |
| `"é"`, `"-"`, `""` | `""` |

## 5. API signatures

```xi
pub fn sanitize_control_chars(s: Str, replacement: Str) -> Str
pub fn sanitize_ascii(s: Str) -> Str
pub fn sanitize_whitespace(s: Str) -> Str
pub fn sanitize_keep(s: Str, allow: Str) -> Str
pub fn sanitize_filename(s: Str) -> Str
pub fn sanitize_numeric(s: Str) -> Str
pub fn sanitize_slug(s: Str) -> Str
```

Complexity: every function is O(s.len()), except `sanitize_keep` which is
O(s.len() * allow.len()) because the allow set is scanned byte-wise.

## 6. Test plan

`tests/test_conformance.xi` (module `sanitize_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | control replacement | 0x01, 0x08, 0x1F -> `_` (rule 4.1; 0x00 not representable, section 3.5) |
| t2 | LF/TAB preserved | exceptions in 4.1 |
| t3 | DEL replaced | 0x7F -> `_`, 0x7E untouched |
| t4 | replacement verbatim | multi-byte replacement and `""` deletion |
| t5 | ascii filter | `>= 0x80` dropped (4.2) |
| t6 | whitespace collapse | runs -> one space (4.3) |
| t7 | whitespace trim | leading/trailing runs dropped (4.3) |
| t8 | before-LF strip | run before LF dropped, LF kept, indentation after LF kept (4.3) |
| t9 | keep allow set | alnum + caller bytes kept (4.4) |
| t10 | keep drops unicode | non-ASCII dropped (4.4) |
| t11 | filename metachars | all nine specials + control bytes -> `_` (4.5) |
| t12 | filename trim | trailing dots, leading dots, spaces stripped (4.5) |
| t13 | filename fallback | empty results -> `_`; `///` -> `___` (4.5) |
| t14 | numeric extraction | digits kept, signs/separators dropped (4.6) |
| t15 | slug spaces | spaces -> single dash (4.7) |
| t16 | slug case | ASCII lowercasing (4.7) |
| t17 | slug punctuation | separator runs -> one dash (4.7) |
| t18 | slug edge dashes | leading/trailing `-` trimmed (4.7) |
| t19 | slug unicode | non-ASCII dropped as separators (4.7) |
| t20 | empty inputs | every function on `""`; filename -> `_` (rule 3.4) |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Raw control bytes are built with `Vec[UInt8]` +
`Str::from_utf8`, since source literals cannot spell every control byte.

## 7. Known limitations

- Byte-oriented, ASCII-centric (see sections 1-3); non-ASCII results may be
  invalid UTF-8 when bytes are dropped.
- No Unicode normalization, case folding or locale rules.
- No validation channel: callers cannot tell "clean input" from "everything
  was dropped"; only `sanitize_filename` guarantees a non-empty result.
- `sanitize_filename` does not handle Windows reserved device names
  (`CON`, `NUL`, ...), path length limits, or `..` traversal -- `".."` maps
  to `"_"` via the dot trim + fallback, but `"..a"` maps to `"a"`, i.e. no
  traversal detection is attempted.
- `sanitize_numeric` drops signs and decimal points; it does not parse or
  validate numbers.
- No streaming variant; the whole `Str` is processed in memory.
- NUL (`0x00`): `Str::from_utf8` truncates at the first NUL byte, so Strs
  built by the library's own tests (and likely by most callers) cannot carry
  `0x00`; the `sanitize_control_chars` rule includes it, but the suite covers
  only `0x01`-`0x1F` and `0x7F`.

## 8. Compiler / stdlib notes

No compiler workarounds were required beyond the documented v0.61.3 idioms:
free functions only, byte-wise scanning via `xiom.string.byte_at`, output
accumulated in `Vec[UInt8]` with `xiom.string.builder.sb_push_str` /
`sb_to_str`, guard predicates working on `Int` values (`(byte as Int) & 0xFF`)
with `as UInt8` casts on push, and no `==` on `Str`. The module imports
`xiom.string` and `xiom.string.builder` only; it performs no `Str` comparison,
so `xiom.string.compare` is not imported in the library (the tests import it).
