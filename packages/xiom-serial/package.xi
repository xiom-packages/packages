// XIOM -- xiom.serial package manifest
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// UART/serial-port bindings: the MCU/host bridge foundation.  Platform
// wrapper over the Win32 comm API (kernel32 CreateFileA/DCB/COMMTIMEOUTS/
// PurgeComm + advapi32 SERIALCOMM enumeration) through xiom.ffi.dl --
// system libraries only, nothing vendored (the canonical cross-platform
// reference, libserialport, is LGPL-3.0+ and stays reference-only per the
// owner's 2026-10-16 restatement; see PROVENANCE.md / SPEC.md).
// Modules: xiom.serial (loader, enumeration, open/close, configure,
// timeouts, blocking/poll read, write, flush, drain, typed errors).

package xiom_serial {
  name: "xiom.serial";
  version: "0.1.0";
  description: "UART/serial-port bindings (Win32 comm API via dynamic loader): port enumeration, open/close, baud/data-bits/parity/stop/flow configuration, blocking and poll-mode reads with timeouts, writes, flush/drain, typed errors with a deterministic absent-device SKIP path";
  categories: ["systems"];
  keywords: ["serial", "uart", "com", "comm", "binding", "mcu", "win32"];
  license: "MIT OR Apache-2.0";
  repository: "https://github.com/xiom-packages/packages";
  authors: ["Eleftherios Notas", "The XIOM Authors"];
  modules: ["xiom.serial"];
  deps: { "xiom.std": ">=0.60.0 <1.0.0" };
}
