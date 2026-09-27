# xiom.tor -- byte-level specification

This document records exactly what `src/tor.xi` implements, at byte level.
Sources: the public Tor specifications (spec.torproject.org) -- "Cells
(messages on channels)", "Preliminaries" (message lengths), "Negotiating
channels" (VERSIONS/NETINFO), "Relay cells", "Opening streams" (BEGIN,
CONNECTED), "Closing streams" (END), "Flow control" (SENDME) and "Remote
hostname lookup" (RESOLVE, RESOLVED). All integers are big-endian. The
implementation is a pure decoder: errors are `Err("tor: <what> at <offset>")`
with offsets relative to the buffer passed in.

## 1. Sizes

| Name | Value | Meaning |
|------|-------|---------|
| `TOR_CELL_BODY_LEN` | 509 | fixed-length cell body |
| `TOR_CELL_NARROW_LEN` | 512 | v3-and-earlier fixed cell = 2 + 1 + 509 |
| `TOR_CELL_WIDE_LEN` | 514 | v4-and-later fixed cell = 4 + 1 + 509 |
| `TOR_RELAY_HEADER_LEN` | 11 | relay envelope header |
| `TOR_RELAY_DIGEST_FIELD_LEN` | 4 | relay digest field |
| `TOR_RELAY_MAX_DATA_FIXED` | 498 | 509 - 11, max relay data in a fixed cell |
| `TOR_SENDME_DIGEST_LEN` | 20 | SENDME v1 digest |
| `TOR_MAX_VARIABLE_LEN` | 65535 | u16 Length ceiling |
| `TOR_MIN_LINK_VERSION` | 3 | versions 1 and 2 are obsolete |

## 2. Cell framing

Narrow fixed-length cell (link protocol v < 4), 512 bytes:

```
offset  size  field
0       2     CircID (big-endian; 0 under the auto-detection rule)
2       1     Command
3       509   Body (zero padded)
```

Wide fixed-length cell (link protocol v >= 4), 514 bytes:

```
offset  size  field
0       4     CircID (big-endian)
4       1     Command
5       509   Body (zero padded)
```

Variable-length cell:

```
offset  size  field
0       w     CircID (w = 2 or 4 depending on the link version)
w       1     Command
w+1     2     Length (big-endian u16)
w+3     L     Body (L = Length)
```

A command is variable-length when it is `VERSIONS` (7) or >= 128; every
other command is fixed-length. The total consumed length is
`3 + 509` / `5 + 509` for fixed cells and `w + 3 + L` for variable cells.

### 2.1 Width selection

`tor_parse_cell(data, off)` -- auto detection: read the first two bytes; if
either is nonzero the cell is wide (4-byte CircID), otherwise narrow
(2-byte CircID). This is the classic byte rule and matches the port
specification.

`tor_parse_cell_v(data, off, link_version)` -- authoritative form:
`link_version >= 4` selects the wide framing, `link_version < 4`
(including 0, the pre-negotiation VERSIONS case) the narrow one, and a
negative version is rejected. Use this when the negotiated link version is
known; see the ambiguity note in section 8.

## 3. Link commands

| Value | Identifier | Framing |
|-------|------------|---------|
| 0 | PADDING | fixed |
| 1 | CREATE | fixed |
| 2 | CREATED | fixed |
| 3 | RELAY | fixed |
| 4 | DESTROY | fixed |
| 5 | CREATE_FAST | fixed |
| 6 | CREATED_FAST | fixed |
| 7 | VERSIONS | variable |
| 8 | NETINFO | fixed |
| 9 | RELAY_EARLY | fixed |
| 10 | CREATE2 | fixed |
| 11 | CREATED2 | fixed |
| 12 | PADDING_NEGOTIATE | fixed |
| >= 128 | (undefined here) | variable |

`tor_link_cmd_name` returns these identifiers; `tor_cell_is_variable_cmd`
implements the classification. Unknown ids decode structurally and are
named `"UNKNOWN"`. This module does not decode CREATE/CREATED/CREATE2/
CREATED2/DESTROY/PADDING bodies.

