# xiom-kafka

Apache Kafka client for XIOM — typed librdkafka bindings.

## Installation

```xiom
deps: { "xiom-kafka": "0.1.0" };
```

### Native Dependency

Full functionality requires `librdkafka` installed on the system:

```bash
# macOS
brew install librdkafka

# Ubuntu/Debian
sudo apt install librdkafka-dev

# Windows
vcpkg install librdkafka
```

## Usage

### Producer

```xiom
let config = kafka_config_new("localhost:9092");
let producer = kafka_producer_new(&config)?;

let key = vec![];
let value = vec![72, 101, 108, 108, 111];  # "Hello"

let result = kafka_produce(&producer, "my-topic", &key, &value)?;
kafka_producer_flush(&producer, 5000)?;
kafka_producer_close(producer);
```

### Consumer

```xiom
let config = kafka_config_new("localhost:9092");
let topics = vec!["my-topic"];
let mut consumer = kafka_consumer_new(&config, &topics)?;

kafka_subscribe(&mut consumer, &topics)?;

# Poll loop (recursive, no for loops)
poll_loop(&consumer, 100);
kafka_commit(&consumer)?;
kafka_consumer_close(consumer);
```

### Admin Operations

```xiom
let result = kafka_create_topic("localhost:9092", "new-topic", 3, 1);
Match result {
  Ok(()) => "Topic created",
  Err(e) => "Error: " + e.message,
}
```

## Modules

| Module | Description |
|---|---|
| `xiom.kafka.types` | Config, message, producer, consumer, error types |
| `xiom.kafka.producer` | Message production with input validation |
| `xiom.kafka.consumer` | Subscription, poll, commit lifecycle |
| `xiom.kafka.admin` | Topic create, delete, list (stubs) |

## Current Status

This package provides a **complete type system and API surface** for Kafka operations. All producer and consumer functions compile and validate inputs in pure XIOM but require the librdkafka native backend for actual message transport. Admin operations return descriptive error stubs.

| Component | Status |
|---|---|
| Types and config | Fully implemented |
| Input validation | Fully implemented |
| Producer (FFI) | Stub — requires librdkafka |
| Consumer (FFI) | Stub — requires librdkafka |
| Admin (FFI) | Stub — requires librdkafka |

## License

MIT
