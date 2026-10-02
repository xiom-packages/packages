<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.ansible

> **Status:** `incubating` -- conformance-tested (26/26); published at `v0.1.0` on the XIOM registry.
> **Scope:** the semantic core of an Ansible-like configuration-management
> tool as a pure, deterministic value machine: inventory (hosts, groups,
> children, group/host vars with documented precedence), playbooks (plays,
> blocks, tasks, handlers), a documented module registry with explicit case
> dispatch, tag/limit filtering, typed facts with aggregation, handler
> notification dedup/order and changed/ok/failed/skipped result accounting
> under linear and free strategies.
> **Deps:** `xiom.std` (manifest only); the library imports `xiom.string`,
> `xiom.convert` and `xiom.string.compare` from it, the tests additionally
> use `xiom.test` and `xiom.io`.

## What it is

`xiom.ansible` models configuration management as plain values and free
functions. There is no SSH, no network, no subprocess, no clock and no I/O:
simulated modules return one of four result codes from their name and argument
text, and the executor applies the documented ordering rules. The model is
deterministic -- the same inventory, playbook, facts and filters always produce
the same `RunReport` -- so it can be conformance-tested exactly, and a real
backend (SSH, containers, agents) can implement the same semantics behind the
same shapes later.

The package owns:

- **Inventory** -- hosts and groups in declaration order, direct membership
  edges, a parent/child group hierarchy (cycles are refused), and group/host
  variables with replace-in-place semantics.
- **Playbooks** -- plays with a target pattern and a strategy, blocks with
  cascading tags, tasks with module/args/tags/notify, and named handlers.
- **Module registry** -- 12 documented builtins (`ping`, `debug`, `fail`,
  `command`, `shell`, `copy`, `template`, `file`, `package`, `service`,
  `user`, `setup`) dispatched by an explicit if/else chain, never a table of
  function values.
- **Facts** -- a typed (Str/Int/Bool) store keyed by (scope, key) with
  scope-aware aggregation; `setup` tasks gather facts for each target host.
- **Filters** -- comma-tag filtering (`always`/`never`/`all` rules) and a
  host/group limit pattern.
- **Handler queue** -- notifications dedup per (handler, host) pair, trigger
  order = first notification, handlers run at the end of the play.
- **Executor + report** -- linear (task-major) and free (host-major)
  strategies, a full execution trace and changed/ok/failed/skipped counters.

## Inventory variable precedence

Lowest to highest:

1. group vars on the implicit `all` group (may be set without registering it);
2. group vars of root groups (depth 0), later declared group wins on ties;
3. group vars of deeper groups (a child group overrides its parents);
4. host vars (always win).

Within one (group, key) or (host, key) pair the last assignment wins. A host
is considered a member of every ancestor of its direct groups, and of `all`.

## Module simulation

| Module | Rule |
|---|---|
| `ping`, `debug` | always `ok` (never changed) |
| `fail` | always `failed` |
| unknown | `failed` |
| all others | literal flags `failed=1`, then `skip=1`, then `changed=1`; fallback `ok` |

`setup` always returns `ok` and additionally writes four typed facts for the
executing host: `ansible_host_name` (Str), `ansible_distribution` (Str, from
the `ansible_distribution` variable or `"unknown"`), `ansible_cpu_count`
(Int, parsed or 0) and `ansible_gathered` (Bool).

## Execution model

A play resolves its target hosts (pattern + limit) in inventory declaration
order. A task runs when the tag filter selects it; `never` excludes a task
unless requested, `always` selects it whenever the filter is active, an empty
or `all` request runs every non-`never` task. Filtered tasks produce no result
line and are counted in `filtered`.

- `ANSIBLE_STRATEGY_LINEAR` -- for each task, every target host.
- `ANSIBLE_STRATEGY_FREE` -- for each host, every task.

A `failed` result marks that host failed for the rest of the play; its later
tasks are recorded as `skipped`. Handler notifications are play-global and
deduplicated per (handler, host); after the tasks, each queued handler runs in
first-notification order once per notifying, non-failed host.

