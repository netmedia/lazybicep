@description('{{title}} (5-50 letters and digits, globally unique: <name>.azurecr.io).')
@minLength(5)
@maxLength(50)
param {{name}} string

@description('Tier of {{title}}: Basic to start; Standard and Premium for more storage and throughput.')
@allowed({{sizeOptions}})
param {{size}} string = '{{sizeDefault}}'

// No admin user and no anonymous pull: the apps pull with their own identities (AcrPull), GitHub Actions pushes
// with OIDC (AcrPush) - no registry password anywhere.
resource {{key}} 'Microsoft.ContainerRegistry/registries@2025-04-01' = {
  name: {{name}}
  location: location
  tags: tags
  sku: { name: {{size}} }
  properties: {
    adminUserEnabled: false
    anonymousPullEnabled: false
  }
}
