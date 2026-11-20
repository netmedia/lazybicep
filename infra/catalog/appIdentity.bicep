@description('{{title}} (3-128 letters, digits, hyphens and underscores): the user-assigned managed identity only {{owner}} signs in with.')
param {{name}} string

// Made before its app, so the app's role assignments (to this identity) exist when the app first starts.
resource {{key}} 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: {{name}}
  location: location
  tags: tags
}
