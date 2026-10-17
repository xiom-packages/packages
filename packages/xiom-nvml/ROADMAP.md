# ROADMAP: xiom.nvml

## 0.1.0 (shipped in-lane)

System versions/count; device identity (name, UUID, serial-if-supported, PCI
ids/bus); memory v1; utilization; GPU-die temperature; power usage/limits;
graphics/SM/memory clocks; fan speed; PCIe link; total energy. Typed errors,
deterministic SKIP paths, live RTX 3070 Ti suite.

## 0.2.x

- **Process telemetry:** compute/graphics running processes (PID + used GPU
  memory), MIG-aware variants.
- **Memory v2:** reserved bytes, per-process breakdown.
- **Device enumeration helper:** `nvml_devices()` returning a `Vec[NvmlDevice]`
  for the count from `nvml_system`.
- **Throttle reasons and performance state**, temperature thresholds and
  clocks-event sampling.

## 0.3.x (platform / fleet)

- Linux soname (`libnvidia-ml.so.1`) and the platform loader map.
- MIG mode enumeration and per-instance telemetry.
- ECC/retired-page counters and NVLink state for datacenter cards.

## Out of scope

Mutating NVML APIs (set power limit, fan control, reset), events/callbacks,
vGPU management: monitoring should not need elevated controls. Separate
decision if a consumer asks.

## Re-carve cadence

Refresh the `go-nvml` oracle at each new NVML major/minor; re-verify the
entry-point set and struct asserts, run the suite x2, record `STATUS.json`.
