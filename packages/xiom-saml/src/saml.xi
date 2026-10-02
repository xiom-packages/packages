// XIOM -- xiom.saml: SAML 2.0 structure toolkit (assertions, SSO, metadata, XML-DSig structure)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no public-key crypto) STRUCTURE toolkit for
// SAML 2.0. It parses and builds the payloads a caller exchanges over its own
// transport; it never performs network I/O, never contacts an IdP, never
// decodes an EncryptedAssertion, and never verifies an RSA/ECDSA signature.
//
// Covered surface (see SPEC.md for the exact grammar, limits and error
// catalog):
//   * A minimal XML subset reader: elements, attributes (double or single
//     quoted), entity decoding (&amp; &lt; &gt; &quot; &apos; plus &#NN; and
//     &#xHH;), comments, processing instructions, CDATA, and self-closing
//     tags, with bounded nesting depth, node count and attribute count. A
//     DOCTYPE / internal subset is rejected. The document is carried as a
//     FLAT node list in parallel Vec fields (Vec[StructType] is unsupported
//     on this compiler); node 0 is a synthetic document root.
//   * In-package standard base64 encode/decode (strict padding and trailing
//     bit checks) and the HTTP-POST binding helpers that carry the base64
//     payload of a SAML message. The local stdlib ships a base64 module, but
//     this package hand-rolls its own to stay dependency-free as briefed.
//   * An in-package SHA-256 (FIPS 180-4) used for XML-DSig DigestValue
//     checks. Full XML-DSig (exclusive c14n transforms and public-key
//     signature verification) is a documented non-goal.
//   * xs:dateTime parsing/formatting with an Int epoch-seconds model
//     (integer timestamps only; no floats).
//   * SAML Assertion and Response parsing: Issuer, Subject/NameID,
//     SubjectConfirmationData, Conditions (NotBefore / NotOnOrAfter /
//     AudienceRestriction), AuthnStatement, AttributeStatement (flattened
//     attribute/value lists), Status, and Signature location.
//   * Condition validation helpers with optional clock skew and audience
//     matching.
//   * SP-initiated AuthnRequest building (deterministic attribute order) and
//     parsing, for the POST binding.
//   * IdP EntityDescriptor metadata parsing: entityID, IDPSSODescriptor,
//     WantAuthnRequestsSigned, SingleSignOnService bindings/locations and
//     X509Certificate entries (normalized base64 text).
//   * XML-DSig STRUCTURAL parsing: SignedInfo, CanonicalizationMethod,
//     SignatureMethod, References (URI, DigestMethod, DigestValue) and
//     SignatureValue presence, reference resolution by ID/Id/xml:id, digest
//     length checks per algorithm, and SHA-256 digest verification over
//     caller-supplied octets or over the raw referenced element bytes.
//
// v0.62.2 notes that shaped this module:
//   * free functions only; no methods, no lambdas, no mut match patterns,
//     no Vec of structs, no Vec[fn] dispatch, no table-driven dispatch;
//   * Ok/Err construction for struct payloads is confined to the tiny leaf
//     helpers below (constructing Results directly inside larger functions
//     miscompiles);
//   * every Str read out of a Vec[Str] element is compared only through
//     xiom.string.compare.str_compare (BUG 17 discipline);
//   * every byte read from a Vec[UInt8] is widened with `(x as Int) & 0xFF`
//     before it enters Int arithmetic;
//   * the XML parser is iterative with an explicit open-element stack; the
//     nesting depth, node count, attribute count and input size are capped;
//   * parallel Vecs are pushed in lockstep and mismatched lengths are
//     treated as malformed.

module xiom.saml

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;

// --------------------------------------------------
//  Public constants
// --------------------------------------------------

/// SAML protocol version implemented by this module.
pub const SAML_VERSION: Str = "2.0";

/// SAML assertion namespace URI.
pub const SAML_NS_ASSERTION: Str = "urn:oasis:names:tc:SAML:2.0:assertion";

/// SAML protocol namespace URI.
pub const SAML_NS_PROTOCOL: Str = "urn:oasis:names:tc:SAML:2.0:protocol";

/// SAML metadata namespace URI.
pub const SAML_NS_METADATA: Str = "urn:oasis:names:tc:SAML:2.0:metadata";

/// XML digital signature namespace URI.
pub const SAML_NS_DSIG: Str = "http://www.w3.org/2000/09/xmldsig#";

/// Top-level success status code.
pub const SAML_STATUS_SUCCESS: Str = "urn:oasis:names:tc:SAML:2.0:status:Success";

/// Top-level requester-error status code.
pub const SAML_STATUS_REQUESTER: Str = "urn:oasis:names:tc:SAML:2.0:status:Requester";

/// Top-level responder-error status code.
pub const SAML_STATUS_RESPONDER: Str = "urn:oasis:names:tc:SAML:2.0:status:Responder";

/// Top-level version-mismatch status code.
pub const SAML_STATUS_VERSION_MISMATCH: Str = "urn:oasis:names:tc:SAML:2.0:status:VersionMismatch";

/// Common prefix of every registered status code.
pub const SAML_STATUS_PREFIX: Str = "urn:oasis:names:tc:SAML:2.0:status:";

/// HTTP-Redirect binding identifier.
pub const SAML_BINDING_HTTP_REDIRECT: Str = "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-Redirect";

/// HTTP-POST binding identifier.
pub const SAML_BINDING_HTTP_POST: Str = "urn:oasis:names:tc:SAML:2.0:bindings:HTTP-POST";

/// URI reference of the Exclusive XML Canonicalization transform.
pub const SAML_ALG_C14N_EXCLUSIVE: Str = "http://www.w3.org/2001/10/xml-exc-c14n#";

/// RSA-SHA256 signature method URI.
pub const SAML_ALG_SIG_RSA_SHA256: Str = "http://www.w3.org/2001/04/xmldsig-more#rsa-sha256";

/// SHA-256 digest method URI.
pub const SAML_ALG_DIGEST_SHA256: Str = "http://www.w3.org/2001/04/xmlenc#sha256";

/// SHA-1 digest method URI (accepted for structural parsing; not computed).
pub const SAML_ALG_DIGEST_SHA1: Str = "http://www.w3.org/2000/09/xmldsig#sha1";

/// SHA-512 digest method URI (accepted for structural parsing; not computed).
pub const SAML_ALG_DIGEST_SHA512: Str = "http://www.w3.org/2001/04/xmlenc#sha512";

// Parser limits (bounded work, see SPEC.md).
const _SAML_MAX_XML: Int = 1048576;
const _SAML_MAX_DEPTH: Int = 64;
const _SAML_MAX_NODES: Int = 16384;
const _SAML_MAX_ATTRS: Int = 256;

// Byte constants (Int space).
const _SAML_LT: Int = 60;
const _SAML_GT: Int = 62;
const _SAML_AMP: Int = 38;
const _SAML_DQUOTE: Int = 34;
const _SAML_SQUOTE: Int = 39;
const _SAML_SLASH: Int = 47;
const _SAML_EQ: Int = 61;
const _SAML_BANG: Int = 33;
const _SAML_QUEST: Int = 63;
const _SAML_HASH: Int = 35;
const _SAML_SEMI: Int = 59;
const _SAML_DASH: Int = 45;
const _SAML_SPACE: Int = 32;
const _SAML_TAB: Int = 9;
const _SAML_CR: Int = 13;
const _SAML_LF: Int = 10;
const _SAML_LOWER_X: Int = 120;
const _SAML_UPPER_X: Int = 88;
const _SAML_COLON: Int = 58;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A parsed XML document as a flat node list with parallel vectors.
/// kinds[i] is 0 for an element and 1 for a text node; node 0 is the
/// synthetic document root (an element with an empty name and parent -1) and
/// is always present at index 0. names[i] holds an element's tag name ("" for
/// text nodes), texts[i] a text node's decoded content ("" for elements) and
/// parents[i] the owning node index (-1 only for node 0). opens[i]/closes[i]
/// bound the source byte range of node i: [opens[i], closes[i]) is the raw
/// element (start tag through end tag) or text run. Attributes form a flat
/// association list: attr_names[k] / attr_values[k] belong to node
/// attr_owners[k]. src holds the whole document bytes for raw-span work.
pub type XmlDoc = {
  kinds: Vec[Int];
  names: Vec[Str];
  texts: Vec[Str];
  parents: Vec[Int];
  opens: Vec[Int];
  closes: Vec[Int];
  attr_names: Vec[Str];
  attr_values: Vec[Str];
  attr_owners: Vec[Int];
  src: Vec[UInt8];
}

/// SAML Conditions as parsed from an Assertion.
/// Timestamps are epoch seconds (UTC); `has_*` flags mark presence. Audience
/// restrictions are flattened in document order.
pub type SamlConditions = {
  has_not_before: Bool;
  not_before_text: Str;
  not_before_epoch: Int;
  has_not_on_or_after: Bool;
  not_on_or_after_text: Str;
  not_on_or_after_epoch: Int;
  has_audience_restriction: Bool;
  audiences: Vec[Str];
}

/// SAML Subject subset: NameID plus the first SubjectConfirmationData.
pub type SamlSubject = {
  has_subject: Bool;
  has_name_id: Bool;
  name_id: Str;
  name_id_format: Str;
  confirmation_count: Int;
  recipient: Str;
  in_response_to: Str;
}

/// Flattened AttributeStatement: attribute i has names[i]/name_formats[i]/
/// friendly_names[i] and value_counts[i] values; those values live in
/// `values` and `value_owners` (owner index into `names`). The two value
/// vectors are always pushed in lockstep and never drift.
pub type SamlAttributes = {
  names: Vec[Str];
  name_formats: Vec[Str];
  friendly_names: Vec[Str];
  value_counts: Vec[Int];
  values: Vec[Str];
  value_owners: Vec[Int];
}

/// A parsed SAML Assertion (structure only; no trust).
pub type SamlAssertion = {
  doc: XmlDoc;
  node: Int;
  id: Str;
  version: Str;
  issue_instant: Str;
  has_issuer: Bool;
  issuer: Str;
  subject: SamlSubject;
  conditions: SamlConditions;
  has_authn_statement: Bool;
  authn_instant: Str;
  session_index: Str;
  attributes: SamlAttributes;
  has_signature: Bool;
  signature_node: Int;
}

/// A parsed SAML Response envelope (assertions are extracted separately).
pub type SamlResponse = {
  doc: XmlDoc;
  node: Int;
  id: Str;
  version: Str;
  issue_instant: Str;
  destination: Str;
  in_response_to: Str;
  has_issuer: Bool;
  issuer: Str;
  has_status: Bool;
  status_code: Str;
  status_message: Str;
  assertion_count: Int;
  encrypted_assertion_count: Int;
  has_signature: Bool;
  signature_node: Int;
}

/// A parsed SAML AuthnRequest.
pub type SamlAuthnRequest = {
  doc: XmlDoc;
  node: Int;
  id: Str;
  version: Str;
  issue_instant: Str;
  destination: Str;
  acs_url: Str;
  has_issuer: Bool;
  issuer: Str;
  has_signature: Bool;
  signature_node: Int;
}

/// Parsed IdP EntityDescriptor metadata. SSO services and certificates are
/// flattened into parallel vectors; `sso_count` and `cert_count` mirror
/// their lengths.
pub type SamlIdpMetadata = {
  doc: XmlDoc;
  node: Int;
  entity_id: Str;
  has_entity_id: Bool;
  want_authn_requests_signed: Bool;
  protocol_support: Str;
  sso_count: Int;
  sso_bindings: Vec[Str];
  sso_locations: Vec[Str];
  cert_count: Int;
  certs: Vec[Str];
  has_signature: Bool;
  signature_node: Int;
}

