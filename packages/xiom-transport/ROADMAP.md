# xiom.transport -- Roadmap

Current: 0.1.0 (incubating). Phase 1 delivers the seam, the wire codec,
the pure reliability engine, the session/channel layer, the simulated
network, loopback/null semantic reference backends and the real UDP
backend -- all conformance-tested (42 checks) on XIOM v0.65.3.

Landed additively after the 0.1.0 reliable-datagram base (no wire or API
break):

- **Ordered packet-handler chain** (`xiom.transport.handlers`): outbound
  handlers in registration order, inbound in reverse, append/insert/clear,
  per-entry and whole-chain disable, byte-exact no-op default, and sample
  prefix/XOR kinds as seams for compression/encryption/resend layers.
- **Saturating send budget** (`xiom.transport.rate`): time-refilled byte
  window with fractional carry and hard capacity, plus the additive
  `session_send_rate_limited` wrapper. This is basic pacing, not
  congestion control.

Planned, in rough priority order (all still bound by the declared
non-goals unless explicitly moved):

1. **Toy-emulator wiring**: connect `xiom.transport.session` to the
   engine's loopback/null seam in xiom-engine and record the first
   end-to-end netcode session (the package is ready for it today:
   two sessions + `xiom.transport.loopback` is the whole wiring).
2. **Ack cadence and piggyback tuning**: batch acks (delayed-ack policy
   driven by the injected clock rather than a wall clock), piggyback acks
   on every outgoing frame automatically, and prove loss recovery under
   heavier sim schedules (drop bursts, 50% loss).
3. **Window and congestion policy**: adaptive send windows bounded by the
   existing engine and the basic `xiom.transport.rate` window (no
   congestion control yet: no RTT/loss feedback and no adaptive target),
   plus stats hooks for the engine's telemetry lane.
   **Handler adapters**: add real compression/encryption kinds over the
   ordered chain (an AEAD adapter needs an explicit per-packet nonce/key
   policy first, so it stays out of the deterministic base).
4. **UDP hardening**: connected-socket mode, per-peer verification on
   receive (the peer address is already reported), and a second socket
   option pass (buffer sizes) with honest Windows notes.
5. **Channel negotiation (still no mux weights)**: a hello extension that
   exchanges the channel table so both ends can verify symmetric
   declarations instead of trusting configuration.
6. **Fragment-level repair**: retransmit only the missing fragments of a
   message (the receiver already tracks per-fragment bits) once the ack
   bitfield can express message-level coverage of large messages; keep
   the all-fragments fallback as the conservative default.
7. **Toolchain debt**: drop the runtime-primitive declaration and switch
   back to the stdlib `socket_recv_from` wrapper once the pinned compiler
   fixes the tuple lowering (AUDIT.md TB-1), and revisit bare `assert`
   calls once the resolver ambiguity (TB-2) is fixed.
