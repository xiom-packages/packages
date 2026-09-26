# xiom.imap

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** IMAP4rev1 protocol parser (RFC 3501): client commands and server
> responses, with atoms, quoted strings, `{n}`/`{n+}` literals, NIL, nested
> parenthesized lists and response text codes; in-memory `Str` buffers only,
> no sockets and no session state.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare`,
> `xiom.string.builder.sb_to_str` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.imap` parses both directions of the IMAP4rev1 wire protocol out of a
caller-owned buffer:

- **client commands**: `tag SP command-name [SP arguments] CRLF` for
  `CAPABILITY`, `NOOP`, `LOGOUT`, `LOGIN`, `SELECT`, `EXAMINE`, `CREATE`,
  `DELETE`, `RENAME`, `LIST`, `STATUS`, `FETCH`, `STORE`, `SEARCH`, `APPEND`,
  `CLOSE`, `EXPUNGE`, plus the `UID FETCH` / `UID STORE` / `UID SEARCH`
  forms. Command names are matched case-insensitively and stored uppercase;
  argument shapes are validated per command (arity, mailbox strings,
  sequence sets, `FLAGS`/`+FLAGS`/`-FLAGS`, parenthesized `STATUS` item
  lists, `APPEND` message literals), while the *contents* of mailboxes,
  sequence sets, flags, search keys and dates stay opaque text.
- **server responses**: tagged completions `tag OK/NO/BAD [code] text`, all
  untagged forms (`CAPABILITY`, `FLAGS`, `SEARCH`, `LIST`, `LSUB`, `STATUS`,
  numbered `EXISTS`/`RECENT`/`EXPUNGE`/`FETCH`, text-bearing
  `OK`/`NO`/`BAD`/`BYE`/`PREAUTH`) and continuation requests `+`. FETCH
  responses parse parenthesized attribute lists with `\Seen`-style flags and
  multi-line `{n}` literals.
- **response text codes**: `[READ-ONLY]`, `[TRYCREATE]`, `[ALERT]`,
  `[UIDVALIDITY 123]`, `[PERMANENTFLAGS (\Seen \Deleted)]` and friends are
  exposed as an uppercased `code` plus flattened `code_args` text.
- **streaming-ish parsing**: every parse call consumes exactly one command or
  response and reports `consumed` bytes (literals included, so a message may
  span lines); `imap_parse_command_at` / `imap_parse_response_at` resume at a
  byte offset, so a buffer holding several messages can be drained.

A parsed command/response is one flat record with depth-annotated parallel
`Vec`s (`Vec[StructType]` is unsupported in this compiler): list markers and
their children are a flat element stream, so nesting needs no recursion.
Malformed input is rejected with `"imap: ..."` errors that carry byte
offsets, including unbalanced parentheses and bad literal sizes. See
Limitations and `SPEC.md`.

## API

| Function | Returns | Description |
|---|---|---|
| `imap_parse_command(line)` | `Result[ImapCommand, Str]` | Parse one command from the start of a buffer. |
| `imap_parse_command_at(line, pos)` | `Result[ImapCommand, Str]` | Parse one command starting at `pos`. |
| `imap_parse_response(text)` | `Result[ImapResponse, Str]` | Parse one response from the start of a buffer. |
| `imap_parse_response_at(text, pos)` | `Result[ImapResponse, Str]` | Parse one response starting at `pos`. |
| `imap_command_tag(cmd)` | `Str` | Verbatim tag. |
| `imap_command_name(cmd)` | `Str` | Uppercase command name (`UID FETCH` for UID commands). |
| `imap_command_kind(cmd)` | `Int` | `IMAP_CMD_*` code. |
| `imap_command_is_uid(cmd)` | `Bool` | True when the `UID` prefix was present. |
| `imap_command_consumed(cmd)` | `Int` | Bytes consumed through the terminating CRLF. |
| `imap_command_arg_count(cmd)` | `Int` | Number of top-level arguments. |
| `imap_command_arg_kind(cmd, i)` | `Int` | Kind of top-level argument `i` (0 when absent). |
| `imap_command_arg_text(cmd, i)` | `Str` | Text of top-level argument `i` (`""` when absent). |
| `imap_command_element_count(cmd)` | `Int` | Flat element count (list markers included). |
| `imap_command_element_kind(cmd, i)` | `Int` | `IMAP_ARG_*` of element `i` (or -1). |
| `imap_command_element_text(cmd, i)` | `Str` | Decoded text of element `i` (`""` out of range). |
| `imap_command_element_depth(cmd, i)` | `Int` | List depth of element `i` (top level 0; -1 out of range). |
| `imap_command_element_offset(cmd, i)` | `Int` | Absolute byte offset of element `i` (or -1). |
| `imap_response_kind(resp)` | `Int` | `IMAP_RESPONSE_TAGGED/_UNTAGGED/_CONTINUATION`. |
| `imap_response_tag(resp)` | `Str` | Tag of a tagged completion, else `""`. |
| `imap_response_status(resp)` | `Str` | Uppercase status keyword (`OK`, `FETCH`, ...). |
| `imap_response_number(resp)` | `Int` | Message number of a numbered response, else -1. |
| `imap_response_code(resp)` | `Str` | Response code without brackets; `""` when absent. |
| `imap_response_code_arg_count(resp)` | `Int` | Number of response-code arguments. |
| `imap_response_code_arg(resp, i)` | `Str` | Response-code argument `i` (`""` out of range). |
| `imap_response_text(resp)` | `Str` | Response text; `""` for argument-bearing responses. |
| `imap_response_consumed(resp)` | `Int` | Bytes consumed through the final CRLF. |
| `imap_response_arg_count(resp)` | `Int` | Number of top-level arguments. |
| `imap_response_arg_kind(resp, i)` | `Int` | Kind of top-level argument `i` (0 when absent). |
| `imap_response_arg_text(resp, i)` | `Str` | Text of top-level argument `i` (`""` when absent). |
| `imap_response_element_count(resp)` | `Int` | Flat element count. |
| `imap_response_element_kind(resp, i)` | `Int` | `IMAP_ARG_*` of element `i` (or -1). |
| `imap_response_element_text(resp, i)` | `Str` | Decoded text of element `i` (`""` out of range). |
| `imap_response_element_depth(resp, i)` | `Int` | List depth of element `i` (or -1). |
| `imap_response_element_offset(resp, i)` | `Int` | Absolute byte offset of element `i` (or -1). |

