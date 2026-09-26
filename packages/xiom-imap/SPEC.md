# xiom.imap -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.imap` (`src/imap.xi`). Pure XIOM, no FFI, no file or socket I/O.

This document is the normative description of the `xiom.imap` parser: the
data model, the implemented command and response grammars, literal handling,
response codes, the error catalog and the test plan. Reference: RFC 3501
(INTERNET MESSAGE ACCESS PROTOCOL - VERSION 4rev1), the only IMAP revision
modelled. Everything below describes what is *actually implemented*,
including the documented leniencies and narrowings.

## 1. Scope

`xiom.imap` parses one message at a time out of a caller-owned `Str` buffer
and reports the bytes consumed, so a buffer holding several messages can be
drained with repeated parse calls:

- **commands**: `CAPABILITY`, `NOOP`, `LOGOUT`, `LOGIN`, `SELECT`,
  `EXAMINE`, `CREATE`, `DELETE`, `RENAME`, `LIST`, `STATUS`, `FETCH`,
  `STORE`, `SEARCH`, `APPEND`, `CLOSE`, `EXPUNGE`, plus `UID FETCH`,
  `UID STORE` and `UID SEARCH`;
- **arguments**: atoms, quoted strings (with `\\` and `\"` escapes),
  `{n}` and `{n+}` literals (whose content may contain CRLF and therefore
  extends the message across lines), `NIL` (case-insensitive) and nested
  parenthesized lists;
- **responses**: tagged completions, untagged responses (text-bearing
  `OK`/`NO`/`BAD`/`BYE`/`PREAUTH`, argument-bearing `CAPABILITY`, `FLAGS`,
  `SEARCH`, `LIST`, `LSUB`, `STATUS`, and numbered
  `EXISTS`/`RECENT`/`EXPUNGE`/`FETCH` including FETCH attribute lists with
  flags and multi-line literals) and continuation requests;
- **response codes**: bracketed `[CODE args]` text exposed as an uppercased
  code plus flattened arguments.

The module does **not** build any wire text, and it contains no sockets,
TLS/STARTTLS, AUTHENTICATE/SASL, IDLE, sequence-set expansion, search-key
evaluation, flag semantics, mailbox hierarchy logic, charset translation or
session state machine. It is a parser, not a client or server.

## 2. Constants

| Name | Value | Meaning |
|---|---|---|
| `IMAP_CMD_UNKNOWN` | 0 | unmodelled or unrecognized command name |
| `IMAP_CMD_CAPABILITY` .. `IMAP_CMD_EXPUNGE` | 1..17 | command kinds in the order listed in section 1 |
| `IMAP_ARG_ATOM` | 1 | atom argument element |
| `IMAP_ARG_QUOTED` | 2 | quoted-string argument element |
| `IMAP_ARG_LITERAL` | 3 | synchronizing `{n}` literal element |
| `IMAP_ARG_LITERAL_PLUS` | 4 | non-synchronizing `{n+}` literal element |
| `IMAP_ARG_NIL` | 5 | `NIL` element (text keeps the wire spelling) |
| `IMAP_ARG_LIST_OPEN` | 6 | `(` list-open marker |
| `IMAP_ARG_LIST_CLOSE` | 7 | `)` list-close marker |
| `IMAP_RESPONSE_TAGGED` | 1 | `tag OK/NO/BAD ...` |
| `IMAP_RESPONSE_UNTAGGED` | 2 | `* ...` |
| `IMAP_RESPONSE_CONTINUATION` | 3 | `+ ...` |
| `IMAP_MAX_LITERAL` | 2147483647 | largest accepted literal size (2^31-1) |
| `IMAP_MAX_NUMBER` | 2147483647 | largest accepted `* n ...` message number |

`IMAP_CMD_UNKNOWN` is never returned in a successful parse: an unrecognized
command name is an error. It exists as the kind sentinel.

## 3. Data model

