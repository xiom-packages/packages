// XIOM -- Realtime Priority Scheduler (Pure XIOM, contract-protected)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// Licensed under the MIT or Apache-2.0 license, at your option.

module xiom.realtime

use xiom.string;
use xiom.convert;

// --- Types ----------------------------------------------------------------

pub enum RtPriority {
  Critical,
  High,
  Normal,
  Low,
  Background,
} derive[Clone]

pub type RtTask = {
  id: Str;
  name: Str;
  priority: RtPriority;
  deadline_ms: Int;
  created_at_ms: Int;
  state: RtTaskState;
  retry_count: Int;
  max_retries: Int;
} derive[Clone]

pub enum RtTaskState {
  Pending,
  Running,
  Completed,
  Failed,
  Skipped,
} derive[Clone]

pub type RtScheduler = {
  tasks: Vec[RtTask];
  now_ms: Int;
  max_concurrent: Int;
  running_count: Int;
  stats: RtSchedulerStats;
} derive[Clone]

pub type RtSchedulerStats = {
  total_scheduled: Int;
  total_completed: Int;
  total_failed: Int;
  total_skipped: Int;
} derive[Clone]

pub type RtScheduleResult = {
  executed: Vec[Str];
  deferred: Vec[Str];
  failed: Vec[Str];
} derive[Clone]

// --- Priority Helpers -----------------------------------------------------

pub fn priority_to_int(p: RtPriority) -> Int {
  match p {
    RtPriority.Critical => return 0,
    RtPriority.High => return 1,
    RtPriority.Normal => return 2,
    RtPriority.Low => return 3,
    RtPriority.Background => return 4,
  };
}

pub fn priority_from_int(n: Int) -> RtPriority {
  if n <= 0 { return RtPriority.Critical; };
  if n == 1 { return RtPriority.High; };
  if n == 2 { return RtPriority.Normal; };
  if n == 3 { return RtPriority.Low; };
  return RtPriority.Background;
}

pub fn priority_to_str(p: RtPriority) -> Str {
  match p {
    RtPriority.Critical => return "Critical",
    RtPriority.High => return "High",
    RtPriority.Normal => return "Normal",
    RtPriority.Low => return "Low",
    RtPriority.Background => return "Background",
  };
}

// --- Task Builder ---------------------------------------------------------

pub fn task_new(id: Str, name: Str, priority: RtPriority, deadline_ms: Int, now_ms: Int) -> RtTask
  requires: string.str_len(id) > 0
  requires: deadline_ms >= 0
{
  return RtTask{
    id: id,
    name: name,
    priority: priority,
    deadline_ms: deadline_ms,
    created_at_ms: now_ms,
    state: RtTaskState.Pending,
    retry_count: 0,
    max_retries: 3,
  };
}

pub fn task_is_pending(task: &RtTask) -> Bool {
  match task.state {
    RtTaskState.Pending => return true,
    _ => return false,
  };
}

pub fn task_is_expired(task: &RtTask, now_ms: Int) -> Bool {
  return task.deadline_ms > 0 && now_ms > task.created_at_ms + task.deadline_ms;
}

pub fn task_can_retry(task: &RtTask) -> Bool {
  return task.retry_count < task.max_retries;
}

// --- Task Comparator ------------------------------------------------------

pub fn task_cmp_priority(a: &RtTask, b: &RtTask) -> Int {
  var pa: Int = priority_to_int(a.priority);
  var pb: Int = priority_to_int(b.priority);
  if pa < pb { return -1; };
  if pa > pb { return 1; };
  return 0;
}

// --- Scheduler Builder ----------------------------------------------------

pub fn scheduler_new(max_concurrent: Int) -> RtScheduler
  requires: max_concurrent >= 0
{
  return RtScheduler{
    tasks: Vec[RtTask].new(),
    now_ms: 0,
    max_concurrent: max_concurrent,
    running_count: 0,
    stats: RtSchedulerStats{
      total_scheduled: 0,
      total_completed: 0,
      total_failed: 0,
      total_skipped: 0,
    },
  };
}

pub fn scheduler_add_task(sched: &mut RtScheduler, task: RtTask) {
  sched.tasks.push(task);
  sched.stats.total_scheduled = sched.stats.total_scheduled + 1;
}

pub fn scheduler_task_count(sched: &RtScheduler) -> Int {
  return sched.tasks.len();
}

pub fn scheduler_pending_count(sched: &RtScheduler) -> Int {
  var count: Int = 0;
  var i: Int = 0;
  while i < sched.tasks.len() {
    if task_is_pending(&sched.tasks[i]) {
      count = count + 1;
    };
    i = i + 1;
  };
  return count;
}

pub fn scheduler_set_now(sched: &mut RtScheduler, ms: Int) {
  sched.now_ms = ms;
}

// --- Priority-Based Sort --------------------------------------------------

