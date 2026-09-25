# xiom.gcode -- specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.gcode` (`src/gcode.xi`). Pure XIOM, no FFI.

## 1. Scope and model

A pure-XIOM codec for a documented subset of RS-274-style G-code:

- `gcode_parse_line` -- parse one physical line into a `GcodeLine`,
- `gcode_parse` -- parse a whole text into a `GcodeProgram`, skipping blank
  lines,
- `gcode_emit` -- canonical emission for one parsed line,
- `gcode_micro` -- scaled-integer accessor converting `(value, scale)` to
  millionths,
- line accessors (`gcode_line_*`, `gcode_command_*`, `gcode_param_*`) and
  program accessors (`gcode_command_count`, `gcode_program_param_count`,
  `gcode_program_line`).

Parsing is **stateless and byte-oriented**: nothing is cached, every entry
point rescans its input, and malformed text yields a documented `Err`, never
a crash. Comments and checksums are recognized but not retained: the model is
the command/parameter stream. All arithmetic is 64-bit signed integer
arithmetic; there is no floating point, no locale, no I/O and no global
state.

The program type is a struct of parallel `Vec`s (XIOM v0.61.3 cannot hold a
`Vec[StructType]`): one entry per non-blank line for the command stream, plus
one flat parameter stream with per-line ranges.

## 2. Non-goals

- **No motion or modal semantics:** `G0`/`G1`/`M3`/... are opaque words; no
  coordinate interpolation, no plane/units/tool-offset state, no arcs (`G2`
  is just the word `G2`).
- **No machine state:** nothing is carried between lines; the parser does not
  know a line is a "modal continuation".
- **No file I/O** and no streaming/incremental parsing: inputs are `Str`
  values, outputs are plain values; the package never reads or writes files.
- **No letter whitelist:** any ASCII letter may open a word; the "command
  letter (G/M/T/S etc.)" distinction is positional (first word of the line),
  not semantic.
- **No comments or checksums in the output:** `gcode_emit` drops both; the
  parser does not retain comment text.
- **No `%` program delimiters, no `:` block deletes, no macro/expression
  syntax, no `#` parameters, no line-continuation rules.**
- **No nested parentheses:** the first `)` closes a `( ... )` comment.
- **ASCII only:** the scanner is byte-wise; multi-byte UTF-8 is never decoded
  and never accepted as a digit or letter.

## 3. Line grammar

Informal grammar of one physical line (no line terminator; a trailing CR is
whitespace):

```
line        = trivia [ line-number trivia ] ( word trivia )* [ checksum trivia ]
trivia      = ( ws | ';' text | '(' text ')' )*
line-number = ( 'N' | 'n' ) digits                 (first word only)
word        = letter number
letter      = 'A'..'Z' | 'a'..'z'
number      = sign? ( digits ( '.' digits* )? | '.' digits+ )
sign        = '+' | '-'
digits      = '0'..'9'+
checksum    = '*' hex hex                          (last non-trivia element)
hex         = '0'..'9' | 'A'..'F' | 'a'..'f'
ws          = ' ' | '\t' | '\r' | '\n'             (skipped anywhere)
comment     = ';' ... end-of-line
            | '(' ... first ')' after the '('
```

Decisions (each one is covered by the conformance suite):

1. **Word shape.** A word is a letter *immediately* followed by its number;
   `X 10` is two tokens: the word `X` (bad number) and the standalone number
   `10` (also bad number). Adjacent words need no separator: `G1X1Y2` is
   `G1`, `X1`, `Y2`.
2. **Line number.** The first word of the line is the line number exactly
   when its letter is `N`/`n` and it is a plain run of digits (no sign, no
   dot, at least one digit). It is stored in `line_number` and is not a
   parameter. `N` anywhere else is an ordinary word; the parser does not
   reject duplicate line numbers.
3. **Command.** The first word after the optional line number is the command;
   every following word is a parameter. A line with no command word (for
   example `N10` alone, or a checksum-only line) is a `missing command`
   error; it is not blank.
4. **Letters.** Case-insensitive; the stored letter is always uppercase.
   Any ASCII letter is accepted (see non-goals).
5. **Whitespace.** Space, tab, CR and LF are skipped between tokens and
   around the line number, words, comments and checksum. Leading and
   trailing whitespace is irrelevant. Because LF is also skipped, a caller
   that parses a multi-line string as one line gets one merged stream rather
   than an error.
