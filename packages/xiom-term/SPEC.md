# xiom.term -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.term` (`src/term.xi`). Pure XIOM, no FFI, no `Result` channel.

## 1. Scope

Byte-oriented ANSI/VT escape handling over `Str`:

- detect escapes (`term_has_escapes`, `term_is_plain`),
- remove escape sequences (`term_strip`),
- count removed sequences (`term_count_escapes`),
- measure the visible text (`term_visible_len`),
- truncate on a visible-byte budget while keeping styling
  (`term_truncate_visible`),
- extract SGR parameters (`term_parse_sgr`).

Every function is infallible: it returns a `Str`, `Bool`, `Int` or
`Vec[Int]` and never reports errors. Malformed input is handled leniently by
the rules below; nothing is validated and no output is rejected.

## 2. Sequence grammar

`ESC` is byte `0x1B`. Scanning is left to right; an ESC byte starts exactly
one unit:

| Unit | Start | End | Unterminated |
|---|---|---|---|
| CSI | `ESC '['` | the first following byte in `0x40..0x7E` (the final byte), inclusive | consumes to end of input |
| OSC | `ESC ']'` | BEL (`0x07`) or ST (`ESC '\'`), inclusive | consumes to end of input |
| Two-byte | any other `ESC` | the ESC plus exactly one following byte | n/a |
| Lone ESC | `ESC` at end of input | nothing follows | dropped by itself |

For a two-byte unit the second byte is dropped with the ESC; there is no
special casing of `ESC '['`/`ESC ']'` follow-ups, because those are CSI/OSC.

Examples (`. = ESC`, `BEL` = `0x07`, `ST` = `ESC '\'`):

| Input (escaped) | Unit | Bytes |
|---|---|---|
| `. [ 3 1 m` | CSI | 5 |
| `. [ 1 0 ; 2 0 H` | CSI | 8 |
| `. [ K` | CSI | 3 |
| `. ] 0 ; t BEL` | OSC | 6 |
| `. ] 8 ; ; u ST` | OSC | 7 |
| `. ( B` | two-byte | 2 |
| `.` | lone ESC | 1 |
| `. [ 3 1` | CSI, unterminated | 3 (to end) |
| `. ] 0 ; t` | OSC, unterminated | 5 (to end) |

Notes:

- A CSI ends at the first byte in `0x40..0x7E`; bytes below `0x40`
  (including another ESC) do not terminate it. This is the same rule
  `term_strip` documents and applies consistently in every function.
- A CSI that reaches end of input without a final byte is consumed entirely
  and never counts as SGR.
- Inside an OSC, an ESC not followed by `\` is payload; only `BEL` or
  `ESC '\'` terminates.

## 3. Per-function rules

All functions read `s` byte-wise and perform no `Str` comparison.

### 3.1 `term_has_escapes(s) -> Bool`

True when any byte of `s` equals `0x1B`; false otherwise, including `""`.
No sequence parsing is involved: a malformed or unterminated unit still
counts as an escape.

### 3.2 `term_is_plain(s) -> Bool`

`!term_has_escapes(s)`. `""` is plain.

### 3.3 `term_strip(s) -> Str`

Single left-to-right pass. When the byte is ESC, the whole unit (section 2)
is dropped; every other byte is copied verbatim in order. Bytes `>= 0x80`
pass through unchanged, so stripping never invalidates UTF-8. `0x00` is not
representable in a `Str` built with `Str::from_utf8` (it truncates at the
first NUL), which does not affect the rules above.

Worked examples:

| Input (escaped) | Output |
|---|---|
| `. [ 3 1 m r e d . [ 0 m` | `red` |
| `. [ 2 A m o v e . [ K` | `move` |
| `. ] 0 ; t i t l e BEL t e x t` | `text` |
| `. ] 0 ; t i t l e ST t e x t` | `text` |
| `. [ 1 m . [ 3 1 m . [ 4 m A` | `A` |
| `p l a i n` | `plain` |
| `a b . [ 3 1` | `ab` (unterminated CSI to end) |
| `a b c .` | `abc` (trailing lone ESC) |
| `""` | `""` |

### 3.4 `term_count_escapes(s) -> Int`

Increments once per unit consumed by the `term_strip` state machine. For
well-formed input this equals the number of ESC bytes; a trailing lone ESC
counts once; a unit cut short by a malformed byte (for example an ESC that
happens to itself be the final byte of a preceding CSI) still counts once.

