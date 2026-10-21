// XIOM -- xiom.kafka: admin API (CreateTopics / DeleteTopics / topic list).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.kafka.admin

use xiom.kafka;
use xiom.kafka.types;
use xiom.kafka.metadata;

fn admin_create_with_config(config: &KafkaConfig, topic: Str, partitions: Int, replication: Int) -> Result[Int, KafkaError] {
  match kafka_conf_build(config) {
    Ok(conf) => {
      match kafka_bridge_admin_new(conf) {
        Ok(rk) => {
          let rc = kafka_bridge_create_topic(rk, topic, partitions, replication, KAFKA_ADMIN_TIMEOUT_MS);
          kafka_bridge_admin_destroy(rk);
          return rc;
        }
        Err(e) => { return Err(e); }
      }
    }
    Err(e) => { return Err(e); }
  }
}

fn admin_delete_with_config(config: &KafkaConfig, topic: Str) -> Result[Int, KafkaError] {
  match kafka_conf_build(config) {
    Ok(conf) => {
      match kafka_bridge_admin_new(conf) {
        Ok(rk) => {
          let rc = kafka_bridge_delete_topic(rk, topic, KAFKA_ADMIN_TIMEOUT_MS);
          kafka_bridge_admin_destroy(rk);
          return rc;
        }
        Err(e) => { return Err(e); }
      }
    }
    Err(e) => { return Err(e); }
  }
}

/// Create a topic on the cluster described by `config`.
/// Complexity: O(1) plus broker round-trip.
pub fn kafka_create_topic_with(config: &KafkaConfig, topic: Str, partitions: Int, replication: Int) -> Result[Int, KafkaError]
  requires: config.brokers.len() > 0
  requires: topic.len() > 0
  requires: partitions > 0
  requires: replication >= 0
{
  return admin_create_with_config(config, topic, partitions, replication);
}

/// Delete a topic on the cluster described by `config`.
/// Complexity: O(1) plus broker round-trip.
pub fn kafka_delete_topic_with(config: &KafkaConfig, topic: Str) -> Result[Int, KafkaError]
  requires: config.brokers.len() > 0
  requires: topic.len() > 0
{
  return admin_delete_with_config(config, topic);
}

/// List topic names through a short-lived metadata client.
/// Complexity: O(metadata).
pub fn kafka_list_topics_with(config: &KafkaConfig) -> Result[Vec[Str], KafkaError]
  requires: config.brokers.len() > 0
{
  match metadata.kafka_metadata_with_config(config, KAFKA_ADMIN_TIMEOUT_MS) {
    Ok(md) => {
      var names = Vec[Str].new();
      var i = 0;
      while i < md.topics.len() {
        names.push(md.topics[i].name);
        i = i + 1;
      }
      return Ok(names);
    }
    Err(e) => { return Err(e); }
  }
}

// -- broker-string conveniences (the 0.1.0 entry-point shape) -------------

pub fn kafka_create_topic(brokers: Str, topic: Str, partitions: Int, replication: Int) -> Result[Int, KafkaError]
  requires: brokers.len() > 0
  requires: topic.len() > 0
  requires: partitions > 0
  requires: replication >= 0
{
  let config = kafka_config_new(brokers);
  return admin_create_with_config(&config, topic, partitions, replication);
}

pub fn kafka_delete_topic(brokers: Str, topic: Str) -> Result[Int, KafkaError]
  requires: brokers.len() > 0
  requires: topic.len() > 0
{
  let config = kafka_config_new(brokers);
  return admin_delete_with_config(&config, topic);
}

pub fn kafka_list_topics(brokers: Str) -> Result[Vec[Str], KafkaError]
  requires: brokers.len() > 0
{
  let config = kafka_config_new(brokers);
  return kafka_list_topics_with(&config);
}
