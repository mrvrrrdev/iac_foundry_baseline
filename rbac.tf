#------------------------------------------------------
# Predefined RBAC for the AI Foundry project and the Foundry
# managed identity. Account-scoped and adjacent-resource role
# assignments are defined inline in their respective module
# blocks; this file covers project-scope and cross-resource
# assignments.
#------------------------------------------------------

#------------------------------------------------------
# Foundry User role definition ID.
#
# Assigned by role definition ID (not name) because the Foundry RBAC roles were
# recently renamed - "Foundry User" was previously "Azure AI User" and the name
# may not resolve in every tenant during the rename rollout. The role ID is
# stable. This is the least-privilege role for building and testing agents in a
# Foundry project (grants project data actions + reader on account/project).
#
# NOTE: the "Azure AI Developer" role is deliberately NOT used here - despite the
# name it is scoped to Azure ML workspaces / Foundry hubs, not project-based
# Foundry accounts, so it does not grant agent-building permissions.
#------------------------------------------------------
locals {
  foundry_user_role_definition_id = "/subscriptions/${data.azurerm_client_config.current.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/53ca6127-db72-4b80-b1b0-d745d6d5456d"
}

#------------------------------------------------------
# Admin group - Foundry User on the AI Foundry account (Foundry resource scope).
#
# Grants owners/developers in the admin group the ability to build and test
# agents in every project under the account. Assigned at account scope (which
# includes child projects) per the Foundry "minimum role assignments" guidance.
#------------------------------------------------------
resource "azurerm_role_assignment" "admin_account_foundry_user" {
  scope              = module.ai_foundry.resource_id
  role_definition_id = local.foundry_user_role_definition_id
  principal_id       = var.admin_group_id
  principal_type     = "Group"
}

#------------------------------------------------------
# Project managed identity - Foundry User on the AI Foundry account.
#
# The project's managed identity also requires the Foundry User role on the
# Foundry resource so the project can access Foundry features (documented
# minimum assignment alongside the user-principal grant above).
#------------------------------------------------------
resource "azurerm_role_assignment" "foundry_mi_foundry_user" {
  scope              = module.ai_foundry.resource_id
  role_definition_id = local.foundry_user_role_definition_id
  principal_id       = module.foundry_managed_identity.principal_id
  principal_type     = "ServicePrincipal"
}

#------------------------------------------------------
# Project system-assigned managed identity - Foundry User on the project.
#
# The project has its OWN system-assigned managed identity (distinct from the
# user-assigned identity above). Platform features such as Agent Service memory
# use this project identity, which the portal reports as needing the Foundry
# User role "on this project" (Setup incomplete / Resolve). Assigned at project
# scope to match the portal Resolve action and keep the grant least-privilege.
#
# principal_id comes from the project's exported system-assigned identity
# (azapi_resource.project response_export_values = ["identity.principalId"]).
#------------------------------------------------------
resource "azurerm_role_assignment" "foundry_project_mi_foundry_user" {
  scope              = azapi_resource.project.id
  role_definition_id = local.foundry_user_role_definition_id
  principal_id       = azapi_resource.project.output.identity.principalId
  principal_type     = "ServicePrincipal"
}

#------------------------------------------------------
# Foundry managed identity - invoke deployed models (agents)
#------------------------------------------------------
resource "azurerm_role_assignment" "foundry_mi_openai_user" {
  scope                = module.ai_foundry.resource_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.foundry_managed_identity.principal_id
  principal_type       = "ServicePrincipal"
}

#------------------------------------------------------
# Foundry managed identity - Cosmos DB data-plane access for
# Agent Service thread storage (built-in Data Contributor).
# Cosmos data-plane RBAC uses the Cosmos SQL role model, which is
# separate from Azure control-plane role assignments.
#------------------------------------------------------
resource "azurerm_cosmosdb_sql_role_assignment" "foundry_mi_cosmos_data_contributor" {
  count = var.enable_cosmosdb ? 1 : 0

  resource_group_name = azurerm_resource_group.foundry.name
  account_name        = local.resource_names.cosmosdb_name
  role_definition_id  = "${module.cosmosdb[0].resource_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = module.foundry_managed_identity.principal_id
  scope               = module.cosmosdb[0].resource_id
}

#------------------------------------------------------
# Admin group - Reader on the resource group.
#
# Portal navigation across the Foundry blade and every adjacent resource
# requires read on the containing RG. Without this the Foundry portal shows
# empty side-nav sections for group members who otherwise have all the
# resource-scope roles above.
#------------------------------------------------------
resource "azurerm_role_assignment" "admin_group_rg_reader" {
  scope                = azurerm_resource_group.foundry.id
  role_definition_name = "Reader"
  principal_id         = var.admin_group_id
  principal_type       = "Group"
}

#------------------------------------------------------
# Foundry managed identity - BYO Agent Service store provisioning.
#
# The project capability host provisions the agent's file storage, thread
# storage (Cosmos "enterprise_memory" database) and vector store USING the
# Foundry managed identity. That requires control-plane access on Cosmos DB and
# management access on Storage and AI Search, in addition to the Cosmos
# data-plane role above. Without these the capability host fails with
# CapabilityHostOperationFailed / "does not have authorization".
#------------------------------------------------------

# Cosmos DB control plane: create the enterprise_memory database and containers.
resource "azurerm_role_assignment" "foundry_mi_cosmos_operator" {
  count                = var.enable_cosmosdb ? 1 : 0
  scope                = module.cosmosdb[0].resource_id
  role_definition_name = "Cosmos DB Operator"
  principal_id         = module.foundry_managed_identity.principal_id
  principal_type       = "ServicePrincipal"
}

# Allow the new agent RBAC assignment to propagate before the capability host
# provisions the BYO stores (avoids "access recently granted" races). The
# Storage Blob Data Contributor and AI Search index/service roles the agent also
# needs are already granted to this identity by the storage and search module
# blocks (avm.storage_account.tf / avm.ai_search.tf).
resource "time_sleep" "wait_for_agent_rbac" {
  count           = local.enable_agent_service ? 1 : 0
  create_duration = "120s"

  depends_on = [
    azurerm_role_assignment.foundry_mi_cosmos_operator,
    azurerm_cosmosdb_sql_role_assignment.foundry_mi_cosmos_data_contributor,
  ]
}
