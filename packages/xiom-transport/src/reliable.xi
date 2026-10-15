// XIOM -- xiom.transport.reliable: pure reliability engine over an injected
// clock
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The L2 reliability engine of the transport: per-channel bounded send
// windows, an unacked (inflight) map, acknowledgement and ack-bitfield
// processing, RTO with bounded exponential backoff, a retransmit path,
// duplicate suppression, ordered-delivery buffering (unordered channels
// flush immediately) and stats accounting.
//
// Purity rules (declared): every call takes now_ms from the caller -- the
// engine never reads a wall clock, never uses randomness and keeps no
// globals. An engine value is plain state: step it through the functions
// below, read it through the introspection functions.
//
// Every timeout/failure path is a TYPED verdict: exhausted bounded
// retransmits become RlFailure records (kind RL_ERR_RETRIES) retrieved
// with rl_take_failures; window exhaustion is RL_ERR_WINDOW; unknown
// channels RL_ERR_CHANNEL; far-future sequences are refused as
// out-of-window (a verdict, never a hang).
//
// Sequence discipline (per channel; each side tracks its own view):
//   * send side: next_seq starts at 0 and advances one step per message;
//     reliable messages stay in the inflight map until acked;
//   * receive side: recv_next is the lowest sequence NOT yet received;
//     recv_mask bit i (0..=63, RL_RECV_WINDOW = 63) marks sequence
//     recv_next + i as received, so bit 0 is always clear after every
//     normalization. Receiving recv_next itself normalizes: recv_next
//     advances past every contiguous received sequence, delivering the
//     passing messages in sequence order (held buffer for ordered
//     channels; already delivered for unordered ones);
//   * ack = recv_next - 1 (highest contiguous received; -1 = none). Ack
//     frames carry low 32 mask bits; a data-frame ack piggybacks the
//     same pair.
//
// Language notes (XIOM v0.64.5): free functions only; Ok/Err construction
// confined to leaf helpers; every Vec element read binds a typed local;
// payload copies are explicit (`_copy_bytes`) so no value is aliased
// across engine records; no `?` operator.

module xiom.transport.reliable

// ---------------------------------------------------------------------------
// Bounds (all declared, no magic numbers at call sites)
// ---------------------------------------------------------------------------

/// Send window is bounded to 32 so one ack frame's 32-bit bitfield always
/// covers the whole inflight map.
pub const RL_MAX_WINDOW: Int = 32;

/// Receive window width: sequences recv_next+1 .. recv_next+63 are
/// tracked (63 keeps every mask bit inside a 64-bit Int).
pub const RL_RECV_WINDOW: Int = 63;

/// Base retransmission timeout in milliseconds.
pub const RL_DEFAULT_RTO_MS: Int = 100;

/// Exponential backoff cap in milliseconds (bounded backoff).
pub const RL_MAX_RTO_MS: Int = 3200;

/// Bounded retransmit budget: a record reaching this retry count becomes
/// a typed failure verdict (never an unbounded retry loop).
pub const RL_MAX_RETRIES: Int = 5;

// Failure kinds (RlError.kind, RlFailure.kind).
pub const RL_ERR_CHANNEL: Int = 1;
pub const RL_ERR_WINDOW: Int = 2;
pub const RL_ERR_RETRIES: Int = 3;
pub const RL_ERR_SEQ: Int = 4;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A typed reliability failure. `channel` and `seq` locate the record the
/// verdict belongs to (-1 when not applicable).
pub type RlError = {
  kind: Int;
  channel: Int;
  seq: Int;
  message: Str;
}

/// One unacked reliable message awaiting acknowledgement.
pub type RlInflight = {
  seq: Int;
  payload: Vec[UInt8];
  sent_at_ms: Int;
  retries: Int;
}

/// A message handed to the wire (initial send or retransmission).
pub type RlOutbound = {
  channel: Int;
  seq: Int;
  payload: Vec[UInt8];
}

