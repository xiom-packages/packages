# Ordering & Deduplication

> Status: Design stage — specification only, not yet implemented.

Realtime systems fail in characteristic ways: events arrive **twice**, arrive **late**, or arrive **out of order**. `xiom-realtime` addresses all three with explicit ordering metadata, deduplication windows, and replay cursors, rather than hoping the transport preserves order end-to-end (it does not, especially once distributed fan-out and reconnects are involved).

**Sequence numbers.** Each room maintains a monotonic sequence counter. Every durable event emitted into the room is assigned the next sequence number, and this assignment happens centrally — before fan-out scatters the event across nodes. Sequence monotonicity is a contract hotspot: the allocation path is guarded so that the returned sequence is always strictly greater than the previous one for that room. Subscribers can therefore detect gaps (a missing sequence means a dropped or delayed event) and detect reordering (a sequence lower than one already seen).

**Deduplication.** Because retries, reconnect replay, and multi-path delivery can all cause the same logical event to appear more than once, each room keeps a **dedupe window** keyed by event identity. An event whose id is already inside the window is discarded rather than re-delivered. The window is bounded — it is a sliding window over recent events, not an unbounded set — which keeps memory predictable while catching the duplicates that matter in practice.

**Replay cursors.** For reconnect flows, each subscriber has a **cursor** marking the last sequence number it successfully processed. On reconnect, the offline/replay path uses this cursor to resend exactly the durable events the client missed, in order, with no duplicates and no gaps. The cursor is the bridge between the ordering layer and offline sync: ordering guarantees the events have a well-defined position, and the cursor records how far a given client has consumed that position.

Ephemeral and signal events are deliberately **not** sequenced or deduplicated the same way — they are best-effort and short-lived, so paying the ordering cost for them would be wasted. Ordering guarantees apply to the durable event stream where correctness actually matters.

**Planned surface:** `ordering_next_seq` (with an `ensures: result > previous` contract), `ordering_dedupe`, `ordering_cursor`. All are design-stage and not yet implemented.
