# xiom.irc

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** an IRC message codec for a documented RFC 1459/2812 subset plus
> IRCv3 message tags: parse and build, prefix nick/user/host split, ASCII
> case-insensitive command comparison, numeric reply formatting/parse, and
> byte-exact wire round-trips. Message text only: no networking, no
> client/server state.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.compare.str_compare`, and
> `xiom.string.builder.sb_push_str`/`sb_push_int`/`sb_to_str`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.irc` turns IRC wire text

```
@+example=raw+:=,escaped\:\s\\ :nick!user@host PRIVMSG #chan :Hello, world!
:irc.example.net 001 nick :Welcome to the network
```

into a flat `IrcMessage` and back. The codec is byte-oriented and stateless:
every function works on `Str` input and returns plain values, so there is no
connection object, no channel state and no global configuration. All
decisions are pinned in `SPEC.md` and locked by the 24-check conformance
suite.

Non-goals: no client/server, no DCC, no channel or user tracking, no CTCP
payload interpretation, no line-length policy and no UTF-8 validation.

## API

Types:

| Type | Fields |
|---|---|
| `IrcMessage` | `tag_names`, `tag_values`, `tag_flags` (index-aligned, `tag_flags[i] == 1` when the tag carried `=value`), `has_prefix`, `prefix`, `nick`, `user`, `host`, `is_server_prefix`, `command`, `params` (middle parameters only), `has_trailing`, `trailing` |
| `IrcPrefix` | `raw`, `nick`, `user`, `host`, `is_server` |

Functions:

| Function | Returns | Description |
|---|---|---|
| `irc_parse(text)` | `Result[IrcMessage, Str]` | Parse one line (tags, prefix, command, middle params, trailing); deterministic `Err("irc: ...")` on malformed input. |
| `irc_parse_prefix(prefix)` | `IrcPrefix` | Split `nick!user@host` / `nick@host` / `nick!user` / `nick` / server name; a leading `:` is accepted and stripped. |
| `irc_render(m)` | `Str` | Wire text with a terminating CRLF; parse/render round-trips are byte-exact for well-formed input. |
| `irc_build(command, params, trailing, has_trailing)` | `Result[Str, Str]` | Build a plain line; validates every part. |
| `irc_build_full(tag_names, tag_values, prefix, command, params, trailing, has_trailing)` | `Result[Str, Str]` | Build a tagged line with an optional prefix; empty tag values render as valueless tags. |
| `irc_build_numeric(prefix, code, params, trailing, has_trailing)` | `Result[Str, Str]` | Build a numeric reply, code zero-padded to three digits. |
| `irc_is_numeric(m)` | `Bool` | True when the command is exactly three ASCII digits. |
| `irc_numeric_code(m)` | `Result[Int, Str]` | `"001"` -> `1`, `"433"` -> `433`; `Err("irc: not a numeric reply")` otherwise. |
| `irc_eq_ci(a, b)` | `Bool` | ASCII case-insensitive equality (uppercase mapping + integer byte compare). |
| `irc_command_is(m, want)` | `Bool` | Case-insensitive command comparison. |
| `irc_has_tags(m)` | `Bool` | Whether the message carries tags. |
| `irc_tag_count(m)` | `Int` | Number of tags. |
| `irc_tag_name(m, i)` | `Str` | Name of tag `i` (case-sensitive); `""` out of range. |
| `irc_tag_value(m, i)` | `Str` | Decoded value of tag `i`; `""` for a valueless tag or out of range. |
| `irc_tag_has_value(m, i)` | `Bool` | Whether tag `i` was written as `key=value` (even empty). |
| `irc_tag(m, name)` | `Option[Str]` | Value of the final occurrence of `name` (duplicates: last wins); `None` when absent. |
| `irc_param_count(m)` | `Int` | Number of middle parameters (trailing not counted). |
| `irc_param(m, i)` | `Str` | Middle parameter `i`; `""` out of range. |

## Quick start

```xi
use xiom.irc;
use xiom.io;

fn main() -> Int {
  let line = ":nick!user@host PRIVMSG #chan :Hello, world!";
  let r = irc_parse(line);
  match r {
    Ok(m) => {
      io.println(m.nick);            // nick
      io.println(m.user);            // user
      io.println(irc_param(&m, 0));  // #chan
      io.println(m.trailing);        // Hello, world!
      if irc_command_is(&m, "privmsg") {
        io.println(irc_render(&m));  // the line again, with CRLF
      }
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

Building a numeric reply:

```xi
use xiom.irc;
use xiom.io;

fn main() -> Int {
  var params = Vec[Str].new();
  params.push("nick");
  match irc_build_numeric("irc.example.net", 1, params, "Welcome to the network", true) {
    Ok(line) => { io.println(line); },   // :irc.example.net 001 nick :Welcome to the network
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

## Error model

Every fallible entry point returns `Err(Str)` whose message starts with
`irc: ` and is deterministic (no line numbers, no hidden state). Parse
errors are `irc: empty message`, `irc: empty tags`, `irc: missing command`
and `irc: empty prefix`; build errors name the offending part, e.g.
`irc: invalid parameter: a b`. The full catalog is in `SPEC.md` section 8.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.irc
```

Expected tail: 24 `[PASS]` lines, `xiom.irc: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Message text only:** parsing, building and round-trips; there is no
  socket layer, no reconnect/queue logic, and no channel/user/mode state.
- **Documented subset, structural only:** the grammar is enforced, but no
  command-specific validation (parameter counts, target syntax) is performed,
  and ISUPPORT/CTCP payloads are not interpreted.
- **Single line:** `irc_parse` expects one message; it truncates the input at
  the first CR/LF and ignores the remainder. Stream buffering and message
  framing are the caller's job.
- **Lenient parse:** the RFC 2812 limit of 14 middle parameters is not
  enforced, prefix and command contents are stored verbatim, and an empty tag
  key (`@=v`) is accepted (the IRCv3 spec forbids rejecting a message over an
  invalid key name).
- **No size limits:** the 512-byte message / 8191-byte tag limits are not
  checked or enforced; callers own any length policy.
- **ASCII only:** case folding covers `A`..`Z` only (no RFC 1459
  `[]\~` <-> `{}|^` casemapping), and tag values are opaque bytes -- UTF-8 is
  neither validated nor normalized.
- **Tag normalization:** empty values and valueless tags are distinguished on
  parse (`irc_tag_has_value`), but `irc_build_full` renders an empty value as
  a valueless tag, as the message-tags specification allows.
- **No escaping for other contexts:** CTCP quoting, `\r`/`\n` inside middle
  parameters and message-length escaping are out of scope.

See `SPEC.md` for the exact grammar, parsing decisions, API contract, error
catalog and test matrix. License: MIT OR Apache-2.0 (see the repository root
`LICENSE`).