/// A message ready for application delivery.
pub type RlMessage = {
  channel: Int;
  seq: Int;
  payload: Vec[UInt8];
}

/// A typed failure verdict retrieved from the engine.
pub type RlFailure = {
  channel: Int;
  seq: Int;
  kind: Int;
  retries: Int;
}

/// Per-channel counters; the aggregate in rl_stats is their exact sum.
pub type RlChannelStats = {
  id: Int;
  sent: Int;
  recv: Int;
  delivered: Int;
  acked: Int;
  retransmits: Int;
  dup_dropped: Int;
  stale: Int;
  out_of_window: Int;
  timeouts: Int;
  held: Int;
}

/// One channel: declared semantics plus live state. `reliable` gates the
/// send-side tracking (window/inflight/retransmit); receive-side ordering
/// and duplicate suppression run for every channel.
pub type RlChannel = {
  id: Int;
  reliable: Bool;
  ordered: Bool;
  priority: Int;
  window: Int;
  next_seq: Int;
  inflight: Vec[RlInflight];
  recv_next: Int;
  recv_mask: Int;
  held: Vec[RlMessage];
  stats: RlChannelStats;
}

/// The engine: a plain value, stepped only through the functions below.
pub type RlEngine = {
  channels: Vec[RlChannel];
  failed: Vec[RlFailure];
}

/// Receive-side outcome of one accepted/refused packet.
pub type RlRecvResult = {
  delivered: Vec[RlMessage];
  ack: Int;
  ack_bits: Int;
  duplicate: Bool;
  stale: Bool;
  out_of_window: Bool;
  held: Bool;
}

/// Aggregate counters across every channel (exact sums).
pub type RlStats = {
  sent: Int;
  recv: Int;
  delivered: Int;
  acked: Int;
  retransmits: Int;
  dup_dropped: Int;
  stale: Int;
  out_of_window: Int;
  timeouts: Int;
  held: Int;
}

// ---------------------------------------------------------------------------
// Leaf helpers
// ---------------------------------------------------------------------------

fn _rlerr(kind: Int, channel: Int, seq: Int, message: Str) -> RlError {
  return RlError { kind: kind, channel: channel, seq: seq, message: message };
}

fn _ok_bool(v: Bool) -> Result[Bool, RlError] { return Ok(v); }
fn _err_bool(e: RlError) -> Result[Bool, RlError] { return Err(e); }
fn _ok_int(v: Int) -> Result[Int, RlError] { return Ok(v); }
fn _err_int(e: RlError) -> Result[Int, RlError] { return Err(e); }
fn _ok_outbounds(v: Vec[RlOutbound]) -> Result[Vec[RlOutbound], RlError] { return Ok(v); }
fn _err_outbounds(e: RlError) -> Result[Vec[RlOutbound], RlError] { return Err(e); }
fn _ok_outbound(v: RlOutbound) -> Result[RlOutbound, RlError] { return Ok(v); }
fn _err_outbound(e: RlError) -> Result[RlOutbound, RlError] { return Err(e); }
fn _ok_recv(v: RlRecvResult) -> Result[RlRecvResult, RlError] { return Ok(v); }
fn _err_recv(e: RlError) -> Result[RlRecvResult, RlError] { return Err(e); }
fn _ok_msgs(v: Vec[RlMessage]) -> Result[Vec[RlMessage], RlError] { return Ok(v); }
fn _err_msgs(e: RlError) -> Result[Vec[RlMessage], RlError] { return Err(e); }
fn _ok_int_vec(v: Vec[Int]) -> Result[Vec[Int], RlError] { return Ok(v); }
fn _err_int_vec(e: RlError) -> Result[Vec[Int], RlError] { return Err(e); }
fn _ok_cstats(v: RlChannelStats) -> Result[RlChannelStats, RlError] { return Ok(v); }
fn _err_cstats(e: RlError) -> Result[RlChannelStats, RlError] { return Err(e); }

