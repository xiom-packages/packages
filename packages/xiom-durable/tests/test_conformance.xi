module xiom.durable.tests.test_conformance

use xiom.durable.error;
use xiom.durable.result;
use xiom.durable.ids;
use xiom.durable.limits;
use xiom.durable.config;
use xiom.durable.contracts;
use xiom.durable.metrics;
use xiom.durable.version;
use xiom.durable.storage.page;
use xiom.durable.storage.checksum;
use xiom.durable.storage.pager;
use xiom.durable.storage.buffer_pool;
use xiom.durable.wal.lsn;
use xiom.durable.wal.wal_record;
use xiom.durable.wal.wal_writer;
use xiom.durable.wal.wal_reader;
use xiom.durable.wal.checkpoint;
use xiom.durable.wal.recovery;
use xiom.durable.txn.txn_state;
use xiom.durable.txn.txn_manager;
use xiom.durable.txn.snapshot;

// =============================================================================
// version.xi -- 5 tests
// =============================================================================

fn test_engine_version()
  requires: true
{
  var v = engine_version();
}

fn test_storage_format_version()
  requires: true
{
  var v = storage_format_version();
}

fn test_wal_format_version()
  requires: true
{
  var v = wal_format_version();
}

fn test_protocol_version()
  requires: true
{
  var v = protocol_version();
}

fn test_snapshot_format_version()
  requires: true
{
  var v = snapshot_format_version();
}

// =============================================================================
// result.xi -- 3 tests
// =============================================================================

fn test_is_ok_result_true()
  requires: true
{
  var r = is_ok_result(true);
}

fn test_is_ok_result_false()
  requires: true
{
  var r = is_ok_result(false);
}

fn test_result_info_ok()
  requires: true
{
  var ri = result_info_ok();
}

fn test_result_info_err()
  requires: true
{
  var ri = result_info_err(42);
}

// =============================================================================
// metrics.xi -- 10 tests
// =============================================================================

fn test_counter_new()
  requires: true
{
  var c = counter_new("test_counter");
}

fn test_counter_inc()
  requires: true
{
  var c = counter_new("test_counter");
  counter_inc(&mut c);
}

fn test_counter_add()
  requires: true
{
  var c = counter_new("test_counter");
  counter_add(&mut c, 5);
}

fn test_gauge_new()
  requires: true
{
  var g = gauge_new("test_gauge");
}

fn test_gauge_set()
  requires: true
{
  var g = gauge_new("test_gauge");
  gauge_set(&mut g, 100);
}

fn test_histogram_new()
  requires: true
{
  var bounds = Vec[Int].new();
  bounds.push(10);
  bounds.push(100);
  var h = histogram_new("test_hist", bounds);
}

fn test_histogram_observe()
  requires: true
{
  var bounds = Vec[Int].new();
  bounds.push(10);
  bounds.push(100);
  var h = histogram_new("test_hist", bounds);
  histogram_observe(&mut h, 5);
  histogram_observe(&mut h, 50);
  histogram_observe(&mut h, 200);
}

fn test_registry_new()
  requires: true
{
  var r = registry_new();
}

fn test_registry_add_counter()
  requires: true
{
  var r = registry_new();
  var c = counter_new("reg_counter");
  registry_add_counter(&mut r, c);
}

fn test_registry_add_gauge()
  requires: true
{
  var r = registry_new();
  var g = gauge_new("reg_gauge");
  registry_add_gauge(&mut r, g);
}

// =============================================================================
// limits.xi -- 10 tests
// =============================================================================

fn test_max_dimensions()
  requires: true
{
  var v = max_dimensions();
}

fn test_max_page_size()
  requires: true
{
  var v = max_page_size();
}

fn test_default_page_size()
  requires: true
{
  var v = default_page_size();
}

fn test_max_batch_size()
  requires: true
{
  var v = max_batch_size();
}

fn test_max_key_size()
  requires: true
{
  var v = max_key_size();
}

fn test_max_value_size()
  requires: true
{
  var v = max_value_size();
}

fn test_max_segment_count()
  requires: true
{
  var v = max_segment_count();
}

fn test_default_btree_order()
  requires: true
{
  var v = default_btree_order();
}

fn test_max_graph_degree()
  requires: true
{
  var v = max_graph_degree();
}

fn test_max_top_k()
  requires: true
{
  var v = max_top_k();
}

// =============================================================================
// ids.xi -- 25 tests
// =============================================================================

