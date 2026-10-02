// XIOM -- xiom.azure: Microsoft Azure provider model (entry module)
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Pure-XIOM MODEL of the Microsoft Azure provider surface: ARM resource ids
// (xiom.azure.arm), blob storage (xiom.azure.storage), virtual machines
// (xiom.azure.compute), Functions routes and triggers
// (xiom.azure.functions), Cosmos DB (xiom.azure.cosmos), Service Bus
// (xiom.azure.servicebus) and Entra ID tokens (xiom.azure.auth). No network,
// no FFI, no clocks and no crypto: every input is supplied by the caller, so
// every result is deterministic and testable offline.
//
// This entry module pins the shared endpoint/provider/API-version registry
// and the package version; the sibling modules carry the models. See SPEC.md
// for the documented subset of each model.
//
// v0.62.2 discipline: free functions only, no match, no &mut scalar
// parameters, masked byte widening, bounded loops, no Vec[StructType],
// Ok/Err construction confined to the _ok_* / _err_* leaf helpers.

module xiom.azure

// Cloud service host suffixes (pinned subset).
pub const AZURE_HOST_MANAGEMENT: Str = "management.azure.com";
pub const AZURE_HOST_BLOB: Str = "blob.core.windows.net";
pub const AZURE_HOST_FUNCTIONS: Str = "azurewebsites.net";
pub const AZURE_HOST_COSMOS: Str = "documents.azure.com";
pub const AZURE_HOST_SERVICE_BUS: Str = "servicebus.windows.net";
pub const AZURE_HOST_LOGIN: Str = "login.microsoftonline.com";

// Cloud service codes for azure_cloud_host / azure_service_code_name.
pub const AZURE_SERVICE_MANAGEMENT: Int = 0;
pub const AZURE_SERVICE_BLOB: Int = 1;
pub const AZURE_SERVICE_FUNCTIONS: Int = 2;
pub const AZURE_SERVICE_COSMOS: Int = 3;
pub const AZURE_SERVICE_SERVICE_BUS: Int = 4;
pub const AZURE_SERVICE_LOGIN: Int = 5;

// ARM provider namespaces (pinned subset).
pub const AZURE_PROVIDER_COMPUTE: Int = 0;
pub const AZURE_PROVIDER_STORAGE: Int = 1;
pub const AZURE_PROVIDER_WEB: Int = 2;
pub const AZURE_PROVIDER_DOCUMENT_DB: Int = 3;
pub const AZURE_PROVIDER_SERVICE_BUS: Int = 4;

// Representative ARM api-versions (pinned 2023-era subset).
pub const AZURE_API_COMPUTE: Str = "2023-03-01";
pub const AZURE_API_STORAGE: Str = "2023-01-01";
pub const AZURE_API_WEB: Str = "2022-03-01";
pub const AZURE_API_DOCUMENT_DB: Str = "2023-04-15";
pub const AZURE_API_SERVICE_BUS: Str = "2022-10-01-preview";

// --------------------------------------------------
//  Result constructors (leaf helpers only)
// --------------------------------------------------

fn _ok_str(v: Str) -> Result[Str, Str] {
  return Ok(v);
}

fn _err_str(m: Str) -> Result[Str, Str] {
  return Err(m);
}

// --------------------------------------------------
//  Registry
// --------------------------------------------------

/// Package version.
pub fn azure_version() -> Str {
  return "0.1.0";
}

/// Host suffix for a cloud service code, or Err for an unknown code.
pub fn azure_cloud_host(service: Int) -> Result[Str, Str] {
  if service == AZURE_SERVICE_MANAGEMENT {
    return _ok_str(AZURE_HOST_MANAGEMENT);
  }
  if service == AZURE_SERVICE_BLOB {
    return _ok_str(AZURE_HOST_BLOB);
  }
  if service == AZURE_SERVICE_FUNCTIONS {
    return _ok_str(AZURE_HOST_FUNCTIONS);
  }
  if service == AZURE_SERVICE_COSMOS {
    return _ok_str(AZURE_HOST_COSMOS);
  }
  if service == AZURE_SERVICE_SERVICE_BUS {
    return _ok_str(AZURE_HOST_SERVICE_BUS);
  }
  if service == AZURE_SERVICE_LOGIN {
    return _ok_str(AZURE_HOST_LOGIN);
  }
  return _err_str("azure: unknown service code");
}

/// Human-readable service name (unknown -> "unknown").
pub fn azure_service_code_name(service: Int) -> Str {
  if service == AZURE_SERVICE_MANAGEMENT {
    return "management";
  }
  if service == AZURE_SERVICE_BLOB {
    return "blob";
  }
  if service == AZURE_SERVICE_FUNCTIONS {
    return "functions";
  }
  if service == AZURE_SERVICE_COSMOS {
    return "cosmos";
  }
  if service == AZURE_SERVICE_SERVICE_BUS {
    return "service_bus";
  }
  if service == AZURE_SERVICE_LOGIN {
    return "login";
  }
  return "unknown";
}

/// ARM provider namespace for a provider code (unknown -> "").
pub fn azure_provider_namespace(provider: Int) -> Str {
  if provider == AZURE_PROVIDER_COMPUTE {
    return "Microsoft.Compute";
  }
  if provider == AZURE_PROVIDER_STORAGE {
    return "Microsoft.Storage";
  }
  if provider == AZURE_PROVIDER_WEB {
    return "Microsoft.Web";
  }
  if provider == AZURE_PROVIDER_DOCUMENT_DB {
    return "Microsoft.DocumentDB";
  }
  if provider == AZURE_PROVIDER_SERVICE_BUS {
    return "Microsoft.ServiceBus";
  }
  return "";
}

// ARM api-version code dispatch (same provider codes as above).
fn _api_version(provider: Int) -> Str {
  if provider == AZURE_PROVIDER_COMPUTE {
    return AZURE_API_COMPUTE;
  }
  if provider == AZURE_PROVIDER_STORAGE {
    return AZURE_API_STORAGE;
  }
  if provider == AZURE_PROVIDER_WEB {
    return AZURE_API_WEB;
  }
  if provider == AZURE_PROVIDER_DOCUMENT_DB {
    return AZURE_API_DOCUMENT_DB;
  }
  if provider == AZURE_PROVIDER_SERVICE_BUS {
    return AZURE_API_SERVICE_BUS;
  }
  return "";
}

/// Representative ARM api-version for a provider code, or Err when unknown.
pub fn azure_api_version(provider: Int) -> Result[Str, Str] {
  let v = _api_version(provider);
  if v.len() == 0 {
    return _err_str("azure: unknown provider code");
  }
  return _ok_str(v);
}

/// Management endpoint URL.
pub fn azure_management_url() -> Str {
  return "https://" + AZURE_HOST_MANAGEMENT + "/";
}
