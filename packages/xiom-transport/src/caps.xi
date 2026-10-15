// XIOM -- xiom.transport.caps: backend capability facts
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Capability facts are QUERIED, never assumed (NETCODE.md sec. 2): every
// backend declares what it can honestly promise, and consumers adapt. The
// facts are static data per backend kind; no probing, no wall clock.
//
// Fact semantics (declared, matrix in SPEC.md):
//   reliable           -- the medium delivers every datagram it accepts
//                         (loopback: true; a lossy/simulated/UDP medium:
//                         false; null: false -- a null backend delivers
//                         nothing, so it cannot claim reliability);
//   ordered            -- datagrams arrive in send order (loopback: true;
//                         UDP/sim: false);
//   max_datagram       -- largest single datagram the backend can carry,
//                         in bytes, including the transport header (0 when
//                         the backend carries nothing);
//   max_payload        -- largest application payload per datagram after
//                         the wire header + fragment metadata
//                         (max_datagram - TX_CAP_HEADER - TX_CAP_FRAG_META);
//   mtu_estimate       -- conservative path-MTU estimate in bytes (0 when
//                         not applicable);
//   channels           -- the session/channel layer (xiom.transport.session)
//                         is available over this backend;
//   reliable_unordered -- the L2 reliability engine can carry a
//                         reliable+unordered channel over this backend
//                         (an L2 fact, never a transport property).
//
// This module is also the shared base of the package: the backend-kind
// constants below are declared here (not in the root module) so the module
// dependency order stays acyclic: caps -> frames -> reliable -> session ->
// backends -> root.

module xiom.transport.caps

// ---------------------------------------------------------------------------
// Backend kinds
// ---------------------------------------------------------------------------

pub const TX_KIND_LOOPBACK: Int = 1;
pub const TX_KIND_NULL: Int = 2;
pub const TX_KIND_SIM: Int = 3;
pub const TX_KIND_UDP: Int = 4;

// ---------------------------------------------------------------------------
// Shared wire-size constants (single source; xiom.transport.frames uses
// these for its hard caps)
// ---------------------------------------------------------------------------

/// Largest single datagram any datagram-class backend carries (UDP
/// payload ceiling; loopback and sim mirror it so frames stay portable).
pub const TX_CAP_MAX_DATAGRAM: Int = 65507;

/// Compact packet header size in bytes (version 1, see SPEC.md sec. 4).
pub const TX_CAP_HEADER: Int = 19;

/// Fragment metadata size in bytes when the fragment flag is set.
pub const TX_CAP_FRAG_META: Int = 12;

/// Largest data chunk per datagram: 65507 - 19 - 12 = 65476.
pub const TX_CAP_MAX_PAYLOAD: Int = 65476;

// ---------------------------------------------------------------------------
// Cap facts
// ---------------------------------------------------------------------------

/// The capability facts of one backend, queried by consumers. Values are
/// static per backend kind; nothing here is inferred at run time.
pub type CapFacts = {
  reliable: Bool;
  ordered: Bool;
  max_datagram: Int;
  max_payload: Int;
  mtu_estimate: Int;
  channels: Bool;
  reliable_unordered: Bool;
}

/// Loopback facts (in-memory FIFO queue): the semantic reference -- every
/// datagram is delivered byte-exact and in send order, no loss, no window,
/// no wall clock.
pub fn caps_loopback() -> CapFacts {
  return CapFacts {
    reliable: true,
    ordered: true,
    max_datagram: TX_CAP_MAX_DATAGRAM,
    max_payload: TX_CAP_MAX_PAYLOAD,
    mtu_estimate: 65535,
    channels: true,
    reliable_unordered: true,
  };
}

/// Null facts (honest emptiness): everything is counted, nothing is
/// delivered; a backend that delivers nothing cannot claim reliability,
/// ordering, channels or an MTU.
pub fn caps_null() -> CapFacts {
  return CapFacts {
    reliable: false,
    ordered: false,
    max_datagram: 0,
    max_payload: 0,
    mtu_estimate: 0,
    channels: false,
    reliable_unordered: false,
  };
}

/// Simulated-network facts: the schedule may drop, reorder and duplicate,
/// so the base claim is lossy/unordered regardless of the configured
/// tables; the L2 engine can still carry reliable channels over it.
pub fn caps_sim() -> CapFacts {
  return CapFacts {
    reliable: false,
    ordered: false,
    max_datagram: TX_CAP_MAX_DATAGRAM,
    max_payload: TX_CAP_MAX_PAYLOAD,
    mtu_estimate: 1500,
    channels: true,
    reliable_unordered: true,
  };
}

/// Real UDP facts: lossy, unordered, 1500-byte conservative MTU estimate;
/// the L2 engine carries reliability per channel.
pub fn caps_udp() -> CapFacts {
  return CapFacts {
    reliable: false,
    ordered: false,
    max_datagram: TX_CAP_MAX_DATAGRAM,
    max_payload: TX_CAP_MAX_PAYLOAD,
    mtu_estimate: 1500,
    channels: true,
    reliable_unordered: true,
  };
}

/// Facts for a TX_KIND_* constant. Unknown kinds get the null facts
/// (honest empty), never a guess.
pub fn caps_for_kind(kind: Int) -> CapFacts {
  if kind == TX_KIND_LOOPBACK {
    return caps_loopback();
  }
  if kind == TX_KIND_SIM {
    return caps_sim();
  }
  if kind == TX_KIND_UDP {
    return caps_udp();
  }
  return caps_null();
}

/// True when the kind names a backend this package ships.
pub fn caps_known_kind(kind: Int) -> Bool {
  if kind == TX_KIND_LOOPBACK { return true; }
  if kind == TX_KIND_NULL { return true; }
  if kind == TX_KIND_SIM { return true; }
  if kind == TX_KIND_UDP { return true; }
  return false;
}

/// Readable one-line rendering of a facts record (tests, diagnostics).
pub fn caps_to_str(f: &CapFacts) -> Str {
  var rel = "false";
  if f.reliable { rel = "true"; }
  var ord = "false";
  if f.ordered { ord = "true"; }
  var ch = "false";
  if f.channels { ch = "true"; }
  var ru = "false";
  if f.reliable_unordered { ru = "true"; }
  return "CapFacts{reliable=" + rel + ", ordered=" + ord +
    ", max_datagram=" + f.max_datagram.to_str() +
    ", max_payload=" + f.max_payload.to_str() +
    ", mtu_estimate=" + f.mtu_estimate.to_str() +
    ", channels=" + ch + ", reliable_unordered=" + ru + "}";
}