6. **Comments.** `;` ignores the rest of the line. `(` ignores bytes up to
   the first `)`; parentheses do not nest, so `G1 (a(b) X1` has the comment
   `a(b` and the parameter `X1`. An unterminated `(` is an error. A comment
   may appear wherever whitespace is allowed; a `;` or `*` inside it is
   comment text.
7. **Checksum.** The first `*` outside a comment starts the checksum suffix.
   Exactly two hex digits must follow (either case); anything after them may
   only be whitespace and comments, otherwise the line has `trailing
   garbage`. The suffix value must equal the XOR described in section 4. A
   checksum after a `( ... )` comment is evaluated on the bytes that precede
   the `*`, comments included.
8. **Blank lines.** A line with no word and no checksum marker -- including
   empty, whitespace-only and comment-only lines -- parses as `Ok` with
   `blank = true`. `gcode_parse` skips blank lines (they consume no command
   slot) but still counts them for error positions.
9. **Error order.** The scanner reports the first structural error in scan
   order (bad number, bad line number, unterminated comment, unexpected
   character); checksum malformedness and trailing garbage are reported next,
   then a checksum mismatch, then a missing command.
10. **Determinism.** The same text always yields the same values and the same
    error; the input is never mutated.

## 4. Checksum rule

`XOR` is computed over every byte of the line from byte offset 0 up to (not
including) the `*`, each byte widened with `& 0xFF`. The two suffix digits are
parsed as hex (either case) and compared as an integer.

| Line prefix | XOR | Suffix |
|---|---|---|
| `G1 X1` | `0x3F` = 63 | `*3F` or `*3f` |
| `N10` | `0x4F` = 79 | `*4F` |
| `N10 G0 X0` | `0x50` = 80 | `*50` |
| `G1 (c)` | `0x34` = 52 | `*34` |
| ` (c) G1` | `0x14` = 20 | `*14` |

The conformance suite recomputes these values independently of the library
with its own byte-wise XOR helper.

## 5. Number and scaling rules

A number keeps **two representations**:

- **`text`** -- the verbatim source text without the leading letter, e.g.
  `10.50`, `+3`, `.5`, `007`. It is never normalized by the parser.
- **`value` / `scale`** -- the signed scaled integer and the number of
  decimal fraction digits (0-18). `value = magnitude * 10^scale` where
  `magnitude` is the concatenation of the integer and fraction digits:
  `"10.50"` -> `value = 1050`, `scale = 2`; `".050"` -> `value = 50`,
  `scale = 3`; `"+3"` -> `value = 3`, `scale = 0`; `"5."` -> `value = 5`,
  `scale = 0`.

The numeric magnitude is `value / 10^scale`; the pair is exact, and the
parser never divides or truncates a parsed number.

Boundaries:

- the accumulated magnitude must fit the signed 64-bit range
  (`<= 9223372036854775807`), otherwise `number too large`;
- more than 18 fraction digits is `too many fraction digits` (this also
  bounds `10^scale` for emission);
- a lone `.` or `+`/`-`, a second `.`, or a sign/digit after the fraction
  dot is a bad number;
- `-0`, `-0.0` and `0.000` all yield `value = 0`; the sign of a zero is not
  retained.

`gcode_micro(value, scale)` converts to millionths (1e-6 units):

```
scale <= 6:  micro = value * 10^(6-scale)          (overflow -> Err)
scale >  6:  micro = value / 10^(scale-6)          (truncates toward zero)
```

