# xiom-websocket ROADMAP

## v0.1.0 (Current)
- [x] Core types (WsOpcode, WsConnectionState, WsConnection, WsFrame, WsMessage, WsMessageKind)
- [x] Support types (WsHandshakeRequest, WsHandshakeResponse, WsError, WsServer, WsChannel)
- [x] Opcode enum with helpers (to_int, from_int, is_control, is_data, to_str)
- [x] Frame constructors (frame_new, frame_text, frame_binary, frame_close, frame_ping, frame_pong)
- [x] Frame introspection (frame_is_final, frame_is_control, frame_is_data, frame_payload_len)
- [x] Frame validation with RFC 6455 rules (control frame size limits, fragmentation rules)
- [x] Frame encode/decode stubs (frame_encode, frame_decode)
- [x] extern "C" FFI block for platform socket operations (ws_socket_*)
- [x] extern "C" FFI block for WebSocket handshake (ws_handshake_*)
- [x] extern "C" FFI block for WebSocket frame codec (ws_frame_*)
- [x] Connection lifecycle (connection_new, connection_is_open, connection_is_closed, connection_set_state, connection_set_heartbeat)
- [x] Handshake validation stubs (handshake_validate_request, handshake_is_valid, handshake_compute_key)
- [x] Server management (server_new, server_add_connection, server_find_connection, server_remove_connection, server_broadcast_count)
- [x] Message type with sequence numbers (message_new, message_text, message_binary)
- [x] Channel subscriptions (channel_new, channel_subscribe, channel_unsubscribe, channel_has_subscriber, channel_subscriber_count)
- [x] Close code helpers (close_code_*) with RFC 6455 codes
- [x] Heartbeat utilities (heartbeat_interval_default, heartbeat_timeout_default, heartbeat_is_due, heartbeat_is_alive)
- [x] Conformance test suite (10 tests)

## v0.2.0 — Working Frame Codec
- [ ] Implement actual frame encoding with mask XOR
- [ ] Implement actual frame decoding with mask XOR
- [ ] 16-bit and 64-bit extended payload length support
- [ ] Fragmentation reassembly
- [ ] UTF-8 validation for text frames
- [ ] Control frame interleaving in fragmented messages

## v0.3.0 — Live Transport
- [ ] TCP socket integration via xiom-net
- [ ] Server accept loop with connection registry
- [ ] Client connect with full handshake
- [ ] Send queue with backpressure
- [ ] Receive loop with frame dispatch
- [ ] Non-blocking I/O mode

## v0.4.0 — Protocol Hardening
- [ ] RFC 6455 close handshake state machine
- [ ] Ping/pong keep-alive loop
- [ ] Per-message deflate extension (RFC 7692)
- [ ] Subprotocol negotiation
- [ ] Authentication hooks (JWT, token, cookie-based)

## v0.5.0 — Advanced Features
- [ ] Reconnect with sequence recovery
- [ ] Presence tracking with TTL
- [ ] Pub/sub backplane interface
- [ ] Redis/NATS/Kafka backplane adapters
- [ ] Broadcast helpers (local + distributed)

## v1.0.0 — Production Readiness
- [ ] Full contract verification on all public functions
- [ ] Performance benchmarks (throughput, latency, memory)
- [ ] Load testing suite with concurrent connections
- [ ] Fuzzing harness for frame codec
- [ ] Integration tests with xiom-http upgrade bridge
