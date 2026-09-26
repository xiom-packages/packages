# xiom.ftp

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and tested by
> the package conformance suite. **NOT published** to the XIOM registry.
> **Scope:** a codec for the FTP control connection (RFC 959 plus common
> extensions): parse and emit the commands `USER PASS ACCT CWD CDUP PWD QUIT
> PORT PASV TYPE MODE STRU RETR STOR STOU APPE LIST NLST DELE RMD MKD RNFR
> RNTO ABOR SYST STAT FEAT OPTS SIZE MDTM`, and parse and emit `NNN text`
> single-line replies and `NNN-...` multiline reply blocks.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder` and
> `xiom.string.compare`). Tests additionally use `xiom.test` and `xiom.io`.

## Scope

`xiom.ftp` is a *protocol codec*, not a client and not a server. It turns the
bytes of one control-connection line into typed values and back:

```
USER alice<CRLF>                       -> Command("USER", "alice")
PORT 192,168,0,1,4,1<CRLF>             -> Command("PORT", "192,168,0,1,4,1")
220 Service ready<CRLF>                -> Response(220, single line)
211-Features:<CRLF> SIZE<CRLF>211 End<CRLF> -> Response(211, multiline)
```

There are no sockets, no session/state machine, no data-connection semantics
and no directory-listing parsing: `LIST`/`NLST`/`STAT` arguments are carried
as opaque text. Everything is byte-oriented, allocation-light and free of
global state.

## API

| Function | Returns | Description |
|---|---|---|
| `ftp_parse_command(text)` | `Result[Command, Str]` | Parse one `VERB [arg]` CRLF line; verb uppercased, argument validated and canonicalized per verb. |
| `ftp_emit_command(c)` | `Str` | Canonical `VERB [arg]` CRLF line. |
| `ftp_command_name(c)` | `Str` | Uppercase verb. |
| `ftp_command_argument(c)` | `Str` | Canonical argument text (`""` when none). |
| `ftp_command_raw(c)` | `Str` | Verbatim input line, CRLF included. |
| `ftp_port_octets(c)` | `Vec[Int]` | Six PORT octets (`h1..p2`); empty for a non-PORT command or a malformed argument. |
| `ftp_type_code(c)` | `Str` | TYPE code letter (`"A"`, `"E"`, `"I"`, `"L"`); `""` for a non-TYPE command. |
| `ftp_mode_code(c)` | `Str` | MODE code letter (`"S"`, `"B"`, `"C"`); `""` for a non-MODE command. |
| `ftp_stru_code(c)` | `Str` | STRU code letter (`"F"`, `"R"`, `"P"`); `""` for a non-STRU command. |
| `ftp_parse_response(text)` | `Result[Response, Str]` | Parse exactly one single-line or multiline reply (whole input consumed). |
| `ftp_emit_response(r)` | `Str` | Canonical CRLF reply text. |
| `ftp_response_code(r)` | `Int` | Reply code (equal on every reply-prefixed line). |
| `ftp_response_class(r)` | `Int` | Code / 100: 1, 2, 3, 4 or 5. |
| `ftp_response_is_multiline(r)` | `Bool` | True when the reply has more than one physical line. |
| `ftp_response_line_count(r)` | `Int` | Number of physical lines. |
| `ftp_response_line(r, i)` | `Str` | Physical line `i` without CRLF; `""` out of range. |
| `ftp_response_line_code(r, i)` | `Int` | Reply code of line `i`, or `-1` when the line has no `NNN`/`NNN-` prefix. |
| `ftp_response_text(r)` | `Str` | First line's text after the code and space/dash. |
| `ftp_response_raw(r)` | `Str` | Verbatim reply text, CRLF included. |

`FTP_MAX_COMMAND_BYTES` (512) and `FTP_MAX_RESPONSE_BYTES` (8192) are the
accepted size caps. The exact grammar, per-verb rules, documented decisions,
error catalog and test plan are in `SPEC.md`.

## Usage

```xi
use xiom.ftp;
use xiom.io;

fn main() -> Int {
  let c = ftp_parse_command("port 192,168,0,1,7,138\r\n");
  if c.is_ok {
    let cmd: Command = c.value;
    io.println(ftp_command_name(&cmd));     // "PORT"
    io.println(ftp_emit_command(&cmd));     // "PORT 192,168,0,1,7,138\r\n"
  }
  let r = ftp_parse_response("220 Service ready\r\n");
  if r.is_ok {
    let rep: Response = r.value;
    io.println(ftp_response_text(&rep));    // "Service ready"
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.ftp
```

Expected tail: 24 `[PASS]` lines, `xiom.ftp: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **No sockets and no state:** no connect, no greeting, no login sequence, no
  data channel, no transfer progress. The caller drives the session.
- **No directory-listing parsing:** `LIST`/`NLST`/`STAT` payload text is
  carried verbatim; MLSD/MLST line formats are not decoded.
- **Strict CRLF:** a command or reply line without its terminating CRLF is an
  error; bare LF is a control byte, not a line ending.
- **Simplified multiline replies:** the terminating `NNN ` line must carry
  the opening code. Lines between are carried as-is, with `-1` as their line
  code when they do not start with `NNN ` or `NNN-`; a differently-numbered
  reply-shaped line is a mismatch error (see `SPEC.md`).
- **Verb set is fixed:** other verbs (e.g. `NOOP`, `SITE`, `REST`, `MLSD`)
  are `ftp: unknown verb`.
- **ASCII validation only:** characters above 0x7E are passed through
  byte-wise; control bytes (0x00-0x1F, 0x7F) are always rejected.

License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
