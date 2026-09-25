# xiom.pgn -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.pgn` (`src/pgn.xi`). Pure XIOM, no FFI, no file I/O.

## 1. Scope

An in-memory codec for a documented subset of PGN (Portable Game Notation,
the 1994 standard's export format):

- `pgn_parse` -- PGN text -> `Result[Game, Str]`: a tag list plus a flat
  movetext token stream,
- accessors for tags (`pgn_tag_count`, `pgn_tag_name`, `pgn_tag_value`,
  `pgn_tag_of`) and movetext (`pgn_move_count`, `pgn_move_kind`,
  `pgn_move_text`, `pgn_move_start`, `pgn_result`),
- `pgn_is_san` -- standalone lexical SAN validation,
- `pgn_emit` -- canonical serialization of a parsed game.

The codec validates *lexically and structurally*: tag syntax, movetext token
shapes, move-number sequence and SAN lexical form. It never consults a board,
a game tree or a rule engine, so `1. e4 e4` parses exactly like any other
token sequence.

## 2. Non-goals

- No board legality, check/checkmate verification, disambiguation
  correctness, or move generation of any kind.
- No recursive annotation variations: `(` and `)` abort with
  `pgn: unsupported variation at <pos>`.
- No NAG semantics: `$n` is stored as its digit text and emitted back
  unchanged.
- No clock/annotation interpretation, no eval comments, no glyph syntax
  (`!`, `?` are not SAN here; use NAGs).
- No recursive/streaming parsing, no multi-game files: one call parses one
  game; a second game's tag section after movetext is a stray-character
  error. Split multi-game files with the caller's own game-separator logic.
- No byte-exact round-tripping of the original text: `pgn_emit` is canonical
  (spacing, line structure and tag escaping are normalized); token sequences
  round-trip exactly (section 5).
- No transfer of unknown tag values, no date/ECO/result semantics beyond the
  four result tokens.

## 3. Data model

```xi
pub type TagList = {
  names: Vec[Str];   // tag names, verbatim, document order
  values: Vec[Str];  // values with \" and \\ decoded
}

pub type MoveText = {
  kinds: Vec[Str];   // "num" | "san" | "comment" | "comment_line" | "nag" | "result"
  texts: Vec[Str];   // token text, per the table below
  starts: Vec[Int];  // byte offset of the token in the parsed input
}

pub type Game = {
  tags: TagList;
  moves: MoveText;
}
```

Invariants: `names.len() == values.len()` and
`kinds.len() == texts.len() == starts.len()`; duplicate tag names are
preserved in order; `Vec[StructType]` is not usable in this compiler, so the
streams are parallel homogeneous vectors rather than token structs.

Per-kind `texts[i]`:

| kind | token text |
|---|---|
| `"num"` | canonical move number: `N.` or `N...` (digits kept verbatim, so leading zeros survive: `0001.` stays `0001.`) |
| `"san"` | the SAN token exactly as written |
| `"comment"` | the bytes between `{` and `}`, verbatim (may contain newlines) |
| `"comment_line"` | the bytes after `;` up to (not including) the line terminator, verbatim |
| `"nag"` | the digits after `$`, without the `$` |
| `"result"` | `1-0`, `0-1`, `1/2-1/2` or `*` |

`starts[i]` points at the `{` of a brace comment, the `;` of a line comment,
the `$` of a NAG, the first digit of a move number or result token, and the
first byte of an SAN token.

## 4. Grammar

```
document     = *( ws | escape-line | tag-pair ) movetext
tag-pair     = "[" ws* name 1*space-tab '"' value '"' space-tab* "]" line-end
name         = 1*( ALNUM | "_" )
value        = *( escaped | byte except '"' / "\" / LF / CR )
escaped      = "\" '"' | "\" "\"
movetext     = *( ws | escape-line | comment | comment-line | nag | num | san | result )
comment      = "{" *( byte except "}" ) "}"          ; may span lines
comment-line = ";" *( byte except LF / CR )
nag          = "$" 1*DIGIT
num          = 1*DIGIT "." | 1*DIGIT "..."
result       = "1-0" | "0-1" | "1/2-1/2" | "*"
san          = castling [check] | piece-move [check] | pawn-move [check]
castling     = "O-O" | "O-O-O"
piece-move   = PIECE [file] [rank] ["x"] file rank
pawn-move    = [file "x"] file rank ["=" PROMO]
PIECE        = "K" | "Q" | "R" | "B" | "N"
PROMO        = "Q" | "R" | "B" | "N"
check        = "+" | "#"
file         = "a".."h"        rank = "1".."8"
escape-line  = "%" *( byte except LF / CR )          ; % may appear wherever a token could start
line-end     = LF | CRLF | CR | EOF
```

Parsing decisions (each is covered by the conformance suite):

1. **Two phases.** Tag pairs are recognized only before the first non-tag
   token; whitespace, `%` escape lines and further tag pairs may repeat
   freely. The first byte that can start neither ends the tag phase and
   begins the movetext. A `[` in movetext is a stray-character error.
2. **Tag pair line.** A tag pair must open and close on one physical line.
   A missing `]` (end of line or end of input) is `unterminated tag`; a
   missing closing quote is `unterminated quote`; anything other than
   whitespace between the closing quote and `]` is a stray character.
3. **Tag names and values.** Names are one or more ALNUM/`_` bytes and are
   kept verbatim (lookup is byte-exact and case-sensitive: PGN tag names
   are). At least one space/tab must separate the name from the value, and
   the value must be a `"..."` literal. Values decode only `\"` -> `"` and
   `\\` -> `\`; any other backslash sequence is an invalid escape, and a raw
   LF/CR before the closing quote is an unterminated quote. A value may be
   empty (`X ""`).
4. **Move numbers.** No whitespace is allowed between the digits and the
   dots (`1 .` is unsupported). One dot is the white/next-move form, three
   dots the continuation form, and the digits may be attached to the
   following SAN (`1.e4`). A digit run followed by `-` or `/` is treated as
   an attempted result token, never as a number.
5. **Move-number sequence.** Numbers are optional, but when present: the
   first must be `N.` with N = 1; a later `N.` must satisfy N = previous + 1;
   a later `N...` must satisfy N = previous (so the ellipsis form needs a
   preceding number token). Digits are parsed with a clamp at 10^9, so
   absurdly long numbers fail the sequence check instead of overflowing.
6. **SAN lexical rules.** The table in section 4 is the whole grammar; see
   section 5 for the exact acceptance order. Case is significant: piece
   letters are uppercase, files lowercase, castling uses the letter `O`
   (an ASCII zero `0-0` is rejected as an illegal result token).
7. **Comments.** Brace comments run to the first `}` regardless of newlines
   and nesting; an unclosed comment is an error at its `{`. Line comments
   run to the next LF or CR. Both are preserved verbatim, including leading
   whitespace after `;`.
8. **NAGs.** `$` must be followed by at least one digit; the digits are kept
   without the `$`.
9. **Results.** The four result tokens above are recognized exactly. At most
   one may appear, and after it only comments and `%` escape lines may
   follow: any other token is `token after result`.
10. **Escape lines.** A `%` where a movetext token could start skips bytes
    to the next LF/CR; the terminator itself is ordinary whitespace. A `%`
    inside a comment is comment text.
11. **Whitespace and line endings.** Space, tab, LF and CR separate tokens
    everywhere in movetext; there is no line-sensitivity inside movetext. An
    empty document parses as zero tags and zero tokens.
12. **Encoding.** `Str` is a UTF-8 byte buffer and all scanning is byte-wise;
    non-ASCII bytes inside comments or literal text pass through, and a
    non-ASCII byte where a token must start is a stray character.

## 5. SAN acceptance order

`pgn_is_san(s)` (and SAN token validation during parsing) strips at most one
trailing `+` or `#`, then accepts exactly one of:

1. `O-O` or `O-O-O`;
2. a piece move: PIECE, then an optional file, an optional rank (in that
   order -- either, both or neither), an optional `x`, a destination square,
   and end of token. The parser tries the four disambiguation shapes in the
   order "none", "file", "rank", "file+rank", so `Nf3` is destination f3 and
   `Nbd2`/`N1d2`/`Nb1d2` are disambiguated forms;
3. a pawn move: an optional capture (`file "x"`, e.g. `exd5`) or a push
   (`file rank`, e.g. `e4`), followed optionally by `=PROMO`.

Consequences: `e9`, `i4`, `Nf9`, `e4Q`, `OO`, `P`, `Nf3x`, `a8=K`, `e4!`
(rejected -- `!` is not part of a token) and trailing whitespace are all
invalid. There is no board, so `a1=Q`, `Nb1d2` and `Qh5#` are accepted on
syntax alone.

## 6. Error catalog

Every parse failure is `Err(msg)` with a fixed message carrying a byte
position in the parsed input:

| Message | Trigger |
|---|---|
| `pgn: bad tag name at <pos>` | `[` followed by no ALNUM/`_` name byte (`[ "x"]`) |
| `pgn: missing tag value at <pos>` | no whitespace after the name, or no quoted value (`[Event]`, `[Event ]`, `[Event x]`) |
| `pgn: unterminated quote at <pos>` | tag value quote not closed before LF/CR/EOF (pos = opening quote) |
| `pgn: invalid escape at <pos>` | `\` in a value not followed by `"` or `\` (pos = backslash) |
| `pgn: unterminated tag at <pos>` | tag pair not closed by `]` on its line (pos = `[`) |
| `pgn: unterminated comment at <pos>` | `{` without a later `}` (pos = `{`) |
| `pgn: unsupported variation at <pos>` | `(` or `)` in movetext (pos = paren) |
| `pgn: bad nag at <pos>` | `$` not followed by a digit (pos = `$`) |
| `pgn: illegal result token at <pos>` | digit run followed by `-`/`/` that is not one of the four results (`2-0`, `0-0`) |
| `pgn: bad move number at <pos>` | digit run with no dots or with 2/4+ dots, or bare digits (pos = first digit) |
| `pgn: bad move number sequence at <pos>` | first number not `1.`, a `N.` that is not previous+1, or `N...` that does not repeat the previous number |
| `pgn: stray character at <pos>` | a byte that starts no token and is not a SAN-start byte (`@`, `]`, `}`, `i`, `P`, ...) |
| `pgn: illegal san token '<w>' at <pos>` | word starting like SAN that fails section 5 (`e9`, `Nf9`, `e4Q`) |
| `pgn: token after result at <pos>` | any num/san/nag/result token after the result token |

Messages are built as `"pgn: "` + text + `" at "` + decimal position (via
`xiom.convert.int_to_string`) except `illegal san token`, which embeds the
offending word in single quotes. The scanner stops at the first error; partial
tags and tokens are discarded.

## 7. Canonical emit

`pgn_emit(g)` produces:

```
tag-line      = "[" name " " '"' escaped-value '"' "]" LF     ; one line per tag
tag-section   = *( tag-line ) LF                              ; the blank line only when tags exist
movetext      = token *( " " token ) LF                       ; single spaces
              ; a token following a comment_line starts on a new line instead of after a space
whole-output  = tag-section movetext                          ; either part may be empty
```

- Values are re-escaped: `"` -> `\"`, `\` -> `\\`; every other byte is
  emitted verbatim.
- `num` emits its canonical text, `nag` emits `$` + digits, `comment` emits
  `{` + text + `}`, `comment_line` emits `;` + text.
- An empty game emits `""`.
- Because input tokens round-trip (`texts` are preserved verbatim except the
  canonical `num` text and decoded/re-escaped tag values), `pgn_parse` of an
  emitted game yields exactly the same tags and tokens:
  `same_tokens(x, pgn_emit(pgn_parse(x)))` holds for every document this
  codec accepts, while the byte layout is normalized.

## 8. API signatures

```xi
pub fn pgn_parse(text: Str) -> Result[Game, Str]
pub fn pgn_emit(g: &Game) -> Str

pub fn pgn_tag_count(t: &TagList) -> Int
pub fn pgn_tag_name(t: &TagList, i: Int) -> Str        // "" out of range
pub fn pgn_tag_value(t: &TagList, i: Int) -> Str       // "" out of range
pub fn pgn_tag_of(t: &TagList, name: Str) -> Option[Str]

pub fn pgn_move_count(m: &MoveText) -> Int
pub fn pgn_move_kind(m: &MoveText, i: Int) -> Str      // "" out of range
pub fn pgn_move_text(m: &MoveText, i: Int) -> Str      // "" out of range
pub fn pgn_move_start(m: &MoveText, i: Int) -> Int     // -1 out of range
pub fn pgn_result(m: &MoveText) -> Str                 // "" when absent

pub fn pgn_is_san(s: Str) -> Bool
```

Out-of-range accessors return `""`/`-1` (a comment can legitimately have
empty text, so use the kind or the count to tell an empty comment apart from
a missing token). Complexity: `pgn_parse` is O(input length); `pgn_emit` is
O(output length); accessors are O(1) except `pgn_tag_of` and `pgn_result`,
which are O(count).

## 9. Test plan

`tests/test_conformance.xi` (module `pgn_tests`) runs 24 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | full game | 4 tags, 10 tokens, kinds/texts/result (sections 3-4) |
| t2 | tag escapes | `\"`/`\\` decode and re-escape on emit (rule 3, section 7) |
| t3 | duplicate tags | order preserved; `tag_of` exact, first, case-sensitive |
| t4 | brace comments | verbatim multiline text, `{` byte offset (rules 7, 3) |
| t5 | semicolon comments | run to end of line, verbatim leading space, offsets |
| t6 | NAGs | digits only, no `$` in text (rule 8) |
| t7 | attached numbers | `1.e4`, `2...Nc6` tokenize (rule 4) |
| t8 | `%` escapes | skipped in tag and movetext phases (rules 1, 10) |
| t9 | sequence errors | first != 1, jump, `1...` first, wrong ellipsis (rule 5) |
| t10 | ellipsis form | repeats the previous number (rule 5) |
| t11 | SAN acceptance | pieces, disambiguation, captures, promotion, castling, suffixes (section 5) |
| t12 | SAN rejection | bad squares/file, bad promotion, unknown letters (section 5) |
| t13 | comment errors | unterminated `{` position, multiline case (rule 7) |
| t14 | quote errors | unterminated quote (LF and EOF), invalid escape (rule 3) |
| t15 | tag errors | unterminated `]` at EOL/EOF, stray byte before `]` (rule 2) |
| t16 | name/value errors | bad name, missing whitespace, missing quoted value (rule 3) |
| t17 | movetext errors | stray chars, illegal results, bare digits, bare `$` (section 6) |
| t18 | variations | `(` and `)` are documented errors |
| t19 | normalization | emit spacing is canonical; result reparses token-equal (section 7) |
| t20 | emit byte-exact | tags + blank line + movetext + trailing LF; re-escaping |
| t21 | empty/missing result | `""`, `*`, `1. e4` all valid; empty emits `""` (rules 1, 9, 11) |
| t22 | after result | comments allowed; other tokens error (rule 9) |
| t23 | accessors | tag/move/result accessors in and out of range (section 8) |
| t24 | `pgn_is_san` | 14 accepted forms, 11 rejected forms (section 5) |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison). Tests call the check functions directly (`t1()` ...
`t24()`); `Vec[fn]` indexed dispatch is not used.

