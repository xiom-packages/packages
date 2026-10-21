// xiom.kafka conformance suite -- real librdkafka bindings, live leg on the
// in-process mock cluster (no external broker).
//
// Classification (never FAIL just because the runtime is absent):
//   no librdkafka on PATH -> KAFKA_LOAD_ABSENT -> SKIP lines (green)
//   present but export set broken -> KAFKA_LOAD_ABI -> FAIL
//   present -> live battery: probe/errors, config set/get, mock cluster,
//              producer + delivery callbacks, metadata, subscribe/assign
//              consumer + field decode + commit, admin request paths,
//              transactions (commit + abort).
//
// Build+run through the runner (compiles src/kafka_bridge.c):
//   scripts/port.ps1 -Package xiom.kafka -TimeoutSec 300
// Put a librdkafka build on PATH (or in the package dir) for the live leg.

module kafka_conformance_tests

use xiom.io;
use xiom.string;
use xiom.kafka;
use xiom.kafka.types;
use xiom.kafka.producer;
use xiom.kafka.consumer;
use xiom.kafka.metadata;
use xiom.kafka.admin;
use xiom.kafka.mock;

fn report(ok: Bool, name: Str) -> Int {
  if ok {
    io.println("  [PASS] " + name);
    io.flush_stdout();
    return 0;
  }
  io.println("  [FAIL] " + name);
  io.flush_stdout();
  return 1;
}

fn digit_str(d: Int) -> Str {
  if d == 0 { return "0"; }
  if d == 1 { return "1"; }
  if d == 2 { return "2"; }
  if d == 3 { return "3"; }
  if d == 4 { return "4"; }
  if d == 5 { return "5"; }
  if d == 6 { return "6"; }
  if d == 7 { return "7"; }
  if d == 8 { return "8"; }
  return "9";
}

fn i2s(n: Int) -> Str {
  if n == 0 { return "0"; }
  var value = n;
  var out = "";
  if value < 0 {
    out = "-";
    value = 0 - value;
  }
  var digits = "";
  while value > 0 {
    digits = digit_str(value % 10) + digits;
    value = value / 10;
  }
  return out + digits;
}

fn s2b(s: Str) -> Vec[Int] {
  var out = Vec[Int].new();
  var i = 0;
  while i < s.len() {
    out.push(string.byte_at(s, i) as Int);
    i = i + 1;
  }
  return out;
}

fn bytes_eq(a: &Vec[Int], b: &Vec[Int]) -> Bool {
  if a.len() != b.len() {
    return false;
  }
  var i = 0;
  while i < a.len() {
    if a[i] != b[i] {
      return false;
    }
    i = i + 1;
  }
  return true;
}

fn topic_in(names: &Vec[Str], target: Str) -> Bool {
  var i = 0;
  while i < names.len() {
    if string.str_compare(names[i], target) == 0 {
      return true;
    }
    i = i + 1;
  }
  return false;
}

fn props_present(err: KafkaError) -> Bool {
  return err.code != 0 && err.message.len() > 0;
}

// =========================================================================
// Pure (library-independent) checks
// =========================================================================

fn test_types() -> Int {
  var fails = 0;
  var config = kafka_config_new("localhost:9092");
  fails = fails + report(string.str_compare(config.brokers, "localhost:9092") == 0, "types: config construction");
  fails = fails + report(config.prop_names.len() == 0 && config.prop_values.len() == 0, "types: config starts with no properties");

  var val = Vec[Int].new();
  val.push(42);
  var key = Vec[Int].new();
  key.push(7);
  let message = KafkaMessage {
    topic: "test-topic";
    partition: 1;
    offset: 100;
    key: key;
    value: val;
    timestamp: 1620000000000;
    timestamp_type: 1;
  };
  fails = fails + report(string.str_compare(message.topic, "test-topic") == 0 && message.offset == 100 && message.value[0] == 42, "types: message construction");

  let err = KafkaError { code: -185; message: "Local: Timed out"; is_retryable: true };
  fails = fails + report(err.code == -185 && err.is_retryable && err.message.len() > 0, "types: error construction");
  return fails;
}

// =========================================================================
// Live battery (librdkafka present)
// =========================================================================

