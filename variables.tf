variable "location" {
  type        = string
  description = "The location/region where the resources will be created. Must be in the short form (e.g. 'uksouth') and match the 01.HubSpoke location."
  default     = "uksouth"
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.location))
    error_message = "The location must only contain lowercase letters, numbers, and hyphens"
  }
  validation {
    condition     = length(var.location) <= 20
    error_message = "The location must be 20 characters or less"
  }
}

variable "resource_name_workload" {
  type        = string
  description = "The name segment for the workload. Must match 01.HubSpoke project_prefix."
  default     = "acme"
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.resource_name_workload))
    error_message = "The name segment for the workload must only contain lowercase letters and numbers"
  }
  validation {
    condition     = length(var.resource_name_workload) <= 4
    error_message = "The name segment for the workload must be 4 characters or less"
  }
}

variable "resource_name_environment" {
  type        = string
  description = "The name segment for the environment. Must match 01.HubSpoke environment."
  default     = "dev"
  validation {
    condition     = can(regex("^[a-z0-9]+$", var.resource_name_environment))
    error_message = "The name segment for the environment must only contain lowercase letters and numbers"
  }
  validation {
    condition     = length(var.resource_name_environment) <= 4
    error_message = "The name segment for the environment must be 4 characters or less"
  }
}

variable "resource_name_sequence_start" {
  type        = number
  description = "The number to use for the resource names"
  default     = 1
  validation {
    condition     = var.resource_name_sequence_start >= 1 && var.resource_name_sequence_start <= 99
    error_message = "The number must be between 1 and 99"
  }
}

variable "tags" {
  type        = map(string)
  description = "A map of tags to add to all resources"
}

variable "admin_group_name" {
  type        = string
  description = "The display name of the Entra ID administrator group (correlates with admin_group_id). These users are the end-user owners of the AI Foundry account and project."
  validation {
    condition     = length(var.admin_group_name) >= 1 && length(var.admin_group_name) <= 256
    error_message = "The admin_group_name must be between 1 and 256 characters."
  }
}

variable "admin_group_id" {
  type        = string
  description = "The Object ID of the Entra ID group whose members will be owners/super-admins on the AI Foundry resources."
  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.admin_group_id))
    error_message = "The admin_group_id must be a valid GUID/UUID format."
  }
}

variable "log_analytics_workspace_retention_in_days" {
  type        = number
  description = "Retention period in days for the Log Analytics workspace."
  default     = 90
  validation {
    condition     = var.log_analytics_workspace_retention_in_days >= 30 && var.log_analytics_workspace_retention_in_days <= 730
    error_message = "Retention must be between 30 and 730 days."
  }
}

#------------------------------------------------------
# AI Foundry account configuration
#------------------------------------------------------
variable "ai_foundry_sku" {
  type        = string
  description = "SKU for the AI Foundry (Cognitive Services) account."
  default     = "S0"
}

variable "ai_foundry_public_network_access_enabled" {
  type        = bool
  description = "Whether public network access is allowed for the AI Foundry account and adjacent resources. Disabled by default; private endpoints are always created. Set to true only for controlled break-glass scenarios."
  default     = false
}

variable "ai_foundry_local_auth_enabled" {
  type        = bool
  description = "Whether local (key-based) authentication is enabled on the AI Foundry account. Disabled by default to enforce Entra ID authentication."
  default     = false
}

#------------------------------------------------------
# Networking mode
#------------------------------------------------------
variable "enable_private_networking" {
  type        = bool
  description = <<-EOT
    Master switch for the private, landing-zone-integrated network posture.

      * true  (default) - regulated posture: private endpoints on every service,
                          BYO subnets (private_endpoints_subnet_resource_id is
                          REQUIRED), optional BYO agent subnet for Agent Service
                          network injection, optional BYO private DNS zones. No
                          resources are exposed on the public internet unless
                          ai_foundry_public_network_access_enabled is also
                          flipped for a break-glass window.

      * false - self-contained posture: NO private endpoints, NO BYO subnets, NO
                BYO DNS. Every resource is reached over its public endpoint
                (ai_foundry_public_network_access_enabled must be true) and the
                Foundry Agent Service runs on Microsoft's platform-managed
                network. Use this for demos / greenfield subscriptions with no
                enterprise landing zone.
  EOT
  default     = true
}

#------------------------------------------------------
# Networking (bring-your-own subnets - only used when enable_private_networking = true)
#------------------------------------------------------
variable "private_endpoints_subnet_resource_id" {
  type        = string
  description = "Resource ID of the subnet that hosts the private endpoints for the AI Foundry account and all adjacent resources (storage, key vault, AI Search, Cosmos DB). Required when enable_private_networking = true; ignored otherwise."
  default     = null
  validation {
    condition     = var.private_endpoints_subnet_resource_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoints_subnet_resource_id))
    error_message = "private_endpoints_subnet_resource_id must be a full subnet resource ID (/subscriptions/.../virtualNetworks/.../subnets/...)."
  }
  validation {
    condition     = !var.enable_private_networking || var.private_endpoints_subnet_resource_id != null
    error_message = "private_endpoints_subnet_resource_id is required when enable_private_networking = true. Set enable_private_networking = false to deploy without a landing zone (public endpoints, Microsoft-managed network for agents)."
  }
}

