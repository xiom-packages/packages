# xiom.ldap

> **Status:** `incubating` -- implemented and green on the local harness
> (20/20), NOT yet published to the XIOM registry.
> **Scope:** pure-XIOM (no FFI, no sockets) decoder for the LDAP protocol
> wire format (RFC 4511) plus a minimal encoder. Covers the BER subset LDAP
> uses: one-byte tags, definite short/long-form lengths (minimal long form
> only), INTEGER, ENUMERATED, BOOLEAN, OCTET STRING and SEQUENCE/SET; the
> LDAPMessage envelope; BindRequest/BindResponse, UnbindRequest,
> SearchRequest, SearchResultEntry, SearchResultDone, SearchResultReference,
> ModifyRequest/Response, AddRequest/Response, DelRequest/Response,
> ModifyDNRequest/Response, CompareRequest/Response, AbandonRequest and
> ExtendedRequest/Response; every RFC 4511 filter choice; and the shared
> LDAPResult fields (resultCode, matchedDN, diagnosticMessage, referral).
> **Deps:** `xiom.std` only. The library module imports
> `xiom.string.builder`; the tests add `xiom.test`, `xiom.io`,
> `xiom.string`, `xiom.string.compare` and `xiom.encoding.hex`.

## What it is

`xiom.ldap` reads LDAP messages from a byte buffer and writes the two
request forms needed to drive a directory:

```
LDAPMessage ::= SEQUENCE {
  INTEGER messageID,
  protocolOp      -- a context/application tagged element, tag 0x42..0x78
  [0] Controls OPTIONAL   -- captured as offset/length, not decoded
}
```

`ldap_message_parse` validates the envelope and returns a flat
`LdapMessage` index (`message_id`, `op_tag`, `op_offset`/`op_length`,
optional controls bounds). The protocolOp itself is decoded by the
per-operation parser for that tag, e.g. `ldap_bind_request_parse(data,
m.op_offset)` or `ldap_search_request_parse(data, m.op_offset)`. Parsers
never copy value bytes: attribute values, assertion values and
request/referral payloads stay in the source buffer as offset/length pairs,
and `ldap_bytes_copy` copies them out.

Search filters are decoded into a flat tree (parallel `Vec` fields, no
`Vec` of structs, no pointers): every node carries its kind, parent index
and depth, and/or/not nodes expose their children, item nodes expose the
attribute description plus raw value bounds, substring nodes expose their
initial/any/final parts, and extensible nodes expose the matching rule and
`dnAttributes` flag. The tree is depth-capped at
`LDAP_MAX_FILTER_DEPTH` (32) ancestors.

On the write side `ldap_message_encode`, `ldap_bind_request_encode`
(simple authentication) and `ldap_search_request_encode` (one equality
filter) produce protocol messages that parse back byte-identically. The
BER building blocks (`ber_length_encode`, `ber_int_encode`,
`ber_octet_string_encode`, `ber_bool_encode`, `ber_enum_encode`,
`ber_tlv_wrap`) are public.

Every malformed input is rejected with a stable `Err(Str)` naming the byte
offset of the offending structure, for example
`ber: non-minimal integer at offset 12` or
`ldap: filter too deeply nested at offset 66`.

## Wire format

BER TLV (one-byte tags only):

| Field | Encoding |
|---|---|
| tag | 1 byte; low five bits 11111 (multi-byte tags) rejected |
| length | definite form: 1 byte below 128, else `0x80\|n` + n big-endian bytes (n = 1..8); indefinite (0x80) and non-minimal long form rejected |
| content | `length` raw bytes |

Documented tags:

| Tag | Type | Content rules |
|---|---|---|
| 0x01 | BOOLEAN | exactly 1 byte; 0x00 is FALSE, any other value TRUE |
| 0x02 | INTEGER | 1..8 bytes, minimal two's complement (0x00/0xFF sign extension rejected) |
| 0x04 | OCTET STRING | any bytes, zero-length allowed |
| 0x0A | ENUMERATED | same content rules as INTEGER |
| 0x30 / 0x31 | SEQUENCE / SET | nested TLVs |

protocolOp tags (RFC 4511, IMPLICIT TAGS):

