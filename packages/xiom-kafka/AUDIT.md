# AUDIT: xiom-kafka

## Status
All 4 source files compile on xiom v0.45.3 with stub implementations.

## System Library Dependencies
- **librdkafka** (Apache Kafka C client library)
  - Windows: `vcpkg install librdkafka`
  - Linux: `apt install librdkafka-dev` (Debian) / `dnf install librdkafka-devel` (Fedora)
  - macOS: `brew install librdkafka`
  - Link flag: `-l rdkafka`

## Known Gaps
1. **librdkafka FFI not available**: All producer/consumer/admin functions are stubs. Producer stub returns handle=-1, consumer poll always returns None, admin always returns errors.
2. **`let _ =` pattern removed**: The `_` identifier for unused variable bindings is not supported in `let`/`var` statements. Replaced with proper variable names or removed unused bindings.
3. **`Unit{}` replaced**: The `Unit` type is not recognized by the compiler. Return types are now `Int` with `Ok(0)` for success or `Result[Int, KafkaError]`.
4. **`use xiom.kafka.types` added**: Cross-module type imports added to producer, consumer, and admin modules. Original files had no imports, causing unresolved type errors.
5. **topic_list_copy tail call**: Fixed `acc.push()` return — needs explicit `return acc` after push to comply with XIOM's move semantics.

## Files Modified
- `src/types.xi` — No changes needed (compiled clean)
- `src/producer.xi` — Added `use xiom.kafka.types`, removed `let _`, fixed return types
- `src/consumer.xi` — Added `use xiom.kafka.types`, removed `let _`, fixed return types, fixed tail recursion
- `src/admin.xi` — Added `use xiom.kafka.types`, removed `let _`, fixed return types

## Restoring Production FFI
To restore production functionality:
1. Implement librdkafka C FFI bindings (`rd_kafka_new`, `rd_kafka_produce`, `rd_kafka_consumer_poll`, etc.) via `extern "C"` blocks
2. Link against `librdkafka` at compile time
3. Replace stub handle=-1 with real librdkafka context handles
