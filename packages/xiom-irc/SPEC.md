# xiom.irc -- specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.irc` (`src/irc.xi`). Pure XIOM, no FFI, no I/O.

## 1. Scope and model

A small, dependency-free codec for the IRC message format: the RFC 1459/2812
message grammar (section 2.3.1 of RFC 2812) extended by the IRCv3
message-tags specification. It provides:

- `irc_parse` -- wire text -> `Result[IrcMessage, Str]`,
- `irc_parse_prefix` -- prefix text -> `IrcPrefix` (nick/user/host split),
- `irc_render` -- `IrcMessage` -> wire text,
- `irc_build`, `irc_build_full`, `irc_build_numeric` -- wire text from parts,
- `irc_is_numeric`, `irc_numeric_code` -- numeric reply handling,
- `irc_eq_ci`, `irc_command_is` -- ASCII case-insensitive command comparison,
- tag and parameter accessors (section 9).

Everything is byte-oriented and stateless: nothing allocates a connection
object, every function works on `Str` input, and malformed text yields a
deterministic `Err` or an empty value, never a crash. Non-goals: networking,
client/server state, channel/user tracking, DCC, CTCP payload interpretation,
line-length policy and UTF-8 validation.

## 2. Data model

```xi
pub type IrcMessage = {
  tag_names: Vec[Str];   // tag keys, wire order, verbatim (case-sensitive)
  tag_values: Vec[Str];  // decoded values, index-aligned with tag_names
  tag_flags: Vec[Int];   // 1 when the tag carried "=value", else 0
  has_prefix: Bool;      // true when the line carried ":" prefix
  prefix: Str;           // prefix text without ':' ("" when absent)
  nick: Str;             // split prefix parts ("" when absent)
  user: Str;
  host: Str;
  is_server_prefix: Bool; // true when the prefix had no '!' and no '@'
  command: Str;          // verbatim; case preserved
  params: Vec[Str];      // middle parameters only, wire order
  has_trailing: Bool;    // distinguishes "CMD :" from "CMD"
  trailing: Str;         // trailing text ("" when has_trailing is false)
}

pub type IrcPrefix = {
  raw: Str;      // prefix text without a leading ':'
  nick: Str;     // nick (or the whole server name)
  user: Str;
  host: Str;
  is_server: Bool;
}
```

Invariants (maintained by every constructor in the module): the three tag
vectors have equal length; `has_prefix` implies `prefix != ""`; `params`
never contains the trailing text. `Vec[StructType]` is unsupported in this
compiler, so the message is flat (parallel homogeneous vectors) instead of a
list of tag structs.

## 3. Message grammar

```
message    = [ tags SP ] [ ":" prefix SP ] command [ SP middle ]* [ SP ":" trailing ] [ break ]
tags       = "@" tag *(";" tag)
tag        = key [ "=" escaped ]
key        = *( byte except ";" / "=" / SP / CR / LF )     ; verbatim, may be empty
escaped    = *( byte except ";" / SP / CR / LF )           ; ';' is the separator
prefix     = *( byte except SP / CR / LF )
command    = 1*( byte except SP / CR / LF )
middle     = 1*( byte except SP / CR / LF )                ; no leading ':'
trailing   = *( byte except CR / LF )
break      = CRLF / LF / CR
```

All lengths are byte lengths; `Str` is treated as a UTF-8 byte buffer and the
codec never rewrites multi-byte sequences.

## 4. Parsing decisions (`irc_parse`)

Each decision below is covered by the conformance suite.

1. **Single line.** The input is truncated at the first CR or LF; anything
   after it is ignored. A terminator is optional, so `"PING"`, `"PING\n"`,
   `"PING\r"` and `"PING\r\n"` all parse as `PING`. Text after the
   terminator (`"PING\r\nJUNK"`) is not parsed.
2. **Empty input.** A line holding no non-space byte (empty, spaces, CRLF)
   is `Err("irc: empty message")`.
