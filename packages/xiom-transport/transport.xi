// XIOM -- xiom.transport: the transport seam (public facade)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// The seam the engine plugs into (NETCODE.md sec. 2): a value handle over
// a backend with open/close, send/receive/poll, connection state and
// stats, plus capability facts (queried through xiom.transport.caps,
// never assumed) and the reconnect policy as plain data.
//
// Backends in this facade: loopback (in-memory semantic reference), null
// (honest empty) and sim (deterministic simulated network; constructed
// through transport_open_sim with a caller seed and delay). The real UDP
// backend binds sockets and lives in xiom.transport.udp; the L2 wiring
// (handshake, channels, reliability) lives in xiom.transport.session.
// Backends may express less, never something else.
//
// The facade is single-endpoint: transport_send/transport_poll move bytes
// from this endpoint's perspective (poll drains what the peer sent).
// transport_peer_send stands in for the peer endpoint (a second process
// in production; another endpoint of the same link in a test). For sim,
// transport_advance steps the virtual clock; loopback/null are
// zero-latency and ignore it (Ok(0), documented).
//
// Determinism: no wall clock, no randomness beyond the caller's sim seed,
// no globals. State transitions: open -> active; close -> closed; every
// refusal after close is a typed TxError.

module xiom.transport

use xiom.transport.caps;
use xiom.transport.session;
use xiom.transport.loopback;
use xiom.transport.null;
use xiom.transport.sim;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

// TxError kinds.
pub const TXE_KIND: Int = 1;
pub const TXE_STATE: Int = 2;
pub const TXE_CLOSED: Int = 3;
pub const TXE_PAYLOAD: Int = 4;

// Reconnect backoff shapes (ReconnectPolicy.backoff).
pub const RECONNECT_BACKOFF_CONSTANT: Int = 1;
pub const RECONNECT_BACKOFF_LINEAR: Int = 2;
pub const RECONNECT_BACKOFF_EXPONENTIAL: Int = 3;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// A typed facade failure.
pub type TxError = {
  kind: Int;
  code: Int;
  message: Str;
}

/// Facade-level counters (backend internals stay in their modules).
pub type TransportStats = {
  sent: Int;
  received: Int;
  bytes_sent: Int;
  bytes_received: Int;
  refused: Int;
}

/// Reconnect policy is data (NETCODE.md sec. 3): bounded attempts, a
/// delay shape, a cap and deterministic jitter. reconnect_delay_ms is
/// its pure interpreter; -1 means "attempts exhausted" (a verdict).
pub type ReconnectPolicy = {
  max_attempts: Int;
  base_delay_ms: Int;
  max_delay_ms: Int;
  backoff: Int;
  jitter: Bool;
}

/// The transport handle. One kind field selects one live backend struct
/// (the others stay at their defaults and are never read for another
/// kind); plain copy-in/step/copy-out keeps value semantics exact.
pub type TransportHandle = {
  kind: Int;
  state: ConnState;
  caps: CapFacts;
  stats: TransportStats;
  reconnect: ReconnectPolicy;
  lb: LoopbackLink;
  nl: NullTransport;
  smq: SimLink;
}

// ---------------------------------------------------------------------------
// Leaf helpers
// ---------------------------------------------------------------------------

fn _txerr(kind: Int, code: Int, message: Str) -> TxError {
  return TxError { kind: kind, code: code, message: message };
}

fn _ok_handle(v: TransportHandle) -> Result[TransportHandle, TxError] { return Ok(v); }
fn _err_handle(e: TxError) -> Result[TransportHandle, TxError] { return Err(e); }
fn _ok_int(v: Int) -> Result[Int, TxError] { return Ok(v); }
fn _err_int(e: TxError) -> Result[Int, TxError] { return Err(e); }
fn _ok_units(v: Vec[Vec[UInt8]]) -> Result[Vec[Vec[UInt8]], TxError] { return Ok(v); }
fn _err_units(e: TxError) -> Result[Vec[Vec[UInt8]], TxError] { return Err(e); }

fn _empty_units() -> Vec[Vec[UInt8]] {
  return Vec[Vec[UInt8]].new();
}

fn _empty_tstats() -> TransportStats {
  return TransportStats { sent: 0; received: 0; bytes_sent: 0; bytes_received: 0; refused: 0; };
}

/// Documented defaults: 5 attempts, 250 ms base, 8 s cap, exponential
/// backoff, deterministic jitter on.
pub fn transport_default_reconnect() -> ReconnectPolicy {
  return ReconnectPolicy {
    max_attempts: 5;
    base_delay_ms: 250;
    max_delay_ms: 8000;
    backoff: RECONNECT_BACKOFF_EXPONENTIAL;
    jitter: true;
  };
}

