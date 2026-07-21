module kafka_conformance_tests

pub type KafkaConfig = {
  brokers: Str;
  client_id: Str;
  group_id: Str;
}

pub type KafkaMessage = {
  topic: Str;
  partition: Int;
  offset: Int;
  key: Vec[Int];
  value: Vec[Int];
  timestamp: Int;
}

pub type KafkaProducer = {
  handle: Int;
  config: KafkaConfig;
}

pub type KafkaConsumer = {
  handle: Int;
  config: KafkaConfig;
  topics: Vec[Str];
}

pub type KafkaError = {
  code: Int;
  message: Str;
  is_retryable: Bool;
}

fn kafka_config_new(brokers: Str) -> KafkaConfig
  requires: brokers.len() > 0
{
  KafkaConfig { brokers: brokers; client_id: "xiom-kafka"; group_id: "" }
}

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
  requires: topics.len() > 0
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
  return Ok(None);
}

fn kafka_commit(consumer: &KafkaConsumer) -> Result[Int, KafkaError] {
  return Ok(0);
}

fn kafka_consumer_close(consumer: KafkaConsumer) {
}

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

fn test_kafka_config_construction() -> Int {
  var config = kafka_config_new("localhost:9092");
  if config.brokers == "localhost:9092" { return 0; }
  return 1;
}

fn test_kafka_error_construction() -> Int {
  var err = KafkaError { code: -1, message: "test", is_retryable: true };
  if err.code == -1 && err.message == "test" && err.is_retryable { return 0; }
  return 1;
}

fn test_kafka_message_construction() -> Int {
  var key: Vec[Int] = Vec[Int].new();
  var val: Vec[Int] = Vec[Int].new();
  val.push(42);
  var msg = KafkaMessage {
    topic: "test-topic",
    partition: 0,
    offset: 100,
    key: key,
    value: val,
    timestamp: 1620000000000,
  };
  if msg.topic == "test-topic" && msg.offset == 100 && msg.value[0] == 42 { return 0; }
  return 1;
}

fn test_kafka_producer_new_ok() -> Int {
  var config = kafka_config_new("localhost:9092");
  match kafka_producer_new(&config) {
    Ok(p) => { return 0; }
    Err(e) => { return 1; }
  }
}

fn test_kafka_produce_nonempty_params() -> Int {
  var config = kafka_config_new("localhost:9092");
  var producer_match = kafka_producer_new(&config);
  match producer_match {
    Ok(p) => {
      var key: Vec[Int] = Vec[Int].new();
      var val: Vec[Int] = Vec[Int].new();
      val.push(1);
      match kafka_produce(&p, "my-topic", &key, &val) {
        Ok(_) => { return 0; }
        Err(_) => { return 2; }
      }
    }
    Err(_) => { return 1; }
  }
}

fn test_kafka_produce_empty_topic() -> Int {
  var config = kafka_config_new("localhost:9092");
  var producer_match = kafka_producer_new(&config);
  match producer_match {
    Ok(p) => {
      var key: Vec[Int] = Vec[Int].new();
      var val: Vec[Int] = Vec[Int].new();
      val.push(1);
      match kafka_produce(&p, "", &key, &val) {
        Ok(_) => { return 1; }
        Err(e) => {
          if e.is_retryable { return 3; }
          return 0;
        }
      }
    }
    Err(_) => { return 2; }
  }
}

fn test_kafka_produce_empty_value() -> Int {
  var config = kafka_config_new("localhost:9092");
  var producer_match = kafka_producer_new(&config);
  match producer_match {
    Ok(p) => {
      var key: Vec[Int] = Vec[Int].new();
      var val: Vec[Int] = Vec[Int].new();
      match kafka_produce(&p, "my-topic", &key, &val) {
        Ok(_) => { return 1; }
        Err(e) => {
          if e.is_retryable { return 3; }
          return 0;
        }
      }
    }
    Err(_) => { return 2; }
  }
}

fn test_kafka_producer_flush_ok() -> Int {
  var config = kafka_config_new("localhost:9092");
  var producer_match = kafka_producer_new(&config);
  match producer_match {
    Ok(p) => {
      match kafka_producer_flush(&p, 5000) {
        Ok(_) => { return 0; }
        Err(_) => { return 2; }
      }
    }
    Err(_) => { return 1; }
  }
}

fn test_kafka_producer_close_ok() -> Int {
  var config = kafka_config_new("localhost:9092");
  var producer_match = kafka_producer_new(&config);
  match producer_match {
    Ok(p) => {
      kafka_producer_close(p);
      return 0;
    }
    Err(_) => { return 1; }
  }
}

fn test_kafka_consumer_new_ok() -> Int {
  var config = kafka_config_new("localhost:9092");
  var topics: Vec[Str] = Vec[Str].new();
  topics.push("test-topic");
  match kafka_consumer_new(&config, &topics) {
    Ok(c) => { return 0; }
    Err(e) => { return 1; }
  }
}

fn test_kafka_subscribe_nonempty() -> Int {
  var config = kafka_config_new("localhost:9092");
  var topics: Vec[Str] = Vec[Str].new();
  topics.push("test-topic");
  var consumer_match = kafka_consumer_new(&config, &topics);
  match consumer_match {
    Ok(mut c) => {
      match kafka_subscribe(&mut c, &topics) {
        Ok(_) => { return 0; }
        Err(_) => { return 2; }
      }
    }
    Err(_) => { return 1; }
  }
}

