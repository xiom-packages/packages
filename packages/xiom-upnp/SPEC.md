# xiom.upnp -- specification of the implemented subset

Version: 0.1.2 (stable; published on the XIOM registry).

This document describes exactly what `packages/xiom-upnp/src/upnp.xi`
parses and produces. It is deliberately narrower than the SSDP/UPnP
specifications: everything below is implemented, everything else is
rejected or ignored as noted.

## 1. Message grammar

An SSDP datagram is a byte string of at most `UPNP_MAX_MESSAGE` (8192)
bytes:

```
message    = start-line CRLF header* [ CRLF ] EOF
start-line = request-line / response-line
request-line = method SP "*" SP "HTTP/1.1"
method     = "M-SEARCH" / "NOTIFY"          ; case-sensitive
response-line = "HTTP/1.1" SP "200" [ SP reason ]  ; reason may be empty
header     = name ":" [ OWS ] value [ OWS ] CRLF
name       = 1*tchar                        ; RFC 7230 token set
value      = bytes without CR, LF, NUL or C0/DEL controls
```

Rules and limits:

* A line is terminated by CRLF. A bare CR, a bare LF, NUL, any other C0
  control byte and DEL (0x7F) are rejected wherever they appear; TAB is
  the only control byte allowed inside a line.
* The final line may end at EOF without CRLF (UDP datagrams are commonly
  unterminated).
* The first empty line ends the header block; bytes after it are ignored
  (no bodies are read).
* Header names are matched ASCII case-insensitively; the as-sent name,
  the trimmed value and the header's absolute byte offset are stored in
  the parallel vectors `names`, `values`, `header_offsets`. Duplicate
  headers are all stored; the typed fields use the first occurrence.
* Space is the only token separator in the start line, and the number of
  tokens is exact for requests (3): `M-SEARCH  * HTTP/1.1` (double space)
  or a trailing token is `upnp: bad start line`.
* The start line is decoded into `kind`, `method`, `target`, `version`,
  `status` (-1 for requests) and `reason` ("" for requests).

## 2. Header sets per message form

| Form (`kind`) | Required headers | Optional headers honoured |
|---|---|---|
| `UPNP_KIND_MSEARCH` | HOST, MAN, MX, ST | USER-AGENT |
| `UPNP_KIND_NOTIFY` (`ssdp:alive`) | HOST, NT, NTS, USN, CACHE-CONTROL, LOCATION | SERVER, BOOTID.UPNP.ORG, CONFIGID.UPNP.ORG, SEARCHPORT.UPNP.ORG |
| `UPNP_KIND_NOTIFY` (`ssdp:byebye`) | HOST, NT, NTS, USN | CACHE-CONTROL, LOCATION, SERVER, BOOTID, CONFIGID, SEARCHPORT |
| `UPNP_KIND_NOTIFY` (`ssdp:update`) | HOST, NT, NTS, USN, BOOTID.UPNP.ORG | CACHE-CONTROL, LOCATION, SERVER, CONFIGID, SEARCHPORT |
| `UPNP_KIND_RESPONSE` (`status == 200`) | CACHE-CONTROL, DATE, EXT, LOCATION, ST, USN | SERVER, BOOTID, CONFIGID, SEARCHPORT |

A missing required header is `upnp: missing required header <NAME>` at the
end-of-headers offset (`end_offset`: the offset of the terminating blank
line, or the message length when the datagram ends after the last header).

## 3. Validation order and value rules

Order of checks in `upnp_parse`:

1. `len == 0` -> `upnp: empty message` (offset 0).
2. `len > 8192` -> `upnp: message too large` (offset = len).
3. Start-line scan and decode (offsets below).
4. Header block scan (offsets below).
5. Per-form required-header presence, in the table order above.
6. Per-form value validation, in the order listed in section 4.
7. Optional integer headers.
8. Form-specific extras (`ssdp:alive`: CACHE-CONTROL >= 1 and nonempty
   LOCATION; `ssdp:update`: BOOTID presence -- this is the same check as
   step 5, restated here for the update form).

Value rules:

* **HOST** -- nonempty and accepted by `upnp_validate_authority` (below);
  otherwise `upnp: empty HOST` / `upnp: bad HOST` at the header offset.
  For responses HOST is not required and the field stays "".
