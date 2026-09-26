# xiom.ftp -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.ftp` (`src/ftp.xi`). Pure XIOM, no FFI, no sockets, no I/O.

## 1. Scope

A small, dependency-free codec for the FTP control connection (RFC 959 with
the common FEAT/OPTS/SIZE/MDTM extensions), operating on in-memory `Str`
values:

- `ftp_parse_command` / `ftp_emit_command` -- command lines,
- `ftp_command_name` / `ftp_command_argument` / `ftp_command_raw` --
  command accessors,
- `ftp_port_octets` / `ftp_type_code` / `ftp_mode_code` / `ftp_stru_code` --
  typed argument accessors,
- `ftp_parse_response` / `ftp_emit_response` -- single-line and multiline
  replies,
- `ftp_response_code` / `ftp_response_class` / `ftp_response_is_multiline` /
  `ftp_response_line_count` / `ftp_response_line` / `ftp_response_line_code` /
  `ftp_response_text` / `ftp_response_raw` -- reply accessors.

Non-goals: sockets, connection/session state, authentication, data-channel
semantics, transfer progress, directory-listing decoding (LIST/NLST/STAT
payloads are opaque text), MLSD/MLST line formats, and every verb outside the
fixed set in section 4.

## 2. Data model

```xi
pub type Command = {
  name: Str;      // canonical uppercase verb, e.g. "USER"
  argument: Str;  // canonical argument text, "" when the verb takes none
  raw: Str;       // verbatim input line, CRLF included
}

pub type Response = {
  code: Int;         // reply code of the first line (= terminator code)
  raw: Str;          // verbatim reply text, CRLF included
  codes: Vec[Int];   // per-line code, -1 for a line with no reply prefix
  lines: Vec[Str];   // physical line content without CRLF, index-aligned
}
```

Invariants:

- `Command.raw` is the exact input on `ftp_parse_command` success.
- `Command.name` is always one of the 31 uppercase verbs of section 4 and
  never empty; `Command.argument` has passed the per-verb validation of
  section 5 and is canonical (uppercase code letters, canonical decimals in
  `PORT`, no leading zeros in `TYPE L n`).
- `Response.lines.len() >= 1` and `Response.lines.len() ==
  Response.codes.len()`; `Response.codes[0] == Response.code` and the last
  entry of `codes` equals `Response.code` (both are reply-prefixed lines);
  `-1` marks a line stored verbatim without a `NNN`/`NNN-` prefix.
- `Response.raw` is the exact input consumed by `ftp_parse_response`.
- `Vec[StructType]` is unusable in this compiler, so no field is a vector of
  structs; the reply body is two parallel homogeneous vectors.

## 3. Line grammar and CRLF framing

```
command-line = verb [ SP argument ] CRLF
verb         = 3*4 ALPHA                    ; case-insensitive on input
argument     = 1*( printable byte )         ; SP allowed inside
reply-line   = code ( SP text / "-" text )
code         = 3 DIGIT
text         = *( printable byte )
CRLF         = %x0D %x0A
```

- Every command line and every reply line must be terminated by CRLF. A
  missing terminator is `ftp: missing CRLF` (a bare LF or CR is not a line
  ending; it is a control byte).
- A control byte is any byte `< 0x20` or `== 0x7F`. Commands may not contain
  one anywhere before the final CRLF (`ftp: control byte in command`); reply
  lines may not contain one before their CRLF (`ftp: control byte in
  response line`). Bytes above 0x7E pass through byte-wise.
- Size caps: a command is at most 512 bytes including CRLF (RFC 959);
  a reply is at most 8192 bytes including all CRLFs. Over-cap input is
  rejected before any parsing.

## 4. Verb set and arity

Parsing uppercases the leading run of ASCII letters. If there are none, the
error is `ftp: bad verb: <first-space-delimited-word>`; if the uppercased run
is not one of the verbs below, the error is `ftp: unknown verb: <NAME>`.
Anything between the verb run and the next space is `ftp: bad argument
shape: <NAME>` (e.g. `PWD/`).

| Argument class | Verbs |
|---|---|
| none | `CDUP PWD QUIT PASV ABOR SYST FEAT` |
| required, non-empty | `USER ACCT CWD PORT TYPE MODE STRU RETR STOR STOU APPE DELE RMD MKD RNFR RNTO OPTS SIZE MDTM` |
| optional (`LIST`, `NLST`, `STAT [path]`) | `LIST NLST STAT` |
| required but may be empty | `PASS` |

