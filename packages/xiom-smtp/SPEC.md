# xiom.smtp -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.smtp` (`src/smtp.xi`). Pure XIOM, no FFI, no I/O, no session
state.

## 1. Scope

A small, dependency-free codec for the SMTP wire format defined by RFC 5321
(grammar subset):

- `cmd_parse` -- one command line -> `Result[Cmd, Str]`,
- `cmd_build` and the convenience builders (`cmd_ehlo`, `cmd_helo`,
  `cmd_mail`, `cmd_rcpt`, `cmd_auth`, `cmd_noop`, `cmd_data`, `cmd_rset`,
  `cmd_quit`, `cmd_starttls`) -- `Cmd` values from parts,
- `cmd_emit` and the `cmd_*` accessors -- canonical wire text and fields,
- `resp_parse` -- one reply block -> `Result[Resp, Str]`,
- `resp_build` / `resp_emit` and the `resp_*` accessors -- reply blocks and
  their fields, including the enhanced status code.

Non-goals: sockets and session state, DATA content parsing (sibling
`xiom.eml`), AUTH mechanism logic, TLS, address rewriting, DNS.

## 2. Data model

```xi
pub type Cmd = {
  verb: Str;        // canonical uppercase verb ("MAIL", "EHLO", ...)
  arg: Str;         // argument text; canonical for MAIL/RCPT, verbatim otherwise
  path: Str;        // "<...>" for MAIL/RCPT, "" otherwise
  params: Vec[Str]; // ESMTP parameters for MAIL/RCPT in order, otherwise empty
}

pub type Resp = {
  code: Int;        // 100..599
  klass: Int;       // code / 100 (2..5 for SMTP reply classes)
  pool: Str;        // the line texts joined with CRLF
  spans: Vec[Int];  // two Ints per line: start, end into pool
}
```

Invariants (maintained by every constructor in the module):

- `Cmd.verb` is always the uppercase canonical verb; `path` is non-empty
  exactly for MAIL/RCPT; `params` is non-empty only for MAIL/RCPT.
- `Resp.spans.len()` is always even and equals `2 * line_count`; the count is
  derived (`spans.len() / 2`), so the two structures cannot drift.
- The reply pool holds the line texts only (the codes, separators and CRLFs
  are not stored); `spans[2i] .. spans[2i+1]` is line `i`, in order.

`Vec[StructType]` is unsupported in this compiler, so a reply is stored flat
(one `Str` pool plus one `Vec[Int]` of spans) instead of a list of line
structs; a command is a single struct with a `Vec[Str]` for its parameters.

## 3. Wire grammar

```
command    = verb [ SP argument ] CRLF
verb       = "EHLO" / "HELO" / "MAIL" / "RCPT" / "DATA" / "RSET" / "NOOP" /
             "QUIT" / "STARTTLS" / "AUTH" / "VRFY" / "EXPN" / "HELP"
mail-arg   = "FROM:" [ SP ] path *( SP parameter )
rcpt-arg   = "TO:"   [ SP ] path *( SP parameter )
path       = "<" inner ">"                  ; inner may be empty (MAIL only)
parameter  = keyword [ "=" value ]
keyword    = 1*( ALPHA / DIGIT / "-" )
value      = 1*( %d33-126 )

reply      = single / multiline
single     = code [ SP text ] CRLF
multiline  = *( code "-" text CRLF ) code [ SP text ] CRLF
code       = 3DIGIT                          ; accepted range 100..599
text       = *( TAB / %d32-126 / UTF-8 byte )
```

`Str` is treated as a UTF-8 byte buffer; scanning is byte-wise and never
rewrites multi-byte sequences. Framing is CRLF-only: a bare LF, a bare CR or
a missing terminator is rejected.

## 4. Command parsing (`cmd_parse`)

Each decision is covered by the conformance suite.

1. **Framing.** The input must end with `CRLF`; otherwise
   `Err("smtp: missing CRLF")`. A CR or LF inside the content is a control
   byte (rule 3).
