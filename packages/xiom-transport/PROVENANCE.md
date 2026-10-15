# xiom.transport -- Provenance

## Independent declaration

`xiom.transport` is an **independent, own-reader build**. Every line of
XIOM in this package was written from scratch by the XIOM authors against
the package's own declared design references:

- `xiom-engine/docs/NETCODE.md` sections 2 and 3 (the transport seam,
  capability facts queried never assumed, loopback/null first, the
  datagram base, reliability-is-not-a-transport-property, simulated
  latency/loss at the seam, mandatory protocol-version exchange, channel
  semantics, per-channel sequencing/ack windows/bounded retransmit,
  timeouts-as-verdicts, lifecycle with a failure contract per transition,
  reconnect policy as data);
- `xiom-engine/docs/PACKAGE-ASKS.md` row A08 and the surface rule
  (reliability, ordering, fragmentation limits and MTU estimates as
  capability facts; the reliable-datagram/QUIC-class plugs into the same
  seam).

No upstream implementation, vendored source, generated file or copied
constant table is consumed. There is **no FFI to any upstream library and
no bridge C**: the package ships zero C sources, zero build scripts and
zero vendored artifacts.

The package's only externally linked symbol beyond the standard runtime is
its use of the XIOM runtime's own socket primitive `xiom_socket_recvfrom`
(declared with the same pointer-out-parameter signature the standard
  library's `xiom.net.socket` module wraps; see SPEC.md sec. 11 and
AUDIT.md for why the stdlib wrapper's tuple-returning form is unusable on
the pinned toolchain). That symbol is part of the XIOM runtime the
standard library itself links against; declaring it is not an FFI
dependency and adds no C code.

## Wire format provenance

The wire format is the package's own declared layout (SPEC.md sec. 4):
a compact little-endian packet header, seven packet kinds, optional
fragment metadata with explicit byte offsets, and hard size caps. It is
designed against the NETCODE.md requirements (fragmentation limits, MTU
honesty, per-channel sequencing, ack windows, bounded retransmit) and is
pinned by hand-composed byte goldens in `tests/suite_frames.xi`; no
external protocol bytes are reproduced.

## Rejected alternatives (recorded)

- UDP framing modeled on an existing datagram protocol's header (e.g.
  QUIC packet headers): rejected as upstream-design copying; NETCODE.md
  asks for a seam to which a QUIC-class transport *plugs in*, not a
  reimplementation of any specific protocol.
- Vendoring the older `xiom-websocket`-style C bridge for sockets:
  rejected outright (no FFI/bridge C; the standard-library socket layer
  plus the runtime primitive are sufficient, as the probes show).
- Using the stdlib `socket_recv_from` tuple wrapper: impossible on the
  pinned toolchain (miscompiled tuple type; see AUDIT.md TB-1).

## Verification evidence

- `scripts/port.ps1 -Package xiom.transport` -- the conformance suite
  (36 checks across five suites) passes deterministically; run twice with
  an identical `port: PASS (passed=36 failed=0 ...)` line (recorded in
  AUDIT.md).
- Scratch socket probes on 127.0.0.1 (udp create/bind/send_to/poll/
  recvfrom) preceded the UDP module; results recorded in AUDIT.md.
- Toolchain findings that shaped the code (all reproduced and minimized
  before working around): TB-1 (mixed-element tuples miscompiled; the
  package's own four-element decision tuple triggered a clang type clash
  at link time), TB-2 (ambiguous bare `assert` mis-resolves to
  `xiom.core.assert` in some modules; suites call `test.assert`
  qualified).
