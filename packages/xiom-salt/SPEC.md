# xiom.salt -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.salt` (`src/salt.xi`). Pure XIOM, no FFI, no network, no
sockets, no shell, no file I/O.

## 1. Scope

A pure, in-memory model of the Salt remote-execution / configuration
pipeline:

- typed grains with precedence and aggregation (`salt_grains_*`),
- minion targeting: glob (`salt_glob_match`), a documented regex-like subset
  (`salt_regex_match`), grain matches (`salt_grain_match`,
  `salt_grain_match_regex`) and compound expressions (`salt_target_match`),
- top-file targeting (`salt_top_*`) and layered pillar merge
  (`salt_pillar_*`),
- state declarations with requisites (`salt_sls_new`, `salt_state_add`,
  `salt_state_require/watch/onchanges`, `salt_state_*_in`),
- stable topological ordering and deterministic run simulation
  (`salt_run_order`, `salt_run`, `salt_run_render`),
- an event bus with tag/payload framing and glob-matched reactor rules
  (`salt_event_*`, `salt_reactor_*`).

Out of scope by design: real execution modules, YAML/SLS loading, master /
minion transport, file servers, pillar trees, beacons, returners, and every
form of network or shell access.

## 2. Data model

```xi
pub type GrainSet = {
  keys: Vec[Str]; values: Vec[Str];
  types: Vec[Int];    // 0 str, 1 int, 2 bool
  levels: Vec[Int];   // 0 core, 1 config, 2 custom
}

pub type Top = { t_target: Vec[Str]; t_sls: Vec[Str]; }

pub type Pillar = {
  keys: Vec[Str]; values: Vec[Str];
  levels: Vec[Int];   // 0 base, 1 env, 2 override
  origins: Vec[Str];
}

pub type SLS = {
  name: Str;
  ids: Vec[Str]; funs: Vec[Str]; names: Vec[Str];
  results: Vec[Int];   // 0 ok, 1 fail
  changes: Vec[Int];
  rq_owner: Vec[Int]; rq_kind: Vec[Int]; rq_target: Vec[Str];
  // kinds: 0 require, 1 watch, 2 onchanges, 3 require_in, 4 watch_in,
  //        5 onchanges_in
}

pub type RunReport = {
  total: Int; applied: Int; noop: Int; failed: Int; skipped: Int;
  watches: Int; onchanges: Int; changes: Int; events: Vec[Str];
}

pub type EventBuf = {
  tags: Vec[Str]; p_owner: Vec[Int]; p_key: Vec[Str]; p_value: Vec[Str];
}

pub type Reactor = { r_tag: Vec[Str]; r_action: Vec[Str]; }
```

`Vec[StructType]` is unusable in this compiler (v0.62.2), so every collection
is a set of index-aligned parallel vectors. Invariants enforced by the builder
API: every requisite owner names a declaration; every requisite target
resolves at run/order time; every payload row's `p_owner` names an event;
`RunReport.total == applied + noop + failed + skipped`.

## 3. Grains

A grain fact is `(key, canonical text value, type tag, level)`. Types are str
(0), int (1) and bool (2); ints and bools are stored as canonical text
(`int_to_string`, `bool_to_string`) and returned by typed getters that return
`None` when the key is absent or has another type.

Precedence levels, lowest to highest: core = 0, config = 1, custom = 2.

Per write (`_grain_put`):

1. A new key is appended; its position is the first insertion position and
   never changes.
2. An existing key is replaced when the new level is **>=** its current level.
   Equal level = later write wins; a lower level never overwrites a higher
   one, regardless of write or merge order.
3. `salt_grains_set_str/int/bool` returns false for any level name other than
   `"core"` / `"config"` / `"custom"` and stores nothing.

`salt_grains_merge(base, overlay)` copies `base` then applies `overlay` with
the same rule; neither input is modified. Applying the merge once per source
in precedence order resolves a chain.

`salt_grains_agg(gs, typ)` counts facts by type tag (aggregation).
`salt_grains_render` emits a counter header line then one
`key=value type=.. level=..` line per fact in insertion order, LF separated
with no trailing LF.

## 4. Targeting

### 4.1 Glob

`salt_glob_match(pat, text)` matches bytes: `*` matches any run (including
empty), `?` matches exactly one byte, every other byte is literal and
case-sensitive. The two-pointer backtracking algorithm is iterative and
always terminates in O(len(pat) * len(text)).

### 4.2 Regex-like subset

`salt_regex_match(pat, text)` implements a documented subset of PCRE:

| Syntax | Meaning |
|---|---|
| `^` | start anchor; only special as the first pattern byte |
| `$` | end anchor; only special as the last pattern byte |
| `.` | any one byte |
| `*` `+` `?` | greedy quantifiers on the preceding atom, with backtracking |
| `\x` | literal byte x (`\.` `\*` `\+` `\?` `\^` `\$` `\\`) |
| anything else | literal byte |

Atom = one literal byte (possibly escaped) or `.`. There are no character
classes, groups, alternation or other escapes. Matching is a search: without
`^` the pattern may match at any byte offset; the match need not consume the
whole text unless `$` requires the text end. The empty pattern matches every
text. Backtracking fails closed after 65536 steps.

