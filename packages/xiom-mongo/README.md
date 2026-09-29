# xiom.mongo

> **Status:** `incubating` -- conformance-tested (23/23); published at `v0.1.1` on the XIOM registry.
> **Scope:** BSON document decoding plus MongoDB wire-message structural
> framing. No queries, no driver, no sockets, no encoders.
> **Deps:** none (the library imports only `xiom.convert` and `xiom.string`
> from `xiom.std`; tests additionally use `xiom.io`, `xiom.test` and
> `xiom.encoding.hex`).

## What it is

`xiom.mongo` is a pure-XIOM decoder for the structural layer of MongoDB:

- **BSON documents** (spec v1.1): the int32 total length, the element stream
  up to the 0x00 terminator, cstring keys, embedded documents and arrays,
  and every standard element type -- double, string, binary, undefined,
  ObjectId, bool, UTC datetime, null, regex, javascript, symbol,
  code-with-scope, int32, timestamp, int64, decimal128, min-key and max-key
  -- with a documented nesting depth cap of 100.
- **Wire messages**: the 16-byte header plus `OP_MSG` (both section kinds and
  the checksumPresent flag), `OP_COMPRESSED` (payload preserved raw), and the
  legacy opcodes `OP_QUERY`, `OP_REPLY`, `OP_INSERT`, `OP_UPDATE`,
  `OP_DELETE`, `OP_GET_MORE` and `OP_KILL_CURSORS`.
- **One message per parse** with a consumed-byte count, so concatenated
  messages can be walked from a stream. Unknown opcodes are preserved raw
  instead of rejected; truncation, bad lengths, malformed framing and
  malformed BSON are rejected with deterministic, byte-offset-carrying
  errors.

Decoded documents live in a flat, pre-order token stream (`BsonDoc`) with
parallel vectors and O(1) navigation, mirroring `xiom.cbor` / `xiom.amqp`;
messages expose opcode fields, section tables and the top-level documents
found in the body. `SPEC.md` has the exact byte layouts and the full error
catalogs.

## API sketch

| Group | Functions |
|---|---|
| BSON decode | `bson_parse_document`, `bson_max_depth` |
| BSON navigation | `bson_token_count`, `bson_root`, `bson_kind`, `bson_parent`, `bson_first_child`, `bson_child_count`, `bson_child`, `bson_next_sibling`, `bson_token_start`, `bson_token_end`, `bson_find_key`, `bson_find_key_str` |
| BSON values | `bson_key_len/_bytes`, `bson_payload_len/_bytes`, `bson_int_value`, `bson_bool_value`, `bson_binary_len/_subtype`, `bson_oid_bytes`, `bson_decimal_bytes`, `bson_word_low/_high`, `bson_string_bytes`, `bson_regex_pattern_bytes/_options_bytes` |
| Kind/opcode constants | `bson_kind_*`, `mongo_op_*`, `mongo_opcode_name`, `mongo_opcode_known`, `mongo_msg_flag_*` |
| Wire decode | `mongo_parse_message`, `mongo_header_size` |
| Wire fields | `mongo_msg_consumed`, `mongo_msg_message_length`, `mongo_msg_request_id`, `mongo_msg_response_to`, `mongo_msg_opcode`, `mongo_msg_opcode_name/_known`, `mongo_msg_flags`, `mongo_msg_number_to_skip`, `mongo_msg_number_to_return`, `mongo_msg_cursor_id`, `mongo_msg_cursor_count/_id_count/_id_at`, `mongo_msg_starting_from`, `mongo_msg_number_returned`, `mongo_msg_zero`, `mongo_msg_namespace_bytes` |
| Wire bodies | `mongo_msg_body_start/_end/_body`, `mongo_msg_orig_opcode`, `mongo_msg_uncompressed_size`, `mongo_msg_compressor_id`, `mongo_msg_payload`, `mongo_msg_checksum_bytes` |
| Wire documents | `mongo_msg_doc_count`, `mongo_msg_doc_root`, `mongo_msg_body_doc_index`, `mongo_msg_section_count/_kind/_start/_end/_ident_bytes` |

## Usage

```xi
use xiom.mongo;

fn walk(data: Vec[UInt8]) {
  // One complete wire message from the start of `data`.
  let r = mongo_parse_message(data);
  if r.is_ok {
    let m: MongoMsg = r.value;
    let op = mongo_msg_opcode(&m);       // e.g. 2013 = OP_MSG
    let docs = mongo_msg_doc_count(&m);  // top-level BSON documents found
    let used = mongo_msg_consumed(&m);   // advance a stream by this much
    if docs > 0 {
      let root = mongo_msg_doc_root(&m, 0);
      let stream: BsonDoc = m.docs;
      let t = bson_find_key_str(&stream, root, "ok");
      let ok = bson_int_value(&stream, t);
    }
  }
}
```

```xi
// Standalone BSON document:
let b = bson_parse_document(document_bytes);
if b.is_ok {
  let d: BsonDoc = b.value;
  let t = bson_find_key_str(&d, 0, "name");
  io.println(hex.hex_encode(&bson_string_bytes(&d, t)));
}
```

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 23 `[PASS]` lines, then `xiom.mongo: all tests passed`, exit 0.
The suite builds every BSON and wire buffer synthetically in-test (typed
documents, nesting, binary payloads containing 0x00, both OP_MSG section
kinds, malformed lengths and truncations) and checks exact byte-offset error
messages.

## Non-goals

No BSON encoding, no query or command semantics, no driver, no sockets, no
authentication, no compression/decompression, no decimal128 or double value
math, no UTF-8 validation. See `SPEC.md` section 10 for the precise list.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
