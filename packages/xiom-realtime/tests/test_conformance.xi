// XIOM -- xiom-realtime Conformance Tests (10 tests)
module xiom.realtime.tests

use xiom.realtime;
use xiom.string;
use xiom.io;

fn assert_true(condition: Bool, label: Str) -> Result[Unit, Str] {
  if condition { return Ok(Unit); };
  return Err("FAIL: " + label);
}

fn assert_int_eq(actual: Int, expected: Int, label: Str) -> Result[Unit, Str] {
  if actual == expected { return Ok(Unit); };
  return Err("FAIL: " + label + " -- expected " + int_to_str(expected) + " got " + int_to_str(actual));
}

fn assert_str_eq(actual: Str, expected: Str, label: Str) -> Result[Unit, Str] {
  if actual == expected { return Ok(Unit); };
  return Err("FAIL: " + label + " -- expected '" + expected + "' got '" + actual + "'");
}

fn int_to_str(n: Int) -> Str {
  if n == 0 { return "0"; };
  var num: Int = n;
  var neg: Bool = false;
  if num < 0 { neg = true; num = -num; };
  var out: Str = "";
  while num > 0 {
    var d: Int = num % 10;
    if d == 0 { out = "0" + out; }
    elif d == 1 { out = "1" + out; }
    elif d == 2 { out = "2" + out; }
    elif d == 3 { out = "3" + out; }
    elif d == 4 { out = "4" + out; }
    elif d == 5 { out = "5" + out; }
    elif d == 6 { out = "6" + out; }
    elif d == 7 { out = "7" + out; }
    elif d == 8 { out = "8" + out; }
    elif d == 9 { out = "9" + out; };
    num = num / 10;
  };
  if neg { out = "-" + out; };
  return out;
}

pub fn run_all_tests() -> Result[Unit, Str] {
  io.println("=== xiom-realtime Conformance Tests ===");

  var passed: Int = 0;
  var failed: Int = 0;
  var total: Int = 0;

  var results: Vec[Result[Unit, Str]] = Vec[Result[Unit, Str]].new();
  results.push(test_task_new());
  results.push(test_task_is_pending());
  results.push(test_task_is_expired());
  results.push(test_task_cmp_priority());
  results.push(test_scheduler_new());
  results.push(test_scheduler_add_and_sort());
  results.push(test_scheduler_tick_executes());
  results.push(test_scheduler_complete_task());
  results.push(test_scheduler_fail_task());
  results.push(test_scheduler_state_counts());

  var i: Int = 0;
  while i < results.len() {
    total = total + 1;
    match results[i] {
      Ok(_) => { passed = passed + 1; },
      Err(e) => { failed = failed + 1; io.println(e); },
    };
    i = i + 1;
  };

  io.println("");
  io.println(int_to_str(passed) + " passed, " + int_to_str(failed) + " failed out of " + int_to_str(total));

  if failed > 0 {
    return Err(int_to_str(failed) + " test(s) failed");
  };
  return Ok(Unit);
}

fn test_task_new() -> Result[Unit, Str] {
  var t = task_new("t1", "send-alert", RtPriority.Critical, 5000, 0);
  try(assert_str_eq(t.id, "t1", "task_new: id"));
  try(assert_str_eq(t.name, "send-alert", "task_new: name"));
  match t.priority {
    RtPriority.Critical => {},
    _ => { return Err("FAIL: task_new: expected Critical priority"); },
  };
  try(assert_int_eq(t.deadline_ms, 5000, "task_new: deadline_ms"));
  try(assert_int_eq(t.created_at_ms, 0, "task_new: created_at_ms"));
  try(assert_int_eq(t.retry_count, 0, "task_new: retry_count=0"));
  try(assert_int_eq(t.max_retries, 3, "task_new: max_retries=3"));
  try(assert_true(task_is_pending(&t), "task_new: state=Pending"));
  return Ok(Unit);
}

fn test_task_is_pending() -> Result[Unit, Str] {
  var t = task_new("t2", "log", RtPriority.Low, 1000, 0);
  try(assert_true(task_is_pending(&t), "is_pending: fresh task"));

  var t2 = RtTask{
    id: "t3", name: "done", priority: RtPriority.Normal, deadline_ms: 0,
    created_at_ms: 0, state: RtTaskState.Completed, retry_count: 0, max_retries: 3,
  };
  try(assert_true(!task_is_pending(&t2), "is_pending: completed task"));
  return Ok(Unit);
}

fn test_task_is_expired() -> Result[Unit, Str] {
  var t = task_new("t4", "compute", RtPriority.High, 100, 0);
  try(assert_true(!task_is_expired(&t, 50), "is_expired: deadline=100, now=50 -> not expired"));
  try(assert_true(task_is_expired(&t, 150), "is_expired: deadline=100, now=150 -> expired"));

  var t2 = task_new("t5", "no-deadline", RtPriority.Normal, 0, 0);
  try(assert_true(!task_is_expired(&t2, 9999), "is_expired: deadline=0 -> never expires"));
  return Ok(Unit);
}

fn test_task_cmp_priority() -> Result[Unit, Str] {
  var high = task_new("h", "high", RtPriority.High, 1000, 0);
  var low = task_new("l", "low", RtPriority.Low, 1000, 0);

  try(assert_int_eq(task_cmp_priority(&high, &high), 0, "cmp: same priority = 0"));
  try(assert_true(task_cmp_priority(&high, &low) < 0, "cmp: high vs low -> high first"));
  try(assert_true(task_cmp_priority(&low, &high) > 0, "cmp: low vs high -> low later"));
  return Ok(Unit);
}