Arity violations are `ftp: bad argument shape: <NAME>`:

- a no-argument verb followed by a space (even an empty argument), e.g.
  `PWD `;
- a required verb with no argument or an empty argument, e.g. `USER`,
  `CWD \r\n`;
- an optional verb with an empty argument after its space, e.g. `STAT `;
- `PASS` with no space/argument at all (`PASS\r\n`); `PASS \r\n` is accepted
  with an empty argument (an empty password is representable).

`LIST`/`NLST` carry an opaque path/options text; `STAT`'s path is opaque.
Trailing spaces are part of the argument (no trimming): `CWD /pub ` stores
`"/pub "`.

## 5. Documented argument validation

### 5.1 PORT

`PORT <h1>,<h2>,<h3>,<h4>,<p1>,<p2>`:

- exactly six comma-separated fields, no more, no fewer;
- every field is 1..3 ASCII digits; empty fields and signs are rejected;
- every value is 0..255 (the octet range); `256` is rejected;
- leading zeros are accepted and canonicalized away: `010` -> `10`;
- the stored argument is the canonical decimal form
  `h1,h2,h3,h4,p1,p2` (so `PORT 192,168,0,1,4,1` is stored as-is).

`ftp_port_octets(c)` re-validates the stored argument and returns the six
values; a non-`PORT` command or a malformed argument yields an empty vector.

### 5.2 TYPE

`TYPE A [N|T|C] | TYPE E [N|T|C] | TYPE I | TYPE L <byte-size>`:

- case-insensitive; the stored argument is canonical uppercase (`type a n` ->
  `A N`);
- `A`/`E` take the optional second form letter `N`, `T` or `C` only;
- `I` takes no second letter (`TYPE I N` is rejected);
- `L` requires `SP` then a byte size: 1..6 ASCII digits, no leading zero,
  value >= 1. The RFC 959 form `TYPE L 8` is canonical; `TYPE L 0`,
  `TYPE L 0123` and `TYPE L 1234567` are rejected. The byte size is carried
  as text (no numeric reinterpretation).

`ftp_type_code(c)` returns the code letter `A`, `E`, `I` or `L`, else `""`.

### 5.3 MODE and STRU

- `MODE S|B|C` (stream, block, compressed), case-insensitive, canonical
  uppercase; anything else is rejected. `ftp_mode_code` returns the letter
  or `""`.
- `STRU F|R|P` (file, record, page), case-insensitive, canonical uppercase;
  anything else is rejected. `ftp_stru_code` returns the letter or `""`.

### 5.4 OPTS

`OPTS <option> [ SP <value> ]` (RFC 2389 shape):

- `<option>` is a non-empty run of ASCII letters/digits (`UTF8`, `MLST`,
  `HOST`, ...);
- the option may stand alone (`OPTS UTF8`);
- a value, when present, follows exactly one space and is non-empty printable
  text that may itself contain spaces and punctuation
  (`OPTS UTF8 ON`, `OPTS MLST Type;Size;`);
- an option run followed by anything other than end-of-line or a space is
  rejected, as is an empty option, a double space, and a trailing space with
  no value.

The argument is stored verbatim after the single space (no case folding): the
option and value are opaque to this codec.

## 6. Reply grammar and parsing decisions

```
reply        = single-line / multiline
single-line  = code SP text CRLF
multiline    = code "-" text CRLF *( body-line CRLF ) code SP text CRLF
body-line    = *( printable byte )            ; any line between the two
```

1. The first line must carry a 3-digit code and then `SP` or `-`.
   - fewer than three leading digits / a non-digit in the first three bytes:
     `ftp: bad code digits: <line>`;
   - first digit not `1`..`5` (code outside 100..599):
     `ftp: bad response class: <line>`;
   - fourth byte neither space nor `-`, or a line shorter than four bytes:
     `ftp: malformed response line: <line>`.
2. A first line ending with `NNN ` (space) is single-line: the reply ends at
   its CRLF and any further bytes are `ftp: trailing data after response`.
3. A first line ending with `NNN-` (dash) opens a multiline block. The block
   runs line by line until a line whose first four bytes are the *same* code
   followed by a space. That closing line is included.
