# xiom.amqp

Pure-XIOM AMQP 0-9-1 frame codec: protocol header, method frames with
schema-driven arguments, content header frames (the 13 basic properties),
body frames and heartbeat frames. No FFI, no sockets and no session state:
this package turns byte buffers into decoded frames and back.

> **Status:** implemented (v0.1.0). Scope is the codec only; there is no
> broker client, connection state machine, heartbeating loop or TCP layer.

## What is implemented

* **Protocol header** -- `"AMQP" 0x00 0x00 0x09 0x01`, with the 0-9
  revision 0 header also accepted on parse.
* **Frame header** -- type octet (1 method, 2 content header, 3 body,
  8 heartbeat), channel u16, payload size u32, payload, frame-end 0xCE.
  Bad frame ends, truncated payloads, payloads over `frame_max` and
  trailing bytes are rejected.
* **Method frames** for the connection (10), channel (20), exchange (40),
  queue (50) and basic (60) methods listed in [SPEC.md](SPEC.md), with
  argument types octet, short, long, long-long, shortstr, longstr, table,
  array and LSB-first packed bits.
* **Field tables and arrays** with recursion up to 32 open containers and
  the field tags `t/f/s/I/l/D/b/A/T/F/V/x`.
* **Content header frames** for class 60 with all 13 basic properties
  (content-type ... app-id) selected by the property flag word.
* **Body and heartbeat frames**, including binary bodies that contain
  0x00 or 0xCE bytes.
* **Round-trip serialization**: every decoded frame re-encodes to the
  exact input bytes (canonical encodings).

Everything is bounded by deterministic `Err(Str)` messages; the full error
catalog and byte tables live in [SPEC.md](SPEC.md).

## Usage

Build and encode a `connection.start-ok` method frame:

```xiom
use xiom.amqp;

fn to_bytes(s: Str) -> Vec[UInt8] {
  var v = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    v.push(byte_at(s, i));
    i = i + 1;
  }
  return v;
}

fn start_ok_frame() -> Vec[UInt8] {
  var args = amqp_tree_new();
  amqp_tree_begin_table(&mut args);          // client-properties
  amqp_tree_end(&mut args);
  let mech = to_bytes("PLAIN");
  amqp_tree_push_shortstr(&mut args, &mech);
  let response = to_bytes("guest");
  amqp_tree_push_longstr(&mut args, &response);
  let locale = to_bytes("en_US");
  amqp_tree_push_shortstr(&mut args, &locale);

  let frame = AmqpMethodFrame{
    channel: 0; class_id: 10; method_id: 11; args: args;
  };
  let r = amqp_encode_method_frame(&frame);
  if !r.is_ok {
    return Vec[UInt8].new();
  }
  return r.value;
}
```

Parse a frame and read a field-table entry (for example `server-properties`
in `connection.start`, argument index 2):

```xiom
let r = amqp_parse_method_frame(&bytes, amqp_default_frame_max());
if r.is_ok {
  let f: AmqpMethodFrame = r.value;
  let a: AmqpTree = f.args;
  let props = amqp_tree_arg_node(&a, 2);       // the server-properties table
  let key = to_bytes("capabilities");
  let n = amqp_tree_find_key(&a, props, &key);
  if n >= 0 {
    let kind: Int = amqp_tree_kind_at(&a, n);
    let raw: Vec[UInt8] = amqp_tree_bytes_at(&a, n);
  }
}
```

Encode a content header with `content-type`, `delivery-mode` and `priority`:

```xiom
var flags = amqp_basic_flag(0) + amqp_basic_flag(3) + amqp_basic_flag(4);
let h = AmqpContentHeader{
  channel: 1; class_id: 60; weight: 0; body_size: payload.len(); flags: flags;
  content_type: to_bytes("application/json"); content_encoding: Vec[UInt8].new();
  headers: amqp_tree_new(); delivery_mode: 2; priority: 5;
  correlation_id: Vec[UInt8].new(); reply_to: Vec[UInt8].new();
  expiration: Vec[UInt8].new(); message_id: Vec[UInt8].new();
  timestamp: 0; msg_type: Vec[UInt8].new(); user_id: Vec[UInt8].new();
  app_id: Vec[UInt8].new();
};
let encoded = amqp_encode_content_header_frame(&h);
```

## API groups

| Group | Functions |
|---|---|
| Protocol header | `amqp_encode_protocol_header`, `amqp_encode_protocol_header_rev`, `amqp_parse_protocol_header` |
| Frame header | `amqp_parse_frame_header`, `amqp_default_frame_max`, `amqp_frame_end_marker`, `amqp_frame_method/header/body/heartbeat` |
| Method schemas | `amqp_method_schema`, `amqp_argtype_*` |
| Value tree | `amqp_tree_new`, `amqp_tree_push_*`, `amqp_tree_begin_*`, `amqp_tree_end`, accessors and `amqp_tree_find_key` |
| Method frames | `amqp_parse_method_frame`, `amqp_encode_method_frame` |
| Content header | `amqp_parse_content_header_frame`, `amqp_encode_content_header_frame`, `amqp_basic_flag` |
| Body / heartbeat | `amqp_parse_body_frame`, `amqp_encode_body_frame`, `amqp_parse_heartbeat_frame`, `amqp_encode_heartbeat_frame` |

## Scope limits

* One frame per buffer; parsers reject trailing bytes (slice concatenated
  frames before parsing).
* Only the methods and field tags listed in SPEC.md decode; unknown
  methods and tags are rejected instead of being skipped.
* No networking, connection state, heartbeats on a timer, or SASL.
* `frame_max` bounds the payload size; encoders do not enforce it.
* 64-bit values >= 2^63 are rejected because `Int` is signed 64-bit.

## Tests

21 conformance checks with synthetic frames built in-test (no data files):

```
cd <repo root>
& .\scripts\port.ps1 -Package xiom.amqp
```

The suite covers each frame type, all implemented methods, bit packing,
field-table recursion, every supported field tag, shortstr/longstr bounds,
round-trips, malformed/truncated input and the value-tree navigation API.
