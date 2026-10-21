// XIOM -- xiom.kafka: metadata API.
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.kafka.metadata

use xiom.kafka;
use xiom.kafka.types;

/// Full cluster metadata through an existing producer client.
/// Complexity: O(metadata).
pub fn kafka_metadata(producer: &KafkaProducer, timeout_ms: Int) -> Result[KafkaMetadata, KafkaError]
  requires: producer.handle != 0
  requires: timeout_ms >= 0
{
  return kafka_bridge_metadata_producer(producer.handle, timeout_ms);
}

/// Cluster id reported in broker metadata (empty when the cluster does not
/// report one).
/// Complexity: O(1) plus metadata wait.
pub fn kafka_cluster_id(producer: &KafkaProducer, timeout_ms: Int) -> Result[Str, KafkaError]
  requires: producer.handle != 0
  requires: timeout_ms >= 0
{
  return kafka_bridge_producer_cluster_id(producer.handle, timeout_ms);
}

/// Full cluster metadata through a short-lived client built from config.
/// Complexity: O(metadata).
pub fn kafka_metadata_with_config(config: &KafkaConfig, timeout_ms: Int) -> Result[KafkaMetadata, KafkaError]
  requires: config.brokers.len() > 0
  requires: timeout_ms >= 0
{
  match kafka_conf_build(config) {
    Ok(conf) => {
      return kafka_bridge_metadata_conf(conf, timeout_ms);
    }
    Err(e) => { return Err(e); }
  }
}