/// The policy interpreter: delay before reconnect attempt N (1-based).
/// Constant/linear/exponential shapes, capped at max_delay_ms, with
/// deterministic decorrelation when jitter is on. Returns -1 when the
/// attempt exceeds max_attempts (the give-up verdict).
pub fn reconnect_delay_ms(p: &ReconnectPolicy, attempt: Int) -> Int {
  if attempt < 1 { return p.base_delay_ms; }
  if attempt > p.max_attempts { return -1; }
  var v = p.base_delay_ms;
  if p.backoff == RECONNECT_BACKOFF_LINEAR {
    v = p.base_delay_ms * attempt;
  }
  if p.backoff == RECONNECT_BACKOFF_EXPONENTIAL {
    v = p.base_delay_ms;
    var k = 1;
    while k < attempt {
      v = v * 2;
      if v > p.max_delay_ms { break; }
      k = k + 1;
    }
  }
  if p.jitter {
    v = v + ((attempt * 37) % 53);
  }
  if v > p.max_delay_ms { v = p.max_delay_ms; }
  return v;
}

pub fn transport_kind_name(kind: Int) -> Str {
  if kind == TX_KIND_LOOPBACK { return "loopback"; }
  if kind == TX_KIND_NULL { return "null"; }
  if kind == TX_KIND_SIM { return "sim"; }
  if kind == TX_KIND_UDP { return "udp"; }
  return "unknown";
}

// ---------------------------------------------------------------------------
// Open / close
// ---------------------------------------------------------------------------

// Assemble a handle; the default backends are cheap placeholders for the
// non-selected kinds.
fn _handle(kind: Int, state: ConnState, smq: SimLink) -> TransportHandle {
  return TransportHandle {
    kind: kind;
    state: state;
    caps: caps_for_kind(kind);
    stats: _empty_tstats();
    reconnect: transport_default_reconnect();
    lb: loopback_new();
    nl: null_new();
    smq: smq;
  };
}

/// Open a facade backend: TX_KIND_LOOPBACK or TX_KIND_NULL. The
/// in-memory link is immediately Active (the handshake belongs to the
/// session layer, xiom.transport.session). Sim uses
/// transport_open_sim; UDP binds sockets and lives in
/// xiom.transport.udp.
pub fn transport_open(kind: Int) -> Result[TransportHandle, TxError] {
  if kind == TX_KIND_LOOPBACK {
    return _ok_handle(_handle(TX_KIND_LOOPBACK, Active, sim_new(1, 0)));
  }
  if kind == TX_KIND_NULL {
    return _ok_handle(_handle(TX_KIND_NULL, Active, sim_new(1, 0)));
  }
  if kind == TX_KIND_SIM {
    return _err_handle(_txerr(TXE_KIND, kind, "transport_open: sim needs a seed and delay; use transport_open_sim"));
  }
  if kind == TX_KIND_UDP {
    return _err_handle(_txerr(TXE_KIND, kind, "transport_open: UDP binds sockets; use xiom.transport.udp"));
  }
  return _err_handle(_txerr(TXE_KIND, kind, "transport_open: unknown backend kind"));
}

/// Open a simulated-network handle with the caller's seed and one-way
/// delay (ms). Same seed + same call sequence => same transcript.
pub fn transport_open_sim(seed: Int, delay_ms: Int) -> Result[TransportHandle, TxError] {
  return _ok_handle(_handle(TX_KIND_SIM, Active, sim_new(seed, delay_ms)));
}

/// Close the handle (idempotent); further sends and polls are refused.
pub fn transport_close(h: &mut TransportHandle) {
  if h.kind == TX_KIND_LOOPBACK {
    var l: LoopbackLink = h.lb;
    loopback_close(&mut l);
    h.lb = l;
  }
  if h.kind == TX_KIND_NULL {
    var t: NullTransport = h.nl;
    null_close(&mut t);
    h.nl = t;
  }
  h.state = Closed;
}

pub fn transport_state(h: &TransportHandle) -> ConnState {
  return h.state;
}

pub fn transport_state_name(h: &TransportHandle) -> Str {
  return session_state_name(h.state);
}

pub fn transport_is_open(h: &TransportHandle) -> Bool {
  match h.state {
    Active => { return true; },
    Connecting => { return false; },
    Handshaking => { return false; },
    Draining => { return false; },
    Closed => { return false; },
  }
  return false;
}

pub fn transport_caps(h: &TransportHandle) -> CapFacts {
  return h.caps;
}

pub fn transport_stats(h: &TransportHandle) -> TransportStats {
  return h.stats;
}

pub fn transport_reconnect(h: &TransportHandle) -> ReconnectPolicy {
  return h.reconnect;
}

/// Reconnect policy is data: set it at run time.
pub fn transport_set_reconnect(h: &mut TransportHandle, p: ReconnectPolicy) {
  h.reconnect = p;
}

// ---------------------------------------------------------------------------
// Send / poll
// ---------------------------------------------------------------------------

fn _check_open(h: &TransportHandle, op: Str) -> TxError {
  match h.state {
    Active => { return _txerr(0, 0, ""); },
    _ => {
      return _txerr(TXE_CLOSED, 0, op + ": transport not open (" + session_state_name(h.state) + ")");
    },
  }
  return _txerr(TXE_STATE, 0, op + ": unknown state");
}