fn _copy_bytes(src: &Vec[UInt8]) -> Vec[UInt8] {
  var out: Vec[UInt8] = Vec[UInt8].new();
  var i = 0;
  while i < src.len() {
    let b: UInt8 = src[i];
    out.push(b);
    i = i + 1;
  }
  return out;
}

fn _empty_cstats(id: Int) -> RlChannelStats {
  return RlChannelStats {
    id: id;
    sent: 0;
    recv: 0;
    delivered: 0;
    acked: 0;
    retransmits: 0;
    dup_dropped: 0;
    stale: 0;
    out_of_window: 0;
    timeouts: 0;
    held: 0;
  };
}

fn _empty_recv() -> RlRecvResult {
  var empty: Vec[RlMessage] = Vec[RlMessage].new();
  return RlRecvResult {
    delivered: empty;
    ack: -1;
    ack_bits: 0;
    duplicate: false;
    stale: false;
    out_of_window: false;
    held: false;
  };
}

fn _channel_index(e: &RlEngine, id: Int) -> Int {
  var i = 0;
  while i < e.channels.len() {
    let c: RlChannel = e.channels[i];
    if c.id == id { return i; }
    i = i + 1;
  }
  return -1;
}

// ---------------------------------------------------------------------------
// Construction
// ---------------------------------------------------------------------------

pub fn rl_new() -> RlEngine {
  var chans: Vec[RlChannel] = Vec[RlChannel].new();
  var failed: Vec[RlFailure] = Vec[RlFailure].new();
  return RlEngine { channels: chans, failed: failed };
}

/// Open a channel: id 0..255, window clamped to [1, RL_MAX_WINDOW]; a
/// re-open of an existing id is Ok(false), never an error.
pub fn rl_open_channel(e: &mut RlEngine, id: Int, reliable: Bool, ordered: Bool, priority: Int, window: Int) -> Result[Bool, RlError] {
  if id < 0 || id > 255 {
    return _err_bool(_rlerr(RL_ERR_CHANNEL, id, -1, "rl_open_channel: channel id out of 0..255"));
  }
  if _channel_index(e, id) >= 0 {
    return _ok_bool(false);
  }
  var w = window;
  if w < 1 { w = 1; }
  if w > RL_MAX_WINDOW { w = RL_MAX_WINDOW; }
  var pr = priority;
  if pr < 0 { pr = 0; }
  var inflight: Vec[RlInflight] = Vec[RlInflight].new();
  var held: Vec[RlMessage] = Vec[RlMessage].new();
  var ch = RlChannel {
    id: id;
    reliable: reliable;
    ordered: ordered;
    priority: pr;
    window: w;
    next_seq: 0;
    inflight: inflight;
    recv_next: 0;
    recv_mask: 0;
    held: held;
    stats: _empty_cstats(id);
  };
  e.channels.push(ch);
  return _ok_bool(true);
}

/// Close a channel, dropping its state; true when it existed.
pub fn rl_close_channel(e: &mut RlEngine, id: Int) -> Bool {
  let idx = _channel_index(e, id);
  if idx < 0 { return false; }
  var survivors: Vec[RlChannel] = Vec[RlChannel].new();
  var i = 0;
  while i < e.channels.len() {
    if i != idx {
      let c: RlChannel = e.channels[i];
      survivors.push(c);
    }
    i = i + 1;
  }
  e.channels = survivors;
  return true;
}

pub fn rl_channel_exists(e: &RlEngine, id: Int) -> Bool {
  if _channel_index(e, id) >= 0 { return true; }
  return false;
}

pub fn rl_channel_count(e: &RlEngine) -> Int {
  return e.channels.len();
}

// ---------------------------------------------------------------------------
// Clock-derived policy (pure functions of the injected clock/attempt)
// ---------------------------------------------------------------------------