### 4.3 Grain matches

`salt_grain_match(gs, "key:glob")` and
`salt_grain_match_regex(gs, "key:regex")` compare the fact's canonical text
value with the glob / regex. False when the key is absent or empty or when the
expression has no `:` (the first `:` separates key and pattern).

### 4.4 Compound expressions

`salt_target_match(minion_id, gs, expr)` implements:

```
expr    = and ( "or"  and )*
and     = not ( "and" not )*
not     = "not" not | primary
primary = "(" expr ")" | term
term    = "G@" glob          ; minion id glob
        | "E@" regex         ; minion id regex
        | "I@" key ":" glob  ; grain glob
        | "P@" key ":" regex ; grain regex
        | bare-glob          ; minion id glob
```

Precedence is `not` > `and` > `or`. `(`, `)` and whitespace separate tokens;
the whole expression is always parsed, so a malformed tail is an error even
when the head already decides the value. The keyword tokens `and`, `or` and
`not` cannot be used as bare glob terms.

## 5. Top file and pillar

A **top file** (`Top`) holds target-expression / SLS-name rows in declaration
order. `salt_top_sls(top, minion_id, gs)` returns the SLS names of every
matching row in declaration order, duplicates preserved; a malformed target
expression aborts with the targeting error.

A **pillar** (`Pillar`) holds key/value rows with a level (base = 0, env = 1,
override = 2) and an origin label. The write and merge rules are exactly the
grain rules (section 3): a new key appends; an existing key is replaced when
the new level is >= its current level; equal level = later wins; a key keeps
its first position. `salt_pillar_origin` returns the origin of the winning
assignment, so a merge chain shows which source produced each value. Applying
`salt_pillar_merge` once per top-file SLS, in top-file order, is the pillar
resolution model.

`salt_pillar_render` emits a counter header line then one
`key=value level=.. origin=..` line per key, insertion order, LF separated
with no trailing LF.

## 6. States and requisites

A declaration is `(id, state function, name)` plus a host-supplied outcome
`(result, changes)`. `salt_state_add` stores result ok / one change by
default and returns -1 without storing when the id or function is not a valid
identifier (non-empty, no byte <= space, no brackets) or the name is empty.
`salt_state_set_outcome` sets the outcome (changes clamped to >= 0 and forced
to 0 on failure).

Requisite rows:

| Builder | Kind | Meaning |
|---|---|---|
| `salt_state_require(sls, owner, target)` | 0 | `target` runs first; must end applied/noop |
| `salt_state_watch(...)` | 1 | as require; changes in `target` fire a watch trigger for `owner` |
| `salt_state_onchanges(...)` | 2 | as require; changes in `target` fire an onchanges trigger for `owner` |
| `salt_state_require_in(...)` | 3 | inverse: the named target requires `owner` |
| `salt_state_watch_in(...)` | 4 | inverse: the named target watches `owner` |
| `salt_state_onchanges_in(...)` | 5 | inverse: changes in `owner` trigger the named target |

Builders return false for an out-of-range owner or an empty target and store
nothing.

## 7. Ordering and execution model

### 7.1 Edges and order

Every requisite normalizes to one edge `(from, to, kind)` with the *_in kinds
mapped to 0/1/2:

- require / watch / onchanges on owner O with target T -> edge T -> O;
- require_in / watch_in / onchanges_in on owner O with target T -> edge O -> T.

`salt_run_order` performs a stable Kahn topological sort: repeatedly pick the
lowest declaration index with in-degree zero. Ties are therefore broken by
declaration index, so the order is a pure function of the declarations. Errors:
`salt: unknown state id: <id>` (a target that resolves to no declaration) and
`salt: requisite cycle` (a cycle or self-edge).

### 7.2 Execution

`salt_run` walks the order once. For declaration `i`:

1. If any incoming edge source ended failed or skipped, `i` is **skipped**
   (event `skipped: <id> (requisite failed: <src>)`). Skipped counts as a
   failed prerequisite, so failure propagates along the graph.
2. Otherwise the host outcome decides: result fail -> **failed** (event
   `failed: <id>`); result ok with changes > 0 -> **applied** (event
   `applied: <id> (changes=<n>)`); result ok with 0 changes -> **noop**
   (event `noop: <id>`).
3. After an executed (non-skipped, non-failed) declaration, every incoming
   watch / onchanges edge whose source is applied (changes > 0) fires one
   trigger in edge order: watch -> `watch: <src> -> <id>` and the `watches`
   counter; onchanges -> `onchanges: <src> -> <id>` and the `onchanges`
   counter.

`watch` and `onchanges` share ordering and failure semantics and differ only
in the counter / event they produce (a mod_watch call vs a plain re-run
trigger). A declaration executes at most once and triggers never rebroadcast,
so a cycle cannot recurse. `changes` accumulates the applied states' change
counts. `total == applied + noop + failed + skipped` holds at every point.

### 7.3 Report rendering

`salt_run_render` emits, LF-separated with no trailing LF:

```
salt run: total=<T> applied=<A> noop=<N> failed=<F> skipped=<S>
watches=<W> onchanges=<C> changes=<H>
event: <event>
event: <event>
...
```

