module "log_analytics_workspace" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  name                                      = local.resource_names.log_analytics_workspace_name
  location                                  = var.location
  resource_group_name                       = azurerm_resource_group.foundry.name
  tags                                      = var.tags
  log_analytics_workspace_retention_in_days = var.log_analytics_workspace_retention_in_days

  # Allow query access from the internet (portal/log queries). Ingestion from
  # the private workloads still traverses the VNet/Firewall.
  log_analytics_workspace_internet_query_enabled = "true"

  role_assignments = {
    admin_group_log_analytics_contributor = {
      role_definition_id_or_name = "Log Analytics Contributor"
      principal_id               = var.admin_group_id
    }
  }
}
