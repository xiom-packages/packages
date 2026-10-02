<!-- XIOM -- xiom.ansible specification -->
<!-- Copyright (c) 2026 Eleftherios Notas and The XIOM Authors -->
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->

# xiom.ansible -- Specification

Status: `incubating` (implemented, harness-green 26/26, not published).
Module: `xiom.ansible` (`src/ansible.xi`). Manifest: `package.xi` (name
`xiom.ansible`, version `0.1.0`, category `systems`). `xiom.std` is a manifest
dependency; the library module imports `xiom.string`, `xiom.convert` and
`xiom.string.compare` only.

## 1. Scope

A pure, deterministic configuration-management model -- the semantic core an
Ansible-like tool would execute over real transports:

- inventory construction (hosts, groups, membership, parent/child hierarchy)
  with explicit duplicate, unknown-reference and cycle errors;
- group/host variable storage and precedence-resolved lookup;
- target-pattern resolution (`all`, group names with descendant closure, exact
  host names) in inventory declaration order;
- playbook construction (plays, blocks, tasks, handlers) with registry and
  index validation;
- a fixed module registry with explicit case dispatch and deterministic,
  argument-driven simulation;
- tag filtering (`always`, `never`, `all`, token matching) and a host/group
  limit pattern;
- a typed fact store (Str/Int/Bool) with replacement, scope queries and
  aggregation, plus `setup`-driven fact gathering;
- handler notification with (handler, host) dedup, first-notification queue
  order and end-of-play execution;
- a deterministic executor with linear (task-major) and free (host-major)
  strategies, per-host failure short-circuit and changed/ok/failed/skipped
  accounting;
- a `RunReport` trace and accessors.

No SSH, no network, no subprocess, no clock, no I/O, no FFI, no global state.

## 2. Non-goals

- Real transport, connection plugins, privilege escalation or file transfer.
- YAML parsing or any textual playbook/inventory format: values are built
  through the API only.
- Templating (`{{ }}`), conditionals (`when`), loops, roles, includes,
  delegation, serial batches, check mode or diff mode.
- Module-specific argument semantics beyond the documented simulation flags.
- Cryptography, vaults, secrets or any I/O.
- Dynamic inventory, `host_vars/` file loading or fact caching.
- Concurrency, parallelism or timing; "free" describes deterministic
  host-major ordering, not actual concurrent execution.
- Strategy plugins, callback plugins or custom module loading.

## 3. State

```xi
pub type Inventory = {
  hosts: Vec[Str];          // host names, declaration order
  groups: Vec[Str];         // group names, declaration order (no "all")
  member_group: Vec[Str];   // edge i: group of member_host[i]
  member_host: Vec[Str];    // edge i: host of member_group[i]
  parent_group: Vec[Str];   // edge i: parent of child_group[i]
  child_group: Vec[Str];    // edge i: child of parent_group[i]
  gvar_group: Vec[Str];     // variable i: owning group name
  gvar_key: Vec[Str];       // variable i: name
  gvar_value: Vec[Str];     // variable i: value
  hvar_host: Vec[Str];      // variable i: owning host name
  hvar_key: Vec[Str];       // variable i: name
  hvar_value: Vec[Str];     // variable i: value
}

pub type FactStore = {
  scopes: Vec[Str];         // entry i: scope (usually a host name)
  keys: Vec[Str];           // entry i: fact name
  kinds: Vec[Int];          // ANSIBLE_FACT_* code
  strs: Vec[Str];           // Str payload ("" for other kinds)
  ints: Vec[Int];           // Int/Bool payload (0/1)
}

pub type Playbook = {
  play_names: Vec[Str];
  play_hosts: Vec[Str];     // target pattern per play
  play_strategy: Vec[Int];  // ANSIBLE_STRATEGY_* code
  play_tags: Vec[Str];
  block_play: Vec[Int];
  block_names: Vec[Str];
  block_tags: Vec[Str];
  task_play: Vec[Int];
  task_block: Vec[Int];     // block index or -1
  task_names: Vec[Str];
  task_module: Vec[Str];
  task_args: Vec[Str];
  task_tags: Vec[Str];
  task_notify: Vec[Str];    // handler name or ""
  handler_play: Vec[Int];
  handler_names: Vec[Str];
  handler_module: Vec[Str];
  handler_args: Vec[Str];
}

pub type RunReport = {
  play_names: Vec[Str];     // task lines, execution order
  task_names: Vec[Str];
  hosts: Vec[Str];
  modules: Vec[Str];
  results: Vec[Int];        // ANSIBLE_RESULT_* code
  trace: Vec[Str];          // "play | name | host | result"
  handler_play: Vec[Str];   // handler lines, run order
  handler_names: Vec[Str];
  handler_hosts: Vec[Str];
  handler_results: Vec[Int];
  notified: Vec[Str];       // handler trigger queue, first-notification order
  changed: Int;             // counters over task + handler lines
  ok: Int;
  failed: Int;
  skipped: Int;
  filtered: Int;            // tasks excluded by the tag filter per play
}
```

