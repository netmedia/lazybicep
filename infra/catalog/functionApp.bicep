@description('{{title}} (globally unique: <name>.azurewebsites.net).')
param {{name}} string
//#if flex

// Where the Flex Consumption app's packages go (a container of {{storageTitle}}). By its full name: an
// "existing" blob service per app would name the same resource twice when two apps share the storage (BCP121).
resource {{key}}Packages 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: '${{{storage}}.name}/default/{{container}}'
  properties: { publicAccess: 'None' }
}
//#end

resource {{key}} 'Microsoft.Web/sites@2024-04-01' = {
  name: {{name}}
  location: location
  kind: 'functionapp,linux'
  tags: tags
//#if identity
  // Signs in to Azure as its own user-assigned identity only: its host's storage, triggers, Key Vault references.
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
//#if flex
    functionAppConfig: {
      deployment: {
        storage: {
          type: 'blobContainer'
          value: '${{{storage}}.properties.primaryEndpoints.blob}{{container}}'
          authentication: {{deploymentAuthentication}}
        }
      }
      scaleAndConcurrency: { maximumInstanceCount: 40, instanceMemoryMB: 2048 }
      runtime: { name: '{{runtimeName}}', version: '{{runtimeVersion}}' }
    }
    siteConfig: {
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: {{settingsArray}}
    }
//#end
//#if plan
    siteConfig: {
      linuxFxVersion: '{{runtime}}'
      alwaysOn: true
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: {{settingsArray}}
    }
//#end
  }
{{dependsOn}}
}

// Deployments come from GitHub Actions with OIDC, so no FTP or basic-auth publishing.
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
