# xiom.pki -- specification (as implemented)

Byte-level description of the DER/X.509/PEM subset that `src/pki.xi` actually
implements. Anything not listed here is not implemented. This is a **structure
parser**: no signature verification, no key parsing beyond the BIT STRING's
bit length, no chain building, no name matching, no validity checking, no
criticality enforcement.

Module: `xiom.pki` (single module, `src/pki.xi`). Deps: `xiom.std` only
(`xiom.string`, `xiom.string.builder`, `xiom.string.compare`). No FFI.

## 1. DER TLV walker (X.690)

### 1.1 Identifier octets

* Byte 1 splits into `tag_class = b / 64` (0 universal, 1 application,
  2 context, 3 private), `constructed = (b / 32) % 2`, `low = b % 32`.
* `low != 31`: `tag_number = low`, the TLV header continues at `off + 1`.
* `low == 31` (high-tag-number form): the following base-128 octets carry the
  tag number, high bit = continuation. The first octet may not be `0x80`
  (non-minimal). The tag number must fit a signed 64-bit Int and use at most
  8 continuation octets; otherwise `pki: tag number overflow`.
* High-tag-number form is decoded and exposed (`tag_number`), but structural
  fields are matched by class + number, so a high-tag re-encoding of a known
  universal tag is still recognized.

### 1.2 Length octets (definite only)

* Short form `0x00..0x7F`: length 0..127, size 1.
* Long form `0x80|n` + n big-endian octets, `n` in 1..8. `0x80` (indefinite)
  is rejected: `pki: indefinite length`. `n > 8` or a value that would not fit
  a signed 64-bit Int: `pki: long-form length overflow`. A leading zero octet
  or a value < 128 in the long form: `pki: non-minimal length`.
* Missing octets: `pki: truncated length` at the first length octet.

### 1.3 Values

* `content = header_end`, `next = content + len`.
* `content + len > data.len()`: `pki: truncated value` at the tag byte.
* `der_tlv_in(data, off, end)` additionally rejects `next > end` with
  `pki: value overruns container` at the tag byte. Every nested parse in this
  package goes through the container-bounded walker; top-level decoders use
  the whole buffer.

### 1.4 Error offsets

Every error is `"<message> at offset <n>"` except `pki: negative offset`.
Offsets are absolute byte indexes into the buffer passed to the decoder;
content-level violations name the offending content byte where that is
meaningful (see the catalog in section 6).

## 2. ASN.1 primitives

| Function | Tag | Accepts | Rejects |
|----------|-----|---------|---------|
| `der_bool_decode` | 01 | content exactly 1 byte; 0x00 false, non-zero true | `pki: bad boolean` |
| `der_integer_decode` | 02 | 1..8 content bytes, first byte < 0x80, minimal (leading 0x00 only when next byte >= 0x80) | `pki: empty integer`, `pki: negative integer`, `pki: non-minimal integer`, `pki: integer overflow` |
| `der_bit_string_decode` | 03 | content >= 1 byte; first byte = unused 0..7; zero bit bytes require unused 0; unused region bits must be zero | `pki: empty bit string`, `pki: bad unused bits`, `pki: non-zero unused bits` |
| `der_octet_string_decode` | 04 | any content, copied verbatim | -- |
| `der_null_decode` | 05 | empty content | `pki: unexpected null content` |
| `der_oid_decode` | 06 | first subidentifier one octet 0..119 -> arcs `b/40`, `b%40`; later arcs base-128, minimal, <= 64 arcs total | `pki: empty oid`, `pki: bad oid`, `pki: truncated oid`, `pki: non-minimal oid arc`, `pki: oid overflow`, `pki: oid too long` |
| `der_string_decode` | 0C/13/16 | UTF8String: valid UTF-8, no NUL; PrintableString: 0x20..0x7E; IA5String: 0x01..0x7F | `pki: bad utf8 string`, `pki: bad printable string`, `pki: bad ia5 string` |
| `der_time_decode` | 17/18 | UTCTime exactly `YYMMDDhhmmssZ` (13 bytes, YY < 50 -> 20YY else 19YY); GeneralizedTime exactly `YYYYMMDDhhmmssZ` (15 bytes) | `pki: bad utc time`, `pki: bad generalized time`, `pki: bad time digit`, `pki: bad time zone`, `pki: bad time month/day/hour/minute/second` |

All primitives reject a wrong universal tag with `pki: tag mismatch` at the
tag byte. Multi-byte (high-tag) universal re-encodings are rejected by the
tag-number match for primitives (the walker still decodes them).

Time ranges are checked as month 1..12, day 1..31, hour 0..23, minute 0..59,
second 0..59; calendar month lengths and leap seconds are not validated.
Zoneless, fractional-second and offset forms are rejected.

