// C-ORBIT-10 minimal repro (type-error path): `xiom --check` must exit
// nonzero when it reports errors. On the v0.64.4 Linux build (WSL canonical
// ~/.local/share/xiom/bin/xiom) this prints
//   error[T001] ... / note: 1 type errors -- aborting codegen / compilation failed
// but EXITS 0, while the Windows build of the same release exits 1.
module orbitdb_repro_check_exit_type

fn main() -> Int {
  return undefined_symbol_repro;
}
