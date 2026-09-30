# xiom.legacy-proto -- specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.legacy_proto` (`src/legacy_proto.xi`). Pure XIOM, no FFI, no I/O.
Tests: `tests/test_conformance.xi` (24 checks).

## 1. Scope and model

A small, dependency-free codec for three legacy internet text protocols:

- **Finger (RFC 1288)** -- query lines and single-line / multi-line
  responses,
- **Gopher (RFC 1436)** -- menu items and whole menu documents,
- **WHOIS (RFC 3912)** -- response records of key-value fields, comments and
  continuations.

Everything is byte-oriented and stateless: every function takes `Str` input
(or a struct produced by a parse function) and returns plain values. There is
no connection object, no configuration and no global state. Malformed input
yields a deterministic `Err` message, never a crash.

Non-goals: networking, sockets, DNS, URL parsing (the `gopher://` URL scheme
of RFC 4266 is out of scope), response-size policy and UTF-8 validation.

## 2. Data model

```xi
pub type FingerQuery = {
  username: Str;   // requested user; "" selects the server default user
  verbose: Bool;   // true when the long "/W" format was requested
}

pub type FingerResponse = {
  lines: Vec[Str];      // content lines, terminators stripped, kept verbatim
  is_multiline: Bool;   // more than one line, or a terminator was present
  had_terminator: Bool; // the response carried a lone "." line
}

pub type GopherItem = {
  item_type: Str;  // one-byte type; "." is the info-text type
  display: Str;    // decoded display text
  selector: Str;   // decoded selector ("" for info text)
  host: Str;       // decoded host ("" for info text)
  port: Int;       // decoded port, 0..65535 (0 for info text)
}

pub type GopherMenu = {
  types: Vec[Str];      // one-byte item types, parallel vectors,
  displays: Vec[Str];   // all of equal length (maintained by the parser)
  selectors: Vec[Str];
  hosts: Vec[Str];
  ports: Vec[Int];
}

pub type WhoisRecord = {
  keys: Vec[Str];                // field keys, wire order, repeats preserved
  values: Vec[Str];              // values, parallel with keys
  continuation_counts: Vec[Int]; // continuation lines per field
  continuations: Vec[Str];       // all continuation lines, wire order:
                                 // the first counts[0] belong to field 0, ...
  comments: Vec[Str];            // "%"/"#" lines, trimmed, marker included
}
```

Invariants: `GopherMenu` vectors are equal length; `WhoisRecord.keys` and
`values` are equal length and `continuations.len()` equals the sum of
`continuation_counts`. `Vec[StructType]` is unsupported in this compiler, so
the menu and record models are flat with parallel vectors (section 11).

## 3. Shared text conventions

1. **Byte model.** `Str` is a byte buffer; the codec never rewrites
   multi-byte sequences, validates UTF-8, or interprets character classes
   beyond the ASCII bytes named below. All lengths are byte lengths.
2. **Line endings.** Where a whole document is split into lines
   (`finger_parse_response`, `gopher_parse_menu`, `whois_parse`), the
   terminators CRLF, LF and CR are all accepted. A trailing terminator does
   not create a phantom empty line; a final unterminated segment is a line.
3. **Single line inputs.** `finger_parse_query` and `gopher_parse_item`
   truncate their input at the first CR or LF and ignore the remainder.
4. **Trimming.** "Trimmed" always means surrounding ASCII space (32) and tab
   (9) bytes only, never CR/LF or other whitespace.
5. **Canonical output.** Render functions always use CRLF and normalize
   non-canonical input (line endings, escaped Gopher fields, Finger
   terminators, WHOIS comment order). Parse/render is byte-exact for
   canonical wire text; the tests pin both directions.

## 4. Finger

### 4.1 Query grammar

```
query = [ user ] [ "/W" ]
user  = 1*( byte except SP / TAB / CR / LF )
```

Parsing decisions (`finger_parse_query`):