* **MAN** -- one optional pair of surrounding double quotes is stripped,
  then the value must equal `ssdp:discover` case-insensitively; otherwise
  `upnp: bad MAN`. The field stores the raw trimmed value (quotes
  included).
* **MX** -- digits only (at most 10), value 1..5; otherwise
  `upnp: bad MX`. The field is -1 for other forms.
* **ST** -- nonempty and accepted by `upnp_classify_target`; otherwise
  `upnp: empty ST` / `upnp: bad ST`.
* **NT** -- nonempty and accepted by `upnp_classify_target`; otherwise
  `upnp: empty NT` / `upnp: bad NT`. (`ssdp:all` is accepted as an NT
  even though the UDA only uses it as an ST; no extra check is imposed.)
* **NTS** -- case-insensitive `ssdp:alive` / `ssdp:byebye` /
  `ssdp:update`; otherwise `upnp: bad NTS`. The raw text is stored and
  `nts_kind` is `UPNP_NTS_*` or -1.
* **USN** -- must pass `usn_split`; otherwise `upnp: bad USN`.
* **CACHE-CONTROL** -- the value is lowercased and trimmed; it must
  start with `max-age=`; the text after `=` up to the first comma is
  trimmed and must be digits only. `max_age` stores the integer.
  Malformed: `upnp: bad CACHE-CONTROL`. For `ssdp:alive` and responses
  the header is required and `max_age >= 1`; for `ssdp:byebye` and
  `ssdp:update` it is optional, but when present it must parse (0 is
  accepted there since no alive requirement applies).
* **LOCATION** -- nonempty, and accepted by `upnp_validate_location`;
  otherwise `upnp: bad LOCATION`. Required for `ssdp:alive` and
  responses (missing -> `upnp: missing required header LOCATION`).
* **DATE** -- loose RFC 1123 shape: at least 20 bytes, byte 3 is `,`,
  byte 4 is a space, the value ends with ` GMT`; otherwise
  `upnp: bad DATE`. Calendar validity is not checked.
* **EXT** -- presence only; any value is accepted and stored raw.
* **SERVER** / **USER-AGENT** -- no validation; stored raw ("" when
  absent).
* **BOOTID.UPNP.ORG** -- when present: digits only, 0..4294967295
  (32-bit); otherwise `upnp: bad BOOTID.UPNP.ORG`. Required for
  `ssdp:update`.
* **CONFIGID.UPNP.ORG** -- when present: digits only, 0..16777215
  (24-bit); otherwise `upnp: bad CONFIGID.UPNP.ORG`.
* **SEARCHPORT.UPNP.ORG** -- when present: digits only, 1..65535;
  otherwise `upnp: bad SEARCHPORT.UPNP.ORG`.

Integer header offsets point at the first byte of the offending header
line. The digits-only rule rejects signs, spaces, leading `+` and values
longer than 10 digits.

### 3.1 Authority and LOCATION validation

`upnp_validate_authority` accepts `host`, `host:port`, `ipv4:port` and
bracketed IPv6 `[addr]` / `[addr]:port`:

* characters: ASCII alphanumeric plus `-`, `.`, `_`, `:`, `[`, `]`;
* bracketed form: nonempty inside `[...]`, then either end or `:port`;
* unbracketed form: zero or one `:`; the host part must be nonempty and
  match the hostname characters above (alphanumeric plus `-`, `.`, `_`);
* a port is 1..5 digits with value 1..65535; `:0` and `:70000` are
  invalid, as are empty hosts (`:80`).

`upnp_validate_location` requires:

* no ASCII byte <= 0x20 anywhere (this rejects spaces and controls);
* scheme `http://` or `https://`, case-insensitively;
* a nonempty authority (the text up to the first `/`, `?` or `#`)
  accepted by `upnp_validate_authority`;
* the path/query/fragment is not validated further.

### 3.2 USN grammar (`usn_split`)

```
usn        = uuid-form / uuid-urn-form / uuid-root-form / urn-form
uuid-form      = "uuid:" uuid
uuid-urn-form  = "uuid:" uuid "::" urn
uuid-root-form = "uuid:" uuid "::" "upnp:rootdevice"   ; case-insensitive
urn-form       = urn
uuid       = 8HEX "-" 4HEX "-" 4HEX "-" 4HEX "-" 12HEX ; 36 bytes total
urn        = "urn:" part ":" part *( ":" part )         ; every part nonempty
```

