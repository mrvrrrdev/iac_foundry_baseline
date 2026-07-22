#------------------------------------------------------
# Optional adjacent Azure AI Search service.
# Provisioned only when var.enable_ai_search = true. Private endpoint,
# Entra-only auth, system-assigned identity, max diagnostics.
#------------------------------------------------------
module "ai_search" {
  count = var.enable_ai_search ? 1 : 0

  source  = "Azure/avm-res-search-searchservice/azurerm"
  version = "0.3.0"

  name                = local.resource_names.search_name
  location            = var.location
  resource_group_name = azurerm_resource_group.foundry.name

  sku                           = var.ai_search_sku
  partition_count               = 1
  replica_count                 = 1
  local_authentication_enabled  = false
  public_network_access_enabled = var.ai_foundry_public_network_access_enabled

  managed_identities = {
    system_assigned = true
  }

  private_endpoints = {
    search = {
      name                          = "${local.resource_names.search_name}-pep"
      network_interface_name        = "${local.resource_names.search_name}-pep-nic"
      private_dns_zone_resource_ids = local.private_dns_zones.search != null ? [local.private_dns_zones.search] : []
      subnet_resource_id            = local.subnet_ids.private_endpoints
      tags                          = var.tags
    }
  }

  role_assignments = {
    admin_group_search_service_contributor = {
      role_definition_id_or_name = "Search Service Contributor"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    admin_group_search_index_data_contributor = {
      role_definition_id_or_name = "Search Index Data Contributor"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    #------------------------------------------------------
    # AI Foundry managed identity - Agent Service vector store
    #------------------------------------------------------
    foundry_mi_search_service_contributor = {
      role_definition_id_or_name = "Search Service Contributor"
      principal_id               = module.foundry_managed_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
    foundry_mi_search_index_data_contributor = {
      role_definition_id_or_name = "Search Index Data Contributor"
      principal_id               = module.foundry_managed_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
  }

  diagnostic_settings = local.diagnostic_settings
  tags                = var.tags
}
