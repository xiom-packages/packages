# xiom.pop3 -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.pop3` (`src/pop3.xi`). Pure XIOM, no FFI, no file or socket I/O.

This document is the normative description of the `xiom.pop3` codec: the
data model, the command and response grammars, the byte-stuffing rules, the
listing pair columns, the error catalog and the test plan. Reference: RFC
1939 (Post Office Protocol - Version 3), the only POP3 revision modelled.

## 1. Scope

`xiom.pop3` is an in-memory codec for the twelve RFC 1939 commands and for
server responses:

- commands: `USER name`, `PASS string`, `STAT`, `LIST [msg]`, `UIDL [msg]`,
  `RETR msg`, `DELE msg`, `NOOP`, `RSET`, `QUIT`, `TOP msg n`,
  `APOP name digest`;
- responses: single-line `+OK [text]` / `-ERR text`, and multi-line
  responses (`LIST`/`UIDL` without an argument, `RETR`, `TOP`) with the
  `"."` terminator and RFC 1939 byte-stuffing;
- LIST/UIDL entries materialized into two flat parallel columns (message
  number, value) for direct lookup by message number.

The module does **not** include sockets, TLS/STLS, a session state machine,
MD5 computation (the APOP digest is an opaque 32-hex-character string passed
in by the caller), authentication policy, or any POP3 extension command
(`CAPA`, `AUTH`, `STLS`, `PIPELINING`, ...). It is a codec, not a client or
server.

## 2. Constants

| Name | Value | Meaning |
|---|---|---|
| `POP3_USER` | 1 | `Pop3Request.kind` for `USER` |
| `POP3_PASS` | 2 | `PASS` |
| `POP3_STAT` | 3 | `STAT` |
| `POP3_LIST` | 4 | `LIST`; also a `pop3_parse_listing` kind |
| `POP3_UIDL` | 5 | `UIDL`; also a `pop3_parse_listing` kind |
| `POP3_RETR` | 6 | `RETR` |
| `POP3_DELE` | 7 | `DELE` |
| `POP3_NOOP` | 8 | `NOOP` |
| `POP3_RSET` | 9 | `RSET` |
| `POP3_QUIT` | 10 | `QUIT` |
| `POP3_TOP` | 11 | `TOP` |
| `POP3_APOP` | 12 | `APOP` |
| `POP3_MAX_NUM` | 2147483647 | largest numeric argument / listing value (2^31-1) |
| `POP3_MAX_LINE` | 510 | maximum line content in bytes, excluding CRLF |
| `POP3_MAX_NAME` | 40 | maximum USER / APOP name length in bytes |
| `POP3_UID_MIN` | 1 | minimum unique-id length in bytes |
| `POP3_UID_MAX` | 70 | maximum unique-id length in bytes |

`POP3_MAX_LINE` is the codec's line-content cap. With the CRLF a wire line is
at most 512 bytes, RFC 1939's response-line limit (section 3 of the RFC);
the cap is applied to commands, status lines and payload lines alike.

## 3. Data model

```xi
pub type Pop3Request = {
  kind: Int;    // POP3_USER..POP3_APOP
  text: Str;    // USER name / PASS string / APOP name, "" otherwise
  digest: Str;  // APOP digest, lowercase 32-hex, "" otherwise
  msg: Int;     // message number, -1 when absent
  n: Int;       // TOP line count, -1 when absent
}

pub type Pop3Response = {
  ok: Bool;            // true = +OK, false = -ERR
  multiline: Bool;     // true when a payload section was/has to be emitted
  text: Str;           // status text after the separator space, may be ""
  lines: Vec[Str];     // payload lines, dot-unstuffed, in order
  pair_nums: Vec[Int]; // LIST/UIDL message numbers
  pair_vals: Vec[Str]; // LIST sizes text / UIDL unique-ids, index-aligned
}
```

Invariants:

