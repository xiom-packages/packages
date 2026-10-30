# xiom.transport -- Specification

Version: 0.1.0 (incubating).
Modules: `xiom.transport`, `xiom.transport.caps`, `xiom.transport.frames`,
`xiom.transport.reliable`, `xiom.transport.rate`, `xiom.transport.session`,
`xiom.transport.handlers`, `xiom.transport.sim`, `xiom.transport.loopback`,
`xiom.transport.null`, `xiom.transport.udp`. Pure XIOM, single
runtime-primitive declaration (sec. 5), no FFI to any upstream library, no
bridge C.
Dependencies: `xiom.std >=0.60.0 <1.0.0` (`xiom.net.socket`,
`xiom.string.compare`; tests additionally `xiom.test`, `xiom.io`).
Design reference: NETCODE.md sec. 2-3 and PACKAGE-ASKS.md row A08 with the
surface rule (reliability, ordering, fragmentation limits and MTU estimates
as capability facts; the transport seam is loopback/null first; the
reliable-datagram/QUIC-class plugs into the same seam; simulated
latency/loss lives at the seam as deterministic schedules).

This document is the package's P8 design artifact: it declares the surface,
the wire tables, the state machine, the channel and retransmit/ack
semantics, the cap-facts matrix per backend, the error taxonomy, the
determinism contract and the non-goals.

## 1. Scope

A transport-class seam and one reliable-datagram L2 over it, in eleven
modules:

| Module | Role |
|---|---|
| `xiom.transport` | Public facade: `TransportHandle`, open/close, send/poll, state, stats, reconnect policy data |
| `xiom.transport.caps` | `CapFacts` + per-backend facts functions + shared wire-size constants |
| `xiom.transport.frames` | Wire codec: header, packet kinds, fragmentation metadata, typed errors with byte offsets |
| `xiom.transport.reliable` | Pure reliability engine over an injected clock |
| `xiom.transport.rate` | Saturating byte-budget send window (basic pacing, not congestion control) |
| `xiom.transport.session` | Lifecycle, handshake, channels, fragmentation/reassembly, poll |
| `xiom.transport.handlers` | Ordered outbound/inbound packet-handler chain (layering seam) |
| `xiom.transport.sim` | Deterministic simulated network (virtual clock + schedule tables) |
| `xiom.transport.loopback` | In-memory semantic reference (byte-exact FIFO) |
| `xiom.transport.null` | Honest empty backend (counted, never delivered) |
| `xiom.transport.udp` | Real UDP over `xiom.net.socket` (+ Windows notes) |

Module placement decisions:

- Backend kinds (`TX_KIND_*`) and the shared wire-size constants live in
  `xiom.transport.caps` (the base module) so the dependency order stays
  acyclic: caps -> frames -> reliable -> rate -> session -> backends -> root;
  `xiom.transport.handlers` is independent (plain payloads in/out).
- The connection-state enum `ConnState` lives in `xiom.transport.session`
  (the lifecycle owner); the root facade surfaces it through its handle
  and `transport_state*` functions.

## 2. Public surface (by module)

`xiom.transport.caps`
`caps_loopback`, `caps_null`, `caps_sim`, `caps_udp`,
`caps_for_kind`, `caps_known_kind`, `caps_to_str`; constants
`TX_KIND_*`, `TX_CAP_MAX_DATAGRAM` (65507), `TX_CAP_HEADER` (19),
`TX_CAP_FRAG_META` (12), `TX_CAP_MAX_PAYLOAD` (65476); type `CapFacts`.

`xiom.transport.frames`
`put_u16_le`, `put_u32_le`, `read_u16_le`, `read_u32_le`,
`frame_new`, `frame_hello`, `frame_hello_ack`, `frame_data`,
`frame_data_fragment`, `frame_ack`, `frame_ping`, `frame_pong`,
`frame_fin`, `frame_encode`, `frame_decode`, `frame_kind_name`;
constants `FRAME_VERSION` (1), `FRAME_HEADER_SIZE` (19),
`FRAME_FRAG_META_SIZE` (12), `FRAME_MAX_DATAGRAM` (65507),
`FRAME_MAX_PAYLOAD` (65476), `FRAME_MAX_MESSAGE` (262144),
`FRAME_MAX_PROTOCOL_VERSION` (65535), `FRAME_KIND_*`, `FRAME_FLAG_FRAGMENT`,
`FIN_REASON_*`, `FRAME_ERR_*`; types `Frame`, `FrameError`.

