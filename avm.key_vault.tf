module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.2"

  name                           = local.resource_names.key_vault_name
  location                       = var.location
  resource_group_name            = azurerm_resource_group.foundry.name
  tenant_id                      = data.azurerm_client_config.current.tenant_id
  legacy_access_policies_enabled = false
  sku_name                       = "standard"
  public_network_access_enabled  = var.ai_foundry_public_network_access_enabled
  purge_protection_enabled       = false
  soft_delete_retention_days     = 90

  network_acls = {
    default_action = var.ai_foundry_public_network_access_enabled ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }

  private_endpoints = {
    vault = {
      name                          = "${local.resource_names.key_vault_name}-pep-vault"
      network_interface_name        = "${local.resource_names.key_vault_name}-pep-vault-nic"
      private_dns_zone_resource_ids = local.private_dns_zones.vault != null ? [local.private_dns_zones.vault] : []
      subnet_resource_id            = local.subnet_ids.private_endpoints
      subresource_name              = ["vault"]
      tags                          = var.tags
    }
  }

  role_assignments = {
    admin_group_key_vault_administrator = {
      role_definition_id_or_name = "Key Vault Administrator"
      principal_id               = var.admin_group_id
      principal_type             = "Group"
    }
    #------------------------------------------------------
    # AI Foundry managed identity - read secrets for BYO connections
    #------------------------------------------------------
    foundry_mi_key_vault_secrets_user = {
      role_definition_id_or_name = "Key Vault Secrets User"
      principal_id               = module.foundry_managed_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
  }

  diagnostic_settings = local.diagnostic_settings
  tags                = var.tags
}