1. `Pop3Request.msg` is -1 for every kind that takes no message number, and
   `n` is -1 for every kind other than `TOP`. A parsed absent `LIST`/`UIDL`
   argument is `msg == -1`; `TOP` accepts `n == 0` because the RFC's line
   count is non-negative (`msg >= 1` always).
2. `pair_nums.len() == pair_vals.len()` always. After `pop3_parse_listing`
   every payload line produced one pair in the same order, so pair index `i`
   also addresses `lines[i]`; a generic `pop3_parse_response` leaves both
   columns empty.
3. `multiline` is true exactly when the response carried (or must emit) a
   status line plus a payload section terminated by `"."`; it is false for
   every `-ERR` and for every single-line `+OK`. A multi-line response may
   have zero payload lines (`+OK\r\n.\r\n`).
4. `text` never contains control bytes or non-ASCII bytes; payload lines may
   contain 8-bit bytes but never CR or LF.

`Vec[StructType]` is unsupported in this compiler, so a response is one flat
record with parallel `Vec`s instead of a list of per-line structs, and a
listing lookup is a linear scan over `pair_nums`.

## 4. Command grammar and rules

```
command  = keyword [ SP argument ] [ CRLF ]
keyword  = "USER" / "PASS" / "STAT" / "LIST" / "UIDL" / "RETR"
         / "DELE" / "NOOP" / "RSET" / "QUIT" / "TOP" / "APOP"    ; case-insensitive
```

`pop3_parse_request` accepts the line with or without its CRLF; every
decision below is pinned by the conformance suite.

1. **Terminator.** Only one exact trailing two-byte CRLF is stripped. A lone
   trailing CR or LF is *not* a terminator, stays in the content and fails
   the printable-byte rule (section 4.3). An empty line and a CRLF-only line
   are rejected as empty commands.
2. **Keywords.** Matched case-insensitively (ASCII only), 3 or 4 bytes, at
   full length: `USERX`, `TO`, `LISTING` and any unmodelled command are
   `pop3: bad argument: unknown command`. `pop3_build_request` always emits
   the canonical uppercase keyword.
3. **Printable content.** Every byte of the content (line minus terminator)
   must be in `0x20..0x7E`; any other byte -- tab, DEL, 8-bit, NUL, CR, LF
   -- is `pop3: control byte in command line`.
4. **Line cap.** Content longer than `POP3_MAX_LINE` (510) bytes is
   `pop3: line too long`.
5. **Keyword/argument split.** The first space separates the keyword from
   the rest; the canonical form uses exactly one space. A no-argument
   command tolerates one trailing space (`STAT ` parses) but rejects any
   non-empty rest (`STAT x`, `STAT  `) as an unexpected argument.
6. **Numeric arguments.** Message numbers, TOP line counts and LIST sizes
   are canonical decimal: 1..10 ASCII digits, no leading zero (`0` alone is
   allowed where the minimum is 0), value in the inclusive range
   `[minimum, POP3_MAX_NUM]`. `007`, `+1`, `-1`, `1a`, `2147483648` and
   `99999999999` are all rejected.
7. **Argument shapes.**

   | Command | Shape |
   |---|---|
   | `USER` | one token, 1..40 bytes, no space |
   | `PASS` | the rest of the line verbatim (embedded spaces are part of the password), 1..510 bytes |
   | `STAT`, `NOOP`, `RSET`, `QUIT` | no argument |
   | `LIST`, `UIDL` | optional message number `1..POP3_MAX_NUM` |
   | `RETR`, `DELE` | required message number `1..POP3_MAX_NUM` |
   | `TOP` | `msg` `SP` `n`, both required; `msg >= 1`, `n >= 0` |
   | `APOP` | `name` `SP` `digest`: `name` as in `USER`, `digest` exactly 32 hex digits, either case |

8. **APOP digest.** 32 ASCII hex digits, upper or lower case on parse;
   it is stored and emitted lowercased (`C4C9..FB` -> `c4c9..fb`). No MD5 is
   computed or verified.
