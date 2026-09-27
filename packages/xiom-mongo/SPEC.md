# xiom.mongo byte-level specification

This document describes exactly what `xiom.mongo` (version 0.1.0) decodes. It
is the implemented subset of BSON (spec v1.1) and the MongoDB wire protocol,
written against the wire format rather than the full protocol grammar.
Everything not described here is either rejected with a deterministic error
(see the error catalogs) or explicitly out of scope (see Limitations).

`Int` is the XIOM signed 64-bit integer. All multi-byte integers on the wire
are **little-endian** unless stated otherwise; `int32`/`int64` are
two's-complement.

## 1. BSON document frame

```
offset  size  field
0       4     int32 total document length (includes the length and the
              terminating 0x00)
4       ...   element stream: zero or more elements
last    1     0x00 terminator (at offset total_length - 1)
```

An element is:

```
1       type byte (see section 2)
n       cstring key: bytes followed by a single 0x00
m       value payload, per the type byte
```

`bson_parse_document(data)` requires `data` to contain exactly one document:
the declared length must fit the buffer, the terminator must be exactly at
`length - 1`, and bytes after the document are rejected. Embedded documents
and arrays are parsed recursively; their element streams must consume exactly
their declared length.

Arrays are parsed exactly like documents (their keys are the numeric index
strings the caller encoded; this codec does not validate that they are
numeric or contiguous). A `code_w_scope` value's scope document must exactly
fill the remainder of its declared total length.

## 2. Element types

| byte | name | value layout | token `value` / `aux` | payload |
|---|---|---|---|---|
| 0x01 | double | 8 raw bytes | low 32 bits / high 32 bits (raw words) | the 8 bytes |
| 0x02 | string | int32 len (includes NUL) + len bytes, last byte 0x00 | len | content bytes, no NUL |
| 0x03 | embedded document | document frame | declared length | the document bytes |
| 0x04 | array | document frame | declared length | the document bytes |
| 0x05 | binary | int32 len + subtype byte + len bytes | len / subtype | the len bytes |
| 0x06 | undefined | none | - | empty |
| 0x07 | ObjectId | 12 bytes | - | the 12 bytes |
| 0x08 | bool | 1 byte (0 or 1; anything else rejected) | 0/1 | the byte |
| 0x09 | datetime | int64 milliseconds | milliseconds | the 8 bytes |
| 0x0A | null | none | - | empty |
| 0x0B | regex | cstring pattern + cstring options | - | both cstrings incl. NULs |
| 0x0D | javascript | string layout | len | code bytes, no NUL |
| 0x0E | symbol | string layout | len | symbol bytes, no NUL |
| 0x0F | code-with-scope | int32 total (>= 14) + string code + scope document | total | code bytes, no NUL |
| 0x10 | int32 | 4 bytes | value | the 4 bytes |
| 0x11 | timestamp | 8 raw bytes | low 32 (increment) / high 32 (seconds) | the 8 bytes |
| 0x12 | int64 | 8 bytes | value | the 8 bytes |
| 0x13 | decimal128 | 16 bytes | - | the 16 bytes |
| 0x7F | max-key | none | - | empty |
| 0xFF | min-key | none | - | empty |

Type byte 0x0C (DBPointer) and every other byte are rejected as unknown.
Strings are opaque bytes: no UTF-8 validation is performed, and an embedded
0x00 inside declared string content is accepted (only the final byte must be
0x00). Binary payloads may contain 0x00 anywhere; subtype 0x02 "old binary"
is not special-cased (the leading length stays inside the payload).

For code-with-scope, the scope document is a single child token of the 0x0F
element (the code bytes are the element payload).

## 3. Token model

`BsonDoc` stores a flat token stream in parallel vectors, one token per
element, in depth-first pre-order:

* token 0 is the root document container (kind
  `bson_kind_root_document()` = 100);
* element tokens carry their BSON type byte as `kind` (0x01..0x13, 0x7F,
  0xFF); embedded documents (0x03) and arrays (0x04) are containers whose
  children are their elements; a code-with-scope element (0x0F) has exactly
  one child, its scope document (kind 100);
