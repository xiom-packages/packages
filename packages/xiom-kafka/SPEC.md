# SPEC: xiom.kafka -- Apache Kafka client (librdkafka runtime bindings)

## 1. Identity

| Field | Value |
|-------|-------|
| Package | `xiom.kafka` |
| Version | 0.2.0 |
| Kind | binding (`keywords: ["binding"]`) |
| Upstream project | librdkafka -- https://github.com/confluentinc/librdkafka (formerly edenhill/librdkafka) |
| Upstream version | **v2.16.0** (2026-10-02), commit `c6c9973cf1b25394c58e0cade13a36f386856f77` |
| Upstream license | BSD-2-Clause (`LICENSE`, SHA256 `1AD5DF319467E7616C502D1CEE59423110024C3B27474A54AFF771B03DCA473E`) |
| Package license | MIT OR Apache-2.0 |
| Platform | Windows x64 (multi-soname runtime loader; POSIX sonames included) |
| Compiler pin | v0.64.8 |
| Runtime shape | **Runtime-loaded system library. Nothing vendored.** The user supplies `librdkafka.dll` on PATH (or the package directory); the suite SKIPs green when it is absent. |

## 2. Decision: system-library runtime-load, never vendored

The lane's policy (`docs/BINDINGS-LANE.md` §4) allows BSD-2 material, but
the established binding practice in this repo is system libraries only
(`xiom.ffmpeg`, `xiom.fidelityfx`, `xiom.openssl`): no binaries are committed.
`xiom.kafka` follows that shape. The bridge resolves librdkafka with
`LoadLibraryA` on Windows and `dlopen` on POSIX from a multi-soname list:

| Platform | Soname candidates (in order) |
|----------|------------------------------|
| Windows | `librdkafka.dll`, `rdkafka.dll`, `librdkafka-2.dll` |
| Linux | `librdkafka.so.1`, `librdkafka.so` |
| macOS | `librdkafka.1.dylib`, `librdkafka.dylib` |

A missing library is `KAFKA_LOAD_ABSENT` -> SKIP. A library that loads but
does not export the required core set is `KAFKA_LOAD_ABI` -> FAIL. The mock
API is an optional group: a v2.x build without it still loads, and the live
mock battery reports SKIP.

## 3. G2 pin: ABI facts and entry-point set

**Declaration oracle (files read at the pinned commit):**

| File | SHA256 |
|------|--------|
| `src/rdkafka.h` | `4EB8EDE3471C9AD89A862CCDD1BDD21715C5A42EF0E8D285AADBDA7F4DE890C1` |
| `src/rdkafka_mock.h` | `7CC989C2D500F06E0BE7AE1B3741D84EA03D898FC9A53CD499ABA69EA205F029` |
| `src/rdkafka_admin.h` | `9E110CD4FEC0FD865488AF266D281AC1CC716F0C7F3190D32B5646EF5C11655A` |
| `src/rdkafka_mock_handlers.c` | handler table at lines 5167-5202 (evidence for admin support, §5) |
| `LICENSE` | `1AD5DF319467E7616C502D1CEE59423110024C3B27474A54AFF771B03DCA473E` |

**ABI facts encoded by the bridge** (public structs; no upstream code copied):

| Struct | Layout used | Notes |
|--------|-------------|-------|
| `rd_kafka_message_t` (`rdkafka.h:1508-1538`) | `err` @0 (i32), `rkt` @8, `partition` @16 (i32), `payload` @24, `len` @32, `key` @40, `key_len` @48, `offset` @56 (i64), `_private` @64 | v2.16 moved `timestamp`/`timestamp_type` out of the struct; the bridge uses `rd_kafka_message_timestamp()`, so the head stays valid across 2.x |
| `rd_kafka_metadata_t` (`rdkafka.h:6176-6185`) | `broker_cnt` @0 (i32), `brokers` @8, `topic_cnt` @16 (i32), `topics` @24, `orig_broker_id` @32 (i32), `orig_broker_name` @40 | stable across v2.x |
| `rd_kafka_metadata_broker_t` | `id` (i32), `host` (char\*), `port` (i32) | |
| `rd_kafka_metadata_topic_t` | `topic` (char\*), `partition_cnt` (i32), `partitions` (ptr), `err` (i32) | |
| `rd_kafka_metadata_partition_t` | `id`, `err`, `leader` (i32), `replica_cnt` (i32), `replicas` (i32\*), `isr_cnt` (i32), `isrs` (i32\*) | |

**Resolved entry points: 73** (68 required core + 5 optional mock):