variable "agent_subnet_resource_id" {
  type        = string
  description = "Resource ID of the delegated subnet used for Agent Service network injection. Only meaningful when enable_private_networking = true; supplying it then ENABLES the Foundry Agent Service via network injection. Ignored when enable_private_networking = false (in that mode the Agent Service always runs on Microsoft's platform-managed network)."
  default     = null
  validation {
    condition     = var.agent_subnet_resource_id == null || can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.agent_subnet_resource_id))
    error_message = "agent_subnet_resource_id must be a full subnet resource ID (/subscriptions/.../virtualNetworks/.../subnets/...)."
  }
}

#------------------------------------------------------
# Private DNS integration
#------------------------------------------------------
variable "private_dns_zone_resource_ids" {
  type = object({
    cognitiveservices  = optional(string)
    openai             = optional(string)
    ai                 = optional(string)
    blob               = optional(string)
    file               = optional(string)
    vault              = optional(string)
    search             = optional(string)
    cosmos_sql         = optional(string)
    container_registry = optional(string)
  })
  default     = {}
  description = <<-EOT
    Resource IDs of the private DNS zones to link each private endpoint to, keyed
    by zone purpose. When a zone ID is provided, a private DNS zone group
    (A-record) is created for the matching private endpoint. When omitted/null
    (the default), the private endpoint is still created but no DNS zone group is
    added, allowing the DNS records to be created out-of-band - e.g. by an Azure
    Policy 'deployIfNotExists' in a central connectivity subscription.

    Keys: cognitiveservices, openai, ai (AI Foundry account); blob, file
    (storage); vault (key vault); search (AI Search); cosmos_sql (Cosmos DB);
    container_registry (ACR privatelink.azurecr.io - only used when the Agent
    Service is enabled, which auto-provisions a Premium ACR for hosted agents).
  EOT
}

#------------------------------------------------------
# AI Foundry project configuration
#------------------------------------------------------
variable "ai_foundry_project_name" {
  type        = string
  description = "Resource name of the AI Foundry project (child of the account). Lowercase letters, numbers and hyphens."
  default     = "proj-default"
  validation {
    condition     = can(regex("^[a-zA-Z0-9-]{2,32}$", var.ai_foundry_project_name))
    error_message = "The project name must be 2-32 characters, alphanumeric and hyphens only."
  }
}

variable "ai_foundry_project_display_name" {
  type        = string
  description = "Human-friendly display name of the AI Foundry project."
  default     = "Default Project"
}

variable "ai_foundry_project_description" {
  type        = string
  description = "Description of the AI Foundry project."
  default     = "AI Foundry project provisioned by Terraform."
}

variable "ai_foundry_model_deployments" {
  type = map(object({
    model_format    = optional(string, "OpenAI")
    model_name      = string
    model_version   = optional(string)
    sku_name        = optional(string, "GlobalStandard")
    sku_capacity    = optional(number, 1)
    rai_policy_name = optional(string)
  }))
  description = <<-EOT
    Map of model deployments to create on the AI Foundry account. The map key is
    the deployment name. Example:
      {
        "gpt-4o" = { model_name = "gpt-4o", model_version = "2024-11-20", sku_capacity = 20 }
      }
  EOT
  default     = {}
}

#------------------------------------------------------
# Optional adjacent resources
#------------------------------------------------------
variable "enable_ai_search" {
  type        = bool
  description = "Provision an adjacent Azure AI Search service (private endpoint, Entra-only auth)."
  default     = false
}

variable "ai_search_sku" {
  type        = string
  description = "SKU of the Azure AI Search service when enabled."
  default     = "standard"
}

variable "enable_cosmosdb" {
  type        = bool
  description = "Provision an adjacent Azure Cosmos DB (NoSQL) account for Agent Service thread storage (private endpoint, Entra-only auth)."
  default     = false
}

#------------------------------------------------------
# Demo scaffolding (agent-demo/)
#------------------------------------------------------
variable "enable_demo_scaffolding" {
  type        = bool
  description = <<-EOT
    Provision the small set of demo resources consumed by the agent-demo/ sample
    hosted agent: a blob container (demo-data), an SMB file share (demo-share), a
    Key Vault secret (demo-flag), and a Cosmos DB SQL database (demo) + container
    (memory). Also adds the two role assignments the demo requires on top of the
    baseline admin-group roles: Storage Account Contributor (so the admin caller
    can create the file share via ARM) and Cosmos DB SQL Built-in Data Contributor
    (so a developer identity in the admin group can read/write the memory
    container from outside the hosted agent for local debugging).

    Only meaningful when the underlying optional services are enabled
    (var.enable_cosmosdb for the Cosmos parts, otherwise those resources are
    silently skipped inside demo_scaffolding.tf). The AI Search demo index is NOT
    created here - it is seeded idempotently by the running agent container.
  EOT
  default     = false
}