* `first_child` / `child_count` enumerate direct children, `next_sibling`
  links them (subtrees interleave pre-order, so adjacency is not sibling
  order);
* `start` / `end` delimit the whole element (type byte through the value end;
  for containers through the closing 0x00);
* `key_start` / `key_end` delimit the key bytes without the NUL (-1 for the
  root and scope documents, which have no key);
* `payload_start` / `payload_end` delimit the value payload as tabled in
  section 2;
* `value` / `aux` hold the parsed scalar or raw words as tabled above.

Accessors (`bson_kind`, `bson_child`, `bson_find_key`, ...) are bounds-safe:
out-of-range indices return -1 (or an empty vector), never crash.

## 4. Nesting depth

Depth is the number of enclosing containers; the root document has depth 0.
A container at depth 100 is accepted; a container at depth 101 (or deeper)
is rejected with `bson: nesting depth exceeds limit of 100 at <offset>`,
where `<offset>` is the offset of the rejected document's int32 length.
`bson_max_depth()` returns 100.

## 5. BSON error catalog

Every message starts with `bson: `; `<off>` is a byte offset into the buffer
being parsed (the BSON buffer for `bson_parse_document`, the message buffer
inside `mongo_parse_message`).

| message | produced by |
|---|---|
| `bson: truncated document at <off>` | fewer than 4 bytes for the length, or the declared length crosses the parse limit |
| `bson: bad document length <n> at <off>` | declared length < 5 |
| `bson: bad document length at <off>` | the 0x00 terminator is not at `length - 1` |
| `bson: missing document terminator at <off>` | element stream reached the declared end without a 0x00 |
| `bson: truncated element at <off>` | fixed-size value (or its length prefix) does not fit |
| `bson: unterminated key at <off>` | no 0x00 before the document end |
| `bson: bad string length <n> at <off>` | string/javascript/symbol/code length < 1 |
| `bson: truncated string at <off>` | declared string bytes do not fit |
| `bson: unterminated string at <off>` | final string byte is not 0x00 |
| `bson: bad binary length <n> at <off>` | negative binary length |
| `bson: truncated binary at <off>` | declared binary bytes do not fit |
| `bson: bad boolean <b> at <off>` | bool byte other than 0 or 1 |
| `bson: unterminated regex at <off>` | pattern or options cstring has no 0x00 |
| `bson: bad code_w_scope length <n> at <off>` | total < 14, or the scope document does not exactly fill the total |
| `bson: truncated code_w_scope at <off>` | declared total crosses the enclosing document |
| `bson: unknown element type <t> at <off>` | type byte outside the table in section 2 |
| `bson: nesting depth exceeds limit of 100 at <off>` | depth cap |
| `bson: trailing data after document at <off>` | `bson_parse_document` input extends past the document |

## 6. Wire message header (16 bytes)

```
offset  size  field
0       4     int32 messageLength (includes the header)
4       4     int32 requestID
8       4     int32 responseTo
12      4     int32 opCode
16      ...   opcode body
```

`mongo_parse_message(data)` parses one message from the start of `data`.
`messageLength` must be >= 16 and <= the buffer length; bytes after the
declared length are left unconsumed so callers can walk concatenated
messages (`mongo_msg_consumed` returns messageLength). For every known
opcode, the body parser must consume the declared body exactly; anything
left over is `mongo: trailing bytes at <off>`.

Unknown opcodes (anything outside section 7) are **not** rejected: the
message parses with `opcode` set, `mongo_msg_opcode_known` false,
`mongo_opcode_name` "", and the body bytes preserved verbatim in
`mongo_msg_payload`.

## 7. Opcodes

| opcode | name |
|---|---|
| 1 | OP_REPLY |
| 2001 | OP_UPDATE |
| 2002 | OP_INSERT |
| 2004 | OP_QUERY |
| 2005 | OP_GET_MORE |
| 2006 | OP_DELETE |
| 2007 | OP_KILL_CURSORS |
| 2012 | OP_COMPRESSED |
| 2013 | OP_MSG |

