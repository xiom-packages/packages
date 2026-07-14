# xiom-kafka SPEC

## Package Overview
`xiom-kafka` provides typed XIOM bindings for Apache Kafka via librdkafka. It defines configuration, message, producer, consumer, and admin types with stub implementations that produce descriptive errors. Full functionality requires a native librdkafka backend.

## Modules

### `xiom.kafka.types` — Kafka Data Types
| Type | Fields |
|---|---|
| `KafkaConfig` | `brokers: Str; client_id: Str; group_id: Str;` |
| `KafkaMessage` | `topic: Str; partition: Int; offset: Int; key: Vec[Int]; value: Vec[Int]; timestamp: Int;` |
| `KafkaProducer` | `handle: Int; config: KafkaConfig;` |
| `KafkaConsumer` | `handle: Int; config: KafkaConfig; topics: Vec[Str];` |
| `KafkaError` | `code: Int; message: Str; is_retryable: Bool;` |

**Constructor:** `kafka_config_new(brokers: Str) -> KafkaConfig` — `requires: brokers.len() > 0`

### `xiom.kafka.producer` — Producer API
| Function | Signature | Contracts |
|---|---|---|
| `kafka_producer_new` | `(config: &KafkaConfig) -> Result[KafkaProducer, KafkaError]` | Stub: returns handle=-1 |
| `kafka_produce` | `(producer: &KafkaProducer, topic: Str, key: &Vec[Int], value: &Vec[Int]) -> Result[(), KafkaError]` | `requires: topic.len() > 0, value.len() > 0` |
| `kafka_producer_flush` | `(producer: &KafkaProducer, timeout_ms: Int) -> Result[(), KafkaError]` | Stub: always Ok |
| `kafka_producer_close` | `(producer: KafkaProducer)` | Consumes producer |

**Stub behavior:**
- `kafka_producer_new` returns a valid (but inert) `KafkaProducer` with `handle = -1`.
- `kafka_produce` validates inputs (topic/value non-empty) then returns `Ok(())`.
- All actual message production requires librdkafka FFI.

### `xiom.kafka.consumer` — Consumer API
| Function | Signature | Contracts |
|---|---|---|
| `kafka_consumer_new` | `(config: &KafkaConfig, topics: &Vec[Str]) -> Result[KafkaConsumer, KafkaError]` | Stub: returns handle=-1 |
| `kafka_subscribe` | `(consumer: &mut KafkaConsumer, topics: &Vec[Str]) -> Result[(), KafkaError]` | `requires: topics.len() > 0` |
| `kafka_poll` | `(consumer: &KafkaConsumer, timeout_ms: Int) -> Result[Option[KafkaMessage], KafkaError]` | Stub: always `Ok(None)` |
| `kafka_commit` | `(consumer: &KafkaConsumer) -> Result[(), KafkaError]` | Stub: always Ok |
| `kafka_consumer_close` | `(consumer: KafkaConsumer)` | Consumes consumer |

**Stub behavior:**
- `kafka_subscribe` copies topic list to consumer state (pure XIOM operation).
- `kafka_poll` always returns `Ok(None)` — no messages without librdkafka.
- `kafka_commit` always returns `Ok(())`.

### `xiom.kafka.admin` — Admin API
| Function | Signature | Notes |
|---|---|---|
| `kafka_create_topic` | `(brokers: Str, topic: Str, partitions: Int, replication: Int) -> Result[(), KafkaError]` | Stub: always Err |
| `kafka_delete_topic` | `(brokers: Str, topic: Str) -> Result[(), KafkaError]` | Stub: always Err |
| `kafka_list_topics` | `(brokers: Str) -> Result[Vec[Str], KafkaError]` | Stub: always Err |

**Stub behavior:**
All admin functions return `Err(KafkaError { code: -999; message: "..."; is_retryable: false })`. These require librdkafka `rd_kafka_AdminOptions` and are the most complex FFI surface.

## Error Handling
All FFI-bound functions return `Result[T, KafkaError]`. The `KafkaError` type carries:
- `code`: librdkafka error code (rd_kafka_resp_err_t)
- `message`: Human-readable error description
- `is_retryable`: Whether the operation can be retried safely

Pure XIOM validation (e.g., empty topic check) returns errors immediately. Stub operations return `Ok` for all non-admin calls and `Err` for admin calls.

## Dependencies
- `xiom-std` (0.1.0): Vec, Int, Str, Bool, Option, Result types.
- **Native:** librdkafka (C library) for actual Kafka I/O.

## Design Constraints
- No `for` loops — topic list copying uses `topic_list_copy` recursive helper.
- No `self` methods — all functions take explicit receiver parameters.
- `Match` uses bare variant names.
- Admin API is fully stubbed; producer and consumer have inert but valid-in-memory representations.