| Input (escaped) | Count |
|---|---|
| `. [ 3 1 m r e d . [ 0 m` | 2 |
| `. [ 1 m . [ 3 1 m . [ 4 m A` | 3 |
| `p l a i n`, `""` | 0 |
| `a b . [ 3 1` | 1 |
| `a b c .` | 1 |

### 3.5 `term_visible_len(s) -> Int`

`term_strip(s).len()`: the byte length of the visible text. Counting is
byte-oriented (section 6).

### 3.6 `term_truncate_visible(s, n) -> Str`

Budget `n` is a count of visible bytes.

1. **Empty budget.** `n <= 0` returns `""` (never a reset-only string).
2. **Copy.** Scan left to right, copying bytes and escape units. A unit that
   is reached before the cut is copied verbatim, so escapes that precede the
   kept visible bytes are preserved. A unit is reached before the cut when
   fewer than `n` visible bytes have been copied when it starts.
3. **Cut.** Scanning stops immediately after the `n`-th visible byte. All
   remaining bytes are dropped.
4. **Reset.** When a cut happened and the dropped remainder contains at least
   one SGR sequence -- a terminated CSI whose final byte is `m` -- the result
   ends with `ESC '[' '0' 'm'` (four bytes). Otherwise the result is a plain
   truncation. Unterminated CSI and non-CSI units never trigger the reset.
5. **No cut.** When the string ends at or before the `n`-th visible byte (its
   visible length is `<= n` and no byte remains after that byte), the input
   is returned unchanged, escapes included, with no reset.

Worked examples (`n` is the budget; `.` = ESC):

| Input (escaped) | n | Output (escaped) | Why |
|---|---|---|---|
| `. [ 3 1 m a b c d e f . [ 0 m` | 3 | `. [ 3 1 m a b c . [ 0 m` | SGR cut, reset appended |
| `. [ 3 1 m a b . [ 3 2 m c d e f` | 3 | `. [ 3 1 m a b . [ 3 2 m c` | second SGR precedes the cut, kept; no SGR dropped, no reset |
| `. [ 3 1 m a b . [ 3 2 m c d . [ 3 3 m e f` | 3 | `. [ 3 1 m a b . [ 3 2 m c . [ 0 m` | third SGR dropped after the cut, reset appended |
| `. [ 3 1 m a b . [ 4 m c d e f` | 2 | `. [ 3 1 m a b . [ 0 m` | SGR at the cut dropped, reset appended |
| `. [ 3 1 m a b c . [ 2 A` | 2 | `. [ 3 1 m a b` | non-SGR cut, no reset |
| `. [ 3 1 m a b c d` | 4 | `. [ 3 1 m a b c d` | ends at the boundary, unchanged |
| `h e l l o w o r l d` | 5 | `h e l l o` | plain truncation |
| `. [ 3 1 m r e d` | 0, -1 | `""` | empty budget |

### 3.7 `term_parse_sgr(s) -> Vec[Int]`

Scans for terminated CSI sequences whose final byte is `m` and appends their
parameters to a flat `Vec[Int]`, in input order:

1. The parameter region is the text between `ESC '['` and the final byte.
2. The separators `;` (0x3B) and `:` (0x3A) both end a parameter. Treating
   `:` as a separator flattens colon-form extended colours
   (`38:5:196` -> `38, 5, 196`).
3. A parameter contributes the value of its leading run of ASCII digits
   (base 10). A parameter with no digits at all (empty, or starting with a
   non-digit) contributes `0`; bytes that are neither digits nor separators
   are ignored (they do not split or end a parameter).
4. Digit runs after a non-digit byte inside the same parameter are part of
   the same leading value only when they directly continue the digit run;
   e.g. `2x3` parses as `23` because `x` is ignored.
5. A sequence with no parameter bytes (`. [ m`) contributes one `0`.
6. Multiple sequences are concatenated in order; unterminated CSI sequences
   and non-CSI units contribute nothing.

Worked examples (`.` = ESC):

| Input (escaped) | Result |
|---|---|
| `. [ 1 ; 3 1 m` | `[1, 31]` |
| `. [ m` | `[0]` |
| `. [ 1 ; ; 3 m` | `[1, 0, 3]` |
| `. [ 3 8 : 5 : 1 9 6 m X . [ 1 m` | `[38, 5, 196, 1]` |
| `. [ 3 1 m r e d . [ 0 m` | `[31, 0]` |
| `p l a i n`, `""` | `[]` |
| `. [ 3 1` (unterminated) | `[]` |
| `. ] 0 ; t BEL` | `[]` |

