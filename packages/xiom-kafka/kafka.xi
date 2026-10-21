// XIOM -- xiom.kafka: Apache Kafka client bindings (librdkafka).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.
//
// DESIGN: runtime-loaded librdkafka (LoadLibraryA / dlopen) behind the
// vendored bridge `src/kafka_bridge.c` (port.args.json).  No link-time
// dependency and nothing committed from upstream.  The loader verifies the
// declared export set: missing library -> ABSENT (SKIP); present but broken
// -> ABI (FAIL).  All `unsafe`/`extern "C"` live in this module (G5); the
// per-area modules are typed wrappers over the `kafka_bridge_*` helpers.
//
// Upstream pin: librdkafka v2.16.0 commit
// c6c9973cf1b25394c58e0cade13a36f386856f77 -- see PROVENANCE.md.
//
// Surface: client config set/get, probe/version/errors, producer
// (new/topic-partition/produce/delivery callbacks/flush/poll/transactions/
// close), consumer (subscribe/assign/poll/field decode/commit/close),
// metadata, admin create/delete/list, and the librdkafka mock cluster used
// by the live suite (test.mock.num.brokers / rd_kafka_mock_*).

module xiom.kafka

use xiom.kafka.types;
use xiom.string;

pub const KAFKA_LOAD_ABSENT: Int = 0;
pub const KAFKA_LOAD_ABI: Int = 1;

pub const KAFKA_OFFSET_BEGINNING: Int = -2;
pub const KAFKA_OFFSET_END: Int = -1;
pub const KAFKA_OFFSET_STORED: Int = -1000;
pub const KAFKA_OFFSET_INVALID: Int = -1001;

pub const KAFKA_ADMIN_TIMEOUT_MS: Int = 10000;

// =========================================================================
// FFI surface (G5: the only extern/unsafe block in the package)
// =========================================================================

