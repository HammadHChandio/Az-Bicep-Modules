param name string
param location string

param keyVaultUri string
param storageKeyName string
param storageKeyVersion string

param accessConnectorPrincipalId string

param privateEndpointSubnetId string


@description('Databricks container name')
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
    isHnsEnabled: true
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
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

// ADLS Gen2 filesystem container for Databricks
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

resource databricksContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  parent: blobService
  name: containerName
  properties: {
    publicAccess: 'None'
  }
}

// Grant Access Connector Storage Blob Data Contributor on the storage account
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

// Private endpoint for storage DFS (ADLS Gen2) endpoint
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