## 4. VERSIONS handshake (command 7)

Body: a series of big-endian u16 link versions, in wire order. An odd byte
count is an error (`"tor: versions body has odd length at <off>"`); an
empty body parses with `consumed == 0`. `tor_versions_choose(sent, recv)`
returns the highest version present in both lists and >= 3, or 0 when there
is none (versions 1 and 2 are ignored as obsolete). `tor_link_version_valid`
accepts 3 and above.

## 5. RELAY envelope (command 3/9 payload)

```
offset  size  field
0       1     Relay command
1       2     Recognized
3       2     StreamID
5       4     Digest
9       2     Length
11      L     Data (L = Length)
```

`consumed = 11 + L`. The digest is copied out verbatim and **never
verified**: verification requires the running SHA-1/SHA3 digest keyed by the
circuit hop, which is out of scope. `tor_parse_relay` rejects a header
shorter than 11 bytes and a Length that overruns the available bytes.

| Value | Relay command |
|-------|---------------|
| 1 | BEGIN |
| 2 | DATA |
| 3 | END |
| 4 | CONNECTED |
| 5 | SENDME |
| 6 | EXTEND |
| 7 | EXTENDED |
| 8 | TRUNCATE |
| 9 | TRUNCATED |
| 10 | DROP |
| 11 | RESOLVE |
| 12 | RESOLVED |
| 13 | BEGIN_DIR |
| 14 | EXTEND2 |
| 15 | EXTENDED2 |

EXTEND/EXTENDED/EXTEND2/EXTENDED2/TRUNCATE/TRUNCATED/DROP/BEGIN_DIR bodies
are not decoded (they carry crypto material or no body). DROP and DATA have
no special structure beyond the envelope.

## 6. Typed RELAY payloads

All decoders take the RELAY `Data` bytes (section 5, offset 11).

### 6.1 BEGIN (relay command 1)

```
ADDRPORT  NUL-terminated: ADDRESS | ':' | PORT
FLAGS     4 bytes, optional (omitted when zero)
```

- The address is taken up to the last `:` before the NUL; an IPv6 address
  is bracketed (`[::1]:443`) and the brackets are stripped from the result.
- PORT is decimal, 0..65535; the specification recommends 1..65535 but
  this codec accepts 0. A missing port, a non-digit or a value > 65535 is
  `"tor: begin bad port"` / `"tor: begin port missing"`.
- FLAGS, when present, must be exactly 4 bytes; `has_flags` reports its
  presence and `flags` its u32 value (0 when absent).

### 6.2 CONNECTED (relay command 4)

| Body length | Interpretation |
|-------------|----------------|
| 0 | empty; kind NONE |
| 8 | IPv4: 4 address octets + 4-byte TTL |
| 25 | IPv6: 4 zero octets, type byte 6, 16 address octets, 4-byte TTL |

Any other length is `"tor: connected bad body length"`. In the 25-byte
form the first four octets must be zero (`"tor: connected bad ipv6
marker"`) and the type byte must be 6 (`"tor: connected bad ipv6 type"`).
The address is raw network-order bytes, not text.

### 6.3 END (relay command 3)

First byte: reason. An empty body is treated as `REASON_MISC` (1). For
every reason except `REASON_EXITPOLICY` (4) the body must be exactly one
byte (`"tor: end body has trailing bytes"` otherwise). For EXITPOLICY the
optional address block is accepted at these total lengths, mirroring the
specification's tolerance for a missing TTL or address:

| Total length | Meaning |
|--------------|---------|
| 1 | reason only |
| 5 | 4-byte IPv4 address, TTL absent (reported as 4294967295) |
| 9 | 4-byte IPv4 address + 4-byte TTL |
| 17 | 16-byte IPv6 address, TTL absent |
| 21 | 16-byte IPv6 address + 4-byte TTL |

