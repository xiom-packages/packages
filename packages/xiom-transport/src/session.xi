// XIOM -- xiom.transport.session: lifecycle, handshake, channels
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The L2 session over the frames codec and the pure reliability engine:
//
//   * handshake: both ends start by sending a hello carrying the protocol
//     version (u16, TX_PROTOCOL_VERSION). Receiving a hello with a
//     different version REFUSES the connection (FIN reason
//     FIN_REASON_VERSION_MISMATCH, state Closed, typed failure event) --
//     never a partial session and never a silent downgrade;
//   * lifecycle: Connecting -> Handshaking -> Active -> Draining ->
//     Closed with a typed failure contract per transition (ConnState +
//     session_state_name / session_state_code make it inspectable);
//   * channels: declared semantics (reliable, ordered, priority, window)
//     via session_open_channel; the channel map is symmetric configuration
//     data in phase 1 (wire channel negotiation is a declared non-goal);
//   * send: payloads above the per-datagram chunk cap fragment with
//     explicit byte offsets (<= TX_MAX_FRAGMENTS pieces; message cap
//     FRAME_MAX_MESSAGE); every outgoing data frame piggybacks this
//     side's ack state for its channel;
//   * receive: frames route to the reliability engine; fragments reassemble
//     in a bounded buffer and a partial message is NEVER delivered nor
//     acked; each completed message is acknowledged (ack-only frames in
//     phase 1; ack batching is a declared non-goal);
//   * poll(now_ms): drains due retransmissions and reliability failure
//     verdicts against the injected clock; a reliable-channel timeout is
//     a draining transition plus a typed event, never a hang.
//
// Every step returns a SessionPoll: the exact bytes to put on the wire
// and the typed events observed. Nothing mutates mid-step; the caller
// owns the wire. No wall clock, no randomness, no globals.

module xiom.transport.session

use xiom.transport.caps;
use xiom.transport.frames;
use xiom.transport.reliable;
use xiom.transport.rate;

// ---------------------------------------------------------------------------
// Protocol constants
// ---------------------------------------------------------------------------

/// Protocol version exchanged in the handshake (u16 on the wire). A
/// mismatch is a refusal with a report.
pub const TX_PROTOCOL_VERSION: Int = 1;

/// Max fragments per message (message cap 256 KiB / smallest chunk).
pub const TX_MAX_FRAGMENTS: Int = 256;

/// Max concurrent partial messages being reassembled per session.
pub const TX_MAX_REASM_ENTRIES: Int = 16;

// Session error kinds (SessionError.kind).
pub const TX_ERR_STATE: Int = 1;
pub const TX_ERR_CHANNEL: Int = 2;
pub const TX_ERR_VERSION: Int = 3;
pub const TX_ERR_FRAME: Int = 4;
pub const TX_ERR_PAYLOAD: Int = 5;
pub const TX_ERR_WINDOW: Int = 6;
pub const TX_ERR_RELIABLE: Int = 7;
pub const TX_ERR_BUFFER: Int = 8;
pub const TX_ERR_CONN_ID: Int = 9;
pub const TX_ERR_RATE: Int = 10;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// Connection lifecycle state (the session owns the lifecycle; the root
/// facade surfaces the same enum through its handle).
pub enum ConnState {
  Connecting,
  Handshaking,
  Active,
  Draining,
  Closed,
}

/// A typed session failure. `code` carries the frame error kind, or the
/// reliability verdict kind, or 0.
pub type SessionError = {
  kind: Int;
  code: Int;
  message: Str;
}

/// A typed session event observed by a step.
pub enum SessionEvent {
  EvStateChanged(from: Int, to: Int),
  EvDelivered(channel: Int, seq: Int, payload: Vec[UInt8]),
  EvChannelOpened(channel: Int, reliable: Bool, ordered: Bool, priority: Int),
  EvChannelClosed(channel: Int),
  EvFailure(kind: Int, channel: Int, seq: Int),
  EvHello(protocol_version: Int),
  EvHelloAck(protocol_version: Int),
  EvPing,
  EvPong,
  EvFinish(reason: Int),
}

/// The result of one step: exact frames to send, typed events observed.
pub type SessionPoll = {
  out: Vec[Vec[UInt8]];
  events: Vec[SessionEvent];
}