All parallel vectors are index-aligned and pushed together by the builder
functions, so they cannot skew.

## 4. Inventory semantics

- `inventory_add_host` / `inventory_add_group`: name must be non-empty and
  contain no comma, space or tab; duplicates are refused. `all` is reserved
  and may not be registered as a group; it exists implicitly.
- `inventory_add_host_to_group`: both endpoints must exist; duplicate edges
  are refused.
- `inventory_add_group_child`: both endpoints must exist; duplicate edges and
  cycles (including self-edges) are refused. The hierarchy is a DAG.
- Membership is transitive: a host belongs to a group if it has a direct edge
  or if any descendant group of that group contains it. Every host belongs to
  `all`.
- `inventory_target_hosts(pattern)` resolves in host declaration order:
  `all` -> every host; a registered group name -> hosts in its closure; a
  registered host name -> that host; `""` or anything else -> empty. A group
  name wins over a host name when both exist.
- `inventory_validate` re-checks every membership, child, group-var and
  host-var edge against the host/group lists (for hand-built values).

### 4.1 Variable precedence

`inventory_var(inv, host, key)` selects, among all groups that contain the
host plus the host's own variables:

1. host vars always win (last matching assignment);
2. otherwise the group var with the greatest depth wins, where `all` has
   depth -1, a root group 0 and a child `max(parent depth) + 1`;
3. on an equal-depth tie, the later-declared group wins;
4. within one (group, key) or (host, key) pair, `set_*_var` replaces in place,
   so the last assignment wins.

## 5. Playbook model

- `playbook_add_play(name, hosts, strategy)` requires a non-empty name and
  target pattern and a valid strategy. Play tags start as `""` and can be
  replaced with `playbook_set_play_tags`.
- `playbook_add_block(play, name, tags)` requires a valid play.
- `playbook_add_task(play, block, name, module, args, tags, notify)` requires
  a valid play, a valid same-play block (or -1), a non-empty name and a
  registered module. `notify` may be `""`; a non-empty name is validated
  against the same play by `playbook_validate`.
- `playbook_add_handler(play, name, module, args)` requires a valid play, a
  non-empty name and a registered module.
- `playbook_validate` returns `Ok(task count)` when every task module is known
  and every `notify` names a handler of the same play; otherwise the first
  `Err` in declaration order.

## 6. Module registry

The documented set is fixed, in this kind order (kind codes 1..12):

| Kind | Name | Simulation |
|---|---|---|
| 1 | `ping` | always `ok` |
| 2 | `debug` | always `ok` |
| 3 | `fail` | always `failed` |
| 4 | `command` | flags |
| 5 | `shell` | flags |
| 6 | `copy` | flags |
| 7 | `template` | flags |
| 8 | `file` | flags |
| 9 | `package` | flags |
| 10 | `service` | flags |
| 11 | `user` | flags |
| 12 | `setup` | always `ok` + gathers facts |

`module_kind` is an explicit if/else `str_compare` chain -- never a table of
function values (indexed function vectors are not used anywhere in this
package). Unknown names return kind 0. `module_simulate` checks the flags
`failed=1`, `skip=1`, `changed=1` in that order as literal substrings of the
argument text and otherwise returns `ok`; unknown modules return `failed`.

Result codes: `0` ok (unchanged), `1` changed, `2` failed, `3` skipped.

## 7. Execution model

`run_playbook(pb, inv, fs, tags, limit)` first runs `playbook_validate` and
returns its error unchanged on failure. Then, for each play in declaration
order:

1. Resolve targets: `inventory_target_hosts(play_hosts)` filtered by `limit`
   (`""` or `all` = no restriction; otherwise a host or group pattern). A play
   with no targets contributes nothing.
2. Count selected tasks under the tag filter; the rest are added to
   `filtered`.
3. Execute selected tasks in strategy order over the target hosts:
   - LINEAR: task-major -- for each task (declaration order), for each host
     (target order);
   - FREE: host-major -- for each host (target order), for each task.
4. Per task/host: a host already failed in this play records `skipped`;
   otherwise the module result is recorded and a `failed` result marks the
   host failed for the remainder of the play. A `changed` result with a
   non-empty `notify` notifies that handler for that host.
5. Run the notified handlers: for each queued handler in first-notification
   order, for each target host in order, if the (handler, host) pair was
   notified and the host has not failed, simulate the handler and record it.

