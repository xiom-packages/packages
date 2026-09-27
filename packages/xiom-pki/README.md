# xiom.pki

Pure-XIOM **structure parser** for X.509/PKIX certificates: a DER (X.690) TLV
walker, ASN.1 primitives, TBSCertificate + extension decoding, and a PEM
`CERTIFICATE` unwrap helper. No FFI; depends only on `xiom.std`.

> **No cryptography and no trust.** This package parses bytes into a decoded
> model. It does **not** verify signatures, keys, chains, hostnames, dates,
> revocation, or criticality. A certificate that parses is not a certificate
> that is valid or trusted. Use it before/alongside a real crypto stack, not
> instead of one.

## Status

* Package `xiom.pki` 0.1.0, module `xiom.pki` (`src/pki.xi`).
* Conformance suite: 20 checks, all synthetic DER/PEM built in-test
  (`tests/test_conformance.xi`). Run `.\scripts\port.ps1 -Package xiom.pki`
  from the repository root.
* Byte-level behavior and the complete error catalog are in
  [SPEC.md](SPEC.md).

## Implemented

* **DER walker**: tag class / constructed bit / tag number including the
  high-tag-number form; definite short and long lengths (indefinite and
  non-minimal long forms rejected); truncation checks against the buffer and
  against enclosing containers; nested SEQUENCE/SET.
* **Primitives**: BOOLEAN, positive INTEGER, BIT STRING (unused-bit
  validation), OCTET STRING, NULL, OBJECT IDENTIFIER (dotted output),
  UTF8String / PrintableString / IA5String, UTCTime and GeneralizedTime
  (structured fields, YY < 50 -> 20YY).
* **Certificate**: `version [0]` (v1/v2/v3), serialNumber (positive, 1..20
  bytes), signature AlgorithmIdentifier, issuer/subject RDNSequence
  (multi-valued RDNs included), validity, subjectPublicKeyInfo (algorithm OID
  + key bit length), extensions `[3]`: basicConstraints (cA + pathLen),
  keyUsage (divisor/modulo bit decode), extKeyUsage, subjectAltName
  (DNS/email/URI/IP), subjectKeyIdentifier and authorityKeyIdentifier
  presence + hex. Unknown extension OIDs are preserved as dotted strings.
* **PEM unwrap**: one `BEGIN/END CERTIFICATE` block, LF or CRLF, strict
  self-contained base64 (canonical padding, zero unused trailing bits).
* Every structural error is a stable `Err(Str)` naming the **byte offset** of
  the offending structure.

## Not implemented

Signature/key verification of any kind; public-key internals; CSR, CRL,
OCSP, PKCS#7/#8/#12; BER indefinite lengths; name canonicalization;
criticality enforcement; calendar validation beyond numeric ranges. See
SPEC.md section 8.

## Usage

```xiom
module demo
use xiom.io;
use xiom.pki;
use xiom.string.compare;   // Str values from the model compare via str_compare

fn main() -> Int {
  let pem = "-----BEGIN CERTIFICATE-----\nTWFu\n-----END CERTIFICATE-----\n";
  let der = pki_pem_to_der(pem);
  if !der.is_ok {
    io.println("pem error: " + der.error);
    return 1;
  }
  let bytes: Vec[UInt8] = der.value;
  let cr = pki_certificate_parse(&bytes);
  if !cr.is_ok {
    io.println("der error: " + cr.error);
    return 1;
  }
  let cert: PkiCertificate = cr.value;
  io.println("version: " + pki_certificate_version(&cert));
  io.println("serial:  " + pki_serial_hex(&cert));
  io.println("spki:    " + pki_spki_algorithm_oid(&cert));
  io.println("key bits:" + pki_spki_key_bits(&cert));

  let issuer: PkiName = cert.issuer;
  var i = 0;
  while i < pki_name_attribute_count(&issuer) {
    io.println("issuer  " + pki_name_oid(&issuer, i) + " = " + pki_name_value(&issuer, i));
    i = i + 1;
  }

  let ex: PkiExtensions = cert.extensions;
  if pki_basic_constraints_present(&ex) {
    io.println("CA: " + pki_ca(&ex) + " pathLen: " + pki_path_len(&ex));
  }
  if pki_key_usage_present(&ex) {
    io.println("keyUsage bit 0 (digitalSignature): " + pki_key_usage_has(&ex, 0));
  }
  var k = 0;
  while k < pki_extension_count(&ex) {
    io.println("ext " + pki_extension_oid(&ex, k) + " critical=" + pki_extension_critical(&ex, k));
    k = k + 1;
  }
  return 0;
}
```

Reading `Str` values out of the model: compare them with
`xiom.string.compare.str_compare` (or a helper), never with `==`.

## Main API

| Function | Purpose |
|----------|---------|
| `pki_pem_to_der(text)` | unwrap one PEM CERTIFICATE block to DER bytes |
| `pki_certificate_parse(data)` | parse one full DER certificate |
| `der_tlv_decode(data, off)` / `der_tlv_in(data, off, end)` | walk any DER TLV |
| `der_length_decode`, `der_bool_decode`, `der_integer_decode`, `der_bit_string_decode`, `der_octet_string_decode`, `der_null_decode`, `der_oid_decode`, `der_string_decode`, `der_time_decode` | primitives |
| `pki_certificate_version`, `pki_serial_hex`, `pki_serial_len`, `pki_serial_bytes`, `pki_tbs_signature_oid`, `pki_outer_signature_oid`, `pki_spki_algorithm_oid`, `pki_spki_key_bits`, `pki_signature_bits` | certificate fields |
| `pki_name_*` | RDNSequence accessors |
| `pki_time_*` | structured time accessors |
| `pki_extension_*`, `pki_basic_constraints_present`, `pki_ca`, `pki_path_len`, `pki_key_usage_present`, `pki_key_usage_value`, `pki_key_usage_has`, `pki_ext_key_usage_*`, `pki_san_*`, `pki_has_subject_key_id`, `pki_subject_key_id_hex`, `pki_has_authority_key_id`, `pki_authority_key_id_hex` | extension accessors |

## Layout

```
package.xi               manifest (xiom.pki 0.1.0)
src/pki.xi               the parser module
tests/test_conformance.xi  20 synthetic-DER conformance checks
SPEC.md                  byte-level behavior + error catalog
```

License: MIT OR Apache-2.0.