/// RTO for a retry count: base << retries, capped at RL_MAX_RTO_MS
/// (100, 200, 400, 800, 1600, 3200, 3200, ...).
pub fn rl_rto_ms(retries: Int) -> Int {
  if retries <= 0 { return RL_DEFAULT_RTO_MS; }
  var v = RL_DEFAULT_RTO_MS;
  var k = 0;
  while k < retries {
    v = v * 2;
    if v >= RL_MAX_RTO_MS { return RL_MAX_RTO_MS; }
    k = k + 1;
  }
  return v;
}

/// True when seq is covered by an (ack, ack_bits) pair: ack itself, or
/// within the 32 slots below it that the bitfield marks.
pub fn rl_seq_acked(seq: Int, ack: Int, ack_bits: Int) -> Bool {
  if ack < 0 { return false; }
  if seq > ack { return false; }
  if seq == ack { return true; }
  let d = ack - seq;
  if d > 32 { return false; }
  let bit = 1 << (d - 1);
  if (ack_bits & bit) != 0 { return true; }
  return false;
}

// ---------------------------------------------------------------------------
// Send side
// ---------------------------------------------------------------------------

/// Hand one message to a channel. Reliable channels bound the inflight
/// map at the channel window (RL_ERR_WINDOW when full); unreliable
/// channels assign a sequence and count the send only.
pub fn rl_send(e: &mut RlEngine, channel: Int, payload: &Vec[UInt8], now_ms: Int) -> Result[RlOutbound, RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_outbound(_rlerr(RL_ERR_CHANNEL, channel, -1, "rl_send: unknown channel"));
  }
  if e.channels[ci].reliable {
    if e.channels[ci].inflight.len() >= e.channels[ci].window {
      return _err_outbound(_rlerr(RL_ERR_WINDOW, channel, e.channels[ci].next_seq, "rl_send: send window full"));
    }
  }
  let seq = e.channels[ci].next_seq;
  e.channels[ci].next_seq = seq + 1;
  e.channels[ci].stats.sent = e.channels[ci].stats.sent + 1;
  var ob = RlOutbound { channel: channel; seq: seq; payload: _copy_bytes(payload); };
  if e.channels[ci].reliable {
    var inf = RlInflight { seq: seq; payload: _copy_bytes(payload); sent_at_ms: now_ms; retries: 0; };
    e.channels[ci].inflight.push(inf);
  }
  return _ok_outbound(ob);
}

/// Process an acknowledgement (ack + bitfield) for a channel; returns the
/// number of inflight records newly acked.
pub fn rl_on_ack(e: &mut RlEngine, channel: Int, ack: Int, ack_bits: Int) -> Result[Int, RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_int(_rlerr(RL_ERR_CHANNEL, channel, -1, "rl_on_ack: unknown channel"));
  }
  var ch: RlChannel = e.channels[ci];
  var survivors: Vec[RlInflight] = Vec[RlInflight].new();
  var acked = 0;
  var j = 0;
  while j < ch.inflight.len() {
    let inf: RlInflight = ch.inflight[j];
    if rl_seq_acked(inf.seq, ack, ack_bits) {
      acked = acked + 1;
    } else {
      survivors.push(inf);
    }
    j = j + 1;
  }
  ch.inflight = survivors;
  ch.stats.acked = ch.stats.acked + acked;
  e.channels[ci] = ch;
  return _ok_int(acked);
}