fn live_probe() -> Int {
  var fails = 0;
  fails = fails + report(kafka_version().len() > 0, "probe: version string");
  fails = fails + report(kafka_version_int() > 0, "probe: version integer");
  fails = fails + report(kafka_soname().len() > 0, "probe: resolved soname");
  fails = fails + report(kafka_error_string(-185).len() > 0, "errors: err2str(-185)");
  fails = fails + report(kafka_error_name(-185).len() > 0, "errors: err2name(-185)");
  fails = fails + report(kafka_error_is_retryable(-185), "errors: -185 retryable");
  fails = fails + report(!kafka_error_is_retryable(-186), "errors: -186 not retryable");

  var cfg = kafka_config_new("127.0.0.1:1");
  match kafka_config_set(&mut cfg, "test.mock.num.brokers", "1") {
    Ok(_) => {
      fails = fails + report(true, "config: set known property");
      match kafka_config_get(&cfg, "test.mock.num.brokers") {
        Ok(v) => { fails = fails + report(string.str_compare(v, "1") == 0, "config: get stored property"); }
        Err(_) => { fails = fails + report(false, "config: get stored property"); }
      }
    }
    Err(_) => { fails = fails + report(false, "config: set known property"); }
  }
  match kafka_config_get(&cfg, "socket.timeout.ms") {
    Ok(v) => { fails = fails + report(v.len() > 0, "config: get library default"); }
    Err(_) => { fails = fails + report(false, "config: get library default"); }
  }
  match kafka_config_set(&mut cfg, "xiom.not.a.real.property", "x") {
    Ok(_) => { fails = fails + report(false, "config: unknown property -> typed error"); }
    Err(e) => { fails = fails + report(props_present(e) && !e.is_retryable, "config: unknown property -> typed error"); }
  }
  return fails;
}

fn live_producer_and_metadata(brokers: Str) -> Result[KafkaProducer, KafkaError] {
  var pcfg = kafka_config_new(brokers);
  pcfg.client_id = "xiom-kafka-live-producer";
  var fails = 0;
  match kafka_producer_new(&pcfg) {
    Ok(producer) => {
      var i = 0;
      var bad_ids = 0;
      while i < 5 {
        let key = s2b("k" + i2s(i));
        let value = s2b("m" + i2s(i));
        match kafka_produce(&producer, "xiom-kafka-live", &key, &value) {
          Ok(id) => { if id <= 0 { bad_ids = bad_ids + 1; } }
          Err(_) => { bad_ids = bad_ids + 1; }
        }
        i = i + 1;
      }
      match kafka_produce_partition(&producer, "xiom-kafka-live", 0, &s2b("kp0"), &s2b("p0")) {
        Ok(id) => { if id <= 0 { bad_ids = bad_ids + 1; } }
        Err(_) => { bad_ids = bad_ids + 1; }
      }
      match kafka_produce_partition(&producer, "xiom-kafka-live", 1, &s2b("kp1"), &s2b("p1")) {
        Ok(id) => { if id <= 0 { bad_ids = bad_ids + 1; } }
        Err(_) => { bad_ids = bad_ids + 1; }
      }
      fails = fails + report(bad_ids == 0, "producer: 7 produce calls accepted");

      match kafka_producer_flush(&producer, 15000) {
        Ok(remaining) => { fails = fails + report(remaining == 0, "producer: flush drained"); }
        Err(_) => { fails = fails + report(false, "producer: flush drained"); }
      }

      var reports = 0;
      var report_errors = 0;
      var seen_topic = 0;
      var j = 0;
      while j < 80 && reports < 7 {
        let poll = kafka_producer_poll_delivery(&producer, 200);
        if poll.status == 1 {
          let rep = poll.report;
          reports = reports + 1;
          if rep.err != 0 { report_errors = report_errors + 1; }
          if string.str_compare(rep.topic, "xiom-kafka-live") == 0 {
            seen_topic = seen_topic + 1;
          }
        } elif poll.status == 2 {
          report_errors = report_errors + 1;
        }
        j = j + 1;
      }
      fails = fails + report(reports == 7 && report_errors == 0, "producer: 7 delivery callbacks");
      fails = fails + report(seen_topic == 7, "producer: delivery report topic decoded");

      match kafka_metadata(&producer, 5000) {
        Ok(md) => {
          fails = fails + report(md.brokers.len() >= 1, "metadata: brokers reported");
          var found = false;
          var parts = 0;
          var leader_ok = false;
          var replicas_ok = false;
          var isr_ok = false;
          var t = 0;
          while t < md.topics.len() {
            if string.str_compare(md.topics[t].name, "xiom-kafka-live") == 0 {
              found = true;
              parts = md.topics[t].partitions.len();
              if parts > 0 {
                leader_ok = md.topics[t].partitions[0].leader >= 0;
                replicas_ok = md.topics[t].partitions[0].replicas.len() >= 1;
                isr_ok = md.topics[t].partitions[0].isrs.len() >= 1;
              }
            }
            t = t + 1;
          }
          fails = fails + report(found, "metadata: seeded topic present");
          fails = fails + report(parts == 2, "metadata: partition count");
          fails = fails + report(leader_ok, "metadata: partition leader");
          fails = fails + report(replicas_ok, "metadata: replicas");
          fails = fails + report(isr_ok, "metadata: in-sync replicas");
        }
        Err(_) => {
          fails = fails + report(false, "metadata: brokers reported");
          fails = fails + report(false, "metadata: seeded topic present");
          fails = fails + report(false, "metadata: partition count");
          fails = fails + report(false, "metadata: partition leader");
          fails = fails + report(false, "metadata: replicas");
          fails = fails + report(false, "metadata: in-sync replicas");
        }
      }
      match kafka_cluster_id(&producer, 5000) {
        Ok(_) => { fails = fails + report(true, "metadata: cluster id query"); }
        Err(_) => { fails = fails + report(false, "metadata: cluster id query"); }
      }
      if fails > 0 {
        kafka_producer_close(producer);
        return Err(KafkaError { code: 1; message: "producer/metadata checks failed"; is_retryable: false });
      }
      return Ok(producer);
    }
    Err(e) => {
      fails = fails + report(false, "producer: new");
      return Err(e);
    }
  }
}

