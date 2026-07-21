#------------------------------------------------------
# Azure Monitor workspace (Managed Prometheus) adjacent to AI Foundry.
#------------------------------------------------------
resource "azurerm_monitor_workspace" "monitor_workspace" {
  name                = local.resource_names.monitor_workspace_name
  location            = var.location
  resource_group_name = azurerm_resource_group.foundry.name

  public_network_access_enabled = true

  tags = var.tags
}

#------------------------------------------------------
# Admin Group - Data-plane access to Azure Monitor Workspace.
# Querying metrics requires the data-plane role "Monitoring Data Reader"
# on the workspace itself.
#------------------------------------------------------
resource "azurerm_role_assignment" "admin_group_monitor_data_reader" {
  scope                = azurerm_monitor_workspace.monitor_workspace.id
  role_definition_name = "Monitoring Data Reader"
  principal_id         = var.admin_group_id
}