extern "C" {
  fn xkd_load_named(soname: *UInt8) -> Int32;
  fn xkd_load() -> Int32;
  fn xkd_loaded() -> Int32;
  fn xkd_soname() -> *UInt8;
  fn xkd_error() -> *UInt8;
  fn xkd_abi_missing_count() -> Int32;
  fn xkd_abi_missing() -> *UInt8;
  fn xkd_mock_available() -> Int32;
  fn xkd_unload();
  fn xkd_version_int() -> Int32;
  fn xkd_version_str() -> *UInt8;
  fn xkd_err2str(code: Int32) -> *UInt8;
  fn xkd_err2name(code: Int32) -> *UInt8;
  fn xkd_err_is_retryable(code: Int32) -> Int32;
  fn xkd_last_error_code() -> Int32;

  fn xkd_conf_new() -> Int64;
  fn xkd_conf_destroy(conf: Int64);
  fn xkd_conf_set(conf: Int64, name: *UInt8, value: *UInt8, errstr: *UInt8, cap: Int64) -> Int32;
  fn xkd_conf_set_validate(name: *UInt8, value: *UInt8, errstr: *UInt8, cap: Int64) -> Int32;
  fn xkd_conf_get_default(name: *UInt8, dest: *UInt8, cap: Int64, errstr: *UInt8, errcap: Int64) -> Int32;

  fn xkd_producer_new(conf: Int64, errstr: *UInt8, cap: Int64) -> Int64;
  fn xkd_produce(handle: Int64, topic: *UInt8, partition: Int32, key: *UInt8, keylen: Int64, value: *UInt8, vallen: Int64) -> Int64;
  fn xkd_producer_poll(handle: Int64, timeout_ms: Int32) -> Int32;
  fn xkd_producer_poll_report(handle: Int64, timeout_ms: Int32) -> Int32;
  fn xkd_report_id(handle: Int64) -> Int64;
  fn xkd_report_partition(handle: Int64) -> Int32;
  fn xkd_report_err(handle: Int64) -> Int32;
  fn xkd_report_offset(handle: Int64) -> Int64;
  fn xkd_report_timestamp(handle: Int64) -> Int64;
  fn xkd_report_topic(handle: Int64, dest: *UInt8, cap: Int64) -> Int32;
  fn xkd_flush(handle: Int64, timeout_ms: Int32) -> Int32;
  fn xkd_outq_len(handle: Int64) -> Int32;
  fn xkd_producer_cluster_id(handle: Int64, timeout_ms: Int32, dest: *UInt8, cap: Int64) -> Int32;
  fn xkd_producer_destroy(handle: Int64);

  fn xkd_init_transactions(handle: Int64, timeout_ms: Int32) -> Int64;
  fn xkd_begin_transaction(handle: Int64) -> Int64;
  fn xkd_commit_transaction(handle: Int64, timeout_ms: Int32) -> Int64;
  fn xkd_abort_transaction(handle: Int64, timeout_ms: Int32) -> Int64;
  fn xkd_error_code(errh: Int64) -> Int32;
  fn xkd_error_is_retriable(errh: Int64) -> Int32;
  fn xkd_error_is_fatal(errh: Int64) -> Int32;
  fn xkd_error_string(errh: Int64, dest: *UInt8, cap: Int64) -> Int32;
  fn xkd_error_destroy(errh: Int64);

  fn xkd_consumer_new(conf: Int64, errstr: *UInt8, cap: Int64) -> Int64;
  fn xkd_topic_list_new() -> Int64;
  fn xkd_topic_list_destroy(tpl: Int64);
  fn xkd_topic_list_add_at(tpl: Int64, topic: *UInt8, partition: Int32, offset: Int64) -> Int32;
  fn xkd_subscribe(rk: Int64, tpl: Int64) -> Int32;
  fn xkd_assign(rk: Int64, tpl: Int64) -> Int32;
  fn xkd_unsubscribe(rk: Int64) -> Int32;
  fn xkd_consumer_poll(rk: Int64, timeout_ms: Int32) -> Int64;
  fn xkd_commit(rk: Int64, async: Int32) -> Int32;
  fn xkd_consumer_close(rk: Int64) -> Int32;
  fn xkd_consumer_name(rk: Int64, dest: *UInt8, cap: Int64) -> Int32;
  fn xkd_message_err(msg: Int64) -> Int32;
  fn xkd_message_error_string(msg: Int64, dest: *UInt8, cap: Int64) -> Int32;
  fn xkd_message_topic(msg: Int64, dest: *UInt8, cap: Int64) -> Int32;
  fn xkd_message_partition(msg: Int64) -> Int32;
  fn xkd_message_offset(msg: Int64) -> Int64;
  fn xkd_message_timestamp(msg: Int64) -> Int64;
  fn xkd_message_timestamp_type(msg: Int64) -> Int32;
  fn xkd_message_key_len(msg: Int64) -> Int64;
  fn xkd_message_value_len(msg: Int64) -> Int64;
  fn xkd_message_key_copy(msg: Int64, dest: *UInt8, cap: Int64) -> Int64;
  fn xkd_message_value_copy(msg: Int64, dest: *UInt8, cap: Int64) -> Int64;
  fn xkd_message_destroy(msg: Int64);

  fn xkd_metadata(rk: Int64, timeout_ms: Int32) -> Int64;
  fn xkd_producer_metadata(handle: Int64, timeout_ms: Int32) -> Int64;
  fn xkd_metadata_for_conf(conf: Int64, timeout_ms: Int32) -> Int64;
  fn xkd_metadata_destroy(md: Int64);
  fn xkd_metadata_broker_count(md: Int64) -> Int32;
  fn xkd_metadata_broker_id(md: Int64, i: Int32) -> Int32;
  fn xkd_metadata_broker_host(md: Int64, i: Int32, dest: *UInt8, cap: Int64) -> Int32;
  fn xkd_metadata_broker_port(md: Int64, i: Int32) -> Int32;
  fn xkd_metadata_topic_count(md: Int64) -> Int32;
  fn xkd_metadata_topic_name(md: Int64, i: Int32, dest: *UInt8, cap: Int64) -> Int32;
  fn xkd_metadata_topic_err(md: Int64, i: Int32) -> Int32;
  fn xkd_metadata_topic_partition_count(md: Int64, i: Int32) -> Int32;
  fn xkd_metadata_partition_id(md: Int64, i: Int32, j: Int32) -> Int32;
  fn xkd_metadata_partition_err(md: Int64, i: Int32, j: Int32) -> Int32;
  fn xkd_metadata_partition_leader(md: Int64, i: Int32, j: Int32) -> Int32;
  fn xkd_metadata_partition_replica_count(md: Int64, i: Int32, j: Int32) -> Int32;
  fn xkd_metadata_partition_replica(md: Int64, i: Int32, j: Int32, k: Int32) -> Int32;
  fn xkd_metadata_partition_isr_count(md: Int64, i: Int32, j: Int32) -> Int32;
  fn xkd_metadata_partition_isr(md: Int64, i: Int32, j: Int32, k: Int32) -> Int32;

  fn xkd_admin_new(conf: Int64, errstr: *UInt8, cap: Int64) -> Int64;
  fn xkd_admin_destroy(rk: Int64);
  fn xkd_create_topic(rk: Int64, topic: *UInt8, partitions: Int32, replication: Int32, timeout_ms: Int32, errstr: *UInt8, cap: Int64) -> Int32;
  fn xkd_delete_topic(rk: Int64, topic: *UInt8, timeout_ms: Int32, errstr: *UInt8, cap: Int64) -> Int32;

  fn xkd_mock_cluster_new(broker_cnt: Int32, bootstraps: *UInt8, bootstraps_cap: Int64, errstr: *UInt8, errstr_cap: Int64) -> Int64;
  fn xkd_mock_bootstraps(mctx: Int64, dest: *UInt8, cap: Int64) -> Int32;
  fn xkd_mock_topic_create(mctx: Int64, topic: *UInt8, partitions: Int32, replication: Int32) -> Int32;
  fn xkd_mock_set_controller(mctx: Int64, controller_id: Int32) -> Int32;
  fn xkd_mock_cluster_destroy(mctx: Int64);
}

