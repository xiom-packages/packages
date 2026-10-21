package xiom_kafka {
  name: "xiom.kafka";
  version: "0.2.0";
  description: "Apache Kafka client (librdkafka v2.16.0) -- runtime-loaded producer, consumer, transactions, metadata and admin bindings with an in-process mock-cluster live suite";
  categories: ["network", "data"];
  keywords: ["kafka", "librdkafka", "streaming", "events", "messaging", "binding"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["XIOM Team"];
  modules: ["xiom.kafka", "xiom.kafka.types", "xiom.kafka.producer", "xiom.kafka.consumer", "xiom.kafka.metadata", "xiom.kafka.admin", "xiom.kafka.mock"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