fn live_consumer_subscribe(brokers: Str) -> Int {
  var fails = 0;
  var ccfg = kafka_config_new(brokers);
  ccfg.client_id = "xiom-kafka-live-consumer";
  ccfg.group_id = "xiom-kafka-live-group";
  match kafka_config_set(&mut ccfg, "auto.offset.reset", "earliest") {
    Ok(_) => { }
    Err(_) => { fails = fails + report(false, "consumer: auto.offset.reset config"); }
  }
  var topics = Vec[Str].new();
  topics.push("xiom-kafka-live");
  match kafka_consumer_new(&ccfg, &topics) {
    Ok(c) => {
      var c_mut = c;
      match kafka_subscribe(&mut c_mut, &topics) {
        Ok(_) => {
          fails = fails + report(true, "consumer: subscribe");
          var got = 0;
          var bad = 0;
          var saw_m0 = false;
          var saw_p1 = false;
          var i = 0;
          while i < 120 && got < 7 {
            let poll = kafka_poll(&c_mut, 250);
            if poll.status == 1 {
              let m = poll.message;
              got = got + 1;
              if string.str_compare(m.topic, "xiom-kafka-live") != 0 { bad = bad + 1; }
              if m.partition < 0 || m.offset < 0 { bad = bad + 1; }
              if m.key.len() == 0 || m.value.len() == 0 { bad = bad + 1; }
              if m.timestamp <= 0 || m.timestamp_type < 0 { bad = bad + 1; }
              if bytes_eq(&m.value, &s2b("m0")) { saw_m0 = true; }
              if bytes_eq(&m.value, &s2b("p1")) { saw_p1 = true; }
            } elif poll.status == 2 {
              bad = bad + 1;
            }
            i = i + 1;
          }
          fails = fails + report(got == 7, "consumer: 7 messages decoded");
          fails = fails + report(bad == 0, "consumer: topic/partition/offset/key/value/timestamp fields");
          fails = fails + report(saw_m0 && saw_p1, "consumer: key/value bytes round-trip");
          match kafka_commit(&c_mut) {
            Ok(_) => { fails = fails + report(true, "consumer: commit"); }
            Err(_) => { fails = fails + report(false, "consumer: commit"); }
          }
          match kafka_consumer_close(c_mut) {
            Ok(_) => { fails = fails + report(true, "consumer: close"); }
            Err(_) => { fails = fails + report(false, "consumer: close"); }
          }
        }
        Err(_) => { fails = fails + report(false, "consumer: subscribe"); }
      }
    }
    Err(_) => { fails = fails + report(false, "consumer: new"); }
  }
  return fails;
}