| Tag | Operation | Decoder |
|---|---|---|
| 0x42 | UnbindRequest | `ldap_unbind_request_parse` |
| 0x4A | DelRequest | `ldap_del_request_parse` |
| 0x50 | AbandonRequest | `ldap_abandon_request_parse` |
| 0x60 | BindRequest | `ldap_bind_request_parse` |
| 0x61 | BindResponse | `ldap_bind_response_parse` |
| 0x63 | SearchRequest | `ldap_search_request_parse` |
| 0x64 | SearchResultEntry | `ldap_search_entry_parse` |
| 0x65 | SearchResultDone | `ldap_result_parse` |
| 0x66 / 0x67 | ModifyRequest / ModifyResponse | `ldap_modify_request_parse` / `ldap_result_parse` |
| 0x68 / 0x69 | AddRequest / AddResponse | `ldap_add_request_parse` / `ldap_result_parse` |
| 0x6B | DelResponse | `ldap_result_parse` |
| 0x6C / 0x6D | ModifyDNRequest / ModifyDNResponse | `ldap_modify_dn_request_parse` / `ldap_result_parse` |
| 0x6E / 0x6F | CompareRequest / CompareResponse | `ldap_compare_request_parse` / `ldap_result_parse` |
| 0x73 | SearchResultReference | `ldap_search_reference_parse` |
| 0x77 / 0x78 | ExtendedRequest / ExtendedResponse | `ldap_extended_request_parse` / `ldap_extended_response_parse` |

Filter choice tags, all decoded by `ldap_filter_parse`:

| Tag | Choice | Flat kind |
|---|---|---|
| 0xA0 / 0xA1 / 0xA2 | and / or / not | 1 / 2 / 3 |
| 0xA3 | equalityMatch | 4 |
| 0xA4 | substrings (parts 0x80/0x81/0x82) | 5 |
| 0xA5 / 0xA6 | greaterOrEqual / lessOrEqual | 6 / 7 |
| 0x87 | present | 8 |
| 0xA8 | approxMatch | 9 |
| 0xA9 | extensibleMatch ([1] rule, [2] type, [3] value, [4] dnAttributes) | 10 |

## API

| Function | Returns | Description |
|---|---|---|
| `ber_length_decode(data, off)` | `Result[BerLength, Str]` | Decode a length field (`len`, `size`). |
| `ber_tlv_decode(data, off)` | `Result[BerTlv, Str]` | Decode a tag/length header and bounds-check the content. |
| `ber_int_decode` / `ber_enum_decode` / `ber_bool_decode` | `Result[BerInt/BerEnum/BerBool, Str]` | Typed scalar TLVs. |
| `ber_octet_string_decode(data, off)` | `Result[BerBytes, Str]` | OCTET STRING bytes (copied verbatim). |
| `ber_sequence_decode(data, off)` | `Result[BerTlv, Str]` | SEQUENCE (0x30) or SET (0x31) header. |
| `ber_length_encode(len)` | `Vec[UInt8]` | Minimal definite length bytes. |
| `ber_int_encode` / `ber_enum_encode(value)` | `Vec[UInt8]` | Minimal INTEGER / ENUMERATED TLV. |
| `ber_octet_string_encode(bytes)` | `Vec[UInt8]` | OCTET STRING TLV. |
| `ber_bool_encode(value)` | `Vec[UInt8]` | BOOLEAN TLV (0xFF / 0x00). |
| `ber_tlv_wrap(tag, content)` | `Vec[UInt8]` | Tag + definite length + content. |
| `ldap_message_parse(data)` | `Result[LdapMessage, Str]` | Envelope validation + op/controls index. |
| `ldap_message_encode(message_id, op)` | `Result[Vec[UInt8], Str]` | Wrap a protocolOp TLV in a message. |
| `ldap_op_tag_known(tag)` / `ldap_op_tag_name(tag)` | `Bool` / `Str` | protocolOp tag table. |
| `ldap_bind_request_parse(data, off)` | `Result[LdapBindRequest, Str]` | version/name/simple or SASL auth. |
| `ldap_bind_request_encode(version, name, password)` | `Result[Vec[UInt8], Str]` | Simple-auth BindRequest TLV. |
| `ldap_bind_response_parse(data, off)` | `Result[LdapResult, Str]` | LDAPResult + serverSaslCreds. |
| `ldap_unbind_request_parse` / `ldap_abandon_request_parse` | `Result[Int, Str]` | Next offset / abandoned id. |
| `ldap_search_request_parse(data, off)` | `Result[LdapSearchRequest, Str]` | Fields + embedded flat filter + attributes. |
| `ldap_search_request_encode(base, scope, deref, size, time, types_only, attr, value, attributes)` | `Result[Vec[UInt8], Str]` | SearchRequest with one equality filter. |
| `ldap_search_entry_parse(data, off)` | `Result[LdapSearchEntry, Str]` | objectName + PartialAttributeList. |
| `ldap_attribute_list_parse(data, off)` | `Result[LdapAttributeList, Str]` | Standalone PartialAttributeList. |
| `ldap_result_parse(data, off)` | `Result[LdapResult, Str]` | Plain LDAPResult responses. |
| `ldap_modify_request_parse` / `ldap_add_request_parse` | `Result[LdapModifyRequest/LdapAddRequest, Str]` | object/entry + attributes/changes. |
| `ldap_del_request_parse` | `Result[LdapStr, Str]` | Target DN. |
| `ldap_modify_dn_request_parse` | `Result[LdapModifyDnRequest, Str]` | entry/newRDN/deleteoldrdn/newSuperior. |
| `ldap_compare_request_parse` | `Result[LdapCompareRequest, Str]` | entry + attr + raw assertion value. |
| `ldap_search_reference_parse` | `Result[LdapSearchReference, Str]` | LDAPURL list. |
| `ldap_extended_request_parse` / `ldap_extended_response_parse` | `Result[LdapExtendedRequest/LdapResult, Str]` | StartTLS/WhoAmI style ops. |
| `ldap_filter_parse(data, off)` | `Result[LdapFilter, Str]` | Flat filter tree. |
| `ldap_bytes_copy(data, off, len)` | `Vec[UInt8]` | Copy a raw value out of the buffer. |
| `ldap_result_code_name(code)` / `ldap_result_code_known(code)` | `Str` / `Bool` | RFC 4511 + IANA result-code table. |

