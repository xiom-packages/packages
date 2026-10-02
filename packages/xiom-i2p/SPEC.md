# xiom.i2p -- SPEC

Specification of the SAM v3 subset modelled by `src/i2p.xi` (module
`xiom.i2p`, version 0.1.0). This is a **model**: message structure and
state, not a client implementation.

## 1. Scope

In scope:

1. Canonical I2P destination strings: 387 raw bytes rendered as 516
   base64 characters, with the null certificate; key split into the
   256-byte encryption key and 128-byte signing key; certificate and
   signature-type tables.
2. Destination-hash b32 addresses (52 lowercase base32 characters plus
   `.b32.i2p`) and general `.i2p` hostname syntax.
3. SAM v3 line framing (`VERB SUBCOMMAND [KEY=value ...]\n`), quoted
   values, bounded keys/values, printable-ASCII-only payloads.
4. The SAM v3 result-code table and reply field access.
5. The session lifecycle surface: `HELLO VERSION`, `DEST GENERATE`,
   `SESSION CREATE`, `SESSION ADD`, `SESSION REMOVE`; styles `STREAM`,
   `DATAGRAM`, `RAW`; session ids; NEW/ACTIVE/CLOSED/FAILED states.
6. The stream state surface: `STREAM CONNECT`, `STREAM ACCEPT`,
   `STREAM FORWARD`, the `SILENT` flag; CONNECTING/ACCEPTING/FORWARDING/
   OPEN/FAILED/CLOSED states; inbound peer hashes.
7. In-memory address book (name -> destination) and lease-set shapes.

## 2. Non-goals

Out of scope for 0.1.0 (documented, tested as such where applicable):

- **Transport**: no sockets, no dialing the SAM bridge, no I/O, no
  retries, no timeouts, no clock.
- **Cryptography**: keys, hashes and signatures are opaque bytes; nothing
  is generated, encrypted, signed, verified or hashed. `addr_b32_host`
  encodes a caller-supplied 32-byte hash; it does not compute SHA-256.
- **Destination key certificates**: only the null-certificate form
  (type 0, length 0) is parsed. Destinations carrying a key certificate
  (e.g. EdDSA) have a different, signature-type-dependent length and are
  rejected as non-canonical by `dest_parse_b64`.
- **DATAGRAM and RAW message bodies**: sessions with those styles can be
  created and inspected, but `DATAGRAM SEND`, `RAW SEND` and their
  connect/accept/forward cousins are not modelled (STREAM is).
- **Option semantics**: SESSION CREATE options are carried and validated
  syntactically (bounded keys/values) but not interpreted.
- **Persistence**: address books and lease sets live in values returned
  by functions; there is no disk format.
- **SAM v1/v2 and I2CP**, lease management, tunnel building, router
  interaction, streaming library semantics.

## 3. Canonical destination

Layout of the 387 raw bytes:

| Offset | Size | Field |
| --- | --- | --- |
| 0 | 256 | encryption public key |
| 256 | 128 | signing public key |
| 384 | 1 | certificate type (0 = null) |
| 385 | 2 | certificate length, big-endian (0) |

The base64 string has exactly 516 characters because 387 is a multiple of
3 (no `=` padding for canonical destinations; the trailing certificate
bytes are zero, so canonical strings end in `AAAA`).

`dest_parse_b64` is strict:

1. length exactly 516;
2. canonical base64 (see section 4);
3. decoded length exactly 387;
4. certificate type 0 and length 0.

Errors: `i2p: destination length must be 516`,
`i2p: destination must decode to 387 bytes`,
`i2p: destination certificate invalid`, or the base64 error.

`dest_sig_type` reports `DSA_SHA1` (0) for the null certificate -- the
legacy default for a certificate-free destination. The signature-type
table (`dest_sig_type_name`) covers types 0..9:

| Id | Name | Id | Name |
| --- | --- | --- | --- |
| 0 | DSA_SHA1 | 5 | RSA_SHA256_2048 |
| 1 | ECDSA_SHA256_P256 | 6 | RSA_SHA384_3072 |
| 2 | ECDSA_SHA384_P384 | 7 | RSA_SHA512_4096 |
| 3 | ECDSA_SHA512_P521 | 8 | EdDSA_SHA512_Ed25519ph |
| 4 | EdDSA_SHA512_Ed25519 | 9 | RedDSA_SHA512_Ed25519 |