## 4. API signatures

```xi
pub fn term_has_escapes(s: Str) -> Bool
pub fn term_is_plain(s: Str) -> Bool
pub fn term_strip(s: Str) -> Str
pub fn term_count_escapes(s: Str) -> Int
pub fn term_visible_len(s: Str) -> Int
pub fn term_truncate_visible(s: Str, n: Int) -> Str
pub fn term_parse_sgr(s: Str) -> Vec[Int]
```

Complexity: every function is a single pass over `s`, i.e. O(s.len());
`term_visible_len` is O(s.len()) plus one allocation for the stripped text.
`term_truncate_visible` allocates one output buffer.

## 5. Test plan

`tests/test_conformance.xi` (module `term_tests`) runs 20 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | strip SGR | colour sequences removed (3.3) |
| t2 | strip cursor/erase | cursor-move and erase CSI removed (3.3) |
| t3 | OSC BEL | OSC terminated by BEL removed; BEL body dropped (3.3) |
| t4 | OSC ST | OSC terminated by `ESC '\'` removed (3.3) |
| t5 | consecutive escapes | adjacent and trailing units all removed (3.3) |
| t6 | plain passthrough | text, TAB/LF and `""` unchanged (3.3) |
| t7 | detect | `has_escapes`/`is_plain` for escaped, plain and `""` (3.1, 3.2) |
| t8 | count | one per unit; 0 for plain/empty (3.4) |
| t9 | visible length | stripped byte length including OSC and escape-only input (3.5) |
| t10 | truncate boundary | exact boundary unchanged; trailing non-SGR dropped without reset (3.6) |
| t11 | truncate reset | reset appended when an SGR is cut, incl. an SGR exactly at the cut (3.6) |
| t12 | truncate plain | cut inside plain text; n beyond length unchanged (3.6) |
| t13 | n = 0 / negative | `""` in every case (3.6 rule 1) |
| t14 | unterminated CSI | consumed to end; counted once; not SGR (3.3, 3.4, 3.7) |
| t15 | lone trailing ESC | dropped; counted once; visible length unaffected (3.3, 3.4) |
| t16 | parse_sgr flatten | `[1,31]`; empty parameter => 0; `[1,0,3]` (3.7) |
| t17 | edge escapes | escapes at start/end stripped, detected and truncation-stable (3.3, 3.6) |
| t18 | parse_sgr order | several sequences flatten in order; colon form (3.7) |
| t19 | non-SGR cut | no reset for cursor CSI or OSC cuts (3.6 rule 4) |
| t20 | parse_sgr ignores / idempotence | non-CSI and unterminated input ignored; strip(strip(x)) == strip(x) (3.3, 3.7) |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); `Vec[Int]` elements are read through an explicitly
typed local and compared as `Int`. Escape bytes are written as `\x1b`,
`\x07` and `\\` literals; no escape literal is immediately followed by a hex
digit, so no literal-parsing ambiguity arises.

## 6. Known limitations

- **Byte-oriented visible length.** `term_visible_len` and the `n` budget of
  `term_truncate_visible` count bytes, not display columns: wide characters
  (CJK, emoji), combining marks and grapheme clusters are not handled, and a
  cut may fall inside a multi-byte UTF-8 sequence, producing invalid UTF-8.
  ASCII-oriented, like the rest of the package.
- `term_strip` removes ESC-initiated units only; other control bytes (CR,
  BEL outside an OSC, other C0/C1 controls) pass through.
- `term_parse_sgr` is syntactic: it does not validate parameter meaning,
  clamps or ranges, and colon-form sub-parameters are flattened rather than
  interpreted.
- No Windows console/VT enablement, cursor state tracking, or rendering.
- No streaming variant; the whole `Str` is processed in memory.
- No error channel: malformed input is handled leniently (unterminated units
  consume to end) and never reported.

## 7. Compiler / stdlib notes

No compiler workarounds were required beyond the documented v0.61.3 idioms:
free functions only, byte-wise scanning via `xiom.string.byte_at` with
`(byte as Int) & 0xFF` widening, output accumulated in `Vec[UInt8]` and
materialized once with `xiom.string.builder.sb_to_str`, and no `==` on
`Str`. The module imports `xiom.string` and `xiom.string.builder` only; it
performs no `Str` comparison, so `xiom.string.compare` is imported by the
tests, not by the library.
