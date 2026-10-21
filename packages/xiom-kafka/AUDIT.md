# AUDIT: xiom.kafka

## Status

**0.2.0 -- real librdkafka bindings; publishable.** The 0.1.0 stubs are
gone: producer/consumer handles are real `rd_kafka_t` instances,
`kafka_poll` decodes real messages, admin calls send real
CreateTopics/DeleteTopics requests, and delivery callbacks are installed.
The library is runtime-loaded (no link-time dependency); the suite SKIPs
green when it is absent.

| Gate | Result |
|------|--------|
| G0 manifest/marker | `package.xi` 0.2.0, `keywords` contains `binding`, BSD-2 upstream recorded |
| G1 compile | 7 modules compile on v0.64.8 (`port.ps1 -NoRun`: PASS 7/7) |
| G2 ABI pin | librdkafka v2.16.0 commit `c6c9973...`; header hashes + entry-point set in `SPEC.md`/`PROVENANCE.md` |
| G3 loader smoke | live: version `2.16.0` + soname; absent: bogus-soname ABSENT -> SKIP |
| G4 function smoke | live mock cluster: producer, delivery callbacks, metadata, subscribe/assign consumer, commit, admin request paths, transactions; real-broker sample: admin create/delete success + produce/consume |
| G5 confinement | all `unsafe`/`extern "C"` in `kafka.xi`; all foreign struct reads/copies in `src/kafka_bridge.c` |
| G6 upstream-first | `PROVENANCE.md`; pinned clone + header hashes; independent code; no upstream vectors |
| G7 coverage | **73/73 bound C entry points** (68 required + 5 optional mock); **54/54 declared application functions** implemented |

## Tests (v0.64.8)

| Run | Command | Result |
|-----|---------|--------|
| Live x2 A/B | `scripts/port.ps1 -Package xiom.kafka -TimeoutSec 300` with the redist win-x64 dir on `PATH` | **PASS 50/50** each (probe/config/mock/producer/metadata/consumer/admin/transactions) |
| SKIP x2 A/B | same command, default `PATH` (no librdkafka) | **PASS 6/6** each (ABSENT classification + pure types) |
| Real broker (optional) | `port.ps1 -Package xiom.kafka -Suite tests/test_real_broker.xi` against `apache/kafka:3.9.1` at `127.0.0.1:9092` | **PASS 10/10** (CreateTopics, list, produce/delivery, consume, commit, DeleteTopics, list-after-delete) |
| Compile-only | `port.ps1 -Package xiom.kafka -NoRun` | PASS 7/7 modules |

The old baseline was 22/22 stubs. The suite now has 50 live assertions; the
absent-library run reports SKIP checks (never FAIL) and the pure type checks.

## Changes from 0.1.0

- **Real FFI**: `src/kafka_bridge.c` resolves 73 `rd_kafka_*` entry points
  at runtime (LoadLibraryA/dlopen), verifies the export set, and exposes a
  flat C surface. Nothing is linked or vendored.
- **Producer**: real `rd_kafka_t`; `rd_kafka_produce` with
  `RD_KAFKA_MSG_F_COPY`; delivery callback ring (id/topic/partition/offset/
  err/timestamp); `flush`, `poll`, `outq_len`, `destroy`; transactions
  (`init/begin/commit/abort` via `rd_kafka_error_t`).
- **Consumer**: real `rd_kafka_subscribe` / `rd_kafka_assign` (explicit
  topic-partitions at `OFFSET_BEGINNING`), `rd_kafka_consumer_poll` with
  full field decode (topic/partition/offset/key/value/timestamp/type),
  synchronous commit, unsubscribe, close.
- **Metadata**: full broker/topic/partition tree + cluster id.
- **Admin**: real `CreateTopics`/`DeleteTopics` with `AdminOptions`
  operation timeout, result-event validation (`event_type` 100/101),
  `event_error*` and `topic_result_*` parsing; topic list via metadata.
- **Config**: `kafka_config_set/get` validate against a real
  `rd_kafka_conf_t`; named fields plus arbitrary properties (SSL/SASL/
  compression reachable).
- **Loader**: multi-soname candidates; ABSENT vs ABI classification; mock
  API treated as an optional export group.
- **Live suite**: in-process librdkafka mock cluster, seeded topics, real
  clients over localhost; no broker or Docker required.
- **Types/API**: added `KafkaDeliveryReport`, flat `KafkaMessagePoll` /
  `KafkaDeliveryPoll`, metadata and mock types; `KafkaConfig` carries
  `prop_names`/`prop_values`; `KafkaMessage` carries `timestamp_type`;
  `kafka_consumer_close` now returns `Result` (errors are not swallowed).

## Compiler findings (v0.64.8, recorded for the compiler lane)

1. **`Result[Option[Struct]]` payload corruption.** The first live run
   returned a `KafkaDeliveryReport` through `Result[Option[...]]`; the
   matched report's `Str` field had length `0xFFFFFFFF` and garbage content
   while the C bridge's own harness decoded the same reports correctly.
   Switched both poll paths to flat outcome structs (`status` 0/1/2), the
   B-26 discipline; the live suite then passed. No bridge change was needed.
2. **T007 pre-entry contract on whole-body `unsafe`.** Functions whose body
   is a single `unsafe { ... }` block are rejected unless they declare a
   `requires:` clause; `requires: true` is used for the copy/loader helpers.

## Known gaps / non-goals

1. **Admin create/delete success is not exercised by the mock suite.** The
   pinned upstream mock (`rdkafka_mock_handlers.c:5167-5202`) has no
   CreateTopics/DeleteTopics handler. The suite exercises the real request,
   controller resolution and result-event parsing, and asserts the typed
   `-165` unsupported-feature result. Success is verified by the optional
   real-broker sample (10/10 above). This is an upstream mock property, not
   a binding gap.
2. **Runtime generation coverage.** The pin is v2.16.0; the bridge uses the
   stable message head and `rd_kafka_message_timestamp()`, so other v2.x
   builds are expected to work, but only 2.16.0 was verified. The loader
   requires the admin/transaction export set (librdkafka >= 0.11 era);
   older builds are not claimed.
3. **Declared non-goals** (see `SPEC.md` §8): message headers, share
   groups, consumer-group admin, offsets-for-times/watermarks, OAuth
   callbacks, C++ API.
4. **No committed binary.** The live proof needs a host-supplied librdkafka;
   CI without it records SKIP, as the lane policy requires.

## Files

- `kafka.xi` -- loader/errors/config + the only `extern`/`unsafe` surface.
- `src/kafka_bridge.c` -- original runtime bridge (added).
- `src/types.xi` -- public types (rewritten).
- `src/producer.xi`, `src/consumer.xi`, `src/admin.xi` -- real wrappers
  (rewritten); `src/metadata.xi`, `src/mock.xi` -- added.
- `tests/test_conformance.xi` -- 50 live checks or 6 SKIP checks (rewritten).
- `tests/test_real_broker.xi` -- optional real-broker sample (10 checks).
- `port.args.json` -- `--c-source` bridge + 240 s timeout.
- `SPEC.md`, `README.md`, `PROVENANCE.md`, `STATUS.json`, `ROADMAP.md`,
  `AUDIT.md` -- updated in the same change.