/// Collect every retransmission due at now_ms. A record whose bounded
/// retry budget is exhausted is NOT retransmitted again: it is removed
/// and recorded as a typed failure (kind RL_ERR_RETRIES) retrievable
/// through rl_take_failures.
pub fn rl_poll_rtx(e: &mut RlEngine, now_ms: Int) -> Result[Vec[RlOutbound], RlError] {
  var out: Vec[RlOutbound] = Vec[RlOutbound].new();
  var ci = 0;
  while ci < e.channels.len() {
    var ch: RlChannel = e.channels[ci];
    if ch.reliable && ch.inflight.len() > 0 {
      var survivors: Vec[RlInflight] = Vec[RlInflight].new();
      var j = 0;
      while j < ch.inflight.len() {
        var inf: RlInflight = ch.inflight[j];
        let due = inf.sent_at_ms + rl_rto_ms(inf.retries);
        if now_ms >= due {
          let next_retries = inf.retries + 1;
          if next_retries >= RL_MAX_RETRIES {
            ch.stats.timeouts = ch.stats.timeouts + 1;
            var fmsg = RlFailure { channel: ch.id; seq: inf.seq; kind: RL_ERR_RETRIES; retries: inf.retries; };
            e.failed.push(fmsg);
          } else {
            inf.retries = next_retries;
            inf.sent_at_ms = now_ms;
            survivors.push(inf);
            ch.stats.retransmits = ch.stats.retransmits + 1;
            var ob = RlOutbound { channel: ch.id; seq: inf.seq; payload: inf.payload; };
            out.push(ob);
          }
        } else {
          survivors.push(inf);
        }
        j = j + 1;
      }
      ch.inflight = survivors;
      e.channels[ci] = ch;
    }
    ci = ci + 1;
  }
  return _ok_outbounds(out);
}

/// Drain and return the typed failure verdicts accumulated so far.
pub fn rl_take_failures(e: &mut RlEngine) -> Vec[RlFailure] {
  var out: Vec[RlFailure] = Vec[RlFailure].new();
  var i = 0;
  while i < e.failed.len() {
    let f: RlFailure = e.failed[i];
    out.push(f);
    i = i + 1;
  }
  e.failed = Vec[RlFailure].new();
  return out;
}

// ---------------------------------------------------------------------------
// Receive side
// ---------------------------------------------------------------------------

// Insert a held message keeping the vector ascending by seq (duplicates
// are excluded before insertion).
fn _hold_insert(ch: &mut RlChannel, msg: RlMessage) {
  var out: Vec[RlMessage] = Vec[RlMessage].new();
  var placed = false;
  var i = 0;
  while i < ch.held.len() {
    let m: RlMessage = ch.held[i];
    if !placed && msg.seq < m.seq {
      out.push(msg);
      placed = true;
    }
    out.push(m);
    i = i + 1;
  }
  if !placed {
    out.push(msg);
  }
  ch.held = out;
}

// Remove and return the held message for seq, if any (rebuilt vector).
fn _hold_take(ch: &mut RlChannel, seq: Int) -> Option[RlMessage] {
  var found = false;
  var out: Vec[RlMessage] = Vec[RlMessage].new();
  var msg: RlMessage = RlMessage { channel: ch.id; seq: seq; payload: Vec[UInt8].new(); };
  var i = 0;
  while i < ch.held.len() {
    let m: RlMessage = ch.held[i];
    if m.seq == seq {
      found = true;
      msg = m;
    } else {
      out.push(m);
    }
    i = i + 1;
  }
  ch.held = out;
  if found {
    return Some(msg);
  }
  return None;
}