Kind constants: `IMAP_CMD_UNKNOWN` (0) and 1..17 for the commands;
`IMAP_ARG_ATOM` (1), `IMAP_ARG_QUOTED` (2), `IMAP_ARG_LITERAL` (3),
`IMAP_ARG_LITERAL_PLUS` (4), `IMAP_ARG_NIL` (5), `IMAP_ARG_LIST_OPEN` (6),
`IMAP_ARG_LIST_CLOSE` (7); `IMAP_RESPONSE_TAGGED` (1),
`IMAP_RESPONSE_UNTAGGED` (2), `IMAP_RESPONSE_CONTINUATION` (3);
`IMAP_MAX_LITERAL` (2147483647) and `IMAP_MAX_NUMBER` (2147483647).

## Usage

```xi
use xiom.imap;
use xiom.io;
use xiom.convert;

fn main() -> Int {
  // One command; literals may cross line boundaries.
  let c = imap_parse_command("A1 LOGIN {5}\r\nalice {6}\r\nsecret\r\n");
  match c {
    Ok(cmd) => {
      io.println(imap_command_name(&cmd));                  // LOGIN
      io.println(imap_command_arg_text(&cmd, 0));           // alice
      io.println(imap_command_arg_text(&cmd, 1));           // secret
      io.println(convert.int_to_string(imap_command_consumed(&cmd)));
    },
    Err(e) => { io.println(e); },
  }

  // A FETCH response with a response-code-free attribute list and a literal.
  let r = imap_parse_response("* 12 FETCH (FLAGS (\\Seen) BODY[] {5}\r\nhello)\r\n");
  match r {
    Ok(resp) => {
      io.println(imap_response_status(&resp));              // FETCH
      io.println(imap_response_element_text(&resp, 3));     // \Seen
    },
    Err(e) => { io.println(e); },
  }

  // Drain a buffer of several responses one message at a time.
  var stream = "A1 OK done\r\n* 3 EXISTS\r\n* BYE bye\r\n";
  var pos = 0;
  var live = true;
  while live {
    let p = imap_parse_response_at(stream, pos);
    match p {
      Ok(resp) => {
        io.println(imap_response_status(&resp));
        pos = pos + imap_response_consumed(&resp);
        if pos >= stream.len() { live = false; }
      },
      Err(e) => { io.println(e); live = false; },
    }
  }
  return 0;
}
```

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.imap
```

Expected tail: 18 `[PASS]` lines, `xiom.imap: all tests passed`, then
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Parser only**: no command/response building, no sockets, timers, TLS or
  session state machine. Callers own the wire and the
  NOT-AUTHENTICATED/AUTHENTICATED/SELECTED/LOGOUT sequencing and pass one
  command or one response per call.
- **No extensions**: only the RFC 3501 commands listed above; IDLE, STARTTLS,
  AUTHENTICATE, LITERAL+, NAMESPACE, SORT, THREAD, CONDSTORE and every other
  extension command are unknown commands. `LITERAL+` markers parse, but no
  non-synchronizing continuation policy is modelled.
- **Generic extension responses**: an untagged keyword outside the modelled
  set is parsed generically (arguments accepted); numbered responses are
  restricted to `EXISTS`, `RECENT`, `EXPUNGE` and `FETCH`.
- **Opaque payloads**: mailbox names, sequence sets, flags, search keys,
  dates and BODY sections are not semantically validated or decoded; there is
  no modified-UTF-7 or MIME decoding, and 8-bit bytes pass through.
- **Buffer-at-a-time**: a literal that is not yet fully present in the buffer
  is an error, not a `need more data` signal; incremental accumulation is the
  caller's job.
- **Documented leniencies**: one or more spaces separate arguments, leading
  zeros are accepted in numbers (RFC `number = 1*DIGIT`), and trailing spaces
  before CRLF are tolerated. **Documented narrowing**: tags reject `%`, `*`,
  `]` and `+` (RFC 3501 tags allow `]`).
- Errors carry byte offsets for lexical problems; command-shape errors name
  the command and the offset of its name.
- License: MIT OR Apache-2.0 (see the repository root `LICENSE`).