2. **Length cap.** The whole line including CRLF is at most 512 octets
   (RFC 5321 section 4.5.3.1.5), i.e. the content cap is 510; a longer input
   is `Err("smtp: command too long: <octets>")`. `smtp_command_limit()`
   exposes 512.
3. **Control bytes.** Every content byte must be space (0x20) or above and
   not DEL (0x7F); a C0 byte (TAB included) or DEL is
   `Err("smtp: control byte in command")`. Bytes >= 0x80 pass through.
4. **Verb split.** The verb is the leading non-space token up to the first
   space; the argument runs to the end of the content with surrounding
   spaces trimmed (interior runs are preserved here and canonicalized on
   emit for MAIL/RCPT only). An empty or unknown verb is
   `Err("smtp: bad verb: <raw-verb>")` -- no leading spaces are allowed.
5. **Case.** The verb is matched case-insensitively (ASCII) and stored
   uppercase. EHLO/HELO, MAIL, RCPT, DATA, RSET, NOOP, QUIT, STARTTLS, AUTH,
   VRFY, EXPN and HELP are recognized.
6. **MAIL/RCPT keyword.** The argument must start with `FROM:` / `TO:`
   (case-insensitive) followed by optional spaces; anything else is
   `Err("smtp: bad path: missing FROM:")` (or `... missing TO:`).
7. **Path.** After the keyword (and spaces) the argument must start with
   `<`; the path is the byte range through the matching `>`. A double quote
   toggles quoted mode: inside it, a `>` does not close the path and spaces
   do not split parameters. Backslash-escaped quotes are not decoded
   (documented limitation). A missing `>` is
   `Err("smtp: bad path: unterminated '<'")`; a missing `<` is
   `Err("smtp: bad path: expected '<'")`; an argument that ends after the
   keyword is `Err("smtp: bad path: missing path")`.
8. **Source routes.** An inner path starting with `@` is rejected:
   `Err("smtp: bad path: source routes are not supported")`. RFC 5321 source
   routes (`<@a,@b:user@c>`) are deliberately out of scope.
9. **Null paths.** `MAIL FROM:<>` (the null reverse-path) is accepted;
   `RCPT TO:<>` is `Err("smtp: bad path: empty forward-path")`.
10. **Parameters.** After the path, the next byte must be a space or the end
    of the argument; otherwise
    `Err("smtp: bad path: path must be followed by a space")`. Parameters
    are space-separated tokens validated by section 5. An empty token cannot
    occur (runs of spaces are skipped), so the parameter errors are
    keyword/value shape errors.
11. **Per-verb argument rules.** `DATA`, `RSET`, `QUIT` and `STARTTLS` take
    no argument: any non-empty argument is
    `Err("smtp: bad verb: <VERB> takes no argument")`. `AUTH` requires a
    non-empty argument: `Err("smtp: bad verb: AUTH requires a mechanism")`.
    `EHLO`, `HELO`, `NOOP`, `VRFY`, `EXPN` and `HELP` accept any argument,
    including an empty one.
12. **MAIL/RCPT argument canonicalization.** After a successful path parse,
    `cmd.arg` is re-rendered as `FROM:`/`TO:` + path + one space per
    parameter, so `"mail  from: <a@b>  SIZE=1"` parses to the canonical
    `MAIL FROM:<a@b> SIZE=1`.
13. **All other arguments are verbatim** (case preserved, surrounding spaces
    trimmed): `cmd_argument` for `EHLO Example.COM` is `Example.COM`.

## 5. Parameter grammar

A parameter token is `keyword` or `keyword=value`:

- the keyword is 1 or more ASCII letters, digits or `-`; a token whose
  keyword is empty (`=v`), or that carries any other byte, is
  `Err("smtp: bad path: malformed parameter: <token>")` (an empty keyword is
  `Err("smtp: bad path: empty parameter keyword: <token>")`);
