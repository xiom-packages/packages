# xiom.cloud

Pure-XIOM cloud provider and orchestration **descriptor registry**. No SDK
bindings, no FFI, no network, no file I/O -- the cloud/vendor umbrella is
modeled as deterministic data plus a resolution API.

## What it models

| Table | Entries | Notes |
|-------|---------|-------|
| Providers | 6 | `aws`, `azure`, `gcp` (public cloud); `k8s`, `docker`, `nomad` (orchestrators) |
| Capabilities | 5 | `compute`, `storage`, `functions`, `db`, `queue` |
| Compatibility matrix | 6 x 5 | `none` / `partial` / `full` per provider/capability cell |
| Regions | 12 | 4 each for aws, azure and gcp; orchestrators are region-less |
| Zones | 24 | two per region, derived at build time (`<region>-a`, `<region>-b`) |
| Vendors | 150 | cloud-vendor umbrella; the first 30 are the documented well-known subset |

The six modeled providers are the provider-model siblings (`xiom.aws`,
`xiom.azure`, `xiom.gcp`, `xiom.k8s`, `xiom.docker`, and the generic `nomad`
entry) as descriptors only: this package never imports them and never signs,
deploys or talks to anything.

## Usage

```xiom
use xiom.cloud;

fn main() -> Int {
  let rg = cloud_registry_new();

  // provider lookup
  let r = cloud_provider_lookup(&rg, "k8s");
  if r.is_ok {
    let id: Int = r.value;                       // 3
    io.println(cloud_describe_provider(&rg, id));
    // "k8s: orchestrator, 0 regions, 5/5 capabilities"
  }

  // capability query
  let state = cloud_provider_compat(&rg, CLOUD_PROVIDER_AWS, CLOUD_CAP_QUEUE); // FULL
  let has_db = cloud_provider_supports(&rg, CLOUD_PROVIDER_DOCKER, CLOUD_CAP_DB); // true

  // region validation
  let ok = cloud_region_valid(&rg, CLOUD_PROVIDER_AWS, "eu-west-1"); // true
  let zone = cloud_zone_name(&rg, 0, 1);          // "us-east-1-b"

  // vendor table
  let i = cloud_vendor_lookup(&rg, "minio");      // 129
  let known = cloud_vendor_is_well_known(&rg, "oracle"); // true
  return 0;
}
```

All tables are built by `cloud_registry_new()` at run time: there are no
module-level `Vec` globals. Strings live in `Str` blobs with parallel monotone
`Vec[Int]` offset tables, and every Vec element read inside the library binds a
typed local.

## API surface

* Registry: `cloud_registry_new`, `cloud_registry_consistent`.
* Providers: `cloud_provider_count`, `cloud_provider_name`,
  `cloud_provider_kind`, `cloud_provider_vendor`, `cloud_provider_region_start`,
  `cloud_provider_region_count`, `cloud_provider_descriptor`,
  `cloud_provider_lookup`, `cloud_provider_kind_name`.
* Capabilities: `cloud_capability_name`, `cloud_compat_name`,
  `cloud_provider_compat`, `cloud_provider_supports`,
  `cloud_provider_capability_count`.
* Regions/zones: `cloud_region_count`, `cloud_region_name`,
  `cloud_region_owner`, `cloud_first_region`, `cloud_region_lookup`,
  `cloud_region_valid`, `cloud_zone_count`, `cloud_zone_name`,
  `cloud_zone_owner`.
* Vendors: `cloud_vendor_count`, `cloud_vendor_name`,
  `cloud_vendor_well_known`, `cloud_vendor_lookup`,
  `cloud_vendor_is_well_known`, `cloud_vendor_well_known_count`.
* Reporting: `cloud_describe_provider`.

## Testing

```powershell
.\scripts\port.ps1 -Package xiom-cloud -TimeoutSec 60
```

The deterministic conformance suite (`tests/test_conformance.xi`, 26 checks)
pins the provider/region/zone/vendor tables, the compatibility matrix, every
error string and a pairwise-uniqueness sweep over all 150 vendor entries.

## License

MIT OR Apache-2.0. See `SPEC.md` for the full model and invariants.
