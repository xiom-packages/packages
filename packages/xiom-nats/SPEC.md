# xiom.nats -- specification

Byte-exact specification of the NATS 1.x text protocol subset implemented by
`src/nats.xi` (package `xiom.nats` 0.1.0). The module is a pure codec: it owns
no sockets and no session state, and every parser consumes one op at a time
out of an in-memory `Vec[UInt8]`.

## 1. Framing

```
op          = control-line CRLF [ payload CRLF ]      ; payload ops only
control-line= token *( SP token )
CRLF        = %x0D %x0A
SP          = %x20
```

- Control lines are at most **4096 bytes including the CRLF**. A longer line
  is `nats: control line too long`.
- Tokens are separated by exactly one space: a leading space, a trailing
  space or a double space is `nats: bad args`.
- Control-line bytes may not be C0 controls (below `%x20`) and `%x7F` is
  rejected wherever text is validated (subjects, queue groups, `-ERR` text,
  JSON objects).
- For the payload ops the control line declares a decimal byte count `n`; the
  payload is exactly `n` bytes and the op is closed by CRLF. **The closing
  CRLF is not part of `n`.** Payloads are copied verbatim: they may contain
  NUL, CR, LF and bytes >= 128, and they are never converted to `Str`.
- `nats_parse_op(data, off)` returns `Ok(op)` with
  `op.consumed` = control-line bytes + payload bytes + closing CRLF bytes, so
  the next op starts at `off + op.consumed`.

Worked example (hex):

```
50 55 42 20 6a 6f 62 73 20 64 6f 6e 65 20 36 0d 0a   "PUB jobs done 6\r\n"
00 ff 80 0d 0a 42                                    payload (6 bytes)
0d 0a                                                closing CRLF
```

parses to `subject = "jobs"`, `reply = "done"`, `total_size = 6`,
`payload = 00 ff 80 0d 0a 42`, `consumed = 17`.

## 2. Op grammar

Client ops:

| Op | Grammar |
|----|---------|
| `CONNECT` | `CONNECT SP json-object` |
| `PUB` | `PUB SP subject [SP reply] SP size` |
| `HPUB` | `HPUB SP subject [SP reply] SP hsize SP tsize` |
| `SUB` | `SUB SP filter [SP queue] SP sid` |
| `UNSUB` | `UNSUB SP sid [SP max_msgs]` |
| `PING` / `PONG` | no argument |

Server ops:

| Op | Grammar |
|----|---------|
| `INFO` | `INFO SP json-object` |
| `MSG` | `MSG SP subject SP sid [SP reply] SP size` |
| `HMSG` | `HMSG SP subject SP sid [SP reply] SP hsize SP tsize` |
| `+OK` | no argument |
| `-ERR` | `-ERR SP message` (message non-empty, control-free) |