| Group | Count | Symbols |
|-------|-------|---------|
| Probe/errors | 5 | `rd_kafka_version`, `_version_str`, `_err2str`, `_err2name`, `_last_error` |
| Config | 6 | `conf_new`, `conf_destroy`, `conf_set`, `conf_get`, `conf_set_dr_msg_cb`, `conf_set_opaque` |
| Client | 8 | `new`, `destroy`, `name`, `poll`, `outq_len`, `flush`, `clusterid`, `mem_free` |
| Producer | 4 | `topic_new`, `topic_destroy`, `topic_name`, `produce` |
| Consumer | 13 | `topic_partition_list_new/destroy/add/set_offset`, `subscribe`, `assign`, `unsubscribe`, `consumer_poll`, `message_destroy`, `message_timestamp`, `message_errstr`, `commit`, `consumer_close` |
| Transactions | 9 | `init/begin/commit/abort_transaction`, `error_destroy/code/string/is_retriable/is_fatal` |
| Metadata | 2 | `metadata`, `metadata_destroy` |
| Admin | 21 | `queue_new/destroy/poll`, `event_destroy/type/error/error_string`, `CreateTopics_result_topics`, `DeleteTopics_result_topics`, `topic_result_error/error_string/name`, `NewTopic_new/destroy`, `DeleteTopic_new/destroy`, `CreateTopics`, `DeleteTopics`, `AdminOptions_new/destroy/set_operation_timeout` |
| Mock (optional) | 5 | `mock_cluster_new/destroy`, `mock_bootstraps`, `mock_topic_create`, `mock_set_controller_id` |

All C entry points are resolved at runtime and ABI-checked; no `-l rdkafka`
link flag is used.

### Re-pin procedure

1. Re-clone/refresh `E:\repos\librdkafka` at the new tag; update the commit,
   tag and header hashes here and in `PROVENANCE.md`.
2. Re-verify the message-head offsets, the metadata struct field order and
   the mock/admin signatures in `src/rdkafka.h` / `src/rdkafka_mock.h`.
3. Re-run the suite twice with the matching prebuilt redist DLL directory on
   `PATH` and twice without it (SKIP path); update §6 and `AUDIT.md`.

## 4. Surface and coverage (0.2.0, 100% of the declared set)

The declared application surface is 54 functions + 14 types + 7 constants.
Every declared function is implemented; no stub returns remain.

| Area | Public functions | Bound to |
|------|------------------|----------|
| Module `xiom.kafka` | `kafka_load_named`, `kafka_load`, `kafka_unload`, `kafka_available`, `kafka_soname`, `kafka_version`, `kafka_version_int`, `kafka_error_string`, `kafka_error_name`, `kafka_error_is_retryable`, `kafka_error_from_code`, `kafka_abi_missing`, `kafka_abi_missing_count`, `kafka_mock_available`, `kafka_last_error_code`, `kafka_last_error`, `kafka_config_new`, `kafka_config_clone`, `kafka_config_set`, `kafka_config_get` (20) | loader + `conf_*` + `last_error` + `err2*` |
| `xiom.kafka.producer` | `kafka_producer_new`, `kafka_produce`, `kafka_produce_partition`, `kafka_producer_poll_delivery`, `kafka_producer_poll`, `kafka_producer_flush`, `kafka_producer_outq_len`, `kafka_producer_close`, `kafka_init_transactions`, `kafka_begin_transaction`, `kafka_commit_transaction`, `kafka_abort_transaction` (12) | `new`, `topic_new`, `produce`, `produce` delivery callback via `conf_set_dr_msg_cb`, `poll`, `flush`, `outq_len`, `destroy`, transaction API |
| `xiom.kafka.consumer` | `kafka_consumer_new`, `kafka_consumer_name`, `kafka_subscribe`, `kafka_assign`, `kafka_unsubscribe`, `kafka_poll`, `kafka_commit`, `kafka_consumer_close` (8) | `new`, `name`, `subscribe`, `assign`, `unsubscribe`, `consumer_poll`, `message_*`, `commit`, `consumer_close` |
| `xiom.kafka.metadata` | `kafka_metadata`, `kafka_cluster_id`, `kafka_metadata_with_config` (3) | `metadata`, `clusterid` |
| `xiom.kafka.admin` | `kafka_create_topic_with`, `kafka_delete_topic_with`, `kafka_list_topics_with`, `kafka_create_topic`, `kafka_delete_topic`, `kafka_list_topics` (6) | `CreateTopics`, `DeleteTopics`, admin result event parsing, metadata |
| `xiom.kafka.mock` | `kafka_mock_is_available`, `kafka_mock_cluster_new`, `kafka_mock_topic_create`, `kafka_mock_set_controller`, `kafka_mock_cluster_destroy` (5) | `rd_kafka_mock_*` |