Certificate type constants 0..5 (`I2P_CERT_NULL` .. `I2P_CERT_KEY`) are
exposed for callers; only type 0 can occur in a canonical 387-byte value.

## 4. Codecs (hand-rolled, KAT-pinned)

### base64 (RFC 4648 section 4)

- `b64_encode`: standard alphabet, canonical `=` padding; `""` -> `""`.
- `b64_decode`: strict and canonical. Rejects a length that is not a
  multiple of 4, any character outside the alphabet, `=` anywhere except
  the final one or two positions, data after padding, and non-zero unused
  bits in the last data character. Offsets are byte offsets.
- KATs (RFC 4648): `f` -> `Zg==`, `fo` -> `Zm8=`, `foo` -> `Zm9v`,
  `foob` -> `Zm9vYg==`, `fooba` -> `Zm9vYmE=`, `foobar` -> `Zm9vYmFy`.

### base32 (RFC 4648 section 6)

- `b32_encode`: **lowercase**, unpadded; the b32 address label is exactly
  52 characters for a 32-byte hash.
- `b32_decode`: strict and canonical; rejects leftover character counts
  1, 3 and 6, uppercase or non-alphabet characters, and non-zero final
  padding bits. Unpadded KATs: `f` -> `my`, `fo` -> `mzxq`,
  `foo` -> `mzxw6`, `foob` -> `mzxw6yq`, `fooba` -> `mzxw6ytb`,
  `foobar` -> `mzxw6ytboi`; 32 zero bytes -> 52 `a` characters.

## 5. Addresses

`addr_kind(s)` classifies with precedence base64 destination > b32 host >
`.i2p` host > invalid:

- `I2P_ADDR_B64_DEST`: a canonical 516-character destination string.
- `I2P_ADDR_B32_HOST`: exactly 52 lowercase base32 characters plus
  `.b32.i2p` (the label decodes to 32 bytes canonically).
- `I2P_ADDR_I2P_HOST`: at most 255 bytes, ending in `.i2p`, one or more
  dot-separated labels of 1..63 lowercase LDH characters (letters,
  digits, hyphen) with no leading/trailing hyphen and no empty label.
  Uppercase, underscore, a trailing dot and `foo` without the suffix are
  invalid. Note that a valid b32 host also satisfies the general host
  rule but classifies as `I2P_ADDR_B32_HOST`.

`addr_b32_host(hash)` requires exactly 32 hash bytes and appends
`.b32.i2p`; `addr_b32_hash(host)` is its inverse.

## 6. SAM v3 line framing

Grammar:

```
line      := command " " subcommand *( " " field ) LF
command   := word                     ; non-empty, no space, no '='
subcommand:= word
field     := key "=" value
key       := 1..64 of A-Z a-z 0-9 . _ -
value     := 0..2048 printable ASCII bytes
```

- Lines are at most 4096 bytes including `\n`; a bare `\r` before `\n` is
  accepted. Bytes below 0x20 (tab included) and above 0x7E are rejected
  with a byte offset.
- Tokens are separated by one or more spaces.
- A value containing a space, `"` or `\` is written double-quoted with
  `\"` and `\\` escapes; `sam_parse_line` decodes them, and
  `sam_build_line` emits them, so the pair round-trips exactly.
- The first two tokens must not contain `=`; every later token must.
  Duplicate keys are preserved in order; `sam_msg_field` returns the
  first.
- On the build side, `keys`/`values` must be parallel, at most 64 fields,
  with bounded printable values.

Error convention: `Err("i2p: <what>")`, with ` at offset <n>` appended
for byte-level failures.

## 7. Commands modelled

| Command | Builder | Notes |
| --- | --- | --- |
| `HELLO VERSION MIN= MAX=` | `sam_hello_line` | packed `major*100+minor`; `sam_version_parse("3.3") = 303` |
| `DEST GENERATE` | `sam_dest_generate_line` | no fields |
| `SESSION CREATE STYLE= ID= DESTINATION= [opts]` | `sam_session_create_line` | requires a session |
| `SESSION ADD ID= DESTINATION=` | `sam_session_add_line` | validates the destination |
| `SESSION REMOVE ID= DESTINATION=` | `sam_session_remove_line` | validates the destination |
| `STREAM CONNECT ID= DESTINATION= [SILENT=true]` | `sam_stream_connect_line` | requires a CONNECT target |
| `STREAM ACCEPT ID= [SILENT=true]` | `sam_stream_accept_line` | |
| `STREAM FORWARD ID= PORT= [SILENT=true]` | `sam_stream_forward_line` | |
| `NAMING LOOKUP NAME=` | `sam_naming_lookup_line` | target must classify |

