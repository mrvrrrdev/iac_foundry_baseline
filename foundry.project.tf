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
# Application Insights project connection.
#
# Always created (App Insights is unconditional in this module). Wires the
# Foundry portal Tracing / Evaluations panels to the workspace-backed App
# Insights component so agent traces surface automatically. Uses the connection
# string (documented category = "AppInsights", authType = "ApiKey" for the
# instrumentation-key/connection-string style connection).
#------------------------------------------------------
resource "azapi_resource" "conn_appinsights" {
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "appinsightsconn"
  parent_id = azapi_resource.project.id

  body = {
    properties = {
      category      = "AppInsights"
      target        = module.application_insights.resource_id
      authType      = "ApiKey"
      isSharedToAll = true
      credentials = {
        key = module.application_insights.connection_string
      }
      metadata = {
        ApiType    = "Azure"
        ResourceId = module.application_insights.resource_id
        location   = var.location
      }
    }
  }
}

#------------------------------------------------------
# Agent Service capability host.
#
# Two flavours depending on the network posture:
#
# * Landing-zone posture (private_networking_enabled = true, network injection
#   configured): the platform AUTOMATICALLY provisions the account-level agent
#   capability host ("<account>@aml_aiagentservice") at account creation,
#   using the injected agent subnet as its customerSubnet. Creating a second
#   account-level capability host in that case conflicts with the platform-
#   managed one ("customerSubnet must match the subnet recorded on the Foundry
#   account"), so we only create the project-level capability host and let it
#   inherit from the platform-provisioned account one.
#
# * Self-contained posture (private_networking_enabled = false, no network
#   injection): the platform does NOT auto-provision an account-level
#   capability host. Trying to create the project-level one first fails with:
#     "Foundry Account capabilityHost Not Found, please retry again after
#      creating capabilityHost for the Foundry Account."
#   In that case we create a basic (no customerSubnet) account-level capability
#   host here and make the project-level one depend on it.
#------------------------------------------------------
resource "azapi_resource" "account_capability_host" {
  count = local.enable_agent_service && !local.private_networking_enabled ? 1 : 0

  type      = "Microsoft.CognitiveServices/accounts/capabilityHosts@2025-04-01-preview"
  name      = "caphost"
  parent_id = module.ai_foundry.resource_id

  # The azapi provider's embedded schema for
  # accounts/capabilityHosts@2025-04-01-preview is stale (same story as the
  # project-level resource below) and rejects `capabilityHostKind`, which the
  # real Azure API accepts. Disable client-side schema validation.
  schema_validation_enabled = false

  body = {
    properties = {
      capabilityHostKind = "Agents"
    }
  }

  # The account resource (including model deployments and role assignments in
  # the AVM module) must be fully created before the account-level capability
  # host is provisioned.
  depends_on = [module.ai_foundry]
}

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
    azapi_resource.account_capability_host,
    azapi_resource.conn_storage,
    azapi_resource.conn_cosmos,
    azapi_resource.conn_search,
    time_sleep.wait_for_agent_rbac,
  ]
}
