module xiom.kafka.consumer

fn kafka_consumer_new(config: &KafkaConfig, topics: &Vec[Str]) -> Result[KafkaConsumer, KafkaError] {
  let consumer = KafkaConsumer {
    handle: -1,
    config: KafkaConfig {
      brokers: config.brokers,
      client_id: config.client_id,
      group_id: config.group_id,
    },
    topics: Vec[Str].new(),
  };
  Ok(consumer)
}

fn kafka_subscribe(consumer: &mut KafkaConsumer, topics: &Vec[Str]) -> Result[(), KafkaError] {
  if topics.len() == 0 {
    return Err(KafkaError { code: -1, message: "topics must not be empty", is_retryable: false });
  };
  consumer.topics = topic_list_copy(topics, 0, Vec[Str].new());
  Ok(())
}

fn topic_list_copy(src: &Vec[Str], idx: Int, acc: Vec[Str]) -> Vec[Str] {
  if idx >= src.len() {
    acc
  } else {
    acc.push(src[idx]);
    topic_list_copy(src, idx + 1, acc)
  }
}

fn kafka_poll(consumer: &KafkaConsumer, timeout_ms: Int) -> Result[Option[KafkaMessage], KafkaError] {
  let _ = consumer;
  let _ = timeout_ms;
  Ok(None)
}

fn kafka_commit(consumer: &KafkaConsumer) -> Result[(), KafkaError] {
  let _ = consumer;
  Ok(())
}

fn kafka_consumer_close(consumer: KafkaConsumer) {
  let _ = consumer;
}