`xiom.transport.reliable`
`rl_new`, `rl_open_channel`, `rl_close_channel`, `rl_channel_exists`,
`rl_channel_count`, `rl_rto_ms`, `rl_seq_acked`, `rl_send`, `rl_on_ack`,
`rl_poll_rtx`, `rl_take_failures`, `rl_on_packet`, `rl_skip_gap`,
`rl_unacked_seqs`, `rl_inflight_len`, `rl_held_len`, `rl_recv_next`,
`rl_recv_mask`, `rl_next_seq`, `rl_channel_stats`, `rl_stats`; constants
`RL_MAX_WINDOW` (32), `RL_RECV_WINDOW` (63), `RL_DEFAULT_RTO_MS` (100),
`RL_MAX_RTO_MS` (3200), `RL_MAX_RETRIES` (5), `RL_ERR_*`; types
`RlEngine`, `RlChannel`, `RlChannelStats`, `RlStats`, `RlInflight`,
`RlOutbound`, `RlMessage`, `RlFailure`, `RlRecvResult`, `RlError`.

`xiom.transport.rate`
`rate_window_new`, `rate_window_bytes`, `rate_window_capacity`,
`rate_refill`, `rate_can_send`, `rate_consume`, `rate_window_to_str`;
constants `RATE_ERR_CONFIG`, `RATE_ERR_BUDGET`; type `RateWindow`
(`capacity_bytes`, `available_bytes`, `refill_bytes_per_sec`, `remainder`,
`last_ms`, `sent_bytes`, `sent_packets`, `refilled_bytes`, `refused`).

`xiom.transport.handlers`
`handlers_new`, `handlers_noop`, `handlers_prefix`, `handlers_xor`,
`handlers_is_enabled`, `handlers_set_enabled`, `handlers_outbound_len`,
`handlers_inbound_len`, `handlers_register_outbound`,
`handlers_register_inbound`, `handlers_insert_outbound`,
`handlers_insert_inbound`, `handlers_set_handler_enabled`,
`handlers_clear_outbound`, `handlers_clear_inbound`, `handlers_clear`,
`handlers_apply_outbound`, `handlers_apply_inbound`, `handlers_apply`;
constants `HANDLER_KIND_*`, `HANDLER_STAGE_*`, `HANDLER_ERR_*`; types
`PacketHandler`, `HandlerChain`, `HandlerOutcome`.

`xiom.transport.session`
`session_new`, `session_state`, `session_state_code`, `session_state_name`,
`session_state_name_of_code`, `session_is_active`, `session_stats`,
`session_reliable_stats`, `session_reasm_len`, `session_conn_id`,
`session_start`, `session_close`, `session_handshake_deadline`,
`session_open_channel`, `session_close_channel`, `session_send`,
`session_send_rate_limited`, `session_on_packet`, `session_poll`;
constants `TX_PROTOCOL_VERSION` (1), `TX_MAX_FRAGMENTS` (256),
`TX_MAX_REASM_ENTRIES` (16), `TX_ERR_*` (including `TX_ERR_RATE`); types
`ConnState`, `Session`, `SessionEvent`, `SessionPoll`, `SessionStats`,
`SessionError`, `ReasmEntry`, `ReasmOutcome`.

`xiom.transport.sim`
`sim_new`, `sim_set_tables`, `sim_now`, `sim_advance`, `sim_send_a`,
`sim_send_b`, `sim_recv_a`, `sim_recv_b`, `sim_capture`, `sim_stats`,
`sim_digest`; types `SimLink`, `SimSchedule`, `SimPacket`, `SimStats`,
`SimDecision`, `SimRelease`.

`xiom.transport.loopback`
`loopback_new`, `loopback_send_a`, `loopback_send_b`, `loopback_poll_a`,
`loopback_poll_b`, `loopback_pending_a`, `loopback_pending_b`,
`loopback_stats`, `loopback_close`, `loopback_is_open`; types
`LoopbackLink`, `LoopbackStats`.