/// Session-level counters (reliability counters live in the engine and
/// are surfaced through session_reliable_stats).
pub type SessionStats = {
  frames_sent: Int;
  frames_recv: Int;
  bytes_sent: Int;
  bytes_recv: Int;
  messages_sent: Int;
  messages_delivered: Int;
  fragments_sent: Int;
  fragments_recv: Int;
  reasm_completed: Int;
  reasm_duplicates: Int;
  acks_sent: Int;
  pings: Int;
  pongs: Int;
  refusals: Int;
  failures: Int;
}

/// One in-progress reassembly (bounded by TX_MAX_REASM_ENTRIES).
pub type ReasmEntry = {
  channel: Int;
  seq: Int;
  count: Int;
  total: Int;
  got: Vec[Bool];
  payload: Vec[UInt8];
}

/// Outcome of placing one fragment.
pub type ReasmOutcome = {
  complete: Bool;
  payload: Vec[UInt8];
}

/// The session value: plain state, stepped only through the functions
/// below.
pub type Session = {
  state: ConnState;
  conn_id: Int;
  local_protocol_version: Int;
  peer_protocol_version: Int;
  hello_sent: Bool;
  hello_ack_sent: Bool;
  peer_hello_seen: Bool;
  peer_hello_ack_seen: Bool;
  fin_sent: Bool;
  fin_reason: Int;
  max_datagram: Int;
  engine: RlEngine;
  reasm: Vec[ReasmEntry];
  stats: SessionStats;
}

// ---------------------------------------------------------------------------
// Leaf helpers
// ---------------------------------------------------------------------------

fn _sxerr(kind: Int, code: Int, message: Str) -> SessionError {
  return SessionError { kind: kind, code: code, message: message };
}

fn _ok_poll(v: SessionPoll) -> Result[SessionPoll, SessionError] { return Ok(v); }
fn _err_poll(e: SessionError) -> Result[SessionPoll, SessionError] { return Err(e); }
fn _ok_bool(v: Bool) -> Result[Bool, SessionError] { return Ok(v); }
fn _err_bool(e: SessionError) -> Result[Bool, SessionError] { return Err(e); }
fn _ok_outcome(v: ReasmOutcome) -> Result[ReasmOutcome, SessionError] { return Ok(v); }
fn _err_outcome(e: SessionError) -> Result[ReasmOutcome, SessionError] { return Err(e); }

fn _empty_frames() -> Vec[Vec[UInt8]] {
  return Vec[Vec[UInt8]].new();
}

fn _make_poll() -> SessionPoll {
  var events: Vec[SessionEvent] = Vec[SessionEvent].new();
  return SessionPoll { out: _empty_frames(), events: events };
}

fn _empty_sstats() -> SessionStats {
  return SessionStats {
    frames_sent: 0;
    frames_recv: 0;
    bytes_sent: 0;
    bytes_recv: 0;
    messages_sent: 0;
    messages_delivered: 0;
    fragments_sent: 0;
    fragments_recv: 0;
    reasm_completed: 0;
    reasm_duplicates: 0;
    acks_sent: 0;
    pings: 0;
    pongs: 0;
    refusals: 0;
    failures: 0;
  };
}

fn _chunk_cap(s: &Session) -> Int {
  return s.max_datagram - FRAME_HEADER_SIZE - FRAME_FRAG_META_SIZE;
}

fn _state_event(from: Int, to: Int) -> SessionEvent {
  return EvStateChanged(from: from, to: to);
}

// Append one encoded frame to the poll's out list, counting stats.
fn _emit(s: &mut Session, poll: &mut SessionPoll, f: &Frame) -> Bool {
  let enc = frame_encode(f);
  if !enc.is_ok {
    return false;
  }
  let bytes: Vec[UInt8] = enc.value;
  s.stats.frames_sent = s.stats.frames_sent + 1;
  s.stats.bytes_sent = s.stats.bytes_sent + bytes.len();
  poll.out.push(bytes);
  return true;
}

// This side's current ack pair for a channel: (ack, bits).
fn _ack_value(s: &Session, channel: Int) -> Int {
  let rn = rl_recv_next(&s.engine, channel);
  if !rn.is_ok { return -1; }
  if rn.value > 0 { return rn.value - 1; }
  return -1;
}

fn _ack_bits_value(s: &Session, channel: Int) -> Int {
  let rm = rl_recv_mask(&s.engine, channel);
  if !rm.is_ok { return 0; }
  return rm.value & 4294967295;
}