## Usage

Build a search request, wrap it in a message, and decode it back:

```xiom
use xiom.ldap;
use xiom.io;
use xiom.convert.int;

fn main() -> Int {
  var attrs = Vec[Str].new();
  attrs.push("cn");
  attrs.push("mail");
  var value = Vec[UInt8].new();
  value.push(97);   // "admin"
  value.push(100);
  value.push(109);
  value.push(105);
  value.push(110);

  let opr = ldap_search_request_encode("dc=example,dc=com", 2, 0, 500, 30, false, "cn", &value, &attrs);
  if !opr.is_ok {
    io.println("encode failed: " + opr.error);
    return 1;
  }
  let op: Vec[UInt8] = opr.value;
  let mr = ldap_message_encode(7, &op);
  if !mr.is_ok {
    io.println("wrap failed: " + mr.error);
    return 1;
  }
  let msg: Vec[UInt8] = mr.value;

  let pr = ldap_message_parse(&msg);
  if !pr.is_ok {
    io.println("parse failed: " + pr.error);
    return 1;
  }
  let m: LdapMessage = pr.value;
  io.println("message id: " + int.int_to_string(m.message_id));
  io.println("op: " + ldap_op_tag_name(m.op_tag));

  let sr = ldap_search_request_parse(&msg, m.op_offset);
  if !sr.is_ok {
    io.println("op parse failed: " + sr.error);
    return 1;
  }
  let req: LdapSearchRequest = sr.value;
  io.println("base: " + req.base_object);
  let f: LdapFilter = req.filter;
  io.println("filter nodes: " + int.int_to_string(f.kinds.len()));
  io.println("result code 49: " + ldap_result_code_name(49));
  return 0;
}
```

Reading a response: parse the envelope, then dispatch on `op_tag` and copy
the pieces you need out of the buffer, e.g. an entry value at
`attrs.value_offsets[i]` / `attrs.value_lengths[i]` with
`ldap_bytes_copy`.

## Documented subset and limitations

* **No I/O, no connections, no ASN.1 text syntax.** This package turns
  buffers into indexes and back; TCP/TLS, LDIF and schema handling are out
  of scope.
* **Controls are captured, not decoded.** `ldap_message_parse` bounds the
  optional `[0]` controls TLV but does not decode Control ::= SEQUENCE {
  controlType, criticality, controlValue }.
* **Strings must be printable ASCII (0x20..0x7E).** LDAPString / LDAPDN /
  LDAPOID values that are decoded into a `Str` are validated first; a Str
  is a NUL-terminated C string at the ABI, so non-printable or NUL bytes
  are rejected with `ldap: non-printable string` instead of being silently
  truncated. Attribute values, assertion values, passwords and SASL
  credentials stay raw `Vec[UInt8]`.
* **SASL is a placeholder.** Mechanism and optional credentials are
  exposed as a string plus raw bytes; no SASL mechanism is implemented.
* **Minimal long-form lengths only.** Indefinite and non-minimal long-form
  lengths are rejected even though X.690 BER would accept some of them;
  every real LDAP encoder emits minimal definite lengths.
* **Filter depth is capped** at 32 ancestors (`LDAP_MAX_FILTER_DEPTH`);
  deeper trees are rejected with `ldap: filter too deeply nested`.
* **Attribute values are not interpreted** (no schema, no DN parsing, no
  recursions); they are offset/length pairs into the source buffer.
* **Decode-first.** Only BindRequest (simple) and SearchRequest (single
  equality filter) have encoders; there are no response builders, no
  IntermediateResponse (0x79) and no LDAPURL parser. Unsupported op tags
  are rejected at `ldap_message_parse` time.
* **Trailing bytes after the message TLV are ignored** so a stream can
  carry back-to-back messages; trailing bytes inside any container are
  rejected with the exact offset.

## Testing

From the repository root:

```
& .\scripts\port.ps1 -Package xiom.ldap
```

runs `tests/test_conformance.xi` (20 checks) against this module. Every
fixture is synthetic and built in-test from hex strings plus the library's
own encoders; no external data files are used. See `SPEC.md` for the
byte-level grammar, validation order and the full error catalog.