## API (highlights)

| Function | Returns | Description |
|---|---|---|
| `inventory_new()` | `Inventory` | Empty inventory. |
| `inventory_add_host/group(&mut inv, name)` | `Result[Int, Str]` | Register; duplicates refused. |
| `inventory_add_host_to_group(&mut inv, host, group)` | `Result[Int, Str]` | Direct membership edge. |
| `inventory_add_group_child(&mut inv, parent, child)` | `Result[Int, Str]` | Hierarchy edge; cycles refused. |
| `inventory_set_group_var / set_host_var` | `Result[Int, Str]` | Set/replace a variable. |
| `inventory_var(inv, host, key)` | `Result[Str, Str]` | Precedence-resolved variable. |
| `inventory_var_or(inv, host, key, fallback)` | `Str` | Variable with fallback. |
| `inventory_target_hosts(inv, pattern)` | `Vec[Str]` | Pattern -> hosts. |
| `inventory_validate(inv)` | `Result[Int, Str]` | Structural edge check. |
| `module_kind(name)` / `module_is_known(name)` | `Int` / `Bool` | Registry dispatch. |
| `module_names()` / `module_count()` | `Vec[Str]` / `Int` | Documented builtin set. |
| `module_simulate(name, args)` | `Int` | Deterministic result code. |
| `playbook_new()` | `Playbook` | Empty playbook. |
| `playbook_add_play(&mut pb, name, hosts, strategy)` | `Result[Int, Str]` | Add a play. |
| `playbook_add_block(&mut pb, play, name, tags)` | `Result[Int, Str]` | Add a tagged block. |
| `playbook_add_task(&mut pb, play, block, name, module, args, tags, notify)` | `Result[Int, Str]` | Add a task. |
| `playbook_add_handler(&mut pb, play, name, module, args)` | `Result[Int, Str]` | Add a handler. |
| `playbook_validate(&mut pb)` | `Result[Int, Str]` | Modules + notify references. |
| `ansible_tags_match(requested, play, block, task)` | `Bool` | Tag-filter decision. |
| `facts_set_str/int/bool(&mut fs, scope, key, v)` | `Result[Int, Str]` | Typed set/replace. |
| `facts_get_str/int/bool(fs, scope, key)` | `Result[_, Str]` | Typed get with mismatch errors. |
| `facts_sum_int(fs, scope, prefix)` | `Int` | Aggregate Int facts. |
| `facts_count_str(fs, key, value)` | `Int` | Count a Str value across scopes. |
| `run_playbook(&mut pb, inv, &mut fs, tags, limit)` | `Result[RunReport, Str]` | Execute. |
| `report_*` accessors + `report_trace_text` | | Trace, counters, handlers. |

## Guarantees

- **Pure and deterministic** -- no FFI, no threads, no clock, no network, no
  global mutable state; every operation is a total function over values.
- **Bounded** -- documented capacity caps for hosts, groups, edges, plays,
  blocks, tasks, handlers, facts and trace lines; recursion is depth-budgeted.
- **No silent failures** -- every builder returns `Result` with a stable
  `"ansible: ..."` message; the executor refuses invalid playbooks.
- **No memory-unsafe constructs** -- free functions only, no `unsafe`, no
  `Vec[StructType]`, no `Vec[Float64]`.

## Conformance

`tests/test_conformance.xi` (module `ansible_tests`) runs 26 checks covering
inventory construction and errors, hierarchy/closure/cycles, target patterns,
variable precedence, the registry, simulation rules, playbook construction and
validation, tag/limit filtering, both strategies, handler dedup/order, result
accounting, failure short-circuit and typed facts/aggregation/setup. Run it
with:

```powershell
& .\scripts\port.ps1 -Package xiom-ansible -TimeoutSec 60
```

The expected gate line is `port: PASS (passed=26 failed=0 program_exit=0)`.