// Queue a state transition + event when the state actually changes.
fn _transition(s: &mut Session, poll: &mut SessionPoll, to: ConnState) {
  let from = session_state_code(s.state);
  let to_code = session_state_code(to);
  if from != to_code {
    s.state = to;
    poll.events.push(_state_event(from, to_code));
  }
}

// Encode one logical message (one frame, or fragments when above the
// chunk cap) at a given channel/seq. Used for initial sends and for
// retransmissions, so the wire bytes are identical either way.
fn _emit_message(s: &mut Session, poll: &mut SessionPoll, channel: Int, seq: Int, payload: &Vec[UInt8]) -> Result[Unit, SessionError] {
  let cap = _chunk_cap(s);
  let plen = payload.len();
  let ack = _ack_value(s, channel);
  let bits = _ack_bits_value(s, channel);
  if plen <= cap {
    var chunk: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < plen {
      let b: UInt8 = payload[i];
      chunk.push(b);
      i = i + 1;
    }
    var f = frame_data(s.conn_id, channel, seq, ack, bits, chunk);
    if !_emit(s, poll, &f) {
      return _err_unit_result(_sxerr(TX_ERR_FRAME, 0, "session: data frame encode failed"));
    }
    return _ok_unit_result();
  }
  var count = plen / cap;
  if plen % cap != 0 { count = count + 1; }
  if count > TX_MAX_FRAGMENTS {
    return _err_unit_result(_sxerr(TX_ERR_PAYLOAD, 0, "session: message needs " + count.to_str() + " fragments (max TX_MAX_FRAGMENTS)"));
  }
  var index = 0;
  var offset = 0;
  while index < count {
    var take = cap;
    if offset + take > plen { take = plen - offset; }
    var chunk: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < take {
      let b: UInt8 = payload[offset + i];
      chunk.push(b);
      i = i + 1;
    }
    var f = frame_data_fragment(s.conn_id, channel, seq, ack, bits, index, count, offset, plen, chunk);
    if !_emit(s, poll, &f) {
      return _err_unit_result(_sxerr(TX_ERR_FRAME, 0, "session: fragment frame encode failed"));
    }
    s.stats.fragments_sent = s.stats.fragments_sent + 1;
    offset = offset + take;
    index = index + 1;
  }
  return _ok_unit_result();
}

fn _ok_unit_result() -> Result[Unit, SessionError] { return Ok(()); }
fn _err_unit_result(e: SessionError) -> Result[Unit, SessionError] { return Err(e); }

// Emit the session's pending FIN once.
fn _emit_fin(s: &mut Session, poll: &mut SessionPoll) {
  if s.fin_sent { return; }
  var f = frame_fin(s.conn_id, s.fin_reason);
  if _emit(s, poll, &f) {
    s.fin_sent = true;
  }
}

// Map a reliability error onto the session taxonomy.
fn _map_rl_error(prefix: Str, re: RlError) -> SessionError {
  if re.kind == RL_ERR_CHANNEL {
    return _sxerr(TX_ERR_CHANNEL, re.kind, prefix + ": " + re.message);
  }
  if re.kind == RL_ERR_WINDOW {
    return _sxerr(TX_ERR_WINDOW, re.kind, prefix + ": " + re.message);
  }
  return _sxerr(TX_ERR_RELIABLE, re.kind, prefix + ": " + re.message);
}

// Refuse the connection with a version mismatch report.
fn _refuse_version(s: &mut Session, poll: &mut SessionPoll, peer_pv: Int) {
  s.stats.refusals = s.stats.refusals + 1;
  s.peer_protocol_version = peer_pv;
  poll.events.push(EvFailure(kind: TX_ERR_VERSION, channel: -1, seq: -1));
  if s.fin_reason == FIN_REASON_NONE {
    s.fin_reason = FIN_REASON_VERSION_MISMATCH;
  }
  _emit_fin(s, poll);
  _transition(s, poll, Closed);
}

// ---------------------------------------------------------------------------
// Construction and introspection
// ---------------------------------------------------------------------------

