locals {
  #------------------------------------------------------
  # Naming
  #------------------------------------------------------
  name_prefix = "${var.resource_name_workload}-${var.resource_name_environment}"
  # Compact prefix for resources that disallow hyphens (storage account)
  name_compact = "${var.resource_name_workload}${var.resource_name_environment}"
  seq          = format("%02d", var.resource_name_sequence_start)

  resource_names = {
    resource_group_name = "${local.name_prefix}-rg-foundry-${local.seq}"

    # AI Foundry (Cognitive Services / AIServices) account: 2-64 chars,
    # alphanumeric and hyphens, globally unique custom subdomain.
    ai_foundry_name = "${local.name_prefix}-aif-${local.seq}"
    foundry_mi_name = "${local.name_prefix}-id-foundry-${local.seq}"

    # Key Vault: 3-24 chars, alphanumerics and hyphens, must start with a letter.
    key_vault_name = "${local.name_prefix}-kv-fdy-${local.seq}"

    log_analytics_workspace_name = "${local.name_prefix}-log-foundry-${local.seq}"
    monitor_workspace_name       = "${local.name_prefix}-amw-foundry-${local.seq}"
    application_insights_name    = "${local.name_prefix}-appi-foundry-${local.seq}"

    # Storage account: 3-24 chars, lowercase alphanumeric only, globally unique.
    storage_account_name = "${local.name_compact}stfnd${local.seq}"

    # AI Search: 2-60 chars, lowercase letters, digits and hyphens.
    search_name = "${local.name_prefix}-srch-${local.seq}"

    # Cosmos DB: 3-44 chars, lowercase letters, digits and hyphens.
    cosmosdb_name = "${local.name_prefix}-cosmos-${local.seq}"

    # Container Registry: 5-50 chars, alphanumeric only, globally unique.
    container_registry_name = "${local.name_compact}acrfnd${local.seq}"
  }

  #------------------------------------------------------
  # Networking posture (derived from var.enable_private_networking).
  #
  # private_networking_enabled = true  => landing-zone posture:
  #   private endpoints on every service, BYO subnets, optional BYO DNS.
  #
  # private_networking_enabled = false => self-contained posture:
  #   NO private endpoints, NO subnets, NO DNS zone groups. Every resource is
  #   reached over its public endpoint and the Foundry Agent Service runs on
  #   Microsoft's platform-managed network.
  #------------------------------------------------------
  private_networking_enabled = var.enable_private_networking

  #------------------------------------------------------
  # Subnet IDs (supplied via input variables). Only consumed when private
  # networking is enabled; ignored in the self-contained posture.
  #------------------------------------------------------
  subnet_ids = {
    private_endpoints = var.private_endpoints_subnet_resource_id
    agent             = var.agent_subnet_resource_id
  }

  #------------------------------------------------------
  # Private DNS zone IDs keyed by the names used in the AVM fragments.
  # Sourced from the input variable; a null value means "no DNS zone group" - the
  # private endpoint is still created but its DNS records are managed out-of-band
  # (e.g. by an Azure Policy in a central connectivity subscription).
  # Only consulted when private_networking_enabled = true.
  #------------------------------------------------------
  private_dns_zones = var.private_dns_zone_resource_ids

  # Private DNS zone configs for the AI Foundry account private endpoint, limited
  # to the zones whose resource IDs were supplied. Empty => the self-managed zone
  # group is skipped entirely (DNS handled out-of-band, or public-only posture).
  ai_foundry_account_dns_configs = local.private_networking_enabled ? {
    for k in ["cognitiveservices", "openai", "ai"] :
    k => local.private_dns_zones[k] if local.private_dns_zones[k] != null
  } : {}

  #------------------------------------------------------
  # Agent Service enablement.
  #
  # * Landing-zone posture: enabled implicitly when an agent subnet is supplied
  #   (network injection into that subnet).
  # * Self-contained posture: always enabled - the platform runs the Agent
  #   Service on its own Microsoft-managed network; no injection is configured.
  #
  # BYO (standard) additionally requires Storage + Cosmos DB + AI Search. When
  # all three are present the capability host is wired to the adjacent
  # resources; otherwise a basic capability host is created.
  #------------------------------------------------------
  enable_agent_service = local.private_networking_enabled ? (var.agent_subnet_resource_id != null) : true

  create_agent_byo = local.enable_agent_service && var.enable_cosmosdb && var.enable_ai_search

  #------------------------------------------------------
  # Diagnostic settings -> Log Analytics workspace (max: all logs + all metrics)
  #------------------------------------------------------
  diagnostic_settings = {
    to_law = {
      name                  = "diag-to-law"
      workspace_resource_id = module.log_analytics_workspace.resource_id
      log_groups            = ["allLogs"]
      metric_categories     = ["AllMetrics"]
    }
  }

  # Cosmos DB restricts metric categories to 'SLI' and 'Requests'.
  diagnostic_settings_cosmos = {
    to_law = {
      name                  = "diag-to-law"
      workspace_resource_id = module.log_analytics_workspace.resource_id
      log_groups            = ["allLogs"]
      metric_categories     = ["Requests"]
    }
  }

  #------------------------------------------------------
  # Model deployments mapped to the AVM cognitive_deployments shape
  #------------------------------------------------------
  cognitive_deployments = {
    for name, deployment in var.ai_foundry_model_deployments : name => {
      name            = name
      rai_policy_name = deployment.rai_policy_name
      model = {
        format  = deployment.model_format
        name    = deployment.model_name
        version = deployment.model_version
      }
      scale = {
        type     = deployment.sku_name
        capacity = deployment.sku_capacity
      }
    }
  }
}
