# Rooms

> Status: Design stage — specification only, not yet implemented.

A **room** is a scoped communication group built on top of a channel. Where a channel is a bare namespace, a room adds three things that products almost always need: explicit **membership rules**, **authorization rules**, and a **fan-out policy**. A room is the unit most applications reason about — "the #general room," "this document's editing session," "the game lobby."

Rooms tie together several modules. **Membership** (`membership.xi`) tracks who has joined, who has left, and what role each member holds; membership legality is a contract hotspot, so every join and leave is a validated state transition rather than a bare mutation. **Subscriptions** (`subscription.xi`) track the client-side listening state within the room, which is distinct from membership: a user can be a member of a room without an active subscription (offline), and the two are reconciled on reconnect.

Authorization is checked at the room boundary at three points — on join, on send, and on subscription change. This separation keeps *room access* distinct from *broadcast rights*: a user may be allowed to join and read a room but not to send, or allowed to send only certain event kinds. Because these checks are expressed as XIOM contracts (`requires:` clauses on the join/send entry points), illegal access is a type-level and contract-level failure, not a runtime convention that can be forgotten.

Each room carries a **policy** object describing message retention, fan-out scope, presence TTL, and event expiry. This is what lets one room be a durable chat log while another is an ephemeral typing-and-cursor collaboration space, without special-casing the delivery machinery. When a room broadcasts, it hands the event and its policy to the fan-out layer, which decides between local-only and distributed delivery.

**Planned surface:** `room_create`, `room_subscribe`, `room_leave`, `room_broadcast`, plus membership and roster queries. All are design-stage and not yet implemented.
