// XIOM -- xiom.transport package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM transport-class package (reliable datagram / QUIC-class): a
// transport seam (open/close, send/receive/poll, connection state, stats)
// with capability facts, a versioned wire codec, a pure reliability engine
// over an injected clock, a session/channel layer, deterministic simulated
// network injection, loopback/null semantic reference backends and a real
// UDP backend over xiom.net.socket. Independent own-reader build: no
// upstream code, no FFI, no bridge C (see PROVENANCE.md). xiom.std is the
// standard library: a platform dependency, excluded from the registry
// install closure. Modules: xiom.transport (public facade + seam types),
// xiom.transport.caps (capability facts), xiom.transport.frames (wire
// codec), xiom.transport.reliable (reliability engine), xiom.transport.session
// (lifecycle + channels), xiom.transport.sim (simulated network),
// xiom.transport.loopback / xiom.transport.null (reference backends) and
// xiom.transport.udp (real datagram backend).

package xiom_transport {
  name: "xiom.transport";
  version: "0.2.0";
  description: "Pure-XIOM transport-class seam: reliable datagram framing, reliability engine, session/channels, simulated network, loopback/null/UDP backends (no FFI, no bridge C)";
  categories: ["networking"];
  keywords: ["transport", "udp", "reliable", "datagram", "quic", "netcode", "session", "channels"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.transport", "xiom.transport.caps", "xiom.transport.frames", "xiom.transport.reliable", "xiom.transport.rate", "xiom.transport.session", "xiom.transport.handlers", "xiom.transport.sim", "xiom.transport.loopback", "xiom.transport.null", "xiom.transport.udp"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
