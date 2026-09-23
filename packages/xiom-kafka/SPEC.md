# xiom.kafka -- SPEC
**Phase**: 4 (Enterprise) | **Priority**: Medium
**Status**: Stub implementation ported to XIOM 0.61.3; conformance suite green (22/22) | **Depends on**: xiom.ffi (planned)
Apache Kafka client (librdkafka). System-installed. Weekend effort.

## Port notes (XIOM 0.61.3, stdlib `E:\xiom-lang\stdlib`)

Ported to the current compiler/stdlib. The conformance suite passes 22/22 with
program exit 0 (`& .\scripts\port.ps1 -Package xiom.kafka`). The package is not
published. librdkafka FFI remains unimplemented: producer/consumer handles stay
`-1`, `kafka_poll` always returns `Ok(None)`, and admin operations return a
typed `KafkaError` with `code: -999`.

### Behavior / contract changes during the port

- **Dropped `requires:` preconditions for empty inputs.** `kafka_produce`
  (topic, value) and `kafka_subscribe` (topics) previously declared
  `requires: <x>.len() > 0`. On 0.61.3 `requires:` clauses are enforced at
  runtime and abort before the body runs, which contradicts the documented and
  tested behavior of returning a typed, non-retryable `KafkaError` for empty
  inputs. The clauses were removed and the in-body validation kept; all other
  contracts (non-empty brokers, `timeout_ms >= 0`, `partitions > 0`,
  `replication >= 0`) are unchanged. The conformance suite continues to cover
  both the accepting and rejecting paths.
- **Suite reporting.** `tests/test_conformance.xi` now prints `[PASS]`/`[FAIL]`
  per test so the port harness can count results; the assertions and their
  expected values are unchanged.

### Known limitations and compiler issues (0.61.3)

- Direct `return Ok(None);` in a function returning
  `Result[Option[T], StructErr]` mis-lowers to an out-of-range `getelementptr`
  (clang: "invalid getelementptr indices"). Workaround used: bind the payload
  first (`let none: Option[KafkaMessage] = None; return Ok(none);`).
- `mut` bindings in match patterns (`Ok(mut c) =>`) are rejected by the parser.
  Workaround used: bind immutably and move into a `var` local inside the arm.
- librdkafka FFI is still unavailable, so the package is conformant but not
  functional against a real broker.