// =========================================================================
// Buffer / copy helpers
// =========================================================================

fn k_zeroes(n: Int) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < n {
    out.push(0 as UInt8);
    i = i + 1;
  }
  return out;
}

fn k_str(buf: &Vec[UInt8]) -> Str
  requires: true
{
  unsafe {
    return Str::from_c_str(buf.as_mut_ptr());
  }
}

fn k_error_text() -> Str
  requires: true
{
  unsafe {
    return Str::from_c_str(xkd_error());
  }
}

pub fn kafka_bytes_from_ints(values: &Vec[Int]) -> Vec[UInt8] {
  var out = Vec[UInt8].new();
  var i = 0;
  while i < values.len() {
    out.push((values[i] & 255) as UInt8);
    i = i + 1;
  }
  return out;
}

fn k_ints_from_message(handle: Int64, size: Int64, key: Bool) -> Vec[Int] {
  var out = Vec[Int].new();
  if size <= 0 {
    return out;
  }
  var buf = k_zeroes(size as Int);
  var got: Int64 = 0;
  if key {
    got = unsafe { xkd_message_key_copy(handle, buf.as_mut_ptr(), size) };
  } else {
    got = unsafe { xkd_message_value_copy(handle, buf.as_mut_ptr(), size) };
  }
  if got != size {
    return out;
  }
  var i = 0;
  while i < size as Int {
    out.push(buf[i] as Int);
    i = i + 1;
  }
  return out;
}

// =========================================================================
// Loader / probe / error strings
// =========================================================================

pub fn kafka_load_named(soname: Str) -> Result[Int, KafkaLoadError] {
  if soname.len() == 0 {
    return Err(KafkaLoadError { kind: KAFKA_LOAD_ABSENT; message: "soname must not be empty" });
  }
  let rc = unsafe { xkd_load_named(soname.c_str()) } as Int;
  if rc == 0 {
    return Ok(0);
  }
  let kind = if rc == 2 { KAFKA_LOAD_ABI } else { KAFKA_LOAD_ABSENT };
  return Err(KafkaLoadError { kind: kind; message: k_error_text() });
}

pub fn kafka_load() -> Result[Int, KafkaLoadError] {
  let rc = unsafe { xkd_load() } as Int;
  if rc == 0 {
    return Ok(0);
  }
  let kind = if rc == 2 { KAFKA_LOAD_ABI } else { KAFKA_LOAD_ABSENT };
  return Err(KafkaLoadError { kind: kind; message: k_error_text() });
}

pub fn kafka_unload()
  requires: true
{
  unsafe { xkd_unload(); }
}

pub fn kafka_available() -> Bool {
  return unsafe { xkd_loaded() } != 0;
}

pub fn kafka_soname() -> Str
  requires: true
{
  unsafe {
    return Str::from_c_str(xkd_soname());
  }
}

pub fn kafka_version() -> Str
  requires: true
{
  unsafe {
    return Str::from_c_str(xkd_version_str());
  }
}

pub fn kafka_version_int() -> Int {
  return unsafe { xkd_version_int() } as Int;
}

pub fn kafka_error_string(code: Int) -> Str
  requires: true
{
  unsafe {
    return Str::from_c_str(xkd_err2str(code as Int32));
  }
}

pub fn kafka_error_name(code: Int) -> Str
  requires: true
{
  unsafe {
    return Str::from_c_str(xkd_err2name(code as Int32));
  }
}

pub fn kafka_error_is_retryable(code: Int) -> Bool {
  return unsafe { xkd_err_is_retryable(code as Int32) } != 0;
}

pub fn kafka_error_from_code(code: Int) -> KafkaError {
  return KafkaError {
    code: code;
    message: kafka_error_string(code);
    is_retryable: kafka_error_is_retryable(code);
  };
}

pub fn kafka_abi_missing() -> Str
  requires: true
{
  unsafe {
    return Str::from_c_str(xkd_abi_missing());
  }
}

pub fn kafka_abi_missing_count() -> Int {
  return unsafe { xkd_abi_missing_count() } as Int;
}

pub fn kafka_mock_available() -> Bool {
  return unsafe { xkd_mock_available() } != 0;
}

pub fn kafka_last_error_code() -> Int {
  return unsafe { xkd_last_error_code() } as Int;
}

pub fn kafka_last_error() -> KafkaError {
  return kafka_error_from_code(kafka_last_error_code());
}

// =========================================================================
// Configuration
// =========================================================================

