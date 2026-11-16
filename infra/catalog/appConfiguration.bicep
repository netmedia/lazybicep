@description('{{title}} (globally unique: <name>.azconfig.io); Entra sign-in only, no access keys.')
param {{name}} string

@description('Tier of {{title}}: developer (3,000 requests a day included), free (one per subscription) or standard.')
@allowed({{sizeOptions}})
param {{size}} string = '{{sizeDefault}}'

resource {{key}} 'Microsoft.AppConfiguration/configurationStores@2024-06-01' = {
  name: {{name}}
  location: location
  tags: tags
  sku: { name: {{size}} }
  properties: {
    disableLocalAuth: true // the apps and you sign in with Entra ID
    publicNetworkAccess: 'Enabled'
  }
}

// The person running the setup writes the keys: App Configuration Data Owner.
resource {{key}}Owner 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(ownerObjectId)) {
  scope: {{key}}
  name: guid({{key}}.id, ownerObjectId, '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5ae67dd6-50cb-40e7-96ff-dc2bfa4b606b')
    principalId: ownerObjectId
    principalType: 'User'
  }
}