/// A fresh session in Connecting for a caller-chosen connection id
/// (0..4294967295). max_datagram is the caller's wire datagram budget;
/// it is clamped into [64, FRAME_MAX_DATAGRAM] and falls back to the
/// full codec cap when smaller than one fragment frame.
pub fn session_new(conn_id: Int, max_datagram: Int) -> Session {
  var md = max_datagram;
  if md < 64 { md = FRAME_MAX_DATAGRAM; }
  if md > FRAME_MAX_DATAGRAM { md = FRAME_MAX_DATAGRAM; }
  var reasm: Vec[ReasmEntry] = Vec[ReasmEntry].new();
  return Session {
    state: Connecting;
    conn_id: conn_id;
    local_protocol_version: TX_PROTOCOL_VERSION;
    peer_protocol_version: 0;
    hello_sent: false;
    hello_ack_sent: false;
    peer_hello_seen: false;
    peer_hello_ack_seen: false;
    fin_sent: false;
    fin_reason: FIN_REASON_NONE;
    max_datagram: md;
    engine: rl_new();
    reasm: reasm;
    stats: _empty_sstats();
  };
}

pub fn session_state_code(st: ConnState) -> Int {
  match st {
    Connecting => { return 0; },
    Handshaking => { return 1; },
    Active => { return 2; },
    Draining => { return 3; },
    Closed => { return 4; },
  }
  return 4;
}

pub fn session_state_name(st: ConnState) -> Str {
  match st {
    Connecting => { return "connecting"; },
    Handshaking => { return "handshaking"; },
    Active => { return "active"; },
    Draining => { return "draining"; },
    Closed => { return "closed"; },
  }
  return "closed";
}

pub fn session_state_name_of_code(code: Int) -> Str {
  if code == 0 { return "connecting"; }
  if code == 1 { return "handshaking"; }
  if code == 2 { return "active"; }
  if code == 3 { return "draining"; }
  return "closed";
}

pub fn session_state(s: &Session) -> ConnState {
  return s.state;
}

pub fn session_is_active(s: &Session) -> Bool {
  match s.state {
    Active => { return true; },
    Connecting => { return false; },
    Handshaking => { return false; },
    Draining => { return false; },
    Closed => { return false; },
  }
  return false;
}

pub fn session_stats(s: &Session) -> SessionStats {
  return s.stats;
}

/// Reliability counters (exact aggregates) pass-through.
pub fn session_reliable_stats(s: &Session) -> RlStats {
  return rl_stats(&s.engine);
}

pub fn session_reasm_len(s: &Session) -> Int {
  return s.reasm.len();
}

pub fn session_conn_id(s: &Session) -> Int {
  return s.conn_id;
}

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

/// Begin the connection: emit hello and move Connecting -> Handshaking.
pub fn session_start(s: &mut Session, now_ms: Int) -> Result[SessionPoll, SessionError] {
  let _ = now_ms;
  var poll = _make_poll();
  match s.state {
    Connecting => {},
    _ => {
      return _err_poll(_sxerr(TX_ERR_STATE, 0, "session_start: not in Connecting"));
    },
  }
  var f = frame_hello(s.conn_id, s.local_protocol_version);
  if !_emit(s, &mut poll, &f) {
    return _err_poll(_sxerr(TX_ERR_FRAME, 0, "session_start: hello encode failed"));
  }
  s.hello_sent = true;
  _transition(s, &mut poll, Handshaking);
  return _ok_poll(poll);
}

/// Close initiated by this side: emit FIN(reason) and move to Draining
/// (idempotent; Closed sessions stay closed). The peer's FIN (or this
/// side's own close-complete) moves Draining -> Closed via on_packet.
pub fn session_close(s: &mut Session, reason: Int, now_ms: Int) -> Result[SessionPoll, SessionError] {
  let _ = now_ms;
  var poll = _make_poll();
  match s.state {
    Closed => {
      return _ok_poll(poll);
    },
    _ => {},
  }
  if s.fin_reason == FIN_REASON_NONE {
    s.fin_reason = reason;
  }
  _emit_fin(s, &mut poll);
  _transition(s, &mut poll, Draining);
  return _ok_poll(poll);
}