```xi
pub type ImapCommand = {
  tag: Str;           // verbatim tag
  name: Str;          // canonical uppercase name ("UID FETCH" for UID commands)
  kind: Int;          // IMAP_CMD_*
  uid: Bool;          // true when the UID prefix was present
  consumed: Int;      // bytes from the parse start through the terminating CRLF
  kinds: Vec[Int];    // IMAP_ARG_* per element, in wire order
  texts: Vec[Str];    // decoded text per element ("" for list markers)
  depths: Vec[Int];   // list depth per element (top level 0)
  offsets: Vec[Int];  // absolute byte offset per element in the caller's buffer
}

pub type ImapResponse = {
  kind: Int;          // IMAP_RESPONSE_*
  tag: Str;           // tagged: the tag; otherwise ""
  status: Str;        // tagged: OK/NO/BAD; untagged: the keyword; continuation: ""
  number: Int;        // message number of a numbered response, -1 when absent
  code: Str;          // response code without brackets, uppercase, "" when absent
  code_args: Vec[Str];// flattened response-code arguments
  text: Str;          // text after status/code for text-bearing forms, else ""
  consumed: Int;      // bytes from the parse start through the final CRLF
  kinds: Vec[Int];    // argument elements (empty for text-bearing forms)
  texts: Vec[Str];
  depths: Vec[Int];
  offsets: Vec[Int];
}
```

Invariants:

1. `kinds.len() == texts.len() == depths.len() == offsets.len()` for every
   parsed command and response; the four columns are pushed in lockstep by a
   single scanner loop, so they can never drift.
2. A parenthesized list is the sequence `LIST_OPEN` at depth `d`, its
   children (and nested lists) at depth `d + 1`, then `LIST_CLOSE` at depth
   `d`. A top-level list is one top-level argument: `arg_count` counts
   depth-0 elements other than `LIST_CLOSE`.
3. `consumed` counts from the `pos` passed to the `_at` function (usually 0),
   through the CRLF that terminates the message; literal content bytes and
   the CRLFs inside them are included.
4. `offsets[i]` is absolute in the caller's buffer (not relative to `pos`).
5. `texts[i]` for a quoted string or literal is the decoded content; for an
   atom the verbatim bytes; for `NIL` the wire spelling (`NIL`, `nil`, ...);
   for list markers the empty string.
6. A tagged/untagged text-bearing response carries its whole tail in `text`
   (after the optional code), and its element columns are empty. An
   argument-bearing response carries its arguments in the element columns and
   leaves `text` empty.

`Vec[StructType]` is unsupported in this compiler, so a parsed message is one
flat record with parallel `Vec`s instead of a tree of per-argument structs.

## 4. Command grammar and rules

```
command      = tag SP command-name [ SP arguments ] CRLF
tag          = 1*( printable byte except SP and the tag specials
                   "*" / "+" / "%" / "]" / "(" / ")" / "{" )
command-name = 1*( byte except SP / CR / LF / "(" / ")" / "{" )    ; upper-cased
uid-command  = "UID" SP ( "FETCH" / "STORE" / "SEARCH" )
arguments    = argument *( 1*SP argument )
argument     = atom / "NIL" / quoted / literal / "(" [ arguments ] ")"
atom         = 1*( %x21-7E / %x80-FF )   ; stops at SP, CR, LF, "(", ")", "{"
quoted       = DQUOTE *( %x20-7E except DQUOTE or "\" /
                         "\" ( "\" / DQUOTE ) ) DQUOTE
literal      = "{" 1*DIGIT [ "+" ] "}" CRLF *OCTET
```

Rules, all pinned by the conformance suite:

1. **Tag.** Scanned as an atom, then validated: no control byte and no tag
   special. Empty, `*`, `+`, `A]1` and similar are
   `imap: bad tag at byte N`. The tag is kept verbatim; only the command
   name is case-folded.
2. **Command name.** Matched case-insensitively at full length against the
   modelled names. `UID` must be followed by `FETCH`, `STORE` or `SEARCH`
   (anything else is `unknown command`); a UID command stores `name` as
   `"UID <SUB>"`, shares the base command's `kind` and sets `uid = true`.
3. **Separators.** One or more spaces separate the tag, the command name and
   each argument; runs of spaces are accepted (documented leniency). A
   trailing run of spaces before CRLF is tolerated.
4. **Atoms.** Control bytes (0x00-0x1F and 0x7F) are rejected; 8-bit bytes
   are opaque data. `NIL` (any case) becomes `IMAP_ARG_NIL`; every other
   atom is `IMAP_ARG_ATOM`.
5. **Quoted strings.** The only escapes are `\\` and `\"`. An unterminated
   string, a CR, an LF, a control byte inside, or a backslash followed by
   anything else is an error. Spaces are literal content.
