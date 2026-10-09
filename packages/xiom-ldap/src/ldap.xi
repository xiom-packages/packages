// XIOM -- xiom.ldap: LDAP (RFC 4511) BER message codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets) decoder for the LDAP protocol wire format
// plus a minimal encoder. The covered subset is RFC 4511 with implicit
// context tagging:
//
//   * BER: one-byte tags, definite short/long-form lengths (minimal long
//     form only; indefinite and overlong lengths are rejected), signed
//     minimal INTEGER, ENUMERATED, BOOLEAN (single content byte), OCTET
//     STRING and SEQUENCE/SET;
//   * LDAPMessage: SEQUENCE { INTEGER messageID, protocolOp, controls [0]
//     OPTIONAL }; the controls TLV is captured by offset/length but not
//     parsed;
//   * protocolOps: BindRequest 0x60 (simple 0x80 and SASL 0xA3), BindResponse
//     0x61, UnbindRequest 0x42, SearchRequest 0x63, SearchResultEntry 0x64,
//     SearchResultDone 0x65, ModifyRequest 0x66 / ModifyResponse 0x67,
//     AddRequest 0x68 / AddResponse 0x69, DelRequest 0x4A / DelResponse
//     0x6B, ModifyDNRequest 0x6C / ModifyDNResponse 0x6D, CompareRequest
//     0x6E / CompareResponse 0x6F, AbandonRequest 0x50, SearchResultReference
//     0x73 and ExtendedRequest 0x77 / ExtendedResponse 0x78, with the
//     LDAPResult fields resultCode, matchedDN, diagnosticMessage and the
//     optional referral;
//   * filters: decoded into a flat tree (parallel Vec fields, no Vec of
//     structs) with a depth cap;
//   * encoding: minimal BindRequest (simple) and SearchRequest (single
//     equality filter) that parse back byte-identically.
//
// Every malformed input is rejected with a stable Err(Str) that names the
// byte offset of the offending structure. See SPEC.md for the exact error
// catalog and the documented subset.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; no methods and no lambdas; no table-driven
//     dispatch;
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results directly inside other functions miscompiles);
//   * every byte read from a Vec[UInt8] is widened with
//     `(data[pos] as Int) & 0xFF` before it enters Int arithmetic, and the
//     context tags 0x80..0x8B / 0xA0..0xA9 are only ever compared as
//     widened Ints;
//   * Vec elements are read into typed locals before use; Str values from a
//     Vec[Str] are never compared with `==` (BUG 17 discipline);
//   * decoded LDAPString / LDAPDN values are validated as printable ASCII
//     (0x20..0x7E) before they become a Str, because a Str is a
//     NUL-terminated C string at the ABI; arbitrary octet values stay
//     Vec[UInt8], and encoder inputs are validated the same way;
//   * every parallel Vec in the flat filter/changetype models is pushed in
//     lockstep; mismatched lengths are treated as malformed input.

module xiom.ldap

use xiom.string.builder;

// --------------------------------------------------
//  Protocol constants
// --------------------------------------------------

/// Maximum number of ancestors a filter node may have. The root has depth 0,
/// so a filter whose deepest node has depth LDAP_MAX_FILTER_DEPTH is accepted
/// and one deeper is rejected.
pub const LDAP_MAX_FILTER_DEPTH: Int = 32;

/// Largest accepted messageID / abandon-request id.
pub const LDAP_MAX_MESSAGE_ID: Int = 2147483647;

/// BER tag of BOOLEAN (0x01).
pub const BER_TAG_BOOLEAN: Int = 1;

/// BER tag of INTEGER (0x02).
pub const BER_TAG_INTEGER: Int = 2;

/// BER tag of OCTET STRING (0x04).
pub const BER_TAG_OCTET_STRING: Int = 4;

/// BER tag of ENUMERATED (0x0A).
pub const BER_TAG_ENUMERATED: Int = 10;

/// BER tag of SEQUENCE (0x30).
pub const BER_TAG_SEQUENCE: Int = 48;

/// BER tag of SET (0x31).
pub const BER_TAG_SET: Int = 49;

/// Tag of the LDAPMessage controls field ([0], 0xA0, constructed).
pub const LDAP_TAG_CONTROLS: Int = 160;

/// Tag of the LDAPResult referral field ([3], 0xA3, constructed).
pub const LDAP_TAG_REFERRAL: Int = 163;

/// Tag of the BindResponse serverSaslCreds field ([7], 0x87, primitive).
pub const LDAP_TAG_SASL_CREDS: Int = 135;

/// Tag of the ExtendedResponse responseName field ([10], 0x8A).
pub const LDAP_TAG_RESPONSE_NAME: Int = 138;

/// Tag of the ExtendedResponse responseValue field ([11], 0x8B).
pub const LDAP_TAG_RESPONSE_VALUE: Int = 139;

/// Tag of the BindRequest simple authentication choice ([0], 0x80).
pub const LDAP_AUTH_SIMPLE: Int = 128;

/// Tag of the BindRequest SASL authentication choice ([3], 0xA3).
pub const LDAP_AUTH_SASL: Int = 163;

/// Tag of the ExtendedRequest requestName field ([0], 0x80).
pub const LDAP_EXT_REQUEST_NAME: Int = 128;

/// Tag of the ExtendedRequest requestValue field ([1], 0x81).
pub const LDAP_EXT_REQUEST_VALUE: Int = 129;

/// Tag of the ModifyDNRequest newSuperior field ([0], 0x80).
pub const LDAP_MODDN_NEW_SUPERIOR: Int = 128;

/// Tag of the Filter present choice ([7], 0x87, primitive).
pub const LDAP_FILTER_PRESENT: Int = 135;

/// Tag of the Filter and choice ([0], 0xA0, constructed).
pub const LDAP_FILTER_AND: Int = 160;

/// Tag of the Filter or choice ([1], 0xA1, constructed).
pub const LDAP_FILTER_OR: Int = 161;

/// Tag of the Filter not choice ([2], 0xA2, constructed).
pub const LDAP_FILTER_NOT: Int = 162;

/// Tag of the Filter equalityMatch choice ([3], 0xA3, constructed).
pub const LDAP_FILTER_EQUALITY: Int = 163;

/// Tag of the Filter substrings choice ([4], 0xA4, constructed).
pub const LDAP_FILTER_SUBSTRINGS: Int = 164;

/// Tag of the Filter greaterOrEqual choice ([5], 0xA5, constructed).
pub const LDAP_FILTER_GREATER_OR_EQUAL: Int = 165;

/// Tag of the Filter lessOrEqual choice ([6], 0xA6, constructed).
pub const LDAP_FILTER_LESS_OR_EQUAL: Int = 166;

/// Tag of the Filter approxMatch choice ([8], 0xA8, constructed).
pub const LDAP_FILTER_APPROX: Int = 168;

/// Tag of the Filter extensibleMatch choice ([9], 0xA9, constructed).
pub const LDAP_FILTER_EXTENSIBLE: Int = 169;

/// Tag of a substrings initial part ([0], 0x80, primitive).
pub const LDAP_SUBSTR_INITIAL: Int = 128;

/// Tag of a substrings any part ([1], 0x81, primitive).
pub const LDAP_SUBSTR_ANY: Int = 129;

/// Tag of a substrings final part ([2], 0x82, primitive).
pub const LDAP_SUBSTR_FINAL: Int = 130;

/// Tag of MatchingRuleAssertion matchingRule ([1], 0x81, primitive).
pub const LDAP_EXT_MATCHING_RULE: Int = 129;

/// Tag of MatchingRuleAssertion type ([2], 0x82, primitive).
pub const LDAP_EXT_TYPE: Int = 130;

/// Tag of MatchingRuleAssertion matchValue ([3], 0x83, primitive).
pub const LDAP_EXT_MATCH_VALUE: Int = 131;

/// Tag of MatchingRuleAssertion dnAttributes ([4], 0x84, primitive).
pub const LDAP_EXT_DN_ATTRIBUTES: Int = 132;

/// Flat filter node kind for and (tag 0xA0).
pub const LDAP_FILTER_KIND_AND: Int = 1;

/// Flat filter node kind for or (tag 0xA1).
pub const LDAP_FILTER_KIND_OR: Int = 2;

/// Flat filter node kind for not (tag 0xA2).
pub const LDAP_FILTER_KIND_NOT: Int = 3;

/// Flat filter node kind for equalityMatch (tag 0xA3).
pub const LDAP_FILTER_KIND_EQUALITY: Int = 4;

/// Flat filter node kind for substrings (tag 0xA4).
pub const LDAP_FILTER_KIND_SUBSTRINGS: Int = 5;

/// Flat filter node kind for greaterOrEqual (tag 0xA5).
pub const LDAP_FILTER_KIND_GREATER_OR_EQUAL: Int = 6;

/// Flat filter node kind for lessOrEqual (tag 0xA6).
pub const LDAP_FILTER_KIND_LESS_OR_EQUAL: Int = 7;

/// Flat filter node kind for present (tag 0x87).
pub const LDAP_FILTER_KIND_PRESENT: Int = 8;

/// Flat filter node kind for approxMatch (tag 0xA8).
pub const LDAP_FILTER_KIND_APPROX: Int = 9;

/// Flat filter node kind for extensibleMatch (tag 0xA9).
pub const LDAP_FILTER_KIND_EXTENSIBLE: Int = 10;

/// protocolOp tag of UnbindRequest (APPLICATION 2, primitive).
pub const LDAP_OP_UNBIND_REQUEST: Int = 66;

/// protocolOp tag of DelRequest (APPLICATION 10, primitive).
pub const LDAP_OP_DEL_REQUEST: Int = 74;

/// protocolOp tag of AbandonRequest (APPLICATION 16, primitive).
pub const LDAP_OP_ABANDON_REQUEST: Int = 80;

/// protocolOp tag of BindRequest (APPLICATION 0, constructed).
pub const LDAP_OP_BIND_REQUEST: Int = 96;

/// protocolOp tag of BindResponse (APPLICATION 1, constructed).
pub const LDAP_OP_BIND_RESPONSE: Int = 97;

/// protocolOp tag of SearchRequest (APPLICATION 3, constructed).
pub const LDAP_OP_SEARCH_REQUEST: Int = 99;

/// protocolOp tag of SearchResultEntry (APPLICATION 4, constructed).
pub const LDAP_OP_SEARCH_ENTRY: Int = 100;

/// protocolOp tag of SearchResultDone (APPLICATION 5, constructed).
pub const LDAP_OP_SEARCH_DONE: Int = 101;

/// protocolOp tag of ModifyRequest (APPLICATION 6, constructed).
pub const LDAP_OP_MODIFY_REQUEST: Int = 102;

/// protocolOp tag of ModifyResponse (APPLICATION 7, constructed).
pub const LDAP_OP_MODIFY_RESPONSE: Int = 103;

/// protocolOp tag of AddRequest (APPLICATION 8, constructed).
pub const LDAP_OP_ADD_REQUEST: Int = 104;

/// protocolOp tag of AddResponse (APPLICATION 9, constructed).
pub const LDAP_OP_ADD_RESPONSE: Int = 105;

/// protocolOp tag of DelResponse (APPLICATION 11, constructed).
pub const LDAP_OP_DEL_RESPONSE: Int = 107;

/// protocolOp tag of ModifyDNRequest (APPLICATION 12, constructed).
pub const LDAP_OP_MODIFY_DN_REQUEST: Int = 108;

/// protocolOp tag of ModifyDNResponse (APPLICATION 13, constructed).
pub const LDAP_OP_MODIFY_DN_RESPONSE: Int = 109;

/// protocolOp tag of CompareRequest (APPLICATION 14, constructed).
pub const LDAP_OP_COMPARE_REQUEST: Int = 110;

/// protocolOp tag of CompareResponse (APPLICATION 15, constructed).
pub const LDAP_OP_COMPARE_RESPONSE: Int = 111;

/// protocolOp tag of SearchResultReference (APPLICATION 19, constructed).
pub const LDAP_OP_SEARCH_REFERENCE: Int = 115;

/// protocolOp tag of ExtendedRequest (APPLICATION 23, constructed).
pub const LDAP_OP_EXTENDED_REQUEST: Int = 119;

/// protocolOp tag of ExtendedResponse (APPLICATION 24, constructed).
pub const LDAP_OP_EXTENDED_RESPONSE: Int = 120;

/// Result code of success (0).
pub const LDAP_RESULT_SUCCESS: Int = 0;

/// Result code of operationsError (1).
pub const LDAP_RESULT_OPERATIONS_ERROR: Int = 1;

/// Result code of protocolError (2).
pub const LDAP_RESULT_PROTOCOL_ERROR: Int = 2;

/// Result code of timeLimitExceeded (3).
pub const LDAP_RESULT_TIME_LIMIT_EXCEEDED: Int = 3;

/// Result code of sizeLimitExceeded (4).
pub const LDAP_RESULT_SIZE_LIMIT_EXCEEDED: Int = 4;

/// Result code of compareFalse (5).
pub const LDAP_RESULT_COMPARE_FALSE: Int = 5;

/// Result code of compareTrue (6).
pub const LDAP_RESULT_COMPARE_TRUE: Int = 6;

/// Result code of authMethodNotSupported (7).
pub const LDAP_RESULT_AUTH_METHOD_NOT_SUPPORTED: Int = 7;

/// Result code of strongerAuthRequired (8).
pub const LDAP_RESULT_STRONGER_AUTH_REQUIRED: Int = 8;

/// Result code of the reserved partialResults (9).
pub const LDAP_RESULT_PARTIAL_RESULTS: Int = 9;

/// Result code of referral (10).
pub const LDAP_RESULT_REFERRAL: Int = 10;

/// Result code of adminLimitExceeded (11).
pub const LDAP_RESULT_ADMIN_LIMIT_EXCEEDED: Int = 11;

/// Result code of unavailableCriticalExtension (12).
pub const LDAP_RESULT_UNAVAILABLE_CRITICAL_EXTENSION: Int = 12;

/// Result code of confidentialityRequired (13).
pub const LDAP_RESULT_CONFIDENTIALITY_REQUIRED: Int = 13;

/// Result code of saslBindInProgress (14).
pub const LDAP_RESULT_SASL_BIND_IN_PROGRESS: Int = 14;

/// Result code of noSuchAttribute (16).
pub const LDAP_RESULT_NO_SUCH_ATTRIBUTE: Int = 16;

/// Result code of undefinedAttributeType (17).
pub const LDAP_RESULT_UNDEFINED_ATTRIBUTE_TYPE: Int = 17;

/// Result code of inappropriateMatching (18).
pub const LDAP_RESULT_INAPPROPRIATE_MATCHING: Int = 18;

/// Result code of constraintViolation (19).
pub const LDAP_RESULT_CONSTRAINT_VIOLATION: Int = 19;

/// Result code of attributeOrValueExists (20).
pub const LDAP_RESULT_ATTRIBUTE_OR_VALUE_EXISTS: Int = 20;

/// Result code of invalidAttributeSyntax (21).
pub const LDAP_RESULT_INVALID_ATTRIBUTE_SYNTAX: Int = 21;

/// Result code of noSuchObject (32).
pub const LDAP_RESULT_NO_SUCH_OBJECT: Int = 32;

/// Result code of aliasProblem (33).
pub const LDAP_RESULT_ALIAS_PROBLEM: Int = 33;

/// Result code of invalidDNSyntax (34).
pub const LDAP_RESULT_INVALID_DN_SYNTAX: Int = 34;

