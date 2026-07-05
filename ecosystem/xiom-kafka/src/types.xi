module xiom.kafka.types;

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

fn kafka_config_new(brokers: Str) -> KafkaConfig {
  KafkaConfig { brokers: brokers; client_id: "xiom-kafka"; group_id: "" }
}
