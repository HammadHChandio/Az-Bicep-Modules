
@description('Storage Account name')
param name string

@description('Location')
param location string

@description('Key Vault URI')
param keyVaultUri string

@description('Storage CMK key name')
param storageKeyName string

@description('Storage CMK key version')
param storageKeyVersion string

@description('Access Connector Principal ID for role assignment')
param accessConnectorPrincipalId string

@description('Private Endpoint Subnet ID')
param privateEndpointSubnetId string

@description('Blob service name - must always be default')
param blobServiceName string = 'default'

@description('Container name for Databricks data')
param containerName string = 'databricks'

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: name
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // HNS enables ADLS Gen2 - required for Databricks data lake
    isHnsEnabled: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    // Shared key disabled - only Azure AD auth permitted
    allowSharedKeyAccess: false
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Deny'
    }
    encryption: {
      keySource: 'Microsoft.Keyvault'
      keyvaultproperties: {
        keyname: storageKeyName
        keyvaulturi: keyVaultUri
        keyversion: storageKeyVersion
      }
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
      }
      requireInfrastructureEncryption: true
    }
  }
}

// ADLS Gen2 blob service - name must always be 'default'
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: blobServiceName
}

// Default container for Databricks data
resource databricksContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// Grant Access Connector Storage Blob Data Contributor
// This allows Databricks to read/write data via the Access Connector identity
resource storageRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, accessConnectorPrincipalId, 'storage-blob-contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    )
    principalId: accessConnectorPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Private endpoint on DFS endpoint (ADLS Gen2)
// Routes all storage traffic through the VNet
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: '${name}-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-dfs'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'dfs'
          ]
        }
      }
    ]
  }
}

output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output primaryEndpointDfs string = storageAccount.properties.primaryEndpoints.dfs
