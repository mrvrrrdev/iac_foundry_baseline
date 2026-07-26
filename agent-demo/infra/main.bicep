// -----------------------------------------------------------------------------
// No-op Bicep template for the agent-demo azd project.
//
// The entire Foundry landing zone (resource group, Foundry account/project,
// Cosmos DB, AI Search, Key Vault, Storage, ACR, App Insights, Log Analytics,
// Monitor Workspace, private endpoints, RBAC, BYO Agent Service capability
// host, model deployments, plus the agent-demo scaffolding container / share
// / secret / cosmos db) is provisioned by the Terraform stack at the repo
// root (../*.tf) via a separate `terraform apply` step BEFORE `azd up` runs.
//
// azd's provision phase still needs *something* to deploy — and its ARM
// preflight rejects templates with zero resources ("ARM template contains no
// resources"). So this file declares exactly one placeholder resource: a
// nested `Microsoft.Resources/deployments` whose inner template is itself
// empty. The nested deployment runs in a few seconds, creates zero Azure
// resources, and the real work happens in `azd deploy` where the
// azure.ai.agents extension registers the agent revision against the
// pre-existing Foundry project.
// -----------------------------------------------------------------------------

targetScope = 'resourceGroup'

#disable-next-line no-deployments-resources
resource noop 'Microsoft.Resources/deployments@2022-09-01' = {
  name: 'agent-demo-noop'
  properties: {
    mode: 'Incremental'
    expressionEvaluationOptions: {
      scope: 'inner'
    }
    template: {
      '$schema': 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
      contentVersion: '1.0.0.0'
      resources: []
      outputs: {
        message: {
          type: 'string'
          value: 'agent-demo infrastructure is provisioned by the Terraform stack at the repo root; this azd provision step is intentionally a no-op.'
        }
      }
    }
  }
}

output noopMessage string = noop.properties.outputs.message.value
