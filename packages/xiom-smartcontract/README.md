# xiom.smartcontract

> **Status:** `incubating` -- conformance-tested (22/22); published at `v0.1.0` on the XIOM registry.
> **Scope:** one pure, deterministic stack VM for a documented contract
> bytecode subset: a bounds-checked integer stack, keyed memory slots,
> checked arithmetic, per-opcode gas metering with out-of-gas aborts,
> deterministic execution traces, an assembler and a disassembler with
> exact round-trips, and a closed error catalog.
> **Deps:** `xiom.std` only (`xiom.string`, `xiom.string.compare`,
> `xiom.convert`, `xiom.serialize.endian`; tests add `xiom.test` and
> `xiom.io`).
> No FFI, no IO, no threads, no network, no crypto, no floating point.

## What it is

`xiom.smartcontract` is a small virtual machine for the sort of bytecode a
contract sandbox runs, kept deliberately pure and deterministic: execution is
a function of `(program, gas_limit)` alone, so identical inputs always
produce byte-identical traces, gas figures and error texts. It is the
execution half of a contract toolchain -- not a blockchain client: there is no
state, no signatures, no hashing, no persistence, no networking.

- **Documented bytecode subset.** 17 opcodes: `STOP`, `PUSH`, `ADD`, `SUB`,
  `MUL`, `DIV`, `MOD`, `CMP`, `JUMP`, `JUMPI`, `LABEL`, `DUP`, `SWAP`, `POP`,
  `MLOAD`, `MSTORE`, `REVERT`. `PUSH`/`JUMP`/`JUMPI`/`LABEL` carry an 8-byte
  big-endian signed operand.
- **Symbolic labels.** `LABEL id` is an inline no-op marker; `JUMP id` and
  `JUMPI id` resolve against the label table at load time. Programs stay
  position-independent and duplicate or undefined labels are rejected before
  anything executes.
- **Bounds-checked stack.** One `Vec[Int]` stack, signed 64-bit, capped at
  1024 entries; underflow and overflow abort with precise `pc` reporting.
- **Keyed memory.** An `Int -> Int` map stored as parallel `Vec[Int]` key and
  value vectors; reading an unset slot aborts, writing an existing key
  overwrites in place.
- **Checked arithmetic.** `ADD`/`SUB`/`MUL`/`DIV`/`MOD` never wrap or divide
  by zero: every out-of-range result is an explicit `vm: arithmetic overflow`
  abort (`INT64_MIN % -1` is defined as 0).
- **Gas.** Every opcode has a fixed cost (`sc_gas_cost`); an instruction is
  charged only when it completes, so a trapped instruction is neither charged
  nor traced. Running out of gas aborts with the exact `pc`, need and have.
- **Deterministic traces.** Every completed instruction appends one record to
  eight parallel trace vectors (`pc`, opcode, operand, gas before/after,
  stack depth, stack top); `vm_trace_line`/`vm_trace_text` render them.
- **Assembler + disassembler.** Text such as `PUSH 5` / `LABEL 1` / `JUMP 1`
  / `STOP` assembles to bytecode; disassembly emits the canonical text.
  `sc_assemble(sc_disassemble(p))` reproduces `p` byte-for-byte.

## Quick start

```xi
use xiom.smartcontract;
use xiom.convert;
use xiom.io;

fn main() {
  // Assemble a tiny program that doubles 21 and stops.
  let text = "PUSH 21\nDUP\nADD\nSTOP\n";
  match sc_assemble(text) {
    Ok(program) => {
      match vm_run(&program, 100) {
        Ok(outcome) => {
          // 42
          io.println("result: " + convert.int_to_string(vm_return_value(&outcome)));
          // "pc 10 ADD gas 2->3 depth 1 top 42" and the rest
          io.println(vm_trace_text(&outcome));
        }
        Err(e) => { io.println("program error: " + e); },
      }
    }
    Err(e) => { io.println("assembly error: " + e); },
  }
}
```

Programs can also be built by hand: a `PUSH n` is the byte `01` followed by
the eight big-endian two's-complement bytes of `n`, and zero-operand opcodes
are single bytes.

## API

### Assembler / disassembler

| Function | Returns | Description |
|---|---|---|
| `sc_assemble(text)` | `Result[Vec[UInt8], Str]` | Text (one instruction per line, `;` comments, blank lines skipped) to bytecode. |
| `sc_disassemble(program)` | `Result[Str, Str]` | Canonical text for a program; decode errors are `program: ...`. |
| `sc_validate(program)` | `Result[Int, Str]` | Decode + validate; returns the instruction count. |

### Execution