1. Truncate at the first CR or LF; surrounding spaces/tabs are stripped.
2. Empty after stripping -> `Err("finger: empty query")`.
3. When the remaining text ends with `/W` or `/w`, `verbose` is true and
   those two bytes are removed (then trailing spaces/tabs are stripped
   again). The suffix is checked case-insensitively; a user name that
   literally ends in `/W` is therefore read as the verbose form (the
   protocol's inherent ambiguity).
4. An interior space or tab in the user name ->
   `Err("finger: whitespace in query")`.
5. An empty user name with `verbose` is legal (`/W` = default user, long
   format); an empty user name without `verbose` is the already-error case
   of step 2.

Canonical render (`finger_render_query`): `username`, plus `/W` when
verbose, plus CRLF. `/W\r\n` for the default-user long format; round-trips
through `finger_parse_query`.

### 4.2 Response grammar

```
response = line *( CRLF line ) [ CRLF "." ] [ CRLF ]
```

Parsing decisions (`finger_parse_response`):

1. Lines are split per section 3.2 and kept verbatim, including empty lines
   and surrounding whitespace.
2. The first line that is exactly `.` (a single byte) ends the response:
   `had_terminator = true`, and the lines after it are ignored.
3. A response with no content line (empty text, or `.\r\n`) is
   `Err("finger: empty response")`. A blank line is an empty content line
   and is legal.
4. `is_multiline = lines.len() > 1 || had_terminator`.

Canonical render (`finger_render_response`): every content line followed by
CRLF, then `.\r\n` when `is_multiline` or `had_terminator` (RFC 1288
requires the terminator for the long format). Examples:

| Input wire | lines | is_multiline | had_terminator | Canonical render |
|---|---|---|---|---|
| `Hello` | `["Hello"]` | false | false | `Hello\r\n` |
| `Hello\r\n` | `["Hello"]` | false | false | `Hello\r\n` |
| `a\nb\rc` | `["a","b","c"]` | true | false | `a\r\nb\r\nc\r\n.\r\n` |
| `first\r\n.\r\nJUNK` | `["first"]` | true | true | `first\r\n.\r\n` |

### 4.3 Accessors

`finger_line_count(r)` is `lines.len()`; `finger_line(r, i)` returns `""`
for a negative or past-the-end index; `finger_is_multiline(r)` returns the
flag.

## 5. Gopher field escaping

RFC 1436 defines no escaping. To make the codec lossless for arbitrary field
bytes, the codec pins this convention for the `display`, `selector` and
`host` fields:

| Wire (two bytes) | Decoded (one byte) |
|---|---|
| backslash + `t` | TAB (9) |
| backslash + `n` | LF (10) |
| backslash + `r` | CR (13) |
| backslash + backslash | backslash (92) |

- Any other escape (`\x` with a different `x`, including a digit or an
  uppercase letter) keeps **both** bytes verbatim; the backslash is not
  dropped.
- A lone trailing backslash is kept verbatim.
- Encoding maps TAB -> `\t`, LF -> `\n`, CR -> `\r`, backslash -> `\\` and
  passes every other byte through.

Consequences: raw TAB/CR/LF can never occur in a decoded field (TAB is the
field separator, CR/LF end lines), so the escape set is exactly what
losslessness needs. A wire field that contains a bare backslash decodes
verbatim; canonical rendering then doubles it, i.e. render canonicalizes
rather than reproducing noncanonical wires byte-for-byte.

## 6. Gopher items and menus

### 6.1 Item grammar

```
item = info / entry
info = "." display
entry = type display TAB selector TAB host TAB port
type = %x21-7E                     ; exactly one printable non-tab byte
display = *( byte except TAB / CR / LF ), with section 5 escapes
selector = same
host = same
port = 1*5( DIGIT )                ; numeric value 0..65535
```

Parsing decisions (`gopher_parse_item`):

1. The input is truncated at the first CR or LF.
2. Empty -> `Err("gopher: empty line")`.
3. A first byte of `.` makes it an info-text line: `item_type = "."`,
   `display` is the decoded remainder of the line, `selector = ""`,
   `host = ""`, `port = 0`. (A line starting with `.` is always info text;
   tabs in it stay part of the display and are escaped on render.)
4. Otherwise the number of TAB bytes is counted: fewer than three ->
   `Err("gopher: missing fields")`; more than three ->
   `Err("gopher: too many fields")`.
5. The item type is the first byte; it must be printable 33..126, else
   `Err("gopher: invalid item type")`.
6. Fields: `display` = bytes 1..first TAB, `selector` = first..second,
   `host` = second..third, `port` = after the third; all three text fields
   are decoded per section 5. Empty display/selector/host are legal.
7. The port must be 1..5 ASCII digits with numeric value 0..65535
   (leading zeros allowed), else `Err("gopher: invalid port")`.

Canonical render (`gopher_render_item`): info text renders as `.` + escaped
display + CRLF; an entry renders as type + escaped display + TAB + escaped
selector + TAB + escaped host + TAB + decimal port + CRLF. Leading zeros
are canonicalized away (`0070` -> `70`).

### 6.2 Menu grammar and decisions

A menu is one or more item lines (section 6.1) in order; lines are split per
section 3.2. Blank lines are **not** separators: an empty line is the
`empty line` error.

Parsing decisions (`gopher_parse_menu`):

1. No lines at all -> `Err("gopher: empty menu")`.
2. Every line must pass the item checks; the first failure is
   `Err("gopher: line N: <reason>")` where `N` is 1-based and `<reason>` is
   the bare `gopher_parse_item` reason (`empty line`, `missing fields`,
   `too many fields`, `invalid item type`, `invalid port`).
3. Items are stored in the five parallel vectors in document order.

Canonical render (`gopher_render_menu`): every item rendered by
`gopher_render_item`, concatenated (each line carries its own CRLF).
Parsing the rendered document yields the same menu; for canonical input the
render is byte-exact.

### 6.3 Accessors

`gopher_item_count`, `gopher_item_type`, `gopher_item_display`,
`gopher_item_selector`, `gopher_item_host`, `gopher_item_port`,
`gopher_item_is_text`. Str accessors return `""` and `gopher_item_port`
returns `-1` for a negative or past-the-end index;
`gopher_item_is_text` is true exactly when the type is one byte `.`.

## 7. WHOIS

### 7.1 Record grammar

```
record = *( blank / comment / field / continuation )
blank = *( SP / TAB )
comment = ( SP / TAB )* ( "%" / "#" ) *( byte except CR / LF )
field = key ":" value
key = trimmed text before the first ":"        ; must be non-empty
value = trimmed text after the first ":"       ; may be empty
continuation = a non-blank line without ":"
```

Parsing decisions (`whois_parse`):

1. Lines are split per section 3.2.
2. Blank lines (only spaces/tabs) are skipped entirely; they are not stored
   and do not break continuation attachment.
3. A line whose first non-space/tab byte is `%` or `#` is a comment: stored
   in `comments` trimmed of surrounding spaces/tabs, with its marker.
4. Otherwise, if the line holds a `:`, the first colon splits it: key and
   value are trimmed of surrounding spaces/tabs. An empty key (`: x`,
   `   :x`) is `Err("whois: empty key")`. An empty value is legal; colons
   after the first stay in the value (`URL: http://x` -> value
   `http://x`). Repeated keys are preserved in wire order.
5. Otherwise the line is a continuation of the most recent field: the
   field's `continuation_counts` entry is incremented and the trimmed line
   is appended to `continuations`. A continuation before any field is
   `Err("whois: continuation before any field")`.
6. A response that yields no field and no comment (empty text, or only
   blank lines) is `Err("whois: empty response")`. A comment-only response
   is legal.

### 7.2 Continuation addressing

`whois_continuation(r, i, j)` addresses the `j`-th continuation of field
`i` through the prefix sum of `continuation_counts[0..i-1]`; out-of-range
`i` or `j` returns `""`. This keeps the flat `continuations` vector
addressable without `Vec[StructType]`.

### 7.3 Canonical render

`whois_render(r)` emits: every comment (verbatim, marker included) followed
by CRLF, then every field in wire order as `key: value` (or `key:` when the
value is empty) followed by CRLF and its continuation lines. Canonical
order is comments first, then fields; re-parsing the rendered record yields
the same field/comment/continuation structure (the tests pin this for a
record that already has that order and for one with a trailing comment).

### 7.4 Accessors

`whois_field_count`, `whois_key`, `whois_value`, `whois_continuation_count`,
`whois_continuation`, `whois_comment_count`, `whois_comment`,
`whois_count(r, key)` and `whois_field(r, key)`. Str accessors return `""`
and count accessors return `0` for out-of-range indices. `whois_count` and
`whois_field` compare keys byte-exactly (case-sensitive) through
`xiom.string.compare.str_compare`; `whois_field` returns the final
occurrence, as registry output supersedes earlier values.

## 8. API contract

```xi
pub const FINGER_PORT_DEFAULT: Int = 79
pub const GOPHER_PORT_DEFAULT: Int = 70
pub const WHOIS_PORT_DEFAULT: Int = 43

pub fn finger_parse_query(query: Str) -> Result[FingerQuery, Str]
pub fn finger_render_query(q: &FingerQuery) -> Str
pub fn finger_parse_response(text: Str) -> Result[FingerResponse, Str]
pub fn finger_render_response(r: &FingerResponse) -> Str
pub fn finger_is_multiline(r: &FingerResponse) -> Bool
pub fn finger_line_count(r: &FingerResponse) -> Int
pub fn finger_line(r: &FingerResponse, i: Int) -> Str

pub fn gopher_parse_item(line: Str) -> Result[GopherItem, Str]
pub fn gopher_render_item(item: &GopherItem) -> Str
pub fn gopher_parse_menu(text: Str) -> Result[GopherMenu, Str]
pub fn gopher_render_menu(m: &GopherMenu) -> Str
pub fn gopher_item_count(m: &GopherMenu) -> Int
pub fn gopher_item_type(m: &GopherMenu, i: Int) -> Str
pub fn gopher_item_display(m: &GopherMenu, i: Int) -> Str
pub fn gopher_item_selector(m: &GopherMenu, i: Int) -> Str
pub fn gopher_item_host(m: &GopherMenu, i: Int) -> Str
pub fn gopher_item_port(m: &GopherMenu, i: Int) -> Int
pub fn gopher_item_is_text(m: &GopherMenu, i: Int) -> Bool

pub fn whois_parse(text: Str) -> Result[WhoisRecord, Str]
pub fn whois_render(r: &WhoisRecord) -> Str
pub fn whois_field_count(r: &WhoisRecord) -> Int
pub fn whois_key(r: &WhoisRecord, i: Int) -> Str
pub fn whois_value(r: &WhoisRecord, i: Int) -> Str
pub fn whois_continuation_count(r: &WhoisRecord, i: Int) -> Int
pub fn whois_continuation(r: &WhoisRecord, i: Int, j: Int) -> Str
pub fn whois_comment_count(r: &WhoisRecord) -> Int
pub fn whois_comment(r: &WhoisRecord, i: Int) -> Str
pub fn whois_count(r: &WhoisRecord, key: Str) -> Int
pub fn whois_field(r: &WhoisRecord, key: Str) -> Option[Str]
```

The render functions are total for values produced by the parse functions;
a hand-constructed value is the caller's responsibility (e.g. menu vectors
must be parallel). Complexities: every parse is O(len(text)); lookups are
O(field count); `whois_continuation` is O(i); accessors are O(1).