3. **Leading spaces.** Spaces before the tag section, prefix and command are
   skipped. Whitespace is not allowed inside the tag section (a space always
   ends it).
4. **Tags.** A section starting with `@` runs to the next space (or to the
   end of the line, which is then `Err("irc: missing command")`). The
   section must hold at least one non-empty tag segment, else
   `Err("irc: empty tags")`. Empty segments between `;` are skipped
   (`"@a=1;"` has one tag).
5. **Tag split.** A segment is split at its first `=` into key and raw
   value; a segment without `=` is a valueless tag. Keys are stored verbatim
   (any byte except the separators), including the empty key of `"@=v"` --
   the message-tags specification requires not rejecting a message over an
   invalid key name. Raw values are decoded per section 5.
6. **Prefix.** After the tags, a byte `:` starts the prefix, which runs to
   the next space. An empty prefix (`":"`, `": CMD"`) is
   `Err("irc: empty prefix")`. Prefix bytes are stored verbatim; `nick`,
   `user` and `host` come from the split of section 6. No command after the
   prefix is `Err("irc: missing command")`.
7. **Command.** The next non-space token, stored verbatim (case preserved,
   no validation on parse). Since a non-space byte is required at this point,
   the command is never empty; a missing command is
   `Err("irc: missing command")`.
8. **Middle parameters and trailing.** The rest of the line is tokenized on
   one or more spaces. A token whose first byte is `:` starts the trailing
   text: the trailing is everything after that `:` to the end of the line
   (spaces and further colons included), and parsing stops. `"CMD ::x"` has
   trailing `":x"`. Otherwise the token is a middle parameter, which may
   contain `:` in any non-initial position (`"CMD a:b"` -> `a:b`).
9. **Trailing presence.** `"CMD"` has no trailing; `"CMD :"` has an empty
   trailing; `"CMD :x"` has trailing `x`. `has_trailing` records the
   difference.
10. **Parameter count.** No upper limit is enforced (RFC 2812 says 14; the
    stricter limit is left to callers).

## 5. IRCv3 message tags

The tag section follows the IRCv3 message-tags specification:

- **Escapes** (decode on parse, encode on render):

  | Wire | Decoded |
  |---|---|
  | `\:` | `;` (59) |
  | `\s` | space (32) |
  | `\\` | `\` (92) |
  | `\r` | CR (13) |
  | `\n` | LF (10) |
  | `\x` (any other x) | `x` -- the backslash is dropped |

  A lone backslash at the end of an escaped value is dropped
  (`"@k=test\\"` -> value `test`).
- **Empty vs missing values.** `@k` (valueless) and `@k=` (empty) are stored
  distinctly in `tag_flags`; both are queried as `""`. The specification
  treats them as equivalent and permits normalising empty to missing, so
  `irc_build_full` renders an empty value as a valueless tag while
  `irc_render` preserves the parsed form.
- **Duplicates.** Repeated keys are preserved in wire order; `irc_tag`
  returns the final occurrence, as the specification says all but the last
  duplicate should be disregarded.
- **Case.** Tag names are case-sensitive opaque identifiers; lookups compare
  bytes exactly.
- **Values.** Decoded value bytes are not UTF-8 validated and may contain
  CR/LF (they were escaped on the wire). Rendering re-escapes `;`, space,
  `\`, CR and LF and passes every other byte through.

## 6. Prefix split (`irc_parse_prefix`)

A leading `:` is stripped; `raw` is the remainder. Let `!` be the first `!`
and `@` the first `@` (either may be absent):

| Shape | nick | user | host | is_server |
|---|---|---|---|---|
| `nick!user@host` | `nick` | `user` | `host` | false |
| `nick!user` | `nick` | `user` | `""` | false |
| `nick@host` | `nick` | `""` | `host` | false |
| `nick` | `nick` | `""` | `""` | true |
| `""` | `""` | `""` | `""` | false |

Rules: when both `!` and `@` exist, the `!` splits user only if it comes
before the `@`; when the `@` comes first (or is the only marker), everything
after it is the host (so `nick@host!user` has host `host!user`). A prefix
with neither marker is a server name: `is_server` is true and `nick` holds
the whole text. Parts may be empty (`!user@host` has nick `""`); no prefix
character validation is performed on parse.

## 7. Building (`irc_build`, `irc_build_full`, `irc_build_numeric`)

`irc_build(command, params, trailing, has_trailing)` equals
`irc_build_full` with no tags and no prefix. `irc_build_full` validates in
this fixed order and returns the first failure:

1. `tag_names.len() == tag_values.len()`, else
   `Err("irc: tag name/value count mismatch")`.
2. Each tag name: non-empty and free of space, `;`, `=` and CR/LF (the IRCv3
   key grammar is not otherwise enforced), else `Err("irc: empty tag name")`
   / `Err("irc: invalid tag name: <name>")`.
3. Prefix: `""` means no prefix; otherwise no space/CR/LF, else
   `Err("irc: invalid prefix: <prefix>")`.
4. Command: non-empty run of ASCII letters/digits, else
   `Err("irc: empty command")` / `Err("irc: invalid command: <command>")`.
5. Middle parameters: non-empty, no space/CR/LF and no leading `:`, else
   `Err("irc: empty parameter")` / `Err("irc: invalid parameter: <param>")`.
6. Trailing (only when `has_trailing`): no CR/LF (spaces and `:` are legal),
   else `Err("irc: trailing contains a line break")`.

On success the rendered line is `[tags SP] [':' prefix SP] command
[ SP param]* [ SP ':' trailing] CRLF`, where a tag renders as `key`,
`key=value` or `key=` (empty values render valueless, section 5) and the
value is escaped. Building is the only place input validation happens; the
parser is deliberately lenient.

`irc_build_numeric(prefix, code, ...)` rejects `code < 0 || code > 999` with
`Err("irc: invalid numeric code: <code>")` and otherwise builds the command
as exactly three zero-padded digits (`1` -> `"001"`, `0` -> `"000"`).

## 8. Numeric replies

- `irc_is_numeric(m)` is true when `m.command` is exactly three ASCII
  digits; `"12"`, `"1234"` and `"12a"` are false.
- `irc_numeric_code(m)` returns `Ok(code)` with `code = 100*h + 10*t + u`
  (`"001"` -> 1, `"433"` -> 433), or
  `Err("irc: not a numeric reply")` when `irc_is_numeric` is false.
- Formatting goes through `irc_build_numeric`, so reply lines such as
  `":irc.example.net 001 nick :Welcome to the network"` carry the usual
  server prefix, three-digit code and trailing text.

## 9. API contract

```xi
pub fn irc_parse(text: Str) -> Result[IrcMessage, Str]
pub fn irc_parse_prefix(prefix: Str) -> IrcPrefix
pub fn irc_render(m: &IrcMessage) -> Str
pub fn irc_build(command: Str, params: Vec[Str], trailing: Str, has_trailing: Bool) -> Result[Str, Str]
pub fn irc_build_full(tag_names: Vec[Str], tag_values: Vec[Str], prefix: Str, command: Str, params: Vec[Str], trailing: Str, has_trailing: Bool) -> Result[Str, Str]
pub fn irc_build_numeric(prefix: Str, code: Int, params: Vec[Str], trailing: Str, has_trailing: Bool) -> Result[Str, Str]
pub fn irc_is_numeric(m: &IrcMessage) -> Bool
pub fn irc_numeric_code(m: &IrcMessage) -> Result[Int, Str]
pub fn irc_eq_ci(a: Str, b: Str) -> Bool
pub fn irc_command_is(m: &IrcMessage, want: Str) -> Bool
pub fn irc_has_tags(m: &IrcMessage) -> Bool
pub fn irc_tag_count(m: &IrcMessage) -> Int
pub fn irc_tag_name(m: &IrcMessage, i: Int) -> Str
pub fn irc_tag_value(m: &IrcMessage, i: Int) -> Str
pub fn irc_tag_has_value(m: &IrcMessage, i: Int) -> Bool
pub fn irc_tag(m: &IrcMessage, name: Str) -> Option[Str]
pub fn irc_param_count(m: &IrcMessage) -> Int
pub fn irc_param(m: &IrcMessage, i: Int) -> Str
```

Accessor semantics:

- `irc_tag_name` / `irc_tag_value` / `irc_param` return `""` for a negative
  or past-the-end index; `irc_tag_has_value` returns `false` there.
- `irc_tag(m, name)` returns the last occurrence's decoded value
  (`Some("")` for a valueless or empty tag) and `None` when absent.
- `irc_eq_ci` compares lengths first (integer), then maps `a`..`z` to
  `A`..`Z` byte-wise and compares integers. It is the command helper and
  never compares `Str` values from a `Vec`.
- `irc_render` assumes the `IrcMessage` invariants; it is total for values
  produced by `irc_parse` and the build functions.

Round-trip property: for any well-formed line `L` accepted by `irc_parse`,
`irc_render(irc_parse(L)) == L + CRLF`, and parsing that result yields the
same tags/prefix/command/params/trailing. Escaped values are canonicalised
(unknown escapes and lone trailing backslashes lose the backslash), so the
equality holds for canonical input; test t23/t24 pin both directions.

## 10. Error catalog

All failures are `Err(msg)` with `msg` starting with `"irc: "`. Errors are
deterministic and carry the offending text where noted.

| Message | Function | Trigger |
|---|---|---|
| `irc: empty message` | `irc_parse` | no non-space byte before the first CR/LF (empty text, spaces, CRLF) |
| `irc: empty tags` | `irc_parse` | a `@` section with no non-empty tag segment (`"@ CMD"`, `"@; CMD"`) |
| `irc: missing command` | `irc_parse` | tags or prefix present but no command token (`":nick"`, `"@a=1"`, `"@a=1 :nick"`) |
| `irc: empty prefix` | `irc_parse` | `:` with no prefix text before the next space (`":"`, `": CMD"`) |
| `irc: empty command` | build | `command == ""` |
| `irc: invalid command: <command>` | build | non-alphanumeric byte in the command |
| `irc: empty parameter` | build | an empty middle parameter |
| `irc: invalid parameter: <param>` | build | space, CR, LF or leading `:` in a middle parameter |
| `irc: trailing contains a line break` | build | CR or LF in the trailing text |
| `irc: invalid prefix: <prefix>` | build | space, CR or LF in the prefix |
| `irc: empty tag name` | build | empty tag name |
| `irc: invalid tag name: <name>` | build | space, `;`, `=` or CR/LF in a tag name |
| `irc: tag name/value count mismatch` | build | `tag_names.len() != tag_values.len()` |
| `irc: invalid numeric code: <code>` | `irc_build_numeric` | `code < 0` or `code > 999` |
| `irc: not a numeric reply` | `irc_numeric_code` | command is not exactly three ASCII digits |

Parse never fails on tag key/value content (invalid keys are accepted
verbatim) and never validates prefix/command/parameter bytes.

## 11. Test matrix (`tests/test_conformance.xi`, 24 checks)

| # | Check | Semantics pinned |
|---|---|---|
| t1 | simple message | prefix split, one middle param, trailing, render round-trip |
| t2 | command +/- trailing | `PING` vs `PING :token`; rendering |
| t3 | 005 numeric | three middle params (`MODE=+i`), sentence trailing |
| t4 | colons | `:` inside middle params, trailing after `:`, `::x`, spaces in trailing |
| t5 | empty trailing | `TOPIC #chan :` keeps `has_trailing` and renders the bare `:` |
| t6 | prefix split | `nick!user@host`, `nick@host`, `nick!user`, `nick`, leading `:`, empty |
| t7 | server prefix | `is_server_prefix`, whole-name `nick`, command comparison |
| t8 | IRCv3 example | three tags (valued, valueless, vendor), case-sensitive lookup, render |
| t9 | escapes | `\s` `\:` `\\` `\r` `\n` decode and re-encode; explicit empty value `@k=` |
| t10 | invalid escapes | `\b` -> `b`; lone trailing backslash dropped; canonical render |
| t11 | duplicate keys | order preserved; `irc_tag` returns the last value |
| t12 | tag-section edges | empty section errors, empty segments skipped, `@=v`, leading spaces |
| t13 | empty/missing | empty message, missing command after tags/prefix, `"@a=1 :nick"` |
| t14 | empty prefix | `": CMD"` and `":"` errors |
| t15 | line endings | CRLF/LF/CR accepted; text after the first break ignored; trailing kept |
| t16 | build | params, absent trailing, empty trailing, several params, CRLF |
| t17 | build_full | tags + prefix render and re-parse; empty value -> valueless tag |
| t18 | build errors | full error catalog pins, including count mismatch and prefix/tag names |
| t19 | numerics | `001`/`433`/`000` formatting, out-of-range codes, code parsing |
| t20 | numeric detection | `001`, `007`, `PING`, `12`, `1234`, `12a` |
| t21 | command compare | case-insensitivity, length mismatch, non-letter bytes (`[` vs `{`) |
| t22 | params | out-of-range `""`, 15 middle params, trailing after them |
| t23 | round-trips | byte-exact parse/render for prefix/tags/colon/trailing corpus |
| t24 | escape stability | re-parse keeps decoded values; `@a;b=` form survives |

