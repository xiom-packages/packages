// XIOM -- xiom.etcd: etcd v3 gRPC message-structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM (no FFI, no sockets, no brokers, no client state) structural
// codec for the etcd v3 gRPC wire format, operating on complete in-memory
// buffers. Reference: etcd-io/etcd `api/etcdserverpb/rpc.proto` (proto3).
// In scope:
//   * the protobuf-wire subset etcd uses: base-128 varints (u32/u64,
//     10 bytes max, overflow rejection), wire types 0 varint / 1 fixed64 /
//     2 length-delimited / 5 fixed32, field keys (field_number * 8 +
//     wire_type), length-delimited nested messages with a nesting cap,
//     packed repeated varints, and unknown-field skipping with bounds.
//   * the gRPC frame: 1 compressed-flag byte | u32 big-endian message length
//     | message bytes, parse-one-frame-at-offset with consumed counts.
//   * the decoded etcdserverpb message subset documented in SPEC.md:
//     ResponseHeader, KeyValue, RangeRequest/RangeResponse, PutRequest/
//     PutResponse, DeleteRangeRequest/DeleteRangeResponse, CompactionRequest,
//     TxnRequest/TxnResponse with Compare and RequestOp/ResponseOp one-ofs,
//     WatchRequest/WatchResponse with events, Lease grant/keepalive/revoke/
//     timetolive, Auth authenticate/user-add/role-add, Maintenance (Status,
//     MemberList, Alarm, Defragment, Hash, HashKV, Snapshot).
//     Unknown fields are counted and preserved raw (`EtcdUnknown.bytes`);
//     one-of branches and repeated messages are kept as raw nested bodies
//     with kind tags and re-decoded on demand with the exposed body parsers.
//
// Documented boundaries (see SPEC.md):
//   * every read is bounds-checked; truncation reports the first missing
//     byte offset, malformed values report the value/field offset;
//   * XIOM Int is signed 64-bit: a u64 wire value >= 2^63 is rejected by the
//     unsigned reader instead of being truncated;
//   * `etcd_parse_frame_at` ignores bytes after the frame; the frame's
//     `frame_len` is the consumed count, so streams are walked frame by
//     frame;
//   * the compressed flag is preserved but never interpreted: gRPC
//     compression is out of scope (0 = uncompressed, 1 = compressed);
//   * depth is capped at etcd_max_depth() (16); a frame message is capped at
//     etcd_max_message_bytes() (8 MiB) because the v0.61.3 runtime aborts on
//     ~16 MiB vectors (documented compiler finding);
//   * repeated message lists (kvs, events, compares, ops, members, alarms,
//     TTL keys) are parallel `Vec` fields, never `Vec[StructType]`.
//
// v0.61.3 notes that shaped this module:
//   * free functions only; Ok/Err construction is confined to the leaf
//     helpers below (struct payloads are only wrapped there);
//   * every byte read widens with `(b as Int) & 0xFF`;
//   * Vec reads are bound to typed locals first; Str values are compared
//     with xiom.string.compare, never with `==`;
//   * `&struct.field` is never passed where `&Vec[UInt8]` is expected:
//     values are copied into typed locals first;
//   * struct fields are mutated only through a local `var` or through
//     `&mut` struct/vector parameters (the pattern proven in xiom.pulsar);
//   * numeric widths use division/modulo, never bit shifts; big-endian
//     sizes are composed byte by byte.

module xiom.etcd

use xiom.string;
use xiom.string.builder;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (see the module header)
// --------------------------------------------------

// Ok(v) for Result[Int, Str].
fn _ok_int(v: Int) -> Result[Int, Str] {
  return Ok(v);
}

// Err(m) for Result[Int, Str].
fn _err_int(m: Str) -> Result[Int, Str] {
  return Err(m);
}

// Ok(v) for Result[Bool, Str].
fn _ok_bool(v: Bool) -> Result[Bool, Str] {
  return Ok(v);
}