pub fn kafka_config_new(brokers: Str) -> KafkaConfig
  requires: brokers.len() > 0
{
  return KafkaConfig {
    brokers: brokers;
    client_id: "xiom.kafka";
    group_id: "";
    prop_names: Vec[Str].new();
    prop_values: Vec[Str].new();
  };
}

pub fn kafka_config_clone(config: &KafkaConfig) -> KafkaConfig {
  var names = Vec[Str].new();
  var values = Vec[Str].new();
  var i = 0;
  while i < config.prop_names.len() {
    names.push(config.prop_names[i]);
    values.push(config.prop_values[i]);
    i = i + 1;
  }
  return KafkaConfig {
    brokers: config.brokers;
    client_id: config.client_id;
    group_id: config.group_id;
    prop_names: names;
    prop_values: values;
  };
}

/// Validate and store one librdkafka configuration property.  Validation is
/// performed against a real rd_kafka_conf_t, so unknown/invalid names fail
/// here as typed errors instead of at client creation.
pub fn kafka_config_set(config: &mut KafkaConfig, name: Str, value: Str) -> Result[Int, KafkaError] {
  if name.len() == 0 {
    return Err(KafkaError { code: -186; message: "configuration property name must not be empty"; is_retryable: false });
  }
  var errbuf = k_zeroes(512);
  let rc = unsafe { xkd_conf_set_validate(name.c_str(), value.c_str(), errbuf.as_mut_ptr(), 512) } as Int;
  if rc != 0 {
    return Err(KafkaError { code: rc; message: k_str(&errbuf); is_retryable: false });
  }
  config.prop_names.push(name);
  config.prop_values.push(value);
  return Ok(0);
}

/// Read a configuration value: named fields first, then stored properties
/// (last set wins), then the librdkafka default for the loaded build.
pub fn kafka_config_get(config: &KafkaConfig, name: Str) -> Result[Str, KafkaError] {
  if name.len() == 0 {
    return Err(KafkaError { code: -186; message: "configuration property name must not be empty"; is_retryable: false });
  }
  if string.str_compare(name, "bootstrap.servers") == 0 {
    return Ok(config.brokers);
  }
  if string.str_compare(name, "client.id") == 0 && config.client_id.len() > 0 {
    return Ok(config.client_id);
  }
  if string.str_compare(name, "group.id") == 0 && config.group_id.len() > 0 {
    return Ok(config.group_id);
  }
  var i = config.prop_names.len();
  while i > 0 {
    i = i - 1;
    if string.str_compare(config.prop_names[i], name) == 0 {
      return Ok(config.prop_values[i]);
    }
  }
  var buf = k_zeroes(4096);
  var errbuf = k_zeroes(512);
  let rc = unsafe { xkd_conf_get_default(name.c_str(), buf.as_mut_ptr(), 4096, errbuf.as_mut_ptr(), 512) } as Int;
  if rc != 0 {
    return Err(KafkaError { code: rc; message: k_str(&errbuf); is_retryable: false });
  }
  return Ok(k_str(&buf));
}

/// Build an rd_kafka_conf_t handle from a KafkaConfig.  The handle is owned
/// by the caller (or consumed by the client constructor).  Complexity:
/// O(properties).
pub fn kafka_conf_build(config: &KafkaConfig) -> Result[Int, KafkaError] {
  let h = unsafe { xkd_conf_new() };
  if h == 0 {
    return Err(KafkaError { code: -172; message: k_error_text(); is_retryable: false });
  }
  var errbuf = k_zeroes(512);
  var rc = unsafe { xkd_conf_set(h, "bootstrap.servers".c_str(), config.brokers.c_str(), errbuf.as_mut_ptr(), 512) } as Int;
  if rc != 0 {
    unsafe { xkd_conf_destroy(h); }
    return Err(KafkaError { code: rc; message: k_str(&errbuf); is_retryable: false });
  }
  if config.client_id.len() > 0 {
    rc = unsafe { xkd_conf_set(h, "client.id".c_str(), config.client_id.c_str(), errbuf.as_mut_ptr(), 512) } as Int;
    if rc != 0 {
      unsafe { xkd_conf_destroy(h); }
      return Err(KafkaError { code: rc; message: k_str(&errbuf); is_retryable: false });
    }
  }
  if config.group_id.len() > 0 {
    rc = unsafe { xkd_conf_set(h, "group.id".c_str(), config.group_id.c_str(), errbuf.as_mut_ptr(), 512) } as Int;
    if rc != 0 {
      unsafe { xkd_conf_destroy(h); }
      return Err(KafkaError { code: rc; message: k_str(&errbuf); is_retryable: false });
    }
  }
  var i = 0;
  while i < config.prop_names.len() {
    rc = unsafe { xkd_conf_set(h, config.prop_names[i].c_str(), config.prop_values[i].c_str(), errbuf.as_mut_ptr(), 512) } as Int;
    if rc != 0 {
      unsafe { xkd_conf_destroy(h); }
      return Err(KafkaError { code: rc; message: k_str(&errbuf); is_retryable: false });
    }
    i = i + 1;
  }
  return Ok(h as Int);
}