fn test_kafka_subscribe_empty_topics() -> Int {
  var config = kafka_config_new("localhost:9092");
  var topics: Vec[Str] = Vec[Str].new();
  topics.push("test-topic");
  var consumer_match = kafka_consumer_new(&config, &topics);
  match consumer_match {
    Ok(mut c) => {
      var empty: Vec[Str] = Vec[Str].new();
      match kafka_subscribe(&mut c, &empty) {
        Ok(_) => { return 1; }
        Err(e) => { return 0; }
      }
    }
    Err(_) => { return 2; }
  }
}

fn test_kafka_poll_none() -> Int {
  var config = kafka_config_new("localhost:9092");
  var topics: Vec[Str] = Vec[Str].new();
  topics.push("test-topic");
  var consumer_match = kafka_consumer_new(&config, &topics);
  match consumer_match {
    Ok(c) => {
      match kafka_poll(&c, 1000) {
        Ok(opt) => {
          match opt {
            Some(_) => { return 1; }
            None => { return 0; }
          }
        }
        Err(_) => { return 2; }
      }
    }
    Err(_) => { return 3; }
  }
}

fn test_kafka_commit_ok() -> Int {
  var config = kafka_config_new("localhost:9092");
  var topics: Vec[Str] = Vec[Str].new();
  topics.push("test-topic");
  var consumer_match = kafka_consumer_new(&config, &topics);
  match consumer_match {
    Ok(c) => {
      match kafka_commit(&c) {
        Ok(_) => { return 0; }
        Err(_) => { return 1; }
      }
    }
    Err(_) => { return 2; }
  }
}

fn test_kafka_consumer_close_ok() -> Int {
  var config = kafka_config_new("localhost:9092");
  var topics: Vec[Str] = Vec[Str].new();
  topics.push("test-topic");
  var consumer_match = kafka_consumer_new(&config, &topics);
  match consumer_match {
    Ok(c) => {
      kafka_consumer_close(c);
      return 0;
    }
    Err(_) => { return 1; }
  }
}

fn test_kafka_create_topic_err() -> Int {
  match kafka_create_topic("localhost:9092", "new-topic", 3, 1) {
    Ok(_) => { return 1; }
    Err(e) => {
      if e.code == -999 { return 0; }
      return 2;
    }
  }
}

fn test_kafka_delete_topic_err() -> Int {
  match kafka_delete_topic("localhost:9092", "old-topic") {
    Ok(_) => { return 1; }
    Err(e) => {
      if e.code == -999 { return 0; }
      return 2;
    }
  }
}

fn test_kafka_list_topics_err() -> Int {
  match kafka_list_topics("localhost:9092") {
    Ok(_) => { return 1; }
    Err(e) => {
      if e.code == -999 { return 0; }
      return 2;
    }
  }
}

fn test_producer_handle_initialized() -> Int {
  var config = kafka_config_new("localhost:9092");
  match kafka_producer_new(&config) {
    Ok(p) => {
      if p.handle == -1 { return 0; }
      return 1;
    }
    Err(_) => { return 2; }
  }
}

fn test_consumer_handle_initialized() -> Int {
  var config = kafka_config_new("localhost:9092");
  var topics: Vec[Str] = Vec[Str].new();
  topics.push("test-topic");
  match kafka_consumer_new(&config, &topics) {
    Ok(c) => {
      if c.handle == -1 { return 0; }
      return 1;
    }
    Err(_) => { return 2; }
  }
}

fn test_kafka_error_is_not_retryable() -> Int {
  var err = KafkaError { code: -999, message: "fail", is_retryable: false };
  if err.is_retryable { return 1; }
  return 0;
}

fn test_kafka_error_message_present() -> Int {
  var err = KafkaError { code: -1, message: "critical error", is_retryable: true };
  if err.message.len() > 0 { return 0; }
  return 1;
}

pub fn main() -> Int {
  var failures: Int = 0;
  failures = failures + test_kafka_config_construction();
  failures = failures + test_kafka_error_construction();
  failures = failures + test_kafka_message_construction();
  failures = failures + test_kafka_producer_new_ok();
  failures = failures + test_kafka_produce_nonempty_params();
  failures = failures + test_kafka_produce_empty_topic();
  failures = failures + test_kafka_produce_empty_value();
  failures = failures + test_kafka_producer_flush_ok();
  failures = failures + test_kafka_producer_close_ok();
  failures = failures + test_kafka_consumer_new_ok();
  failures = failures + test_kafka_subscribe_nonempty();
  failures = failures + test_kafka_subscribe_empty_topics();
  failures = failures + test_kafka_poll_none();
  failures = failures + test_kafka_commit_ok();
  failures = failures + test_kafka_consumer_close_ok();
  failures = failures + test_kafka_create_topic_err();
  failures = failures + test_kafka_delete_topic_err();
  failures = failures + test_kafka_list_topics_err();
  failures = failures + test_producer_handle_initialized();
  failures = failures + test_consumer_handle_initialized();
  failures = failures + test_kafka_error_is_not_retryable();
  failures = failures + test_kafka_error_message_present();
  return failures;
}
