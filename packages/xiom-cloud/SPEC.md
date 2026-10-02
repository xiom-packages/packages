# xiom.cloud -- Specification (0.1.0)

Pure-XIOM cloud provider/orchestration descriptor registry. The module is a
single source file, `src/cloud.xi` (module `xiom.cloud`), depends only on the
stdlib (`xiom.string`, `xiom.string.compare`, `xiom.convert`) and performs no
I/O, no FFI and no network access. It is data plus pure resolution functions.

## 1. Data model

All tables are built at run time by `cloud_registry_new() -> CloudRegistry` and
stored as parallel arrays inside one value:

* name-like strings live in a `Str` blob with a monotone `Vec[Int]` offset
  table of length `count + 1`; entry `i` is `blob[off[i] .. off[i+1]]`;
* no module-level `Vec` globals, no `Vec[Str]`, no `Vec[StructType]`;
* `CloudRegistry` fields are implementation detail; callers use the accessors.

`CloudProvider` (returned by `cloud_provider_descriptor`):

| field | type | meaning |
|-------|------|---------|
| `name` | `Str` | provider name, `""` when the id is out of range |
| `kind` | `Int` | `CLOUD_KIND_PUBLIC` or `CLOUD_KIND_ORCHESTRATOR`, `CLOUD_NOT_FOUND` OOR |
| `vendor_index` | `Int` | index into the vendor table, `CLOUD_NOT_FOUND` OOR |
| `region_start` | `Int` | first global region id, `CLOUD_NOT_FOUND` for orchestrators |
| `region_count` | `Int` | number of regions (0 for orchestrators) |
| `capability_count` | `Int` | non-`NONE` cells in this provider's matrix row |

## 2. Constants

| constant | value |
|----------|-------|
| `CLOUD_PROVIDER_AWS/AZURE/GCP/K8S/DOCKER/NOMAD` | 0..5 |
| `CLOUD_PROVIDER_COUNT` | 6 |
| `CLOUD_KIND_PUBLIC`, `CLOUD_KIND_ORCHESTRATOR` | 0, 1 |
| `CLOUD_CAP_COMPUTE/STORAGE/FUNCTIONS/DB/QUEUE` | 0..4 |
| `CLOUD_CAP_COUNT` | 5 |
| `CLOUD_COMPAT_NONE/PARTIAL/FULL` | 0, 1, 2 |
| `CLOUD_NOT_FOUND` | -1 |
| `CLOUD_REGION_COUNT`, `CLOUD_ZONE_COUNT` | 12, 24 |
| `CLOUD_VENDOR_COUNT`, `CLOUD_WELL_KNOWN_VENDOR_COUNT` | 150, 30 |

Provider ids are dense array indices (stable because the registry is built in
this order): `aws=0, azure=1, gcp=2, k8s=3, docker=4, nomad=5`. Region ids are
global and dense in table order; zone ids are addressed as `(region, k)`.

## 3. Providers

| id | name | kind | vendor index | regions |
|----|------|------|--------------|---------|
| 0 | aws | public-cloud | 0 (`aws`) | us-east-1, us-west-2, eu-west-1, ap-southeast-1 |
| 1 | azure | public-cloud | 1 (`azure`) | eastus, westus2, westeurope, southeastasia |
| 2 | gcp | public-cloud | 2 (`gcp`) | us-central1, us-east1, europe-west1, asia-southeast1 |
| 3 | k8s | orchestrator | 3 (`kubernetes`) | none (region-less) |
| 4 | docker | orchestrator | 4 (`docker`) | none (region-less) |
| 5 | nomad | orchestrator | 5 (`nomad`) | none (region-less) |

Zones: every region has exactly two zones, named `<region>-a` and
`<region>-b`; zone names are derived from the region table at build time.

## 4. Compatibility matrix

States: `none` (0) not offered, `partial` (1) offered with caveats
(self-managed, operator, CSI, single host), `full` (2) first-class managed
capability. Matrix is stored provider-major at `provider * 5 + capability`.

| provider | compute | storage | functions | db | queue |
|----------|---------|---------|-----------|----|-------|
| aws | full | full | full | full | full |
| azure | full | full | full | full | full |
| gcp | full | full | full | full | full |
| k8s | full | partial | partial | partial | partial |
| docker | partial | partial | none | partial | partial |
| nomad | full | partial | none | none | none |

## 5. Resolution API