// =========================================================================
// Producer bridge
// =========================================================================

pub fn kafka_bridge_producer_new(conf: Int) -> Result[Int, KafkaError] {
  var errbuf = k_zeroes(512);
  let h = unsafe { xkd_producer_new(conf as Int64, errbuf.as_mut_ptr(), 512) };
  if h == 0 {
    return Err(KafkaError { code: -172; message: k_str(&errbuf); is_retryable: false });
  }
  return Ok(h as Int);
}

pub fn kafka_bridge_produce(handle: Int, topic: Str, partition: Int, key: &Vec[Int], value: &Vec[Int]) -> Result[Int, KafkaError> {
  var kb = kafka_bytes_from_ints(key);
  var vb = kafka_bytes_from_ints(value);
  let id = unsafe { xkd_produce(handle as Int64, topic.c_str(), partition as Int32, kb.as_mut_ptr(), kb.len() as Int64, vb.as_mut_ptr(), vb.len() as Int64) };
  if id < 0 {
    return Err(kafka_last_error());
  }
  return Ok(id as Int);
}

pub fn kafka_bridge_producer_poll(handle: Int, timeout_ms: Int) -> Result[Int, KafkaError] {
  let rc = unsafe { xkd_producer_poll(handle as Int64, timeout_ms as Int32) } as Int;
  if rc < 0 {
    return Err(kafka_last_error());
  }
  return Ok(rc);
}

fn kafka_empty_error() -> KafkaError {
  return KafkaError { code: 0; message: ""; is_retryable: false };
}

fn kafka_empty_message() -> KafkaMessage {
  return KafkaMessage {
    topic: "";
    partition: -1;
    offset: -1;
    key: Vec[Int].new();
    value: Vec[Int].new();
    timestamp: 0;
    timestamp_type: 0;
  };
}

fn kafka_empty_report() -> KafkaDeliveryReport {
  return KafkaDeliveryReport {
    id: -1;
    topic: "";
    partition: -1;
    offset: -1;
    err: 0;
    err_message: "";
    timestamp: 0;
  };
}

pub fn kafka_bridge_poll_delivery(handle: Int, timeout_ms: Int) -> KafkaDeliveryPoll {
  let has = unsafe { xkd_producer_poll_report(handle as Int64, timeout_ms as Int32) } as Int;
  if has < 0 {
    return KafkaDeliveryPoll { status: 2; report: kafka_empty_report(); error: kafka_last_error() };
  }
  if has == 0 {
    return KafkaDeliveryPoll { status: 0; report: kafka_empty_report(); error: kafka_empty_error() };
  }
  var topicbuf = k_zeroes(256);
  var ig = unsafe { xkd_report_topic(handle as Int64, topicbuf.as_mut_ptr(), 256) };
  let code = unsafe { xkd_report_err(handle as Int64) } as Int;
  let report = KafkaDeliveryReport {
    id: unsafe { xkd_report_id(handle as Int64) } as Int;
    topic: k_str(&topicbuf);
    partition: unsafe { xkd_report_partition(handle as Int64) } as Int;
    offset: unsafe { xkd_report_offset(handle as Int64) } as Int;
    err: code;
    err_message: kafka_error_string(code);
    timestamp: unsafe { xkd_report_timestamp(handle as Int64) } as Int;
  };
  return KafkaDeliveryPoll { status: 1; report: report; error: kafka_empty_error() };
}

pub fn kafka_bridge_flush(handle: Int, timeout_ms: Int) -> Result[Int, KafkaError> {
  let rc = unsafe { xkd_flush(handle as Int64, timeout_ms as Int32) } as Int;
  if rc != 0 {
    return Err(kafka_error_from_code(rc));
  }
  return Ok(unsafe { xkd_outq_len(handle as Int64) } as Int);
}

pub fn kafka_bridge_outq_len(handle: Int) -> Int {
  return unsafe { xkd_outq_len(handle as Int64) } as Int;
}

pub fn kafka_bridge_producer_cluster_id(handle: Int, timeout_ms: Int) -> Result[Str, KafkaError] {
  var buf = k_zeroes(512);
  let n = unsafe { xkd_producer_cluster_id(handle as Int64, timeout_ms as Int32, buf.as_mut_ptr(), 512) } as Int;
  if n < 0 {
    return Err(kafka_last_error());
  }
  return Ok(k_str(&buf));
}

pub fn kafka_bridge_producer_destroy(handle: Int)
  requires: true
{
  unsafe { xkd_producer_destroy(handle as Int64); }
}

fn kafka_bridge_txn_result(errh: Int64) -> Result[Int, KafkaError> {
  if errh == 0 {
    return Ok(0);
  }
  let code = unsafe { xkd_error_code(errh) } as Int;
  let retry = unsafe { xkd_error_is_retriable(errh) } != 0;
  var buf = k_zeroes(512);
  var ig = unsafe { xkd_error_string(errh, buf.as_mut_ptr(), 512) };
  unsafe { xkd_error_destroy(errh); }
  return Err(KafkaError { code: code; message: k_str(&buf); is_retryable: retry });
}

pub fn kafka_bridge_init_transactions(handle: Int, timeout_ms: Int) -> Result[Int, KafkaError> {
  let errh = unsafe { xkd_init_transactions(handle as Int64, timeout_ms as Int32) };
  return kafka_bridge_txn_result(errh);
}

pub fn kafka_bridge_begin_transaction(handle: Int) -> Result[Int, KafkaError> {
  let errh = unsafe { xkd_begin_transaction(handle as Int64) };
  return kafka_bridge_txn_result(errh);
}

pub fn kafka_bridge_commit_transaction(handle: Int, timeout_ms: Int) -> Result[Int, KafkaError> {
  let errh = unsafe { xkd_commit_transaction(handle as Int64, timeout_ms as Int32) };
  return kafka_bridge_txn_result(errh);
}

pub fn kafka_bridge_abort_transaction(handle: Int, timeout_ms: Int) -> Result[Int, KafkaError> {
  let errh = unsafe { xkd_abort_transaction(handle as Int64, timeout_ms as Int32) };
  return kafka_bridge_txn_result(errh);
}

// =========================================================================
// Consumer bridge
// =========================================================================

pub fn kafka_bridge_consumer_new(conf: Int) -> Result[Int, KafkaError] {
  var errbuf = k_zeroes(512);
  let h = unsafe { xkd_consumer_new(conf as Int64, errbuf.as_mut_ptr(), 512) };
  if h == 0 {
    return Err(KafkaError { code: -172; message: k_str(&errbuf); is_retryable: false });
  }
  return Ok(h as Int);
}

pub fn kafka_bridge_subscribe(handle: Int, topics: &Vec[Str]) -> Result[Int, KafkaError] {
  let tl = unsafe { xkd_topic_list_new() };
  if tl == 0 {
    return Err(KafkaError { code: -172; message: "topic list allocation failed"; is_retryable: false });
  }
  var i = 0;
  while i < topics.len() {
    let arc = unsafe { xkd_topic_list_add_at(tl, topics[i].c_str(), -1 as Int32, KAFKA_OFFSET_INVALID as Int64) } as Int;
    if arc != 0 {
      unsafe { xkd_topic_list_destroy(tl); }
      return Err(kafka_error_from_code(arc));
    }
    i = i + 1;
  }
  let rc = unsafe { xkd_subscribe(handle as Int64, tl) } as Int;
  unsafe { xkd_topic_list_destroy(tl); }
  if rc != 0 {
    return Err(kafka_error_from_code(rc));
  }
  return Ok(0);
}

pub fn kafka_bridge_assign(handle: Int, topic: Str, partitions: &Vec[Int]) -> Result[Int, KafkaError> {
  let tl = unsafe { xkd_topic_list_new() };
  if tl == 0 {
    return Err(KafkaError { code: -172; message: "topic list allocation failed"; is_retryable: false });
  }
  var i = 0;
  while i < partitions.len() {
    let arc = unsafe { xkd_topic_list_add_at(tl, topic.c_str(), partitions[i] as Int32, KAFKA_OFFSET_BEGINNING as Int64) } as Int;
    if arc != 0 {
      unsafe { xkd_topic_list_destroy(tl); }
      return Err(kafka_error_from_code(arc));
    }
    i = i + 1;
  }
  let rc = unsafe { xkd_assign(handle as Int64, tl) } as Int;
  unsafe { xkd_topic_list_destroy(tl); }
  if rc != 0 {
    return Err(kafka_error_from_code(rc));
  }
  return Ok(0);
}

pub fn kafka_bridge_unsubscribe(handle: Int) -> Result[Int, KafkaError] {
  let rc = unsafe { xkd_unsubscribe(handle as Int64) } as Int;
  if rc != 0 {
    return Err(kafka_error_from_code(rc));
  }
  return Ok(0);
}

pub fn kafka_bridge_poll_message(handle: Int, timeout_ms: Int) -> KafkaMessagePoll {
  let msg = unsafe { xkd_consumer_poll(handle as Int64, timeout_ms as Int32) };
  if msg == 0 {
    return KafkaMessagePoll { status: 0; message: kafka_empty_message(); error: kafka_empty_error() };
  }
  let code = unsafe { xkd_message_err(msg) } as Int;
  if code != 0 {
    var errbuf = k_zeroes(512);
    var ig = unsafe { xkd_message_error_string(msg, errbuf.as_mut_ptr(), 512) };
    unsafe { xkd_message_destroy(msg); }
    return KafkaMessagePoll {
      status: 2;
      message: kafka_empty_message();
      error: KafkaError { code: code; message: k_str(&errbuf); is_retryable: kafka_error_is_retryable(code) };
    };
  }
  var topicbuf = k_zeroes(256);
  var igt = unsafe { xkd_message_topic(msg, topicbuf.as_mut_ptr(), 256) };
  let key_len = unsafe { xkd_message_key_len(msg) };
  let value_len = unsafe { xkd_message_value_len(msg) };
  let key = k_ints_from_message(msg, key_len, true);
  let value = k_ints_from_message(msg, value_len, false);
  let message = KafkaMessage {
    topic: k_str(&topicbuf);
    partition: unsafe { xkd_message_partition(msg) } as Int;
    offset: unsafe { xkd_message_offset(msg) } as Int;
    key: key;
    value: value;
    timestamp: unsafe { xkd_message_timestamp(msg) } as Int;
    timestamp_type: unsafe { xkd_message_timestamp_type(msg) } as Int;
  };
  unsafe { xkd_message_destroy(msg); }
  return KafkaMessagePoll { status: 1; message: message; error: kafka_empty_error() };
}

pub fn kafka_bridge_commit(handle: Int) -> Result[Int, KafkaError] {
  let rc = unsafe { xkd_commit(handle as Int64, 0) } as Int;
  if rc != 0 {
    return Err(kafka_error_from_code(rc));
  }
  return Ok(0);
}

pub fn kafka_bridge_consumer_close(handle: Int) -> Result[Int, KafkaError] {
  let rc = unsafe { xkd_consumer_close(handle as Int64) } as Int;
  if rc != 0 {
    return Err(kafka_error_from_code(rc));
  }
  return Ok(0);
}

pub fn kafka_bridge_consumer_name(handle: Int) -> Str {
  var buf = k_zeroes(256);
  var ig = unsafe { xkd_consumer_name(handle as Int64, buf.as_mut_ptr(), 256) };
  return k_str(&buf);
}

// =========================================================================
// Metadata bridge
// =========================================================================

fn kafka_bridge_decode_metadata(md: Int64) -> KafkaMetadata {
  var brokers = Vec[KafkaBroker].new();
  let broker_cnt = unsafe { xkd_metadata_broker_count(md) } as Int;
  var i = 0;
  while i < broker_cnt {
    var hostbuf = k_zeroes(256);
    var igh = unsafe { xkd_metadata_broker_host(md, i as Int32, hostbuf.as_mut_ptr(), 256) };
    brokers.push(KafkaBroker {
      id: unsafe { xkd_metadata_broker_id(md, i as Int32) } as Int;
      host: k_str(&hostbuf);
      port: unsafe { xkd_metadata_broker_port(md, i as Int32) } as Int;
    });
    i = i + 1;
  }
  var topics = Vec[KafkaTopicMetadata].new();
  let topic_cnt = unsafe { xkd_metadata_topic_count(md) } as Int;
  var t = 0;
  while t < topic_cnt {
    var namebuf = k_zeroes(256);
    var ign = unsafe { xkd_metadata_topic_name(md, t as Int32, namebuf.as_mut_ptr(), 256) };
    var parts = Vec[KafkaPartitionMetadata].new();
    let part_cnt = unsafe { xkd_metadata_topic_partition_count(md, t as Int32) } as Int;
    var p = 0;
    while p < part_cnt {
      var replicas = Vec[Int].new();
      let rcnt = unsafe { xkd_metadata_partition_replica_count(md, t as Int32, p as Int32) } as Int;
      var r = 0;
      while r < rcnt {
        replicas.push(unsafe { xkd_metadata_partition_replica(md, t as Int32, p as Int32, r as Int32) } as Int);
        r = r + 1;
      }
      var isrs = Vec[Int].new();
      let icnt = unsafe { xkd_metadata_partition_isr_count(md, t as Int32, p as Int32) } as Int;
      var s = 0;
      while s < icnt {
        isrs.push(unsafe { xkd_metadata_partition_isr(md, t as Int32, p as Int32, s as Int32) } as Int);
        s = s + 1;
      }
      parts.push(KafkaPartitionMetadata {
        id: unsafe { xkd_metadata_partition_id(md, t as Int32, p as Int32) } as Int;
        err: unsafe { xkd_metadata_partition_err(md, t as Int32, p as Int32) } as Int;
        leader: unsafe { xkd_metadata_partition_leader(md, t as Int32, p as Int32) } as Int;
        replicas: replicas;
        isrs: isrs;
      });
      p = p + 1;
    }
    topics.push(KafkaTopicMetadata {
      name: k_str(&namebuf);
      err: unsafe { xkd_metadata_topic_err(md, t as Int32) } as Int;
      partitions: parts;
    });
    t = t + 1;
  }
  return KafkaMetadata { brokers: brokers; topics: topics };
}

pub fn kafka_bridge_metadata_producer(handle: Int, timeout_ms: Int) -> Result[KafkaMetadata, KafkaError> {
  let md = unsafe { xkd_producer_metadata(handle as Int64, timeout_ms as Int32) };
  if md == 0 {
    return Err(kafka_last_error());
  }
  let decoded = kafka_bridge_decode_metadata(md);
  unsafe { xkd_metadata_destroy(md); }
  return Ok(decoded);
}

pub fn kafka_bridge_metadata_conf(conf: Int, timeout_ms: Int) -> Result[KafkaMetadata, KafkaError> {
  let md = unsafe { xkd_metadata_for_conf(conf as Int64, timeout_ms as Int32) };
  if md == 0 {
    return Err(kafka_last_error());
  }
  let decoded = kafka_bridge_decode_metadata(md);
  unsafe { xkd_metadata_destroy(md); }
  return Ok(decoded);
}

// =========================================================================
// Admin bridge
// =========================================================================

pub fn kafka_bridge_admin_new(conf: Int) -> Result[Int, KafkaError] {
  var errbuf = k_zeroes(512);
  let h = unsafe { xkd_admin_new(conf as Int64, errbuf.as_mut_ptr(), 512) };
  if h == 0 {
    return Err(KafkaError { code: -172; message: k_str(&errbuf); is_retryable: false });
  }
  return Ok(h as Int);
}

pub fn kafka_bridge_create_topic(rk: Int, topic: Str, partitions: Int, replication: Int, timeout_ms: Int) -> Result[Int, KafkaError] {
  var errbuf = k_zeroes(1024);
  let rc = unsafe { xkd_create_topic(rk as Int64, topic.c_str(), partitions as Int32, replication as Int32, timeout_ms as Int32, errbuf.as_mut_ptr(), 1024) } as Int;
  if rc != 0 {
    let msg = k_str(&errbuf);
    let text = if msg.len() > 0 { msg } else { kafka_error_string(rc) };
    return Err(KafkaError { code: rc; message: text; is_retryable: kafka_error_is_retryable(rc) });
  }
  return Ok(0);
}

pub fn kafka_bridge_delete_topic(rk: Int, topic: Str, timeout_ms: Int) -> Result[Int, KafkaError] {
  var errbuf = k_zeroes(1024);
  let rc = unsafe { xkd_delete_topic(rk as Int64, topic.c_str(), timeout_ms as Int32, errbuf.as_mut_ptr(), 1024) } as Int;
  if rc != 0 {
    let msg = k_str(&errbuf);
    let text = if msg.len() > 0 { msg } else { kafka_error_string(rc) };
    return Err(KafkaError { code: rc; message: text; is_retryable: kafka_error_is_retryable(rc) });
  }
  return Ok(0);
}

pub fn kafka_bridge_admin_destroy(rk: Int)
  requires: true
{
  unsafe { xkd_admin_destroy(rk as Int64); }
}

// =========================================================================
// Mock cluster bridge (librdkafka public test API)
// =========================================================================

pub fn kafka_bridge_mock_cluster_new(brokers: Int) -> Result[KafkaMockCluster, KafkaError] {
  var boot = k_zeroes(512);
  var errbuf = k_zeroes(512);
  let h = unsafe { xkd_mock_cluster_new(brokers as Int32, boot.as_mut_ptr(), 512, errbuf.as_mut_ptr(), 512) };
  if h == 0 {
    let msg = k_str(&errbuf);
    let text = if msg.len() > 0 { msg } else { "mock cluster creation failed" };
    return Err(KafkaError { code: -172; message: text; is_retryable: false });
  }
  return Ok(KafkaMockCluster { handle: h as Int; brokers: k_str(&boot) });
}

pub fn kafka_bridge_mock_topic_create(cluster: &KafkaMockCluster, topic: Str, partitions: Int, replication: Int) -> Result[Int, KafkaError> {
  let rc = unsafe { xkd_mock_topic_create(cluster.handle as Int64, topic.c_str(), partitions as Int32, replication as Int32) } as Int;
  if rc != 0 {
    return Err(kafka_error_from_code(rc));
  }
  return Ok(0);
}

pub fn kafka_bridge_mock_set_controller(cluster: &KafkaMockCluster, controller_id: Int) -> Result[Int, KafkaError> {
  let rc = unsafe { xkd_mock_set_controller(cluster.handle as Int64, controller_id as Int32) } as Int;
  if rc != 0 {
    return Err(kafka_error_from_code(rc));
  }
  return Ok(0);
}

pub fn kafka_bridge_mock_cluster_destroy(cluster: KafkaMockCluster)
  requires: true
{
  unsafe { xkd_mock_cluster_destroy(cluster.handle as Int64); }
}



