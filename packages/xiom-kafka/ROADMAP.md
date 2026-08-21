# xiom-kafka ROADMAP

## v0.1.0 (Current)
- [x] Type system (KafkaConfig, KafkaMessage, KafkaProducer, KafkaConsumer, KafkaError)
- [x] Producer API (new, produce, flush, close) with input validation
- [x] Consumer API (new, subscribe, poll, commit, close) with recursive topic copy
- [x] Admin API stubs (create_topic, delete_topic, list_topics)
- [x] Result-based error handling with retryable flag
- [x] requires contracts on all public functions (10 contracts)
- [x] Conformance test suite (22 tests)

## v0.2.0 -- librdkafka FFI Bridge
- [ ] extern "C" FFI bindings to librdkafka (rd_kafka_new, rd_kafka_produce, rd_kafka_consumer_poll)
- [ ] Real producer handle allocation via rd_kafka_conf_t / rd_kafka_t
- [ ] Real consumer group coordination with rd_kafka_subscribe / rd_kafka_assign
- [ ] Admin API real implementation (CreateTopics, DeleteTopics, ListTopics via AdminOptions)
- [ ] Link-time dependency on librdkafka (-l rdkafka)
- [ ] Build system integration for native library discovery
- [ ] CI pipeline with librdkafka installed for integration tests

## v0.3.0 -- Advanced Features
- [ ] Async producer with delivery report callbacks (rd_kafka_producev)
- [ ] Consumer rebalance callbacks (rd_kafka_assign / rd_kafka_revoke)
- [ ] Offset management (manual commit, seek, position)
- [ ] Partition-aware produce with key-based routing
- [ ] Message headers support
- [ ] Compression codecs (snappy, gzip, lz4, zstd)
- [ ] SSL/SASL authentication (SCRAM, Kerberos, OAuth)
- [ ] Batch produce with transactions

## v1.0.0 -- Production Readiness
- [ ] Idempotent producer (enable.idempotence)
- [ ] Exactly-once semantics via transactions
- [ ] Schema Registry client integration
- [ ] Avro/Protobuf serde with xiom-protobuf
- [ ] Dead letter queue support
- [ ] Consumer health metrics (lag, throughput)
- [ ] Admin describe/list consumer groups
- [ ] Performance benchmarks (throughput, latency percentiles)
- [ ] Chaos testing (broker failure, network partition)
- [ ] Full librdkafka config surface exposed via KafkaConfig