| function | behavior |
|----------|----------|
| `cloud_provider_lookup(rg, name)` | `Result[Int, Str]`; provider id or an error (section 6) |
| `cloud_provider_compat(rg, provider, cap)` | matrix state; `none` for OOR/malformed input |
| `cloud_provider_supports(rg, provider, cap)` | `compat != none`, `false` for OOR input |
| `cloud_provider_capability_count` | count of non-`none` cells in a provider row |
| `cloud_region_lookup(rg, provider, name)` | `Result[Int, Str]`; global region id or an error |
| `cloud_region_valid(rg, provider, name)` | `lookup(...).is_ok` |
| `cloud_first_region(rg, provider)` | first global region id or `-1` |
| `cloud_zone_name(rg, region, k)` / `cloud_zone_owner` | zone name / owning region, safe ranges |
| `cloud_vendor_lookup(rg, name)` | vendor index or `-1`; `""` maps to `-1` |
| `cloud_vendor_is_well_known(rg, name)` | `true` only for flagged subset entries |
| `cloud_describe_provider(rg, provider)` | `"<name>: <kind>, <n> regions, <c>/5 capabilities"` or `"cloud: unknown provider"` |
| `cloud_registry_consistent(rg)` | full structural invariant check (section 7) |

Out-of-range reads never abort: they return `""`, `0`, `false`, `-1`
(`CLOUD_NOT_FOUND`) or `CLOUD_COMPAT_NONE` as documented per accessor.

## 6. Error strings

`cloud_provider_lookup`:

* `"cloud: empty provider name"` for `""`;
* `"cloud: unknown provider"` for any other miss (comparison is bytewise and
  case-sensitive: `"AWS"` does not resolve).

`cloud_region_lookup`:

* `"cloud: unknown provider"` for an out-of-range provider;
* `"cloud: empty region name"` for `""`;
* `"cloud: provider has no region model"` for region-less orchestrators;
* `"cloud: unknown region"` when the name is not in the provider's range.

## 7. Structural invariants

`cloud_registry_consistent` returns `true` only when all of:

1. the five provider tables share one length (`CLOUD_PROVIDER_COUNT`);
2. region tables share one length (`CLOUD_REGION_COUNT` = 12), zone tables and
   per-region counts agree (`CLOUD_ZONE_COUNT` = 24 total);
3. the compatibility matrix has exactly `6 * 5` cells;
4. the vendor table has exactly `CLOUD_VENDOR_COUNT` entries and exactly
   `CLOUD_WELL_KNOWN_VENDOR_COUNT` flagged entries;
5. every provider's region range is inside the region table and each region is
   owned by the provider whose range contains it;
6. every zone owner is a valid region id.

The registry is deterministic: two calls to `cloud_registry_new()` produce
byte-for-byte identical tables and provider summaries (pinned by t25).

## 8. Vendor table (150 entries)

First 30 entries are flagged well-known (`vendor_flags = 1`); the remaining
120 are the long tail (`vendor_flags = 0`). Indices below are 0-based.

Well-known (0-29): aws, azure, gcp, kubernetes, docker, nomad, oracle, ibm,
alibaba, tencent, huawei, digitalocean, linode, vultr, hetzner, ovh, scaleway,
cloudflare, rackspace, vmware, nutanix, openstack, openshift, heroku, vercel,
netlify, render, fly-io, railway, cloudstack.

Long tail (30-149): proxmox, upcloud, gcore, selectel, yandex, sbercloud,
vk-cloud, mail-ru, beget, timeweb, reg-ru, ionos, strato, contabo, netcup,
akamai, fastly, bunny, keycdn, stackpath, imperva, f5, citrix, nvidia,
coreweave, lambda-labs, paperspace, vast-data, runpod, modal, replicate,
huggingface, databricks, snowflake, mongodb-atlas, datastax, confluent,
elastic-cloud, cloudera, datadog, newrelic, dynatrace, splunk, grafana-cloud,
logzio, sentry, pagerduty, opsgenie, victorops, atlassian, github, gitlab,
bitbucket, circleci, travis-ci, buildkite, drone, argo, tekton, flux, rancher,
harvester, talos, podman, containerd, cri-o, lxc, incus, kata, firecracker,
gvisor, xcp-ng, opennebula, cloudify, juju, maas, terraform-cloud, pulumi,
crossplane, spacelift, env0, scalr, consul, hashicorp, openfaas, knative,
fission, nuclio, openwhisk, openfunction, dapr, istio, linkerd, cilium, calico,
portworx, longhorn, rook, ceph, minio, openebs, juicefs, seaweedfs, velero,
baidu, jd-cloud, volcano-engine, naver, kakao, nhn, kt-cloud, equinix,
digital-realty, cyrusone, interxion, openai, anthropic, mistral, dreamhost,
liquid-web.

## 9. Non-goals

* No SDK bindings, no credentials, no signing, no HTTP.
* No live catalog sync: tables are a pinned, documented descriptor snapshot.
* No vendor-specific API schemas beyond the umbrella table.
* No concurrency: one immutable `CloudRegistry` value per caller.

## 10. Testing

`tests/test_conformance.xi` (module `cloud_tests`) has 26 self-contained
checks: provider/kind/descriptor resolution, capability and compatibility
matrix cells, region/zone tables and validation errors, vendor count, flags,
pinned indices, pairwise uniqueness across all 150 vendors, build determinism
and structural invariants. Run with:

```powershell
.\scripts\port.ps1 -Package xiom-cloud -TimeoutSec 60
```
