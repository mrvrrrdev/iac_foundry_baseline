#------------------------------------------------------
# Demo scaffolding for the agent-demo/ sample hosted agent.
#
# Everything in this file is gated by var.enable_demo_scaffolding (default true).
# Setting it to false leaves NO trace of the demo in the environment - the file
# is safe to delete entirely along with the agent-demo/ folder if the demo is
# ever retired.
#
# What this file creates (in the existing adjacent resources - no new accounts):
#   * Storage blob container `demo-data`
#   * Storage SMB file share `demo-share` (100 GiB quota)
#   * Key Vault secret `demo-flag` (sentinel value the agent's KV tool reads)
#   * Cosmos DB SQL database `demo` (only when enable_cosmosdb = true)
#   * Cosmos DB container `memory` (partition /userId, autoscale 1000 RU)
#
# What this file does NOT create:
#   * The AI Search index used by the KB tool - the agent container creates it
#     idempotently on first boot (see agent-demo/src/bootstrap.py). AI Search
#     index creation is a data-plane call and is naturally handled from inside
#     the VNet under the Foundry MI which already holds Search Index Data
#     Contributor. Keeping it out of Terraform also avoids an
#     out-of-VNet apply-time dependency.
#
# Additional RBAC (scoped to enable_demo_scaffolding, symmetric with the roles
# already granted inside the adjacent-resource module blocks):
#   * Admin group -> Storage Account Contributor on the storage account.
#     "Storage Blob Data Owner" (already granted) covers ARM container writes,
#     but SMB file-share ARM creation requires
#     Microsoft.Storage/storageAccounts/fileServices/shares/write, which is only
#     included in Storage Account Contributor / Contributor. Grant the minimum
#     that lets the admin caller create the demo share.
#   * Admin group -> Cosmos DB SQL Built-in Data Contributor (data plane).
#     The admin group already has Cosmos DB Operator (control plane) but not
#     data plane. Not required for the primary Windows/PS deploy flow (all
#     runtime data-plane access is via the Foundry MI which already has this
#     role), but useful for local debugging / manual verification of the memory
#     container under a developer identity.
#------------------------------------------------------

#------------------------------------------------------
# Storage: blob container `demo-data`
#
# Uses the ARM path (storage_account_id form). Admin group already holds
# "Storage Blob Data Owner" on the account, which includes
# Microsoft.Storage/storageAccounts/blobServices/containers/write, so no extra
# RBAC is needed for container creation itself.
#------------------------------------------------------
resource "azurerm_storage_container" "demo_data" {
  count = var.enable_demo_scaffolding ? 1 : 0

  name                  = "demo-data"
  storage_account_id    = module.storage_account.resource_id
  container_access_type = "private"

  depends_on = [module.storage_account]
}

#------------------------------------------------------
# Storage: SMB file share `demo-share`
#
# Requires Storage Account Contributor on the caller (see role assignment
# below); Storage File Data Privileged Contributor is only enough for
# data-plane file operations, not for ARM share creation.
#------------------------------------------------------
resource "azurerm_storage_share" "demo_share" {
  count = var.enable_demo_scaffolding ? 1 : 0

  name               = "demo-share"
  storage_account_id = module.storage_account.resource_id
  quota              = 100
  enabled_protocol   = "SMB"

  depends_on = [
    module.storage_account,
    azurerm_role_assignment.admin_group_storage_account_contributor,
  ]
}

#------------------------------------------------------
# Admin group -> Storage Account Contributor
#
# Needed for the file share create above (ARM share write). Blob container
# creation is already covered by the group's existing Storage Blob Data Owner
# assignment inside avm.storage_account.tf.
#------------------------------------------------------
resource "azurerm_role_assignment" "admin_group_storage_account_contributor" {
  count = var.enable_demo_scaffolding ? 1 : 0

  scope                = module.storage_account.resource_id
  role_definition_name = "Storage Account Contributor"
  principal_id         = var.admin_group_id
  principal_type       = "Group"
}

#------------------------------------------------------
# Key Vault: demo secret `demo-flag`
#
# Sentinel value read by the agent's KV tool. Admin group already has "Key Vault
# Administrator" on the vault (avm.key_vault.tf), which covers secret create.
#------------------------------------------------------
resource "azurerm_key_vault_secret" "demo_flag" {
  count = var.enable_demo_scaffolding ? 1 : 0

  name         = "demo-flag"
  value        = "hello-from-key-vault"
  key_vault_id = module.key_vault.resource_id
  content_type = "text/plain"

  tags = var.tags

  depends_on = [module.key_vault]
}

#------------------------------------------------------
# Cosmos DB: demo database + memory container
#
# Only created when the Cosmos account itself is provisioned
# (var.enable_cosmosdb = true). Both use control-plane calls; admin group's
# Cosmos DB Operator (avm.cosmosdb.tf) is sufficient. The Foundry MI already
# has Cosmos DB Operator + built-in Data Contributor for the runtime data-plane
# path used by the agent.
#------------------------------------------------------
resource "azurerm_cosmosdb_sql_database" "demo" {
  count = var.enable_demo_scaffolding && var.enable_cosmosdb ? 1 : 0

  name                = "demo"
  resource_group_name = azurerm_resource_group.foundry.name
  account_name        = local.resource_names.cosmosdb_name

  depends_on = [module.cosmosdb]
}

resource "azurerm_cosmosdb_sql_container" "memory" {
  count = var.enable_demo_scaffolding && var.enable_cosmosdb ? 1 : 0

  name                = "memory"
  resource_group_name = azurerm_resource_group.foundry.name
  account_name        = local.resource_names.cosmosdb_name
  database_name       = azurerm_cosmosdb_sql_database.demo[0].name

  partition_key_paths = ["/userId"]

  # Small footprint: autoscale with 1000 RU/s max (scales down to 100 RU/s
  # minimum billed floor). Overkill for the demo but the smallest supported
  # autoscale window.
  autoscale_settings {
    max_throughput = 1000
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }
  }
}

#------------------------------------------------------
# Admin group -> Cosmos DB SQL Built-in Data Contributor (data plane)
#
# Cosmos data-plane RBAC uses the Cosmos SQL role model, separate from Azure
# control-plane role assignments. Role definition ID
# 00000000-0000-0000-0000-000000000002 is the built-in "Cosmos DB Built-in Data
# Contributor" (read + write on all data). Not required for the primary
# Windows/PS deploy flow (the hosted agent uses the Foundry MI which already
# holds this role), but keeps the door open for developers in the admin group
# to inspect / repair the memory container manually.
#------------------------------------------------------
resource "azurerm_cosmosdb_sql_role_assignment" "admin_group_data_contributor" {
  count = var.enable_demo_scaffolding && var.enable_cosmosdb ? 1 : 0

  resource_group_name = azurerm_resource_group.foundry.name
  account_name        = local.resource_names.cosmosdb_name
  role_definition_id  = "${module.cosmosdb[0].resource_id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002"
  principal_id        = var.admin_group_id
  scope               = module.cosmosdb[0].resource_id
}
