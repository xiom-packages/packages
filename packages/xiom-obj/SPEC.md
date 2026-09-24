# xiom.obj -- Specification

Version: 0.1.0 (incubating, not published).
Module: `xiom.obj` (`src/obj.xi`). Pure XIOM, no FFI.

## 1. Scope

A parser for the geometry subset of the Wavefront OBJ text format:

- `v x y z` records produce vertices whose coordinates are scaled to integers
  (`trunc(value * scale)`, truncation toward zero),
- `f i j k...` records produce polygon faces whose references are resolved to
  0-based vertex indices at the time the face line is read,
- read-only accessors for vertex/face counts, vertex coordinates, face length
  and packed face indices.

The input is a `Str` treated as a byte buffer; the output is an `ObjMesh`
holding only `Vec[Int]`s. `ObjMesh` is a struct of six parallel vectors
because this compiler (v0.61.3) cannot hold `Vec[StructType]`.

## 2. Non-goals

- No texture coordinates, normals or free-form geometry (`vt`, `vn`, `vp`,
  `curv`, `surf`, ...): those records are ignored (or rejected when unknown),
  never exposed.
- No groups, object names, smoothing groups, material libraries or material
  uses: `g`, `o`, `s`, `usemtl`, `mtllib` are ignored.
- No triangulation: a polygon keeps its original vertex count.
- No writer/serializer, no file I/O, no streaming API, no error recovery (the
  first bad line aborts the parse).
- No floating point: `Float64` is unsupported by this compiler, so the decimal
  parser produces scaled `Int`s directly.
- No OBJ index warnings/recovery beyond the range check (no clamping, no
  "index 0 means 1" interpretation).

## 3. Line and record grammar

Informal grammar (`ws` is space or TAB; `comment` is `#` followed by any bytes
up to end of line; lines end at LF, and a CR immediately before the LF is
dropped):

```
document = *line
line     = ws* ( record | comment )? ws*
record   = vertex | face | ignored
vertex   = "v" ws+ number ws+ number ws+ number extra*
face     = "f" ws+ ref ws+ ref ws+ ref ref*
ignored  = ("vt" | "vn" | "vp" | "g" | "o" | "s" | "usemtl" | "mtllib") rest*
extra    = any token                          ; w, vertex colors, ... ignored
```

Decisions (each one is covered by the conformance suite):

1. **Supported records.** Only `v` and `f` carry data. Any other first token is
   an unknown record and fails the parse, except the ignored keywords listed
   above (their payload is never validated).
2. **Tokens.** A record is split on runs of space/TAB; every other byte is
   token data. `#` starts a comment anywhere on a line, so the rest of the
   line after `#` is not parsed (this also removes inline comments).
3. **Lines.** LF terminates a line; one CR immediately before the LF is
   dropped. A bare CR is ordinary data. The final line needs no terminator.
   Blank and whitespace-only lines are ignored.
4. **Vertices.** `v` needs at least three tokens after the keyword. `x`, `y`
   and `z` must parse as numbers (section 4); every token after `z` is ignored
   (this covers the optional `w` and vertex-color extensions). A missing or
   malformed coordinate fails the whole parse.
5. **Faces.** `f` needs at least three reference tokens. Every token after the
   keyword must be a well-formed reference (section 5); there is no upper
   limit, so an n-gon of any arity is one face. Repeated references are allowed
   (no degeneracy check).
6. **Case.** Keywords are case-sensitive: `V` is an unknown record.
7. **Errors stop the parse.** The first failing line is reported; no partial
   mesh is returned.

## 4. Number grammar, scaling and truncation

```
number  = sign? int-digits? ( "." frac-digits? )?    ; at least one digit
sign    = "+" | "-" | ""
```

A number is accepted when it has at most **12 integer digits** and at most
**9 fraction digits** and at least one digit overall. `.5` (empty integer
part), `5.` (empty fraction part) and leading zeros (`007.50`) are accepted.
Anything else -- a second dot, an exponent (`1e3`), a letter, or digit counts
over the limits -- makes the enclosing vertex malformed.

The exact value `v = sign * (I + F / 10^f)` (with `I` the integer part, `F` the
fraction digits and `f` their count) is converted to

```
scaled = sign * (I * scale + (F * scale) / 10^f)
```

where `/` is integer division on the non-negative magnitude. Because the
magnitude is computed first and the sign applied afterwards, the result is
`trunc(v * scale)` **toward zero** (symmetric about zero). Examples:

| Token | scale | Result | Note |
|---|---|---|---|
| `1` | 1000 | 1000 | integer part only |
| `1.5` | 1000 | 1500 | exact |
| `-6.25` | 1000 | -6250 | sign applied after truncation |
| `0.0001` | 1000 | 0 | fraction below one unit |
| `-0.001` | 1000 | -1 | truncation toward zero |
| `1.9999` | 1000 | 1999 | fraction truncated, not rounded |
| `-2.9` | 1 | -2 | scale 1 |
| `0.5` | 1 | 0 | scale 1 |

`scale` itself must be in `1..=1000000`; anything else fails with
`Err("obj: scale out of range")` before any line is read. The digit limits keep
`I * scale` and `F * scale` inside `Int64` for every accepted scale
(`10^12 * 10^6 + 10^9 * 10^6` < `2^63`), so the computation never overflows.

## 5. Face references and index resolution

```
ref = n | n "/" t | n "//" nrm | n "/" t "/" nrm
n   = sign? digits
t   = sign? digits
nrm = sign? digits
```

Each of `n`, `t` and `nrm` is an optional sign plus 1..9 digits; the texture
(`t`) and normal (`nrm`) parts are parsed for well-formedness and then
discarded. Malformed forms include `1/`, `1//`, `1/2/`, `1/2/3/4`, `1/x` and a
reference with a 10-digit part.

Resolution of `n` happens when the face line is read, against `vcount`, the
number of vertices defined **before** that line:

- `n > 0`: 0-based index = `n - 1`.
- `n < 0`: 0-based index = `vcount + n` (OBJ relative indexing: `-1` is the
  most recent vertex).
- The resolved index must satisfy `0 <= index < vcount`, otherwise the parse
  fails with `Err("obj: index out of range at line N")`. In particular `n = 0`
  is always out of range (`0 - 1 = -1`), and `n = -vcount - 1` resolves below
  zero.
- References to vertices defined later in the document are out of range; a
  face may only reference vertices that precede it.

Stored indices are always 0-based and always in range, which makes `-1` a safe
"out of range" sentinel for `obj_face_index`.

## 6. Mesh representation

```xi
pub type ObjMesh = {
  xs: Vec[Int];
  ys: Vec[Int];
  zs: Vec[Int];
  face_starts: Vec[Int];
  face_ends: Vec[Int];
  face_indices: Vec[Int];
}
```

- Vertex `i` is `(xs[i], ys[i], zs[i])`; the three vectors have one entry per
  accepted `v` record, in source order.
- Face `f` owns the half-open range
  `face_indices[face_starts[f] .. face_ends[f]]`; entries are 0-based vertex
  indices in the face's original order (no triangulation).
- Faces are stored in source order; `face_count == face_starts.len()`.

## 7. Error catalog

| Message | Condition | Reported |
|---|---|---|
| `obj: scale out of range` | `scale < 1` or `scale > 1000000` (checked before parsing) | no line |
| `obj: malformed vertex at line N` | `v` with fewer than three coordinates, or a coordinate that is not an accepted number (section 4) | the vertex line |
| `obj: malformed face at line N` | `f` with fewer than three references, or a reference outside the section-5 grammar | the face line |
| `obj: index out of range at line N` | a well-formed reference resolves to an index outside `0..vcount` at face-read time | the face line |
| `obj: unknown record at line N` | the first token is neither `v`, `f` nor one of the ignored keywords | the record line |

`N` is the 1-based **physical** line number in the input; blank lines and
comment lines count. Messages are built as `"obj: " + text + " at line " +
int_to_string(N)` with `xiom.convert.int_to_string`. Parsing stops at the first
error and the partial mesh is discarded.

## 8. API signatures

```xi
pub type ObjMesh = { ... }                       // section 6

pub fn obj_parse(text: Str, scale: Int) -> Result[ObjMesh, Str]
pub fn obj_vertex_count(m: &ObjMesh) -> Int
pub fn obj_face_count(m: &ObjMesh) -> Int
pub fn obj_vertex_x(m: &ObjMesh, i: Int) -> Int
pub fn obj_vertex_y(m: &ObjMesh, i: Int) -> Int
pub fn obj_vertex_z(m: &ObjMesh, i: Int) -> Int
pub fn obj_face_len(m: &ObjMesh, f: Int) -> Int
pub fn obj_face_index(m: &ObjMesh, f: Int, j: Int) -> Int
```

Accessor defaults: `obj_vertex_x/y/z` return `0` for `i < 0` or
`i >= vertex_count`; `obj_face_len` returns `0` for `f < 0` or
`f >= face_count`; `obj_face_index` returns `-1` for `f < 0`,
`f >= face_count`, `j < 0` or `j >= face_len`. A mesh cannot contain an index
of `-1`, so the sentinel is unambiguous.

