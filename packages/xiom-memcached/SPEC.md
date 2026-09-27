# xiom.memcached -- SPEC

Byte-level layouts actually implemented by `src/memcached.xi`. Everything
below is pinned by `tests/test_conformance.xi`.

## 1. Conventions

- All byte offsets are 0-based into an explicit `data: &Vec[UInt8]` buffer;
  every parser takes an `off` argument and reports `consumed` bytes so a
  caller can walk a stream of concatenated commands or packets.
- Numeric wire fields are unsigned unless stated otherwise. `Int` is the
  codec's integer type; 64-bit quantities are accepted only in
  `0..2^63-1` (see section 4) and larger values are rejected rather than
  wrapped.
- Payload bytes never pass through `Str`: keys, data blocks and packet
  bodies are `Vec[UInt8]`, so `0x00`, `0xC0`, CR and LF are all safe.
- Error messages are stable and prefixed `memcached: `.

## 2. Text protocol

### 2.1 Framing

A request is one command line terminated by CRLF (`0x0D 0x0A`). Storage
commands are followed immediately by exactly `<bytes>` payload bytes and a
second CRLF. A stray CR not followed by LF is skipped while scanning for the
line terminator; payload scanning never scans -- it counts bytes.

### 2.2 Request grammar

```
storage   = ("set" / "add" / "replace" / "append" / "prepend")
            SP key SP flags SP exptime SP bytes [SP "noreply"] CRLF data CRLF
cas       = "cas" SP key SP flags SP exptime SP bytes SP casid [SP "noreply"]
            CRLF data CRLF
retrieval = ("get" / "gets") (SP key)+ CRLF
delete    = "delete" SP key [SP "noreply"] CRLF
delta     = ("incr" / "decr") SP key SP delta [SP "noreply"] CRLF
touch     = "touch" SP key SP exptime [SP "noreply"] CRLF
stats     = "stats" [SP arg] CRLF
flush     = "flush_all" [SP delay] [SP "noreply"] CRLF
simple    = "version" CRLF / "quit" CRLF
```

Verbs, `noreply` and status keywords are parsed case-insensitively and
canonicalized to lowercase verbs / uppercase statuses. Tokens are split on
single ASCII spaces; repeated spaces produce an empty token, which then
fails numeric/key validation (no silent normalization).

| Field | Encoding | Accepted range | Rejection |
|-------|----------|----------------|-----------|
| `key` | raw bytes | 1..250 bytes, no byte `0x00..0x20`, no `0x7F` (`memcached: bad key`) | empty, too long, space/control/DEL |
| `flags` | decimal | 0..4294967295 (u32) | non-digit, overflow (`memcached: bad integer`) |
| `exptime` | decimal | 0..4294967295 (u32) | non-digit, overflow |
| `bytes` | decimal | 0..1048576 (codec cap) | non-digit, overflow, above cap (`memcached: bad bytes`) |
| `casid` | decimal | 0..2^63-1 | non-digit, overflow |
| `delta` | decimal | 0..2^63-1 | non-digit, overflow, negative on encode (`memcached: bad delta`) |
| `delay` | decimal | 0..4294967295; `-1` on encode means "omit" | out of range (`memcached: bad exptime`) |
| `arg` (stats) | ASCII token | bytes 0x21..0x7E (`memcached: bad args`) | empty/space/control |

Token-count rules: `set`/`add`/`replace`/`append`/`prepend` take 5 tokens
plus an optional `noreply`; `cas` takes 6 plus an optional `noreply`;
`delete`/`touch`/`incr`/`decr` take 3 plus optional `noreply`; `get`/`gets`
take 2 or more; `stats` 1 or 2; `flush_all` 1..3 (`[delay] [noreply]` in
that order); `version`/`quit` exactly 1. Anything else is
`memcached: bad args`.

Parsed form (`TextCommand`): `verb` (canonical lowercase), `keys` (one entry
for most verbs, all entries for `get`/`gets`), `flags`, `exptime`, `cas_id`
(-1 when absent), `delta` (-1 when absent), `delay` (-1 when absent),
`noreply`, `data` (raw data block, empty when absent), `arg` (stats argument,
else ""), `consumed`.

### 2.3 Response grammar

Single-line responses parsed by `text_parse_status` (returns
`(status_id, next_offset)`; the detail text of `CLIENT_ERROR`,
`SERVER_ERROR` and `VERSION` is the bytes between the first space and CRLF):

| Status id | Keyword | Meaning |
|-----------|---------|---------|
| 1 | `STORED` | storage success |
| 2 | `NOT_STORED` | add/replace/cas precondition failed |
| 3 | `EXISTS` | `cas` id mismatch |
| 4 | `NOT_FOUND` | key missing |
| 5 | `DELETED` | delete success |
| 6 | `TOUCHED` | touch success |
| 7 | `OK` | generic success (e.g. flush_all) |
| 8 | `ERROR` | unknown command / bad line |
| 9 | `CLIENT_ERROR <text>` | bad request |
| 10 | `SERVER_ERROR <text>` | server-side failure |
| 11 | `VERSION <text>` | version response |
| 12 | `END` | end of a retrieval response |
| 13 | `VALUE` | start of a retrieval value (parsed by the retrieval parser) |