The sign is applied to the magnitude, so truncation is toward zero for
negative values too. Pins: `(105, 1) -> 10500000` (10.5), `(12345, 7) ->
1234` (0.0012345), `(-12345, 7) -> -1234`, `(-3, 0) -> -3000000`,
`(5, 6) -> 5`, `(1, 18) -> 0`. A value below `-9223372036854775807` (the
parser's own magnitude cap, so only reachable by hand-built calls) or a
multiplication overflow is `value out of range`.

## 6. Canonical emission

`gcode_emit` renders one parsed line as:

```
[ 'N' line-number ' ' ] letter number ( ' ' letter number )*
```

- the `N` prefix appears exactly when `line_number >= 0`;
- the number is re-rendered from `(value, scale)`: scale 0 uses the plain
  decimal integer; scale > 0 uses exactly `scale` fraction digits with at
  least one integer digit and no leading zeros; `-` appears only when
  `value < 0`; `+`, leading zeros and a trailing `.` are never emitted;
- one space separates words; there is no leading or trailing whitespace, no
  comment, no checksum and no newline;
- a blank line emits `""`.

`gcode_emit` is a fixed point on canonical text: for any canonical line `s`
(one already in emitted form), `gcode_emit(parse_line(s)) == s`, and
`parse_line(gcode_emit(parse_line(s)))` equals `parse_line(s)` on every
letter, value, scale and line number (texts of non-canonical inputs may be
renormalized).

Examples: `G01 X+010.50 Y.5` -> `G1 X10.50 Y0.5`; `N007 G0 X0` ->
`N7 G0 X0`; `m3 s1000` -> `M3 S1000`; `G1 X1*3F` -> `G1 X1`;
`G1 Y-0.0` -> `G1 Y0.0`.

## 7. API contract

Types:

```
pub type GcodeLine   = { blank: Bool; line_number: Int;
                         command_letter: Str; command_text: Str;
                         command_value: Int; command_scale: Int;
                         param_letters: Vec[Str]; param_texts: Vec[Str];
                         param_values: Vec[Int]; param_scales: Vec[Int] }
pub type GcodeProgram = { line_numbers: Vec[Int]; letters: Vec[Str];
                          texts: Vec[Str]; values: Vec[Int]; scales: Vec[Int];
                          param_start: Vec[Int]; param_count: Vec[Int];
                          param_letters: Vec[Str]; param_texts: Vec[Str];
                          param_values: Vec[Int]; param_scales: Vec[Int] }
```

| Function | Returns | Behavior |
|---|---|---|
| `gcode_parse_line(text)` | `Result[GcodeLine, Str]` | Parse one line; blank -> `Ok` with `blank = true`. |
| `gcode_parse(text)` | `Result[GcodeProgram, Str]` | Parse LF-separated text; blank lines skipped; errors are `gcode: line <n>: <detail>` with the 1-based physical line number. |
| `gcode_emit(line)` | `Str` | Canonical line text; `""` for blank. |
| `gcode_line_is_blank(line)` | `Bool` | The `blank` flag. |
| `gcode_line_number(line)` | `Int` | `N` value; `-1` when absent or blank. |
| `gcode_command_letter(line)` | `Str` | Uppercase command letter; `""` for blank. |
| `gcode_command_text(line)` | `Str` | Verbatim command number text. |
| `gcode_command_value(line)` | `Int` | Scaled command value. |
| `gcode_command_scale(line)` | `Int` | Command fraction digit count. |
| `gcode_param_count(line)` | `Int` | Parameter count. |
| `gcode_param_letter(line, j)` | `Str` | Uppercase parameter letter; `""` when out of range. |
| `gcode_param_text(line, j)` | `Str` | Verbatim parameter number text; `""` when out of range. |
| `gcode_param_value(line, j)` | `Int` | Scaled parameter value; `0` when out of range. |
| `gcode_param_scale(line, j)` | `Int` | Parameter fraction digit count; `0` when out of range. |
| `gcode_micro(value, scale)` | `Result[Int, Str]` | Millionths (section 5). |
| `gcode_command_count(program)` | `Int` | Number of non-blank lines (commands). |
| `gcode_program_param_count(program)` | `Int` | Total parameter words across all commands. |
| `gcode_program_line(program, i)` | `GcodeLine` | Rebuild command `i`; a blank line value when `i` is out of range. |

Line numbers in `gcode_parse` errors count **physical** lines, including
blank and comment-only lines.

## 8. Error catalog

`gcode_parse_line` prefixes every detail with `gcode: `;
`gcode_parse` wraps the same detail as `gcode: line <n>: <detail>`.

| Message | Trigger |
|---|---|
| `gcode: bad line number` | First word is `N`/`n` but not a plain digit run: missing number, sign, dot, or a magnitude beyond the 64-bit range. |
| `gcode: bad number: <word>` | A letter with a malformed/absent number, a number with a second `.` or an inner sign, or a standalone number with no letter (`123`, `.5`, `-2`). `<word>` is the letter plus its number run, or the whole run when there is no run (e.g. `Xabc`). |
| `gcode: number too large: <word>` | The accumulated magnitude exceeds `9223372036854775807`. |
| `gcode: too many fraction digits: <word>` | More than 18 digits after the `.`. |
| `gcode: bad checksum` | `*` with fewer than two following bytes or a non-hex digit in either of the two suffix positions. |
| `gcode: checksum mismatch: <hh>` | The two suffix digits (as written) do not equal the recomputed XOR. |
| `gcode: unterminated paren comment` | `(` with no closing `)` -- including a `(` after the checksum digits. |
| `gcode: trailing garbage` | After the two checksum digits, a byte that is neither whitespace nor the start of a comment. |
| `gcode: unexpected character at <pos>` | A byte that starts no token (not whitespace, letter, number, comment or `*`); `<pos>` is the 0-based byte offset within the line. |
| `gcode: missing command` | The line has a line number and/or a checksum but no command word. |
| `gcode: bad scale` | `gcode_micro` called with `scale < 0` or `scale > 18`. |
| `gcode: value out of range` | `gcode_micro` with `value < -9223372036854775807`, or a `scale <= 6` multiplication that would overflow the signed 64-bit range. |

## 9. Test matrix (`tests/test_conformance.xi`, 23 checks)

| # | Check |
|---|---|
| 1 | Canonical `N10 G1 X10.5 Y-3`: line number, command, both parameters, accessors. |
| 2 | Verbatim texts and scaling for `G0.50 X.050 Y+10.50`. |
| 3 | Case-insensitive letters and `N` (`n5 m3 s1000 x1.5 y-2`). |
| 4 | Whitespace tolerance and adjacent words (`G1X1Y2`). |
| 5 | `;` and `( ... )` comments; first `)` closes; `*` inside a comment. |
| 6 | Blank lines: empty, whitespace, comment-only, `()`, mixed; emit `""`. |
| 7 | `N10`, `N10 (c)`, `N10 ; c`, `N10*4F` -> missing command (checksum first). |
| 8 | Bad line numbers: `N`, `N-1`, `N1.5`, `N+0`, `Nx`, 20-digit overflow. |
| 9 | Bad numbers: `G`, `X1.2.3`, `X+`, `Xabc`, `.5`, `123`, `X1-2`. |
| 10 | Unterminated paren comments, including after a valid checksum. |
| 11 | Unexpected characters report their byte offset. |
| 12 | Checksum accepted: literal `*3F`, computed `*50`, lower-case `*3f`, trailing `;` and `( )` comments, trailing CR. |
| 13 | Checksum XOR covers comments and leading whitespace (`G1 (c)*34`, ` (c) G1*14`); content after a checksum is garbage. |
| 14 | Malformed suffixes: `*`, `*3`, `*G1`, `* 3F`, `**3F`. |
| 15 | Mismatches quote the suffix: `*40`, `*00` (twice). |
| 16 | Trailing garbage after the suffix: word, bare byte, second `*`. |
| 17 | Document parse: CRLF, blank and comment lines skipped, command order, per-command parameters, canonical emission. |
| 18 | Document errors carry the 1-based physical line number (bad number, bad line number, checksum mismatch). |
| 19 | Emitter normalization incl. checksum/comment dropping and negative zero. |
| 20 | Round-trips: parse -> emit -> parse equality, blank line, 64-bit extremes, emit fixed points. |
| 21 | `gcode_micro`: pins, truncation, sign, overflow (including `INT_MIN`) and bad scale. |
| 22 | Boundaries: `9223372036854775807`, one past it, 18 vs 19 fraction digits. |
| 23 | Out-of-range accessors and empty documents return documented defaults. |

Expected harness tail: 23 `[PASS]` lines, then `xiom.gcode: all tests passed`,
then `port: PASS (passed=23 failed=0 program_exit=0 exit=0)`.

## 10. Compiler / stdlib notes (XIOM v0.61.3)

Written under the same constraints as its sibling packages:

- free functions only -- no self methods, no lambdas, no `Vec[StructType]`
  (the program is a struct of parallel `Vec`s), no `Vec[fn]` dispatch, no
  `Vec[Float64]`;
- `Str` values read from `Vec[Str]` elements are never compared with `==`
  (BUG 17 lowers that to a pointer comparison); element reads are bound with
  typed `let`s and the tests route every text comparison through
  `xiom.string.compare.str_compare`;
- `string.byte_at` results are widened with `as Int` and masked with
  `& 0xFF` before arithmetic;
- `Ok`/`Err` are constructed only in the leaf helpers (`_ok_int`, `_err_int`,
  `_ok_num`, `_err_num`, `_ok_line`, `_err_line`, `_ok_program`,
  `_err_program`) because constructing a `Result` inside a larger function
  miscompiles;
- `result.value` / `result.error` are read through `.is_ok` rather than
  `match` in the library; the tests use `.is_ok`/`.value`/`.error` helpers as
  well.