## 3. Certificate structure (RFC 5280 shapes)

`pki_certificate_parse(data)` requires the entire buffer to be exactly one
`Certificate` TLV; trailing bytes are `pki: trailing data` at the first extra
byte.

```
Certificate  ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
TBSCertificate ::= SEQUENCE {
  version [0] EXPLICIT INTEGER OPTIONAL,   -- 0=v1, 1=v2, 2=v3; absent = v1
  serialNumber INTEGER,                    -- positive, 1..20 bytes
  signature AlgorithmIdentifier,
  issuer Name, validity Validity, subject Name,
  subjectPublicKeyInfo SubjectPublicKeyInfo,
  issuerUniqueID [1] OPTIONAL,             -- accepted, skipped
  subjectUniqueID [2] OPTIONAL,            -- accepted, skipped
  extensions [3] EXPLICIT OPTIONAL }       -- must be the last field
```

* `version`: the `[0]` wrapper must contain exactly one INTEGER with value
  0..2 (`pki: bad version` otherwise). A missing `[0]` yields v1.
* `serialNumber`: 1..20 content bytes; first byte >= 0x80 is
  `pki: negative serial`; a leading 0x00 followed by a byte < 0x80 is
  `pki: non-minimal serial`; 21+ bytes is `pki: serial too long`; empty is
  `pki: empty serial`. `serial_hex` is the uppercase hex of the content bytes
  (including the DER sign pad when present).
* `AlgorithmIdentifier`: SEQUENCE whose first element is an OID; any
  following parameter TLVs are skipped without interpretation. The decoded
  OID's `next` is past the whole SEQUENCE. No OID is `pki: bad algorithm
  identifier`.
* `Name` (RDNSequence): SEQUENCE OF SET OF AttributeTypeAndValue. Every SET
  must be non-empty; every attribute is a SEQUENCE { OID, value } with no
  trailing bytes. Values of type UTF8String/PrintableString/IA5String are
  decoded; any other value type is recorded with `value_tag = -1` and an
  empty string (its bytes are not copied). Attributes are flattened into
  parallel vectors with their 0-based RDN ordinal; multi-valued RDNs share an
  ordinal.
* `Validity`: SEQUENCE of exactly two Times.
* `SubjectPublicKeyInfo`: SEQUENCE { AlgorithmIdentifier, BIT STRING }.
  `spki_key_bits = bit bytes * 8 - unused`.
* Unknown optional context tags in TBS are `pki: bad tbs field`; `[3]` may
  appear once and last (`pki: duplicate extensions`, `pki: trailing tbs
  data`).
* `signatureValue`: BIT STRING; `pki_signature_bits` = bit bytes * 8 - unused.
  The signature bytes are not verified or interpreted.

## 4. Extensions

```
Extensions ::= [3] EXPLICIT SEQUENCE OF Extension
Extension  ::= SEQUENCE { extnID OBJECT IDENTIFIER,
                          critical BOOLEAN DEFAULT FALSE,
                          extnValue OCTET STRING }
