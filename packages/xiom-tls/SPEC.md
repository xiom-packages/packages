# xiom.tls -- specification

Byte-level layouts actually implemented by `src/tls.xi` (v0.1.0). Every
"at an offset" statement below is enforced: the parser copies bytes, checks
exact bounds and returns `Err("tls: <reason> at <offset>")`.

- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
- SPDX-License-Identifier: MIT OR Apache-2.0
- References: RFC 8446 (TLS 1.3), RFC 5246 (TLS 1.2). This module implements
  **structure only** -- no cryptography, no certificate validation, no
  session state.

## 1. Record layer

```
TLSPlaintext {
  ContentType  type;      // 1 byte, 20..24
  ProtocolVersion version; // 2 bytes, 0x0301..0x0304
  uint16       length;    // 2 bytes, 1..2^14 (zero rejected here)
  opaque       fragment[length];
}
```

- Header size: 5 bytes (`TLS_RECORD_HEADER_LEN`).
- Accepted content types: 20 change_cipher_spec, 21 alert, 22 handshake,
  23 application_data, 24 heartbeat.
- Accepted legacy versions: 0x0301 (TLS 1.0) .. 0x0304 (TLS 1.3). 0x0300
  (SSL 3.0) is named but rejected. TLS 1.3 records on the wire carry 0x0303;
  0x0304 is accepted structurally.
- `length` must be 1..16384 (`TLS_MAX_FRAGMENT_LEN` = 2^14). Zero-length
  records and overlength records are rejected before the fragment is bound.