Anything else is `"tor: end bad exitpolicy body"`. Reason ids: 0 NONE
(empty-body default reported as MISC instead), 1 MISC, 2 RESOLVEFAILED,
3 CONNECTREFUSED, 4 EXITPOLICY, 5 DESTROY, 6 DONE, 7 TIMEOUT, 8 NOROUTE,
9 HIBERNATING, 10 INTERNAL, 11 RESOURCELIMIT, 12 CONNRESET, 13 TORPROTOCOL,
14 NOTDIRECTORY; unknown reasons parse and are named `"UNKNOWN"`.

### 6.4 SENDME (relay command 5)

```
offset  size  field
0       1     Version
1       2     DataLen
3       DataLen  Data
```

- An empty body is the legacy v0 form (`legacy == true`, version 0,
  data_len 0, digest empty).
- Version 1 requires `DataLen >= 20`; `digest` receives the first 20 DATA
  bytes and extra DATA is ignored. `DataLen < 20` is
  `"tor: sendme digest too short"`. The digest is the rolling digest of
  the DATA-bearing relay cell that triggered the SENDME and is **never
  verified** here.
- Version 0 with a non-empty body and unknown versions are accepted
  structurally; `digest` stays empty.
- A circuit-level SENDME has StreamID 0; a stream-level SENDME carries the
  stream id. The distinction is the envelope's `stream_id`, not the body.

### 6.5 RESOLVE (relay command 11)

The hostname as a NUL-terminated string, and the NUL must be the final
byte. `name` holds the bytes before the NUL. Errors: empty body, missing
NUL, empty name, trailing bytes.

### 6.6 RESOLVED (relay command 12)

One answer (the first of possibly several):

```
offset  size  field
0       1     Type
1       1     Length
2       Length  Value
2+Length 4    TTL
```

`consumed = 6 + Length`, so callers can walk further answers. Known types:
0 HOSTNAME (value is a DNS-order name, not NUL-terminated), 4 IPv4 (value
must be 4 bytes), 6 IPv6 (value must be 16 bytes), 240 ERROR_TRANSIENT,
241 ERROR_NONTRANSIENT. A wrong IPv4/IPv6 value length is rejected
(`"tor: resolved ipv4 length"` / `"tor: resolved ipv6 length"`); unknown
types keep their raw value bytes.

## 7. NETINFO (command 8)

```
offset  size  field
0       4     TIME (big-endian seconds)
4       1     Other ATYPE
5       1     Other ALEN
6       ALEN  Other address value
6+ALEN  1     NMYADDR
repeat NMYADDR times:
        +1    ATYPE
        +1    ALEN
        +ALEN address value
```

`consumed` covers the declared fields only; trailing bytes are ignored as
the specification requires. ATYPE/ALEN pairing is recorded as declared
(the caller may validate 4/4 and 6/16). Errors: truncated header, truncated
other address, missing NMYADDR, truncated declared address, all with
`"at <off>"`.

## 8. Documented limitations and ambiguities

- No cryptography of any kind: relay digests, recognized values, SENDME
  digests and cell ciphertext are opaque bytes.
- `tor_parse_cell`'s auto-detection cannot see the width of a wide cell
  whose CircID high half is zero (NETINFO, zero-CircID DESTROY/VERSIONS on
  a v4 link): those parse as narrow. Use `tor_parse_cell_v` with the
  negotiated link version. A narrow cell with a nonzero CircID is likewise
  only reliably parsed by `tor_parse_cell_v`.
- Variable framing here follows the classic rule (command 7 or >= 128);
  the obsolete v1/v2 link protocols are not supported.
- Bodies of CREATE/CREATED/CREATE2/CREATED2/DESTROY/PADDING,
  EXTEND/EXTENDED/EXTEND2/EXTENDED2/TRUNCATE/TRUNCATED and CERTS/
  AUTH_CHALLENGE/AUTHENTICATE are not decoded.
- `tor_ascii_to_str` is deliberately narrow: printable ASCII 0x20..0x7E
  only; NUL, control bytes and >= 128 are rejected, so a Str built from
  wire bytes can never contain a NUL.