6. **Literals.** `{n}` and `{n+}` must be followed immediately by CRLF; the
   next exactly `n` bytes are the content, taken verbatim (CR, LF, NUL-free
   or not). `n` is 1..10 digits (leading zeros accepted, RFC
   `number = 1*DIGIT`), at most `IMAP_MAX_LITERAL`; a missing `}` or a
   non-digit size is `bad literal size`; a size above the cap is
   `literal size exceeds the limit`; a literal that does not fit in the
   remaining buffer is `literal of <n> bytes does not fit`. After a literal,
   the next element must be separated by a space, or be `)` or the line end:
   a token or `(` directly after a literal is
   `literal not followed by a separator`. `{n+}` produces
   `IMAP_ARG_LITERAL_PLUS`; `{n}` produces `IMAP_ARG_LITERAL`.
7. **Lists.** Nesting is tracked with a depth counter; the scanner is
   iterative, not recursive. A `)` at depth 0 is
   `unexpected closing parenthesis`; a CRLF (or buffer end) while the depth
   is above 0 is `unbalanced parentheses`.
8. **Line ending.** Every line ends with exactly CRLF. A lone LF is
   `bare LF`; a CR not followed by LF is `bare CR`; a buffer that ends
   without CRLF is `missing CRLF at byte <len>`.
9. **Offsets.** Every lexical error message ends with `at byte N` (an
   absolute offset). Command-shape errors name the command and the offset of
   its name.
10. **Shape table.** Only structure is validated; the contents of sequence
    sets, mailboxes, flags, search keys and dates are opaque.

    | Command | Required top-level shape |
    |---|---|
    | `CAPABILITY`, `NOOP`, `LOGOUT`, `CLOSE`, `EXPUNGE` | no arguments |
    | `LOGIN` | exactly 2 string arguments |
    | `SELECT`, `EXAMINE`, `CREATE`, `DELETE` | exactly 1 string mailbox |
    | `RENAME` | exactly 2 string mailboxes |
    | `LIST` | reference (string or `NIL`) + pattern (string) |
    | `STATUS` | mailbox (string) + non-empty parenthesized item list |
    | `FETCH` / `UID FETCH` | sequence set (string) + (non-empty parenthesized attribute list or one string attribute) |
    | `STORE` / `UID STORE` | sequence set (string) + atom item name `FLAGS` / `+FLAGS` / `-FLAGS` (case-insensitive) + optional flag list (parenthesized list or one string) |
    | `SEARCH` / `UID SEARCH` | at least 1 criterion |
    | `APPEND` | mailbox (string) + optional flag list (parenthesized) + optional quoted date-time + a message literal (`{n}` or `{n+}`); 2..4 arguments, last is the literal |

## 5. Response grammar and rules

```
response      = tagged / untagged / continuation
tagged        = tag SP ( "OK" / "NO" / "BAD" ) [ resp-text ] CRLF
untagged      = "*" SP ( number SP numbered-name / name ) tail CRLF
numbered-name = "EXISTS" / "RECENT" / "EXPUNGE" / "FETCH"
name          = atom
tail          = resp-text                       ; for OK / NO / BAD / BYE / PREAUTH
              / [ arguments ]                   ; for name-bearing forms
continuation  = "+" ( SP resp-text / "" ) CRLF
resp-text     = [ "[" code-word [ arguments ] "]" 1*SP ] *TEXT
```

1. **Tagged completions.** `tag SP OK/NO/BAD` with any case (status is
   canonicalized to uppercase); any other status is
   `bad tagged response status`. `[code]` and text follow the same rules as
   below.
2. **Untagged.** After `* `, a leading atom of digits is the message number
   (1..10 digits, at most `IMAP_MAX_NUMBER`): it is required for `EXISTS`,
   `RECENT`, `EXPUNGE` and `FETCH` and rejected for every other keyword
   (`message number required` / `unexpected message number`). The keyword is
   canonicalized to uppercase.
3. **Text-bearing keywords.** `OK`, `NO`, `BAD`, `BYE` and `PREAUTH` take an
   optional bracketed code and then the response text verbatim up to CRLF;
   they carry no argument elements. Text may be empty, and may contain any
   byte except CR and LF.