### 7.1 OP_MSG (2013)

```
offset  size  field
16      4     int32 flagBits
20      ...   one or more sections
```

Flag bits implemented/recognised: bit 0 `checksumPresent` (1), bit 1
`moreToCome` (2), bit 16 `exhaustAllowed` (65536). Other bits are accepted
and preserved in `flags` (no rejection). When bit 0 is set, the last 4 bytes
of the message are a checksum: they are excluded from section parsing
(`mongo_msg_body_end` becomes `messageLength - 4`) and are exposed raw by
`mongo_msg_checksum_bytes`; the value is never verified or computed.

Sections:

* kind 0 (body): `0x00` + document. At most one per message; if present it
  must be the last section.
* kind 1 (document sequence): `0x01` + int32 size + cstring identifier +
  documents. `size` counts itself, the identifier (including its NUL) and
  the documents. `size` must be >= 10 and must not cross the message end;
  at least one document must fit inside the section.

At least one section must be present. A message may consist of document
sequences only; `mongo_msg_body_doc_index` then returns -1. Section metadata
is available through `mongo_msg_section_count/_kind/_start/_end/_ident_bytes`.

### 7.2 OP_COMPRESSED (2012)

```
offset  size  field
16      4     int32 originalOpcode
20      4     int32 uncompressedSize (must be >= 0)
24      1     compressorId
25      ...   compressed payload (opaque)
```

The payload is preserved verbatim in `mongo_msg_payload`; no decompression
is attempted, and the inner message is not parsed (even for compressorId 0,
which the protocol defines as "noop").

### 7.3 OP_QUERY (2004)

```
offset  size  field
16      4     int32 flags
20      n     fullCollectionName cstring (must be non-empty)
20+n    4     int32 numberToSkip
24+n    4     int32 numberToReturn
28+n    m     query document
28+n+m  k     optional returnFieldsSelector document
```

A second document is parsed only when at least 5 bytes remain (the minimum
document size); 1..4 leftover bytes are `mongo: trailing bytes`.

### 7.4 OP_REPLY (1)

```
offset  size  field
16      4     int32 responseFlags
20      8     int64 cursorID
28      4     int32 startingFrom
32      4     int32 numberReturned (must be >= 0)
36      ...   numberReturned documents
```

### 7.5 OP_INSERT (2002)

```
offset  size  field
16      4     int32 flags
20      n     fullCollectionName cstring (must be non-empty)
20+n    ...   one or more documents to the end of the message
```

### 7.6 OP_UPDATE (2001)

```
offset  size  field
16      4     int32 ZERO (must be 0)
20      n     fullCollectionName cstring (must be non-empty)
20+n    4     int32 flags
24+n    m     selector document
24+n+m  k     update document
```

### 7.7 OP_DELETE (2006)

```
offset  size  field
16      4     int32 ZERO (must be 0)
20      n     fullCollectionName cstring (must be non-empty)
20+n    4     int32 flags
24+n    m     selector document
```

### 7.8 OP_GET_MORE (2005)

```
offset  size  field
16      4     int32 ZERO (must be 0)
20      n     fullCollectionName cstring (must be non-empty)
20+n    4     int32 numberToReturn
24+n    8     int64 cursorID
```

### 7.9 OP_KILL_CURSORS (2007)

```
offset  size  field
16      4     int32 ZERO (must be 0)
20      4     int32 numberOfCursorIDs (must be >= 0)
24      8*N   N int64 cursor IDs
```

Each cursor ID is stored; `mongo_msg_cursor_id_at` indexes them.

## 8. Documents found in messages

`MongoMsg.docs` is one shared BSON token stream over the whole message
buffer, and `doc_roots` lists the token index of each top-level document in
order of appearance:

| opcode | `doc_roots` order |
|---|---|
| OP_MSG | document-sequence documents in section order, then the kind-0 body document if present |
| OP_QUERY | query, then returnFieldsSelector |
| OP_REPLY | the returned documents |
| OP_INSERT | the inserted documents |
| OP_UPDATE | selector, then update |
| OP_DELETE | selector |
| others | none |