/// Pure predicate: has a bounded handshake deadline expired without the
/// session reaching Active? The clock is the caller's (started_ms is the
/// caller-recorded start). The caller turns Ok(true) into
/// session_close(s, FIN_REASON_TIMEOUT, now_ms) -- a verdict, not a hang.
pub fn session_handshake_deadline(s: &Session, started_ms: Int, now_ms: Int, budget_ms: Int) -> Result[Bool, SessionError] {
  if budget_ms < 0 {
    return _err_bool(_sxerr(TX_ERR_STATE, 0, "session_handshake_deadline: negative budget"));
  }
  match s.state {
    Active => { return _ok_bool(false); },
    Closed => { return _ok_bool(false); },
    _ => {},
  }
  if now_ms - started_ms >= budget_ms {
    return _ok_bool(true);
  }
  return _ok_bool(false);
}

// ---------------------------------------------------------------------------
// Channels
// ---------------------------------------------------------------------------

/// Declare a channel (id 0..255, window clamped 1..32). Channels are
/// symmetric configuration data in phase 1; re-opening an existing id is
/// Ok(false) with no event.
pub fn session_open_channel(s: &mut Session, id: Int, reliable: Bool, ordered: Bool, priority: Int, window: Int) -> Result[SessionPoll, SessionError] {
  var poll = _make_poll();
  match s.state {
    Closed => {
      return _err_poll(_sxerr(TX_ERR_STATE, 0, "session_open_channel: session closed"));
    },
    _ => {},
  }
  let r = rl_open_channel(&mut s.engine, id, reliable, ordered, priority, window);
  if !r.is_ok {
    let re: RlError = r.error;
    return _err_poll(_map_rl_error("session_open_channel", re));
  }
  let created = r.value;
  if created {
    var pr = priority;
    if pr < 0 { pr = 0; }
    poll.events.push(EvChannelOpened(channel: id, reliable: reliable, ordered: ordered, priority: pr));
  }
  return _ok_poll(poll);
}

/// Close a channel (drops its live state); event only when it existed.
pub fn session_close_channel(s: &mut Session, id: Int) -> Result[SessionPoll, SessionError] {
  var poll = _make_poll();
  let existed = rl_close_channel(&mut s.engine, id);
  if existed {
    poll.events.push(EvChannelClosed(channel: id));
  }
  return _ok_poll(poll);
}

// ---------------------------------------------------------------------------
// Send
// ---------------------------------------------------------------------------

/// Send one message on a channel. Active only; Draining refuses
/// (TX_ERR_STATE). Payloads above FRAME_MAX_MESSAGE are refused
/// (TX_ERR_PAYLOAD); reliable channels honor the bounded window
/// (TX_ERR_WINDOW); larger payloads fragment automatically.
pub fn session_send(s: &mut Session, channel: Int, payload: &Vec[UInt8], now_ms: Int) -> Result[SessionPoll, SessionError] {
  var poll = _make_poll();
  match s.state {
    Active => {},
    _ => {
      return _err_poll(_sxerr(TX_ERR_STATE, 0, "session_send: not active (" + session_state_name(s.state) + ")"));
    },
  }
  if payload.len() > FRAME_MAX_MESSAGE {
    return _err_poll(_sxerr(TX_ERR_PAYLOAD, 0, "session_send: message above FRAME_MAX_MESSAGE"));
  }
  let r = rl_send(&mut s.engine, channel, payload, now_ms);
  if !r.is_ok {
    let re: RlError = r.error;
    return _err_poll(_map_rl_error("session_send", re));
  }
  let ob: RlOutbound = r.value;
  let e = _emit_message(s, &mut poll, channel, ob.seq, &ob.payload);
  if !e.is_ok {
    return _err_poll(e.error);
  }
  s.stats.messages_sent = s.stats.messages_sent + 1;
  return _ok_poll(poll);
}

/// Additive rate-limited send: refill `w` to now_ms, refuse with TX_ERR_RATE
/// when the payload does not fit, otherwise delegate to session_send and
/// consume the payload bytes only after the send succeeds. Existing callers
/// of session_send are untouched; this wrapper changes nothing unless used.
/// The budget is application payload bytes, not encoded frame bytes.
pub fn session_send_rate_limited(s: &mut Session, channel: Int, payload: &Vec[UInt8], now_ms: Int, w: &mut RateWindow) -> Result[SessionPoll, SessionError] {
  let _ = rate_refill(w, now_ms);
  let need = payload.len();
  if !rate_can_send(w, need) {
    let _ = rate_consume(w, need);
    return _err_poll(_sxerr(TX_ERR_RATE, 0, "session_send_rate_limited: send window exhausted (" + need.to_str() + " > " + rate_window_bytes(w).to_str() + ")"));
  }
  let r = session_send(s, channel, payload, now_ms);
  if !r.is_ok {
    return r;
  }
  let _ = rate_consume(w, need);
  return r;
}

