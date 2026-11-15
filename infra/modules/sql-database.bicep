// A database on a SQL server (infra/catalog/sqlDatabase.bicep), deployed in the server's resource group.

param serverName string

@description('The region of the server (infra/azure-setup.ps1 checks that a shared one is in the environment\'s region).')
param location string
param name string

@description('Basic, S0, S1... (DTU), or GP_S_Gen5_<vCores> (serverless).')
param sku string
param tags object

@description('Production: 35 days of point-in-time restore (Basic: 7, its limit) and long-term retention (Netmedia Azure Conventions 7.1).')
param production bool = false

var serverless = startsWith(sku, 'GP_S_')
var tier = sku == 'Basic' ? 'Basic' : (startsWith(sku, 'S') ? 'Standard' : 'GeneralPurpose')

resource server 'Microsoft.Sql/servers@2023-08-01' existing = {
  name: serverName
}

resource database 'Microsoft.Sql/servers/databases@2023-08-01' = {
  parent: server
  name: name
  location: location
  tags: tags
  sku: serverless ? { name: 'GP_S_Gen5', tier: tier, family: 'Gen5', capacity: int(last(split(sku, '_'))) } : { name: sku, tier: tier }
  properties: serverless ? { autoPauseDelay: 60, minCapacity: json('0.5') } : {}
}

// Production backups: the last way back after a failed or destructive migration (AZ 7.1).
resource shortTermRetention 'Microsoft.Sql/servers/databases/backupShortTermRetentionPolicies@2023-08-01' = if (production) {
  parent: database
  name: 'default'
  properties: { retentionDays: tier == 'Basic' ? 7 : 35 }
}

resource longTermRetention 'Microsoft.Sql/servers/databases/backupLongTermRetentionPolicies@2023-08-01' = if (production) {
  parent: database
  name: 'default'
  properties: { weeklyRetention: 'P4W', monthlyRetention: 'P12M', yearlyRetention: 'P5Y', weekOfYear: 1 }
}
