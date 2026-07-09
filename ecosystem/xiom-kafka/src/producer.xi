module xiom.kafka.producer

fn kafka_producer_new(config: &KafkaConfig) -> Result[KafkaProducer, KafkaError] {
  let producer = KafkaProducer {
    handle: -1,
    config: KafkaConfig {
      brokers: config.brokers,
      client_id: config.client_id,
      group_id: config.group_id,
    },
  };
  Ok(producer)
}

fn kafka_produce(producer: &KafkaProducer, topic: Str, key: &Vec[Int], value: &Vec[Int]) -> Result[Unit, KafkaError] {
  let _ = producer;
  let _ = key;
  if topic.len() == 0 {
    return Err(KafkaError { code: -1, message: "topic must not be empty", is_retryable: false });
  };
  if value.len() == 0 {
    return Err(KafkaError { code: -1, message: "value must not be empty", is_retryable: false });
  };
  Ok(Unit{})
}

fn kafka_producer_flush(producer: &KafkaProducer, timeout_ms: Int) -> Result[Unit, KafkaError] {
  let _ = producer;
  let _ = timeout_ms;
  Ok(Unit{})
}

fn kafka_producer_close(producer: KafkaProducer) {
  let _ = producer;
}
