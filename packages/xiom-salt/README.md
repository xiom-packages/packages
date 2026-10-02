# xiom.salt

> **Status:** `incubating` -- conformance-tested (28/28). Not yet published.
> **Scope:** pure-XIOM Salt remote-execution / configuration MODEL: state
> declarations (ids, state functions, names) with require / watch / onchanges
> ordering (and the `_in` inverses), top-file targeting with layered pillar
> merge precedence, minion targeting (glob, a documented regex-like subset,
> grain matches and compound `and` / `or` / `not` expressions), typed grains
> with precedence and aggregation, and an event bus with tags, deterministic
> payload framing and glob-matched reactor rules.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.str_starts_with`,
> `xiom.string.index_of`, `xiom.string.str_to_int`,
> `xiom.string.compare.str_compare`, `xiom.convert.int_to_string` and
> `xiom.convert.bool_to_string`). Tests additionally use `xiom.test` and
> `xiom.io`.

## What it is

`xiom.salt` is a pure, dependency-light model of the Salt configuration and
remote-execution pipeline for XIOM programs. It declares typed grain facts and
resolves them by precedence; it targets minions with globs, a regex subset,
grain matches and compound expressions; it evaluates a top file into an
ordered SLS list and merges pillar data by precedence and origin; it declares
states with requisites and computes a stable topological execution order; and
it simulates an SLS run into a deterministic report with applied / noop /
failed / skipped counts, watch / onchanges trigger counts and an ordered event
log. It also frames published events and dispatches them through glob-matched
reactor rules.

There is no network, no socket, no shell-out, no FFI and no file I/O. A run is
a pure function of the declared SLS and the host-supplied per-state outcome:
the same inputs always produce the same order, report and event sequence. A
host that really executes states supplies each state's outcome (failed or not,
and how many changes it reported) and uses the report to drive real execution
modules.

## Quick start

```xi
use xiom.salt;
use xiom.io;

