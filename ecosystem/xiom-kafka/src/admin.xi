module xiom.kafka.admin

fn kafka_create_topic(brokers: Str, topic: Str, partitions: Int, replication: Int) -> Result[(), KafkaError] {
  let _ = brokers;
  let _ = topic;
  let _ = partitions;
  let _ = replication;
  Err(KafkaError {
    code: -999;
    message: "kafka_create_topic: librdkafka FFI not available in pure XIOM";
    is_retryable: false;
  })
}

fn kafka_delete_topic(brokers: Str, topic: Str) -> Result[(), KafkaError] {
  let _ = brokers;
  let _ = topic;
  Err(KafkaError {
    code: -999;
    message: "kafka_delete_topic: librdkafka FFI not available in pure XIOM";
    is_retryable: false;
  })
}

fn kafka_list_topics(brokers: Str) -> Result[Vec[Str], KafkaError] {
  let _ = brokers;
  Err(KafkaError {
    code: -999;
    message: "kafka_list_topics: librdkafka FFI not available in pure XIOM";
    is_retryable: false;
  })
}