`xiom.transport.null`
`null_new`, `null_send`, `null_poll`, `null_stats`, `null_close`,
`null_is_open`; types `NullTransport`, `NullStats`.

`xiom.transport.udp`
`udp_bind`, `udp_bind_auto`, `udp_set_peer`, `udp_send`, `udp_send_to`,
`udp_poll`, `udp_close`, `udp_is_open`, `udp_local_port`, `udp_stats`,
`udp_caps`; constants `UDP_ERR_*`, `UDP_RECV_CAP` (65507), `UDP_DRAIN_MAX`
(4096); types `UdpSocket`, `UdpDatagram`, `UdpStats`, `UdpError`.

`xiom.transport` (root)
`transport_open`, `transport_open_sim`, `transport_close`,
`transport_state`, `transport_state_name`, `transport_is_open`,
`transport_caps`, `transport_stats`, `transport_reconnect`,
`transport_set_reconnect`, `transport_default_reconnect`,
`reconnect_delay_ms`, `transport_kind_name`, `transport_send`,
`transport_peer_send`, `transport_poll`, `transport_advance`,
`transport_pending_out`, `transport_pending_in`; constants `TXE_*`,
`RECONNECT_BACKOFF_*`; types `TransportHandle`, `TransportStats`,
`TxError`, `ReconnectPolicy`.

## 3. Seam contract (facade)

- `transport_open(kind)` accepts `TX_KIND_LOOPBACK` and `TX_KIND_NULL` and
  returns the handle already `Active` (the in-memory link is immediately
  usable; the handshake belongs to the session layer). `TX_KIND_SIM`
  requires `transport_open_sim(seed, delay_ms)`; `TX_KIND_UDP` is refused
  with `TXE_KIND` and points at `xiom.transport.udp`; unknown kinds are
  `TXE_KIND`.
- One handle is one endpoint: `transport_send`/`transport_poll` move bytes
  from that endpoint's perspective; `transport_peer_send` stands in for the
  peer endpoint (a second process in production, the other end of the link
  in a test). `transport_advance` steps the sim's virtual clock; loopback
  and null are zero-latency and return `Ok(0)` as a documented no-op.
- `transport_close` is idempotent; every later send/poll is a typed
  `TXE_CLOSED` refusal and increments `refused`.
- Reconnect policy is data: `max_attempts`, `base_delay_ms`,
  `max_delay_ms`, `backoff` (constant/linear/exponential), deterministic
  `jitter`. `reconnect_delay_ms(p, attempt)` returns the delay for a
  1-based attempt, always capped at `max_delay_ms`, and `-1` when the
  attempt exceeds `max_attempts` (the give-up verdict). Jitter is
  deterministic (`(attempt * 37) mod 53` added before the cap) -- no
  randomness enters the policy.

## 4. Wire format (normative tables)

One datagram carries exactly one frame. All multi-byte fields are
little-endian. Header, 19 bytes, at absolute offsets:

| off | size | field | notes |
|---|---|---|---|
| 0 | 1 | `version` u8 | MUST be 1 (`FRAME_VERSION`); anything else is `FRAME_ERR_VERSION` at 0 |
| 1 | 1 | `flags` u8 | low nibble = kind, `0x10` = fragment flag; other bits `FRAME_ERR_FLAGS` at 1 |
| 2 | 4 | `conn_id` u32 | connection identity; sessions refuse foreign ids |
| 6 | 1 | `channel` u8 | channel id 0..255 |
| 7 | 4 | `seq` u32 | send sequence, per channel |
| 11 | 4 | `ack` u32 | highest contiguous seq received on this channel; `0xFFFFFFFF` = "no ack yet" (surfaced as -1) |
| 15 | 4 | `ack_bits` u32 | bit `d-1` marks `ack-d` as received (d in 1..32) |

Kinds (flags low nibble) and fixed tails:

| kind | value | tail |
|---|---|---|
| `HELLO` | 0 | `protocol_version` u16 (21 bytes total) |
| `HELLO_ACK` | 1 | `protocol_version` u16 (21 bytes total) |
| `DATA` | 2 | payload bytes; with the fragment flag: 12 bytes metadata first |
| `ACK` | 3 | none (19 bytes; header ack fields are the body) |
| `PING` | 4 | none (19 bytes) |
| `PONG` | 5 | none (19 bytes) |
| `FIN` | 6 | `reason` u8 (20 bytes total; `FIN_REASON_*`) |

Fragment metadata (12 bytes, only with `FRAME_FLAG_FRAGMENT` on DATA):
`frag_index` u16, `frag_count` u16, `frag_offset` u32 (byte offset of the
chunk inside the message), `frag_total` u32 (message length). Explicit
offsets keep reassembly correct when the two ends use different datagram
budgets.

Hard caps (all typed, never silently exceeded):

| cap | value | breach |
|---|---|---|
| datagram | 65507 (`FRAME_MAX_DATAGRAM`) | encode `FRAME_ERR_SIZE`; decode `FRAME_ERR_SIZE` at the frame offset |
| data payload / fragment chunk | 65476 (`FRAME_MAX_PAYLOAD`) | `FRAME_ERR_SIZE` |
| reassembled message | 262144 (`FRAME_MAX_MESSAGE`) | encode/decode `FRAME_ERR_FRAG` |
| fragment count per message | 256 (`TX_MAX_FRAGMENTS`, session) | session `TX_ERR_PAYLOAD` |
| concurrent partial messages | 16 (`TX_MAX_REASM_ENTRIES`) | session `TX_ERR_BUFFER` |

Fixed-size kinds refuse trailing bytes (`FRAME_ERR_SIZE` at the first
trailing byte), so a datagram is never ambiguous. Decode is total: every
read is bounds-checked first; every error carries the byte offset where the
problem starts (encode-side validation failures report offset 0).

## 5. Session state machine

States: `Connecting` (0), `Handshaking` (1), `Active` (2), `Draining` (3),
`Closed` (4).

```
Connecting --session_start/hello--> Handshaking
Handshaking --hello(peer, version ok)--> emits hello_ack (state unchanged)
Handshaking --hello_ack(peer, version ok)--> Active
Active --session_close(reason)/FIN--> Draining
Handshaking --session_close(reason)/FIN--> Draining
any --FIN(peer)--> emits FIN echo (if none sent) --> Closed
any --hello/hello_ack version mismatch--> FIN(VERSION_MISMATCH), refusal event --> Closed
Active|Handshaking --retries exhausted (session_poll)--> FIN(TIMEOUT) --> Draining
Draining --FIN(peer)--> Closed
```

Failure contract per transition:

- `Connecting -> Handshaking` only via `session_start`; any other start is
  `TX_ERR_STATE`.
- `Handshaking -> Active` only on a version-matching `hello_ack`; a
  version mismatch in either direction is a refusal: `EvFailure`
  (kind `TX_ERR_VERSION`), `refusals` counter, FIN with
  `FIN_REASON_VERSION_MISMATCH`, state `Closed`. Late packets on a closed
  session are `TX_ERR_STATE` refusals.
- Sends are `Active`-only (`TX_ERR_STATE`, message names the state);
  `Draining` refuses sends but still accepts and acks in-flight data.
- Reliability timeouts (bounded retries exhausted) surface from
  `session_poll` as `EvFailure` plus FIN(`FIN_REASON_TIMEOUT`) plus
  `Active -> Draining`; a session never hangs on a lost packet.
- The handshake deadline is a caller-owned verdict:
  `session_handshake_deadline(s, started_ms, now_ms, budget_ms)` is pure;
  the caller then issues `session_close(s, FIN_REASON_TIMEOUT, now_ms)`.
- Data before `Active` is `TX_ERR_STATE`; data on a channel the session
  does not know is `TX_ERR_CHANNEL`; a foreign `conn_id` is
  `TX_ERR_CONN_ID`; a bad frame is `TX_ERR_FRAME` carrying the codec's
  error kind and offset-bearing message.