9. **Canonical emission.** `pop3_build_request` emits the uppercase keyword,
   single separating spaces, canonical decimal numbers (no leading zero),
   the lowercased digest and a trailing CRLF. Fields not used by the kind
   are ignored; a kind whose used fields violate their shape is
   `pop3: bad argument: ...`, and content above the cap is
   `pop3: line too long`.
10. **Round-trips.** For every kind, `parse(build(req)) -> build` is
    byte-identical to `build(req)`, and parsing a non-canonical-but-legal
    line (lowercase keyword, one extra space before a `PASS` string,
    uppercase digest) then re-building yields the canonical line.

## 5. Response grammar and rules

```
response = status [ SP text ] CRLF [ payload "." CRLF ]
status   = "+OK" / "-ERR"                  ; uppercase only
text     = * ( 0x20..0x7E )                ; may be empty
payload  = *( line CRLF )
line     = * octet-not-CR-LF               ; may be empty; CRLF-terminated
terminator = "." CRLF                      ; a bare "." line
```

`pop3_parse_response(multiline, text)` parses exactly one complete response,
end to end.

1. **Marker.** The status marker is exactly the uppercase 3-byte `+OK` or
   4-byte `-ERR`, followed by either the CRLF or one space and the text.
   Anything else (`+ok`, `-ERRx`, `+OKAY`, a leading byte, empty input) is
   `pop3: bad status marker`. Exactly one space is the separator; the text
   is the verbatim remainder, so it may itself contain spaces, and a status
   line written with a trailing space and no text normalizes to a bare
   marker on re-emit.
2. **Text.** The status text must be printable ASCII (0x20..0x7E); DEL,
   control bytes and 8-bit bytes are `pop3: control byte in response text`.
3. **CRLF.** Every line must be CRLF-terminated; an unfinished last line or
   a status line that never reaches its CRLF is `pop3: missing CRLF`.
4. **Exactly one response.** Bytes after a complete single-line response
   (including a `-ERR`), and bytes after the `"."` terminator, are
   `pop3: text after response`. The parser is not a stream splitter: the
   caller passes one response at a time.
5. **Multi-line expectation.** The `multiline` parameter states what the
   caller expects: true for `LIST`/`UIDL` without an argument, `RETR` and
   `TOP`; false for single-line responses (`STAT`, `USER`, ...). A `-ERR`
   response is always single-line and parses in either mode. A `+OK` parsed
   with `multiline == false` that carries further bytes is
   `pop3: text after response`; a `+OK` parsed with `multiline == true`
   that never reaches `"."` is `pop3: unterminated multiline response`
   (including `+OK\r\n` with no payload at all).
6. **Payload and dot-stuffing.** Payload lines are CRLF-terminated, the
   terminator is the first bare `"."` line, and order is preserved. A
   payload line beginning with `"."` loses exactly one leading `"."`
   (unstuffed: `..x` -> `.x`, `..` -> `.`); a line that is exactly `"."` is
   the terminator and is *not* payload, so a logical `"."` payload line
   exists only in its stuffed `..` form. Stuffed text is what is measured
   for the cap; payload line content above `POP3_MAX_LINE` is
   `pop3: line too long`.
7. **Payload bytes.** Payload lines are otherwise opaque: any byte except
   CR and LF is accepted (8-bit message text included). A lone CR or LF
   inside a line is `pop3: control byte in payload line`.
8. **Emitter.** `pop3_build_response` emits `+OK`/`-ERR`, the text after one
   space when non-empty, CRLF, then -- only when `multiline` is true --
   every payload line with one stuffing `"."` prepended where needed,
   followed by the `"."` terminator, even for an empty payload. A `-ERR`
   response with `multiline == true`, or any payload on a `multiline ==
   false` response, is `pop3: bad argument: ...`. The pair columns are parse
   output and are never emitted; `lines` is the only payload source, so
   `build(parse(x))` reproduces canonical multi-line bytes exactly.

## 6. LIST and UIDL listings

`pop3_parse_listing(kind, text)` parses a complete `LIST` or `UIDL` response
(multi-line expectation always on) and fills `pair_nums`/`pair_vals`:

