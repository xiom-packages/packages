# xiom.mbox -- Specification

## 1. Scope

`xiom.mbox` is a pure-XIOM, in-memory codec for mbox mailboxes (the
`From `-line separated family, RFC 4155 style). It provides:

- separation of a mailbox into messages on `From ` delimiter lines;
- flat storage: one shared, verbatim `Str` pool plus per-message byte ranges
  (`Int` offsets), never `Vec[StructType]`;
- envelope accessors that keep the address and date as raw text;
- body accessors: offset, length, raw slice, and decoded materialization into
  a caller-supplied buffer;
- header/body separator detection inside a message;
- a canonical emitter that writes `From ` envelope lines, re-quotes body
  lines for the pinned mboxrd stance, and separates messages with one blank
  line.

No file I/O: `mbox_parse` takes a `Str`, `mbox_emit` returns a `Str`.

## 2. Non-goals

- No RFC 5322 header parsing, unfolding, or address/date interpretation
  (sibling package `xiom.eml` parses message structure).
- No mboxcl / mboxcl2 / mboxo variants, no `Content-Length:` handling.
- No file reading/writing, no streaming, no incremental parsing.
- No transfer decoding; message content is bytes in, bytes out.

## 3. Mailbox grammar and separation rules

```
mailbox      = [ message *( blank-line message ) ]         ; empty pool is Ok
message      = from-line LF message-body
from-line    = "From " envelope-text                       ; 5 fixed bytes + text
envelope-text= *( byte except LF / CR-of-CRLF )
message-body = *( byte )                                    ; to the next delimiter
delimiter    = from-line at pool offset 0 or after an empty line
line-term    = LF | CRLF
```

Rules, precisely:

1. **Empty pool**: `""` parses as `Ok` with zero messages (not an error).
2. **Leading text**: a non-empty pool whose first line does not begin with
   the five bytes `From ` (including a leading empty line, leading spaces,
   `From` without a space, `From\t`) is `Err("mbox: leading text before
   first From line")`.
3. **Delimiter position**: the first line of the pool always opens the first
   message. Any later line beginning with `From ` opens a new message **iff**
   the physical line immediately before it is empty; otherwise that line is
   ordinary body content.
4. **Line terminators**: LF and CRLF terminate lines. The CR of a CRLF pair
   is not part of the line content. A **bare CR** (not followed by LF) is an
   ordinary data byte; it never terminates a line and never participates in
   the empty-line test.
5. **Body span**: message `i`'s body is `pool[body_start[i], body_end[i])`,
   where `body_start` is the byte after the envelope line's terminator and
   `body_end` is the start (`F`) of the next delimiter, or `pool.len()` for
   the final message. The empty line that precedes a delimiter is therefore
   part of the preceding body span.
6. **Final message**: the last message may be unterminated (no trailing
   terminator); its body runs to the end of the pool. This is accepted and
   documented, not an error.
7. **`From`-looking lines**: a line beginning `From ` that does not satisfy
   rule 3, and every line beginning `From` or `From` + non-space, is body
   content and is preserved.

## 4. mboxrd quoting stance (pinned)

The codec pins the mboxrd stance:

- **Parse / pool**: bytes are stored verbatim. `mbox_body_raw` returns them
  exactly, quoted lines included (`>From `, `>>From `, ...).
- **Decode**: `mbox_body_into` removes exactly one `>` from every body line
  matching `>+From ` (one or more `>` followed by `From `); all other bytes,
  including the raw LF/CRLF terminators, are copied verbatim.
- **Emit**: `mbox_emit` re-quotes: a body line whose content starts with
  `From ` gains one leading `>`. A line already starting with `>` is written
  verbatim (it is not double-quoted). Consequently `parse` / `emit` / `parse`
  is stable for decoded bodies, and canonical input round-trips
  byte-for-byte.
- `mbox_body_into` decoding is the only place quoting is removed; the pool
  and all offset accessors always address the original bytes.

## 5. Data model and byte ranges