Types: `KafkaConfig`, `KafkaMessage`, `KafkaDeliveryReport`,
`KafkaMessagePoll`, `KafkaDeliveryPoll`, `KafkaProducer`, `KafkaConsumer`,
`KafkaError`, `KafkaBroker`, `KafkaPartitionMetadata`,
`KafkaTopicMetadata`, `KafkaMetadata`, `KafkaLoadError`,
`KafkaMockCluster`.

**Poll shapes are flat** (`KafkaMessagePoll` / `KafkaDeliveryPoll` with
`status` 0/1/2), not `Result[Option[T]]` -- the 0.64.8 lowering of
`Result[Option[T]]` with struct payloads corrupts the payload (observed on
this package; see `AUDIT.md`). This is the B-26 discipline.

### Producer delivery callbacks

The bridge installs `rd_kafka_conf_set_dr_msg_cb` with a C callback that
records `(correlation id, topic, partition, offset, error, timestamp)` in a
1024-entry per-producer ring. `kafka_produce` / `kafka_produce_partition`
return the correlation id assigned by the bridge; the report carries it back.
Callbacks are served by `rd_kafka_poll` / `rd_kafka_flush` from
`kafka_producer_poll_delivery`, so no librdkafka thread ever enters XIOM.

### Error mapping

`KafkaError.code` is the librdkafka `rd_kafka_resp_err_t` (negative local
errors, positive broker errors). `message` comes from `rd_kafka_err2str` or
the operation's error buffer. `is_retryable` maps the retriable local codes
(`__TRANSPORT`, `__RESOLVE`, `__MSG_TIMED_OUT`, `__ALL_BROKERS_DOWN`,
`__TIMED_OUT`, `__QUEUE_FULL`, `__WAIT_COORD`, `__IN_PROGRESS`,
`__TIMED_OUT_QUEUE`); transaction errors use
`rd_kafka_error_is_retriable`. Empty-input validation errors are local
`-186` (`__INVALID_ARG`), non-retryable.

## 5. Live leg: in-process mock cluster (zero infrastructure)

`xiom.kafka.mock` binds the public `rdkafka_mock.h` API. The suite starts an
explicit mock cluster (`rd_kafka_mock_cluster_new`), seeds topics with
`rd_kafka_mock_topic_create`, and runs **real clients over localhost
listeners**:

| Battery | What is proven |
|---------|----------------|
| Producer | 7 real produce calls (5 auto-partitioned, 2 explicit partitions), flush drains `outq_len` to 0, 7 delivery callbacks with matching ids/topics/offsets and err 0 |
| Metadata | 1 broker, seeded topic, 2 partitions, leader, replicas, ISRs, cluster-id query |
| Consumer (subscribe) | group subscription, 7 messages with topic/partition/offset/key/value/timestamp/timestamp-type decode, byte-for-byte key/value equality, synchronous commit, close |
| Consumer (assign) | explicit topic-partition assignment at `OFFSET_BEGINNING`, 7 messages, unsubscribe, close |
| Admin | real `CreateTopics` / `DeleteTopics` request + result-event parsing; `list_topics` via metadata includes the seeded topic |
| Transactions | `init_transactions`, `begin`, produce, `commit_transaction`; a second `begin`, produce, `abort_transaction`; a `read_committed` consumer sees the committed record and not the aborted one |

**Admin success-path note.** The mock cluster does **not** implement the
Kafka admin wire API: `src/rdkafka_mock_handlers.c` (pinned commit) registers
Produce/Fetch/ListOffsets/OffsetFetch/OffsetCommit/ApiVersion/Metadata/
coordinators/groups/transactions/share APIs, but not `CreateTopics` or
`DeleteTopics`. With `rd_kafka_mock_set_controller_id(1)` the client resolves
a controller and the request reaches the mock, which answers the real
"Topic Admin API (KIP-4) not supported by broker" path; the suite asserts
that typed `-165` result. The success path for `CreateTopics`/`DeleteTopics`
(vs. the request/result machinery) is therefore exercised against a real
broker only; a local Kafka 3.9.1 container run is recorded in §6 / `AUDIT.md`.
This is a property of the upstream mock, not a binding gap.

**Why this still proves the admin binding:** the suite exercises the real
`rd_kafka_CreateTopics`/`rd_kafka_DeleteTopics` calls, the admin-options
timeout, the result queue, `rd_kafka_event_*` classification, and
`rd_kafka_topic_result_*` parsing. A success response takes the same code
path after `rd_kafka_event_error() == 0`.

## 6. Test matrix

Command (from the repo root):

```
& .\scripts\port.ps1 -Package xiom.kafka -TimeoutSec 300
```

