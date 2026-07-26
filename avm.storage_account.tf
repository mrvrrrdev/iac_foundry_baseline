#------------------------------------------------------
# Adjacent Storage account (ZRS) for AI Foundry / Agent Service.
# Zone-redundant, Entra-only auth (shared keys disabled), private
# endpoints for blob and file, max diagnostics.
#------------------------------------------------------
module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.7.3"

  location  = var.location
  name      = local.resource_names.storage_account_name
  parent_id = azurerm_resource_group.foundry.id

  access_tier                     = "Hot"
  account_sku_name                = "Standard_ZRS"
  shared_access_key_enabled       = false
  public_network_access_enabled   = var.ai_foundry_public_network_access_enabled
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  network_rules = {
    default_action = var.ai_foundry_public_network_access_enabled ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
  }

  containers = {
    foundry = {
      name          = "foundry"
      public_access = "None"
    }
  }

  private_endpoints = local.private_networking_enabled ? {
    blob = {
      name                          = "${local.resource_names.storage_account_name}-pep-blob"
      network_interface_name        = "${local.resource_names.storage_account_name}-pep-blob-nic"
      private_dns_zone_resource_ids = local.private_dns_zones.blob != null ? [local.private_dns_zones.blob] : []
      subnet_resource_id            = local.subnet_ids.private_endpoints
      subresource_name              = "blob"
      tags                          = var.tags
    }
    file = {
      name                          = "${local.resource_names.storage_account_name}-pep-file"
      network_interface_name        = "${local.resource_names.storage_account_name}-pep-file-nic"
      private_dns_zone_resource_ids = local.private_dns_zones.file != null ? [local.private_dns_zones.file] : []
      subnet_resource_id            = local.subnet_ids.private_endpoints
      subresource_name              = "file"
      tags                          = var.tags
    }
  } : {}

  role_assignments = {
    admin_group_blob_data_owner = {
      role_definition_id_or_name = "Storage Blob Data Owner"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    admin_group_file_data_contributor = {
      role_definition_id_or_name = "Storage File Data Privileged Contributor"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    #------------------------------------------------------
    # AI Foundry managed identity - Agent Service BYO storage
    #------------------------------------------------------
    foundry_mi_blob_data_contributor = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = module.foundry_managed_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
    foundry_mi_file_data_contributor = {
      role_definition_id_or_name = "Storage File Data Privileged Contributor"
      principal_id               = module.foundry_managed_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
    # Control-plane management of the storage account (list containers, resolve
    # keys for AAD-based data-plane operations, manage lifecycle). Documented as
    # required for the project managed identity in the Foundry "Standard Agent
    # Setup" role matrix, Phase 3.
    foundry_mi_storage_account_contributor = {
      role_definition_id_or_name = "Storage Account Contributor"
      principal_id               = module.foundry_managed_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
  }

  # v0.7.3 uses the v2 diagnostic settings interface (logs/metrics sets), not
  # the v1 log_groups/metric_categories shape used elsewhere in this repo.
  # Storage account (control-plane) accepts metrics only; blob accepts both.
  diagnostic_settings_storage_account = {
    to_law = {
      name                  = "diag-to-law"
      workspace_resource_id = module.log_analytics_workspace.resource_id
      metrics               = [{ category = "AllMetrics" }]
    }
  }
  diagnostic_settings_blob = {
    to_law = {
      name                  = "diag-to-law"
      workspace_resource_id = module.log_analytics_workspace.resource_id
      logs                  = [{ category_group = "allLogs" }]
      metrics               = [{ category = "AllMetrics" }]
    }
  }
  tags = var.tags
}
