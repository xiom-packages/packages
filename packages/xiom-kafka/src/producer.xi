module xiom.kafka.producer

use xiom.kafka.types;

fn kafka_producer_new(config: &KafkaConfig) -> Result[KafkaProducer, KafkaError]
  requires: config.brokers.len() > 0
{
  var producer = KafkaProducer {
    handle: -1,
    config: KafkaConfig {
      brokers: config.brokers,
      client_id: config.client_id,
      group_id: config.group_id,
    },
  };
  return Ok(producer);
}

fn kafka_produce(producer: &KafkaProducer, topic: Str, key: &Vec[Int], value: &Vec[Int]) -> Result[Int, KafkaError]
  requires: topic.len() > 0
  requires: value.len() > 0
{
  if topic == "" {
    return Err(KafkaError { code: -1, message: "topic must not be empty", is_retryable: false });
  };
  if value.len() == 0 {
    return Err(KafkaError { code: -1, message: "value must not be empty", is_retryable: false });
  };
  return Ok(0);
}

fn kafka_producer_flush(producer: &KafkaProducer, timeout_ms: Int) -> Result[Int, KafkaError]
  requires: timeout_ms >= 0
{
  return Ok(0);
}

fn kafka_producer_close(producer: KafkaProducer) {
}