// ---------------------------------------------------------------------------
// Receive: reassembly
// ---------------------------------------------------------------------------

fn _reasm_index(s: &Session, channel: Int, seq: Int) -> Int {
  var i = 0;
  while i < s.reasm.len() {
    let r: ReasmEntry = s.reasm[i];
    if r.channel == channel && r.seq == seq { return i; }
    i = i + 1;
  }
  return -1;
}

fn _reasm_remove(s: &mut Session, idx: Int) {
  var survivors: Vec[ReasmEntry] = Vec[ReasmEntry].new();
  var i = 0;
  while i < s.reasm.len() {
    if i != idx {
      let r: ReasmEntry = s.reasm[i];
      survivors.push(r);
    }
    i = i + 1;
  }
  s.reasm = survivors;
}

// A fresh, incompleteness outcome (each return site builds its own; a
// shared value would be moved twice and the toolchain forbids that).
fn _reasm_incomplete() -> ReasmOutcome {
  return ReasmOutcome { complete: false; payload: Vec[UInt8].new(); };
}

// Place one fragment; a complete outcome carries the full message.
fn _reasm_place(s: &mut Session, f: &Frame) -> Result[ReasmOutcome, SessionError] {
  var idx = _reasm_index(s, f.channel, f.seq);
  if idx < 0 {
    if s.reasm.len() >= TX_MAX_REASM_ENTRIES {
      return _err_outcome(_sxerr(TX_ERR_BUFFER, 0, "session: reassembly buffer full"));
    }
    var got: Vec[Bool] = Vec[Bool].new();
    var payload: Vec[UInt8] = Vec[UInt8].new();
    var i = 0;
    while i < f.frag_count {
      got.push(false);
      i = i + 1;
    }
    var j = 0;
    while j < f.frag_total {
      payload.push(0 as UInt8);
      j = j + 1;
    }
    var entry = ReasmEntry {
      channel: f.channel;
      seq: f.seq;
      count: f.frag_count;
      total: f.frag_total;
      got: got;
      payload: payload;
    };
    s.reasm.push(entry);
    idx = s.reasm.len() - 1;
  } else {
    let existing: ReasmEntry = s.reasm[idx];
    if existing.count != f.frag_count || existing.total != f.frag_total {
      return _err_outcome(_sxerr(TX_ERR_FRAME, FRAME_ERR_FRAG, "session: fragment metadata inconsistent with earlier pieces"));
    }
  }
  var work: ReasmEntry = s.reasm[idx];
  var is_dup = false;
  let gi: Bool = work.got[f.frag_index];
  if gi {
    is_dup = true;
    s.stats.reasm_duplicates = s.stats.reasm_duplicates + 1;
  } else {
    work.got[f.frag_index] = true;
    var i = 0;
    while i < f.payload.len() {
      let b: UInt8 = f.payload[i];
      work.payload[f.frag_offset + i] = b;
      i = i + 1;
    }
    s.stats.fragments_recv = s.stats.fragments_recv + 1;
  }
  s.reasm[idx] = work;
  if is_dup {
    return _ok_outcome(_reasm_incomplete());
  }
  var complete = true;
  var check: ReasmEntry = s.reasm[idx];
  var k = 0;
  while k < check.got.len() {
    let g: Bool = check.got[k];
    if !g { complete = false; }
    k = k + 1;
  }
  if !complete {
    return _ok_outcome(_reasm_incomplete());
  }
  var taken: ReasmEntry = s.reasm[idx];
  var done = ReasmOutcome { complete: true; payload: taken.payload };
  _reasm_remove(s, idx);
  s.stats.reasm_completed = s.stats.reasm_completed + 1;
  return _ok_outcome(done);
}

// ---------------------------------------------------------------------------
// Receive: frame dispatch
// ---------------------------------------------------------------------------