- every payload line must have the shape `<msg> SP <value>` with a non-empty
  message-number part and no further parsing of the value part;
- `msg` is canonical decimal in `1..POP3_MAX_NUM`; `0`, leading zeros and
  non-digits are `pop3: bad argument: listing message number`;
- for `LIST` the value is a canonical decimal size in `0..POP3_MAX_NUM`
  (`0` is a valid size); anything else is
  `pop3: bad argument: listing size`;
- for `UIDL` the value is 1..70 bytes, each in `0x21..0x7E` (no spaces);
  anything else is `pop3: bad argument: listing unique-id`;
- a line without a space, or with an empty message-number part, is
  `pop3: bad argument: listing line`;
- a `-ERR` response parses as a single-line response with zero pairs, and a
  single-line `+OK` (a rejected listing is impossible in RFC 1939, but the
  parser does not guess) also yields zero pairs;
- message-number ordering and duplicates are *not* validated; `kind` values
  other than `POP3_LIST`/`POP3_UIDL` are
  `pop3: bad argument: kind is not LIST or UIDL`.

Documented narrowing: RFC 1939 permits implementations to append extra
information after a scan listing's size; this codec is strict and rejects
anything after the size, so a listing line carries exactly two fields. RFC
1939 already forbids anything after a unique-id.

## 7. API signatures

```xi
// Requests
pub fn pop3_parse_request(line: Str) -> Result[Pop3Request, Str]
pub fn pop3_build_request(req: &Pop3Request) -> Result[Str, Str]

// Responses
pub fn pop3_parse_response(multiline: Bool, text: Str) -> Result[Pop3Response, Str]
pub fn pop3_parse_listing(kind: Int, text: Str) -> Result[Pop3Response, Str]
pub fn pop3_build_response(resp: &Pop3Response) -> Result[Str, Str]

// Dot-stuffing helpers
pub fn pop3_dot_stuff(line: Str) -> Str
pub fn pop3_dot_unstuff(line: Str) -> Str

// Response accessors (bounds-safe, sentinel-based)
pub fn pop3_is_ok(resp: &Pop3Response) -> Bool
pub fn pop3_is_multiline(resp: &Pop3Response) -> Bool
pub fn pop3_response_text(resp: &Pop3Response) -> Str
pub fn pop3_line_count(resp: &Pop3Response) -> Int
pub fn pop3_line(resp: &Pop3Response, index: Int) -> Str
pub fn pop3_pair_count(resp: &Pop3Response) -> Int
pub fn pop3_pair_num(resp: &Pop3Response, index: Int) -> Int
pub fn pop3_pair_val(resp: &Pop3Response, index: Int) -> Str
pub fn pop3_lookup_line(resp: &Pop3Response, msg: Int) -> Int
pub fn pop3_list_size(resp: &Pop3Response, msg: Int) -> Int
pub fn pop3_uidl_id(resp: &Pop3Response, msg: Int) -> Str
pub fn pop3_payload(resp: &Pop3Response) -> Str
```

Accessor conventions: out-of-range indexes and absent messages return `-1`
(`pop3_pair_num`, `pop3_lookup_line`, `pop3_list_size`) or `""`
(`pop3_line`, `pop3_pair_val`, `pop3_uidl_id`). `pop3_lookup_line` returns
the first matching pair index, which for a listing parse is also the payload
line index. `pop3_payload` concatenates the dot-unstuffed payload lines,
each terminated by CRLF, and returns `""` when there are none.

## 8. Error catalog

Errors are plain `Str` values. Every message starts with `"pop3: "`; the
conformance suite matches that prefix, and the exact suffixes below are part
of the specification.

