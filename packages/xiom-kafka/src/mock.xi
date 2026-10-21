// XIOM -- xiom.kafka: librdkafka mock cluster (public test API).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// The mock cluster lets the conformance suite exercise real producer,
// consumer, metadata, transaction and admin request paths in-process with
// no external broker.  It is a public librdkafka API (src/rdkafka_mock.h at
// the pinned commit), not a test-only backdoor: the returned bootstrap list
// is a normal localhost listener usable by real clients.

module xiom.kafka.mock

use xiom.kafka;
use xiom.kafka.types;

/// Whether the loaded librdkafka build exports the mock-cluster API.
pub fn kafka_mock_is_available() -> Bool {
  return kafka_mock_available();
}

/// Start an in-process mock cluster and return its bootstrap list.
/// Complexity: O(brokers).
pub fn kafka_mock_cluster_new(brokers: Int) -> Result[KafkaMockCluster, KafkaError]
  requires: brokers > 0
{
  return kafka_bridge_mock_cluster_new(brokers);
}

/// Create a topic directly in the mock cluster (the mock does not serve the
/// wire CreateTopics API).
/// Complexity: O(1).
pub fn kafka_mock_topic_create(cluster: &KafkaMockCluster, topic: Str, partitions: Int, replication: Int) -> Result[Int, KafkaError]
  requires: cluster.handle != 0
  requires: topic.len() > 0
  requires: partitions > 0
  requires: replication >= 0
{
  return kafka_bridge_mock_topic_create(cluster, topic, partitions, replication);
}

/// Set the controller broker id reported in mock metadata.  Needed before
/// admin requests so they resolve a controller deterministically.
/// Complexity: O(1).
pub fn kafka_mock_set_controller(cluster: &KafkaMockCluster, controller_id: Int) -> Result[Int, KafkaError]
  requires: cluster.handle != 0
{
  return kafka_bridge_mock_set_controller(cluster, controller_id);
}

/// Destroy the mock cluster and its owner client.
pub fn kafka_mock_cluster_destroy(cluster: KafkaMockCluster)
  requires: cluster.handle != 0
{
  kafka_bridge_mock_cluster_destroy(cluster);
}