// Err(m) for Result[Bool, Str].
fn _err_bool(m: Str) -> Result[Bool, Str] {
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

// Ok(v) for Result[Vec[UInt8], Str].
fn _ok_bytes(v: Vec[UInt8]) -> Result[Vec[UInt8], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[UInt8], Str].
fn _err_bytes(m: Str) -> Result[Vec[UInt8], Str] {
  return Err(m);
}

// Ok(()) for Result[Unit, Str].
fn _ok_unit() -> Result[Unit, Str] {
  return Ok(());
}

// Err(m) for Result[Unit, Str].
fn _err_unit(m: Str) -> Result[Unit, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdScalar, Str].
fn _ok_scalar(v: EtcdScalar) -> Result[EtcdScalar, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdScalar, Str].
fn _err_scalar(m: Str) -> Result[EtcdScalar, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdAdvance, Str].
fn _ok_advance(v: EtcdAdvance) -> Result[EtcdAdvance, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdAdvance, Str].
fn _err_advance(m: Str) -> Result[EtcdAdvance, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdDelimited, Str].
fn _ok_delim(v: EtcdDelimited) -> Result[EtcdDelimited, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdDelimited, Str].
fn _err_delim(m: Str) -> Result[EtcdDelimited, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdFieldValue, Str].
fn _ok_fv(v: EtcdFieldValue) -> Result[EtcdFieldValue, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdFieldValue, Str].
fn _err_fv(m: Str) -> Result[EtcdFieldValue, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdFieldStep, Str].
fn _ok_step(v: EtcdFieldStep) -> Result[EtcdFieldStep, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdFieldStep, Str].
fn _err_step(m: Str) -> Result[EtcdFieldStep, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdFrame, Str].
fn _ok_frame(v: EtcdFrame) -> Result[EtcdFrame, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdFrame, Str].
fn _err_frame(m: Str) -> Result[EtcdFrame, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdHeader, Str].
fn _ok_header(v: EtcdHeader) -> Result[EtcdHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdHeader, Str].
fn _err_header(m: Str) -> Result[EtcdHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdKeyValue, Str].
fn _ok_kv(v: EtcdKeyValue) -> Result[EtcdKeyValue, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdKeyValue, Str].
fn _err_kv(m: Str) -> Result[EtcdKeyValue, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdEvent, Str].
fn _ok_event(v: EtcdEvent) -> Result[EtcdEvent, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdEvent, Str].
fn _err_event(m: Str) -> Result[EtcdEvent, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdOp, Str].
fn _ok_op(v: EtcdOp) -> Result[EtcdOp, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdOp, Str].
fn _err_op(m: Str) -> Result[EtcdOp, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdCompare, Str].
fn _ok_cmp(v: EtcdCompare) -> Result[EtcdCompare, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdCompare, Str].
fn _err_cmp(m: Str) -> Result[EtcdCompare, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdRangeRequest, Str].
fn _ok_range_req(v: EtcdRangeRequest) -> Result[EtcdRangeRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdRangeRequest, Str].
fn _err_range_req(m: Str) -> Result[EtcdRangeRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdRangeResponse, Str].
fn _ok_range_resp(v: EtcdRangeResponse) -> Result[EtcdRangeResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdRangeResponse, Str].
fn _err_range_resp(m: Str) -> Result[EtcdRangeResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdPutRequest, Str].
fn _ok_put_req(v: EtcdPutRequest) -> Result[EtcdPutRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdPutRequest, Str].
fn _err_put_req(m: Str) -> Result[EtcdPutRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdPutResponse, Str].
fn _ok_put_resp(v: EtcdPutResponse) -> Result[EtcdPutResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdPutResponse, Str].
fn _err_put_resp(m: Str) -> Result[EtcdPutResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdDeleteRangeRequest, Str].
fn _ok_del_req(v: EtcdDeleteRangeRequest) -> Result[EtcdDeleteRangeRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdDeleteRangeRequest, Str].
fn _err_del_req(m: Str) -> Result[EtcdDeleteRangeRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdDeleteRangeResponse, Str].
fn _ok_del_resp(v: EtcdDeleteRangeResponse) -> Result[EtcdDeleteRangeResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdDeleteRangeResponse, Str].
fn _err_del_resp(m: Str) -> Result[EtcdDeleteRangeResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdTxnRequest, Str].
fn _ok_txn_req(v: EtcdTxnRequest) -> Result[EtcdTxnRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdTxnRequest, Str].
fn _err_txn_req(m: Str) -> Result[EtcdTxnRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdTxnResponse, Str].
fn _ok_txn_resp(v: EtcdTxnResponse) -> Result[EtcdTxnResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdTxnResponse, Str].
fn _err_txn_resp(m: Str) -> Result[EtcdTxnResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdCompactionRequest, Str].
fn _ok_compact(v: EtcdCompactionRequest) -> Result[EtcdCompactionRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdCompactionRequest, Str].
fn _err_compact(m: Str) -> Result[EtcdCompactionRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdWatchRequest, Str].
fn _ok_watch_req(v: EtcdWatchRequest) -> Result[EtcdWatchRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdWatchRequest, Str].
fn _err_watch_req(m: Str) -> Result[EtcdWatchRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdWatchResponse, Str].
fn _ok_watch_resp(v: EtcdWatchResponse) -> Result[EtcdWatchResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdWatchResponse, Str].
fn _err_watch_resp(m: Str) -> Result[EtcdWatchResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdLeaseGrantRequest, Str].
fn _ok_lgrant_req(v: EtcdLeaseGrantRequest) -> Result[EtcdLeaseGrantRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdLeaseGrantRequest, Str].
fn _err_lgrant_req(m: Str) -> Result[EtcdLeaseGrantRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdLeaseGrantResponse, Str].
fn _ok_lgrant_resp(v: EtcdLeaseGrantResponse) -> Result[EtcdLeaseGrantResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdLeaseGrantResponse, Str].
fn _err_lgrant_resp(m: Str) -> Result[EtcdLeaseGrantResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdLeaseKeepAliveRequest, Str].
fn _ok_lkeep_req(v: EtcdLeaseKeepAliveRequest) -> Result[EtcdLeaseKeepAliveRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdLeaseKeepAliveRequest, Str].
fn _err_lkeep_req(m: Str) -> Result[EtcdLeaseKeepAliveRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdLeaseKeepAliveResponse, Str].
fn _ok_lkeep_resp(v: EtcdLeaseKeepAliveResponse) -> Result[EtcdLeaseKeepAliveResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdLeaseKeepAliveResponse, Str].
fn _err_lkeep_resp(m: Str) -> Result[EtcdLeaseKeepAliveResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdLeaseRevokeRequest, Str].
fn _ok_lrevoke_req(v: EtcdLeaseRevokeRequest) -> Result[EtcdLeaseRevokeRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdLeaseRevokeRequest, Str].
fn _err_lrevoke_req(m: Str) -> Result[EtcdLeaseRevokeRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdLeaseTimeToLiveRequest, Str].
fn _ok_lttl_req(v: EtcdLeaseTimeToLiveRequest) -> Result[EtcdLeaseTimeToLiveRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdLeaseTimeToLiveRequest, Str].
fn _err_lttl_req(m: Str) -> Result[EtcdLeaseTimeToLiveRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdLeaseTimeToLiveResponse, Str].
fn _ok_lttl_resp(v: EtcdLeaseTimeToLiveResponse) -> Result[EtcdLeaseTimeToLiveResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdLeaseTimeToLiveResponse, Str].
fn _err_lttl_resp(m: Str) -> Result[EtcdLeaseTimeToLiveResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdAuthenticateRequest, Str].
fn _ok_auth_req(v: EtcdAuthenticateRequest) -> Result[EtcdAuthenticateRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdAuthenticateRequest, Str].
fn _err_auth_req(m: Str) -> Result[EtcdAuthenticateRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdAuthenticateResponse, Str].
fn _ok_auth_resp(v: EtcdAuthenticateResponse) -> Result[EtcdAuthenticateResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdAuthenticateResponse, Str].
fn _err_auth_resp(m: Str) -> Result[EtcdAuthenticateResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdUserAddRequest, Str].
fn _ok_useradd_req(v: EtcdUserAddRequest) -> Result[EtcdUserAddRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdUserAddRequest, Str].
fn _err_useradd_req(m: Str) -> Result[EtcdUserAddRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdRoleAddRequest, Str].
fn _ok_roleadd_req(v: EtcdRoleAddRequest) -> Result[EtcdRoleAddRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdRoleAddRequest, Str].
fn _err_roleadd_req(m: Str) -> Result[EtcdRoleAddRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdStatusResponse, Str].
fn _ok_status(v: EtcdStatusResponse) -> Result[EtcdStatusResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdStatusResponse, Str].
fn _err_status(m: Str) -> Result[EtcdStatusResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdMemberListResponse, Str].
fn _ok_members(v: EtcdMemberListResponse) -> Result[EtcdMemberListResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdMemberListResponse, Str].
fn _err_members(m: Str) -> Result[EtcdMemberListResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdAlarmMember, Str].
fn _ok_almember(v: EtcdAlarmMember) -> Result[EtcdAlarmMember, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdAlarmMember, Str].
fn _err_almember(m: Str) -> Result[EtcdAlarmMember, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdAlarmRequest, Str].
fn _ok_alarm_req(v: EtcdAlarmRequest) -> Result[EtcdAlarmRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdAlarmRequest, Str].
fn _err_alarm_req(m: Str) -> Result[EtcdAlarmRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdAlarmResponse, Str].
fn _ok_alarm_resp(v: EtcdAlarmResponse) -> Result[EtcdAlarmResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdAlarmResponse, Str].
fn _err_alarm_resp(m: Str) -> Result[EtcdAlarmResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdHashResponse, Str].
fn _ok_hash(v: EtcdHashResponse) -> Result[EtcdHashResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdHashResponse, Str].
fn _err_hash(m: Str) -> Result[EtcdHashResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdHashKvResponse, Str].
fn _ok_hashkv(v: EtcdHashKvResponse) -> Result[EtcdHashKvResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdHashKvResponse, Str].
fn _err_hashkv(m: Str) -> Result[EtcdHashKvResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[EtcdSnapshotResponse, Str].
fn _ok_snapshot(v: EtcdSnapshotResponse) -> Result[EtcdSnapshotResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[EtcdSnapshotResponse, Str].
fn _err_snapshot(m: Str) -> Result[EtcdSnapshotResponse, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Public types
// --------------------------------------------------

/// Fields outside the decoded subset: how many, and their raw tag+value
/// bytes concatenated in wire order. A message with no unknown fields has
/// count 0 and an empty byte vector.
pub type EtcdUnknown = {
  count: Int;
  bytes: Vec[UInt8];
}

/// Decoded ResponseHeader. `present` is false when the enclosing message
/// carried no header field. `revision` is signed (int64); the id fields are
/// unsigned (a wire value >= 2^63 is rejected by the reader).
pub type EtcdHeader = {
  present: Bool;
  cluster_id: Int;
  member_id: Int;
  revision: Int;
  raft_term: Int;
  unknown: EtcdUnknown;
}

/// Decoded KeyValue. Keys and values are raw bytes (etcd permits arbitrary
/// bytes); the revision/version/lease fields are int64.
pub type EtcdKeyValue = {
  key: Vec[UInt8];
  create_revision: Int;
  mod_revision: Int;
  version: Int;
  value: Vec[UInt8];
  lease: Int;
  unknown: EtcdUnknown;
}

/// A flat list of KeyValue entries: six parallel vectors, one entry per kv,
/// pushed together (they never drift). `keys.len()` is the entry count.
pub type EtcdKvList = {
  keys: Vec[Vec[UInt8]];
  values: Vec[Vec[UInt8]];
  create_revisions: Vec[Int];
  mod_revisions: Vec[Int];
  versions: Vec[Int];
  leases: Vec[Int];
}

/// One decoded RequestOp/ResponseOp: the one-of discriminator (`kind` is
/// 1 range, 2 put, 3 delete_range, 4 txn, 0 when no branch was present) and
/// the raw nested message bytes, re-decoded on demand with the matching
/// body parser.
pub type EtcdOp = {
  kind: Int;
  raw: Vec[UInt8];
  unknown: EtcdUnknown;
}

/// One decoded Compare. `union_field` is the wire field number of the
/// target_union selection (4 version, 5 create_revision, 6 mod_revision,
/// 7 value, 8 lease; 0 when absent).
pub type EtcdCompare = {
  result: Int;
  target: Int;
  key: Vec[UInt8];
  union_field: Int;
  version: Int;
  create_revision: Int;
  mod_revision: Int;
  value: Vec[UInt8];
  lease: Int;
  unknown: EtcdUnknown;
}

/// A flat list of Compare entries: nine parallel vectors, one entry per
/// compare.
pub type EtcdCompareList = {
  results: Vec[Int];
  targets: Vec[Int];
  keys: Vec[Vec[UInt8]];
  union_fields: Vec[Int];
  versions: Vec[Int];
  create_revisions: Vec[Int];
  mod_revisions: Vec[Int];
  values: Vec[Vec[UInt8]];
  leases: Vec[Int];
}

/// A flat list of request/response ops: two parallel vectors, one entry per
/// op. `raws[i]` is the nested message body for `kinds[i]`.
pub type EtcdOpList = {
  kinds: Vec[Int];
  raws: Vec[Vec[UInt8]];
}

/// One decoded watch Event: the type (PUT 0 / DELETE 1), the kv, and the
/// previous kv. `kv_present`/`prev_present` record wire presence.
pub type EtcdEvent = {
  etype: Int;
  kv_present: Int;
  kv: EtcdKeyValue;
  prev_present: Int;
  prev: EtcdKeyValue;
  unknown: EtcdUnknown;
}

/// One decoded AlarmMember.
pub type EtcdAlarmMember = {
  member_id: Int;
  alarm: Int;
  unknown: EtcdUnknown;
}

/// Decoded RangeRequest (sort_order and sort_target keep their numeric
/// values; see etcd_sort_order_name / etcd_sort_target_name).
pub type EtcdRangeRequest = {
  key: Vec[UInt8];
  range_end: Vec[UInt8];
  limit: Int;
  revision: Int;
  sort_order: Int;
  sort_target: Int;
  serializable: Bool;
  keys_only: Bool;
  count_only: Bool;
  min_mod_revision: Int;
  max_mod_revision: Int;
  min_create_revision: Int;
  max_create_revision: Int;
  unknown: EtcdUnknown;
}

/// Decoded RangeResponse. `kvs` holds every KeyValue field in order.
pub type EtcdRangeResponse = {
  header: EtcdHeader;
  kvs: EtcdKvList;
  more: Bool;
  count: Int;
  unknown: EtcdUnknown;
}

/// Decoded PutRequest.
pub type EtcdPutRequest = {
  key: Vec[UInt8];
  value: Vec[UInt8];
  lease: Int;
  prev_kv: Bool;
  ignore_value: Bool;
  ignore_lease: Bool;
  unknown: EtcdUnknown;
}

/// Decoded PutResponse. `prev_kv` is meaningful only when `has_prev_kv`.
pub type EtcdPutResponse = {
  header: EtcdHeader;
  prev_kv: EtcdKeyValue;
  has_prev_kv: Bool;
  unknown: EtcdUnknown;
}

/// Decoded DeleteRangeRequest.
pub type EtcdDeleteRangeRequest = {
  key: Vec[UInt8];
  range_end: Vec[UInt8];
  prev_kv: Bool;
  unknown: EtcdUnknown;
}

/// Decoded DeleteRangeResponse. `prev_kvs` holds every prev_kv field.
pub type EtcdDeleteRangeResponse = {
  header: EtcdHeader;
  deleted: Int;
  prev_kvs: EtcdKvList;
  unknown: EtcdUnknown;
}

/// Decoded TxnRequest: the compare list plus the success/failure op lists.
pub type EtcdTxnRequest = {
  compares: EtcdCompareList;
  success: EtcdOpList;
  failure: EtcdOpList;
  unknown: EtcdUnknown;
}

/// Decoded TxnResponse: header, succeeded flag, response op list.
pub type EtcdTxnResponse = {
  header: EtcdHeader;
  succeeded: Bool;
  responses: EtcdOpList;
  unknown: EtcdUnknown;
}

/// Decoded CompactionRequest (revision, physical).
pub type EtcdCompactionRequest = {
  revision: Int;
  physical: Bool;
  unknown: EtcdUnknown;
}

/// Decoded WatchRequest. `kind` is the one-of discriminator (1 create,
/// 2 cancel, 3 progress, 0 none); create fields and `cancel_watch_id` share
/// the struct.
pub type EtcdWatchRequest = {
  kind: Int;
  key: Vec[UInt8];
  range_end: Vec[UInt8];
  start_revision: Int;
  progress_notify: Bool;
  filters: Vec[Int];
  prev_kv: Bool;
  watch_id: Int;
  fragment: Bool;
  cancel_watch_id: Int;
  unknown: EtcdUnknown;
}

/// Decoded WatchResponse. Every event is folded into parallel vectors (one
/// entry per event) because Vec[StructType] is unsupported; use
/// etcd_watch_event_get to reassemble one event.
pub type EtcdWatchResponse = {
  header: EtcdHeader;
  watch_id: Int;
  created: Bool;
  canceled: Bool;
  compact_revision: Int;
  cancel_reason: Str;
  fragment: Bool;
  event_types: Vec[Int];
  event_kv_present: Vec[Int];
  event_kv_keys: Vec[Vec[UInt8]];
  event_kv_values: Vec[Vec[UInt8]];
  event_kv_create_revisions: Vec[Int];
  event_kv_mod_revisions: Vec[Int];
  event_kv_versions: Vec[Int];
  event_kv_leases: Vec[Int];
  event_prev_present: Vec[Int];
  event_prev_keys: Vec[Vec[UInt8]];
  event_prev_values: Vec[Vec[UInt8]];
  event_prev_create_revisions: Vec[Int];
  event_prev_mod_revisions: Vec[Int];
  event_prev_versions: Vec[Int];
  event_prev_leases: Vec[Int];
  unknown: EtcdUnknown;
}

/// Decoded LeaseGrantRequest (TTL, ID).
pub type EtcdLeaseGrantRequest = {
  ttl: Int;
  id: Int;
  unknown: EtcdUnknown;
}

/// Decoded LeaseGrantResponse (ID, TTL, error string).
pub type EtcdLeaseGrantResponse = {
  header: EtcdHeader;
  id: Int;
  ttl: Int;
  error_text: Str;
  has_error_text: Bool;
  unknown: EtcdUnknown;
}

/// Decoded LeaseKeepAliveRequest (ID).
pub type EtcdLeaseKeepAliveRequest = {
  id: Int;
  unknown: EtcdUnknown;
}

/// Decoded LeaseKeepAliveResponse (ID, TTL).
pub type EtcdLeaseKeepAliveResponse = {
  header: EtcdHeader;
  id: Int;
  ttl: Int;
  unknown: EtcdUnknown;
}

/// Decoded LeaseRevokeRequest (ID).
pub type EtcdLeaseRevokeRequest = {
  id: Int;
  unknown: EtcdUnknown;
}

/// Decoded LeaseTimeToLiveRequest (ID, keys flag).
pub type EtcdLeaseTimeToLiveRequest = {
  id: Int;
  keys: Bool;
  unknown: EtcdUnknown;
}

/// Decoded LeaseTimeToLiveResponse (ID, TTL, grantedTTL, keys).
pub type EtcdLeaseTimeToLiveResponse = {
  header: EtcdHeader;
  id: Int;
  ttl: Int;
  granted_ttl: Int;
  keys: Vec[Vec[UInt8]];
  unknown: EtcdUnknown;
}

/// Decoded AuthenticateRequest (name, password).
pub type EtcdAuthenticateRequest = {
  name: Str;
  password: Str;
  unknown: EtcdUnknown;
}

/// Decoded AuthenticateResponse (token).
pub type EtcdAuthenticateResponse = {
  header: EtcdHeader;
  token: Str;
  unknown: EtcdUnknown;
}

/// Decoded AuthUserAddRequest subset: name and password are decoded;
/// `options_raw` preserves the raw authpb.UserAddOptions body and
/// hashedPassword is decoded, both documented as a noted subset.
pub type EtcdUserAddRequest = {
  name: Str;
  password: Str;
  has_options: Bool;
  options_raw: Vec[UInt8];
  hashed_password: Str;
  has_hashed_password: Bool;
  unknown: EtcdUnknown;
}

/// Decoded AuthRoleAddRequest subset (name).
pub type EtcdRoleAddRequest = {
  name: Str;
  unknown: EtcdUnknown;
}

/// Decoded StatusResponse (version, dbSize, leader, raftIndex, raftTerm,
/// dbSizeInUse, isLearner).
pub type EtcdStatusResponse = {
  header: EtcdHeader;
  version: Str;
  db_size: Int;
  leader: Int;
  raft_index: Int;
  raft_term: Int;
  db_size_in_use: Int;
  is_learner: Bool;
  unknown: EtcdUnknown;
}

/// A flat member list: parallel vectors plus per-member URL runs delimited
/// by `peer_offsets`/`client_offsets` (len == member count + 1).
pub type EtcdMemberList = {
  ids: Vec[Int];
  names: Vec[Vec[UInt8]];
  learners: Vec[Int];
  peer_offsets: Vec[Int];
  peer_urls: Vec[Vec[UInt8]];
  client_offsets: Vec[Int];
  client_urls: Vec[Vec[UInt8]];
}

/// Decoded MemberListResponse.
pub type EtcdMemberListResponse = {
  header: EtcdHeader;
  members: EtcdMemberList;
  unknown: EtcdUnknown;
}

/// Decoded AlarmRequest (alarm type, memberID, action).
pub type EtcdAlarmRequest = {
  alarm: Int;
  member_id: Int;
  action: Int;
  unknown: EtcdUnknown;
}

/// Decoded AlarmResponse: parallel member ids and alarm types.
pub type EtcdAlarmResponse = {
  header: EtcdHeader;
  member_ids: Vec[Int];
  alarms: Vec[Int];
  unknown: EtcdUnknown;
}

/// Decoded HashResponse (hash is a uint32 carried as an Int).
pub type EtcdHashResponse = {
  header: EtcdHeader;
  hash: Int;
  unknown: EtcdUnknown;
}

/// Decoded HashKVResponse (hash, compact_revision, hash_revision).
pub type EtcdHashKvResponse = {
  header: EtcdHeader;
  hash: Int;
  compact_revision: Int;
  hash_revision: Int;
  unknown: EtcdUnknown;
}

/// Decoded SnapshotResponse (remaining_bytes, blob).
pub type EtcdSnapshotResponse = {
  header: EtcdHeader;
  remaining_bytes: Int;
  blob: Vec[UInt8];
  unknown: EtcdUnknown;
}

/// One decoded integer scalar and the number of wire bytes it consumed.
pub type EtcdScalar = {
  value: Int;
  size: Int;
}

/// A new cursor position and the number of bytes consumed to reach it.
pub type EtcdAdvance = {
  pos: Int;
  size: Int;
}

/// A length-delimited value: `start` is the first payload byte, `size` the
/// payload length and `total` the bytes consumed (length prefix + payload).
pub type EtcdDelimited = {
  start: Int;
  size: Int;
  total: Int;
}

/// One decoded protobuf field value (without its key). `wire_type` is
/// 0/1/2/5; `int_value` carries the scalar for 0/1/5; `start`/`size` carry
/// the payload span for 2; `total` is the value's wire size in bytes.
pub type EtcdFieldValue = {
  wire_type: Int;
  int_value: Int;
  start: Int;
  size: Int;
  total: Int;
}

/// One decoded protobuf field: key metadata plus the value, and `next`, the
/// absolute offset of the field after this one.
pub type EtcdFieldStep = {
  field_number: Int;
  wire_type: Int;
  tag_start: Int;
  key_size: Int;
  value: EtcdFieldValue;
  next: Int;
}

/// One parsed gRPC frame. `compressed` is the raw flag byte (0 uncompressed,
/// 1 compressed; other values are preserved, never interpreted), `length`
/// the declared message length, `message` a copy of the message bytes and
/// `frame_len` the consumed count (5 + length). `offset` is the absolute
/// offset of the frame start.
pub type EtcdFrame = {
  compressed: Int;
  length: Int;
  message: Vec[UInt8];
  frame_len: Int;
  offset: Int;
}

// --------------------------------------------------
//  Constructors
// --------------------------------------------------

/// A fresh empty unknown-field record. Complexity: O(1).
pub fn etcd_unknown_new() -> EtcdUnknown {
  return EtcdUnknown{ count: 0; bytes: Vec[UInt8].new() };
}

/// A fresh header with present = false and every field at its proto3
/// default (0). Complexity: O(1).
pub fn etcd_header_new() -> EtcdHeader {
  return EtcdHeader{
    present: false; cluster_id: 0; member_id: 0; revision: 0; raft_term: 0;
    unknown: etcd_unknown_new();
  };
}

/// A fresh KeyValue with every field at its proto3 default (empty/0).
pub fn etcd_key_value_new() -> EtcdKeyValue {
  return EtcdKeyValue{
    key: Vec[UInt8].new(); create_revision: 0; mod_revision: 0; version: 0;
    value: Vec[UInt8].new(); lease: 0; unknown: etcd_unknown_new();
  };
}

/// A fresh empty kv list. Complexity: O(1).
pub fn etcd_kv_list_new() -> EtcdKvList {
  return EtcdKvList{
    keys: Vec[Vec[UInt8]].new(); values: Vec[Vec[UInt8]].new();
    create_revisions: Vec[Int].new(); mod_revisions: Vec[Int].new();
    versions: Vec[Int].new(); leases: Vec[Int].new();
  };
}

/// A fresh op with kind 0. Complexity: O(1).
pub fn etcd_op_new() -> EtcdOp {
  return EtcdOp{ kind: 0; raw: Vec[UInt8].new(); unknown: etcd_unknown_new() };
}

/// A fresh Compare with every field at its proto3 default.
pub fn etcd_compare_new() -> EtcdCompare {
  return EtcdCompare{
    result: 0; target: 0; key: Vec[UInt8].new(); union_field: 0; version: 0;
    create_revision: 0; mod_revision: 0; value: Vec[UInt8].new(); lease: 0;
    unknown: etcd_unknown_new();
  };
}

/// A fresh empty compare list. Complexity: O(1).
pub fn etcd_compare_list_new() -> EtcdCompareList {
  return EtcdCompareList{
    results: Vec[Int].new(); targets: Vec[Int].new(); keys: Vec[Vec[UInt8]].new();
    union_fields: Vec[Int].new(); versions: Vec[Int].new();
    create_revisions: Vec[Int].new(); mod_revisions: Vec[Int].new();
    values: Vec[Vec[UInt8]].new(); leases: Vec[Int].new();
  };
}

/// A fresh empty op list. Complexity: O(1).
pub fn etcd_op_list_new() -> EtcdOpList {
  return EtcdOpList{ kinds: Vec[Int].new(); raws: Vec[Vec[UInt8]].new() };
}

/// A fresh Event with both kv fields absent and at their defaults.
pub fn etcd_event_new() -> EtcdEvent {
  return EtcdEvent{
    etype: 0; kv_present: 0; kv: etcd_key_value_new();
    prev_present: 0; prev: etcd_key_value_new(); unknown: etcd_unknown_new();
  };
}

/// A fresh AlarmMember at its defaults. Complexity: O(1).
pub fn etcd_alarm_member_new() -> EtcdAlarmMember {
  return EtcdAlarmMember{ member_id: 0; alarm: 0; unknown: etcd_unknown_new() };
}

/// A fresh RangeRequest at its proto3 defaults.
pub fn etcd_range_request_new() -> EtcdRangeRequest {
  return EtcdRangeRequest{
    key: Vec[UInt8].new(); range_end: Vec[UInt8].new(); limit: 0; revision: 0;
    sort_order: 0; sort_target: 0; serializable: false; keys_only: false;
    count_only: false; min_mod_revision: 0; max_mod_revision: 0;
    min_create_revision: 0; max_create_revision: 0; unknown: etcd_unknown_new();
  };
}

/// A fresh RangeResponse at its proto3 defaults.
pub fn etcd_range_response_new() -> EtcdRangeResponse {
  return EtcdRangeResponse{
    header: etcd_header_new(); kvs: etcd_kv_list_new(); more: false;
    count: 0; unknown: etcd_unknown_new();
  };
}

/// A fresh PutRequest at its proto3 defaults.
pub fn etcd_put_request_new() -> EtcdPutRequest {
  return EtcdPutRequest{
    key: Vec[UInt8].new(); value: Vec[UInt8].new(); lease: 0; prev_kv: false;
    ignore_value: false; ignore_lease: false; unknown: etcd_unknown_new();
  };
}

/// A fresh PutResponse at its proto3 defaults.
pub fn etcd_put_response_new() -> EtcdPutResponse {
  return EtcdPutResponse{
    header: etcd_header_new(); prev_kv: etcd_key_value_new();
    has_prev_kv: false; unknown: etcd_unknown_new();
  };
}

/// A fresh DeleteRangeRequest at its proto3 defaults.
pub fn etcd_delete_range_request_new() -> EtcdDeleteRangeRequest {
  return EtcdDeleteRangeRequest{
    key: Vec[UInt8].new(); range_end: Vec[UInt8].new(); prev_kv: false;
    unknown: etcd_unknown_new();
  };
}

/// A fresh DeleteRangeResponse at its proto3 defaults.
pub fn etcd_delete_range_response_new() -> EtcdDeleteRangeResponse {
  return EtcdDeleteRangeResponse{
    header: etcd_header_new(); deleted: 0; prev_kvs: etcd_kv_list_new();
    unknown: etcd_unknown_new();
  };
}

/// A fresh TxnRequest with empty lists and defaults.
pub fn etcd_txn_request_new() -> EtcdTxnRequest {
  return EtcdTxnRequest{
    compares: etcd_compare_list_new(); success: etcd_op_list_new();
    failure: etcd_op_list_new(); unknown: etcd_unknown_new();
  };
}

/// A fresh TxnResponse with defaults.
pub fn etcd_txn_response_new() -> EtcdTxnResponse {
  return EtcdTxnResponse{
    header: etcd_header_new(); succeeded: false; responses: etcd_op_list_new();
    unknown: etcd_unknown_new();
  };
}

/// A fresh CompactionRequest at its proto3 defaults.
pub fn etcd_compaction_request_new() -> EtcdCompactionRequest {
  return EtcdCompactionRequest{
    revision: 0; physical: false; unknown: etcd_unknown_new();
  };
}

/// A fresh WatchRequest with kind 0 and defaults.
pub fn etcd_watch_request_new() -> EtcdWatchRequest {
  return EtcdWatchRequest{
    kind: 0; key: Vec[UInt8].new(); range_end: Vec[UInt8].new();
    start_revision: 0; progress_notify: false; filters: Vec[Int].new();
    prev_kv: false; watch_id: 0; fragment: false; cancel_watch_id: 0;
    unknown: etcd_unknown_new();
  };
}

/// A fresh WatchResponse with an empty event list.
pub fn etcd_watch_response_new() -> EtcdWatchResponse {
  return EtcdWatchResponse{
    header: etcd_header_new(); watch_id: 0; created: false; canceled: false;
    compact_revision: 0; cancel_reason: ""; fragment: false;
    event_types: Vec[Int].new();
    event_kv_present: Vec[Int].new();
    event_kv_keys: Vec[Vec[UInt8]].new();
    event_kv_values: Vec[Vec[UInt8]].new();
    event_kv_create_revisions: Vec[Int].new();
    event_kv_mod_revisions: Vec[Int].new();
    event_kv_versions: Vec[Int].new();
    event_kv_leases: Vec[Int].new();
    event_prev_present: Vec[Int].new();
    event_prev_keys: Vec[Vec[UInt8]].new();
    event_prev_values: Vec[Vec[UInt8]].new();
    event_prev_create_revisions: Vec[Int].new();
    event_prev_mod_revisions: Vec[Int].new();
    event_prev_versions: Vec[Int].new();
    event_prev_leases: Vec[Int].new();
    unknown: etcd_unknown_new();
  };
}

/// A fresh LeaseGrantRequest at its proto3 defaults.
pub fn etcd_lease_grant_request_new() -> EtcdLeaseGrantRequest {
  return EtcdLeaseGrantRequest{ ttl: 0; id: 0; unknown: etcd_unknown_new() };
}

/// A fresh LeaseGrantResponse at its proto3 defaults.
pub fn etcd_lease_grant_response_new() -> EtcdLeaseGrantResponse {
  return EtcdLeaseGrantResponse{
    header: etcd_header_new(); id: 0; ttl: 0; error_text: "";
    has_error_text: false; unknown: etcd_unknown_new();
  };
}

/// A fresh LeaseKeepAliveRequest at its proto3 defaults.
pub fn etcd_lease_keep_alive_request_new() -> EtcdLeaseKeepAliveRequest {
  return EtcdLeaseKeepAliveRequest{ id: 0; unknown: etcd_unknown_new() };
}

/// A fresh LeaseKeepAliveResponse at its proto3 defaults.
pub fn etcd_lease_keep_alive_response_new() -> EtcdLeaseKeepAliveResponse {
  return EtcdLeaseKeepAliveResponse{
    header: etcd_header_new(); id: 0; ttl: 0; unknown: etcd_unknown_new();
  };
}

/// A fresh LeaseRevokeRequest at its proto3 defaults.
pub fn etcd_lease_revoke_request_new() -> EtcdLeaseRevokeRequest {
  return EtcdLeaseRevokeRequest{ id: 0; unknown: etcd_unknown_new() };
}

/// A fresh LeaseTimeToLiveRequest at its proto3 defaults.
pub fn etcd_lease_time_to_live_request_new() -> EtcdLeaseTimeToLiveRequest {
  return EtcdLeaseTimeToLiveRequest{
    id: 0; keys: false; unknown: etcd_unknown_new();
  };
}

/// A fresh LeaseTimeToLiveResponse at its proto3 defaults.
pub fn etcd_lease_time_to_live_response_new() -> EtcdLeaseTimeToLiveResponse {
  return EtcdLeaseTimeToLiveResponse{
    header: etcd_header_new(); id: 0; ttl: 0; granted_ttl: 0;
    keys: Vec[Vec[UInt8]].new(); unknown: etcd_unknown_new();
  };
}

/// A fresh AuthenticateRequest at its proto3 defaults.
pub fn etcd_authenticate_request_new() -> EtcdAuthenticateRequest {
  return EtcdAuthenticateRequest{
    name: ""; password: ""; unknown: etcd_unknown_new();
  };
}

/// A fresh AuthenticateResponse at its proto3 defaults.
pub fn etcd_authenticate_response_new() -> EtcdAuthenticateResponse {
  return EtcdAuthenticateResponse{
    header: etcd_header_new(); token: ""; unknown: etcd_unknown_new();
  };
}

/// A fresh AuthUserAddRequest at its proto3 defaults.
pub fn etcd_user_add_request_new() -> EtcdUserAddRequest {
  return EtcdUserAddRequest{
    name: ""; password: ""; has_options: false; options_raw: Vec[UInt8].new();
    hashed_password: ""; has_hashed_password: false; unknown: etcd_unknown_new();
  };
}

/// A fresh AuthRoleAddRequest at its proto3 defaults.
pub fn etcd_role_add_request_new() -> EtcdRoleAddRequest {
  return EtcdRoleAddRequest{ name: ""; unknown: etcd_unknown_new() };
}

/// A fresh StatusResponse at its proto3 defaults.
pub fn etcd_status_response_new() -> EtcdStatusResponse {
  return EtcdStatusResponse{
    header: etcd_header_new(); version: ""; db_size: 0; leader: 0;
    raft_index: 0; raft_term: 0; db_size_in_use: 0; is_learner: false;
    unknown: etcd_unknown_new();
  };
}

/// A fresh MemberList with empty URL runs. After decoding, each run is
/// closed so offsets.len() == ids.len() + 1; a hand-built empty list has
/// empty offsets and the accessors return zero/empty for it.
/// Complexity: O(1).
pub fn etcd_member_list_new() -> EtcdMemberList {
  return EtcdMemberList{
    ids: Vec[Int].new(); names: Vec[Vec[UInt8]].new();
    learners: Vec[Int].new(); peer_offsets: Vec[Int].new();
    peer_urls: Vec[Vec[UInt8]].new(); client_offsets: Vec[Int].new();
    client_urls: Vec[Vec[UInt8]].new();
  };
}

/// A fresh MemberListResponse at its proto3 defaults.
pub fn etcd_member_list_response_new() -> EtcdMemberListResponse {
  return EtcdMemberListResponse{
    header: etcd_header_new(); members: etcd_member_list_new();
    unknown: etcd_unknown_new();
  };
}

/// A fresh AlarmRequest at its proto3 defaults.
pub fn etcd_alarm_request_new() -> EtcdAlarmRequest {
  return EtcdAlarmRequest{
    alarm: 0; member_id: 0; action: 0; unknown: etcd_unknown_new();
  };
}

/// A fresh AlarmResponse with no alarms.
pub fn etcd_alarm_response_new() -> EtcdAlarmResponse {
  return EtcdAlarmResponse{
    header: etcd_header_new(); member_ids: Vec[Int].new();
    alarms: Vec[Int].new(); unknown: etcd_unknown_new();
  };
}

/// A fresh HashResponse at its proto3 defaults.
pub fn etcd_hash_response_new() -> EtcdHashResponse {
  return EtcdHashResponse{
    header: etcd_header_new(); hash: 0; unknown: etcd_unknown_new();
  };
}

/// A fresh HashKVResponse at its proto3 defaults.
pub fn etcd_hash_kv_response_new() -> EtcdHashKvResponse {
  return EtcdHashKvResponse{
    header: etcd_header_new(); hash: 0; compact_revision: 0;
    hash_revision: 0; unknown: etcd_unknown_new();
  };
}

/// A fresh SnapshotResponse at its proto3 defaults.
pub fn etcd_snapshot_response_new() -> EtcdSnapshotResponse {
  return EtcdSnapshotResponse{
    header: etcd_header_new(); remaining_bytes: 0;
    blob: Vec[UInt8].new(); unknown: etcd_unknown_new();
  };
}

// --------------------------------------------------
//  Constants and limits
// --------------------------------------------------

/// Maximum bytes in one base-128 varint. Complexity: O(1).
pub fn etcd_max_varint_bytes() -> Int {
  return 10;
}

/// Nesting cap for length-delimited message parsing. Complexity: O(1).
pub fn etcd_max_depth() -> Int {
  return 16;
}

/// Upper bound on entries decoded into one repeated-message list.
/// Complexity: O(1).
pub fn etcd_max_list_entries() -> Int {
  return 65536;
}

/// Upper bound on the values decoded from one packed repeated run.
/// Complexity: O(1).
pub fn etcd_max_packed_entries() -> Int {
  return 65536;
}

/// Upper bound on one gRPC message in this codec. 8 MiB keeps a message
/// copy plus its owning buffer below the v0.61.3 two-live-16-MiB-vector
/// runtime abort. Complexity: O(1).
pub fn etcd_max_message_bytes() -> Int {
  return 8388608;
}

/// Bytes of one gRPC frame header (flag + u32 length). Complexity: O(1).
pub fn etcd_grpc_header_size() -> Int {
  return 5;
}

/// gRPC compressed flag: uncompressed (0). Complexity: O(1).
pub fn etcd_grpc_uncompressed() -> Int {
  return 0;
}

/// gRPC compressed flag: compressed (1; preserved, never interpreted).
/// Complexity: O(1).
pub fn etcd_grpc_compressed() -> Int {
  return 1;
}

/// Wire type 0: base-128 varint. Complexity: O(1).
pub fn etcd_wire_varint() -> Int {
  return 0;
}

/// Wire type 1: 64-bit little-endian fixed. Complexity: O(1).
pub fn etcd_wire_fixed64() -> Int {
  return 1;
}

/// Wire type 2: varint length prefix plus payload. Complexity: O(1).
pub fn etcd_wire_length_delimited() -> Int {
  return 2;
}

/// Wire type 5: 32-bit little-endian fixed. Complexity: O(1).
pub fn etcd_wire_fixed32() -> Int {
  return 5;
}

/// RangeRequest.SortOrder NONE (0). Complexity: O(1).
pub fn etcd_sort_none() -> Int {
  return 0;
}

/// RangeRequest.SortOrder ASCEND (1). Complexity: O(1).
pub fn etcd_sort_ascend() -> Int {
  return 1;
}

/// RangeRequest.SortOrder DESCEND (2). Complexity: O(1).
pub fn etcd_sort_descend() -> Int {
  return 2;
}

/// RangeRequest.SortTarget KEY (0). Complexity: O(1).
pub fn etcd_sort_target_key() -> Int {
  return 0;
}

/// RangeRequest.SortTarget VERSION (1). Complexity: O(1).
pub fn etcd_sort_target_version() -> Int {
  return 1;
}

/// RangeRequest.SortTarget CREATE (2). Complexity: O(1).
pub fn etcd_sort_target_create() -> Int {
  return 2;
}

/// RangeRequest.SortTarget MOD (3). Complexity: O(1).
pub fn etcd_sort_target_mod() -> Int {
  return 3;
}

/// RangeRequest.SortTarget VALUE (4). Complexity: O(1).
pub fn etcd_sort_target_value() -> Int {
  return 4;
}

/// Compare.CompareResult EQUAL (0). Complexity: O(1).
pub fn etcd_compare_result_equal() -> Int {
  return 0;
}

/// Compare.CompareResult GREATER (1). Complexity: O(1).
pub fn etcd_compare_result_greater() -> Int {
  return 1;
}

/// Compare.CompareResult LESS (2). Complexity: O(1).
pub fn etcd_compare_result_less() -> Int {
  return 2;
}

/// Compare.CompareResult NOT_EQUAL (3). Complexity: O(1).
pub fn etcd_compare_result_not_equal() -> Int {
  return 3;
}

/// Compare.CompareTarget VERSION (0). Complexity: O(1).
pub fn etcd_compare_target_version() -> Int {
  return 0;
}

/// Compare.CompareTarget CREATE (1). Complexity: O(1).
pub fn etcd_compare_target_create() -> Int {
  return 1;
}

/// Compare.CompareTarget MOD (2). Complexity: O(1).
pub fn etcd_compare_target_mod() -> Int {
  return 2;
}

/// Compare.CompareTarget VALUE (3). Complexity: O(1).
pub fn etcd_compare_target_value() -> Int {
  return 3;
}

/// Compare.CompareTarget LEASE (4). Complexity: O(1).
pub fn etcd_compare_target_lease() -> Int {
  return 4;
}

/// Event.EventType PUT (0). Complexity: O(1).
pub fn etcd_event_put() -> Int {
  return 0;
}

/// Event.EventType DELETE (1). Complexity: O(1).
pub fn etcd_event_delete() -> Int {
  return 1;
}

/// WatchCreateRequest.FilterType NOPUT (0). Complexity: O(1).
pub fn etcd_filter_noput() -> Int {
  return 0;
}

/// WatchCreateRequest.FilterType NODELETE (1). Complexity: O(1).
pub fn etcd_filter_nodelete() -> Int {
  return 1;
}

/// AlarmType NONE (0). Complexity: O(1).
pub fn etcd_alarm_type_none() -> Int {
  return 0;
}

/// AlarmType NOSPACE (1). Complexity: O(1).
pub fn etcd_alarm_type_nospace() -> Int {
  return 1;
}

/// AlarmType CORRUPT (2). Complexity: O(1).
pub fn etcd_alarm_type_corrupt() -> Int {
  return 2;
}

/// AlarmRequest.AlarmAction GET (0). Complexity: O(1).
pub fn etcd_alarm_action_get() -> Int {
  return 0;
}

/// AlarmRequest.AlarmAction ACTIVATE (1). The port brief called this
/// "PUT"; the canonical rpc.proto enum is GET/ACTIVATE/DEACTIVATE.
/// Complexity: O(1).
pub fn etcd_alarm_action_activate() -> Int {
  return 1;
}

/// AlarmRequest.AlarmAction DEACTIVATE (2). Complexity: O(1).
pub fn etcd_alarm_action_deactivate() -> Int {
  return 2;
}

/// RequestOp/ResponseOp one-of branch: range (field 1). Complexity: O(1).
pub fn etcd_op_range() -> Int {
  return 1;
}

/// RequestOp/ResponseOp one-of branch: put (field 2). Complexity: O(1).
pub fn etcd_op_put() -> Int {
  return 2;
}

/// RequestOp/ResponseOp one-of branch: delete_range (field 3). O(1).
pub fn etcd_op_delete_range() -> Int {
  return 3;
}

/// RequestOp/ResponseOp one-of branch: txn (field 4). Complexity: O(1).
pub fn etcd_op_txn() -> Int {
  return 4;
}

// --------------------------------------------------
//  Internal scalar helpers
// --------------------------------------------------

// Smallest Int (-2^63), written so the literal itself never overflows.
fn _min_i64() -> Int {
  return -9223372036854775807 - 1;
}

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u32 at [pos, pos+4); callers guarantee the bounds.
fn _read_be32(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 16777216 + _byte(data, pos + 1) * 65536 + _byte(data, pos + 2) * 256 + _byte(data, pos + 3);
}

// Append `v` (0..2^32-1) as four big-endian bytes.
fn _push_be32(out: &mut Vec[UInt8], v: Int) {
  out.push((v / 16777216) as UInt8);
  out.push(((v / 65536) % 256) as UInt8);
  out.push(((v / 256) % 256) as UInt8);
  out.push((v % 256) as UInt8);
}

// Append every byte of `v` to `out`.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// A fresh copy of `v`.
fn _vec_copy(v: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  _push_vec(&mut out, v);
  return out;
}

// A copy of the span [start, start+size) of `data`. An out-of-bounds span
// yields an empty vector; every internal caller checks the bounds first.
fn _slice(data: &Vec[UInt8], start: Int, size: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if start < 0 || size < 0 {
    return out;
  }
  if start + size > data.len() {
    return out;
  }
  var i = 0;
  while i < size {
    out.push(data[start + i]);
    i = i + 1;
  }
  return out;
}

/// Byte-wise equality of two byte vectors. Complexity: O(bytes).
pub fn etcd_bytes_equal(a: &Vec[UInt8], b: &Vec[UInt8]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// The bytes of a Str (UTF-8, one byte per index; no NUL unless the caller
// validated it away).
fn _str_to_bytes(s: Str) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
  return out;
}

// The bytes of `v` as a Str; only called on NUL-free valid UTF-8 spans, so
// sb_to_str cannot abort.
fn _bytes_to_str(v: &Vec[UInt8]) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    sb.push(v[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Build a Str from a data span (validated by the caller).
fn _span_to_str(data: &Vec[UInt8], start: Int, size: Int) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < size {
    sb.push(data[start + i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// Strict UTF-8 validation of a data span (RFC 3629: overlong forms,
// surrogate halves and truncated sequences are rejected). Returns "" when
// valid, otherwise the deterministic error with the offending byte offset.
// A 0x00 byte is valid UTF-8 but reported separately because a NUL would
// abort the v0.61.3 string builder.
fn _utf8_span_error(data: &Vec[UInt8], start: Int, size: Int) -> Str {
  var i = 0;
  while i < size {
    let b = _byte(data, start + i);
    if b == 0 {
      return "etcd: string contains nul at offset " + convert.int_to_string(start + i);
    }
    if b < 128 {
      i = i + 1;
    } elif b < 194 {
      return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
    } elif b < 224 {
      if i + 1 >= size {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      let c1: Int = _byte(data, start + i + 1);
      if c1 < 128 || c1 >= 192 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      i = i + 2;
    } elif b < 240 {
      if i + 2 >= size {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      let c1: Int = _byte(data, start + i + 1);
      let c2: Int = _byte(data, start + i + 2);
      if c1 < 128 || c1 >= 192 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if c2 < 128 || c2 >= 192 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if b == 224 && c1 < 160 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if b == 237 && c1 >= 160 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      i = i + 3;
    } elif b < 245 {
      if i + 3 >= size {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      let c1: Int = _byte(data, start + i + 1);
      let c2: Int = _byte(data, start + i + 2);
      let c3: Int = _byte(data, start + i + 3);
      if c1 < 128 || c1 >= 192 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if c2 < 128 || c2 >= 192 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if c3 < 128 || c3 >= 192 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if b == 240 && c1 < 144 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      if b == 244 && c1 >= 144 {
        return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
      }
      i = i + 4;
    } else {
      return "etcd: invalid utf-8 at offset " + convert.int_to_string(start + i);
    }
  }
  return "";
}

// A validated Str from a data span, or the UTF-8 error.
fn _span_str(data: &Vec[UInt8], start: Int, size: Int) -> Result[Str, Str] {
  let e = _utf8_span_error(data, start, size);
  if e.len() > 0 {
    return _err_str(e);
  }
  return _ok_str(_span_to_str(data, start, size));
}

/// A validated Str from a raw byte vector (same rules as the field
/// decoders: strict UTF-8, no NUL). Complexity: O(bytes).
pub fn etcd_bytes_to_str(v: &Vec[UInt8]) -> Result[Str, Str] {
  let e = _utf8_span_error(v, 0, v.len());
  if e.len() > 0 {
    return _err_str(e);
  }
  return _ok_str(_bytes_to_str(v));
}

/// A validated Str from the span [start, start+size) of `data`.
/// Complexity: O(size).
pub fn etcd_span_to_str(data: &Vec[UInt8], start: Int, size: Int) -> Result[Str, Str] {
  if start < 0 || size < 0 || start + size > data.len() {
    return _err_str("etcd: bad message range at offset " + convert.int_to_string(start));
  }
  return _span_str(data, start, size);
}

// Deterministic depth-cap message.
fn _depth_msg(off: Int) -> Str {
  return "etcd: nesting depth exceeds limit of 16 at offset " + convert.int_to_string(off);
}

// True when `depth` is within the nesting cap.
fn _depth_ok(depth: Int) -> Bool {
  return depth <= etcd_max_depth();
}

// Deterministic bad-range message.
fn _bad_range(off: Int) -> Str {
  return "etcd: bad message range at offset " + convert.int_to_string(off);
}

// Deterministic repeated-list cap message.
fn _list_too_large(off: Int) -> Str {
  return "etcd: list too large at offset " + convert.int_to_string(off);
}

// Deterministic packed-run cap message.
fn _packed_too_large(off: Int) -> Str {
  return "etcd: packed run too large at offset " + convert.int_to_string(off);
}

// Record one unknown field: count it and preserve its tag+value bytes raw.
// Callers guarantee tag_start + len is within the buffer.
fn _note_unknown(u: &mut EtcdUnknown, data: &Vec[UInt8], tag_start: Int, len: Int) {
  u.count = u.count + 1;
  var i = 0;
  while i < len {
    u.bytes.push(data[tag_start + i]);
    i = i + 1;
  }
}

// Append one KeyValue to a flat list, mirroring every parallel vector.
fn _kvlist_push(list: &mut EtcdKvList, kv: &EtcdKeyValue) {
  let k: Vec[UInt8] = kv.key;
  let v: Vec[UInt8] = kv.value;
  list.keys.push(_vec_copy(&k));
  list.values.push(_vec_copy(&v));
  list.create_revisions.push(kv.create_revision);
  list.mod_revisions.push(kv.mod_revision);
  list.versions.push(kv.version);
  list.leases.push(kv.lease);
}

// Append one Compare to a flat list, mirroring every parallel vector.
fn _cmp_push(list: &mut EtcdCompareList, c: &EtcdCompare) {
  let k: Vec[UInt8] = c.key;
  let v: Vec[UInt8] = c.value;
  list.results.push(c.result);
  list.targets.push(c.target);
  list.keys.push(_vec_copy(&k));
  list.union_fields.push(c.union_field);
  list.versions.push(c.version);
  list.create_revisions.push(c.create_revision);
  list.mod_revisions.push(c.mod_revision);
  list.values.push(_vec_copy(&v));
  list.leases.push(c.lease);
}

// Append one op to a flat list, mirroring both parallel vectors.
fn _op_push(list: &mut EtcdOpList, op: &EtcdOp) {
  let r: Vec[UInt8] = op.raw;
  list.kinds.push(op.kind);
  list.raws.push(_vec_copy(&r));
}

// Append one Event to a WatchResponse, mirroring all 15 parallel vectors.
fn _event_push(wr: &mut EtcdWatchResponse, ev: &EtcdEvent) {
  let kv: EtcdKeyValue = ev.kv;
  let pv: EtcdKeyValue = ev.prev;
  let k: Vec[UInt8] = kv.key;
  let v: Vec[UInt8] = kv.value;
  let pk: Vec[UInt8] = pv.key;
  let pvv: Vec[UInt8] = pv.value;
  wr.event_types.push(ev.etype);
  wr.event_kv_present.push(ev.kv_present);
  wr.event_kv_keys.push(_vec_copy(&k));
  wr.event_kv_values.push(_vec_copy(&v));
  wr.event_kv_create_revisions.push(kv.create_revision);
  wr.event_kv_mod_revisions.push(kv.mod_revision);
  wr.event_kv_versions.push(kv.version);
  wr.event_kv_leases.push(kv.lease);
  wr.event_prev_present.push(ev.prev_present);
  wr.event_prev_keys.push(_vec_copy(&pk));
  wr.event_prev_values.push(_vec_copy(&pvv));
  wr.event_prev_create_revisions.push(pv.create_revision);
  wr.event_prev_mod_revisions.push(pv.mod_revision);
  wr.event_prev_versions.push(pv.version);
  wr.event_prev_leases.push(pv.lease);
}

// Append one AlarmMember to an AlarmResponse, mirroring both vectors.
fn _alarm_push(resp: &mut EtcdAlarmResponse, a: &EtcdAlarmMember) {
  resp.member_ids.push(a.member_id);
  resp.alarms.push(a.alarm);
}

// --------------------------------------------------
//  Wire primitives
// --------------------------------------------------

/// Encode a field key: field_number * 8 + wire_type. Complexity: O(1).
pub fn etcd_key(field_number: Int, wire_type: Int) -> Int {
  return field_number * 8 + wire_type;
}

/// The field number encoded in a field key. Complexity: O(1).
pub fn etcd_key_field_number(key: Int) -> Int {
  return key / 8;
}

/// The wire type encoded in a field key. Complexity: O(1).
pub fn etcd_key_wire_type(key: Int) -> Int {
  return key % 8;
}

/// Decode a base-128 varint with unsigned u64 semantics, restricted to the
/// signed 64-bit Int range: at most 10 bytes; a continuation bit on the
/// 10th byte, 10th-byte data bits above bit 0, or bit 63 set are rejected.
///
/// Err("etcd: varint out of bounds at offset P") when `pos` is not a
/// readable index; Err("etcd: truncated varint at offset N") when the
/// buffer ends mid-varint; Err("etcd: varint too long at offset P");
/// Err("etcd: varint overflows 64 bits at offset P");
/// Err("etcd: varint exceeds signed 64-bit range at offset P").
/// Complexity: O(varint bytes).
pub fn etcd_read_varint(data: &Vec[UInt8], pos: Int) -> Result[EtcdScalar, Str] {
  let n = data.len();
  if pos < 0 || pos >= n {
    return _err_scalar("etcd: varint out of bounds at offset " + convert.int_to_string(pos));
  }
  var value = 0;
  var mult = 1;
  var i = 0;
  var p = pos;
  while i < 9 {
    if p >= n {
      return _err_scalar("etcd: truncated varint at offset " + convert.int_to_string(n));
    }
    let b = _byte(data, p);
    value = value + (b % 128) * mult;
    if b < 128 {
      return _ok_scalar(EtcdScalar{ value: value; size: i + 1 });
    }
    i = i + 1;
    if i < 9 {
      mult = mult * 128;
    }
    p = p + 1;
  }
  if p >= n {
    return _err_scalar("etcd: truncated varint at offset " + convert.int_to_string(n));
  }
  let b10 = _byte(data, p);
  if b10 >= 128 {
    return _err_scalar("etcd: varint too long at offset " + convert.int_to_string(pos));
  }
  let bits = b10 % 128;
  if bits > 1 {
    return _err_scalar("etcd: varint overflows 64 bits at offset " + convert.int_to_string(pos));
  }
  if bits == 1 {
    return _err_scalar("etcd: varint exceeds signed 64-bit range at offset " + convert.int_to_string(pos));
  }
  return _ok_scalar(EtcdScalar{ value: value; size: 10 });
}

/// Decode a varint and reject values above 2^32 - 1 (u32 semantics).
/// Err("etcd: varint exceeds u32 at offset P") for larger values; every
/// other error is the same as `etcd_read_varint`.
/// Complexity: O(varint bytes).
pub fn etcd_read_varint_u32(data: &Vec[UInt8], pos: Int) -> Result[EtcdScalar, Str] {
  let r = etcd_read_varint(data, pos);
  if !r.is_ok {
    return _err_scalar(r.error);
  }
  let s: EtcdScalar = r.value;
  if s.value > 4294967295 {
    return _err_scalar("etcd: varint exceeds u32 at offset " + convert.int_to_string(pos));
  }
  return _ok_scalar(s);
}

/// Decode a varint with signed int32 semantics: the low 32 bits are the
/// value, sign-extended (proto encodes negative int32 fields as 10-byte
/// sign-extended varints, which this reader accepts).
/// Complexity: O(varint bytes).
pub fn etcd_read_varint_i32(data: &Vec[UInt8], pos: Int) -> Result[EtcdScalar, Str] {
  let n = data.len();
  if pos < 0 || pos >= n {
    return _err_scalar("etcd: varint out of bounds at offset " + convert.int_to_string(pos));
  }
  var acc = 0;
  var mult = 1;
  var i = 0;
  var p = pos;
  while i < 10 {
    if p >= n {
      return _err_scalar("etcd: truncated varint at offset " + convert.int_to_string(n));
    }
    let b = _byte(data, p);
    if i < 5 {
      acc = acc + (b % 128) * mult;
    }
    if b < 128 {
      let low = acc % 4294967296;
      var v = low;
      if low >= 2147483648 {
        v = low - 4294967296;
      }
      return _ok_scalar(EtcdScalar{ value: v; size: i + 1 });
    }
    if i < 4 {
      mult = mult * 128;
    }
    i = i + 1;
    p = p + 1;
  }
  return _err_scalar("etcd: varint too long at offset " + convert.int_to_string(pos));
}

/// Decode a varint with the full signed int64 range: a 10-byte varint whose
/// 10th byte carries bit 63 yields a negative value (two's complement), so
/// sign-extended negative int64 fields decode exactly.
/// Complexity: O(varint bytes).
pub fn etcd_read_varint_i64(data: &Vec[UInt8], pos: Int) -> Result[EtcdScalar, Str] {
  let n = data.len();
  if pos < 0 || pos >= n {
    return _err_scalar("etcd: varint out of bounds at offset " + convert.int_to_string(pos));
  }
  var value = 0;
  var mult = 1;
  var i = 0;
  var p = pos;
  while i < 9 {
    if p >= n {
      return _err_scalar("etcd: truncated varint at offset " + convert.int_to_string(n));
    }
    let b = _byte(data, p);
    value = value + (b % 128) * mult;
    if b < 128 {
      return _ok_scalar(EtcdScalar{ value: value; size: i + 1 });
    }
    i = i + 1;
    if i < 9 {
      mult = mult * 128;
    }
    p = p + 1;
  }
  if p >= n {
    return _err_scalar("etcd: truncated varint at offset " + convert.int_to_string(n));
  }
  let b10 = _byte(data, p);
  if b10 >= 128 {
    return _err_scalar("etcd: varint too long at offset " + convert.int_to_string(pos));
  }
  let bits = b10 % 128;
  if bits == 0 {
    return _ok_scalar(EtcdScalar{ value: value; size: 10 });
  }
  if bits == 1 {
    return _ok_scalar(EtcdScalar{ value: value + _min_i64(); size: 10 });
  }
  return _err_scalar("etcd: varint overflows 64 bits at offset " + convert.int_to_string(pos));
}

/// Decode a little-endian fixed32 (wire type 5).
/// Err("etcd: truncated fixed32 at offset N") when 4 bytes are not
/// available (N = first missing byte). Complexity: O(1).
pub fn etcd_read_fixed32(data: &Vec[UInt8], pos: Int) -> Result[EtcdScalar, Str] {
  let n = data.len();
  if pos < 0 || pos + 4 > n {
    return _err_scalar("etcd: truncated fixed32 at offset " + convert.int_to_string(n));
  }
  let v = _byte(data, pos) + _byte(data, pos + 1) * 256 + _byte(data, pos + 2) * 65536 + _byte(data, pos + 3) * 16777216;
  return _ok_scalar(EtcdScalar{ value: v; size: 4 });
}

/// Decode a little-endian fixed64 (wire type 1) into the signed Int range.
/// Err("etcd: truncated fixed64 at offset N") when 8 bytes are not
/// available; Err("etcd: fixed64 exceeds signed 64-bit range at offset P")
/// when bit 63 is set. Complexity: O(1).
pub fn etcd_read_fixed64(data: &Vec[UInt8], pos: Int) -> Result[EtcdScalar, Str] {
  let n = data.len();
  if pos < 0 || pos + 8 > n {
    return _err_scalar("etcd: truncated fixed64 at offset " + convert.int_to_string(n));
  }
  let hi = _byte(data, pos + 4) + _byte(data, pos + 5) * 256 + _byte(data, pos + 6) * 65536 + _byte(data, pos + 7) * 16777216;
  if hi >= 2147483648 {
    return _err_scalar("etcd: fixed64 exceeds signed 64-bit range at offset " + convert.int_to_string(pos));
  }
  let lo = _byte(data, pos) + _byte(data, pos + 1) * 256 + _byte(data, pos + 2) * 65536 + _byte(data, pos + 3) * 16777216;
  return _ok_scalar(EtcdScalar{ value: hi * 4294967296 + lo; size: 8 });
}

/// Read a length-delimited value (wire type 2): a u32 varint length at
/// `pos` followed by that many payload bytes.
/// Err("etcd: truncated length-delimited field at offset N") when the
/// prefix or the payload does not fit (N = first missing byte);
/// Err("etcd: truncated varint at offset N") for a clipped length prefix;
/// Err("etcd: varint exceeds u32 at offset P") for a length above 2^32 - 1.
/// Complexity: O(1).
pub fn etcd_read_delimited(data: &Vec[UInt8], pos: Int) -> Result[EtcdDelimited, Str] {
  let lr = etcd_read_varint_u32(data, pos);
  if !lr.is_ok {
    return _err_delim(lr.error);
  }
  let ls: EtcdScalar = lr.value;
  let start = pos + ls.size;
  let n = data.len();
  if start + ls.value > n {
    return _err_delim("etcd: truncated length-delimited field at offset " + convert.int_to_string(n));
  }
  return _ok_delim(EtcdDelimited{ start: start; size: ls.value; total: ls.size + ls.value });
}

/// Skip one field value of wire type 0/1/2/5 and return the new position
/// plus the bytes consumed.
/// Err("etcd: unsupported wire type W at offset P") for group/other wire
/// types; truncation errors as in the matching reader.
/// Complexity: O(value bytes).
pub fn etcd_skip_field(data: &Vec[UInt8], pos: Int, wire_type: Int) -> Result[EtcdAdvance, Str] {
  if wire_type == 0 {
    let r = etcd_read_varint(data, pos);
    if !r.is_ok {
      return _err_advance(r.error);
    }
    let s: EtcdScalar = r.value;
    return _ok_advance(EtcdAdvance{ pos: pos + s.size; size: s.size });
  }
  if wire_type == 1 {
    let n = data.len();
    if pos < 0 || pos + 8 > n {
      return _err_advance("etcd: truncated fixed64 at offset " + convert.int_to_string(n));
    }
    return _ok_advance(EtcdAdvance{ pos: pos + 8; size: 8 });
  }
  if wire_type == 2 {
    let r = etcd_read_delimited(data, pos);
    if !r.is_ok {
      return _err_advance(r.error);
    }
    let d: EtcdDelimited = r.value;
    return _ok_advance(EtcdAdvance{ pos: pos + d.total; size: d.total });
  }
  if wire_type == 5 {
    let n = data.len();
    if pos < 0 || pos + 4 > n {
      return _err_advance("etcd: truncated fixed32 at offset " + convert.int_to_string(n));
    }
    return _ok_advance(EtcdAdvance{ pos: pos + 4; size: 4 });
  }
  return _err_advance("etcd: unsupported wire type " + convert.int_to_string(wire_type) + " at offset " + convert.int_to_string(pos));
}

/// Decode a packed repeated varint run occupying [start, end) and append
/// every value to `out`; returns the number of values decoded.
/// Err("etcd: packed run crosses boundary at offset P") when a varint
/// crosses `end`; Err("etcd: packed run too large at offset S") above
/// etcd_max_packed_entries(); varint errors as in `etcd_read_varint`.
/// Complexity: O(run bytes).
pub fn etcd_read_packed_varints(data: &Vec[UInt8], start: Int, end: Int, out: &mut Vec[Int]) -> Result[Int, Str] {
  var pos = start;
  var count = 0;
  while pos < end {
    if count >= etcd_max_packed_entries() {
      return _err_int(_packed_too_large(start));
    }
    let r = etcd_read_varint(data, pos);
    if !r.is_ok {
      return _err_int(r.error);
    }
    let s: EtcdScalar = r.value;
    if pos + s.size > end {
      return _err_int("etcd: packed run crosses boundary at offset " + convert.int_to_string(pos));
    }
    out.push(s.value);
    pos = pos + s.size;
    count = count + 1;
  }
  return _ok_int(count);
}

// Decode one field value (without the key) at `pos`.
fn _field_value(data: &Vec[UInt8], pos: Int, wire_type: Int) -> Result[EtcdFieldValue, Str] {
  if wire_type == 0 {
    let r = etcd_read_varint_i64(data, pos);
    if !r.is_ok {
      return _err_fv(r.error);
    }
    let s: EtcdScalar = r.value;
    return _ok_fv(EtcdFieldValue{ wire_type: 0; int_value: s.value; start: 0; size: 0; total: s.size });
  }
  if wire_type == 1 {
    let r = etcd_read_fixed64(data, pos);
    if !r.is_ok {
      return _err_fv(r.error);
    }
    let s: EtcdScalar = r.value;
    return _ok_fv(EtcdFieldValue{ wire_type: 1; int_value: s.value; start: 0; size: 0; total: 8 });
  }
  if wire_type == 2 {
    let r = etcd_read_delimited(data, pos);
    if !r.is_ok {
      return _err_fv(r.error);
    }
    let d: EtcdDelimited = r.value;
    return _ok_fv(EtcdFieldValue{ wire_type: 2; int_value: 0; start: d.start; size: d.size; total: d.total });
  }
  if wire_type == 5 {
    let r = etcd_read_fixed32(data, pos);
    if !r.is_ok {
      return _err_fv(r.error);
    }
    let s: EtcdScalar = r.value;
    return _ok_fv(EtcdFieldValue{ wire_type: 5; int_value: s.value; start: 0; size: 0; total: 4 });
  }
  return _err_fv("etcd: unsupported wire type " + convert.int_to_string(wire_type) + " at offset " + convert.int_to_string(pos));
}

// Read one whole field (key + value) that must fit inside [pos, end).
fn _field_step(data: &Vec[UInt8], pos: Int, end: Int) -> Result[EtcdFieldStep, Str] {
  let kr = etcd_read_varint_u32(data, pos);
  if !kr.is_ok {
    return _err_step(kr.error);
  }
  let ks: EtcdScalar = kr.value;
  let fnum = ks.value / 8;
  let wt = ks.value % 8;
  if fnum < 1 {
    return _err_step("etcd: field number 0 at offset " + convert.int_to_string(pos));
  }
  let vpos = pos + ks.size;
  if vpos > end {
    return _err_step("etcd: truncated field at offset " + convert.int_to_string(end));
  }
  let vr = _field_value(data, vpos, wt);
  if !vr.is_ok {
    return _err_step(vr.error);
  }
  let fv: EtcdFieldValue = vr.value;
  if vpos + fv.total > end {
    return _err_step("etcd: field crosses message boundary at offset " + convert.int_to_string(vpos));
  }
  return _ok_step(EtcdFieldStep{ field_number: fnum; wire_type: wt; tag_start: pos; key_size: ks.size; value: fv; next: vpos + fv.total });
}

// Append `v` (>= 0) as a base-128 varint.
fn _push_varint_raw(out: &mut Vec[UInt8], v: Int) {
  var x = v;
  while x >= 128 {
    out.push(((x % 128) + 128) as UInt8);
    x = x / 128;
  }
  out.push(x as UInt8);
}

/// Encode a non-negative Int as a standalone varint.
/// Err("etcd: negative varint value") for negative input.
/// Complexity: O(varint bytes).
pub fn etcd_encode_varint(v: Int) -> Result[Vec[UInt8], Str] {
  if v < 0 {
    return _err_bytes("etcd: negative varint value");
  }
  var out = Vec[UInt8].new();
  _push_varint_raw(&mut out, v);
  return _ok_bytes(out);
}

/// Encode a field key. Err("etcd: bad field number") unless field_number
/// is in 1..536870911; Err("etcd: bad wire type") unless the wire type is
/// 0/1/2/5. Complexity: O(1).
pub fn etcd_encode_key(field_number: Int, wire_type: Int) -> Result[Vec[UInt8], Str] {
  if field_number < 1 || field_number > 536870911 {
    return _err_bytes("etcd: bad field number");
  }
  if wire_type != 0 && wire_type != 1 && wire_type != 2 && wire_type != 5 {
    return _err_bytes("etcd: bad wire type");
  }
  var out = Vec[UInt8].new();
  _push_varint_raw(&mut out, field_number * 8 + wire_type);
  return _ok_bytes(out);
}

/// Build a complete gRPC frame: 1 flag byte | u32 BE message length |
/// message bytes. `compressed` is written verbatim (gRPC uses 0 or 1);
/// `message.len()` above 2^32 - 1 would truncate and is a caller violation.
/// Complexity: O(message bytes).
pub fn etcd_encode_frame(message: &Vec[UInt8], compressed: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  out.push(compressed as UInt8);
  _push_be32(&mut out, message.len());
  _push_vec(&mut out, message);
  return out;
}

// --------------------------------------------------
//  gRPC frame
// --------------------------------------------------

/// Parse one gRPC frame starting at `offset`. The buffer must contain the
/// whole frame; bytes after it are ignored and `EtcdFrame.frame_len` is the
/// consumed count (5 + message length).
///
/// Layout: 1 compressed-flag byte | u32 BE message length | message bytes.
///
/// Err("etcd: negative frame offset"); Err("etcd: truncated grpc frame
/// header at offset N"); Err("etcd: grpc message exceeds 8 MiB at offset
/// P") for a declared length above etcd_max_message_bytes();
/// Err("etcd: truncated grpc frame at offset N"). N is the first missing
/// byte. The flag is preserved raw and never interpreted.
/// Complexity: O(message bytes).
pub fn etcd_parse_frame_at(data: &Vec[UInt8], offset: Int) -> Result[EtcdFrame, Str] {
  let n = data.len();
  if offset < 0 {
    return _err_frame("etcd: negative frame offset");
  }
  if offset + 5 > n {
    return _err_frame("etcd: truncated grpc frame header at offset " + convert.int_to_string(n));
  }
  let flag = _byte(data, offset);
  let length = _read_be32(data, offset + 1);
  if length > etcd_max_message_bytes() {
    return _err_frame("etcd: grpc message exceeds 8 MiB at offset " + convert.int_to_string(offset));
  }
  if offset + 5 + length > n {
    return _err_frame("etcd: truncated grpc frame at offset " + convert.int_to_string(n));
  }
  let message = _slice(data, offset + 5, length);
  return _ok_frame(EtcdFrame{
    compressed: flag; length: length; message: message;
    frame_len: 5 + length; offset: offset;
  });
}

/// Parse one gRPC frame at offset 0 (see `etcd_parse_frame_at`).
/// Complexity: O(message bytes).
pub fn etcd_parse_frame(data: &Vec[UInt8]) -> Result[EtcdFrame, Str] {
  return etcd_parse_frame_at(data, 0);
}

// --------------------------------------------------
//  ResponseHeader and KeyValue
// --------------------------------------------------

/// Decode a ResponseHeader body occupying [start, end) at nesting `depth`.
/// Fields: 1 cluster_id, 2 member_id, 3 revision, 4 raft_term. `present`
/// records whether any of them appeared on the wire.
/// Complexity: O(body bytes).
pub fn etcd_parse_header_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdHeader, Str] {
  if !_depth_ok(depth) {
    return _err_header(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_header(_bad_range(start));
  }
  var msg = etcd_header_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_header(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.cluster_id = fv.int_value;
      msg.present = true;
    } elif fnum == 2 && wt == 0 {
      msg.member_id = fv.int_value;
      msg.present = true;
    } elif fnum == 3 && wt == 0 {
      msg.revision = fv.int_value;
      msg.present = true;
    } elif fnum == 4 && wt == 0 {
      msg.raft_term = fv.int_value;
      msg.present = true;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_header(msg);
}

/// Decode a whole ResponseHeader message. Complexity: O(body bytes).
pub fn etcd_decode_header(data: &Vec[UInt8]) -> Result[EtcdHeader, Str] {
  return etcd_parse_header_body(data, 0, data.len(), 1);
}

/// Decode a KeyValue body occupying [start, end) at nesting `depth`.
/// Fields: 1 key, 2 create_revision, 3 mod_revision, 4 version, 5 value,
/// 6 lease. Complexity: O(body bytes).
pub fn etcd_parse_key_value_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdKeyValue, Str] {
  if !_depth_ok(depth) {
    return _err_kv(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_kv(_bad_range(start));
  }
  var msg = etcd_key_value_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_kv(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      msg.key = _slice(data, fv.start, fv.size);
    } elif fnum == 2 && wt == 0 {
      msg.create_revision = fv.int_value;
    } elif fnum == 3 && wt == 0 {
      msg.mod_revision = fv.int_value;
    } elif fnum == 4 && wt == 0 {
      msg.version = fv.int_value;
    } elif fnum == 5 && wt == 2 {
      msg.value = _slice(data, fv.start, fv.size);
    } elif fnum == 6 && wt == 0 {
      msg.lease = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_kv(msg);
}

/// Decode a whole KeyValue message. Complexity: O(body bytes).
pub fn etcd_decode_key_value(data: &Vec[UInt8]) -> Result[EtcdKeyValue, Str] {
  return etcd_parse_key_value_body(data, 0, data.len(), 1);
}

// --------------------------------------------------
//  Range
// --------------------------------------------------

/// Decode a RangeRequest body occupying [start, end) at nesting `depth`.
/// Fields: 1 key, 2 range_end, 3 limit, 4 revision, 5 sort_order,
/// 6 sort_target, 7 serializable, 8 keys_only, 9 count_only,
/// 10 min_mod_revision, 11 max_mod_revision, 12 min_create_revision,
/// 13 max_create_revision. Complexity: O(body bytes).
pub fn etcd_parse_range_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdRangeRequest, Str] {
  if !_depth_ok(depth) {
    return _err_range_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_range_req(_bad_range(start));
  }
  var msg = etcd_range_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_range_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      msg.key = _slice(data, fv.start, fv.size);
    } elif fnum == 2 && wt == 2 {
      msg.range_end = _slice(data, fv.start, fv.size);
    } elif fnum == 3 && wt == 0 {
      msg.limit = fv.int_value;
    } elif fnum == 4 && wt == 0 {
      msg.revision = fv.int_value;
    } elif fnum == 5 && wt == 0 {
      msg.sort_order = fv.int_value;
    } elif fnum == 6 && wt == 0 {
      msg.sort_target = fv.int_value;
    } elif fnum == 7 && wt == 0 {
      if fv.int_value != 0 {
        msg.serializable = true;
      } else {
        msg.serializable = false;
      }
    } elif fnum == 8 && wt == 0 {
      if fv.int_value != 0 {
        msg.keys_only = true;
      } else {
        msg.keys_only = false;
      }
    } elif fnum == 9 && wt == 0 {
      if fv.int_value != 0 {
        msg.count_only = true;
      } else {
        msg.count_only = false;
      }
    } elif fnum == 10 && wt == 0 {
      msg.min_mod_revision = fv.int_value;
    } elif fnum == 11 && wt == 0 {
      msg.max_mod_revision = fv.int_value;
    } elif fnum == 12 && wt == 0 {
      msg.min_create_revision = fv.int_value;
    } elif fnum == 13 && wt == 0 {
      msg.max_create_revision = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_range_req(msg);
}

/// Decode a whole RangeRequest message. Complexity: O(body bytes).
pub fn etcd_decode_range_request(data: &Vec[UInt8]) -> Result[EtcdRangeRequest, Str] {
  return etcd_parse_range_request_body(data, 0, data.len(), 1);
}

/// Decode a RangeResponse body occupying [start, end) at nesting `depth`.
/// Fields: 1 header, 2 repeated kvs, 3 more, 4 count.
/// Complexity: O(body bytes).
pub fn etcd_parse_range_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdRangeResponse, Str] {
  if !_depth_ok(depth) {
    return _err_range_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_range_resp(_bad_range(start));
  }
  var msg = etcd_range_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_range_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_range_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 2 {
      if msg.kvs.keys.len() >= etcd_max_list_entries() {
        return _err_range_resp(_list_too_large(pos));
      }
      let kr = etcd_parse_key_value_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !kr.is_ok {
        return _err_range_resp(kr.error);
      }
      let kv: EtcdKeyValue = kr.value;
      _kvlist_push(&mut msg.kvs, &kv);
    } elif fnum == 3 && wt == 0 {
      if fv.int_value != 0 {
        msg.more = true;
      } else {
        msg.more = false;
      }
    } elif fnum == 4 && wt == 0 {
      msg.count = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_range_resp(msg);
}

/// Decode a whole RangeResponse message. Complexity: O(body bytes).
pub fn etcd_decode_range_response(data: &Vec[UInt8]) -> Result[EtcdRangeResponse, Str] {
  return etcd_parse_range_response_body(data, 0, data.len(), 1);
}

// --------------------------------------------------
//  Put and DeleteRange
// --------------------------------------------------

/// Decode a PutRequest body occupying [start, end) at nesting `depth`.
/// Fields: 1 key, 2 value, 3 lease, 4 prev_kv, 5 ignore_value,
/// 6 ignore_lease. Complexity: O(body bytes).
pub fn etcd_parse_put_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdPutRequest, Str] {
  if !_depth_ok(depth) {
    return _err_put_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_put_req(_bad_range(start));
  }
  var msg = etcd_put_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_put_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      msg.key = _slice(data, fv.start, fv.size);
    } elif fnum == 2 && wt == 2 {
      msg.value = _slice(data, fv.start, fv.size);
    } elif fnum == 3 && wt == 0 {
      msg.lease = fv.int_value;
    } elif fnum == 4 && wt == 0 {
      if fv.int_value != 0 {
        msg.prev_kv = true;
      } else {
        msg.prev_kv = false;
      }
    } elif fnum == 5 && wt == 0 {
      if fv.int_value != 0 {
        msg.ignore_value = true;
      } else {
        msg.ignore_value = false;
      }
    } elif fnum == 6 && wt == 0 {
      if fv.int_value != 0 {
        msg.ignore_lease = true;
      } else {
        msg.ignore_lease = false;
      }
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_put_req(msg);
}

/// Decode a whole PutRequest message. Complexity: O(body bytes).
pub fn etcd_decode_put_request(data: &Vec[UInt8]) -> Result[EtcdPutRequest, Str] {
  return etcd_parse_put_request_body(data, 0, data.len(), 1);
}

/// Decode a PutResponse body occupying [start, end) at nesting `depth`.
/// Fields: 1 header, 2 prev_kv. Complexity: O(body bytes).
pub fn etcd_parse_put_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdPutResponse, Str] {
  if !_depth_ok(depth) {
    return _err_put_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_put_resp(_bad_range(start));
  }
  var msg = etcd_put_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_put_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_put_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 2 {
      let kr = etcd_parse_key_value_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !kr.is_ok {
        return _err_put_resp(kr.error);
      }
      let kv: EtcdKeyValue = kr.value;
      msg.prev_kv = kv;
      msg.has_prev_kv = true;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_put_resp(msg);
}

/// Decode a whole PutResponse message. Complexity: O(body bytes).
pub fn etcd_decode_put_response(data: &Vec[UInt8]) -> Result[EtcdPutResponse, Str] {
  return etcd_parse_put_response_body(data, 0, data.len(), 1);
}

/// Decode a DeleteRangeRequest body occupying [start, end) at nesting
/// `depth`. Fields: 1 key, 2 range_end, 3 prev_kv.
/// Complexity: O(body bytes).
pub fn etcd_parse_delete_range_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdDeleteRangeRequest, Str] {
  if !_depth_ok(depth) {
    return _err_del_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_del_req(_bad_range(start));
  }
  var msg = etcd_delete_range_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_del_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      msg.key = _slice(data, fv.start, fv.size);
    } elif fnum == 2 && wt == 2 {
      msg.range_end = _slice(data, fv.start, fv.size);
    } elif fnum == 3 && wt == 0 {
      if fv.int_value != 0 {
        msg.prev_kv = true;
      } else {
        msg.prev_kv = false;
      }
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_del_req(msg);
}

/// Decode a whole DeleteRangeRequest message. Complexity: O(body bytes).
pub fn etcd_decode_delete_range_request(data: &Vec[UInt8]) -> Result[EtcdDeleteRangeRequest, Str] {
  return etcd_parse_delete_range_request_body(data, 0, data.len(), 1);
}

/// Decode a DeleteRangeResponse body occupying [start, end) at nesting
/// `depth`. Fields: 1 header, 2 deleted, 3 repeated prev_kvs.
/// Complexity: O(body bytes).
pub fn etcd_parse_delete_range_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdDeleteRangeResponse, Str] {
  if !_depth_ok(depth) {
    return _err_del_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_del_resp(_bad_range(start));
  }
  var msg = etcd_delete_range_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_del_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_del_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 0 {
      msg.deleted = fv.int_value;
    } elif fnum == 3 && wt == 2 {
      if msg.prev_kvs.keys.len() >= etcd_max_list_entries() {
        return _err_del_resp(_list_too_large(pos));
      }
      let kr = etcd_parse_key_value_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !kr.is_ok {
        return _err_del_resp(kr.error);
      }
      let kv: EtcdKeyValue = kr.value;
      _kvlist_push(&mut msg.prev_kvs, &kv);
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_del_resp(msg);
}

/// Decode a whole DeleteRangeResponse message. Complexity: O(body bytes).
pub fn etcd_decode_delete_range_response(data: &Vec[UInt8]) -> Result[EtcdDeleteRangeResponse, Str] {
  return etcd_parse_delete_range_response_body(data, 0, data.len(), 1);
}

// --------------------------------------------------
//  Compare, RequestOp/ResponseOp and Txn
// --------------------------------------------------

/// Decode a Compare body occupying [start, end) at nesting `depth`.
/// Fields: 1 result, 2 target, 3 key, 4 version, 5 create_revision,
/// 6 mod_revision, 7 value, 8 lease. The target_union field number that
/// appeared is recorded in `union_field`.
/// Complexity: O(body bytes).
pub fn etcd_parse_compare_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdCompare, Str] {
  if !_depth_ok(depth) {
    return _err_cmp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_cmp(_bad_range(start));
  }
  var msg = etcd_compare_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_cmp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.result = fv.int_value;
    } elif fnum == 2 && wt == 0 {
      msg.target = fv.int_value;
    } elif fnum == 3 && wt == 2 {
      msg.key = _slice(data, fv.start, fv.size);
    } elif fnum == 4 && wt == 0 {
      msg.version = fv.int_value;
      msg.union_field = 4;
    } elif fnum == 5 && wt == 0 {
      msg.create_revision = fv.int_value;
      msg.union_field = 5;
    } elif fnum == 6 && wt == 0 {
      msg.mod_revision = fv.int_value;
      msg.union_field = 6;
    } elif fnum == 7 && wt == 2 {
      msg.value = _slice(data, fv.start, fv.size);
      msg.union_field = 7;
    } elif fnum == 8 && wt == 0 {
      msg.lease = fv.int_value;
      msg.union_field = 8;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_cmp(msg);
}

/// Decode a whole Compare message. Complexity: O(body bytes).
pub fn etcd_decode_compare(data: &Vec[UInt8]) -> Result[EtcdCompare, Str] {
  return etcd_parse_compare_body(data, 0, data.len(), 1);
}

/// Decode a RequestOp/ResponseOp body occupying [start, end) at nesting
/// `depth`. The one-of branch is recorded as `kind` (1 range, 2 put,
/// 3 delete_range, 4 txn) and its nested body is preserved raw in `raw`
/// so it can be re-decoded with the matching body parser; a body without
/// a branch has kind 0.
/// Complexity: O(body bytes).
pub fn etcd_parse_op_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdOp, Str] {
  if !_depth_ok(depth) {
    return _err_op(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_op(_bad_range(start));
  }
  var msg = etcd_op_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_op(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum >= 1 && fnum <= 4 && wt == 2 {
      msg.kind = fnum;
      msg.raw = _slice(data, fv.start, fv.size);
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_op(msg);
}

/// Decode a whole RequestOp/ResponseOp message. Complexity: O(body bytes).
pub fn etcd_decode_op(data: &Vec[UInt8]) -> Result[EtcdOp, Str] {
  return etcd_parse_op_body(data, 0, data.len(), 1);
}

/// Decode a TxnRequest body occupying [start, end) at nesting `depth`.
/// Fields: 1 repeated compare, 2 repeated success RequestOp, 3 repeated
/// failure RequestOp. Complexity: O(body bytes).
pub fn etcd_parse_txn_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdTxnRequest, Str] {
  if !_depth_ok(depth) {
    return _err_txn_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_txn_req(_bad_range(start));
  }
  var msg = etcd_txn_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_txn_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      if msg.compares.results.len() >= etcd_max_list_entries() {
        return _err_txn_req(_list_too_large(pos));
      }
      let cr = etcd_parse_compare_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !cr.is_ok {
        return _err_txn_req(cr.error);
      }
      let c: EtcdCompare = cr.value;
      _cmp_push(&mut msg.compares, &c);
    } elif fnum == 2 && wt == 2 {
      if msg.success.kinds.len() >= etcd_max_list_entries() {
        return _err_txn_req(_list_too_large(pos));
      }
      let opr = etcd_parse_op_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !opr.is_ok {
        return _err_txn_req(opr.error);
      }
      let op: EtcdOp = opr.value;
      _op_push(&mut msg.success, &op);
    } elif fnum == 3 && wt == 2 {
      if msg.failure.kinds.len() >= etcd_max_list_entries() {
        return _err_txn_req(_list_too_large(pos));
      }
      let opr = etcd_parse_op_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !opr.is_ok {
        return _err_txn_req(opr.error);
      }
      let op: EtcdOp = opr.value;
      _op_push(&mut msg.failure, &op);
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_txn_req(msg);
}

/// Decode a whole TxnRequest message. Complexity: O(body bytes).
pub fn etcd_decode_txn_request(data: &Vec[UInt8]) -> Result[EtcdTxnRequest, Str] {
  return etcd_parse_txn_request_body(data, 0, data.len(), 1);
}

/// Decode a TxnResponse body occupying [start, end) at nesting `depth`.
/// Fields: 1 header, 2 succeeded, 3 repeated ResponseOp.
/// Complexity: O(body bytes).
pub fn etcd_parse_txn_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdTxnResponse, Str] {
  if !_depth_ok(depth) {
    return _err_txn_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_txn_resp(_bad_range(start));
  }
  var msg = etcd_txn_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_txn_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_txn_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 0 {
      if fv.int_value != 0 {
        msg.succeeded = true;
      } else {
        msg.succeeded = false;
      }
    } elif fnum == 3 && wt == 2 {
      if msg.responses.kinds.len() >= etcd_max_list_entries() {
        return _err_txn_resp(_list_too_large(pos));
      }
      let opr = etcd_parse_op_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !opr.is_ok {
        return _err_txn_resp(opr.error);
      }
      let op: EtcdOp = opr.value;
      _op_push(&mut msg.responses, &op);
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_txn_resp(msg);
}

/// Decode a whole TxnResponse message. Complexity: O(body bytes).
pub fn etcd_decode_txn_response(data: &Vec[UInt8]) -> Result[EtcdTxnResponse, Str] {
  return etcd_parse_txn_response_body(data, 0, data.len(), 1);
}

// --------------------------------------------------
//  Compaction
// --------------------------------------------------

/// Decode a CompactionRequest body occupying [start, end) at nesting
/// `depth`. Fields: 1 revision, 2 physical.
/// Complexity: O(body bytes).
pub fn etcd_parse_compaction_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdCompactionRequest, Str] {
  if !_depth_ok(depth) {
    return _err_compact(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_compact(_bad_range(start));
  }
  var msg = etcd_compaction_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_compact(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.revision = fv.int_value;
    } elif fnum == 2 && wt == 0 {
      if fv.int_value != 0 {
        msg.physical = true;
      } else {
        msg.physical = false;
      }
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_compact(msg);
}

/// Decode a whole CompactionRequest message. Complexity: O(body bytes).
pub fn etcd_decode_compaction_request(data: &Vec[UInt8]) -> Result[EtcdCompactionRequest, Str] {
  return etcd_parse_compaction_request_body(data, 0, data.len(), 1);
}

// --------------------------------------------------
//  Watch
// --------------------------------------------------

/// Decode an Event body occupying [start, end) at nesting `depth`.
/// Fields: 1 type, 2 kv, 3 prev_kv.
/// Complexity: O(body bytes).
pub fn etcd_parse_event_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdEvent, Str] {
  if !_depth_ok(depth) {
    return _err_event(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_event(_bad_range(start));
  }
  var msg = etcd_event_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_event(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.etype = fv.int_value;
    } elif fnum == 2 && wt == 2 {
      let kr = etcd_parse_key_value_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !kr.is_ok {
        return _err_event(kr.error);
      }
      let kv: EtcdKeyValue = kr.value;
      msg.kv = kv;
      msg.kv_present = 1;
    } elif fnum == 3 && wt == 2 {
      let kr = etcd_parse_key_value_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !kr.is_ok {
        return _err_event(kr.error);
      }
      let kv: EtcdKeyValue = kr.value;
      msg.prev = kv;
      msg.prev_present = 1;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_event(msg);
}

/// Decode a whole Event message. Complexity: O(body bytes).
pub fn etcd_decode_event(data: &Vec[UInt8]) -> Result[EtcdEvent, Str] {
  return etcd_parse_event_body(data, 0, data.len(), 1);
}

/// Decode a WatchCreateRequest body and fold it into `msg` (the enclosing
/// WatchRequest), setting kind 1. Fields: 1 key, 2 range_end,
/// 3 start_revision, 4 progress_notify, 5 filters (unpacked or packed),
/// 6 prev_kv, 7 watch_id, 8 fragment.
/// Complexity: O(body bytes).
fn _watch_create_into(data: &Vec[UInt8], start: Int, end: Int, depth: Int, msg: &mut EtcdWatchRequest) -> Result[Unit, Str] {
  if !_depth_ok(depth) {
    return _err_unit(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_unit(_bad_range(start));
  }
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_unit(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      msg.key = _slice(data, fv.start, fv.size);
    } elif fnum == 2 && wt == 2 {
      msg.range_end = _slice(data, fv.start, fv.size);
    } elif fnum == 3 && wt == 0 {
      msg.start_revision = fv.int_value;
    } elif fnum == 4 && wt == 0 {
      if fv.int_value != 0 {
        msg.progress_notify = true;
      } else {
        msg.progress_notify = false;
      }
    } elif fnum == 5 && wt == 0 {
      if msg.filters.len() >= etcd_max_list_entries() {
        return _err_unit(_list_too_large(pos));
      }
      msg.filters.push(fv.int_value);
    } elif fnum == 5 && wt == 2 {
      var vals = Vec[Int].new();
      let pr = etcd_read_packed_varints(data, fv.start, fv.start + fv.size, &mut vals);
      if !pr.is_ok {
        return _err_unit(pr.error);
      }
      if msg.filters.len() + vals.len() > etcd_max_list_entries() {
        return _err_unit(_list_too_large(pos));
      }
      var i = 0;
      while i < vals.len() {
        let v: Int = vals[i];
        msg.filters.push(v);
        i = i + 1;
      }
    } elif fnum == 6 && wt == 0 {
      if fv.int_value != 0 {
        msg.prev_kv = true;
      } else {
        msg.prev_kv = false;
      }
    } elif fnum == 7 && wt == 0 {
      msg.watch_id = fv.int_value;
    } elif fnum == 8 && wt == 0 {
      if fv.int_value != 0 {
        msg.fragment = true;
      } else {
        msg.fragment = false;
      }
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_unit();
}

/// Decode a WatchCancelRequest body and fold it into `msg`, setting
/// kind 2. Field: 1 watch_id.
/// Complexity: O(body bytes).
fn _watch_cancel_into(data: &Vec[UInt8], start: Int, end: Int, depth: Int, msg: &mut EtcdWatchRequest) -> Result[Unit, Str] {
  if !_depth_ok(depth) {
    return _err_unit(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_unit(_bad_range(start));
  }
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_unit(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.cancel_watch_id = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_unit();
}

/// Decode a WatchRequest body occupying [start, end) at nesting `depth`.
/// The one-of request_union: 1 create_request, 2 cancel_request,
/// 3 progress_request (recorded as kind 3, no fields). A later branch
/// replaces an earlier one's discriminator; decoded create fields stay.
/// Complexity: O(body bytes).
pub fn etcd_parse_watch_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdWatchRequest, Str] {
  if !_depth_ok(depth) {
    return _err_watch_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_watch_req(_bad_range(start));
  }
  var msg = etcd_watch_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_watch_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      msg.kind = 1;
      let cr = _watch_create_into(data, fv.start, fv.start + fv.size, depth + 1, &mut msg);
      if !cr.is_ok {
        return _err_watch_req(cr.error);
      }
    } elif fnum == 2 && wt == 2 {
      msg.kind = 2;
      let cr = _watch_cancel_into(data, fv.start, fv.start + fv.size, depth + 1, &mut msg);
      if !cr.is_ok {
        return _err_watch_req(cr.error);
      }
    } elif fnum == 3 && wt == 2 {
      msg.kind = 3;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_watch_req(msg);
}

/// Decode a whole WatchRequest message. Complexity: O(body bytes).
pub fn etcd_decode_watch_request(data: &Vec[UInt8]) -> Result[EtcdWatchRequest, Str] {
  return etcd_parse_watch_request_body(data, 0, data.len(), 1);
}

/// Decode a WatchResponse body occupying [start, end) at nesting `depth`.
/// Fields: 1 header, 2 watch_id, 3 created, 4 canceled, 5 compact_revision,
/// 6 cancel_reason, 7 fragment, 11 repeated events.
/// Complexity: O(body bytes).
pub fn etcd_parse_watch_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdWatchResponse, Str] {
  if !_depth_ok(depth) {
    return _err_watch_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_watch_resp(_bad_range(start));
  }
  var msg = etcd_watch_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_watch_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_watch_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 0 {
      msg.watch_id = fv.int_value;
    } elif fnum == 3 && wt == 0 {
      if fv.int_value != 0 {
        msg.created = true;
      } else {
        msg.created = false;
      }
    } elif fnum == 4 && wt == 0 {
      if fv.int_value != 0 {
        msg.canceled = true;
      } else {
        msg.canceled = false;
      }
    } elif fnum == 5 && wt == 0 {
      msg.compact_revision = fv.int_value;
    } elif fnum == 6 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_watch_resp(sr2.error);
      }
      let s: Str = sr2.value;
      msg.cancel_reason = s;
    } elif fnum == 7 && wt == 0 {
      if fv.int_value != 0 {
        msg.fragment = true;
      } else {
        msg.fragment = false;
      }
    } elif fnum == 11 && wt == 2 {
      if msg.event_types.len() >= etcd_max_list_entries() {
        return _err_watch_resp(_list_too_large(pos));
      }
      let er = etcd_parse_event_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !er.is_ok {
        return _err_watch_resp(er.error);
      }
      let ev: EtcdEvent = er.value;
      _event_push(&mut msg, &ev);
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_watch_resp(msg);
}

/// Decode a whole WatchResponse message. Complexity: O(body bytes).
pub fn etcd_decode_watch_response(data: &Vec[UInt8]) -> Result[EtcdWatchResponse, Str] {
  return etcd_parse_watch_response_body(data, 0, data.len(), 1);
}

// --------------------------------------------------
//  Lease
// --------------------------------------------------

/// Decode a LeaseGrantRequest body. Fields: 1 TTL, 2 ID.
/// Complexity: O(body bytes).
pub fn etcd_parse_lease_grant_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdLeaseGrantRequest, Str] {
  if !_depth_ok(depth) {
    return _err_lgrant_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_lgrant_req(_bad_range(start));
  }
  var msg = etcd_lease_grant_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_lgrant_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.ttl = fv.int_value;
    } elif fnum == 2 && wt == 0 {
      msg.id = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_lgrant_req(msg);
}

/// Decode a whole LeaseGrantRequest message. Complexity: O(body bytes).
pub fn etcd_decode_lease_grant_request(data: &Vec[UInt8]) -> Result[EtcdLeaseGrantRequest, Str] {
  return etcd_parse_lease_grant_request_body(data, 0, data.len(), 1);
}

/// Decode a LeaseGrantResponse body. Fields: 1 header, 2 ID, 3 TTL,
/// 4 error string. Complexity: O(body bytes).
pub fn etcd_parse_lease_grant_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdLeaseGrantResponse, Str] {
  if !_depth_ok(depth) {
    return _err_lgrant_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_lgrant_resp(_bad_range(start));
  }
  var msg = etcd_lease_grant_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_lgrant_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_lgrant_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 0 {
      msg.id = fv.int_value;
    } elif fnum == 3 && wt == 0 {
      msg.ttl = fv.int_value;
    } elif fnum == 4 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_lgrant_resp(sr2.error);
      }
      let s: Str = sr2.value;
      msg.error_text = s;
      msg.has_error_text = true;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_lgrant_resp(msg);
}

/// Decode a whole LeaseGrantResponse message. Complexity: O(body bytes).
pub fn etcd_decode_lease_grant_response(data: &Vec[UInt8]) -> Result[EtcdLeaseGrantResponse, Str] {
  return etcd_parse_lease_grant_response_body(data, 0, data.len(), 1);
}

/// Decode a LeaseKeepAliveRequest body. Field: 1 ID.
/// Complexity: O(body bytes).
pub fn etcd_parse_lease_keep_alive_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdLeaseKeepAliveRequest, Str] {
  if !_depth_ok(depth) {
    return _err_lkeep_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_lkeep_req(_bad_range(start));
  }
  var msg = etcd_lease_keep_alive_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_lkeep_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.id = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_lkeep_req(msg);
}

/// Decode a whole LeaseKeepAliveRequest message. Complexity: O(body bytes).
pub fn etcd_decode_lease_keep_alive_request(data: &Vec[UInt8]) -> Result[EtcdLeaseKeepAliveRequest, Str] {
  return etcd_parse_lease_keep_alive_request_body(data, 0, data.len(), 1);
}

/// Decode a LeaseKeepAliveResponse body. Fields: 1 header, 2 ID, 3 TTL.
/// Complexity: O(body bytes).
pub fn etcd_parse_lease_keep_alive_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdLeaseKeepAliveResponse, Str] {
  if !_depth_ok(depth) {
    return _err_lkeep_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_lkeep_resp(_bad_range(start));
  }
  var msg = etcd_lease_keep_alive_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_lkeep_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_lkeep_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 0 {
      msg.id = fv.int_value;
    } elif fnum == 3 && wt == 0 {
      msg.ttl = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_lkeep_resp(msg);
}

/// Decode a whole LeaseKeepAliveResponse message. Complexity: O(body bytes).
pub fn etcd_decode_lease_keep_alive_response(data: &Vec[UInt8]) -> Result[EtcdLeaseKeepAliveResponse, Str] {
  return etcd_parse_lease_keep_alive_response_body(data, 0, data.len(), 1);
}

/// Decode a LeaseRevokeRequest body. Field: 1 ID.
/// Complexity: O(body bytes).
pub fn etcd_parse_lease_revoke_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdLeaseRevokeRequest, Str] {
  if !_depth_ok(depth) {
    return _err_lrevoke_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_lrevoke_req(_bad_range(start));
  }
  var msg = etcd_lease_revoke_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_lrevoke_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.id = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_lrevoke_req(msg);
}

/// Decode a whole LeaseRevokeRequest message. Complexity: O(body bytes).
pub fn etcd_decode_lease_revoke_request(data: &Vec[UInt8]) -> Result[EtcdLeaseRevokeRequest, Str] {
  return etcd_parse_lease_revoke_request_body(data, 0, data.len(), 1);
}

// Decode a response body whose only field is 1 header (DefragmentResponse,
// CompactionResponse, LeaseRevokeResponse): walk the body, decode the
// nested header, skip anything else with bounds checks.
fn _parse_header_only_response(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdHeader, Str] {
  if !_depth_ok(depth) {
    return _err_header(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_header(_bad_range(start));
  }
  var msg = etcd_header_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_header(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_header(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg = h;
    }
    pos = st.next;
  }
  return _ok_header(msg);
}

/// Decode a LeaseRevokeResponse body (field 1 header) to its EtcdHeader.
/// Complexity: O(body bytes).
pub fn etcd_parse_lease_revoke_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdHeader, Str] {
  return _parse_header_only_response(data, start, end, depth);
}

/// Decode a whole LeaseRevokeResponse message to its EtcdHeader.
/// Complexity: O(body bytes).
pub fn etcd_decode_lease_revoke_response(data: &Vec[UInt8]) -> Result[EtcdHeader, Str] {
  return _parse_header_only_response(data, 0, data.len(), 1);
}

/// Decode a LeaseTimeToLiveRequest body. Fields: 1 ID, 2 keys flag.
/// Complexity: O(body bytes).
pub fn etcd_parse_lease_time_to_live_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdLeaseTimeToLiveRequest, Str] {
  if !_depth_ok(depth) {
    return _err_lttl_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_lttl_req(_bad_range(start));
  }
  var msg = etcd_lease_time_to_live_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_lttl_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.id = fv.int_value;
    } elif fnum == 2 && wt == 0 {
      if fv.int_value != 0 {
        msg.keys = true;
      } else {
        msg.keys = false;
      }
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_lttl_req(msg);
}

/// Decode a whole LeaseTimeToLiveRequest message. Complexity: O(body bytes).
pub fn etcd_decode_lease_time_to_live_request(data: &Vec[UInt8]) -> Result[EtcdLeaseTimeToLiveRequest, Str] {
  return etcd_parse_lease_time_to_live_request_body(data, 0, data.len(), 1);
}

/// Decode a LeaseTimeToLiveResponse body. Fields: 1 header, 2 ID, 3 TTL,
/// 4 grantedTTL, 5 repeated keys (bytes).
/// Complexity: O(body bytes).
pub fn etcd_parse_lease_time_to_live_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdLeaseTimeToLiveResponse, Str] {
  if !_depth_ok(depth) {
    return _err_lttl_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_lttl_resp(_bad_range(start));
  }
  var msg = etcd_lease_time_to_live_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_lttl_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_lttl_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 0 {
      msg.id = fv.int_value;
    } elif fnum == 3 && wt == 0 {
      msg.ttl = fv.int_value;
    } elif fnum == 4 && wt == 0 {
      msg.granted_ttl = fv.int_value;
    } elif fnum == 5 && wt == 2 {
      if msg.keys.len() >= etcd_max_list_entries() {
        return _err_lttl_resp(_list_too_large(pos));
      }
      let key = _slice(data, fv.start, fv.size);
      msg.keys.push(key);
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_lttl_resp(msg);
}

/// Decode a whole LeaseTimeToLiveResponse message. Complexity: O(body bytes).
pub fn etcd_decode_lease_time_to_live_response(data: &Vec[UInt8]) -> Result[EtcdLeaseTimeToLiveResponse, Str] {
  return etcd_parse_lease_time_to_live_response_body(data, 0, data.len(), 1);
}

// --------------------------------------------------
//  Auth
// --------------------------------------------------

/// Decode an AuthenticateRequest body. Fields: 1 name, 2 password.
/// Complexity: O(body bytes).
pub fn etcd_parse_authenticate_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdAuthenticateRequest, Str] {
  if !_depth_ok(depth) {
    return _err_auth_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_auth_req(_bad_range(start));
  }
  var msg = etcd_authenticate_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_auth_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_auth_req(sr2.error);
      }
      let s: Str = sr2.value;
      msg.name = s;
    } elif fnum == 2 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_auth_req(sr2.error);
      }
      let s: Str = sr2.value;
      msg.password = s;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_auth_req(msg);
}

/// Decode a whole AuthenticateRequest message. Complexity: O(body bytes).
pub fn etcd_decode_authenticate_request(data: &Vec[UInt8]) -> Result[EtcdAuthenticateRequest, Str] {
  return etcd_parse_authenticate_request_body(data, 0, data.len(), 1);
}

/// Decode an AuthenticateResponse body. Fields: 1 header, 2 token.
/// Complexity: O(body bytes).
pub fn etcd_parse_authenticate_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdAuthenticateResponse, Str] {
  if !_depth_ok(depth) {
    return _err_auth_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_auth_resp(_bad_range(start));
  }
  var msg = etcd_authenticate_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_auth_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_auth_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_auth_resp(sr2.error);
      }
      let s: Str = sr2.value;
      msg.token = s;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_auth_resp(msg);
}

/// Decode a whole AuthenticateResponse message. Complexity: O(body bytes).
pub fn etcd_decode_authenticate_response(data: &Vec[UInt8]) -> Result[EtcdAuthenticateResponse, Str] {
  return etcd_parse_authenticate_response_body(data, 0, data.len(), 1);
}

/// Decode an AuthUserAddRequest subset: 1 name, 2 password, 3 options
/// (raw authpb.UserAddOptions body preserved in `options_raw`),
/// 4 hashedPassword. Complexity: O(body bytes).
pub fn etcd_parse_user_add_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdUserAddRequest, Str] {
  if !_depth_ok(depth) {
    return _err_useradd_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_useradd_req(_bad_range(start));
  }
  var msg = etcd_user_add_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_useradd_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_useradd_req(sr2.error);
      }
      let s: Str = sr2.value;
      msg.name = s;
    } elif fnum == 2 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_useradd_req(sr2.error);
      }
      let s: Str = sr2.value;
      msg.password = s;
    } elif fnum == 3 && wt == 2 {
      msg.options_raw = _slice(data, fv.start, fv.size);
      msg.has_options = true;
    } elif fnum == 4 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_useradd_req(sr2.error);
      }
      let s: Str = sr2.value;
      msg.hashed_password = s;
      msg.has_hashed_password = true;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_useradd_req(msg);
}