## 10. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the pure-parser idioms
of `xiom.eml`/`xiom.lexing` and documents these compiler-driven choices:

- Free functions only, no methods on `TagList`/`MoveText`/`Game`.
- No `Vec[StructType]`: token streams are parallel `Vec`s; `Game` nests the
  two plain structs (a proven shape).
- `Ok`/`Err` for `Result[Game, Str]`, `Result[MoveText, Str]` and
  `Result[Int, Str]` are constructed only in the leaf helpers
  `_ok_game`/`_err_game`, `_ok_moves`/`_err_moves`, `_ok_pos`/`_err_pos`.
- `Str` equality between `Vec[Str]` elements goes through
  `xiom.string.compare.str_compare` (BUG 17); every element read binds a
  typed local, and every `Vec[Int]` read binds `let x: Int = v[i];`.
- Strings are materialized from a `Vec[UInt8]` buffer with
  `xiom.string.builder.sb_to_str`; `&mut Vec` arguments are passed with an
  explicit `&mut` at each call site.
- `pgn_parse` owns its scanning loops; `_parse_tag_pair` folds pairs through
  `&mut TagList`, and read-only accessors borrow `&Game` fields only through
  locals (never `&struct.field`).

## 11. Known limitations

- One game per call; multi-game files need caller-side splitting at the
  tag/movetext boundary.
- No variations, no comments nested inside comments, no `%` semantics beyond
  skip-to-end-of-line.
- SAN validation is lexical: piece identity, disambiguation correctness,
  promotion rank, check/mate claims and pawn-capture geometry are not
  checked against a board.
- Castling must use the letter `O`; `0-0` is rejected.
- Move numbers cannot be separated from their dots; suffix symbols like `!`
  and `?` are stray characters and `e.p.` is not accepted -- write NAGs
  instead. At most one `+` or `#` suffix is allowed (`e4++` is rejected).
- Tag values decode only the two PGN escapes; there is no multi-line value
  support and no non-ASCII escape handling.
- `pgn_emit` is canonical, not byte-faithful: original spacing, line breaks
  and NAG placement are normalized; comment text and SAN text are preserved.
- Errors carry one byte position and no line/column information.