- a value must be non-empty (`SIZE=` is
  `Err("smtp: bad path: empty parameter value: <token>")`) and printable
  ASCII 33..126 (no spaces, no controls, no bytes >= 0x80);
- a value-less parameter (`PIPELINING`) is legal.

Quoted parameter values are not special-cased: a `"` is an ordinary value
byte, and a value containing a space splits into two tokens (the second one
then fails keyword validation).

## 6. Command building and canonical emit

- `cmd_build(verb, arg)` trims and uppercases `verb` (unknown ->
  `Err("smtp: bad verb: <verb>")`), trims `arg`, runs the control-byte check,
  then applies the same rules as parsing. For MAIL/RCPT, `arg` must be the
  full `FROM:`/`TO:` form; `cmd_mail`/`cmd_rcpt` assemble it from a path and
  a `&Vec[Str]` of parameters.
- `cmd_ehlo`/`cmd_helo` reject an empty or spaces-only domain with
  `Err("smtp: bad verb: EHLO requires a domain")` (resp. HELO). The generic
  builder is permissive there; only the control-byte rule applies.
- `cmd_auth(mechanism, initial_response)` requires a non-empty mechanism and
  keeps the optional initial response verbatim (`"=` is the empty-response
  form).
- `cmd_data`/`cmd_rset`/`cmd_quit`/`cmd_starttls` return bare commands (no
  `Result`), as no validation is needed.
- `cmd_emit` renders `verb`, then `" " + arg` when `arg` is non-empty, then
  `CRLF`. Canonically written input round-trips byte-for-byte; non-canonical
  spacing is normalized (a run of spaces becomes one, surrounding spaces are
  dropped), and MAIL/RCPT keywords are uppercased.

## 7. Reply parsing (`resp_parse`)

1. **Framing.** The input must end with `CRLF` and may contain no bare CR or
   LF; otherwise `Err("smtp: missing CRLF")`.
2. **Lines.** The input is scanned into CRLF-terminated lines. A line shorter
   than three bytes is `Err("smtp: bad code digits: <line>")`.
3. **Code.** The first three bytes must be ASCII digits and the code must be
   in 100..599; otherwise `Err("smtp: bad code digits: <line>")`. The fourth
   byte selects the form: `-` is a continuation line, a space is a final
   line, and a three-byte line (`NNN`) is a bare final line. Any other
   fourth byte is `Err("smtp: bad code digits: <line>")`.
4. **Block consistency.** The first line fixes `code` and `klass`
   (`code / 100`, so 1..5); a later line carrying a different code is
   `Err("smtp: multiline code mismatch: <line>")`. The check order per line
   is: length, digits, range, code match, separator byte, text bytes.
5. **Termination.** The first final line (`NNN`, `NNN SP text`) ends the
   reply. A single-line reply therefore ends at its first line and any
   remaining bytes are ignored (the caller splits a stream); a multiline
   block ends at its `NNN SP text` line, and bytes after it are likewise
   ignored.
6. **Unterminated.** When the input ends on a continuation line (its last
   line used `-`, including a first line `"250-"`), the result is
   `Err("smtp: unterminated multiline")`.
7. **Text.** The text is everything after the fourth byte (empty for a bare
   `NNN` line). TAB (0x09) is legal; every other C0 byte and DEL is
   `Err("smtp: control byte in response")`. Bytes >= 0x80 pass through.
8. **Storage.** Line texts are appended to the pool in order, separated by
   CRLF, with a `(start, end)` pair pushed per line; `resp_line_count` is
   `spans.len() / 2`.

Parsed examples (all covered by the suite):

