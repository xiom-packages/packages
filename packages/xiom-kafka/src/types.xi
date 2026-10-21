// XIOM -- xiom.kafka: public types.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.kafka.types

/// Client configuration.  `prop_names`/`prop_values` carry the generic
/// librdkafka property surface added with `kafka.kafka_config_set`; the
/// three named fields are the common path applied first (properties apply
/// afterwards and therefore override them).
pub type KafkaConfig = {
  brokers: Str;
  client_id: Str;
  group_id: Str;
  prop_names: Vec[Str];
  prop_values: Vec[Str];
}

pub type KafkaMessage = {
  topic: Str;
  partition: Int;
  offset: Int;
  key: Vec[Int];
  value: Vec[Int];
  timestamp: Int;
  timestamp_type: Int;
}

pub type KafkaDeliveryReport = {
  id: Int;
  topic: Str;
  partition: Int;
  offset: Int;
  err: Int;
  err_message: Str;
  timestamp: Int;
}

/// Flat poll outcome (no Result[Option[T]] shape): status 0 = nothing
/// arrived, 1 = message, 2 = message-level error.
pub type KafkaMessagePoll = {
  status: Int;
  message: KafkaMessage;
  error: KafkaError;
}

/// Flat delivery-report poll outcome: status 0 = none, 1 = report,
/// 2 = error.
pub type KafkaDeliveryPoll = {
  status: Int;
  report: KafkaDeliveryReport;
  error: KafkaError;
}

pub type KafkaProducer = {
  handle: Int;
  config: KafkaConfig;
}

pub type KafkaConsumer = {
  handle: Int;
  config: KafkaConfig;
  topics: Vec[Str];
}

pub type KafkaError = {
  code: Int;
  message: Str;
  is_retryable: Bool;
}

pub type KafkaBroker = {
  id: Int;
  host: Str;
  port: Int;
}

pub type KafkaPartitionMetadata = {
  id: Int;
  err: Int;
  leader: Int;
  replicas: Vec[Int];
  isrs: Vec[Int];
}

pub type KafkaTopicMetadata = {
  name: Str;
  err: Int;
  partitions: Vec[KafkaPartitionMetadata];
}

pub type KafkaMetadata = {
  brokers: Vec[KafkaBroker];
  topics: Vec[KafkaTopicMetadata];
}

pub type KafkaLoadError = {
  kind: Int;
  message: Str;
}

pub type KafkaMockCluster = {
  handle: Int;
  brokers: Str;
}