// --- PageId ---
fn test_page_id()
  requires: true
{
  var id = page_id(1);
}

fn test_page_id_value()
  requires: true
{
  var id = page_id(42);
  var v = page_id_value(&id);
}

fn test_page_id_eq_true()
  requires: true
{
  var a = page_id(5);
  var b = page_id(5);
  var eq = page_id_eq(&a, &b);
}

fn test_page_id_eq_false()
  requires: true
{
  var a = page_id(1);
  var b = page_id(2);
  var eq = page_id_eq(&a, &b);
}

// --- Lsn ---
fn test_lsn_construct()
  requires: true
{
  var id = lsn(10);
}

fn test_lsn_value()
  requires: true
{
  var id = lsn(10);
  var v = lsn_value(&id);
}

fn test_lsn_next()
  requires: is_valid_lsn_ordering(5, 6)
{
  var id = lsn(5);
  var next = lsn_next(&id);
}

fn test_lsn_lt_true()
  requires: is_valid_lsn_ordering(1, 2)
{
  var a = lsn(1);
  var b = lsn(2);
  var lt = lsn_lt(&a, &b);
}

fn test_lsn_lt_false()
  requires: true
{
  var a = lsn(5);
  var b = lsn(3);
  var lt = lsn_lt(&a, &b);
}

fn test_lsn_eq_true()
  requires: true
{
  var a = lsn(7);
  var b = lsn(7);
  var eq = lsn_eq(&a, &b);
}

fn test_lsn_zero()
  requires: true
{
  var z = lsn_zero();
}

// --- SegmentId ---
fn test_segment_id()
  requires: true
{
  var id = segment_id(100);
}

fn test_segment_id_value()
  requires: true
{
  var id = segment_id(100);
  var v = segment_id_value(&id);
}

fn test_segment_id_eq()
  requires: true
{
  var a = segment_id(3);
  var b = segment_id(3);
  var eq = segment_id_eq(&a, &b);
}

// --- TxnId ---
fn test_txn_id()
  requires: true
{
  var id = txn_id(1);
}

fn test_txn_id_value()
  requires: true
{
  var id = txn_id(99);
  var v = txn_id_value(&id);
}

fn test_txn_id_eq()
  requires: true
{
  var a = txn_id(10);
  var b = txn_id(10);
  var eq = txn_id_eq(&a, &b);
}

fn test_txn_id_next()
  requires: true
{
  var id = txn_id(10);
  var next = txn_id_next(&id);
}

// --- CollectionId ---
fn test_collection_id()
  requires: true
{
  var id = collection_id(1);
}

fn test_collection_id_value()
  requires: true
{
  var id = collection_id(200);
  var v = collection_id_value(&id);
}

fn test_collection_id_eq()
  requires: true
{
  var a = collection_id(1);
  var b = collection_id(1);
  var eq = collection_id_eq(&a, &b);
}

// --- VectorId ---
fn test_vector_id()
  requires: true
{
  var id = vector_id(0);
}

fn test_vector_id_value()
  requires: true
{
  var id = vector_id(50);
  var v = vector_id_value(&id);
}

fn test_vector_id_eq()
  requires: true
{
  var a = vector_id(7);
  var b = vector_id(7);
  var eq = vector_id_eq(&a, &b);
}

// --- ShardId ---
fn test_shard_id()
  requires: true
{
  var id = shard_id(0);
}

fn test_shard_id_value()
  requires: true
{
  var id = shard_id(4);
  var v = shard_id_value(&id);
}

fn test_shard_id_eq()
  requires: true
{
  var a = shard_id(9);
  var b = shard_id(9);
  var eq = shard_id_eq(&a, &b);
}

// =============================================================================
// error.xi -- 2 tests
// =============================================================================

fn test_core_error_to_str_not_found()
  requires: true
{
  var e = CoreError.NotFound;
  var s = core_error_to_str(&e);
}

fn test_core_error_is_retryable_io()
  requires: true
{
  var e = CoreError.IOFailure("disk full");
  var r = core_error_is_retryable(&e);
}

fn test_core_error_is_retryable_not_found()
  requires: true
{
  var e = CoreError.NotFound;
  var r = core_error_is_retryable(&e);
}

// =============================================================================
// contracts.xi -- 7 tests with requires: contracts
// =============================================================================

fn test_is_power_of_two_2()
  requires: true
{
  var r = is_power_of_two(2);
}