Complexity: `obj_parse` is O(text bytes) with one tokenization pass per line and
constant work per token (the keyword dispatcher performs at most ten
`str_compare`s per line); the accessors are O(1). Memory is O(vertices + face
references).

## 9. Test plan

`tests/test_conformance.xi` (module `obj_tests`) runs 23 named checks through
`assert(cond, "name")`, one `fn` per check, and `main` returns the failure
count (0 = green). Coverage map:

| # | Check | Semantics pinned |
|---|---|---|
| t1 | integers + decimals at scale 1000 | scaling of `v` coordinates (section 4) |
| t2 | exact truncation toward zero | below-unit fractions, `1.9999` -> 1999, `-0.001` -> -1 |
| t3 | signs, optional w, extra tokens | `+` sign, ignored `w` and color tokens |
| t4 | triangle kept as-is | `f 1 2 3` -> one face of length 3 |
| t5 | quad kept as-is | no triangulation: `f 1 2 4 3` stays length 4 |
| t6 | index forms | `n/t`, `n//n`, `n/t/n` all resolve identically |
| t7 | negative indices | `-k` relative to the current vertex count |
| t8 | comments + ignored records | `vt vn vp g o s usemtl mtllib`, blank and inline comments |
| t9 | CRLF | CR before LF is dropped, values unchanged |
| t10 | empty input | `""`, whitespace-only and comment-only yield an empty mesh; accessor defaults |
| t11 | malformed vertices | missing/z-failure, `1x`, double dot, exponent, 13 int digits, 10 frac digits, line numbers |
| t12 | malformed faces | fewer than 3 refs, `x`, `3/`, `3//`, `3/1/2/3` |
| t13 | range errors | index `0`, `count + 1`, negative beyond the first vertex, textured variant |
| t14 | earlier vertices only | a face before its vertices fails; later vertices do not change `-k` |
| t15 | accessor ranges | `0` / `-1` defaults and valid reads for every accessor |
| t16 | scale 1 | fractional coordinates truncate toward zero |
| t17 | 2x2 quad fixture | the README fixture pinned end to end |
| t18 | multiple faces | shared vertices and correct per-face ranges |
| t19 | unknown records | `l`, `p`, `V` rejected with line numbers |
| t20 | scale range | `0`, negative and `1000001` fail; `1` and `1000000` pass |
| t21 | physical line numbers | blank and comment lines count in error messages |
| t22 | mixed forms on one polygon | `1/1/1 2//2 3/3 4` -> indices 0,1,2,3 |
| t23 | numeric shapes | leading zeros, `+.5`, `-.5`, `5.` accepted |

Element comparisons use `xiom.string.compare`'s `str_compare`, never `==`
(BUG 17: `==` on `Str` values read from `Vec[Str]` elements lowers to a
pointer comparison); the helpers `err_is`, `vertex_is`, `face3_is` and
`face4_is` compare whole results field by field.

## 10. Compiler / stdlib notes

XIOM v0.61.3 workarounds used (same shape as the other ported packages):

- Free functions only; no methods on `ObjMesh`.
- No `Vec[StructType]`, no `Vec[fn]` and no `Float64` vectors: the mesh is six
  parallel `Vec[Int]`s and coordinates are parsed into `Int` directly.
- `Ok`/`Err` construction for `Result[ObjMesh, Str]` lives only in the leaf
  helpers `_obj_ok_mesh` / `_obj_err_mesh`; private helpers return `""` for
  success or the error message.
- `Str` keyword comparisons go through
  `xiom.string.compare.str_compare` (BUG 17: `==` on `Vec[Str]` elements is a
  pointer comparison).
- Bytes are read as `(string.byte_at(s, i) as Int) & 0xFF` and compared in the
  `Int` domain.
- All `Vec` element reads are bound with an explicit type (`let v: Int = ...`,
  `let tok: Str = ...`).
- `Option[Int]` is returned by the number and reference parsers; every `match`
  is exhaustive and ends with a fallback return.

## 11. Known limitations

- Ignored records are never validated (a malformed `vt`/`vn` line passes), and
  unknown records are hard errors rather than warnings.
- Texture and normal indices are discarded after validation; no `vt`/`vn`
  storage.
- No triangulation, no curves/surfaces, no writer, no streaming.
- Coordinates are integer-only with the section-4 digit limits; values beyond
  them are rejected instead of clamped or rounded.
- A `#` byte anywhere starts a comment (there is no escaping), and the input is
  treated as bytes, so a UTF-8 BOM is not stripped.
- The whole document is parsed in one pass into memory.
