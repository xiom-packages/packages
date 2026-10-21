// XIOM -- xiom.kafka: producer API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.kafka.producer

use xiom.kafka;
use xiom.kafka.types;

/// Create a real librdkafka producer.  The config is applied to a real
/// rd_kafka_conf_t (including every stored property) and a delivery-report
/// callback is installed.
/// Complexity: O(config properties).
pub fn kafka_producer_new(config: &KafkaConfig) -> Result[KafkaProducer, KafkaError]
  requires: config.brokers.len() > 0
{
  match kafka_conf_build(config) {
    Ok(conf) => {
      match kafka_bridge_producer_new(conf) {
        Ok(handle) => {
          return Ok(KafkaProducer { handle: handle; config: kafka_config_clone(config) });
        }
        Err(e) => { return Err(e); }
      }
    }
    Err(e) => { return Err(e); }
  }
}

/// Produce one record with librdkafka's automatic partitioning.  Returns the
/// correlation id carried by the delivery report.
/// Complexity: O(key + value).
pub fn kafka_produce(producer: &KafkaProducer, topic: Str, key: &Vec[Int], value: &Vec[Int]) -> Result[Int, KafkaError]
  requires: producer.handle != 0
{
  if topic.len() == 0 {
    return Err(KafkaError { code: -186; message: "topic must not be empty"; is_retryable: false });
  }
  if value.len() == 0 {
    return Err(KafkaError { code: -186; message: "value must not be empty"; is_retryable: false });
  }
  return kafka_bridge_produce(producer.handle, topic, -1, key, value);
}

/// Produce one record to an explicit partition (topic-partition addressing).
/// Complexity: O(key + value).
pub fn kafka_produce_partition(producer: &KafkaProducer, topic: Str, partition: Int, key: &Vec[Int], value: &Vec[Int]) -> Result[Int, KafkaError]
  requires: producer.handle != 0
  requires: partition >= 0
{
  if topic.len() == 0 {
    return Err(KafkaError { code: -186; message: "topic must not be empty"; is_retryable: false });
  }
  if value.len() == 0 {
    return Err(KafkaError { code: -186; message: "value must not be empty"; is_retryable: false });
  }
  return kafka_bridge_produce(producer.handle, topic, partition, key, value);
}

/// Serve the delivery callback and return one report, or None when no report
/// arrived within timeout_ms.
/// Complexity: O(1) plus poll wait.
pub fn kafka_producer_poll_delivery(producer: &KafkaProducer, timeout_ms: Int) -> KafkaDeliveryPoll
  requires: producer.handle != 0
  requires: timeout_ms >= 0
{
  return kafka_bridge_poll_delivery(producer.handle, timeout_ms);
}

/// Serve producer callbacks without consuming a delivery report.
/// Complexity: O(1) plus poll wait.
pub fn kafka_producer_poll(producer: &KafkaProducer, timeout_ms: Int) -> Result[Int, KafkaError]
  requires: producer.handle != 0
  requires: timeout_ms >= 0
{
  return kafka_bridge_producer_poll(producer.handle, timeout_ms);
}

/// Flush all outstanding messages; returns the remaining out-queue length.
/// Complexity: O(outstanding messages).
pub fn kafka_producer_flush(producer: &KafkaProducer, timeout_ms: Int) -> Result[Int, KafkaError]
  requires: producer.handle != 0
  requires: timeout_ms >= 0
{
  return kafka_bridge_flush(producer.handle, timeout_ms);
}

pub fn kafka_producer_outq_len(producer: &KafkaProducer) -> Int
  requires: producer.handle != 0
{
  return kafka_bridge_outq_len(producer.handle);
}

/// Destroy the producer (librdkafka flushes/terminates it).  The handle is
/// consumed; do not use the value afterwards.
pub fn kafka_producer_close(producer: KafkaProducer)
  requires: producer.handle != 0
{
  kafka_bridge_producer_destroy(producer.handle);
}

// -- transactions ---------------------------------------------------------

pub fn kafka_init_transactions(producer: &KafkaProducer, timeout_ms: Int) -> Result[Int, KafkaError]
  requires: producer.handle != 0
  requires: timeout_ms >= 0
{
  return kafka_bridge_init_transactions(producer.handle, timeout_ms);
}

pub fn kafka_begin_transaction(producer: &KafkaProducer) -> Result[Int, KafkaError]
  requires: producer.handle != 0
{
  return kafka_bridge_begin_transaction(producer.handle);
}

pub fn kafka_commit_transaction(producer: &KafkaProducer, timeout_ms: Int) -> Result[Int, KafkaError]
  requires: producer.handle != 0
  requires: timeout_ms >= 0
{
  return kafka_bridge_commit_transaction(producer.handle, timeout_ms);
}

pub fn kafka_abort_transaction(producer: &KafkaProducer, timeout_ms: Int) -> Result[Int, KafkaError]
  requires: producer.handle != 0
  requires: timeout_ms >= 0
{
  return kafka_bridge_abort_transaction(producer.handle, timeout_ms);
}