// Deliver one complete message through the reliability engine, emitting
// delivery events and the acknowledging frame.
fn _accept_message(s: &mut Session, poll: &mut SessionPoll, channel: Int, seq: Int, payload: &Vec[UInt8], now_ms: Int) -> Result[Unit, SessionError] {
  let r = rl_on_packet(&mut s.engine, channel, seq, payload, now_ms);
  if !r.is_ok {
    let re: RlError = r.error;
    return _err_poll_unit(_map_rl_error("session_on_packet", re));
  }
  let rr: RlRecvResult = r.value;
  var i = 0;
  while i < rr.delivered.len() {
    let m: RlMessage = rr.delivered[i];
    s.stats.messages_delivered = s.stats.messages_delivered + 1;
    poll.events.push(EvDelivered(channel: m.channel, seq: m.seq, payload: m.payload));
    i = i + 1;
  }
  // Acknowledge every accepted/refused data frame with the current
  // watermark (re-acks are cheap and keep the sender truthful).
  var af = frame_ack(s.conn_id, channel, rr.ack, rr.ack_bits);
  if _emit(s, poll, &af) {
    s.stats.acks_sent = s.stats.acks_sent + 1;
  }
  return _ok_unit_result();
}

fn _err_poll_unit(e: SessionError) -> Result[Unit, SessionError] { return Err(e); }

fn _handle_data(s: &mut Session, poll: &mut SessionPoll, f: &Frame, now_ms: Int) -> Result[Unit, SessionError] {
  match s.state {
    Active => {},
    Draining => {},
    Connecting => {
      return _err_poll_unit(_sxerr(TX_ERR_STATE, 0, "session_on_packet: data in connecting"));
    },
    Handshaking => {
      return _err_poll_unit(_sxerr(TX_ERR_STATE, 0, "session_on_packet: data before active"));
    },
    Closed => {
      return _err_poll_unit(_sxerr(TX_ERR_STATE, 0, "session_on_packet: data after close"));
    },
  }
  if !rl_channel_exists(&s.engine, f.channel) {
    return _err_poll_unit(_sxerr(TX_ERR_CHANNEL, RL_ERR_CHANNEL, "session_on_packet: unknown channel " + f.channel.to_str()));
  }
  if f.fragment {
    let ro = _reasm_place(s, f);
    if !ro.is_ok {
      return _err_poll_unit(ro.error);
    }
    let out: ReasmOutcome = ro.value;
    if !out.complete {
      return _ok_unit_result();
    }
    let e = _accept_message(s, poll, f.channel, f.seq, &out.payload, now_ms);
    return e;
  }
  return _accept_message(s, poll, f.channel, f.seq, &f.payload, now_ms);
}