`HEX` is `0-9a-fA-F`; the URN scheme match is case-insensitive. Exactly
zero or one `::` is allowed. Result kinds: `UPNP_USN_UUID`,
`UPNP_USN_UUID_URN`, `UPNP_USN_UUID_ROOTDEVICE`, `UPNP_USN_URN`. Fields:
`uuid` (full token, ""), `device_uuid` (bare id, ""), `urn` (""),
`suffix` (text after `::`, ""; equals the URN for the urn form).

Errors (offset is an index into the USN string):

| Condition | Message | Offset |
|---|---|---|
| empty input | `upnp: empty USN` | 0 |
| two or more `::` | `upnp: bad USN` | second `::` |
| left side neither uuid nor urn | `upnp: bad USN` | 0 |
| `uuid:` with malformed id | `upnp: bad uuid in USN` | 5 |
| suffix not urn/rootdevice (or urn left with a suffix) | `upnp: bad USN` | 0 or after `::` |
| malformed urn | `upnp: bad urn in USN` | 0 or start of the urn |

### 3.3 ST/NT grammar (`upnp_classify_target`)

| Input (case-insensitive where noted) | kind | Fields |
|---|---|---|
| `ssdp:all` | `UPNP_TARGET_SSDP_ALL` | raw |
| `upnp:rootdevice` | `UPNP_TARGET_ROOTDEVICE` | raw |
| `uuid:<id>` with canonical uuid | `UPNP_TARGET_UUID` | `uuid` = bare id |
| `urn:<domain>:device:<type>:<ver>` | `UPNP_TARGET_DEVICE` | `domain`, `class_word`, `dev_type`, `version`, `major`, `minor` |
| `urn:<domain>:service:<type>:<ver>` | `UPNP_TARGET_SERVICE` | as above |
| any other structurally valid `urn:...` | `UPNP_TARGET_OTHER_URN` | `domain`, `class_word` = second part |

* The `device` / `service` forms must have exactly four colon-separated
  parts after `urn:`; the version is digits, optionally `.` digits, and
  `major`/`minor` are decoded (`minor` = -1 for a bare integer).
* `domain` and `type` are nonempty runs of ASCII alphanumerics plus `-`,
  `.`, `_`.
* Errors: `upnp: empty target` (0), `upnp: bad target` (0),
  `upnp: bad uuid in target` (5), `upnp: bad urn in target` (4),
  `upnp: bad type in target` (type offset), `upnp: bad version in target`
  (version offset).

## 4. Canonical serialisation

`upnp_build_msearch(host, mx, st, user_agent)` writes exactly:

```
M-SEARCH * HTTP/1.1 CRLF
HOST: <host> CRLF
MAN: "ssdp:discover" CRLF
MX: <mx> CRLF
ST: <st> CRLF
[ USER-AGENT: <user_agent> CRLF ]
CRLF
```

`upnp_build_notify_alive(host, max_age, location, nt, usn, server,
bootid, configid)` writes exactly:

```
NOTIFY * HTTP/1.1 CRLF
HOST: <host> CRLF
CACHE-CONTROL: max-age=<max_age> CRLF
LOCATION: <location> CRLF
NT: <nt> CRLF
NTS: ssdp:alive CRLF
[ SERVER: <server> CRLF ]
USN: <usn> CRLF
[ BOOTID.UPNP.ORG: <bootid> CRLF ]
[ CONFIGID.UPNP.ORG: <configid> CRLF ]
CRLF
```

Header names are always written in the canonical uppercase forms above.
Builder validation reuses the parser rules: authority (`upnp: empty
HOST` / `upnp: bad HOST`), `mx` 1..5 (`upnp: bad MX`), ST classification
(`upnp: empty ST` / `upnp: bad ST`), `max_age` 1..2147483647
(`upnp: bad CACHE-CONTROL`), LOCATION (`upnp: bad LOCATION`), NT
classification (`upnp: empty NT` / `upnp: bad NT`), USN (`upnp: empty
USN` / `upnp: bad USN`), BOOTID <= 2^32-1 and CONFIGID <= 2^24-1. A
negative `bootid`/`configid` omits that header; an empty `server` or
`user_agent` omits it. Serialiser errors carry offset -1 (there is no
input buffer). `upnp_canonical_header_name` maps the known header names
to the same canonical casing and returns unknown names unchanged.

