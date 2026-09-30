# xiom.smartcontract -- Specification

Status: `incubating` (implemented, conformance-green with compiler v0.62.x;
not published).
Manifest: `package.xi` (`xiom.smartcontract`, version `0.1.0`).
Module: `src/smartcontract.xi` (`module xiom.smartcontract`).
Depends on `xiom.std` (`xiom.string`, `xiom.string.compare`, `xiom.convert`,
`xiom.serialize.endian`).
No FFI. No IO, no threads, no network, no crypto, no floating point, no state.

This document describes the exact bytecode format, execution semantics, gas
schedule and error texts implemented by the module. Where the design is
deliberately narrower than EVM-style machines (single fixed-width integer
type, symbolic labels, total outcomes for traps), that is stated explicitly.

## 1. Scope and non-goals

The VM executes a program (`Vec[UInt8]`) against a gas budget and returns a
`VmOutcome`. Execution is pure and deterministic: identical
`(program, gas_limit)` inputs produce byte-identical bytecode interpretation,
traces, gas figures and error texts, on every run and platform.

Not implemented, by design: account/storage persistence, byte-string values,
keccak/SHA, signatures, transaction envelopes, events, gas refunds, call
frames, nested execution, access lists, JSON-RPC, floats, concurrency. Values
are signed 64-bit `Int` words only.

## 2. Bytecode encoding

A program is a flat byte string. Instructions are decoded left to right:

| Form | Encoding |
|---|---|
| zero-operand instruction | the 1 opcode byte |
| operand instruction | 1 opcode byte + `sc_operand_bytes()` = 8 bytes |

Operands are big-endian two's-complement signed 64-bit integers (the whole
`Int` range, `INT64_MIN` included), read and written with
`xiom.serialize.endian`'s `read_u64_be`/`write_u64_be` through an
`Int as UInt64` reinterpretation. An opcode byte above `sc_op_revert()`
(= 16) is rejected; an operand that would extend past the end of the program
is rejected (`program: truncated instruction at pc N`).

## 3. Instructions

Stack notation is bottom -> top; `-1` means one item consumed, `+1` one item
pushed. `pc` is the byte offset of the instruction.

| Byte | Mnemonic | Operand | Stack effect | Semantics |
|---|---|---|---|---|
| 0x00 | `STOP` | -- | 0 | Halt with status `stopped` (0); `return_value` is the top of stack, or 0 when the stack is empty. |
| 0x01 | `PUSH n` | 8-byte Int | +1 | Push `n`. |
| 0x02 | `ADD` | -- | -1 | Pop `b`, pop `a`, push checked `a + b`. |
| 0x03 | `SUB` | -- | -1 | Pop `b`, pop `a`, push checked `a - b`. |
| 0x04 | `MUL` | -- | -1 | Pop `b`, pop `a`, push checked `a * b`. |
| 0x05 | `DIV` | -- | -1 | Pop `b`, pop `a`, push `a / b` truncated toward zero. `b == 0` traps; `INT64_MIN / -1` traps. |
| 0x06 | `MOD` | -- | -1 | Pop `b`, pop `a`, push `a % b`; the sign follows the dividend (`-7 % 2 == -1`). `b == 0` traps; `b == -1` is defined as 0 for every `a`. |
| 0x07 | `CMP` | -- | -1 | Pop `b`, pop `a`, push -1 when `a < b`, 0 when `a == b`, 1 when `a > b`. |
| 0x08 | `JUMP x` | label id | 0 | Continue at the instruction holding `LABEL x`. |
| 0x09 | `JUMPI x` | label id | -1 | Pop `c`; jump to `LABEL x` when `c != 0`, else fall through. |
| 0x0A | `LABEL x` | label id | 0 | No-op marker anchoring the jump target `x`; traced, zero gas. |
| 0x0B | `DUP` | -- | +1 | Push a copy of the top item. |
| 0x0C | `SWAP` | -- | 0 | Exchange the top two items. |
| 0x0D | `POP` | -- | -1 | Discard the top item. |
| 0x0E | `MLOAD` | -- | 0 | Pop key `k`, push `memory[k]`; an unset `k` traps. |
| 0x0F | `MSTORE` | -- | -2 | Pop key `k`, pop value `v`, set `memory[k] = v`. |
| 0x10 | `REVERT` | -- | -1 | Pop `code`, halt with status `reverted` (1) and `exit_code = code`. |