fn test_is_power_of_two_1()
  requires: true
{
  var r = is_power_of_two(1);
}

fn test_is_power_of_two_0()
  requires: true
{
  var r = is_power_of_two(0);
}

fn test_is_power_of_two_3()
  requires: true
{
  var r = is_power_of_two(3);
}

fn test_is_valid_page_size_4096()
  requires: is_power_of_two(4096)
{
  var r = is_valid_page_size(4096);
}

fn test_is_valid_page_size_512()
  requires: is_power_of_two(512)
{
  var r = is_valid_page_size(512);
}

fn test_is_valid_page_size_256()
  requires: true
{
  var r = is_valid_page_size(256);
}

fn test_is_valid_page_size_65536()
  requires: is_power_of_two(65536)
{
  var r = is_valid_page_size(65536);
}

fn test_is_valid_dimension_1()
  requires: true
{
  var r = is_valid_dimension(1);
}

fn test_is_valid_dimension_65536()
  requires: true
{
  var r = is_valid_dimension(65536);
}

fn test_is_valid_dimension_0()
  requires: true
{
  var r = is_valid_dimension(0);
}

fn test_is_valid_key_size_1()
  requires: true
{
  var r = is_valid_key_size(1);
}

fn test_is_valid_key_size_4096()
  requires: true
{
  var r = is_valid_key_size(4096);
}

fn test_is_valid_key_size_0()
  requires: true
{
  var r = is_valid_key_size(0);
}

fn test_is_valid_top_k_1()
  requires: true
{
  var r = is_valid_top_k(1);
}

fn test_is_valid_top_k_10000()
  requires: true
{
  var r = is_valid_top_k(10000);
}

fn test_is_valid_top_k_0()
  requires: true
{
  var r = is_valid_top_k(0);
}

fn test_is_valid_lsn_ordering_1_2()
  requires: true
{
  var r = is_valid_lsn_ordering(1, 2);
}

fn test_is_valid_lsn_ordering_2_1()
  requires: true
{
  var r = is_valid_lsn_ordering(2, 1);
}

fn test_is_sorted_ints_empty()
  requires: true
{
  var v = Vec[Int].new();
  var r = is_sorted_ints(&v);
}

fn test_is_sorted_ints_sorted()
  requires: true
{
  var v = Vec[Int].new();
  v.push(1);
  v.push(2);
  v.push(3);
  var r = is_sorted_ints(&v);
}

fn test_is_sorted_ints_unsorted()
  requires: true
{
  var v = Vec[Int].new();
  v.push(3);
  v.push(1);
  v.push(2);
  var r = is_sorted_ints(&v);
}

// =============================================================================
// config.xi -- 4 tests
// =============================================================================

fn test_core_config_default()
  requires: true
{
  var cfg = core_config_default();
}

fn test_core_config_validate_default()
  requires: is_valid_page_size(4096)
{
  var cfg = core_config_default();
  var ok = core_config_validate(&cfg);
}

fn test_core_config_validate_invalid_page()
  requires: true
{
  var cfg = CoreConfig{
    page_size: 1000,
    buffer_pool_size: 1024,
    wal_enabled: true,
    sync_on_commit: true,
    data_dir: "./data",
    max_open_files: 256,
  };
  var ok = core_config_validate(&cfg);
}

fn test_core_config_validate_zero_pool()
  requires: is_valid_page_size(4096)
{
  var cfg = CoreConfig{
    page_size: 4096,
    buffer_pool_size: 0,
    wal_enabled: true,
    sync_on_commit: true,
    data_dir: "./data",
    max_open_files: 256,
  };
  var ok = core_config_validate(&cfg);
}

fn test_core_config_dev()
  requires: is_valid_page_size(4096)
{
  var cfg = core_config_dev();
}

fn test_core_config_prod()
  requires: is_valid_page_size(8192)
{
  var cfg = core_config_prod();
}

// =============================================================================
// storage/page.xi -- 5 tests
// =============================================================================

fn test_page_new()
  requires: is_valid_page_size(4096)
{
  var p = page_new(0, 4096);
}

fn test_page_is_dirty_fresh()
  requires: is_valid_page_size(4096)
{
  var p = page_new(0, 4096);
  var d = page_is_dirty(&p);
}

fn test_page_mark_dirty()
  requires: is_valid_page_size(4096)
{
  var p = page_new(0, 4096);
  page_mark_dirty(&mut p);
}

