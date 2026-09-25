# xiom.mqtt

> **Status:** `incubating` -- implemented and green on the local harness,
> NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no sockets) MQTT 3.1.1 packet codec for the
> documented subset: fixed header, CONNECT, CONNACK, PUBLISH, PUBACK,
> SUBSCRIBE, SUBACK, PINGREQ and DISCONNECT.
> **Deps:** `xiom.std` only. The library module imports nothing; the tests
> use `xiom.test`, `xiom.io`, `xiom.string`, `xiom.string.compare` and
> `xiom.encoding.hex` from it. No FFI.

## What it is

`xiom.mqtt` encodes and decodes MQTT 3.1.1 control packets as byte vectors.
It is a codec, not a client: there is no socket layer, no keepalive timer,
no session or retransmission state machine and no MQTT 5 support. Encoders
return fresh `Vec[UInt8]` packets; parsers consume one whole in-memory
packet and return a decoded struct with the payload fields copied out.
Malformed input is rejected with deterministic `Err(Str)` messages from a
closed catalog (`SPEC.md`).

All string fields (client id, will topic/message, username, password,
topic, topic filters) are raw bytes: the codec performs no UTF-8
validation, so it can carry opaque binary client ids and credentials.

## Wire layout

Every packet starts with a fixed header: one byte (`packet_type << 4 |
flags`) followed by the remaining length as a 1..4-byte varint (7 payload
bits per byte, least significant group first, bit 7 continues; maximum
268435455). Encodings must be minimal; a 5th byte or an overlong form such
as `80 00` is rejected.

| Type | Name | Flags | Body |
|---|---|---|---|
| 1 | CONNECT | 0 | protocol name `MQTT`, level 4, connect flags, keepalive, then client id, will topic/message, username, password |
| 2 | CONNACK | 0 | acknowledge flags (bit 0 = session present), return code 0..5 |
| 3 | PUBLISH | DUP/QoS/RETAIN | topic, packet id (QoS > 0), payload |
| 4 | PUBACK | 0 | packet id |
| 8 | SUBSCRIBE | 2 | packet id, (filter, requested QoS) entries |
| 9 | SUBACK | 0 | packet id, codes 0/1/2/0x80 |
| 12 | PINGREQ | 0 | empty |
| 14 | DISCONNECT | 0 | empty |

The fixed header is validated for all packet types 1..14 (types 6, 8 and
10 require flags 2; PUBLISH accepts every nibble except QoS 3; the rest
require 0), even though only the scoped bodies above have encoders and
parsers. PUBLISH with QoS 2 is representable; the QoS 2 handshake packets
(PUBREC/PUBREL/PUBCOMP) are out of scope.

## API

| Function | Returns | Description |
|---|---|---|
| `mqtt_remaining_length_size(n)` | `Int` | Varint byte count; 0 when `n` is outside 0..268435455. |
| `mqtt_encode_remaining_length(n)` | `Result[Vec[UInt8], Str]` | Minimal remaining-length varint (1..4 bytes). |
| `mqtt_decode_remaining_length(data, off)` | `Result[(Int, Int), Str]` | Value and next offset; rejects truncation and overlong forms. |
| `mqtt_encode_fixed_header(type, flags, len)` | `Result[Vec[UInt8], Str]` | Type byte + remaining length; validates type/flags/range. |
| `mqtt_parse_fixed_header(data)` | `Result[MqttFixedHeader, Str]` | Type, flags, remaining length and total header size. |
| `mqtt_topic_is_valid(topic)` | `Bool` | 1..65535 bytes, no `+`/`#` (PUBLISH topic name). |
| `mqtt_topic_filter_is_valid(filter)` | `Bool` | 1..65535 bytes, `#` only as the final byte. |
| `mqtt_encode_connect(c)` | `Result[Vec[UInt8], Str]` | CONNECT from an `MqttConnect` spec. |
| `mqtt_parse_connect(data)` | `Result[MqttConnect, Str]` | Parse CONNECT incl. will/credentials. |
| `mqtt_encode_connack(sp, rc)` | `Result[Vec[UInt8], Str]` | CONNACK with session-present and code 0..5. |
| `mqtt_parse_connack(data)` | `Result[MqttConnack, Str]` | Parse CONNACK. |
| `mqtt_encode_publish(topic, payload, qos, retain, dup, id)` | `Result[Vec[UInt8], Str]` | PUBLISH; `id` must be 0 for QoS 0. |
| `mqtt_parse_publish(data)` | `Result[MqttPublish, Str]` | Parse PUBLISH incl. binary payload. |
| `mqtt_encode_puback(id)` | `Result[Vec[UInt8], Str]` | PUBACK for a packet id. |
| `mqtt_parse_puback(data)` | `Result[Int, Str]` | Packet id of a PUBACK. |
| `mqtt_encode_subscribe(id, filters, qoss)` | `Result[Vec[UInt8], Str]` | SUBSCRIBE from parallel filter/QoS vectors. |
| `mqtt_parse_subscribe(data)` | `Result[MqttSubscribe, Str]` | Packet id, filters and requested QoS values. |
| `mqtt_encode_suback(id, codes)` | `Result[Vec[UInt8], Str]` | SUBACK with codes 0/1/2/0x80. |
| `mqtt_parse_suback(data)` | `Result[MqttSuback, Str]` | Packet id and return codes. |
| `mqtt_encode_pingreq()` | `Vec[UInt8]` | `C0 00`. |
| `mqtt_parse_pingreq(data)` | `Result[Unit, Str]` | Validates an empty-body PINGREQ. |
| `mqtt_encode_disconnect()` | `Vec[UInt8]` | `E0 00`. |
| `mqtt_parse_disconnect(data)` | `Result[Unit, Str]` | Validates an empty-body DISCONNECT. |