- `tls_parse_record` returns `start`, `fragment_off = start + 5` and
  `end = start + 5 + length` (absolute offsets into the caller's buffer), so
  a multi-record buffer is walked by feeding `end` back as the next `start`.
- `tls_record_fragment` copies the `length` bytes at `fragment_off`; an empty
  vector means the record's bounds do not fit the buffer that was passed.

## 2. Handshake envelope

```
Handshake {
  HandshakeType msg_type;   // 1 byte
  uint24        length;     // 3 bytes, big-endian
  opaque        body[length];
}
```

- Header size: 4 bytes (`TLS_HANDSHAKE_HEADER_LEN`).
- `tls_parse_handshake` accepts the message types named in section 3 and
  requires `off + 4 + length <= data.len()`. It returns `start`, `body_off =
  start + 4` and `total = 4 + length` (the consumed byte count);
  `tls_handshake_next(h) = start + total` is the offset of the next message
  in a multi-message buffer.
- Unknown message types (including DTLS-only 3) are rejected with
  `tls: bad handshake type`.

## 3. Handshake messages

All typed parsers (`tls_parse_client_hello`, ...) take the message start
offset, re-parse the envelope, verify the message type and then require the
encoded fields to consume the body exactly.

### 3.1 ClientHello (type 1)

```
struct {
  ProtocolVersion legacy_version;            // 2 bytes
  Random          random;                    // 32 bytes
  opaque          legacy_session_id<0..32>;  // 1-byte length + bytes
  CipherSuite     cipher_suites<2..2^16-2>;  // 2-byte length + 2-byte values
  opaque          legacy_compression_methods<1..2^8-1>; // 1-byte length
  Extension       extensions<0..2^16-1>;     // optional block
} ClientHello;
```

- The cipher-suite list length must be even and at least 2; the compression
  list length must be at least 1; the session id at most 32.
- The extension block is optional (TLS 1.2 permits its absence). When present,
  it occupies `[ext_off, ext_end)` and begins with its own 16-bit list length
  that must equal `ext_end - ext_off - 2`.
- `TlsClientHello` holds copies of `random`, `session_id`,
  `cipher_suites` and `compression_methods`, plus the absolute
  `ext_off`/`ext_end` bounds and `total`.
- Passing `ext_off`/`ext_end` to `tls_parse_extensions` returns the parsed
  extension list (section 4).

### 3.2 ServerHello (type 2)

```
struct {
  ProtocolVersion legacy_version;       // 2 bytes
  Random          random;               // 32 bytes
  opaque          legacy_session_id<0..32>;
  CipherSuite     cipher_suite;         // 2 bytes
  uint8           legacy_compression_method;
  Extension       extensions<0..2^16-1>; // optional block, same rules
} ServerHello;
```

`TlsServerHello` reports `cipher_suite` and `compression_method`; the parser
does not enforce protocol-specific values (for example TLS 1.3 requires
compression method 0) -- that is a protocol-state decision, not structure.

### 3.3 EncryptedExtensions (type 8)

```
struct {
  Extension extensions<0..2^16-1>;  // the entire body
} EncryptedExtensions;
```

`TlsEncryptedExtensions` reports `body_off`, the declared `list_len` and
`total`; the list length must equal the body length minus 2. Parse the block
with `tls_parse_extensions(data, body_off, body_off + list_len + 2)`.

### 3.4 Certificate (type 11, TLS 1.2 shape)

```
struct {
  ASN.1Cert certificate_list<0..2^24-1>;   // 24-bit list length
} Certificate;
ASN.1Cert: opaque certificate<1..2^24-1>;  // 24-bit length + DER bytes
```

- The declared list length must equal the body length minus 3; every entry
  must fit inside the list.
- `TlsCertificate.cert_starts[i]` / `cert_lens[i]` are absolute offsets and
  lengths into the caller's buffer; `tls_certificate_der(data, c, i)` copies
  one DER certificate. An empty list is accepted structurally (count 0).
- **TLS 1.3 Certificate is a different shape** (a 1-byte
  `certificate_request_context` precedes the list) and is therefore *not*
  parsed as a 1.2 Certificate; it is generally rejected by the list-length
  check. DER/X.509 interpretation belongs to `xiom.pki` (armor: `xiom.pem`).

### 3.5 ServerKeyExchange (type 12) and ClientKeyExchange (type 16)

```
struct { select (SignatureAlgorithm) ... } ServerKeyExchange; // opaque
struct { select (KeyExchangeAlgorithm) ... } ClientKeyExchange; // opaque
```

- The body is kept opaque (`body_off`, `body_len`).
- For ServerKeyExchange with at least 3 body bytes and first byte
  `curve_type == 3` (`named_curve`), the following 2 bytes are exposed as
  `named_curve`; otherwise `named_curve` is -1 and `curve_type` keeps the raw
  first byte. This is a hint for ECDHE; the parameters and signature stay
  opaque.
- ClientKeyExchange reports `curve_type = -1`, `named_curve = -1`.
- A ServerKeyExchange body shorter than 3 bytes and an empty
  ClientKeyExchange body are rejected as truncated.

### 3.6 Finished (type 20)

```
struct { opaque verify_data[Hash.length]; } Finished;
```

- The verify_data length is cipher-suite dependent, so any non-empty body is
  accepted; the slice is exposed as `body_off`/`body_len`. An empty body is
  rejected (`tls: empty finished body`).

### 3.7 NewSessionTicket (type 4, TLS 1.3 shape)

```
struct {
  uint32 ticket_lifetime;             // 4 bytes
  uint32 ticket_age_add;              // 4 bytes
  opaque ticket_nonce<0..255>;        // 1-byte length + bytes
  opaque ticket<1..2^16-1>;           // 2-byte length, at least 1 byte
  Extension extensions<0..2^16-1>;    // 2-byte length, must fill the body
} NewSessionTicket;
```

- Minimum body size is 13 bytes.
- A zero-length ticket is rejected; the trailing extension block length must
  equal the remaining body length. `tls_parse_extensions(data, ext_off,
  ext_end)` parses it.
- The TLS 1.2 NewSessionTicket shape (lifetime + 2-byte ticket, no nonce and
  no extensions) is **not** what this parser implements.

## 4. Extensions

```
struct {
  ExtensionType extension_type;  // 2 bytes
  opaque        extension_data<0..2^16-1>; // 2-byte length + bytes
} Extension;
Extension extensions<0..2^16-1>;  // 2-byte total length
```

`tls_parse_extensions(data, off, end)`:

- requires `off >= 0`, `end <= data.len()`, `end >= off`;
- reads the 16-bit list length at `off`; it must equal `end - off - 2`;
- walks entries; every 4-byte entry header and every declared body must fit
  inside the block;
- **rejects duplicates** (`tls: duplicate extension`);
- enforces the RFC 8446 rule that `pre_shared_key` (0x0029) is the final
  extension (`tls: pre_shared_key not last`);
- stores each body verbatim in one byte pool, so unknown extensions are
  preserved with their raw bytes.

`TlsExtensions` is flat: `types[i]`, `starts[i]` (offset into the pool),
`lens[i]`, and the pool `bytes`. Decoders (all return an empty vector / 0 /
-1 when the type or shape does not match, never an error):

| Extension | Type | Body layout parsed | Accessor |
|---|---|---|---|
| server_name | 0x0000 | `ServerNameList`: u16 list length == len-2; `name_type(0) + u16 name length + host_name` | `tls_ext_sni_host_name` (first host_name) |
| supported_groups | 0x000a | u16 list length == len-2, even, then u16 values | `tls_ext_supported_groups` |
| signature_algorithms | 0x000d | u16 list length == len-2, even, then u16 values | `tls_ext_signature_algorithms` |
| application_layer_protocol_negotiation | 0x0010 | u16 list length == len-2; entries `u8 length + bytes` | `tls_ext_alpn_count`, `tls_ext_alpn_name` |
| pre_shared_key | 0x0029 | raw only (binders are opaque) | `tls_ext_bytes` |
| supported_versions | 0x002b | ClientHello: u8 list length == len-1, even u16 list; ServerHello: exactly 2 bytes | `tls_ext_supported_versions` (CH), `tls_ext_selected_version` (SH, else -1) |
| key_share | 0x0033 | ClientHello: u16 list length == len-2; entries `u16 group + u16 length + bytes`; HelloRetryRequest: exactly 2 bytes | `tls_ext_key_share_count/group_at/bytes`, `tls_ext_key_share_selected_group` |

`tls_version_is_tls13(v)` is true exactly for 0x0304. The name catalogs
(`tls_ext_type_name`, `tls_group_name`, `tls_signature_scheme_name`,
`tls_handshake_type_name`, `tls_alert_description_name`,
`tls_alert_level_name`, `tls_content_type_name`, `tls_legacy_version_name`)
return `""` for unknown values.

## 5. Alert and ChangeCipherSpec

```
Alert { AlertLevel level; AlertDescription description; }  // 2 bytes
ChangeCipherSpec { enum { change_cipher_spec(1) } type; }  // 1 byte
```

- `tls_parse_alert` accepts level 1 (warning) or 2 (fatal) and preserves any
  description code (unknown codes get `""` from the name helper).
- `tls_parse_change_cipher_spec` accepts exactly the byte 0x01.

## 6. Buffered handshake reassembly

`TlsHandshakeBuffer` keeps:

- `pending`: the incomplete trailing handshake bytes;
- `messages`: every completed handshake message (header included)
  concatenated in arrival order;
- `starts` / `lens`: per-message offsets into `messages`.

`tls_hsbuf_feed(buf, content_type, fragment)` appends the fragment and then
emits every complete message: while at least 4 pending bytes remain, the
24-bit length at pending[1..4) is read; if the whole `4 + length` is present
the message is copied into `messages` and `pending` is compacted to the
remaining tail. It returns the number of messages completed by this call and
errors with `tls: not a handshake fragment` for any content type other than
22.

`tls_hsbuf_feed_record(buf, data, off)` parses the record at `off` (record
error catalog applies), rejects non-handshake content types with
`tls: not a handshake record`, feeds the fragment and returns
`(next_offset, messages_completed)`.

Message copies from `tls_hsbuf_message` are standalone: `tls_parse_handshake
(&msg, 0)` reports offsets relative to the copy. There is no cap on `pending`
growth beyond the 24-bit length field itself; the buffer is freed by
`tls_hsbuf_reset`.

## 7. Error catalog

Every structural error is `"tls: <reason> at <offset>"` (offsets are decimal)
except `"tls: negative offset"` and `"tls: not a handshake fragment"`, which
carry no offset because none is available.

Record: `truncated record header`, `bad content type`, `bad record version`,
`zero-length record`, `record overlength`, `truncated record fragment`.

Handshake envelope: `truncated handshake header`, `bad handshake type`,
`truncated handshake body`.

ClientHello / ServerHello: `not a client hello`, `not a server hello`,
`truncated client hello`, `truncated server hello`, `bad session id length`,
`bad cipher suites length`, `bad compression methods length`,
`truncated extension block`, `extension block length mismatch`.

EncryptedExtensions: `not encrypted extensions`, `truncated extension
block`, `extension block length mismatch`.

Certificate: `not a certificate`, `truncated certificate list`,
`certificate list length mismatch`, `truncated certificate entry`.

Key exchanges: `not a server key exchange`, `not a client key exchange`,
`truncated key exchange body`, `empty key exchange body`.

Finished / NewSessionTicket: `not a finished message`, `empty finished body`,
`not a new session ticket`, `truncated new session ticket`,
`bad ticket length`, `extension block length mismatch`.

Extensions: `extension block out of bounds`, `truncated extension block`,
`extension block length mismatch`, `truncated extension header`,
`truncated extension body`, `duplicate extension`, `pre_shared_key not last`.

Alert / CCS: `truncated alert`, `bad alert level`, `truncated change cipher
spec`, `bad change cipher spec byte`.

Reassembly: `not a handshake fragment`, `not a handshake record`.

## 8. Documented limitations

- **No cryptography and no validation.** Nothing is decrypted, verified or
  authenticated; a structurally valid message says nothing about its
  legitimacy. Certificate chains must be validated with `xiom.pki`.
- **Record protection is not modelled.** TLS 1.3 encrypted records
  (application_data and post-ServerHello handshake records) are returned as
  opaque fragments; the inner content type is inside the ciphertext.
- **Handshake types without a typed parser** (hello_request,
  end_of_early_data, certificate_request, server_hello_done,
  certificate_verify, key_update, compressed_certificate, message_hash) can
  be read with the envelope parser; their bodies are opaque.
- **TLS 1.3 Certificate / CompressedCertificate shapes are not parsed.**
- **Unknown handshake types are rejected**, not skipped.
- **No state machine**: message ordering, record-sequence and protocol-version
  rules are out of scope.
- **Absolute vs pool offsets:** `TlsCertificate.cert_starts`,
  `TlsClientHello.ext_off/ext_end`, `TlsServerHello.ext_off/ext_end`,
  `TlsEncryptedExtensions.body_off`, `TlsFinished.body_off` and
  `TlsNewSessionTicket.*_off` are absolute offsets into the buffer passed to
  the parser; `TlsExtensions.starts` are offsets into
  `TlsExtensions.bytes`; reassembled message copies are standalone.