Retrieval response (`text_parse_get_response`):

```
VALUE SP key SP flags SP bytes [SP casid] CRLF data CRLF
... zero or more ...
END CRLF
```

Zero `VALUE` lines is a miss (valid, `consumed` includes `END`). Parsed form
(`TextGetResponse`) is flat to avoid nested struct vectors: `keys`, `flags`
and `cas` are parallel vectors (one entry per value, `cas` = -1 for `get`),
`pool` concatenates all payloads, and `spans` holds two Ints per value
(`start`, `length` into `pool`). Value count is `keys.len()`; helpers
`text_value_key/flags/cas/data` copy out a single value and return
empty/-1 beyond the range.

### 2.4 Text flags

memcached treats the flags word as opaque; this codec documents the two
conventional client bits:

| Bit | Constant | Meaning |
|-----|----------|---------|
| 0x2 | `_FLAG_COMPRESSED` | value is compressed |
| 0x4 | `_FLAG_SERIALIZED` | value is serialized |

- `text_flags_pack(user_flags, compressed, serialized)`: `user_flags` plus
  the set bits (caller keeps the result in 0..4294967295).
- `text_flags_is_compressed(flags)` -> bit 0x2; `text_flags_is_serialized`
  -> bit 0x4.
- `text_flags_user(flags)`: `flags` with 0x2 and 0x4 cleared.

### 2.5 Text error catalog

| Message | Trigger |
|---------|---------|
| `memcached: negative offset` | parse `off` < 0 |
| `memcached: truncated line` | no CRLF in range |
| `memcached: truncated response` | retrieval buffer ends before `END` |
| `memcached: truncated data` | declared data block does not fit the buffer |
| `memcached: bad data block` | data block not followed by CRLF |
| `memcached: bad command` | unknown verb |
| `memcached: bad args` | wrong token count, stray `noreply`, bad stats arg |
| `memcached: bad key` | key is empty, > 250 bytes, or contains space/control/DEL |
| `memcached: bad integer` | non-digit or out-of-range numeric field |
| `memcached: bad bytes` | declared block > 1048576 (encode and parse) |
| `memcached: bad response line` | unknown status keyword or malformed VALUE/END line |
| `memcached: bad storage command` | encode-side unknown storage verb |
| `memcached: bad delta command` | encode-side verb other than `incr`/`decr` |
| `memcached: bad flags` / `bad exptime` / `bad cas id` / `bad delta` | encode-side range/precondition errors |

## 3. Binary protocol

### 3.1 Header (24 bytes)

| Offset | Size | Field | Request (0x80) | Response (0x81) |
|--------|------|-------|----------------|-----------------|
| 0 | 1 | magic | 0x80 | 0x81 |
| 1 | 1 | opcode | section 3.2 | section 3.2 |
| 2 | 2 | key length | BE u16 | BE u16 |
| 4 | 1 | extras length | BE u8 | BE u8 |
| 5 | 1 | data type | 0 | 0 |
| 6 | 2 | vbucket / status | vbucket id | status code (section 3.4) |
| 8 | 4 | total body length | BE u32 | BE u32 |
| 12 | 4 | opaque | BE u32 | BE u32 |
| 16 | 8 | CAS | BE u64, 0..2^63-1 | BE u64, 0..2^63-1 |

Body = `total_body` bytes = extras (`extras_len`) + key (`key_len`) +
value (`total_body - extras_len - key_len`), in that order.
`bin_parse_header` consumes 24 bytes; `bin_parse_packet` consumes
`24 + total_body` and copies extras/key/value into fresh vectors.

### 3.2 Opcodes

| Code | Name | Request extras | Success-response extras |
|------|------|----------------|-------------------------|
| 0x00 | GET | 0 | 4 (flags) |
| 0x01 | SET | 8 (exptime + flags) | 0 |
| 0x02 | ADD | 8 | 0 |
| 0x03 | REPLACE | 8 | 0 |
| 0x04 | DELETE | 0 | 0 |
| 0x05 | INCR | 20 (delta + initial + exptime) | 8 (new value) |
| 0x06 | DECR | 20 | 8 |
| 0x07 | QUIT | 0 | 0 |
| 0x08 | FLUSH | 0 or 4 (expiration) | 0 |
| 0x0A | NOOP | 0 | 0 |
| 0x0B | VERSION | 0 | 0 |
| 0x0C | GETK | 0 | 4 (flags) |
| 0x0D | GETKQ | 0 | 4 (flags) |

`bin_extras_len_is_valid(magic, opcode, extras_len)` implements this table.
Error responses (response magic with status != 0) are exempt from the check
because they legitimately carry no extras.

