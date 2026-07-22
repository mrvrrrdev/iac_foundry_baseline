#------------------------------------------------------
# Premium Azure Container Registry for Foundry hosted agents.
#
# Auto-provisioned when the Agent Service is enabled (agent subnet supplied).
# Hosted agents (`azd ai agent deploy`) pull their runtime image from an ACR
# that the project can reach privately. Regulated posture:
#   - Premium SKU (private endpoint support, zone redundancy)
#   - Zone-redundant
#   - Public network access follows the account posture (default: disabled)
#   - Admin user disabled, anonymous pull disabled
#   - Trusted Microsoft services bypass (Foundry Agent Service pull)
#   - Private endpoint on the "registry" subresource
#   - Max diagnostics to Log Analytics
#
# The Foundry MI gets AcrPull (agents pull); the admin group gets both
# AcrPush and AcrPull (build/push from CI + inspect from portal).
#------------------------------------------------------
module "container_registry" {
  count = local.enable_agent_service ? 1 : 0

  source  = "Azure/avm-res-containerregistry-registry/azurerm"
  version = "0.5.1"

  name                = local.resource_names.container_registry_name
  location            = var.location
  resource_group_name = azurerm_resource_group.foundry.name

  sku                           = "Premium"
  zone_redundancy_enabled       = true
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  data_endpoint_enabled         = true
  public_network_access_enabled = var.ai_foundry_public_network_access_enabled

  network_rule_set = var.ai_foundry_public_network_access_enabled ? null : {
    default_action = "Deny"
    ip_rule        = []
  }
  network_rule_bypass_option = "AzureServices"

  retention_policy_in_days = 30

  private_endpoints = {
    registry = {
      name                          = "${local.resource_names.container_registry_name}-pep"
      network_interface_name        = "${local.resource_names.container_registry_name}-pep-nic"
      subnet_resource_id            = local.subnet_ids.private_endpoints
      private_dns_zone_resource_ids = local.private_dns_zones.container_registry != null ? [local.private_dns_zones.container_registry] : []
      tags                          = var.tags
    }
  }

  role_assignments = {
    admin_group_acr_push = {
      role_definition_id_or_name = "AcrPush"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    admin_group_acr_pull = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    #------------------------------------------------------
    # AI Foundry managed identity - pull hosted-agent images
    #------------------------------------------------------
    foundry_mi_acr_pull = {
      role_definition_id_or_name = "AcrPull"
      principal_id               = module.foundry_managed_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
  }

  diagnostic_settings = local.diagnostic_settings
  tags                = var.tags
}