4. Lines inside the block are carried verbatim (without CRLF):
   - a line shaped `xxx ` or `xxx-` with `xxx != code` is a terminator/reply
     attempt with the wrong number -> `ftp: multiline code mismatch:
     <line>`;
   - a line shaped `NNN ` with the opening code terminates the block; a line
     shaped `NNN-` with the opening code stores code `NNN` and continues;
   - every other line (including ` SIZE`, `MDTM`, empty lines, or text that
     merely starts with digits) stores code `-1` and continues. This is what
     makes real `FEAT` blocks (`211-Features:` + uncoded feature lines +
     `211 End`) parse.
   - interior control bytes are rejected (`ftp: control byte in response
     line`); a line longer than the total cap cannot occur (cap checked
     first).
5. End of input inside a block before the matching `NNN ` line is
   `ftp: unterminated multiline response`; a body line without its CRLF is
   `ftp: missing CRLF`.
6. The code is an integer 100..599; `ftp_response_class` is `code / 100`
   (integer division, so exactly 1..5).

## 7. Canonical emitter

`ftp_emit_command(c)` emits `name + " " + argument + CRLF`, omitting the
space when the argument is empty; since parsing canonicalizes, the emitted
command is uppercase-verb canonical CRLF text. An empty `name` emits `""`.

`ftp_emit_response(r)` rebuilds the reply from `lines`/`codes`:

- a coded line (`codes[i] >= 0`) is re-emitted as `NNN-<text>` for the first
  and intermediate lines and `NNN <text>` for the last line, where `<text>`
  is the stored line minus its code+marker prefix;
- an uncoded line (`-1`) is emitted verbatim;
- every line gets CRLF. `remit(parse(x)) == x` holds for every canonical
  reply `x` accepted by section 6 (non-canonical input such as `230-` plus
  `230-`-terminated blocks is normalized by the terminator rule).

Round-trips: `parse(emit(parse(x)))` preserves `name`/`argument` for
commands and `code`/`lines` for replies; `emit(parse(x))` equals `x` when
`x` is canonical (uppercase verb, CRLF, canonical argument).

## 8. Error catalog

All messages start with `"ftp: "`; commands return them as `Err` from
`ftp_parse_command`, replies from `ftp_parse_response`.

| Message | Trigger |
|---|---|
| `ftp: command too long` | command input > 512 bytes |
| `ftp: response too long` | reply input > 8192 bytes |
| `ftp: missing CRLF` | command/reply line not terminated by CRLF (including empty input) |
| `ftp: empty command` | command input is exactly CRLF |
| `ftp: control byte in command` | byte < 0x20 or 0x7F inside the command line |
| `ftp: control byte in response line` | byte < 0x20 or 0x7F inside a reply line |
| `ftp: bad verb: <word>` | command does not start with an ASCII letter |
| `ftp: unknown verb: <NAME>` | verb not in the 31-verb set (uppercased) |
| `ftp: bad argument shape: <NAME>` | arity violation or bad PORT/TYPE/MODE/STRU/OPTS argument |
| `ftp: bad code digits: <line>` | first reply line without three leading digits |
| `ftp: bad response class: <line>` | first reply code outside 100..599 |
| `ftp: malformed response line: <line>` | first reply line without a space/dash marker |
| `ftp: multiline code mismatch: <line>` | reply-shaped body line with a different code |
| `ftp: unterminated multiline response` | input ended before the matching terminator |
| `ftp: trailing data after response` | bytes after the final reply CRLF |

Precedence: length cap, then CRLF framing, then per-line digit/class/marker
checks, then control bytes, then block structure. `PASS` special-cases an
empty-but-present argument; every other required verb rejects an empty one.

## 9. API signatures

```xi
pub const FTP_MAX_COMMAND_BYTES: Int = 512;
pub const FTP_MAX_RESPONSE_BYTES: Int = 8192;

pub fn ftp_parse_command(text: Str) -> Result[Command, Str]
pub fn ftp_emit_command(c: &Command) -> Str
pub fn ftp_command_name(c: &Command) -> Str
pub fn ftp_command_argument(c: &Command) -> Str
pub fn ftp_command_raw(c: &Command) -> Str
pub fn ftp_port_octets(c: &Command) -> Vec[Int]
pub fn ftp_type_code(c: &Command) -> Str
pub fn ftp_mode_code(c: &Command) -> Str
pub fn ftp_stru_code(c: &Command) -> Str

pub fn ftp_parse_response(text: Str) -> Result[Response, Str]
pub fn ftp_emit_response(r: &Response) -> Str
pub fn ftp_response_code(r: &Response) -> Int
pub fn ftp_response_class(r: &Response) -> Int
pub fn ftp_response_is_multiline(r: &Response) -> Bool
pub fn ftp_response_line_count(r: &Response) -> Int
pub fn ftp_response_line(r: &Response, i: Int) -> Str
pub fn ftp_response_line_code(r: &Response, i: Int) -> Int
pub fn ftp_response_text(r: &Response) -> Str
pub fn ftp_response_raw(r: &Response) -> Str
```

