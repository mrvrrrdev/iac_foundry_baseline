output "resource_group_name" {
  description = "AI Foundry phase resource group name."
  value       = azurerm_resource_group.foundry.name
}

output "ai_foundry_account_id" {
  description = "Resource ID of the AI Foundry (Cognitive Services) account."
  value       = module.ai_foundry.resource_id
}

output "ai_foundry_account_name" {
  description = "Name of the AI Foundry account."
  value       = local.resource_names.ai_foundry_name
}

output "ai_foundry_endpoint" {
  description = "Endpoint of the AI Foundry account."
  value       = module.ai_foundry.endpoint
}

output "ai_foundry_project_id" {
  description = "Resource ID of the AI Foundry project."
  value       = azapi_resource.project.id
}

output "ai_foundry_project_name" {
  description = "Name of the AI Foundry project."
  value       = azapi_resource.project.name
}

output "foundry_managed_identity_id" {
  description = "Resource ID of the user-assigned managed identity used by AI Foundry."
  value       = module.foundry_managed_identity.resource_id
}

output "foundry_managed_identity_principal_id" {
  description = "Principal ID of the user-assigned managed identity used by AI Foundry."
  value       = module.foundry_managed_identity.principal_id
}

output "foundry_managed_identity_client_id" {
  description = "Client ID of the stable user-assigned managed identity attached to AI Foundry. Hosted agent containers use a per-version platform identity unless the service explicitly injects a client ID."
  value       = module.foundry_managed_identity.client_id
}

output "key_vault_id" {
  description = "Resource ID of the adjacent Key Vault."
  value       = module.key_vault.resource_id
}

output "storage_account_id" {
  description = "Resource ID of the adjacent Storage account."
  value       = module.storage_account.resource_id
}

output "log_analytics_workspace_id" {
  description = "Resource ID of the Log Analytics workspace."
  value       = module.log_analytics_workspace.resource_id
}

output "monitor_workspace_id" {
  description = "Resource ID of the Azure Monitor workspace."
  value       = azurerm_monitor_workspace.monitor_workspace.id
}

output "ai_search_id" {
  description = "Resource ID of the adjacent Azure AI Search service (null when disabled)."
  value       = var.enable_ai_search ? module.ai_search[0].resource_id : null
}

output "cosmosdb_id" {
  description = "Resource ID of the adjacent Azure Cosmos DB account (null when disabled)."
  value       = var.enable_cosmosdb ? module.cosmosdb[0].resource_id : null
}

output "application_insights_id" {
  description = "Resource ID of the Application Insights component."
  value       = module.application_insights.resource_id
}

output "application_insights_connection_string" {
  description = "Connection string of the Application Insights component. Foundry SDKs and hosted agents use this to emit traces to the Foundry portal."
  value       = module.application_insights.connection_string
  sensitive   = true
}

output "container_registry_id" {
  description = "Resource ID of the Premium Container Registry (null when the Agent Service is disabled)."
  value       = local.enable_agent_service ? module.container_registry[0].resource_id : null
}

output "container_registry_login_server" {
  description = "Login server (FQDN) of the Premium Container Registry (null when the Agent Service is disabled)."
  value       = local.enable_agent_service ? module.container_registry[0].resource.login_server : null
}

#------------------------------------------------------
# Outputs consumed by agent-demo/scripts/Bootstrap-Env.ps1
#
# The demo agent's PowerShell bootstrap script reads `terraform output -json`
# and calls `azd env set` for each of these values. They are deterministic
# strings built from the module naming convention (mirrors the pattern used
# in foundry.project.tf when wiring the project connections), which keeps them
# available even before the AVM modules expose them as first-class outputs.
#------------------------------------------------------
output "container_registry_name" {
  description = "Name of the Premium Container Registry (null when the Agent Service is disabled). Consumed by agent-demo's predeploy hook as AZURE_CONTAINER_REGISTRY_NAME for az acr build."
  value       = local.enable_agent_service ? local.resource_names.container_registry_name : null
}

output "ai_foundry_project_endpoint" {
  description = "Foundry project endpoint URL. Consumed by the demo agent as AZURE_AI_PROJECT_ENDPOINT."
  value       = "https://${local.resource_names.ai_foundry_name}.services.ai.azure.com/api/projects/${azapi_resource.project.name}"
}

