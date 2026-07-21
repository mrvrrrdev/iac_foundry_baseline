#------------------------------------------------------
# Resource group for all AI Foundry-phase resources
#------------------------------------------------------
resource "azurerm_resource_group" "foundry" {
  name     = local.resource_names.resource_group_name
  location = var.location
  tags     = var.tags
}

#------------------------------------------------------
# User-assigned managed identity used by the AI Foundry
# account and project to authenticate to the adjacent
# bring-your-own dependencies (Storage, Key Vault, AI Search,
# Cosmos DB) with Entra ID / RBAC.
#------------------------------------------------------
module "foundry_managed_identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.0"

  name                = local.resource_names.foundry_mi_name
  location            = var.location
  resource_group_name = azurerm_resource_group.foundry.name

  tags = var.tags
}

#------------------------------------------------------
# Propagation delay for the user-assigned managed identity.
#
# The AI Foundry (Cognitive Services / AmlRp) account create validates the
# user-assigned identity via a different resource provider. Immediately after the
# identity is created, cross-RP replication can lag, causing the account create to
# fail with "User Assigned Identity not found". This delay lets the identity
# propagate before the account (and project) reference it.
#------------------------------------------------------
resource "time_sleep" "wait_for_identity" {
  create_duration = "60s"

  triggers = {
    identity_id = module.foundry_managed_identity.resource_id
  }

  depends_on = [module.foundry_managed_identity]
}
