# xiom.saml

> **Status:** `incubating` -- conformance-tested (28/28); published at `v0.1.0` on the XIOM registry.

Pure-XIOM **structure toolkit** for SAML 2.0: a minimal XML subset reader,
assertion/response parsing, SP-initiated AuthnRequest building, IdP metadata
parsing, in-package base64 and SHA-256, and XML-DSig *structural* parsing with
SHA-256 digest verification. No FFI, no networking; depends only on
`xiom.std`.

> **No networking and no trust.** This package never opens a socket, never
> contacts an IdP, never decrypts an `EncryptedAssertion`, and never verifies
> an RSA/ECDSA signature. A structure that parses is not a structure that is
> trusted. Pair it with your own transport, key store and signature
> verification (or a real crypto stack), not instead of them.

## Status

* Package `xiom.saml` 0.1.0, module `xiom.saml` (`src/saml.xi`).
* Conformance suite: 28 checks, all fixtures inline
  (`tests/test_conformance.xi`). Run `.\scripts\port.ps1 -Package xiom.saml`
  from the repository root.
* Byte-level behavior, limits and the complete error catalog are in
  [SPEC.md](SPEC.md).

## Implemented

* **XML subset reader** (`saml_xml_parse`): elements, double/single-quoted
  attributes, self-closing tags, text, the five predefined entities plus
  `&#NN;` / `&#xHH;` numeric references, comments, processing instructions and
  CDATA. DOCTYPE / internal subsets are rejected. The document is a flat node
  list in parallel `Vec` fields; namespace-prefix queries work on local names.
  Bounded: 1 MiB input, depth 64, 16384 nodes, 256 attributes per element,
  duplicate attributes rejected. Errors carry byte offsets.
* **Base64** (`saml_base64_encode` / `saml_base64_decode`): standard alphabet
  with optional padding, whitespace tolerated, strict padding placement and
  non-canonical trailing-bit rejection. `saml_post_binding_encode` /
  `saml_post_binding_decode` carry a SAML message over the HTTP-POST binding.
  Hand-rolled in-package (the local stdlib ships base64 too; see SPEC.md
  section 7).
* **SHA-256** (`saml_sha256`, `saml_sha256_hex`, `saml_sha256_str`):
  FIPS 180-4 via the stdlib `xiom.crypto` module; used for XML-DSig
  `DigestValue` checks.
* **xs:dateTime** (`saml_parse_datetime` / `saml_format_datetime`): integer
  epoch-seconds UTC model with `Z` or `(+|-)hh:mm` offsets; fractional seconds
  accepted and truncated; leap-year rules enforced; no floating point.
* **Assertions** (`saml_assertion_parse`): Issuer, Subject/NameID format,
  first SubjectConfirmationData (Recipient / InResponseTo), Conditions
  (NotBefore / NotOnOrAfter as epochs, AudienceRestriction flattened),
  AuthnStatement (AuthnInstant / SessionIndex), AttributeStatement flattened
  into parallel name/format/friendly/count/value vectors, and Signature
  location. Conditions validation with optional clock skew and audience
  matching.
* **Responses** (`saml_response_parse`): envelope fields, Issuer, Status
  (StatusCode / StatusMessage), direct Assertion and EncryptedAssertion
  counts, per-assertion extraction, Signature location and a success
  predicate.
* **AuthnRequest** (`saml_authn_request_build` / `saml_authn_request_parse`):
  deterministic attribute order, XML escaping, round-trip parse.
* **IdP metadata** (`saml_idp_metadata_parse`): EntityDescriptor entityID,
  IDPSSODescriptor protocol support and WantAuthnRequestsSigned, all
  SingleSignOnService Binding/Location pairs, and normalized X509Certificate
  base64 entries.
* **XML-DSig structure** (`saml_dsig_parse`): SignedInfo,
  CanonicalizationMethod, SignatureMethod, References (URI, DigestMethod,
  DigestValue) and SignatureValue; reference resolution by `ID`/`Id`/`xml:id`;
  digest length checks per algorithm; SHA-256 digest verification over
  caller-supplied octets or over the raw referenced element span.

## Not implemented

Public-key signature verification (RSA/ECDSA), decoder of
`EncryptedAssertion`, exclusive C14N transform, HTTP-Redirect deflate
encoding, SAML protocol state machines, XML Encryption. See SPEC.md section 8.

## Usage

```xiom
module demo
use xiom.io;
use xiom.saml;
use xiom.string.compare;   // Str values from the model compare via str_compare

fn main() -> Int {
  // POST binding: an SP receives base64(Response XML).
  let payload = "PHNhbWxwOlJlc3BvbnNlIC8+";
  let xml = saml_post_binding_decode(payload);
  if !xml.is_ok {
    io.println("decode error: " + xml.error);
    return 1;
  }
  let text: Str = xml.value;
  let rr = saml_response_parse(text);
  if !rr.is_ok {
    io.println("parse error: " + rr.error);
    return 1;
  }
  let resp = rr.value;
  if !saml_response_is_success(&resp) {
    io.println("status: " + resp.status_code);
    return 1;
  }
  let ar = saml_response_assertion(&resp, 0);
  if !ar.is_ok {
    io.println("no assertion: " + ar.error);
    return 1;
  }
  let assertion = ar.value;
  let now = 1780000000;   // caller-supplied UTC clock
  let vr = saml_assertion_valid_at(&assertion, now);
  if !vr.is_ok {
    io.println("invalid: " + vr.error);
    return 1;
  }
  io.println("subject: " + assertion.subject.name_id);
  return 0;
}
```
