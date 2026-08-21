# Channels

> Status: Design stage -- specification only, not yet implemented.

A **channel** is the top-level abstraction in `xiom-realtime`: a communication *namespace* through which events flow. It is deliberately generic. A channel can back a chat room, a live document session, a presence-only lobby, or a notification stream -- the channel does not care what the events mean, only how they are routed to subscribers.

Channels sit in the **subscription layer** of the three-layer realtime model. They own routing, not persistence and not protocol. When a client subscribes to a channel, the channel becomes responsible for delivering every event emitted on it to that subscriber, subject to authorization and the channel's fan-out policy. The actual bytes-on-the-wire delivery is delegated down to `xiom-websocket` through the WebSocket integration bridge; the channel only decides *who* should receive *what*.

In XIOM terms, a channel is modeled as a structural type representing a communication namespace. It carries an identity (its name), the set of active subscriptions, and a reference to the policy that governs retention, fan-out scope, and event expiry for events on that namespace. Rooms build on top of channels by adding membership rules and authorization; a plain channel is the thinner primitive used when a product needs raw pub/sub semantics without room-level access control.

Because channels are the emission point for events, they are where the **event classification** first matters. A durable event emitted on a channel is eligible for persistence and replay; an ephemeral or signal event emitted on the same channel is delivered best-effort and dropped for offline clients. Keeping this distinction at the channel boundary means the rest of the system never has to guess whether an event should survive a disconnect.

**Planned surface:** `channel_open`, `channel_close`, `channel_subscribe`, `channel_emit`. All are design-stage and not yet implemented.