Execution starts at instruction index 0 (byte `pc` 0) and proceeds in
instruction order; only `JUMP`/`JUMPI` redirect it. Falling past the last
instruction traps (`vm: execution ran past the end of the program at pc N`,
where N is the bytecode length). A program is under no obligation to end with
`STOP` or `REVERT`; infinite loops terminate through gas exhaustion because
every control-transfer instruction costs gas (`LABEL` alone can never move
the program counter).

## 4. Gas schedule

`sc_gas_cost(op)`:

| Opcode | Cost |
|---|---|
| `STOP`, `LABEL`, `REVERT` | 0 |
| `PUSH`, `ADD`, `SUB`, `CMP`, `DUP`, `SWAP`, `POP` | 1 |
| `MUL`, `DIV`, `MOD`, `JUMP`, `MLOAD` | 2 |
| `JUMPI`, `MSTORE` | 3 |
| unknown opcode byte | -1 |

These are VM-defined constants chosen for testability, not EVM parity.

An instruction is charged **only when it completes**: before dispatching it,
the VM checks `cost > gas_limit - gas_used` and traps with
`vm: out of gas at pc N (need C, have H)` when the budget is short. A trapped
instruction is therefore neither traced nor charged, and `gas_used` always
equals the sum of the costs of the completed (traced) instructions. The exact
fit (`cost == gas_limit - gas_used`) executes.

## 5. Stack rules

One stack per execution, `Vec[Int]`, signed 64-bit words.

- The maximum depth is `sc_max_stack()` = 1024. A push that would exceed it
  traps with `vm: stack overflow at pc N`.
- Every pop is bounds checked; popping below empty traps with
  `vm: stack underflow at pc N`.
- `ADD`/`SUB`/`MUL`/`DIV`/`MOD`/`CMP`/`SWAP` consume two items (underflow when
  depth < 2); `POP`/`DUP`/`MLOAD`/`REVERT` consume one; `JUMPI` consumes one;
  `MSTORE` consumes two.
- On `STOP` the top of stack is returned as `return_value` (0 when empty); on
  `REVERT` and traps it is 0.

## 6. Memory rules

Memory is a keyed `Int -> Int` map implemented as parallel `Vec[Int]` key and
value vectors, preserving insertion order:

- `MSTORE` with a new key appends `(key, value)`; with an existing key it
  overwrites the value in place (the slot's insertion position is kept).
- `MLOAD` of a key that was never written traps with
  `vm: memory slot K is not initialized at pc N`. There is no implicit zero.
- Keys are arbitrary `Int` values, negatives included. There is no depth,
  slot-count or key-range limit.
- The final map is exposed through `vm_mem_len`, `vm_mem_key`,
  `vm_mem_value`, `vm_mem_has` and `vm_mem_find`.

## 7. Checked arithmetic

Arithmetic never wraps: `ADD`, `SUB`, `MUL` and `DIV` verify their result is
in `[sc_int_min(), sc_int_max()]` and trap with
`vm: arithmetic overflow at pc N` otherwise. Notable edges:

- `INT64_MAX + 1`, `INT64_MIN - 1`, `INT64_MAX * 2` trap.
- `INT64_MIN / -1` traps; `INT64_MIN * -1` traps; `INT64_MIN + 0` is fine.
- `(INT64_MIN + 1) * -1 == INT64_MAX` is fine.
- `INT64_MIN % -1 == 0` is defined (no trap).
- `DIV` truncates toward zero (`-7 / 2 == -3`); `MOD` takes the sign of the
  dividend (`-7 % 2 == -1`, `7 % -2 == 1`).

## 8. Labels and jump resolution

`LABEL` instructions are inert at run time but carry an id. During load:

- duplicate label ids are rejected: `program: duplicate label id N`;
- every `JUMP`/`JUMPI` target must name an existing label:
  `program: unknown label N at pc M` (M = jump `pc`).

At run time a jump sets the instruction index to the `LABEL` instruction
holding the id, so the `LABEL` itself executes (a zero-gas no-op) and then the
following instruction runs. Programs are position-independent; byte offsets
never appear inside the bytecode.

## 9. Traces

Every completed instruction appends one record, in execution order, to eight
parallel vectors in the outcome: `trace_pc`, `trace_op`, `trace_arg`,
`trace_has_arg` (0/1), `trace_gas_before`, `trace_gas_after`, `trace_depth`
(stack depth after the step), `trace_top` (top of stack after the step, 0
when empty). `vm_trace_len` equals `vm_steps` and the number of completed
instructions; a trapped instruction contributes no record.

`vm_trace_line(o, i)` renders one record as

```
pc <N> <MNEMONIC>[ <arg>] gas <before>-><after> depth <D>[ top <T>]
```

The ` top <T>` suffix is present only when the depth is positive.
`vm_trace_text(o)` concatenates the lines, each terminated by `\n` (empty
trace -> empty string). The rendering is canonical: traces are compared
byte-for-byte in the conformance suite.

## 10. Outcomes

`vm_run(program, gas_limit) -> Result[VmOutcome, Str]`.

- `Err` only when the program itself is invalid (`program: ...` texts) or
  `gas_limit < 0` (`vm: negative gas limit`). Program validation (decode,
  duplicate labels, known jump targets) happens before any execution.
- `Ok(outcome)` otherwise; `outcome.status` is `stopped` (0), `reverted` (1)
  or `trapped` (2). Traps are normal outcomes so the partial trace, gas usage
  and memory remain observable; `outcome.error` holds the `vm: ...` text
  (empty for non-traps).

`VmOutcome` fields: `status`, `exit_code`, `return_value`, `error`,
`gas_used`, `steps`, the eight `trace_*` vectors, and the final `mem_keys` /
`mem_vals` vectors.

## 11. Assembler

`sc_assemble(text) -> Result[Vec[UInt8], Str]`.

Grammar (one instruction per line; `\n` terminates a line, `\r` is
whitespace):

```
line        = ws* (instruction ws* comment?)? ws*
comment     = ";" any*
instruction = zero-op | "PUSH" ws+ int | "JUMP" ws+ int
            | "JUMPI" ws+ int | "LABEL" ws+ int
zero-op     = "STOP" | "ADD" | "SUB" | "MUL" | "DIV" | "MOD" | "CMP"
            | "DUP" | "SWAP" | "POP" | "MLOAD" | "MSTORE" | "REVERT"
int         = ["+"|"-"] digit+          ; signed 64-bit, overflow rejected
ws          = space | tab | carriage return
```

Notes:

- Mnemonics are case-sensitive; anything else is
  `asm: unknown mnemonic 'X' at line N`.
- `int` is parsed as decimal by the assembler's own full-range parser: the
  whole signed 64-bit range is accepted, `-9223372036854775808` included
  (`xiom.convert.parse.parse_int` rejects the magnitude 2^63, so it cannot be
  used for this grammar; see the stdlib-gap note in section 14). A missing
  operand for the four operand instructions is
  `asm: missing operand at line N`; an operand on a zero-operand instruction
  (or a third token) is `asm: unexpected operand at line N`; a
  malformed/overflowing operand is `asm: operand is not an integer at line
  N`.
- The input must not contain a NUL byte
  (`asm: text contains a NUL byte`); this keeps every token safe to slice
  into a `Str`.
- Blank and comment-only text assembles to an empty program, which the VM
  rejects with `program: empty bytecode`.
- `LABEL`/`JUMP`/`JUMPI` operands are label ids (any signed 64-bit integer),
  not byte offsets.

## 12. Disassembler

`sc_disassemble(program) -> Result[Str, Str]`. Decodes the program (the same
`program: ...` errors as execution loading) and emits the canonical text:
one instruction per line, operands in signed decimal, every line including
the last terminated by `\n`. No `pc`, comments or padding are emitted, so
`sc_assemble(sc_disassemble(p))` reproduces the exact bytes of every program
the disassembler accepts, and `sc_disassemble(sc_assemble(t))` is the
canonical form of `t`. Note that the disassembler, unlike `vm_run` and
`sc_validate`, does not require jumps to have defined targets (it only
decodes), so a listing of a program with dangling jumps still renders.

`sc_validate(program) -> Result[Int, Str]` runs decode + all label checks and
returns the instruction count.

## 13. Error catalog

Program validation (returned as `Err`; also by `sc_validate`/`sc_disassemble`
where applicable):

| Text | Condition |
|---|---|
| `program: empty bytecode` | no bytes |
| `program: unknown opcode N at pc M` | opcode byte > 16 |
| `program: truncated instruction at pc M` | operand bytes missing |
| `program: duplicate label id N` | `LABEL N` occurs twice |
| `program: unknown label N at pc M` | jump target has no label |

Execution traps (`Ok(outcome)` with `status == trapped`):

| Text | Condition |
|---|---|
| `vm: negative gas limit` | returned as `Err`, not a trap |
| `vm: out of gas at pc N (need C, have H)` | budget short before dispatch |
| `vm: stack underflow at pc N` | pop below empty |
| `vm: stack overflow at pc N` | push beyond 1024 entries |
| `vm: arithmetic overflow at pc N` | checked ADD/SUB/MUL/DIV out of range |
| `vm: division by zero at pc N` | `DIV` with divisor 0 |
| `vm: modulo by zero at pc N` | `MOD` with divisor 0 |
| `vm: memory slot K is not initialized at pc N` | `MLOAD` of an unset key |
| `vm: execution ran past the end of the program at pc N` | no `STOP`/`REVERT` reached |

Assembler errors (`Err` from `sc_assemble`):

| Text | Condition |
|---|---|
| `asm: text contains a NUL byte` | NUL byte in the text |
| `asm: unknown mnemonic 'X' at line N` | unrecognized mnemonic |
| `asm: missing operand at line N` | operand instruction without operand |
| `asm: unexpected operand at line N` | operand where none is allowed, or a third token |
| `asm: operand is not an integer at line N` | malformed or overflowing decimal |

## 14. Known stdlib gaps (hand-rolled here)

- `xiom.convert.parse.parse_int` accumulates the magnitude as a positive
  `Int`, so it rejects `9223372036854775808` and cannot parse
  `-9223372036854775808`; the assembler carries `_parse_operand`, a decimal
  parser that accumulates the negative value and covers the whole signed
  64-bit range.
- There is no stdlib helper for signed checked arithmetic;
  `_add_overflows`, `_sub_overflows`, `_mul_overflows` and `_div_overflows`
  are implemented locally.
- There is no stdlib in-place line/byte scanner that yields `(start, end)`
  byte spans of a raw `Str` without building a `Vec[Str]`; the assembler
  scans bytes in place.

## 15. Verification

```
xiom --run tests/test_conformance.xi
```

22 checks, all `[PASS]`, exit 0, with compiler v0.62.x and the pinned
`E:\xiom-lang\stdlib`. The suite builds every fixture in-test and covers the
two round-trip directions, arithmetic including the `INT64_MIN` edges,
branches, gas exhaustion and exact-fit budgets, stack bounds, memory slots,
label validation, malformed bytecode, past-the-end traps, trace determinism,
and the complete assembler error catalog.