fn scheduler_sort_pending(sched: &mut RtScheduler) {
  var n: Int = sched.tasks.len();
  if n <= 1 { return; };

  var i: Int = 0;
  while i < n - 1 {
    var j: Int = 0;
    while j < n - i - 1 {
      var cmp: Int = task_cmp_priority(&sched.tasks[j], &sched.tasks[j + 1]);
      if cmp > 0 {
        var tmp: RtTask = sched.tasks[j];
        sched.tasks[j] = sched.tasks[j + 1];
        sched.tasks[j + 1] = tmp;
      };
      j = j + 1;
    };
    i = i + 1;
  };
}

// --- Tick Execution -------------------------------------------------------

pub fn scheduler_tick(sched: &mut RtScheduler) -> RtScheduleResult {
  var result = RtScheduleResult{
    executed: Vec[Str].new(),
    deferred: Vec[Str].new(),
    failed: Vec[Str].new(),
  };

  scheduler_sort_pending(sched);

  var slots: Int = sched.max_concurrent - sched.running_count;
  if slots <= 0 {
    // All slots full -- defer everything
    var i: Int = 0;
    while i < sched.tasks.len() {
      if task_is_pending(&sched.tasks[i]) {
        result.deferred.push(sched.tasks[i].id);
      };
      i = i + 1;
    };
    return result;
  };

  var i: Int = 0;
  while i < sched.tasks.len() && slots > 0 {
    var task: &mut RtTask = &mut sched.tasks[i];

    if !task_is_pending(task) {
      i = i + 1;
      continue;
    };

    if task_is_expired(task, sched.now_ms) {
      sched.tasks[i].state = RtTaskState.Skipped;
      sched.stats.total_skipped = sched.stats.total_skipped + 1;
      result.deferred.push(sched.tasks[i].id);
      i = i + 1;
      continue;
    };

    sched.tasks[i].state = RtTaskState.Running;
    sched.running_count = sched.running_count + 1;
    result.executed.push(sched.tasks[i].id);
    slots = slots - 1;
    i = i + 1;
  };

  // Mark remaining pending as deferred
  while i < sched.tasks.len() {
    if task_is_pending(&sched.tasks[i]) {
      result.deferred.push(sched.tasks[i].id);
    };
    i = i + 1;
  };

  return result;
}

// --- Task Completion ------------------------------------------------------

pub fn scheduler_complete_task(sched: &mut RtScheduler, task_id: Str) -> Bool {
  var i: Int = 0;
  while i < sched.tasks.len() {
    if sched.tasks[i].id == task_id {
      match sched.tasks[i].state {
        RtTaskState.Running => {
          sched.tasks[i].state = RtTaskState.Completed;
          sched.stats.total_completed = sched.stats.total_completed + 1;
          if sched.running_count > 0 {
            sched.running_count = sched.running_count - 1;
          };
          return true;
        },
        _ => { return false; },
      };
    };
    i = i + 1;
  };
  return false;
}

pub fn scheduler_fail_task(sched: &mut RtScheduler, task_id: Str) -> Bool {
  var i: Int = 0;
  while i < sched.tasks.len() {
    if sched.tasks[i].id == task_id {
      match sched.tasks[i].state {
        RtTaskState.Running => {
          if task_can_retry(&sched.tasks[i]) {
            sched.tasks[i].state = RtTaskState.Pending;
            sched.tasks[i].retry_count = sched.tasks[i].retry_count + 1;
          } else {
            sched.tasks[i].state = RtTaskState.Failed;
            sched.stats.total_failed = sched.stats.total_failed + 1;
          };
          if sched.running_count > 0 {
            sched.running_count = sched.running_count - 1;
          };
          return true;
        },
        _ => { return false; },
      };
    };
    i = i + 1;
  };
  return false;
}

// --- Scheduler Query ------------------------------------------------------

pub fn scheduler_find_task(sched: &RtScheduler, task_id: Str) -> Option[RtTask] {
  var i: Int = 0;
  while i < sched.tasks.len() {
    if sched.tasks[i].id == task_id {
      return Some(sched.tasks[i]);
    };
    i = i + 1;
  };
  return None;
}

pub fn scheduler_state_counts(sched: &RtScheduler) -> (Int, Int, Int, Int, Int) {
  var pending: Int = 0;
  var running: Int = 0;
  var completed: Int = 0;
  var failed: Int = 0;
  var skipped: Int = 0;
  var i: Int = 0;
  while i < sched.tasks.len() {
    match sched.tasks[i].state {
      RtTaskState.Pending => { pending = pending + 1; },
      RtTaskState.Running => { running = running + 1; },
      RtTaskState.Completed => { completed = completed + 1; },
      RtTaskState.Failed => { failed = failed + 1; },
      RtTaskState.Skipped => { skipped = skipped + 1; },
    };
    i = i + 1;
  };
  return (pending, running, completed, failed, skipped);
}

pub fn scheduler_is_idle(sched: &RtScheduler) -> Bool {
  var counts = scheduler_state_counts(sched);
  var _pend: Int = counts.0;
  var _run: Int = counts.1;
  var _comp: Int = counts.2;
  var _fail: Int = counts.3;
  var _skip: Int = counts.4;
  return counts.0 == 0 && counts.1 == 0;
}
