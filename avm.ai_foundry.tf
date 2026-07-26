#------------------------------------------------------
# AI Foundry account (Cognitive Services, kind = AIServices).
#
# Regulated-enterprise posture:
#   - project management enabled (Foundry projects as child resources)
#   - system-assigned + user-assigned managed identity
#   - local (key) auth disabled by default
#   - public network access disabled by default (private endpoints only)
#   - private endpoint bound to cognitiveservices + openai + services.ai zones
#   - agent network injection into the delegated agent subnet
#   - model deployments driven from input
#   - max diagnostics to Log Analytics
#------------------------------------------------------
module "ai_foundry" {
  source  = "Azure/avm-res-cognitiveservices-account/azurerm"
  version = "0.11.1"

  kind                  = "AIServices"
  name                  = local.resource_names.ai_foundry_name
  location              = var.location
  parent_id             = azurerm_resource_group.foundry.id
  sku_name              = var.ai_foundry_sku
  custom_subdomain_name = local.resource_names.ai_foundry_name

  # Foundry project management (projects as child resources).
  allow_project_management = true

  # Entra ID-only auth and private-by-default posture.
  local_auth_enabled            = var.ai_foundry_local_auth_enabled
  public_network_access_enabled = var.ai_foundry_public_network_access_enabled

  network_acls = {
    default_action = var.ai_foundry_public_network_access_enabled ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  managed_identities = {
    system_assigned            = true
    user_assigned_resource_ids = [module.foundry_managed_identity.resource_id]
  }

  # Model deployments (serialized to avoid 409 conflicts).
  cognitive_deployments = local.cognitive_deployments

  # Agent Service network injection into the delegated agent subnet. Only used
  # in the landing-zone posture (private_networking_enabled = true) with a
  # supplied agent subnet. In the self-contained posture the Agent Service
  # runs on Microsoft's platform-managed network - no injection is configured.
  network_injections = local.enable_agent_service && local.private_networking_enabled ? {
    subnet_id                         = local.subnet_ids.agent
    scenario                          = "agent"
    microsoft_managed_network_enabled = false
  } : null

  # The AVM module delegates private DNS zone group creation to avm-utl-interfaces
  # (0.6.0), which names every privateDnsZoneConfig after the zone GROUP name.
  # With multiple zones on one private endpoint this emits duplicate "default"
  # configs -> ARM DuplicateResourceName. Both modules are at their latest with no
  # upstream fix, so DNS zone group management is disabled here and the zone group
  # is created directly in azapi_resource.ai_foundry_account_pe_dns_zone_group.
  private_endpoints_manage_dns_zone_group = false

  private_endpoints = local.private_networking_enabled ? {
    account = {
      name                   = "${local.resource_names.ai_foundry_name}-pep"
      network_interface_name = "${local.resource_names.ai_foundry_name}-pep-nic"
      subnet_resource_id     = local.subnet_ids.private_endpoints
      tags                   = var.tags
    }
  } : {}

  # NOTE: "Azure AI Developer" is intentionally NOT assigned here. This module's
  # role-assignment helper only treats role names containing "Cognitive Services"
  # as role NAMES; any other value is passed as a role definition ID, so a
  # friendly name like "Azure AI Developer" becomes a malformed roleDefinitionId
  # (400 BadRequestFormat). It is assigned directly in rbac.tf instead.
  role_assignments = {
    admin_group_openai_contributor = {
      role_definition_id_or_name = "Cognitive Services OpenAI Contributor"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    admin_group_cognitive_user = {
      role_definition_id_or_name = "Cognitive Services User"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    # Portal write-back on account-scope settings the Foundry UI touches
    # (model deployments, RAI policies, connections, capability host state).
    # Without this the portal returns AuthorizationFailed on edits even though
    # the group can read/build agents. Least-privilege control-plane role for
    # Foundry admins.
    admin_group_cognitive_contributor = {
      role_definition_id_or_name = "Cognitive Services Contributor"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
  }

  diagnostic_settings = local.diagnostic_settings
  tags                = var.tags

  timeouts = {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  # The account create validates the user-assigned identity through a different
  # resource provider; wait for cross-RP propagation to avoid intermittent
  # "User Assigned Identity not found" failures on fresh deployments.
  depends_on = [time_sleep.wait_for_identity]
}

#------------------------------------------------------
# Account private endpoint DNS zone group (self-managed, optional).
#
# Replaces the AVM module's built-in DNS zone group management, which is disabled
# on the module above because avm-utl-interfaces 0.6.0 assigns every
# privateDnsZoneConfig the same name ("default"), producing an ARM
# DuplicateResourceName error when a private endpoint targets multiple zones
# (cognitiveservices + openai + ai).
#
# Created only for the zones whose resource IDs are supplied via
# var.private_dns_zone_resource_ids. When none are supplied the private endpoint
# is still created but no DNS zone group is added, so the A-records can be managed
# out-of-band (e.g. by an Azure Policy in a central connectivity subscription).
#------------------------------------------------------
resource "azapi_resource" "ai_foundry_account_pe_dns_zone_group" {
  count = length(local.ai_foundry_account_dns_configs) > 0 ? 1 : 0

  type      = "Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01"
  name      = "default"
  parent_id = module.ai_foundry.private_endpoints["account"].id

  body = {
    properties = {
      privateDnsZoneConfigs = [
        for zone_name, zone_id in local.ai_foundry_account_dns_configs : {
          name = zone_name
          properties = {
            privateDnsZoneId = zone_id
          }
        }
      ]
    }
  }
}