## 5. Error catalog

All errors are `SsdpError { message: Str; offset: Int }`. Offsets are
absolute byte positions in the parsed buffer, except for the standalone
classifiers (`usn_split`, `upnp_classify_target`), where they index the
input string, and the serialisers, where they are -1.

| Message | Emitted by |
|---|---|
| `upnp: empty message` | empty buffer |
| `upnp: message too large` | buffer over `UPNP_MAX_MESSAGE` |
| `upnp: bare CR` / `upnp: bare LF` | line scanning |
| `upnp: control character` | NUL, C0 controls other than TAB, DEL |
| `upnp: empty start line` | zero-length first line |
| `upnp: bad start line` | unknown method/version token, wrong token count |
| `upnp: bad target` | request target other than `*` |
| `upnp: bad version` | request version other than `HTTP/1.1` |
| `upnp: bad status` | response status other than 3-digit `200` |
| `upnp: missing colon in header` | header line without `:` |
| `upnp: empty header name` | header line starting with `:` |
| `upnp: bad header name` | non-token byte in the name |
| `upnp: missing required header <NAME>` | per-form requirements |
| `upnp: empty HOST` / `upnp: bad HOST` | HOST validation |
| `upnp: bad MAN` | MAN not `ssdp:discover` |
| `upnp: bad MX` | MX absent/non-numeric/out of 1..5 |
| `upnp: empty ST` / `upnp: bad ST` | ST validation |
| `upnp: empty NT` / `upnp: bad NT` | NT validation |
| `upnp: bad NTS` | NTS not alive/byebye/update |
| `upnp: bad USN` | USN validation |
| `upnp: bad CACHE-CONTROL` | malformed `max-age`, or max-age < 1 for alive/response |
| `upnp: bad LOCATION` | LOCATION validation |
| `upnp: bad DATE` | DATE shape |
| `upnp: bad BOOTID.UPNP.ORG` / `upnp: bad CONFIGID.UPNP.ORG` / `upnp: bad SEARCHPORT.UPNP.ORG` | integer header validation |
| `upnp: empty target` / `upnp: bad target` / `upnp: bad uuid in target` / `upnp: bad urn in target` / `upnp: bad type in target` / `upnp: bad version in target` | `upnp_classify_target` |
| `upnp: empty USN` / `upnp: bad USN` / `upnp: bad uuid in USN` / `upnp: bad urn in USN` | `usn_split` |

## 6. Non-goals (explicitly out of scope)

* Sockets, multicast, retransmission, MX scheduling -- the codec is pure.
* XML device/service descriptions, SOAP, GENA eventing.
* HTTP bodies, chunked framing, keep-alive.
* Methods other than M-SEARCH/NOTIFY and response statuses other than 200.
* HTTP/1.0 messages, header folding (obs-fold), non-token header names,
  UTF-8 validation of header values.
* Duplicate-header merging and full RFC 1123 calendar validation.
* A registry of UPnP device/service types: any structurally valid URN is
  classified, but no type catalogue is maintained.

## 7. Test coverage map

`tests/test_conformance.xi` (18 checks, all fixtures synthetic):

| Test | Covers |
|---|---|
| t1 | canonical M-SEARCH: typed fields, case-insensitive lookup, offsets, `upnp_parse_text` |
| t2 | lower-case header names while preserving as-sent casing |
| t3 | MX bounds 1..5, bad values by offset |
| t4 | missing MAN/ST/HOST, bad MAN/HOST/ST by offset |
| t5 | bad method/target/version/status, start line at EOF, missing headers |
| t6 | NOTIFY alive: typed fields, NT/USN classification, integer headers |
| t7 | NOTIFY byebye minimal form, optionals at -1 |
| t8 | NOTIFY update (BOOTID required) and bad NTS/CC/LOCATION/NT/USN offsets |
| t9 | 200 response: DATE/EXT/LOCATION/ST/USN, optional SERVER |
| t10 | `usn_split` all four kinds and malformed forms |
| t11 | `upnp_classify_target` all kinds and malformed forms |
| t12 | M-SEARCH byte-exact serialisation + round-trip + build errors |
| t13 | NOTIFY alive byte-exact serialisation + round-trip + build errors |
| t14 | canonical header casing and kind names |
| t15 | empty/oversized messages, CR/LF/NUL/control/DEL and header-line violations |
| t16 | truncated buffers and offsets at end of input |
| t17 | authority and LOCATION validation matrix |
| t18 | integer header bounds (32/24/16-bit) and accessor range guards |

