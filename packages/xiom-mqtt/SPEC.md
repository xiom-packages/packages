# xiom.mqtt -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.mqtt`, version `0.1.0`).
Module: `src/mqtt.xi` (`module xiom.mqtt`).
Depends on `xiom.std` only (platform dependency; the module itself imports
nothing).

## Scope

A pure-XIOM (no FFI, no sockets) MQTT 3.1.1 packet codec over in-memory
`Vec[UInt8]` buffers for a documented subset:

- the fixed header: packet type 1..14, type flags, remaining-length varint
  (1..4 bytes, canonical form enforced);
- CONNECT (protocol name `MQTT`, level 4, connect flags, keepalive, client
  id, will topic/message, username/password);
- CONNACK (session present, return codes 0..5);
- PUBLISH (DUP/QoS/RETAIN, topic, packet id when QoS > 0, payload) and
  PUBACK;
- SUBSCRIBE (packet id, topic filters and requested QoS) and SUBACK (codes
  0/1/2/0x80);
- PINGREQ and DISCONNECT (empty bodies).

All string fields are raw bytes (`Vec[UInt8]`): the codec performs no
UTF-8 validation and no normalization.

## Non-goals

- **No sockets / transport.** The API works on whole in-memory packets.
- **No session state machine.** No keepalive timers, retransmission,
  message ordering or packet-id allocation.
- **No MQTT 5.** No properties, reason codes, topic aliases or shared
  subscriptions.
- **No QoS 2 flow.** PUBLISH with QoS 2 is representable, but
  PUBREC/PUBREL/PUBCOMP and the QoS 2 handshake are out of scope. There are
  also no encoders/parsers for PUBREC (5), PUBREL (6), PUBCOMP (7) or
  UNSUBSCRIBE/UNSUBACK (10/11) bodies; their fixed headers are still
  accepted by `mqtt_parse_fixed_header` and rejected as
  `mqtt: bad packet type` by the typed parsers.
- **No streaming decode.** No partial-packet accumulation; the fixed header
  is the only incremental entry point.
- **No UTF-8/NUL validation** of topics, filters or credentials, and no
  full wildcard-level validation of topic filters.

## Fixed header

```
byte 0:  packet_type (high nibble, 1..14) | flags (low nibble)
bytes 1..4: remaining length, varint (present in every packet)
```

`header_len` (returned by `mqtt_parse_fixed_header`) is the type byte plus
the varint bytes, so the body starts at `header_len` and is
`remaining_length` bytes long.

Flag rules (`_flags_ok`):

| Packet type | Required flags |
|---|---|
| PUBLISH (3) | any nibble except QoS bits = 3 (DUP bit 3, QoS bits 2-1, RETAIN bit 0) |
| PUBREL (6), SUBSCRIBE (8), UNSUBSCRIBE (10) | 2 |
| all other types 1..14 | 0 |
| type 0 or 15 | rejected: `mqtt: bad packet type` |

## Remaining length varint

- 7 payload bits per byte, least significant group first; bit 7 is the
  continuation flag; the final byte has it clear.
- 1..4 bytes, value range 0..268435455 (2^28-1).
- Encodings must be **canonical**: the consumed byte count must equal
  `mqtt_remaining_length_size(value)`. Overlong forms such as `80 00`
  (zero in two bytes) are rejected.
- A continuation bit on the 4th byte (a 5th byte would be required) is
  rejected.

| Value | Encoded bytes |
|---|---|
| `0` | `00` |
| `127` | `7f` |
| `128` | `80 01` |
| `16383` | `ff 7f` |
| `16384` | `80 80 01` |
| `2097151` | `ff ff 7f` |
| `2097152` | `80 80 80 01` |
| `268435455` | `ff ff ff 7f` |

## Packet layouts

All multi-byte integers are big-endian. "String" means a two-byte length
(0..65535) followed by that many raw bytes.

### CONNECT (type 1, flags 0)

```
string   protocol name            must be 4 bytes: 4D 51 54 54 ("MQTT")
u8       protocol level           must be 4
u8       connect flags
u16      keepalive                seconds, 0..65535
string   client id
[will]   string will topic        present iff will flag = 1; non-empty
[will]   string will message      present iff will flag = 1; may be empty
[user]   string username          present iff username flag = 1
[pass]   string password          present iff password flag = 1
```

Connect flags:

| Bit | Name | Rule |
|---|---|---|
| 0 | reserved | must be 0 |
| 1 | clean session | 0/1 |
| 2 | will flag | 0/1 |
| 3-4 | will QoS | 0/1/2 when will flag = 1; 3 rejected; 0 when will flag = 0 |
| 5 | will retain | 0 when will flag = 0 |
| 6 | password flag | 0/1 (a password without a username is legal in 3.1.1) |
| 7 | username flag | 0/1 |

An empty will topic is rejected (`mqtt: bad topic`). The encoder also
requires the presence booleans and payload bytes to agree: non-empty
username/password/will fields with the matching flag clear are rejected
(`mqtt: bad connect flags`), and a present will with an empty topic is
rejected. A zero-length client id is allowed by the codec (session
semantics are the broker's concern).

### CONNACK (type 2, flags 0)

```
u8  acknowledge flags   only bit 0 (session present); bits 1-7 must be 0
u8  return code         0..5 (0 = accepted, 1..5 = refusals)
```

A non-zero return code with session present set is rejected
(MQTT-3.2.2-4). The body must be exactly two bytes.

### PUBLISH (type 3)

```
u8      flags        DUP (bit 3), QoS (bits 2-1, 0/1/2), RETAIN (bit 0)
string  topic        non-empty, no '+' (0x2B) or '#' (0x23) wildcard
u16     packet id    present iff QoS > 0; must be non-zero
bytes   payload      the rest of the body, may be empty or binary
```

QoS 0 packets must not carry a packet id (`mqtt: unexpected packet id` on
encode); QoS > 0 packets must carry a non-zero one. Packet ids are 1..65535.

### PUBACK (type 4, flags 0)

```
u16 packet id   non-zero
```

The body must be exactly two bytes.

### SUBSCRIBE (type 8, flags 2)

```
u16 packet id           non-zero
repeat 1..N times:
  string filter         1..65535 bytes
  u8     requested QoS  0/1/2; 3 (0x03) is rejected
```

At least one filter is required. The structural filter check
(`mqtt_topic_filter_is_valid`) accepts `+` anywhere, allows at most one
`#`, and requires it to be the final byte; it is not full wildcard-level
validation.

### SUBACK (type 9, flags 0)

```
u16 packet id       non-zero
repeat 1..N times:
  u8 return code    0 (QoS 0), 1 (QoS 1), 2 (QoS 2) or 0x80 (128, failure)
```

At least one code is required.

### PINGREQ (type 12, flags 0) / DISCONNECT (type 14, flags 0)

No variable header and no payload: `remaining_length` must be 0
(`C0 00` and `E0 00` respectively).

## API contract

All functions are free functions in module `xiom.mqtt`.

```xi
pub type MqttFixedHeader = { packet_type: Int; flags: Int; remaining_length: Int; header_len: Int; }
pub type MqttConnect = { client_id: Vec[UInt8]; keepalive: Int; clean_session: Bool;
                         will_present: Bool; will_qos: Int; will_retain: Bool;
                         will_topic: Vec[UInt8]; will_message: Vec[UInt8];
                         username_present: Bool; password_present: Bool;
                         username: Vec[UInt8]; password: Vec[UInt8]; }
pub type MqttConnack = { session_present: Bool; return_code: Int; }
pub type MqttPublish = { dup: Bool; qos: Int; retain: Bool; topic: Vec[UInt8];
                         packet_id: Int; payload: Vec[UInt8]; }
pub type MqttSubscribe = { packet_id: Int; filters: Vec[Vec[UInt8]]; qoss: Vec[Int]; }
pub type MqttSuback = { packet_id: Int; codes: Vec[Int]; }

pub fn mqtt_remaining_length_size(n: Int) -> Int
pub fn mqtt_encode_remaining_length(n: Int) -> Result[Vec[UInt8], Str]
pub fn mqtt_decode_remaining_length(data: &Vec[UInt8], off: Int) -> Result[(Int, Int), Str]
pub fn mqtt_encode_fixed_header(packet_type: Int, flags: Int, remaining_length: Int) -> Result[Vec[UInt8], Str]
pub fn mqtt_parse_fixed_header(data: &Vec[UInt8]) -> Result[MqttFixedHeader, Str]
pub fn mqtt_topic_is_valid(topic: &Vec[UInt8]) -> Bool
pub fn mqtt_topic_filter_is_valid(filter: &Vec[UInt8]) -> Bool
pub fn mqtt_encode_connect(c: &MqttConnect) -> Result[Vec[UInt8], Str]
pub fn mqtt_parse_connect(data: &Vec[UInt8]) -> Result[MqttConnect, Str]
pub fn mqtt_encode_connack(session_present: Bool, return_code: Int) -> Result[Vec[UInt8], Str]
pub fn mqtt_parse_connack(data: &Vec[UInt8]) -> Result[MqttConnack, Str]
pub fn mqtt_encode_publish(topic: &Vec[UInt8], payload: &Vec[UInt8], qos: Int, retain: Bool, dup: Bool, packet_id: Int) -> Result[Vec[UInt8], Str]
pub fn mqtt_parse_publish(data: &Vec[UInt8]) -> Result[MqttPublish, Str]
pub fn mqtt_encode_puback(packet_id: Int) -> Result[Vec[UInt8], Str]
pub fn mqtt_parse_puback(data: &Vec[UInt8]) -> Result[Int, Str]
pub fn mqtt_encode_subscribe(packet_id: Int, filters: &Vec[Vec[UInt8]], qoss: &Vec[Int]) -> Result[Vec[UInt8], Str]
pub fn mqtt_parse_subscribe(data: &Vec[UInt8]) -> Result[MqttSubscribe, Str]
pub fn mqtt_encode_suback(packet_id: Int, codes: &Vec[Int]) -> Result[Vec[UInt8], Str]
pub fn mqtt_parse_suback(data: &Vec[UInt8]) -> Result[MqttSuback, Str]
pub fn mqtt_encode_pingreq() -> Vec[UInt8]
pub fn mqtt_parse_pingreq(data: &Vec[UInt8]) -> Result[Unit, Str]
pub fn mqtt_encode_disconnect() -> Vec[UInt8]
pub fn mqtt_parse_disconnect(data: &Vec[UInt8]) -> Result[Unit, Str]
```

Behavioral contract:

- Every typed parser requires the packet to occupy **exactly** the buffer
  (short body -> `mqtt: truncated packet`, extra bytes ->
  `mqtt: trailing bytes`) and the fixed-header type to match the parser.
- Parsers copy string fields into fresh vectors; they never alias the
  input buffer.
- Encoders validate every field before writing a byte and return `Err`
  without producing output on failure.
- `mqtt_parse_fixed_header` consumes only the header and does not require
  the body to be present.
- Complexity is linear in the buffer/packet size unless noted (all fixed
  header and PUBACK/CONNACK paths are O(1)).

## Error catalog

| Condition | Error text |
|---|---|
| `off < 0` in `mqtt_decode_remaining_length` | `mqtt: negative offset` |
| Buffer ends before the packet/varint/body/string does | `mqtt: truncated packet` |
| Buffer extends past `header_len + remaining_length` | `mqtt: trailing bytes` |
| Remaining-length varint is overlong or needs a 5th byte | `mqtt: bad remaining length` |
| Encode remaining length outside 0..268435455 | `mqtt: remaining length out of range` |
| Fixed-header type 0 or 15, or parser/type mismatch | `mqtt: bad packet type` |
| Flag nibble not the reserved value for the type | `mqtt: bad fixed header flags` |
| QoS bits = 3 in a PUBLISH (or will/requested QoS = 3) | `mqtt: bad qos` |
| CONNECT protocol name is not `MQTT` (length > 4 or bad bytes) | `mqtt: bad protocol name` |
| CONNECT protocol level is not 4 | `mqtt: bad protocol level` |
| Reserved connect-flag bit set, will QoS/retain without will flag, flag/payload disagreement | `mqtt: bad connect flags` |
| Empty will topic, empty/wildcard PUBLISH topic | `mqtt: bad topic` |
| Empty SUBSCRIBE filter, or `#` not as the final byte | `mqtt: bad topic filter` |
| Packet id 0 where one is required | `mqtt: packet id zero` |
| Packet id < 0 or > 65535 | `mqtt: packet id out of range` |
| QoS 0 PUBLISH carrying a packet id | `mqtt: unexpected packet id` |
| CONNACK return code outside 0..5 | `mqtt: bad return code` |
| CONNACK reserved flag bits set, or session present with a non-zero code | `mqtt: bad connack flags` |
| SUBACK code outside 0/1/2/0x80 | `mqtt: bad suback code` |
| CONNECT keepalive outside 0..65535 | `mqtt: bad keepalive` |
| Any binary string longer than 65535 bytes on encode | `mqtt: string too long` |
| SUBSCRIBE filters/qoss vector length mismatch | `mqtt: filters/qos length mismatch` |
| Body of the wrong size (PUBACK/CONNACK != 2 bytes, PINGREQ/DISCONNECT not empty, SUBSCRIBE/SUBACK empty list) | `mqtt: bad payload` |

## Test plan

`tests/test_conformance.xi` (`module mqtt_tests`, 21 named tests; the
hello-style `main` prints `[PASS]`/`[FAIL]` per test, a summary line and
returns the failure count). Coverage:

1. remaining length encode pinned at 0, 127, 128, 16383, 16384, 2097151,
   2097152, 268435455 plus `mqtt_remaining_length_size` bounds;
2. remaining length decode pinned at the same boundaries incl. non-zero
   offsets in a stream;
3. truncation, overlong (`80 00`, `81 00`, `ac 82 00`, `80 80 80 00`),
   5-byte (`ff ff ff ff`), negative offset and out-of-range encode errors;
4. fixed header encode pinned (`c000`, `1014`, `3a05`, `820c`, `e000`) and
   type/flags/QoS/range errors;
5. fixed header parse pinned (incl. `30 ff ff ff 7f`, `header_len` 5) and
   type/flags/QoS/varint errors;
6. CONNECT minimal encode pinned (`10 14 ... "client-1"`);
7. CONNECT full encode pinned (clean session off, will QoS 1 + retain,
   username + password);
8. CONNECT parse of both payloads with all fields checked;
9. CONNECT parse rejects bad protocol name, bad protocol level, reserved
   flag bit and wrong packet type;
10. CONNECT parse rejects will QoS 3, retain without will, trailing bytes
    and truncation;
11. CONNECT encode validates keepalive, will QoS, empty will topic,
    flag/payload disagreement and 65535-byte string bounds;
12. CONNACK encode/parse pinned incl. session present, refusal code 5,
    reserved flags, truncated/trailing bodies and wrong type;
13. PUBLISH QoS 0 encode/parse pinned;
14. PUBLISH QoS 1/2 with DUP/RETAIN and a binary payload incl. round-trip;
15. PUBLISH errors: QoS 3, packet id 0/70000, unexpected id for QoS 0,
    empty/wildcard topics, truncation, trailing bytes and the topic
    predicate;
16. PUBACK encode/parse pinned and error catalog;
17. SUBSCRIBE encode/parse pinned (id 2, filters `a` and `b/#`, QoS 0/1);
18. SUBSCRIBE errors (length mismatch, empty list, empty/bad filters,
    QoS 3, id 0, truncation) and the filter predicate;
19. SUBACK encode/parse pinned incl. code 0x80 and code errors;
20. PINGREQ/DISCONNECT pinned bytes, empty-body parse, non-empty body and
    type errors;
21. encode -> parse -> encode round-trips for CONNECT (full), PUBLISH
    (200-byte payload), SUBSCRIBE and SUBACK.

Run from the repository root:

```
& .\scripts\port.ps1 -Package xiom.mqtt
```

Last verified: compiler 0.61.3,
`port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Known limitations

- Codec only: no transport, timers, sessions, retransmission or QoS 2
  handshake packets.
- MQTT 3.1.1 protocol level 4 only; no MQTT 5 properties or 3.1 quirks.
- Whole-packet, in-memory API; no streaming decode.
- Raw byte strings: no UTF-8 validation, no wildcard-level filter
  validation beyond "`#` last".
- Presence booleans and payload bytes must agree on encode; an empty
  client id/username/password cannot be expressed with its flag set.
- `MqttSubscribe.filters` is a `Vec[Vec[UInt8]]` (index-aligned with
  `qoss`); the other decoded structs store one flat vector per field.
- Plain value functions; no thread-safety concerns beyond the underlying
  `Vec` ownership model.

## Compiler / stdlib notes for v0.61.3

- `Ok`/`Err` construction is confined to the leaf helpers `_ok_*`/`_err_*`
  (constructing Results in functions that also build struct values
  miscompiles in this compiler).
- Raw bytes widen through `(x as Int) & 0xFF` before use; the fixed-header
  nibbles are extracted with division/modulo (`b / 16`, `b % 16`) rather
  than shifts.
- `Vec[UInt8]` struct fields are bound to typed locals before being passed
  by reference (`&struct.field` yields an empty vector).
- Tests compare `Str` errors with `str_compare` (`xiom.string.compare`),
  never with `==`, and use typed locals for every `Vec` read.