| Message | Trigger |
|---|---|
| `pop3: bad status marker` | status line does not start with uppercase `+OK`/`-ERR`, or the marker is followed by neither CRLF nor one space |
| `pop3: missing CRLF` | a required CRLF is absent (unfinished status line, payload bytes left without a terminator) |
| `pop3: unterminated multiline response` | multi-line expected but the `"."` terminator never arrives (including a `+OK` with no payload) |
| `pop3: text after response` | bytes after a single-line response or after the `"."` terminator |
| `pop3: control byte in command line` | command content byte outside `0x20..0x7E` |
| `pop3: control byte in response text` | status text byte outside `0x20..0x7E` |
| `pop3: control byte in payload line` | CR or LF inside a payload line |
| `pop3: dot-stuffing violation` | `pop3_build_response` payload line contains CR or LF and cannot be framed |
| `pop3: line too long` | line content above `POP3_MAX_LINE` (510 bytes, CRLF excluded) in any direction |
| `pop3: bad argument: empty command line` | empty or CRLF-only command line |
| `pop3: bad argument: unknown command` | unmodelled keyword |
| `pop3: bad argument: unexpected argument` | argument on `STAT`/`NOOP`/`RSET`/`QUIT` |
| `pop3: bad argument: user name` | `USER`/`APOP` name empty, over 40 bytes, or containing a space |
| `pop3: bad argument: password` | `PASS` string empty |
| `pop3: bad argument: message number` | missing or malformed message number |
| `pop3: bad argument: line count` | missing or malformed `TOP` line count |
| `pop3: bad argument: TOP arguments` | `TOP` without two arguments |
| `pop3: bad argument: apop name` | `APOP` name missing or malformed |
| `pop3: bad argument: apop digest` | digest not exactly 32 hex digits |
| `pop3: bad argument: unknown command kind` | `pop3_build_request` kind outside 1..12 |
| `pop3: bad argument: kind is not LIST or UIDL` | `pop3_parse_listing` kind other than 4/5 |
| `pop3: bad argument: listing line` | listing line without `SP` or with an empty message number |
| `pop3: bad argument: listing message number` | listing message number not canonical decimal in 1..2^31-1 |
| `pop3: bad argument: listing size` | LIST value not canonical decimal in 0..2^31-1 |
| `pop3: bad argument: listing unique-id` | UIDL value outside 1..70 bytes / `0x21..0x7E` |
| `pop3: bad argument: payload on a single-line response` | `pop3_build_response` with `multiline == false` and non-empty `lines` or pair columns |
| `pop3: bad argument: multiline -ERR response` | `pop3_build_response` with `ok == false` and `multiline == true` |