`DEST REPLY`, `SESSION STATUS`, `STREAM STATUS`, `NAMING REPLY` and
`HELLO REPLY` are parsed generically: `sam_parse_line`, then
`sam_reply_code` (RESULT field -> code) and `sam_msg_field` for
`DESTINATION`, `NAME`, `VALUE`, `VERSION`, `MESSAGE`, ...

## 8. Result codes

| Id | Name | Id | Name |
| --- | --- | --- | --- |
| 0 | OK | 7 | PEER_NOT_FOUND |
| 1 | INVALID_KEY | 8 | TIMEOUT |
| 2 | DUPLICATE_DEST | 9 | ALREADY_ACCEPTING |
| 3 | INVALID_SIGTYPE | 10 | NO_LEASESET |
| 4 | DUPLICATE_ID | 11 | KEY_NOT_FOUND |
| 5 | INVALID_ID | 12 | NOVERSION |
| 6 | CANT_REACH_PEER | 13 | I2P_ERROR |

Unknown names map to `I2P_RESULT_UNKNOWN` (-1) from `sam_result_code` and
`sam_reply_code` returns `Err("i2p: unknown result code")`.

## 9. State machines

### Session

```
NEW --SESSION STATUS RESULT=OK--> ACTIVE
NEW/ACTIVE --any other RESULT--> FAILED
FAILED --SESSION STATUS RESULT=OK--> ACTIVE
any --session_close--> CLOSED (terminal)
```

- `session_create` validates id (1..64 printable, no space, no `=`),
  style and destination; the primary destination is `dests[0]`.
- `session_add_dest` appends an extra destination (no duplicates, at most
  8 extras, rejected on a closed session).
- `session_remove_dest` removes an extra destination; the primary cannot
  be removed -- use `session_close` (documented deviation: SAM closes a
  session when its last destination is removed; this model requires the
  explicit close).

### Stream (STREAM sessions only)

```
CONNECT:  CONNECTING --STREAM STATUS OK--> OPEN;  non-OK --> FAILED
ACCEPT:   ACCEPTING  --STREAM STATUS OK--> ACCEPTING (ready);
                     --stream_inbound--> OPEN with peer;  non-OK --> FAILED
FORWARD:  FORWARDING --STREAM STATUS OK--> FORWARDING;  non-OK --> FAILED
any --stream_close--> CLOSED (terminal; later status codes ignored)
```

`stream_connect`/`stream_accept`/`stream_forward` require an ACTIVE STREAM
session; FORWARD ports are 1..65535; `stream_inbound` requires ACCEPTING
and a base64 32-byte peer hash. Only an OPEN stream `stream_can_send`.

## 10. Address book and lease set

- `I2pAddressBook`: parallel `names`/`dests`; `book_set` inserts,
  replaces in place, or reports `i2p: address book full` at 256 entries;
  names must be valid `.i2p` hosts, destinations canonical.
- `I2pLeaseSet`: `dest_b64` plus parallel `peers` / `tunnel_ids` /
  `end_dates` arrays. `leaseset_add` mirrors all three arrays (16 leases
  max), validates a 32-byte base64 peer hash, tunnel id 0..2^32-1 and a
  positive end date. `leaseset_all_expired(now_ms)` is true when no lease
  ends after `now_ms` (empty set: true). Accessors guard index and length
  drift.

## 11. Error text

All errors are `Str` values beginning with `i2p:`. Parser offsets are
relative to the string or line handed in. The conformance suite pins a
representative set of exact messages, including:

```
i2p: empty sam line
i2p: sam line too long
i2p: sam line not newline-terminated
i2p: sam line needs a command and a subcommand
i2p: sam field missing '='
i2p: sam field keys/values length mismatch
i2p: base64 length not a multiple of 4
i2p: base64 non-canonical padding bits at offset N
i2p: destination length must be 516
i2p: destination certificate invalid
i2p: b32 address requires a 32-byte hash
i2p: invalid address book name
i2p: session id invalid
i2p: session not active
i2p: forward port out of range
i2p: lease set full
```

## 12. Test surface

`tests/test_conformance.xi` (module `i2p_tests`) runs 24 checks covering
sections 3-11 and is fully deterministic: synthetic 387-byte destinations
built in-test, RFC 4648 vectors, exact error strings, state transitions
and round-trips of every builder through `sam_parse_line`.
