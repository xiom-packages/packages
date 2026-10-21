# xiom.kafka

Apache Kafka client for XIOM -- real librdkafka v2.16.0 bindings through a
runtime loader. No link-time dependency, nothing vendored.

> **Status:** `incubating` -- 50/50 live checks (in-process mock cluster) and
> 6/6 SKIP checks; not yet published.
> **Runtime:** librdkafka v2.16.0 (`librdkafka.dll` / `librdkafka.so.1` /
> `librdkafka.1.dylib`) supplied by the host. The suite SKIPs green when the
> library is absent.

## Run

From the repo root:

```
& .\scripts\port.ps1 -Package xiom.kafka -TimeoutSec 300
```

Put a librdkafka build on `PATH` (or in the package directory) for the live
leg. The suite starts an in-process **mock cluster** -- no broker required.
A local prebuilt release set can be obtained from the Confluent
`librdkafka.redist` NuGet package; see `SPEC.md` §6 / `PROVENANCE.md`.

## Usage

```xiom
use xiom.kafka;
use xiom.kafka.types;
use xiom.kafka.producer;
use xiom.kafka.consumer;
use xiom.kafka.mock;

match kafka_load() {
  Ok(_) => {
    var cfg = kafka_config_new("localhost:9092");
    cfg.client_id = "my-service";
    match kafka_producer_new(&cfg) {
      Ok(p) => {
        var key = Vec[Int].new();
        var value = Vec[Int].new();
        value.push(104); value.push(105);       // "hi"
        match kafka_produce(&p, "events", &key, &value) {
          Ok(id) => {
            // id comes back in the delivery report
            let poll = kafka_producer_poll_delivery(&p, 5000);
            if poll.status == 1 && poll.report.err == 0 { /* delivered */ }
          }
          Err(e) => { /* e.code / e.message / e.is_retryable */ }
        }
        var flush_rc = kafka_producer_flush(&p, 10000);
        kafka_producer_close(p);
      }
      Err(e) => { /* typed KafkaError */ }
    }
  }
  Err(e) => { /* e.kind == KAFKA_LOAD_ABSENT -> library not installed */ }
}
```

Consumers use `kafka_consumer_new` + `kafka_subscribe` (or `kafka_assign`)
and poll `KafkaMessagePoll` (status 0 = timeout, 1 = message, 2 = error).
`kafka_metadata`, `kafka_cluster_id`, `kafka_create_topic_with`,
`kafka_delete_topic_with`, `kafka_list_topics_with` and the transaction
calls are available; `kafka_config_set/get` exposes the full librdkafka
property surface (SSL/SASL/compression included).

## Libs inventory

| Module | Contents | State |
|--------|----------|-------|
| `xiom.kafka` | loader/version/errors, config set/get, FFI bridge helpers | implemented |
| `xiom.kafka.types` | KafkaConfig/Message/Error/Metadata/Delivery/Poll/Mock types | implemented |
| `xiom.kafka.producer` | produce (auto + explicit partition), delivery reports, flush, poll, transactions, close | implemented |
| `xiom.kafka.consumer` | subscribe, assign, poll + field decode, commit, unsubscribe, close | implemented |
| `xiom.kafka.metadata` | full metadata + cluster id | implemented |
| `xiom.kafka.admin` | CreateTopics, DeleteTopics, topic list | implemented |
| `xiom.kafka.mock` | librdkafka mock cluster (live-suite support) | implemented |

## Licenses

Package: MIT OR Apache-2.0. Upstream librdkafka: BSD-2-Clause
(`PROVENANCE.md`). No upstream binaries or sources are committed.