The `setup` module is special-cased in the executor (not in
`module_simulate`): before recording `ok`, it writes four facts for the host
(see section 9). Handler results and task results share the same counters and
the same trace.

## 8. Tags and limits

A tag string is comma-separated with no surrounding whitespace. The effective
tags of a task are the union of its play tags, its block tags (when it belongs
to a block) and its own tags. `ansible_tags_match` decides:

1. If any source is tagged `never`, the task runs only when the requested
   filter itself contains the token `never`.
2. Otherwise, an empty request selects the task.
3. Otherwise, a task tagged `always` is selected.
4. Otherwise, a request containing `all` selects the task.
5. Otherwise the task is selected when any requested token matches any
   effective tag.

`limit` is resolved with the same pattern language as `play_hosts`; the
intersection preserves target order.

## 9. Facts

- Entries are keyed by (scope, key); `set` replaces the kind and payload in
  place (entry count grows only for new keys).
- `facts_get_str/int/bool` return `Err("ansible: fact type mismatch: s.k")`
  when the stored kind differs, and `Err("ansible: undefined fact: s.k")`
  when the entry is missing.
- `facts_sum_int(fs, scope, prefix)` sums Int facts; an empty scope means all
  scopes, an empty prefix all keys.
- `facts_count_str(fs, key, value)` counts matching Str facts across scopes.
- `facts_scope_count` counts entries in one scope.
- A `setup` task writes, for its host scope: `ansible_host_name` (Str),
  `ansible_distribution` (Str; variable `ansible_distribution` or
  `"unknown"`), `ansible_cpu_count` (Int; `ansible_cpu_count` parsed via
  `xiom.string.str_to_int`, else 0) and `ansible_gathered` (Bool true).

## 10. Report and accounting

Task lines and handler lines are appended in execution order; `trace` renders
each as `play | name | host | result`. The counters `changed`, `ok`, `failed`
and `skipped` cover task and handler lines together; `filtered` counts
tag-filtered tasks per play (not per host). Accessors exist for every vector
plus `report_result_count`, `report_trace_text`, `report_order_text`
("task@host" comma list) and `report_summary`
("changed=N ok=N failed=N skipped=N filtered=N").

## 11. Error catalog

All messages are stable and start with `ansible: `. Representative set:

| Message | Cause |
|---|---|
| `ansible: empty name` | empty name/key; or a host/group name with `,`, space or tab |
| `ansible: duplicate host: X` / `duplicate group: X` | repeated registration |
| `ansible: group name is reserved: all` | registering `all` |
| `ansible: unknown host: X` / `unknown group: X` | edge or var against a missing endpoint |
| `ansible: duplicate membership: H in G` | repeated membership edge |
| `ansible: duplicate group child: P>C` | repeated hierarchy edge |
| `ansible: group cycle: P>C` | cycle/self-edge |
| `ansible: undefined variable: K` | no host/group var for the key |
| `ansible: invalid membership edge` / `invalid group child edge` / `invalid group var edge` / `invalid host var edge` | `inventory_validate` |
| `ansible: unknown module: M` | builder/validator |
| `ansible: unknown play` / `unknown block` / `unknown handler: H` | index or notify reference |
| `ansible: invalid strategy` | strategy code not 0/1 |
| `ansible: fact type mismatch: S.K` / `undefined fact: S.K` | typed get |
| `ansible: index out of range: W` | positional accessor |
| `ansible: capacity exceeded` | a documented cap is full |
| `ansible: trace capacity exceeded` / `fact capacity exceeded` | executor caps |

## 12. Caps and complexity

Caps: 256 hosts, 128 groups, 4096 variable/membership/child edges, 64 plays,
128 blocks, 512 tasks, 128 handlers, 4096 facts, 8192 report lines. Group
containment and depth are recursive with a budget of `groups + 1`, so a
malformed or adversarial graph cannot recurse without bound; loops are bounded
by stored lengths. Variable lookup is O(groups * group-vars) per call;
execution is O(selected tasks * hosts + handlers * hosts); tag matching is
O(tokens) with a small constant.

## 13. Conformance matrix

| # | Check |
|---|---|
| 1-2 | inventory builder, duplicates, membership errors |
| 3-4 | hierarchy/closure/cycles, target patterns, validate |
| 5-6 | host-var override, group-var precedence (depth/later/last/all) |
| 7-9 | registry kinds/names, kind round-trip, simulation rules |
| 10-12 | playbook builders, error cases, validation gates executor |
| 13-15 | tag tokens/counting, tag rules, limit filtering |
| 16-18 | linear order, free order, handler dedup/order |
| 19-21 | accounting, failure short-circuit, tag filtering in a run |
| 22-24 | typed facts, aggregation, setup gathering |
| 25-26 | report accessors/trace, strategy totals consistency |

