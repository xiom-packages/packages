# xiom.pgn

> **Status:** `incubating` -- implemented, pure XIOM (no FFI), and green under
> the repo harness. **NOT published** to the XIOM registry.
> **Scope:** a PGN (Portable Game Notation) codec for a documented subset:
> tag pairs, a flat movetext token stream (move numbers, SAN, comments, NAGs,
> results), lexical validation and canonical emit.
> **Deps:** `xiom.std >=0.60.0 <1.0.0` (uses `xiom.string.byte_at`,
> `xiom.string.str_slice`, `xiom.string.builder.sb_to_str`,
> `xiom.string.compare.str_compare` and `xiom.convert.int_to_string`). Tests
> additionally use `xiom.test` and `xiom.io`.

## What it is

`xiom.pgn` parses an in-memory PGN game into a tag list plus a flat movetext
token stream, and serializes that model back to canonical PGN text. It is a
*codec*, not a chess engine: validation is lexical and structural -- tag
syntax, token shapes, move-number sequence and SAN token grammar -- and no
board, game tree or legality check is ever consulted.

Covered syntax:

- tag pairs `[Event "..." ]` with `\"`/`\\` escapes in the value;
- move numbers `N.` and `N...`, including the attached forms `1.e4`,
  `2...Nc6`;
- SAN tokens: castling, piece moves with file/rank disambiguation and
  captures, pawn moves and `=` promotions, optional `+`/`#` suffixes;
- brace comments `{ ... }` (multiline) and rest-of-line comments `; ...`,
  both preserved as tokens;
- NAGs `$n`, result tokens `1-0`, `0-1`, `1/2-1/2`, `*`;
- `%` escape lines (skipped).

Variations `( )` are deliberately unsupported and fail with a clear
`pgn: unsupported variation at <pos>` error. See `SPEC.md` for the exact
grammar, the SAN lexical rules, the error catalog and the test plan.

## API

| Function | Returns | Description |
|---|---|---|
| `pgn_parse(text)` | `Result[Game, Str]` | Parse one PGN game: tags + movetext tokens; errors are fixed `"pgn: ..."` messages with a byte position. |
| `pgn_emit(g)` | `Str` | Canonical text: one `[Name "value"]` line per tag, blank line, then movetext tokens joined with single spaces and a trailing newline. |
| `pgn_tag_count(t)` | `Int` | Number of tag pairs (duplicates counted). |
| `pgn_tag_name(t, i)` | `Str` | Name of tag `i`; `""` out of range. |
| `pgn_tag_value(t, i)` | `Str` | Value of tag `i` (escapes decoded); `""` out of range. |
| `pgn_tag_of(t, name)` | `Option[Str]` | First value of the exact, case-sensitive tag name. |
| `pgn_move_count(m)` | `Int` | Number of movetext tokens. |
| `pgn_move_kind(m, i)` | `Str` | `"num"`, `"san"`, `"comment"`, `"comment_line"`, `"nag"` or `"result"`; `""` out of range. |
| `pgn_move_text(m, i)` | `Str` | Token text (see `SPEC.md` section 3); `""` out of range. |
| `pgn_move_start(m, i)` | `Int` | Byte offset in the parsed input; `-1` out of range. |
| `pgn_result(m)` | `Str` | The game's result token, or `""` when absent. |
| `pgn_is_san(s)` | `Bool` | Standalone lexical SAN check (no board legality). |

## Quick start

```xi
use xiom.pgn;
use xiom.convert;
use xiom.io;

fn main() -> Int {
  let text = "[Event \"Casual\"]\n[White \"Ada\"]\n[Black \"Bob\"]\n\n1. e4 e5 2. Nf3 Nc6 1-0\n";
  let r = pgn_parse(text);
  match r {
    Ok(g) => {
      io.println(int_to_string(pgn_tag_count(&g.tags)));    // 3
      io.println(int_to_string(pgn_move_count(&g.moves)));  // 7
      io.println(pgn_move_kind(&g.moves, 0));               // num
      io.println(pgn_move_text(&g.moves, 1));               // e4
      io.println(pgn_result(&g.moves));                     // 1-0
      io.println(pgn_emit(&g));                             // canonical text
    },
    Err(e) => { io.println(e); },
  }
  return 0;
}
```

(`io.println` takes a `Str`, hence `int_to_string` for the count accessors.)

`pgn_parse` preserves comments as first-class tokens: index the stream and
branch on the kind to walk annotations, or simply filter for `"comment"` /
`"comment_line"`. `pgn_is_san` validates a candidate token without parsing a
document. `pgn_emit` always produces canonical layout: messy whitespace and
arbitrary line breaks become single spaces, while comment and SAN text are
preserved byte-for-byte; re-parsing the emitted text yields the same tags and
tokens.

## Error model

Every failure is an `Err(Str)` with a fixed message and the offending byte
offset, e.g.:

- `pgn: unterminated comment at 6`
- `pgn: bad move number sequence at 6`
- `pgn: illegal san token 'Nf9' at 3`
- `pgn: illegal result token at 3`
- `pgn: unsupported variation at 6`
- `pgn: token after result at 8`

The scanner stops at the first error; tags and tokens read before it are
discarded. The full catalog is in `SPEC.md` section 6.

## Testing

From the repository root:

```
.\scripts\port.ps1 -Package xiom.pgn
```

Expected tail: 24 `[PASS]` lines, `xiom.pgn: all tests passed`, then
`port: PASS (passed=24 failed=0 program_exit=0 exit=0)`.

## Limitations

- No board legality: `1. e4 e4` parses; check/mate, disambiguation and
  promotion claims are not verified.
- No recursive variations (`(`/`)` are errors), no NAG semantics, no clock
  annotation interpretation (all pass through as tokens).
- One game per call; multi-game files must be split by the caller.
- Castling must use the letter `O` (`0-0` is rejected), move numbers may not
  be separated from their dots, and suffix symbols like `!`/`?` and `e.p.`
  are not accepted -- write NAGs instead.
- `pgn_emit` is canonical, not byte-faithful: original spacing, line breaks
  and `%` lines are not preserved; comment/SAN text is.
- Tag values decode only `\"` and `\\`; there is no non-ASCII escape or
  multi-line value support.
- Errors report a byte position only, with no line/column mapping.

See `SPEC.md` for the full semantics and test plan. License: MIT OR
Apache-2.0 (see the repository root `LICENSE`).
