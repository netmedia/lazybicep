@description('{{title}} (globally unique: <name>.azurewebsites.net).')
param {{name}} string

resource {{key}} 'Microsoft.Web/sites@2024-04-01' = {
  name: {{name}}
  location: location
  kind: 'app,linux'
  tags: tags
//#if identity
  // Signs in to Azure as its own user-assigned identity only; Key Vault references too.
  identity: { type: 'UserAssigned', userAssignedIdentities: { '${{{identity}}.id}': {} } }
//#end
//#if systemIdentity
  identity: { type: 'SystemAssigned' }
//#end
  properties: {
    serverFarmId: {{hostId}}
//#if identity
    keyVaultReferenceIdentity: {{identity}}.id
//#end
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: '{{runtime}}'
      alwaysOn: true
      http20Enabled: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
//#if health
      healthCheckPath: '{{healthCheckPath}}'
//#end
      appSettings: {{settingsArray}}
    }
  }
{{dependsOn}}
}

// Deployments come from GitHub Actions with OIDC (infra/README.md), so no FTP or basic-auth publishing.
resource {{key}}Ftp 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: {{key}}
  name: 'ftp'
  properties: { allow: false }
}

resource {{key}}Scm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2024-04-01' = {
  parent: {{key}}
  name: 'scm'
  properties: { allow: false }
}