## 9. Error catalog

All failures are `Err(msg)` with a deterministic message.

| Message | Function | Trigger |
|---|---|---|
| `finger: empty query` | `finger_parse_query` | no non-space byte after CR/LF truncation and trimming |
| `finger: whitespace in query` | `finger_parse_query` | interior space/tab in the user name |
| `finger: empty response` | `finger_parse_response` | no content line before the (optional) `.` terminator |
| `gopher: empty line` | `gopher_parse_item` | empty line (also as the menu reason) |
| `gopher: missing fields` | `gopher_parse_item` | fewer than three TAB bytes |
| `gopher: too many fields` | `gopher_parse_item` | more than three TAB bytes |
| `gopher: invalid item type` | `gopher_parse_item` | the first byte is not printable 33..126 |
| `gopher: invalid port` | `gopher_parse_item` | port is not 1..5 digits or exceeds 65535 |
| `gopher: empty menu` | `gopher_parse_menu` | the document holds no line |
| `gopher: line N: <reason>` | `gopher_parse_menu` | first malformed line; N is 1-based |
| `whois: empty response` | `whois_parse` | no field and no comment in the whole response |
| `whois: empty key` | `whois_parse` | the text before the first colon trims to empty |
| `whois: continuation before any field` | `whois_parse` | a non-field line before the first field |

