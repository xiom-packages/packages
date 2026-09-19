# Authorization

> Status: Design stage -- specification only, not yet implemented.

Realtime authorization in `xiom.realtime` is checked at **three distinct points**, and keeping them separate is a deliberate design decision:

- **On join** -- may this user enter this room at all?
- **On send** -- may this user emit this particular event into this room?
- **On subscription change** -- may this user start, pause, or alter what they are listening to?

Separating join rights from send rights from subscription rights keeps *room access* and *broadcast rights* independent and auditable. A user might be allowed to join and read a room but not send; another might be allowed to send only certain event kinds; a moderator might have subscription privileges others lack. Collapsing these into a single "is a member" check would lose all of that nuance and make access decisions impossible to audit after the fact.

The XIOM-native translation of this is **contract-checked join/send rules**. The authorization checks are not advisory helper functions that callers may forget to invoke -- they are expressed as `requires:` contracts on the entry points that perform joins, sends, and subscription changes. The example workflow shows the shape: `join_room` carries `requires: ctx.user.is_authenticated()` at the contract level, and its body calls `room.auth.can_join(...)?` before creating a subscription. If the contract or the check fails, the operation cannot proceed. This turns "did we remember to authorize this?" from a code-review question into a compile-and-contract guarantee.

Authorization is intentionally positioned **upstream of fan-out and ordering**. The send check runs before an event is assigned a sequence number and before it is scattered across the cluster, so an unauthorized event never enters the durable stream, never consumes a sequence number, and never reaches a subscriber on any node. This ordering of concerns is what keeps the distributed case sound: the authorization decision is made once, centrally, at the point of emission.

**Planned surface:** `auth_can_join`, `auth_can_send`, `auth_can_subscribe`, all returning `Result[Unit, AuthError]`. All are design-stage and not yet implemented.
