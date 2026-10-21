// XIOM -- xiom.kafka: consumer API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.kafka.consumer

use xiom.kafka;
use xiom.kafka.types;

fn topic_list_copy(src: &Vec[Str]) -> Vec[Str] {
  var out = Vec[Str].new();
  var i = 0;
  while i < src.len() {
    out.push(src[i]);
    i = i + 1;
  }
  return out;
}

/// Create a real high-level consumer.  `topics` is remembered for the
/// subscription bookkeeping; call `kafka_subscribe` to subscribe.
/// Complexity: O(config properties + topics).
pub fn kafka_consumer_new(config: &KafkaConfig, topics: &Vec[Str]) -> Result[KafkaConsumer, KafkaError]
  requires: config.brokers.len() > 0
{
  match kafka_conf_build(config) {
    Ok(conf) => {
      match kafka_bridge_consumer_new(conf) {
        Ok(handle) => {
          return Ok(KafkaConsumer {
            handle: handle;
            config: kafka_config_clone(config);
            topics: topic_list_copy(topics);
          });
        }
        Err(e) => { return Err(e); }
      }
    }
    Err(e) => { return Err(e); }
  }
}

pub fn kafka_consumer_name(consumer: &KafkaConsumer) -> Str
  requires: consumer.handle != 0
{
  return kafka_bridge_consumer_name(consumer.handle);
}

/// Subscribe to topics with librdkafka group coordination.
/// Complexity: O(topics).
pub fn kafka_subscribe(consumer: &mut KafkaConsumer, topics: &Vec[Str]) -> Result[Int, KafkaError]
  requires: consumer.handle != 0
{
  if topics.len() == 0 {
    return Err(KafkaError { code: -186; message: "topics must not be empty"; is_retryable: false });
  }
  var i = 0;
  while i < topics.len() {
    if topics[i].len() == 0 {
      return Err(KafkaError { code: -186; message: "topic must not be empty"; is_retryable: false });
    }
    i = i + 1;
  }
  match kafka_bridge_subscribe(consumer.handle, topics) {
    Ok(rc) => {
      consumer.topics = topic_list_copy(topics);
      return Ok(rc);
    }
    Err(e) => { return Err(e); }
  }
}

/// Replace the assignment with explicit topic-partitions starting at the
/// beginning of each partition.
/// Complexity: O(partitions).
pub fn kafka_assign(consumer: &mut KafkaConsumer, topic: Str, partitions: &Vec[Int]) -> Result[Int, KafkaError]
  requires: consumer.handle != 0
{
  if topic.len() == 0 {
    return Err(KafkaError { code: -186; message: "topic must not be empty"; is_retryable: false });
  }
  if partitions.len() == 0 {
    return Err(KafkaError { code: -186; message: "partitions must not be empty"; is_retryable: false });
  }
  var i = 0;
  while i < partitions.len() {
    if partitions[i] < 0 {
      return Err(KafkaError { code: -186; message: "partition must be >= 0"; is_retryable: false });
    }
    i = i + 1;
  }
  match kafka_bridge_assign(consumer.handle, topic, partitions) {
    Ok(rc) => {
      var assigned = Vec[Str].new();
      assigned.push(topic);
      consumer.topics = assigned;
      return Ok(rc);
    }
    Err(e) => { return Err(e); }
  }
}

pub fn kafka_unsubscribe(consumer: &mut KafkaConsumer) -> Result[Int, KafkaError]
  requires: consumer.handle != 0
{
  match kafka_bridge_unsubscribe(consumer.handle) {
    Ok(rc) => {
      consumer.topics = Vec[Str].new();
      return Ok(rc);
    }
    Err(e) => { return Err(e); }
  }
}

/// Poll one message.  A timeout returns Ok(None); a message-level error
/// returns a typed KafkaError (retryability mapped from the library code).
/// Complexity: O(message bytes).
pub fn kafka_poll(consumer: &KafkaConsumer, timeout_ms: Int) -> KafkaMessagePoll
  requires: consumer.handle != 0
  requires: timeout_ms >= 0
{
  return kafka_bridge_poll_message(consumer.handle, timeout_ms);
}

/// Synchronously commit the current assignment's consumed offsets.
/// Complexity: O(partitions).
pub fn kafka_commit(consumer: &KafkaConsumer) -> Result[Int, KafkaError]
  requires: consumer.handle != 0
{
  return kafka_bridge_commit(consumer.handle);
}

/// Close and destroy the consumer (commits per the configured policy).
/// The handle is consumed; do not use the value afterwards.
pub fn kafka_consumer_close(consumer: KafkaConsumer) -> Result[Int, KafkaError]
  requires: consumer.handle != 0
{
  return kafka_bridge_consumer_close(consumer.handle);
}