| Configuration | Result |
|---------------|--------|
| librdkafka v2.16.0 redist dir prepended to `PATH` (live) | **PASS 50/50 x2** -- probe/config/mock/producer/metadata/consumer/admin/transactions |
| No librdkafka on `PATH` (SKIP) | **PASS 6/6 x2** -- loader ABSENT classification + pure type checks |
| Real broker (optional sample) | **PASS 10/10** -- `apache/kafka:3.9.1` KRaft at `127.0.0.1:9092`; CreateTopics success, produce/consume, commit, DeleteTopics success, list before/after |
| Bogus soname (every run) | ABSENT, never FAIL |
| Present library missing core exports | ABI FAIL (not a silent SKIP) |

Local runtime sample used for the live run (NOT the pin, nothing committed):

| Artifact | Size | SHA256 |
|----------|------|--------|
| `librdkafka.redist` 2.16.0 NuGet package | 43,345,224 B | `F5B41D820D6A7E886BCB4C574020A1DCD54D72A965BAD681F15C1C788A80AF5B` |
| `librdkafka.dll` (win-x64) | 2,852,864 B | `8DB0996180665F2A52394F27DDC00DE6F08F64F9809E8B437FD209991A317953` |
| `libcrypto-3-x64.dll` | 5,303,296 B | `97F488DB248269E1D2AD426EEBD4F093333055BB30165D3C844A9EE06295FE05` |
| `libssl-3-x64.dll` | 865,792 B | `E739348CBA96819AC0E0B85F8FE160B0BCE6F0EB139A106E6F9CAAF63867DC28` |
| `libcurl.dll` | 709,120 B | `D843CF862C360AB1DEC4D236B5850208E8556BE64AACBE79260A4D1BAEC80FEA` |
| `zstd.dll` | 661,504 B | `C04BE707F8D1A1D264F62291F397957D145D6522D9A3BE4E160B58E4B437B181` |
| `z.dll` | 89,600 B | `933108900484900EEB6267C8C3D13DE74DAC2F44C2E9EB96B24DE5F1CE371BE2` |
| `librdkafkacpp.dll` | 92,160 B | `FDCB9FBAC3E72F12A519865554064D7B0A3BD0A789D98A703C4008A82621DF4E` |
| `msvcp140.dll` | 575,056 B | `7B8A6F283884E6448559DCF510B00C1A885BFB8E598EA05CD2C290C874657326` |
| `vcruntime140.dll` | 119,888 B | `642AE52687A7A6BFB03D0B20DC7E07F4B11CECA634F7EB7BA184D6711AB51A51` |

The redist package also carries win-x86 and other runtimes; only win-x64 was
extracted for the local run.

## 7. Design and safe boundary (G5)

`kafka.xi` is the only module with `unsafe`/`extern "C"`; every foreign call
and struct read is confined to `src/kafka_bridge.c` and the root module's
`kafka_bridge_*` helpers. The per-area modules (`producer`, `consumer`,
`metadata`, `admin`, `mock`) are typed wrappers with validation and no FFI.

- Handles cross as `Int`; C pointers never enter XIOM.
- Copy-out happens in C: message key/value, topics, metadata names/hosts,
  delivery reports, error strings.
- Nullable C arguments are `Int 0`; out-params are caller-owned buffers.
- No `Result[Option[T]]`; flat poll outcome structs (B-26).
- The bridge is compiled with `--c-source` (`port.args.json`); it never
  links librdkafka.
- Config: named fields (`bootstrap.servers`, `client.id`, `group.id`) plus
  the full librdkafka property surface through `kafka_config_set/get`, which
  validates against a real `rd_kafka_conf_t`. SSL/SASL/compression are
  reachable as configuration; no separate wrappers are declared.

## 8. Scope / non-goals

Declared non-goals for 0.2.0: message headers, share groups, consumer-group
admin (describe/list groups), offsets-for-times/watermarks, manual
per-partition offset commit structures, OAuth callbacks, and the C++
(`librdkafkacpp`) API. The admin surface is topics only (create/delete/list).
The full librdkafka config surface is exposed generically rather than as
typed setters.

## 9. Version history

- **0.2.0** -- real runtime-loaded librdkafka bindings. All 0.1.0 stubs
  removed: producer handles are real `rd_kafka_t`, `kafka_poll` returns real
  messages with decoded fields, admin calls are real `CreateTopics` /
  `DeleteTopics` requests, and the suite runs a live mock-cluster battery.
  Added transactions, metadata, config set/get, delivery reports, multi-
  soname loader, ABI/SKIP classification, mock cluster support, PROVENANCE.
- **0.1.0** -- ported stubs (22 tests; not publishable).


