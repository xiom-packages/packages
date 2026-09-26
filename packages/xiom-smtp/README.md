# xiom.smtp

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** SMTP protocol codec: RFC 5321 command lines and reply blocks,
> in-memory `Str` only.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice` and `xiom.string.builder.sb_to_str`). Tests
> additionally use `xiom.test`, `xiom.io` and `xiom.string.compare`.

## Scope

`xiom.smtp` is a stateless codec for the SMTP wire format: it parses and
builds command lines (EHLO, HELO, MAIL, RCPT, DATA, RSET, NOOP, QUIT,
STARTTLS, AUTH, VRFY, EXPN, HELP) and reply blocks (`NNN text` and the
`NNN-text` multiline form), with CRLF framing, a command length cap, the
`<...>` path grammar (quoted local parts pass through, source routes are
rejected) and enhanced status codes. Parsing is case-insensitive for verbs;
canonical emit is uppercase. Malformed input returns `Err("smtp: ...")` from
the documented error catalog.

It intentionally does **not** open sockets, track session state, parse DATA
content (that is `xiom.eml`), implement AUTH mechanisms or speak TLS.

## API

| Function | Returns | Description |
|---|---|---|
| `cmd_parse(line)` | `Result[Cmd, Str]` | Parse one CRLF-terminated command line. |
| `cmd_build(verb, arg)` | `Result[Cmd, Str]` | Generic builder; MAIL/RCPT need the full `FROM:`/`TO:` argument. |
| `cmd_ehlo(domain)` / `cmd_helo(domain)` | `Result[Cmd, Str]` | EHLO/HELO with a non-empty domain. |
| `cmd_mail(reverse_path, params)` | `Result[Cmd, Str]` | `MAIL FROM:<path> [params]`; `<>` is legal. |
| `cmd_rcpt(forward_path, params)` | `Result[Cmd, Str]` | `RCPT TO:<path> [params]`; `<>` is rejected. |
| `cmd_auth(mechanism, initial_response)` | `Result[Cmd, Str]` | `AUTH <mechanism> [initial-response]`. |
| `cmd_noop(arg)` | `Result[Cmd, Str]` | `NOOP [string]`. |
| `cmd_data()` / `cmd_rset()` / `cmd_quit()` / `cmd_starttls()` | `Cmd` | Bare commands. |
| `cmd_emit(c)` | `Str` | Canonical CRLF-framed line. |
| `cmd_name(c)` | `Str` | Canonical uppercase verb. |
| `cmd_argument(c)` | `Str` | Argument text (canonical for MAIL/RCPT). |
| `cmd_path(c)` | `Str` | The `<...>` path of MAIL/RCPT (else `""`). |
| `cmd_param_count(c)` / `cmd_param(c, i)` | `Int` / `Str` | ESMTP parameters of MAIL/RCPT; out-of-range yields `""`. |
| `cmd_verb_is(c, name)` | `Bool` | Case-insensitive verb test. |
| `resp_parse(text)` | `Result[Resp, Str]` | Parse exactly one reply block. |
| `resp_build(code, lines)` | `Result[Resp, Str]` | Build a single-line or multiline reply. |
| `resp_emit(r)` | `Str` | Canonical CRLF-framed reply block. |
| `resp_code(r)` / `resp_class(r)` | `Int` | Code (100..599) and class (`code / 100`). |
| `resp_is_multiline(r)` | `Bool` | True for a `NNN-` block. |
| `resp_line_count(r)` / `resp_line(r, i)` | `Int` / `Str` | Line count and line text; out-of-range yields `""`. |
| `resp_text(r)` | `Str` | Text of the first line. |
| `resp_enhanced(r)` / `resp_has_enhanced(r)` | `Str` / `Bool` | Enhanced `x.y.z` code at the start of the first line text, when present. |
| `smtp_command_limit()` | `Int` | 512: the maximum command line length including CRLF. |

## Usage

```xi
use xiom.smtp;
use xiom.io;

fn main() -> Int {
  match cmd_parse("mail from:<alice@example.com> SIZE=100\r\n") {
    Ok(c) => { io.println(cmd_emit(&c)); }   // MAIL FROM:<alice@example.com> SIZE=100
    Err(e) => { io.println(e); },
  }
  match resp_parse("550-5.1.1 no such user\r\n550 5.1.1 giving up\r\n") {
    Ok(r) => {
      io.println(resp_enhanced(&r));          // 5.1.1
      io.println(resp_class(&r));             // 5
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.smtp
```

Expected tail: 22 `[PASS]` lines, `xiom.smtp: all tests passed`, then
`port: PASS (passed=22 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No I/O and no session state**: the codec never connects, buffers streams
  or tracks the envelope; it parses one command line or one reply block at a
  time.
- **No DATA content parsing**: after `DATA` the payload is the caller's
  problem; `xiom.eml` handles message structure.
- **No AUTH mechanisms and no TLS**: `AUTH` arguments and `STARTTLS` are
  transported verbatim.
- Replies have no length cap (commands do: 512 octets including CRLF), and
  enhanced status codes are only read from the first line of a block.
- A quoted local part may contain spaces, but quoted-pairs (`\"`) are not
  decoded and a quoted ESMTP parameter value may not contain spaces.
- `resp_parse` consumes exactly one reply: a single-line reply ends at its
  first final line and any bytes after it are ignored.

See `SPEC.md` for the full grammar, canonicalization rules, the error catalog
and the test plan. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