fn live_consumer_assign(brokers: Str) -> Int {
  var fails = 0;
  var ccfg = kafka_config_new(brokers);
  ccfg.client_id = "xiom-kafka-assign-consumer";
  ccfg.group_id = "xiom-kafka-assign-group";
  var empty = Vec[Str].new();
  match kafka_consumer_new(&ccfg, &empty) {
    Ok(c) => {
      var c_mut = c;
      var parts = Vec[Int].new();
      parts.push(0);
      parts.push(1);
      match kafka_assign(&mut c_mut, "xiom-kafka-live", &parts) {
        Ok(_) => {
          fails = fails + report(true, "consumer: assign topic-partitions");
          var got = 0;
          var i = 0;
          while i < 120 && got < 7 {
            let poll = kafka_poll(&c_mut, 250);
            if poll.status == 1 {
              if poll.message.value.len() > 0 { got = got + 1; }
            }
            i = i + 1;
          }
          fails = fails + report(got >= 7, "consumer: assigned partitions deliver messages");
          match kafka_unsubscribe(&mut c_mut) {
            Ok(_) => { fails = fails + report(true, "consumer: unsubscribe"); }
            Err(_) => { fails = fails + report(false, "consumer: unsubscribe"); }
          }
          match kafka_consumer_close(c_mut) {
            Ok(_) => { fails = fails + report(true, "consumer: assign close"); }
            Err(_) => { fails = fails + report(false, "consumer: assign close"); }
          }
        }
        Err(_) => { fails = fails + report(false, "consumer: assign topic-partitions"); }
      }
    }
    Err(_) => { fails = fails + report(false, "consumer: assign new"); }
  }
  return fails;
}

fn live_admin(brokers: Str) -> Int {
  var fails = 0;
  var acfg = kafka_config_new(brokers);
  acfg.client_id = "xiom-kafka-live-admin";
  match kafka_create_topic_with(&acfg, "xiom-admin-topic", 1, 1) {
    Ok(_) => { fails = fails + report(false, "admin: create request path (mock has no CreateTopics handler)"); }
    Err(e) => {
      fails = fails + report(e.code == -165 && e.message.len() > 0, "admin: create -> typed unsupported (-165)");
    }
  }
  match kafka_delete_topic_with(&acfg, "xiom-admin-topic") {
    Ok(_) => { fails = fails + report(false, "admin: delete request path"); }
    Err(e) => {
      fails = fails + report(e.code == -165 && e.message.len() > 0, "admin: delete -> typed unsupported (-165)");
    }
  }
  match kafka_list_topics_with(&acfg) {
    Ok(names) => {
      fails = fails + report(topic_in(&names, "xiom-kafka-live"), "admin: list topics via metadata");
    }
    Err(_) => { fails = fails + report(false, "admin: list topics via metadata"); }
  }
  return fails;
}

fn live_transactions(brokers: Str) -> Int {
  var fails = 0;
  var tcfg = kafka_config_new(brokers);
  tcfg.client_id = "xiom-kafka-txn-producer";
  match kafka_config_set(&mut tcfg, "transactional.id", "xiom-kafka-txn-id") {
    Ok(_) => {
      match kafka_producer_new(&tcfg) {
        Ok(txn) => {
          match kafka_init_transactions(&txn, 15000) {
            Ok(_) => {
              fails = fails + report(true, "transactions: init");
              match kafka_begin_transaction(&txn) {
                Ok(_) => {
                  let ok_produce = kafka_produce_partition(&txn, "xiom-kafka-live", 0, &s2b("tk1"), &s2b("txn-commit"));
                  match ok_produce {
                    Ok(_) => {
                      match kafka_commit_transaction(&txn, 15000) {
                        Ok(_) => { fails = fails + report(true, "transactions: commit"); }
                        Err(_) => { fails = fails + report(false, "transactions: commit"); }
                      }
                    }
                    Err(_) => { fails = fails + report(false, "transactions: produce in transaction"); }
                  }
                }
                Err(_) => { fails = fails + report(false, "transactions: begin"); }
              }
              match kafka_begin_transaction(&txn) {
                Ok(_) => {
                  let abort_produce = kafka_produce_partition(&txn, "xiom-kafka-live", 0, &s2b("tk2"), &s2b("txn-abort"));
                  match abort_produce {
                    Ok(_) => {
                      match kafka_abort_transaction(&txn, 15000) {
                        Ok(_) => { fails = fails + report(true, "transactions: abort"); }
                        Err(_) => { fails = fails + report(false, "transactions: abort"); }
                      }
                    }
                    Err(_) => { fails = fails + report(false, "transactions: abort produce"); }
                  }
                }
                Err(_) => { fails = fails + report(false, "transactions: second begin"); }
              }
            }
            Err(_) => { fails = fails + report(false, "transactions: init"); }
          }
          kafka_producer_close(txn);
        }
        Err(_) => { fails = fails + report(false, "transactions: producer new"); }
      }
    }
    Err(_) => { fails = fails + report(false, "transactions: transactional.id config"); }
  }
  return fails;
}