4. **Argument-bearing keywords.** `CAPABILITY`, `FLAGS`, `SEARCH`, `LIST`,
   `LSUB`, `STATUS` and numbered `EXISTS`/`RECENT`/`EXPUNGE`/`FETCH` parse
   their arguments with the command argument grammar. Additionally:
   `EXISTS`/`RECENT`/`EXPUNGE` must carry no arguments; `FETCH` must carry a
   parenthesized attribute list as its first argument; `FLAGS` must carry
   exactly one list; `LIST`/`LSUB` must carry a list, a string-or-`NIL`
   delimiter and a string; `STATUS` must carry a string mailbox and a list
   with an even child count of at least 2 name/value tokens.
   `CAPABILITY`, `SEARCH` and unknown (extension) keywords are accepted
   generically.
5. **Continuations.** `+` alone, `+ SP` with empty text, or `+ SP text`;
   `+x` is `bad continuation response`. An optional `[code]` is recognized
   the same way as in `resp-text`.
6. **Response codes.** A code is exposed as the uppercase code word plus its
   arguments flattened to text: list parentheses are dropped and quoted
   strings are unescaped, so `[PERMANENTFLAGS (\Seen \Deleted)]` yields code
   `PERMANENTFLAGS` with arguments `\Seen`, `\Deleted`, and
   `[UIDVALIDITY 123]` yields argument `123`. An empty `[]`, an unterminated
   `[`, or a code whose first token is not an atom is
   `bad response code` / `unterminated response code`.
7. **Consumed.** `consumed` always ends at the terminating CRLF of the
   response. For a FETCH response with a literal, that is after the closing
   `)` on a later line: literals make responses multi-line.

## 6. API signatures

```xi
// Commands
pub fn imap_parse_command(buf: Str) -> Result[ImapCommand, Str]
pub fn imap_parse_command_at(buf: Str, pos: Int) -> Result[ImapCommand, Str]
pub fn imap_command_tag(cmd: &ImapCommand) -> Str
pub fn imap_command_name(cmd: &ImapCommand) -> Str
pub fn imap_command_kind(cmd: &ImapCommand) -> Int
pub fn imap_command_is_uid(cmd: &ImapCommand) -> Bool
pub fn imap_command_consumed(cmd: &ImapCommand) -> Int
pub fn imap_command_arg_count(cmd: &ImapCommand) -> Int
pub fn imap_command_arg_kind(cmd: &ImapCommand, index: Int) -> Int
pub fn imap_command_arg_text(cmd: &ImapCommand, index: Int) -> Str
pub fn imap_command_element_count(cmd: &ImapCommand) -> Int
pub fn imap_command_element_kind(cmd: &ImapCommand, index: Int) -> Int
pub fn imap_command_element_text(cmd: &ImapCommand, index: Int) -> Str
pub fn imap_command_element_depth(cmd: &ImapCommand, index: Int) -> Int
pub fn imap_command_element_offset(cmd: &ImapCommand, index: Int) -> Int

// Responses
pub fn imap_parse_response(buf: Str) -> Result[ImapResponse, Str]
pub fn imap_parse_response_at(buf: Str, pos: Int) -> Result[ImapResponse, Str]
pub fn imap_response_kind(resp: &ImapResponse) -> Int
pub fn imap_response_tag(resp: &ImapResponse) -> Str
pub fn imap_response_status(resp: &ImapResponse) -> Str
pub fn imap_response_number(resp: &ImapResponse) -> Int
pub fn imap_response_code(resp: &ImapResponse) -> Str
pub fn imap_response_code_arg_count(resp: &ImapResponse) -> Int
pub fn imap_response_code_arg(resp: &ImapResponse, index: Int) -> Str
pub fn imap_response_text(resp: &ImapResponse) -> Str
pub fn imap_response_consumed(resp: &ImapResponse) -> Int
pub fn imap_response_arg_count(resp: &ImapResponse) -> Int
pub fn imap_response_arg_kind(resp: &ImapResponse, index: Int) -> Int
pub fn imap_response_arg_text(resp: &ImapResponse, index: Int) -> Str
pub fn imap_response_element_count(resp: &ImapResponse) -> Int
pub fn imap_response_element_kind(resp: &ImapResponse, index: Int) -> Int
pub fn imap_response_element_text(resp: &ImapResponse, index: Int) -> Str
pub fn imap_response_element_depth(resp: &ImapResponse, index: Int) -> Int
pub fn imap_response_element_offset(resp: &ImapResponse, index: Int) -> Int
```

Accessor conventions: out-of-range element indexes return `-1` for the
`Int` accessors and `""` for `Str`; an absent top-level argument returns
`arg_kind == 0` and `arg_text == ""`. `imap_response_number` returns -1 when
the response was not numbered.

