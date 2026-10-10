// Everything the starter/leaver API needs in Azure. Deploy with deploy\deploy.ps1.
// Re-running it is safe: Bicep only changes what differs from this file.

@description('Azure region for all resources.')
param location string = resourceGroup().location

@description('Short, unique name for the app. Default is made from the resource group ID.')
param appName string = 'sla-${uniqueString(resourceGroup().id)}'

@description('The Entra tenant the app is allowed to change. Checked again by the code before every change.')
param tenantId string = tenant().tenantId

@description('Domain for new sign-in addresses, e.g. contoso.onmicrosoft.com.')
param userDomain string

// Storage the Functions runtime needs for its own bookkeeping. Locked down: HTTPS only, no public blobs.
resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: take(replace('st${appName}', '-', ''), 24)
  location: location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    supportsHttpsTrafficOnly: true
  }
}

// Logs, so failures can be investigated. Pay-per-GB; tiny at this volume.
resource logs 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'log-${appName}'
  location: location
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource insights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${appName}'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logs.id
  }
}

// Consumption plan: pay per run, with a monthly free allowance, and nothing when idle.
resource plan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: 'plan-${appName}'
  location: location
  sku: { name: 'Y1', tier: 'Dynamic' }
  properties: {}
}

var storageConnection = 'DefaultEndpointsProtocol=https;AccountName=${storage.name};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storage.listKeys().keys[0].value}'

resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: 'func-${appName}'
  location: location
  kind: 'functionapp'
  // The app's own identity in Entra. Graph permissions are granted to it by deploy\grant-graph-permissions.ps1.
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: plan.id
    httpsOnly: true
    siteConfig: {
      powerShellVersion: '7.4'
      minTlsVersion: '1.2'
      ftpsState: 'Disabled'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: storageConnection }
        { name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING', value: storageConnection }
        { name: 'WEBSITE_CONTENTSHARE', value: toLower('func-${appName}') }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'powershell' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: insights.properties.ConnectionString }
        { name: 'TENANT_ID', value: tenantId }
        { name: 'USER_DOMAIN', value: userDomain }
      ]
    }
  }
}

output functionAppName string = functionApp.name
output principalId string = functionApp.identity.principalId
output hostName string = functionApp.properties.defaultHostName