/// Result code of the reserved isLeaf (35).
pub const LDAP_RESULT_IS_LEAF: Int = 35;

/// Result code of aliasDereferencingProblem (36).
pub const LDAP_RESULT_ALIAS_DEREFERENCING_PROBLEM: Int = 36;

/// Result code of inappropriateAuthentication (48).
pub const LDAP_RESULT_INAPPROPRIATE_AUTHENTICATION: Int = 48;

/// Result code of invalidCredentials (49).
pub const LDAP_RESULT_INVALID_CREDENTIALS: Int = 49;

/// Result code of insufficientAccessRights (50).
pub const LDAP_RESULT_INSUFFICIENT_ACCESS_RIGHTS: Int = 50;

/// Result code of busy (51).
pub const LDAP_RESULT_BUSY: Int = 51;

/// Result code of unavailable (52).
pub const LDAP_RESULT_UNAVAILABLE: Int = 52;

/// Result code of unwillingToPerform (53).
pub const LDAP_RESULT_UNWILLING_TO_PERFORM: Int = 53;

/// Result code of loopDetect (54).
pub const LDAP_RESULT_LOOP_DETECT: Int = 54;

/// Result code of namingViolation (64).
pub const LDAP_RESULT_NAMING_VIOLATION: Int = 64;

/// Result code of objectClassViolation (65).
pub const LDAP_RESULT_OBJECT_CLASS_VIOLATION: Int = 65;

/// Result code of notAllowedOnNonLeaf (66).
pub const LDAP_RESULT_NOT_ALLOWED_ON_NON_LEAF: Int = 66;

/// Result code of notAllowedOnRDN (67).
pub const LDAP_RESULT_NOT_ALLOWED_ON_RDN: Int = 67;

/// Result code of entryAlreadyExists (68).
pub const LDAP_RESULT_ENTRY_ALREADY_EXISTS: Int = 68;

/// Result code of objectClassModsProhibited (69).
pub const LDAP_RESULT_OBJECT_CLASS_MODS_PROHIBITED: Int = 69;

/// Result code of the reserved resultsTooLarge (70).
pub const LDAP_RESULT_RESULTS_TOO_LARGE: Int = 70;

/// Result code of affectsMultipleDSAs (71).
pub const LDAP_RESULT_AFFECTS_MULTIPLE_DSAS: Int = 71;

/// Result code of other (80).
pub const LDAP_RESULT_OTHER: Int = 80;

/// Result code of lcupResourcesExhausted (113).
pub const LDAP_RESULT_LCUP_RESOURCES_EXHAUSTED: Int = 113;

/// Result code of lcupSecurityViolation (114).
pub const LDAP_RESULT_LCUP_SECURITY_VIOLATION: Int = 114;

/// Result code of lcupInvalidData (115).
pub const LDAP_RESULT_LCUP_INVALID_DATA: Int = 115;

/// Result code of lcupUnsupportedScheme (116).
pub const LDAP_RESULT_LCUP_UNSUPPORTED_SCHEME: Int = 116;

/// Result code of lcupReloadRequired (117).
pub const LDAP_RESULT_LCUP_RELOAD_REQUIRED: Int = 117;

/// Result code of canceled (118).
pub const LDAP_RESULT_CANCELED: Int = 118;

/// Result code of noSuchOperation (119).
pub const LDAP_RESULT_NO_SUCH_OPERATION: Int = 119;

/// Result code of tooLate (120).
pub const LDAP_RESULT_TOO_LATE: Int = 120;

/// Result code of cannotCancel (121).
pub const LDAP_RESULT_CANNOT_CANCEL: Int = 121;

/// Result code of assertionFailed (122).
pub const LDAP_RESULT_ASSERTION_FAILED: Int = 122;

/// Result code of authorizationDenied (123).
pub const LDAP_RESULT_AUTHORIZATION_DENIED: Int = 123;

/// Result code of syncRefreshRequired (4096).
pub const LDAP_RESULT_SYNC_REFRESH_REQUIRED: Int = 4096;

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// A decoded BER length field. `len` is the content length (>= 0) and `size`
/// is the number of length-field bytes (1 for the short form, 1 + n for the
/// long form).
pub type BerLength = {
  len: Int;
  size: Int;
}

/// A decoded BER tag-length-value header. `tag` is the full first tag byte
/// (multi-byte tags are rejected), `len` the content length, `size` the tag
/// byte plus the length field, `content` the absolute offset of the first
/// content byte and `next` the offset just past the content.
pub type BerTlv = {
  tag: Int;
  len: Int;
  size: Int;
  content: Int;
  next: Int;
}

/// A decoded INTEGER (or ENUMERATED) value plus `next`, the offset just past
/// the TLV.
pub type BerInt = {
  value: Int;
  next: Int;
}

/// A decoded OCTET STRING value (copied verbatim) plus `next`, the offset
/// just past the TLV.
pub type BerBytes = {
  bytes: Vec[UInt8];
  next: Int;
}

/// A decoded BOOLEAN value (0 or 1) plus `next`, the offset just past the
/// TLV.
pub type BerBool = {
  value: Int;
  next: Int;
}

/// A decoded ENUMERATED value plus `next`, the offset just past the TLV.
pub type BerEnum = {
  value: Int;
  next: Int;
}

/// A printable LDAPString decoded from an OCTET STRING TLV: the validated
/// `value` plus `next`, the offset just past the TLV.
pub type LdapStr = {
  value: Str;
  next: Int;
}

/// Parsed LDAPMessage framing. `op_tag` is the protocolOp tag and
/// `op_offset`/`op_length` bound its TLV (tag byte through last content
/// byte). When a controls field is present, `has_controls` is true and
/// `controls_offset`/`controls_length` bound the raw [0] TLV (never parsed).
/// `next` is the offset just past the whole message TLV; bytes after `next`
/// are ignored by the parser (a stream may carry further messages).
pub type LdapMessage = {
  message_id: Int;
  op_tag: Int;
  op_offset: Int;
  op_length: Int;
  has_controls: Bool;
  controls_offset: Int;
  controls_length: Int;
  next: Int;
}

/// Parsed BindRequest. `auth_tag` is 0x80 for simple (the password bytes are
/// in `auth_bytes`) or 0xA3 for SASL, where `sasl_present` is true, the
/// `mechanism` string is decoded and `auth_bytes` holds the optional raw
/// credentials.
pub type LdapBindRequest = {
  version: Int;
  name: Str;
  auth_tag: Int;
  sasl_present: Bool;
  mechanism: Str;
  auth_bytes: Vec[UInt8];
  next: Int;
}

/// Parsed LDAPResult (shared by every response form). `has_referral` marks
/// the optional [3] referral; `has_sasl_creds` the BindResponse [7]
/// serverSaslCreds; `has_response_name`/`has_response_value` the
/// ExtendedResponse [10]/[11] fields.
pub type LdapResult = {
  result_code: Int;
  matched_dn: Str;
  diagnostic: Str;
  has_referral: Bool;
  referrals: Vec[Str];
  has_sasl_creds: Bool;
  sasl_creds: Vec[UInt8];
  has_response_name: Bool;
  response_name: Str;
  has_response_value: Bool;
  response_value: Vec[UInt8];
  next: Int;
}

/// Parsed SearchRequest. `filter` is the flat decoded filter tree;
/// `filter_offset`/`filter_length` bound the filter TLV in the source
/// buffer; `attributes` holds the AttributeSelection strings.
pub type LdapSearchRequest = {
  base_object: Str;
  scope: Int;
  deref_aliases: Int;
  size_limit: Int;
  time_limit: Int;
  types_only: Bool;
  filter_offset: Int;
  filter_length: Int;
  filter: LdapFilter;
  attributes: Vec[Str];
  next: Int;
}

/// Decoded PartialAttributeList. Entry i is described by
/// names[i] / first_value[i] / value_count[i]; its values are the
/// value_offsets[first_value[i] + k] / value_lengths[...] pairs for
/// k < value_count[i]. Value bytes live in the source buffer (copy them with
/// `ldap_bytes_copy`) and are never validated as text.
pub type LdapAttributeList = {
  names: Vec[Str];
  first_value: Vec[Int];
  value_count: Vec[Int];
  value_offsets: Vec[Int];
  value_lengths: Vec[Int];
  next: Int;
}

/// Parsed SearchResultEntry: the object name plus its attribute list.
pub type LdapSearchEntry = {
  object_name: Str;
  attrs: LdapAttributeList;
  next: Int;
}

/// Decoded SEQUENCE OF change for ModifyRequest. Entry i is described by
/// ops[i] (0 add, 1 delete, 2 replace) plus the same attribute-index layout
/// as `LdapAttributeList`.
pub type LdapChanges = {
  ops: Vec[Int];
  names: Vec[Str];
  first_value: Vec[Int];
  value_count: Vec[Int];
  value_offsets: Vec[Int];
  value_lengths: Vec[Int];
  next: Int;
}

/// Parsed ModifyRequest: the target object plus its change list.
pub type LdapModifyRequest = {
  object: Str;
  changes: LdapChanges;
  next: Int;
}

/// Parsed AddRequest: the entry name plus its attribute list.
pub type LdapAddRequest = {
  entry: Str;
  attrs: LdapAttributeList;
  next: Int;
}

/// Parsed CompareRequest: entry, attribute name and the raw assertion value
/// bounds.
pub type LdapCompareRequest = {
  entry: Str;
  attr: Str;
  value_offset: Int;
  value_length: Int;
  next: Int;
}

/// Parsed ModifyDNRequest. `new_superior` is only meaningful when
/// `has_new_superior` is true.
pub type LdapModifyDnRequest = {
  entry: Str;
  new_rdn: Str;
  delete_old_rdn: Bool;
  has_new_superior: Bool;
  new_superior: Str;
  next: Int;
}

/// Parsed SearchResultReference: the LDAPURL strings in wire order.
pub type LdapSearchReference = {
  uris: Vec[Str];
  next: Int;
}

/// Parsed ExtendedRequest: the requestName OID plus the optional raw
/// requestValue bounds.
pub type LdapExtendedRequest = {
  request_name: Str;
  has_value: Bool;
  value_offset: Int;
  value_length: Int;
  next: Int;
}

/// Flat decoded filter tree: node i is described by kind[i]
/// (LDAP_FILTER_KIND_*), parent[i] (-1 for the root), depth[i],
/// first_child[i]/child_count[i] for and/or/not nodes, attrs[i] (attribute
/// description; empty for and/or/not), and val_offsets[i]/val_lengths[i] for
/// the assertion value of item nodes (raw bytes in the source buffer).
/// Substring parts are the parallel part_kinds/part_offsets/part_lengths
/// entries starting at sub_first[i] (`sub_count[i]` of them). Extensible
/// match data is rules[i] (\"\" when absent) and dn_attrs[i] (0/1). `next` is
/// the offset just past the filter TLV.
pub type LdapFilter = {
  kinds: Vec[Int];
  parents: Vec[Int];
  depths: Vec[Int];
  first_child: Vec[Int];
  child_count: Vec[Int];
  attrs: Vec[Str];
  val_offsets: Vec[Int];
  val_lengths: Vec[Int];
  sub_first: Vec[Int];
  sub_count: Vec[Int];
  rules: Vec[Str];
  dn_attrs: Vec[Int];
  part_kinds: Vec[Int];
  part_offsets: Vec[Int];
  part_lengths: Vec[Int];
  next: Int;
}

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[BerLength, Str].
fn _ok_blen(v: BerLength) -> Result[BerLength, Str] {
  return Ok(v);
}

// Err(m) for Result[BerLength, Str].
fn _err_blen(m: Str) -> Result[BerLength, Str] {
  return Err(m);
}

// Ok(v) for Result[BerTlv, Str].
fn _ok_tlv(v: BerTlv) -> Result[BerTlv, Str] {
  return Ok(v);
}

// Err(m) for Result[BerTlv, Str].
fn _err_tlv(m: Str) -> Result[BerTlv, Str] {
  return Err(m);
}

// Ok(v) for Result[BerInt, Str].
fn _ok_bint(v: BerInt) -> Result[BerInt, Str] {
  return Ok(v);
}

// Err(m) for Result[BerInt, Str].
fn _err_bint(m: Str) -> Result[BerInt, Str] {
  return Err(m);
}

// Ok(v) for Result[BerBytes, Str].
fn _ok_bbytes(v: BerBytes) -> Result[BerBytes, Str] {
  return Ok(v);
}

// Err(m) for Result[BerBytes, Str].
fn _err_bbytes(m: Str) -> Result[BerBytes, Str] {
  return Err(m);
}

// Ok(v) for Result[BerBool, Str].
fn _ok_bbool(v: BerBool) -> Result[BerBool, Str] {
  return Ok(v);
}

// Err(m) for Result[BerBool, Str].
fn _err_bbool(m: Str) -> Result[BerBool, Str] {
  return Err(m);
}

// Ok(v) for Result[BerEnum, Str].
fn _ok_benum(v: BerEnum) -> Result[BerEnum, Str] {
  return Ok(v);
}