The six required error areas map to these messages as follows: status and
framing (bad status marker, missing CRLF, unterminated multi-line, trailing
text), emitter input (dot-stuffing violation), bad argument (all
`bad argument:` messages), control bytes (the three `control byte` messages
and the emitter's dot-stuffing violation), plus the documented line cap
(`line too long`).

## 9. Test plan

`tests/test_conformance.xi` (module `pop3_tests`) runs 27 named checks
through `xiom.test`'s `assert(cond, "name")`, one `fn` per check, and `main`
returns the failure count (0 = green).

| # | Check | Semantics pinned |
|---|---|---|
| t1 | USER/PASS/STAT parse | kinds, text, absent fields; CRLF optional |
| t2 | LIST/UIDL/RETR/DELE | optional vs required message number |
| t3 | NOOP/RSET/QUIT/TOP/APOP | kinds; `TOP n=0`; digest lowercase folding |
| t4 | keyword case | lowercase/mixed parse; full-length matching; unknown keywords |
| t5 | canonical request bytes | all twelve kinds, uppercase, CRLF |
| t6 | request build validation | bad kinds/fields; unused fields ignored |
| t7 | request round-trips | build -> parse -> build identity per kind |
| t8 | CRLF/empty grammar | lone CR/LF, double CRLF, empty and spaced lines |
| t9 | name/printable rules | 40 vs 41 bytes; tab/DEL/8-bit rejection |
| t10 | message-number rule | 1..2^31-1, no leading zero, junk forms |
| t11 | TOP line count | 0 allowed; missing/leading-zero/overflow forms |
| t12 | PASS/name tokens | spaces in `PASS`; single-token names |
| t13 | APOP digest | 32 hex either case; 31/33/non-hex/extra token |
| t14 | single-line responses | `+OK`/`-ERR`, text with spaces, empty text |
| t15 | marker and trailing bytes | exact uppercase markers; text after a complete response |
| t16 | CRLF and control bytes | unfinished status lines; tab/DEL/CR in text |
| t17 | multi-line RETR | line accessors, blank line, payload join, rebuild identity |
| t18 | dot-stuffing | `..x` -> `.x`, `..` -> `.`, bare `.` terminates; helpers |
| t19 | unterminated payloads | no terminator/no CRLF; stray CR/LF; 8-bit opacity |
| t20 | empty multi-line payload | `+OK\r\n.\r\n`; `-ERR` single-line round-trip |
| t21 | LIST pairs | pair columns, lookup, sizes, byte-identical rebuild |
| t22 | LIST strictness | leading zero, msg 0, extra column, missing size; `-ERR` |
| t23 | UIDL unique-ids | 1..70 bytes, colon allowed, space/control/71 bytes rejected |
| t24 | response building | exact single/multi-line bytes, stuffing, terminator |
| t25 | response build errors | bad shapes, control text, CR/LF payloads, overlong lines |
| t26 | line caps | 510 accepted / 511 rejected in requests and responses |
| t27 | accessor bounds | negative and past-the-end indexes return sentinels |

Element Str comparisons go through `xiom.string.compare.str_compare`, never
`==` (BUG 17: `==` on a `Str` read from a `Vec[Str]` element lowers to a
pointer comparison).

Command: `.\scripts\port.ps1 -Package xiom.pop3` (compiler v0.61.3,
`XIOM_STDLIB=E:\xiom-lang\stdlib`). Expected tail: 27 `[PASS]` lines,
`xiom.pop3: all tests passed`, then
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## 10. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the pure-parser idioms
of `xiom.eml`/`xiom.telnet` (byte-wise scanning with `xiom.string.byte_at`,
byte accumulation with `xiom.string.builder.sb_to_str`, typed locals) and
documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so responses are flat (parallel `Vec`s)
  and requests are a single record, never a vector of per-line structs.
- `Ok`/`Err` for the three public `Result` shapes are constructed only in
  the leaf helpers `_ok_request`/`_err_request`, `_ok_response`/
  `_err_response`, `_ok_str`/`_err_str`.
- Every widened byte goes through `(byte_at(s, i) as Int) & 0xFF`; element
  reads are bound to typed locals (`let line: Str = resp.lines[i];`) before
  comparison, and every `Str` comparison uses `str_compare`.
- No `[T, U]` generics, no `Vec[fn]`, no `Vec[Float64]`, no `match` arm
  binds `mut`; tests dispatch `t1()` .. `t27()` directly; every `match` is
  exhaustive.
- The source and test files are grep-audited for stray `Vec<`/`Result<`
  angle brackets after every edit (v0.61.3 accepts malformed bracket types
  silently in some positions).

## 11. Non-goals and limitations

- No sockets, timers, TLS or session state machine: callers own the wire and
  the AUTHORIZATION/TRANSACTION/UPDATE sequencing and pass one command or
  one response per call.
- No cryptography: the APOP digest is stored and compared as text; no MD5.
- No extensions: `CAPA`, `AUTH`, `STLS`, `SASL`, response codes (`+OK
  [CODE] text` is kept as opaque printable text), pipelining and
  `LAST`/`XLST`-style commands are out of scope.
- Strict framing: exactly one CRLF terminator, exactly one response per
  parse call, no lone CR/LF acceptance anywhere, and a strict two-field
  LIST/UIDL form (a documented narrowing of RFC 1939's optional trailing
  scan-listing information).
- Listing pairs are not validated for order, uniqueness or coverage; the
  first duplicate message number wins in `pop3_lookup_line`.
- Status text is ASCII-only; 8-bit text is rejected. Payload bytes are
  opaque except CR/LF, but no charset or transfer decoding is applied.
- Errors carry no line or byte offset; each message names the violated rule.
