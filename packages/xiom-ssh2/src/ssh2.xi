// XIOM -- xiom.ssh2: SSH-2 message structure codec (no crypto)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM structural encoder/parser for the SSH-2 wire format as defined by
// RFC 4251 (data type representations), RFC 4253 (transport layer: binary
// packet protocol, algorithm negotiation, key exchange envelopes, service
// request), RFC 4252 (user authentication messages) and RFC 4254 (connection
// protocol: channels, channel requests, data flow control).
//
// Scope boundary -- this module performs NO cryptography and NO session state:
//   * binary packets are decoded structurally; the trailing MAC is NOT parsed
//     or verified (ssh2_parse_packet leaves mac_off = end and the caller, who
//     knows the negotiated MAC algorithm, consumes it);
//   * KEXDH / ECDH bodies are carried RAW. mpints are never converted into
//     big numbers; ssh2_mpint_is_negative is the only sign inspection offered;
//   * padding bytes are not generated randomly here: ssh2_write_packet writes
//     zero padding, ssh2_write_packet_aligned picks a legal pad count. A real
//     transport must replace the padding with random bytes before sending.
//
// Packet layout (RFC 4253 section 6), byte offsets relative to the packet
// start `off`:
//
//   [off+0 .. off+4)   uint32  packet_length = 1 + payload_len + padding_len
//   [off+4]            byte    padding_length (MUST be >= 4)
//   [off+5 .. +n)      bytes   payload (payload_len bytes)
//   [.. .. +pad)       bytes   random padding (padding_len bytes)
//   [end .. end+maclen) bytes  MAC (not parsed here)
//
//   total consumed by the packet = 4 + packet_length (MAC excluded)
//   the length block (4 + packet_length) is a multiple of 8 for unencrypted
//   transport and of the cipher block size (8 or 16, i.e. AES) once encryption
//   is active; ssh2_packet_padding_for computes a pad count that satisfies
//   either alignment, and ssh2_packet_is_aligned checks it.
//
// Every structural error is Err(Str) shaped "ssh2: <reason> at <offset>",
// where <offset> is the absolute byte offset in the buffer passed in.
//
// v0.61.3 notes that shaped this module (mirrors xiom.tls / xiom.nats):
//   * free functions only; no methods, no lambdas, no Vec[StructType], no
//     Vec[fn] dispatch, no generics, no match in the library (if chains only);
//   * every public type is FLAT: Int/Bool/Vec[Int]/Vec[UInt8] fields only;
//   * Ok/Err construction is confined to the tiny leaf helpers below
//     (constructing Results inside larger functions miscompiles);
//   * every byte read from a Vec[UInt8] widens with `(x as Int) & 0xFF`;
//   * a struct's Vec field is bound to a typed local before it is passed as a
//     `&Vec[UInt8]` parameter (`&struct.field` is not trusted);
//   * `&mut Int` out-params are avoided (miscompiled): parsing functions
//     return (value, offset) pairs or flat structs instead;
//   * 32-bit big-endian fields are composed with explicit multiplication
//     (never shifts); division truncates.

module xiom.ssh2

use xiom.convert.int;
use xiom.string;
use xiom.string.compare;

// --------------------------------------------------
//  Message numbers (RFC 4253 / 4252 / 4254)
// --------------------------------------------------

/// Message number 1: SSH_MSG_DISCONNECT (RFC 4253 section 11.1).
pub const SSH_MSG_DISCONNECT: Int = 1;
/// Message number 2: SSH_MSG_IGNORE.
pub const SSH_MSG_IGNORE: Int = 2;
/// Message number 3: SSH_MSG_UNIMPLEMENTED.
pub const SSH_MSG_UNIMPLEMENTED: Int = 3;
/// Message number 4: SSH_MSG_DEBUG.
pub const SSH_MSG_DEBUG: Int = 4;
/// Message number 5: SSH_MSG_SERVICE_REQUEST (RFC 4253 section 10).
pub const SSH_MSG_SERVICE_REQUEST: Int = 5;
/// Message number 6: SSH_MSG_SERVICE_ACCEPT.
pub const SSH_MSG_SERVICE_ACCEPT: Int = 6;
/// Message number 20: SSH_MSG_KEXINIT (RFC 4253 section 7.1).
pub const SSH_MSG_KEXINIT: Int = 20;
/// Message number 21: SSH_MSG_NEWKEYS.
pub const SSH_MSG_NEWKEYS: Int = 21;
/// Message number 30: SSH_MSG_KEXDH_INIT (RFC 4253 section 8) and, under an
/// ECDH method, SSH_MSG_KEX_ECDH_INIT (RFC 5656 section 4.1); the meaning
/// depends on the negotiated key exchange algorithm, so both parsers accept
/// number 30 and apply their own body shape.
pub const SSH_MSG_KEXDH_INIT: Int = 30;
/// Message number 30 seen as SSH_MSG_KEX_ECDH_INIT.
pub const SSH_MSG_KEX_ECDH_INIT: Int = 30;
/// Message number 31: SSH_MSG_KEXDH_REPLY / SSH_MSG_KEX_ECDH_REPLY.
pub const SSH_MSG_KEXDH_REPLY: Int = 31;
/// Message number 31 seen as SSH_MSG_KEX_ECDH_REPLY.
pub const SSH_MSG_KEX_ECDH_REPLY: Int = 31;
/// Message number 50: SSH_MSG_USERAUTH_REQUEST (RFC 4252 section 5).
pub const SSH_MSG_USERAUTH_REQUEST: Int = 50;
/// Message number 51: SSH_MSG_USERAUTH_FAILURE.
pub const SSH_MSG_USERAUTH_FAILURE: Int = 51;
/// Message number 52: SSH_MSG_USERAUTH_SUCCESS.
pub const SSH_MSG_USERAUTH_SUCCESS: Int = 52;
/// Message number 53: SSH_MSG_USERAUTH_BANNER.
pub const SSH_MSG_USERAUTH_BANNER: Int = 53;
/// Message number 80: SSH_MSG_GLOBAL_REQUEST (RFC 4254 section 4).
pub const SSH_MSG_GLOBAL_REQUEST: Int = 80;
/// Message number 81: SSH_MSG_REQUEST_SUCCESS.
pub const SSH_MSG_REQUEST_SUCCESS: Int = 81;
/// Message number 82: SSH_MSG_REQUEST_FAILURE.
pub const SSH_MSG_REQUEST_FAILURE: Int = 82;
/// Message number 90: SSH_MSG_CHANNEL_OPEN (RFC 4254 section 5.1).
pub const SSH_MSG_CHANNEL_OPEN: Int = 90;
/// Message number 91: SSH_MSG_CHANNEL_OPEN_CONFIRMATION (section 5.1).
pub const SSH_MSG_CHANNEL_OPEN_CONFIRMATION: Int = 91;
/// Message number 92: SSH_MSG_CHANNEL_OPEN_FAILURE (section 5.1).
pub const SSH_MSG_CHANNEL_OPEN_FAILURE: Int = 92;
/// Message number 93: SSH_MSG_CHANNEL_WINDOW_ADJUST (section 5.2).
pub const SSH_MSG_CHANNEL_WINDOW_ADJUST: Int = 93;
/// Message number 94: SSH_MSG_CHANNEL_DATA (section 5.2).
pub const SSH_MSG_CHANNEL_DATA: Int = 94;
/// Message number 95: SSH_MSG_CHANNEL_EXTENDED_DATA (section 5.2).
pub const SSH_MSG_CHANNEL_EXTENDED_DATA: Int = 95;
/// Message number 96: SSH_MSG_CHANNEL_EOF.
pub const SSH_MSG_CHANNEL_EOF: Int = 96;
/// Message number 97: SSH_MSG_CHANNEL_CLOSE.
pub const SSH_MSG_CHANNEL_CLOSE: Int = 97;
/// Message number 98: SSH_MSG_CHANNEL_REQUEST (section 6.5).
pub const SSH_MSG_CHANNEL_REQUEST: Int = 98;
/// Message number 99: SSH_MSG_CHANNEL_SUCCESS.
pub const SSH_MSG_CHANNEL_SUCCESS: Int = 99;
/// Message number 100: SSH_MSG_CHANNEL_FAILURE.
pub const SSH_MSG_CHANNEL_FAILURE: Int = 100;

// --------------------------------------------------
//  Binary packet limits (RFC 4253 section 6)
// --------------------------------------------------

/// Bytes of the binary packet header: packet_length(4) + padding_length(1).
pub const SSH2_PACKET_HEADER_LEN: Int = 5;
/// Smallest legal padding_length (RFC 4253: at least 4 bytes of padding).
pub const SSH2_MIN_PADDING: Int = 4;
/// Largest representable padding_length (one byte).
pub const SSH2_MAX_PADDING: Int = 255;
/// Largest accepted packet_length. RFC 4253 section 6.1 requires support for
/// an uncompressed payload of 32768 bytes and a total packet size of 35000
/// bytes; this codec accepts packet_length up to 35000 and rejects longer
/// frames (ssh2: packet too long).
pub const SSH2_MAX_PACKET_LENGTH: Int = 35000;
/// Default packet length-block alignment: 8 (unencrypted transport or a
/// 64-bit block cipher).
pub const SSH2_DEFAULT_BLOCK_SIZE: Int = 8;
/// Maximum alignment unit relevant to RFC 4253: 16 (AES and other 128-bit
/// block ciphers).
pub const SSH2_MAX_BLOCK_SIZE: Int = 16;

// --------------------------------------------------
//  Disconnect reason codes (RFC 4253 section 11.1)
// --------------------------------------------------

/// 1: host not allowed to connect.
pub const SSH_DISCONNECT_HOST_NOT_ALLOWED_TO_CONNECT: Int = 1;
/// 2: protocol error.
pub const SSH_DISCONNECT_PROTOCOL_ERROR: Int = 2;
/// 3: key exchange failed.
pub const SSH_DISCONNECT_KEY_EXCHANGE_FAILED: Int = 3;
/// 4: reserved (RFC 4253 does not define reason 4).
pub const SSH_DISCONNECT_RESERVED: Int = 4;
/// 5: MAC error.
pub const SSH_DISCONNECT_MAC_ERROR: Int = 5;
/// 6: compression error.
pub const SSH_DISCONNECT_COMPRESSION_ERROR: Int = 6;
/// 7: service not available.
pub const SSH_DISCONNECT_SERVICE_NOT_AVAILABLE: Int = 7;
/// 8: protocol version not supported.
pub const SSH_DISCONNECT_PROTOCOL_VERSION_NOT_SUPPORTED: Int = 8;
/// 9: host key not verifiable.
pub const SSH_DISCONNECT_HOST_KEY_NOT_VERIFIABLE: Int = 9;
/// 10: connection lost.
pub const SSH_DISCONNECT_CONNECTION_LOST: Int = 10;
/// 11: disconnected by application.
pub const SSH_DISCONNECT_BY_APPLICATION: Int = 11;
/// 12: too many connections.
pub const SSH_DISCONNECT_TOO_MANY_CONNECTIONS: Int = 12;
/// 13: authentication cancelled by user.
pub const SSH_DISCONNECT_AUTH_CANCELLED_BY_USER: Int = 13;
/// 14: no more authentication methods available.
pub const SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE: Int = 14;
/// 15: illegal user name.
pub const SSH_DISCONNECT_ILLEGAL_USER_NAME: Int = 15;

// --------------------------------------------------
//  Channel open failure reason codes (RFC 4254 section 5.1)
// --------------------------------------------------

/// 1: administratively prohibited.
pub const SSH_OPEN_ADMINISTRATIVELY_PROHIBITED: Int = 1;
/// 2: connect failed.
pub const SSH_OPEN_CONNECT_FAILED: Int = 2;
/// 3: unknown channel type.
pub const SSH_OPEN_UNKNOWN_CHANNEL_TYPE: Int = 3;
/// 4: resource shortage.
pub const SSH_OPEN_RESOURCE_SHORTAGE: Int = 4;

// --------------------------------------------------
//  Extended data type codes (RFC 4254 section 5.2)
// --------------------------------------------------

/// 1: SSH_EXTENDED_DATA_STDERR.
pub const SSH_EXTENDED_DATA_STDERR: Int = 1;

// --------------------------------------------------
//  Parsed types (all flat)
// --------------------------------------------------

/// Parsed binary packet frame. `start` is the packet offset in the source
/// buffer; `payload_off` = start + 5; `payload_len` = packet_length -
/// padding_length - 1; `padding_off` = payload_off + payload_len; `total` =
/// 4 + packet_length (bytes consumed by the frame, MAC excluded); `end` =
/// start + total; `mac_off` = end (the MAC, when the negotiated algorithm has
/// one, begins here and is NOT parsed or verified by this module).
pub type Ssh2Packet = {
  start: Int;
  packet_length: Int;
  padding_length: Int;
  payload_off: Int;
  payload_len: Int;
  padding_off: Int;
  total: Int;
  end: Int;
  mac_off: Int;
}

/// A length-prefixed field bound into the source buffer: `start` is the
/// absolute offset of the first content byte, `len` the declared content
/// length and `total` the bytes consumed from the field's own offset
/// (4 + len for strings, mpints and name-lists). `start` is not bounds
/// checked against a particular buffer here; copy with ssh2_slice_bytes.
pub type Ssh2Slice = {
  start: Int;
  len: Int;
  total: Int;
}

/// One parsed message envelope from ssh2_parse_message: the binary packet
/// frame plus the message type and a verbatim copy of the whole payload in
/// `raw` (message type byte included). `known` is true when the message
/// number is in the RFC 4253/4252/4254 catalog implemented here; unknown
/// numbers are preserved raw with known = false. `body_off` = payload_off + 1
/// and `body_len` = payload_len - 1. `total` is 4 + packet_length.
pub type Ssh2Message = {
  msg_type: Int;
  known: Bool;
  start: Int;
  payload_off: Int;
  payload_len: Int;
  body_off: Int;
  body_len: Int;
  total: Int;
  packet_length: Int;
  padding_length: Int;
  mac_off: Int;
  raw: Vec[UInt8];
}