| Function | Returns | Description |
|---|---|---|
| `vm_run(program, gas_limit)` | `Result[VmOutcome, Str]` | Execute; `Err` only for invalid programs or a negative gas limit. |
| `vm_status(outcome)` | `Int` | 0 stopped, 1 reverted, 2 trapped. |
| `vm_stopped / vm_reverted / vm_trapped(outcome)` | `Bool` | Status predicates. |
| `vm_error(outcome)` | `Str` | Trap text, or `""`. |
| `vm_exit_code(outcome)` | `Int` | 0 for `STOP`, the popped code for `REVERT`. |
| `vm_return_value(outcome)` | `Int` | Top of stack at `STOP` (0 when empty). |
| `vm_gas_used(outcome)` / `vm_steps(outcome)` | `Int` | Charged gas / completed instructions. |

### Traces and memory

| Function | Returns | Description |
|---|---|---|
| `vm_trace_len(outcome)` | `Int` | Number of trace records. |
| `vm_trace_pc / vm_trace_op / vm_trace_arg` | `Int` | Record fields (`-1`/`0` out of range). |
| `vm_trace_has_arg(outcome, i)` | `Bool` | Whether the instruction carries an operand. |
| `vm_trace_gas_before / vm_trace_gas_after` | `Int` | Gas before/after the instruction. |
| `vm_trace_depth / vm_trace_top` | `Int` | Stack depth and top after the instruction. |
| `vm_trace_line(outcome, i)` | `Str` | `pc N OP [arg] gas A->B depth D [top T]`, or `""`. |
| `vm_trace_text(outcome)` | `Str` | All trace lines, newline terminated. |
| `vm_mem_len / vm_mem_key / vm_mem_value` | `Int` | Final memory map in insertion order. |
| `vm_mem_has / vm_mem_find` | `Bool` / `Int` | Key membership / slot index (`-1` absent). |

### Opcode metadata

| Function | Returns | Description |
|---|---|---|
| `sc_op_stop ... sc_op_revert` | `Int` | The 17 opcode byte constants (0..16). |
| `sc_op_name(op)` | `Str` | Mnemonic, or `""` for an unknown opcode byte. |
| `sc_has_operand(op)` | `Bool` | True for `PUSH`/`JUMP`/`JUMPI`/`LABEL`. |
| `sc_gas_cost(op)` | `Int` | Fixed cost, or `-1` for an unknown opcode. |
| `sc_operand_bytes()` / `sc_max_stack()` | `Int` | 8 / 1024. |
| `sc_status_stopped / sc_status_reverted / sc_status_trapped` | `Int` | 0 / 1 / 2. |
| `sc_int_min()` / `sc_int_max()` | `Int` | The checked-arithmetic bounds. |

## Opcodes

| Byte | Mnemonic | Operand | Stack | Gas |
|---|---|---|---|---|
| 0x00 | `STOP` | -- | halts, result is top of stack | 0 |
| 0x01 | `PUSH n` | 8-byte `Int` | `+1` | 1 |
| 0x02 | `ADD` | -- | `a b -> a+b` | 1 |
| 0x03 | `SUB` | -- | `a b -> a-b` | 1 |
| 0x04 | `MUL` | -- | `a b -> a*b` | 2 |
| 0x05 | `DIV` | -- | `a b -> a/b` (toward zero) | 2 |
| 0x06 | `MOD` | -- | `a b -> a%b` (sign of `a`) | 2 |
| 0x07 | `CMP` | -- | `a b -> -1/0/1` | 1 |
| 0x08 | `JUMP x` | 8-byte label | -- | 2 |
| 0x09 | `JUMPI x` | 8-byte label | `-1` (condition) | 3 |
| 0x0A | `LABEL x` | 8-byte label | no-op marker | 0 |
| 0x0B | `DUP` | -- | `a -> a a` | 1 |
| 0x0C | `SWAP` | -- | `a b -> b a` | 1 |
| 0x0D | `POP` | -- | `-1` | 1 |
| 0x0E | `MLOAD` | -- | `k -> memory[k]` | 2 |
| 0x0F | `MSTORE` | -- | `v k -> ()` | 3 |
| 0x10 | `REVERT` | -- | `code -> halts reverted` | 0 |

Full semantics, trap conditions and the error catalog are in `SPEC.md`.

## Tests

```
xiom --run tests/test_conformance.xi
```

Expected: 22 `[PASS]` lines, then `xiom.smartcontract: all tests passed`,
exit 0. The suite builds every program in-test (through the assembler, or as
raw bytes for malformed cases) and covers arithmetic, branches, gas
exhaustion and exact-fit budgets, reverts, stack bounds, memory slots, label
validation, malformed bytecode, trace determinism, and every assembler error.

## Install / publish

```
xiom pkg install xiom.smartcontract@0.1.0   # consumer
xiom pkg publish                             # maintainer (needs XIOM_REGISTRY_TOKEN)
```

## License

MIT OR Apache-2.0 (see the repository root `LICENSE`).
