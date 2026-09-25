# xiom.snbt -- Specification

Status: `incubating` (implemented, harness-green with compiler v0.61.3; not
published).
Manifest: `package.xi` (`xiom.snbt`, version `0.1.0`).
Module: `src/snbt.xi` (`module xiom.snbt`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.builder`,
`xiom.convert`; tests additionally use `xiom.test`, `xiom.io`,
`xiom.string.compare`).

## Scope

A pure-XIOM (no FFI) codec for SNBT, the text form of Minecraft's Named
Binary Tag data:

- compounds `{key:value,...}` with bare or quoted keys;
- lists `[value,...]` with heterogeneous elements (documented policy);
- typed arrays `[B;...]`, `[I;...]`, `[L;...]` with homogeneous, validated
  elements;
- strings, double- or single-quoted with the documented escapes, or bare;
- booleans `true` / `false`;
- integer numbers with `b`/`s`/`L` suffixes as typed, range-checked values,
  and decimal/exponent/float forms as validated text tokens;
- trailing commas accepted (single, documented);
- parsing into a flat node store (`kinds`/`texts`/`parents` plus contiguous
  child ranges, like `xiom.nbt`) -- no `Vec[StructType]`;
- accessors (root/kind, key lookup, list/array counts, typed integer, bool
  and string readers);
- a canonical emitter with a stable round-trip;
- a deterministic `Err(Str)` catalog for every failure.

## Non-goals

- Binary NBT (Java big-endian or Bedrock little-endian); that is the sibling
  package `xiom.nbt`.
- Mojang data-component syntax (`minecraft:...` component forms), UUID or
  date semantics, schemas, data-fix upgrades, or any Minecraft-version
  interpretation of values.
- Comments (SNBT has none).
- Unicode escapes (`\uXXXX`), JSON-style `\/`, `\b`, `\r`, `\f` escapes.
- A generic `Value` enum or a recursive `Vec[StructType]` tree.
- `Float64` values in the API: decimal/float forms stay as validated text
  (there is no `Vec[Float64]` in XIOM v0.61.3; see Known limitations).
- A builder API in 0.1.0: trees come from `snbt_parse`.
- Streaming/incremental parsing; input is one in-memory `Str`.

## Grammar

```
document   := ws value ws EOF
value      := compound | list | array | string | number | boolean | bare
compound   := '{' ws ( entry ( ',' ws entry )* ( ',' ws )? )? '}'
entry      := key ws ':' ws value
key        := quoted | bare
list       := '[' ws ( value ( ',' ws value )* ( ',' ws )? )? ']'
array      := '[' ws ( 'B' | 'I' | 'L' ) ';' ws
              ( array_elem ( ',' ws array_elem )* ( ',' ws )? )? ']'
array_elem := value   // must be the declared element kind, checked after parse
string     := '"' dq_chars '"' | '\'' sq_chars '\''
number     := '-'? digit+ ( '.' digit+ )? ( ('e'|'E') ('+'|'-')? digit+ )? suffix?
suffix     := 'b' | 'B' | 's' | 'S' | 'l' | 'L' | 'f' | 'F' | 'd' | 'D'
boolean    := 'true' | 'false'
bare       := bare_char+
```

- `ws` (between tokens) is space, tab, LF or CR; it is never required to be
  present (`{a:1,b:2}` and `{ a : 1 , b : 2 }` are equivalent).
- The root value may be any kind, not just a compound.
- A single trailing comma is accepted in compounds, lists and typed arrays;
  two consecutive commas are an error (`snbt: unexpected character`).
- Container nesting is capped at `SNBT_MAX_DEPTH` = 64 (the root container
  is depth 1); a 65th container is `snbt: depth exceeded`.

### Token charset rules

- **Bare keys and bare string values** use exactly the documented charset:
  `A-Z a-z 0-9 . _ + -`. A bare token must not be empty.
- A **bare key** may start with any charset byte, digits included; a bare
  key that is immediately followed by a byte outside `{ws, ':'}` is
  `snbt: bad key`, and a valid key not followed by `:` (after ws) is
  `snbt: missing colon`.
- A **bare string value** may start with a letter, `_`, `.` or `+`. A token
  starting with a digit or `-` is scanned as a number, so `1abc` is
  `snbt: bad number suffix` and `.5` is the bare string `".5"`, not a
  number. `true` / `false` are booleans; quote them to get strings.
- **Quoted keys and strings** may contain any byte except a raw control byte
  below 32 (rejected as `snbt: unexpected character`); bytes >= 128 pass
  through verbatim (UTF-8 is not validated).
- **Escapes** (identical in both quote styles): `\\` -> `\`, `\"` -> `"`,
  `\'` -> `'`, `\n` -> LF (10), `\t` -> TAB (9). Any other escape is
  `snbt: bad escape`; a backslash at end of input is also `snbt: bad
  escape`. EOF before the closing quote is `snbt: unterminated string`.
- **Typed arrays** require the uppercase type letter `B`, `I` or `L`
  immediately followed by `;` (`[B;1b]`). `[b;1b]`, `[B ;1b]` and `[B1]`
  are not typed arrays; they fail as lists (`snbt: unexpected character`).
  `[B]` is a list containing the bare string `"B"`.

### Number policy

| Form | Kind | Storage | Canonical emit |
|---|---|---|---|
| `0`, `-42` | `SNBT_KIND_INT` | Int value, signed 32-bit range | `<value>` |
| `1b`, `1B` | `SNBT_KIND_BYTE` | Int value, -128..127 | `<value>b` |
| `1s`, `1S` | `SNBT_KIND_SHORT` | Int value, -32768..32767 | `<value>s` |
| `1L`, `1l` | `SNBT_KIND_LONG` | Int value, signed 64-bit | `<value>L` |
| `1f`, `1F`, `1.5f` | `SNBT_KIND_FLOAT` | numeric body text | `<body>f` |
| `1.5`, `1e3`, `1.5d` | `SNBT_KIND_DOUBLE` | numeric body text | `<body>d` |

- Integer forms are parsed to `Int` values with an overflow guard and a
  per-kind range check (`snbt: integer out of range`). Leading zeros are
  accepted and canonicalized away (`007` -> `7`), as are `-0` -> `0`.
- The exact Int64 minimum `-9223372036854775808L` is rejected: the magnitude
  accumulator caps at `Int` max (`9223372036854775807`), so the accepted
  `L` range is `-9223372036854775807..9223372036854775807`.
- Decimal and exponent forms never lose bytes: the body (`-`, digits,
  `.`, exponent including its sign) is stored verbatim as `texts[node]` and
  re-emitted with the canonical suffix. `1e3` -> `1e3d`,
  `1.5F` -> `1.5f`, `2.0D` -> `2.0d`.
- An integer must have at least digit before/after `.`; an exponent must
  have at least one digit. `1.`, `1e`, `1e+`, `-`, `1.2.3`, `1_0` are
  `snbt: invalid number`. A byte after the numeric part that is a letter
  outside the suffix set is `snbt: bad number suffix`; a `b`/`s`/`L`
  suffix on a decimal/exponent body is also `snbt: bad number suffix`.

### Typed array rule

An `array_elem` is parsed as a normal value and then checked: its kind must
equal the declared element kind (`BYTE` for `[B;`, `INT` for `[I;`, `LONG`
for `[L;`). Any mismatch is `snbt: mixed typed array`, which covers
`[B;1,2]`, `[I;1b]`, `[L;1]`, `[B;true]` and `[I;1.5]`. An empty typed
array `[B;]` is legal and has count 0.

## Node store semantics

```xi
pub type SnbtTree = {
  kinds: Vec[Int]; texts: Vec[Str]; text_off: Vec[Int]; text_len: Vec[Int];
  key_off: Vec[Int]; key_len: Vec[Int]; parents: Vec[Int];
  child_start: Vec[Int]; child_count: Vec[Int]; order: Vec[Int];
  values: Vec[Int]; data: Vec[UInt8]; root: Int;
}
```

| Field | Meaning |
|---|---|
| `kinds` | Node kind, one of the 13 `SNBT_KIND_*` constants. |
| `texts` | Materialized text (`""` for booleans/containers). |
| `text_off`, `text_len` | Exact text bytes of the node inside `data`. |
| `key_off`, `key_len` | Key bytes inside `data` (0/0 outside a compound; an empty quoted key is also 0/0). |
| `parents` | Owning node index, -1 for the root. |
| `child_start`, `child_count`, `order` | Contiguous child range: children of a node are `order[child_start + i]`, `i < child_count`. |
| `values` | Integer/boolean payload, or a typed array's element kind; 0 otherwise. |
| `data` | Shared text/key byte buffer. |
| `root` | Root node index, -1 for an empty tree. |

Node indices are document order: the root is node 0, and a node's parent
always has a smaller index. Child order is preserved exactly (including
duplicate keys); `snbt_find_child` returns the first match. Text bytes never
contain a raw 0x00: quoted strings reject control bytes and bare tokens are
ASCII, and the materializer stops at a NUL as defense in depth.

## API signatures

All functions are free functions in module `xiom.snbt`:

```xi
pub const SNBT_KIND_STRING .. SNBT_KIND_LONG_ARRAY   // 1..13
pub const SNBT_MAX_DEPTH                             // 64

pub fn snbt_parse(input: Str) -> Result[SnbtTree, Str]
pub fn snbt_emit(tree: &SnbtTree) -> Result[Str, Str]

pub fn snbt_node_count(tree: &SnbtTree) -> Int
pub fn snbt_root(tree: &SnbtTree) -> Int
pub fn snbt_kind(tree: &SnbtTree, node: Int) -> Int
pub fn snbt_kind_name(kind: Int) -> Str
pub fn snbt_text(tree: &SnbtTree, node: Int) -> Str
pub fn snbt_key(tree: &SnbtTree, node: Int) -> Str
pub fn snbt_parent(tree: &SnbtTree, node: Int) -> Int
pub fn snbt_child_count(tree: &SnbtTree, node: Int) -> Int
pub fn snbt_child_at(tree: &SnbtTree, node: Int, index: Int) -> Int
pub fn snbt_find_child(tree: &SnbtTree, node: Int, key: Str) -> Int

pub fn snbt_list_count(tree: &SnbtTree, node: Int) -> Result[Int, Str]
pub fn snbt_list_item(tree: &SnbtTree, node: Int, index: Int) -> Result[Int, Str]
pub fn snbt_array_count(tree: &SnbtTree, node: Int) -> Result[Int, Str]
pub fn snbt_array_element_kind(tree: &SnbtTree, node: Int) -> Result[Int, Str]
pub fn snbt_get_integer(tree: &SnbtTree, node: Int) -> Result[Int, Str]
pub fn snbt_get_byte(tree: &SnbtTree, node: Int) -> Result[Int, Str]
pub fn snbt_get_short(tree: &SnbtTree, node: Int) -> Result[Int, Str]
pub fn snbt_get_int(tree: &SnbtTree, node: Int) -> Result[Int, Str]
pub fn snbt_get_long(tree: &SnbtTree, node: Int) -> Result[Int, Str]
pub fn snbt_get_bool(tree: &SnbtTree, node: Int) -> Result[Bool, Str]
pub fn snbt_get_string(tree: &SnbtTree, node: Int) -> Result[Str, Str]
```

Out-of-range navigation accessors return sentinels (`-1`, `0`, `""`) and
never fault; typed readers return `snbt: node index out of range` instead.

## Canonical emit form

`snbt_emit` is deterministic for a given tree:

- no whitespace anywhere between tokens;
- compound keys bare when every byte is in `A-Za-z0-9._+-` and non-empty,
  double-quoted (with escapes) otherwise -- so the empty quoted key emits as
  `""`;
- strings always double-quoted; `\` `"` LF and TAB escaped as
  `\\` `\"` `\n` `\t`, everything else verbatim (parse admits no other
  control bytes);
- booleans as `true`/`false`;
- integer kinds rendered from their values with the canonical suffix
  `b` / `s` / `L` (bare for int), so `007` emits `7`;
- float/double bodies verbatim with `f` / `d` appended;
- typed arrays as `[B;...]` / `[I;...]` / `[L;...]` with comma-separated
  elements; every element is re-checked against the declared kind;
- containers emitted with no trailing comma.

Round-trip guarantee: for any text `s` accepted by `snbt_parse`,
`parse(emit(parse(s)))` succeeds, and `emit` of it equals
`emit(parse(s))` byte for byte. `snbt_emit` fails only on hand-corrupted
stores: `snbt: invalid tree` for drifted parallel vectors, bad ranges,
cycles/out-of-range children, an unknown kind or an out-of-range integer
value, and `snbt: empty tree` when `root < 0`.

## Error string catalog

| Message | Raised by |
|---|---|
| `snbt: empty input` | `snbt_parse` on empty/whitespace-only input. |
| `snbt: unexpected character` | Value position with no valid value start; a wrong closer where a value/separator is expected; a raw control byte inside a quoted string. |
| `snbt: unbalanced braces` | EOF inside a compound, or `]` where a compound key/separator is expected. |
| `snbt: unbalanced brackets` | EOF inside a list/array, or `}` where a list separator is expected. |
| `snbt: missing colon` | Valid key not followed by `:` (after ws). |
| `snbt: bad key` | Empty or invalid-start key; key byte outside the bare charset and not ws/`:`; invalid quoted key escape surfaces as `snbt: bad escape`/`snbt: unterminated string`. |
| `snbt: bad escape` | Escape other than `\\ \" \' \n \t`, or trailing backslash. |
| `snbt: unterminated string` | EOF before the closing quote of a quoted string or key. |
| `snbt: invalid number` | Malformed numeric token (`-`, `1.`, `1e`, `1.2.3`, ...). |
| `snbt: bad number suffix` | Unknown suffix letter, extra bare bytes after a suffix, or `b`/`s`/`L` on a decimal/exponent body. |
| `snbt: integer out of range` | Value outside the kind's range, or magnitude overflow. |
| `snbt: mixed typed array` | Typed array element kind differs from the declared kind. |
| `snbt: depth exceeded` | 65th nested container (parse and emit). |
| `snbt: trailing tokens` | Non-whitespace text after the root value. |
| `snbt: invalid tree` | `snbt_emit` store-consistency guard. |
| `snbt: empty tree` | `snbt_emit` on a tree with `root < 0`. |
| `snbt: node index out of range` | Typed reader on a bad node index. |
| `snbt: unexpected kind N` | Typed reader on the wrong node kind. |
| `snbt: list index out of range` | `snbt_list_item` index past the end. |

## Complexity

- `snbt_parse`: O(n) over the input bytes plus O(m) node-store work and the
  O(m) `_finalize` counting sort; recursion depth <= 64.
- `snbt_emit`: O(output bytes).
- `snbt_find_child`: O(children * key length), byte-wise.
- Navigation accessors: O(1); `snbt_child_at` O(1).
- Text materialization copies bytes once per node at parse time; no
  quadratic string concatenation is used in the library (the emitter builds
  into a `Vec[UInt8]` via `xiom.string.builder`, one allocation).

## Test matrix

`tests/test_conformance.xi` (22 checks, harness-green):

| # | Check | Area |
|---|---|---|
| t1 | flat compound: kinds, values and readers | compound, 8 kinds, key/reader access |
| t2 | nested compound/list navigation | nesting, list items, parent/key |
| t3 | empty containers and empty typed arrays | `{}`, `[]`, `[B;]`, `[I;]`, `[L;]` |
| t4 | quoted keys and canonical key emission | key charset, quoting, escapes |
| t5 | string escapes decode and re-emit canonically | `\\ \" \' \n \t` |
| t6 | single-quoted strings | both quote styles, canonical quoting |
| t7 | typed arrays validate and round-trip | counts, element kinds, int boundaries |
| t8 | mixed typed arrays are rejected | error catalog |
| t9 | a single trailing comma is accepted and canonicalized away | grammar |
| t10 | structural error catalog | braces/brackets/trailing/empty |
| t11 | key and string error catalog | colon, bad key, bad escape, unterminated |
| t12 | number error catalog | suffix/invalid/range |
| t13 | number forms, canonical suffixes and normalization | all numeric forms |
| t14 | canonical emit is stable under re-parse | round-trip |
| t15 | every node kind is reachable at the root | root policy, kind names |
| t16 | container depth cap is exactly 64 | depth boundaries |
| t17 | accessor and reader error behaviour | sentinels, unexpected kind |
| t18 | bare strings, booleans and the bare charset | bare policy |
| t19 | heterogeneous lists are supported | documented list policy |
| t20 | empty quoted key and key lookup edges | key edge cases |
| t21 | integer boundary values round-trip exactly | per-kind min/max |
| t22 | whitespace between tokens is tolerated | CR/LF/tab/space |

## Known limitations

- No binary NBT, components, UUID/date semantics, schemas or comments.
- Float/double are text tokens; there is no numeric float type in the API
  and no `Vec[Float64]` (unavailable in XIOM v0.61.3).
- The exact Int64 minimum is rejected (documented above).
- Raw control bytes are rejected inside quoted strings; only the five
  documented escapes are accepted, so a string containing a literal CR or
  NUL cannot be represented (quote and use `\n`/`\t` instead).
- Duplicate compound keys are preserved and looked up first-match; the
  emitter keeps them as written.
- A single trailing comma only; comments are not supported.
- No builder API in 0.1.0: `snbt_emit` accepts only parse-consistent trees.
- In-memory only; not thread-safe; trees are value types.

## Compiler / stdlib notes for v0.61.3

- Ok/Err construction is confined to leaf helpers (`_ok_tree`/`_err_tree`,
  `_ok_bytes`/`_err_bytes`, ...); constructing `Result` values directly in
  struct-returning functions miscompiles.
- Str values read from `Vec[Str]` elements are never compared with `==` and
  never measured with `str_len` (BUG 17): text byte lengths live in the
  parallel `text_len` vector, key lookup compares `data` bytes, and
  materialized text is bound to a typed local before being returned. Tests
  compare strings with `str_compare` only.
- Every `byte_at` result widens through `(b as Int) & 0xFF`; every
  `Vec[Int]` element read is bound to a typed local (`let x: Int = v[i];`).
- Passing `&result.value` as a `&Vec[UInt8]` parameter is avoided; quoted
  strings are bound to a local first (`let bytes = qr.value;`).
- The emitter refuses trees whose parallel vectors have drifted apart
  (misalignment can cause nondeterministic access violations).
- `xiom.string.builder` (`sb_new`, `sb_push_byte`, `sb_push_str`,
  `sb_push_int`, `sb_to_str`) is used for all output construction; it never
  sees NUL bytes here.