fn main() -> Int {
  var g = salt_grains_new();
  salt_grains_set_str(&mut g, "os", "Ubuntu", "core");
  salt_grains_set_int(&mut g, "cpus", 4, "config");

  var s = salt_sls_new("web");
  salt_state_add(&mut s, "pkg", "pkg.installed", "nginx");
  salt_state_add(&mut s, "svc", "service.running", "nginx");
  salt_state_watch(&mut s, 1, "pkg");

  let r = salt_run(&s);
  match r {
    Ok(rep) => { io.println(salt_run_render(&rep)); },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

The report:

```
salt run: total=2 applied=2 noop=0 failed=0 skipped=0
watches=1 onchanges=0 changes=2
event: applied: pkg (changes=1)
event: applied: svc (changes=1)
event: watch: pkg -> svc
```

## Model in one screen

- **Grains** -- typed facts: str (0), int (1), bool (2), each with a
  precedence level: core (0) < config (1) < custom (2). A higher level always
  wins; at equal level the later write wins; a key keeps the position of its
  first insertion. Values are stored as canonical text and returned through
  typed getters (`salt_grains_get_str/int/bool`).
- **Targeting** -- `salt_glob_match` (`*`, `?`), `salt_regex_match` (a
  documented subset: `^` `$` anchors, `.`, greedy `*` `+` `?`, `\x` escapes),
  `salt_grain_match` / `salt_grain_match_regex` (`key:pattern`) and
  `salt_target_match` (compound grammar `not` > `and` > `or`, parentheses,
  terms `G@glob`, `E@regex`, `I@key:glob`, `P@key:regex` and bare globs).
- **Pillar** -- a top file maps target expressions to SLS names in declaration
  order; a pillar is key/value rows with a level (base < env < override) and
  an origin label. Merge follows the same precedence rule as grains, and the
  origin tracks the winning source.
- **States** -- each declaration is an id, a state function
  (`pkg.installed`, `service.running`, ...) and a name, plus a host-supplied
  outcome (result, changes) and requisite rows: require / watch / onchanges
  and the inverse require_in / watch_in / onchanges_in.
- **Ordering** -- requisites are ordering edges; a stable topological sort
  (lowest declaration index first) gives a pure-function run order. Cycles are
  an error; unknown target ids are an error.
- **Execution** -- a declaration executes at most once; if any prerequisite
  failed or was skipped it is skipped and failure propagates. Applied means
  result ok with changes > 0; noop means result ok with 0 changes. A watch or
  onchanges trigger fires when its source applied changes. `total == applied +
  noop + failed + skipped` always holds.
- **Events** -- published events carry a tag and insertion-ordered payload
  rows framed as `<tag>|k=v;k=v`; reactor rules glob-match tags and dispatch
  actions as `<event-index>:<action>` in event order then rule order.

`SPEC.md` carries the full semantics, error catalog and test map.

## API

| Function | Returns | Description |
|---|---|---|
| `salt_grains_new()` | `GrainSet` | Empty grain set. |
| `salt_grains_set_str/int/bool(gs, key, value, level)` | `Bool` | Set a typed fact at `core` / `config` / `custom`. |
| `salt_grains_get_str/int/bool(gs, key)` | `Option[...]` | Typed fact value. |
| `salt_grains_type(gs, key)` | `Int` | Type tag (0/1/2) or -1. |
| `salt_grains_level(gs, key)` | `Int` | Level (0/1/2) or -1. |
| `salt_grains_merge(base, overlay)` | `GrainSet` | Documented precedence merge. |
| `salt_grains_agg(gs, typ)` | `Int` | Count of facts of a type. |
| `salt_grains_render(gs)` | `Str` | Canonical typed render. |
| `salt_glob_match(pat, text)` | `Bool` | `*` / `?` glob. |
| `salt_regex_match(pat, text)` | `Bool` | Regex-like subset. |
| `salt_grain_match(gs, expr)` | `Bool` | `key:glob` grain match. |
| `salt_grain_match_regex(gs, expr)` | `Bool` | `key:regex` grain match. |
| `salt_target_match(id, gs, expr)` | `Result[Bool, Str]` | Compound targeting expression. |
| `salt_top_new()` | `Top` | Empty top file. |
| `salt_top_add(top, target_expr, sls)` | `--` | Append a top-file row. |
| `salt_top_sls(top, id, gs)` | `Result[Vec[Str], Str]` | Ordered SLS list for a minion. |
| `salt_pillar_new()` | `Pillar` | Empty pillar. |
| `salt_pillar_set(p, key, value, level, origin)` | `Bool` | Set at `base` / `env` / `override`. |
| `salt_pillar_get/level/origin(p, key)` | `Option`/`Int`/`Option` | Winning row. |
| `salt_pillar_merge(base, overlay)` | `Pillar` | Documented precedence merge. |
| `salt_pillar_render(p)` | `Str` | Canonical render. |
| `salt_sls_new(name)` | `SLS` | Empty state list. |
| `salt_state_add(sls, id, fun, name)` | `Int` | Append a declaration (defaults: ok, 1 change). |
| `salt_state_set_outcome(sls, i, result, changes)` | `Bool` | Host-supplied outcome. |
| `salt_state_require/watch/onchanges(sls, owner, target)` | `Bool` | Forward requisites. |
| `salt_state_require_in/watch_in/onchanges_in(sls, owner, target)` | `Bool` | Inverse requisites. |
| `salt_state_count/id/fun/name(sls, ...)` | `Int`/`Str` | Declaration accessors. |
| `salt_requisite_count/owner/kind/target(sls, ...)` | `Int`/`Str` | Requisite accessors. |
| `salt_run_order(sls)` | `Result[Vec[Int], Str]` | Stable topological order. |
| `salt_run(sls)` | `Result[RunReport, Str]` | Deterministic run simulation. |
| `salt_run_render(r)` | `Str` | Canonical report render. |
| `salt_eventbuf_new()` | `EventBuf` | Empty event buffer. |
| `salt_event_publish(buf, tag)` | `Int` | Publish; returns the event index. |
| `salt_event_put(buf, ev, key, value)` | `Bool` | Append a payload row. |
| `salt_event_count/tag/frame(buf, ev)` | `Int`/`Str`/`Str` | Event accessors. |
| `salt_reactor_new()` | `Reactor` | Empty reactor. |
| `salt_reactor_add(r, tag_glob, action)` | `--` | Append a rule. |
| `salt_reactor_match(r, tag)` | `Vec[Str]` | Matching actions in rule order. |
| `salt_reactor_dispatch(r, buf)` | `Vec[Str]` | `<event>:<action>` dispatch list. |

`RunReport` fields: `total`, `applied`, `noop`, `failed`, `skipped`,
`watches`, `onchanges`, `changes`, `events`; `total` always equals `applied +
noop + failed + skipped`.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom-salt -TimeoutSec 60
```

Expected tail: 28 `[PASS]` lines, `xiom.salt: all tests passed`, then
`port: PASS (passed=28 failed=0 program_exit=0 exit=0)`.

## Limitations (honest scope)

- **Model only.** State functions are names, not implementations: no package
  is installed, no service is restarted, nothing touches a machine. The host
  supplies outcomes and executes the plan the report describes.
- **No network, no sockets, no shell, no FFI, no file I/O.** Grains, tops,
  pillars, states and events are built programmatically; there is no YAML/SLS
  loader.
- **Simplified requisite semantics.** watch and onchanges share the trigger
  condition (watched state applied changes) and differ only in which counter
  they feed (mod_watch call vs plain re-run trigger); every declaration
  executes at most once and triggers never rebroadcast, so runs always
  terminate. Real Salt re-runs notified states and can cascade.
- **Regex subset only.** No character classes, groups or alternation; use
  globs or the documented subset. The empty pattern matches everything and
  unanchored patterns search.
- **No pillar nesting.** Pillar keys are flat; dotted key paths are a
  caller convention, not a tree.

## Copyright and license

Copyright (c) 2026 Eleftherios Notas and The XIOM Authors.
SPDX-License-Identifier: MIT OR Apache-2.0.