The public structs are `MqttFixedHeader{packet_type, flags, remaining_length,
header_len}`, `MqttConnect{client_id, keepalive, clean_session,
will_present, will_qos, will_retain, will_topic, will_message,
username_present, password_present, username, password}`,
`MqttConnack{session_present, return_code}`, `MqttPublish{dup, qos, retain,
topic, packet_id, payload}`, `MqttSubscribe{packet_id, filters, qoss}` and
`MqttSuback{packet_id, codes}`.

## Error model

Every failure is an `Err` whose `Str` is one of the stable messages in
`SPEC.md` (`mqtt: truncated packet`, `mqtt: bad remaining length`,
`mqtt: bad protocol name`, `mqtt: bad protocol level`, `mqtt: bad qos`,
`mqtt: packet id zero`, `mqtt: bad topic`, `mqtt: bad topic filter`,
`mqtt: bad payload`, `mqtt: trailing bytes`, ...). Encoders never write a
partial packet: validation happens before any output byte is produced.
Parsers are all-or-nothing: a packet either decodes fully or yields the
first error in catalog order.

## Usage

```xi
use xiom.mqtt;
use xiom.io;

// Encode a CONNECT (clean session, keepalive 60, client id "client-1").
var c = MqttConnect{
  client_id: Vec[UInt8].new();
  keepalive: 60;
  clean_session: true;
  will_present: false;
  will_qos: 0;
  will_retain: false;
  will_topic: Vec[UInt8].new();
  will_message: Vec[UInt8].new();
  username_present: false;
  password_present: false;
  username: Vec[UInt8].new();
  password: Vec[UInt8].new();
};
let packet = mqtt_encode_connect(&c);      // Ok(10 14 00 04 4d 51 54 54 ...)

// Parse a PUBLISH (QoS 1) back into its fields.
let parsed = mqtt_parse_publish(&wire_bytes);
match parsed {
  Ok(p) => {
    let qos: Int = p.qos;
    let packet_id: Int = p.packet_id;
    let payload: Vec[UInt8] = p.payload;
    io.println("payload bytes: " + xiom.convert.int_to_string(payload.len()));
  },
  Err(e) => { io.println("mqtt error: " + e); },
}
```

Building `MqttConnect` field by field is verbose; the tests show the
pattern (a local helper with defaults plus field assignment). Bind
`Vec` struct fields to locals before passing them by reference.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.mqtt
```

Expected: the section-4 namespace check passes, 21 `[PASS]` lines, and a
final `port: PASS (passed=21 failed=0 program_exit=0 exit=0)`.

## Limitations

- **Codec only.** No sockets, no reconnect/keepalive logic, no session or
  retransmission state; QoS 1/2 delivery is not implemented beyond the
  packet bytes, and the QoS 2 handshake packets are out of scope.
- **MQTT 3.1.1, protocol level 4 only.** MQTT 5 (properties, topic
  aliases, reason codes) and MQTT 3.1 (the old client-id rules and the
  username-required-with-password rule) are not supported.
- **Whole in-memory packets.** Parsers require the entire packet in one
  buffer (no streaming/partial decode); the fixed header is the only
  incremental entry point.
- **Raw byte strings.** No UTF-8 validation, no NUL/control-character
  rules; `mqtt_topic_filter_is_valid` is a light structural check (`#`
  only last), not full wildcard-level validation.
- **Empty-string presence.** An empty client id/username/password cannot
  be expressed via the presence booleans: bytes and flags must agree
  (`mqtt_encode_connect` rejects disagreement).
- **No encode error channel for PINGREQ/DISCONNECT** (they cannot fail)
  and no error channel for the `Bool` topic predicates.
- Not thread-safe; the functions are plain free functions over values.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
