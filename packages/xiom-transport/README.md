# xiom.transport

> **Status:** `incubating` -- conformance-tested (42/42) on XIOM v0.65.3.
> **0.2.0 published 2026-10-30** as single tag `xiom-transport/v0.2.0`
> (sha256 `32506ea1...`): additive ordered handler chain + saturating rate
> window. 0.1.0 was `eco-v0.1.188` (sha256 `6638577d...`).
> **Scope:** transport-class seam, pure XIOM: capability facts, compact
> little-endian wire codec, a pure reliability engine over an injected
> clock, a session/channel layer with a mandatory version handshake,
> an ordered packet-handler chain, a saturating send budget,
> deterministic simulated-network injection, loopback/null semantic
> reference backends and a real UDP backend over `xiom.net.socket`.
> No FFI, no bridge C, no vendored upstream code.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.net.socket`,
> `xiom.string.compare`, `xiom.transport.udp` reaches the runtime's own
> `xiom_socket_recvfrom` entry point; the tests use `xiom.test` and
> `xiom.io`).

## What it is

`xiom.transport` is the engine-facing transport seam
(NETCODE.md sec. 2) plus a reliable-datagram / QUIC-class L2 over it:

- **Seam** (`xiom.transport`): a value handle with open/close,
  send/peer-send/poll, connection state (`Connecting` /
  `Handshaking` / `Active` / `Draining` / `Closed`), stats and the
  reconnect policy as plain data (`reconnect_delay_ms` is its pure
  interpreter; attempt overflow is the give-up verdict `-1`).
- **Capability facts** (`xiom.transport.caps`): `CapFacts` per backend
  (`reliable`, `ordered`, `max_datagram`, `max_payload`, `mtu_estimate`,
  `channels`, `reliable_unordered`). Facts are QUERIED, never assumed;
  the matrix is declared in `SPEC.md` sec. 6.
- **Wire codec** (`xiom.transport.frames`): compact 19-byte packet header
  (version u8, flags u8, conn_id u32, channel u8, seq u32, ack u32,
  ack_bits u32), little-endian throughout, packet kinds hello /
  hello_ack / data (+ optional 12-byte fragment metadata) / ack /
  ping / pong / fin, hard size caps, and a total decoder whose every
  error carries the exact byte offset (`FrameError`).
- **Reliability engine** (`xiom.transport.reliable`): pure state stepped
  only through functions with `now_ms` injected by the caller: per-channel
  bounded send windows (<= 32), unacked map, ack + ack-bitfield processing,
  RTO 100..3200 ms bounded exponential backoff, retransmit queue, duplicate
  suppression, ordered-delivery buffering (unordered channels flush
  immediately), exact stats. Exhausted retries and window exhaustion are
  typed verdicts, never hangs.
- **Session** (`xiom.transport.session`): lifecycle
  `Connecting -> Handshaking -> Active -> Draining -> Closed` with a typed
  failure contract per transition; protocol version exchanged in a
  mandatory hello/hello_ack handshake (mismatch refuses with a FIN report);
  channels declared with reliable/ordered/priority/window semantics;
  automatic fragmentation with explicit byte offsets; reassembly that never
  delivers or acks a partial message; `poll(now_ms)` drains retransmissions
  and turns timeouts into typed events plus a draining transition.
  Reliability is NOT a transport property: the L2 decides per channel.
- **Handler chain** (`xiom.transport.handlers`): ordered outbound handlers
  (registration order) and inbound handlers (reverse registration order)
  over plain datagram/session payloads. Small `PacketHandler` records,
  append/insert/clear, per-entry and whole-chain disable, a byte-exact
  no-op default, and sample prefix/XOR transforms as adapters for
  compression/encryption/resend layers (no bundled crypto).
- **Send budget** (`xiom.transport.rate`): a saturating byte window with
  time refill and fractional carry (`rate_window_new`, `rate_refill`,
  `rate_can_send`, `rate_consume`, `rate_window_bytes`), plus the additive
  `session_send_rate_limited` wrapper. Basic pacing only: no RTT/loss
  feedback and no adaptive congestion target.
- **Simulated network** (`xiom.transport.sim`): virtual clock, fixed
  one-way delay, deterministic drop / duplicate / reorder tables, a seeded
  xorshift64 stream, packet capture and a transcript digest. Same seed +
  same call sequence => identical transcript, byte for byte.
- **Backends**: `xiom.transport.loopback` (in-memory FIFO, byte-exact, no
  window, no wall clock -- the semantic reference), `xiom.transport.null`
  (everything counted, nothing delivered, delivered stays a provable zero)
  and `xiom.transport.udp` (real UDP over `xiom.net.socket`: bind,
  non-blocking `send_to`/`recvfrom` inside `poll()`, peer address on every
  datagram, typed refusals).

## Quick start

Two sessions, one loopback link, one reliable message:

```xi
use xiom.io;
use xiom.transport.frames;
use xiom.transport.loopback;
use xiom.transport.session;