/// Parsed XML-DSig Signature structure. References are flattened:
/// ref_uri[i] / ref_digest_algorithm[i] / ref_digest_value[i] describe
/// reference i; reference_count mirrors the three lengths.
pub type SamlSignature = {
  doc: XmlDoc;
  node: Int;
  has_signed_info: Bool;
  canonicalization_algorithm: Str;
  signature_algorithm: Str;
  reference_count: Int;
  ref_uri: Vec[Str];
  ref_digest_algorithm: Vec[Str];
  ref_digest_value: Vec[Str];
  has_signature_value: Bool;
  signature_value: Str;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[XmlDoc, Str].
fn _ok_doc(v: XmlDoc) -> Result[XmlDoc, Str] {
  return Ok(v);
}

// Err(m) for Result[XmlDoc, Str].
fn _err_doc(m: Str) -> Result[XmlDoc, Str] {
  return Err(m);
}

// Ok(v) for Result[Str, Str].
fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

// Err(m) for Result[Str, Str].
fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(v) for Result[SamlAssertion, Str].
fn _ok_assertion(v: SamlAssertion) -> Result[SamlAssertion, Str] {
  return Ok(v);
}

// Err(m) for Result[SamlAssertion, Str].
fn _err_assertion(m: Str) -> Result[SamlAssertion, Str] {
  return Err(m);
}

// Ok(v) for Result[SamlResponse, Str].
fn _ok_response(v: SamlResponse) -> Result[SamlResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[SamlResponse, Str].
fn _err_response(m: Str) -> Result[SamlResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[SamlAuthnRequest, Str].
fn _ok_req(v: SamlAuthnRequest) -> Result[SamlAuthnRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[SamlAuthnRequest, Str].
fn _err_req(m: Str) -> Result[SamlAuthnRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[SamlIdpMetadata, Str].
fn _ok_meta(v: SamlIdpMetadata) -> Result[SamlIdpMetadata, Str] {
  return Ok(v);
}

// Err(m) for Result[SamlIdpMetadata, Str].
fn _err_meta(m: Str) -> Result[SamlIdpMetadata, Str] {
  return Err(m);
}

// Ok(v) for Result[SamlSignature, Str].
fn _ok_signature(v: SamlSignature) -> Result[SamlSignature, Str] {
  return Ok(v);
}

// Err(m) for Result[SamlSignature, Str].
fn _err_signature(m: Str) -> Result[SamlSignature, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Shared helpers
// --------------------------------------------------

// Str equality through str_compare (BUG 17 discipline).
fn _streq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Raw bytes of a Str (one byte per index); NUL cannot occur in a Str.
fn _str_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// Copy data[a, b) into a fresh vector; callers guarantee the bounds.
fn _copy_span(data: &Vec[UInt8], a: Int, b: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = a;
  while i < b {
    out.push(data[i]);
    i = i + 1;
  }
  return out;
}

// True when a and b hold the same bytes.
fn _bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    let x: Int = (a[i] as Int) & 0xFF;
    let y: Int = (b[i] as Int) & 0xFF;
    if x != y {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  XML parser state and helpers
// --------------------------------------------------

// Mutable parser state (mirrors the proven xiom.xml shape).
type _XmlParser = {
  text: Str;
  pos: Int;
  kinds: Vec[Int];
  names: Vec[Str];
  texts: Vec[Str];
  parents: Vec[Int];
  opens: Vec[Int];
  closes: Vec[Int];
  attr_names: Vec[Str];
  attr_values: Vec[Str];
  attr_owners: Vec[Int];
  stack: Vec[Int];
  have_root: Bool;
  failed: Bool;
  error: Str;
}

// Record the first failure as "<m> at offset <pos>" and return false.
fn _fail(p: &mut _XmlParser, m: Str) -> Bool {
  if p.failed {
    return false;
  }
  p.failed = true;
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, m);
  builder.sb_push_str(&mut out, " at offset ");
  builder.sb_push_int(&mut out, p.pos);
  p.error = builder.sb_to_str(&out);
  return false;
}

// Byte of the parser text at i, widened to 0..255.
fn _pbyte(p: &_XmlParser, i: Int) -> Int {
  return (string.byte_at(p.text, i) as Int) & 0xFF;
}

// True for XML whitespace: space, TAB, CR, LF.
fn _is_ws(b: Int) -> Bool {
  if b == _SAML_SPACE || b == _SAML_TAB {
    return true;
  }
  if b == _SAML_CR || b == _SAML_LF {
    return true;
  }
  return false;
}

// True when every byte of s is XML whitespace.
fn _is_ws_only(s: Str) -> Bool {
  var i = 0;
  while i < s.len() {
    if !_is_ws((string.byte_at(s, i) as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Byte that ends a tag or attribute name: whitespace, '<', '>', '/' or '='.
fn _is_name_end(b: Int) -> Bool {
  if _is_ws(b) {
    return true;
  }
  if b == _SAML_LT || b == _SAML_GT {
    return true;
  }
  if b == _SAML_SLASH || b == _SAML_EQ {
    return true;
  }
  return false;
}

// Skip whitespace from the parser position.
fn _skip_ws(p: &mut _XmlParser) {
  let n = p.text.len();
  while p.pos < n {
    if !_is_ws(_pbyte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
}

// Index of the first occurrence of `needle` at or after `from`, -1 when absent.
fn _find_seq(p: &_XmlParser, from: Int, needle: Str) -> Int {
  let n = p.text.len();
  let m = needle.len();
  var i = from;
  while i + m <= n {
    var j = 0;
    var hit = true;
    while j < m {
      if _pbyte(p, i + j) != ((string.byte_at(needle, j) as Int) & 0xFF) {
        hit = false;
        break;
      }
      j = j + 1;
    }
    if hit {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// True when the literal `lit` occurs at pos.
fn _seq_at(p: &_XmlParser, pos: Int, lit: Str) -> Bool {
  if pos + lit.len() > p.text.len() {
    return false;
  }
  var i = 0;
  while i < lit.len() {
    if _pbyte(p, pos + i) != ((string.byte_at(lit, i) as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Append the UTF-8 encoding of code (1..0x10FFFF) to out.
fn _push_utf8(out: &mut Vec[UInt8], code: Int) {
  if code <= 127 {
    out.push(code as UInt8);
    return;
  }
  if code <= 2047 {
    out.push((192 + code / 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  if code <= 65535 {
    out.push((224 + code / 4096) as UInt8);
    out.push((128 + (code / 64) % 64) as UInt8);
    out.push((128 + code % 64) as UInt8);
    return;
  }
  out.push((240 + code / 262144) as UInt8);
  out.push((128 + (code / 4096) % 64) as UInt8);
  out.push((128 + (code / 64) % 64) as UInt8);
  out.push((128 + code % 64) as UInt8);
}

// Codepoint of a "#NN" or "#xHH" reference body: >0 on success, -1 for a NUL,
// malformed digits, an empty body or a value above U+10FFFF.
fn _entity_code(body: Str) -> Int {
  let n = body.len();
  if n < 2 {
    return -1;
  }
  if ((string.byte_at(body, 0) as Int) & 0xFF) != _SAML_HASH {
    return -1;
  }
  var i = 1;
  var base = 10;
  let mark = (string.byte_at(body, i) as Int) & 0xFF;
  if mark == _SAML_LOWER_X || mark == _SAML_UPPER_X {
    base = 16;
    i = i + 1;
  }
  if i >= n {
    return -1;
  }
  var v = 0;
  while i < n {
    let b = (string.byte_at(body, i) as Int) & 0xFF;
    var d = -1;
    if b >= 48 && b <= 57 {
      d = b - 48;
    } elif base == 16 && b >= 97 && b <= 102 {
      d = b - 87;
    } elif base == 16 && b >= 65 && b <= 70 {
      d = b - 55;
    } else {
      return -1;
    }
    if d >= base {
      return -1;
    }
    v = v * base + d;
    if v > 1114111 {
      return -1;
    }
    i = i + 1;
  }
  if v == 0 {
    return -1;
  }
  if v >= 55296 && v <= 57343 {
    return -1;
  }
  return v;
}

// Decode one entity starting at `at` (which must be '&'); appends the decoded
// bytes and returns the number of input bytes consumed, or -1 after setting
// the parser error.
fn _push_entity(p: &mut _XmlParser, at: Int, end: Int, out: &mut Vec[UInt8]) -> Int {
  var limit = at + 11;
  if limit > end {
    limit = end;
  }
  var semi = -1;
  var j = at + 1;
  while j < limit {
    if _pbyte(p, j) == _SAML_SEMI {
      semi = j;
      break;
    }
    j = j + 1;
  }
  if semi < 0 {
    _fail(p, "saml: unterminated entity");
    return -1;
  }
  let body = string.str_slice(p.text, at + 1, semi);
  if _streq(body, "amp") {
    out.push(_SAML_AMP as UInt8);
    return semi - at + 1;
  }
  if _streq(body, "lt") {
    out.push(_SAML_LT as UInt8);
    return semi - at + 1;
  }
  if _streq(body, "gt") {
    out.push(_SAML_GT as UInt8);
    return semi - at + 1;
  }
  if _streq(body, "quot") {
    out.push(_SAML_DQUOTE as UInt8);
    return semi - at + 1;
  }
  if _streq(body, "apos") {
    out.push(_SAML_SQUOTE as UInt8);
    return semi - at + 1;
  }
  let code = _entity_code(body);
  if code > 0 {
    _push_utf8(out, code);
    return semi - at + 1;
  }
  _fail(p, "saml: invalid character reference");
  return -1;
}

// Entity-decode text[start, end) into out; false on the first bad entity.
fn _decode_into(p: &mut _XmlParser, start: Int, end: Int, out: &mut Vec[UInt8]) -> Bool {
  var i = start;
  while i < end {
    let b = _pbyte(p, i);
    if b == _SAML_AMP {
      let adv = _push_entity(p, i, end, out);
      if adv < 0 {
        return false;
      }
      i = i + adv;
    } else {
      out.push(string.byte_at(p.text, i));
      i = i + 1;
    }
  }
  return true;
}

// --------------------------------------------------
//  XML parser internals
// --------------------------------------------------

// Append one node (kind 0 element, 1 text) and return its index.
fn _push_node(p: &mut _XmlParser, kind: Int, name: Str, txt: Str, parent: Int, open: Int, close: Int) -> Int {
  p.kinds.push(kind);
  p.names.push(name);
  p.texts.push(txt);
  p.parents.push(parent);
  p.opens.push(open);
  p.closes.push(close);
  return p.kinds.len() - 1;
}

// Append one attribute association.
fn _push_attr(p: &mut _XmlParser, owner: Int, name: Str, value: Str) {
  p.attr_names.push(name);
  p.attr_values.push(value);
  p.attr_owners.push(owner);
}

// Consume character data up to the next '<' or EOF.
fn _consume_text(p: &mut _XmlParser) -> Bool {
  let n = p.text.len();
  let start = p.pos;
  var i = p.pos;
  while i < n {
    if _pbyte(p, i) == _SAML_LT {
      break;
    }
    i = i + 1;
  }
  var out = Vec[UInt8].new();
  if !_decode_into(p, start, i, &mut out) {
    return false;
  }
  let txt = builder.sb_to_str(&out);
  p.pos = i;
  if p.stack.len() == 0 {
    if _is_ws_only(txt) {
      return true;
    }
    return _fail(p, "saml: text outside root element");
  }
  if p.kinds.len() >= _SAML_MAX_NODES {
    return _fail(p, "saml: too many nodes");
  }
  let parent: Int = p.stack[p.stack.len() - 1];
  _push_node(p, 1, "", txt, parent, start, i);
  return true;
}

// Consume a start tag (p.pos at the first name byte) and register the element
// plus its attributes.
fn _start_tag(p: &mut _XmlParser) -> Bool {
  let n = p.text.len();
  let open = p.pos - 1;
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_pbyte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start {
    return _fail(p, "saml: stray '<'");
  }
  let name = string.str_slice(p.text, name_start, p.pos);
  var parent = 0;
  if p.stack.len() > 0 {
    parent = p.stack[p.stack.len() - 1];
  } else {
    if p.have_root {
      return _fail(p, "saml: multiple root elements");
    }
    p.have_root = true;
  }
  if p.kinds.len() >= _SAML_MAX_NODES {
    return _fail(p, "saml: too many nodes");
  }
  let node = _push_node(p, 0, name, "", parent, open, 0);
  var seen = Vec[Str].new();
  var self_close = false;
  loop {
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "saml: unclosed tag");
    }
    let b = _pbyte(p, p.pos);
    if b == _SAML_GT {
      p.pos = p.pos + 1;
      break;
    }
    if b == _SAML_SLASH {
      p.pos = p.pos + 1;
      _skip_ws(p);
      if p.pos >= n {
        return _fail(p, "saml: unclosed tag");
      }
      if _pbyte(p, p.pos) != _SAML_GT {
        return _fail(p, "saml: malformed tag");
      }
      p.pos = p.pos + 1;
      self_close = true;
      break;
    }
    let an_start = p.pos;
    while p.pos < n {
      if _is_name_end(_pbyte(p, p.pos)) {
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos == an_start {
      return _fail(p, "saml: malformed attribute");
    }
    let aname = string.str_slice(p.text, an_start, p.pos);
    var d = 0;
    var dup = false;
    while d < seen.len() {
      let prev: Str = seen[d];
      if _streq(prev, aname) {
        dup = true;
      }
      d = d + 1;
    }
    if dup {
      return _fail(p, "saml: duplicate attribute");
    }
    if seen.len() >= _SAML_MAX_ATTRS {
      return _fail(p, "saml: too many attributes");
    }
    seen.push(aname);
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "saml: unclosed tag");
    }
    if _pbyte(p, p.pos) != _SAML_EQ {
      return _fail(p, "saml: malformed attribute");
    }
    p.pos = p.pos + 1;
    _skip_ws(p);
    if p.pos >= n {
      return _fail(p, "saml: unclosed tag");
    }
    let q = _pbyte(p, p.pos);
    if q != _SAML_DQUOTE && q != _SAML_SQUOTE {
      return _fail(p, "saml: malformed attribute");
    }
    p.pos = p.pos + 1;
    let v_start = p.pos;
    while p.pos < n {
      if _pbyte(p, p.pos) == q {
        break;
      }
      p.pos = p.pos + 1;
    }
    if p.pos >= n {
      return _fail(p, "saml: unclosed attribute value");
    }
    var vout = Vec[UInt8].new();
    if !_decode_into(p, v_start, p.pos, &mut vout) {
      return false;
    }
    let value = builder.sb_to_str(&vout);
    p.pos = p.pos + 1;
    _push_attr(p, node, aname, value);
  }
  if self_close {
    p.closes[node] = p.pos;
  } else {
    if p.stack.len() >= _SAML_MAX_DEPTH {
      return _fail(p, "saml: nesting too deep");
    }
    p.stack.push(node);
  }
  return true;
}

// Consume a closing tag (p.pos at the first name byte after "</").
fn _close_tag(p: &mut _XmlParser) -> Bool {
  let n = p.text.len();
  let name_start = p.pos;
  while p.pos < n {
    if _is_name_end(_pbyte(p, p.pos)) {
      break;
    }
    p.pos = p.pos + 1;
  }
  if p.pos == name_start {
    return _fail(p, "saml: stray '<'");
  }
  let name = string.str_slice(p.text, name_start, p.pos);
  _skip_ws(p);
  if p.pos >= n {
    return _fail(p, "saml: unclosed tag");
  }
  if _pbyte(p, p.pos) != _SAML_GT {
    return _fail(p, "saml: malformed tag");
  }
  p.pos = p.pos + 1;
  if p.stack.len() == 0 {
    return _fail(p, "saml: unexpected closing tag");
  }
  let open_idx: Int = p.stack[p.stack.len() - 1];
  let oname: Str = p.names[open_idx];
  if !_streq(oname, name) {
    return _fail(p, "saml: mismatched closing tag");
  }
  p.closes[open_idx] = p.pos;
  p.stack.pop();
  return true;
}

// Consume markup after '<'.
fn _consume_markup(p: &mut _XmlParser) -> Bool {
  let n = p.text.len();
  if p.pos >= n {
    return _fail(p, "saml: unclosed tag");
  }
  let b = _pbyte(p, p.pos);
  if b == _SAML_BANG {
    if p.pos + 2 < n && _pbyte(p, p.pos + 1) == _SAML_DASH {
      if _pbyte(p, p.pos + 2) == _SAML_DASH {
        p.pos = p.pos + 3;
        let close = _find_seq(p, p.pos, "-->");
        if close < 0 {
          return _fail(p, "saml: unclosed comment");
        }
        p.pos = close + 3;
        return true;
      }
    }
    if _seq_at(p, p.pos, "![CDATA[") {
      p.pos = p.pos + 8;
      let cstart = p.pos;
      let close2 = _find_seq(p, p.pos, "]]>");
      if close2 < 0 {
        return _fail(p, "saml: unclosed CDATA section");
      }
      if p.stack.len() == 0 {
        return _fail(p, "saml: text outside root element");
      }
      if p.kinds.len() >= _SAML_MAX_NODES {
        return _fail(p, "saml: too many nodes");
      }
      let txt = string.str_slice(p.text, cstart, close2);
      let parent: Int = p.stack[p.stack.len() - 1];
      _push_node(p, 1, "", txt, parent, cstart, close2);
      p.pos = close2 + 3;
      return true;
    }
    return _fail(p, "saml: unsupported markup declaration");
  }
  if b == _SAML_QUEST {
    p.pos = p.pos + 1;
    let close3 = _find_seq(p, p.pos, "?>");
    if close3 < 0 {
      return _fail(p, "saml: unclosed processing instruction");
    }
    p.pos = close3 + 2;
    return true;
  }
  if b == _SAML_SLASH {
    p.pos = p.pos + 1;
    return _close_tag(p);
  }
  return _start_tag(p);
}

// Parse the whole document text into the flat node model.
fn _xml_parse(text: Str) -> Result[XmlDoc, Str] {
  if text.len() > _SAML_MAX_XML {
    return _err_doc("saml: document too large");
  }
  var p = _XmlParser{
    text: text;
    pos: 0;
    kinds: Vec[Int].new();
    names: Vec[Str].new();
    texts: Vec[Str].new();
    parents: Vec[Int].new();
    opens: Vec[Int].new();
    closes: Vec[Int].new();
    attr_names: Vec[Str].new();
    attr_values: Vec[Str].new();
    attr_owners: Vec[Int].new();
    stack: Vec[Int].new();
    have_root: false;
    failed: false;
    error: "";
  };
  _push_node(&mut p, 0, "", "", -1, 0, text.len());
  let n = text.len();
  while p.pos < n {
    let b = _pbyte(&p, p.pos);
    if b == _SAML_LT {
      p.pos = p.pos + 1;
      if !_consume_markup(&mut p) {
        return _err_doc(p.error);
      }
    } else {
      if !_consume_text(&mut p) {
        return _err_doc(p.error);
      }
    }
  }
  if p.stack.len() > 0 {
    return _err_doc("saml: unclosed element");
  }
  if !p.have_root {
    return _err_doc("saml: no root element");
  }
  let src = _str_bytes(text);
  return _ok_doc(XmlDoc{
    kinds: p.kinds;
    names: p.names;
    texts: p.texts;
    parents: p.parents;
    opens: p.opens;
    closes: p.closes;
    attr_names: p.attr_names;
    attr_values: p.attr_values;
    attr_owners: p.attr_owners;
    src: src;
  });
}

// --------------------------------------------------
//  XML public API
// --------------------------------------------------

/// Parse an XML document in the supported subset.
/// Params: text - the whole document as one Str.
/// Returns: Ok(doc) with the flat node model (node 0 is the synthetic root).
/// Error case: Err("saml: ... at offset N") on the first malformed construct;
/// see SPEC.md for the catalog (stray '<', unclosed/malformed tag, unclosed
/// attribute value, duplicate attribute, bad entity, unclosed comment/PI/
/// CDATA, unsupported DOCTYPE, mismatched closing tag, text outside the root,
/// multiple roots, too deep / too many nodes / too many attributes / document
/// too large).
/// Complexity: O(n) over the document length.
pub fn saml_xml_parse(text: Str) -> Result[XmlDoc, Str] {
  return _xml_parse(text);
}

// Local part of a qualified name (text after the first ':').
fn _local_name_of(s: Str) -> Str {
  var i = 0;
  while i < s.len() {
    if ((string.byte_at(s, i) as Int) & 0xFF) == _SAML_COLON {
      return string.str_slice(s, i + 1, s.len());
    }
    i = i + 1;
  }
  return s;
}

/// Index of the root element (first element child of the synthetic root).
/// Params: d - the parsed document. Returns: the node index or -1.
/// Error case: none. Complexity: O(nodes).
pub fn saml_xml_root(d: &XmlDoc) -> Int {
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 {
      if d.parents[i] == 0 {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Number of nodes, including the synthetic root. Empty documents report 1.
pub fn saml_xml_node_count(d: &XmlDoc) -> Int {
  return d.kinds.len();
}

/// Node kind: 0 element, 1 text. -1 when out of range.
pub fn saml_xml_node_kind(d: &XmlDoc, node: Int) -> Int {
  if node < 0 || node >= d.kinds.len() {
    return -1;
  }
  return d.kinds[node];
}

/// Element tag name ("" for text nodes, the synthetic root or bad indices).
pub fn saml_xml_node_name(d: &XmlDoc, node: Int) -> Str {
  if node < 0 || node >= d.names.len() {
    return "";
  }
  let v: Str = d.names[node];
  return v;
}

/// Local name of an element (text after the first ':'), "" for bad indices.
pub fn saml_xml_node_local(d: &XmlDoc, node: Int) -> Str {
  if node < 0 || node >= d.names.len() {
    return "";
  }
  let v: Str = d.names[node];
  return _local_name_of(v);
}

/// Parent node index (-1 for the synthetic root and bad indices).
pub fn saml_xml_node_parent(d: &XmlDoc, node: Int) -> Int {
  if node < 0 || node >= d.parents.len() {
    return -1;
  }
  return d.parents[node];
}

/// Element depth below the synthetic root (root = 1); -1 when out of range.
pub fn saml_xml_node_depth(d: &XmlDoc, node: Int) -> Int {
  if node < 0 || node >= d.parents.len() {
    return -1;
  }
  var depth = 0;
  var cur = node;
  var guard = 0;
  while cur > 0 && guard <= _SAML_MAX_DEPTH {
    depth = depth + 1;
    let p: Int = d.parents[cur];
    cur = p;
    guard = guard + 1;
  }
  return depth;
}

/// Concatenation of a node's direct text children, in document order.
pub fn saml_xml_text(d: &XmlDoc, node: Int) -> Str {
  var out = Vec[UInt8].new();
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 1 {
      if d.parents[i] == node {
        let tv: Str = d.texts[i];
        builder.sb_push_str(&mut out, tv);
      }
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Number of direct element children of a node.
pub fn saml_xml_child_count(d: &XmlDoc, node: Int) -> Int {
  var count = 0;
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 && d.parents[i] == node {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Direct element child by zero-based index; -1 when out of range.
pub fn saml_xml_child(d: &XmlDoc, node: Int, index: Int) -> Int {
  if index < 0 {
    return -1;
  }
  var seen = 0;
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 && d.parents[i] == node {
      if seen == index {
        return i;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return -1;
}

/// First direct element child whose local name equals `local`; -1 when none.
pub fn saml_xml_child_by_name(d: &XmlDoc, node: Int, local: Str) -> Int {
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 && d.parents[i] == node {
      let nm: Str = d.names[i];
      let ln = _local_name_of(nm);
      if _streq(ln, local) {
        return i;
      }
    }
    i = i + 1;
  }
  return -1;
}

// Count direct element children with the given local name.
fn _count_children_named(d: &XmlDoc, node: Int, local: Str) -> Int {
  var count = 0;
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 && d.parents[i] == node {
      let nm: Str = d.names[i];
      let ln = _local_name_of(nm);
      if _streq(ln, local) {
        count = count + 1;
      }
    }
    i = i + 1;
  }
  return count;
}

// Direct element child with the given local name at position k (0-based).
fn _child_named_at(d: &XmlDoc, node: Int, local: Str, k: Int) -> Int {
  if k < 0 {
    return -1;
  }
  var seen = 0;
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 && d.parents[i] == node {
      let nm: Str = d.names[i];
      let ln = _local_name_of(nm);
      if _streq(ln, local) {
        if seen == k {
          return i;
        }
        seen = seen + 1;
      }
    }
    i = i + 1;
  }
  return -1;
}

// True when cand is a strict descendant of anc.
fn _is_descendant(d: &XmlDoc, cand: Int, anc: Int) -> Bool {
  if cand == anc {
    return false;
  }
  var cur: Int = d.parents[cand];
  var guard = 0;
  while cur > 0 && guard <= _SAML_MAX_NODES {
    if cur == anc {
      return true;
    }
    let p: Int = d.parents[cur];
    cur = p;
    guard = guard + 1;
  }
  return false;
}

/// First descendant element (document order, self excluded) with the given
/// local name; -1 when none.
/// Params: d - the doc; node - subtree root; local - the local name.
/// Error case: none. Complexity: O(nodes*depth).
pub fn saml_xml_descendant_by_name(d: &XmlDoc, node: Int, local: Str) -> Int {
  var i = 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 && i != node {
      let nm: Str = d.names[i];
      let ln = _local_name_of(nm);
      if _streq(ln, local) {
        if _is_descendant(d, i, node) {
          return i;
        }
      }
    }
    i = i + 1;
  }
  return -1;
}

/// Number of attributes attached to a node.
pub fn saml_xml_attr_count(d: &XmlDoc, node: Int) -> Int {
  var count = 0;
  var i = 0;
  while i < d.attr_owners.len() {
    if d.attr_owners[i] == node {
      count = count + 1;
    }
    i = i + 1;
  }
  return count;
}

/// Attribute name by zero-based position on a node ("" when out of range).
pub fn saml_xml_attr_name_at(d: &XmlDoc, node: Int, index: Int) -> Str {
  var seen = 0;
  var i = 0;
  while i < d.attr_owners.len() {
    if d.attr_owners[i] == node {
      if seen == index {
        let v: Str = d.attr_names[i];
        return v;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return "";
}

/// Attribute value by zero-based position on a node ("" when out of range).
pub fn saml_xml_attr_value_at(d: &XmlDoc, node: Int, index: Int) -> Str {
  var seen = 0;
  var i = 0;
  while i < d.attr_owners.len() {
    if d.attr_owners[i] == node {
      if seen == index {
        let v: Str = d.attr_values[i];
        return v;
      }
      seen = seen + 1;
    }
    i = i + 1;
  }
  return "";
}

/// First attribute value named `name` on `node`.
/// Params: d - doc; node - element index; name - exact attribute name.
/// Returns: Ok(value) on a hit.
/// Error case: Err("saml: attribute not found: <name>") and
/// Err("saml: node index out of range"). Complexity: O(attributes).
pub fn saml_xml_attr(d: &XmlDoc, node: Int, name: Str) -> Result[Str, Str] {
  if node < 0 || node >= d.kinds.len() {
    return _err_str("saml: node index out of range");
  }
  var i = 0;
  while i < d.attr_owners.len() {
    if d.attr_owners[i] == node {
      let an: Str = d.attr_names[i];
      if _streq(an, name) {
        let av: Str = d.attr_values[i];
        return _ok_str(av);
      }
    }
    i = i + 1;
  }
  return _err_str("saml: attribute not found: " + name);
}

/// First attribute value named `name`, or `dflt` when absent.
pub fn saml_xml_attr_or(d: &XmlDoc, node: Int, name: Str, dflt: Str) -> Str {
  let r = saml_xml_attr(d, node, name);
  if !r.is_ok {
    return dflt;
  }
  let v: Str = r.value;
  return v;
}

/// Offset of the first source byte of node (its '<' for elements).
pub fn saml_xml_node_open(d: &XmlDoc, node: Int) -> Int {
  if node < 0 || node >= d.opens.len() {
    return -1;
  }
  return d.opens[node];
}

/// Offset just past the last source byte of node.
pub fn saml_xml_node_close(d: &XmlDoc, node: Int) -> Int {
  if node < 0 || node >= d.closes.len() {
    return -1;
  }
  return d.closes[node];
}

/// Raw source bytes of node, [open, close) into the document text.
/// Params: d - doc; node - node index.
/// Returns: a fresh Vec; empty for bad indices or unclosed spans.
/// Error case: none. Complexity: O(span).
pub fn saml_xml_node_raw_bytes(d: &XmlDoc, node: Int) -> Vec[UInt8] {
  if node < 0 || node >= d.opens.len() {
    return Vec[UInt8].new();
  }
  let a: Int = d.opens[node];
  let b: Int = d.closes[node];
  if a < 0 || b <= a || b > d.src.len() {
    return Vec[UInt8].new();
  }
  return _copy_span(&d.src, a, b);
}

// Append s to out escaping the five XML metacharacters.
fn _xml_escape_into(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    let b = (string.byte_at(s, i) as Int) & 0xFF;
    if b == _SAML_AMP {
      builder.sb_push_str(out, "&amp;");
    } elif b == _SAML_LT {
      builder.sb_push_str(out, "&lt;");
    } elif b == _SAML_GT {
      builder.sb_push_str(out, "&gt;");
    } elif b == _SAML_DQUOTE {
      builder.sb_push_str(out, "&quot;");
    } elif b == _SAML_SQUOTE {
      builder.sb_push_str(out, "&apos;");
    } else {
      out.push(string.byte_at(s, i));
    }
    i = i + 1;
  }
}

/// Escape the five XML metacharacters as named entities.
/// Params: s - text. Returns: s with & < > " ' escaped as entities.
/// Error case: none. Complexity: O(s.len()).
pub fn saml_xml_escape(s: Str) -> Str {
  var out = Vec[UInt8].new();
  _xml_escape_into(&mut out, s);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Base64 (in-package, standard alphabet with padding)
// --------------------------------------------------

// Standard base64 alphabet.
const _B64_ALPHABET: Str = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

// "`m` at offset `off`" (shared by the error catalogs).
fn _at(m: Str, off: Int) -> Str {
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, m);
  builder.sb_push_str(&mut out, " at offset ");
  builder.sb_push_int(&mut out, off);
  return builder.sb_to_str(&out);
}

// True for base64 whitespace: space, TAB, CR, LF.
fn _b64_ws(c: Int) -> Bool {
  if c == _SAML_SPACE || c == _SAML_TAB {
    return true;
  }
  if c == _SAML_CR || c == _SAML_LF {
    return true;
  }
  return false;
}

// Sextet value of a base64 data character, -1 for anything else.
fn _b64_val(c: Int) -> Int {
  if c >= 65 && c <= 90 {
    return c - 65;
  }
  if c >= 97 && c <= 122 {
    return c - 97 + 26;
  }
  if c >= 48 && c <= 57 {
    return c - 48 + 52;
  }
  if c == 43 {
    return 62;
  }
  if c == 47 {
    return 63;
  }
  return -1;
}

/// Encode bytes as standard base64 with '=' padding.
/// Params: data - raw bytes. Returns: the base64 text ("" for empty input).
/// Error case: none. Complexity: O(n).
pub fn saml_base64_encode(data: &Vec[UInt8]) -> Str {
  var out = Vec[UInt8].new();
  let n = data.len();
  var i = 0;
  while i + 3 <= n {
    let b0: Int = (data[i] as Int) & 0xFF;
    let b1: Int = (data[i + 1] as Int) & 0xFF;
    let b2: Int = (data[i + 2] as Int) & 0xFF;
    out.push(string.byte_at(_B64_ALPHABET, b0 / 4));
    out.push(string.byte_at(_B64_ALPHABET, (b0 % 4) * 16 + b1 / 16));
    out.push(string.byte_at(_B64_ALPHABET, (b1 % 16) * 4 + b2 / 64));
    out.push(string.byte_at(_B64_ALPHABET, b2 % 64));
    i = i + 3;
  }
  let rem = n - i;
  if rem == 1 {
    let c0: Int = (data[i] as Int) & 0xFF;
    out.push(string.byte_at(_B64_ALPHABET, c0 / 4));
    out.push(string.byte_at(_B64_ALPHABET, (c0 % 4) * 16));
    out.push(61 as UInt8);
    out.push(61 as UInt8);
  } elif rem == 2 {
    let d0: Int = (data[i] as Int) & 0xFF;
    let d1: Int = (data[i + 1] as Int) & 0xFF;
    out.push(string.byte_at(_B64_ALPHABET, d0 / 4));
    out.push(string.byte_at(_B64_ALPHABET, (d0 % 4) * 16 + d1 / 16));
    out.push(string.byte_at(_B64_ALPHABET, (d1 % 16) * 4));
    out.push(61 as UInt8);
  }
  return builder.sb_to_str(&out);
}

/// Decode standard base64 (optional '=' padding, whitespace ignored).
/// Params: s - the base64 text (may contain spaces, TAB, CR, LF).
/// Returns: Ok(bytes) on success; unpadded input is accepted when the number
/// of significant characters is 0, 2 or 3 modulo 4.
/// Error case: Err("saml: base64 ... at offset N") for an invalid character,
/// an invalid length (1 modulo 4), misplaced padding, or non-canonical
/// trailing bits.
/// Complexity: O(s.len()).
pub fn saml_base64_decode(s: Str) -> Result[Vec[UInt8], Str] {
  let n = s.len();
  var chars = Vec[Int].new();
  var offs = Vec[Int].new();
  var i = 0;
  while i < n {
    let c = (string.byte_at(s, i) as Int) & 0xFF;
    if !_b64_ws(c) {
      chars.push(c);
      offs.push(i);
    }
    i = i + 1;
  }
  let m = chars.len();
  if m == 0 {
    return _ok_bytes(Vec[UInt8].new());
  }
  let r = m % 4;
  if r == 1 {
    let off0: Int = offs[m - 1];
    return _err_bytes(_at("saml: base64 invalid length", off0));
  }
  var pad = 0;
  var first_pad = -1;
  var j = 0;
  while j < m {
    let c: Int = chars[j];
    let off: Int = offs[j];
    if c == 61 {
      if j + 2 < m {
        return _err_bytes(_at("saml: base64 misplaced padding", off));
      }
      if first_pad < 0 {
        first_pad = j;
      }
      pad = pad + 1;
    } elif _b64_val(c) < 0 {
      return _err_bytes(_at("saml: base64 invalid character", off));
    }
    j = j + 1;
  }
  if pad > 0 && first_pad != m - pad {
    let offr: Int = offs[first_pad];
    return _err_bytes(_at("saml: base64 misplaced padding", offr));
  }
  if pad > 0 && r != 0 {
    let offp: Int = offs[m - 1];
    return _err_bytes(_at("saml: base64 misplaced padding", offp));
  }
  let data_len = m - pad;
  var out = Vec[UInt8].new();
  var k = 0;
  while k + 4 <= data_len {
    let v0: Int = _b64_val(chars[k]);
    let v1: Int = _b64_val(chars[k + 1]);
    let v2: Int = _b64_val(chars[k + 2]);
    let v3: Int = _b64_val(chars[k + 3]);
    out.push((v0 * 4 + v1 / 16) as UInt8);
    out.push(((v1 % 16) * 16 + v2 / 4) as UInt8);
    out.push(((v2 % 4) * 64 + v3) as UInt8);
    k = k + 4;
  }
  let tail = data_len - k;
  if tail == 2 {
    let w0: Int = _b64_val(chars[k]);
    let w1: Int = _b64_val(chars[k + 1]);
    if w1 % 16 != 0 {
      let offt: Int = offs[k + 1];
      return _err_bytes(_at("saml: base64 non-canonical trailing bits", offt));
    }
    out.push((w0 * 4 + w1 / 16) as UInt8);
  } elif tail == 3 {
    let x0: Int = _b64_val(chars[k]);
    let x1: Int = _b64_val(chars[k + 1]);
    let x2: Int = _b64_val(chars[k + 2]);
    if x2 % 4 != 0 {
      let offt2: Int = offs[k + 2];
      return _err_bytes(_at("saml: base64 non-canonical trailing bits", offt2));
    }
    out.push((x0 * 4 + x1 / 16) as UInt8);
    out.push(((x1 % 16) * 16 + x2 / 4) as UInt8);
  } elif tail != 0 {
    let offl: Int = offs[m - 1];
    return _err_bytes(_at("saml: base64 invalid length", offl));
  }
  return _ok_bytes(out);
}

/// Base64-encode the UTF-8 bytes of a SAML message (HTTP-POST binding).
/// Params: xml - the message text. Returns: the base64 payload.
/// Error case: none. Complexity: O(xml.len()).
pub fn saml_post_binding_encode(xml: Str) -> Str {
  let data = _str_bytes(xml);
  return saml_base64_encode(&data);
}

/// Decode a base64 SAML POST payload back to message text.
/// Params: payload - the base64 payload (whitespace allowed).
/// Returns: Ok(xml) when the decoded bytes are NUL-free.
/// Error case: the saml_base64_decode catalog, or Err("saml: post binding
/// payload contains NUL") because a decoded 0x00 cannot live in a Str.
/// Complexity: O(payload.len()).
pub fn saml_post_binding_decode(payload: Str) -> Result[Str, Str] {
  let dr = saml_base64_decode(payload);
  if !dr.is_ok {
    return _err_str(dr.error);
  }
  let bytes: Vec[UInt8] = dr.value;
  var i = 0;
  while i < bytes.len() {
    if ((bytes[i] as Int) & 0xFF) == 0 {
      return _err_str("saml: post binding payload contains NUL");
    }
    i = i + 1;
  }
  return _ok_str(builder.sb_to_str(&bytes));
}

// --------------------------------------------------
//  SHA-256 (in-package, FIPS 180-4)
// --------------------------------------------------

// 32-bit rotate right; x is masked to 32 bits, n is 1..31.
fn _rotr32(x: Int, n: Int) -> Int {
  let a = x & 0xFFFFFFFF;
  return ((a >> n) | ((a << (32 - n)) & 0xFFFFFFFF)) & 0xFFFFFFFF;
}

// SHA-256 round constants.
fn _sha256_k() -> Vec[Int] {
  var k = Vec[Int].new();
  k.push(0x428a2f98);
  k.push(0x71374491);
  k.push(0xb5c0fbcf);
  k.push(0xe9b5dba5);
  k.push(0x3956c25b);
  k.push(0x59f111f1);
  k.push(0x923f82a4);
  k.push(0xab1c5ed5);
  k.push(0xd807aa98);
  k.push(0x12835b01);
  k.push(0x243185be);
  k.push(0x550c7dc3);
  k.push(0x72be5d74);
  k.push(0x80deb1fe);
  k.push(0x9bdc06a7);
  k.push(0xc19bf174);
  k.push(0xe49b69c1);
  k.push(0xefbe4786);
  k.push(0x0fc19dc6);
  k.push(0x240ca1cc);
  k.push(0x2de92c6f);
  k.push(0x4a7484aa);
  k.push(0x5cb0a9dc);
  k.push(0x76f988da);
  k.push(0x983e5152);
  k.push(0xa831c66d);
  k.push(0xb00327c8);
  k.push(0xbf597fc7);
  k.push(0xc6e00bf3);
  k.push(0xd5a79147);
  k.push(0x06ca6351);
  k.push(0x14292967);
  k.push(0x27b70a85);
  k.push(0x2e1b2138);
  k.push(0x4d2c6dfc);
  k.push(0x53380d13);
  k.push(0x650a7354);
  k.push(0x766a0abb);
  k.push(0x81c2c92e);
  k.push(0x92722c85);
  k.push(0xa2bfe8a1);
  k.push(0xa81a664b);
  k.push(0xc24b8b70);
  k.push(0xc76c51a3);
  k.push(0xd192e819);
  k.push(0xd6990624);
  k.push(0xf40e3585);
  k.push(0x106aa070);
  k.push(0x19a4c116);
  k.push(0x1e376c08);
  k.push(0x2748774c);
  k.push(0x34b0bcb5);
  k.push(0x391c0cb3);
  k.push(0x4ed8aa4a);
  k.push(0x5b9cca4f);
  k.push(0x682e6ff3);
  k.push(0x748f82ee);
  k.push(0x78a5636f);
  k.push(0x84c87814);
  k.push(0x8cc70208);
  k.push(0x90befffa);
  k.push(0xa4506ceb);
  k.push(0xbef9a3f7);
  k.push(0xc67178f2);
  return k;
}

// SHA-256 initial hash state.
fn _sha256_iv() -> Vec[Int] {
  var h = Vec[Int].new();
  h.push(0x6a09e667);
  h.push(0xbb67ae85);
  h.push(0x3c6ef372);
  h.push(0xa54ff53a);
  h.push(0x510e527f);
  h.push(0x9b05688c);
  h.push(0x1f83d9ab);
  h.push(0x5be0cd19);
  return h;
}

// 16 big-endian words of the 64-byte block starting at off.
fn _sha256_words(data: &Vec[UInt8], off: Int) -> Vec[Int] {
  var w = Vec[Int].new();
  var i = 0;
  while i < 16 {
    let b0: Int = (data[off + i * 4] as Int) & 0xFF;
    let b1: Int = (data[off + i * 4 + 1] as Int) & 0xFF;
    let b2: Int = (data[off + i * 4 + 2] as Int) & 0xFF;
    let b3: Int = (data[off + i * 4 + 3] as Int) & 0xFF;
    w.push((b0 * 16777216 + b1 * 65536 + b2 * 256 + b3) & 0xFFFFFFFF);
    i = i + 1;
  }
  return w;
}

// One SHA-256 compression round over h with one 16-word block.
fn _sha256_block(h: &mut Vec[Int], block: &Vec[Int]) {
  var w = Vec[Int].new();
  var i = 0;
  while i < 16 {
    let v: Int = block[i];
    w.push(v);
    i = i + 1;
  }
  while i < 64 {
    let w15: Int = w[i - 15];
    let w2: Int = w[i - 2];
    let s0 = (_rotr32(w15, 7) ^ _rotr32(w15, 18) ^ (w15 >> 3)) & 0xFFFFFFFF;
    let s1 = (_rotr32(w2, 17) ^ _rotr32(w2, 19) ^ (w2 >> 10)) & 0xFFFFFFFF;
    let wv: Int = w[i - 16];
    let w7: Int = w[i - 7];
    w.push((wv + s0 + w7 + s1) & 0xFFFFFFFF);
    i = i + 1;
  }
  let k = _sha256_k();
  let h0: Int = h[0];
  let h1: Int = h[1];
  let h2: Int = h[2];
  let h3: Int = h[3];
  let h4: Int = h[4];
  let h5: Int = h[5];
  let h6: Int = h[6];
  let h7: Int = h[7];
  var va = h0;
  var vb = h1;
  var vc = h2;
  var vd = h3;
  var ve = h4;
  var vf = h5;
  var vg = h6;
  var vh = h7;
  var t = 0;
  while t < 64 {
    let big_s1 = _rotr32(ve, 6) ^ _rotr32(ve, 11) ^ _rotr32(ve, 25);
    let ch = (ve & vf) ^ ((ve ^ 0xFFFFFFFF) & vg);
    let kw: Int = k[t];
    let ww: Int = w[t];
    let temp1 = (vh + big_s1 + ch + kw + ww) & 0xFFFFFFFF;
    let big_s0 = _rotr32(va, 2) ^ _rotr32(va, 13) ^ _rotr32(va, 22);
    let maj = (va & vb) ^ (va & vc) ^ (vb & vc);
    let temp2 = (big_s0 + maj) & 0xFFFFFFFF;
    vh = vg;
    vg = vf;
    vf = ve;
    ve = (vd + temp1) & 0xFFFFFFFF;
    vd = vc;
    vc = vb;
    vb = va;
    va = (temp1 + temp2) & 0xFFFFFFFF;
    t = t + 1;
  }
  h[0] = (h0 + va) & 0xFFFFFFFF;
  h[1] = (h1 + vb) & 0xFFFFFFFF;
  h[2] = (h2 + vc) & 0xFFFFFFFF;
  h[3] = (h3 + vd) & 0xFFFFFFFF;
  h[4] = (h4 + ve) & 0xFFFFFFFF;
  h[5] = (h5 + vf) & 0xFFFFFFFF;
  h[6] = (h6 + vg) & 0xFFFFFFFF;
  h[7] = (h7 + vh) & 0xFFFFFFFF;
}

/// SHA-256 digest (32 bytes) of raw bytes.
/// Params: data - the message. Returns: the 32-byte digest.
/// Error case: none. Complexity: O(n).
pub fn saml_sha256(data: &Vec[UInt8]) -> Vec[UInt8] {
  var h = _sha256_iv();
  let n = data.len();
  var pos = 0;
  while pos + 64 <= n {
    let blk = _sha256_words(data, pos);
    _sha256_block(&mut h, &blk);
    pos = pos + 64;
  }
  var tail = Vec[UInt8].new();
  var i = pos;
  while i < n {
    tail.push(data[i]);
    i = i + 1;
  }
  tail.push(128 as UInt8);
  while tail.len() % 64 != 56 {
    tail.push(0 as UInt8);
  }
  let bits = n * 8;
  var s = 56;
  while s >= 0 {
    tail.push(((bits >> s) & 0xFF) as UInt8);
    s = s - 8;
  }
  var p2 = 0;
  while p2 < tail.len() {
    let blk2 = _sha256_words(&tail, p2);
    _sha256_block(&mut h, &blk2);
    p2 = p2 + 64;
  }
  var out = Vec[UInt8].new();
  var j = 0;
  while j < 8 {
    let word: Int = h[j];
    out.push(((word >> 24) & 0xFF) as UInt8);
    out.push(((word >> 16) & 0xFF) as UInt8);
    out.push(((word >> 8) & 0xFF) as UInt8);
    out.push((word & 0xFF) as UInt8);
    j = j + 1;
  }
  return out;
}

/// SHA-256 digest of a Str's UTF-8 bytes.
/// Params: s - the text. Returns: the 32-byte digest.
/// Error case: none. Complexity: O(s.len()).
pub fn saml_sha256_str(s: Str) -> Vec[UInt8] {
  let data = _str_bytes(s);
  return saml_sha256(&data);
}

/// Lowercase hex of the SHA-256 digest of raw bytes (64 characters).
pub fn saml_sha256_hex(data: &Vec[UInt8]) -> Str {
  let digest = saml_sha256(data);
  let alpha = "0123456789abcdef";
  var out = Vec[UInt8].new();
  var i = 0;
  while i < digest.len() {
    let b: Int = (digest[i] as Int) & 0xFF;
    out.push(string.byte_at(alpha, b / 16));
    out.push(string.byte_at(alpha, b % 16));
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  xs:dateTime (Int epoch seconds, UTC)
// --------------------------------------------------

// True for a leap year.
fn _is_leap_year(y: Int) -> Bool {
  if y % 4 != 0 {
    return false;
  }
  if y % 100 != 0 {
    return true;
  }
  return y % 400 == 0;
}

// Days in month m (1..12) of year y.
fn _days_in_month(y: Int, m: Int) -> Int {
  if m == 2 {
    if _is_leap_year(y) {
      return 29;
    }
    return 28;
  }
  if m == 4 || m == 6 || m == 9 || m == 11 {
    return 30;
  }
  return 31;
}

// Days since 1970-01-01 for a proleptic Gregorian date (Hinnant).
fn _days_from_civil(y: Int, m: Int, d: Int) -> Int {
  var yy = y;
  if m <= 2 {
    yy = y - 1;
  }
  let era = yy / 400;
  let yoe = yy - era * 400;
  var mp = m - 3;
  if mp < 0 {
    mp = m + 9;
  }
  let doy = (153 * mp + 2) / 5 + d - 1;
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + doe - 719468;
}

// Digit value of the byte at i of s, -1 when not a digit.
fn _digit_at(s: Str, i: Int) -> Int {
  if i < 0 || i >= s.len() {
    return -1;
  }
  let c = (string.byte_at(s, i) as Int) & 0xFF;
  if c >= 48 && c <= 57 {
    return c - 48;
  }
  return -1;
}

// Two-digit decimal value at i, -1 when either byte is not a digit.
fn _two_digits(s: Str, i: Int) -> Int {
  let a = _digit_at(s, i);
  let b = _digit_at(s, i + 1);
  if a < 0 || b < 0 {
    return -1;
  }
  return a * 10 + b;
}

/// Parse an xs:dateTime to epoch seconds (UTC, integer).
/// Params: s - "YYYY-MM-DDThh:mm:ss[.fff](Z|(+|-)hh:mm)"; at least 20 bytes;
/// fractional seconds are accepted and truncated.
/// Returns: Ok(epoch seconds).
/// Error case: Err("saml: invalid datetime") for any malformed field, a
/// missing/invalid timezone, year outside 1..9999, hour above 23, minute or
/// second above 59, offset above 14:00, or a leap-second value of 60.
/// Complexity: O(s.len()).
pub fn saml_parse_datetime(s: Str) -> Result[Int, Str] {
  let n = s.len();
  if n < 20 {
    return _err_int("saml: invalid datetime");
  }
  let y1 = _digit_at(s, 0);
  let y2 = _digit_at(s, 1);
  let y3 = _digit_at(s, 2);
  let y4 = _digit_at(s, 3);
  if y1 < 0 || y2 < 0 || y3 < 0 || y4 < 0 {
    return _err_int("saml: invalid datetime");
  }
  let year = y1 * 1000 + y2 * 100 + y3 * 10 + y4;
  if year < 1 {
    return _err_int("saml: invalid datetime");
  }
  if ((string.byte_at(s, 4) as Int) & 0xFF) != _SAML_DASH {
    return _err_int("saml: invalid datetime");
  }
  let month = _two_digits(s, 5);
  if month < 1 || month > 12 {
    return _err_int("saml: invalid datetime");
  }
  if ((string.byte_at(s, 7) as Int) & 0xFF) != _SAML_DASH {
    return _err_int("saml: invalid datetime");
  }
  let day = _two_digits(s, 8);
  if day < 1 || day > _days_in_month(year, month) {
    return _err_int("saml: invalid datetime");
  }
  let sep = (string.byte_at(s, 10) as Int) & 0xFF;
  if sep != 84 && sep != 116 {
    return _err_int("saml: invalid datetime");
  }
  let hour = _two_digits(s, 11);
  if hour < 0 || hour > 23 {
    return _err_int("saml: invalid datetime");
  }
  if ((string.byte_at(s, 13) as Int) & 0xFF) != _SAML_COLON {
    return _err_int("saml: invalid datetime");
  }
  let minute = _two_digits(s, 14);
  if minute < 0 || minute > 59 {
    return _err_int("saml: invalid datetime");
  }
  if ((string.byte_at(s, 16) as Int) & 0xFF) != _SAML_COLON {
    return _err_int("saml: invalid datetime");
  }
  let second = _two_digits(s, 17);
  if second < 0 || second > 59 {
    return _err_int("saml: invalid datetime");
  }
  var i = 19;
  if i < n && ((string.byte_at(s, i) as Int) & 0xFF) == 46 {
    i = i + 1;
    var fdigits = 0;
    while i < n && _digit_at(s, i) >= 0 {
      fdigits = fdigits + 1;
      i = i + 1;
    }
    if fdigits == 0 {
      return _err_int("saml: invalid datetime");
    }
  }
  if i >= n {
    return _err_int("saml: invalid datetime");
  }
  let zc = (string.byte_at(s, i) as Int) & 0xFF;
  var offset = 0;
  if zc == 90 || zc == 122 {
    i = i + 1;
  } elif zc == 43 || zc == 45 {
    if i + 6 != n {
      return _err_int("saml: invalid datetime");
    }
    if ((string.byte_at(s, i + 3) as Int) & 0xFF) != _SAML_COLON {
      return _err_int("saml: invalid datetime");
    }
    let oh = _two_digits(s, i + 1);
    let om = _two_digits(s, i + 4);
    if oh < 0 || om < 0 || oh > 14 || om > 59 {
      return _err_int("saml: invalid datetime");
    }
    offset = oh * 3600 + om * 60;
    if zc == 45 {
      offset = 0 - offset;
    }
    i = i + 6;
  } else {
    return _err_int("saml: invalid datetime");
  }
  if i != n {
    return _err_int("saml: invalid datetime");
  }
  let days = _days_from_civil(year, month, day);
  let secs = days * 86400 + hour * 3600 + minute * 60 + second - offset;
  return _ok_int(secs);
}

// Append v as exactly width zero-padded decimal digits.
fn _push_pad(out: &mut Vec[UInt8], v: Int, width: Int) {
  var div = 1;
  var k = 1;
  while k < width {
    div = div * 10;
    k = k + 1;
  }
  var d = div;
  while d >= 1 {
    let digit = (v / d) % 10;
    out.push((48 + digit) as UInt8);
    d = d / 10;
  }
}

/// Format epoch seconds as "YYYY-MM-DDThh:mm:ssZ" (UTC).
/// Params: epoch - seconds since 1970-01-01T00:00:00Z (negative allowed).
/// Returns: the xs:dateTime text; years outside 0..9999 are rendered modulo
/// their four digits (documented limitation).
/// Error case: none. Complexity: O(1).
pub fn saml_format_datetime(epoch: Int) -> Str {
  var days = epoch / 86400;
  var rem = epoch % 86400;
  if rem < 0 {
    rem = rem + 86400;
    days = days - 1;
  }
  let hh = rem / 3600;
  let mi = (rem % 3600) / 60;
  let ss = rem % 60;
  var z = days + 719468;
  var era = z / 146097;
  var doe = z - era * 146097;
  if doe < 0 {
    doe = doe + 146097;
    era = era - 1;
  }
  let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  let y = yoe + era * 400;
  let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  let mp = (5 * doy + 2) / 153;
  let d = doy - (153 * mp + 2) / 5 + 1;
  var m = mp + 3;
  var yr = y;
  if mp >= 10 {
    m = mp - 9;
    yr = y + 1;
  }
  var out = Vec[UInt8].new();
  _push_pad(&mut out, yr, 4);
  out.push(_SAML_DASH as UInt8);
  _push_pad(&mut out, m, 2);
  out.push(_SAML_DASH as UInt8);
  _push_pad(&mut out, d, 2);
  out.push(84 as UInt8);
  _push_pad(&mut out, hh, 2);
  out.push(_SAML_COLON as UInt8);
  _push_pad(&mut out, mi, 2);
  out.push(_SAML_COLON as UInt8);
  _push_pad(&mut out, ss, 2);
  out.push(90 as UInt8);
  return builder.sb_to_str(&out);
}

// --------------------------------------------------
//  Empty model constructors
// --------------------------------------------------

// Empty document (synthetic root only).
fn _doc_empty() -> XmlDoc {
  var d = XmlDoc{
    kinds: Vec[Int].new();
    names: Vec[Str].new();
    texts: Vec[Str].new();
    parents: Vec[Int].new();
    opens: Vec[Int].new();
    closes: Vec[Int].new();
    attr_names: Vec[Str].new();
    attr_values: Vec[Str].new();
    attr_owners: Vec[Int].new();
    src: Vec[UInt8].new();
  };
  d.kinds.push(0);
  d.names.push("");
  d.texts.push("");
  d.parents.push(-1);
  d.opens.push(0);
  d.closes.push(0);
  return d;
}

// Copy a document into a fresh value (explicit typed copies).
fn _copy_doc(d: &XmlDoc) -> XmlDoc {
  let kinds: Vec[Int] = d.kinds;
  let names: Vec[Str] = d.names;
  let texts: Vec[Str] = d.texts;
  let parents: Vec[Int] = d.parents;
  let opens: Vec[Int] = d.opens;
  let closes: Vec[Int] = d.closes;
  let an: Vec[Str] = d.attr_names;
  let av: Vec[Str] = d.attr_values;
  let ao: Vec[Int] = d.attr_owners;
  let src: Vec[UInt8] = d.src;
  return XmlDoc{
    kinds: kinds;
    names: names;
    texts: texts;
    parents: parents;
    opens: opens;
    closes: closes;
    attr_names: an;
    attr_values: av;
    attr_owners: ao;
    src: src;
  };
}

fn _conditions_empty() -> SamlConditions {
  return SamlConditions{
    has_not_before: false;
    not_before_text: "";
    not_before_epoch: 0;
    has_not_on_or_after: false;
    not_on_or_after_text: "";
    not_on_or_after_epoch: 0;
    has_audience_restriction: false;
    audiences: Vec[Str].new();
  };
}

fn _subject_empty() -> SamlSubject {
  return SamlSubject{
    has_subject: false;
    has_name_id: false;
    name_id: "";
    name_id_format: "";
    confirmation_count: 0;
    recipient: "";
    in_response_to: "";
  };
}

fn _attributes_empty() -> SamlAttributes {
  return SamlAttributes{
    names: Vec[Str].new();
    name_formats: Vec[Str].new();
    friendly_names: Vec[Str].new();
    value_counts: Vec[Int].new();
    values: Vec[Str].new();
    value_owners: Vec[Int].new();
  };
}

fn _assertion_empty() -> SamlAssertion {
  return SamlAssertion{
    doc: _doc_empty();
    node: -1;
    id: "";
    version: "";
    issue_instant: "";
    has_issuer: false;
    issuer: "";
    subject: _subject_empty();
    conditions: _conditions_empty();
    has_authn_statement: false;
    authn_instant: "";
    session_index: "";
    attributes: _attributes_empty();
    has_signature: false;
    signature_node: -1;
  };
}

fn _response_empty() -> SamlResponse {
  return SamlResponse{
    doc: _doc_empty();
    node: -1;
    id: "";
    version: "";
    issue_instant: "";
    destination: "";
    in_response_to: "";
    has_issuer: false;
    issuer: "";
    has_status: false;
    status_code: "";
    status_message: "";
    assertion_count: 0;
    encrypted_assertion_count: 0;
    has_signature: false;
    signature_node: -1;
  };
}

fn _req_empty() -> SamlAuthnRequest {
  return SamlAuthnRequest{
    doc: _doc_empty();
    node: -1;
    id: "";
    version: "";
    issue_instant: "";
    destination: "";
    acs_url: "";
    has_issuer: false;
    issuer: "";
    has_signature: false;
    signature_node: -1;
  };
}

fn _meta_empty() -> SamlIdpMetadata {
  return SamlIdpMetadata{
    doc: _doc_empty();
    node: -1;
    entity_id: "";
    has_entity_id: false;
    want_authn_requests_signed: false;
    protocol_support: "";
    sso_count: 0;
    sso_bindings: Vec[Str].new();
    sso_locations: Vec[Str].new();
    cert_count: 0;
    certs: Vec[Str].new();
    has_signature: false;
    signature_node: -1;
  };
}

fn _signature_empty() -> SamlSignature {
  return SamlSignature{
    doc: _doc_empty();
    node: -1;
    has_signed_info: false;
    canonicalization_algorithm: "";
    signature_algorithm: "";
    reference_count: 0;
    ref_uri: Vec[Str].new();
    ref_digest_algorithm: Vec[Str].new();
    ref_digest_value: Vec[Str].new();
    has_signature_value: false;
    signature_value: "";
  };
}

// --------------------------------------------------
//  Assertion parsing
// --------------------------------------------------

// Next element sibling of a node in the flat model.
fn _next_sibling_node(d: &XmlDoc, node: Int) -> Int {
  let parent: Int = d.parents[node];
  var i = node + 1;
  while i < d.kinds.len() {
    if d.kinds[i] == 0 && d.parents[i] == parent {
      return i;
    }
    i = i + 1;
  }
  return -1;
}

// Extract one AttributeStatement subtree into attrs.
fn _collect_attributes(d: &XmlDoc, stmt: Int, attrs: &mut SamlAttributes) -> Result[Str, Str] {
  var an = saml_xml_child(d, stmt, 0);
  while an >= 0 {
    let anl: Str = d.names[an];
    let ln = _local_name_of(anl);
    if _streq(ln, "Attribute") {
      let nm = saml_xml_attr_or(d, an, "Name", "");
      if nm.len() == 0 {
        return _err_str("saml: Attribute missing Name");
      }
      let fmt = saml_xml_attr_or(d, an, "NameFormat", "");
      let friendly = saml_xml_attr_or(d, an, "FriendlyName", "");
      attrs.names.push(nm);
      attrs.name_formats.push(fmt);
      attrs.friendly_names.push(friendly);
      let owner_index = attrs.names.len() - 1;
      var vc = 0;
      var idx = 0;
      while idx < saml_xml_child_count(d, an) {
        let vn = saml_xml_child(d, an, idx);
        if vn >= 0 {
          let vnl: Str = d.names[vn];
          let vln = _local_name_of(vnl);
          if _streq(vln, "AttributeValue") {
            attrs.values.push(saml_xml_text(d, vn));
            attrs.value_owners.push(owner_index);
            vc = vc + 1;
          }
        }
        idx = idx + 1;
      }
      attrs.value_counts.push(vc);
    }
    an = _next_sibling_node(d, an);
  }
  return _ok_str("");
}

// Extract Conditions (timestamps and audience restrictions) into cond.
fn _collect_conditions(d: &XmlDoc, cnode: Int, cond: &mut SamlConditions) -> Result[Str, Str] {
  let nbr = saml_xml_attr(d, cnode, "NotBefore");
  if nbr.is_ok {
    let nbs: Str = nbr.value;
    let nbp = saml_parse_datetime(nbs);
    if !nbp.is_ok {
      return _err_str("saml: invalid NotBefore");
    }
    cond.has_not_before = true;
    cond.not_before_text = nbs;
    cond.not_before_epoch = nbp.value;
  }
  let nar = saml_xml_attr(d, cnode, "NotOnOrAfter");
  if nar.is_ok {
    let nas: Str = nar.value;
    let nap = saml_parse_datetime(nas);
    if !nap.is_ok {
      return _err_str("saml: invalid NotOnOrAfter");
    }
    cond.has_not_on_or_after = true;
    cond.not_on_or_after_text = nas;
    cond.not_on_or_after_epoch = nap.value;
  }
  var ar = saml_xml_child(d, cnode, 0);
  while ar >= 0 {
    let arl: Str = d.names[ar];
    let aln = _local_name_of(arl);
    if _streq(aln, "AudienceRestriction") {
      cond.has_audience_restriction = true;
      var au = saml_xml_child(d, ar, 0);
      while au >= 0 {
        let aul: Str = d.names[au];
        let auln = _local_name_of(aul);
        if _streq(auln, "Audience") {
          cond.audiences.push(saml_xml_text(d, au));
        }
        au = _next_sibling_node(d, au);
      }
    }
    ar = _next_sibling_node(d, ar);
  }
  return _ok_str("");
}

/// Parse one Assertion element from a parsed document.
/// Params: d - the document; node - the Assertion element index.
/// Returns: Ok(assertion) with the flattened structure.
/// Error case: Err("saml: ...") for a non-Assertion node, a missing/unsupported
/// Version, a missing/empty ID, a missing or malformed IssueInstant, a
/// malformed Condition timestamp, a malformed AuthnInstant, or an Attribute
/// without a Name.
/// Complexity: O(nodes + text bytes).
pub fn saml_assertion_from_doc(d: &XmlDoc, node: Int) -> Result[SamlAssertion, Str] {
  if node < 0 || node >= d.kinds.len() {
    return _err_assertion("saml: node index out of range");
  }
  let ln: Str = d.names[node];
  let local = _local_name_of(ln);
  if !_streq(local, "Assertion") {
    return _err_assertion("saml: not an Assertion element");
  }
  var a = _assertion_empty();
  a.doc = _copy_doc(d);
  a.node = node;
  let vr = saml_xml_attr(d, node, "Version");
  if !vr.is_ok {
    return _err_assertion("saml: missing Version");
  }
  let v: Str = vr.value;
  if !_streq(v, SAML_VERSION) {
    return _err_assertion("saml: unsupported Version");
  }
  a.version = v;
  let idr = saml_xml_attr(d, node, "ID");
  if !idr.is_ok {
    return _err_assertion("saml: missing ID");
  }
  let idv: Str = idr.value;
  if idv.len() == 0 {
    return _err_assertion("saml: empty ID");
  }
  a.id = idv;
  let iir = saml_xml_attr(d, node, "IssueInstant");
  if !iir.is_ok {
    return _err_assertion("saml: missing IssueInstant");
  }
  let iiv: Str = iir.value;
  let iip = saml_parse_datetime(iiv);
  if !iip.is_ok {
    return _err_assertion("saml: invalid IssueInstant");
  }
  a.issue_instant = iiv;
  let inode = saml_xml_child_by_name(d, node, "Issuer");
  if inode >= 0 {
    a.has_issuer = true;
    a.issuer = saml_xml_text(d, inode);
  }
  let snode = saml_xml_child_by_name(d, node, "Subject");
  if snode >= 0 {
    var sub = _subject_empty();
    sub.has_subject = true;
    let nid = saml_xml_child_by_name(d, snode, "NameID");
    if nid >= 0 {
      sub.has_name_id = true;
      sub.name_id = saml_xml_text(d, nid);
      sub.name_id_format = saml_xml_attr_or(d, nid, "Format", "");
    }
    sub.confirmation_count = _count_children_named(d, snode, "SubjectConfirmation");
    let sc = saml_xml_child_by_name(d, snode, "SubjectConfirmation");
    if sc >= 0 {
      let scd = saml_xml_child_by_name(d, sc, "SubjectConfirmationData");
      if scd >= 0 {
        sub.recipient = saml_xml_attr_or(d, scd, "Recipient", "");
        sub.in_response_to = saml_xml_attr_or(d, scd, "InResponseTo", "");
      }
    }
    a.subject = sub;
  }
  let cnode = saml_xml_child_by_name(d, node, "Conditions");
  if cnode >= 0 {
    var cond = _conditions_empty();
    let cr = _collect_conditions(d, cnode, &mut cond);
    if !cr.is_ok {
      return _err_assertion(cr.error);
    }
    a.conditions = cond;
  }
  let asn = saml_xml_child_by_name(d, node, "AuthnStatement");
  if asn >= 0 {
    a.has_authn_statement = true;
    a.session_index = saml_xml_attr_or(d, asn, "SessionIndex", "");
    let air = saml_xml_attr(d, asn, "AuthnInstant");
    if air.is_ok {
      let ais: Str = air.value;
      let aip = saml_parse_datetime(ais);
      if !aip.is_ok {
        return _err_assertion("saml: invalid AuthnInstant");
      }
      a.authn_instant = ais;
    }
  }
  var attrs = _attributes_empty();
  var stmt = saml_xml_child(d, node, 0);
  while stmt >= 0 {
    let sl: Str = d.names[stmt];
    let sln = _local_name_of(sl);
    if _streq(sln, "AttributeStatement") {
      let ar2 = _collect_attributes(d, stmt, &mut attrs);
      if !ar2.is_ok {
        return _err_assertion(ar2.error);
      }
    }
    stmt = _next_sibling_node(d, stmt);
  }
  a.attributes = attrs;
  let sg = saml_xml_child_by_name(d, node, "Signature");
  if sg >= 0 {
    a.has_signature = true;
    a.signature_node = sg;
  }
  return _ok_assertion(a);
}

/// Parse a standalone Assertion XML document.
/// Params: text - the whole assertion document.
/// Returns: Ok(assertion) when the root element is an Assertion.
/// Error case: the saml_xml_parse catalog plus saml_assertion_from_doc.
/// Complexity: O(text.len() + nodes).
pub fn saml_assertion_parse(text: Str) -> Result[SamlAssertion, Str] {
  let dr = saml_xml_parse(text);
  if !dr.is_ok {
    return _err_assertion(dr.error);
  }
  let doc: XmlDoc = dr.value;
  let root = saml_xml_root(&doc);
  if root < 0 {
    return _err_assertion("saml: no root element");
  }
  return saml_assertion_from_doc(&doc, root);
}

/// True when the assertion carries a Signature child.
pub fn saml_assertion_has_signature(a: &SamlAssertion) -> Bool {
  return a.has_signature;
}

/// Parse the assertion's Signature child.
/// Params: a - the parsed assertion.
/// Returns: Ok(signature) when present and structurally sound.
/// Error case: Err("saml: assertion has no signature") or the
/// saml_dsig_parse catalog.
/// Complexity: O(nodes).
pub fn saml_assertion_signature(a: &SamlAssertion) -> Result[SamlSignature, Str] {
  if !a.has_signature {
    return _err_signature("saml: assertion has no signature");
  }
  let node: Int = a.signature_node;
  return saml_dsig_parse(&a.doc, node);
}

/// Validate an assertion's Conditions against a caller-supplied UTC clock.
/// Params: a - the assertion; now - epoch seconds (UTC).
/// Returns: Ok("") when inside [NotBefore, NotOnOrAfter).
/// Error case: Err("saml: assertion not yet valid") or
/// Err("saml: assertion expired").
/// Complexity: O(1).
pub fn saml_assertion_valid_at(a: &SamlAssertion, now: Int) -> Result[Str, Str] {
  return saml_assertion_valid_skew(a, now, 0);
}

/// Validate an assertion's Conditions with a symmetric clock-skew allowance.
/// Params: a - the assertion; now - epoch seconds (UTC); skew - non-negative
/// tolerance seconds accepted on both boundaries.
/// Returns: Ok("") when now is inside the skewed window (or the window is
/// absent).
/// Error case: Err("saml: negative clock skew"), Err("saml: assertion not yet
/// valid"), Err("saml: assertion expired").
/// Complexity: O(1).
pub fn saml_assertion_valid_skew(a: &SamlAssertion, now: Int, skew: Int) -> Result[Str, Str] {
  if skew < 0 {
    return _err_str("saml: negative clock skew");
  }
  let cond: SamlConditions = a.conditions;
  if cond.has_not_before {
    let nb: Int = cond.not_before_epoch;
    if now + skew < nb {
      return _err_str("saml: assertion not yet valid");
    }
  }
  if cond.has_not_on_or_after {
    let na: Int = cond.not_on_or_after_epoch;
    if now - skew >= na {
      return _err_str("saml: assertion expired");
    }
  }
  return _ok_str("");
}

/// True when the assertion's AudienceRestriction is absent or lists
/// `audience` (exact byte comparison).
pub fn saml_assertion_audience_matches(a: &SamlAssertion, audience: Str) -> Bool {
  let cond: SamlConditions = a.conditions;
  if !cond.has_audience_restriction {
    return true;
  }
  var i = 0;
  while i < cond.audiences.len() {
    let x: Str = cond.audiences[i];
    if _streq(x, audience) {
      return true;
    }
    i = i + 1;
  }
  return false;
}

/// Number of values of the first attribute named `name` (0 when absent).
pub fn saml_assertion_attribute_value_count(a: &SamlAssertion, name: Str) -> Int {
  let attrs: SamlAttributes = a.attributes;
  var i = 0;
  while i < attrs.names.len() {
    let nm: Str = attrs.names[i];
    if _streq(nm, name) {
      let c: Int = attrs.value_counts[i];
      return c;
    }
    i = i + 1;
  }
  return 0;
}

/// Values of the first attribute named `name`, in document order.
/// Params: a - the assertion; name - the attribute name.
/// Returns: a fresh Vec of values ("" values included); empty when absent.
/// Error case: none. Complexity: O(values).
pub fn saml_assertion_attribute_values(a: &SamlAssertion, name: Str) -> Vec[Str] {
  var out = Vec[Str].new();
  let attrs: SamlAttributes = a.attributes;
  var owner = -1;
  var i = 0;
  while i < attrs.names.len() {
    let nm: Str = attrs.names[i];
    if _streq(nm, name) {
      if owner < 0 {
        owner = i;
      }
    }
    i = i + 1;
  }
  if owner < 0 {
    return out;
  }
  var j = 0;
  while j < attrs.values.len() && j < attrs.value_owners.len() {
    let vo: Int = attrs.value_owners[j];
    if vo == owner {
      let v: Str = attrs.values[j];
      out.push(v);
    }
    j = j + 1;
  }
  return out;
}

// --------------------------------------------------
//  Response parsing
// --------------------------------------------------

/// True when `code` is the registered Success status code.
pub fn saml_status_is_success(code: Str) -> Bool {
  return _streq(code, SAML_STATUS_SUCCESS);
}

/// True when `code` starts with the SAML status-code URN prefix and has a
/// non-empty local part.
pub fn saml_status_is_valid(code: Str) -> Bool {
  if code.len() <= SAML_STATUS_PREFIX.len() {
    return false;
  }
  let head = string.str_slice(code, 0, SAML_STATUS_PREFIX.len());
  return _streq(head, SAML_STATUS_PREFIX);
}

/// Parse one Response element from a parsed document.
/// Params: d - the document; node - the Response element index.
/// Returns: Ok(response) with the envelope fields and assertion counts.
/// Error case: Err("saml: ...") for a non-Response node, a missing/unsupported
/// Version, a missing/empty ID, a missing or malformed IssueInstant, or a
/// Status without a StatusCode.
/// Complexity: O(nodes + text bytes).
pub fn saml_response_from_doc(d: &XmlDoc, node: Int) -> Result[SamlResponse, Str] {
  if node < 0 || node >= d.kinds.len() {
    return _err_response("saml: node index out of range");
  }
  let ln: Str = d.names[node];
  let local = _local_name_of(ln);
  if !_streq(local, "Response") {
    return _err_response("saml: not a Response element");
  }
  var r = _response_empty();
  r.doc = _copy_doc(d);
  r.node = node;
  let vr = saml_xml_attr(d, node, "Version");
  if !vr.is_ok {
    return _err_response("saml: missing Version");
  }
  let v: Str = vr.value;
  if !_streq(v, SAML_VERSION) {
    return _err_response("saml: unsupported Version");
  }
  r.version = v;
  let idr = saml_xml_attr(d, node, "ID");
  if !idr.is_ok {
    return _err_response("saml: missing ID");
  }
  let idv: Str = idr.value;
  if idv.len() == 0 {
    return _err_response("saml: empty ID");
  }
  r.id = idv;
  let iir = saml_xml_attr(d, node, "IssueInstant");
  if !iir.is_ok {
    return _err_response("saml: missing IssueInstant");
  }
  let iiv: Str = iir.value;
  let iip = saml_parse_datetime(iiv);
  if !iip.is_ok {
    return _err_response("saml: invalid IssueInstant");
  }
  r.issue_instant = iiv;
  r.destination = saml_xml_attr_or(d, node, "Destination", "");
  r.in_response_to = saml_xml_attr_or(d, node, "InResponseTo", "");
  let inode = saml_xml_child_by_name(d, node, "Issuer");
  if inode >= 0 {
    r.has_issuer = true;
    r.issuer = saml_xml_text(d, inode);
  }
  let snode = saml_xml_child_by_name(d, node, "Status");
  if snode >= 0 {
    r.has_status = true;
    let sc = saml_xml_child_by_name(d, snode, "StatusCode");
    if sc < 0 {
      return _err_response("saml: Status without StatusCode");
    }
    let sr = saml_xml_attr(d, sc, "Value");
    if !sr.is_ok {
      return _err_response("saml: StatusCode without Value");
    }
    let scv: Str = sr.value;
    r.status_code = scv;
    let sm = saml_xml_child_by_name(d, snode, "StatusMessage");
    if sm >= 0 {
      r.status_message = saml_xml_text(d, sm);
    }
  }
  r.assertion_count = _count_children_named(d, node, "Assertion");
  r.encrypted_assertion_count = _count_children_named(d, node, "EncryptedAssertion");
  let sg = saml_xml_child_by_name(d, node, "Signature");
  if sg >= 0 {
    r.has_signature = true;
    r.signature_node = sg;
  }
  return _ok_response(r);
}

/// Parse a standalone SAML Response XML document.
/// Params: text - the whole response document.
/// Returns: Ok(response) when the root element is a Response.
/// Error case: the saml_xml_parse catalog plus saml_response_from_doc.
/// Complexity: O(text.len() + nodes).
pub fn saml_response_parse(text: Str) -> Result[SamlResponse, Str] {
  let dr = saml_xml_parse(text);
  if !dr.is_ok {
    return _err_response(dr.error);
  }
  let doc: XmlDoc = dr.value;
  let root = saml_xml_root(&doc);
  if root < 0 {
    return _err_response("saml: no root element");
  }
  return saml_response_from_doc(&doc, root);
}

/// Number of direct Assertion children of the response.
pub fn saml_response_assertion_count(r: &SamlResponse) -> Int {
  return r.assertion_count;
}

/// Node index of the k-th direct Assertion child; -1 when out of range.
pub fn saml_response_assertion_node(r: &SamlResponse, k: Int) -> Int {
  return _child_named_at(&r.doc, r.node, "Assertion", k);
}

/// Parse the k-th direct Assertion child of the response.
/// Params: r - the parsed response; k - zero-based assertion position.
/// Returns: Ok(assertion).
/// Error case: Err("saml: assertion index out of range") or the
/// saml_assertion_from_doc catalog.
/// Complexity: O(nodes + text bytes).
pub fn saml_response_assertion(r: &SamlResponse, k: Int) -> Result[SamlAssertion, Str] {
  let node = _child_named_at(&r.doc, r.node, "Assertion", k);
  if node < 0 {
    return _err_assertion("saml: assertion index out of range");
  }
  return saml_assertion_from_doc(&r.doc, node);
}

/// True when the response Status is the registered Success code.
pub fn saml_response_is_success(r: &SamlResponse) -> Bool {
  if !r.has_status {
    return false;
  }
  return saml_status_is_success(r.status_code);
}

// --------------------------------------------------
//  IdP metadata parsing
// --------------------------------------------------

// Strip base64 whitespace from s.
fn _normalize_b64(s: Str) -> Str {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    let c = (string.byte_at(s, i) as Int) & 0xFF;
    if !_b64_ws(c) {
      out.push(string.byte_at(s, i));
    }
    i = i + 1;
  }
  return builder.sb_to_str(&out);
}

/// Parse IdP EntityDescriptor metadata.
/// Params: text - the whole EntityDescriptor document.
/// Returns: Ok(metadata) with entityID, IDPSSODescriptor fields, flattened
/// SingleSignOnService pairs and normalized X509Certificate base64 strings.
/// Error case: the saml_xml_parse catalog, Err("saml: not an EntityDescriptor
/// element"), Err("saml: missing entityID"), Err("saml: missing
/// IDPSSODescriptor"), Err("saml: IDPSSODescriptor without
/// SingleSignOnService"), or a SingleSignOnService/KeyDescriptor without the
/// required attributes (Binding/Location).
/// Complexity: O(text.len() + nodes).
pub fn saml_idp_metadata_parse(text: Str) -> Result[SamlIdpMetadata, Str] {
  let dr = saml_xml_parse(text);
  if !dr.is_ok {
    return _err_meta(dr.error);
  }
  let doc: XmlDoc = dr.value;
  let root = saml_xml_root(&doc);
  if root < 0 {
    return _err_meta("saml: no root element");
  }
  let ln: Str = doc.names[root];
  let local = _local_name_of(ln);
  if !_streq(local, "EntityDescriptor") {
    return _err_meta("saml: not an EntityDescriptor element");
  }
  var m = _meta_empty();
  m.doc = _copy_doc(&doc);
  m.node = root;
  let idr = saml_xml_attr(&doc, root, "entityID");
  if !idr.is_ok {
    return _err_meta("saml: missing entityID");
  }
  let idv: Str = idr.value;
  if idv.len() == 0 {
    return _err_meta("saml: empty entityID");
  }
  m.has_entity_id = true;
  m.entity_id = idv;
  let idp = saml_xml_child_by_name(&doc, root, "IDPSSODescriptor");
  if idp < 0 {
    return _err_meta("saml: missing IDPSSODescriptor");
  }
  m.protocol_support = saml_xml_attr_or(&doc, idp, "protocolSupportEnumeration", "");
  let wa = saml_xml_attr_or(&doc, idp, "WantAuthnRequestsSigned", "");
  if _streq(wa, "true") || _streq(wa, "1") {
    m.want_authn_requests_signed = true;
  }
  var sso = saml_xml_child(&doc, idp, 0);
  while sso >= 0 {
    let sl: Str = doc.names[sso];
    let sln = _local_name_of(sl);
    if _streq(sln, "SingleSignOnService") {
      let br = saml_xml_attr(&doc, sso, "Binding");
      if !br.is_ok {
        return _err_meta("saml: SingleSignOnService without Binding");
      }
      let lr = saml_xml_attr(&doc, sso, "Location");
      if !lr.is_ok {
        return _err_meta("saml: SingleSignOnService without Location");
      }
      let bv: Str = br.value;
      let lv: Str = lr.value;
      if bv.len() == 0 {
        return _err_meta("saml: empty SingleSignOnService Binding");
      }
      if lv.len() == 0 {
        return _err_meta("saml: empty SingleSignOnService Location");
      }
      m.sso_bindings.push(bv);
      m.sso_locations.push(lv);
      m.sso_count = m.sso_count + 1;
    }
    sso = _next_sibling_node(&doc, sso);
  }
  if m.sso_count == 0 {
    return _err_meta("saml: IDPSSODescriptor without SingleSignOnService");
  }
  var i = 1;
  while i < doc.kinds.len() {
    if doc.kinds[i] == 0 {
      let nl: Str = doc.names[i];
      let nln = _local_name_of(nl);
      if _streq(nln, "X509Certificate") {
        let cert = _normalize_b64(saml_xml_text(&doc, i));
        if cert.len() > 0 {
          m.certs.push(cert);
          m.cert_count = m.cert_count + 1;
        }
      }
    }
    i = i + 1;
  }
  let sg = saml_xml_child_by_name(&doc, root, "Signature");
  if sg >= 0 {
    m.has_signature = true;
    m.signature_node = sg;
  }
  return _ok_meta(m);
}

/// Number of SingleSignOnService entries.
pub fn saml_metadata_sso_count(m: &SamlIdpMetadata) -> Int {
  return m.sso_count;
}

/// Binding of SSO entry i ("" when out of range).
pub fn saml_metadata_sso_binding_at(m: &SamlIdpMetadata, i: Int) -> Str {
  if i < 0 || i >= m.sso_bindings.len() {
    return "";
  }
  let v: Str = m.sso_bindings[i];
  return v;
}

/// Location of SSO entry i ("" when out of range).
pub fn saml_metadata_sso_location_at(m: &SamlIdpMetadata, i: Int) -> Str {
  if i < 0 || i >= m.sso_locations.len() {
    return "";
  }
  let v: Str = m.sso_locations[i];
  return v;
}

/// Location of the first SSO entry with the given binding ("" when none).
pub fn saml_metadata_sso_location_for_binding(m: &SamlIdpMetadata, binding: Str) -> Str {
  var i = 0;
  while i < m.sso_bindings.len() && i < m.sso_locations.len() {
    let b: Str = m.sso_bindings[i];
    if _streq(b, binding) {
      let l: Str = m.sso_locations[i];
      return l;
    }
    i = i + 1;
  }
  return "";
}

/// Normalized base64 of X509Certificate i ("" when out of range).
pub fn saml_metadata_certificate_at(m: &SamlIdpMetadata, i: Int) -> Str {
  if i < 0 || i >= m.certs.len() {
    return "";
  }
  let v: Str = m.certs[i];
  return v;
}

// --------------------------------------------------
//  AuthnRequest (SP-initiated SSO, POST binding)
// --------------------------------------------------

/// Build a SAML AuthnRequest document (deterministic attribute order).
/// Params: id - a non-empty request ID; issuer - the SP entityID; destination
/// - the IdP SSO URL ("" to omit); acs_url - the AssertionConsumerService URL
/// ("" to omit); issue_instant - an xs:dateTime (validated).
/// Returns: Ok(xml) with the samlp:AuthnRequest envelope and a saml:Issuer
/// child; text and attribute values are XML-escaped.
/// Error case: Err("saml: empty AuthnRequest ID"), Err("saml: empty issuer"),
/// Err("saml: invalid IssueInstant"), Err("saml: empty Destination") when a
/// non-empty Destination is malformed (whitespace) or Err("saml: empty
/// AssertionConsumerServiceURL") for a whitespace-only ACS URL.
/// Complexity: O(total input).
pub fn saml_authn_request_build(id: Str, issuer: Str, destination: Str,
                               acs_url: Str, issue_instant: Str) -> Result[Str, Str] {
  if id.len() == 0 {
    return _err_str("saml: empty AuthnRequest ID");
  }
  if issuer.len() == 0 {
    return _err_str("saml: empty issuer");
  }
  let iip = saml_parse_datetime(issue_instant);
  if !iip.is_ok {
    return _err_str("saml: invalid IssueInstant");
  }
  var out = Vec[UInt8].new();
  builder.sb_push_str(&mut out, "<samlp:AuthnRequest xmlns:samlp=\"urn:oasis:names:tc:SAML:2.0:protocol\" xmlns:saml=\"urn:oasis:names:tc:SAML:2.0:assertion\" ID=\"");
  _xml_escape_into(&mut out, id);
  builder.sb_push_str(&mut out, "\" Version=\"2.0\" IssueInstant=\"");
  _xml_escape_into(&mut out, issue_instant);
  builder.sb_push_str(&mut out, "\"");
  if destination.len() > 0 {
    builder.sb_push_str(&mut out, " Destination=\"");
    _xml_escape_into(&mut out, destination);
    builder.sb_push_str(&mut out, "\"");
  }
  if acs_url.len() > 0 {
    builder.sb_push_str(&mut out, " AssertionConsumerServiceURL=\"");
    _xml_escape_into(&mut out, acs_url);
    builder.sb_push_str(&mut out, "\"");
  }
  builder.sb_push_str(&mut out, "><saml:Issuer>");
  _xml_escape_into(&mut out, issuer);
  builder.sb_push_str(&mut out, "</saml:Issuer></samlp:AuthnRequest>");
  return _ok_str(builder.sb_to_str(&out));
}

/// Parse a SAML AuthnRequest document.
/// Params: text - the whole request document.
/// Returns: Ok(request) when the root element is an AuthnRequest.
/// Error case: the saml_xml_parse catalog, Err("saml: not an AuthnRequest
/// element"), a missing/unsupported Version, a missing/empty ID, or a missing
/// or malformed IssueInstant.
/// Complexity: O(text.len() + nodes).
pub fn saml_authn_request_parse(text: Str) -> Result[SamlAuthnRequest, Str] {
  let dr = saml_xml_parse(text);
  if !dr.is_ok {
    return _err_req(dr.error);
  }
  let doc: XmlDoc = dr.value;
  let root = saml_xml_root(&doc);
  if root < 0 {
    return _err_req("saml: no root element");
  }
  return saml_authn_request_from_doc(&doc, root);
}

/// Parse one AuthnRequest element from a parsed document.
/// Params: d - the document; node - the AuthnRequest element index.
/// Returns: Ok(request) with ID, Version, IssueInstant, Destination,
/// AssertionConsumerServiceURL and Issuer.
/// Error case: Err("saml: ...") for a non-AuthnRequest node, a
/// missing/unsupported Version, a missing/empty ID, or a missing or malformed
/// IssueInstant.
/// Complexity: O(nodes + text bytes).
pub fn saml_authn_request_from_doc(d: &XmlDoc, node: Int) -> Result[SamlAuthnRequest, Str] {
  if node < 0 || node >= d.kinds.len() {
    return _err_req("saml: node index out of range");
  }
  let ln: Str = d.names[node];
  let local = _local_name_of(ln);
  if !_streq(local, "AuthnRequest") {
    return _err_req("saml: not an AuthnRequest element");
  }
  var q = _req_empty();
  q.doc = _copy_doc(d);
  q.node = node;
  let vr = saml_xml_attr(d, node, "Version");
  if !vr.is_ok {
    return _err_req("saml: missing Version");
  }
  let v: Str = vr.value;
  if !_streq(v, SAML_VERSION) {
    return _err_req("saml: unsupported Version");
  }
  q.version = v;
  let idr = saml_xml_attr(d, node, "ID");
  if !idr.is_ok {
    return _err_req("saml: missing ID");
  }
  let idv: Str = idr.value;
  if idv.len() == 0 {
    return _err_req("saml: empty ID");
  }
  q.id = idv;
  let iir = saml_xml_attr(d, node, "IssueInstant");
  if !iir.is_ok {
    return _err_req("saml: missing IssueInstant");
  }
  let iiv: Str = iir.value;
  let iip = saml_parse_datetime(iiv);
  if !iip.is_ok {
    return _err_req("saml: invalid IssueInstant");
  }
  q.issue_instant = iiv;
  q.destination = saml_xml_attr_or(d, node, "Destination", "");
  q.acs_url = saml_xml_attr_or(d, node, "AssertionConsumerServiceURL", "");
  let inode = saml_xml_child_by_name(d, node, "Issuer");
  if inode >= 0 {
    q.has_issuer = true;
    q.issuer = saml_xml_text(d, inode);
  }
  let sg = saml_xml_child_by_name(d, node, "Signature");
  if sg >= 0 {
    q.has_signature = true;
    q.signature_node = sg;
  }
  return _ok_req(q);
}

// --------------------------------------------------
//  XML-DSig structural parsing and digest checks
// --------------------------------------------------

/// First Signature element in the subtree of `node` (self included), in
/// document order; -1 when none.
pub fn saml_dsig_find(d: &XmlDoc, node: Int) -> Int {
  if node < 0 || node >= d.kinds.len() {
    return -1;
  }
  let self_name: Str = d.names[node];
  let self_local = _local_name_of(self_name);
  if d.kinds[node] == 0 && _streq(self_local, "Signature") {
    return node;
  }
  return saml_xml_descendant_by_name(d, node, "Signature");
}

// Digest byte length of a digest algorithm URI, -1 when unknown.
fn _digest_len(alg: Str) -> Int {
  if _streq(alg, SAML_ALG_DIGEST_SHA256) {
    return 32;
  }
  if _streq(alg, SAML_ALG_DIGEST_SHA1) {
    return 20;
  }
  if _streq(alg, SAML_ALG_DIGEST_SHA512) {
    return 64;
  }
  return -1;
}

/// True when the digest algorithm URI is one of SHA-256, SHA-1, SHA-512.
pub fn saml_dsig_digest_algorithm_supported(alg: Str) -> Bool {
  return _digest_len(alg) >= 0;
}

/// Parse a Signature element structure.
/// Params: d - the document; node - the Signature element index.
/// Returns: Ok(signature) with SignedInfo algorithms, flattened References
/// (URI, DigestMethod, DigestValue) and SignatureValue.
/// Error case: Err("saml: ...") for a non-Signature node, a missing
/// SignedInfo/CanonicalizationMethod/SignatureMethod/Reference/SignatureValue,
/// an empty algorithm URI, a Reference without DigestMethod/DigestValue, or
/// an empty digest algorithm.
/// Complexity: O(nodes + text bytes).
pub fn saml_dsig_parse(d: &XmlDoc, node: Int) -> Result[SamlSignature, Str] {
  if node < 0 || node >= d.kinds.len() {
    return _err_signature("saml: node index out of range");
  }
  let ln: Str = d.names[node];
  let local = _local_name_of(ln);
  if !_streq(local, "Signature") {
    return _err_signature("saml: not a Signature element");
  }
  var s = _signature_empty();
  s.doc = _copy_doc(d);
  s.node = node;
  let si = saml_xml_child_by_name(d, node, "SignedInfo");
  if si < 0 {
    return _err_signature("saml: missing SignedInfo");
  }
  s.has_signed_info = true;
  let cm = saml_xml_child_by_name(d, si, "CanonicalizationMethod");
  if cm < 0 {
    return _err_signature("saml: missing CanonicalizationMethod");
  }
  let ca = saml_xml_attr_or(d, cm, "Algorithm", "");
  if ca.len() == 0 {
    return _err_signature("saml: empty CanonicalizationMethod Algorithm");
  }
  s.canonicalization_algorithm = ca;
  let sm = saml_xml_child_by_name(d, si, "SignatureMethod");
  if sm < 0 {
    return _err_signature("saml: missing SignatureMethod");
  }
  let sa = saml_xml_attr_or(d, sm, "Algorithm", "");
  if sa.len() == 0 {
    return _err_signature("saml: empty SignatureMethod Algorithm");
  }
  s.signature_algorithm = sa;
  var ri = saml_xml_child(d, si, 0);
  while ri >= 0 {
    let rl: Str = d.names[ri];
    let rln = _local_name_of(rl);
    if _streq(rln, "Reference") {
      let uri = saml_xml_attr_or(d, ri, "URI", "");
      let dm = saml_xml_child_by_name(d, ri, "DigestMethod");
      if dm < 0 {
        return _err_signature("saml: Reference without DigestMethod");
      }
      let da = saml_xml_attr_or(d, dm, "Algorithm", "");
      if da.len() == 0 {
        return _err_signature("saml: empty DigestMethod Algorithm");
      }
      let dv = saml_xml_child_by_name(d, ri, "DigestValue");
      if dv < 0 {
        return _err_signature("saml: Reference without DigestValue");
      }
      s.ref_uri.push(uri);
      s.ref_digest_algorithm.push(da);
      s.ref_digest_value.push(saml_xml_text(d, dv));
      s.reference_count = s.reference_count + 1;
    }
    ri = _next_sibling_node(d, ri);
  }
  if s.reference_count == 0 {
    return _err_signature("saml: no Reference");
  }
  let sv = saml_xml_child_by_name(d, node, "SignatureValue");
  if sv < 0 {
    return _err_signature("saml: missing SignatureValue");
  }
  s.has_signature_value = true;
  s.signature_value = saml_xml_text(d, sv);
  return _ok_signature(s);
}

/// Number of References in the signature.
pub fn saml_dsig_reference_count(s: &SamlSignature) -> Int {
  return s.ref_uri.len();
}

/// URI of Reference i ("" when out of range or absent).
pub fn saml_dsig_reference_uri(s: &SamlSignature, i: Int) -> Str {
  if i < 0 || i >= s.ref_uri.len() {
    return "";
  }
  let v: Str = s.ref_uri[i];
  return v;
}

/// Digest algorithm URI of Reference i ("" when out of range).
pub fn saml_dsig_reference_digest_algorithm(s: &SamlSignature, i: Int) -> Str {
  if i < 0 || i >= s.ref_digest_algorithm.len() {
    return "";
  }
  let v: Str = s.ref_digest_algorithm[i];
  return v;
}

/// DigestValue text of Reference i ("" when out of range).
pub fn saml_dsig_reference_digest_value(s: &SamlSignature, i: Int) -> Str {
  if i < 0 || i >= s.ref_digest_value.len() {
    return "";
  }
  let v: Str = s.ref_digest_value[i];
  return v;
}

// ID-ish attribute of a node (ID, Id or xml:id), "" when absent.
fn _id_attr_of(d: &XmlDoc, node: Int) -> Str {
  let r = saml_xml_attr(d, node, "ID");
  if r.is_ok {
    let v: Str = r.value;
    return v;
  }
  let r2 = saml_xml_attr(d, node, "Id");
  if r2.is_ok {
    let v2: Str = r2.value;
    return v2;
  }
  let r3 = saml_xml_attr(d, node, "xml:id");
  if r3.is_ok {
    let v3: Str = r3.value;
    return v3;
  }
  return "";
}

/// Resolve Reference i to a document node.
/// Params: d - the document; s - the parsed signature; i - reference index.
/// Returns: the node index for URI "" (whole document root), for "#id" when
/// an element carries ID/Id/xml:id == id and for an empty URI; -1 for an
/// external URI, a missing ID target, a bad index or a bad signature doc.
/// Error case: none. Complexity: O(nodes).
pub fn saml_dsig_reference_target(d: &XmlDoc, s: &SamlSignature, i: Int) -> Int {
  let target = saml_xml_root(d);
  if i < 0 || i >= s.ref_uri.len() {
    return -1;
  }
  let uri: Str = s.ref_uri[i];
  if uri.len() == 0 {
    return target;
  }
  if ((string.byte_at(uri, 0) as Int) & 0xFF) != _SAML_HASH {
    return -1;
  }
  var k = 1;
  while k < d.kinds.len() {
    if d.kinds[k] == 0 {
      let idv = _id_attr_of(d, k);
      if idv.len() > 0 {
        if _streq(uri, "#" + idv) {
          return k;
        }
      }
    }
    k = k + 1;
  }
  return -1;
}

/// True when Reference i resolves to a document node.
pub fn saml_dsig_reference_resolves(d: &XmlDoc, s: &SamlSignature, i: Int) -> Bool {
  return saml_dsig_reference_target(d, s, i) >= 0;
}

/// Decode the DigestValue of Reference i and check its length against its
/// DigestMethod algorithm.
/// Params: s - the signature; i - reference index.
/// Returns: Ok(bytes) with 20/32/64 bytes for SHA-1/SHA-256/SHA-512.
/// Error case: Err("saml: reference index out of range"), the base64 catalog,
/// Err("saml: unsupported digest algorithm") or Err("saml: digest value
/// length mismatch").
/// Complexity: O(base64 length).
pub fn saml_dsig_digest_bytes(s: &SamlSignature, i: Int) -> Result[Vec[UInt8], Str] {
  if i < 0 || i >= s.ref_digest_value.len() {
    return _err_bytes("saml: reference index out of range");
  }
  let dv: Str = s.ref_digest_value[i];
  let alg: Str = s.ref_digest_algorithm[i];
  let want = _digest_len(alg);
  if want < 0 {
    return _err_bytes("saml: unsupported digest algorithm");
  }
  let dr = saml_base64_decode(dv);
  if !dr.is_ok {
    return _err_bytes(dr.error);
  }
  let bytes: Vec[UInt8] = dr.value;
  if bytes.len() != want {
    return _err_bytes("saml: digest value length mismatch");
  }
  return _ok_bytes(bytes);
}

/// Decode the signature's SignatureValue (non-empty).
/// Params: s - the signature.
/// Returns: Ok(bytes) with the decoded signature octets.
/// Error case: the base64 catalog or Err("saml: empty signature value").
/// Complexity: O(base64 length).
pub fn saml_dsig_signature_value_bytes(s: &SamlSignature) -> Result[Vec[UInt8], Str] {
  if !s.has_signature_value {
    return _err_bytes("saml: missing SignatureValue");
  }
  let sv: Str = s.signature_value;
  let dr = saml_base64_decode(sv);
  if !dr.is_ok {
    return _err_bytes(dr.error);
  }
  let bytes: Vec[UInt8] = dr.value;
  if bytes.len() == 0 {
    return _err_bytes("saml: empty signature value");
  }
  return _ok_bytes(bytes);
}

/// Verify a base64 SHA-256 digest against caller-supplied octets.
/// Params: digest_b64 - the DigestValue text; octets - the exact octets the
/// digest was computed over (the caller owns canonicalization).
/// Returns: true when the digest decodes to 32 bytes and equals
/// SHA-256(octets); false otherwise.
/// Error case: none. Complexity: O(octets).
pub fn saml_dsig_verify_digest_sha256(digest_b64: Str, octets: &Vec[UInt8]) -> Bool {
  let dr = saml_base64_decode(digest_b64);
  if !dr.is_ok {
    return false;
  }
  let want: Vec[UInt8] = dr.value;
  if want.len() != 32 {
    return false;
  }
  let got = saml_sha256(octets);
  return _bytes_equal(&got, &want);
}

/// Verify Reference i's SHA-256 digest against caller-supplied octets.
/// Params: s - the signature; i - reference index; octets - the exact octets.
/// Returns: true when the reference uses SHA-256 and the digest matches.
/// Error case: none. Complexity: O(octets).
pub fn saml_dsig_verify_reference_sha256(s: &SamlSignature, i: Int, octets: &Vec[UInt8]) -> Bool {
  if i < 0 || i >= s.ref_digest_value.len() {
    return false;
  }
  let alg: Str = s.ref_digest_algorithm[i];
  if !_streq(alg, SAML_ALG_DIGEST_SHA256) {
    return false;
  }
  let dv: Str = s.ref_digest_value[i];
  return saml_dsig_verify_digest_sha256(dv, octets);
}

/// Verify Reference i's SHA-256 digest over the RAW bytes of the resolved
/// element (open tag through end tag).
/// Params: d - the document; s - the parsed signature; i - reference index.
/// Returns: true when the reference uses SHA-256, resolves to an element and
/// the digest matches SHA-256(raw element span).
/// NOTE: XML-DSig digests are defined over the canonicalized octets, not the
/// raw span. This check is valid when the raw span already equals the
/// CanonicalizationMethod output (no comments/PIs inside the element,
/// attributes in canonical order); otherwise use
/// saml_dsig_verify_reference_sha256 with caller-produced octets.
/// Error case: none. Complexity: O(span).
pub fn saml_dsig_verify_reference_raw_sha256(d: &XmlDoc, s: &SamlSignature, i: Int) -> Bool {
  if i < 0 || i >= s.ref_digest_algorithm.len() {
    return false;
  }
  let alg: Str = s.ref_digest_algorithm[i];
  if !_streq(alg, SAML_ALG_DIGEST_SHA256) {
    return false;
  }
  let target = saml_dsig_reference_target(d, s, i);
  if target < 0 {
    return false;
  }
  let raw = saml_xml_node_raw_bytes(d, target);
  if raw.len() == 0 {
    return false;
  }
  let dv: Str = s.ref_digest_value[i];
  return saml_dsig_verify_digest_sha256(dv, &raw);
}

/// Package version marker.
pub fn saml_version() -> Str {
  return "0.1.0";
}