/// SSH_MSG_DISCONNECT body: uint32 reason code + string description +
/// string language tag.
pub type Ssh2Disconnect = {
  reason: Int;
  description: Vec[UInt8];
  language: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_IGNORE body: string data (any bytes).
pub type Ssh2Ignore = {
  data: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_UNIMPLEMENTED body: uint32 sequence number of the offending packet.
pub type Ssh2Unimplemented = {
  sequence: Int;
  total: Int;
}

/// SSH_MSG_DEBUG body: boolean always_display + string message + string
/// language tag.
pub type Ssh2Debug = {
  always_display: Bool;
  message: Vec[UInt8];
  language: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_KEXINIT body: 16-byte cookie, ten name-lists in wire order
/// (kex, host key, encryption c2s, encryption s2c, MAC c2s, MAC s2c,
/// compression c2s, compression s2c, languages c2s, languages s2c), then
/// boolean first_kex_packet_follows and uint32 reserved. Name-lists are kept
/// raw (comma-joined ASCII); split them with ssh2_name_list_count /
/// ssh2_name_list_name / ssh2_name_list_contains.
pub type Ssh2KexInit = {
  cookie: Vec[UInt8];
  kex_algorithms: Vec[UInt8];
  host_key_algorithms: Vec[UInt8];
  encryption_c2s: Vec[UInt8];
  encryption_s2c: Vec[UInt8];
  mac_c2s: Vec[UInt8];
  mac_s2c: Vec[UInt8];
  compression_c2s: Vec[UInt8];
  compression_s2c: Vec[UInt8];
  languages_c2s: Vec[UInt8];
  languages_s2c: Vec[UInt8];
  first_kex_packet_follows: Bool;
  reserved: Int;
  total: Int;
}

/// SSH_MSG_KEXDH_INIT body: mpint e, carried raw.
pub type Ssh2KexDhInit = {
  e: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_KEX_ECDH_INIT body: string Q_C, carried raw (the first byte is
/// normally the EC point format, 4 = uncompressed).
pub type Ssh2KexEcdhInit = {
  q_c: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_KEXDH_REPLY and SSH_MSG_KEX_ECDH_REPLY share the wire shape
/// string host key + one length-prefixed value + string signature. `value`
/// is the raw mpint f (DH) or raw string Q_S (ECDH); the distinguishing
/// parsers are ssh2_parse_kexdh_reply (which applies the mpint sign check)
/// and ssh2_parse_kex_ecdh_reply.
pub type Ssh2KexReply = {
  host_key: Vec[UInt8];
  value: Vec[UInt8];
  signature: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_SERVICE_REQUEST / SSH_MSG_SERVICE_ACCEPT body: string service name.
pub type Ssh2Service = {
  service: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_USERAUTH_REQUEST body. The method-specific decode covers
/// "password" (change_password false: `secret` = password; true:
/// `old_password` + `secret` = new password) and "publickey"
/// (`algorithm`, `secret` = key blob, and `signature` when has_signature).
/// For any other method `decoded` is false and `extra` holds the raw
/// method-specific tail. Fields not applicable to the method are empty/false.
/// `total` = 4 + packet_length.
pub type Ssh2UserAuthRequest = {
  user: Vec[UInt8];
  service: Vec[UInt8];
  method: Vec[UInt8];
  decoded: Bool;
  change_password: Bool;
  has_signature: Bool;
  algorithm: Vec[UInt8];
  secret: Vec[UInt8];
  signature: Vec[UInt8];
  old_password: Vec[UInt8];
  extra: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_USERAUTH_FAILURE body: name-list of methods that can continue +
/// boolean partial success.
pub type Ssh2UserAuthFailure = {
  methods: Vec[UInt8];
  partial: Bool;
  total: Int;
}

/// SSH_MSG_USERAUTH_BANNER body: string message + string language tag.
pub type Ssh2Banner = {
  message: Vec[UInt8];
  language: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_GLOBAL_REQUEST body: string request name + boolean want_reply +
/// raw request-specific data (possibly empty).
pub type Ssh2GlobalRequest = {
  name: Vec[UInt8];
  want_reply: Bool;
  data: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_REQUEST_SUCCESS body: raw response data (possibly empty).
pub type Ssh2RequestSuccess = {
  data: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_CHANNEL_OPEN body. `decoded` is true for the channel types this
/// codec understands: "session" (no type-specific fields), "direct-tcpip"
/// (`host`/`port` = host to connect, `origin`/`origin_port` = originator) and
/// "forwarded-tcpip" (`host`/`port` = connected address, `origin`/
/// `origin_port` = originator). For any other channel type decoded is false
/// and `extra` holds the raw type-specific tail. `window` is the initial
/// window size, `max_packet` the maximum packet size.
pub type Ssh2ChannelOpen = {
  channel_type: Vec[UInt8];
  sender: Int;
  window: Int;
  max_packet: Int;
  decoded: Bool;
  host: Vec[UInt8];
  port: Int;
  origin: Vec[UInt8];
  origin_port: Int;
  extra: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_CHANNEL_OPEN_CONFIRMATION body: recipient, sender, initial window
/// size, maximum packet size and the raw type-specific tail in `extra`.
pub type Ssh2ChannelOpenConfirmation = {
  recipient: Int;
  sender: Int;
  window: Int;
  max_packet: Int;
  extra: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_CHANNEL_OPEN_FAILURE body: recipient, uint32 reason code, string
/// description, string language tag.
pub type Ssh2ChannelOpenFailure = {
  recipient: Int;
  reason: Int;
  description: Vec[UInt8];
  language: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_CHANNEL_WINDOW_ADJUST body: recipient + uint32 bytes to add.
pub type Ssh2WindowAdjust = {
  recipient: Int;
  bytes: Int;
  total: Int;
}

/// SSH_MSG_CHANNEL_REQUEST body. The request-specific decode covers
/// "pty-req" (text0 = TERM, u32_0..3 = cols/rows/width/height px,
/// text1 = raw encoded terminal modes), "env" (text0 = name, text1 = value),
/// "exec" (text0 = command), "shell" (no fields), "subsystem" (text0 =
/// subsystem name) and "window-change" (u32_0..3 = cols/rows/width/height).
/// For any other request type decoded is false and `extra` holds the raw
/// tail. `total` = 4 + packet_length.
pub type Ssh2ChannelRequest = {
  recipient: Int;
  request: Vec[UInt8];
  want_reply: Bool;
  decoded: Bool;
  text0: Vec[UInt8];
  text1: Vec[UInt8];
  u32_0: Int;
  u32_1: Int;
  u32_2: Int;
  u32_3: Int;
  extra: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_CHANNEL_DATA body: recipient + string data (binary safe).
pub type Ssh2ChannelData = {
  recipient: Int;
  data: Vec[UInt8];
  total: Int;
}

/// SSH_MSG_CHANNEL_EXTENDED_DATA body: recipient + uint32 data type code
/// (1 = stderr) + string data.
pub type Ssh2ChannelExtendedData = {
  recipient: Int;
  data_type: Int;
  data: Vec[UInt8];
  total: Int;
}

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

// Ok(v) for Result[Ssh2Packet, Str].
fn _ok_packet(v: Ssh2Packet) -> Result[Ssh2Packet, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2Packet, Str].
fn _err_packet(m: Str) -> Result[Ssh2Packet, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2Slice, Str].
fn _ok_slice(v: Ssh2Slice) -> Result[Ssh2Slice, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2Slice, Str].
fn _err_slice(m: Str) -> Result[Ssh2Slice, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2Message, Str].
fn _ok_message(v: Ssh2Message) -> Result[Ssh2Message, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2Message, Str].
fn _err_message(m: Str) -> Result[Ssh2Message, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2Disconnect, Str].
fn _ok_disconnect(v: Ssh2Disconnect) -> Result[Ssh2Disconnect, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2Disconnect, Str].
fn _err_disconnect(m: Str) -> Result[Ssh2Disconnect, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2Ignore, Str].
fn _ok_ignore(v: Ssh2Ignore) -> Result[Ssh2Ignore, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2Ignore, Str].
fn _err_ignore(m: Str) -> Result[Ssh2Ignore, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2Unimplemented, Str].
fn _ok_unimplemented(v: Ssh2Unimplemented) -> Result[Ssh2Unimplemented, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2Unimplemented, Str].
fn _err_unimplemented(m: Str) -> Result[Ssh2Unimplemented, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2Debug, Str].
fn _ok_debug(v: Ssh2Debug) -> Result[Ssh2Debug, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2Debug, Str].
fn _err_debug(m: Str) -> Result[Ssh2Debug, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2KexInit, Str].
fn _ok_kexinit(v: Ssh2KexInit) -> Result[Ssh2KexInit, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2KexInit, Str].
fn _err_kexinit(m: Str) -> Result[Ssh2KexInit, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2KexDhInit, Str].
fn _ok_kexdh_init(v: Ssh2KexDhInit) -> Result[Ssh2KexDhInit, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2KexDhInit, Str].
fn _err_kexdh_init(m: Str) -> Result[Ssh2KexDhInit, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2KexEcdhInit, Str].
fn _ok_kexecdh_init(v: Ssh2KexEcdhInit) -> Result[Ssh2KexEcdhInit, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2KexEcdhInit, Str].
fn _err_kexecdh_init(m: Str) -> Result[Ssh2KexEcdhInit, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2KexReply, Str].
fn _ok_kexreply(v: Ssh2KexReply) -> Result[Ssh2KexReply, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2KexReply, Str].
fn _err_kexreply(m: Str) -> Result[Ssh2KexReply, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2Service, Str].
fn _ok_service(v: Ssh2Service) -> Result[Ssh2Service, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2Service, Str].
fn _err_service(m: Str) -> Result[Ssh2Service, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2UserAuthRequest, Str].
fn _ok_userauth_req(v: Ssh2UserAuthRequest) -> Result[Ssh2UserAuthRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2UserAuthRequest, Str].
fn _err_userauth_req(m: Str) -> Result[Ssh2UserAuthRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2UserAuthFailure, Str].
fn _ok_userauth_fail(v: Ssh2UserAuthFailure) -> Result[Ssh2UserAuthFailure, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2UserAuthFailure, Str].
fn _err_userauth_fail(m: Str) -> Result[Ssh2UserAuthFailure, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2Banner, Str].
fn _ok_banner(v: Ssh2Banner) -> Result[Ssh2Banner, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2Banner, Str].
fn _err_banner(m: Str) -> Result[Ssh2Banner, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2GlobalRequest, Str].
fn _ok_global_req(v: Ssh2GlobalRequest) -> Result[Ssh2GlobalRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2GlobalRequest, Str].
fn _err_global_req(m: Str) -> Result[Ssh2GlobalRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2RequestSuccess, Str].
fn _ok_req_success(v: Ssh2RequestSuccess) -> Result[Ssh2RequestSuccess, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2RequestSuccess, Str].
fn _err_req_success(m: Str) -> Result[Ssh2RequestSuccess, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2ChannelOpen, Str].
fn _ok_channel_open(v: Ssh2ChannelOpen) -> Result[Ssh2ChannelOpen, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2ChannelOpen, Str].
fn _err_channel_open(m: Str) -> Result[Ssh2ChannelOpen, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2ChannelOpenConfirmation, Str].
fn _ok_channel_confirm(v: Ssh2ChannelOpenConfirmation) -> Result[Ssh2ChannelOpenConfirmation, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2ChannelOpenConfirmation, Str].
fn _err_channel_confirm(m: Str) -> Result[Ssh2ChannelOpenConfirmation, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2ChannelOpenFailure, Str].
fn _ok_channel_open_fail(v: Ssh2ChannelOpenFailure) -> Result[Ssh2ChannelOpenFailure, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2ChannelOpenFailure, Str].
fn _err_channel_open_fail(m: Str) -> Result[Ssh2ChannelOpenFailure, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2WindowAdjust, Str].
fn _ok_window_adjust(v: Ssh2WindowAdjust) -> Result[Ssh2WindowAdjust, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2WindowAdjust, Str].
fn _err_window_adjust(m: Str) -> Result[Ssh2WindowAdjust, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2ChannelRequest, Str].
fn _ok_channel_request(v: Ssh2ChannelRequest) -> Result[Ssh2ChannelRequest, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2ChannelRequest, Str].
fn _err_channel_request(m: Str) -> Result[Ssh2ChannelRequest, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2ChannelData, Str].
fn _ok_channel_data(v: Ssh2ChannelData) -> Result[Ssh2ChannelData, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2ChannelData, Str].
fn _err_channel_data(m: Str) -> Result[Ssh2ChannelData, Str] {
  return Err(m);
}

// Ok(v) for Result[Ssh2ChannelExtendedData, Str].
fn _ok_channel_ext(v: Ssh2ChannelExtendedData) -> Result[Ssh2ChannelExtendedData, Str] {
  return Ok(v);
}

// Err(m) for Result[Ssh2ChannelExtendedData, Str].
fn _err_channel_ext(m: Str) -> Result[Ssh2ChannelExtendedData, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Internal byte helpers
// --------------------------------------------------

// "ssh2: <msg> at <off>" -- every structural error carries its byte offset.
fn _at(msg: Str, off: Int) -> Str {
  return msg + " at " + int_to_base(off, 10);
}

// True when the two strings are byte-equal (BUG 17 discipline: never `==`
// on Str values; the compare module is the only equality source).
fn _str_eq(a: Str, b: Str) -> Bool {
  return compare.str_compare(a, b) == 0;
}

// Byte at `pos` widened to 0..255; callers guarantee the bounds.
fn _byte(data: &Vec[UInt8], pos: Int) -> Int {
  return (data[pos] as Int) & 0xFF;
}

// Unsigned big-endian u32 at [pos, pos+4); callers guarantee the bounds.
fn _read_u32(data: &Vec[UInt8], pos: Int) -> Int {
  return _byte(data, pos) * 16777216 + _byte(data, pos + 1) * 65536 + _byte(data, pos + 2) * 256 + _byte(data, pos + 3);
}

// Append every byte of v to out.
fn _push_vec(out: &mut Vec[UInt8], v: &Vec[UInt8]) {
  var i = 0;
  while i < v.len() {
    out.push(v[i]);
    i = i + 1;
  }
}

// Append data[a, b) to out; callers guarantee the bounds.
fn _copy_span(data: &Vec[UInt8], a: Int, b: Int, out: &mut Vec[UInt8]) {
  var i = a;
  while i < b {
    out.push(data[i]);
    i = i + 1;
  }
}

// Append every byte of the ASCII/UTF-8 string `s` to out.
fn _push_str(out: &mut Vec[UInt8], s: Str) {
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i));
    i = i + 1;
  }
}

// True when v is exactly the ASCII literal `lit` (used for method/type
// dispatch; compares bytes, never Str with ==).
fn _vec_eq_lit(v: &Vec[UInt8], lit: Str) -> Bool {
  if v.len() != lit.len() {
    return false;
  }
  var i = 0;
  while i < v.len() {
    if _byte(v, i) != ((string.byte_at(lit, i) as Int) & 0xFF) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// True when a[a1, b1) and b[a2, b2) are byte-equal (two different vectors).
fn _span_eq2(a: &Vec[UInt8], a1: Int, b1: Int, b: &Vec[UInt8], a2: Int, b2: Int) -> Bool {
  if b1 - a1 != b2 - a2 {
    return false;
  }
  var i = 0;
  while i < b1 - a1 {
    if _byte(a, a1 + i) != _byte(b, a2 + i) {
      return false;
    }
    i = i + 1;
  }
  return true;
}

// --------------------------------------------------
//  Message type tables
// --------------------------------------------------

/// RFC name of a message number ("SSH_MSG_DISCONNECT" .. "SSH_MSG_CHANNEL_
/// FAILURE"), or "UNKNOWN" for a number outside this codec's catalog.
/// Params: t - a message number. Returns: the name. Error case: none.
pub fn ssh2_message_type_name(t: Int) -> Str {
  if t == SSH_MSG_DISCONNECT { return "SSH_MSG_DISCONNECT"; }
  if t == SSH_MSG_IGNORE { return "SSH_MSG_IGNORE"; }
  if t == SSH_MSG_UNIMPLEMENTED { return "SSH_MSG_UNIMPLEMENTED"; }
  if t == SSH_MSG_DEBUG { return "SSH_MSG_DEBUG"; }
  if t == SSH_MSG_SERVICE_REQUEST { return "SSH_MSG_SERVICE_REQUEST"; }
  if t == SSH_MSG_SERVICE_ACCEPT { return "SSH_MSG_SERVICE_ACCEPT"; }
  if t == SSH_MSG_KEXINIT { return "SSH_MSG_KEXINIT"; }
  if t == SSH_MSG_NEWKEYS { return "SSH_MSG_NEWKEYS"; }
  if t == SSH_MSG_KEXDH_INIT { return "SSH_MSG_KEXDH_INIT"; }
  if t == SSH_MSG_KEXDH_REPLY { return "SSH_MSG_KEXDH_REPLY"; }
  if t == SSH_MSG_USERAUTH_REQUEST { return "SSH_MSG_USERAUTH_REQUEST"; }
  if t == SSH_MSG_USERAUTH_FAILURE { return "SSH_MSG_USERAUTH_FAILURE"; }
  if t == SSH_MSG_USERAUTH_SUCCESS { return "SSH_MSG_USERAUTH_SUCCESS"; }
  if t == SSH_MSG_USERAUTH_BANNER { return "SSH_MSG_USERAUTH_BANNER"; }
  if t == SSH_MSG_GLOBAL_REQUEST { return "SSH_MSG_GLOBAL_REQUEST"; }
  if t == SSH_MSG_REQUEST_SUCCESS { return "SSH_MSG_REQUEST_SUCCESS"; }
  if t == SSH_MSG_REQUEST_FAILURE { return "SSH_MSG_REQUEST_FAILURE"; }
  if t == SSH_MSG_CHANNEL_OPEN { return "SSH_MSG_CHANNEL_OPEN"; }
  if t == SSH_MSG_CHANNEL_OPEN_CONFIRMATION { return "SSH_MSG_CHANNEL_OPEN_CONFIRMATION"; }
  if t == SSH_MSG_CHANNEL_OPEN_FAILURE { return "SSH_MSG_CHANNEL_OPEN_FAILURE"; }
  if t == SSH_MSG_CHANNEL_WINDOW_ADJUST { return "SSH_MSG_CHANNEL_WINDOW_ADJUST"; }
  if t == SSH_MSG_CHANNEL_DATA { return "SSH_MSG_CHANNEL_DATA"; }
  if t == SSH_MSG_CHANNEL_EXTENDED_DATA { return "SSH_MSG_CHANNEL_EXTENDED_DATA"; }
  if t == SSH_MSG_CHANNEL_EOF { return "SSH_MSG_CHANNEL_EOF"; }
  if t == SSH_MSG_CHANNEL_CLOSE { return "SSH_MSG_CHANNEL_CLOSE"; }
  if t == SSH_MSG_CHANNEL_REQUEST { return "SSH_MSG_CHANNEL_REQUEST"; }
  if t == SSH_MSG_CHANNEL_SUCCESS { return "SSH_MSG_CHANNEL_SUCCESS"; }
  if t == SSH_MSG_CHANNEL_FAILURE { return "SSH_MSG_CHANNEL_FAILURE"; }
  return "UNKNOWN";
}

/// True when the message number is in this codec's catalog (1..100 as
/// implemented: disconnect, ignore, unimplemented, debug, service, kex,
/// userauth, global request and channel messages). Unknown numbers are valid
/// SSH messages only if the negotiated extensions define them; the codec
/// preserves them raw with known = false.
/// Params: t - a message number. Returns: the predicate. Error case: none.
pub fn ssh2_message_type_known(t: Int) -> Bool {
  if t == SSH_MSG_DISCONNECT { return true; }
  if t == SSH_MSG_IGNORE { return true; }
  if t == SSH_MSG_UNIMPLEMENTED { return true; }
  if t == SSH_MSG_DEBUG { return true; }
  if t == SSH_MSG_SERVICE_REQUEST { return true; }
  if t == SSH_MSG_SERVICE_ACCEPT { return true; }
  if t == SSH_MSG_KEXINIT { return true; }
  if t == SSH_MSG_NEWKEYS { return true; }
  if t == SSH_MSG_KEXDH_INIT { return true; }
  if t == SSH_MSG_KEXDH_REPLY { return true; }
  if t == SSH_MSG_USERAUTH_REQUEST { return true; }
  if t == SSH_MSG_USERAUTH_FAILURE { return true; }
  if t == SSH_MSG_USERAUTH_SUCCESS { return true; }
  if t == SSH_MSG_USERAUTH_BANNER { return true; }
  if t == SSH_MSG_GLOBAL_REQUEST { return true; }
  if t == SSH_MSG_REQUEST_SUCCESS { return true; }
  if t == SSH_MSG_REQUEST_FAILURE { return true; }
  if t == SSH_MSG_CHANNEL_OPEN { return true; }
  if t == SSH_MSG_CHANNEL_OPEN_CONFIRMATION { return true; }
  if t == SSH_MSG_CHANNEL_OPEN_FAILURE { return true; }
  if t == SSH_MSG_CHANNEL_WINDOW_ADJUST { return true; }
  if t == SSH_MSG_CHANNEL_DATA { return true; }
  if t == SSH_MSG_CHANNEL_EXTENDED_DATA { return true; }
  if t == SSH_MSG_CHANNEL_EOF { return true; }
  if t == SSH_MSG_CHANNEL_CLOSE { return true; }
  if t == SSH_MSG_CHANNEL_REQUEST { return true; }
  if t == SSH_MSG_CHANNEL_SUCCESS { return true; }
  if t == SSH_MSG_CHANNEL_FAILURE { return true; }
  return false;
}

/// Short text of a disconnect reason code (RFC 4253 section 11.1); unknown
/// codes return "". Params: code - a reason code. Returns: the text.
/// Error case: none.
pub fn ssh2_disconnect_reason_name(code: Int) -> Str {
  if code == SSH_DISCONNECT_HOST_NOT_ALLOWED_TO_CONNECT { return "HOST_NOT_ALLOWED_TO_CONNECT"; }
  if code == SSH_DISCONNECT_PROTOCOL_ERROR { return "PROTOCOL_ERROR"; }
  if code == SSH_DISCONNECT_KEY_EXCHANGE_FAILED { return "KEY_EXCHANGE_FAILED"; }
  if code == SSH_DISCONNECT_RESERVED { return "RESERVED"; }
  if code == SSH_DISCONNECT_MAC_ERROR { return "MAC_ERROR"; }
  if code == SSH_DISCONNECT_COMPRESSION_ERROR { return "COMPRESSION_ERROR"; }
  if code == SSH_DISCONNECT_SERVICE_NOT_AVAILABLE { return "SERVICE_NOT_AVAILABLE"; }
  if code == SSH_DISCONNECT_PROTOCOL_VERSION_NOT_SUPPORTED { return "PROTOCOL_VERSION_NOT_SUPPORTED"; }
  if code == SSH_DISCONNECT_HOST_KEY_NOT_VERIFIABLE { return "HOST_KEY_NOT_VERIFIABLE"; }
  if code == SSH_DISCONNECT_CONNECTION_LOST { return "CONNECTION_LOST"; }
  if code == SSH_DISCONNECT_BY_APPLICATION { return "BY_APPLICATION"; }
  if code == SSH_DISCONNECT_TOO_MANY_CONNECTIONS { return "TOO_MANY_CONNECTIONS"; }
  if code == SSH_DISCONNECT_AUTH_CANCELLED_BY_USER { return "AUTH_CANCELLED_BY_USER"; }
  if code == SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE { return "NO_MORE_AUTH_METHODS_AVAILABLE"; }
  if code == SSH_DISCONNECT_ILLEGAL_USER_NAME { return "ILLEGAL_USER_NAME"; }
  return "";
}

/// One-line explanatory text of a disconnect reason code; unknown codes
/// return "". Params: code - a reason code. Returns: the text.
/// Error case: none.
pub fn ssh2_disconnect_reason_message(code: Int) -> Str {
  if code == SSH_DISCONNECT_HOST_NOT_ALLOWED_TO_CONNECT { return "host not allowed to connect"; }
  if code == SSH_DISCONNECT_PROTOCOL_ERROR { return "protocol error"; }
  if code == SSH_DISCONNECT_KEY_EXCHANGE_FAILED { return "key exchange failed"; }
  if code == SSH_DISCONNECT_RESERVED { return "reserved"; }
  if code == SSH_DISCONNECT_MAC_ERROR { return "MAC error"; }
  if code == SSH_DISCONNECT_COMPRESSION_ERROR { return "compression error"; }
  if code == SSH_DISCONNECT_SERVICE_NOT_AVAILABLE { return "service not available"; }
  if code == SSH_DISCONNECT_PROTOCOL_VERSION_NOT_SUPPORTED { return "protocol version not supported"; }
  if code == SSH_DISCONNECT_HOST_KEY_NOT_VERIFIABLE { return "host key not verifiable"; }
  if code == SSH_DISCONNECT_CONNECTION_LOST { return "connection lost"; }
  if code == SSH_DISCONNECT_BY_APPLICATION { return "disconnected by application"; }
  if code == SSH_DISCONNECT_TOO_MANY_CONNECTIONS { return "too many connections"; }
  if code == SSH_DISCONNECT_AUTH_CANCELLED_BY_USER { return "authentication cancelled by user"; }
  if code == SSH_DISCONNECT_NO_MORE_AUTH_METHODS_AVAILABLE { return "no more authentication methods available"; }
  if code == SSH_DISCONNECT_ILLEGAL_USER_NAME { return "illegal user name"; }
  return "";
}

/// Name of a channel open failure reason code (RFC 4254 section 5.1);
/// unknown codes return "". Params: code - a reason code. Returns: the name.
/// Error case: none.
pub fn ssh2_channel_open_failure_reason_name(code: Int) -> Str {
  if code == SSH_OPEN_ADMINISTRATIVELY_PROHIBITED { return "ADMINISTRATIVELY_PROHIBITED"; }
  if code == SSH_OPEN_CONNECT_FAILED { return "CONNECT_FAILED"; }
  if code == SSH_OPEN_UNKNOWN_CHANNEL_TYPE { return "UNKNOWN_CHANNEL_TYPE"; }
  if code == SSH_OPEN_RESOURCE_SHORTAGE { return "RESOURCE_SHORTAGE"; }
  return "";
}

/// Name of an extended data type code (RFC 4254 section 5.2): "STDERR" for 1,
/// "" otherwise. Params: code - a data type code. Returns: the name.
/// Error case: none.
pub fn ssh2_extended_data_type_name(code: Int) -> Str {
  if code == SSH_EXTENDED_DATA_STDERR { return "STDERR"; }
  return "";
}

// --------------------------------------------------
//  Field primitives (RFC 4251 section 5)
// --------------------------------------------------
//
// byte      one unsigned octet (0..255)
// boolean   one octet: 0 = false, any non-zero = true
// uint32    four octets, unsigned big-endian
// string    uint32 length + that many bytes (binary safe, may be empty)
// mpint     uint32 length + that many big-endian two's-complement bytes,
//           carried RAW (no bignum arithmetic anywhere in this module)
// name-list uint32 length + comma-separated US-ASCII names; the empty
//           name-list is legal, every present name must be non-empty and
//           consist of printable ASCII 0x21..0x7E (no spaces, no commas)
//
// Readers with an `off` parameter return the decoded value; use the
// *_slice variants when the consumed byte count matters (Ssh2Slice.total).

// Read the u32 length prefix of a string/mpint/name-list at `off`, bounded by
// `end`. `what` names the field in the error text. Bounds: the 4-byte prefix
// must fit, then the declared content must fit.
fn _len_in(data: &Vec[UInt8], off: Int, end: Int, what: Str) -> Result[Int, Str] {
  if off + 4 > end {
    return _err_int(_at("ssh2: truncated " + what + " length", off));
  }
  let n = _read_u32(data, off);
  if off + 4 + n > end {
    return _err_int(_at("ssh2: truncated " + what, off));
  }
  return _ok_int(n);
}

// One byte in [off, end), widened to 0..255.
fn _u8_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[Int, Str] {
  if off + 1 > end {
    return _err_int(_at("ssh2: truncated byte", off));
  }
  return _ok_int(_byte(data, off));
}

// One boolean in [off, end): 0 is false, every other byte is true.
fn _bool_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[Bool, Str] {
  if off + 1 > end {
    return _err_bool(_at("ssh2: truncated boolean", off));
  }
  if _byte(data, off) == 0 {
    return _ok_bool(false);
  }
  return _ok_bool(true);
}

// One uint32 in [off, end).
fn _u32_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[Int, Str] {
  if off + 4 > end {
    return _err_int(_at("ssh2: truncated uint32", off));
  }
  return _ok_int(_read_u32(data, off));
}

// One length-prefixed field in [off, end), copied out. `what` names the
// field in the error text.
fn _bytes_in(data: &Vec[UInt8], off: Int, end: Int, what: Str) -> Result[Vec[UInt8], Str] {
  let lr = _len_in(data, off, end, what);
  if !lr.is_ok {
    return _err_bytes(lr.error);
  }
  let n: Int = lr.value;
  var out = Vec[UInt8].new();
  _copy_span(data, off + 4, off + 4 + n, &mut out);
  return _ok_bytes(out);
}

// One length-prefixed field in [off, end), bound as a slice.
fn _slice_in(data: &Vec[UInt8], off: Int, end: Int, what: Str) -> Result[Ssh2Slice, Str] {
  let lr = _len_in(data, off, end, what);
  if !lr.is_ok {
    return _err_slice(lr.error);
  }
  let n: Int = lr.value;
  return _ok_slice(Ssh2Slice{ start: off + 4; len: n; total: 4 + n; });
}

// One name-list in [off, end), copied out and structurally validated.
fn _nl_in(data: &Vec[UInt8], off: Int, end: Int) -> Result[Vec[UInt8], Str] {
  let br = _bytes_in(data, off, end, "name-list");
  if !br.is_ok {
    return _err_bytes(br.error);
  }
  let v: Vec[UInt8] = br.value;
  let n = v.len();
  if !_nl_span_is_valid(data, off + 4, off + 4 + n) {
    return _err_bytes(_at("ssh2: bad name-list", off));
  }
  return _ok_bytes(v);
}

/// Read one byte at `off`, widened to 0..255.
/// Params: data - buffer; off - field offset.
/// Returns: Ok(value 0..255).
/// Errors: "ssh2: negative offset"; "ssh2: truncated byte at <off>".
/// Complexity: O(1).
pub fn ssh2_read_byte(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  if off < 0 {
    return _err_int("ssh2: negative offset");
  }
  return _u8_in(data, off, data.len());
}

/// Read one boolean at `off` (0 = false, any non-zero byte = true).
/// Params: data - buffer; off - field offset.
/// Returns: Ok(the predicate).
/// Errors: "ssh2: negative offset"; "ssh2: truncated boolean at <off>".
/// Complexity: O(1).
pub fn ssh2_read_boolean(data: &Vec[UInt8], off: Int) -> Result[Bool, Str] {
  if off < 0 {
    return _err_bool("ssh2: negative offset");
  }
  return _bool_in(data, off, data.len());
}

/// Read one unsigned big-endian uint32 at `off` (0..4294967295).
/// Params: data - buffer; off - field offset.
/// Returns: Ok(value).
/// Errors: "ssh2: negative offset"; "ssh2: truncated uint32 at <off>".
/// Complexity: O(1).
pub fn ssh2_read_uint32(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  if off < 0 {
    return _err_int("ssh2: negative offset");
  }
  return _u32_in(data, off, data.len());
}

/// Read one RFC 4251 string at `off`: uint32 length + that many bytes. The
/// copy is binary safe (embedded NUL, CR, LF and bytes >= 128 are preserved).
/// Params: data - buffer; off - field offset.
/// Returns: Ok(the content bytes; empty for a zero-length string).
/// Errors: "ssh2: negative offset"; "ssh2: truncated string length at <off>";
/// "ssh2: truncated string at <off>".
/// Complexity: O(length).
pub fn ssh2_read_string(data: &Vec[UInt8], off: Int) -> Result[Vec[UInt8], Str] {
  if off < 0 {
    return _err_bytes("ssh2: negative offset");
  }
  return _bytes_in(data, off, data.len(), "string");
}

/// Read one RFC 4251 string binding at `off` without copying the bytes.
/// Params: data - buffer; off - field offset.
/// Returns: Ok(slice) with start = off + 4, len = declared length and
/// total = 4 + len (bytes consumed from off).
/// Errors: as ssh2_read_string.
/// Complexity: O(1).
pub fn ssh2_read_string_slice(data: &Vec[UInt8], off: Int) -> Result[Ssh2Slice, Str] {
  if off < 0 {
    return _err_slice("ssh2: negative offset");
  }
  return _slice_in(data, off, data.len(), "string");
}

/// Read one mpint at `off` as RAW big-endian two's-complement bytes (uint32
/// length + bytes). No bignum interpretation happens here; use
/// ssh2_mpint_is_negative for the only sign inspection offered. The empty
/// mpint (length 0) represents the value 0.
/// Params: data - buffer; off - field offset.
/// Returns: Ok(the raw bytes).
/// Errors: "ssh2: negative offset"; "ssh2: truncated mpint length at <off>";
/// "ssh2: truncated mpint at <off>".
/// Complexity: O(length).
pub fn ssh2_read_mpint(data: &Vec[UInt8], off: Int) -> Result[Vec[UInt8], Str] {
  if off < 0 {
    return _err_bytes("ssh2: negative offset");
  }
  return _bytes_in(data, off, data.len(), "mpint");
}

/// Read one mpint binding at `off` without copying (raw bytes).
/// Params: data - buffer; off - field offset.
/// Returns: Ok(slice) with start = off + 4, len and total = 4 + len.
/// Errors: as ssh2_read_mpint.
/// Complexity: O(1).
pub fn ssh2_read_mpint_slice(data: &Vec[UInt8], off: Int) -> Result[Ssh2Slice, Str] {
  if off < 0 {
    return _err_slice("ssh2: negative offset");
  }
  return _slice_in(data, off, data.len(), "mpint");
}

/// Read one name-list at `off` (uint32 length + comma-separated ASCII) and
/// validate it: the empty list is legal; every present name must be non-empty
/// and printable ASCII 0x21..0x7E.
/// Params: data - buffer; off - field offset.
/// Returns: Ok(the raw comma-joined bytes; empty for an empty list).
/// Errors: "ssh2: negative offset"; "ssh2: truncated name-list length at
/// <off>"; "ssh2: truncated name-list at <off>"; "ssh2: bad name-list at
/// <off>".
/// Complexity: O(length).
pub fn ssh2_read_name_list(data: &Vec[UInt8], off: Int) -> Result[Vec[UInt8], Str] {
  if off < 0 {
    return _err_bytes("ssh2: negative offset");
  }
  return _nl_in(data, off, data.len());
}

/// Read one name-list binding at `off` without copying, after the same
/// validation as ssh2_read_name_list.
/// Params: data - buffer; off - field offset.
/// Returns: Ok(slice) with start = off + 4, len and total = 4 + len.
/// Errors: as ssh2_read_name_list.
/// Complexity: O(length).
pub fn ssh2_read_name_list_slice(data: &Vec[UInt8], off: Int) -> Result[Ssh2Slice, Str] {
  if off < 0 {
    return _err_slice("ssh2: negative offset");
  }
  let r = _slice_in(data, off, data.len(), "name-list");
  if !r.is_ok {
    return _err_slice(r.error);
  }
  let s: Ssh2Slice = r.value;
  if !_nl_span_is_valid(data, s.start, s.start + s.len) {
    return _err_slice(_at("ssh2: bad name-list", off));
  }
  return _ok_slice(s);
}

/// Copy the bytes a slice binds. Returns an empty vector when the slice's
/// bounds do not fit `data` (a slice taken from a different buffer).
/// Params: data - buffer; s - a slice from a *_slice reader.
/// Returns: the content bytes. Error case: none. Complexity: O(len).
pub fn ssh2_slice_bytes(data: &Vec[UInt8], s: &Ssh2Slice) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if s.start < 0 || s.len < 0 || s.start + s.len > data.len() {
    return out;
  }
  _copy_span(data, s.start, s.start + s.len, &mut out);
  return out;
}

// --------------------------------------------------
//  Name-list helpers (RFC 4251 section 5)
// --------------------------------------------------

// True when data[a, b) is a structurally valid name-list: empty, or
// comma-separated non-empty names of printable ASCII (0x21..0x7E).
fn _nl_span_is_valid(data: &Vec[UInt8], a: Int, b: Int) -> Bool {
  if b <= a {
    return true;
  }
  var i = a;
  while i < b {
    let ts = i;
    while i < b && _byte(data, i) != 44 {
      i = i + 1;
    }
    let te = i;
    if te <= ts {
      return false;
    }
    var k = ts;
    while k < te {
      let c = _byte(data, k);
      if c < 33 || c > 126 {
        return false;
      }
      k = k + 1;
    }
    if i < b {
      i = i + 1;
      if i >= b {
        return false;
      }
    }
  }
  return true;
}

/// True when the raw name-list bytes are structurally valid: empty, or
/// comma-separated non-empty names of printable ASCII 0x21..0x7E (so no
/// leading/trailing/double comma, no space, no control byte, no byte >= 128).
/// Params: v - raw name-list bytes. Returns: the predicate.
/// Error case: none. Complexity: O(len).
pub fn ssh2_name_list_is_valid(v: &Vec[UInt8]) -> Bool {
  return _nl_span_is_valid(v, 0, v.len());
}

/// Number of names in a raw name-list: 0 for the empty list, commas + 1
/// otherwise. This counts structurally; call ssh2_name_list_is_valid first
/// when the input is untrusted.
/// Params: v - raw name-list bytes. Returns: the count.
/// Error case: none. Complexity: O(len).
pub fn ssh2_name_list_count(v: &Vec[UInt8]) -> Int {
  if v.len() == 0 {
    return 0;
  }
  var n = 1;
  var i = 0;
  while i < v.len() {
    if _byte(v, i) == 44 {
      n = n + 1;
    }
    i = i + 1;
  }
  return n;
}

/// Copy of name `i` (0-based) from a raw name-list; an empty vector when `i`
/// is out of range or negative.
/// Params: v - raw name-list bytes; i - name index.
/// Returns: the name bytes. Error case: none. Complexity: O(len).
pub fn ssh2_name_list_name(v: &Vec[UInt8], i: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if i < 0 {
    return out;
  }
  var idx = 0;
  var pos = 0;
  while pos <= v.len() {
    let ts = pos;
    while pos < v.len() && _byte(v, pos) != 44 {
      pos = pos + 1;
    }
    let te = pos;
    if idx == i {
      _copy_span(v, ts, te, &mut out);
      return out;
    }
    idx = idx + 1;
    pos = pos + 1;
    if pos > v.len() {
      return out;
    }
  }
  return out;
}

/// True when the raw name-list contains a name byte-equal to `name`.
/// Params: v - raw name-list bytes; name - the name to find.
/// Returns: the predicate. Error case: none. Complexity: O(len).
pub fn ssh2_name_list_contains(v: &Vec[UInt8], name: &Vec[UInt8]) -> Bool {
  var pos = 0;
  while pos < v.len() {
    let ts = pos;
    while pos < v.len() && _byte(v, pos) != 44 {
      pos = pos + 1;
    }
    let te = pos;
    if te - ts == name.len() {
      if _span_eq2(v, ts, te, name, 0, name.len()) {
        return true;
      }
    }
    pos = pos + 1;
  }
  return false;
}

/// True when the raw two's-complement bytes of an mpint are negative, i.e.
/// the most significant bit of the first byte is set (RFC 4251 section 5).
/// The empty mpint (value 0) is not negative.
/// Params: v - raw mpint bytes. Returns: the predicate.
/// Error case: none. Complexity: O(1).
pub fn ssh2_mpint_is_negative(v: &Vec[UInt8]) -> Bool {
  if v.len() == 0 {
    return false;
  }
  let b0 = _byte(v, 0);
  if b0 >= 128 {
    return true;
  }
  return false;
}

// --------------------------------------------------
//  Binary packet protocol (RFC 4253 section 6)
// --------------------------------------------------

/// Parse one binary packet frame at `off`.
///
/// Checks, in order: the 4-byte length block fits ("ssh2: truncated packet
/// header"); packet_length >= 1 ("ssh2: packet length underflow");
/// packet_length <= 35000 ("ssh2: packet too long"); padding_length >= 4
/// ("ssh2: padding too short"); packet_length >= padding_length + 1
/// ("ssh2: packet length underflow"); the whole frame fits ("ssh2: truncated
/// packet payload").
///
/// The random padding bytes are bound (padding_off) but not interpreted, and
/// the MAC is NOT parsed or verified: mac_off = end. Alignment (8 or 16) is
/// not enforced because the cipher block size is a session property; use
/// ssh2_packet_is_aligned to check it.
///
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(packet) with total = 4 + packet_length consumed bytes.
/// Errors: the checks above, all "ssh2: <reason> at <off>" except the
/// negative-offset case.
/// Complexity: O(1).
pub fn ssh2_parse_packet(data: &Vec[UInt8], off: Int) -> Result[Ssh2Packet, Str] {
  if off < 0 {
    return _err_packet("ssh2: negative offset");
  }
  if off + 4 > data.len() {
    return _err_packet(_at("ssh2: truncated packet header", off));
  }
  let plen = _read_u32(data, off);
  if plen < 1 {
    return _err_packet(_at("ssh2: packet length underflow", off));
  }
  if plen > SSH2_MAX_PACKET_LENGTH {
    return _err_packet(_at("ssh2: packet too long", off));
  }
  let pad = _byte(data, off + 4);
  if pad < SSH2_MIN_PADDING {
    return _err_packet(_at("ssh2: padding too short", off));
  }
  if plen < pad + 1 {
    return _err_packet(_at("ssh2: packet length underflow", off));
  }
  if off + 4 + plen > data.len() {
    return _err_packet(_at("ssh2: truncated packet payload", off));
  }
  let payload_len = plen - pad - 1;
  return _ok_packet(Ssh2Packet{
    start: off;
    packet_length: plen;
    padding_length: pad;
    payload_off: off + 5;
    payload_len: payload_len;
    padding_off: off + 5 + payload_len;
    total: 4 + plen;
    end: off + 4 + plen;
    mac_off: off + 4 + plen;
  });
}

/// Copy of the packet payload bytes (message type included).
/// Params: data - buffer the packet came from; p - a parsed packet.
/// Returns: the payload copy; empty when the packet's bounds do not fit
/// `data`. Error case: none. Complexity: O(payload_len).
pub fn ssh2_packet_payload(data: &Vec[UInt8], p: &Ssh2Packet) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  if p.payload_off < 0 || p.payload_len < 0 || p.padding_off > data.len() {
    return out;
  }
  _copy_span(data, p.payload_off, p.padding_off, &mut out);
  return out;
}

/// True when the packet's length block (4 + packet_length bytes, MAC
/// excluded) is a multiple of `block`. RFC 4253 section 6 requires a multiple
/// of 8 (or the cipher block size) on the wire; block sizes seen in practice
/// are 8 and 16 (AES).
/// Params: p - a parsed packet; block - the alignment unit (> 0).
/// Returns: the predicate. Error case: none (block <= 0 yields false).
/// Complexity: O(1).
pub fn ssh2_packet_is_aligned(p: &Ssh2Packet, block: Int) -> Bool {
  if block <= 0 {
    return false;
  }
  if p.total % block == 0 {
    return true;
  }
  return false;
}

/// Smallest padding_length >= 4 that makes (4 + packet_length) a multiple of
/// `block`, where packet_length = 1 + payload_len + padding_length. `block`
/// is clamped up to 8 (the RFC minimum); 8 and 16 are the useful values.
/// Params: payload_len - payload byte count (>= 0); block - alignment unit.
/// Returns: the pad count in [4, block + 3]. Error case: none.
/// Complexity: O(1).
pub fn ssh2_packet_padding_for(payload_len: Int, block: Int) -> Int {
  var blk = block;
  if blk < SSH2_DEFAULT_BLOCK_SIZE {
    blk = SSH2_DEFAULT_BLOCK_SIZE;
  }
  let used = SSH2_PACKET_HEADER_LEN + payload_len;
  let rem = used % blk;
  var pad = blk - rem;
  if rem == 0 {
    pad = 0;
  }
  if pad < SSH2_MIN_PADDING {
    pad = pad + blk;
  }
  return pad;
}

/// Write one binary packet frame with the caller's padding_length. NO
/// validation and NO randomness: the caller passes an exact pad count and the
/// padding bytes are written as 0x00 (a real transport replaces them with
/// random padding before sending; this writer exists for tests and for
/// framing already-encrypted payloads). padding_length is written as one byte
/// (0..255).
/// Params: payload - payload bytes (message type included);
/// padding_len - exact pad count.
/// Returns: header + payload + zeros. Error case: none.
/// Complexity: O(payload_len + padding_len).
pub fn ssh2_write_packet(payload: &Vec[UInt8], padding_len: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  let plen = payload.len();
  let packet_length = 1 + plen + padding_len;
  ssh2_write_uint32(&mut out, packet_length);
  out.push(padding_len as UInt8);
  _push_vec(&mut out, payload);
  var i = 0;
  while i < padding_len {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

/// Write one binary packet frame with a legal, aligned padding_length chosen
/// by ssh2_packet_padding_for (zero padding bytes, no validation of payload
/// content).
/// Params: payload - payload bytes; block - alignment unit (8 or 16).
/// Returns: the frame bytes. Error case: none.
/// Complexity: O(payload_len + padding_len).
pub fn ssh2_write_packet_aligned(payload: &Vec[UInt8], block: Int) -> Vec[UInt8] {
  let pad = ssh2_packet_padding_for(payload.len(), block);
  return ssh2_write_packet(payload, pad);
}

/// Append one byte (low 8 bits of `v`).
/// Params: out - buffer; v - value. Returns: nothing. Error case: none.
pub fn ssh2_write_byte(out: &mut Vec[UInt8], v: Int) {
  out.push((v & 255) as UInt8);
}

/// Append one boolean byte (1 for true, 0 for false).
/// Params: out - buffer; b - the predicate. Returns: nothing.
/// Error case: none.
pub fn ssh2_write_boolean(out: &mut Vec[UInt8], b: Bool) {
  if b {
    out.push(1 as UInt8);
  } else {
    out.push(0 as UInt8);
  }
}

/// Append one unsigned big-endian uint32 (low 32 bits of `v`).
/// Params: out - buffer; v - value in 0..4294967295. Returns: nothing.
/// Error case: none.
pub fn ssh2_write_uint32(out: &mut Vec[UInt8], v: Int) {
  let b0 = (v / 16777216) & 255;
  let b1 = (v / 65536) & 255;
  let b2 = (v / 256) & 255;
  let b3 = v & 255;
  out.push(b0 as UInt8);
  out.push(b1 as UInt8);
  out.push(b2 as UInt8);
  out.push(b3 as UInt8);
}

/// Append one RFC 4251 string (uint32 length + raw bytes).
/// Params: out - buffer; bytes - content (binary safe, may be empty).
/// Returns: nothing. Error case: none. Complexity: O(len).
pub fn ssh2_write_string(out: &mut Vec[UInt8], bytes: &Vec[UInt8]) {
  ssh2_write_uint32(out, bytes.len());
  _push_vec(out, bytes);
}

/// Append one mpint as raw uint32-length-prefixed big-endian bytes. The
/// caller supplies the two's-complement bytes; no bignum math is performed.
/// Params: out - buffer; bytes - raw mpint bytes (may be empty = zero).
/// Returns: nothing. Error case: none. Complexity: O(len).
pub fn ssh2_write_mpint(out: &mut Vec[UInt8], bytes: &Vec[UInt8]) {
  ssh2_write_uint32(out, bytes.len());
  _push_vec(out, bytes);
}

/// Append one name-list (uint32 length + raw comma-joined bytes). The caller
/// supplies the joined form; build it and validate it with
/// ssh2_name_list_is_valid.
/// Params: out - buffer; list - raw comma-joined names (may be empty).
/// Returns: nothing. Error case: none. Complexity: O(len).
pub fn ssh2_write_name_list(out: &mut Vec[UInt8], list: &Vec[UInt8]) {
  ssh2_write_uint32(out, list.len());
  _push_vec(out, list);
}

// --------------------------------------------------
//  Message parsing (one message at a time)
// --------------------------------------------------

/// Parse one binary packet at `off` as an SSH message and return its
/// envelope: frame, message type, known flag and a verbatim payload copy in
/// `raw` (message type byte included). Known message numbers are additionally
/// validated by running the matching typed parser; a structural error inside
/// the body is returned here with the parser's byte offset. Unknown message
/// numbers are preserved raw with known = false and are not an error.
///
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(message) with total = 4 + packet_length (the number of bytes
/// to advance); the MAC, when present, is not consumed.
/// Errors: the packet errors; "ssh2: empty payload at <off>" when
/// packet_length leaves no payload byte; and any typed-parser error for a
/// known message number.
/// Complexity: O(payload_len).
pub fn ssh2_parse_message(data: &Vec[UInt8], off: Int) -> Result[Ssh2Message, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_message(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_message(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  let known = ssh2_message_type_known(mt);
  var raw = Vec[UInt8].new();
  _copy_span(data, p.payload_off, p.padding_off, &mut raw);
  if known {
    let vr = _validate_message(data, off, mt);
    if !vr.is_ok {
      return _err_message(vr.error);
    }
  }
  return _ok_message(Ssh2Message{
    msg_type: mt;
    known: known;
    start: off;
    payload_off: p.payload_off;
    payload_len: p.payload_len;
    body_off: p.payload_off + 1;
    body_len: p.payload_len - 1;
    total: p.total;
    packet_length: p.packet_length;
    padding_length: p.padding_length;
    mac_off: p.mac_off;
    raw: raw;
  });
}

// Validate a message number 30 body: exactly one length-prefixed blob
// (classic DH mpint e or ECDH string Q_C; the byte shape is identical).
fn _validate_blob1(data: &Vec[UInt8], off: Int) -> Result[Unit, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_unit(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_unit(_at("ssh2: empty payload", off));
  }
  let r = _bytes_in(data, p.payload_off + 1, p.padding_off, "string");
  if !r.is_ok {
    return _err_unit(r.error);
  }
  let v: Vec[UInt8] = r.value;
  let cur = p.payload_off + 1 + 4 + v.len();
  if cur != p.padding_off {
    return _err_unit(_at("ssh2: trailing bytes", cur));
  }
  return _ok_unit();
}

// Validate a message number 31 body: three strings (host key, mpint/string
// value, signature).
fn _validate_blob3(data: &Vec[UInt8], off: Int) -> Result[Unit, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_unit(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_unit(_at("ssh2: empty payload", off));
  }
  var cur = p.payload_off + 1;
  let r1 = _bytes_in(data, cur, p.padding_off, "string");
  if !r1.is_ok {
    return _err_unit(r1.error);
  }
  let v1: Vec[UInt8] = r1.value;
  cur = cur + 4 + v1.len();
  let r2 = _bytes_in(data, cur, p.padding_off, "string");
  if !r2.is_ok {
    return _err_unit(r2.error);
  }
  let v2: Vec[UInt8] = r2.value;
  cur = cur + 4 + v2.len();
  let r3 = _bytes_in(data, cur, p.padding_off, "string");
  if !r3.is_ok {
    return _err_unit(r3.error);
  }
  let v3: Vec[UInt8] = r3.value;
  cur = cur + 4 + v3.len();
  if cur != p.padding_off {
    return _err_unit(_at("ssh2: trailing bytes", cur));
  }
  return _ok_unit();
}

// Structural validation dispatch used by ssh2_parse_message: every known
// message number is parsed with its typed parser and a structural error is
// propagated (unknown numbers never reach here).
fn _validate_message(data: &Vec[UInt8], off: Int, mt: Int) -> Result[Unit, Str] {
  if mt == SSH_MSG_DISCONNECT {
    let r = ssh2_parse_disconnect(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_IGNORE {
    let r = ssh2_parse_ignore(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_UNIMPLEMENTED {
    let r = ssh2_parse_unimplemented(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_DEBUG {
    let r = ssh2_parse_debug(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_SERVICE_REQUEST {
    let r = ssh2_parse_service_request(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_SERVICE_ACCEPT {
    let r = ssh2_parse_service_accept(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_KEXINIT {
    let r = ssh2_parse_kexinit(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_NEWKEYS {
    return ssh2_parse_newkeys(data, off);
  }
  if mt == SSH_MSG_KEXDH_INIT {
    return _validate_blob1(data, off);
  }
  if mt == SSH_MSG_KEXDH_REPLY {
    return _validate_blob3(data, off);
  }
  if mt == SSH_MSG_USERAUTH_REQUEST {
    let r = ssh2_parse_userauth_request(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_USERAUTH_FAILURE {
    let r = ssh2_parse_userauth_failure(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_USERAUTH_SUCCESS {
    return ssh2_parse_userauth_success(data, off);
  }
  if mt == SSH_MSG_USERAUTH_BANNER {
    let r = ssh2_parse_banner(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_GLOBAL_REQUEST {
    let r = ssh2_parse_global_request(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_REQUEST_SUCCESS {
    let r = ssh2_parse_request_success(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_REQUEST_FAILURE {
    return ssh2_parse_request_failure(data, off);
  }
  if mt == SSH_MSG_CHANNEL_OPEN {
    let r = ssh2_parse_channel_open(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_OPEN_CONFIRMATION {
    let r = ssh2_parse_channel_open_confirmation(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_OPEN_FAILURE {
    let r = ssh2_parse_channel_open_failure(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_WINDOW_ADJUST {
    let r = ssh2_parse_window_adjust(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_DATA {
    let r = ssh2_parse_channel_data(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_EXTENDED_DATA {
    let r = ssh2_parse_channel_extended_data(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_EOF {
    let r = ssh2_parse_channel_eof(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_CLOSE {
    let r = ssh2_parse_channel_close(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_REQUEST {
    let r = ssh2_parse_channel_request(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_SUCCESS {
    let r = ssh2_parse_channel_success(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  if mt == SSH_MSG_CHANNEL_FAILURE {
    let r = ssh2_parse_channel_failure(data, off);
    if !r.is_ok {
      return _err_unit(r.error);
    }
    return _ok_unit();
  }
  return _err_unit(_at("ssh2: unknown message type", off));
}

// --------------------------------------------------
//  Typed message parsers
// --------------------------------------------------
//
// Each parser takes the whole buffer and the packet offset, re-parses the
// frame, requires its own message number and then decodes the body. Fixed
// shape messages reject trailing bytes ("ssh2: trailing bytes at <offset>");
// messages with an open-ended tail (global request data, unknown channel
// types / request types / userauth methods, channel open confirmation
// type-specific data) copy that tail into the result instead.

/// Parse an SSH_MSG_DISCONNECT (1) body: uint32 reason + string description +
/// string language tag.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(disconnect).
/// Errors: packet errors; "ssh2: empty payload at <off>"; "ssh2: not a
/// disconnect message at <off>"; field truncation errors; "ssh2: trailing
/// bytes at <offset>".
/// Complexity: O(body length).
pub fn ssh2_parse_disconnect(data: &Vec[UInt8], off: Int) -> Result[Ssh2Disconnect, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_disconnect(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_disconnect(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_DISCONNECT {
    return _err_disconnect(_at("ssh2: not a disconnect message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let rr = _u32_in(data, body, end);
  if !rr.is_ok {
    return _err_disconnect(rr.error);
  }
  let reason: Int = rr.value;
  var cur = body + 4;
  let dr = _bytes_in(data, cur, end, "string");
  if !dr.is_ok {
    return _err_disconnect(dr.error);
  }
  let desc: Vec[UInt8] = dr.value;
  cur = cur + 4 + desc.len();
  let lr = _bytes_in(data, cur, end, "string");
  if !lr.is_ok {
    return _err_disconnect(lr.error);
  }
  let lang: Vec[UInt8] = lr.value;
  cur = cur + 4 + lang.len();
  if cur != end {
    return _err_disconnect(_at("ssh2: trailing bytes", cur));
  }
  return _ok_disconnect(Ssh2Disconnect{ reason: reason; description: desc; language: lang; total: p.total; });
}

/// Parse an SSH_MSG_IGNORE (2) body: string data (any bytes).
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(ignore).
/// Errors: packet errors; empty payload; "ssh2: not an ignore message at
/// <off>"; string truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_ignore(data: &Vec[UInt8], off: Int) -> Result[Ssh2Ignore, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_ignore(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_ignore(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_IGNORE {
    return _err_ignore(_at("ssh2: not an ignore message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let dr = _bytes_in(data, body, end, "string");
  if !dr.is_ok {
    return _err_ignore(dr.error);
  }
  let v: Vec[UInt8] = dr.value;
  let cur = body + 4 + v.len();
  if cur != end {
    return _err_ignore(_at("ssh2: trailing bytes", cur));
  }
  return _ok_ignore(Ssh2Ignore{ data: v; total: p.total; });
}

/// Parse an SSH_MSG_UNIMPLEMENTED (3) body: uint32 sequence number.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(unimplemented).
/// Errors: packet errors; empty payload; "ssh2: not an unimplemented message
/// at <off>"; uint32 truncation; trailing bytes.
/// Complexity: O(1).
pub fn ssh2_parse_unimplemented(data: &Vec[UInt8], off: Int) -> Result[Ssh2Unimplemented, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_unimplemented(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_unimplemented(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_UNIMPLEMENTED {
    return _err_unimplemented(_at("ssh2: not an unimplemented message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let rr = _u32_in(data, body, end);
  if !rr.is_ok {
    return _err_unimplemented(rr.error);
  }
  let seq: Int = rr.value;
  if body + 4 != end {
    return _err_unimplemented(_at("ssh2: trailing bytes", body + 4));
  }
  return _ok_unimplemented(Ssh2Unimplemented{ sequence: seq; total: p.total; });
}

/// Parse an SSH_MSG_DEBUG (4) body: boolean always_display + string message +
/// string language tag.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(debug).
/// Errors: packet errors; empty payload; "ssh2: not a debug message at
/// <off>"; field truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_debug(data: &Vec[UInt8], off: Int) -> Result[Ssh2Debug, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_debug(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_debug(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_DEBUG {
    return _err_debug(_at("ssh2: not a debug message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let br = _bool_in(data, body, end);
  if !br.is_ok {
    return _err_debug(br.error);
  }
  let always: Bool = br.value;
  var cur = body + 1;
  let mr = _bytes_in(data, cur, end, "string");
  if !mr.is_ok {
    return _err_debug(mr.error);
  }
  let msg: Vec[UInt8] = mr.value;
  cur = cur + 4 + msg.len();
  let lr = _bytes_in(data, cur, end, "string");
  if !lr.is_ok {
    return _err_debug(lr.error);
  }
  let lang: Vec[UInt8] = lr.value;
  cur = cur + 4 + lang.len();
  if cur != end {
    return _err_debug(_at("ssh2: trailing bytes", cur));
  }
  return _ok_debug(Ssh2Debug{ always_display: always; message: msg; language: lang; total: p.total; });
}

/// Parse an SSH_MSG_KEXINIT (20) body: 16-byte cookie + ten name-lists +
/// boolean first_kex_packet_follows + uint32 reserved.
///
/// Every list is validated as a name-list; the eight algorithm lists (kex,
/// host key, encryption c2s/s2c, MAC c2s/s2c, compression c2s/s2c) must be
/// non-empty ("ssh2: empty algorithm name-list at <offset>"); the two
/// language lists may be empty. first_kex_packet_follows and reserved are
/// returned as-is; guessing semantics are the caller's business.
///
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(kexinit).
/// Errors: packet errors; empty payload; "ssh2: not a kexinit message at
/// <off>"; "ssh2: truncated cookie at <offset>"; name-list errors; "ssh2:
/// empty algorithm name-list at <offset>"; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_kexinit(data: &Vec[UInt8], off: Int) -> Result[Ssh2KexInit, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_kexinit(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_kexinit(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_KEXINIT {
    return _err_kexinit(_at("ssh2: not a kexinit message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  if body + 16 > end {
    return _err_kexinit(_at("ssh2: truncated cookie", body));
  }
  var cookie = Vec[UInt8].new();
  _copy_span(data, body, body + 16, &mut cookie);
  var cur = body + 16;
  let k1 = _nl_in(data, cur, end);
  if !k1.is_ok {
    return _err_kexinit(k1.error);
  }
  let kex: Vec[UInt8] = k1.value;
  if kex.len() == 0 {
    return _err_kexinit(_at("ssh2: empty algorithm name-list", cur));
  }
  cur = cur + 4 + kex.len();
  let k2 = _nl_in(data, cur, end);
  if !k2.is_ok {
    return _err_kexinit(k2.error);
  }
  let hk: Vec[UInt8] = k2.value;
  if hk.len() == 0 {
    return _err_kexinit(_at("ssh2: empty algorithm name-list", cur));
  }
  cur = cur + 4 + hk.len();
  let k3 = _nl_in(data, cur, end);
  if !k3.is_ok {
    return _err_kexinit(k3.error);
  }
  let enc_c2s: Vec[UInt8] = k3.value;
  if enc_c2s.len() == 0 {
    return _err_kexinit(_at("ssh2: empty algorithm name-list", cur));
  }
  cur = cur + 4 + enc_c2s.len();
  let k4 = _nl_in(data, cur, end);
  if !k4.is_ok {
    return _err_kexinit(k4.error);
  }
  let enc_s2c: Vec[UInt8] = k4.value;
  if enc_s2c.len() == 0 {
    return _err_kexinit(_at("ssh2: empty algorithm name-list", cur));
  }
  cur = cur + 4 + enc_s2c.len();
  let k5 = _nl_in(data, cur, end);
  if !k5.is_ok {
    return _err_kexinit(k5.error);
  }
  let mac_c2s: Vec[UInt8] = k5.value;
  if mac_c2s.len() == 0 {
    return _err_kexinit(_at("ssh2: empty algorithm name-list", cur));
  }
  cur = cur + 4 + mac_c2s.len();
  let k6 = _nl_in(data, cur, end);
  if !k6.is_ok {
    return _err_kexinit(k6.error);
  }
  let mac_s2c: Vec[UInt8] = k6.value;
  if mac_s2c.len() == 0 {
    return _err_kexinit(_at("ssh2: empty algorithm name-list", cur));
  }
  cur = cur + 4 + mac_s2c.len();
  let k7 = _nl_in(data, cur, end);
  if !k7.is_ok {
    return _err_kexinit(k7.error);
  }
  let comp_c2s: Vec[UInt8] = k7.value;
  if comp_c2s.len() == 0 {
    return _err_kexinit(_at("ssh2: empty algorithm name-list", cur));
  }
  cur = cur + 4 + comp_c2s.len();
  let k8 = _nl_in(data, cur, end);
  if !k8.is_ok {
    return _err_kexinit(k8.error);
  }
  let comp_s2c: Vec[UInt8] = k8.value;
  if comp_s2c.len() == 0 {
    return _err_kexinit(_at("ssh2: empty algorithm name-list", cur));
  }
  cur = cur + 4 + comp_s2c.len();
  let k9 = _nl_in(data, cur, end);
  if !k9.is_ok {
    return _err_kexinit(k9.error);
  }
  let lang_c2s: Vec[UInt8] = k9.value;
  cur = cur + 4 + lang_c2s.len();
  let k10 = _nl_in(data, cur, end);
  if !k10.is_ok {
    return _err_kexinit(k10.error);
  }
  let lang_s2c: Vec[UInt8] = k10.value;
  cur = cur + 4 + lang_s2c.len();
  let br = _bool_in(data, cur, end);
  if !br.is_ok {
    return _err_kexinit(br.error);
  }
  let follows: Bool = br.value;
  cur = cur + 1;
  let rr = _u32_in(data, cur, end);
  if !rr.is_ok {
    return _err_kexinit(rr.error);
  }
  let reserved: Int = rr.value;
  cur = cur + 4;
  if cur != end {
    return _err_kexinit(_at("ssh2: trailing bytes", cur));
  }
  return _ok_kexinit(Ssh2KexInit{
    cookie: cookie;
    kex_algorithms: kex;
    host_key_algorithms: hk;
    encryption_c2s: enc_c2s;
    encryption_s2c: enc_s2c;
    mac_c2s: mac_c2s;
    mac_s2c: mac_s2c;
    compression_c2s: comp_c2s;
    compression_s2c: comp_s2c;
    languages_c2s: lang_c2s;
    languages_s2c: lang_s2c;
    first_kex_packet_follows: follows;
    reserved: reserved;
    total: p.total;
  });
}

/// Parse an SSH_MSG_NEWKEYS (21) body, which is empty.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(()).
/// Errors: packet errors; empty payload; "ssh2: not a newkeys message at
/// <off>"; "ssh2: trailing bytes at <offset>".
/// Complexity: O(1).
pub fn ssh2_parse_newkeys(data: &Vec[UInt8], off: Int) -> Result[Unit, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_unit(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_unit(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_NEWKEYS {
    return _err_unit(_at("ssh2: not a newkeys message", off));
  }
  let body = p.payload_off + 1;
  if body != p.padding_off {
    return _err_unit(_at("ssh2: trailing bytes", body));
  }
  return _ok_unit();
}

/// Parse an SSH_MSG_KEXDH_INIT (30) body: mpint e, raw. The classic DH check
/// rejects a negative value ("ssh2: negative DH value at <offset>"): e must
/// be a positive mpint (a leading 0x00 byte when the MSB of the value is
/// set).
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(init) with the raw mpint bytes in e.
/// Errors: packet errors; empty payload; "ssh2: not a kexdh init message at
/// <off>"; mpint truncation; negative DH value; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_kexdh_init(data: &Vec[UInt8], off: Int) -> Result[Ssh2KexDhInit, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_kexdh_init(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_kexdh_init(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_KEXDH_INIT {
    return _err_kexdh_init(_at("ssh2: not a kexdh init message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let er = _bytes_in(data, body, end, "mpint");
  if !er.is_ok {
    return _err_kexdh_init(er.error);
  }
  let e: Vec[UInt8] = er.value;
  if ssh2_mpint_is_negative(&e) {
    return _err_kexdh_init(_at("ssh2: negative DH value", body));
  }
  let cur = body + 4 + e.len();
  if cur != end {
    return _err_kexdh_init(_at("ssh2: trailing bytes", cur));
  }
  return _ok_kexdh_init(Ssh2KexDhInit{ e: e; total: p.total; });
}

/// Parse an SSH_MSG_KEXDH_REPLY (31) body: string K_S host key + mpint f +
/// string signature. The classic DH check rejects a negative f ("ssh2:
/// negative DH value at <offset>").
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(reply) with host_key, value = raw f and signature.
/// Errors: packet errors; empty payload; "ssh2: not a kexdh reply message at
/// <off>"; string/mpint truncation; negative DH value; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_kexdh_reply(data: &Vec[UInt8], off: Int) -> Result[Ssh2KexReply, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_kexreply(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_kexreply(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_KEXDH_REPLY {
    return _err_kexreply(_at("ssh2: not a kexdh reply message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let hr = _bytes_in(data, body, end, "string");
  if !hr.is_ok {
    return _err_kexreply(hr.error);
  }
  let hk: Vec[UInt8] = hr.value;
  var cur = body + 4 + hk.len();
  let fr = _bytes_in(data, cur, end, "mpint");
  if !fr.is_ok {
    return _err_kexreply(fr.error);
  }
  let f: Vec[UInt8] = fr.value;
  if ssh2_mpint_is_negative(&f) {
    return _err_kexreply(_at("ssh2: negative DH value", cur));
  }
  cur = cur + 4 + f.len();
  let sr = _bytes_in(data, cur, end, "string");
  if !sr.is_ok {
    return _err_kexreply(sr.error);
  }
  let sig: Vec[UInt8] = sr.value;
  cur = cur + 4 + sig.len();
  if cur != end {
    return _err_kexreply(_at("ssh2: trailing bytes", cur));
  }
  return _ok_kexreply(Ssh2KexReply{ host_key: hk; value: f; signature: sig; total: p.total; });
}

/// Parse an SSH_MSG_KEX_ECDH_INIT (30) body: string Q_C, raw (no sign check;
/// Q_C is an encoded EC point, not an mpint).
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(init) with q_c raw.
/// Errors: packet errors; empty payload; "ssh2: not an ecdh init message at
/// <off>"; string truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_kex_ecdh_init(data: &Vec[UInt8], off: Int) -> Result[Ssh2KexEcdhInit, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_kexecdh_init(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_kexecdh_init(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_KEX_ECDH_INIT {
    return _err_kexecdh_init(_at("ssh2: not an ecdh init message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let qr = _bytes_in(data, body, end, "string");
  if !qr.is_ok {
    return _err_kexecdh_init(qr.error);
  }
  let q: Vec[UInt8] = qr.value;
  let cur = body + 4 + q.len();
  if cur != end {
    return _err_kexecdh_init(_at("ssh2: trailing bytes", cur));
  }
  return _ok_kexecdh_init(Ssh2KexEcdhInit{ q_c: q; total: p.total; });
}

/// Parse an SSH_MSG_KEX_ECDH_REPLY (31) body: string K_S + string Q_S +
/// string signature, all raw.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(reply) with host_key, value = raw Q_S and signature.
/// Errors: packet errors; empty payload; "ssh2: not an ecdh reply message at
/// <off>"; string truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_kex_ecdh_reply(data: &Vec[UInt8], off: Int) -> Result[Ssh2KexReply, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_kexreply(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_kexreply(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_KEX_ECDH_REPLY {
    return _err_kexreply(_at("ssh2: not an ecdh reply message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let hr = _bytes_in(data, body, end, "string");
  if !hr.is_ok {
    return _err_kexreply(hr.error);
  }
  let hk: Vec[UInt8] = hr.value;
  var cur = body + 4 + hk.len();
  let qr = _bytes_in(data, cur, end, "string");
  if !qr.is_ok {
    return _err_kexreply(qr.error);
  }
  let q: Vec[UInt8] = qr.value;
  cur = cur + 4 + q.len();
  let sr = _bytes_in(data, cur, end, "string");
  if !sr.is_ok {
    return _err_kexreply(sr.error);
  }
  let sig: Vec[UInt8] = sr.value;
  cur = cur + 4 + sig.len();
  if cur != end {
    return _err_kexreply(_at("ssh2: trailing bytes", cur));
  }
  return _ok_kexreply(Ssh2KexReply{ host_key: hk; value: q; signature: sig; total: p.total; });
}

/// Parse an SSH_MSG_SERVICE_REQUEST (5) body: string service name.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(service).
/// Errors: packet errors; empty payload; "ssh2: not a service request
/// message at <off>"; string truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_service_request(data: &Vec[UInt8], off: Int) -> Result[Ssh2Service, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_service(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_service(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_SERVICE_REQUEST {
    return _err_service(_at("ssh2: not a service request message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let sr = _bytes_in(data, body, end, "string");
  if !sr.is_ok {
    return _err_service(sr.error);
  }
  let svc: Vec[UInt8] = sr.value;
  let cur = body + 4 + svc.len();
  if cur != end {
    return _err_service(_at("ssh2: trailing bytes", cur));
  }
  return _ok_service(Ssh2Service{ service: svc; total: p.total; });
}

/// Parse an SSH_MSG_SERVICE_ACCEPT (6) body: string service name.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(service).
/// Errors: packet errors; empty payload; "ssh2: not a service accept message
/// at <off>"; string truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_service_accept(data: &Vec[UInt8], off: Int) -> Result[Ssh2Service, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_service(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_service(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_SERVICE_ACCEPT {
    return _err_service(_at("ssh2: not a service accept message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let sr = _bytes_in(data, body, end, "string");
  if !sr.is_ok {
    return _err_service(sr.error);
  }
  let svc: Vec[UInt8] = sr.value;
  let cur = body + 4 + svc.len();
  if cur != end {
    return _err_service(_at("ssh2: trailing bytes", cur));
  }
  return _ok_service(Ssh2Service{ service: svc; total: p.total; });
}

/// Parse an SSH_MSG_USERAUTH_REQUEST (50) body: string user name + string
/// service name + string method, then the method-specific fields.
///
/// "password": boolean change; without change `secret` is the password;
/// with change `old_password` is the old password and `secret` the new one.
/// "publickey": boolean has_signature + string algorithm + string key blob
/// (`secret`), plus string signature when has_signature.
/// Every other method stays raw in `extra` with decoded = false.
///
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(request).
/// Errors: packet errors; empty payload; "ssh2: not a userauth request
/// message at <off>"; string/boolean truncation; trailing bytes for the
/// decoded methods.
/// Complexity: O(body length).
pub fn ssh2_parse_userauth_request(data: &Vec[UInt8], off: Int) -> Result[Ssh2UserAuthRequest, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_userauth_req(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_userauth_req(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_USERAUTH_REQUEST {
    return _err_userauth_req(_at("ssh2: not a userauth request message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let ur = _bytes_in(data, body, end, "string");
  if !ur.is_ok {
    return _err_userauth_req(ur.error);
  }
  let user: Vec[UInt8] = ur.value;
  var cur = body + 4 + user.len();
  let sr = _bytes_in(data, cur, end, "string");
  if !sr.is_ok {
    return _err_userauth_req(sr.error);
  }
  let svc: Vec[UInt8] = sr.value;
  cur = cur + 4 + svc.len();
  let mr = _bytes_in(data, cur, end, "string");
  if !mr.is_ok {
    return _err_userauth_req(mr.error);
  }
  let method: Vec[UInt8] = mr.value;
  cur = cur + 4 + method.len();
  var decoded = false;
  var change = false;
  var has_sig = false;
  var algorithm = Vec[UInt8].new();
  var secret = Vec[UInt8].new();
  var signature = Vec[UInt8].new();
  var old_password = Vec[UInt8].new();
  var extra = Vec[UInt8].new();
  if _vec_eq_lit(&method, "password") {
    let br = _bool_in(data, cur, end);
    if !br.is_ok {
      return _err_userauth_req(br.error);
    }
    change = br.value;
    cur = cur + 1;
    let p1 = _bytes_in(data, cur, end, "string");
    if !p1.is_ok {
      return _err_userauth_req(p1.error);
    }
    let first: Vec[UInt8] = p1.value;
    cur = cur + 4 + first.len();
    decoded = true;
    if change {
      old_password = first;
      let p2 = _bytes_in(data, cur, end, "string");
      if !p2.is_ok {
        return _err_userauth_req(p2.error);
      }
      secret = p2.value;
      cur = cur + 4 + secret.len();
    } else {
      secret = first;
    }
    if cur != end {
      return _err_userauth_req(_at("ssh2: trailing bytes", cur));
    }
  } else {
    if _vec_eq_lit(&method, "publickey") {
      let br = _bool_in(data, cur, end);
      if !br.is_ok {
        return _err_userauth_req(br.error);
      }
      has_sig = br.value;
      cur = cur + 1;
      let ar = _bytes_in(data, cur, end, "string");
      if !ar.is_ok {
        return _err_userauth_req(ar.error);
      }
      algorithm = ar.value;
      cur = cur + 4 + algorithm.len();
      let kr = _bytes_in(data, cur, end, "string");
      if !kr.is_ok {
        return _err_userauth_req(kr.error);
      }
      secret = kr.value;
      cur = cur + 4 + secret.len();
      decoded = true;
      if has_sig {
        let xr = _bytes_in(data, cur, end, "string");
        if !xr.is_ok {
          return _err_userauth_req(xr.error);
        }
        signature = xr.value;
        cur = cur + 4 + signature.len();
      }
      if cur != end {
        return _err_userauth_req(_at("ssh2: trailing bytes", cur));
      }
    } else {
      _copy_span(data, cur, end, &mut extra);
    }
  }
  return _ok_userauth_req(Ssh2UserAuthRequest{
    user: user;
    service: svc;
    method: method;
    decoded: decoded;
    change_password: change;
    has_signature: has_sig;
    algorithm: algorithm;
    secret: secret;
    signature: signature;
    old_password: old_password;
    extra: extra;
    total: p.total;
  });
}

/// Parse an SSH_MSG_USERAUTH_FAILURE (51) body: name-list of methods that
/// can continue + boolean partial success. The name-list may be empty.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(failure).
/// Errors: packet errors; empty payload; "ssh2: not a userauth failure
/// message at <off>"; name-list errors; boolean truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_userauth_failure(data: &Vec[UInt8], off: Int) -> Result[Ssh2UserAuthFailure, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_userauth_fail(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_userauth_fail(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_USERAUTH_FAILURE {
    return _err_userauth_fail(_at("ssh2: not a userauth failure message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let nr = _nl_in(data, body, end);
  if !nr.is_ok {
    return _err_userauth_fail(nr.error);
  }
  let methods: Vec[UInt8] = nr.value;
  var cur = body + 4 + methods.len();
  let br = _bool_in(data, cur, end);
  if !br.is_ok {
    return _err_userauth_fail(br.error);
  }
  let partial: Bool = br.value;
  cur = cur + 1;
  if cur != end {
    return _err_userauth_fail(_at("ssh2: trailing bytes", cur));
  }
  return _ok_userauth_fail(Ssh2UserAuthFailure{ methods: methods; partial: partial; total: p.total; });
}

/// Parse an SSH_MSG_USERAUTH_SUCCESS (52) body, which is empty.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(()).
/// Errors: packet errors; empty payload; "ssh2: not a userauth success
/// message at <off>"; trailing bytes.
/// Complexity: O(1).
pub fn ssh2_parse_userauth_success(data: &Vec[UInt8], off: Int) -> Result[Unit, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_unit(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_unit(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_USERAUTH_SUCCESS {
    return _err_unit(_at("ssh2: not a userauth success message", off));
  }
  let body = p.payload_off + 1;
  if body != p.padding_off {
    return _err_unit(_at("ssh2: trailing bytes", body));
  }
  return _ok_unit();
}

/// Parse an SSH_MSG_USERAUTH_BANNER (53) body: string message + string
/// language tag.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(banner).
/// Errors: packet errors; empty payload; "ssh2: not a banner message at
/// <off>"; string truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_banner(data: &Vec[UInt8], off: Int) -> Result[Ssh2Banner, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_banner(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_banner(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_USERAUTH_BANNER {
    return _err_banner(_at("ssh2: not a banner message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let mr = _bytes_in(data, body, end, "string");
  if !mr.is_ok {
    return _err_banner(mr.error);
  }
  let msg: Vec[UInt8] = mr.value;
  var cur = body + 4 + msg.len();
  let lr = _bytes_in(data, cur, end, "string");
  if !lr.is_ok {
    return _err_banner(lr.error);
  }
  let lang: Vec[UInt8] = lr.value;
  cur = cur + 4 + lang.len();
  if cur != end {
    return _err_banner(_at("ssh2: trailing bytes", cur));
  }
  return _ok_banner(Ssh2Banner{ message: msg; language: lang; total: p.total; });
}

/// Parse an SSH_MSG_GLOBAL_REQUEST (80) body: string request name + boolean
/// want_reply + raw request-specific data (possibly empty, preserved in
/// `data`).
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(request).
/// Errors: packet errors; empty payload; "ssh2: not a global request message
/// at <off>"; string/boolean truncation.
/// Complexity: O(body length).
pub fn ssh2_parse_global_request(data: &Vec[UInt8], off: Int) -> Result[Ssh2GlobalRequest, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_global_req(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_global_req(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_GLOBAL_REQUEST {
    return _err_global_req(_at("ssh2: not a global request message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let nr = _bytes_in(data, body, end, "string");
  if !nr.is_ok {
    return _err_global_req(nr.error);
  }
  let name: Vec[UInt8] = nr.value;
  var cur = body + 4 + name.len();
  let br = _bool_in(data, cur, end);
  if !br.is_ok {
    return _err_global_req(br.error);
  }
  let want: Bool = br.value;
  cur = cur + 1;
  var extra = Vec[UInt8].new();
  _copy_span(data, cur, end, &mut extra);
  return _ok_global_req(Ssh2GlobalRequest{ name: name; want_reply: want; data: extra; total: p.total; });
}

/// Parse an SSH_MSG_REQUEST_SUCCESS (81) body: raw response data (possibly
/// empty, preserved in `data`).
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(success).
/// Errors: packet errors; empty payload; "ssh2: not a request success
/// message at <off>".
/// Complexity: O(body length).
pub fn ssh2_parse_request_success(data: &Vec[UInt8], off: Int) -> Result[Ssh2RequestSuccess, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_req_success(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_req_success(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_REQUEST_SUCCESS {
    return _err_req_success(_at("ssh2: not a request success message", off));
  }
  let body = p.payload_off + 1;
  var extra = Vec[UInt8].new();
  _copy_span(data, body, p.padding_off, &mut extra);
  return _ok_req_success(Ssh2RequestSuccess{ data: extra; total: p.total; });
}

/// Parse an SSH_MSG_REQUEST_FAILURE (82) body, which is empty.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(()).
/// Errors: packet errors; empty payload; "ssh2: not a request failure
/// message at <off>"; trailing bytes.
/// Complexity: O(1).
pub fn ssh2_parse_request_failure(data: &Vec[UInt8], off: Int) -> Result[Unit, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_unit(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_unit(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_REQUEST_FAILURE {
    return _err_unit(_at("ssh2: not a request failure message", off));
  }
  let body = p.payload_off + 1;
  if body != p.padding_off {
    return _err_unit(_at("ssh2: trailing bytes", body));
  }
  return _ok_unit();
}

/// Parse an SSH_MSG_CHANNEL_OPEN (90) body: string channel type + uint32
/// sender channel + uint32 initial window size + uint32 maximum packet size +
/// type-specific fields.
///
/// Decoded types: "session" (no fields), "direct-tcpip" and
/// "forwarded-tcpip" (string address + uint32 port + string originator
/// address + uint32 originator port; for direct-tcpip the address/port is the
/// host to connect and the originator is the client, for forwarded-tcpip the
/// address/port is the connected side). Any other type keeps its raw tail in
/// `extra` with decoded = false.
///
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(open).
/// Errors: packet errors; empty payload; "ssh2: not a channel open message
/// at <off>"; field truncation; trailing bytes for decoded types.
/// Complexity: O(body length).
pub fn ssh2_parse_channel_open(data: &Vec[UInt8], off: Int) -> Result[Ssh2ChannelOpen, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_channel_open(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_channel_open(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_OPEN {
    return _err_channel_open(_at("ssh2: not a channel open message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let tr = _bytes_in(data, body, end, "string");
  if !tr.is_ok {
    return _err_channel_open(tr.error);
  }
  let ctype: Vec[UInt8] = tr.value;
  var cur = body + 4 + ctype.len();
  let sr = _u32_in(data, cur, end);
  if !sr.is_ok {
    return _err_channel_open(sr.error);
  }
  let sender: Int = sr.value;
  cur = cur + 4;
  let wr = _u32_in(data, cur, end);
  if !wr.is_ok {
    return _err_channel_open(wr.error);
  }
  let window: Int = wr.value;
  cur = cur + 4;
  let xr = _u32_in(data, cur, end);
  if !xr.is_ok {
    return _err_channel_open(xr.error);
  }
  let maxp: Int = xr.value;
  cur = cur + 4;
  var decoded = false;
  var host = Vec[UInt8].new();
  var origin = Vec[UInt8].new();
  var extra = Vec[UInt8].new();
  var port = 0;
  var oport = 0;
  if _vec_eq_lit(&ctype, "session") {
    decoded = true;
    if cur != end {
      return _err_channel_open(_at("ssh2: trailing bytes", cur));
    }
  } else {
    if _vec_eq_lit(&ctype, "direct-tcpip") {
      let h1 = _bytes_in(data, cur, end, "string");
      if !h1.is_ok {
        return _err_channel_open(h1.error);
      }
      host = h1.value;
      cur = cur + 4 + host.len();
      let p1 = _u32_in(data, cur, end);
      if !p1.is_ok {
        return _err_channel_open(p1.error);
      }
      port = p1.value;
      cur = cur + 4;
      let h2 = _bytes_in(data, cur, end, "string");
      if !h2.is_ok {
        return _err_channel_open(h2.error);
      }
      origin = h2.value;
      cur = cur + 4 + origin.len();
      let p2 = _u32_in(data, cur, end);
      if !p2.is_ok {
        return _err_channel_open(p2.error);
      }
      oport = p2.value;
      cur = cur + 4;
      decoded = true;
      if cur != end {
        return _err_channel_open(_at("ssh2: trailing bytes", cur));
      }
    } else {
      if _vec_eq_lit(&ctype, "forwarded-tcpip") {
        let h1 = _bytes_in(data, cur, end, "string");
        if !h1.is_ok {
          return _err_channel_open(h1.error);
        }
        host = h1.value;
        cur = cur + 4 + host.len();
        let p1 = _u32_in(data, cur, end);
        if !p1.is_ok {
          return _err_channel_open(p1.error);
        }
        port = p1.value;
        cur = cur + 4;
        let h2 = _bytes_in(data, cur, end, "string");
        if !h2.is_ok {
          return _err_channel_open(h2.error);
        }
        origin = h2.value;
        cur = cur + 4 + origin.len();
        let p2 = _u32_in(data, cur, end);
        if !p2.is_ok {
          return _err_channel_open(p2.error);
        }
        oport = p2.value;
        cur = cur + 4;
        decoded = true;
        if cur != end {
          return _err_channel_open(_at("ssh2: trailing bytes", cur));
        }
      } else {
        _copy_span(data, cur, end, &mut extra);
      }
    }
  }
  return _ok_channel_open(Ssh2ChannelOpen{
    channel_type: ctype;
    sender: sender;
    window: window;
    max_packet: maxp;
    decoded: decoded;
    host: host;
    port: port;
    origin: origin;
    origin_port: oport;
    extra: extra;
    total: p.total;
  });
}

/// Parse an SSH_MSG_CHANNEL_OPEN_CONFIRMATION (91) body: uint32 recipient +
/// uint32 sender + uint32 initial window size + uint32 maximum packet size +
/// raw type-specific data (preserved in `extra`, may be empty).
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(confirmation).
/// Errors: packet errors; empty payload; "ssh2: not a channel open
/// confirmation message at <off>"; uint32 truncation.
/// Complexity: O(body length).
pub fn ssh2_parse_channel_open_confirmation(data: &Vec[UInt8], off: Int) -> Result[Ssh2ChannelOpenConfirmation, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_channel_confirm(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_channel_confirm(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_OPEN_CONFIRMATION {
    return _err_channel_confirm(_at("ssh2: not a channel open confirmation message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let r1 = _u32_in(data, body, end);
  if !r1.is_ok {
    return _err_channel_confirm(r1.error);
  }
  let recipient: Int = r1.value;
  let r2 = _u32_in(data, body + 4, end);
  if !r2.is_ok {
    return _err_channel_confirm(r2.error);
  }
  let sender: Int = r2.value;
  let r3 = _u32_in(data, body + 8, end);
  if !r3.is_ok {
    return _err_channel_confirm(r3.error);
  }
  let window: Int = r3.value;
  let r4 = _u32_in(data, body + 12, end);
  if !r4.is_ok {
    return _err_channel_confirm(r4.error);
  }
  let maxp: Int = r4.value;
  var extra = Vec[UInt8].new();
  _copy_span(data, body + 16, end, &mut extra);
  return _ok_channel_confirm(Ssh2ChannelOpenConfirmation{
    recipient: recipient;
    sender: sender;
    window: window;
    max_packet: maxp;
    extra: extra;
    total: p.total;
  });
}

/// Parse an SSH_MSG_CHANNEL_OPEN_FAILURE (92) body: uint32 recipient +
/// uint32 reason code + string description + string language tag.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(failure).
/// Errors: packet errors; empty payload; "ssh2: not a channel open failure
/// message at <off>"; field truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_channel_open_failure(data: &Vec[UInt8], off: Int) -> Result[Ssh2ChannelOpenFailure, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_channel_open_fail(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_channel_open_fail(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_OPEN_FAILURE {
    return _err_channel_open_fail(_at("ssh2: not a channel open failure message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let r1 = _u32_in(data, body, end);
  if !r1.is_ok {
    return _err_channel_open_fail(r1.error);
  }
  let recipient: Int = r1.value;
  let r2 = _u32_in(data, body + 4, end);
  if !r2.is_ok {
    return _err_channel_open_fail(r2.error);
  }
  let reason: Int = r2.value;
  var cur = body + 8;
  let dr = _bytes_in(data, cur, end, "string");
  if !dr.is_ok {
    return _err_channel_open_fail(dr.error);
  }
  let desc: Vec[UInt8] = dr.value;
  cur = cur + 4 + desc.len();
  let lr = _bytes_in(data, cur, end, "string");
  if !lr.is_ok {
    return _err_channel_open_fail(lr.error);
  }
  let lang: Vec[UInt8] = lr.value;
  cur = cur + 4 + lang.len();
  if cur != end {
    return _err_channel_open_fail(_at("ssh2: trailing bytes", cur));
  }
  return _ok_channel_open_fail(Ssh2ChannelOpenFailure{
    recipient: recipient;
    reason: reason;
    description: desc;
    language: lang;
    total: p.total;
  });
}

/// Parse an SSH_MSG_CHANNEL_WINDOW_ADJUST (93) body: uint32 recipient +
/// uint32 bytes to add to the window.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(adjust).
/// Errors: packet errors; empty payload; "ssh2: not a window adjust message
/// at <off>"; uint32 truncation; trailing bytes.
/// Complexity: O(1).
pub fn ssh2_parse_window_adjust(data: &Vec[UInt8], off: Int) -> Result[Ssh2WindowAdjust, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_window_adjust(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_window_adjust(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_WINDOW_ADJUST {
    return _err_window_adjust(_at("ssh2: not a window adjust message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let r1 = _u32_in(data, body, end);
  if !r1.is_ok {
    return _err_window_adjust(r1.error);
  }
  let recipient: Int = r1.value;
  let r2 = _u32_in(data, body + 4, end);
  if !r2.is_ok {
    return _err_window_adjust(r2.error);
  }
  let bytes: Int = r2.value;
  if body + 8 != end {
    return _err_window_adjust(_at("ssh2: trailing bytes", body + 8));
  }
  return _ok_window_adjust(Ssh2WindowAdjust{ recipient: recipient; bytes: bytes; total: p.total; });
}

/// Parse an SSH_MSG_CHANNEL_REQUEST (98) body: uint32 recipient + string
/// request type + boolean want_reply + request-specific fields.
///
/// Decoded requests: "pty-req" (text0 = TERM, u32_0..3 = columns, rows,
/// width px, height px, text1 = raw encoded terminal modes), "env"
/// (text0 = variable name, text1 = value), "exec" (text0 = command),
/// "shell" (no fields), "subsystem" (text0 = subsystem name) and
/// "window-change" (u32_0..3 = columns, rows, width px, height px). Any other
/// request type keeps its raw tail in `extra` with decoded = false.
///
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(request).
/// Errors: packet errors; empty payload; "ssh2: not a channel request
/// message at <off>"; field truncation; trailing bytes for decoded types.
/// Complexity: O(body length).
pub fn ssh2_parse_channel_request(data: &Vec[UInt8], off: Int) -> Result[Ssh2ChannelRequest, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_channel_request(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_channel_request(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_REQUEST {
    return _err_channel_request(_at("ssh2: not a channel request message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let r1 = _u32_in(data, body, end);
  if !r1.is_ok {
    return _err_channel_request(r1.error);
  }
  let recipient: Int = r1.value;
  var cur = body + 4;
  let tr = _bytes_in(data, cur, end, "string");
  if !tr.is_ok {
    return _err_channel_request(tr.error);
  }
  let rtype: Vec[UInt8] = tr.value;
  cur = cur + 4 + rtype.len();
  let br = _bool_in(data, cur, end);
  if !br.is_ok {
    return _err_channel_request(br.error);
  }
  let want: Bool = br.value;
  cur = cur + 1;
  var decoded = false;
  var text0 = Vec[UInt8].new();
  var text1 = Vec[UInt8].new();
  var extra = Vec[UInt8].new();
  var u0 = 0;
  var u1 = 0;
  var u2 = 0;
  var u3 = 0;
  if _vec_eq_lit(&rtype, "pty-req") {
    let t1 = _bytes_in(data, cur, end, "string");
    if !t1.is_ok {
      return _err_channel_request(t1.error);
    }
    text0 = t1.value;
    cur = cur + 4 + text0.len();
    let a1 = _u32_in(data, cur, end);
    if !a1.is_ok {
      return _err_channel_request(a1.error);
    }
    u0 = a1.value;
    let a2 = _u32_in(data, cur + 4, end);
    if !a2.is_ok {
      return _err_channel_request(a2.error);
    }
    u1 = a2.value;
    let a3 = _u32_in(data, cur + 8, end);
    if !a3.is_ok {
      return _err_channel_request(a3.error);
    }
    u2 = a3.value;
    let a4 = _u32_in(data, cur + 12, end);
    if !a4.is_ok {
      return _err_channel_request(a4.error);
    }
    u3 = a4.value;
    cur = cur + 16;
    let t2 = _bytes_in(data, cur, end, "string");
    if !t2.is_ok {
      return _err_channel_request(t2.error);
    }
    text1 = t2.value;
    cur = cur + 4 + text1.len();
    decoded = true;
    if cur != end {
      return _err_channel_request(_at("ssh2: trailing bytes", cur));
    }
  } else {
    if _vec_eq_lit(&rtype, "env") {
      let t1 = _bytes_in(data, cur, end, "string");
      if !t1.is_ok {
        return _err_channel_request(t1.error);
      }
      text0 = t1.value;
      cur = cur + 4 + text0.len();
      let t2 = _bytes_in(data, cur, end, "string");
      if !t2.is_ok {
        return _err_channel_request(t2.error);
      }
      text1 = t2.value;
      cur = cur + 4 + text1.len();
      decoded = true;
      if cur != end {
        return _err_channel_request(_at("ssh2: trailing bytes", cur));
      }
    } else {
      if _vec_eq_lit(&rtype, "exec") {
        let t1 = _bytes_in(data, cur, end, "string");
        if !t1.is_ok {
          return _err_channel_request(t1.error);
        }
        text0 = t1.value;
        cur = cur + 4 + text0.len();
        decoded = true;
        if cur != end {
          return _err_channel_request(_at("ssh2: trailing bytes", cur));
        }
      } else {
        if _vec_eq_lit(&rtype, "shell") {
          decoded = true;
          if cur != end {
            return _err_channel_request(_at("ssh2: trailing bytes", cur));
          }
        } else {
          if _vec_eq_lit(&rtype, "subsystem") {
            let t1 = _bytes_in(data, cur, end, "string");
            if !t1.is_ok {
              return _err_channel_request(t1.error);
            }
            text0 = t1.value;
            cur = cur + 4 + text0.len();
            decoded = true;
            if cur != end {
              return _err_channel_request(_at("ssh2: trailing bytes", cur));
            }
          } else {
            if _vec_eq_lit(&rtype, "window-change") {
              let a1 = _u32_in(data, cur, end);
              if !a1.is_ok {
                return _err_channel_request(a1.error);
              }
              u0 = a1.value;
              let a2 = _u32_in(data, cur + 4, end);
              if !a2.is_ok {
                return _err_channel_request(a2.error);
              }
              u1 = a2.value;
              let a3 = _u32_in(data, cur + 8, end);
              if !a3.is_ok {
                return _err_channel_request(a3.error);
              }
              u2 = a3.value;
              let a4 = _u32_in(data, cur + 12, end);
              if !a4.is_ok {
                return _err_channel_request(a4.error);
              }
              u3 = a4.value;
              cur = cur + 16;
              decoded = true;
              if cur != end {
                return _err_channel_request(_at("ssh2: trailing bytes", cur));
              }
            } else {
              _copy_span(data, cur, end, &mut extra);
            }
          }
        }
      }
    }
  }
  return _ok_channel_request(Ssh2ChannelRequest{
    recipient: recipient;
    request: rtype;
    want_reply: want;
    decoded: decoded;
    text0: text0;
    text1: text1;
    u32_0: u0;
    u32_1: u1;
    u32_2: u2;
    u32_3: u3;
    extra: extra;
    total: p.total;
  });
}

/// Parse an SSH_MSG_CHANNEL_SUCCESS (99) body: uint32 recipient.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(recipient).
/// Errors: packet errors; empty payload; "ssh2: not a channel success
/// message at <off>"; uint32 truncation; trailing bytes.
/// Complexity: O(1).
pub fn ssh2_parse_channel_success(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_int(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_int(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_SUCCESS {
    return _err_int(_at("ssh2: not a channel success message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let rr = _u32_in(data, body, end);
  if !rr.is_ok {
    return _err_int(rr.error);
  }
  let recipient: Int = rr.value;
  if body + 4 != end {
    return _err_int(_at("ssh2: trailing bytes", body + 4));
  }
  return _ok_int(recipient);
}

/// Parse an SSH_MSG_CHANNEL_FAILURE (100) body: uint32 recipient.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(recipient).
/// Errors: packet errors; empty payload; "ssh2: not a channel failure
/// message at <off>"; uint32 truncation; trailing bytes.
/// Complexity: O(1).
pub fn ssh2_parse_channel_failure(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_int(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_int(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_FAILURE {
    return _err_int(_at("ssh2: not a channel failure message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let rr = _u32_in(data, body, end);
  if !rr.is_ok {
    return _err_int(rr.error);
  }
  let recipient: Int = rr.value;
  if body + 4 != end {
    return _err_int(_at("ssh2: trailing bytes", body + 4));
  }
  return _ok_int(recipient);
}

/// Parse an SSH_MSG_CHANNEL_EOF (96) body: uint32 recipient.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(recipient).
/// Errors: packet errors; empty payload; "ssh2: not a channel eof message at
/// <off>"; uint32 truncation; trailing bytes.
/// Complexity: O(1).
pub fn ssh2_parse_channel_eof(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_int(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_int(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_EOF {
    return _err_int(_at("ssh2: not a channel eof message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let rr = _u32_in(data, body, end);
  if !rr.is_ok {
    return _err_int(rr.error);
  }
  let recipient: Int = rr.value;
  if body + 4 != end {
    return _err_int(_at("ssh2: trailing bytes", body + 4));
  }
  return _ok_int(recipient);
}

/// Parse an SSH_MSG_CHANNEL_CLOSE (97) body: uint32 recipient.
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(recipient).
/// Errors: packet errors; empty payload; "ssh2: not a channel close message
/// at <off>"; uint32 truncation; trailing bytes.
/// Complexity: O(1).
pub fn ssh2_parse_channel_close(data: &Vec[UInt8], off: Int) -> Result[Int, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_int(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_int(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_CLOSE {
    return _err_int(_at("ssh2: not a channel close message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let rr = _u32_in(data, body, end);
  if !rr.is_ok {
    return _err_int(rr.error);
  }
  let recipient: Int = rr.value;
  if body + 4 != end {
    return _err_int(_at("ssh2: trailing bytes", body + 4));
  }
  return _ok_int(recipient);
}

/// Parse an SSH_MSG_CHANNEL_DATA (94) body: uint32 recipient + string data
/// (binary safe).
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(channel data).
/// Errors: packet errors; empty payload; "ssh2: not a channel data message
/// at <off>"; field truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_channel_data(data: &Vec[UInt8], off: Int) -> Result[Ssh2ChannelData, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_channel_data(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_channel_data(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_DATA {
    return _err_channel_data(_at("ssh2: not a channel data message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let rr = _u32_in(data, body, end);
  if !rr.is_ok {
    return _err_channel_data(rr.error);
  }
  let recipient: Int = rr.value;
  var cur = body + 4;
  let dr = _bytes_in(data, cur, end, "string");
  if !dr.is_ok {
    return _err_channel_data(dr.error);
  }
  let payload: Vec[UInt8] = dr.value;
  cur = cur + 4 + payload.len();
  if cur != end {
    return _err_channel_data(_at("ssh2: trailing bytes", cur));
  }
  return _ok_channel_data(Ssh2ChannelData{ recipient: recipient; data: payload; total: p.total; });
}

/// Parse an SSH_MSG_CHANNEL_EXTENDED_DATA (95) body: uint32 recipient +
/// uint32 data type code (1 = stderr) + string data (binary safe).
/// Params: data - buffer; off - packet offset.
/// Returns: Ok(extended data).
/// Errors: packet errors; empty payload; "ssh2: not a channel extended data
/// message at <off>"; field truncation; trailing bytes.
/// Complexity: O(body length).
pub fn ssh2_parse_channel_extended_data(data: &Vec[UInt8], off: Int) -> Result[Ssh2ChannelExtendedData, Str] {
  let pr = ssh2_parse_packet(data, off);
  if !pr.is_ok {
    return _err_channel_ext(pr.error);
  }
  let p: Ssh2Packet = pr.value;
  if p.payload_len < 1 {
    return _err_channel_ext(_at("ssh2: empty payload", off));
  }
  let mt = _byte(data, p.payload_off);
  if mt != SSH_MSG_CHANNEL_EXTENDED_DATA {
    return _err_channel_ext(_at("ssh2: not a channel extended data message", off));
  }
  let body = p.payload_off + 1;
  let end = p.padding_off;
  let r1 = _u32_in(data, body, end);
  if !r1.is_ok {
    return _err_channel_ext(r1.error);
  }
  let recipient: Int = r1.value;
  let r2 = _u32_in(data, body + 4, end);
  if !r2.is_ok {
    return _err_channel_ext(r2.error);
  }
  let dtype: Int = r2.value;
  var cur = body + 8;
  let dr = _bytes_in(data, cur, end, "string");
  if !dr.is_ok {
    return _err_channel_ext(dr.error);
  }
  let payload: Vec[UInt8] = dr.value;
  cur = cur + 4 + payload.len();
  if cur != end {
    return _err_channel_ext(_at("ssh2: trailing bytes", cur));
  }
  return _ok_channel_ext(Ssh2ChannelExtendedData{ recipient: recipient; data_type: dtype; data: payload; total: p.total; });
}

// --------------------------------------------------
//  Message encoders
// --------------------------------------------------
//
// Every ssh2_encode_* function returns a complete, 8-byte aligned binary
// packet (payload = message type + body, padding = zeros). They exist so
// callers and tests can build every supported message without hand-rolling
// byte layouts. A real transport must replace the zero padding with random
// bytes before sending.

// Append a Str as one RFC 4251 string (uint32 length + UTF-8 bytes).
fn _write_str_field(out: &mut Vec[UInt8], s: Str) {
  ssh2_write_uint32(out, s.len());
  _push_str(out, s);
}

// Wrap a message type + body into an 8-aligned binary packet.
fn _msg_payload(msg_type: Int, body: &Vec[UInt8]) -> Vec[UInt8] {
  var payload = Vec[UInt8].new();
  payload.push(msg_type as UInt8);
  _push_vec(&mut payload, body);
  return ssh2_write_packet_aligned(&payload, SSH2_DEFAULT_BLOCK_SIZE);
}

/// Encode SSH_MSG_DISCONNECT: reason code + description (language tag empty).
/// Params: reason - RFC 4253 reason code; description - human text.
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_disconnect(reason: Int, description: Str) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, reason);
  _write_str_field(&mut b, description);
  _write_str_field(&mut b, "");
  return _msg_payload(SSH_MSG_DISCONNECT, &b);
}

/// Encode SSH_MSG_IGNORE with raw data.
/// Params: data - bytes to carry. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_ignore(data: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_string(&mut b, data);
  return _msg_payload(SSH_MSG_IGNORE, &b);
}

/// Encode SSH_MSG_UNIMPLEMENTED with the offending sequence number.
/// Params: sequence - packet sequence number. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_unimplemented(sequence: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, sequence);
  return _msg_payload(SSH_MSG_UNIMPLEMENTED, &b);
}

/// Encode SSH_MSG_DEBUG (language tag empty).
/// Params: always_display - the display flag; message - debug text.
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_debug(always_display: Bool, message: Str) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_boolean(&mut b, always_display);
  _write_str_field(&mut b, message);
  _write_str_field(&mut b, "");
  return _msg_payload(SSH_MSG_DEBUG, &b);
}

/// Encode SSH_MSG_KEXINIT: cookie + ten raw name-lists + boolean + reserved.
/// Params: cookie - exactly 16 bytes; kex, host_key, enc_c2s, enc_s2c,
/// mac_c2s, mac_s2c, comp_c2s, comp_s2c, lang_c2s, lang_s2c - raw
/// comma-joined name-lists in wire order; first_follows - the boolean;
/// reserved - the uint32 (0).
/// Returns: the packet bytes. Error case: none (the cookie length is the
/// caller's responsibility; the parser insists on exactly 16).
pub fn ssh2_encode_kexinit(cookie: &Vec[UInt8], kex: &Vec[UInt8], host_key: &Vec[UInt8], enc_c2s: &Vec[UInt8], enc_s2c: &Vec[UInt8], mac_c2s: &Vec[UInt8], mac_s2c: &Vec[UInt8], comp_c2s: &Vec[UInt8], comp_s2c: &Vec[UInt8], lang_c2s: &Vec[UInt8], lang_s2c: &Vec[UInt8], first_follows: Bool, reserved: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _push_vec(&mut b, cookie);
  ssh2_write_name_list(&mut b, kex);
  ssh2_write_name_list(&mut b, host_key);
  ssh2_write_name_list(&mut b, enc_c2s);
  ssh2_write_name_list(&mut b, enc_s2c);
  ssh2_write_name_list(&mut b, mac_c2s);
  ssh2_write_name_list(&mut b, mac_s2c);
  ssh2_write_name_list(&mut b, comp_c2s);
  ssh2_write_name_list(&mut b, comp_s2c);
  ssh2_write_name_list(&mut b, lang_c2s);
  ssh2_write_name_list(&mut b, lang_s2c);
  ssh2_write_boolean(&mut b, first_follows);
  ssh2_write_uint32(&mut b, reserved);
  return _msg_payload(SSH_MSG_KEXINIT, &b);
}

/// Encode SSH_MSG_KEXDH_INIT with a raw mpint e.
/// Params: e - raw two's-complement bytes. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_kexdh_init(e: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_mpint(&mut b, e);
  return _msg_payload(SSH_MSG_KEXDH_INIT, &b);
}

/// Encode SSH_MSG_KEXDH_REPLY: host key + raw mpint f + signature.
/// Params: host_key, f, signature - raw fields. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_kexdh_reply(host_key: &Vec[UInt8], f: &Vec[UInt8], signature: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_string(&mut b, host_key);
  ssh2_write_mpint(&mut b, f);
  ssh2_write_string(&mut b, signature);
  return _msg_payload(SSH_MSG_KEXDH_REPLY, &b);
}

/// Encode SSH_MSG_KEX_ECDH_INIT with a raw string Q_C.
/// Params: q_c - raw point bytes. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_kex_ecdh_init(q_c: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_string(&mut b, q_c);
  return _msg_payload(SSH_MSG_KEX_ECDH_INIT, &b);
}

/// Encode SSH_MSG_KEX_ECDH_REPLY: host key + raw string Q_S + signature.
/// Params: host_key, q_s, signature - raw fields. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_kex_ecdh_reply(host_key: &Vec[UInt8], q_s: &Vec[UInt8], signature: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_string(&mut b, host_key);
  ssh2_write_string(&mut b, q_s);
  ssh2_write_string(&mut b, signature);
  return _msg_payload(SSH_MSG_KEX_ECDH_REPLY, &b);
}

/// Encode SSH_MSG_NEWKEYS (empty body).
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_newkeys() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  return _msg_payload(SSH_MSG_NEWKEYS, &b);
}

/// Encode SSH_MSG_SERVICE_REQUEST with a service name.
/// Params: service - service name ("ssh-userauth" / "ssh-connection").
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_service_request(service: Str) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, service);
  return _msg_payload(SSH_MSG_SERVICE_REQUEST, &b);
}

/// Encode SSH_MSG_SERVICE_ACCEPT with a service name.
/// Params: service - service name. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_service_accept(service: Str) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, service);
  return _msg_payload(SSH_MSG_SERVICE_ACCEPT, &b);
}

/// Encode SSH_MSG_USERAUTH_REQUEST with method "password" (no change flag).
/// Params: user, service, password - text fields.
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_userauth_password(user: Str, service: Str, password: Str) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, user);
  _write_str_field(&mut b, service);
  _write_str_field(&mut b, "password");
  ssh2_write_boolean(&mut b, false);
  _write_str_field(&mut b, password);
  return _msg_payload(SSH_MSG_USERAUTH_REQUEST, &b);
}

/// Encode SSH_MSG_USERAUTH_REQUEST with method "password" and the change
/// flag set (old password + new password).
/// Params: user, service, old_password, new_password - text fields.
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_userauth_password_change(user: Str, service: Str, old_password: Str, new_password: Str) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, user);
  _write_str_field(&mut b, service);
  _write_str_field(&mut b, "password");
  ssh2_write_boolean(&mut b, true);
  _write_str_field(&mut b, old_password);
  _write_str_field(&mut b, new_password);
  return _msg_payload(SSH_MSG_USERAUTH_REQUEST, &b);
}

/// Encode SSH_MSG_USERAUTH_REQUEST with method "publickey". An empty
/// `signature` encodes has_signature = false (query form), otherwise true.
/// Params: user, service, algorithm - text fields; key_blob - the public key
/// blob; signature - the raw signature (may be empty).
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_userauth_publickey(user: Str, service: Str, algorithm: Str, key_blob: &Vec[UInt8], signature: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, user);
  _write_str_field(&mut b, service);
  _write_str_field(&mut b, "publickey");
  if signature.len() > 0 {
    ssh2_write_boolean(&mut b, true);
  } else {
    ssh2_write_boolean(&mut b, false);
  }
  _write_str_field(&mut b, algorithm);
  ssh2_write_string(&mut b, key_blob);
  if signature.len() > 0 {
    ssh2_write_string(&mut b, signature);
  }
  return _msg_payload(SSH_MSG_USERAUTH_REQUEST, &b);
}

/// Encode SSH_MSG_USERAUTH_FAILURE: method name-list + partial success.
/// Params: methods - raw comma-joined name-list (may be empty); partial -
/// the boolean. Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_userauth_failure(methods: &Vec[UInt8], partial: Bool) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_name_list(&mut b, methods);
  ssh2_write_boolean(&mut b, partial);
  return _msg_payload(SSH_MSG_USERAUTH_FAILURE, &b);
}

/// Encode SSH_MSG_USERAUTH_SUCCESS (empty body).
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_userauth_success() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  return _msg_payload(SSH_MSG_USERAUTH_SUCCESS, &b);
}

/// Encode SSH_MSG_USERAUTH_BANNER (language tag empty).
/// Params: message - banner text. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_banner(message: Str) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, message);
  _write_str_field(&mut b, "");
  return _msg_payload(SSH_MSG_USERAUTH_BANNER, &b);
}

/// Encode SSH_MSG_GLOBAL_REQUEST: name + want_reply + raw data.
/// Params: name - request name; want_reply - the boolean; data - raw
/// request-specific bytes (may be empty). Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_global_request(name: Str, want_reply: Bool, data: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, name);
  ssh2_write_boolean(&mut b, want_reply);
  _push_vec(&mut b, data);
  return _msg_payload(SSH_MSG_GLOBAL_REQUEST, &b);
}

/// Encode SSH_MSG_REQUEST_SUCCESS with raw data (possibly empty).
/// Params: data - response bytes. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_request_success(data: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _push_vec(&mut b, data);
  return _msg_payload(SSH_MSG_REQUEST_SUCCESS, &b);
}

/// Encode SSH_MSG_REQUEST_FAILURE (empty body).
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_request_failure() -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  return _msg_payload(SSH_MSG_REQUEST_FAILURE, &b);
}

/// Encode SSH_MSG_CHANNEL_OPEN type "session" (no type-specific fields).
/// Params: sender - sender channel; window - initial window size;
/// max_packet - maximum packet size. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_channel_open_session(sender: Int, window: Int, max_packet: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, "session");
  ssh2_write_uint32(&mut b, sender);
  ssh2_write_uint32(&mut b, window);
  ssh2_write_uint32(&mut b, max_packet);
  return _msg_payload(SSH_MSG_CHANNEL_OPEN, &b);
}

/// Encode SSH_MSG_CHANNEL_OPEN type "direct-tcpip".
/// Params: sender, window, max_packet - channel parameters; host, port - the
/// host to connect; origin, origin_port - the originator.
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_open_direct_tcpip(sender: Int, window: Int, max_packet: Int, host: Str, port: Int, origin: Str, origin_port: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, "direct-tcpip");
  ssh2_write_uint32(&mut b, sender);
  ssh2_write_uint32(&mut b, window);
  ssh2_write_uint32(&mut b, max_packet);
  _write_str_field(&mut b, host);
  ssh2_write_uint32(&mut b, port);
  _write_str_field(&mut b, origin);
  ssh2_write_uint32(&mut b, origin_port);
  return _msg_payload(SSH_MSG_CHANNEL_OPEN, &b);
}

/// Encode SSH_MSG_CHANNEL_OPEN type "forwarded-tcpip".
/// Params: sender, window, max_packet - channel parameters; host, port - the
/// connected address; origin, origin_port - the originator.
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_open_forwarded_tcpip(sender: Int, window: Int, max_packet: Int, host: Str, port: Int, origin: Str, origin_port: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  _write_str_field(&mut b, "forwarded-tcpip");
  ssh2_write_uint32(&mut b, sender);
  ssh2_write_uint32(&mut b, window);
  ssh2_write_uint32(&mut b, max_packet);
  _write_str_field(&mut b, host);
  ssh2_write_uint32(&mut b, port);
  _write_str_field(&mut b, origin);
  ssh2_write_uint32(&mut b, origin_port);
  return _msg_payload(SSH_MSG_CHANNEL_OPEN, &b);
}

/// Encode SSH_MSG_CHANNEL_OPEN_CONFIRMATION.
/// Params: recipient, sender, window, max_packet - channel parameters;
/// extra - raw type-specific bytes (may be empty).
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_open_confirmation(recipient: Int, sender: Int, window: Int, max_packet: Int, extra: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  ssh2_write_uint32(&mut b, sender);
  ssh2_write_uint32(&mut b, window);
  ssh2_write_uint32(&mut b, max_packet);
  _push_vec(&mut b, extra);
  return _msg_payload(SSH_MSG_CHANNEL_OPEN_CONFIRMATION, &b);
}

/// Encode SSH_MSG_CHANNEL_OPEN_FAILURE (language tag empty).
/// Params: recipient - channel recipient; reason - RFC 4254 reason code;
/// description - human text. Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_open_failure(recipient: Int, reason: Int, description: Str) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  ssh2_write_uint32(&mut b, reason);
  _write_str_field(&mut b, description);
  _write_str_field(&mut b, "");
  return _msg_payload(SSH_MSG_CHANNEL_OPEN_FAILURE, &b);
}

/// Encode SSH_MSG_CHANNEL_WINDOW_ADJUST.
/// Params: recipient - channel recipient; bytes - bytes to add.
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_window_adjust(recipient: Int, bytes: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  ssh2_write_uint32(&mut b, bytes);
  return _msg_payload(SSH_MSG_CHANNEL_WINDOW_ADJUST, &b);
}

/// Encode SSH_MSG_CHANNEL_REQUEST type "pty-req".
/// Params: recipient - channel recipient; term - TERM value; cols, rows,
/// width, height - terminal geometry; modes - raw encoded terminal modes
/// (may be empty); want_reply - the boolean.
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_pty_req(recipient: Int, term: Str, cols: Int, rows: Int, width: Int, height: Int, modes: &Vec[UInt8], want_reply: Bool) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  _write_str_field(&mut b, "pty-req");
  ssh2_write_boolean(&mut b, want_reply);
  _write_str_field(&mut b, term);
  ssh2_write_uint32(&mut b, cols);
  ssh2_write_uint32(&mut b, rows);
  ssh2_write_uint32(&mut b, width);
  ssh2_write_uint32(&mut b, height);
  ssh2_write_string(&mut b, modes);
  return _msg_payload(SSH_MSG_CHANNEL_REQUEST, &b);
}

/// Encode SSH_MSG_CHANNEL_REQUEST type "env".
/// Params: recipient - channel recipient; name, value - the variable;
/// want_reply - the boolean. Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_env(recipient: Int, name: Str, value: Str, want_reply: Bool) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  _write_str_field(&mut b, "env");
  ssh2_write_boolean(&mut b, want_reply);
  _write_str_field(&mut b, name);
  _write_str_field(&mut b, value);
  return _msg_payload(SSH_MSG_CHANNEL_REQUEST, &b);
}

/// Encode SSH_MSG_CHANNEL_REQUEST type "exec".
/// Params: recipient - channel recipient; command - the command line;
/// want_reply - the boolean. Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_exec(recipient: Int, command: Str, want_reply: Bool) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  _write_str_field(&mut b, "exec");
  ssh2_write_boolean(&mut b, want_reply);
  _write_str_field(&mut b, command);
  return _msg_payload(SSH_MSG_CHANNEL_REQUEST, &b);
}

/// Encode SSH_MSG_CHANNEL_REQUEST type "shell" (no request-specific fields).
/// Params: recipient - channel recipient; want_reply - the boolean.
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_shell(recipient: Int, want_reply: Bool) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  _write_str_field(&mut b, "shell");
  ssh2_write_boolean(&mut b, want_reply);
  return _msg_payload(SSH_MSG_CHANNEL_REQUEST, &b);
}

/// Encode SSH_MSG_CHANNEL_REQUEST type "subsystem".
/// Params: recipient - channel recipient; subsystem - subsystem name;
/// want_reply - the boolean. Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_subsystem(recipient: Int, subsystem: Str, want_reply: Bool) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  _write_str_field(&mut b, "subsystem");
  ssh2_write_boolean(&mut b, want_reply);
  _write_str_field(&mut b, subsystem);
  return _msg_payload(SSH_MSG_CHANNEL_REQUEST, &b);
}

/// Encode SSH_MSG_CHANNEL_REQUEST type "window-change".
/// Params: recipient - channel recipient; cols, rows, width, height -
/// terminal geometry. Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_window_change(recipient: Int, cols: Int, rows: Int, width: Int, height: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  _write_str_field(&mut b, "window-change");
  ssh2_write_boolean(&mut b, false);
  ssh2_write_uint32(&mut b, cols);
  ssh2_write_uint32(&mut b, rows);
  ssh2_write_uint32(&mut b, width);
  ssh2_write_uint32(&mut b, height);
  return _msg_payload(SSH_MSG_CHANNEL_REQUEST, &b);
}

/// Encode SSH_MSG_CHANNEL_SUCCESS.
/// Params: recipient - channel recipient. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_channel_success(recipient: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  return _msg_payload(SSH_MSG_CHANNEL_SUCCESS, &b);
}

/// Encode SSH_MSG_CHANNEL_FAILURE.
/// Params: recipient - channel recipient. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_channel_failure(recipient: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  return _msg_payload(SSH_MSG_CHANNEL_FAILURE, &b);
}

/// Encode SSH_MSG_CHANNEL_EOF.
/// Params: recipient - channel recipient. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_channel_eof(recipient: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  return _msg_payload(SSH_MSG_CHANNEL_EOF, &b);
}

/// Encode SSH_MSG_CHANNEL_CLOSE.
/// Params: recipient - channel recipient. Returns: the packet bytes.
/// Error case: none.
pub fn ssh2_encode_channel_close(recipient: Int) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  return _msg_payload(SSH_MSG_CHANNEL_CLOSE, &b);
}

/// Encode SSH_MSG_CHANNEL_DATA.
/// Params: recipient - channel recipient; data - raw payload (binary safe).
/// Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_data(recipient: Int, data: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  ssh2_write_string(&mut b, data);
  return _msg_payload(SSH_MSG_CHANNEL_DATA, &b);
}

/// Encode SSH_MSG_CHANNEL_EXTENDED_DATA.
/// Params: recipient - channel recipient; data_type - type code (1 = stderr);
/// data - raw payload. Returns: the packet bytes. Error case: none.
pub fn ssh2_encode_channel_extended_data(recipient: Int, data_type: Int, data: &Vec[UInt8]) -> Vec[UInt8] {
  var b = Vec[UInt8].new();
  ssh2_write_uint32(&mut b, recipient);
  ssh2_write_uint32(&mut b, data_type);
  ssh2_write_string(&mut b, data);
  return _msg_payload(SSH_MSG_CHANNEL_EXTENDED_DATA, &b);
}
