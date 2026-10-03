# xiom.tls

> **Status:** `incubating` -- conformance-tested (20/20); published at `v0.1.3` on the XIOM registry.
> **Scope:** record layer (RFC 8446 section 5) and the TLS 1.2/1.3 handshake
> messages and extensions listed below. **No cryptography:** no key exchange
> math, no AEAD, no signatures, no certificate validation, no session state.
> **Deps:** `xiom.std` only (the module imports `xiom.convert.int`); tests use
> `xiom.test`, `xiom.io`, `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.tls` parses the byte structure of TLS traffic that is handed to it
already in memory: record headers and fragments, handshake message envelopes,
the hello/key-exchange/certificate/finished messages and their extensions,
alerts and ChangeCipherSpec. It copies bytes, reports byte offsets and rejects
malformed structure with deterministic `Err(Str)` messages that end in
`at <offset>`. It never decrypts, never validates a certificate and never
touches a network socket.

Everything outside the structure layer is deliberately somebody else's job:

- X.509/DER certificate parsing and chain validation: `xiom.pki`
  (this module exposes each certificate as a DER slice offset/length, and
  `xiom.pem` handles the armor form the DER bytes usually arrive in),
- the cryptographic algorithms (AEAD, key schedule, signatures):
  `xiom.crypto` family,
- record protection, retransmission and session state machines: not in scope.

## API

### Record layer

| Function | Returns | Description |
|---|---|---|
| `tls_parse_record(data, off)` | `Result[TlsRecord, Str]` | Parse one 5-byte record header at `off`; `fragment_off`/`end` bound the fragment. |
| `tls_record_fragment(data, r)` | `Vec[UInt8]` | Copy of the record's fragment. |
| `tls_content_type_name(t)` / `tls_content_type_ok(t)` | `Str` / `Bool` | 20 CCS, 21 alert, 22 handshake, 23 application_data, 24 heartbeat. |
| `tls_legacy_version_name(v)` / `tls_legacy_version_ok(v)` | `Str` / `Bool` | 0x0301..0x0304 only (0x0300 names as "SSL 3.0" but is rejected). |
| `tls_parse_alert(data, off)` | `Result[TlsAlert, Str]` | Two-byte alert; level 1/2; description preserved (unknown allowed). |
| `tls_alert_level_name(l)` / `tls_alert_description_name(d)` | `Str` | "warning"/"fatal" and the RFC 8446 description catalog. |
| `tls_parse_change_cipher_spec(data, off)` | `Result[Unit, Str]` | Exactly one byte, `0x01`. |

### Handshake messages

All typed parsers take `(data, off)` where `off` is the message start, verify
the message type and require the declared 24-bit body to fit the buffer.

| Function | Returns | Description |
|---|---|---|
| `tls_parse_handshake(data, off)` | `Result[TlsHandshake, Str]` | Envelope only: type, 24-bit length, `body_off`, `total` (consumed). |
| `tls_handshake_next(h)` | `Int` | `start + total`: feed it back to consume the next message. |
| `tls_parse_client_hello(data, off)` | `Result[TlsClientHello, Str]` | Version, random, session id, suites, compression methods, extension bounds. |
| `tls_parse_server_hello(data, off)` | `Result[TlsServerHello, Str]` | Same shape with one selected suite and compression method. |
| `tls_parse_encrypted_extensions(data, off)` | `Result[TlsEncryptedExtensions, Str]` | TLS 1.3; body is one extension block. |
| `tls_parse_certificate(data, off)` | `Result[TlsCertificate, Str]` | TLS 1.2 shape: 24-bit list, 24-bit DER entries (offsets/lengths exposed). |
| `tls_certificate_der(data, c, i)` | `Vec[UInt8]` | Copy of DER certificate `i`. |
| `tls_parse_server_key_exchange(data, off)` | `Result[TlsKeyExchange, Str]` | Opaque body; ECDHE named-curve hint when curve_type is 3. |
| `tls_parse_client_key_exchange(data, off)` | `Result[TlsKeyExchange, Str]` | Opaque body, no hint. |
| `tls_parse_finished(data, off)` | `Result[TlsFinished, Str]` | Opaque verify_data slice. |
| `tls_parse_new_session_ticket(data, off)` | `Result[TlsNewSessionTicket, Str]` | TLS 1.3 shape: lifetime, age_add, nonce, ticket, extension block. |
| `tls_handshake_type_name(t)` | `Str` | The 16 named types (client_hello .. message_hash). |

### Extensions

`tls_parse_extensions(data, off, end)` validates one extension block whose
16-bit list length must consume `[off + 2, end)` exactly. Unknown extensions
are preserved with their raw bytes, duplicates are rejected and
`pre_shared_key` (0x0029) must be the last extension. Decoders:

| Function | Returns |
|---|---|
| `tls_ext_count(e)` / `tls_ext_type_at(e, i)` / `tls_ext_len(e, i)` / `tls_ext_bytes(e, i)` / `tls_ext_find(e, t)` | `Int` / `Int` / `Int` / `Vec[UInt8]` / `Int` |
| `tls_ext_sni_host_name(e, i)` | `Vec[UInt8]` (SNI 0x0000, first host_name) |
| `tls_ext_supported_groups(e, i)` / `tls_ext_signature_algorithms(e, i)` | `Vec[Int]` |
| `tls_ext_alpn_count(e, i)` / `tls_ext_alpn_name(e, i, j)` | `Int` / `Vec[UInt8]` (ALPN 0x0010) |
| `tls_ext_supported_versions(e, i)` / `tls_ext_selected_version(e, i)` | `Vec[Int]` (ClientHello shape) / `Int` (ServerHello shape, -1 otherwise) |
| `tls_ext_key_share_count(e, i)` / `..._group_at(e,i,j)` / `..._bytes(e,i,j)` / `..._selected_group(e, i)` | `Int` / `Int` / `Vec[UInt8]` / `Int` (HelloRetryRequest shape) |
| `tls_group_name(g)` / `tls_signature_scheme_name(s)` / `tls_ext_type_name(t)` | `Str` |

A decoder whose extension type or body shape does not match returns an empty
vector (or -1 / 0 for the Int forms) instead of an error; use the block-level
parser for structural errors.

### Buffered handshake reassembly

Handshake messages may span records. `TlsHandshakeBuffer` collects record
fragments and emits complete messages:

| Function | Returns |
|---|---|
| `tls_handshake_buffer_new()` | `TlsHandshakeBuffer` |
| `tls_hsbuf_feed(buf, content_type, fragment)` | `Result[Int, Str]` (messages completed) |
| `tls_hsbuf_feed_record(buf, data, off)` | `Result[(Int, Int), Str]` (`(next_offset, messages_completed)`) |
| `tls_hsbuf_count(buf)` / `tls_hsbuf_pending_len(buf)` | `Int` |
| `tls_hsbuf_message_type(buf, i)` / `tls_hsbuf_message_len(buf, i)` / `tls_hsbuf_message(buf, i)` | `Int` / `Int` / `Vec[UInt8]` |
| `tls_hsbuf_reset(buf)` | clears pending bytes and buffered messages |

### Errors

Errors are `Err("tls: <reason> at <offset>")` with the offending byte offset
(see the catalog in `SPEC.md`). `"tls: negative offset"` carries no suffix.

## Usage

Parse a ClientHello and print its SNI host name:

```xi
use xiom.tls;

fn sni_of(data: &Vec[UInt8]) -> Int {
  let cr = tls_parse_client_hello(data, 0);
  if !cr.is_ok { return -1; }
  let ch: TlsClientHello = cr.value;
  if !ch.ext_present { return 0; }
  let xr = tls_parse_extensions(data, ch.ext_off, ch.ext_end);
  if !xr.is_ok { return -1; }
  let exts: TlsExtensions = xr.value;
  let i = tls_ext_find(&exts, TLS_EXT_SERVER_NAME);
  if i < 0 { return 0; }
  return tls_ext_sni_host_name(&exts, i).len();
}
```

Reassemble a flight that spans several handshake records:

```xi
var buf = tls_handshake_buffer_new();
var off = 0;
while off < flight.len() {
  let fr = tls_hsbuf_feed_record(&mut buf, &flight, off);
  if !fr.is_ok { break; }
  let pair = fr.value;
  off = pair.0;              // next record
}
var i = 0;
while i < tls_hsbuf_count(&buf) {
  if tls_hsbuf_message_type(&buf, i) == TLS_HS_CLIENT_HELLO {
    let msg = tls_hsbuf_message(&buf, i);
    let cr = tls_parse_client_hello(&msg, 0);   // offsets are relative to msg
    // ...
  }
  i = i + 1;
}
```

Parse one message at a time out of a multi-message buffer:

```xi
var off = 0;
while off + TLS_HANDSHAKE_HEADER_LEN <= buffer.len() {
  let hr = tls_parse_handshake(&buffer, off);
  if !hr.is_ok { break; }
  let h: TlsHandshake = hr.value;
  off = tls_handshake_next(&h);   // start + total
}
```

## Tests

```
.\scripts\port.ps1 -Package xiom.tls
```

Expected: twenty `[PASS]` lines and `port: PASS (passed=20 failed=0
program_exit=0 exit=0)`. The suite builds synthetic record/handshake buffers
in-test (hex literals plus small builders) and pins record offsets, every
message parser, the extension decoders, alert/CCS decoding, multi-record
reassembly and the malformed/truncated/overlength error catalog.

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