Every step returns a `SessionPoll { out: Vec[Vec[UInt8]], events:
Vec[SessionEvent] }`: the exact bytes to put on the wire and the typed
events observed. Nothing mutates mid-step; the caller owns the wire.

## 6. Channel semantics

Channels are declared on both ends with `session_open_channel(id, reliable,
ordered, priority, window)` (symmetric configuration data in phase 1; wire
channel negotiation is a non-goal). `window` clamps into [1, 32];
re-opening an open id emits no event; closing drops live state.

- `reliable` gates the send side: reliable messages enter the bounded
  inflight map and are retransmitted until acked; unreliable messages get a
  sequence number and a send count only.
- `ordered` gates the receive side: out-of-order arrivals are held in a
  bounded buffer and delivered in sequence order as gaps close; unordered
  channels deliver every in-window sequence on arrival (exactly once)
  while the ack watermark still advances only across contiguous receipts.
- Unreliable-ordered channels cannot heal a loss by retransmission; the
  explicit recovery verb is `rl_skip_gap(engine, channel, upto_seq)`,
  which delivers held messages up to the declared gap in order (a
  caller-driven verdict; no clock involved).
- `priority` is declared data (0 = default); it orders nothing in phase 1
  (scheduling by priority is a non-goal).

## 7. Sequencing, acks, retransmission

- Send side: `next_seq` starts at 0 per channel and advances one step per
  message. Reliable messages sit in the inflight map (bounded by the
  channel window) as `{seq, payload, sent_at_ms, retries}`.
- Receive side: `recv_next` is the lowest sequence not yet received;
  `recv_mask` bit `i` (0..63, `RL_RECV_WINDOW` = 63) marks
  `recv_next + i` as received. Receiving `recv_next` normalizes:
  `recv_next` advances across every contiguous received sequence, passing
  messages in order (held buffer for ordered channels, already delivered
  for unordered ones). Bit 0 is always clear after normalization.
- Acks travel as `(ack = recv_next - 1, ack_bits = low 32 mask bits)`
  in ACK frames and piggybacked on DATA frames; `-1` means "nothing
  received yet". `rl_seq_acked(seq, ack, bits)` is the coverage
  predicate: `seq == ack`, or `ack - seq = d` in 1..32 with bit `d-1`
  set. An ack never covers a sequence the receiver has not actually
  received.
- Verdicts on receive: `seq < recv_next` is stale (counted as duplicate
  drop); an in-window bit already set is a duplicate; `seq - recv_next >
  63` is out-of-window and refused (a packet-counter verdict against
  garbage/forged material).
- RTO: `rl_rto_ms(retries)` = `100 * 2^retries` capped at 3200
  (100, 200, 400, 800, 1600, 3200, ...). `rl_poll_rtx(engine, now_ms)`
  returns every retransmission due at the injected time, rescheduling each
  record at `now_ms` with `retries + 1`. When a record's next retry would
  reach `RL_MAX_RETRIES` (5) it is NOT retransmitted again: it becomes an
  `RlFailure` (kind `RL_ERR_RETRIES`) retrieved with
  `rl_take_failures` -- the bounded-retransmit timeout verdict.
- The session re-fragments retransmitted messages identically (same bytes
  as the original attempt), so retransmission is idempotent on the wire;
  duplicate fragments are suppressed during reassembly and a partial
  message is never delivered nor acked.

## 8. Capability facts matrix

| backend | reliable | ordered | max_datagram | max_payload | mtu_estimate | channels | reliable_unordered |
|---|---|---|---|---|---|---|---|
| loopback | true | true | 65507 | 65476 | 65535 | true | true |
| null | false | false | 0 | 0 | 0 | false | false |
| sim | false | false | 65507 | 65476 | 1500 | true | true |
| udp | false | false | 65507 | 65476 | 1500 | true | true |

Rationale (declared, not inferred):

- loopback is the semantic reference: in-memory FIFO, byte-exact, no loss,
  no window, no wall clock.
- null delivers nothing, so it cannot claim reliability, ordering,
  channels or an MTU; its facts are the honest empty.
- sim's schedule may drop, reorder and duplicate regardless of configured
  tables, so the base claim is lossy/unordered; loopback-class size caps
  are mirrored so frames stay portable.