| Input | Result |
|---|---|
| `220 smtp.example.com ESMTP\r\n` | code 220, class 2, 1 line, text `smtp.example.com ESMTP` |
| `250\r\n` | code 250, 1 line, text `""` |
| `250-a\r\n250 b\r\n` | code 250, 2 lines (`a`, `b`) |
| `250-a\r\n251 b\r\n` | Err multiline code mismatch |
| `250-a\r\n250-b\r\n` | Err unterminated multiline |
| `2X0 OK\r\n` / `099 x\r\n` | Err bad code digits |
| `250 OK` / `250 OK\n` | Err missing CRLF |

## 8. Reply building and canonical emit

- `resp_build(code, lines)` accepts `code` in 100..599 (else
  `Err("smtp: bad code digits: <code>")`), at least one line (else
  `Err("smtp: unterminated multiline: response has no lines")`) and applies
  the same text-byte rule as parsing (else
  `Err("smtp: control byte in response")`). One line builds a single-line
  reply; more lines build a multiline block.
- `resp_emit` renders each non-final line as `NNN-text\r\n` and the final
  line as `NNN text\r\n` when its text is non-empty, or `NNN\r\n` when it is
  empty. A final line written with a trailing space but empty text
  (`"250 \r\n"`) canonicalizes to `"250\r\n"`; every other canonical block
  round-trips byte-for-byte.
- There is no reply length cap (the command cap does not apply here).

## 9. Enhanced status codes

`resp_enhanced` inspects the text of the **first line only** and returns the
leading `x.y.z` when it matches RFC 3463 shape: class = exactly one digit,
subject = 1..3 digits, detail = 1..3 digits, each pair separated by `.`, and
the whole code followed by a space or the end of the text. Otherwise it
returns `""` (and `resp_has_enhanced` is false). Examples: `5.1.1` from
`550 5.1.1 User unknown`; `2.1.0` from a first line `250-2.1.0 queued`;
`""` from `250 OK` and from `250 12.1.0 nope` (class must be one digit).

## 10. Accessors

- `cmd_name` -> canonical `verb`; `cmd_argument` -> canonical/verbatim
  argument; `cmd_path` -> `path`; `cmd_param_count` / `cmd_param(i)` ->
  ESMTP parameters (`""` for an out-of-range index); `cmd_verb_is` ->
  ASCII case-insensitive verb test.
- `resp_code` / `resp_class` -> `code` / `klass`; `resp_is_multiline` ->
  line count > 1; `resp_line_count` -> `spans.len() / 2`;
  `resp_line(i)` / `resp_text` -> line text / first line text (`""` for an
  out-of-range index); `resp_enhanced` / `resp_has_enhanced` -> section 9.
- All accessors are read-only and return fresh `Str` values; mutating a
  returned vector never affects the parsed value.

## 11. Error catalog

Every failure is `Err(msg)` with `msg` starting with `"smtp: "`. The eight
classes:

| Message | Trigger |
|---|---|
| `smtp: bad verb: <verb>` | unknown verb; `DATA`/`RSET`/`QUIT`/`STARTTLS` with an argument; `AUTH` without a mechanism; empty domain in `cmd_ehlo`/`cmd_helo`; empty verb |
| `smtp: bad path: ...` | MAIL/RCPT keyword missing; missing `<` / `>`; missing path; source route; `RCPT TO:<>`; path not followed by a space; malformed/empty parameter keyword, value or token |
| `smtp: missing CRLF` | no `CRLF` terminator, a bare LF or CR, or a lone CR inside a reply |
| `smtp: bad code digits: <line-or-code>` | reply code not three digits, outside 100..599, or followed by a byte that is neither `-`, space nor end of line; `resp_build` code out of range |
| `smtp: multiline code mismatch: <line>` | a continuation line whose code differs from the first line |
| `smtp: unterminated multiline` | a multiline block that never reaches a final line; `resp_build` with an empty line vector |
| `smtp: control byte in command` / `smtp: control byte in response` | a C0 byte (TAB included in commands; TAB allowed in reply text) or DEL |
| `smtp: command too long: <octets>` | command line larger than 512 octets including CRLF |

Errors carry the offending line text where useful but never byte positions.