## Contracts (batch #48 hardening pass, 2026-10-09)

Runtime-checkable `ensures:` clauses (35, across the 15 functions below) were
added to `src/upnp.xi` in the batch #48 hardening pass (compiler v0.64.1;
`package.xi` is left for the coordinator to bump at integration). All are
`ensures:` with no `requires:`, so the accepted-input domain is unchanged.
Every clause is enforced as a runtime check; the 18-check conformance suite
exercises the contracted entry points and no clause trapped, so none was
dropped. Two consecutive timed green `& .\scripts\port.ps1 -Package xiom.upnp
-TimeoutSec 90` runs ended `port: PASS (passed=18 failed=0 program_exit=0
exit=0)` with the clauses active (11.26 s and 11.02 s; an earlier untimed run
was also 18/18). None is claimed Z3-provable: `xiom-verify` was not run for
this module, so the Z3-provable column is "no" throughout.

Clause inputs are parameters or parameter fields only; no clause indexes a
vector, reads a vector element, compares a `Str` (length via `.len()` only),
uses a module constant, or reads a `&mut` parameter. Guards keep the plan's
families: sentinel guards (`result is Err`, `result == -1`, `result.len() ==
0`, `!result`), exact formulas (`result == m.names.len()`), tag guard pairs
(`i < 0 || i >= m.names.len() => result.len() == 0` / `result.len() > 0 =>
i >= 0 && i < m.names.len()`), bounds/lengths (the 36-byte UUID form,
`kind < 0 || kind > 2 => result.len() == 7`) and all-valid-on-Ok
conjunctions (`result is Ok => host.len() > 0 && mx >= 1 && mx <= 5 &&
st.len() > 0`). `upnp_canonical_header_name` was deliberately left
uncontracted (16-way case-insensitive mapping; no discriminating expression
in the allowed families).

| Function | Clauses | Guarantee (abridged) | Z3-provable | Runtime-checked |
|---|---|---|---|---|
| `upnp_parse` | 2 | empty input or length > 8192 => `Err` | no | yes |
| `upnp_is_device_uuid` | 2 | length != 36 => `false`; `true` => length 36 | no | yes |
| `upnp_validate_authority` | 2 | empty input => `false`; `true` => nonempty | no | yes |
| `upnp_validate_location` | 2 | empty input => `false`; `true` => nonempty | no | yes |
| `upnp_classify_target` | 2 | empty input => `Err`; `Ok` => nonempty | no | yes |
| `usn_split` | 2 | empty input => `Err`; `Ok` => nonempty | no | yes |
| `upnp_header_count` | 1 | exact `m.names.len()` | no | yes |
| `upnp_header` | 2 | drifted vectors => `""`; nonempty result => vectors aligned | no | yes |
| `upnp_has_header` | 2 | drifted vectors => `false`; `true` => vectors aligned | no | yes |
| `upnp_header_name` | 2 | out-of-range `i` => `""`; nonempty => `i` in range | no | yes |
| `upnp_header_value` | 2 | out-of-range `i` => `""`; nonempty => `i` in range | no | yes |
| `upnp_header_offset` | 2 | out-of-range `i` => `-1`; non-`-1` => `i` in range | no | yes |
| `upnp_build_msearch` | 4 | empty host/`st`, `mx` outside 1..5 => `Err`; `Ok` => all valid | no | yes |
| `upnp_build_notify_alive` | 5 | empty host/`nt`/`usn`, `max_age` outside 1..2147483647, `bootid` > 4294967295 or `configid` > 16777215 => `Err` | no | yes |
| `upnp_msg_kind_name` | 3 | unknown `kind` => 7; kind 0 => 8; kind 1 => 6 | no | yes |
