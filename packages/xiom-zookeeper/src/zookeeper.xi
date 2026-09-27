// XIOM -- xiom.zookeeper: Apache ZooKeeper jute wire-format structure codec
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// A pure-XIOM (no FFI, no dependencies beyond xiom.std) codec for the
// Apache ZooKeeper *jute* serialized message STRUCTURE: the record layouts
// that ZooKeeper clients and servers put on the wire. It covers no
// sessions, no sockets, no packet framing, no heartbeat timing and no
// network layer -- only the bytes of a single message. See SPEC.md for the
// byte-level layouts and the exact error catalog.
//
// Implemented:
//   * jute primitives, all big-endian: byte (1), bool (1), int (4),
//     long (8), float (4 raw), double (8 raw), buffer (int32 length +
//     bytes, -1 = null), ustring (int32 byte length + UTF-8 bytes,
//     -1 = null) and vectors (int32 count + elements, -1 = null);
//   * the connect handshake records ConnectRequest and ConnectResponse;
//   * RequestHeader (xid int + type int) and ReplyHeader (xid int +
//     zxid long + err int);
//   * the opcode table (NOTIFICATION 0, CREATE 1 ... CREATE2 15,
//     ERROR -1, CREATE_SESSION -10, CLOSE -11, AUTH 100,
//     SET_WATCHES 101) and the special xid values (notification -1,
//     PING_XID -2, AUTH_XID -4, SET_WATCHES_XID -8);
//   * common records: Stat, Id, ACL, ACL vectors (flat parallel model),
//     watch events, create request/response, delete, exists, getData,
//     setData, getChildren request/response, getAcl, setAcl, sync,
//     check, auth;
//   * the ZooKeeper error-code, watch-event and watch-state tables;
//   * zk_parse_one / zk_parse_reply: parse exactly one message from the
//     front of a buffer and report the consumed byte count, with
//     byte-offset diagnostics on malformed input.
//
// Documented boundaries:
//   * every reader is bounds-checked; a short read is
//     "zookeeper: truncated input at byte N" (N is the offset at which
//     the read started);
//   * buffer, ustring and vector accept a -1 length/count as null and
//     collapse it to empty on decode; any other negative is rejected;
//   * vector counts are bounded by the bytes remaining (a lower bound
//     of 1 byte per element, 4 for strings, 12 for ACLs), so hostile
//     counts fail fast instead of driving a huge loop;
//   * bool accepts only the bytes 0 and 1;
//   * ustring payloads must be valid UTF-8 with no 0x00 byte (the
//     v0.61.3 string builder aborts on a NUL); use the buffer codec for
//     arbitrary bytes;
//   * float/double are exposed as raw bit patterns: v0.61.3 has no
//     Int <-> Float64 bitcast, so nothing is guessed about their value.
//
// Non-goals: no packet length prefixes (the 4-byte jute framing), no
// read/write timeout negotiation, no session establishment or reattach,
// no watch bookkeeping, no SASL, no multi/transaction op bodies, no
// async/zab or quorum records, no compression, no client library.
//
// v0.61.3 notes that shaped this module:
//   * free functions only, no methods, no lambdas, no Vec[fn] dispatch,
//     no Vec[struct] and no Vec[Float64];
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results for struct payloads inside other functions
//     miscompiles);
//   * every byte read is widened once with `(b as Int) & 0xFF` before
//     entering Int arithmetic or comparisons;
//   * every Vec element read is bound to an explicitly typed local first;
//   * a `&Vec[...]` argument is always a local, never `&struct.field`;
//   * big-endian encoding uses arithmetic byte extraction and 64-bit
//     decoding applies the sign bit after accumulating 63 bits, so no
//     intermediate overflows and every pattern round-trips;
//   * Str output is collected in a Vec[UInt8] and materialized with
//     xiom.string.builder.sb_to_str only after validation.

module xiom.zookeeper

use xiom.string;
use xiom.string.builder;
use xiom.string.compare;
use xiom.convert;

// --------------------------------------------------
//  Result constructors (leaf helpers, see the header)
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

// Ok(v) for Result[Vec[Str], Str].
fn _ok_names(v: Vec[Str]) -> Result[Vec[Str], Str] {
  return Ok(v);
}

// Err(m) for Result[Vec[Str], Str].
fn _err_names(m: Str) -> Result[Vec[Str], Str] {
  return Err(m);
}

// Ok(v) for Result[ZkRequestHeader, Str].
fn _ok_hdr(v: ZkRequestHeader) -> Result[ZkRequestHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkRequestHeader, Str].
fn _err_hdr(m: Str) -> Result[ZkRequestHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkReplyHeader, Str].
fn _ok_rhdr(v: ZkReplyHeader) -> Result[ZkReplyHeader, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkReplyHeader, Str].
fn _err_rhdr(m: Str) -> Result[ZkReplyHeader, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkConnectRequest, Str].
fn _ok_creq(v: ZkConnectRequest) -> Result[ZkConnectRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkConnectRequest, Str].
fn _err_creq(m: Str) -> Result[ZkConnectRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkConnectResponse, Str].
fn _ok_cresp(v: ZkConnectResponse) -> Result[ZkConnectResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkConnectResponse, Str].
fn _err_cresp(m: Str) -> Result[ZkConnectResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkStat, Str].
fn _ok_stat(v: ZkStat) -> Result[ZkStat, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkStat, Str].
fn _err_stat(m: Str) -> Result[ZkStat, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkId, Str].
fn _ok_id(v: ZkId) -> Result[ZkId, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkId, Str].
fn _err_id(m: Str) -> Result[ZkId, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkAcl, Str].
fn _ok_acl(v: ZkAcl) -> Result[ZkAcl, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkAcl, Str].
fn _err_acl(m: Str) -> Result[ZkAcl, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkAclVec, Str].
fn _ok_aclvec(v: ZkAclVec) -> Result[ZkAclVec, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkAclVec, Str].
fn _err_aclvec(m: Str) -> Result[ZkAclVec, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkWatchEvent, Str].
fn _ok_event(v: ZkWatchEvent) -> Result[ZkWatchEvent, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkWatchEvent, Str].
fn _err_event(m: Str) -> Result[ZkWatchEvent, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkCreateRequest, Str].
fn _ok_crq(v: ZkCreateRequest) -> Result[ZkCreateRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkCreateRequest, Str].
fn _err_crq(m: Str) -> Result[ZkCreateRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkPathWatchRequest, Str].
fn _ok_pwr(v: ZkPathWatchRequest) -> Result[ZkPathWatchRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkPathWatchRequest, Str].
fn _err_pwr(m: Str) -> Result[ZkPathWatchRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkSetDataRequest, Str].
fn _ok_sdr(v: ZkSetDataRequest) -> Result[ZkSetDataRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkSetDataRequest, Str].
fn _err_sdr(m: Str) -> Result[ZkSetDataRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkPathVersionRequest, Str].
fn _ok_pvr(v: ZkPathVersionRequest) -> Result[ZkPathVersionRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkPathVersionRequest, Str].
fn _err_pvr(m: Str) -> Result[ZkPathVersionRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkSetAclRequest, Str].
fn _ok_sar(v: ZkSetAclRequest) -> Result[ZkSetAclRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkSetAclRequest, Str].
fn _err_sar(m: Str) -> Result[ZkSetAclRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkAuthRequest, Str].
fn _ok_arq(v: ZkAuthRequest) -> Result[ZkAuthRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkAuthRequest, Str].
fn _err_arq(m: Str) -> Result[ZkAuthRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkGetChildrenResponse, Str].
fn _ok_gcr(v: ZkGetChildrenResponse) -> Result[ZkGetChildrenResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkGetChildrenResponse, Str].
fn _err_gcr(m: Str) -> Result[ZkGetChildrenResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkGetDataResponse, Str].
fn _ok_gdr(v: ZkGetDataResponse) -> Result[ZkGetDataResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkGetDataResponse, Str].
fn _err_gdr(m: Str) -> Result[ZkGetDataResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkGetAclResponse, Str].
fn _ok_gar(v: ZkGetAclResponse) -> Result[ZkGetAclResponse, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkGetAclResponse, Str].
fn _err_gar(m: Str) -> Result[ZkGetAclResponse, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkMessage, Str].
fn _ok_msg(v: ZkMessage) -> Result[ZkMessage, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkMessage, Str].
fn _err_msg(m: Str) -> Result[ZkMessage, Str] {
  return Err(m);
}

// Ok(v) for Result[ZkReply, Str].
fn _ok_reply(v: ZkReply) -> Result[ZkReply, Str] {
  return Ok(v);
}