Parse never fails on field content: any printable/opaque bytes in display,
selector, host, key or value are accepted verbatim (no length limits).

## 10. Test matrix (`tests/test_conformance.xi`, 24 checks)

| # | Check | Semantics pinned |
|---|---|---|
| t1 | finger query basics | `user`, `user/W`, `user/w`, `/W`, surrounding spaces, CRLF truncation; `FINGER_PORT_DEFAULT` |
| t2 | finger query errors | empty/blank/CRLF query, interior space and tab |
| t3 | finger query render | canonical `ghost\r\n`, `ghost/W\r\n`, `/W\r\n`; parse/render round-trip |
| t4 | single-line response | with and without CRLF; flags false; canonical CRLF |
| t5 | multi-line response | three lines + `.` terminator; flags; byte-exact render |
| t6 | line endings | LF and CR splits, unterminated tail, empty line preserved, canonical terminator |
| t7 | terminator semantics | `first\r\n.\r\nJUNK` -> one line, junk ignored |
| t8 | response errors | empty text and `.\r\n` error; blank line is a legal empty content line; accessor bounds |
| t9 | gopher item | `1Floodgap Gopher\t/\tfloodgap.com\t70`; render byte-exact; `GOPHER_PORT_DEFAULT` |
| t10 | gopher info text | `.` lines, empty selector, `i` type with empty selector |
| t11 | gopher escaping | all four escapes round-trip; unknown escape and trailing backslash kept then canonicalized |
| t12 | gopher ports | 0, `0070` -> 70, 65535; 65536, `12x`, empty, 6 digits rejected |
| t13 | gopher malformed lines | empty line, missing/too many fields, invalid type (space, non-ASCII byte), valid three-tab item |
| t14 | gopher menu | three-item mixed-ending menu; accessors; canonical CRLF render |
| t15 | gopher menu errors | empty menu, blank first line, bad port on line 2, too many fields on line 2 |
| t16 | gopher round-trip | canonical menu byte-exact; re-parse equality |
| t17 | whois basics | two fields, keys/values, zero comments/continuations; `WHOIS_PORT_DEFAULT` |
| t18 | whois comments | `%` and `#` stored trimmed, blank line skipped, accessor bounds |
| t19 | whois continuations | two continuations attached to field 0, none to field 1, bounds |
| t20 | whois repeated keys | count 2, `whois_field` last wins, absent key `None`/0, bounds |
| t21 | whois values | colon in value keeps the rest, empty value |
| t22 | whois canonical render | comments first, trimmed continuation; re-parse equality; trailing comment moves first |
| t23 | whois errors | empty/blank response, empty key, orphan continuation |
| t24 | whois realistic record | 7 fields, 2 comments, repeated nameservers, `>>>` line parsed as a field; render/re-parse equality |