/// Decode a whole AuthUserAddRequest message. Complexity: O(body bytes).
pub fn etcd_decode_user_add_request(data: &Vec[UInt8]) -> Result[EtcdUserAddRequest, Str] {
  return etcd_parse_user_add_request_body(data, 0, data.len(), 1);
}

/// Decode an AuthRoleAddRequest subset. Field: 1 name.
/// Complexity: O(body bytes).
pub fn etcd_parse_role_add_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdRoleAddRequest, Str] {
  if !_depth_ok(depth) {
    return _err_roleadd_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_roleadd_req(_bad_range(start));
  }
  var msg = etcd_role_add_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_roleadd_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_roleadd_req(sr2.error);
      }
      let s: Str = sr2.value;
      msg.name = s;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_roleadd_req(msg);
}

/// Decode a whole AuthRoleAddRequest message. Complexity: O(body bytes).
pub fn etcd_decode_role_add_request(data: &Vec[UInt8]) -> Result[EtcdRoleAddRequest, Str] {
  return etcd_parse_role_add_request_body(data, 0, data.len(), 1);
}

// --------------------------------------------------
//  Maintenance: Status, MemberList, Alarm, Hash, Snapshot
// --------------------------------------------------

/// Decode a StatusResponse body occupying [start, end) at nesting `depth`.
/// Fields: 1 header, 2 version, 3 dbSize, 4 leader, 5 raftIndex,
/// 6 raftTerm, 7 dbSizeInUse, 8 isLearner.
/// Complexity: O(body bytes).
pub fn etcd_parse_status_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdStatusResponse, Str] {
  if !_depth_ok(depth) {
    return _err_status(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_status(_bad_range(start));
  }
  var msg = etcd_status_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_status(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_status(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 2 {
      let sr2 = _span_str(data, fv.start, fv.size);
      if !sr2.is_ok {
        return _err_status(sr2.error);
      }
      let s: Str = sr2.value;
      msg.version = s;
    } elif fnum == 3 && wt == 0 {
      msg.db_size = fv.int_value;
    } elif fnum == 4 && wt == 0 {
      msg.leader = fv.int_value;
    } elif fnum == 5 && wt == 0 {
      msg.raft_index = fv.int_value;
    } elif fnum == 6 && wt == 0 {
      msg.raft_term = fv.int_value;
    } elif fnum == 7 && wt == 0 {
      msg.db_size_in_use = fv.int_value;
    } elif fnum == 8 && wt == 0 {
      if fv.int_value != 0 {
        msg.is_learner = true;
      } else {
        msg.is_learner = false;
      }
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_status(msg);
}

/// Decode a whole StatusResponse message. Complexity: O(body bytes).
pub fn etcd_decode_status_response(data: &Vec[UInt8]) -> Result[EtcdStatusResponse, Str] {
  return etcd_parse_status_response_body(data, 0, data.len(), 1);
}

// Decode one Member body and append it to `list`, mirroring every vector
// and closing the URL-run offsets per member.
fn _member_push(data: &Vec[UInt8], start: Int, end: Int, depth: Int, list: &mut EtcdMemberList) -> Result[Unit, Str] {
  if !_depth_ok(depth) {
    return _err_unit(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_unit(_bad_range(start));
  }
  var id = 0;
  var name = Vec[UInt8].new();
  var learner = 0;
  var peer = Vec[Vec[UInt8]].new();
  var client = Vec[Vec[UInt8]].new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_unit(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    if fnum == 1 && wt == 0 {
      id = fv.int_value;
    } elif fnum == 2 && wt == 2 {
      let e = _utf8_span_error(data, fv.start, fv.size);
      if e.len() > 0 {
        return _err_unit(e);
      }
      name = _slice(data, fv.start, fv.size);
    } elif fnum == 3 && wt == 2 {
      let e = _utf8_span_error(data, fv.start, fv.size);
      if e.len() > 0 {
        return _err_unit(e);
      }
      if peer.len() >= etcd_max_list_entries() {
        return _err_unit(_list_too_large(pos));
      }
      let u = _slice(data, fv.start, fv.size);
      peer.push(u);
    } elif fnum == 4 && wt == 2 {
      let e = _utf8_span_error(data, fv.start, fv.size);
      if e.len() > 0 {
        return _err_unit(e);
      }
      if client.len() >= etcd_max_list_entries() {
        return _err_unit(_list_too_large(pos));
      }
      let u = _slice(data, fv.start, fv.size);
      client.push(u);
    } elif fnum == 5 && wt == 0 {
      if fv.int_value != 0 {
        learner = 1;
      } else {
        learner = 0;
      }
    } else {
      // Member-level unknowns are skipped with bounds checks; the
      // enclosing response keeps its own unknown bytes.
    }
    pos = st.next;
  }
  list.ids.push(id);
  list.names.push(_vec_copy(&name));
  list.learners.push(learner);
  list.peer_offsets.push(list.peer_urls.len());
  var i = 0;
  while i < peer.len() {
    let u: Vec[UInt8] = peer[i];
    list.peer_urls.push(_vec_copy(&u));
    i = i + 1;
  }
  list.client_offsets.push(list.client_urls.len());
  var j = 0;
  while j < client.len() {
    let u: Vec[UInt8] = client[j];
    list.client_urls.push(_vec_copy(&u));
    j = j + 1;
  }
  return _ok_unit();
}

/// Decode a Member body occupying [start, end) at nesting `depth`.
/// Fields: 1 ID, 2 name, 3 repeated peerURLs, 4 repeated clientURLs,
/// 5 isLearner. Complexity: O(body bytes).
pub fn etcd_parse_member_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[Unit, Str] {
  var list = etcd_member_list_new();
  let r = _member_push(data, start, end, depth, &mut list);
  if !r.is_ok {
    return _err_unit(r.error);
  }
  return _ok_unit();
}

/// Decode a MemberListResponse body occupying [start, end) at nesting
/// `depth`. Fields: 1 header, 2 repeated members. The URL-run offsets are
/// closed on return: peer_offsets.len() == ids.len() + 1.
/// Complexity: O(body bytes).
pub fn etcd_parse_member_list_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdMemberListResponse, Str] {
  if !_depth_ok(depth) {
    return _err_members(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_members(_bad_range(start));
  }
  var msg = etcd_member_list_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_members(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_members(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 2 {
      if msg.members.ids.len() >= etcd_max_list_entries() {
        return _err_members(_list_too_large(pos));
      }
      let mr = _member_push(data, fv.start, fv.start + fv.size, depth + 1, &mut msg.members);
      if !mr.is_ok {
        return _err_members(mr.error);
      }
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  msg.members.peer_offsets.push(msg.members.peer_urls.len());
  msg.members.client_offsets.push(msg.members.client_urls.len());
  return _ok_members(msg);
}

/// Decode a whole MemberListResponse message. Complexity: O(body bytes).
pub fn etcd_decode_member_list_response(data: &Vec[UInt8]) -> Result[EtcdMemberListResponse, Str] {
  return etcd_parse_member_list_response_body(data, 0, data.len(), 1);
}

/// Decode an AlarmRequest body. Fields: 1 alarm type, 2 memberID,
/// 3 action. Complexity: O(body bytes).
pub fn etcd_parse_alarm_request_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdAlarmRequest, Str] {
  if !_depth_ok(depth) {
    return _err_alarm_req(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_alarm_req(_bad_range(start));
  }
  var msg = etcd_alarm_request_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_alarm_req(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.alarm = fv.int_value;
    } elif fnum == 2 && wt == 0 {
      msg.member_id = fv.int_value;
    } elif fnum == 3 && wt == 0 {
      msg.action = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_alarm_req(msg);
}

/// Decode a whole AlarmRequest message. Complexity: O(body bytes).
pub fn etcd_decode_alarm_request(data: &Vec[UInt8]) -> Result[EtcdAlarmRequest, Str] {
  return etcd_parse_alarm_request_body(data, 0, data.len(), 1);
}

/// Decode one AlarmMember body. Fields: 1 memberID, 2 alarm.
/// Complexity: O(body bytes).
pub fn etcd_parse_alarm_member_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdAlarmMember, Str] {
  if !_depth_ok(depth) {
    return _err_almember(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_almember(_bad_range(start));
  }
  var msg = etcd_alarm_member_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_almember(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 0 {
      msg.member_id = fv.int_value;
    } elif fnum == 2 && wt == 0 {
      msg.alarm = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_almember(msg);
}

/// Decode a whole AlarmMember message. Complexity: O(body bytes).
pub fn etcd_decode_alarm_member(data: &Vec[UInt8]) -> Result[EtcdAlarmMember, Str] {
  return etcd_parse_alarm_member_body(data, 0, data.len(), 1);
}

/// Decode an AlarmResponse body. Fields: 1 header, 2 repeated alarms.
/// Complexity: O(body bytes).
pub fn etcd_parse_alarm_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdAlarmResponse, Str] {
  if !_depth_ok(depth) {
    return _err_alarm_resp(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_alarm_resp(_bad_range(start));
  }
  var msg = etcd_alarm_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_alarm_resp(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_alarm_resp(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 2 {
      if msg.member_ids.len() >= etcd_max_list_entries() {
        return _err_alarm_resp(_list_too_large(pos));
      }
      let ar = etcd_parse_alarm_member_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !ar.is_ok {
        return _err_alarm_resp(ar.error);
      }
      let a: EtcdAlarmMember = ar.value;
      _alarm_push(&mut msg, &a);
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_alarm_resp(msg);
}

/// Decode a whole AlarmResponse message. Complexity: O(body bytes).
pub fn etcd_decode_alarm_response(data: &Vec[UInt8]) -> Result[EtcdAlarmResponse, Str] {
  return etcd_parse_alarm_response_body(data, 0, data.len(), 1);
}

/// Decode a DefragmentResponse body (field 1 header) to its EtcdHeader.
/// Complexity: O(body bytes).
pub fn etcd_parse_defragment_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdHeader, Str] {
  return _parse_header_only_response(data, start, end, depth);
}

/// Decode a whole DefragmentResponse message to its EtcdHeader.
/// Complexity: O(body bytes).
pub fn etcd_decode_defragment_response(data: &Vec[UInt8]) -> Result[EtcdHeader, Str] {
  return _parse_header_only_response(data, 0, data.len(), 1);
}

/// Decode a CompactionResponse body (header only) to its EtcdHeader.
/// Complexity: O(body bytes).
pub fn etcd_parse_compaction_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdHeader, Str] {
  return _parse_header_only_response(data, start, end, depth);
}

/// Decode a whole CompactionResponse message to its EtcdHeader.
/// Complexity: O(body bytes).
pub fn etcd_decode_compaction_response(data: &Vec[UInt8]) -> Result[EtcdHeader, Str] {
  return _parse_header_only_response(data, 0, data.len(), 1);
}

/// Decode a HashResponse body. Fields: 1 header, 2 hash (uint32).
/// Complexity: O(body bytes).
pub fn etcd_parse_hash_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdHashResponse, Str] {
  if !_depth_ok(depth) {
    return _err_hash(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_hash(_bad_range(start));
  }
  var msg = etcd_hash_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_hash(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_hash(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 0 {
      msg.hash = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_hash(msg);
}

/// Decode a whole HashResponse message. Complexity: O(body bytes).
pub fn etcd_decode_hash_response(data: &Vec[UInt8]) -> Result[EtcdHashResponse, Str] {
  return etcd_parse_hash_response_body(data, 0, data.len(), 1);
}

/// Decode a HashKVResponse body. Fields: 1 header, 2 hash (uint64),
/// 3 compact_revision, 4 hash_revision. The port brief asked for
/// "HashResponse (hash, compact_revision)": compact_revision lives on
/// HashKVResponse in the canonical rpc.proto, so this package implements
/// both messages with their real shapes.
/// Complexity: O(body bytes).
pub fn etcd_parse_hash_kv_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdHashKvResponse, Str] {
  if !_depth_ok(depth) {
    return _err_hashkv(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_hashkv(_bad_range(start));
  }
  var msg = etcd_hash_kv_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_hashkv(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_hashkv(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 0 {
      msg.hash = fv.int_value;
    } elif fnum == 3 && wt == 0 {
      msg.compact_revision = fv.int_value;
    } elif fnum == 4 && wt == 0 {
      msg.hash_revision = fv.int_value;
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_hashkv(msg);
}

/// Decode a whole HashKVResponse message. Complexity: O(body bytes).
pub fn etcd_decode_hash_kv_response(data: &Vec[UInt8]) -> Result[EtcdHashKvResponse, Str] {
  return etcd_parse_hash_kv_response_body(data, 0, data.len(), 1);
}

/// Decode a SnapshotResponse body. Fields: 1 header, 2 remaining_bytes,
/// 3 blob. Complexity: O(body bytes).
pub fn etcd_parse_snapshot_response_body(data: &Vec[UInt8], start: Int, end: Int, depth: Int) -> Result[EtcdSnapshotResponse, Str] {
  if !_depth_ok(depth) {
    return _err_snapshot(_depth_msg(start));
  }
  if start < 0 || start > end || end > data.len() {
    return _err_snapshot(_bad_range(start));
  }
  var msg = etcd_snapshot_response_new();
  var pos = start;
  while pos < end {
    let sr = _field_step(data, pos, end);
    if !sr.is_ok {
      return _err_snapshot(sr.error);
    }
    let st: EtcdFieldStep = sr.value;
    let fnum = st.field_number;
    let wt = st.wire_type;
    let fv: EtcdFieldValue = st.value;
    var handled = true;
    if fnum == 1 && wt == 2 {
      let hr = etcd_parse_header_body(data, fv.start, fv.start + fv.size, depth + 1);
      if !hr.is_ok {
        return _err_snapshot(hr.error);
      }
      let h: EtcdHeader = hr.value;
      msg.header = h;
    } elif fnum == 2 && wt == 0 {
      msg.remaining_bytes = fv.int_value;
    } elif fnum == 3 && wt == 2 {
      msg.blob = _slice(data, fv.start, fv.size);
    } else {
      handled = false;
    }
    if !handled {
      _note_unknown(&mut msg.unknown, data, st.tag_start, st.key_size + fv.total);
    }
    pos = st.next;
  }
  return _ok_snapshot(msg);
}

/// Decode a whole SnapshotResponse message. Complexity: O(body bytes).
pub fn etcd_decode_snapshot_response(data: &Vec[UInt8]) -> Result[EtcdSnapshotResponse, Str] {
  return etcd_parse_snapshot_response_body(data, 0, data.len(), 1);
}

// --------------------------------------------------
//  Accessors: unknown records, header, kv, lists
// --------------------------------------------------

/// Number of fields outside the decoded subset. Complexity: O(1).
pub fn etcd_unknown_count(u: &EtcdUnknown) -> Int {
  return u.count;
}

/// The raw tag+value bytes of the unknown fields (a copy).
/// Complexity: O(bytes).
pub fn etcd_unknown_bytes(u: &EtcdUnknown) -> Vec[UInt8] {
  let b: Vec[UInt8] = u.bytes;
  return _vec_copy(&b);
}

/// True when any header field appeared on the wire. Complexity: O(1).
pub fn etcd_header_present(h: &EtcdHeader) -> Bool {
  return h.present;
}

/// Header cluster_id (0 when absent). Complexity: O(1).
pub fn etcd_header_cluster_id(h: &EtcdHeader) -> Int {
  return h.cluster_id;
}

/// Header member_id (0 when absent). Complexity: O(1).
pub fn etcd_header_member_id(h: &EtcdHeader) -> Int {
  return h.member_id;
}

/// Header revision (0 when absent). Complexity: O(1).
pub fn etcd_header_revision(h: &EtcdHeader) -> Int {
  return h.revision;
}

/// Header raft_term (0 when absent). Complexity: O(1).
pub fn etcd_header_raft_term(h: &EtcdHeader) -> Int {
  return h.raft_term;
}

/// KeyValue key bytes (a copy). Complexity: O(bytes).
pub fn etcd_kv_key(kv: &EtcdKeyValue) -> Vec[UInt8] {
  let k: Vec[UInt8] = kv.key;
  return _vec_copy(&k);
}

/// KeyValue value bytes (a copy). Complexity: O(bytes).
pub fn etcd_kv_value(kv: &EtcdKeyValue) -> Vec[UInt8] {
  let v: Vec[UInt8] = kv.value;
  return _vec_copy(&v);
}

/// KeyValue create_revision. Complexity: O(1).
pub fn etcd_kv_create_revision(kv: &EtcdKeyValue) -> Int {
  return kv.create_revision;
}

/// KeyValue mod_revision. Complexity: O(1).
pub fn etcd_kv_mod_revision(kv: &EtcdKeyValue) -> Int {
  return kv.mod_revision;
}

/// KeyValue version. Complexity: O(1).
pub fn etcd_kv_version(kv: &EtcdKeyValue) -> Int {
  return kv.version;
}

/// KeyValue lease. Complexity: O(1).
pub fn etcd_kv_lease(kv: &EtcdKeyValue) -> Int {
  return kv.lease;
}

/// Number of entries in a flat kv list. Complexity: O(1).
pub fn etcd_kvlist_count(list: &EtcdKvList) -> Int {
  let n: Int = list.keys.len();
  return n;
}

/// Entry `i` of a flat kv list reassembled as a KeyValue (a default when
/// out of range; a short or drifted list yields defaults for missing
/// mirrors). Complexity: O(entry bytes).
pub fn etcd_kvlist_get(list: &EtcdKvList, i: Int) -> EtcdKeyValue {
  var kv = etcd_key_value_new();
  if i < 0 || i >= list.keys.len() {
    return kv;
  }
  if i >= list.values.len() {
    return kv;
  }
  if i >= list.create_revisions.len() {
    return kv;
  }
  if i >= list.mod_revisions.len() {
    return kv;
  }
  if i >= list.versions.len() {
    return kv;
  }
  if i >= list.leases.len() {
    return kv;
  }
  let k: Vec[UInt8] = list.keys[i];
  let v: Vec[UInt8] = list.values[i];
  let cr: Int = list.create_revisions[i];
  let mr: Int = list.mod_revisions[i];
  let ver: Int = list.versions[i];
  let le: Int = list.leases[i];
  kv.key = _vec_copy(&k);
  kv.value = _vec_copy(&v);
  kv.create_revision = cr;
  kv.mod_revision = mr;
  kv.version = ver;
  kv.lease = le;
  return kv;
}

/// Key bytes of kv-list entry `i` (empty when out of range).
/// Complexity: O(bytes).
pub fn etcd_kvlist_key(list: &EtcdKvList, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= list.keys.len() {
    return Vec[UInt8].new();
  }
  let k: Vec[UInt8] = list.keys[i];
  return _vec_copy(&k);
}

/// Value bytes of kv-list entry `i` (empty when out of range).
/// Complexity: O(bytes).
pub fn etcd_kvlist_value(list: &EtcdKvList, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= list.values.len() {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = list.values[i];
  return _vec_copy(&v);
}

/// Number of ops in a flat op list. Complexity: O(1).
pub fn etcd_oplist_count(list: &EtcdOpList) -> Int {
  let n: Int = list.kinds.len();
  return n;
}

/// One-of kind of op `i` (0 when out of range). Complexity: O(1).
pub fn etcd_oplist_kind(list: &EtcdOpList, i: Int) -> Int {
  if i < 0 || i >= list.kinds.len() {
    return 0;
  }
  let k: Int = list.kinds[i];
  return k;
}

/// Raw nested-message bytes of op `i` (empty when out of range).
/// Complexity: O(bytes).
pub fn etcd_oplist_raw(list: &EtcdOpList, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= list.raws.len() {
    return Vec[UInt8].new();
  }
  let r: Vec[UInt8] = list.raws[i];
  return _vec_copy(&r);
}

/// The name of a RequestOp/ResponseOp one-of kind ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn etcd_op_name(kind: Int) -> Str {
  if kind == 1 {
    return "RANGE";
  }
  if kind == 2 {
    return "PUT";
  }
  if kind == 3 {
    return "DELETE_RANGE";
  }
  if kind == 4 {
    return "TXN";
  }
  return "UNKNOWN";
}

/// Number of compares in a flat compare list. Complexity: O(1).
pub fn etcd_cmp_count(list: &EtcdCompareList) -> Int {
  let n: Int = list.results.len();
  return n;
}

/// Compare `i` reassembled as an EtcdCompare (defaults when out of range).
/// Complexity: O(bytes).
pub fn etcd_cmp_get(list: &EtcdCompareList, i: Int) -> EtcdCompare {
  var cmp = etcd_compare_new();
  if i < 0 || i >= list.results.len() {
    return cmp;
  }
  if i >= list.targets.len() || i >= list.keys.len() {
    return cmp;
  }
  if i >= list.union_fields.len() || i >= list.versions.len() {
    return cmp;
  }
  if i >= list.create_revisions.len() || i >= list.mod_revisions.len() {
    return cmp;
  }
  if i >= list.values.len() || i >= list.leases.len() {
    return cmp;
  }
  let res: Int = list.results[i];
  let tgt: Int = list.targets[i];
  let k: Vec[UInt8] = list.keys[i];
  let uf: Int = list.union_fields[i];
  let ver: Int = list.versions[i];
  let cr: Int = list.create_revisions[i];
  let mr: Int = list.mod_revisions[i];
  let v: Vec[UInt8] = list.values[i];
  let le: Int = list.leases[i];
  cmp.result = res;
  cmp.target = tgt;
  cmp.key = _vec_copy(&k);
  cmp.union_field = uf;
  cmp.version = ver;
  cmp.create_revision = cr;
  cmp.mod_revision = mr;
  cmp.value = _vec_copy(&v);
  cmp.lease = le;
  return cmp;
}

/// Result enum of compare `i` (0 when out of range). Complexity: O(1).
pub fn etcd_cmp_result(list: &EtcdCompareList, i: Int) -> Int {
  if i < 0 || i >= list.results.len() {
    return 0;
  }
  let v: Int = list.results[i];
  return v;
}

/// Target enum of compare `i` (0 when out of range). Complexity: O(1).
pub fn etcd_cmp_target(list: &EtcdCompareList, i: Int) -> Int {
  if i < 0 || i >= list.targets.len() {
    return 0;
  }
  let v: Int = list.targets[i];
  return v;
}

/// Key bytes of compare `i` (empty when out of range). Complexity: O(bytes).
pub fn etcd_cmp_key(list: &EtcdCompareList, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= list.keys.len() {
    return Vec[UInt8].new();
  }
  let k: Vec[UInt8] = list.keys[i];
  return _vec_copy(&k);
}

/// target_union field number of compare `i` (0 when absent/out of range).
/// Complexity: O(1).
pub fn etcd_cmp_union_field(list: &EtcdCompareList, i: Int) -> Int {
  if i < 0 || i >= list.union_fields.len() {
    return 0;
  }
  let v: Int = list.union_fields[i];
  return v;
}

// --------------------------------------------------
//  Accessors: watch, lease, members, alarms, frame
// --------------------------------------------------

/// Number of filters decoded from a WatchRequest. Complexity: O(1).
pub fn etcd_watch_filter_count(w: &EtcdWatchRequest) -> Int {
  let n: Int = w.filters.len();
  return n;
}

/// Filter `i` of a WatchRequest (0 when out of range). Complexity: O(1).
pub fn etcd_watch_filter(w: &EtcdWatchRequest, i: Int) -> Int {
  if i < 0 || i >= w.filters.len() {
    return 0;
  }
  let v: Int = w.filters[i];
  return v;
}

/// Number of events in a WatchResponse. Complexity: O(1).
pub fn etcd_watch_event_count(wr: &EtcdWatchResponse) -> Int {
  let n: Int = wr.event_types.len();
  return n;
}

/// Event `i` reassembled as an EtcdEvent (defaults when out of range or
/// when the parallel vectors drifted). Complexity: O(event bytes).
pub fn etcd_watch_event_get(wr: &EtcdWatchResponse, i: Int) -> EtcdEvent {
  var ev = etcd_event_new();
  if i < 0 || i >= wr.event_types.len() {
    return ev;
  }
  if i >= wr.event_kv_keys.len() || i >= wr.event_prev_keys.len() {
    return ev;
  }
  let t: Int = wr.event_types[i];
  let kp: Int = wr.event_kv_present[i];
  let kk: Vec[UInt8] = wr.event_kv_keys[i];
  let kvv: Vec[UInt8] = wr.event_kv_values[i];
  let kcr: Int = wr.event_kv_create_revisions[i];
  let kmr: Int = wr.event_kv_mod_revisions[i];
  let kver: Int = wr.event_kv_versions[i];
  let kle: Int = wr.event_kv_leases[i];
  let pp: Int = wr.event_prev_present[i];
  let pk: Vec[UInt8] = wr.event_prev_keys[i];
  let pvv: Vec[UInt8] = wr.event_prev_values[i];
  let pcr: Int = wr.event_prev_create_revisions[i];
  let pmr: Int = wr.event_prev_mod_revisions[i];
  let pver: Int = wr.event_prev_versions[i];
  let ple: Int = wr.event_prev_leases[i];
  ev.etype = t;
  ev.kv_present = kp;
  ev.kv.key = _vec_copy(&kk);
  ev.kv.value = _vec_copy(&kvv);
  ev.kv.create_revision = kcr;
  ev.kv.mod_revision = kmr;
  ev.kv.version = kver;
  ev.kv.lease = kle;
  ev.prev_present = pp;
  ev.prev.key = _vec_copy(&pk);
  ev.prev.value = _vec_copy(&pvv);
  ev.prev.create_revision = pcr;
  ev.prev.mod_revision = pmr;
  ev.prev.version = pver;
  ev.prev.lease = ple;
  return ev;
}

/// Event-type of event `i` (0 when out of range). Complexity: O(1).
pub fn etcd_watch_event_type(wr: &EtcdWatchResponse, i: Int) -> Int {
  if i < 0 || i >= wr.event_types.len() {
    return 0;
  }
  let v: Int = wr.event_types[i];
  return v;
}

/// Key bytes of event `i`'s kv (empty when out of range). O(bytes).
pub fn etcd_watch_event_kv_key(wr: &EtcdWatchResponse, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= wr.event_kv_keys.len() {
    return Vec[UInt8].new();
  }
  let k: Vec[UInt8] = wr.event_kv_keys[i];
  return _vec_copy(&k);
}

/// Value bytes of event `i`'s kv (empty when out of range). O(bytes).
pub fn etcd_watch_event_kv_value(wr: &EtcdWatchResponse, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= wr.event_kv_values.len() {
    return Vec[UInt8].new();
  }
  let v: Vec[UInt8] = wr.event_kv_values[i];
  return _vec_copy(&v);
}

/// Key bytes of event `i`'s prev_kv (empty when out of range). O(bytes).
pub fn etcd_watch_event_prev_key(wr: &EtcdWatchResponse, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= wr.event_prev_keys.len() {
    return Vec[UInt8].new();
  }
  let k: Vec[UInt8] = wr.event_prev_keys[i];
  return _vec_copy(&k);
}

/// Number of TTL keys in a LeaseTimeToLiveResponse. Complexity: O(1).
pub fn etcd_ttl_key_count(r: &EtcdLeaseTimeToLiveResponse) -> Int {
  let n: Int = r.keys.len();
  return n;
}

/// TTL key `i` bytes (empty when out of range). Complexity: O(bytes).
pub fn etcd_ttl_key(r: &EtcdLeaseTimeToLiveResponse, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= r.keys.len() {
    return Vec[UInt8].new();
  }
  let k: Vec[UInt8] = r.keys[i];
  return _vec_copy(&k);
}

/// Number of members in a MemberListResponse. Complexity: O(1).
pub fn etcd_member_count(r: &EtcdMemberListResponse) -> Int {
  let n: Int = r.members.ids.len();
  return n;
}

/// Member `i` ID (0 when out of range). Complexity: O(1).
pub fn etcd_member_id(r: &EtcdMemberListResponse, i: Int) -> Int {
  if i < 0 || i >= r.members.ids.len() {
    return 0;
  }
  let v: Int = r.members.ids[i];
  return v;
}

/// Member `i` name bytes (empty when out of range). Complexity: O(bytes).
pub fn etcd_member_name(r: &EtcdMemberListResponse, i: Int) -> Vec[UInt8] {
  if i < 0 || i >= r.members.names.len() {
    return Vec[UInt8].new();
  }
  let n: Vec[UInt8] = r.members.names[i];
  return _vec_copy(&n);
}

/// True when member `i` is a learner. Complexity: O(1).
pub fn etcd_member_is_learner(r: &EtcdMemberListResponse, i: Int) -> Bool {
  if i < 0 || i >= r.members.learners.len() {
    return false;
  }
  let v: Int = r.members.learners[i];
  return v != 0;
}

/// Number of peer URLs of member `i` (0 when out of range).
/// Complexity: O(1).
pub fn etcd_member_peer_count(r: &EtcdMemberListResponse, i: Int) -> Int {
  if i < 0 || i >= r.members.ids.len() {
    return 0;
  }
  if i + 1 >= r.members.peer_offsets.len() {
    return 0;
  }
  let a: Int = r.members.peer_offsets[i];
  let b: Int = r.members.peer_offsets[i + 1];
  if b < a {
    return 0;
  }
  return b - a;
}

/// Peer URL `j` of member `i` (empty when out of range). O(bytes).
pub fn etcd_member_peer_url(r: &EtcdMemberListResponse, i: Int, j: Int) -> Vec[UInt8] {
  if i < 0 || j < 0 {
    return Vec[UInt8].new();
  }
  if i + 1 >= r.members.peer_offsets.len() {
    return Vec[UInt8].new();
  }
  let a: Int = r.members.peer_offsets[i];
  let b: Int = r.members.peer_offsets[i + 1];
  let idx = a + j;
  if idx >= b || idx >= r.members.peer_urls.len() {
    return Vec[UInt8].new();
  }
  let u: Vec[UInt8] = r.members.peer_urls[idx];
  return _vec_copy(&u);
}

/// Number of client URLs of member `i` (0 when out of range).
/// Complexity: O(1).
pub fn etcd_member_client_count(r: &EtcdMemberListResponse, i: Int) -> Int {
  if i < 0 || i >= r.members.ids.len() {
    return 0;
  }
  if i + 1 >= r.members.client_offsets.len() {
    return 0;
  }
  let a: Int = r.members.client_offsets[i];
  let b: Int = r.members.client_offsets[i + 1];
  if b < a {
    return 0;
  }
  return b - a;
}

/// Client URL `j` of member `i` (empty when out of range). O(bytes).
pub fn etcd_member_client_url(r: &EtcdMemberListResponse, i: Int, j: Int) -> Vec[UInt8] {
  if i < 0 || j < 0 {
    return Vec[UInt8].new();
  }
  if i + 1 >= r.members.client_offsets.len() {
    return Vec[UInt8].new();
  }
  let a: Int = r.members.client_offsets[i];
  let b: Int = r.members.client_offsets[i + 1];
  let idx = a + j;
  if idx >= b || idx >= r.members.client_urls.len() {
    return Vec[UInt8].new();
  }
  let u: Vec[UInt8] = r.members.client_urls[idx];
  return _vec_copy(&u);
}

/// Number of alarms in an AlarmResponse. Complexity: O(1).
pub fn etcd_alarm_count(r: &EtcdAlarmResponse) -> Int {
  let n: Int = r.member_ids.len();
  return n;
}

/// Alarm `i` reassembled as an EtcdAlarmMember (defaults out of range).
/// Complexity: O(1).
pub fn etcd_alarm_member(r: &EtcdAlarmResponse, i: Int) -> EtcdAlarmMember {
  var a = etcd_alarm_member_new();
  if i < 0 || i >= r.member_ids.len() {
    return a;
  }
  if i >= r.alarms.len() {
    return a;
  }
  let id: Int = r.member_ids[i];
  let al: Int = r.alarms[i];
  a.member_id = id;
  a.alarm = al;
  return a;
}

/// Total consumed size of a parsed gRPC frame (5 + length). O(1).
pub fn etcd_frame_consumed(f: &EtcdFrame) -> Int {
  return f.frame_len;
}

/// The raw compressed flag of a frame (0/1 in gRPC). Complexity: O(1).
pub fn etcd_frame_compressed(f: &EtcdFrame) -> Int {
  return f.compressed;
}

/// The declared message length of a frame. Complexity: O(1).
pub fn etcd_frame_length(f: &EtcdFrame) -> Int {
  return f.length;
}

/// A copy of a frame's message bytes. Complexity: O(bytes).
pub fn etcd_frame_message(f: &EtcdFrame) -> Vec[UInt8] {
  let m: Vec[UInt8] = f.message;
  return _vec_copy(&m);
}

// --------------------------------------------------
//  Names
// --------------------------------------------------

/// The name of a RangeRequest.SortOrder value ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn etcd_sort_order_name(o: Int) -> Str {
  if o == 0 {
    return "NONE";
  }
  if o == 1 {
    return "ASCEND";
  }
  if o == 2 {
    return "DESCEND";
  }
  return "UNKNOWN";
}

/// The name of a RangeRequest.SortTarget value ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn etcd_sort_target_name(t: Int) -> Str {
  if t == 0 {
    return "KEY";
  }
  if t == 1 {
    return "VERSION";
  }
  if t == 2 {
    return "CREATE";
  }
  if t == 3 {
    return "MOD";
  }
  if t == 4 {
    return "VALUE";
  }
  return "UNKNOWN";
}

/// The name of a Compare.CompareResult value ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn etcd_compare_result_name(r: Int) -> Str {
  if r == 0 {
    return "EQUAL";
  }
  if r == 1 {
    return "GREATER";
  }
  if r == 2 {
    return "LESS";
  }
  if r == 3 {
    return "NOT_EQUAL";
  }
  return "UNKNOWN";
}

/// The name of a Compare.CompareTarget value ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn etcd_compare_target_name(t: Int) -> Str {
  if t == 0 {
    return "VERSION";
  }
  if t == 1 {
    return "CREATE";
  }
  if t == 2 {
    return "MOD";
  }
  if t == 3 {
    return "VALUE";
  }
  if t == 4 {
    return "LEASE";
  }
  return "UNKNOWN";
}

/// The name of an Event.EventType value ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn etcd_event_type_name(t: Int) -> Str {
  if t == 0 {
    return "PUT";
  }
  if t == 1 {
    return "DELETE";
  }
  return "UNKNOWN";
}

/// The name of a WatchCreateRequest.FilterType value ("UNKNOWN"
/// otherwise). Complexity: O(1).
pub fn etcd_watch_filter_name(f: Int) -> Str {
  if f == 0 {
    return "NOPUT";
  }
  if f == 1 {
    return "NODELETE";
  }
  return "UNKNOWN";
}

/// The name of an AlarmType value ("UNKNOWN" otherwise). Complexity: O(1).
pub fn etcd_alarm_type_name(a: Int) -> Str {
  if a == 0 {
    return "NONE";
  }
  if a == 1 {
    return "NOSPACE";
  }
  if a == 2 {
    return "CORRUPT";
  }
  return "UNKNOWN";
}

/// The name of an AlarmRequest.AlarmAction value ("UNKNOWN" otherwise).
/// Complexity: O(1).
pub fn etcd_alarm_action_name(a: Int) -> Str {
  if a == 0 {
    return "GET";
  }
  if a == 1 {
    return "ACTIVATE";
  }
  if a == 2 {
    return "DEACTIVATE";
  }
  return "UNKNOWN";
}