```

Every extension's OID is preserved in wire order in `oids`; `critical`
parallel vector holds 0/1. A malformed Extension shell is `pki: bad
extension`. The `extnValue` bytes are parsed as nested DER for the known
OIDs; a malformed known extension fails the whole certificate parse with the
nested error.

| OID | Decoded into | Rules |
|-----|--------------|-------|
| 2.5.29.19 basicConstraints | `ca` (default false), `path_len` (-1 absent) | inner SEQUENCE; BOOLEAN + non-negative INTEGER; no other fields |
| 2.5.29.15 keyUsage | `key_usage` | inner BIT STRING with 1 or 2 bit bytes; value normalized to a left-aligned 16-bit word (bit 0 = 0x8000 ... bit 8 = 0x0080) |
| 2.5.29.37 extKeyUsage | `eku_oids` | inner SEQUENCE OF OID |
| 2.5.29.17 subjectAltName | `san_types` / `san_values` | inner SEQUENCE; [1] rfc822Name, [2] dNSName, [6] URI decoded as IA5 text; [7] iPAddress: 4 bytes -> dotted quad, 16 bytes -> uncompressed colon-hex; other choices keep the tag number with an empty value |
| 2.5.29.14 subjectKeyIdentifier | `has_subject_key_id`, `subject_key_id_hex` | inner OCTET STRING, non-empty, uppercase hex |
| 2.5.29.35 authorityKeyIdentifier | `has_authority_key_id`, `authority_key_id_hex` | inner SEQUENCE; keyIdentifier `[0]` primitive captured as uppercase hex ("" when absent); other fields skipped |

`pki_key_usage_has(e, bit)` probes bit 0..8 with divisor/modulo arithmetic
(no shifts). Unknown extension OIDs are not parsed further but are always in
`oids` and can be critical.

## 5. PEM unwrap

`pki_pem_to_der(text)` unwraps one armor block:

* The first non-empty line must be exactly
  `-----BEGIN CERTIFICATE-----`; empty lines before it are ignored.
* Body lines: base64 alphabet plus `=`; every line except the last must be
  exactly 64 characters, the last 1..64; blank lines, dashed lines and lines
  > 64 characters are `pki pem: bad armor`.
* The END line must be exactly `-----END CERTIFICATE-----`. Non-empty lines
  after it are `pki pem: text outside block`.
* LF and CRLF line endings are accepted (one CR before LF is dropped); a
  final line without a newline is accepted.
* The base64 body is strict RFC 4648: character count % 4 == 0
  (`pki pem: bad padding`), only alphabet characters
  (`pki pem: invalid base64 character`), padding only in the final run with
  the exact count (`pki pem: bad padding`), zero unused trailing bits
  (`pki pem: non-canonical trailing bits`).
* No BEGIN line: `pki pem: no certificate block`; EOF inside a block:
  `pki pem: unterminated block`; BEGIN immediately followed by END:
  `pki pem: empty body`.
* PEM errors carry the armor-text byte offset; base64 content errors carry
  the armor-text offset of the offending body character.

Other labels (e.g. `PRIVATE KEY`), nested blocks and multiple blocks are not
supported.

## 6. Error catalog

`pki: negative offset`, `pki: truncated tag`, `pki: non-minimal tag`,
`pki: tag number overflow`, `pki: truncated length`, `pki: indefinite
length`, `pki: long-form length overflow`, `pki: non-minimal length`,
`pki: truncated value`, `pki: value overruns container`, `pki: tag
mismatch`, `pki: bad boolean`, `pki: empty integer`, `pki: integer
overflow`, `pki: negative integer`, `pki: non-minimal integer`,
`pki: empty bit string`, `pki: bad unused bits`, `pki: non-zero unused
bits`, `pki: unexpected null content`, `pki: empty oid`, `pki: bad oid`,
`pki: truncated oid`, `pki: non-minimal oid arc`, `pki: oid overflow`,
`pki: oid too long`, `pki: bad utf8 string`, `pki: bad printable string`,
`pki: bad ia5 string`, `pki: unsupported string tag`, `pki: bad utc time`,
`pki: bad generalized time`, `pki: bad time digit`, `pki: bad time zone`,
`pki: bad time month`, `pki: bad time day`, `pki: bad time hour`,
`pki: bad time minute`, `pki: bad time second`, `pki: bad certificate`,
`pki: bad tbs certificate`, `pki: bad version`, `pki: bad serial number`,
`pki: empty serial`, `pki: serial too long`, `pki: negative serial`,
`pki: non-minimal serial`, `pki: bad algorithm identifier`, `pki: bad
name`, `pki: bad rdn set`, `pki: bad attribute`, `pki: missing attribute
value`, `pki: trailing attribute data`, `pki: bad validity`, `pki: bad
subject public key info`, `pki: bad tbs field`, `pki: duplicate
extensions`, `pki: trailing tbs data`, `pki: trailing data`, `pki: bad
extensions`, `pki: bad extension`, `pki: bad basic constraints`,
`pki: bad key usage`, `pki: bad ext key usage`, `pki: bad subject alt
name`, `pki: bad general name`, `pki: bad ip address`, `pki: bad subject
key id`, `pki: bad authority key id`, `pki: bit string too long`,
`pki pem: no certificate block`, `pki pem: bad armor`, `pki pem:
unterminated block`, `pki pem: text outside block`, `pki pem: empty body`,
`pki pem: invalid base64 character`, `pki pem: bad padding`,
`pki pem: non-canonical trailing bits`.

## 7. Limits

* serialNumber: 1..20 bytes.
* INTEGER values: 8 content bytes (64-bit signed range), non-negative only.
* OID: at most 64 arcs, each arc must fit a signed 64-bit Int.
* keyUsage: at most 2 bit bytes.
* Tag number: at most 8 continuation octets and a signed 64-bit Int.
* No depth cap is needed: the parser never recurses; it uses one pass per
  structure with explicit container bounds.

## 8. Not implemented (explicit non-goals)

* Cryptographic verification of any kind; signature bytes are opaque.
* Public key parsing (RSA/EC/Ed25519 internals); only the algorithm OID and
  the key BIT STRING's bit length.
* CSR (PKCS#10), CRL, OCSP, PKCS#7/#8/#12, private keys.
* BER indefinite lengths, CER, packed encoding rules.
* Name canonicalization, constraint checking, criticality enforcement.
* Calendar validation of time fields beyond the numeric ranges above.
* Non-UTF8/Printable/IA5 attribute value types are not decoded (tag is kept,
  value is empty).
