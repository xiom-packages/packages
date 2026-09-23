module xiom.kafka.consumer

use xiom.kafka.types;

fn kafka_consumer_new(config: &KafkaConfig, topics: &Vec[Str]) -> Result[KafkaConsumer, KafkaError]
  requires: config.brokers.len() > 0
{
  var consumer = KafkaConsumer {
    handle: -1,
    config: KafkaConfig {
      brokers: config.brokers,
      client_id: config.client_id,
      group_id: config.group_id,
    },
    topics: Vec[Str].new(),
  };
  return Ok(consumer);
}

fn kafka_subscribe(consumer: &mut KafkaConsumer, topics: &Vec[Str]) -> Result[Int, KafkaError]
{
  if topics.len() == 0 {
    return Err(KafkaError { code: -1, message: "topics must not be empty", is_retryable: false });
  };
  consumer.topics = topic_list_copy(topics, 0, Vec[Str].new());
  return Ok(0);
}

fn topic_list_copy(src: &Vec[Str], idx: Int, acc: Vec[Str]) -> Vec[Str] {
  if idx >= src.len() {
    return acc;
  };
  acc.push(src[idx]);
  return topic_list_copy(src, idx + 1, acc);
}

fn kafka_poll(consumer: &KafkaConsumer, timeout_ms: Int) -> Result[Option[KafkaMessage], KafkaError]
  requires: timeout_ms >= 0
{
  let none: Option[KafkaMessage] = None;
  return Ok(none);
}

fn kafka_commit(consumer: &KafkaConsumer) -> Result[Int, KafkaError] {
  return Ok(0);
}

fn kafka_consumer_close(consumer: KafkaConsumer) {
}
