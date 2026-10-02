# xiom.azure

> **Status:** implemented (0.1.0) -- pure-XIOM Microsoft Azure provider model,
> no network, no FFI, no crypto, deterministic.
> **Scope:** ARM resource ids, blob storage with ETag preconditions, VM sizes
> and the power-state machine, Functions routes/triggers, Cosmos DB partitions
> and documents, Service Bus delivery states, Entra ID token envelopes.
> **Deps:** stdlib only (`xiom.string`, `xiom.string.builder`,
> `xiom.string.compare`).

`xiom.azure` models the Azure provider surface: it parses ids, validates
names, evaluates preconditions and walks the documented state machines, while
the caller owns transport, clocks, credentials and secret storage. Every
input is passed in, so every result is reproducible and testable offline.

## Modules

| Module | Role |
|--------|------|
| `xiom.azure` | entry module: cloud hosts, provider namespaces, pinned ARM api-versions, package version |
| `xiom.azure.base` | shared helpers: byte-safe compare, slicing, GUID shape, joins |
| `xiom.azure.arm` | ARM resource-id parse/build, scopes, parent ids |
| `xiom.azure.storage` | account/container/blob names, URLs, ETags, preconditions, block lists |
| `xiom.azure.compute` | VM size table, power-state machine, locations, tags |
| `xiom.azure.functions` | app/runtime model, route templates, triggers, invoke URLs |
| `xiom.azure.cosmos` | database/container/document names, partition keys, RU ladder, status codes |
| `xiom.azure.servicebus` | entity/queue model, message state machine, lock/DLQ rules |
| `xiom.azure.auth` | tenant/client ids, scopes, endpoints, token envelopes, identity chain |

## Example

```xiom
use xiom.azure.arm;
use xiom.azure.storage;

fn blob_url_for_resource(id: Str) -> Result[Str, Str] {
  let r = azure_arm_parse(id);
  if !r.is_ok {
    let em: Str = r.error;
    return Err(em);
  }
  let res: ArmResourceId = r.value;
  let account: Str = res.resource_name;
  return azure_blob_url(account, "data", "folder/file.bin");
}
```

The caller sends the returned URL over its own transport; nothing here opens
a socket.

## Surface

- **ARM:** `ArmResourceId`, `azure_arm_parse`, `azure_arm_resource_id`,
  `azure_arm_subscription_scope`, `azure_arm_resource_group_scope`,
  `azure_arm_scope_name`, `AZURE_ARM_SCOPE_*`.
- **Storage:** `AzureEtag`, `AzureBlob`, `azure_storage_account_name_valid`,
  `azure_container_name_valid`, `azure_blob_name_valid`, `azure_blob_url`,
  `azure_etag_parse`, `azure_etag_strong_equal`, `azure_etag_weak_equal`,
  `azure_precondition_allows`, `azure_block_id_valid`,
  `azure_block_list_valid`, `azure_block_list_resolve`,
  `azure_blob_tier_name`, `azure_blob_type_name`, `azure_lease_state_name`.
- **Compute:** `AzureVmSize`, `azure_vm_size_lookup`,
  `azure_vm_size_name_by_shape`, `azure_vm_power_parse`,
  `azure_vm_power_name`, `azure_vm_power_transition`,
  `azure_vm_power_can_start`, `azure_vm_power_can_deallocate`,
  `azure_location_canonical`, `azure_location_valid`, `azure_tags_valid`,
  `azure_tags_get`.
- **Functions:** `AzureFunctionApp`, `AzureHttpTrigger`,
  `azure_function_app_name_valid`, `azure_function_runtime_name`,
  `azure_function_runtime_lookup`, `azure_function_app_lookup`,
  `azure_function_default_hostname`, `azure_route_valid`,
  `azure_route_parameter_names`, `azure_route_match`,
  `azure_trigger_method_valid`, `azure_trigger_method_allowed`,
  `azure_trigger_valid`, `azure_function_key_valid`,
  `azure_function_invoke_url`, `azure_function_status_class`,
  `azure_function_status_retryable`.
- **Cosmos:** `AzureCosmosDocument`, `azure_cosmos_name_valid`,
  `azure_cosmos_partition_key_path_valid`,
  `azure_cosmos_partition_key_value_valid`,
  `azure_cosmos_partition_key_header`,
  `azure_cosmos_partition_key_header_parse`, `azure_cosmos_ttl_valid`,
  `azure_cosmos_document_valid`, `azure_cosmos_document_path`,
  `azure_cosmos_consistency_name`, `azure_cosmos_throughput_normalize`,
  `azure_cosmos_status_error`, `azure_cosmos_status_retryable`.
- **Service Bus:** `AzureSbQueue`, `AzureSbMessage`,
  `azure_sb_entity_name_valid`, `azure_sb_namespace_valid`,
  `azure_sb_queue`, `azure_sb_queue_url`, `azure_sb_subscription_path`,
  `azure_sb_delivery_mode_name`, `azure_sb_state_name`,
  `azure_sb_message_transition`, `azure_sb_lock_expired`,
  `azure_sb_delivery_count_exceeded`, `azure_sb_deadletter_reason_valid`,
  `azure_sb_scheduled_delay_valid`, `azure_sb_rule_filter_valid`,
  `azure_sb_message_valid`.
- **Auth:** `AzureIdentity`, `AzureToken`, `azure_tenant_id_valid`,
  `azure_client_id_valid`, `azure_scope_valid`, `azure_scope_for_resource`,
  `azure_scope_resource`, `azure_authority_url`, `azure_token_url`,
  `azure_token_valid`, `azure_token_expires_at`, `azure_token_is_expired`,
  `azure_bearer_header`, `azure_identity_source_name`,
  `azure_identity_valid`, `azure_identity_resolve`.

## Tests

```powershell
.\scripts\port.ps1 -Package xiom-azure -TimeoutSec 60
```

24 conformance checks, 0 failures: ARM scope/resource/child parsing and
build errors, blob name/ETag/precondition/block-list tables, VM size and
power-state tables, location and tag rules, route validity/matching,
trigger/invoke shapes, Cosmos partition-key and throughput rules, Service Bus
state transitions and lock/DLQ rules, token envelope arithmetic and the
identity chain (see SPEC.md).

## Implementation notes (v0.62.2)

The package is split into sibling modules because no module may import its
parent: `xiom.azure.base` is the shared leaf, every model sibling imports it,
and the entry module stays a registry. All crypto-free: Azure bearer tokens
are validated as envelopes, never signed or verified here.

## License

MIT OR Apache-2.0.