/// Accept one received message for a channel: duplicate suppression,
/// windowed ordering, ordered buffer / immediate unordered delivery, ack
/// computation. `stale` means "below recv_next" (long gone); `duplicate`
/// means "inside the window but already received"; `out_of_window` means
/// "beyond recv_next + 63" (refused, nothing recorded).
pub fn rl_on_packet(e: &mut RlEngine, channel: Int, seq: Int, payload: &Vec[UInt8], now_ms: Int) -> Result[RlRecvResult, RlError] {
  let _ = now_ms;
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_recv(_rlerr(RL_ERR_CHANNEL, channel, seq, "rl_on_packet: unknown channel"));
  }
  if seq < 0 {
    return _err_recv(_rlerr(RL_ERR_SEQ, channel, seq, "rl_on_packet: negative sequence"));
  }
  var res = _empty_recv();
  var ch: RlChannel = e.channels[ci];

  if seq < ch.recv_next {
    ch.stats.stale = ch.stats.stale + 1;
    ch.stats.dup_dropped = ch.stats.dup_dropped + 1;
    res.stale = true;
  } else {
    if seq - ch.recv_next > RL_RECV_WINDOW {
      ch.stats.out_of_window = ch.stats.out_of_window + 1;
      res.out_of_window = true;
    } else {
      let d = seq - ch.recv_next;
      let bit = 1 << d;
      if (ch.recv_mask & bit) != 0 {
        ch.stats.dup_dropped = ch.stats.dup_dropped + 1;
        res.duplicate = true;
      } else {
        ch.recv_mask = ch.recv_mask | bit;
        ch.stats.recv = ch.stats.recv + 1;
        if d == 0 {
          // recv_next itself: mark and normalize, delivering the passing
          // messages in sequence order. The first pass carries the
          // caller's payload; later passes come from the held buffer
          // (ordered) or were already delivered (unordered).
          var first = true;
          while (ch.recv_mask & 1) != 0 {
            let passed = ch.recv_next;
            ch.recv_mask = ch.recv_mask >> 1;
            ch.recv_next = ch.recv_next + 1;
            if first {
              first = false;
              ch.stats.delivered = ch.stats.delivered + 1;
              var msg = RlMessage { channel: channel; seq: passed; payload: _copy_bytes(payload); };
              res.delivered.push(msg);
            } else {
              if ch.ordered {
                let t = _hold_take(&mut ch, passed);
                match t {
                  Some(m) => {
                    ch.stats.delivered = ch.stats.delivered + 1;
                    res.delivered.push(m);
                  },
                  None => {},
                }
              }
            }
          }
        } else {
          var msg = RlMessage { channel: channel; seq: seq; payload: _copy_bytes(payload); };
          if ch.ordered {
            _hold_insert(&mut ch, msg);
            ch.stats.held = ch.stats.held + 1;
            res.held = true;
          } else {
            ch.stats.delivered = ch.stats.delivered + 1;
            res.delivered.push(msg);
          }
          // Bit 0 is clear by invariant here, so this loop is a no-op;
          // kept for defense against future edits.
          while (ch.recv_mask & 1) != 0 {
            let passed = ch.recv_next;
            ch.recv_mask = ch.recv_mask >> 1;
            ch.recv_next = ch.recv_next + 1;
            if ch.ordered {
              let t = _hold_take(&mut ch, passed);
              match t {
                Some(m) => {
                  ch.stats.delivered = ch.stats.delivered + 1;
                  res.delivered.push(m);
                },
                None => {},
              }
            }
          }
        }
      }
    }
  }
  if ch.recv_next > 0 {
    res.ack = ch.recv_next - 1;
  } else {
    res.ack = -1;
  }
  res.ack_bits = ch.recv_mask & 4294967295;
  e.channels[ci] = ch;
  return _ok_recv(res);
}

/// Force a receive gap closed (explicit, caller-driven: unreliable-ordered
/// channels cannot heal a loss by retransmission). Every held message at
/// or below upto_seq is delivered in sequence order; the mask is shifted
/// to the new recv_next.
pub fn rl_skip_gap(e: &mut RlEngine, channel: Int, upto_seq: Int) -> Result[Vec[RlMessage], RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_msgs(_rlerr(RL_ERR_CHANNEL, channel, upto_seq, "rl_skip_gap: unknown channel"));
  }
  var out: Vec[RlMessage] = Vec[RlMessage].new();
  var ch: RlChannel = e.channels[ci];
  if upto_seq < ch.recv_next {
    e.channels[ci] = ch;
    return _ok_msgs(out);
  }
  let delta = upto_seq - ch.recv_next + 1;
  ch.recv_next = upto_seq + 1;
  if delta >= RL_RECV_WINDOW {
    ch.recv_mask = 0;
  } else {
    ch.recv_mask = ch.recv_mask >> delta;
  }
  var kept: Vec[RlMessage] = Vec[RlMessage].new();
  var i = 0;
  while i < ch.held.len() {
    let m: RlMessage = ch.held[i];
    if m.seq < ch.recv_next {
      ch.stats.delivered = ch.stats.delivered + 1;
      out.push(m);
    } else {
      kept.push(m);
    }
    i = i + 1;
  }
  ch.held = kept;
  e.channels[ci] = ch;
  return _ok_msgs(out);
}

