module xiom.kafka.admin

use xiom.kafka.types;

fn kafka_create_topic(brokers: Str, topic: Str, partitions: Int, replication: Int) -> Result[Int, KafkaError]
  requires: brokers.len() > 0
  requires: topic.len() > 0
  requires: partitions > 0
  requires: replication >= 0
{
  return Err(KafkaError {
    code: -999,
    message: "kafka_create_topic: librdkafka FFI not available in pure XIOM",
    is_retryable: false,
  });
}

fn kafka_delete_topic(brokers: Str, topic: Str) -> Result[Int, KafkaError]
  requires: brokers.len() > 0
  requires: topic.len() > 0
{
  return Err(KafkaError {
    code: -999,
    message: "kafka_delete_topic: librdkafka FFI not available in pure XIOM",
    is_retryable: false,
  });
}

fn kafka_list_topics(brokers: Str) -> Result[Vec[Str], KafkaError]
  requires: brokers.len() > 0
{
  return Err(KafkaError {
    code: -999,
    message: "kafka_list_topics: librdkafka FFI not available in pure XIOM",
    is_retryable: false,
  });
}
