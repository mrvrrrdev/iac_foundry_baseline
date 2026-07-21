#------------------------------------------------------
# Providers for the 04.AIFoundry phase
#
# The AI Foundry phase is deployed AFTER 01.HubSpoke (which
# provisions the dedicated Foundry spoke VNet, subnets, Azure
# Firewall egress rules and private DNS zones). It consumes
# those resources via azurerm data sources (looked up by name)
# and keeps its own Terraform state, separate from 01/02/03.
#
# azapi is used for the AI Foundry project, connections and the
# Agent Service capability host, which are not yet exposed by
# the azurerm provider.
#------------------------------------------------------
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }

  # Use Entra ID (AAD) for Storage and Key Vault data-plane calls.
  storage_use_azuread = true
}

provider "azapi" {}