## 12. Test plan

`tests/test_conformance.xi` (module `smtp_tests`) runs 22 named checks
through `assert(cond, "name")`, one `fn` per check, and `main` returns the
failure count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | EHLO | name/argument/path/params/emit |
| t2 | MAIL/RCPT | path, parameter order, argument and emit |
| t3 | null paths | `MAIL FROM:<>` legal; `RCPT TO:<>` rejected; builders |
| t4 | quoted local part | `<"alice smith"@example.com>` passes through unsplit |
| t5 | bad paths | source route, unterminated `<`, missing `FROM:`, truncated path |
| t6 | bare verbs | DATA/RSET/QUIT/STARTTLS round-trip; DATA with an argument; NOOP forms |
| t7 | AUTH | mechanism + initial response, `AUTH` alone, empty mechanism |
| t8 | pass-through | VRFY/EXPN/HELP arguments, empty HELP |
| t9 | case | lowercase verbs parse, uppercase emit, unknown verb error |
| t10 | command framing | missing CRLF, bare LF, bare CR, empty input |
| t11 | command control bytes | TAB, interior CR, builder check |
| t12 | length cap | 512 limit, 510-byte content accepted, 511 rejected |
| t13 | single-line replies | code/class/line count/text/emit; classes 2..5; bare `250` |
| t14 | multiline replies | 4-line EHLO block, every `resp_line`, exact emit |
| t15 | block consistency | code mismatch; unterminated `250-` |
| t16 | bad codes | non-digit, short, bad separator byte, out-of-range, empty line |
| t17 | enhanced codes | `5.1.1`, `2.0.0`, absent, first line only, 2-digit class rejected, code at end |
| t18 | reply framing | missing CRLF, bare LF, bare CR, unterminated second line |
| t19 | `resp_build` | multiline + single-line emit, empty lines, bad code, control byte |
| t20 | reply round-trips | `250`, multiline, enhanced; `250 ` canonicalization |
| t21 | bounds | out-of-range `cmd_param`/`resp_line` -> `""`; `cmd_verb_is` |
| t22 | round-trip battery | 15 canonical commands + 6 canonical replies |

All `Str` equality in the tests goes through `xiom.string.compare`'s
`str_compare` (BUG 17: `==` on a `Str` read from `Vec[Str]` elements lowers
to a pointer comparison), and every vector element read is bound to an
explicitly typed local first.

## 13. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.eml`/`xiom.irc` and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the reply line list is a text pool
  plus a span vector (no `Vec[Line]`) and command parameters are a plain
  `Vec[Str]`.
- `Ok`/`Err` for `Result[Cmd, Str]` and `Result[Resp, Str]` are constructed
  only in the leaf helpers `_ok_cmd`/`_err_cmd`/`_ok_resp`/`_err_resp`.
- Every byte read is widened once: `(string.byte_at(s, i) as Int) & 0xFF`,
  so no `UInt8` value is ever compared against an `Int` literal.
- `Str` values read from vectors are bound to typed locals
  (`let p: Str = params[i];`) before use, and no `Str` pair is compared with
  `==`.
- Tests dispatch directly (`t1()` ... `t22()`); there is no `Vec[fn]`, no
  lambda, no `match` that binds `mut`, and every `match` is exhaustive.

## 14. Known limitations

- No sockets, no session state, no pipelining bookkeeping, no timeouts.
- No DATA payload parsing and no dot-unstuffing: that is `xiom.eml`'s or the
  caller's job.
- AUTH mechanisms and TLS are not implemented; their arguments are opaque
  strings.
- Source routes are rejected rather than decoded; quoted-pairs inside a
  quoted local part are not decoded.
- `resp_parse` consumes one reply; for a single-line first line the rest of
  the buffer is ignored, so a caller parsing a stream must split on line
  boundaries itself.
- Reply text bytes >= 0x80 are passed through without UTF-8 validation, and
  replies have no length cap.