// Err(m) for Result[ZkReply, Str].
fn _err_reply(m: Str) -> Result[ZkReply, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Data model
// --------------------------------------------------

/// An append-only encoder over a byte buffer. Create with `zk_writer_new`,
/// write with the `zk_write_*` functions, then take the bytes with
/// `zk_writer_bytes` (a copy).
pub type ZkWriter = {
  data: Vec[UInt8];
}

/// A bounds-checked cursor reader over an immutable byte buffer. Create
/// with `zk_reader_new`; every `zk_read_*` function advances `pos` and
/// rejects reads past the end with a byte-offset message.
pub type ZkReader = {
  data: Vec[UInt8];
  pos: Int;
}

/// ZooKeeper ConnectRequest (session establishment handshake record):
/// `protocolVersion int, lastZxidSeen long, timeOut int, sessionId long,
/// passwd buffer, readOnly bool`. This codec serializes the record only;
/// it does not open sessions.
pub type ZkConnectRequest = {
  protocol_version: Int;
  last_zxid_seen: Int;
  timeout: Int;
  session_id: Int;
  passwd: Vec[UInt8];
  read_only: Bool;
}

/// ZooKeeper ConnectResponse: `protocolVersion int, timeOut int,
/// sessionId long, passwd buffer, readOnly bool`.
pub type ZkConnectResponse = {
  protocol_version: Int;
  timeout: Int;
  session_id: Int;
  passwd: Vec[UInt8];
  read_only: Bool;
}

/// Request header: `xid int` plus the opcode (`type int`).
pub type ZkRequestHeader = {
  xid: Int;
  op: Int;
}

/// Reply header: `xid int, zxid long, err int`.
pub type ZkReplyHeader = {
  xid: Int;
  zxid: Int;
  err: Int;
}

/// ZooKeeper Stat record (68 bytes on the wire): `czxid, mzxid, ctime,
/// mtime` (long), `version, cversion, aversion` (int), `ephemeralOwner`
/// (long), `dataLength, numChildren` (int), `pzxid` (long).
pub type ZkStat = {
  czxid: Int;
  mzxid: Int;
  ctime: Int;
  mtime: Int;
  version: Int;
  cversion: Int;
  aversion: Int;
  ephemeral_owner: Int;
  data_length: Int;
  num_children: Int;
  pzxid: Int;
}

/// An Id record: `scheme ustring, id ustring` (for example "world" /
/// "anyone", or "digest" / "user:base64hash").
pub type ZkId = {
  scheme: Str;
  id: Str;
}

/// An ACL record: `perms int` plus an `Id`.
pub type ZkAcl = {
  perms: Int;
  id: ZkId;
}

/// A flat ACL vector: three parallel vectors, one entry per ACL --
/// `perms[i]`, `schemes[i]`, `ids[i]`. v0.61.3 cannot hold a
/// `Vec[ZkAcl]`, so the vector is stored as parallel columns. The three
/// vectors always have the same length; they are only grown together by
/// `zk_acl_vec_push`.
pub type ZkAclVec = {
  perms: Vec[Int];
  schemes: Vec[Str];
  ids: Vec[Str];
}

/// A watch event / notification: `type int, state int, path ustring`.
/// `path_is_null` records the jute null path (-1 length), because a `Str`
/// cannot distinguish null from empty.
pub type ZkWatchEvent = {
  event_type: Int;
  state: Int;
  path: Str;
  path_is_null: Bool;
}

/// CreateRequest: `path ustring, data buffer, acl vector, flags int`.
/// Flags: EPHEMERAL 1, SEQUENTIAL 2 (both may be combined).
pub type ZkCreateRequest = {
  path: Str;
  data: Vec[UInt8];
  acls: ZkAclVec;
  flags: Int;
}

/// The shared `path ustring, watch bool` request shape used by EXISTS,
/// GET_DATA, GET_CHILDREN, GET_CHILDREN2 and GET_ACL.
pub type ZkPathWatchRequest = {
  path: Str;
  watch: Bool;
}

/// SetDataRequest: `path ustring, data buffer, version int`.
pub type ZkSetDataRequest = {
  path: Str;
  data: Vec[UInt8];
  version: Int;
}

/// The shared `path ustring, version int` request shape used by DELETE
/// and CHECK.
pub type ZkPathVersionRequest = {
  path: Str;
  version: Int;
}

/// SetACLRequest: `path ustring, acl vector, version int`.
pub type ZkSetAclRequest = {
  path: Str;
  acls: ZkAclVec;
  version: Int;
}

/// AuthPacket: `type int, scheme ustring, auth buffer`.
pub type ZkAuthRequest = {
  auth_type: Int;
  scheme: Str;
  auth_data: Vec[UInt8];
}

/// GetChildrenResponse: `children vector<ustring>, stat Stat`.
pub type ZkGetChildrenResponse = {
  children: Vec[Str];
  stat: ZkStat;
}

/// GetDataResponse: `data buffer, stat Stat`.
pub type ZkGetDataResponse = {
  data: Vec[UInt8];
  stat: ZkStat;
}

/// GetACLResponse: `acl vector<ACL>, stat Stat`.
pub type ZkGetAclResponse = {
  acls: ZkAclVec;
  stat: ZkStat;
}

/// One parsed request message: the request header plus the body fields
/// relevant to `body_kind` (the rest keep their zero value). `consumed`
/// is the total byte count of header + body, so a stream framer can
/// advance by it.
pub type ZkMessage = {
  xid: Int;
  op: Int;
  body_kind: Int;
  consumed: Int;
  path: Str;
  path_is_null: Bool;
  version: Int;
  watch: Bool;
  flags: Int;
  data: Vec[UInt8];
  acls: ZkAclVec;
  event_type: Int;
  state: Int;
  auth_type: Int;
  auth_scheme: Str;
  auth_data: Vec[UInt8];
}

/// One parsed reply: the reply header plus the body fields relevant to
/// `body_kind`. When `is_error` is true the server sent no body (the
/// error code is in `err`), matching the ZooKeeper wire behaviour.
pub type ZkReply = {
  xid: Int;
  zxid: Int;
  err: Int;
  is_error: Bool;
  body_kind: Int;
  consumed: Int;
  path: Str;
  data: Vec[UInt8];
  stat: ZkStat;
  children: Vec[Str];
  acls: ZkAclVec;
}

// --------------------------------------------------
//  Constants
// --------------------------------------------------

const _PROTOCOL_VERSION: Int = 0;   // ZooKeeper clients send protocolVersion 0

const _OP_ERROR: Int = -1;
const _OP_NOTIFICATION: Int = 0;
const _OP_CREATE: Int = 1;
const _OP_DELETE: Int = 2;
const _OP_EXISTS: Int = 3;
const _OP_GET_DATA: Int = 4;
const _OP_SET_DATA: Int = 5;
const _OP_GET_ACL: Int = 6;
const _OP_SET_ACL: Int = 7;
const _OP_GET_CHILDREN: Int = 8;
const _OP_SYNC: Int = 9;
const _OP_CREATE_SESSION: Int = -10;
const _OP_PING: Int = 11;
const _OP_GET_CHILDREN2: Int = 12;
const _OP_CHECK: Int = 13;
const _OP_MULTI: Int = 14;
const _OP_CREATE2: Int = 15;
const _OP_CLOSE: Int = -11;
const _OP_AUTH: Int = 100;
const _OP_SET_WATCHES: Int = 101;

const _XID_NOTIFICATION: Int = -1;
const _XID_PING: Int = -2;
const _XID_AUTH: Int = -4;
const _XID_SET_WATCHES: Int = -8;

const _EVENT_NONE: Int = -1;
const _EVENT_NODE_CREATED: Int = 1;
const _EVENT_NODE_DELETED: Int = 2;
const _EVENT_NODE_DATA_CHANGED: Int = 3;
const _EVENT_NODE_CHILDREN_CHANGED: Int = 4;

const _STATE_DISCONNECTED: Int = 0;
const _STATE_SYNC_CONNECTED: Int = 3;
const _STATE_AUTH_FAILED: Int = 4;
const _STATE_CONNECTED_READ_ONLY: Int = 5;
const _STATE_SASL_AUTHENTICATED: Int = 6;
const _STATE_EXPIRED: Int = -112;

const _ERR_OK: Int = 0;
const _ERR_SYSTEMERROR: Int = -1;
const _ERR_RUNTIMEINCONSISTENCY: Int = -2;
const _ERR_DATAINCONSISTENCY: Int = -3;
const _ERR_CONNECTIONLOSS: Int = -4;
const _ERR_MARSHALLINGERROR: Int = -5;
const _ERR_UNIMPLEMENTED: Int = -6;
const _ERR_OPERATIONTIMEOUT: Int = -7;
const _ERR_BADARGUMENTS: Int = -8;
const _ERR_UNKNOWNSESSION: Int = -12;
const _ERR_NEWCONFIGNOQUORUM: Int = -13;
const _ERR_RECONFIGINPROGRESS: Int = -14;
const _ERR_NONODE: Int = -101;
const _ERR_NOAUTH: Int = -102;
const _ERR_BADVERSION: Int = -103;
const _ERR_NOCHILDRENFOREPHEMERALS: Int = -108;
const _ERR_NODEEXISTS: Int = -110;
const _ERR_NOTEMPTY: Int = -111;
const _ERR_SESSIONEXPIRED: Int = -112;
const _ERR_INVALIDCALLBACK: Int = -113;
const _ERR_INVALIDACL: Int = -114;
const _ERR_AUTHFAILED: Int = -115;
const _ERR_NOTHING: Int = -117;
const _ERR_SESSIONMOVED: Int = -118;
const _ERR_NOTREADONLY: Int = -119;
const _ERR_EPHEMERALONLOCALSESSION: Int = -120;
const _ERR_NOWATCHER: Int = -121;
const _ERR_REQUESTTIMEOUT: Int = -122;
const _ERR_RECONFIGDISABLED: Int = -123;
const _ERR_THROTTLEDOP: Int = -127;

const _FLAG_EPHEMERAL: Int = 1;
const _FLAG_SEQUENTIAL: Int = 2;

const _BODY_EMPTY: Int = 0;
const _BODY_CREATE: Int = 1;
const _BODY_DELETE: Int = 2;
const _BODY_EXISTS: Int = 3;
const _BODY_GET_DATA: Int = 4;
const _BODY_SET_DATA: Int = 5;
const _BODY_GET_ACL: Int = 6;
const _BODY_SET_ACL: Int = 7;
const _BODY_GET_CHILDREN: Int = 8;
const _BODY_SYNC: Int = 9;
const _BODY_CHECK: Int = 10;
const _BODY_AUTH: Int = 11;
const _BODY_NOTIFICATION: Int = 12;
const _BODY_STAT: Int = 13;
const _BODY_PATH: Int = 14;

const _STAT_SIZE: Int = 68;

// --------------------------------------------------
//  Public metadata, opcodes, xids, tables
// --------------------------------------------------

/// ConnectRequest protocolVersion emitted by ZooKeeper clients (0).
/// Complexity: O(1).
pub fn zk_protocol_version() -> Int {
  return 0;
}

/// Wire size of a Stat record in bytes (68). Complexity: O(1).
pub fn zk_stat_wire_size() -> Int {
  return 68;
}

/// The jute null length/count sentinel used by buffer, ustring and
/// vector (-1). Complexity: O(1).
pub fn zk_null_len() -> Int {
  return -1;
}

/// Opcode of ERROR (-1), the reply opcode for a server-side error frame.
/// Complexity: O(1).
pub fn zk_op_error() -> Int {
  return -1;
}

/// Opcode of NOTIFICATION (0), the server-to-client watch event.
/// Complexity: O(1).
pub fn zk_op_notification() -> Int {
  return 0;
}

/// Opcode of CREATE (1). Complexity: O(1).
pub fn zk_op_create() -> Int {
  return 1;
}

/// Opcode of DELETE (2). Complexity: O(1).
pub fn zk_op_delete() -> Int {
  return 2;
}

/// Opcode of EXISTS (3). Complexity: O(1).
pub fn zk_op_exists() -> Int {
  return 3;
}

/// Opcode of GET_DATA (4). Complexity: O(1).
pub fn zk_op_get_data() -> Int {
  return 4;
}

/// Opcode of SET_DATA (5). Complexity: O(1).
pub fn zk_op_set_data() -> Int {
  return 5;
}

/// Opcode of GET_ACL (6). Complexity: O(1).
pub fn zk_op_get_acl() -> Int {
  return 6;
}

/// Opcode of SET_ACL (7). Complexity: O(1).
pub fn zk_op_set_acl() -> Int {
  return 7;
}

/// Opcode of GET_CHILDREN (8). Complexity: O(1).
pub fn zk_op_get_children() -> Int {
  return 8;
}

/// Opcode of SYNC (9). Complexity: O(1).
pub fn zk_op_sync() -> Int {
  return 9;
}

/// Opcode of CREATE_SESSION (-10), the session handshake. Documented
/// extra: it is not a request this codec body-parses, but it is a real
/// wire opcode. Complexity: O(1).
pub fn zk_op_create_session() -> Int {
  return -10;
}

/// Opcode of PING (11). Complexity: O(1).
pub fn zk_op_ping() -> Int {
  return 11;
}

/// Opcode of GET_CHILDREN2 (12). Complexity: O(1).
pub fn zk_op_get_children2() -> Int {
  return 12;
}

/// Opcode of CHECK (13). Complexity: O(1).
pub fn zk_op_check() -> Int {
  return 13;
}

/// Opcode of MULTI (14). The opcode is known, but transaction bodies are
/// a documented non-goal of this codec. Complexity: O(1).
pub fn zk_op_multi() -> Int {
  return 14;
}

/// Opcode of CREATE2 (15). Complexity: O(1).
pub fn zk_op_create2() -> Int {
  return 15;
}

/// Opcode of CLOSE (-11). Complexity: O(1).
pub fn zk_op_close() -> Int {
  return -11;
}

/// Opcode of AUTH (100). Complexity: O(1).
pub fn zk_op_auth() -> Int {
  return 100;
}

/// Opcode of SET_WATCHES (101). Complexity: O(1).
pub fn zk_op_set_watches() -> Int {
  return 101;
}

/// Special xid of a notification (-1). Complexity: O(1).
pub fn zk_xid_notification() -> Int {
  return -1;
}

/// Special xid of a ping (-2). Complexity: O(1).
pub fn zk_xid_ping() -> Int {
  return -2;
}

/// Special xid of an auth packet (-4). Complexity: O(1).
pub fn zk_xid_auth() -> Int {
  return -4;
}

/// Special xid of a setWatches packet (-8). Complexity: O(1).
pub fn zk_xid_set_watches() -> Int {
  return -8;
}

/// Watch event type NONE (-1). Complexity: O(1).
pub fn zk_event_none() -> Int {
  return -1;
}

/// Watch event type NODE_CREATED (1). Complexity: O(1).
pub fn zk_event_node_created() -> Int {
  return 1;
}

/// Watch event type NODE_DELETED (2). Complexity: O(1).
pub fn zk_event_node_deleted() -> Int {
  return 2;
}

/// Watch event type NODE_DATA_CHANGED (3). Complexity: O(1).
pub fn zk_event_node_data_changed() -> Int {
  return 3;
}

/// Watch event type NODE_CHILDREN_CHANGED (4). Complexity: O(1).
pub fn zk_event_node_children_changed() -> Int {
  return 4;
}

/// Watch state DISCONNECTED (0). Complexity: O(1).
pub fn zk_state_disconnected() -> Int {
  return 0;
}

/// Watch state SYNC_CONNECTED (3). Complexity: O(1).
pub fn zk_state_sync_connected() -> Int {
  return 3;
}

/// Watch state AUTH_FAILED (4). Complexity: O(1).
pub fn zk_state_auth_failed() -> Int {
  return 4;
}

/// Watch state CONNECTED_READ_ONLY (5). Complexity: O(1).
pub fn zk_state_connected_read_only() -> Int {
  return 5;
}

/// Watch state SASL_AUTHENTICATED (6). Complexity: O(1).
pub fn zk_state_sasl_authenticated() -> Int {
  return 6;
}

/// Watch state EXPIRED (-112). Complexity: O(1).
pub fn zk_state_expired() -> Int {
  return -112;
}

/// Create flag EPHEMERAL (1). Complexity: O(1).
pub fn zk_create_flag_ephemeral() -> Int {
  return 1;
}

/// Create flag SEQUENTIAL (2). Complexity: O(1).
pub fn zk_create_flag_sequential() -> Int {
  return 2;
}

/// True when the EPHEMERAL bit of a create-flag word is set (assumes a
/// non-negative flag word). Complexity: O(1).
pub fn zk_create_flag_is_ephemeral(flags: Int) -> Bool {
  if flags < 0 {
    return false;
  }
  return flags % 2 == 1;
}

/// True when the SEQUENTIAL bit of a create-flag word is set (assumes a
/// non-negative flag word). Complexity: O(1).
pub fn zk_create_flag_is_sequential(flags: Int) -> Bool {
  if flags < 0 {
    return false;
  }
  let half: Int = flags / 2;
  return half % 2 == 1;
}

/// Error code OK (0). Complexity: O(1).
pub fn zk_err_ok() -> Int {
  return 0;
}

/// Error code SYSTEMERROR (-1). Complexity: O(1).
pub fn zk_err_systemerror() -> Int {
  return -1;
}

/// Error code RUNTIMEINCONSISTENCY (-2). Complexity: O(1).
pub fn zk_err_runtimeinconsistency() -> Int {
  return -2;
}

/// Error code DATAINCONSISTENCY (-3). Complexity: O(1).
pub fn zk_err_datainconsistency() -> Int {
  return -3;
}

/// Error code CONNECTIONLOSS (-4). This is the canonical Apache
/// ZooKeeper value; see SPEC.md "Caveats". Complexity: O(1).
pub fn zk_err_connectionloss() -> Int {
  return -4;
}

/// Error code MARSHALLINGERROR (-5). Complexity: O(1).
pub fn zk_err_marshallingerror() -> Int {
  return -5;
}

/// Error code UNIMPLEMENTED (-6). Complexity: O(1).
pub fn zk_err_unimplemented() -> Int {
  return -6;
}

/// Error code OPERATIONTIMEOUT (-7). This is the canonical Apache
/// ZooKeeper value; see SPEC.md "Caveats". Complexity: O(1).
pub fn zk_err_operationtimeout() -> Int {
  return -7;
}

/// Error code BADARGUMENTS (-8). Complexity: O(1).
pub fn zk_err_badarguments() -> Int {
  return -8;
}

/// Error code UNKNOWNSESSION (-12). Complexity: O(1).
pub fn zk_err_unknownsession() -> Int {
  return -12;
}

/// Error code NEWCONFIGNOQUORUM (-13). Complexity: O(1).
pub fn zk_err_newconfignoquorum() -> Int {
  return -13;
}

/// Error code RECONFIGINPROGRESS (-14). Complexity: O(1).
pub fn zk_err_reconfiginprogress() -> Int {
  return -14;
}

/// Error code NONODE (-101). Complexity: O(1).
pub fn zk_err_nonode() -> Int {
  return -101;
}

/// Error code NOAUTH (-102). Complexity: O(1).
pub fn zk_err_noauth() -> Int {
  return -102;
}

/// Error code BADVERSION (-103). Complexity: O(1).
pub fn zk_err_badversion() -> Int {
  return -103;
}

/// Error code NOCHILDRENFOREPHEMERALS (-108). Complexity: O(1).
pub fn zk_err_nochildrenforephemerals() -> Int {
  return -108;
}

/// Error code NODEEXISTS (-110). Complexity: O(1).
pub fn zk_err_nodeexists() -> Int {
  return -110;
}

/// Error code NOTEMPTY (-111). Complexity: O(1).
pub fn zk_err_notempty() -> Int {
  return -111;
}

/// Error code SESSIONEXPIRED (-112). Complexity: O(1).
pub fn zk_err_sessionexpired() -> Int {
  return -112;
}

/// Error code INVALIDCALLBACK (-113). Complexity: O(1).
pub fn zk_err_invalidcallback() -> Int {
  return -113;
}

/// Error code INVALIDACL (-114). Complexity: O(1).
pub fn zk_err_invalidacl() -> Int {
  return -114;
}

/// Error code AUTHFAILED (-115). Complexity: O(1).
pub fn zk_err_authfailed() -> Int {
  return -115;
}

/// Error code NOTHING (-117). Complexity: O(1).
pub fn zk_err_nothing() -> Int {
  return -117;
}

/// Error code SESSIONMOVED (-118). Complexity: O(1).
pub fn zk_err_sessionmoved() -> Int {
  return -118;
}

/// Error code NOTREADONLY (-119). Complexity: O(1).
pub fn zk_err_notreadonly() -> Int {
  return -119;
}

/// Error code EPHEMERALONLOCALSESSION (-120). Complexity: O(1).
pub fn zk_err_ephemeralonlocalsession() -> Int {
  return -120;
}

/// Error code NOWATCHER (-121). Complexity: O(1).
pub fn zk_err_nowatcher() -> Int {
  return -121;
}

/// Error code REQUESTTIMEOUT (-122). Complexity: O(1).
pub fn zk_err_requesttimeout() -> Int {
  return -122;
}

/// Error code RECONFIGDISABLED (-123). Complexity: O(1).
pub fn zk_err_reconfigdisabled() -> Int {
  return -123;
}

/// Error code THROTTLEDOP (-127). Complexity: O(1).
pub fn zk_err_throttledop() -> Int {
  return -127;
}

/// True when `op` appears in the opcode table this codec knows.
/// Complexity: O(1).
pub fn zk_op_known(op: Int) -> Bool {
  if op == -1 || op == 0 || op == 1 || op == 2 || op == 3 {
    return true;
  }
  if op == 4 || op == 5 || op == 6 || op == 7 || op == 8 {
    return true;
  }
  if op == 9 || op == -10 || op == 11 || op == 12 || op == 13 {
    return true;
  }
  if op == 14 || op == 15 || op == -11 || op == 100 || op == 101 {
    return true;
  }
  return false;
}

/// Mnemonic of an opcode, or "UNKNOWN" when the code is not in the
/// table. Complexity: O(1).
pub fn zk_op_name(op: Int) -> Str {
  if op == -1 { return "ERROR"; }
  if op == 0 { return "NOTIFICATION"; }
  if op == 1 { return "CREATE"; }
  if op == 2 { return "DELETE"; }
  if op == 3 { return "EXISTS"; }
  if op == 4 { return "GET_DATA"; }
  if op == 5 { return "SET_DATA"; }
  if op == 6 { return "GET_ACL"; }
  if op == 7 { return "SET_ACL"; }
  if op == 8 { return "GET_CHILDREN"; }
  if op == 9 { return "SYNC"; }
  if op == -10 { return "CREATE_SESSION"; }
  if op == 11 { return "PING"; }
  if op == 12 { return "GET_CHILDREN2"; }
  if op == 13 { return "CHECK"; }
  if op == 14 { return "MULTI"; }
  if op == 15 { return "CREATE2"; }
  if op == -11 { return "CLOSE"; }
  if op == 100 { return "AUTH"; }
  if op == 101 { return "SET_WATCHES"; }
  return "UNKNOWN";
}

/// True when `xid` is one of the special (negative) xid values used for
/// out-of-band traffic. Complexity: O(1).
pub fn zk_xid_is_special(xid: Int) -> Bool {
  if xid == -1 || xid == -2 || xid == -4 || xid == -8 {
    return true;
  }
  return false;
}

/// Mnemonic of a special xid, or "REQUEST" for a non-negative request
/// xid, or "UNKNOWN" for any other negative value. Complexity: O(1).
pub fn zk_xid_name(xid: Int) -> Str {
  if xid == -1 { return "NOTIFICATION"; }
  if xid == -2 { return "PING"; }
  if xid == -4 { return "AUTH"; }
  if xid == -8 { return "SET_WATCHES"; }
  if xid >= 0 { return "REQUEST"; }
  return "UNKNOWN";
}

/// Mnemonic of a watch event type, or "UNKNOWN". Complexity: O(1).
pub fn zk_event_name(t: Int) -> Str {
  if t == -1 { return "NONE"; }
  if t == 1 { return "NODE_CREATED"; }
  if t == 2 { return "NODE_DELETED"; }
  if t == 3 { return "NODE_DATA_CHANGED"; }
  if t == 4 { return "NODE_CHILDREN_CHANGED"; }
  return "UNKNOWN";
}

/// Mnemonic of a watch state, or "UNKNOWN". Complexity: O(1).
pub fn zk_state_name(s: Int) -> Str {
  if s == 0 { return "DISCONNECTED"; }
  if s == 3 { return "SYNC_CONNECTED"; }
  if s == 4 { return "AUTH_FAILED"; }
  if s == 5 { return "CONNECTED_READ_ONLY"; }
  if s == 6 { return "SASL_AUTHENTICATED"; }
  if s == -112 { return "EXPIRED"; }
  return "UNKNOWN";
}

/// Mnemonic of an error code, or "UNKNOWN". Complexity: O(1).
pub fn zk_err_name(code: Int) -> Str {
  if code == 0 { return "OK"; }
  if code == -1 { return "SYSTEMERROR"; }
  if code == -2 { return "RUNTIMEINCONSISTENCY"; }
  if code == -3 { return "DATAINCONSISTENCY"; }
  if code == -4 { return "CONNECTIONLOSS"; }
  if code == -5 { return "MARSHALLINGERROR"; }
  if code == -6 { return "UNIMPLEMENTED"; }
  if code == -7 { return "OPERATIONTIMEOUT"; }
  if code == -8 { return "BADARGUMENTS"; }
  if code == -12 { return "UNKNOWNSESSION"; }
  if code == -13 { return "NEWCONFIGNOQUORUM"; }
  if code == -14 { return "RECONFIGINPROGRESS"; }
  if code == -101 { return "NONODE"; }
  if code == -102 { return "NOAUTH"; }
  if code == -103 { return "BADVERSION"; }
  if code == -108 { return "NOCHILDRENFOREPHEMERALS"; }
  if code == -110 { return "NODEEXISTS"; }
  if code == -111 { return "NOTEMPTY"; }
  if code == -112 { return "SESSIONEXPIRED"; }
  if code == -113 { return "INVALIDCALLBACK"; }
  if code == -114 { return "INVALIDACL"; }
  if code == -115 { return "AUTHFAILED"; }
  if code == -117 { return "NOTHING"; }
  if code == -118 { return "SESSIONMOVED"; }
  if code == -119 { return "NOTREADONLY"; }
  if code == -120 { return "EPHEMERALONLOCALSESSION"; }
  if code == -121 { return "NOWATCHER"; }
  if code == -122 { return "REQUESTTIMEOUT"; }
  if code == -123 { return "RECONFIGDISABLED"; }
  if code == -127 { return "THROTTLEDOP"; }
  return "UNKNOWN";
}

/// True when `code` appears in the error table. Complexity: O(1).
pub fn zk_err_known(code: Int) -> Bool {
  let n = zk_err_name(code);
  return str_compare(n, "UNKNOWN") != 0;
}

/// Mnemonic of a parsed body kind. Complexity: O(1).
pub fn zk_body_kind_name(kind: Int) -> Str {
  if kind == 0 { return "EMPTY"; }
  if kind == 1 { return "CREATE"; }
  if kind == 2 { return "DELETE"; }
  if kind == 3 { return "EXISTS"; }
  if kind == 4 { return "GET_DATA"; }
  if kind == 5 { return "SET_DATA"; }
  if kind == 6 { return "GET_ACL"; }
  if kind == 7 { return "SET_ACL"; }
  if kind == 8 { return "GET_CHILDREN"; }
  if kind == 9 { return "SYNC"; }
  if kind == 10 { return "CHECK"; }
  if kind == 11 { return "AUTH"; }
  if kind == 12 { return "NOTIFICATION"; }
  if kind == 13 { return "STAT"; }
  if kind == 14 { return "PATH"; }
  return "UNKNOWN";
}

// --------------------------------------------------
//  Byte helpers
// --------------------------------------------------

// 2^k for 0 <= k <= 32.
fn _pow2(k: Int) -> Int {
  var v = 1;
  var i = 0;
  while i < k {
    v = v * 2;
    i = i + 1;
  }
  return v;
}

// Sign-extend the unsigned value `v` (0 <= v < 2^bits) to a signed Int.
// bits is 8, 16 or 32.
fn _sign_extend(v: Int, bits: Int) -> Int {
  let half = _pow2(bits - 1);
  if v >= half {
    let full = _pow2(bits);
    return v - full;
  }
  return v;
}

// Byte `shift_bytes` of `v` in big-endian order (0 = least significant
// byte), as the exact two's-complement bit pattern. Arithmetic only.
fn _be_byte(v: Int, shift_bytes: Int) -> UInt8 {
  var q = v;
  var k = 0;
  while k < shift_bytes {
    var r = q % 256;
    if r < 0 { r = r + 256; }
    q = (q - r) / 256;
    k = k + 1;
  }
  var b = q % 256;
  if b < 0 { b = b + 256; }
  return b as UInt8;
}

// Append one byte (low 8 bits of `b`).
fn _w_push_byte(w: &mut ZkWriter, b: Int) {
  var q = b % 256;
  if q < 0 { q = q + 256; }
  w.data.push(q as UInt8);
}

// Append the low `size` bytes of `v` in big-endian order (size 1..8).
fn _w_push_be(w: &mut ZkWriter, v: Int, size: Int) {
  var i = size - 1;
  while i >= 0 {
    w.data.push(_be_byte(v, i));
    i = i - 1;
  }
}

// Append every UTF-8 byte of `s`.
fn _w_push_str(w: &mut ZkWriter, s: Str) {
  let n = string.str_len(s);
  var i = 0;
  while i < n {
    w.data.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// Append every byte of `v`.
fn _w_push_bytes(w: &mut ZkWriter, v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    w.data.push(v[i]);
    i = i + 1;
  }
}

// Append the jute null length/count (-1).
fn _w_push_null(w: &mut ZkWriter) {
  _w_push_be(w, -1, 4);
}

// A fresh copy of `src` (used where a returned vector must not alias).
fn _copy_bytes(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

// Byte at `pos` widened to 0..255. The caller guarantees the index is in
// bounds.
fn _r_byte(r: &ZkReader, pos: Int) -> Int {
  return (r.data[pos] as Int) & 0xFF;
}

// Same as _r_byte but takes &mut, so reader bodies never mix a `&` call
// before a `&mut` access on the same local (advisory E001).
fn _r_byte_mut(r: &mut ZkReader, pos: Int) -> Int {
  return _r_byte(r, pos);
}

// Read `size` (1..4) bytes big-endian into an unsigned Int, advancing the
// cursor. Err("zookeeper: truncated input at byte N") when fewer than
// `size` bytes remain.
fn _read_unsigned(r: &mut ZkReader, size: Int) -> Result[Int, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  if start + size > total {
    return _err_int(_trunc_at(start));
  }
  var v: Int = 0;
  var i = 0;
  while i < size {
    let b = _r_byte_mut(r, start + i);
    v = v * 256 + b;
    i = i + 1;
  }
  r.pos = start + size;
  return _ok_int(v);
}

// Read 8 bytes big-endian as the exact 64-bit two's-complement pattern.
// The low 63 bits are accumulated (never overflowing) and the top bit is
// applied as a sign afterwards, so every Int64 pattern round-trips.
fn _read_raw64(r: &mut ZkReader) -> Result[Int, Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  if start + 8 > total {
    return _err_int(_trunc_at(start));
  }
  let b0 = _r_byte_mut(r, start);
  let neg = b0 >= 128;
  var v: Int = b0 % 128;
  var i = 1;
  while i < 8 {
    let b = _r_byte_mut(r, start + i);
    v = v * 256 + b;
    i = i + 1;
  }
  r.pos = start + 8;
  if neg {
    v = v - 9223372036854775807 - 1;
  }
  return _ok_int(v);
}

// Read a signed 32-bit big-endian int.
fn _read_i32(r: &mut ZkReader) -> Result[Int, Str] {
  let ur = _read_unsigned(r, 4);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let v: Int = ur.value;
  return _ok_int(_sign_extend(v, 32));
}

// Read exactly `n` bytes into a fresh vector, advancing the cursor.
// Err("zookeeper: truncated input at byte N") when `n` bytes are not
// available.
fn _read_bytes_n(r: &mut ZkReader, n: Int) -> Result[Vec[UInt8], Str] {
  let start: Int = r.pos;
  let total: Int = r.data.len();
  if n < 0 || start + n > total {
    return _err_bytes(_trunc_at(start));
  }
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(r.data[start + i]);
    i = i + 1;
  }
  r.pos = start + n;
  return _ok_bytes(out);
}

// The bytes of `v` as a Str. Only called on NUL-free byte vectors that
// were validated at the API boundary, so sb_to_str cannot abort.
fn _bytes_to_str(v: &Vec[UInt8]) -> Str {
  var sb = Vec[UInt8].new();
  var i = 0;
  while i < v.len() {
    sb.push(v[i]);
    i = i + 1;
  }
  return builder.sb_to_str(&sb);
}

// `msg` with the byte offset appended: "msg at byte N".
fn _msg_at(msg: Str, off: Int) -> Str {
  return msg + " at byte " + convert.int_to_string(off);
}

// The documented truncation error at offset `off`.
fn _trunc_at(off: Int) -> Str {
  return _msg_at("zookeeper: truncated input", off);
}

// Lower-bound guard for a vector count: every element occupies at least
// `min_elem` bytes (1 for scalars, 4 for strings, 12 for ACLs), so a
// count above the bytes remaining is rejected before any loop starts.
// A negative count (null) passes; "" means no error.
fn _vector_guard(r: &ZkReader, count: Int, min_elem: Int, off: Int) -> Str {
  if count < 0 {
    return "";
  }
  let total: Int = r.data.len();
  let remaining: Int = total - r.pos;
  if remaining < 0 {
    return _msg_at("zookeeper: oversized vector count " + convert.int_to_string(count), off);
  }
  if count > remaining / min_elem {
    return _msg_at("zookeeper: oversized vector count " + convert.int_to_string(count), off);
  }
  return "";
}

// UTF-8 validation of a string payload (RFC 3629, strict: overlong forms
// and surrogates are rejected). `base` is the absolute offset of
// bytes[0], so diagnostics point at the offending byte. Returns "" when
// valid, otherwise the deterministic error. A 0x00 byte is valid UTF-8
// but is reported separately because a NUL would abort the v0.61.3
// string builder.
fn _utf8_error(bytes: &Vec[UInt8], base: Int) -> Str {
  let n = bytes.len();
  var i = 0;
  while i < n {
    let b: Int = (bytes[i] as Int) & 0xFF;
    if b == 0 {
      return _msg_at("zookeeper: string contains nul", base + i);
    }
    if b < 128 {
      i = i + 1;
    } elif b < 192 {
      return _msg_at("zookeeper: invalid utf-8", base + i);
    } elif b < 194 {
      return _msg_at("zookeeper: invalid utf-8", base + i);
    } elif b < 224 {
      if i + 1 >= n {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      i = i + 2;
    } elif b < 240 {
      if i + 2 >= n {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      if c2 < 128 || c2 >= 192 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      if b == 224 && c1 < 160 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      if b == 237 && c1 >= 160 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      i = i + 3;
    } else {
      if b >= 245 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      if i + 3 >= n {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      let c1: Int = (bytes[i + 1] as Int) & 0xFF;
      let c2: Int = (bytes[i + 2] as Int) & 0xFF;
      let c3: Int = (bytes[i + 3] as Int) & 0xFF;
      if c1 < 128 || c1 >= 192 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      if c2 < 128 || c2 >= 192 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      if c3 < 128 || c3 >= 192 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      if b == 240 && c1 < 144 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      if b == 244 && c1 >= 144 {
        return _msg_at("zookeeper: invalid utf-8", base + i);
      }
      i = i + 4;
    }
  }
  return "";
}

// --------------------------------------------------
//  Writer and reader lifecycle
// --------------------------------------------------

/// A fresh empty writer. Complexity: O(1).
pub fn zk_writer_new() -> ZkWriter {
  return ZkWriter{ data: Vec[UInt8].new() };
}

/// Number of bytes written so far. Complexity: O(1).
pub fn zk_writer_len(w: &ZkWriter) -> Int {
  return w.data.len();
}

/// A copy of the bytes written so far. Complexity: O(written bytes).
pub fn zk_writer_bytes(w: &ZkWriter) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < w.data.len() {
    out.push(w.data[i]);
    i = i + 1;
  }
  return out;
}

/// A reader positioned at offset 0 of `data`. Complexity: O(1).
pub fn zk_reader_new(data: Vec[UInt8]) -> ZkReader {
  return ZkReader{ data: data; pos: 0; };
}

/// Current cursor offset. Complexity: O(1).
pub fn zk_reader_pos(r: &ZkReader) -> Int {
  return r.pos;
}

/// Bytes left after the cursor (0 when the cursor is at or past the end).
/// Complexity: O(1).
pub fn zk_reader_remaining(r: &ZkReader) -> Int {
  let total: Int = r.data.len();
  let rem: Int = total - r.pos;
  if rem < 0 {
    return 0;
  }
  return rem;
}

// --------------------------------------------------
//  Primitive values
// --------------------------------------------------

/// Write a jute byte (int8): the low 8 bits of `v`, two's complement.
/// Complexity: O(1).
pub fn zk_write_byte(w: &mut ZkWriter, v: Int) {
  _w_push_be(w, v, 1);
}

/// Decode a signed jute byte (int8, -128..127). Complexity: O(1).
pub fn zk_read_byte(r: &mut ZkReader) -> Result[Int, Str] {
  let ur = _read_unsigned(r, 1);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let v: Int = ur.value;
  return _ok_int(_sign_extend(v, 8));
}

/// Write a jute bool: one byte, 1 for true, 0 for false. Complexity:
/// O(1).
pub fn zk_write_bool(w: &mut ZkWriter, v: Bool) {
  if v {
    _w_push_byte(w, 1);
  } else {
    _w_push_byte(w, 0);
  }
}

/// Decode a jute bool. Only 0 (false) and 1 (true) are accepted;
/// Err("zookeeper: invalid bool byte B at byte N") otherwise.
/// Complexity: O(1).
pub fn zk_read_bool(r: &mut ZkReader) -> Result[Bool, Str] {
  let total: Int = r.data.len();
  let start: Int = r.pos;
  if start >= total {
    return _err_bool(_trunc_at(start));
  }
  let b = _r_byte_mut(r, start);
  r.pos = start + 1;
  if b == 0 {
    return _ok_bool(false);
  }
  if b == 1 {
    return _ok_bool(true);
  }
  return _err_bool(_msg_at("zookeeper: invalid bool byte " + convert.int_to_string(b), start));
}

/// Write a jute int (int32): four big-endian bytes. Complexity: O(1).
pub fn zk_write_int(w: &mut ZkWriter, v: Int) {
  _w_push_be(w, v, 4);
}

/// Decode a signed jute int (int32). Complexity: O(1).
pub fn zk_read_int(r: &mut ZkReader) -> Result[Int, Str] {
  return _read_i32(r);
}

/// Write a jute long (int64): eight big-endian bytes. Complexity: O(1).
pub fn zk_write_long(w: &mut ZkWriter, v: Int) {
  _w_push_be(w, v, 8);
}

/// Decode a signed jute long (int64, the full Int range). Complexity:
/// O(1).
pub fn zk_read_long(r: &mut ZkReader) -> Result[Int, Str] {
  return _read_raw64(r);
}

/// Write a jute float as its raw 32-bit IEEE-754 bit pattern (`bits`,
/// big-endian). v0.61.3 has no `Int <-> Float64` bitcast, so the caller
/// supplies the pattern; for example 1.0 is 0x3F800000. Complexity:
/// O(1).
pub fn zk_write_float_bits(w: &mut ZkWriter, bits: Int) {
  _w_push_be(w, bits, 4);
}

/// Decode a jute float as its raw 32-bit bit pattern, returned unsigned
/// (0..4294967295): 1.0 is 1065353216, -2.0 is 3221225472. Complexity:
/// O(1).
pub fn zk_read_float_bits(r: &mut ZkReader) -> Result[Int, Str] {
  let ur = _read_unsigned(r, 4);
  if !ur.is_ok {
    return _err_int(ur.error);
  }
  let v: Int = ur.value;
  return _ok_int(v);
}

/// Write a jute double as its raw 64-bit IEEE-754 bit pattern (`bits`,
/// big-endian). Complexity: O(1).
pub fn zk_write_double_bits(w: &mut ZkWriter, bits: Int) {
  _w_push_be(w, bits, 8);
}

/// Decode a jute double as its raw 64-bit bit pattern; patterns with the
/// top bit set come back as negative Ints. Complexity: O(1).
pub fn zk_read_double_bits(r: &mut ZkReader) -> Result[Int, Str] {
  return _read_raw64(r);
}

/// Write a jute buffer: an int32 byte length then the bytes. A null
/// buffer must be written with `zk_write_null_buffer`. Complexity:
/// O(data bytes).
pub fn zk_write_buffer(w: &mut ZkWriter, data: &Vec[UInt8]) {
  _w_push_be(w, data.len(), 4);
  _w_push_bytes(w, data);
}

/// Write a jute null buffer (length -1). Complexity: O(1).
pub fn zk_write_null_buffer(w: &mut ZkWriter) {
  _w_push_null(w);
}

/// Decode a jute buffer. A length of -1 is a null buffer and decodes as
/// an empty vector; any other negative length is
/// Err("zookeeper: invalid buffer length L at byte N"). Complexity:
/// O(payload bytes).
pub fn zk_read_buffer(r: &mut ZkReader) -> Result[Vec[UInt8], Str] {
  let start: Int = r.pos;
  let lr = _read_i32(r);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let n: Int = lr.value;
  if n == -1 {
    return _ok_bytes(Vec[UInt8].new());
  }
  if n < 0 {
    return _err_bytes(_msg_at("zookeeper: invalid buffer length " + convert.int_to_string(n), start));
  }
  let br = _read_bytes_n(r, n);
  if !br.is_ok {
    return _err_bytes(br.error);
  }
  let raw: Vec[UInt8] = br.value;
  return _ok_bytes(raw);
}

/// Write a jute ustring: an int32 byte length then the UTF-8 bytes. A
/// null ustring must be written with `zk_write_null_ustring`.
/// Complexity: O(byte length).
pub fn zk_write_ustring(w: &mut ZkWriter, s: Str) {
  _w_push_be(w, string.str_len(s), 4);
  _w_push_str(w, s);
}

/// Write a jute null ustring (length -1). Complexity: O(1).
pub fn zk_write_null_ustring(w: &mut ZkWriter) {
  _w_push_null(w);
}

/// Decode a jute ustring as a `Str`. A length of -1 is null and decodes
/// as ""; any other negative length is
/// Err("zookeeper: invalid string length L at byte N"). The payload must
/// be valid UTF-8 with no 0x00 byte. Complexity: O(payload bytes).
pub fn zk_read_ustring(r: &mut ZkReader) -> Result[Str, Str] {
  let start: Int = r.pos;
  let lr = _read_i32(r);
  if !lr.is_ok {
    return _err_str(lr.error);
  }
  let n: Int = lr.value;
  if n == -1 {
    return _ok_str("");
  }
  if n < 0 {
    return _err_str(_msg_at("zookeeper: invalid string length " + convert.int_to_string(n), start));
  }
  let poff: Int = r.pos;
  let br = _read_bytes_n(r, n);
  if !br.is_ok {
    return _err_str(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  let ue = _utf8_error(&bytes, poff);
  if ue.len() > 0 {
    return _err_str(ue);
  }
  return _ok_str(_bytes_to_str(&bytes));
}

/// Write a vector count as an int32. A count of -1 is the jute null
/// vector; use `zk_write_vector_null` for clarity. Complexity: O(1).
pub fn zk_write_vector_count(w: &mut ZkWriter, count: Int) {
  _w_push_be(w, count, 4);
}

/// Write a jute null vector (count -1). Complexity: O(1).
pub fn zk_write_vector_null(w: &mut ZkWriter) {
  _w_push_null(w);
}

/// Decode a vector count: -1 (null) or a non-negative count; any other
/// negative value is Err("zookeeper: invalid vector count C at byte N").
/// Complexity: O(1).
pub fn zk_read_vector_count(r: &mut ZkReader) -> Result[Int, Str] {
  let start: Int = r.pos;
  let lr = _read_i32(r);
  if !lr.is_ok {
    return _err_int(lr.error);
  }
  let n: Int = lr.value;
  if n == -1 {
    return _ok_int(-1);
  }
  if n < 0 {
    return _err_int(_msg_at("zookeeper: invalid vector count " + convert.int_to_string(n), start));
  }
  return _ok_int(n);
}

/// Write a vector of ustrings: an int32 count then each ustring.
/// Complexity: O(total bytes).
pub fn zk_write_ustring_vector(w: &mut ZkWriter, v: &Vec[Str]) {
  _w_push_be(w, v.len(), 4);
  var i = 0;
  while i < v.len() {
    let s: Str = v[i];
    zk_write_ustring(w, s);
    i = i + 1;
  }
}

/// Decode a vector of ustrings. A null vector (-1) decodes as empty; the
/// count is bounded by the bytes remaining before any element is read.
/// Complexity: O(total bytes).
pub fn zk_read_ustring_vector(r: &mut ZkReader) -> Result[Vec[Str], Str] {
  let start: Int = r.pos;
  let cr = zk_read_vector_count(r);
  if !cr.is_ok {
    return _err_names(cr.error);
  }
  let count: Int = cr.value;
  var out = Vec[Str].new();
  if count == -1 {
    return _ok_names(out);
  }
  let g = _vector_guard(r, count, 4, start);
  if g.len() > 0 {
    return _err_names(g);
  }
  var i = 0;
  while i < count {
    let sr = zk_read_ustring(r);
    if !sr.is_ok {
      return _err_names(sr.error);
    }
    let s: Str = sr.value;
    out.push(s);
    i = i + 1;
  }
  return _ok_names(out);
}

// --------------------------------------------------
//  Message headers
// --------------------------------------------------

/// Write a request header: xid int, opcode int. Complexity: O(1).
pub fn zk_write_request_header(w: &mut ZkWriter, xid: Int, op: Int) {
  _w_push_be(w, xid, 4);
  _w_push_be(w, op, 4);
}

/// Decode a request header (xid + opcode). Complexity: O(1).
pub fn zk_read_request_header(r: &mut ZkReader) -> Result[ZkRequestHeader, Str] {
  let xr = _read_i32(r);
  if !xr.is_ok {
    return _err_hdr(xr.error);
  }
  let xid: Int = xr.value;
  let opr = _read_i32(r);
  if !opr.is_ok {
    return _err_hdr(opr.error);
  }
  let op: Int = opr.value;
  return _ok_hdr(ZkRequestHeader{ xid: xid; op: op; });
}

/// Write a reply header: xid int, zxid long, err int. Complexity: O(1).
pub fn zk_write_reply_header(w: &mut ZkWriter, xid: Int, zxid: Int, err: Int) {
  _w_push_be(w, xid, 4);
  _w_push_be(w, zxid, 8);
  _w_push_be(w, err, 4);
}

/// Decode a reply header (xid + zxid + err). Complexity: O(1).
pub fn zk_read_reply_header(r: &mut ZkReader) -> Result[ZkReplyHeader, Str] {
  let xr = _read_i32(r);
  if !xr.is_ok {
    return _err_rhdr(xr.error);
  }
  let xid: Int = xr.value;
  let zr = _read_raw64(r);
  if !zr.is_ok {
    return _err_rhdr(zr.error);
  }
  let zxid: Int = zr.value;
  let er = _read_i32(r);
  if !er.is_ok {
    return _err_rhdr(er.error);
  }
  let err: Int = er.value;
  return _ok_rhdr(ZkReplyHeader{ xid: xid; zxid: zxid; err: err; });
}

// --------------------------------------------------
//  Connect handshake records
// --------------------------------------------------

/// Write a ConnectRequest: protocolVersion int, lastZxidSeen long,
/// timeOut int, sessionId long, passwd buffer, readOnly bool. Complexity:
/// O(passwd bytes).
pub fn zk_write_connect_request(w: &mut ZkWriter, req: &ZkConnectRequest) {
  _w_push_be(w, req.protocol_version, 4);
  _w_push_be(w, req.last_zxid_seen, 8);
  _w_push_be(w, req.timeout, 4);
  _w_push_be(w, req.session_id, 8);
  let passwd: Vec[UInt8] = req.passwd;
  zk_write_buffer(w, &passwd);
  zk_write_bool(w, req.read_only);
}

/// Decode a ConnectRequest. Complexity: O(passwd bytes).
pub fn zk_read_connect_request(r: &mut ZkReader) -> Result[ZkConnectRequest, Str] {
  let pr = _read_i32(r);
  if !pr.is_ok {
    return _err_creq(pr.error);
  }
  let protocol_version: Int = pr.value;
  let zr = _read_raw64(r);
  if !zr.is_ok {
    return _err_creq(zr.error);
  }
  let last_zxid_seen: Int = zr.value;
  let tr = _read_i32(r);
  if !tr.is_ok {
    return _err_creq(tr.error);
  }
  let timeout: Int = tr.value;
  let sr = _read_raw64(r);
  if !sr.is_ok {
    return _err_creq(sr.error);
  }
  let session_id: Int = sr.value;
  let br = zk_read_buffer(r);
  if !br.is_ok {
    return _err_creq(br.error);
  }
  let passwd: Vec[UInt8] = br.value;
  let rr = zk_read_bool(r);
  if !rr.is_ok {
    return _err_creq(rr.error);
  }
  let read_only: Bool = rr.value;
  return _ok_creq(ZkConnectRequest{ protocol_version: protocol_version; last_zxid_seen: last_zxid_seen; timeout: timeout; session_id: session_id; passwd: passwd; read_only: read_only; });
}

/// Encode a ConnectRequest to a fresh byte vector. Complexity: O(record
/// bytes).
pub fn zk_encode_connect_request(req: &ZkConnectRequest) -> Vec[UInt8] {
  var w = zk_writer_new();
  zk_write_connect_request(&mut w, req);
  return zk_writer_bytes(&w);
}

/// Decode exactly one ConnectRequest and require that no bytes are left
/// over (Err("zookeeper: trailing data at byte N") otherwise).
/// Complexity: O(record bytes).
pub fn zk_decode_connect_request(data: Vec[UInt8]) -> Result[ZkConnectRequest, Str] {
  let total: Int = data.len();
  var r = zk_reader_new(data);
  let br = zk_read_connect_request(&mut r);
  if !br.is_ok {
    return _err_creq(br.error);
  }
  if r.pos != total {
    return _err_creq(_msg_at("zookeeper: trailing data", r.pos));
  }
  let req: ZkConnectRequest = br.value;
  return _ok_creq(req);
}

/// Write a ConnectResponse: protocolVersion int, timeOut int, sessionId
/// long, passwd buffer, readOnly bool. Complexity: O(passwd bytes).
pub fn zk_write_connect_response(w: &mut ZkWriter, resp: &ZkConnectResponse) {
  _w_push_be(w, resp.protocol_version, 4);
  _w_push_be(w, resp.timeout, 4);
  _w_push_be(w, resp.session_id, 8);
  let passwd: Vec[UInt8] = resp.passwd;
  zk_write_buffer(w, &passwd);
  zk_write_bool(w, resp.read_only);
}

/// Decode a ConnectResponse. Complexity: O(passwd bytes).
pub fn zk_read_connect_response(r: &mut ZkReader) -> Result[ZkConnectResponse, Str] {
  let pr = _read_i32(r);
  if !pr.is_ok {
    return _err_cresp(pr.error);
  }
  let protocol_version: Int = pr.value;
  let tr = _read_i32(r);
  if !tr.is_ok {
    return _err_cresp(tr.error);
  }
  let timeout: Int = tr.value;
  let sr = _read_raw64(r);
  if !sr.is_ok {
    return _err_cresp(sr.error);
  }
  let session_id: Int = sr.value;
  let br = zk_read_buffer(r);
  if !br.is_ok {
    return _err_cresp(br.error);
  }
  let passwd: Vec[UInt8] = br.value;
  let rr = zk_read_bool(r);
  if !rr.is_ok {
    return _err_cresp(rr.error);
  }
  let read_only: Bool = rr.value;
  return _ok_cresp(ZkConnectResponse{ protocol_version: protocol_version; timeout: timeout; session_id: session_id; passwd: passwd; read_only: read_only; });
}

/// Encode a ConnectResponse to a fresh byte vector. Complexity: O(record
/// bytes).
pub fn zk_encode_connect_response(resp: &ZkConnectResponse) -> Vec[UInt8] {
  var w = zk_writer_new();
  zk_write_connect_response(&mut w, resp);
  return zk_writer_bytes(&w);
}

/// Decode exactly one ConnectResponse and require that no bytes are left
/// over (Err("zookeeper: trailing data at byte N") otherwise).
/// Complexity: O(record bytes).
pub fn zk_decode_connect_response(data: Vec[UInt8]) -> Result[ZkConnectResponse, Str] {
  let total: Int = data.len();
  var r = zk_reader_new(data);
  let br = zk_read_connect_response(&mut r);
  if !br.is_ok {
    return _err_cresp(br.error);
  }
  if r.pos != total {
    return _err_cresp(_msg_at("zookeeper: trailing data", r.pos));
  }
  let resp: ZkConnectResponse = br.value;
  return _ok_cresp(resp);
}

// --------------------------------------------------
//  Stat, Id and ACL records
// --------------------------------------------------

/// A zeroed Stat. Complexity: O(1).
pub fn zk_stat_zero() -> ZkStat {
  return ZkStat{ czxid: 0; mzxid: 0; ctime: 0; mtime: 0; version: 0; cversion: 0; aversion: 0; ephemeral_owner: 0; data_length: 0; num_children: 0; pzxid: 0; };
}

/// Write a Stat: czxid, mzxid, ctime, mtime (long), version, cversion,
/// aversion (int), ephemeralOwner (long), dataLength, numChildren (int),
/// pzxid (long) -- 68 bytes. Complexity: O(1).
pub fn zk_write_stat(w: &mut ZkWriter, s: &ZkStat) {
  _w_push_be(w, s.czxid, 8);
  _w_push_be(w, s.mzxid, 8);
  _w_push_be(w, s.ctime, 8);
  _w_push_be(w, s.mtime, 8);
  _w_push_be(w, s.version, 4);
  _w_push_be(w, s.cversion, 4);
  _w_push_be(w, s.aversion, 4);
  _w_push_be(w, s.ephemeral_owner, 8);
  _w_push_be(w, s.data_length, 4);
  _w_push_be(w, s.num_children, 4);
  _w_push_be(w, s.pzxid, 8);
}

/// Decode a Stat (68 bytes). Complexity: O(1).
pub fn zk_read_stat(r: &mut ZkReader) -> Result[ZkStat, Str] {
  let r1 = _read_raw64(r);
  if !r1.is_ok { return _err_stat(r1.error); }
  let czxid: Int = r1.value;
  let r2 = _read_raw64(r);
  if !r2.is_ok { return _err_stat(r2.error); }
  let mzxid: Int = r2.value;
  let r3 = _read_raw64(r);
  if !r3.is_ok { return _err_stat(r3.error); }
  let ctime: Int = r3.value;
  let r4 = _read_raw64(r);
  if !r4.is_ok { return _err_stat(r4.error); }
  let mtime: Int = r4.value;
  let r5 = _read_i32(r);
  if !r5.is_ok { return _err_stat(r5.error); }
  let version: Int = r5.value;
  let r6 = _read_i32(r);
  if !r6.is_ok { return _err_stat(r6.error); }
  let cversion: Int = r6.value;
  let r7 = _read_i32(r);
  if !r7.is_ok { return _err_stat(r7.error); }
  let aversion: Int = r7.value;
  let r8 = _read_raw64(r);
  if !r8.is_ok { return _err_stat(r8.error); }
  let ephemeral_owner: Int = r8.value;
  let r9 = _read_i32(r);
  if !r9.is_ok { return _err_stat(r9.error); }
  let data_length: Int = r9.value;
  let r10 = _read_i32(r);
  if !r10.is_ok { return _err_stat(r10.error); }
  let num_children: Int = r10.value;
  let r11 = _read_raw64(r);
  if !r11.is_ok { return _err_stat(r11.error); }
  let pzxid: Int = r11.value;
  return _ok_stat(ZkStat{ czxid: czxid; mzxid: mzxid; ctime: ctime; mtime: mtime; version: version; cversion: cversion; aversion: aversion; ephemeral_owner: ephemeral_owner; data_length: data_length; num_children: num_children; pzxid: pzxid; });
}

/// Write an Id: scheme ustring, id ustring. Complexity: O(bytes).
pub fn zk_write_id(w: &mut ZkWriter, x: &ZkId) {
  zk_write_ustring(w, x.scheme);
  zk_write_ustring(w, x.id);
}

/// Decode an Id. Complexity: O(bytes).
pub fn zk_read_id(r: &mut ZkReader) -> Result[ZkId, Str] {
  let sr = zk_read_ustring(r);
  if !sr.is_ok {
    return _err_id(sr.error);
  }
  let scheme: Str = sr.value;
  let ir = zk_read_ustring(r);
  if !ir.is_ok {
    return _err_id(ir.error);
  }
  let id: Str = ir.value;
  return _ok_id(ZkId{ scheme: scheme; id: id; });
}

/// Write an ACL: perms int, then the Id. Complexity: O(bytes).
pub fn zk_write_acl(w: &mut ZkWriter, a: &ZkAcl) {
  _w_push_be(w, a.perms, 4);
  let ident: ZkId = a.id;
  zk_write_id(w, &ident);
}

/// Decode an ACL. Complexity: O(bytes).
pub fn zk_read_acl(r: &mut ZkReader) -> Result[ZkAcl, Str] {
  let pr = _read_i32(r);
  if !pr.is_ok {
    return _err_acl(pr.error);
  }
  let perms: Int = pr.value;
  let ir = zk_read_id(r);
  if !ir.is_ok {
    return _err_acl(ir.error);
  }
  let id: ZkId = ir.value;
  return _ok_acl(ZkAcl{ perms: perms; id: id; });
}

/// A fresh empty ACL vector (three empty parallel columns). Complexity:
/// O(1).
pub fn zk_acl_vec_new() -> ZkAclVec {
  return ZkAclVec{ perms: Vec[Int].new(); schemes: Vec[Str].new(); ids: Vec[Str].new(); };
}

/// Number of ACLs in the vector. Complexity: O(1).
pub fn zk_acl_vec_count(v: &ZkAclVec) -> Int {
  return v.perms.len();
}

/// Append one ACL; the only function that grows the three parallel
/// columns, so they can never drift apart. Complexity: O(1).
pub fn zk_acl_vec_push(v: &mut ZkAclVec, perms: Int, scheme: Str, id: Str) {
  v.perms.push(perms);
  v.schemes.push(scheme);
  v.ids.push(id);
}

/// Perms at index `i`, or 0 when out of range. Complexity: O(1).
pub fn zk_acl_vec_perms(v: &ZkAclVec, i: Int) -> Int {
  if i < 0 || i >= v.perms.len() {
    return 0;
  }
  let x: Int = v.perms[i];
  return x;
}

/// Scheme at index `i`, or "" when out of range. Complexity: O(1).
pub fn zk_acl_vec_scheme(v: &ZkAclVec, i: Int) -> Str {
  if i < 0 || i >= v.schemes.len() {
    return "";
  }
  let x: Str = v.schemes[i];
  return x;
}

/// Id at index `i`, or "" when out of range. Complexity: O(1).
pub fn zk_acl_vec_id(v: &ZkAclVec, i: Int) -> Str {
  if i < 0 || i >= v.ids.len() {
    return "";
  }
  let x: Str = v.ids[i];
  return x;
}

/// Write an ACL vector: int32 count, then perms int + scheme ustring + id
/// ustring per ACL. Complexity: O(bytes).
pub fn zk_write_acl_vector(w: &mut ZkWriter, v: &ZkAclVec) {
  _w_push_be(w, v.perms.len(), 4);
  var i = 0;
  while i < v.perms.len() {
    let p: Int = v.perms[i];
    let s: Str = v.schemes[i];
    let d: Str = v.ids[i];
    _w_push_be(w, p, 4);
    zk_write_ustring(w, s);
    zk_write_ustring(w, d);
    i = i + 1;
  }
}

/// Decode an ACL vector. A null vector (-1) decodes as empty; the count
/// is bounded by bytes remaining / 12 (12 is the minimum ACL size)
/// before any element is read. Complexity: O(bytes).
pub fn zk_read_acl_vector(r: &mut ZkReader) -> Result[ZkAclVec, Str] {
  let start: Int = r.pos;
  let cr = zk_read_vector_count(r);
  if !cr.is_ok {
    return _err_aclvec(cr.error);
  }
  let count: Int = cr.value;
  if count == -1 {
    return _ok_aclvec(zk_acl_vec_new());
  }
  let g = _vector_guard(r, count, 12, start);
  if g.len() > 0 {
    return _err_aclvec(g);
  }
  var v = zk_acl_vec_new();
  var i = 0;
  while i < count {
    let pr = _read_i32(r);
    if !pr.is_ok {
      return _err_aclvec(pr.error);
    }
    let p: Int = pr.value;
    let sr = zk_read_ustring(r);
    if !sr.is_ok {
      return _err_aclvec(sr.error);
    }
    let s: Str = sr.value;
    let ir = zk_read_ustring(r);
    if !ir.is_ok {
      return _err_aclvec(ir.error);
    }
    let d: Str = ir.value;
    zk_acl_vec_push(&mut v, p, s, d);
    i = i + 1;
  }
  return _ok_aclvec(v);
}

// --------------------------------------------------
//  Watch events
// --------------------------------------------------

/// Build a watch event with a non-null path. Complexity: O(1).
pub fn zk_watch_event_make(event_type: Int, state: Int, path: Str) -> ZkWatchEvent {
  return ZkWatchEvent{ event_type: event_type; state: state; path: path; path_is_null: false; };
}

/// Write a watch event: type int, state int, path ustring (or the jute
/// null length when `path_is_null`). Complexity: O(path bytes).
pub fn zk_write_watch_event(w: &mut ZkWriter, e: &ZkWatchEvent) {
  _w_push_be(w, e.event_type, 4);
  _w_push_be(w, e.state, 4);
  if e.path_is_null {
    _w_push_null(w);
  } else {
    zk_write_ustring(w, e.path);
  }
}

/// Decode a watch event. A path length of -1 sets `path_is_null` and
/// leaves `path` empty. Complexity: O(path bytes).
pub fn zk_read_watch_event(r: &mut ZkReader) -> Result[ZkWatchEvent, Str] {
  let tr = _read_i32(r);
  if !tr.is_ok {
    return _err_event(tr.error);
  }
  let t: Int = tr.value;
  let sr = _read_i32(r);
  if !sr.is_ok {
    return _err_event(sr.error);
  }
  let st: Int = sr.value;
  let start: Int = r.pos;
  let lr = _read_i32(r);
  if !lr.is_ok {
    return _err_event(lr.error);
  }
  let n: Int = lr.value;
  if n == -1 {
    return _ok_event(ZkWatchEvent{ event_type: t; state: st; path: ""; path_is_null: true; });
  }
  if n < 0 {
    return _err_event(_msg_at("zookeeper: invalid string length " + convert.int_to_string(n), start));
  }
  let poff: Int = r.pos;
  let br = _read_bytes_n(r, n);
  if !br.is_ok {
    return _err_event(br.error);
  }
  let bytes: Vec[UInt8] = br.value;
  let ue = _utf8_error(&bytes, poff);
  if ue.len() > 0 {
    return _err_event(ue);
  }
  let p: Str = _bytes_to_str(&bytes);
  return _ok_event(ZkWatchEvent{ event_type: t; state: st; path: p; path_is_null: false; });
}

// --------------------------------------------------
//  Request records
// --------------------------------------------------

/// Write a CreateRequest: path ustring, data buffer, acl vector, flags
/// int. Complexity: O(bytes).
pub fn zk_write_create_request(w: &mut ZkWriter, b: &ZkCreateRequest) {
  zk_write_ustring(w, b.path);
  let data: Vec[UInt8] = b.data;
  zk_write_buffer(w, &data);
  let acls: ZkAclVec = b.acls;
  zk_write_acl_vector(w, &acls);
  _w_push_be(w, b.flags, 4);
}

/// Decode a CreateRequest. Complexity: O(bytes).
pub fn zk_read_create_request(r: &mut ZkReader) -> Result[ZkCreateRequest, Str] {
  let pr = zk_read_ustring(r);
  if !pr.is_ok {
    return _err_crq(pr.error);
  }
  let path: Str = pr.value;
  let dr = zk_read_buffer(r);
  if !dr.is_ok {
    return _err_crq(dr.error);
  }
  let data: Vec[UInt8] = dr.value;
  let ar = zk_read_acl_vector(r);
  if !ar.is_ok {
    return _err_crq(ar.error);
  }
  let acls: ZkAclVec = ar.value;
  let fr = _read_i32(r);
  if !fr.is_ok {
    return _err_crq(fr.error);
  }
  let flags: Int = fr.value;
  return _ok_crq(ZkCreateRequest{ path: path; data: data; acls: acls; flags: flags; });
}

/// Write a CREATE/CREATE2 response body: a single path ustring.
/// Complexity: O(path bytes).
pub fn zk_write_create_response(w: &mut ZkWriter, path: Str) {
  zk_write_ustring(w, path);
}

/// Decode a CREATE/CREATE2 response body: a single path ustring. The
/// same shape is the SYNC request and response body. Complexity: O(path
/// bytes).
pub fn zk_read_create_response(r: &mut ZkReader) -> Result[Str, Str] {
  return zk_read_ustring(r);
}

/// Write a SYNC request body: a single path ustring. Complexity: O(path
/// bytes).
pub fn zk_write_sync_request(w: &mut ZkWriter, path: Str) {
  zk_write_ustring(w, path);
}

/// Decode a SYNC request body: a single path ustring. Complexity:
/// O(path bytes).
pub fn zk_read_sync_request(r: &mut ZkReader) -> Result[Str, Str] {
  return zk_read_ustring(r);
}

/// Write a SYNC response body: a single path ustring. Complexity:
/// O(path bytes).
pub fn zk_write_sync_response(w: &mut ZkWriter, path: Str) {
  zk_write_ustring(w, path);
}

/// Decode a SYNC response body: a single path ustring. Complexity:
/// O(path bytes).
pub fn zk_read_sync_response(r: &mut ZkReader) -> Result[Str, Str] {
  return zk_read_ustring(r);
}

/// Write the shared `path ustring, watch bool` request body used by
/// EXISTS, GET_DATA, GET_CHILDREN, GET_CHILDREN2 and GET_ACL.
/// Complexity: O(path bytes).
pub fn zk_write_path_watch_request(w: &mut ZkWriter, b: &ZkPathWatchRequest) {
  zk_write_ustring(w, b.path);
  zk_write_bool(w, b.watch);
}

/// Decode the shared `path ustring, watch bool` request body (EXISTS,
/// GET_DATA, GET_CHILDREN, GET_CHILDREN2, GET_ACL). Complexity: O(path
/// bytes).
pub fn zk_read_path_watch_request(r: &mut ZkReader) -> Result[ZkPathWatchRequest, Str] {
  let pr = zk_read_ustring(r);
  if !pr.is_ok {
    return _err_pwr(pr.error);
  }
  let path: Str = pr.value;
  let wr = zk_read_bool(r);
  if !wr.is_ok {
    return _err_pwr(wr.error);
  }
  let watch: Bool = wr.value;
  return _ok_pwr(ZkPathWatchRequest{ path: path; watch: watch; });
}

/// Write a SetDataRequest: path ustring, data buffer, version int.
/// Complexity: O(bytes).
pub fn zk_write_set_data_request(w: &mut ZkWriter, b: &ZkSetDataRequest) {
  zk_write_ustring(w, b.path);
  let data: Vec[UInt8] = b.data;
  zk_write_buffer(w, &data);
  _w_push_be(w, b.version, 4);
}

/// Decode a SetDataRequest. Complexity: O(bytes).
pub fn zk_read_set_data_request(r: &mut ZkReader) -> Result[ZkSetDataRequest, Str] {
  let pr = zk_read_ustring(r);
  if !pr.is_ok {
    return _err_sdr(pr.error);
  }
  let path: Str = pr.value;
  let dr = zk_read_buffer(r);
  if !dr.is_ok {
    return _err_sdr(dr.error);
  }
  let data: Vec[UInt8] = dr.value;
  let vr = _read_i32(r);
  if !vr.is_ok {
    return _err_sdr(vr.error);
  }
  let version: Int = vr.value;
  return _ok_sdr(ZkSetDataRequest{ path: path; data: data; version: version; });
}

/// Write the shared `path ustring, version int` request body used by
/// DELETE and CHECK. Complexity: O(path bytes).
pub fn zk_write_path_version_request(w: &mut ZkWriter, b: &ZkPathVersionRequest) {
  zk_write_ustring(w, b.path);
  _w_push_be(w, b.version, 4);
}

/// Decode the shared `path ustring, version int` request body (DELETE,
/// CHECK). Complexity: O(path bytes).
pub fn zk_read_path_version_request(r: &mut ZkReader) -> Result[ZkPathVersionRequest, Str] {
  let pr = zk_read_ustring(r);
  if !pr.is_ok {
    return _err_pvr(pr.error);
  }
  let path: Str = pr.value;
  let vr = _read_i32(r);
  if !vr.is_ok {
    return _err_pvr(vr.error);
  }
  let version: Int = vr.value;
  return _ok_pvr(ZkPathVersionRequest{ path: path; version: version; });
}

/// Write a SetACLRequest: path ustring, acl vector, version int.
/// Complexity: O(bytes).
pub fn zk_write_set_acl_request(w: &mut ZkWriter, b: &ZkSetAclRequest) {
  zk_write_ustring(w, b.path);
  let acls: ZkAclVec = b.acls;
  zk_write_acl_vector(w, &acls);
  _w_push_be(w, b.version, 4);
}

/// Decode a SetACLRequest. Complexity: O(bytes).
pub fn zk_read_set_acl_request(r: &mut ZkReader) -> Result[ZkSetAclRequest, Str] {
  let pr = zk_read_ustring(r);
  if !pr.is_ok {
    return _err_sar(pr.error);
  }
  let path: Str = pr.value;
  let ar = zk_read_acl_vector(r);
  if !ar.is_ok {
    return _err_sar(ar.error);
  }
  let acls: ZkAclVec = ar.value;
  let vr = _read_i32(r);
  if !vr.is_ok {
    return _err_sar(vr.error);
  }
  let version: Int = vr.value;
  return _ok_sar(ZkSetAclRequest{ path: path; acls: acls; version: version; });
}

/// Write an AuthPacket: type int, scheme ustring, auth buffer.
/// Complexity: O(bytes).
pub fn zk_write_auth_request(w: &mut ZkWriter, b: &ZkAuthRequest) {
  _w_push_be(w, b.auth_type, 4);
  zk_write_ustring(w, b.scheme);
  let data: Vec[UInt8] = b.auth_data;
  zk_write_buffer(w, &data);
}

/// Decode an AuthPacket. Complexity: O(bytes).
pub fn zk_read_auth_request(r: &mut ZkReader) -> Result[ZkAuthRequest, Str] {
  let tr = _read_i32(r);
  if !tr.is_ok {
    return _err_arq(tr.error);
  }
  let auth_type: Int = tr.value;
  let sr = zk_read_ustring(r);
  if !sr.is_ok {
    return _err_arq(sr.error);
  }
  let scheme: Str = sr.value;
  let br = zk_read_buffer(r);
  if !br.is_ok {
    return _err_arq(br.error);
  }
  let auth_data: Vec[UInt8] = br.value;
  return _ok_arq(ZkAuthRequest{ auth_type: auth_type; scheme: scheme; auth_data: auth_data; });
}

// --------------------------------------------------
//  Response records
// --------------------------------------------------

/// Write a GetChildren/GetChildren2 response: children vector<ustring>,
/// then a Stat. Complexity: O(bytes).
pub fn zk_write_get_children_response(w: &mut ZkWriter, resp: &ZkGetChildrenResponse) {
  let kids: Vec[Str] = resp.children;
  zk_write_ustring_vector(w, &kids);
  let st: ZkStat = resp.stat;
  zk_write_stat(w, &st);
}

/// Decode a GetChildren/GetChildren2 response. Complexity: O(bytes).
pub fn zk_read_get_children_response(r: &mut ZkReader) -> Result[ZkGetChildrenResponse, Str] {
  let cr = zk_read_ustring_vector(r);
  if !cr.is_ok {
    return _err_gcr(cr.error);
  }
  let children: Vec[Str] = cr.value;
  let sr = zk_read_stat(r);
  if !sr.is_ok {
    return _err_gcr(sr.error);
  }
  let stat: ZkStat = sr.value;
  return _ok_gcr(ZkGetChildrenResponse{ children: children; stat: stat; });
}

/// Write a GetData response: data buffer, then a Stat. Complexity:
/// O(bytes).
pub fn zk_write_get_data_response(w: &mut ZkWriter, resp: &ZkGetDataResponse) {
  let data: Vec[UInt8] = resp.data;
  zk_write_buffer(w, &data);
  let st: ZkStat = resp.stat;
  zk_write_stat(w, &st);
}

/// Decode a GetData response. Complexity: O(bytes).
pub fn zk_read_get_data_response(r: &mut ZkReader) -> Result[ZkGetDataResponse, Str] {
  let dr = zk_read_buffer(r);
  if !dr.is_ok {
    return _err_gdr(dr.error);
  }
  let data: Vec[UInt8] = dr.value;
  let sr = zk_read_stat(r);
  if !sr.is_ok {
    return _err_gdr(sr.error);
  }
  let stat: ZkStat = sr.value;
  return _ok_gdr(ZkGetDataResponse{ data: data; stat: stat; });
}

/// Write a GetACL response: acl vector, then a Stat. Complexity:
/// O(bytes).
pub fn zk_write_get_acl_response(w: &mut ZkWriter, resp: &ZkGetAclResponse) {
  let acls: ZkAclVec = resp.acls;
  zk_write_acl_vector(w, &acls);
  let st: ZkStat = resp.stat;
  zk_write_stat(w, &st);
}

/// Decode a GetACL response. Complexity: O(bytes).
pub fn zk_read_get_acl_response(r: &mut ZkReader) -> Result[ZkGetAclResponse, Str] {
  let ar = zk_read_acl_vector(r);
  if !ar.is_ok {
    return _err_gar(ar.error);
  }
  let acls: ZkAclVec = ar.value;
  let sr = zk_read_stat(r);
  if !sr.is_ok {
    return _err_gar(sr.error);
  }
  let stat: ZkStat = sr.value;
  return _ok_gar(ZkGetAclResponse{ acls: acls; stat: stat; });
}

// --------------------------------------------------
//  Parse one message
// --------------------------------------------------

// The zero-value message skeleton for `xid`, `op` and `kind`.
fn _msg_base(xid: Int, op: Int, kind: Int) -> ZkMessage {
  return ZkMessage{ xid: xid; op: op; body_kind: kind; consumed: 0; path: ""; path_is_null: false; version: 0; watch: false; flags: 0; data: Vec[UInt8].new(); acls: zk_acl_vec_new(); event_type: 0; state: 0; auth_type: 0; auth_scheme: ""; auth_data: Vec[UInt8].new(); };
}

// Body parsers. Each consumes the body at the cursor and returns the
// message with `consumed` set to the total bytes read so far.
fn _parse_empty(r: &mut ZkReader, xid: Int, op: Int, kind: Int) -> Result[ZkMessage, Str] {
  var m = _msg_base(xid, op, kind);
  m.consumed = r.pos;
  return _ok_msg(m);
}

fn _parse_path_only(r: &mut ZkReader, xid: Int, op: Int, kind: Int) -> Result[ZkMessage, Str] {
  let pr = zk_read_ustring(r);
  if !pr.is_ok {
    return _err_msg(pr.error);
  }
  let path: Str = pr.value;
  var m = _msg_base(xid, op, kind);
  m.path = path;
  m.consumed = r.pos;
  return _ok_msg(m);
}

fn _parse_create(r: &mut ZkReader, xid: Int, op: Int, kind: Int) -> Result[ZkMessage, Str] {
  let br = zk_read_create_request(r);
  if !br.is_ok {
    return _err_msg(br.error);
  }
  let b: ZkCreateRequest = br.value;
  var m = _msg_base(xid, op, kind);
  m.path = b.path;
  m.data = b.data;
  m.acls = b.acls;
  m.flags = b.flags;
  m.consumed = r.pos;
  return _ok_msg(m);
}

fn _parse_path_version(r: &mut ZkReader, xid: Int, op: Int, kind: Int) -> Result[ZkMessage, Str] {
  let br = zk_read_path_version_request(r);
  if !br.is_ok {
    return _err_msg(br.error);
  }
  let b: ZkPathVersionRequest = br.value;
  var m = _msg_base(xid, op, kind);
  m.path = b.path;
  m.version = b.version;
  m.consumed = r.pos;
  return _ok_msg(m);
}

fn _parse_path_watch(r: &mut ZkReader, xid: Int, op: Int, kind: Int) -> Result[ZkMessage, Str] {
  let br = zk_read_path_watch_request(r);
  if !br.is_ok {
    return _err_msg(br.error);
  }
  let b: ZkPathWatchRequest = br.value;
  var m = _msg_base(xid, op, kind);
  m.path = b.path;
  m.watch = b.watch;
  m.consumed = r.pos;
  return _ok_msg(m);
}

fn _parse_set_data(r: &mut ZkReader, xid: Int, op: Int, kind: Int) -> Result[ZkMessage, Str] {
  let br = zk_read_set_data_request(r);
  if !br.is_ok {
    return _err_msg(br.error);
  }
  let b: ZkSetDataRequest = br.value;
  var m = _msg_base(xid, op, kind);
  m.path = b.path;
  m.data = b.data;
  m.version = b.version;
  m.consumed = r.pos;
  return _ok_msg(m);
}

fn _parse_set_acl(r: &mut ZkReader, xid: Int, op: Int, kind: Int) -> Result[ZkMessage, Str] {
  let br = zk_read_set_acl_request(r);
  if !br.is_ok {
    return _err_msg(br.error);
  }
  let b: ZkSetAclRequest = br.value;
  var m = _msg_base(xid, op, kind);
  m.path = b.path;
  m.acls = b.acls;
  m.version = b.version;
  m.consumed = r.pos;
  return _ok_msg(m);
}

fn _parse_auth(r: &mut ZkReader, xid: Int, op: Int, kind: Int) -> Result[ZkMessage, Str] {
  let br = zk_read_auth_request(r);
  if !br.is_ok {
    return _err_msg(br.error);
  }
  let b: ZkAuthRequest = br.value;
  var m = _msg_base(xid, op, kind);
  m.auth_type = b.auth_type;
  m.auth_scheme = b.scheme;
  m.auth_data = b.auth_data;
  m.consumed = r.pos;
  return _ok_msg(m);
}

fn _parse_notification(r: &mut ZkReader, xid: Int, op: Int, kind: Int) -> Result[ZkMessage, Str] {
  let br = zk_read_watch_event(r);
  if !br.is_ok {
    return _err_msg(br.error);
  }
  let e: ZkWatchEvent = br.value;
  var m = _msg_base(xid, op, kind);
  m.event_type = e.event_type;
  m.state = e.state;
  m.path = e.path;
  m.path_is_null = e.path_is_null;
  m.consumed = r.pos;
  return _ok_msg(m);
}

/// Parse exactly one request message from the front of `data`: the
/// 8-byte request header (xid int + opcode int) followed by the body
/// selected by the opcode. `consumed` reports the total byte count of
/// header + body, so a stream framer can advance its own cursor by it.
///
/// Bodies: CREATE/CREATE2 (path, data, acl vector, flags), DELETE
/// (path, version), EXISTS/GET_DATA/GET_ACL/GET_CHILDREN/GET_CHILDREN2
/// (path, watch), SET_DATA (path, data, version), SET_ACL (path, acl
/// vector, version), SYNC (path), CHECK (path, version), AUTH (type,
/// scheme, data), NOTIFICATION (type, state, path), and PING/CLOSE/
/// SET_WATCHES (no body). MULTI and any unknown opcode are
/// Err("zookeeper: unsupported opcode N at byte 4"). Complexity:
/// O(message bytes).
pub fn zk_parse_one(data: Vec[UInt8]) -> Result[ZkMessage, Str] {
  var r = zk_reader_new(data);
  let hr = zk_read_request_header(&mut r);
  if !hr.is_ok {
    return _err_msg(hr.error);
  }
  let h: ZkRequestHeader = hr.value;
  let xid: Int = h.xid;
  let op: Int = h.op;
  if op == _OP_CREATE || op == _OP_CREATE2 {
    return _parse_create(&mut r, xid, op, _BODY_CREATE);
  }
  if op == _OP_DELETE {
    return _parse_path_version(&mut r, xid, op, _BODY_DELETE);
  }
  if op == _OP_EXISTS {
    return _parse_path_watch(&mut r, xid, op, _BODY_EXISTS);
  }
  if op == _OP_GET_DATA {
    return _parse_path_watch(&mut r, xid, op, _BODY_GET_DATA);
  }
  if op == _OP_SET_DATA {
    return _parse_set_data(&mut r, xid, op, _BODY_SET_DATA);
  }
  if op == _OP_GET_ACL {
    return _parse_path_watch(&mut r, xid, op, _BODY_GET_ACL);
  }
  if op == _OP_SET_ACL {
    return _parse_set_acl(&mut r, xid, op, _BODY_SET_ACL);
  }
  if op == _OP_GET_CHILDREN || op == _OP_GET_CHILDREN2 {
    return _parse_path_watch(&mut r, xid, op, _BODY_GET_CHILDREN);
  }
  if op == _OP_SYNC {
    return _parse_path_only(&mut r, xid, op, _BODY_SYNC);
  }
  if op == _OP_CHECK {
    return _parse_path_version(&mut r, xid, op, _BODY_CHECK);
  }
  if op == _OP_NOTIFICATION {
    return _parse_notification(&mut r, xid, op, _BODY_NOTIFICATION);
  }
  if op == _OP_PING || op == _OP_CLOSE || op == _OP_SET_WATCHES {
    return _parse_empty(&mut r, xid, op, _BODY_EMPTY);
  }
  if op == _OP_AUTH {
    return _parse_auth(&mut r, xid, op, _BODY_AUTH);
  }
  return _err_msg(_msg_at("zookeeper: unsupported opcode " + convert.int_to_string(op), 4));
}

/// `zk_parse_one` plus a check that no bytes are left over
/// (Err("zookeeper: trailing data at byte N") otherwise). Complexity:
/// O(message bytes).
pub fn zk_parse_one_exact(data: Vec[UInt8]) -> Result[ZkMessage, Str] {
  let total: Int = data.len();
  let mr = zk_parse_one(data);
  if !mr.is_ok {
    return _err_msg(mr.error);
  }
  let m: ZkMessage = mr.value;
  if m.consumed != total {
    return _err_msg(_msg_at("zookeeper: trailing data", m.consumed));
  }
  return _ok_msg(m);
}

// The zero-value reply skeleton for a reply header and body kind.
fn _reply_base(xid: Int, zxid: Int, err: Int, is_error: Bool, kind: Int) -> ZkReply {
  return ZkReply{ xid: xid; zxid: zxid; err: err; is_error: is_error; body_kind: kind; consumed: 0; path: ""; data: Vec[UInt8].new(); stat: zk_stat_zero(); children: Vec[Str].new(); acls: zk_acl_vec_new(); };
}

fn _reply_empty(r: &mut ZkReader, h: &ZkReplyHeader, kind: Int) -> Result[ZkReply, Str] {
  var m = _reply_base(h.xid, h.zxid, h.err, false, kind);
  m.consumed = r.pos;
  return _ok_reply(m);
}

fn _reply_path(r: &mut ZkReader, h: &ZkReplyHeader, kind: Int) -> Result[ZkReply, Str] {
  let pr = zk_read_ustring(r);
  if !pr.is_ok {
    return _err_reply(pr.error);
  }
  let path: Str = pr.value;
  var m = _reply_base(h.xid, h.zxid, h.err, false, kind);
  m.path = path;
  m.consumed = r.pos;
  return _ok_reply(m);
}

fn _reply_stat(r: &mut ZkReader, h: &ZkReplyHeader, kind: Int) -> Result[ZkReply, Str] {
  let sr = zk_read_stat(r);
  if !sr.is_ok {
    return _err_reply(sr.error);
  }
  let st: ZkStat = sr.value;
  var m = _reply_base(h.xid, h.zxid, h.err, false, kind);
  m.stat = st;
  m.consumed = r.pos;
  return _ok_reply(m);
}

fn _reply_data_stat(r: &mut ZkReader, h: &ZkReplyHeader, kind: Int) -> Result[ZkReply, Str] {
  let dr = zk_read_buffer(r);
  if !dr.is_ok {
    return _err_reply(dr.error);
  }
  let data: Vec[UInt8] = dr.value;
  let sr = zk_read_stat(r);
  if !sr.is_ok {
    return _err_reply(sr.error);
  }
  let st: ZkStat = sr.value;
  var m = _reply_base(h.xid, h.zxid, h.err, false, kind);
  m.data = data;
  m.stat = st;
  m.consumed = r.pos;
  return _ok_reply(m);
}

fn _reply_children_stat(r: &mut ZkReader, h: &ZkReplyHeader, kind: Int) -> Result[ZkReply, Str] {
  let cr = zk_read_ustring_vector(r);
  if !cr.is_ok {
    return _err_reply(cr.error);
  }
  let kids: Vec[Str] = cr.value;
  let sr = zk_read_stat(r);
  if !sr.is_ok {
    return _err_reply(sr.error);
  }
  let st: ZkStat = sr.value;
  var m = _reply_base(h.xid, h.zxid, h.err, false, kind);
  m.children = kids;
  m.stat = st;
  m.consumed = r.pos;
  return _ok_reply(m);
}

fn _reply_acl_stat(r: &mut ZkReader, h: &ZkReplyHeader, kind: Int) -> Result[ZkReply, Str] {
  let ar = zk_read_acl_vector(r);
  if !ar.is_ok {
    return _err_reply(ar.error);
  }
  let acls: ZkAclVec = ar.value;
  let sr = zk_read_stat(r);
  if !sr.is_ok {
    return _err_reply(sr.error);
  }
  let st: ZkStat = sr.value;
  var m = _reply_base(h.xid, h.zxid, h.err, false, kind);
  m.acls = acls;
  m.stat = st;
  m.consumed = r.pos;
  return _ok_reply(m);
}

/// Parse exactly one reply message from the front of `data`: the 16-byte
/// reply header (xid int, zxid long, err int) followed by the body
/// selected by the *request's* opcode (the wire carries no opcode in a
/// reply). A non-zero `err` means the server sent no body, so `is_error`
/// is set and `consumed` is 16 (or more when a server appends bytes;
/// they are simply not consumed). `consumed` reports header + body.
///
/// Bodies: EXISTS/SET_DATA/SET_ACL -> Stat; GET_DATA -> buffer + Stat;
/// GET_CHILDREN/GET_CHILDREN2 -> children vector + Stat; GET_ACL -> acl
/// vector + Stat; CREATE/CREATE2/SYNC -> path ustring; everything else
/// (PING, CLOSE, CHECK, DELETE, AUTH, unknown) -> no body.
/// Complexity: O(message bytes).
pub fn zk_parse_reply(data: Vec[UInt8], op: Int) -> Result[ZkReply, Str] {
  var r = zk_reader_new(data);
  let hr = zk_read_reply_header(&mut r);
  if !hr.is_ok {
    return _err_reply(hr.error);
  }
  let h: ZkReplyHeader = hr.value;
  if h.err != 0 {
    var me = _reply_base(h.xid, h.zxid, h.err, true, _BODY_EMPTY);
    me.consumed = r.pos;
    return _ok_reply(me);
  }
  if op == _OP_EXISTS || op == _OP_SET_DATA || op == _OP_SET_ACL {
    return _reply_stat(&mut r, &h, _BODY_STAT);
  }
  if op == _OP_GET_DATA {
    return _reply_data_stat(&mut r, &h, _BODY_GET_DATA);
  }
  if op == _OP_GET_CHILDREN || op == _OP_GET_CHILDREN2 {
    return _reply_children_stat(&mut r, &h, _BODY_GET_CHILDREN);
  }
  if op == _OP_GET_ACL {
    return _reply_acl_stat(&mut r, &h, _BODY_GET_ACL);
  }
  if op == _OP_CREATE || op == _OP_CREATE2 || op == _OP_SYNC {
    return _reply_path(&mut r, &h, _BODY_PATH);
  }
  return _reply_empty(&mut r, &h, _BODY_EMPTY);
}

/// `zk_parse_reply` plus a check that no bytes are left over
/// (Err("zookeeper: trailing data at byte N") otherwise). Complexity:
/// O(message bytes).
pub fn zk_parse_reply_exact(data: Vec[UInt8], op: Int) -> Result[ZkReply, Str] {
  let total: Int = data.len();
  let mr = zk_parse_reply(data, op);
  if !mr.is_ok {
    return _err_reply(mr.error);
  }
  let m: ZkReply = mr.value;
  if m.consumed != total {
    return _err_reply(_msg_at("zookeeper: trailing data", m.consumed));
  }
  return _ok_reply(m);
}