Element comparisons in the suite go through `xiom.string.compare.str_compare`
(never `==`), and the harness calls `t1()` ... `t24()` directly (no
`Vec[fn]` dispatch).

## 11. Compiler / stdlib notes (XIOM v0.62.2)

- Free functions only: no self methods, no lambdas, no `Vec[StructType]`,
  no `Vec[Float64]`, no `Vec[fn]` indexed dispatch.
- `Str` values are never compared with `==` when read from a `Vec[Str]`
  element; `whois_count`/`whois_field` use `str_compare`, and every `Vec`
  element read is bound with a typed `let` first.
- `byte_at` results are compared directly against `UInt8` constants and
  widened with `(b as Int) & 0xFF` only for arithmetic.
- `Ok`/`Err` for the struct payloads (`FingerQuery`, `FingerResponse`,
  `GopherItem`, `GopherMenu`, `WhoisRecord`) are constructed only in the
  tiny `_ok_*`/`_err_*` leaf helpers below.
- No builder materializes output; strings are assembled with `+` and
  decimal ports/line numbers use `xiom.convert.int_to_string`, never
  `sb_push_int`.
- `&struct.field` is never passed as a `&Vec[...]` argument; fields are
  bound to locals first.
- Every loop makes progress: each body increments its cursor or returns, so
  the suite terminates in well under a second.

## 12. Hand-rolled helpers (stdlib gaps)

Shared internal helpers, each because the stdlib offered a different
semantic or an incompatible shape:

- `_split_lines` -- `xiom.string.lines` splits on LF only (leaves the CR)
  and always returns at least one part.
- `_parse_port` -- `xiom.convert.parse.parse_int` accepts a leading
  `+`/`-` and arbitrary magnitude; the wire needs strict unsigned digits
  within 0..65535.
- `_escape_field` / `_unescape_field` -- the codec-specific Gopher
  convention (section 5); `xiom.string.escape` uses an unrelated alphabet.
- `_ltrim_start` / `_rtrim_end` / `_trimmed` / `_is_blank_range` /
  `_is_blank` / `_has_ws` -- index-level trimming is needed to segment and
  store fields; `xiom.string.str_trim` trims a wider character set and
  returns a new `Str`.
- `_find_byte`, `_line_end`, `_is_dot`, `_is_ws_byte` -- byte-level
  primitives over `byte_at`.

## 13. Non-goals and limitations

- **No networking:** sockets, DNS, query execution and timeouts are the
  caller's job. The codecs only parse and build text.
- **Canonicalization, not byte preservation:** parse/render is byte-exact
  for canonical wire text; non-canonical input is normalized as described
  in sections 3.5, 4.2, 5 and 7.3.
- **Gopher escaping is a codec extension:** real servers do not escape, so
  a literal `\t`/`\n`/`\r`/`\\` sequence in a real display is decoded; the
  convention is documented and pinned by t11.
- **Byte-oriented:** no UTF-8 validation or normalization; `Str` is a
  NUL-terminated buffer, so embedded NUL bytes cannot occur in practice and
  are not part of the model.
- **No size policy:** line lengths, menu sizes and record sizes are not
  checked or capped.
- **Lenient structure, strict errors:** CRLF/LF/CR are accepted everywhere
  and a final unterminated line is legal, but field-level violations
  produce the exact messages of section 9.