- udp is lossy and unordered; 1500 is the conservative path-MTU estimate.
- `channels` means the session/channel layer is available over the
  backend. `reliable_unordered` is an L2 fact: the reliability engine can
  carry a reliable+unordered channel over this medium -- reliability is
  never a transport property.

Unknown backend kinds get the null facts (`caps_for_kind`), never a guess.

## 9. Error taxonomy

- `FrameError { kind, offset, message }` with `FRAME_ERR_HEADER` (buffer
  shorter than 19), `FRAME_ERR_VERSION`, `FRAME_ERR_KIND`,
  `FRAME_ERR_FLAGS`, `FRAME_ERR_SIZE`, `FRAME_ERR_TRUNCATED`,
  `FRAME_ERR_FRAG`, `FRAME_ERR_OFFSET`.
- `RlError { kind, channel, seq, message }` with `RL_ERR_CHANNEL`,
  `RL_ERR_WINDOW`, `RL_ERR_RETRIES`, `RL_ERR_SEQ`; `RlFailure` records the
  exhausted-retries verdicts.
- `SessionError { kind, code, message }` with `TX_ERR_STATE`,
  `TX_ERR_CHANNEL`, `TX_ERR_VERSION`, `TX_ERR_FRAME` (code = frame error
  kind), `TX_ERR_PAYLOAD`, `TX_ERR_WINDOW`, `TX_ERR_RELIABLE` (code =
  reliability kind), `TX_ERR_BUFFER`, `TX_ERR_CONN_ID`, `TX_ERR_RATE`
  (the additive rate-limited send refused).
- `HandlerOutcome { ok, bytes, failed_id, code }` with
  `HANDLER_ERR_KIND` (unknown handler kind), `HANDLER_ERR_DECODE` (prefix
  mismatch/strip underflow) and `HANDLER_ERR_STAGE` (unknown stage).
- `RateWindow` refusals are the boolean/typed results of `rate_consume`
  (counter `refused`), with `RATE_ERR_*` reserved for callers that prefer
  typed validation.
- `UdpError { kind, message }` with `UDP_ERR_BIND`, `UDP_ERR_SEND`,
  `UDP_ERR_RECV`, `UDP_ERR_ADDR`, `UDP_ERR_CLOSED`.
- `TxError { kind, code, message }` with `TXE_KIND`, `TXE_STATE`,
  `TXE_CLOSED`, `TXE_PAYLOAD`.
- No path fails silently; no path hangs: every refusal, timeout and
  cap breach is one of the typed values above.

## 10. Determinism contract

- No module reads a wall clock: the reliability engine, session and sim
  take `now_ms` from the caller; loopback and null have no time at all.
- No randomness beyond the caller-supplied sim seed (a seeded xorshift64
  stream; state 0 remaps to the fixed seed `0x2545F4914F6CDD1D`). The
  handler chain and rate window add no randomness: handler output is a pure
  function of the chain and bytes, and budget state is a pure function of
  the injected `now_ms` and consume sequence.
- No globals; engine/session/link values are plain state stepped through
  functions. Same inputs => same outputs, byte for byte:
  `sim_digest` proves it for the simulated network, the frame goldens for
  the codec, and the RTO ladder for the engine.
- Packet ids in sim are one shared counter across both directions,
  assigned at send time; release order is (due_ms, insertion order).
- `Str` equality goes through `xiom.string.compare` (`str_compare`).

## 11. UDP backend notes (Windows, verified)

- `socket_bind` binds the wildcard address on the given port; peers reach
  it through `127.0.0.1` on the same host.
- The socket is non-blocking; `udp_poll(timeout_ms)` gates readiness with
  `socket_poll_read` and then drains every pending datagram with the
  runtime's `xiom_socket_recvfrom` entry point, reporting `from_host` /
  `from_port` per datagram. A non-blocking `recvfrom` reports -1 for
  would-block and for genuine errors alike on this runtime; poll gates
  readiness, so -1 is treated as end-of-drain, and the drain is bounded by
  `UDP_DRAIN_MAX` (4096) so a hostile flood cannot spin forever.
