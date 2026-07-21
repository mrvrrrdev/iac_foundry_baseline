#------------------------------------------------------
# Adjacent Storage account (ZRS) for AI Foundry / Agent Service.
# Zone-redundant, Entra-only auth (shared keys disabled), private
# endpoints for blob and file, max diagnostics.
#------------------------------------------------------
module "storage_account" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.6.7"

  location            = var.location
  name                = local.resource_names.storage_account_name
  resource_group_name = azurerm_resource_group.foundry.name

  access_tier                   = "Hot"
  account_replication_type      = "ZRS"
  account_tier                  = "Standard"
  shared_access_key_enabled     = false
  public_network_access_enabled = var.ai_foundry_public_network_access_enabled

  network_rules = {
    default_action = var.ai_foundry_public_network_access_enabled ? "Allow" : "Deny"
    bypass         = ["AzureServices"]
  }

  containers = {
    foundry = {
      name                  = "foundry"
      container_access_type = "private"
    }
  }

  private_endpoints = {
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
  }

  role_assignments = {
    admin_group_blob_data_owner = {
      role_definition_id_or_name = "Storage Blob Data Owner"
      principal_id               = var.admin_group_id
    }
    admin_group_file_data_contributor = {
      role_definition_id_or_name = "Storage File Data Privileged Contributor"
      principal_id               = var.admin_group_id
    }
    #------------------------------------------------------
    # AI Foundry managed identity - Agent Service BYO storage
    #------------------------------------------------------
    foundry_mi_blob_data_contributor = {
      role_definition_id_or_name = "Storage Blob Data Contributor"
      principal_id               = module.foundry_managed_identity.principal_id
    }
    foundry_mi_file_data_contributor = {
      role_definition_id_or_name = "Storage File Data Privileged Contributor"
      principal_id               = module.foundry_managed_identity.principal_id
    }
  }

  diagnostic_settings_storage_account = local.diagnostic_settings
  diagnostic_settings_blob            = local.diagnostic_settings
  tags                                = var.tags
}