/// Send one datagram from this endpoint; returns the packet id (loopback/
/// sim) or 0 (null), Err after close.
pub fn transport_send(h: &mut TransportHandle, bytes: &Vec[UInt8]) -> Result[Int, TxError] {
  let check = _check_open(h, "transport_send");
  if check.kind != 0 {
    h.stats.refused = h.stats.refused + 1;
    return _err_int(check);
  }
  var id = 0;
  if h.kind == TX_KIND_LOOPBACK {
    var l: LoopbackLink = h.lb;
    id = loopback_send_a(&mut l, bytes);
    h.lb = l;
  }
  if h.kind == TX_KIND_NULL {
    var t: NullTransport = h.nl;
    let accepted = null_send(&mut t, bytes);
    h.nl = t;
    if !accepted {
      h.stats.refused = h.stats.refused + 1;
      return _err_int(_txerr(TXE_CLOSED, 0, "transport_send: null backend closed"));
    }
  }
  if h.kind == TX_KIND_SIM {
    var s: SimLink = h.smq;
    id = sim_send_a(&mut s, bytes);
    h.smq = s;
  }
  h.stats.sent = h.stats.sent + 1;
  h.stats.bytes_sent = h.stats.bytes_sent + bytes.len();
  return _ok_int(id);
}

/// The peer endpoint's send (test/tooling stand-in for the other
/// process). Bytes land in this endpoint's inbound path.
pub fn transport_peer_send(h: &mut TransportHandle, bytes: &Vec[UInt8]) -> Result[Int, TxError] {
  let check = _check_open(h, "transport_peer_send");
  if check.kind != 0 {
    h.stats.refused = h.stats.refused + 1;
    return _err_int(check);
  }
  var id = 0;
  if h.kind == TX_KIND_LOOPBACK {
    var l: LoopbackLink = h.lb;
    id = loopback_send_b(&mut l, bytes);
    h.lb = l;
  }
  if h.kind == TX_KIND_SIM {
    var s: SimLink = h.smq;
    id = sim_send_b(&mut s, bytes);
    h.smq = s;
  }
  if h.kind == TX_KIND_NULL {
    // Counted on the inbound side; nothing will ever be delivered.
    h.stats.received = h.stats.received + 1;
    h.stats.bytes_received = h.stats.bytes_received + bytes.len();
    return _ok_int(0);
  }
  return _ok_int(id);
}

// Sum the payload lengths of a drained batch.
fn _sum_len(units: &Vec[Vec[UInt8]]) -> Int {
  var total = 0;
  var i = 0;
  while i < units.len() {
    let u: Vec[UInt8] = units[i];
    total = total + u.len();
    i = i + 1;
  }
  return total;
}

/// Drain everything this endpoint has received (FIFO for loopback; due
/// packets by virtual time for sim; always empty for null).
pub fn transport_poll(h: &mut TransportHandle) -> Result[Vec[Vec[UInt8]], TxError] {
  let check = _check_open(h, "transport_poll");
  if check.kind != 0 {
    return _err_units(check);
  }
  var out: Vec[Vec[UInt8]] = _empty_units();
  if h.kind == TX_KIND_LOOPBACK {
    var l: LoopbackLink = h.lb;
    out = loopback_poll_a(&mut l);
    h.lb = l;
  }
  if h.kind == TX_KIND_NULL {
    var t: NullTransport = h.nl;
    out = null_poll(&mut t);
    h.nl = t;
  }
  if h.kind == TX_KIND_SIM {
    var s: SimLink = h.smq;
    out = sim_recv_a(&mut s);
    h.smq = s;
  }
  h.stats.received = h.stats.received + out.len();
  h.stats.bytes_received = h.stats.bytes_received + _sum_len(&out);
  return _ok_units(out);
}

/// Step the virtual clock (sim only). Loopback and null are zero-latency:
/// advancing is a documented no-op returning 0.
pub fn transport_advance(h: &mut TransportHandle, delta_ms: Int) -> Result[Int, TxError] {
  if h.kind == TX_KIND_SIM {
    var s: SimLink = h.smq;
    let now = sim_advance(&mut s, delta_ms);
    h.smq = s;
    return _ok_int(now);
  }
  return _ok_int(0);
}

/// Datagrams this endpoint has sent that the peer has not yet drained
/// (loopback/sim), 0 elsewhere.
pub fn transport_pending_out(h: &TransportHandle) -> Int {
  if h.kind == TX_KIND_LOOPBACK {
    let l: LoopbackLink = h.lb;
    return loopback_pending_b(&l);
  }
  if h.kind == TX_KIND_SIM {
    let s: SimLink = h.smq;
    let st = sim_stats(&s);
    return st.pending_a_to_b;
  }
  return 0;
}

/// Datagrams waiting for this endpoint to poll.
pub fn transport_pending_in(h: &TransportHandle) -> Int {
  if h.kind == TX_KIND_LOOPBACK {
    let l: LoopbackLink = h.lb;
    return loopback_pending_a(&l);
  }
  if h.kind == TX_KIND_SIM {
    let s: SimLink = h.smq;
    let st = sim_stats(&s);
    return st.pending_b_to_a;
  }
  return 0;
}