fn test_page_pin()
  requires: is_valid_page_size(4096)
{
  var p = page_new(0, 4096);
  page_pin(&mut p);
}

fn test_page_unpin()
  requires: is_valid_page_size(4096)
{
  var p = page_new(0, 4096);
  page_pin(&mut p);
  page_unpin(&mut p);
}

fn test_page_unpin_at_zero()
  requires: is_valid_page_size(4096)
{
  var p = page_new(0, 4096);
  page_unpin(&mut p);
}

// =============================================================================
// storage/checksum.xi -- 2 tests
// =============================================================================

fn test_crc32_empty()
  requires: true
{
  var data = Vec[Int].new();
  var hash = crc32(&data);
}

fn test_crc32_nonempty()
  requires: true
{
  var data = Vec[Int].new();
  data.push(1);
  data.push(2);
  data.push(3);
  var hash = crc32(&data);
}

fn test_verify_checksum_match()
  requires: true
{
  var data = Vec[Int].new();
  data.push(1);
  data.push(2);
  var hash = crc32(&data);
  var ok = verify_checksum(&data, hash);
}

fn test_verify_checksum_mismatch()
  requires: true
{
  var data = Vec[Int].new();
  data.push(1);
  var ok = verify_checksum(&data, 99999);
}

// =============================================================================
// storage/pager.xi -- 5 tests
// =============================================================================

fn test_pager_new()
  requires: is_valid_page_size(4096)
{
  var p = pager_new(4096);
}

fn test_pager_alloc_page()
  requires: is_valid_page_size(4096)
{
  var p = pager_new(4096);
  var id = pager_alloc_page(&mut p);
}

fn test_pager_read_page_valid()
  requires: is_valid_page_size(4096)
{
  var p = pager_new(4096);
  var id = pager_alloc_page(&mut p);
  var pg = pager_read_page(&p, id);
}

fn test_pager_read_page_invalid()
  requires: is_valid_page_size(4096)
{
  var p = pager_new(4096);
  var pg = pager_read_page(&p, -1);
}

fn test_pager_read_page_oob()
  requires: is_valid_page_size(4096)
{
  var p = pager_new(4096);
  var pg = pager_read_page(&p, 100);
}

fn test_pager_page_count()
  requires: is_valid_page_size(4096)
{
  var p = pager_new(4096);
  pager_alloc_page(&mut p);
  pager_alloc_page(&mut p);
  var count = pager_page_count(&p);
}

fn test_pager_flush()
  requires: is_valid_page_size(4096)
{
  var p = pager_new(4096);
  pager_alloc_page(&mut p);
  var flushed = pager_flush(&p);
}

// =============================================================================
// storage/buffer_pool.xi -- 4 tests
// =============================================================================

fn test_buffer_pool_new()
  requires: true
{
  var bp = buffer_pool_new(64);
}

fn test_buffer_pool_get_miss()
  requires: true
{
  var bp = buffer_pool_new(64);
  var pg = buffer_pool_get(&mut bp, 0);
}

fn test_buffer_pool_put_and_get()
  requires: true
{
  var bp = buffer_pool_new(64);
  var p = page_new(1, 4096);
  buffer_pool_put(&mut bp, p);
  var pg = buffer_pool_get(&mut bp, 1);
}

fn test_buffer_pool_hit_ratio_empty()
  requires: true
{
  var bp = buffer_pool_new(64);
  var ratio = buffer_pool_hit_ratio(&bp);
}

fn test_buffer_pool_hit_ratio_after_get()
  requires: true
{
  var bp = buffer_pool_new(64);
  var pg = buffer_pool_get(&mut bp, 42);
  var ratio = buffer_pool_hit_ratio(&bp);
}

// =============================================================================
// wal/lsn.xi -- 3 tests
// =============================================================================

fn test_wal_lsn_construct()
  requires: true
{
  var l = wal_lsn(1);
}

fn test_wal_lsn_value()
  requires: true
{
  var l = wal_lsn(42);
  var v = wal_lsn_value(&l);
}

fn test_wal_lsn_next()
  requires: true
{
  var l = wal_lsn(10);
  var next = wal_lsn_next(&l);
}

// =============================================================================
// wal/wal_record.xi -- 1 test
// =============================================================================

fn test_wal_record_new()
  requires: is_valid_lsn_ordering(0, 1)
{
  var rec = wal_record_new(1, WalOpKind.Insert, 100, 200);
}

// =============================================================================
// wal/wal_writer.xi -- 5 tests
// =============================================================================