```xi
pub type Mailbox = {
  pool: Str;              // whole input, verbatim
  env_start: Vec[Int];    // 'F' of the "From " line
  env_end: Vec[Int];      // first terminator byte of the envelope line
  body_start: Vec[Int];   // first byte after that terminator
  body_end: Vec[Int];     // next delimiter start, or pool.len() at the end
}
```

Invariants for a parsed mailbox (`n = pool.len()`):

```
count = env_start.len() = env_end.len() = body_start.len() = body_end.len()
0 <= env_start[i] < env_end[i] <= body_start[i] <= body_end[i] <= n
pool[env_start[i], env_start[i]+5) = "From "
```

Accessors are total and defensive: an out-of-range index, or a hand-built
`Mailbox` whose four vectors are not aligned or whose spans leave the pool,
yields `""` (Str accessors), `-1` (offset accessors), or `0` (`mbox_count`
uses the smallest vector length; `mbox_body_len` and `mbox_body_into` return
`0`). No accessor panics.

## 6. Envelope and header-separator accessors

- `mbox_envelope_line(m, i)` is `pool[env_start[i], env_end[i])`, e.g.
  `From alice@example.com Mon Jan  1 00:00:00 2024` (no terminator).
- `mbox_envelope_address(m, i)` is the first maximal run of non-space,
  non-tab bytes after `From `, raw; `""` when there is no token.
- `mbox_envelope_date(m, i)` is the raw text after the address token and the
  whitespace run that follows it, with trailing spaces/tabs removed; `""`
  when there is none. No date interpretation.
- `mbox_header_separator(m, i)` scans the body span line by line and returns
  the pool offset of the first empty line (the RFC 5322 header/body
  separator), or `-1` when the span has no empty line. An empty line is a
  line whose content between its start and its terminator is zero bytes; CRLF
  counts as one empty line. For a message with no headers the separator is
  the body offset itself.
- `mbox_header_body_start(m, i)` returns the offset after that separator
  line's terminator, or `-1`. It may equal `body_offset + body_len` when the
  message has headers but no body after the blank line.

## 7. Canonical emitter

`mbox_emit(m, eol)` writes, for each message `i` in order:

1. the envelope line bytes verbatim (no `From ` reconstruction);
2. `eol`;
3. the body, line by line: a line whose content starts with `From ` is
   prefixed with one `>`; every line terminator is rewritten as `eol`; a
   final unterminated line is written without a terminator;
4. for every message except the last: the parsed body already ends with the
   separating empty line (rule 5), so nothing more is written there; if a
   hand-built mailbox has a non-last body that is empty or not
   terminator-terminated, the emitter appends the minimum `eol` bytes needed
   to produce exactly one empty line before the next envelope line;
5. for the last message: nothing is appended, so an unterminated final
   message stays unterminated.

Exact shape of canonical output (LF example, two messages):

```
From alice@example.com Mon Jan  1 00:00:00 2024\n
Header: v\n
\n
body line\n
\n
From bob@example.com Tue Jan  2 00:00:00 2024\n
Header: w\n
\n
other body\n
```

`eol` is written literally; callers pass `"\n"` or `"\r\n"`. Canonical
(already-LF or already-CRLF) mailboxes round-trip byte-for-byte, and
`emit(parse(emit(parse(x)))) = emit(parse(x))` for every accepted `x`
(decoded bodies are stable and emit is idempotent).

## 8. API signatures

```xi
pub fn mbox_parse(text: Str) -> Result[Mailbox, Str]
pub fn mbox_count(m: &Mailbox) -> Int
pub fn mbox_envelope_line(m: &Mailbox, i: Int) -> Str
pub fn mbox_envelope_address(m: &Mailbox, i: Int) -> Str
pub fn mbox_envelope_date(m: &Mailbox, i: Int) -> Str
pub fn mbox_body_offset(m: &Mailbox, i: Int) -> Int
pub fn mbox_body_len(m: &Mailbox, i: Int) -> Int
pub fn mbox_body_raw(m: &Mailbox, i: Int) -> Str
pub fn mbox_body_into(m: &Mailbox, i: Int, out: &mut Vec[UInt8]) -> Int
pub fn mbox_header_separator(m: &Mailbox, i: Int) -> Int
pub fn mbox_header_body_start(m: &Mailbox, i: Int) -> Int
pub fn mbox_emit(m: &Mailbox, eol: Str) -> Str
```