Numeric fields (`size`, `hsize`, `tsize`, `sid`, `max_msgs`) are decimal
digits only: no sign, leading zeros accepted (`007` == 7), value at most
**2147483647**; `sid` and `max_msgs` are at least 1. Requested `max_msgs = 0`
is invalid on the wire (the codec's encoder omits the token instead).

For `PUB`/`MSG` the optional reply token is present exactly when the op has
one token more than the minimum; the last token is always the size. The
counts decide: `PUB foo 5` is subject `foo`, size 5 (a reply `5` on a literal
subject would be encoded `PUB foo 5 5`).

`CONNECT`/`INFO` carry a JSON object as **raw bytes**: the codec checks the
`{...}` shape (at least `{}`, no control bytes) and stores the text verbatim in
`op.text`; it does not interpret the JSON.

`HPUB`/`HMSG` require `hsize <= tsize`; the header block is `hsize` bytes and
the payload is the remaining `tsize - hsize` bytes. The trailing CRLF closes
the op.

## 3. Subjects

```
subject = token *( "." token )
```

Literal subject bytes are `%x21..%x7E` and `%x80..%xFF`, minus `%x7F (DEL)`,
minus the wildcards `*` (`%x2A`) and `>` (`%x3E`); `.` (`%x2E`) separates
tokens and never appears inside one. Empty subjects, empty tokens (leading,
trailing or doubled `.`), spaces and control bytes are invalid.

Filters (SUB) additionally allow two whole-token wildcards:

- a token that is exactly `*` matches exactly one token;
- a token that is exactly `>` matches one or more tokens and must be the
  **final** token.

`foo*`, `*foo`, `a.*b` and `foo.>.bar` are structurally invalid: a wildcard
must be a whole token.

| filter | subject | match |
|--------|---------|-------|
| `foo.bar` | `foo.bar` | yes |
| `foo.*` | `foo.bar` | yes |
| `foo.*` | `foo` / `foo.a.b` | no |
| `foo.>` | `foo.a` / `foo.a.b` | yes |
| `foo.>` | `foo` | no |
| `>` | anything non-empty | yes |
| `*.svc.*` | `us.svc.east` | yes |

`nats_subject_matches` validates both inputs first, so a malformed filter, a
wildcard subject or an empty input yields `false` rather than an error.

## 4. Header blocks (HPUB / HMSG)

A header block is at least 12 bytes and must satisfy:

- bytes `[0, 8)` are exactly `NATS/1.0`;
- byte 8 is CR (then byte 9 must be LF) or SP (inline status form, e.g.
  `NATS/1.0 100\r\n`);
- the last four bytes are CR LF CR LF.

Anything else is `nats: bad headers`. Header line contents are not otherwise
validated (that is header-layer business).

## 5. JSON key lookups

`nats_json_str/int/bool/has(text, key)` find the first **scalar top-level**
member of an object text:

- the quoted key must start at an object boundary (start, after `{`, `,` or
  whitespace) and be followed by `:` (spaces around it are skipped);
- a string value returns its raw inner bytes (quotes stripped, escapes are
  skipped while scanning but **not decoded**);
- an integer value is an optional `-` plus digits, magnitude <= 2147483647;
- a boolean value is `true` or `false`;
- composite values (`{...}` / `[...]`) are `nats: json bad value: <key>`;
- a key that does not exist is `nats: json key not found: <key>`;
- an empty key is `nats: json empty key`.

Because this is a lookup helper and not a JSON parser, a member nested in a
sub-object can still match (the boundary rule only stops matches **inside
string values**). Callers that need full JSON semantics should use a JSON
module on `op.text`.

## 6. Error catalog

Parse errors append the op start offset: `"<message> at <offset>"`.

| Message | Meaning |
|---------|---------|
| `nats: negative offset` | `off < 0` |
| `nats: truncated op` | no CRLF in the buffer (or no bytes at `off`) |
| `nats: control line too long` | control line beyond 4096 bytes incl. CRLF |
| `nats: unknown op` | first token is not a known op name |
| `nats: bad args` | wrong token count / spacing, bad JSON argument, empty `-ERR`, arguments on `PING`/`PONG`/`+OK` |
| `nats: bad subject` | invalid subject/filter |
| `nats: bad reply` | invalid reply-to subject |
| `nats: bad queue` | invalid queue group |
| `nats: bad sid` | sid not decimal or < 1 (or > 2147483647) |
| `nats: bad max` | `max_msgs` not decimal or < 1 |
| `nats: bad size` | size/count not decimal, > 2147483647, or `hsize > tsize` |
| `nats: bad headers` | header block not a NATS/1.0 block |
| `nats: bad json` | `CONNECT`/`INFO` argument is not a braced object |
| `nats: truncated payload` | fewer payload bytes than declared |
| `nats: bad payload terminator` | payload not followed by CRLF |

Per-op precedence: line scan -> op token -> per-op arg count -> subject /
reply / queue -> numeric fields -> `hsize <= tsize` -> payload bounds ->
payload terminator -> header block.

Encoder errors (no offset): `nats: bad subject`, `nats: bad reply`,
`nats: bad queue`, `nats: bad sid`, `nats: bad max`, `nats: bad headers`,
`nats: bad json`, `nats: bad error text`, `nats: payload too long`.

`Ok` op fields use 0/empty for absent values: `sid = 0`, `max_msgs = 0` (no
auto-unsubscribe), `header_size = 0`, empty `reply`/`queue`/`headers`/`text`.

## 7. Limits

| Limit | Value | Applies to |
|-------|-------|-----------|
| control line | 4096 bytes incl. CRLF | every op |
| byte count / sid / `max_msgs` | 2147483647 | sizes, ids |
| header block | >= 12 bytes | HPUB / HMSG |

## 8. Documented limitations

- No sockets, TLS, heartbeats, reconnect, auth or session state; the caller
  drives the transport and the verbose/pedantic logic.
- `CONNECT`/`INFO` JSON is opaque text with a shape check only; no JSON
  validation, no unescaping in lookups, no nested/composite lookup support.
- Subject validation is structural and byte-level: no UTF-8 validation, no
  per-server ACL, no account/import-export resolution.
- `-ERR` messages must be control-free; tabs are rejected.
- The control-line cap mirrors the NATS default `max_control_line`; a server
  configured differently is out of scope.
- Payload counts above 2147483647 are rejected even though NATS itself allows
  larger `max_payload` values on some deployments.

## 9. v0.61.3 implementation notes

- `Ok`/`Err` construction is confined to leaf helpers; larger functions return
  through them.
- Bytes are always read as `(data[i] as Int) & 0xFF` before arithmetic.
- `Vec[StructType]`, `Vec[fn]`, callbacks and `match` are not used in the
  module; op fields are flat `Vec[UInt8]`/`Int` scalars.
- Vec fields are bound to typed locals before being passed by reference.
- No floats, no `log`, no bit shifts; sizes are encoded with
  `xiom.string.builder.sb_push_int`.

## 10. Conformance

`tests/test_conformance.xi` runs 21 checks: kind metadata, subject validation
and matching, pinned parses for every op (including binary payloads with NUL,
CR, LF and bytes >= 128), parse error classes with offsets, the 4096-byte
control-line boundary, consumed-count streams, pinned encoders, encode ->
parse -> encode round-trips and the JSON lookups. Run with:

```powershell
.\scripts\port.ps1 -Package xiom.nats
```