### 3.3 Extras layouts

```
SET/ADD/REPLACE (8 bytes):
  +0  u32 expiration
  +4  u32 flags

INCR/DECR (20 bytes):
  +0  u64 delta     (0..2^63-1)
  +8  u64 initial   (0..2^63-1)
  +16 u32 expiration

GET/GETK/GETKQ response (4 bytes):
  +0  u32 flags
```

`bin_decode_set_extras` -> `{ exptime, flags }`;
`bin_decode_delta_extras` -> `{ delta, initial, exptime }`;
`bin_decode_get_extras` -> flags (Int). High-bit-set 64-bit values are
rejected with `memcached: delta out of range` / `memcached: initial out of
range` (and `memcached: cas out of range` in the header), because they are
not representable as positive `Int`.

### 3.4 Status codes

Wire values 0x0000..0x0086 as implemented by `bin_status_name` /
`bin_status_id` (`bin_status_is_success(s)` is `s == 0`):

| Code | Name (canonical alias) | Code | Name |
|------|------------------------|------|------|
| 0x0000 | SUCCESS | 0x0020 | AUTH_ERROR |
| 0x0001 | NOT_FOUND (KEY_ENOENT) | 0x0021 | AUTH_CONTINUE |
| 0x0002 | EXISTS (KEY_EEXISTS) | 0x0081 | UNKNOWN_COMMAND |
| 0x0003 | TOO_LARGE (E2BIG) | 0x0082 | OUT_OF_MEMORY |
| 0x0004 | INVALID_ARGUMENTS (EINVAL) | 0x0083 | NOT_SUPPORTED |
| 0x0005 | NOT_STORED | 0x0084 | INTERNAL_ERROR |
| 0x0006 | DELTA_BADVAL | 0x0085 | BUSY |
| 0x0007 | NOT_MY_VBUCKET | 0x0086 | TEMP_FAILURE |

### 3.5 Binary error catalog

| Message | Trigger |
|---------|---------|
| `memcached: negative offset` | parse `off` < 0 |
| `memcached: truncated header` | fewer than 24 bytes at `off` |
| `memcached: truncated body` | body shorter than `total_body` |
| `memcached: bad magic` | first byte not 0x80/0x81 |
| `memcached: unknown opcode` | opcode outside section 3.2 |
| `memcached: bad data type` | data-type byte != 0 |
| `memcached: cas out of range` | header CAS top bit set (>= 2^63) |
| `memcached: bad extras length` | extras > body, extras != 0 (encode), or layout mismatch for the opcode |
| `memcached: bad key length` | key_len > total_body - extras_len (or > 65535 on encode) |
| `memcached: delta out of range` / `initial out of range` | INCR/DECR extras top bits set |
| `memcached: bad status` | response status not in 0..65535 |
| `memcached: bad flags` / `bad exptime` / `bad delta` / `bad initial` / `bad cas` / `bad opaque` / `bad body length` | encode-side range errors |

## 4. Limits and documented deviations

- **u63 ceiling.** CAS, delta and initial are accepted in `0..2^63-1`; a wire
  value with the top bit set is rejected (a signed `Int` cannot carry it).
  Opaque and all 32-bit fields are full-range.
- **1 MiB data cap.** Text data blocks and their declared `bytes` field are
  capped at 1048576 (memcached's default item limit) so "bad size" input is
  rejected deterministically. Keys are capped at 250 bytes.
- **Flat retrieval result.** `TextGetResponse` uses parallel vectors plus a
  pool/spans pair instead of `Vec[Struct]` (compiler limitation); the
  invariants are: `keys.len() == flags.len() == cas.len()`,
  `spans.len() == 2 * keys.len()`.
- **Strict subset.** Only the opcodes, statuses and extras layouts in
  sections 3.2-3.4 are implemented; other opcodes are rejected as unknown.
- **No sockets.** Framing helpers produce/consume byte buffers only; a
  caller supplies the transport.

## 5. Conformance map

`tests/test_conformance.xi` (22 checks):

- t1-t5: text encoder bytes, validation, multi-key retrieval, delete/delta/
  touch, stats/flush/version/quit.
- t6: flag bits.
- t7-t9: request parsing with consumed counts, binary-safe data blocks,
  cas/noreply, multi-key get/gets, remaining verbs.
- t10: malformed request catalog (truncation, non-numeric, bad sizes,
  arity, bad key, negative offset).
- t11: every status keyword plus unknown/truncated cases.
- t12-t14: VALUE/END responses (binary payloads, miss, cas, accessors,
  malformed catalog).
- t15-t18: exact binary request bytes for all 13 opcodes incl. error cases.
- t19: request round-trips with extras decode and consumed counts.
- t20: response encode/parse, GET extras, error responses.
- t21: malformed binary catalog (magic, opcode, datatype, sizes, cas).
- t22: opcode/status/extras tables.
