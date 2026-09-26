# xiom.pop3

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** POP3 protocol codec (RFC 1939): the twelve commands, single-line
> and byte-stuffed multi-line responses, and flat LIST/UIDL pair columns;
> in-memory `Str` only, no sockets and no session state.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_starts_with`,
> `xiom.string.builder.sb_push_str/sb_push_int/sb_to_str` and
> `xiom.string.compare.str_compare`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.pop3` parses and builds both directions of the POP3 wire protocol:

- **client commands** (`USER`, `PASS`, `STAT`, `LIST [msg]`, `UIDL [msg]`,
  `RETR msg`, `DELE msg`, `NOOP`, `RSET`, `QUIT`, `TOP msg n`,
  `APOP name digest`) with argument-shape validation: canonical decimal
  message numbers in `1..2^31-1` and TOP line counts in `0..2^31-1`, a
  32-hex APOP digest (opaque, folded to lowercase), single-token names of at
  most 40 bytes, and a `PASS` string that is the rest of the line;
- **server responses**: `+OK [text]` / `-ERR text` and multi-line responses
  terminated by `"."`, with RFC 1939 dot-stuffing applied and undone
  (`..x` <-> `.x`, `..` <-> `.`), CRLF framing, and a documented
  printable-byte and line-length policy;
- **LIST/UIDL listings**: every `<msg> <value>` entry is materialized into
  two flat parallel columns (`pair_nums`, `pair_vals`) so a message can be
  looked up by number without any per-line struct.

A parsed response is one flat record with parallel `Vec`s (`Vec[StructType]`
is unsupported in this compiler); requests are a single record. No MD5 is
computed or verified, and known POP3 extensions (`CAPA`, `AUTH`, `STLS`,
response codes) are out of scope -- see Limitations and `SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `pop3_parse_request(line)` | `Result[Pop3Request, Str]` | Parse one command line (trailing CRLF optional). |
| `pop3_build_request(req)` | `Result[Str, Str]` | Canonical uppercase command line with CRLF. |
| `pop3_parse_response(multiline, text)` | `Result[Pop3Response, Str]` | Parse one complete response; `multiline` states the expectation. |
| `pop3_parse_listing(kind, text)` | `Result[Pop3Response, Str]` | Parse a LIST/UIDL response and fill the pair columns. |
| `pop3_build_response(resp)` | `Result[Str, Str]` | Canonical response bytes; dot-stuffs and terminates a payload. |
| `pop3_dot_stuff(line)` | `Str` | Add one leading `.` when the line starts with `.`. |
| `pop3_dot_unstuff(line)` | `Str` | Remove one leading `.` from a payload line (a bare `.` is the terminator). |
| `pop3_is_ok(resp)` | `Bool` | `+OK` vs `-ERR`. |
| `pop3_is_multiline(resp)` | `Bool` | True when a payload section was parsed (or must be emitted). |
| `pop3_response_text(resp)` | `Str` | Status text after the separator space. |
| `pop3_line_count(resp)` | `Int` | Number of payload lines. |
| `pop3_line(resp, index)` | `Str` | Payload line (dot-unstuffed); `""` out of bounds. |
| `pop3_pair_count(resp)` | `Int` | Number of LIST/UIDL pairs (0 for a generic parse). |
| `pop3_pair_num(resp, index)` | `Int` | Message number of a pair; `-1` out of bounds. |
| `pop3_pair_val(resp, index)` | `Str` | Pair value (size text / unique-id); `""` out of bounds. |
| `pop3_lookup_line(resp, msg)` | `Int` | Pair and payload-line index of `msg`; `-1` when absent. |
| `pop3_list_size(resp, msg)` | `Int` | LIST size of `msg`; `-1` when absent. |
| `pop3_uidl_id(resp, msg)` | `Str` | UIDL unique-id of `msg`; `""` when absent. |
| `pop3_payload(resp)` | `Str` | All payload lines joined, each CRLF-terminated. |

Kind constants: `POP3_USER` .. `POP3_APOP` (1..12), plus `POP3_MAX_NUM`
(2147483647), `POP3_MAX_LINE` (510), `POP3_MAX_NAME` (40), `POP3_UID_MIN`
(1), `POP3_UID_MAX` (70).

## Usage

```xi
use xiom.pop3;
use xiom.io;

fn main() -> Int {
  let c = pop3_parse_request("retr 1");
  match c {
    Ok(req) => {
      match pop3_build_request(&req) {
        Ok(line) => { io.println(line); },   // RETR 1\r\n
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }

  let r = pop3_parse_listing(POP3_LIST, "+OK\r\n1 120\r\n2 200\r\n.\r\n");
  match r {
    Ok(resp) => {
      io.println(pop3_line(&resp, 0));               // 1 120
      if pop3_list_size(&resp, 2) == 200 {
        io.println("message 2 is 200 octets");
      }
      match pop3_build_response(&resp) {
        Ok(wire) => { io.println(wire); },           // +OK\r\n1 120\r\n2 200\r\n.\r\n
        Err(e) => { io.println(e); },
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.pop3
```

Expected tail: 27 `[PASS]` lines, `xiom.pop3: all tests passed`, then
`port: PASS (passed=27 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Codec only**: no sockets, timers, TLS or session state machine. Callers
  own the wire, the AUTHORIZATION/TRANSACTION/UPDATE sequencing and message
  storage, and pass one command or one response per call.
- **No cryptography**: the APOP digest is an opaque 32-hex string; no MD5 is
  computed and no password/timestamp is generated.
- **No extensions**: `CAPA`, `AUTH`, `STLS`, SASL, response codes and
  pipelining are not modelled; `+OK [CODE] text` is opaque printable text.
- **Strict framing**: exactly one CRLF terminator, no lone CR/LF anywhere,
  exactly one response per parse call, and a strict two-field LIST/UIDL
  line (RFC 1939 allows optional trailing columns after a scan-listing
  size; this codec rejects them).
- Status text is ASCII-only; payload bytes are opaque except CR/LF, with no
  charset or transfer decoding. Listing order, duplicates and message
  coverage are not validated.
- Errors carry no line or byte offset, but each message names the rule it
  broke. See `SPEC.md` for the full grammar, catalog and test plan.
- License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