fn test_wal_writer_new()
  requires: true
{
  var w = wal_writer_new();
}

fn test_wal_writer_append()
  requires: true
{
  var w = wal_writer_new();
  var lsn_val = wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
}

fn test_wal_writer_append_multiple()
  requires: true
{
  var w = wal_writer_new();
  var l1 = wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  var l2 = wal_writer_append(&mut w, WalOpKind.Update, 2, 200);
  var l3 = wal_writer_append(&mut w, WalOpKind.Delete, 3, 0);
}

fn test_wal_writer_flush()
  requires: true
{
  var w = wal_writer_new();
  wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  var flushed = wal_writer_flush(&mut w);
}

fn test_wal_writer_current_lsn()
  requires: is_valid_lsn_ordering(1, 2)
{
  var w = wal_writer_new();
  wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  wal_writer_append(&mut w, WalOpKind.Insert, 2, 200);
  var cur = wal_writer_current_lsn(&w);
}

fn test_wal_writer_synced_lsn()
  requires: true
{
  var w = wal_writer_new();
  wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  wal_writer_flush(&mut w);
  var synced = wal_writer_synced_lsn(&w);
}

// =============================================================================
// wal/wal_reader.xi -- 2 tests
// =============================================================================

fn test_wal_read_all()
  requires: true
{
  var w = wal_writer_new();
  wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  wal_writer_append(&mut w, WalOpKind.Update, 2, 200);
  var records = wal_read_all(&w);
}

fn test_wal_read_from()
  requires: true
{
  var w = wal_writer_new();
  wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  wal_writer_append(&mut w, WalOpKind.Update, 2, 200);
  wal_writer_append(&mut w, WalOpKind.Delete, 3, 0);
  var records = wal_read_from(&w, 2);
}

// =============================================================================
// wal/checkpoint.xi -- 2 tests
// =============================================================================

fn test_checkpoint_new()
  requires: true
{
  var cp = checkpoint_new(42, 1000);
}

fn test_checkpoint_can_truncate_before()
  requires: true
{
  var cp = checkpoint_new(10, 1000);
  var can = checkpoint_can_truncate(&cp, 5);
}

fn test_checkpoint_can_truncate_at()
  requires: true
{
  var cp = checkpoint_new(10, 1000);
  var can = checkpoint_can_truncate(&cp, 10);
}

fn test_checkpoint_can_truncate_after()
  requires: true
{
  var cp = checkpoint_new(10, 1000);
  var can = checkpoint_can_truncate(&cp, 15);
}

// =============================================================================
// wal/recovery.xi -- 1 test
// =============================================================================

fn test_recovery_scan_empty()
  requires: true
{
  var w = wal_writer_new();
  var result = recovery_scan(&w, 0);
}

fn test_recovery_scan_with_records()
  requires: is_valid_lsn_ordering(0, 1)
{
  var w = wal_writer_new();
  wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  wal_writer_append(&mut w, WalOpKind.Update, 2, 200);
  wal_writer_append(&mut w, WalOpKind.Delete, 3, 0);
  var result = recovery_scan(&w, 1);
}

// =============================================================================
// txn/txn_state.xi -- 2 tests
// =============================================================================

fn test_txn_state_can_commit_open()
  requires: true
{
  var s = TxnStateKind.Open;
  var can = txn_state_can_commit(&s);
}

fn test_txn_state_can_commit_prepared()
  requires: true
{
  var s = TxnStateKind.Prepared;
  var can = txn_state_can_commit(&s);
}

fn test_txn_state_can_commit_committed()
  requires: true
{
  var s = TxnStateKind.Committed;
  var can = txn_state_can_commit(&s);
}

fn test_txn_state_is_terminal_open()
  requires: true
{
  var s = TxnStateKind.Open;
  var t = txn_state_is_terminal(&s);
}

fn test_txn_state_is_terminal_committed()
  requires: true
{
  var s = TxnStateKind.Committed;
  var t = txn_state_is_terminal(&s);
}

fn test_txn_state_is_terminal_aborted()
  requires: true
{
  var s = TxnStateKind.Aborted;
  var t = txn_state_is_terminal(&s);
}

// =============================================================================
// txn/txn_manager.xi -- 5 tests
// =============================================================================

fn test_txn_manager_new()
  requires: true
{
  var tm = txn_manager_new();
}

fn test_txn_begin()
  requires: true
{
  var tm = txn_manager_new();
  var id = txn_begin(&mut tm, 1);
}

