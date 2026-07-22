#------------------------------------------------------
# Optional adjacent Azure Cosmos DB (NoSQL) account for Agent Service
# thread storage. Provisioned only when var.enable_cosmosdb = true.
# Private endpoint (Sql subresource = NoSQL/SQL API), Entra-only auth,
# max diagnostics. Azure-services network bypass is enabled so the
# Microsoft-managed Foundry Agent Service can reach the account.
#------------------------------------------------------
module "cosmosdb" {
  count = var.enable_cosmosdb ? 1 : 0

  source  = "Azure/avm-res-documentdb-databaseaccount/azurerm"
  version = "0.10.0"

  name                = local.resource_names.cosmosdb_name
  location            = var.location
  resource_group_name = azurerm_resource_group.foundry.name

  local_authentication_disabled = true
  public_network_access_enabled = var.ai_foundry_public_network_access_enabled

  # Allow trusted Microsoft services (the Foundry Agent Service) to reach Cosmos
  # through the firewall to provision the thread-storage database/containers.
  # Required for the standard/BYO agent setup; mirrors bypass = ["AzureServices"]
  # already set on the storage account and the AI Foundry account.
  network_acl_bypass_for_azure_services = true

  consistency_policy = {
    consistency_level = "Session"
  }

  private_endpoints = {
    sql = {
      name                          = "${local.resource_names.cosmosdb_name}-pep-sql"
      network_interface_name        = "${local.resource_names.cosmosdb_name}-pep-sql-nic"
      private_dns_zone_resource_ids = local.private_dns_zones.cosmos_sql != null ? [local.private_dns_zones.cosmos_sql] : []
      subnet_resource_id            = local.subnet_ids.private_endpoints
      subresource_name              = "Sql"
      tags                          = var.tags
    }
  }

  role_assignments = {
    admin_group_documentdb_contributor = {
      role_definition_id_or_name = "DocumentDB Account Contributor"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    # Symmetric with the MI grant in rbac.tf - admins can create/repair the
    # `enterprise_memory` database and containers that the Foundry capability
    # host provisions. Documented in the Foundry Standard Agent Setup role
    # matrix as the admin-side counterpart to the project MI's Cosmos Operator.
    admin_group_cosmos_operator = {
      role_definition_id_or_name = "Cosmos DB Operator"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
  }

  diagnostic_settings = local.diagnostic_settings_cosmos
  tags                = var.tags
}