- The runtime exposes no `getsockname`, so an ephemeral port cannot be
  discovered; `udp_bind_auto(host, lo, hi)` scans a caller range in
  ascending order instead of binding port 0 and guessing.
- `SO_REUSEADDR` is attempted best-effort before bind; a failed option
  never fails the bind.
- Toolchain note (v0.64.5): the stdlib wrapper `socket_recv_from` returns
  a three-element tuple that the pinned compiler miscompiles
  ("unknown type `Tuple__Vec[UInt8]__Str__Int`", garbage fields,
  access violations; scratch-probe evidence in AUDIT.md). The underlying
  runtime primitive is sound, so this module declares that same runtime
  entry point itself (`xiom_socket_recvfrom`, pointer out-parameters) and
  wraps it byte-safely. No C code is added, vendored or linked: it is the
  runtime's own socket call, and it is the only extern declaration in the
  package.

## 12. Extension surface: handler chain and send budget

Both extensions are additive: no existing function, type, constant or wire
byte changed.

### 12.1 Packet-handler chain (`xiom.transport.handlers`)

`HandlerChain` holds an `enabled` flag and two ordered lists of
`PacketHandler` records (`id`, `kind`, `enabled`, `tag`, `key`):

- outbound handlers run in registration order (index 0 first), so later
  handlers wrap earlier output;
- inbound handlers run in reverse registration order, so the same
  registration order unwinds the layers;
- `handlers_register_*` appends; `handlers_insert_*` places at an explicit
  clamped index; `handlers_set_handler_enabled` toggles one entry;
  `handlers_set_enabled` toggles the whole chain; `handlers_clear*` empties
  it (full clear also re-enables).
- An empty, disabled or all-disabled chain is a byte-exact pass-through.
  A failing handler returns `HandlerOutcome{ok:false, failed_id, code}` with
  the input bytes unchanged.
- Shipped kinds are samples, not cryptography: `HANDLER_KIND_NOOP`,
  `HANDLER_KIND_PREFIX` (prepend/verify a tag) and `HANDLER_KIND_XOR`
  (reversible mask). Compression/encryption/resend adapters can be added as
  new kinds without changing ordering, the chain or the wire format.
- No `xiom.crypto` AEAD adapter is bundled: the available AEAD API requires
  per-packet nonce/key lifecycle (and `aead_seal` uses a CSPRNG), which
  would make the deterministic transport path depend on hidden state and
  randomness. Applications that need it should wrap the chain's plain
  byte transforms and inject their own nonce policy.

### 12.2 Send budget (`xiom.transport.rate`)

`RateWindow` is a saturating byte budget: `available_bytes` starts at
`capacity_bytes`, `rate_refill(w, now_ms)` adds
`elapsed_ms * refill_bytes_per_sec / 1000` (fractional carry kept in
`remainder`), never exceeds capacity, and never refills when the injected
clock does not advance. `rate_can_send` is a pure allowance check;
`rate_consume` subtracts and counts accepted bytes/packets, or refuses and
increments `refused`. A request above capacity is permanently unsendable
until the caller raises capacity.

`session_send_rate_limited(session, channel, payload, now_ms, window)`
refills, checks the payload length (application bytes, not encoded frame
bytes), delegates to the unchanged `session_send` on success, and consumes
only after the session accepted the message. Exhaustion is
`TX_ERR_RATE`; plain `session_send` callers see no change. This is basic
pacing, not congestion control (no RTT/loss feedback, no adaptive target).

## 13. Non-goals (declared, phase 1)

- TLS / built-in cryptography of any kind; authentication; connection
  migration. The handler chain is a generic layering seam, not a crypto
  stack (no bundled AEAD adapter; see sec. 12.1).
- Congestion control beyond the fixed window plus the basic saturating
  rate window; bandwidth estimation; adaptive targets; loss recovery beyond
  retransmission (sec. 12.2).
- Stream muxing weights/QoS scheduling by priority (priority is declared
  data only).
- A shared-memory backend; WebTransport; wire channel negotiation.
- Ack batching/cadence policy (phase 1 acknowledges each accepted data
  frame), and RTT measurement (no wall clock is allowed anyway).
