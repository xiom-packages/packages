# xiom.gcp

> **Status:** `incubating` -- conformance-tested (28/28); published at `v0.1.0` on the XIOM registry.
> **Scope:** project/zone/region resource-name grammar, service registry and
> endpoint bases, GCS buckets/objects/generations/preconditions/ACL, GCE
> machine types/instance state machine/metadata, Cloud Functions
> runtime/handler/trigger/deploy/invoke, BigQuery datasets/tables/schemas/jobs
> and row-page framing, Pub/Sub topics/subscriptions/publish/ack/deadline, and
> the service-account key / OAuth scope / token envelope / JWT claim-set
> shapes (signing out of scope).
> **Deps:** stdlib only (`xiom.string`, `xiom.string.builder`,
> `xiom.string.compare`).

`xiom.gcp` models the Google Cloud provider surface: it validates names,
builds resource paths and deterministic query/JSON fragments, and checks the
interaction rules of each service, while the caller owns transport,
credentials and clocks. Every input is passed in, so every result is
reproducible and testable offline.

## Modules

| Module | Role |
|--------|------|
| `xiom.gcp` | resource names (projects/zones/regions/paths), service registry, endpoint bases |
| `xiom.gcp.core` | shared constants and byte/text/JSON-fragment helpers |
| `xiom.gcp.storage` | GCS buckets, objects, generations, preconditions, ACL shape |
| `xiom.gcp.compute` | GCE machine types, instance lifecycle, metadata, instance paths |
| `xiom.gcp.cloudfunctions` | runtimes, entry points, triggers, deploy validation, invoke classification |
| `xiom.gcp.bigquery` | identifiers, schemas, row-page framing, job model |
| `xiom.gcp.pubsub` | topics/subscriptions, publish validation, ack ids and deadlines |
| `xiom.gcp.auth` | service-account key shape, OAuth scopes, token envelope, JWT claims |

Import direction is sibling-to-sibling only: on compiler v0.62.2 a child
module cannot import its parent, so every service module imports only
`xiom.gcp.core`.

## Example

```xiom
use xiom.gcp;
use xiom.gcp.storage;
use xiom.gcp.auth;

fn object_uri() -> Result[Str, Str] {
  return storage.gcs_object_path("my-bucket", "logs/2026-10-02.txt");
}

fn machine_path() -> Result[Str, Str] {
  return gcp.gcp_resource_path("my-proj-1", "instances", "us-central1-a", "vm-1");
}
```

The returned strings are relative JSON API paths; the caller prefixes the
service endpoint base (`gcp_endpoint_base`) and sends them over its own
transport. `auth` renders the JWT claim-set bytes but never signs them.

## Surface

- **Resource names:** `GcpResource`, `gcp_project_id_is_valid`,
  `gcp_region_is_valid`, `gcp_zone_is_valid`, `gcp_region_of_zone`,
  `gcp_project_path`, `gcp_zone_path`, `gcp_region_path`, `gcp_global_path`,
  `gcp_resource_path`, `gcp_parse_resource`.
- **Registry:** `GCP_SERVICE_*`, `gcp_service_code`, `gcp_service_name`,
  `gcp_service_host`, `gcp_service_api_version`, `gcp_service_is_global`,
  `gcp_endpoint_base`.
- **GCS:** `gcs_bucket_name_is_valid`, `gcs_object_name_is_valid`,
  `gcs_bucket_path`, `gcs_object_path`, `gcs_generation_is_valid`,
  `gcs_generation_path`, `GcsPreconditions`, `gcs_preconditions_none`,
  `gcs_preconditions_query`, `gcs_acl_role_is_valid`,
  `gcs_acl_entity_is_valid`, `gcs_acl_entry_validate`.
- **GCE:** `GCE_STATUS_*`, `gce_status_code`, `gce_status_name`,
  `gce_transition_allowed`, `gce_machine_family_is_known`,
  `gce_machine_type_is_valid`, `GceMachineType`, `gce_machine_type_parse`,
  `gce_machine_type_path`, `gce_instance_name_is_valid`, `gce_instance_path`,
  `gce_metadata_key_is_valid`, `gce_metadata_validate`.
- **Cloud Functions:** `GCF_RUNTIME_*`, `gcf_runtime_code`,
  `gcf_runtime_is_valid`, `gcf_runtime_name`, `gcf_runtime_language`,
  `gcf_runtime_is_gen2`, `gcf_entry_point_is_valid`, `GCF_TRIGGER_*`,
  `gcf_trigger_validate`, `GcfDeploy`, `gcf_deploy_validate`,
  `gcf_deploy_path`, `GCF_INVOKE_*`, `gcf_invoke_class`, `gcf_invoke_url`.
- **BigQuery:** `bq_dataset_id_is_valid`, `bq_table_id_is_valid`,
  `bq_field_name_is_valid`, `bq_qualified_name`, `BQ_TYPE_*`, `bq_type_code`,
  `bq_type_name`, `BQ_MODE_*`, `bq_field_validate`, `bq_schema_validate`,
  `BqPage`, `bq_page_frame`, `bq_page_token`, `BQ_JOB_*`,
  `bq_job_type_code`, `bq_job_type_name`, `bq_job_state_code`,
  `bq_job_state_name`, `bq_job_transition_allowed`, `bq_job_id_is_valid`,
  `bq_job_path`.
- **Pub/Sub:** `ps_resource_name_is_valid`, `ps_topic_path`,
  `ps_subscription_path`, `ps_attr_name_is_reserved`, `ps_publish_validate`,
  `ps_ack_id_is_valid`, `ps_ack_deadline_is_valid`, `ps_ack_deadline_clamp`,
  `ps_ack_deadline_extend`, `ps_subscription_validate`.
- **Auth:** `GCA_SCOPE_*`, `GCA_TOKEN_URI`, `GcaServiceAccountKey`,
  `gca_service_account_key_validate`, `gca_scope_is_valid`,
  `gca_scope_list_join`, `gca_scope_list_has`, `GcaToken`,
  `gca_token_json_parse`, `gca_token_is_valid`, `GcaJwtClaims`,
  `gca_jwt_claims_validate`, `gca_jwt_claims_json`,
  `gca_jwt_signing_supported`.

## Tests

```powershell
.\scripts\port.ps1 -Package xiom-gcp -TimeoutSec 60
```

28 conformance checks, 0 failures; every vector is a fixed known answer (see
SPEC.md for the rule tables). The suite covers all eight modules.

## Implementation notes (v0.62.2)

- **JWT signing is out of scope.** The v0.62.2 stdlib `xiom.crypto` does not
  link from a package (`undefined symbol: xiom_sha256_hash`), so this package
  deliberately never computes a signature; `gca_jwt_signing_supported()`
  returns false and the caller signs the rendered claim set.
- **Module-qualified type names.** The compiler rejects qualified struct
  literals across modules (`storage.GcsPreconditions` is a distinct unknown
  type); tests construct structs with their bare imported names.
- **Struct payloads** (`GcpResource`, `GceMachineType`, `BqPage`, `GcaToken`)
  return through leaf `Ok`/`Err` helper constructors, per the v0.62.2
  convention.
- **No global `Vec[Str].push`**, no `&mut` scalar parameters, no
  `Vec[StructType]` (BigQuery schemas use caller-owned parallel vectors), and
  every loop is bounded.

## License

MIT OR Apache-2.0.
