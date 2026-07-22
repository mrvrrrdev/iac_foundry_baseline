#------------------------------------------------------
# Application Insights (workspace-backed) for Foundry agent tracing and
# observability. Always deployed - the Foundry portal Tracing / Evaluations
# panels rely on an App Insights connection on the account (see
# foundry.project.tf -> azapi_resource.conn_appinsights).
#
# Public ingestion is used (per plan / user choice). A future opt-in AMPLS
# private-link scope can be added without changing the module surface.
#------------------------------------------------------
module "application_insights" {
  source  = "Azure/avm-res-insights-component/azurerm"
  version = "0.4.0"

  name                = local.resource_names.application_insights_name
  location            = var.location
  resource_group_name = azurerm_resource_group.foundry.name

  workspace_id      = module.log_analytics_workspace.resource_id
  application_type  = "web"
  retention_in_days = var.log_analytics_workspace_retention_in_days

  # Entra-only ingest and query (matches the regulated posture of the rest of
  # the module). Public network access stays enabled so the Foundry portal
  # Tracing tab can read telemetry without AMPLS.
  local_authentication_disabled = true
  internet_ingestion_enabled    = true
  internet_query_enabled        = true

  role_assignments = {
    admin_group_monitoring_contributor = {
      role_definition_id_or_name = "Monitoring Contributor"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    # The Foundry MI writes traces from agent runs into App Insights. Data-plane
    # ingest role for a workspace-backed component.
    foundry_mi_monitoring_metrics_publisher = {
      role_definition_id_or_name = "Monitoring Metrics Publisher"
      principal_id               = module.foundry_managed_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
  }

  # Diagnostic settings on the App Insights component itself are intentionally
  # omitted: telemetry already routes to Log Analytics via workspace_id above,
  # so a separate diagnostic-settings pipe would be duplicate ingest.
  tags = var.tags
}