fn test_scheduler_new() -> Result[Unit, Str] {
  var s = scheduler_new(4);
  try(assert_int_eq(s.tasks.len(), 0, "scheduler_new: empty tasks"));
  try(assert_int_eq(s.max_concurrent, 4, "scheduler_new: max_concurrent=4"));
  try(assert_int_eq(s.running_count, 0, "scheduler_new: running=0"));
  try(assert_int_eq(s.stats.total_scheduled, 0, "scheduler_new: stats zero"));
  return Ok(Unit);
}

fn test_scheduler_add_and_sort() -> Result[Unit, Str] {
  var s = scheduler_new(3);
  var t1 = task_new("a", "low-job", RtPriority.Low, 1000, 0);
  var t2 = task_new("b", "critical-job", RtPriority.Critical, 500, 0);
  var t3 = task_new("c", "normal-job", RtPriority.Normal, 2000, 0);

  scheduler_add_task(&mut s, t1);
  scheduler_add_task(&mut s, t2);
  scheduler_add_task(&mut s, t3);

  try(assert_int_eq(scheduler_task_count(&s), 3, "add: task count=3"));
  try(assert_int_eq(scheduler_pending_count(&s), 3, "all pending"));
  try(assert_int_eq(s.stats.total_scheduled, 3, "stats: total_scheduled=3"));

  scheduler_set_now(&mut s, 0);
  var result = scheduler_tick(&mut s);

  try(assert_int_eq(result.executed.len(), 3, "tick: 3 executed"));
  try(assert_str_eq(result.executed[0], "b", "tick: Critical first"));
  try(assert_str_eq(result.executed[1], "c", "tick: Normal second"));
  try(assert_str_eq(result.executed[2], "a", "tick: Low last"));
  return Ok(Unit);
}

fn test_scheduler_tick_executes() -> Result[Unit, Str] {
  var s = scheduler_new(2);
  var t1 = task_new("x1", "task1", RtPriority.High, 1000, 0);
  var t2 = task_new("x2", "task2", RtPriority.Normal, 1000, 0);
  var t3 = task_new("x3", "task3", RtPriority.Low, 1000, 0);
  scheduler_add_task(&mut s, t1);
  scheduler_add_task(&mut s, t2);
  scheduler_add_task(&mut s, t3);

  scheduler_set_now(&mut s, 0);
  var r = scheduler_tick(&mut s);

  try(assert_int_eq(r.executed.len(), 2, "tick_limit: 2 executed (max_concurrent=2)"));
  try(assert_int_eq(r.deferred.len(), 1, "tick_limit: 1 deferred"));
  try(assert_int_eq(s.running_count, 2, "tick_limit: running_count=2"));
  return Ok(Unit);
}

fn test_scheduler_complete_task() -> Result[Unit, Str] {
  var s = scheduler_new(1);
  var t = task_new("c1", "completable", RtPriority.Normal, 1000, 0);
  scheduler_add_task(&mut s, t);
  scheduler_set_now(&mut s, 0);
  var _r = scheduler_tick(&mut s);

  var ok = scheduler_complete_task(&mut s, "c1");
  try(assert_true(ok, "complete: returned true"));
  try(assert_int_eq(s.running_count, 0, "complete: running_count=0"));
  try(assert_int_eq(s.stats.total_completed, 1, "complete: stats.total_completed=1"));

  var task = scheduler_find_task(&s, "c1");
  match task {
    Some(found) => {
      match found.state {
        RtTaskState.Completed => {},
        _ => { return Err("FAIL: complete: state not Completed"); },
      };
    },
    None => { return Err("FAIL: complete: task not found"); },
  };
  return Ok(Unit);
}

fn test_scheduler_fail_task() -> Result[Unit, Str] {
  var s = scheduler_new(1);
  var t = task_new("f1", "flaky", RtPriority.Normal, 1000, 0);
  scheduler_add_task(&mut s, t);
  scheduler_set_now(&mut s, 0);
  var _r = scheduler_tick(&mut s);

  var ok = scheduler_fail_task(&mut s, "f1");
  try(assert_true(ok, "fail: returned true"));

  var task = scheduler_find_task(&s, "f1");
  match task {
    Some(found) => {
      try(assert_int_eq(found.retry_count, 1, "fail: retry_count=1"));
      match found.state {
        RtTaskState.Pending => {},
        _ => { return Err("FAIL: fail: should be Pending for retry"); },
      };
    },
    None => { return Err("FAIL: fail: task not found"); },
  };
  return Ok(Unit);
}

fn test_scheduler_state_counts() -> Result[Unit, Str] {
  var s = scheduler_new(3);
  scheduler_add_task(&mut s, task_new("s1", "a", RtPriority.Normal, 1000, 100));
  scheduler_add_task(&mut s, task_new("s2", "b", RtPriority.Normal, 1000, 100));
  scheduler_add_task(&mut s, task_new("s3", "c", RtPriority.Normal, 1000, 100));

  scheduler_set_now(&mut s, 200);
  var _r = scheduler_tick(&mut s);

  var counts = scheduler_state_counts(&s);
  try(assert_int_eq(counts.1, 3, "counts: running=3"));

  var _ok = scheduler_complete_task(&mut s, "s1");
  var _ok2 = scheduler_fail_task(&mut s, "s2");
  scheduler_fail_task(&mut s, "s2");
  scheduler_fail_task(&mut s, "s2");
  var _ok3 = scheduler_fail_task(&mut s, "s2");

  var counts2 = scheduler_state_counts(&s);
  try(assert_int_eq(counts2.2, 1, "counts: completed=1"));
  try(assert_int_eq(counts2.3, 1, "counts: failed=1"));

  return Ok(Unit);
}

fn try(res: Result[Unit, Str]) {
  match res {
    Ok(_) => {},
    Err(e) => { io.println(e); },
  };
}
