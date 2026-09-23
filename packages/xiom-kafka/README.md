# xiom.kafka

> **Status:** Ported -- conformance suite green on the pinned toolchain
> (XIOM 0.61.3, stdlib `E:\xiom-lang\stdlib`), 22/22 tests, program exit 0.
> Not published. librdkafka FFI is not linked yet: producer/consumer/admin are
> pure-XIOM stubs.
> **Scope:** Apache Kafka client bindings (librdkafka).
> **Deps:** stdlib; FFI to librdkafka planned (see ROADMAP.md).

Run the conformance suite from the repo root:

```
& .\scripts\port.ps1 -Package xiom.kafka
```

## Libs inventory

| Lib | Description | State |
|-----|-------------|-------|
| `types` | KafkaConfig, KafkaMessage, KafkaProducer, KafkaConsumer, KafkaError | implemented |
| `producer` | Message production (validation, flush, close) | stub (no librdkafka) |
| `consumer` | Message consumption (subscribe, poll, commit, close) | stub (no librdkafka) |
| `admin` | Admin operations (create/delete/list topics) | stub (typed `Err(-999)`) |

## Known limitations

See "Port notes (XIOM 0.61.3)" and "Known limitations" in SPEC.md for the port
changes (contract/precondition adjustments) and the compiler issues found.