`mbox_body_into` appends to `out` (it does not clear it) and returns the
number of bytes appended. All other functions are read-only.

## 9. Error catalog

| Input | Result |
|---|---|
| Empty pool `""` | `Ok`, `mbox_count == 0` (documented empty mailbox) |
| Pool not starting with `From ` | `Err("mbox: leading text before first From line")` |
| Final message without trailing terminator | `Ok` (documented as accepted; body runs to the pool end) |
| Bare CR inside a line | `Ok` (documented: data byte, not a terminator) |
| `From ` line not at offset 0 and not after an empty line | `Ok` (documented: body content) |
| Line beginning `From`, `From\t`, `Fromx` | never a delimiter |
| Out-of-range accessor index | documented empty value (`""`, `-1`, `0`), no panic |

The catalog has exactly one `Err` case; every other condition is a
documented `Ok` with fixed semantics.

## 10. Test plan

`tests/test_conformance.xi` -- 18 checks, all pinned to this document:

| # | Check |
|---|---|
| 1 | empty mailbox Ok/count 0; leading text (text, blank line, space, `From`, `From\t`) is Err |
| 2 | single LF message: envelope line/address/date, body offset/length, raw body, separator, body start |
| 3 | two LF messages: aligned byte ranges, per-message spans, last span ends at pool end |
| 4 | CRLF message: terminators stripped from spans, byte-exact CRLF emit |
| 5 | canonical LF mailbox round-trips byte-for-byte through emit |
| 6 | canonical CRLF mailbox round-trips with CRLF and normalizes to LF |
| 7 | `From ` line not after a blank line is content and is re-quoted on emit |
| 8 | `From ` after an empty line opens a message; extra blank lines are preserved |
| 9 | mboxrd: raw keeps `>` quotes, `body_into` unquotes one `>`, emit re-quotes exactly |
| 10 | unterminated final message accepted, spans to pool end, emitted as parsed |
| 11 | envelope raw text: empty envelope, address only, space and tab separated date |
| 12 | header separator: present, absent (`-1`), immediately empty body, headers-only |
| 13 | bare CR is data, not a terminator |
| 14 | canonical emit writes exactly one blank line between messages |
| 15 | `body_into` appends into caller's buffer; invalid indices are inert |
| 16 | mixed line endings parse; emitter normalizes to the requested eol |
| 17 | decoded round-trip parse/emit/parse is stable; emit is idempotent |
| 18 | body spans end at the next delimiter; the final one at the pool end |

## 11. Compiler / stdlib notes

Guards for XIOM v0.61.3 honored by this package:

- Free functions only; no `Vec[StructType]`, no generics here.
- `Ok`/`Err` for `Result[Mailbox, Str]` are built only in the leaf helpers
  `_ok_mailbox` / `_err_mailbox`.
- All `Vec[Int]` reads are bound to typed locals (`let es: Int = ...`)
  before use.
- Str equality in tests goes through `xiom.string.compare.str_compare`
  (BUG 17); byte comparisons use `xiom.string.byte_at` against `UInt8`
  constants.
- Emitted bytes go through `xiom.string.builder.sb_push_str` /
  `sb_to_str`.
- No NUL bytes are constructed; no parallel-Vec drift (the four ranges are
  pushed in lockstep in `mbox_parse`).

## 12. Known limitations

- mboxrd only; already-quoted lines are preserved as-is on emit, so
  mboxo-style unquoted `From ` content is canonicalized (quoted) on the first
  emit.
- No header parsing, no date parsing, no `Content-Length:` stripping, no
  status/`X-Status` handling.
- `mbox_body_into` is the only decoded view; all offsets address the raw
  pool, so callers that need decoded offsets must materialize.
- The emitter rewrites all terminators to `eol`, which normalizes mixed
  endings (documented canonicalization).