pub fn main() -> Int {
  var a = session_new(7, 1200);        // conn id 7, <=1200-byte datagrams
  var b = session_new(7, 1200);
  var link = loopback_new();
  // handshake (hello/hello_ack both ways), then channel + message
  // see tests/suite_session.xi for the full deterministic wire loop.
  io.println("state=" + session_state_name(session_state(&a)));
  return 0;
}
```

Deterministic simulated loss at the seam:

```xi
use xiom.transport.sim;

var link = sim_new(42, 10);            // seed 42, 10 ms one-way delay
var drop: Vec[Int] = Vec[Int].new();
drop.push(1);                          // packet id 1 is dropped
var dup: Vec[Int] = Vec[Int].new();
sim_set_tables(&mut link, &drop, &dup, 2, 7);  // every 2nd id reordered <=7ms
```

Layered payload handlers (outbound in registration order, inbound in
reverse; an empty chain is identity):

```xi
use xiom.transport.handlers;

var chain = handlers_new();
let _ = handlers_register_outbound(&mut chain, handlers_prefix(1, tag));
let _ = handlers_register_outbound(&mut chain, handlers_xor(2, key));
let _ = handlers_register_inbound(&mut chain, handlers_prefix(1, tag));
let _ = handlers_register_inbound(&mut chain, handlers_xor(2, key));
let out = handlers_apply_outbound(&chain, &payload);
let back = handlers_apply_inbound(&chain, &out.bytes);
```

Saturating send budget (10 bytes/sec over a 100-byte window):

```xi
use xiom.transport.rate;
use xiom.transport.session;

var w = rate_window_new(100, 10, 0);
let _ = rate_refill(&mut w, 2000);              // +20 bytes (saturates at 100)
let sent = session_send_rate_limited(&mut s, 1, &payload, 2000, &mut w);
```

Real UDP:

```xi
use xiom.transport.udp;

let r = udp_bind_auto("127.0.0.1", 47600, 47650);
match r {
  Ok(s0) => {
    var s: UdpSocket = s0;
    let pr = udp_set_peer(&mut s, "127.0.0.1", 47601);
    // udp_send / udp_poll(ms) / udp_stats / udp_close
  },
  Err(e) => { io.println("bind refused: " + e.message); },
}
```

## Tests

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/port.ps1 -Package xiom.transport
```

42 deterministic checks across six suites (see `tests/test_conformance.xi`).
The UDP checks run against `127.0.0.1` with a candidate-port scan; when no
free port exists they print an explicit `SKIP` line in the check name and
never fake a pass. Everything else is wall-clock free.

## Honest SKIP note

The UDP suite is SKIP-safe by design: `udp_bind_auto` scans an explicit
candidate port range (the runtime exposes no `getsockname`), and a fully
occupied range turns the check into a named SKIP rather than a failure or
a fake pass (the `xiom-redis` `suite_live` convention).