output "ai_foundry_account_endpoint" {
  description = "Foundry account services endpoint URL. Convenience output for tools that prefer the account-scoped endpoint."
  value       = "https://${local.resource_names.ai_foundry_name}.services.ai.azure.com/"
}

output "cosmos_endpoint" {
  description = "Cosmos DB (NoSQL) account endpoint URL (null when disabled). Consumed by the demo agent as AZURE_COSMOS_ENDPOINT."
  value       = var.enable_cosmosdb ? "https://${local.resource_names.cosmosdb_name}.documents.azure.com:443/" : null
}

output "cosmos_demo_database" {
  description = "Name of the demo Cosmos SQL database (null when demo scaffolding is disabled). Consumed as AZURE_COSMOS_DATABASE."
  value       = var.enable_demo_scaffolding && var.enable_cosmosdb ? azurerm_cosmosdb_sql_database.demo[0].name : null
}

output "cosmos_demo_memory_container" {
  description = "Name of the demo memory container inside the demo Cosmos database. Consumed as AZURE_COSMOS_MEMORY_CONTAINER."
  value       = var.enable_demo_scaffolding && var.enable_cosmosdb ? azurerm_cosmosdb_sql_container.memory[0].name : null
}

output "search_endpoint" {
  description = "AI Search service endpoint URL (null when disabled). Consumed as AZURE_SEARCH_ENDPOINT."
  value       = var.enable_ai_search ? "https://${local.resource_names.search_name}.search.windows.net" : null
}

output "key_vault_uri" {
  description = "Key Vault DNS URI (https://<name>.vault.azure.net/). Consumed as AZURE_KEY_VAULT_URI."
  value       = "https://${local.resource_names.key_vault_name}.vault.azure.net/"
}

output "storage_account_name" {
  description = "Adjacent storage account name. Consumed as AZURE_STORAGE_ACCOUNT_NAME."
  value       = local.resource_names.storage_account_name
}

output "storage_blob_endpoint" {
  description = "Blob service endpoint URL (https://<name>.blob.core.windows.net/). Consumed as AZURE_STORAGE_BLOB_ENDPOINT."
  value       = "https://${local.resource_names.storage_account_name}.blob.core.windows.net/"
}

output "storage_file_endpoint" {
  description = "File service endpoint URL (https://<name>.file.core.windows.net/). Consumed as AZURE_STORAGE_FILE_ENDPOINT."
  value       = "https://${local.resource_names.storage_account_name}.file.core.windows.net/"
}

output "demo_blob_container_name" {
  description = "Name of the demo blob container (null when demo scaffolding is disabled). Consumed as AZURE_STORAGE_DEMO_CONTAINER."
  value       = var.enable_demo_scaffolding ? azurerm_storage_container.demo_data[0].name : null
}

output "demo_file_share_name" {
  description = "Name of the demo SMB file share (null when demo scaffolding is disabled). Consumed as AZURE_STORAGE_DEMO_SHARE."
  value       = var.enable_demo_scaffolding ? azurerm_storage_share.demo_share[0].name : null
}

output "demo_kv_secret_name" {
  description = "Name of the demo Key Vault secret (null when demo scaffolding is disabled). Consumed as AZURE_KV_DEMO_SECRET_NAME."
  value       = var.enable_demo_scaffolding ? azurerm_key_vault_secret.demo_flag[0].name : null
}

output "ai_foundry_chat_model_deployment" {
  description = "Convention: the first chat model deployment key (typically 'gpt-5'). Consumed as AZURE_AI_CHAT_DEPLOYMENT."
  value = try(
    [for k, _ in var.ai_foundry_model_deployments : k if !can(regex("embedding", k))][0],
    null
  )
}

output "ai_foundry_embedding_model_deployment" {
  description = "Convention: the first embedding model deployment key (typically 'text-embedding-3-large'). Consumed as AZURE_AI_EMBEDDING_DEPLOYMENT."
  value = try(
    [for k, _ in var.ai_foundry_model_deployments : k if can(regex("embedding", k))][0],
    null
  )
}