The two header lines are always present; an empty SLS renders exactly those
two and no event lines.

## 8. Event bus and reactor

`salt_event_publish(buf, tag)` appends an event and returns its index;
`salt_event_put(buf, ev, key, value)` appends one payload row (false for an
out-of-range event; duplicate keys preserved). `salt_event_frame(buf, ev)`
renders the deterministic frame `<tag>|k=v;k=v` with payload rows in insertion
order and no trailing separator; an event with no payload frames as
`<tag>|` ("" for an out-of-range event).

`salt_reactor_add(reactor, tag_glob, action)` appends a rule.
`salt_reactor_match(reactor, tag)` returns the actions of every rule whose tag
glob matches, in rule order. `salt_reactor_dispatch(reactor, buf)` walks the
events in publish order and, for each, the matching rules in rule order,
returning one `<event-index>:<action>` string per match (duplicates preserved).

## 9. Error catalog

| Message | Raised by |
|---|---|
| `salt: targeting: unexpected end of expression` | compound parse |
| `salt: targeting: expected ')'` | compound parse |
| `salt: targeting: unexpected token: <token>` | compound parse |
| `salt: targeting: malformed grain term: <term>` | compound parse (`I@`/`P@` without `:`) |
| `salt: unknown state id: <id>` | run order / run / edges |
| `salt: requisite cycle` | run order / run |
| `salt: targeting: unreachable` | defensive tail (unreachable) |
| `salt: unreachable` | defensive tail (unreachable) |

Targeting functions that return a plain `Bool` (`salt_glob_match`,
`salt_regex_match`, `salt_grain_match`, `salt_grain_match_regex`) signal
"no match" with false rather than an error.

## 10. Determinism and complexity

Everything is deterministic: iteration is index order over parallel vectors;
the topological sort always picks the lowest eligible index; triggers and
events are in requisite-row order; there is no hash-ordered structure and no
time or randomness. On identical inputs the order, report counts and event
sequence are byte-identical.

Let `N` be declarations, `R` requisite rows, `G` facts and `P` pattern length.
Ordering is O(N^2 + R) (smallest-index Kahn) with O(N + R) memory. A run adds
O(N * R) prerequisite scans. Glob matching is O(len(pat) * len(text)); the
regex subset is exponential in the worst case but fails closed after 65536
steps. Merge/write scans are O(keys) per operation.

## 11. v0.62.2 compiler notes

- Free functions only; every walk is index-based over parallel vectors.
- `Result` constructors live only in the leaf helpers `_bool_ok` /
  `_bool_err`, `_strs_ok` / `_strs_err`, `_ints_ok` / `_ints_err`,
  `_runrep_ok` / `_runrep_err`, `_edge_ok` / `_edge_err`.
- All `Str` equality goes through `xiom.string.compare.str_compare` via
  `_streq` (BUG 17: `==` on `Vec[Str]` elements lowers to a pointer
  comparison).
- Every byte read is widened and masked through `_byte`
  (`(byte_at(...) as Int) & 0xFF`).
- Every vector element read is bound to a typed local first.
- No `&mut` scalar parameters; mutable state lives in structs (`GrainSet`,
  `Pillar`, `SLS`, `_Tgt`, `_Re`, `_Run`, `_Edge`).
- One module: no sibling or parent imports, so no cross-module
  `Ok`/`Err` identity issues. `"\\"` in a source string literal is one
  backslash byte (verified with a KAT probe on v0.62.2).

## 12. Conformance map (tests/test_conformance.xi, 28 checks)

| Test | Covers |
|---|---|
| t01 | grain builders, type tags, levels, typed getters |
| t02 | grain precedence core < config < custom, last-wins, first position |
| t03 | grain merge precedence, immutability, aggregation |
| t04 | canonical grain render |
| t05 | glob `*` / `?`, exact and empty patterns |
| t06 | regex literals, dot, quantifiers |
| t07 | regex anchors, search semantics, escapes |
| t08 | grain glob match and absence rules |
| t09 | grain regex match and absence rules |
| t10 | compound and/or/not precedence |
| t11 | compound parentheses |
| t12 | compound `G@` `E@` `I@` `P@` and bare terms |
| t13 | compound error catalog |
| t14 | top-file targeting order |
| t15 | top-file error propagation |
| t16 | pillar set/get/level/origin precedence |
| t17 | pillar merge precedence and first position |
| t18 | canonical pillar render |
| t19 | state/requisite builders, validation, accessors |
| t20 | stable topological order and tie-break |
| t21 | cycle and unknown-id errors |
| t22 | require failure propagation and the skip chain |
| t23 | watch trigger on change only |
| t24 | onchanges trigger on change only |
| t25 | inverse requisites (require_in / watch_in / onchanges_in) |
| t26 | canonical run render (two states and empty) |
| t27 | event publish order, framing, accessors |
| t28 | reactor glob match and dispatch order |

## 13. Version history

- 0.1.0 -- initial pure-XIOM model, 28-check conformance suite, built and run
  on compiler v0.62.2 with the `stdlib` checkout.
