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
