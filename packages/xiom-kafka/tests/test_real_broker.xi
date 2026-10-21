// Scratch real-broker verification for xiom.kafka 0.2.0 (not the conformance
// suite; run manually against a local Kafka broker).
module kafka_real_broker

use xiom.io;
use xiom.string;
use xiom.kafka;
use xiom.kafka.types;
use xiom.kafka.producer;
use xiom.kafka.consumer;
use xiom.kafka.metadata;
use xiom.kafka.admin;

fn report(ok: Bool, name: Str) -> Int {
  if ok { io.println("  [PASS] " + name); return 0; }
  io.println("  [FAIL] " + name);
  return 1;
}

fn s2b(s: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.len() { out.push(string.byte_at(s, i) as Int); i = i + 1; }
  return out;
}

fn bytes_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() { return false; }
  var i = 0;
  while i < a.len() { if a[i] != b[i] { return false; } i = i + 1; }
  return true;
}

fn topic_in(names: &Vec[Str], target: Str) -> Bool {
  var i = 0;
  while i < names.len() {
    if string.str_compare(names[i], target) == 0 { return true; }
    i = i + 1;
  }
  return false;
}

fn main() -> Int {
  var fails = 0;
  match kafka_load() {
    Ok(_) => {
      let brokers = "127.0.0.1:9092";
      let topic = "xiom-kafka-real-verify";
      var cfg = kafka_config_new(brokers);
      cfg.client_id = "xiom-kafka-real-admin";

      match kafka_create_topic_with(&cfg, topic, 2, 1) {
        Ok(_) => { fails = fails + report(true, "real: CreateTopics success"); }
        Err(e) => { fails = fails + report(false, "real: CreateTopics success (" + e.message + ")"); }
      }
      match kafka_list_topics_with(&cfg) {
        Ok(names) => { fails = fails + report(topic_in(&names, topic), "real: topic listed after create"); }
        Err(_) => { fails = fails + report(false, "real: topic listed after create"); }
      }

      var pcfg = kafka_config_new(brokers);
      pcfg.client_id = "xiom-kafka-real-producer";
      match kafka_producer_new(&pcfg) {
        Ok(producer) => {
          var bad = 0;
          var i = 0;
          while i < 3 {
            match kafka_produce(&producer, topic, &s2b("rk"), &s2b("rv")) {
              Ok(_) => { }
              Err(_) => { bad = bad + 1; }
            }
            i = i + 1;
          }
          fails = fails + report(bad == 0, "real: produce 3 records");
          match kafka_producer_flush(&producer, 15000) {
            Ok(r) => { fails = fails + report(r == 0, "real: flush"); }
            Err(_) => { fails = fails + report(false, "real: flush"); }
          }
          var reports = 0;
          var j = 0;
          while j < 50 && reports < 3 {
            let poll = kafka_producer_poll_delivery(&producer, 200);
            if poll.status == 1 && poll.report.err == 0 { reports = reports + 1; }
            j = j + 1;
          }
          fails = fails + report(reports == 3, "real: 3 delivery reports");

          var ccfg = kafka_config_new(brokers);
          ccfg.client_id = "xiom-kafka-real-consumer";
          ccfg.group_id = "xiom-kafka-real-group";
          match kafka_config_set(&mut ccfg, "auto.offset.reset", "earliest") {
            Ok(_) => { }
            Err(_) => { fails = fails + report(false, "real: consumer config"); }
          }
          var topics = Vec[Str].new();
          topics.push(topic);
          match kafka_consumer_new(&ccfg, &topics) {
            Ok(c) => {
              var c_mut = c;
              match kafka_subscribe(&mut c_mut, &topics) {
                Ok(_) => {
                  var got = 0;
                  var k = 0;
                  while k < 120 && got < 3 {
                    let poll = kafka_poll(&c_mut, 250);
                    if poll.status == 1 && bytes_eq(&poll.message.value, &s2b("rv")) { got = got + 1; }
                    k = k + 1;
                  }
                  fails = fails + report(got >= 3, "real: consumer read 3 records");
                  match kafka_commit(&c_mut) {
                    Ok(_) => { fails = fails + report(true, "real: commit"); }
                    Err(_) => { fails = fails + report(false, "real: commit"); }
                  }
                }
                Err(_) => { fails = fails + report(false, "real: subscribe"); }
              }
              match kafka_consumer_close(c_mut) {
                Ok(_) => { fails = fails + report(true, "real: consumer close"); }
                Err(_) => { fails = fails + report(false, "real: consumer close"); }
              }
            }
            Err(_) => { fails = fails + report(false, "real: consumer new"); }
          }
          kafka_producer_close(producer);
        }
        Err(_) => { fails = fails + report(false, "real: producer new"); }
      }

      match kafka_delete_topic_with(&cfg, topic) {
        Ok(_) => { fails = fails + report(true, "real: DeleteTopics success"); }
        Err(e) => { fails = fails + report(false, "real: DeleteTopics success (" + e.message + ")"); }
      }
      match kafka_list_topics_with(&cfg) {
        Ok(names) => { fails = fails + report(!topic_in(&names, topic), "real: topic gone after delete"); }
        Err(_) => { fails = fails + report(false, "real: topic gone after delete"); }
      }
    }
    Err(e) => { fails = fails + report(false, "real: load (" + e.message + ")"); }
  }
  return fails;
}
