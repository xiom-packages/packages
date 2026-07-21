# xiom-realtime ROADMAP

## v0.1.0 (Current)
- [x] Priority system (RtPriority enum: Critical, High, Normal, Low, Background)
- [x] Task type (RtTask with id, name, priority, deadline, state, retry tracking)
- [x] Task state machine (Pending → Running → Completed/Failed/Skipped)
- [x] Scheduler type (RtScheduler with max_concurrent, task queue, stats)
- [x] Priority-based bubble sort (scheduler_sort_pending using task_cmp_priority)
- [x] Tick execution (scheduler_tick: sort by priority, execute up to max_concurrent)
- [x] Deadline enforcement (task_is_expired — expires tasks past their deadline)
- [x] Task completion (scheduler_complete_task: Running → Completed)
- [x] Task failure with retry (scheduler_fail_task: Running → Pending up to max_retries, then Failed)
- [x] Scheduler stats (total_scheduled, total_completed, total_failed, total_skipped)
- [x] Task query (scheduler_find_task, scheduler_state_counts, scheduler_is_idle)
- [x] Pure XIOM — no extern dependencies
- [x] Conformance test suite (10 tests)

## v0.2.0 — Advanced Scheduling
- [ ] EDF (Earliest Deadline First) scheduling mode
- [ ] Rate monotonic scheduling for periodic tasks
- [ ] Task dependency graph with topological ordering
- [ ] Priority inheritance for shared resources
- [ ] Task preemption support
- [ ] Work-stealing across scheduler instances
- [ ] Scheduler pause/resume lifecycle

## v0.3.0 — Channels & Events
- [ ] Channel abstraction for communication groups
- [ ] Event type system (Durable, Ephemeral, Presence, Signal)
- [ ] Broadcast within channels
- [ ] Subscription management (subscribe → active → paused → closed)
- [ ] Event ordering with monotonic sequence numbers
- [ ] Deduplication windows
- [ ] Event expiry and TTL

## v0.4.0 — Presence & Rooms
- [ ] Room abstraction with membership rules
- [ ] Presence tracking (TTL-backed heartbeat model)
- [ ] Presence roster queries
- [ ] Join/leave state machine with contract validation
- [ ] Authorization hooks (can_join, can_send, can_subscribe)
- [ ] Role-based access control for rooms

## v0.5.0 — Distributed Realtime
- [ ] Distributed fan-out via xiom-micro
- [ ] Shard-aware event routing
- [ ] Presence reconciliation across nodes
- [ ] Offline event queue and replay
- [ ] Cursor-driven replay with retention bounds

## v1.0.0 — Production Readiness
- [ ] Full contract verification on all public functions
- [ ] WebSocket transport bridge (via xiom-websocket)
- [ ] Typing indicator signals
- [ ] Activity streams
- [ ] Chat room workflow composition
- [ ] Collaboration workflow composition
- [ ] Performance benchmarks
- [ ] Load testing suite
- [ ] Security audit