// ---------------------------------------------------------------------------
// Introspection (copy-out views for callers and the suite)
// ---------------------------------------------------------------------------

pub fn rl_unacked_seqs(e: &RlEngine, channel: Int) -> Result[Vec[Int], RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_int_vec(_rlerr(RL_ERR_CHANNEL, channel, -1, "rl_unacked_seqs: unknown channel"));
  }
  var out: Vec[Int] = Vec[Int].new();
  let ch: RlChannel = e.channels[ci];
  var j = 0;
  while j < ch.inflight.len() {
    let inf: RlInflight = ch.inflight[j];
    out.push(inf.seq);
    j = j + 1;
  }
  return _ok_int_vec(out);
}

pub fn rl_inflight_len(e: &RlEngine, channel: Int) -> Result[Int, RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_int(_rlerr(RL_ERR_CHANNEL, channel, -1, "rl_inflight_len: unknown channel"));
  }
  let ch: RlChannel = e.channels[ci];
  return _ok_int(ch.inflight.len());
}

pub fn rl_held_len(e: &RlEngine, channel: Int) -> Result[Int, RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_int(_rlerr(RL_ERR_CHANNEL, channel, -1, "rl_held_len: unknown channel"));
  }
  let ch: RlChannel = e.channels[ci];
  return _ok_int(ch.held.len());
}

pub fn rl_recv_next(e: &RlEngine, channel: Int) -> Result[Int, RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_int(_rlerr(RL_ERR_CHANNEL, channel, -1, "rl_recv_next: unknown channel"));
  }
  let ch: RlChannel = e.channels[ci];
  return _ok_int(ch.recv_next);
}

pub fn rl_recv_mask(e: &RlEngine, channel: Int) -> Result[Int, RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_int(_rlerr(RL_ERR_CHANNEL, channel, -1, "rl_recv_mask: unknown channel"));
  }
  let ch: RlChannel = e.channels[ci];
  return _ok_int(ch.recv_mask);
}

pub fn rl_next_seq(e: &RlEngine, channel: Int) -> Result[Int, RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_int(_rlerr(RL_ERR_CHANNEL, channel, -1, "rl_next_seq: unknown channel"));
  }
  let ch: RlChannel = e.channels[ci];
  return _ok_int(ch.next_seq);
}

pub fn rl_channel_stats(e: &RlEngine, channel: Int) -> Result[RlChannelStats, RlError] {
  let ci = _channel_index(e, channel);
  if ci < 0 {
    return _err_cstats(_rlerr(RL_ERR_CHANNEL, channel, -1, "rl_channel_stats: unknown channel"));
  }
  let ch: RlChannel = e.channels[ci];
  return _ok_cstats(ch.stats);
}

/// Exact aggregate counters: the sum over every channel.
pub fn rl_stats(e: &RlEngine) -> RlStats {
  var s = RlStats {
    sent: 0; recv: 0; delivered: 0; acked: 0; retransmits: 0;
    dup_dropped: 0; stale: 0; out_of_window: 0; timeouts: 0; held: 0;
  };
  var i = 0;
  while i < e.channels.len() {
    let c: RlChannel = e.channels[i];
    let cs: RlChannelStats = c.stats;
    s.sent = s.sent + cs.sent;
    s.recv = s.recv + cs.recv;
    s.delivered = s.delivered + cs.delivered;
    s.acked = s.acked + cs.acked;
    s.retransmits = s.retransmits + cs.retransmits;
    s.dup_dropped = s.dup_dropped + cs.dup_dropped;
    s.stale = s.stale + cs.stale;
    s.out_of_window = s.out_of_window + cs.out_of_window;
    s.timeouts = s.timeouts + cs.timeouts;
    s.held = s.held + cs.held;
    i = i + 1;
  }
  return s;
}
