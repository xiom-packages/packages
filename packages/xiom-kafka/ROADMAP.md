# xiom.kafka ROADMAP

## v0.1.0 -- ported stubs (not published)
- [x] Type system, producer/consumer/admin API shapes, 22-test conformance
- [x] Typed error paths and contracts
- [ ] Real librdkafka FFI (superseded by 0.2.0)

## v0.2.0 -- real librdkafka bindings (current)
- [x] Runtime loader (multi-soname, LoadLibraryA/dlopen, no link dependency)
- [x] ABI export verification; ABSENT -> SKIP, broken install -> FAIL
- [x] Client config set/get against a real `rd_kafka_conf_t`
- [x] Producer: real handles, auto + explicit partition produce, delivery
      callbacks/reports, flush, poll, outq, close
- [x] Transactions: init/begin/commit/abort with typed `rd_kafka_error_t`
- [x] Consumer: subscribe, assign (explicit partitions), poll + full field
      decode, commit, unsubscribe, close
- [x] Metadata: brokers/topics/partitions + cluster id
- [x] Admin: real CreateTopics/DeleteTopics + result parsing, topic list
- [x] In-process mock-cluster live suite (producer/consumer/metadata/admin/
      transactions) with zero external infrastructure
- [x] Optional real-broker sample (Kafka 3.9.1) for admin success
- [x] PROVENANCE / AUDIT / SPEC / README coverage records
- [ ] Publish request (lane -> native/release)

## v0.3.0 -- advanced client surface
- [ ] Message headers (produce/consume + header iteration)
- [ ] Consumer-group admin (describe/list groups)
- [ ] Offsets for times / watermarks / per-partition commit structures
- [ ] Header/record timestamps on produce
- [ ] Rebalance callback hooks
- [ ] Typed config setters for the most-used security/compression keys
- [ ] Windows CI image with the redist DLL set for the live leg

## v1.0.0 -- production readiness
- [ ] Idempotent producer defaults and documented exactly-once recipe
- [ ] Consumer lag/throughput metrics
- [ ] Schema Registry / serde integration (xiom.protobuf, xiom.avro)
- [ ] Dead-letter queue helpers
- [ ] Multi-broker mock fault injection (disconnects, leader moves)
- [ ] Performance benchmarks (throughput, latency percentiles)
