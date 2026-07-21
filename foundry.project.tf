#------------------------------------------------------
# AI Foundry project (child of the AIServices account).
#
# Projects are the containers for access management, data
# isolation and cost in AI Foundry. Created via azapi because
# the azurerm provider does not yet expose the project resource
# with display name / description.
#------------------------------------------------------
resource "azapi_resource" "project" {
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview"
  name      = var.ai_foundry_project_name
  parent_id = module.ai_foundry.resource_id
  location  = var.location

  identity {
    type         = "SystemAssigned, UserAssigned"
    identity_ids = [module.foundry_managed_identity.resource_id]
  }

  body = {
    properties = {
      displayName = var.ai_foundry_project_display_name
      description = var.ai_foundry_project_description
    }
  }

  response_export_values = ["identity.principalId"]

  # Serialize project creation after the whole account module (account, model
  # deployments, private endpoint, role assignments) to avoid concurrent PUTs on
  # the account (RequestConflict 409). The account-level agent capability host is
  # provisioned automatically by the platform (see project_capability_host below).
  depends_on = [module.ai_foundry]

  tags = var.tags
}

#------------------------------------------------------
# Bring-your-own (standard) Agent Service dependencies.
# Project connections are created only when Storage + Cosmos DB
# + AI Search are all present (local.create_agent_byo).
#------------------------------------------------------
resource "azapi_resource" "conn_storage" {
  count = local.create_agent_byo ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "storageconn"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      category      = "AzureStorageAccount"
      target        = "https://${local.resource_names.storage_account_name}.blob.core.windows.net/"
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.storage_account.resource_id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "conn_cosmos" {
  count = local.create_agent_byo ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "cosmosconn"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      category      = "CosmosDB"
      target        = "https://${local.resource_names.cosmosdb_name}.documents.azure.com:443/"
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.cosmosdb[0].resource_id
        location   = var.location
      }
    }
  }
}

resource "azapi_resource" "conn_search" {
  count = local.create_agent_byo ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "searchconn"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      category      = "CognitiveSearch"
      target        = "https://${local.resource_names.search_name}.search.windows.net"
      authType      = "AAD"
      isSharedToAll = true
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.ai_search[0].resource_id
        location   = var.location
      }
    }
  }
}

#------------------------------------------------------
# Agent Service capability host.
#
# For network-injected Foundry accounts (network_injections scenario =
# "agent") the platform AUTOMATICALLY provisions the account-level agent
# capability host ("<account>@aml_aiagentservice") at account creation, using
# the injected agent subnet as its customerSubnet. Creating a second
# account-level capability host here conflicts with that platform-managed one
# ("customerSubnet must match the subnet recorded on the Foundry account"), so
# only the project-level capability host is created below; it relies on the
# platform-provisioned account capability host.
#------------------------------------------------------
resource "azapi_resource" "project_capability_host" {
  count = local.enable_agent_service ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview"
  name      = "caphost"
  parent_id = azapi_resource.project.id

  # The azapi provider's embedded schema for
  # accounts/projects/capabilityHosts@2025-04-01-preview is stale and rejects
  # `capabilityHostKind`, which the real Azure API accepts. Disable client-side
  # schema validation for this resource only.
  schema_validation_enabled = false

  body = {
    properties = merge(
      { capabilityHostKind = "Agents" },
      local.create_agent_byo ? {
        storageConnections       = [azapi_resource.conn_storage[0].name]
        threadStorageConnections = [azapi_resource.conn_cosmos[0].name]
        vectorStoreConnections   = [azapi_resource.conn_search[0].name]
      } : {}
    )
  }

  depends_on = [
    azapi_resource.conn_storage,
    azapi_resource.conn_cosmos,
    azapi_resource.conn_search,
    time_sleep.wait_for_agent_rbac,
  ]
}