## 7. Error catalog

Errors are plain `Str` values. Every message starts with `"imap: "`; the
conformance suite matches that prefix, and the suffixes below are part of
the specification. `N` is an absolute byte offset; the two shape prefixes
(`bad command shape:`) append `at byte N` after the fragment.

| Message | Trigger |
|---|---|
| `imap: bad start offset` | `pos < 0` or `pos > buf.len()` |
| `imap: missing CRLF at byte N` | buffer or line ends without a CRLF terminator |
| `imap: bare CR at byte N` | CR not followed by LF |
| `imap: bare LF at byte N` | LF without a preceding CR |
| `imap: bad tag at byte N` | empty tag or a control/tag-special byte in it |
| `imap: missing command name at byte N` | no space after the tag, or no name |
| `imap: bad UID command at byte N` | `UID` with no sub-command |
| `imap: unknown command at byte N` | name not modelled, or `UID <other>` |
| `imap: empty token at byte N` | token scanner reached end of buffer |
| `imap: control byte in atom at byte N` | byte below 0x20 or 0x7F in an atom |
| `imap: control byte in quoted string at byte N` | control byte inside quotes |
| `imap: unterminated quoted string at byte N` | quote never closed (CR/LF/end) |
| `imap: bad quoted-string escape at byte N` | `\` followed by anything but `\` or `"` |
| `imap: bad literal size at byte N` | non-digit size, missing `}` or `+}` |
| `imap: literal size exceeds the limit at byte N` | size above `IMAP_MAX_LITERAL` |
| `imap: literal marker not followed by CRLF at byte N` | bytes between `}` and the line end |
| `imap: literal of <n> bytes does not fit at byte N` | literal content past buffer end |
| `imap: literal not followed by a separator at byte N` | token or `(` directly after a literal |
| `imap: unbalanced parentheses at byte N` | CRLF/end of buffer while a list is open |
| `imap: unexpected closing parenthesis at byte N` | `)` with no open list |
| `imap: bad untagged response at byte N` | `*` not followed by space and a keyword |
| `imap: bad message number at byte N` | digit-leading first atom is not 0..2^31-1 |
| `imap: message number required at byte N` | numbered keyword without a number |
| `imap: unexpected message number at byte N` | number on a keyword that takes none |
| `imap: bad response code at byte N` | malformed/empty code content |
| `imap: unterminated response code at byte N` | `[` never closed |
| `imap: bad tagged response at byte N` | tag without a following status |
| `imap: bad tagged response status at byte N` | tagged status other than OK/NO/BAD |
| `imap: bad continuation response at byte N` | `+` not followed by space or CR |
| `imap: bad STATUS response at byte N` | STATUS shape violation |
| `imap: bad mailbox list response at byte N` | LIST/LSUB shape violation |
| `imap: bad FLAGS response at byte N` | FLAGS shape violation |
| `imap: bad numbered response at byte N` | arguments on EXISTS/RECENT/EXPUNGE |
| `imap: bad FETCH response at byte N` | FETCH first argument is not a list |
| `imap: bad command shape: <LABEL> ... at byte N` | any per-command shape rule in section 4.10 |

## 8. Test plan

`tests/test_conformance.xi` (module `imap_tests`) runs 18 named checks
through `xiom.test`'s `assert(cond, "name")`, one `fn` per check, and `main`
returns the failure count (0 = green). Every protocol buffer is built in the
test source; no external data files.