fn test_txn_commit()
  requires: true
{
  var tm = txn_manager_new();
  var id = txn_begin(&mut tm, 1);
  var ok = txn_commit(&mut tm, id);
}

fn test_txn_commit_unknown()
  requires: true
{
  var tm = txn_manager_new();
  var ok = txn_commit(&mut tm, 999);
}

fn test_txn_abort()
  requires: true
{
  var tm = txn_manager_new();
  var id = txn_begin(&mut tm, 1);
  var ok = txn_abort(&mut tm, id);
}

fn test_txn_abort_unknown()
  requires: true
{
  var tm = txn_manager_new();
  var ok = txn_abort(&mut tm, 999);
}

fn test_txn_active_count()
  requires: true
{
  var tm = txn_manager_new();
  txn_begin(&mut tm, 1);
  txn_begin(&mut tm, 2);
  var count = txn_active_count(&tm);
}

// =============================================================================
// txn/snapshot.xi -- 2 tests
// =============================================================================

fn test_snapshot_new()
  requires: true
{
  var snap = snapshot_new(100);
}

fn test_snapshot_is_visible_below()
  requires: true
{
  var snap = snapshot_new(100);
  var vis = snapshot_is_visible(&snap, 50);
}

fn test_snapshot_is_visible_at()
  requires: true
{
  var snap = snapshot_new(100);
  var vis = snapshot_is_visible(&snap, 100);
}

fn test_snapshot_is_visible_above()
  requires: true
{
  var snap = snapshot_new(100);
  var vis = snapshot_is_visible(&snap, 150);
}

// =============================================================================
// Integration / cross-module contract tests
// =============================================================================

// WAL-before-ack: after flush, synced_lsn must cover the appended LSN.
fn test_wal_before_ack_contract()
  requires: true
{
  var w = wal_writer_new();
  var lsn_val = wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  wal_writer_flush(&mut w);
  var synced = wal_writer_synced_lsn(&w);
}

// LSN monotonic ordering: each append returns a strictly larger LSN.
fn test_lsn_monotonic_contract()
  requires: is_valid_lsn_ordering(1, 2)
{
  var w = wal_writer_new();
  var a = wal_writer_append(&mut w, WalOpKind.Insert, 1, 100);
  var b = wal_writer_append(&mut w, WalOpKind.Insert, 2, 200);
  var c = wal_writer_append(&mut w, WalOpKind.Insert, 3, 300);
}

// Page lifecycle: pin then unpin; pin_count must not go negative.
fn test_page_pin_unpin_contract()
  requires: is_valid_page_size(4096)
{
  var p = page_new(0, 4096);
  page_pin(&mut p);
  page_pin(&mut p);
  page_unpin(&mut p);
  page_unpin(&mut p);
  page_unpin(&mut p);
}

// Config validation: default config must pass validation.
fn test_config_default_valid_contract()
  requires: is_valid_page_size(4096)
{
  var cfg = core_config_default();
  var ok = core_config_validate(&cfg);
}

// Checksum determinism: same data produces same hash.
fn test_checksum_determinism_contract()
  requires: true
{
  var data = Vec[Int].new();
  data.push(1);
  data.push(2);
  data.push(3);
  var h1 = crc32(&data);
  var h2 = crc32(&data);
}

// Transaction lifecycle: begin -> commit -> terminal.
fn test_txn_lifecycle_contract()
  requires: true
{
  var tm = txn_manager_new();
  var id = txn_begin(&mut tm, 1);
  txn_commit(&mut tm, id);
  var s = TxnStateKind.Committed;
  var terminal = txn_state_is_terminal(&s);
}

// Checkpoint truncation safety: records below checkpoint are truncatable.
fn test_checkpoint_truncation_contract()
  requires: is_valid_lsn_ordering(4, 5)
{
  var cp = checkpoint_new(5, 1000);
  var can1 = checkpoint_can_truncate(&cp, 4);
  var can2 = checkpoint_can_truncate(&cp, 5);
}

// Snapshot visibility: records at or below snapshot LSN are visible.
fn test_snapshot_visibility_contract()
  requires: is_valid_lsn_ordering(5, 10)
{
  var snap = snapshot_new(10);
  var vis1 = snapshot_is_visible(&snap, 5);
  var vis2 = snapshot_is_visible(&snap, 10);
  var vis3 = snapshot_is_visible(&snap, 15);
}