Message-level documents start at BSON depth 0. Access them with
`mongo_msg_doc_count` / `mongo_msg_doc_root` plus the `bson_*` accessors, or
use `mongo_msg_body_doc_index` for the OP_MSG body document.

## 9. Message error catalog

Every message starts with `mongo: ` except errors raised by the nested BSON
parser, which keep the `bson: ` prefix and offsets into the same message
buffer.

| message | produced by |
|---|---|
| `mongo: truncated message header at 0` | buffer shorter than 16 bytes |
| `mongo: bad message length <n> at 0` | messageLength < 16 |
| `mongo: truncated message at 0: declared <n> bytes, have <m>` | messageLength > buffer |
| `mongo: truncated message body at <off>` | fixed opcode body field does not fit |
| `mongo: truncated section at <off>` | OP_MSG section framing does not fit |
| `mongo: bad section size <n> at <off>` | OP_MSG kind-1 size < 10 |
| `mongo: unterminated identifier at <off>` | OP_MSG kind-1 identifier has no 0x00 |
| `mongo: empty document sequence at <off>` | OP_MSG kind-1 section holds no document |
| `mongo: unknown section kind <k> at <off>` | OP_MSG section byte outside 0/1 |
| `mongo: duplicate body section at <off>` | second OP_MSG kind-0 section |
| `mongo: body section is not last at <off>` | section after the OP_MSG kind-0 body |
| `mongo: missing sections at <off>` | OP_MSG with no section |
| `mongo: truncated checksum at <off>` | checksumPresent but the message is too short |
| `mongo: truncated op_compressed header at <off>` | OP_COMPRESSED body shorter than 9 bytes |
| `mongo: bad uncompressed size <n> at <off>` | negative uncompressedSize |
| `mongo: unterminated namespace at <off>` | legacy namespace cstring has no 0x00 |
| `mongo: empty namespace at <off>` | legacy namespace is empty |
| `mongo: bad zero field <n> at <off>` | OP_UPDATE/OP_DELETE/OP_GET_MORE/OP_KILL_CURSORS ZERO != 0 |
| `mongo: bad number_returned <n> at <off>` | negative OP_REPLY numberReturned |
| `mongo: bad cursor count <n> at <off>` | negative OP_KILL_CURSORS numberOfCursorIDs |
| `mongo: truncated cursor ids at <off>` | cursor ID array does not fit the body |
| `mongo: missing insert documents at <off>` | OP_INSERT without a document |
| `mongo: truncated document at <off>` | OP_REPLY announces more documents than fit |
| `mongo: trailing bytes at <off>` | bytes in the declared body the opcode does not use |

## 10. Limitations

* Decode-only: there are no encoders; BSON and messages are parsed, never
  serialized.
* Structure-only: no query/command semantics, no driver, no sockets, no
  authentication, no cursor management.
* One message per call from the start of the buffer; concatenated messages
  must be sliced by `mongo_msg_consumed`.
* OP_COMPRESSED payloads stay opaque; no zlib/zstd/snappy support and no
  recursive parse of the inner opcode.
* OP_MSG checksums are preserved but neither verified nor computed, and
  unknown flag bits are accepted.
* No UTF-8 validation of BSON strings; no decimal128 or double value math
  (raw words/bytes only; this module never uses Float64).
* BSON array keys are not validated as numeric or contiguous.
* BSON type 0x0C (DBPointer) is rejected as unknown.
* `Int` is signed 64-bit: uint64 BSON values with bit 63 set (timestamps,
  raw double/timestamp words) are split into two 32-bit raw words rather
  than converted.
* Namespaces and identifiers are returned as opaque bytes; no
  `database.collection` validation and no collection-name length checks.
* The OP_MSG kind-1 section size minimum (10) is enforced even though a
  protocol-minimal section with a short identifier could be smaller; this
  codec prefers a single deterministic floor.