| # | Check | Semantics pinned |
|---|---|---|
| t1 | zero-argument commands | tags, canonical names, kinds, `uid`, `consumed`, arity errors |
| t2 | LOGIN | atoms, literals as strings, NIL/list rejection, arity |
| t3 | quoted strings | `\\`/`\"` unescaping, unterminated, bad escape, control byte |
| t4 | mailbox commands | SELECT/EXAMINE/CREATE/DELETE/RENAME arity and strings |
| t5 | LIST + STATUS command | `NIL` reference, wildcards, nested item list depths |
| t6 | FETCH + UID FETCH | nested attribute lists, `BODY[...]` tokens, `uid` flag, shape errors |
| t7 | STORE + SEARCH | `FLAGS`/`+FLAGS`/`-FLAGS`, optional flag list, criteria, UID SEARCH |
| t8 | APPEND | literals with embedded CRLF, `{n+}`, flags+date shape, empty literal |
| t9 | literal edge cases | bad sizes, missing CRLF, cap, truncation, leading zeros, lists |
| t10 | command framing | empty input, bare CR/LF, missing CRLF, bad tags, unbalanced lists |
| t11 | tagged responses | OK/NO/BAD, text, codes (ALERT, BADCHARSET, UIDVALIDITY, PERMANENTFLAGS) |
| t12 | untagged text responses | CAPABILITY, FLAGS, SEARCH, BYE, OK[UNSEEN], PREAUTH |
| t13 | numbered responses | EXISTS/RECENT/EXPUNGE/FETCH number rules and errors |
| t14 | FETCH responses | attribute lists, `\Seen` flags, multi-line literal, malformed |
| t15 | LIST/LSUB/STATUS responses | shapes, NIL delimiter, even item count, malformed |
| t16 | continuations | `+`, `+ text`, `+ [code] text`, `+x` rejection |
| t17 | buffer consumption | `consumed` counts, `_at` resumes, multi-message buffers |
| t18 | accessors + malformed | bounds sentinels, offsets, unterminated code, bare line ends |

Element `Str` comparisons go through `xiom.string.compare.str_compare`, never
`==` (BUG 17: `==` on a `Str` read from a `Vec[Str]` element lowers to a
pointer comparison).

Command: `.\scripts\port.ps1 -Package xiom.imap` (compiler v0.61.3,
`XIOM_STDLIB=E:\xiom-lang\stdlib`). Expected tail: 18 `[PASS]` lines,
`xiom.imap: all tests passed`, then
`port: PASS (passed=18 failed=0 program_exit=0 exit=0)`.

## 9. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the pure-parser idioms
of `xiom.bencode`/`xiom.pop3` (byte-wise scanning with `xiom.string.byte_at`,
a mutable cursor record, typed locals) and documents these compiler-driven
choices:

- `Vec[StructType]` is unsupported, so parsed messages are flat records with
  depth-annotated parallel `Vec`s; the four element columns are pushed in one
  loop so they cannot drift.
- `Ok`/`Err` for the two struct-payload `Result` shapes are constructed only
  in the leaf helpers `_ok_command`/`_err_command` and
  `_ok_response`/`_err_response`.
- Every widened byte goes through `(byte_at(s, i) as Int) & 0xFF`; element
  reads are bound to typed locals (`let k: Int = kinds[i];`,
  `let t: Str = texts[i];`) before comparison, and every `Str` comparison
  uses `str_compare`/`str_compare_ignore_case`.
- No `[T, U]` generics, no `Vec[fn]`, no `Vec[Float64]`, no `match` arm
  binds `mut`; tests dispatch `t1()` .. `t18()` directly; every `match` is
  exhaustive.
- The source and test files are grep-audited for stray `Vec<`/`Result<`
  angle brackets after every edit (v0.61.3 accepts malformed bracket types
  silently in some positions).

## 10. Non-goals and limitations

- No wire emission: there is no command/response builder, so round-trip
  build/parse identity is not part of this package.
- No sockets, TLS/STARTTLS, AUTHENTICATE/SASL, IDLE, pipelining, timers or
  session state; callers own the connection and the
  NOT-AUTHENTICATED/AUTHENTICATED/SELECTED/LOGOUT sequencing.
- No extensions: NAMESPACE, SORT, THREAD, CONDSTORE, ENABLE, MOVE, UNSELECT,
  MOVE, ID, QUOTA and every other extension command is `unknown command`.
  `{n+}` parses but no non-synchronizing literal policy is modelled.
- Generic extension responses: an unknown untagged keyword is parsed
  generically; numbered forms are restricted to
  `EXISTS`/`RECENT`/`EXPUNGE`/`FETCH`.
- Mailbox names, sequence sets, flags, search keys, dates and BODY sections
  are opaque text: no sequence-set expansion, search evaluation, flag
  semantics, modified-UTF-7 or MIME decoding, and no length caps beyond the
  literal cap. 8-bit bytes pass through where the grammar allows them.
- Buffer-at-a-time: a partial literal is an error, not a `need more data`
  signal; callers accumulate bytes themselves.
- Documented leniencies: one-or-more spaces separate arguments, leading
  zeros are accepted in decimal numbers, and trailing spaces before CRLF are
  tolerated. Documented narrowing: tags reject `%`, `*`, `]` and `+`
  (RFC 3501 tags allow `]`), and argument-bearing response statuses are
  matched against a fixed shape set rather than a permissive grammar.