## 10. Test plan

`tests/test_conformance.xi` (module `ftp_tests`) runs 24 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green), dispatching `t1()`..`t24()` directly (no `Vec[fn]`).
Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | USER line | name/argument/raw/emit for a plain command |
| t2 | canonicalization | lowercase verb -> uppercase, `type a n` -> `A N`, MODE/STRU codes |
| t3 | no-argument verbs | PWD PASV QUIT FEAT CDUP ABOR SYST round-trip |
| t4 | CRLF framing | missing CRLF variants; bare CRLF -> empty command |
| t5 | bad verbs | unknown verb, non-letter start, glued junk after a verb |
| t6 | arity | required/optional/none; `STAT`/`LIST` paths; `PASS` empty |
| t7 | PORT good | six octets, 0..255, leading-zero canonicalization, non-PORT empty |
| t8 | PORT bad | count, range, empty field, sign, trailing comma, 4-digit field |
| t9 | TYPE forms | A/E/I/L, second letters, `L n` bounds, all rejection shapes |
| t10 | MODE/STRU | S/B/C and F/R/P, case folding, wrong-command accessors |
| t11 | control bytes | tab/SOH/DEL/CR inside a command are rejected |
| t12 | size caps | 512-byte command ok, 513 rejected; 8192-byte reply ok, 8193 rejected |
| t13 | single-line reply | code/class/multiline/count/line/text/raw/emit |
| t14 | multiline same-code | `230-` block, code of every line, empty text line |
| t15 | FEAT block | uncoded body lines get `-1`, terminator code, emit round-trip |
| t16 | mismatch | `230 `, `200 B`, `221-B` inside a `220-` block |
| t17 | unterminated | truncated blocks report the exact error |
| t18 | code digits/class | non-digits, 2-digit, `000`, `600`, `999` |
| t19 | malformed/control | `220` without marker, `220Service`, tab/LF inside a line |
| t20 | trailing/missing | extra reply after a single line; missing CRLF cases |
| t21 | reply classes | 150/220/331/426/550 -> classes 1..5 |
| t22 | empty text/bounds | `220 ` text `""`; out-of-range line/line-code |
| t23 | all verbs | all 31 verbs parse and emit byte-for-byte |
| t24 | OPTS | option, value with spaces/punctuation, empty/double/trailing space |

Element comparisons use `xiom.string.compare.str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison).

## 11. Compiler / stdlib notes

No unsafe code and no FFI. The implementation follows the same pure-parser
idioms as `xiom.eml`/`xiom.tftp` and documents these compiler-driven choices:

- `Vec[StructType]` is unsupported, so the reply body is two parallel
  homogeneous vectors (`codes`, `lines`) with equal length maintained by
  construction and guarded at every read.
- `Ok`/`Err` for `Result[Command, Str]` and `Result[Response, Str]` are
  constructed only in the leaf helpers `_ok_cmd`/`_err_cmd`/
  `_ok_resp`/`_err_resp`.
- Str equality goes through `xiom.string.compare.str_compare` (BUG 17);
  `Vec[Str]` and `Vec[Int]` element reads are bound to typed locals before
  use.
- Byte reads go through `_sb`, which widens with `(byte_at(...) as Int) &
  0xFF`; all arithmetic is integer; no bitwise operation is applied to a
  value that may have the sign bit set.
- Tests dispatch directly (`t1()` ... `t24()`); `Vec[fn]` indexed calls are
  not used, no match arms bind `mut`, and all matching is if/elif chains.

## 12. Known limitations

- No session semantics: replies are not correlated with commands, no state
  machine, no timeouts, no 1xx/3xx sequencing checks.
- No verb extensions: `NOOP`, `SITE`, `REST`, `MLSD`, `MLST`, `AUTH`, ...
  are `ftp: unknown verb`.
- Multiline replies follow the simplified same-code model: an RFC 959 block
  whose intermediate lines start with digits and a space but a different
  code is a mismatch error rather than plain text.
- Argument canonicalization is ASCII-only; non-ASCII bytes (UTF-8 paths) are
  accepted verbatim but never case-folded.
- `PASS` is stored and emitted verbatim (no obfuscation, no logging policy).
- Errors carry no line/column position; the offending line text is embedded
  where the catalog says so.