/// Receive one datagram: decode exactly one frame, dispatch by kind and
/// state, and return the frames this side owes (acks, pongs, hello_ack,
/// FIN) plus the typed events observed. A refuse (bad version, unknown
/// channel, oversized frame) is a typed verdict.
pub fn session_on_packet(s: &mut Session, bytes: &Vec[UInt8], now_ms: Int) -> Result[SessionPoll, SessionError] {
  var poll = _make_poll();
  match s.state {
    Closed => {
      return _err_poll(_sxerr(TX_ERR_STATE, 0, "session_on_packet: session closed"));
    },
    _ => {},
  }
  let dec = frame_decode(bytes, 0);
  if !dec.is_ok {
    let fe: FrameError = dec.error;
    return _err_poll(_sxerr(TX_ERR_FRAME, fe.kind, "session_on_packet: " + fe.message + " (offset " + fe.offset.to_str() + ")"));
  }
  let f: Frame = dec.value;
  s.stats.frames_recv = s.stats.frames_recv + 1;
  s.stats.bytes_recv = s.stats.bytes_recv + bytes.len();
  if f.conn_id != s.conn_id {
    return _err_poll(_sxerr(TX_ERR_CONN_ID, 0, "session_on_packet: frame conn_id mismatch"));
  }
  if f.kind == FRAME_KIND_HELLO {
    poll.events.push(EvHello(protocol_version: f.protocol_version));
    if f.protocol_version != s.local_protocol_version {
      _refuse_version(s, &mut poll, f.protocol_version);
      return _ok_poll(poll);
    }
    s.peer_hello_seen = true;
    s.peer_protocol_version = f.protocol_version;
    if !s.hello_ack_sent {
      var af = frame_hello_ack(s.conn_id, s.local_protocol_version);
      if !_emit(s, &mut poll, &af) {
        return _err_poll(_sxerr(TX_ERR_FRAME, 0, "session_on_packet: hello_ack encode failed"));
      }
      s.hello_ack_sent = true;
    }
    return _ok_poll(poll);
  }
  if f.kind == FRAME_KIND_HELLO_ACK {
    if !s.hello_sent {
      return _err_poll(_sxerr(TX_ERR_STATE, 0, "session_on_packet: hello_ack before hello"));
    }
    poll.events.push(EvHelloAck(protocol_version: f.protocol_version));
    if f.protocol_version != s.local_protocol_version {
      _refuse_version(s, &mut poll, f.protocol_version);
      return _ok_poll(poll);
    }
    s.peer_hello_ack_seen = true;
    s.peer_protocol_version = f.protocol_version;
    _transition(s, &mut poll, Active);
    return _ok_poll(poll);
  }
  if f.kind == FRAME_KIND_DATA {
    let e = _handle_data(s, &mut poll, &f, now_ms);
    if !e.is_ok {
      return _err_poll(e.error);
    }
    return _ok_poll(poll);
  }
  if f.kind == FRAME_KIND_ACK {
    let r = rl_on_ack(&mut s.engine, f.channel, f.ack, f.ack_bits);
    if !r.is_ok {
      let re: RlError = r.error;
      return _err_poll(_map_rl_error("session_on_packet: ack", re));
    }
    return _ok_poll(poll);
  }
  if f.kind == FRAME_KIND_PING {
    s.stats.pings = s.stats.pings + 1;
    poll.events.push(EvPing);
    var pf = frame_pong(s.conn_id);
    if !_emit(s, &mut poll, &pf) {
      return _err_poll(_sxerr(TX_ERR_FRAME, 0, "session_on_packet: pong encode failed"));
    }
    return _ok_poll(poll);
  }
  if f.kind == FRAME_KIND_PONG {
    s.stats.pongs = s.stats.pongs + 1;
    poll.events.push(EvPong);
    return _ok_poll(poll);
  }
  // FRAME_KIND_FIN
  poll.events.push(EvFinish(reason: f.fin_reason));
  if !s.fin_sent {
    s.fin_reason = FIN_REASON_NONE;
    _emit_fin(s, &mut poll);
  }
  _transition(s, &mut poll, Closed);
  return _ok_poll(poll);
}

// ---------------------------------------------------------------------------
// Poll: due retransmissions + failure verdicts
// ---------------------------------------------------------------------------

/// Step the injected clock: emit every retransmission due now and turn
/// exhausted reliability records into typed failure events plus a
/// draining transition (with FIN_REASON_TIMEOUT). Deterministic: same
/// state + same now_ms => same output.
pub fn session_poll(s: &mut Session, now_ms: Int) -> Result[SessionPoll, SessionError] {
  var poll = _make_poll();
  match s.state {
    Closed => {
      return _ok_poll(poll);
    },
    _ => {},
  }
  let rtx = rl_poll_rtx(&mut s.engine, now_ms);
  if !rtx.is_ok {
    let re: RlError = rtx.error;
    return _err_poll(_map_rl_error("session_poll", re));
  }
  let outs: Vec[RlOutbound] = rtx.value;
  var i = 0;
  while i < outs.len() {
    let ob: RlOutbound = outs[i];
    let e = _emit_message(s, &mut poll, ob.channel, ob.seq, &ob.payload);
    if !e.is_ok {
      return _err_poll(e.error);
    }
    i = i + 1;
  }
  let failures = rl_take_failures(&mut s.engine);
  var j = 0;
  while j < failures.len() {
    let fl: RlFailure = failures[j];
    s.stats.failures = s.stats.failures + 1;
    poll.events.push(EvFailure(kind: fl.kind, channel: fl.channel, seq: fl.seq));
    match s.state {
      Active => {
        if s.fin_reason == FIN_REASON_NONE {
          s.fin_reason = FIN_REASON_TIMEOUT;
        }
        _emit_fin(s, &mut poll);
        _transition(s, &mut poll, Draining);
      },
      Handshaking => {
        if s.fin_reason == FIN_REASON_NONE {
          s.fin_reason = FIN_REASON_TIMEOUT;
        }
        _emit_fin(s, &mut poll);
        _transition(s, &mut poll, Draining);
      },
      _ => {},
    }
    j = j + 1;
  }
  return _ok_poll(poll);
}
