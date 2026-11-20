@description('{{title}}: the Container Apps environment its apps run in.')
param {{name}} string

// Workload profiles with the Consumption profile only: billed per use, scales to zero. Logs go to Azure
// Monitor and from there to {{workspaceTitle}} (the diagnostic setting below): no workspace shared key here.
resource {{key}} 'Microsoft.App/managedEnvironments@2025-07-01' = {
  name: {{name}}
  location: location
  tags: tags
  properties: {
    appLogsConfiguration: { destination: 'azure-monitor' }
    workloadProfiles: [
      { name: 'Consumption', workloadProfileType: 'Consumption' }
    ]
    zoneRedundant: false
  }
}

resource {{key}}Logs 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'send-to-${{{workspaceName}}}'
  scope: {{key}}
  properties: {
    workspaceId: {{workspaceId}}
    logAnalyticsDestinationType: 'Dedicated'
    logs: [
      { category: 'ContainerAppConsoleLogs', enabled: true }
      { category: 'ContainerAppSystemLogs', enabled: true }
    ]
  }
}
