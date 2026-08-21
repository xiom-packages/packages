# Heartbeat

> Design stage -- specification only.

WebSocket connections are long-lived and can silently die -- a client may drop off the network without ever sending a close frame, and a stale TCP connection can linger for a long time before the OS notices. The `heartbeat` module keeps liveness explicit by driving periodic `Ping` control frames and tracking the corresponding `Pong` responses as **typed liveness state**.

Each connection carries a `Liveness` value that moves through `Alive -> AwaitingPong -> Dead`. On each interval tick the server sends a `Ping` and transitions to `AwaitingPong`; a matching `Pong` returns it to `Alive` and refreshes the connection's last-seen timestamp. If no `Pong` arrives before the configured timeout, the connection is considered `Dead` and is closed with the appropriate code, released from the registry, and its presence is allowed to expire.

The interval and timeout are configurable per connection (`set_interval`, `set_timeout`), so latency-sensitive and battery-sensitive clients can tune the cadence. Because `Ping`/`Pong` are control frames, they are dispatched immediately by the frame loop and never queued behind data messages, so heartbeat accuracy is not affected by backpressure on the data path.

Heartbeats also feed two adjacent subsystems: they refresh **presence TTLs** so that active connections remain visible, and they provide the timely failure signal that lets **reconnect** recovery kick in. Contract hotspots are the ping/pong timing constraints and the requirement that a `Pong` corresponds to an outstanding `Ping`.