// Err(m) for Result[BerEnum, Str].
fn _err_benum(m: Str) -> Result[BerEnum, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapStr, Str].
fn _ok_lstr(v: LdapStr) -> Result[LdapStr, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapStr, Str].
fn _err_lstr(m: Str) -> Result[LdapStr, Str] {
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

// Ok(v) for Result[Vec[Str], Str].
fn _ok_strs(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _err_strs(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// Ok(v) for Result[LdapMessage, Str].
fn _ok_msg(v: LdapMessage) -> Result[LdapMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapMessage, Str].
fn _err_msg(m: Str) -> Result[LdapMessage, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapFilter, Str].
fn _ok_filter(v: LdapFilter) -> Result[LdapFilter, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapFilter, Str].
fn _err_filter(m: Str) -> Result[LdapFilter, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapBindRequest, Str].
fn _ok_bind(v: LdapBindRequest) -> Result[LdapBindRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapBindRequest, Str].
fn _err_bind(m: Str) -> Result[LdapBindRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapResult, Str].
fn _ok_result(v: LdapResult) -> Result[LdapResult, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapResult, Str].
fn _err_result(m: Str) -> Result[LdapResult, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapSearchRequest, Str].
fn _ok_search(v: LdapSearchRequest) -> Result[LdapSearchRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapSearchRequest, Str].
fn _err_search(m: Str) -> Result[LdapSearchRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapAttributeList, Str].
fn _ok_attrs(v: LdapAttributeList) -> Result[LdapAttributeList, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapAttributeList, Str].
fn _err_attrs(m: Str) -> Result[LdapAttributeList, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapSearchEntry, Str].
fn _ok_entry(v: LdapSearchEntry) -> Result[LdapSearchEntry, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapSearchEntry, Str].
fn _err_entry(m: Str) -> Result[LdapSearchEntry, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapChanges, Str].
fn _ok_changes(v: LdapChanges) -> Result[LdapChanges, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapChanges, Str].
fn _err_changes(m: Str) -> Result[LdapChanges, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapModifyRequest, Str].
fn _ok_modify(v: LdapModifyRequest) -> Result[LdapModifyRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapModifyRequest, Str].
fn _err_modify(m: Str) -> Result[LdapModifyRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapAddRequest, Str].
fn _ok_add(v: LdapAddRequest) -> Result[LdapAddRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapAddRequest, Str].
fn _err_add(m: Str) -> Result[LdapAddRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapCompareRequest, Str].
fn _ok_compare(v: LdapCompareRequest) -> Result[LdapCompareRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapCompareRequest, Str].
fn _err_compare(m: Str) -> Result[LdapCompareRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapModifyDnRequest, Str].
fn _ok_moddn(v: LdapModifyDnRequest) -> Result[LdapModifyDnRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapModifyDnRequest, Str].
fn _err_moddn(m: Str) -> Result[LdapModifyDnRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapSearchReference, Str].
fn _ok_ref(v: LdapSearchReference) -> Result[LdapSearchReference, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapSearchReference, Str].
fn _err_ref(m: Str) -> Result[LdapSearchReference, Str] {
  return Err(m);
}

// Ok(v) for Result[LdapExtendedRequest, Str].
fn _ok_ext(v: LdapExtendedRequest) -> Result[LdapExtendedRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[LdapExtendedRequest, Str].
fn _err_ext(m: Str) -> Result[LdapExtendedRequest, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// Byte at `pos` widened to an Int (0..255); callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Copy `n` bytes starting at `start` into a fresh vector; callers guarantee
// `start >= 0`, `n >= 0` and `start + n <= data.len()`.
fn _copy_bytes(data: &Vec[UInt8], start: Int, n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(data[start + i]);
    i = i + 1;
  }
  return out;
}

// Append every byte of `v` to `out`.
fn _push_bytes(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append the definite-form BER length of `len` (any non-negative Int; eight
// bytes or fewer are produced because Int is 64-bit). A negative length
// writes nothing.
fn _push_length(out: &mut Vec[UInt8], len: Int) {
  if len < 0 {
    return;
  }
  if len < 128 {
    out.push(len as UInt8);
    return;
  }
  var low = Vec[UInt8].new();
  var q = len;
  while q > 0 {
    low.push((q % 256) as UInt8);
    q = q / 256;
  }
  out.push((128 + low.len()) as UInt8);
  var i = low.len() - 1;
  while i >= 0 {
    out.push(low[i]);
    i = i - 1;
  }
}

// Render "`msg` at offset `off`" for the error catalog.
fn _at(msg: Str, off: Int) -> Str {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, msg);
  builder.sb_push_str(&mut sb, " at offset ");
  builder.sb_push_int(&mut sb, off);
  return builder.sb_to_str(&sb);
}

// Absolute offset of the TLV's first byte: `content` minus the tag and
// length bytes.
fn _tlv_start(t: &BerTlv) -> Int {
  return t.content - t.size;
}

// Wrap `content` in a TLV with tag `tag` and a definite length.
fn _wrap_tlv(tag: Int, content: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(tag as UInt8);
  _push_length(&mut out, content.len());
  _push_bytes(&mut out, content);
  return out;
}

// True when data[start, start+n) is printable ASCII (0x20..0x7E); callers
// guarantee the bounds.
fn _printable(data: &Vec[UInt8], start: Int, n: Int) -> Bool {
  var i = 0;
  while i < n {
    let b: Int = _byte(data, start + i);
    if b < 32 || b > 126 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when every byte of `v` is printable ASCII.
fn _bytes_printable(v: &Vec[UInt8]) -> Bool {
  var i = 0;
  while i < v.len() {
    let b: Int = (v[i] as Int) & 0xFF;
    if b < 32 || b > 126 {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// Materialize data[start, start+n) as a Str; callers validate printability
// first (no NUL may reach sb_to_str).
fn _str_from(data: &Vec[UInt8], start: Int, n: Int) -> Str {
  var sb = builder.sb_new();
  var i = 0;
  while i < n {
    builder.sb_push_byte(&mut sb, data[start + i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Byte content of a Str (a reliable Vec result even for Str values read out
// of a Vec[Str]).
fn _str_bytes(s: Str) -> Vec[UInt8] {
  var sb = builder.sb_new();
  builder.sb_push_str(&mut sb, s);
  return sb;
}

// Printable LDAPString from raw bytes [start, start+n); reports at `base`.
fn _ldap_str_raw(data: &Vec[UInt8], start: Int, n: Int, base: Int) -> Result[Str, Str] {
  if !_printable(data, start, n) {
    return _err_str(_at("ldap: non-printable string", base));
  }
  return _ok_str(_str_from(data, start, n));
}

// --------------------------------------------------
//  BER decoding
// --------------------------------------------------

/// Decode the BER length field at `off`. The short form is 0x00..0x7F; the
/// long form is 0x80|n followed by n big-endian bytes with n in 1..8. Only
/// the minimal long form is accepted: a leading zero length byte or a value
/// below 128 encoded in the long form is `ber: overlong length`.
///
/// Errors, each naming `off` (the first length byte):
///   * `ber: negative offset` -- off < 0;
///   * `ber: truncated length` -- no length byte, or the declared number of
///     long-form bytes is missing;
///   * `ber: indefinite length` -- the 0x80 byte;
///   * `ber: length overflow` -- more than 8 length bytes, or a long-form
///     value that does not fit a signed 64-bit Int;
///   * `ber: overlong length` -- non-minimal long form.
/// Complexity: O(length bytes).
pub fn ber_length_decode(data: &Vec[UInt8], off: Int) -> Result[BerLength, Str]
  ensures: off < 0 => result is Err;
  ensures: off >= data.len() => result is Err;
  ensures: result is Ok => off >= 0 && off < data.len();
{
  if off < 0 {
    return _err_blen("ber: negative offset");
  }
  if off >= data.len() {
    return _err_blen(_at("ber: truncated length", off));
  }
  let b: Int = _byte(data, off);
  if b < 128 {
    return _ok_blen(BerLength{ len: b; size: 1; });
  }
  let n: Int = b - 128;
  if n == 0 {
    return _err_blen(_at("ber: indefinite length", off));
  }
  if n > 8 {
    return _err_blen(_at("ber: length overflow", off));
  }
  if off + 1 + n > data.len() {
    return _err_blen(_at("ber: truncated length", off));
  }
  var v = 0;
  var i = 0;
  while i < n {
    let x: Int = _byte(data, off + 1 + i);
    if i == 0 && x == 0 {
      return _err_blen(_at("ber: overlong length", off));
    }
    v = v * 256 + x;
    if v < 0 {
      return _err_blen(_at("ber: length overflow", off));
    }
    i = i + 1;
  }
  if v < 128 {
    return _err_blen(_at("ber: overlong length", off));
  }
  return _ok_blen(BerLength{ len: v; size: 1 + n; });
}

/// Decode one BER tag-length-value at `off` and check that the declared
/// content fits the buffer. Only one-byte tags are accepted (the low five
/// bits of the tag byte may not be 11111).
///
/// Errors, each naming `off` (the tag byte):
///   * `ber: negative offset`, `ber: truncated tag` -- no tag byte;
///   * `ber: multi-byte tag` -- a tag whose low five bits are 31;
///   * the `ber_length_decode` catalog;
///   * `ber: value overruns buffer` -- `content + len > data.len()`.
/// The caller is responsible for checking the TLV against its container
/// (`_tlv_in` reports `ber: value overruns container`).
/// Complexity: O(1) after the length field.
pub fn ber_tlv_decode(data: &Vec[UInt8], off: Int) -> Result[BerTlv, Str]
  ensures: off < 0 => result is Err;
  ensures: off >= data.len() => result is Err;
  ensures: data.len() - off < 2 => result is Err;
  ensures: result is Ok => off >= 0 && data.len() - off >= 2;
{
  if off < 0 {
    return _err_tlv("ber: negative offset");
  }
  if off >= data.len() {
    return _err_tlv(_at("ber: truncated tag", off));
  }
  let tag: Int = _byte(data, off);
  if tag % 32 == 31 {
    return _err_tlv(_at("ber: multi-byte tag", off));
  }
  let lr = ber_length_decode(data, off + 1);
  if !lr.is_ok {
    return _err_tlv(lr.error);
  }
  let l: BerLength = lr.value;
  let content = off + 1 + l.size;
  let len: Int = l.len;
  if len > data.len() - content {
    return _err_tlv(_at("ber: value overruns buffer", off));
  }
  return _ok_tlv(BerTlv{ tag: tag; len: len; size: 1 + l.size; content: content; next: content + len; });
}

// Decode a TLV at `off` that must not extend past `end` (the end of the
// enclosing container); reports `ber: value overruns container` at `off`.
fn _tlv_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[BerTlv, Str] {
  let r = ber_tlv_decode(data, off);
  if !r.is_ok {
    return _err_tlv(r.error);
  }
  let t: BerTlv = r.value;
  if t.next > end {
    return _err_tlv(_at("ber: value overruns container", off));
  }
  return _ok_tlv(t);
}

// Signed value of an integer content field [start, start+n): 1..8 bytes,
// minimally encoded, then sign-extended. Reports at `base`.
fn _int_content(data: &Vec[UInt8], start: Int, n: Int, base: Int) -> Result[Int, Str] {
  if n < 1 {
    return _err_int(_at("ber: empty integer", base));
  }
  if n > 8 {
    return _err_int(_at("ber: integer overflow", base));
  }
  let b0: Int = _byte(data, start);
  if n > 1 {
    let b1: Int = _byte(data, start + 1);
    if b0 == 0 && b1 < 128 {
      return _err_int(_at("ber: non-minimal integer", base));
    }
    if b0 == 255 && b1 >= 128 {
      return _err_int(_at("ber: non-minimal integer", base));
    }
  }
  var v = 0;
  if b0 >= 128 {
    v = b0 - 256;
  } else {
    v = b0;
  }
  var i = 1;
  while i < n {
    let x: Int = _byte(data, start + i);
    v = v * 256 + x;
    i = i + 1;
  }
  return _ok_int(v);
}

// Signed value of an INTEGER TLV; reports at the TLV's first byte.
fn _int_value(data: &Vec[UInt8], t: &BerTlv) -> Result[Int, Str] {
  return _int_content(data, t.content, t.len, _tlv_start(t));
}

/// Decode a signed INTEGER at `off` (tag 0x02). Content must be minimally
/// encoded and 1..8 bytes long.
/// Errors: the `ber_tlv_decode` catalog, `ber: tag mismatch` at `off`, and
/// at the TLV's first byte `ber: empty integer`, `ber: integer overflow` and
/// `ber: non-minimal integer`.
/// Complexity: O(content bytes).
pub fn ber_int_decode(data: &Vec[UInt8], off: Int) -> Result[BerInt, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bint(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != BER_TAG_INTEGER {
    return _err_bint(_at("ber: tag mismatch", off));
  }
  let vr = _int_value(data, &t);
  if !vr.is_ok {
    return _err_bint(vr.error);
  }
  let v: Int = vr.value;
  return _ok_bint(BerInt{ value: v; next: t.next; });
}

// Decode an INTEGER at `off` that must end at or before `end`.
fn _int_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[BerInt, Str] {
  let r = ber_int_decode(data, off);
  if !r.is_ok {
    return _err_bint(r.error);
  }
  let b: BerInt = r.value;
  if b.next > end {
    return _err_bint(_at("ber: value overruns container", off));
  }
  return _ok_bint(b);
}

/// Decode an OCTET STRING at `off` (tag 0x04). The content bytes are copied
/// verbatim (no text validation); a zero-length string is valid.
/// Errors: the `ber_tlv_decode` catalog and `ber: tag mismatch` at `off`.
/// Complexity: O(content bytes).
pub fn ber_octet_string_decode(data: &Vec[UInt8], off: Int) -> Result[BerBytes, Str]
  ensures: off < 0 => result is Err;
  ensures: data.len() - off < 2 => result is Err;
  ensures: result is Ok => off >= 0 && data.len() - off >= 2;
{
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bbytes(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != BER_TAG_OCTET_STRING {
    return _err_bbytes(_at("ber: tag mismatch", off));
  }
  let b: Vec[UInt8] = _copy_bytes(data, t.content, t.len);
  return _ok_bbytes(BerBytes{ bytes: b; next: t.next; });
}

/// Decode a BOOLEAN at `off` (tag 0x01). The content must be exactly one
/// byte; any non-zero byte is TRUE (X.690 BER), so the decoded value is 0 or
/// 1.
/// Errors: the `ber_tlv_decode` catalog, `ber: tag mismatch` at `off` and
/// `ber: bad boolean` at `off` for any other content length.
/// Complexity: O(1).
pub fn ber_bool_decode(data: &Vec[UInt8], off: Int) -> Result[BerBool, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bbool(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != BER_TAG_BOOLEAN {
    return _err_bbool(_at("ber: tag mismatch", off));
  }
  if t.len != 1 {
    return _err_bbool(_at("ber: bad boolean", off));
  }
  let b: Int = _byte(data, t.content);
  var v = 0;
  if b != 0 {
    v = 1;
  }
  return _ok_bbool(BerBool{ value: v; next: t.next; });
}

// Decode a BOOLEAN at `off` that must end at or before `end`.
fn _bool_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[BerBool, Str] {
  let r = ber_bool_decode(data, off);
  if !r.is_ok {
    return _err_bbool(r.error);
  }
  let b: BerBool = r.value;
  if b.next > end {
    return _err_bbool(_at("ber: value overruns container", off));
  }
  return _ok_bbool(b);
}

/// Decode an ENUMERATED at `off` (tag 0x0A). The content follows the
/// INTEGER rules (1..8 bytes, minimal encoding, signed); LDAP enums in this
/// package are then range-checked by the operation parsers.
/// Errors: the `ber_tlv_decode` catalog, `ber: tag mismatch` at `off`, and
/// the `_int_content` catalog at the TLV's first byte.
/// Complexity: O(content bytes).
pub fn ber_enum_decode(data: &Vec[UInt8], off: Int) -> Result[BerEnum, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_benum(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != BER_TAG_ENUMERATED {
    return _err_benum(_at("ber: tag mismatch", off));
  }
  let vr = _int_value(data, &t);
  if !vr.is_ok {
    return _err_benum(vr.error);
  }
  let v: Int = vr.value;
  return _ok_benum(BerEnum{ value: v; next: t.next; });
}

// Decode an ENUMERATED at `off` that must end at or before `end`.
fn _enum_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[BerEnum, Str] {
  let r = ber_enum_decode(data, off);
  if !r.is_ok {
    return _err_benum(r.error);
  }
  let b: BerEnum = r.value;
  if b.next > end {
    return _err_benum(_at("ber: value overruns container", off));
  }
  return _ok_benum(b);
}

/// Decode a SEQUENCE (tag 0x30) or SET (tag 0x31) header at `off`; the
/// returned `BerTlv.tag` is the actual wire tag.
/// Errors: the `ber_tlv_decode` catalog and `ber: tag mismatch` at `off`.
/// Complexity: O(1) after the length field.
pub fn ber_sequence_decode(data: &Vec[UInt8], off: Int) -> Result[BerTlv, Str]
  ensures: off < 0 => result is Err;
  ensures: data.len() - off < 2 => result is Err;
{
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_tlv(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != BER_TAG_SEQUENCE && t.tag != BER_TAG_SET {
    return _err_tlv(_at("ber: tag mismatch", off));
  }
  return _ok_tlv(t);
}

// --------------------------------------------------
//  BER encoding
// --------------------------------------------------

/// Encode `len` as a definite-form BER length: one byte below 128, else
/// 0x80|n followed by the minimal big-endian value. A negative `len`
/// yields an empty vector.
/// Complexity: O(length bytes).
pub fn ber_length_encode(len: Int) -> Vec[UInt8]
  ensures: len < 0 => result.len() == 0;
  ensures: len >= 0 && len < 128 => result.len() == 1;
  ensures: len >= 128 && len <= 255 => result.len() == 2;
{
  var out = Vec[UInt8].new();
  _push_length(&mut out, len);
  return out;
}

// Minimal big-endian two's complement content bytes of a signed Int.
fn _int_content_encode(value: Int) -> Vec[UInt8] {
  var low = Vec[UInt8].new();
  if value >= 0 {
    var x = value;
    while x > 0 {
      low.push((x % 256) as UInt8);
      x = x / 256;
    }
    if low.len() == 0 {
      low.push(0);
    }
    let top: Int = (low[low.len() - 1] as Int) & 0xFF;
    if top >= 128 {
      low.push(0);
    }
  } else {
    var v = value;
    while true {
      var r = v % 256;
      if r < 0 {
        r = r + 256;
      }
      low.push(r as UInt8);
      let q = (v - r) / 256;
      if q == -1 && r >= 128 {
        break;
      }
      v = q;
    }
  }
  var out = Vec[UInt8].new();
  var i = low.len() - 1;
  while i >= 0 {
    out.push(low[i]);
    i = i - 1;
  }
  return out;
}

/// Encode `value` as a minimally encoded signed INTEGER TLV (tag 0x02).
/// Complexity: O(content bytes).
pub fn ber_int_encode(value: Int) -> Vec[UInt8] {
  var body = _int_content_encode(value);
  var out = Vec[UInt8].new();
  out.push(BER_TAG_INTEGER as UInt8);
  _push_length(&mut out, body.len());
  _push_bytes(&mut out, &body);
  return out;
}

/// Encode `value` as an ENUMERATED TLV (tag 0x0A) with the INTEGER content
/// rules. Complexity: O(content bytes).
pub fn ber_enum_encode(value: Int) -> Vec[UInt8] {
  var body = _int_content_encode(value);
  var out = Vec[UInt8].new();
  out.push(BER_TAG_ENUMERATED as UInt8);
  _push_length(&mut out, body.len());
  _push_bytes(&mut out, &body);
  return out;
}

/// Encode `bytes` as an OCTET STRING TLV (tag 0x04), verbatim.
/// Complexity: O(content bytes).
pub fn ber_octet_string_encode(bytes: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(BER_TAG_OCTET_STRING as UInt8);
  _push_length(&mut out, bytes.len());
  _push_bytes(&mut out, bytes);
  return out;
}

/// Encode a BOOLEAN TLV (tag 0x01): 0x01 0x01 0xFF for true and
/// 0x01 0x01 0x00 for false.
/// Complexity: O(1).
pub fn ber_bool_encode(value: Bool) -> Vec[UInt8]
  ensures: result.len() == 3;
{
  var out = Vec[UInt8].new();
  out.push(BER_TAG_BOOLEAN as UInt8);
  out.push(1 as UInt8);
  if value {
    out.push(255 as UInt8);
  } else {
    out.push(0 as UInt8);
  }
  return out;
}

/// Wrap `content` in a TLV with tag `tag` and a definite length.
/// Complexity: O(content bytes).
pub fn ber_tlv_wrap(tag: Int, content: &Vec[UInt8]) -> Vec[UInt8]
  ensures: content.len() < 128 => result.len() == content.len() + 2;
  ensures: content.len() >= 128 && content.len() <= 255 => result.len() == content.len() + 3;
{
  return _wrap_tlv(tag, content);
}

// Printable LDAPString from an OCTET STRING TLV bounded by `end`.
fn _ldap_str_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[LdapStr, Str] {
  let tr = _tlv_in(data, off, end);
  if !tr.is_ok {
    return _err_lstr(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != BER_TAG_OCTET_STRING {
    return _err_lstr(_at("ber: tag mismatch", off));
  }
  let sr = _ldap_str_raw(data, t.content, t.len, off);
  if !sr.is_ok {
    return _err_lstr(sr.error);
  }
  let v: Str = sr.value;
  return _ok_lstr(LdapStr{ value: v; next: t.next; });
}

/// Copy `len` bytes at `off` out of `data`; an out-of-range request yields
/// an empty vector. This is the documented way to read an attribute value,
/// assertion value or referral string that a parse function left in the
/// source buffer.
/// Complexity: O(len).
pub fn ldap_bytes_copy(data: &Vec[UInt8], off: Int, len: Int) -> Vec[UInt8]
  ensures: off < 0 || len < 0 => result.len() == 0;
  ensures: off > data.len() => result.len() == 0;
  ensures: len > data.len() - off => result.len() == 0;
  ensures: off >= 0 && len >= 0 && off <= data.len() && len <= data.len() - off => result.len() == len;
{
  if off < 0 || len < 0 {
    return Vec[UInt8].new();
  }
  if off > data.len() {
    return Vec[UInt8].new();
  }
  if len > data.len() - off {
    return Vec[UInt8].new();
  }
  return _copy_bytes(data, off, len);
}

// --------------------------------------------------
//  Protocol-op tags
// --------------------------------------------------

/// True when `tag` is one of the protocolOp tags this module recognizes.
/// Complexity: O(1).
pub fn ldap_op_tag_known(tag: Int) -> Bool
  ensures: tag < 66 || tag > 120 => result == false;
  ensures: result == true => tag >= 66 && tag <= 120;
{
  if tag == LDAP_OP_UNBIND_REQUEST { return true; }
  if tag == LDAP_OP_DEL_REQUEST { return true; }
  if tag == LDAP_OP_ABANDON_REQUEST { return true; }
  if tag == LDAP_OP_BIND_REQUEST { return true; }
  if tag == LDAP_OP_BIND_RESPONSE { return true; }
  if tag == LDAP_OP_SEARCH_REQUEST { return true; }
  if tag == LDAP_OP_SEARCH_ENTRY { return true; }
  if tag == LDAP_OP_SEARCH_DONE { return true; }
  if tag == LDAP_OP_MODIFY_REQUEST { return true; }
  if tag == LDAP_OP_MODIFY_RESPONSE { return true; }
  if tag == LDAP_OP_ADD_REQUEST { return true; }
  if tag == LDAP_OP_ADD_RESPONSE { return true; }
  if tag == LDAP_OP_DEL_RESPONSE { return true; }
  if tag == LDAP_OP_MODIFY_DN_REQUEST { return true; }
  if tag == LDAP_OP_MODIFY_DN_RESPONSE { return true; }
  if tag == LDAP_OP_COMPARE_REQUEST { return true; }
  if tag == LDAP_OP_COMPARE_RESPONSE { return true; }
  if tag == LDAP_OP_SEARCH_REFERENCE { return true; }
  if tag == LDAP_OP_EXTENDED_REQUEST { return true; }
  if tag == LDAP_OP_EXTENDED_RESPONSE { return true; }
  return false;
}

/// RFC 4511 protocolOp name for `tag`, or "unknown".
/// Complexity: O(1).
pub fn ldap_op_tag_name(tag: Int) -> Str
  ensures: ldap_op_tag_known(tag) == false => result.len() == 7;
  ensures: tag == 99 => result.len() == 13;
{
  if tag == LDAP_OP_UNBIND_REQUEST { return "UnbindRequest"; }
  if tag == LDAP_OP_DEL_REQUEST { return "DelRequest"; }
  if tag == LDAP_OP_ABANDON_REQUEST { return "AbandonRequest"; }
  if tag == LDAP_OP_BIND_REQUEST { return "BindRequest"; }
  if tag == LDAP_OP_BIND_RESPONSE { return "BindResponse"; }
  if tag == LDAP_OP_SEARCH_REQUEST { return "SearchRequest"; }
  if tag == LDAP_OP_SEARCH_ENTRY { return "SearchResultEntry"; }
  if tag == LDAP_OP_SEARCH_DONE { return "SearchResultDone"; }
  if tag == LDAP_OP_MODIFY_REQUEST { return "ModifyRequest"; }
  if tag == LDAP_OP_MODIFY_RESPONSE { return "ModifyResponse"; }
  if tag == LDAP_OP_ADD_REQUEST { return "AddRequest"; }
  if tag == LDAP_OP_ADD_RESPONSE { return "AddResponse"; }
  if tag == LDAP_OP_DEL_RESPONSE { return "DelResponse"; }
  if tag == LDAP_OP_MODIFY_DN_REQUEST { return "ModifyDNRequest"; }
  if tag == LDAP_OP_MODIFY_DN_RESPONSE { return "ModifyDNResponse"; }
  if tag == LDAP_OP_COMPARE_REQUEST { return "CompareRequest"; }
  if tag == LDAP_OP_COMPARE_RESPONSE { return "CompareResponse"; }
  if tag == LDAP_OP_SEARCH_REFERENCE { return "SearchResultReference"; }
  if tag == LDAP_OP_EXTENDED_REQUEST { return "ExtendedRequest"; }
  if tag == LDAP_OP_EXTENDED_RESPONSE { return "ExtendedResponse"; }
  return "unknown";
}

// --------------------------------------------------
//  Messages
// --------------------------------------------------

/// Parse the LDAPMessage framing at offset 0: SEQUENCE { INTEGER messageID,
/// protocolOp, controls [0] OPTIONAL }. The protocolOp is only checked for a
/// known tag and container fit; decode its contents with the per-operation
/// parser for `op_tag` at `op_offset`. The controls TLV, when present, is
/// bounded by `controls_offset`/`controls_length` and never parsed. Bytes
/// after `next` are ignored (stream-friendly).
///
/// Errors: the BER catalogs; `ber: tag mismatch` at offset 0 when the
/// message is not a SEQUENCE; `ldap: negative message id` at the messageID
/// TLV; `ldap: bad protocol op` at the protocolOp tag when it is not a known
/// op tag; `ber: value overruns container` when a field crosses the message;
/// and `ldap: trailing bytes` when the field after protocolOp is neither a
/// [0] controls TLV nor absent.
/// Complexity: O(message bytes) framing only.
pub fn ldap_message_parse(data: &Vec[UInt8]) -> Result[LdapMessage, Str]
  ensures: data.len() < 2 => result is Err;
  ensures: result is Ok => data.len() >= 2;
{
  let mr = ber_tlv_decode(data, 0);
  if !mr.is_ok {
    return _err_msg(mr.error);
  }
  let msg: BerTlv = mr.value;
  if msg.tag != BER_TAG_SEQUENCE {
    return _err_msg(_at("ber: tag mismatch", 0));
  }
  let ir = _int_in(data, msg.content, msg.next);
  if !ir.is_ok {
    return _err_msg(ir.error);
  }
  let ib: BerInt = ir.value;
  let message_id: Int = ib.value;
  if message_id < 0 {
    return _err_msg(_at("ldap: negative message id", msg.content));
  }
  let op_off: Int = ib.next;
  if op_off >= msg.next {
    return _err_msg(_at("ber: truncated tag", op_off));
  }
  let orr = ber_tlv_decode(data, op_off);
  if !orr.is_ok {
    return _err_msg(orr.error);
  }
  let op: BerTlv = orr.value;
  if op.next > msg.next {
    return _err_msg(_at("ber: value overruns container", op_off));
  }
  let op_tag: Int = op.tag;
  if !ldap_op_tag_known(op_tag) {
    return _err_msg(_at("ldap: bad protocol op", op_off));
  }
  var has_controls = false;
  var controls_offset = 0;
  var controls_length = 0;
  if op.next < msg.next {
    let peek: Int = _byte(data, op.next);
    if peek != LDAP_TAG_CONTROLS {
      return _err_msg(_at("ldap: trailing bytes", op.next));
    }
    let cr = _tlv_in(data, op.next, msg.next);
    if !cr.is_ok {
      return _err_msg(cr.error);
    }
    let ct: BerTlv = cr.value;
    has_controls = true;
    controls_offset = op.next;
    controls_length = ct.next - op.next;
    if ct.next != msg.next {
      return _err_msg(_at("ldap: trailing bytes", ct.next));
    }
  }
  return _ok_msg(LdapMessage{
    message_id: message_id;
    op_tag: op_tag;
    op_offset: op_off;
    op_length: op.next - op_off;
    has_controls: has_controls;
    controls_offset: controls_offset;
    controls_length: controls_length;
    next: msg.next;
  });
}

/// Encode a whole LDAPMessage: SEQUENCE { INTEGER `message_id`, `op` } where
/// `op` is an already encoded protocolOp TLV. The message id must be
/// 0..LDAP_MAX_MESSAGE_ID and `op` must not be empty.
/// Errors (no offsets; encoder): `ldap: negative message id`,
/// `ldap: message id too large`, `ldap: empty operation`.
/// Complexity: O(message bytes).
pub fn ldap_message_encode(message_id: Int, op: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  ensures: message_id < 0 => result is Err;
  ensures: message_id > 2147483647 => result is Err;
  ensures: op.len() == 0 => result is Err;
  ensures: result is Ok => message_id >= 0 && message_id <= 2147483647 && op.len() > 0;
{
  if message_id < 0 {
    return _err_bytes("ldap: negative message id");
  }
  if message_id > LDAP_MAX_MESSAGE_ID {
    return _err_bytes("ldap: message id too large");
  }
  if op.len() == 0 {
    return _err_bytes("ldap: empty operation");
  }
  var body = Vec[UInt8].new();
  _push_bytes(&mut body, &ber_int_encode(message_id));
  _push_bytes(&mut body, op);
  return _ok_bytes(_wrap_tlv(BER_TAG_SEQUENCE, &body));
}

// --------------------------------------------------
//  Bind operations
// --------------------------------------------------

/// Parse a BindRequest at `off` (tag 0x60): SEQUENCE { INTEGER version
/// (1..127), LDAPDN name, authentication }. Simple auth ([0], 0x80) copies
/// the password bytes verbatim; SASL ([3], 0xA3) decodes the mechanism
/// LDAPString and copies the optional credentials. The LDAPDN is validated
/// printable.
///
/// Errors: the BER catalogs; `ber: tag mismatch` at `off`;
/// `ldap: bad bind version` at the version TLV; `ldap: non-printable string`
/// at the offending string; `ldap: bad authentication` at the authentication
/// TLV for any tag other than 0x80/0xA3; `ber: tag mismatch` at the SASL
/// mechanism when it is not an OCTET STRING; and `ldap: trailing bytes`
/// inside the SASL choice or the request.
/// Complexity: O(request bytes).
pub fn ldap_bind_request_parse(data: &Vec[UInt8], off: Int) -> Result[LdapBindRequest, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_bind(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_BIND_REQUEST {
    return _err_bind(_at("ber: tag mismatch", off));
  }
  let vr = _int_in(data, t.content, t.next);
  if !vr.is_ok {
    return _err_bind(vr.error);
  }
  let vb: BerInt = vr.value;
  let version: Int = vb.value;
  if version < 1 || version > 127 {
    return _err_bind(_at("ldap: bad bind version", t.content));
  }
  let nr = _ldap_str_in(data, vb.next, t.next);
  if !nr.is_ok {
    return _err_bind(nr.error);
  }
  let nm: LdapStr = nr.value;
  let name: Str = nm.value;
  if nm.next >= t.next {
    return _err_bind(_at("ber: truncated tag", nm.next));
  }
  let ar = ber_tlv_decode(data, nm.next);
  if !ar.is_ok {
    return _err_bind(ar.error);
  }
  let at: BerTlv = ar.value;
  if at.next > t.next {
    return _err_bind(_at("ber: value overruns container", nm.next));
  }
  var auth_tag = 0;
  var sasl_present = false;
  var mechanism = "";
  var auth_bytes = Vec[UInt8].new();
  if at.tag == LDAP_AUTH_SIMPLE {
    auth_tag = at.tag;
    auth_bytes = _copy_bytes(data, at.content, at.len);
    if at.next != t.next {
      return _err_bind(_at("ldap: trailing bytes", at.next));
    }
  } elif at.tag == LDAP_AUTH_SASL {
    auth_tag = at.tag;
    sasl_present = true;
    let mr = _ldap_str_in(data, at.content, at.next);
    if !mr.is_ok {
      return _err_bind(mr.error);
    }
    let mm: LdapStr = mr.value;
    mechanism = mm.value;
    var pos: Int = mm.next;
    if pos < at.next {
      let cr = _tlv_in(data, pos, at.next);
      if !cr.is_ok {
        return _err_bind(cr.error);
      }
      let ct: BerTlv = cr.value;
      if ct.tag != BER_TAG_OCTET_STRING {
        return _err_bind(_at("ber: tag mismatch", pos));
      }
      auth_bytes = _copy_bytes(data, ct.content, ct.len);
      pos = ct.next;
    }
    if pos != at.next {
      return _err_bind(_at("ldap: trailing bytes", pos));
    }
  } else {
    return _err_bind(_at("ldap: bad authentication", nm.next));
  }
  return _ok_bind(LdapBindRequest{
    version: version;
    name: name;
    auth_tag: auth_tag;
    sasl_present: sasl_present;
    mechanism: mechanism;
    auth_bytes: auth_bytes;
    next: t.next;
  });
}

/// Parse an UnbindRequest at `off` (tag 0x42, primitive) and return the
/// offset just past it. The content must be empty.
/// Errors: the BER catalogs, `ber: tag mismatch` at `off` and
/// `ldap: bad unbind` at `off` when the content is non-empty.
/// Complexity: O(1).
pub fn ldap_unbind_request_parse(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_int(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_UNBIND_REQUEST {
    return _err_int(_at("ber: tag mismatch", off));
  }
  if t.len != 0 {
    return _err_int(_at("ldap: bad unbind", off));
  }
  return _ok_int(t.next);
}

/// Parse an AbandonRequest at `off` (tag 0x50, primitive) and return the
/// abandoned message id. The content is an implicitly tagged MessageID and
/// must be a minimally encoded non-negative integer.
/// Errors: the BER catalogs, `ber: tag mismatch` at `off`, the
/// `_int_content` catalog at `off` and `ldap: negative abandon id` at `off`.
/// Complexity: O(content bytes).
pub fn ldap_abandon_request_parse(data: &Vec[UInt8], off: Int) -> Result[Int, Str]
  ensures: off < 0 => result is Err;
  ensures: data.len() - off < 2 => result is Err;
  ensures: result is Ok => result.value >= 0;
{
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_int(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_ABANDON_REQUEST {
    return _err_int(_at("ber: tag mismatch", off));
  }
  let vr = _int_content(data, t.content, t.len, off);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let v: Int = vr.value;
  if v < 0 {
    return _err_int(_at("ldap: negative abandon id", off));
  }
  return _ok_int(v);
}

/// Encode a minimal BindRequest (simple authentication) as a protocolOp TLV
/// (tag 0x60): SEQUENCE { INTEGER version, OCTET STRING name, 0x80 password }.
/// `version` must be 1..127 and `name` must be printable ASCII.
/// Errors (no offsets; encoder): `ldap: bad bind version`,
/// `ldap: non-printable string`.
/// Complexity: O(name + password bytes).
pub fn ldap_bind_request_encode(version: Int, name: Str, password: &Vec[UInt8]) -> Result[Vec[UInt8], Str]
  ensures: version < 1 || version > 127 => result is Err;
  ensures: result is Ok => version >= 1 && version <= 127;
{
  if version < 1 || version > 127 {
    return _err_bytes("ldap: bad bind version");
  }
  let nb: Vec[UInt8] = _str_bytes(name);
  if !_bytes_printable(&nb) {
    return _err_bytes("ldap: non-printable string");
  }
  var body = Vec[UInt8].new();
  _push_bytes(&mut body, &ber_int_encode(version));
  _push_bytes(&mut body, &ber_octet_string_encode(&nb));
  _push_bytes(&mut body, &_wrap_tlv(LDAP_AUTH_SIMPLE, password));
  return _ok_bytes(_wrap_tlv(LDAP_OP_BIND_REQUEST, &body));
}

// --------------------------------------------------
//  Results
// --------------------------------------------------

// Parse the LDAPResult field set of the response TLV `t`; `sasl_ok` accepts
// the BindResponse [7] serverSaslCreds and `ext_ok` the ExtendedResponse
// [10]/[11] fields. Reports at `off` where the response itself begins.
fn _result_parse(data: &Vec[UInt8], off: Int, t: &BerTlv, sasl_ok: Bool, ext_ok: Bool) -> Result[LdapResult, Str] {
  let er = _enum_in(data, t.content, t.next);
  if !er.is_ok {
    return _err_result(er.error);
  }
  let eb: BerEnum = er.value;
  let result_code: Int = eb.value;
  if result_code < 0 {
    return _err_result(_at("ldap: negative result code", t.content));
  }
  let md = _ldap_str_in(data, eb.next, t.next);
  if !md.is_ok {
    return _err_result(md.error);
  }
  let mb: LdapStr = md.value;
  let matched_dn: Str = mb.value;
  let dg = _ldap_str_in(data, mb.next, t.next);
  if !dg.is_ok {
    return _err_result(dg.error);
  }
  let db: LdapStr = dg.value;
  let diagnostic: Str = db.value;
  var pos: Int = db.next;
  var has_referral = false;
  var referrals = Vec[Str].new();
  if pos < t.next {
    let peek: Int = _byte(data, pos);
    if peek == LDAP_TAG_REFERRAL {
      let rr = _tlv_in(data, pos, t.next);
      if !rr.is_ok {
        return _err_result(rr.error);
      }
      let rt: BerTlv = rr.value;
      var rpos: Int = rt.content;
      while rpos < rt.next {
        let ur = _ldap_str_in(data, rpos, rt.next);
        if !ur.is_ok {
          return _err_result(ur.error);
        }
        let ub: LdapStr = ur.value;
        referrals.push(ub.value);
        rpos = ub.next;
      }
      if referrals.len() == 0 {
        return _err_result(_at("ldap: empty referral", pos));
      }
      has_referral = true;
      pos = rt.next;
    }
  }
  var has_sasl = false;
  var sasl_creds = Vec[UInt8].new();
  if sasl_ok && pos < t.next {
    let peek: Int = _byte(data, pos);
    if peek == LDAP_TAG_SASL_CREDS {
      let sr = _tlv_in(data, pos, t.next);
      if !sr.is_ok {
        return _err_result(sr.error);
      }
      let st: BerTlv = sr.value;
      sasl_creds = _copy_bytes(data, st.content, st.len);
      has_sasl = true;
      pos = st.next;
    }
  }
  var has_response_name = false;
  var response_name = "";
  if ext_ok && pos < t.next {
    let peek: Int = _byte(data, pos);
    if peek == LDAP_TAG_RESPONSE_NAME {
      let nr = _tlv_in(data, pos, t.next);
      if !nr.is_ok {
        return _err_result(nr.error);
      }
      let nt: BerTlv = nr.value;
      let ns = _ldap_str_raw(data, nt.content, nt.len, pos);
      if !ns.is_ok {
        return _err_result(ns.error);
      }
      let nv: Str = ns.value;
      response_name = nv;
      has_response_name = true;
      pos = nt.next;
    }
  }
  var has_response_value = false;
  var response_value = Vec[UInt8].new();
  if ext_ok && pos < t.next {
    let peek: Int = _byte(data, pos);
    if peek == LDAP_TAG_RESPONSE_VALUE {
      let vr = _tlv_in(data, pos, t.next);
      if !vr.is_ok {
        return _err_result(vr.error);
      }
      let vt: BerTlv = vr.value;
      response_value = _copy_bytes(data, vt.content, vt.len);
      has_response_value = true;
      pos = vt.next;
    }
  }
  if pos != t.next {
    return _err_result(_at("ldap: trailing bytes", pos));
  }
  return _ok_result(LdapResult{
    result_code: result_code;
    matched_dn: matched_dn;
    diagnostic: diagnostic;
    has_referral: has_referral;
    referrals: referrals;
    has_sasl_creds: has_sasl;
    sasl_creds: sasl_creds;
    has_response_name: has_response_name;
    response_name: response_name;
    has_response_value: has_response_value;
    response_value: response_value;
    next: t.next;
  });
}

/// Parse a BindResponse at `off` (tag 0x61): LDAPResult plus the optional [7]
/// serverSaslCreds. See `_result_parse` for the shared error catalog.
/// Complexity: O(response bytes).
pub fn ldap_bind_response_parse(data: &Vec[UInt8], off: Int) -> Result[LdapResult, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_result(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_BIND_RESPONSE {
    return _err_result(_at("ber: tag mismatch", off));
  }
  return _result_parse(data, off, &t, true, false);
}

/// Parse any plain response at `off`: SearchResultDone 0x65, ModifyResponse
/// 0x67, AddResponse 0x69, DelResponse 0x6B, ModifyDNResponse 0x6D or
/// CompareResponse 0x6F (LDAPResult only). See `_result_parse` for the shared
/// error catalog.
/// Complexity: O(response bytes).
pub fn ldap_result_parse(data: &Vec[UInt8], off: Int) -> Result[LdapResult, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_result(tr.error);
  }
  let t: BerTlv = tr.value;
  let tag: Int = t.tag;
  if tag != LDAP_OP_SEARCH_DONE && tag != LDAP_OP_MODIFY_RESPONSE && tag != LDAP_OP_ADD_RESPONSE && tag != LDAP_OP_DEL_RESPONSE && tag != LDAP_OP_MODIFY_DN_RESPONSE && tag != LDAP_OP_COMPARE_RESPONSE {
    return _err_result(_at("ber: tag mismatch", off));
  }
  return _result_parse(data, off, &t, false, false);
}

/// Parse an ExtendedResponse at `off` (tag 0x78): LDAPResult plus the
/// optional [10] responseName and [11] responseValue. See `_result_parse`
/// for the shared error catalog.
/// Complexity: O(response bytes).
pub fn ldap_extended_response_parse(data: &Vec[UInt8], off: Int) -> Result[LdapResult, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_result(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_EXTENDED_RESPONSE {
    return _err_result(_at("ber: tag mismatch", off));
  }
  return _result_parse(data, off, &t, false, true);
}

// --------------------------------------------------
//  Attribute lists
// --------------------------------------------------

// Parse one PartialAttribute SEQUENCE at `off` bounded by `end` and append
// its type / value-index bookkeeping to the parallel arrays.
fn _partial_attr_parse(data: &Vec[UInt8], off: Int, end: Int, names: &mut Vec[Str], first_value: &mut Vec[Int], value_count: &mut Vec[Int], value_offsets: &mut Vec[Int], value_lengths: &mut Vec[Int]) -> Result[Int, Str] {
  let sr = _tlv_in(data, off, end);
  if !sr.is_ok {
    return _err_int(sr.error);
  }
  let s: BerTlv = sr.value;
  if s.tag != BER_TAG_SEQUENCE {
    return _err_int(_at("ber: tag mismatch", off));
  }
  let tr = _ldap_str_in(data, s.content, s.next);
  if !tr.is_ok {
    return _err_int(tr.error);
  }
  let ty: LdapStr = tr.value;
  let vr = _tlv_in(data, ty.next, s.next);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let vals: BerTlv = vr.value;
  if vals.tag != BER_TAG_SET {
    return _err_int(_at("ber: tag mismatch", ty.next));
  }
  let base: Int = value_offsets.len();
  var pos: Int = vals.content;
  var count = 0;
  while pos < vals.next {
    let xr = _tlv_in(data, pos, vals.next);
    if !xr.is_ok {
      return _err_int(xr.error);
    }
    let x: BerTlv = xr.value;
    if x.tag != BER_TAG_OCTET_STRING {
      return _err_int(_at("ber: tag mismatch", pos));
    }
    value_offsets.push(x.content);
    value_lengths.push(x.len);
    count = count + 1;
    pos = x.next;
  }
  if pos != vals.next {
    return _err_int(_at("ldap: trailing bytes", pos));
  }
  names.push(ty.value);
  first_value.push(base);
  value_count.push(count);
  return _ok_int(s.next);
}

// Parse a PartialAttributeList SEQUENCE at `off` bounded by `end`.
fn _attr_list_parse(data: &Vec[UInt8], off: Int, end: Int) -> Result[LdapAttributeList, Str] {
  let sr = _tlv_in(data, off, end);
  if !sr.is_ok {
    return _err_attrs(sr.error);
  }
  let s: BerTlv = sr.value;
  if s.tag != BER_TAG_SEQUENCE {
    return _err_attrs(_at("ber: tag mismatch", off));
  }
  var names = Vec[Str].new();
  var first_value = Vec[Int].new();
  var value_count = Vec[Int].new();
  var value_offsets = Vec[Int].new();
  var value_lengths = Vec[Int].new();
  var pos: Int = s.content;
  while pos < s.next {
    let pr = _partial_attr_parse(data, pos, s.next, &mut names, &mut first_value, &mut value_count, &mut value_offsets, &mut value_lengths);
    if !pr.is_ok {
      return _err_attrs(pr.error);
    }
    let nx: Int = pr.value;
    if nx <= pos {
      return _err_attrs(_at("ldap: bad attribute list", pos));
    }
    pos = nx;
  }
  if pos != s.next {
    return _err_attrs(_at("ldap: trailing bytes", pos));
  }
  return _ok_attrs(LdapAttributeList{
    names: names;
    first_value: first_value;
    value_count: value_count;
    value_offsets: value_offsets;
    value_lengths: value_lengths;
    next: s.next;
  });
}

/// Parse a PartialAttributeList at `off`: SEQUENCE OF SEQUENCE { type
/// AttributeDescription, vals SET OF AttributeValue }. Attribute values are
/// left in the source buffer as offset/length pairs (copy them with
/// `ldap_bytes_copy`).
/// Errors: the BER catalogs; `ber: tag mismatch` when the list or an element
/// or the value SET is not a SEQUENCE/SET; `ldap: non-printable string` for
/// a non-printable attribute type; and `ldap: trailing bytes` inside the
/// list.
/// Complexity: O(list bytes).
pub fn ldap_attribute_list_parse(data: &Vec[UInt8], off: Int) -> Result[LdapAttributeList, Str] {
  return _attr_list_parse(data, off, data.len());
}

// --------------------------------------------------
//  Filters (flat tree)
// --------------------------------------------------

// Fresh empty filter tree.
fn _filter_new() -> LdapFilter {
  return LdapFilter{
    kinds: Vec[Int].new();
    parents: Vec[Int].new();
    depths: Vec[Int].new();
    first_child: Vec[Int].new();
    child_count: Vec[Int].new();
    attrs: Vec[Str].new();
    val_offsets: Vec[Int].new();
    val_lengths: Vec[Int].new();
    sub_first: Vec[Int].new();
    sub_count: Vec[Int].new();
    rules: Vec[Str].new();
    dn_attrs: Vec[Int].new();
    part_kinds: Vec[Int].new();
    part_offsets: Vec[Int].new();
    part_lengths: Vec[Int].new();
    next: 0;
  };
}

// Append one node to every parallel array and link it to `parent`; returns
// the new node index. Every push is mirrored so the arrays never drift.
fn _fnode_add(f: &mut LdapFilter, kind: Int, parent: Int, depth: Int) -> Int {
  let idx: Int = f.kinds.len();
  f.kinds.push(kind);
  f.parents.push(parent);
  f.depths.push(depth);
  f.first_child.push(-1);
  f.child_count.push(0);
  f.attrs.push("");
  f.val_offsets.push(0);
  f.val_lengths.push(0);
  f.sub_first.push(0);
  f.sub_count.push(0);
  f.rules.push("");
  f.dn_attrs.push(0);
  if parent >= 0 {
    let cc: Int = f.child_count[parent];
    if cc == 0 {
      f.first_child[parent] = idx;
    }
    f.child_count[parent] = cc + 1;
  }
  return idx;
}

// Flat node kind for a wire filter tag, or -1.
fn _filter_kind(tag: Int) -> Int {
  if tag == LDAP_FILTER_AND { return LDAP_FILTER_KIND_AND; }
  if tag == LDAP_FILTER_OR { return LDAP_FILTER_KIND_OR; }
  if tag == LDAP_FILTER_NOT { return LDAP_FILTER_KIND_NOT; }
  if tag == LDAP_FILTER_EQUALITY { return LDAP_FILTER_KIND_EQUALITY; }
  if tag == LDAP_FILTER_SUBSTRINGS { return LDAP_FILTER_KIND_SUBSTRINGS; }
  if tag == LDAP_FILTER_GREATER_OR_EQUAL { return LDAP_FILTER_KIND_GREATER_OR_EQUAL; }
  if tag == LDAP_FILTER_LESS_OR_EQUAL { return LDAP_FILTER_KIND_LESS_OR_EQUAL; }
  if tag == LDAP_FILTER_PRESENT { return LDAP_FILTER_KIND_PRESENT; }
  if tag == LDAP_FILTER_APPROX { return LDAP_FILTER_KIND_APPROX; }
  if tag == LDAP_FILTER_EXTENSIBLE { return LDAP_FILTER_KIND_EXTENSIBLE; }
  return -1;
}

// AttributeValueAssertion content (implicit [3]/[5]/[6]/[8]): an
// AttributeDescription TLV followed by an AssertionValue TLV.
fn _filter_ava_parse(f: &mut LdapFilter, idx: Int, data: &Vec[UInt8], off: Int, end: Int) -> Result[Int, Str] {
  let ar = _ldap_str_in(data, off, end);
  if !ar.is_ok {
    return _err_int(ar.error);
  }
  let a: LdapStr = ar.value;
  let vr = _tlv_in(data, a.next, end);
  if !vr.is_ok {
    return _err_int(vr.error);
  }
  let vt: BerTlv = vr.value;
  if vt.tag != BER_TAG_OCTET_STRING {
    return _err_int(_at("ber: tag mismatch", a.next));
  }
  f.attrs[idx] = a.value;
  f.val_offsets[idx] = vt.content;
  f.val_lengths[idx] = vt.len;
  return _ok_int(vt.next);
}

// SubstringFilter content (implicit [4]): an AttributeDescription TLV
// followed by a SEQUENCE OF CHOICE { initial [0], any [1], final [2] }. The
// initial part may only be first and the final part only last.
fn _filter_substr_parse(f: &mut LdapFilter, idx: Int, data: &Vec[UInt8], t: &BerTlv, base: Int) -> Result[Int, Str] {
  let ar = _ldap_str_in(data, t.content, t.next);
  if !ar.is_ok {
    return _err_int(ar.error);
  }
  let a: LdapStr = ar.value;
  let sr = _tlv_in(data, a.next, t.next);
  if !sr.is_ok {
    return _err_int(sr.error);
  }
  let s: BerTlv = sr.value;
  if s.tag != BER_TAG_SEQUENCE {
    return _err_int(_at("ber: tag mismatch", a.next));
  }
  let first: Int = f.part_kinds.len();
  var pos: Int = s.content;
  var count = 0;
  var seen_final = false;
  while pos < s.next {
    let pr = _tlv_in(data, pos, s.next);
    if !pr.is_ok {
      return _err_int(pr.error);
    }
    let p: BerTlv = pr.value;
    let pt: Int = p.tag;
    if pt != LDAP_SUBSTR_INITIAL && pt != LDAP_SUBSTR_ANY && pt != LDAP_SUBSTR_FINAL {
      return _err_int(_at("ldap: bad substring filter", pos));
    }
    if pt == LDAP_SUBSTR_INITIAL && count != 0 {
      return _err_int(_at("ldap: bad substring filter", pos));
    }
    if seen_final {
      return _err_int(_at("ldap: bad substring filter", pos));
    }
    if pt == LDAP_SUBSTR_FINAL {
      seen_final = true;
    }
    f.part_kinds.push(pt);
    f.part_offsets.push(p.content);
    f.part_lengths.push(p.len);
    count = count + 1;
    pos = p.next;
  }
  if count == 0 {
    return _err_int(_at("ldap: bad substring filter", base));
  }
  f.attrs[idx] = a.value;
  f.sub_first[idx] = first;
  f.sub_count[idx] = count;
  return _ok_int(s.next);
}

// MatchingRuleAssertion content (implicit [9]): optional matchingRule [1],
// optional type [2], required matchValue [3], optional dnAttributes [4], in
// that order.
fn _filter_ext_parse(f: &mut LdapFilter, idx: Int, data: &Vec[UInt8], t: &BerTlv, base: Int) -> Result[Int, Str] {
  var pos: Int = t.content;
  var rule = "";
  var attr = "";
  var v_off = 0;
  var v_len = 0;
  var has_value = false;
  var dn_attrs = 0;
  if pos < t.next {
    let peek: Int = _byte(data, pos);
    if peek == LDAP_EXT_MATCHING_RULE {
      let r = _tlv_in(data, pos, t.next);
      if !r.is_ok {
        return _err_int(r.error);
      }
      let x: BerTlv = r.value;
      let sr = _ldap_str_raw(data, x.content, x.len, pos);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      let sv: Str = sr.value;
      rule = sv;
      pos = x.next;
    }
  }
  if pos < t.next {
    let peek: Int = _byte(data, pos);
    if peek == LDAP_EXT_TYPE {
      let r = _tlv_in(data, pos, t.next);
      if !r.is_ok {
        return _err_int(r.error);
      }
      let x: BerTlv = r.value;
      let sr = _ldap_str_raw(data, x.content, x.len, pos);
      if !sr.is_ok {
        return _err_int(sr.error);
      }
      let sv: Str = sr.value;
      attr = sv;
      pos = x.next;
    }
  }
  if pos < t.next {
    let peek: Int = _byte(data, pos);
    if peek == LDAP_EXT_MATCH_VALUE {
      let r = _tlv_in(data, pos, t.next);
      if !r.is_ok {
        return _err_int(r.error);
      }
      let x: BerTlv = r.value;
      v_off = x.content;
      v_len = x.len;
      has_value = true;
      pos = x.next;
    }
  }
  if !has_value {
    return _err_int(_at("ldap: bad extensible match", base));
  }
  if pos < t.next {
    let peek: Int = _byte(data, pos);
    if peek == LDAP_EXT_DN_ATTRIBUTES {
      let r = _tlv_in(data, pos, t.next);
      if !r.is_ok {
        return _err_int(r.error);
      }
      let x: BerTlv = r.value;
      if x.len != 1 {
        return _err_int(_at("ber: bad boolean", pos));
      }
      let bv: Int = _byte(data, x.content);
      if bv != 0 {
        dn_attrs = 1;
      }
      pos = x.next;
    }
  }
  if pos != t.next {
    return _err_int(_at("ldap: trailing bytes", pos));
  }
  f.attrs[idx] = attr;
  f.rules[idx] = rule;
  f.dn_attrs[idx] = dn_attrs;
  f.val_offsets[idx] = v_off;
  f.val_lengths[idx] = v_len;
  return _ok_int(t.next);
}

// Recursive filter parser: appends nodes to `f`, returns the offset just
// past the filter TLV. `depth` is the node's ancestor count; the root is 0.
fn _filter_parse_into(f: &mut LdapFilter, data: &Vec[UInt8], off: Int, end: Int, parent: Int, depth: Int) -> Result[Int, Str] {
  if depth > LDAP_MAX_FILTER_DEPTH {
    return _err_int(_at("ldap: filter too deeply nested", off));
  }
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_int(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.next > end {
    return _err_int(_at("ber: value overruns container", off));
  }
  let tag: Int = t.tag;
  let kind: Int = _filter_kind(tag);
  if kind < 0 {
    return _err_int(_at("ldap: bad filter tag", off));
  }
  let idx: Int = _fnode_add(f, kind, parent, depth);
  if tag == LDAP_FILTER_AND || tag == LDAP_FILTER_OR {
    var pos: Int = t.content;
    var count = 0;
    while pos < t.next {
      let r = _filter_parse_into(f, data, pos, t.next, idx, depth + 1);
      if !r.is_ok {
        return _err_int(r.error);
      }
      let nx: Int = r.value;
      if nx <= pos {
        return _err_int(_at("ldap: bad filter", pos));
      }
      pos = nx;
      count = count + 1;
    }
    if count == 0 {
      return _err_int(_at("ldap: empty and/or filter", off));
    }
    return _ok_int(t.next);
  }
  if tag == LDAP_FILTER_NOT {
    if t.len == 0 {
      return _err_int(_at("ldap: bad not filter", off));
    }
    let r = _filter_parse_into(f, data, t.content, t.next, idx, depth + 1);
    if !r.is_ok {
      return _err_int(r.error);
    }
    let nx: Int = r.value;
    if nx != t.next {
      return _err_int(_at("ldap: trailing bytes", nx));
    }
    return _ok_int(t.next);
  }
  if tag == LDAP_FILTER_EQUALITY || tag == LDAP_FILTER_GREATER_OR_EQUAL || tag == LDAP_FILTER_LESS_OR_EQUAL || tag == LDAP_FILTER_APPROX {
    let r = _filter_ava_parse(f, idx, data, t.content, t.next);
    if !r.is_ok {
      return _err_int(r.error);
    }
    let nx: Int = r.value;
    if nx != t.next {
      return _err_int(_at("ldap: trailing bytes", nx));
    }
    return _ok_int(t.next);
  }
  if tag == LDAP_FILTER_PRESENT {
    let r = _ldap_str_raw(data, t.content, t.len, off);
    if !r.is_ok {
      return _err_int(r.error);
    }
    let v: Str = r.value;
    f.attrs[idx] = v;
    return _ok_int(t.next);
  }
  if tag == LDAP_FILTER_SUBSTRINGS {
    let r = _filter_substr_parse(f, idx, data, &t, off);
    if !r.is_ok {
      return _err_int(r.error);
    }
    let nx: Int = r.value;
    if nx != t.next {
      return _err_int(_at("ldap: trailing bytes", nx));
    }
    return _ok_int(t.next);
  }
  if tag == LDAP_FILTER_EXTENSIBLE {
    let r = _filter_ext_parse(f, idx, data, &t, off);
    if !r.is_ok {
      return _err_int(r.error);
    }
    return _ok_int(t.next);
  }
  return _err_int(_at("ldap: bad filter tag", off));
}

/// Parse one filter at `off` into a flat tree. Node i: kinds[i] is a
/// LDAP_FILTER_KIND_* value, parents[i] its parent index (-1 for the root),
/// depths[i] its ancestor count; and/or/not nodes expose their children
/// through first_child[i]/child_count[i]; item nodes expose attrs[i] and the
/// raw assertion value bounds val_offsets[i]/val_lengths[i]; substring nodes
/// expose sub_first[i]/sub_count[i] into the part_* arrays; extensible nodes
/// expose rules[i] and dn_attrs[i].
///
/// Errors: the BER catalogs; `ber: tag mismatch` for a wrong nested type;
/// `ldap: bad filter tag` for an unknown choice tag; `ldap: empty and/or
/// filter`; `ldap: bad not filter` for an empty not; `ldap: bad substring
/// filter` for bad part order or an empty part list; `ldap: bad extensible
/// match` when matchValue is missing; `ldap: trailing bytes` when a node
/// declares more bytes than its fields consume; and `ldap: filter too deeply
/// nested` beyond LDAP_MAX_FILTER_DEPTH ancestors.
/// Complexity: O(filter bytes).
pub fn ldap_filter_parse(data: &Vec[UInt8], off: Int) -> Result[LdapFilter, Str] {
  var f = _filter_new();
  let r = _filter_parse_into(&mut f, data, off, data.len(), -1, 0);
  if !r.is_ok {
    return _err_filter(r.error);
  }
  let nx: Int = r.value;
  f.next = nx;
  return _ok_filter(f);
}

// --------------------------------------------------
//  Search operations
// --------------------------------------------------

/// Parse a SearchRequest at `off` (tag 0x63): SEQUENCE { baseObject,
/// scope ENUMERATED (0..2), derefAliases ENUMERATED (0..3), sizeLimit,
/// timeLimit, typesOnly BOOLEAN, filter, attributes SEQUENCE OF LDAPString }.
/// The filter is decoded into `filter` (and also bounded by
/// `filter_offset`/`filter_length`); attribute names are validated printable.
///
/// Errors: the BER catalogs; `ber: tag mismatch` at `off`; the filter
/// catalog; `ldap: bad scope` / `ldap: bad deref aliases` at the offending
/// ENUMERATED; `ldap: negative integer` for a negative limit; and
/// `ldap: trailing bytes` inside the request.
/// Complexity: O(request bytes + filter nodes).
pub fn ldap_search_request_parse(data: &Vec[UInt8], off: Int) -> Result[LdapSearchRequest, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_search(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_SEARCH_REQUEST {
    return _err_search(_at("ber: tag mismatch", off));
  }
  let br = _ldap_str_in(data, t.content, t.next);
  if !br.is_ok {
    return _err_search(br.error);
  }
  let b: LdapStr = br.value;
  let base_object: Str = b.value;
  let srr = _enum_in(data, b.next, t.next);
  if !srr.is_ok {
    return _err_search(srr.error);
  }
  let sr: BerEnum = srr.value;
  let scope: Int = sr.value;
  if scope < 0 || scope > 2 {
    return _err_search(_at("ldap: bad scope", b.next));
  }
  let drr = _enum_in(data, sr.next, t.next);
  if !drr.is_ok {
    return _err_search(drr.error);
  }
  let dr: BerEnum = drr.value;
  let deref_aliases: Int = dr.value;
  if deref_aliases < 0 || deref_aliases > 3 {
    return _err_search(_at("ldap: bad deref aliases", sr.next));
  }
  let szr = _int_in(data, dr.next, t.next);
  if !szr.is_ok {
    return _err_search(szr.error);
  }
  let sz: BerInt = szr.value;
  let size_limit: Int = sz.value;
  if size_limit < 0 {
    return _err_search(_at("ldap: negative integer", dr.next));
  }
  let tlr = _int_in(data, sz.next, t.next);
  if !tlr.is_ok {
    return _err_search(tlr.error);
  }
  let tl: BerInt = tlr.value;
  let time_limit: Int = tl.value;
  if time_limit < 0 {
    return _err_search(_at("ldap: negative integer", sz.next));
  }
  let tyr = _bool_in(data, tl.next, t.next);
  if !tyr.is_ok {
    return _err_search(tyr.error);
  }
  let tyb: BerBool = tyr.value;
  var types_only = false;
  if tyb.value != 0 {
    types_only = true;
  }
  let filter_off: Int = tyb.next;
  var filt = _filter_new();
  let fr = _filter_parse_into(&mut filt, data, filter_off, t.next, -1, 0);
  if !fr.is_ok {
    return _err_search(fr.error);
  }
  let filter_next: Int = fr.value;
  filt.next = filter_next;
  let ar = _tlv_in(data, filter_next, t.next);
  if !ar.is_ok {
    return _err_search(ar.error);
  }
  let at: BerTlv = ar.value;
  if at.tag != BER_TAG_SEQUENCE {
    return _err_search(_at("ber: tag mismatch", filter_next));
  }
  var attrs = Vec[Str].new();
  var apos: Int = at.content;
  while apos < at.next {
    let xr = _ldap_str_in(data, apos, at.next);
    if !xr.is_ok {
      return _err_search(xr.error);
    }
    let x: LdapStr = xr.value;
    attrs.push(x.value);
    apos = x.next;
  }
  if apos != at.next {
    return _err_search(_at("ldap: trailing bytes", apos));
  }
  if at.next != t.next {
    return _err_search(_at("ldap: trailing bytes", at.next));
  }
  return _ok_search(LdapSearchRequest{
    base_object: base_object;
    scope: scope;
    deref_aliases: deref_aliases;
    size_limit: size_limit;
    time_limit: time_limit;
    types_only: types_only;
    filter_offset: filter_off;
    filter_length: filter_next - filter_off;
    filter: filt;
    attributes: attrs;
    next: t.next;
  });
}

/// Parse a SearchResultEntry at `off` (tag 0x64): SEQUENCE { objectName
/// LDAPDN, attributes PartialAttributeList }.
/// Errors: the BER catalogs; `ber: tag mismatch` at `off`; the attribute
/// list catalog; `ldap: trailing bytes` inside the entry.
/// Complexity: O(entry bytes).
pub fn ldap_search_entry_parse(data: &Vec[UInt8], off: Int) -> Result[LdapSearchEntry, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_entry(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_SEARCH_ENTRY {
    return _err_entry(_at("ber: tag mismatch", off));
  }
  let nr = _ldap_str_in(data, t.content, t.next);
  if !nr.is_ok {
    return _err_entry(nr.error);
  }
  let nb: LdapStr = nr.value;
  let alr = _attr_list_parse(data, nb.next, t.next);
  if !alr.is_ok {
    return _err_entry(alr.error);
  }
  let al: LdapAttributeList = alr.value;
  if al.next != t.next {
    return _err_entry(_at("ldap: trailing bytes", al.next));
  }
  return _ok_entry(LdapSearchEntry{
    object_name: nb.value;
    attrs: al;
    next: t.next;
  });
}

/// Encode a minimal SearchRequest with one equality filter as a protocolOp
/// TLV (tag 0x63). The request carries baseObject, scope, derefAliases,
/// sizeLimit, timeLimit, typesOnly, the filter (attributeDesc `attr` +
/// assertionValue `value`) and the AttributeSelection `attributes`.
/// `scope` must be 0..2, `deref_aliases` 0..3, the limits non-negative, and
/// base/attr/attributes printable ASCII.
/// Errors (no offsets; encoder): `ldap: bad scope`,
/// `ldap: bad deref aliases`, `ldap: negative integer`,
/// `ldap: non-printable string`.
/// Complexity: O(request bytes).
pub fn ldap_search_request_encode(base: Str, scope: Int, deref_aliases: Int, size_limit: Int, time_limit: Int, types_only: Bool, attr: Str, value: &Vec[UInt8], attributes: &Vec[Str]) -> Result[Vec[UInt8], Str]
  ensures: scope < 0 || scope > 2 => result is Err;
  ensures: deref_aliases < 0 || deref_aliases > 3 => result is Err;
  ensures: size_limit < 0 || time_limit < 0 => result is Err;
  ensures: result is Ok => scope >= 0 && scope <= 2 && deref_aliases >= 0 && deref_aliases <= 3 && size_limit >= 0 && time_limit >= 0;
{
  if scope < 0 || scope > 2 {
    return _err_bytes("ldap: bad scope");
  }
  if deref_aliases < 0 || deref_aliases > 3 {
    return _err_bytes("ldap: bad deref aliases");
  }
  if size_limit < 0 || time_limit < 0 {
    return _err_bytes("ldap: negative integer");
  }
  let bb: Vec[UInt8] = _str_bytes(base);
  if !_bytes_printable(&bb) {
    return _err_bytes("ldap: non-printable string");
  }
  let ab: Vec[UInt8] = _str_bytes(attr);
  if !_bytes_printable(&ab) {
    return _err_bytes("ldap: non-printable string");
  }
  var fbody = Vec[UInt8].new();
  _push_bytes(&mut fbody, &ber_octet_string_encode(&ab));
  _push_bytes(&mut fbody, &ber_octet_string_encode(value));
  let filt = _wrap_tlv(LDAP_FILTER_EQUALITY, &fbody);
  var alist = Vec[UInt8].new();
  var i = 0;
  while i < attributes.len() {
    let a: Str = attributes[i];
    let ab2: Vec[UInt8] = _str_bytes(a);
    if !_bytes_printable(&ab2) {
      return _err_bytes("ldap: non-printable string");
    }
    _push_bytes(&mut alist, &ber_octet_string_encode(&ab2));
    i = i + 1;
  }
  var body = Vec[UInt8].new();
  _push_bytes(&mut body, &ber_octet_string_encode(&bb));
  _push_bytes(&mut body, &ber_enum_encode(scope));
  _push_bytes(&mut body, &ber_enum_encode(deref_aliases));
  _push_bytes(&mut body, &ber_int_encode(size_limit));
  _push_bytes(&mut body, &ber_int_encode(time_limit));
  _push_bytes(&mut body, &ber_bool_encode(types_only));
  _push_bytes(&mut body, &filt);
  _push_bytes(&mut body, &_wrap_tlv(BER_TAG_SEQUENCE, &alist));
  return _ok_bytes(_wrap_tlv(LDAP_OP_SEARCH_REQUEST, &body));
}

// --------------------------------------------------
//  Update operations
// --------------------------------------------------

// Parse a SEQUENCE OF change at `off` bounded by `end`: each change is
// SEQUENCE { operation ENUMERATED (0..2), modification PartialAttribute }.
fn _changes_parse(data: &Vec[UInt8], off: Int, end: Int) -> Result[LdapChanges, Str] {
  let sr = _tlv_in(data, off, end);
  if !sr.is_ok {
    return _err_changes(sr.error);
  }
  let s: BerTlv = sr.value;
  if s.tag != BER_TAG_SEQUENCE {
    return _err_changes(_at("ber: tag mismatch", off));
  }
  var ops = Vec[Int].new();
  var names = Vec[Str].new();
  var first_value = Vec[Int].new();
  var value_count = Vec[Int].new();
  var value_offsets = Vec[Int].new();
  var value_lengths = Vec[Int].new();
  var pos: Int = s.content;
  while pos < s.next {
    let cr = _tlv_in(data, pos, s.next);
    if !cr.is_ok {
      return _err_changes(cr.error);
    }
    let c: BerTlv = cr.value;
    if c.tag != BER_TAG_SEQUENCE {
      return _err_changes(_at("ber: tag mismatch", pos));
    }
    let er = _enum_in(data, c.content, c.next);
    if !er.is_ok {
      return _err_changes(er.error);
    }
    let eb: BerEnum = er.value;
    let op: Int = eb.value;
    if op < 0 || op > 2 {
      return _err_changes(_at("ldap: bad modify operation", c.content));
    }
    let pr = _partial_attr_parse(data, eb.next, c.next, &mut names, &mut first_value, &mut value_count, &mut value_offsets, &mut value_lengths);
    if !pr.is_ok {
      return _err_changes(pr.error);
    }
    let nx: Int = pr.value;
    if nx != c.next {
      return _err_changes(_at("ldap: trailing bytes", nx));
    }
    ops.push(op);
    pos = c.next;
  }
  if pos != s.next {
    return _err_changes(_at("ldap: trailing bytes", pos));
  }
  return _ok_changes(LdapChanges{
    ops: ops;
    names: names;
    first_value: first_value;
    value_count: value_count;
    value_offsets: value_offsets;
    value_lengths: value_lengths;
    next: s.next;
  });
}

/// Parse a ModifyRequest at `off` (tag 0x66): SEQUENCE { object LDAPDN,
/// changes SEQUENCE OF change }. `ops[i]` is 0 add, 1 delete or 2 replace;
/// values are offset/length pairs into the source buffer.
/// Errors: the BER catalogs; `ber: tag mismatch` at `off` and for a
/// non-SEQUENCE change; `ldap: bad modify operation` for an operation
/// outside 0..2; the attribute/string catalogs; and `ldap: trailing bytes`
/// inside a change or the request.
/// Complexity: O(request bytes).
pub fn ldap_modify_request_parse(data: &Vec[UInt8], off: Int) -> Result[LdapModifyRequest, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_modify(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_MODIFY_REQUEST {
    return _err_modify(_at("ber: tag mismatch", off));
  }
  let orr = _ldap_str_in(data, t.content, t.next);
  if !orr.is_ok {
    return _err_modify(orr.error);
  }
  let ob: LdapStr = orr.value;
  let chr = _changes_parse(data, ob.next, t.next);
  if !chr.is_ok {
    return _err_modify(chr.error);
  }
  let ch: LdapChanges = chr.value;
  if ch.next != t.next {
    return _err_modify(_at("ldap: trailing bytes", ch.next));
  }
  return _ok_modify(LdapModifyRequest{
    object: ob.value;
    changes: ch;
    next: t.next;
  });
}

/// Parse an AddRequest at `off` (tag 0x68): SEQUENCE { entry LDAPDN,
/// attributes PartialAttributeList }.
/// Errors: the BER catalogs; `ber: tag mismatch` at `off`; the attribute
/// list catalog; `ldap: trailing bytes` inside the request.
/// Complexity: O(request bytes).
pub fn ldap_add_request_parse(data: &Vec[UInt8], off: Int) -> Result[LdapAddRequest, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_add(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_ADD_REQUEST {
    return _err_add(_at("ber: tag mismatch", off));
  }
  let er = _ldap_str_in(data, t.content, t.next);
  if !er.is_ok {
    return _err_add(er.error);
  }
  let eb: LdapStr = er.value;
  let alr = _attr_list_parse(data, eb.next, t.next);
  if !alr.is_ok {
    return _err_add(alr.error);
  }
  let al: LdapAttributeList = alr.value;
  if al.next != t.next {
    return _err_add(_at("ldap: trailing bytes", al.next));
  }
  return _ok_add(LdapAddRequest{
    entry: eb.value;
    attrs: al;
    next: t.next;
  });
}

/// Parse a DelRequest at `off` (tag 0x4A, primitive) into the target LDAPDN;
/// the content is the implicitly tagged entry name and must be printable.
/// Errors: the BER catalogs, `ber: tag mismatch` at `off` and
/// `ldap: non-printable string`.
/// Complexity: O(DN bytes).
pub fn ldap_del_request_parse(data: &Vec[UInt8], off: Int) -> Result[LdapStr, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_lstr(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_DEL_REQUEST {
    return _err_lstr(_at("ber: tag mismatch", off));
  }
  let sr = _ldap_str_raw(data, t.content, t.len, off);
  if !sr.is_ok {
    return _err_lstr(sr.error);
  }
  let v: Str = sr.value;
  return _ok_lstr(LdapStr{ value: v; next: t.next; });
}

/// Parse a ModifyDNRequest at `off` (tag 0x6C): SEQUENCE { entry LDAPDN,
/// newrdn RelativeLDAPDN, deleteoldrdn BOOLEAN, newSuperior [0] LDAPDN
/// OPTIONAL }.
/// Errors: the BER catalogs; `ber: tag mismatch` at `off`; the string and
/// boolean catalogs; `ldap: trailing bytes` when the optional field is not
/// [0] or the request has extra bytes.
/// Complexity: O(request bytes).
pub fn ldap_modify_dn_request_parse(data: &Vec[UInt8], off: Int) -> Result[LdapModifyDnRequest, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_moddn(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_MODIFY_DN_REQUEST {
    return _err_moddn(_at("ber: tag mismatch", off));
  }
  let er = _ldap_str_in(data, t.content, t.next);
  if !er.is_ok {
    return _err_moddn(er.error);
  }
  let eb: LdapStr = er.value;
  let nr = _ldap_str_in(data, eb.next, t.next);
  if !nr.is_ok {
    return _err_moddn(nr.error);
  }
  let nb: LdapStr = nr.value;
  let dr = _bool_in(data, nb.next, t.next);
  if !dr.is_ok {
    return _err_moddn(dr.error);
  }
  let db: BerBool = dr.value;
  var delete_old_rdn = false;
  if db.value != 0 {
    delete_old_rdn = true;
  }
  var pos: Int = db.next;
  var has_new_superior = false;
  var new_superior = "";
  if pos < t.next {
    let xr = _tlv_in(data, pos, t.next);
    if !xr.is_ok {
      return _err_moddn(xr.error);
    }
    let xt: BerTlv = xr.value;
    if xt.tag != LDAP_MODDN_NEW_SUPERIOR {
      return _err_moddn(_at("ldap: trailing bytes", pos));
    }
    let sr = _ldap_str_raw(data, xt.content, xt.len, pos);
    if !sr.is_ok {
      return _err_moddn(sr.error);
    }
    let sv: Str = sr.value;
    new_superior = sv;
    has_new_superior = true;
    pos = xt.next;
  }
  if pos != t.next {
    return _err_moddn(_at("ldap: trailing bytes", pos));
  }
  return _ok_moddn(LdapModifyDnRequest{
    entry: eb.value;
    new_rdn: nb.value;
    delete_old_rdn: delete_old_rdn;
    has_new_superior: has_new_superior;
    new_superior: new_superior;
    next: t.next;
  });
}

/// Parse a CompareRequest at `off` (tag 0x6E): SEQUENCE { entry LDAPDN,
/// ava SEQUENCE { attributeDesc, assertionValue } }. The assertion value
/// stays in the source buffer as offset/length.
/// Errors: the BER catalogs; `ber: tag mismatch` at `off`, at the ava
/// SEQUENCE and at the assertion value; `ldap: trailing bytes` inside the
/// request.
/// Complexity: O(request bytes).
pub fn ldap_compare_request_parse(data: &Vec[UInt8], off: Int) -> Result[LdapCompareRequest, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_compare(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_COMPARE_REQUEST {
    return _err_compare(_at("ber: tag mismatch", off));
  }
  let er = _ldap_str_in(data, t.content, t.next);
  if !er.is_ok {
    return _err_compare(er.error);
  }
  let eb: LdapStr = er.value;
  let ar = _tlv_in(data, eb.next, t.next);
  if !ar.is_ok {
    return _err_compare(ar.error);
  }
  let ava: BerTlv = ar.value;
  if ava.tag != BER_TAG_SEQUENCE {
    return _err_compare(_at("ber: tag mismatch", eb.next));
  }
  let nr = _ldap_str_in(data, ava.content, ava.next);
  if !nr.is_ok {
    return _err_compare(nr.error);
  }
  let nb: LdapStr = nr.value;
  let vr = _tlv_in(data, nb.next, ava.next);
  if !vr.is_ok {
    return _err_compare(vr.error);
  }
  let vt: BerTlv = vr.value;
  if vt.tag != BER_TAG_OCTET_STRING {
    return _err_compare(_at("ber: tag mismatch", nb.next));
  }
  if vt.next != ava.next {
    return _err_compare(_at("ldap: trailing bytes", vt.next));
  }
  if ava.next != t.next {
    return _err_compare(_at("ldap: trailing bytes", ava.next));
  }
  return _ok_compare(LdapCompareRequest{
    entry: eb.value;
    attr: nb.value;
    value_offset: vt.content;
    value_length: vt.len;
    next: t.next;
  });
}

/// Parse a SearchResultReference at `off` (tag 0x73): the implicitly tagged
/// SEQUENCE OF LDAPURL, i.e. one or more OCTET STRING TLVs. Every URI is
/// validated printable.
/// Errors: the BER catalogs; `ber: tag mismatch` at `off`; the string
/// catalog; `ldap: empty search reference` when the list is empty.
/// Complexity: O(reference bytes).
pub fn ldap_search_reference_parse(data: &Vec[UInt8], off: Int) -> Result[LdapSearchReference, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_ref(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_SEARCH_REFERENCE {
    return _err_ref(_at("ber: tag mismatch", off));
  }
  var uris = Vec[Str].new();
  var pos: Int = t.content;
  while pos < t.next {
    let ur = _ldap_str_in(data, pos, t.next);
    if !ur.is_ok {
      return _err_ref(ur.error);
    }
    let ub: LdapStr = ur.value;
    uris.push(ub.value);
    pos = ub.next;
  }
  if uris.len() == 0 {
    return _err_ref(_at("ldap: empty search reference", off));
  }
  return _ok_ref(LdapSearchReference{ uris: uris; next: t.next; });
}

/// Parse an ExtendedRequest at `off` (tag 0x77): SEQUENCE { requestName
/// [0] LDAPOID, requestValue [1] OCTET STRING OPTIONAL }. The request name
/// is validated printable; the value stays in the source buffer as
/// offset/length.
/// Errors: the BER catalogs; `ldap: bad extended request` when requestName
/// is missing or not [0]; `ldap: non-printable string` for a bad name; and
/// `ldap: trailing bytes` when the optional field is not [1] or the request
/// has extra bytes.
/// Complexity: O(request bytes).
pub fn ldap_extended_request_parse(data: &Vec[UInt8], off: Int) -> Result[LdapExtendedRequest, Str] {
  let tr = ber_tlv_decode(data, off);
  if !tr.is_ok {
    return _err_ext(tr.error);
  }
  let t: BerTlv = tr.value;
  if t.tag != LDAP_OP_EXTENDED_REQUEST {
    return _err_ext(_at("ber: tag mismatch", off));
  }
  var pos: Int = t.content;
  if pos >= t.next {
    return _err_ext(_at("ldap: bad extended request", pos));
  }
  let nr = _tlv_in(data, pos, t.next);
  if !nr.is_ok {
    return _err_ext(nr.error);
  }
  let nt: BerTlv = nr.value;
  if nt.tag != LDAP_EXT_REQUEST_NAME {
    return _err_ext(_at("ldap: bad extended request", pos));
  }
  let nsr = _ldap_str_raw(data, nt.content, nt.len, pos);
  if !nsr.is_ok {
    return _err_ext(nsr.error);
  }
  let request_name: Str = nsr.value;
  pos = nt.next;
  var has_value = false;
  var value_offset = 0;
  var value_length = 0;
  if pos < t.next {
    let vr = _tlv_in(data, pos, t.next);
    if !vr.is_ok {
      return _err_ext(vr.error);
    }
    let vt: BerTlv = vr.value;
    if vt.tag != LDAP_EXT_REQUEST_VALUE {
      return _err_ext(_at("ldap: trailing bytes", pos));
    }
    has_value = true;
    value_offset = vt.content;
    value_length = vt.len;
    pos = vt.next;
  }
  if pos != t.next {
    return _err_ext(_at("ldap: trailing bytes", pos));
  }
  return _ok_ext(LdapExtendedRequest{
    request_name: request_name;
    has_value: has_value;
    value_offset: value_offset;
    value_length: value_length;
    next: t.next;
  });
}

// --------------------------------------------------
//  Result-code table
// --------------------------------------------------

/// RFC 4511 / IANA name for `code`, or "reserved" inside the reserved
/// ranges (37..47, 55..63, 81..112) and "unknown" otherwise.
/// Complexity: O(1).
pub fn ldap_result_code_name(code: Int) -> Str {
  if code == LDAP_RESULT_SUCCESS { return "success"; }
  if code == LDAP_RESULT_OPERATIONS_ERROR { return "operationsError"; }
  if code == LDAP_RESULT_PROTOCOL_ERROR { return "protocolError"; }
  if code == LDAP_RESULT_TIME_LIMIT_EXCEEDED { return "timeLimitExceeded"; }
  if code == LDAP_RESULT_SIZE_LIMIT_EXCEEDED { return "sizeLimitExceeded"; }
  if code == LDAP_RESULT_COMPARE_FALSE { return "compareFalse"; }
  if code == LDAP_RESULT_COMPARE_TRUE { return "compareTrue"; }
  if code == LDAP_RESULT_AUTH_METHOD_NOT_SUPPORTED { return "authMethodNotSupported"; }
  if code == LDAP_RESULT_STRONGER_AUTH_REQUIRED { return "strongerAuthRequired"; }
  if code == LDAP_RESULT_PARTIAL_RESULTS { return "partialResults"; }
  if code == LDAP_RESULT_REFERRAL { return "referral"; }
  if code == LDAP_RESULT_ADMIN_LIMIT_EXCEEDED { return "adminLimitExceeded"; }
  if code == LDAP_RESULT_UNAVAILABLE_CRITICAL_EXTENSION { return "unavailableCriticalExtension"; }
  if code == LDAP_RESULT_CONFIDENTIALITY_REQUIRED { return "confidentialityRequired"; }
  if code == LDAP_RESULT_SASL_BIND_IN_PROGRESS { return "saslBindInProgress"; }
  if code == LDAP_RESULT_NO_SUCH_ATTRIBUTE { return "noSuchAttribute"; }
  if code == LDAP_RESULT_UNDEFINED_ATTRIBUTE_TYPE { return "undefinedAttributeType"; }
  if code == LDAP_RESULT_INAPPROPRIATE_MATCHING { return "inappropriateMatching"; }
  if code == LDAP_RESULT_CONSTRAINT_VIOLATION { return "constraintViolation"; }
  if code == LDAP_RESULT_ATTRIBUTE_OR_VALUE_EXISTS { return "attributeOrValueExists"; }
  if code == LDAP_RESULT_INVALID_ATTRIBUTE_SYNTAX { return "invalidAttributeSyntax"; }
  if code == LDAP_RESULT_NO_SUCH_OBJECT { return "noSuchObject"; }
  if code == LDAP_RESULT_ALIAS_PROBLEM { return "aliasProblem"; }
  if code == LDAP_RESULT_INVALID_DN_SYNTAX { return "invalidDNSyntax"; }
  if code == LDAP_RESULT_IS_LEAF { return "isLeaf"; }
  if code == LDAP_RESULT_ALIAS_DEREFERENCING_PROBLEM { return "aliasDereferencingProblem"; }
  if code == LDAP_RESULT_INAPPROPRIATE_AUTHENTICATION { return "inappropriateAuthentication"; }
  if code == LDAP_RESULT_INVALID_CREDENTIALS { return "invalidCredentials"; }
  if code == LDAP_RESULT_INSUFFICIENT_ACCESS_RIGHTS { return "insufficientAccessRights"; }
  if code == LDAP_RESULT_BUSY { return "busy"; }
  if code == LDAP_RESULT_UNAVAILABLE { return "unavailable"; }
  if code == LDAP_RESULT_UNWILLING_TO_PERFORM { return "unwillingToPerform"; }
  if code == LDAP_RESULT_LOOP_DETECT { return "loopDetect"; }
  if code == LDAP_RESULT_NAMING_VIOLATION { return "namingViolation"; }
  if code == LDAP_RESULT_OBJECT_CLASS_VIOLATION { return "objectClassViolation"; }
  if code == LDAP_RESULT_NOT_ALLOWED_ON_NON_LEAF { return "notAllowedOnNonLeaf"; }
  if code == LDAP_RESULT_NOT_ALLOWED_ON_RDN { return "notAllowedOnRDN"; }
  if code == LDAP_RESULT_ENTRY_ALREADY_EXISTS { return "entryAlreadyExists"; }
  if code == LDAP_RESULT_OBJECT_CLASS_MODS_PROHIBITED { return "objectClassModsProhibited"; }
  if code == LDAP_RESULT_RESULTS_TOO_LARGE { return "resultsTooLarge"; }
  if code == LDAP_RESULT_AFFECTS_MULTIPLE_DSAS { return "affectsMultipleDSAs"; }
  if code == LDAP_RESULT_OTHER { return "other"; }
  if code == LDAP_RESULT_LCUP_RESOURCES_EXHAUSTED { return "lcupResourcesExhausted"; }
  if code == LDAP_RESULT_LCUP_SECURITY_VIOLATION { return "lcupSecurityViolation"; }
  if code == LDAP_RESULT_LCUP_INVALID_DATA { return "lcupInvalidData"; }
  if code == LDAP_RESULT_LCUP_UNSUPPORTED_SCHEME { return "lcupUnsupportedScheme"; }
  if code == LDAP_RESULT_LCUP_RELOAD_REQUIRED { return "lcupReloadRequired"; }
  if code == LDAP_RESULT_CANCELED { return "canceled"; }
  if code == LDAP_RESULT_NO_SUCH_OPERATION { return "noSuchOperation"; }
  if code == LDAP_RESULT_TOO_LATE { return "tooLate"; }
  if code == LDAP_RESULT_CANNOT_CANCEL { return "cannotCancel"; }
  if code == LDAP_RESULT_ASSERTION_FAILED { return "assertionFailed"; }
  if code == LDAP_RESULT_AUTHORIZATION_DENIED { return "authorizationDenied"; }
  if code == LDAP_RESULT_SYNC_REFRESH_REQUIRED { return "syncRefreshRequired"; }
  if code >= 37 && code <= 47 {
    return "reserved";
  }
  if code >= 55 && code <= 63 {
    return "reserved";
  }
  if code >= 81 && code <= 112 {
    return "reserved";
  }
  return "unknown";
}

/// True when `code` has a name in the table above (reserved ranges and
/// unknown values are false).
/// Complexity: O(1).
pub fn ldap_result_code_known(code: Int) -> Bool {
  if code == LDAP_RESULT_SUCCESS { return true; }
  if code == LDAP_RESULT_OPERATIONS_ERROR { return true; }
  if code == LDAP_RESULT_PROTOCOL_ERROR { return true; }
  if code == LDAP_RESULT_TIME_LIMIT_EXCEEDED { return true; }
  if code == LDAP_RESULT_SIZE_LIMIT_EXCEEDED { return true; }
  if code == LDAP_RESULT_COMPARE_FALSE { return true; }
  if code == LDAP_RESULT_COMPARE_TRUE { return true; }
  if code == LDAP_RESULT_AUTH_METHOD_NOT_SUPPORTED { return true; }
  if code == LDAP_RESULT_STRONGER_AUTH_REQUIRED { return true; }
  if code == LDAP_RESULT_PARTIAL_RESULTS { return true; }
  if code == LDAP_RESULT_REFERRAL { return true; }
  if code == LDAP_RESULT_ADMIN_LIMIT_EXCEEDED { return true; }
  if code == LDAP_RESULT_UNAVAILABLE_CRITICAL_EXTENSION { return true; }
  if code == LDAP_RESULT_CONFIDENTIALITY_REQUIRED { return true; }
  if code == LDAP_RESULT_SASL_BIND_IN_PROGRESS { return true; }
  if code == LDAP_RESULT_NO_SUCH_ATTRIBUTE { return true; }
  if code == LDAP_RESULT_UNDEFINED_ATTRIBUTE_TYPE { return true; }
  if code == LDAP_RESULT_INAPPROPRIATE_MATCHING { return true; }
  if code == LDAP_RESULT_CONSTRAINT_VIOLATION { return true; }
  if code == LDAP_RESULT_ATTRIBUTE_OR_VALUE_EXISTS { return true; }
  if code == LDAP_RESULT_INVALID_ATTRIBUTE_SYNTAX { return true; }
  if code == LDAP_RESULT_NO_SUCH_OBJECT { return true; }
  if code == LDAP_RESULT_ALIAS_PROBLEM { return true; }
  if code == LDAP_RESULT_INVALID_DN_SYNTAX { return true; }
  if code == LDAP_RESULT_IS_LEAF { return true; }
  if code == LDAP_RESULT_ALIAS_DEREFERENCING_PROBLEM { return true; }
  if code == LDAP_RESULT_INAPPROPRIATE_AUTHENTICATION { return true; }
  if code == LDAP_RESULT_INVALID_CREDENTIALS { return true; }
  if code == LDAP_RESULT_INSUFFICIENT_ACCESS_RIGHTS { return true; }
  if code == LDAP_RESULT_BUSY { return true; }
  if code == LDAP_RESULT_UNAVAILABLE { return true; }
  if code == LDAP_RESULT_UNWILLING_TO_PERFORM { return true; }
  if code == LDAP_RESULT_LOOP_DETECT { return true; }
  if code == LDAP_RESULT_NAMING_VIOLATION { return true; }
  if code == LDAP_RESULT_OBJECT_CLASS_VIOLATION { return true; }
  if code == LDAP_RESULT_NOT_ALLOWED_ON_NON_LEAF { return true; }
  if code == LDAP_RESULT_NOT_ALLOWED_ON_RDN { return true; }
  if code == LDAP_RESULT_ENTRY_ALREADY_EXISTS { return true; }
  if code == LDAP_RESULT_OBJECT_CLASS_MODS_PROHIBITED { return true; }
  if code == LDAP_RESULT_RESULTS_TOO_LARGE { return true; }
  if code == LDAP_RESULT_AFFECTS_MULTIPLE_DSAS { return true; }
  if code == LDAP_RESULT_OTHER { return true; }
  if code == LDAP_RESULT_LCUP_RESOURCES_EXHAUSTED { return true; }
  if code == LDAP_RESULT_LCUP_SECURITY_VIOLATION { return true; }
  if code == LDAP_RESULT_LCUP_INVALID_DATA { return true; }
  if code == LDAP_RESULT_LCUP_UNSUPPORTED_SCHEME { return true; }
  if code == LDAP_RESULT_LCUP_RELOAD_REQUIRED { return true; }
  if code == LDAP_RESULT_CANCELED { return true; }
  if code == LDAP_RESULT_NO_SUCH_OPERATION { return true; }
  if code == LDAP_RESULT_TOO_LATE { return true; }
  if code == LDAP_RESULT_CANNOT_CANCEL { return true; }
  if code == LDAP_RESULT_ASSERTION_FAILED { return true; }
  if code == LDAP_RESULT_AUTHORIZATION_DENIED { return true; }
  if code == LDAP_RESULT_SYNC_REFRESH_REQUIRED { return true; }
  return false;
}
