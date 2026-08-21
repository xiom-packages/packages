# Subprotocols

> Design stage -- specification only.

A raw WebSocket connection defines only how bytes are framed, not what those bytes mean. Subprotocols let a client and server agree on message semantics at connection time. During the opening handshake the client may offer one or more protocol names via the `Sec-WebSocket-Protocol` header; the server selects at most one it supports and echoes it back. The `subprotocol` module models this as a **typed negotiation step** so the chosen protocol is an explicit, validated value rather than an unchecked string.

`negotiate(offered, supported)` returns the first mutually acceptable protocol or `None`, and the handshake response includes the selection only when negotiation succeeds. A registered `SubprotocolSpec` can attach message-validation logic, so a connection speaking a given subprotocol can have its messages checked against that protocol's contract before reaching application handlers. This keeps subprotocol rules enforceable at the transport boundary.

The purpose of subprotocol support is **reuse of the same transport by higher-level packages**. `xiom-graphql` subscriptions and `xiom-realtime` rooms can each define their own subprotocol and message semantics while sharing the identical handshake, framing, heartbeat, backpressure, and reconnect machinery provided here. `xiom-websocket` stays a transport-and-session layer; the meaning layered on top lives in the package that registers the subprotocol.

Contract hotspots are the legality of the negotiated protocol (it must be one the server actually registered) and, where a spec provides one, the validity of messages against that subprotocol's rules.