fn live_read_committed(brokers: Str) -> Int {
  var fails = 0;
  var ccfg = kafka_config_new(brokers);
  ccfg.client_id = "xiom-kafka-txn-reader";
  ccfg.group_id = "xiom-kafka-txn-reader-group";
  var cfg_ok = true;
  match kafka_config_set(&mut ccfg, "auto.offset.reset", "earliest") { Ok(_) => { } Err(_) => { cfg_ok = false; } }
  match kafka_config_set(&mut ccfg, "isolation.level", "read_committed") { Ok(_) => { } Err(_) => { cfg_ok = false; } }
  fails = fails + report(cfg_ok, "transactions: read_committed config");
  var topics = Vec[Str].new();
  topics.push("xiom-kafka-live");
  match kafka_consumer_new(&ccfg, &topics) {
    Ok(c) => {
      var c_mut = c;
      match kafka_subscribe(&mut c_mut, &topics) {
        Ok(_) => {
          var saw_commit = false;
          var saw_abort = false;
          var i = 0;
          while i < 120 && !saw_commit {
            let poll = kafka_poll(&c_mut, 250);
            if poll.status == 1 {
              if bytes_eq(&poll.message.value, &s2b("txn-commit")) { saw_commit = true; }
              if bytes_eq(&poll.message.value, &s2b("txn-abort")) { saw_abort = true; }
            }
            i = i + 1;
          }
          var j = 0;
          while j < 8 {
            let poll = kafka_poll(&c_mut, 250);
            if poll.status == 1 {
              if bytes_eq(&poll.message.value, &s2b("txn-abort")) { saw_abort = true; }
            }
            j = j + 1;
          }
          fails = fails + report(saw_commit, "transactions: committed record visible to read_committed");
          fails = fails + report(!saw_abort, "transactions: aborted record not visible");
          match kafka_consumer_close(c_mut) {
            Ok(_) => { }
            Err(_) => { fails = fails + report(false, "transactions: reader close"); }
          }
        }
        Err(_) => { fails = fails + report(false, "transactions: reader subscribe"); }
      }
    }
    Err(_) => { fails = fails + report(false, "transactions: reader new"); }
  }
  return fails;
}

fn live_battery() -> Int {
  var fails = 0;
  fails = fails + live_probe();
  fails = fails + report(kafka_mock_is_available(), "mock: API available");
  match kafka_mock_cluster_new(1) {
    Ok(cluster) => {
      fails = fails + report(cluster.brokers.len() > 0, "mock: cluster started");
      fails = fails + report(kafka_mock_set_controller(&cluster, 1).is_ok, "mock: controller set");
      match kafka_mock_topic_create(&cluster, "xiom-kafka-live", 2, 1) {
        Ok(_) => { fails = fails + report(true, "mock: topic seeded"); }
        Err(_) => { fails = fails + report(false, "mock: topic seeded"); }
      }
      match live_producer_and_metadata(cluster.brokers) {
        Ok(producer) => {
          fails = fails + live_consumer_subscribe(cluster.brokers);
          fails = fails + live_consumer_assign(cluster.brokers);
          fails = fails + live_admin(cluster.brokers);
          fails = fails + live_transactions(cluster.brokers);
          fails = fails + live_read_committed(cluster.brokers);
          kafka_producer_close(producer);
        }
        Err(_) => { fails = fails + 1; }
      }
      kafka_mock_cluster_destroy(cluster);
    }
    Err(e) => {
      fails = fails + report(false, "mock: cluster started (" + e.message + ")");
    }
  }
  return fails;
}

fn main() -> Int {
  var failures = 0;

  match kafka_load_named("xiom-no-such-librdkafka-xyz.dll") {
    Ok(_) => { failures = failures + report(false, "loader: bogus soname -> ABSENT"); }
    Err(e) => { failures = failures + report(e.kind == KAFKA_LOAD_ABSENT, "loader: bogus soname -> ABSENT"); }
  }

  failures = failures + test_types();

  match kafka_load() {
    Ok(_) => {
      failures = failures + live_battery();
    }
    Err(e) => {
      if e.kind == KAFKA_LOAD_ABSENT {
        failures = failures + report(true, "live: SKIP -- librdkafka not present (" + e.message + ")");
      } else {
        failures = failures + report(false, "live: FAIL -- ABI: " + e.message);
      }
    }
  }

  return failures;
}