Element comparisons in the suite go through `xiom.string.compare`'s
`str_compare`, never `==` (BUG 17).

## 12. Compiler / stdlib notes (XIOM v0.61.3)

- Free functions only -- no self methods, no lambdas, no `Vec[StructType]`,
  no `Vec[fn]` dispatch, no `Vec[Float64]`.
- `Str` values are never compared with `==` when read from a `Vec[Str]`
  element (BUG 17 lowers that to a pointer comparison); tag lookups use
  `str_compare` and every `Vec` element read is bound with a typed `let`.
- `byte_at` results are widened with `as Int` before arithmetic; commands
  are compared with the uppercase-mapping helper `irc_eq_ci`.
- Output bytes are collected in a `Vec[UInt8]` and materialized with
  `xiom.string.builder.sb_to_str`.
- `Ok`/`Err` are constructed only in the tiny leaf helpers (`_ok_msg`,
  `_err_msg`, `_ok_str`, `_err_str`, `_ok_int`, `_err_int`).
- The parser owns its scanning loop; the read-only API borrows `&IrcMessage`
  and the renderer pushes into a local builder through
  `_push_message(&mut Vec[UInt8], &IrcMessage)`.
- Tests dispatch directly (`t1()` ... `t24()`), with no match pattern
  binding `mut` and every `match` exhaustive.

## 13. Non-goals and limitations

- **No networking or state:** no sockets, no client/server objects, no
  channel/user/mode tracking, no DCC.
- **Structural codec only:** no command-specific validation or semantics
  (parameter counts, target syntax, ISUPPORT tokens, CTCP bodies).
- **Single line:** the caller buffers input and frames messages; `irc_parse`
  truncates at the first CR/LF.
- **Lenient parse:** command, prefix and middle-parameter contents are stored
  verbatim; the 14-parameter RFC 2812 limit is not enforced; empty tag keys
  are accepted (section 5).
- **No size limits:** 512-byte messages and 8191-byte tag sections are not
  checked.
- **ASCII only:** case folding is `A`..`Z` (no RFC 1459 casemapping), and
  tag values are opaque bytes without UTF-8 validation.
- **No canonicalization of unknown escapes:** the parser drops the
  backslash of an unknown escape (per the message-tags specification), so
  parse -> render is byte-exact only for canonical input.
