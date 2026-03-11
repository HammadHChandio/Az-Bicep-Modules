targetScope = 'resourceGroup'

@description('Location for all resources')
param location string = resourceGroup().location

@description('Databricks Workspace Name')
param databricksName string

@description('Databricks Access Connector Name')
param accessConnectorName string

@description('Resource group containing the VNet')
param vnetResourceGroup string

@description('Existing VNet name for Databricks VNet injection')
param vnetName string

@description('Subnet name for Databricks public subnet')
param publicSubnetName string

@description('Subnet name for Databricks private subnet')
param privateSubnetName string

@description('Subnet used for Private Endpoint')
param privateEndpointSubnetName string

@description('Key Vault name for Databricks CMK')
param keyVaultName string

@description('Managed Services CMK key name')
param managedServicesKeyName string

@description('Managed Disk CMK key name')
param managedDiskKeyName string

@description('Storage Account name')
param storageAccountName string

@description('Storage CMK key name')
param storageKeyName string

@description('Controls public network access to Databricks workspace')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@allowed([
  'standard'
  'premium'
])
param workspaceSku string = 'premium'

var managedResourceGroupName = '${databricksName}-managed-rg'

resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: vnetName
  scope: resourceGroup(vnetResourceGroup)
}

resource privateEndpointSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: vnet
  name: privateEndpointSubnetName
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-02-01' = {
  name: keyVaultName
  location: location
  properties: {
    tenantId: subscription().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
    enableSoftDelete: true
    enablePurgeProtection: true
    enableRbacAuthorization: true
  }
}

resource managedServicesKey 'Microsoft.KeyVault/vaults/keys@2023-02-01' = {
  parent: keyVault
  name: managedServicesKeyName
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'encrypt'
      'decrypt'
      'wrapKey'
      'unwrapKey'
      'sign'
      'verify'
    ]
  }
}

resource managedDiskKey 'Microsoft.KeyVault/vaults/keys@2023-02-01' = {
  parent: keyVault
  name: managedDiskKeyName
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'encrypt'
      'decrypt'
      'wrapKey'
      'unwrapKey'
      'sign'
      'verify'
    ]
  }
}

resource storageKey 'Microsoft.KeyVault/vaults/keys@2023-02-01' = {
  parent: keyVault
  name: storageKeyName
  properties: {
    kty: 'RSA'
    keySize: 2048
    keyOps: [
      'encrypt'
      'decrypt'
      'wrapKey'
      'unwrapKey'
      'sign'
      'verify'
    ]
  }
}

var managedServicesKeyVersion = last(split(managedServicesKey.properties.keyUriWithVersion, '/'))
var managedDiskKeyVersion = last(split(managedDiskKey.properties.keyUriWithVersion, '/'))
var storageKeyVersion = last(split(storageKey.properties.keyUriWithVersion, '/'))

resource databricksNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${databricksName}-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'databricks-worker-to-databricks-webapp'
        properties: {
          priority: 100
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'AzureDatabricks'
          destinationPortRanges: [
            '443'
            '3306'
            '8443-8451'
          ]
        }
      }
      {
        name: 'databricks-worker-to-sql'
        properties: {
          priority: 110
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Sql'
          destinationPortRange: '3306'
        }
      }
      {
        name: 'databricks-worker-to-storage'
        properties: {
          priority: 120
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'Storage'
          destinationPortRange: '443'
        }
      }
      {
        name: 'databricks-worker-to-eventhub'
        properties: {
          priority: 130
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Outbound'
          sourceAddressPrefix: 'VirtualNetwork'
          sourcePortRange: '*'
          destinationAddressPrefix: 'EventHub'
          destinationPortRange: '9093'
        }
      }
    ]
  }
}


module accessConnector './modules/accessConnector.bicep' = {
  name: 'deploy-access-connector'
  params: {
    name: accessConnectorName
    location: location
  }
}

resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, accessConnectorName, 'kv-encryption-role')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '14b46e9e-c2b7-41b4-b07b-48a6ebf60603'
    )
    principalId: accessConnector.outputs.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [
    accessConnector
  ]
}

module databricks './modules/databricks.bicep' = {
  name: 'deploy-databricks'
  params: {
    name: databricksName
    location: location
    sku: workspaceSku
    accessConnectorId: accessConnector.outputs.id
    managedResourceGroupName: managedResourceGroupName
    customVirtualNetworkId: vnet.id
    customPublicSubnetName: publicSubnetName
    customPrivateSubnetName: privateSubnetName
    existingKeyVaultName: keyVault.name
    keyVaultResourceGroup: resourceGroup().name
    managedServicesKeyName: managedServicesKeyName
    managedServicesKeyVersion: managedServicesKeyVersion
    managedDiskKeyName: managedDiskKeyName
    managedDiskKeyVersion: managedDiskKeyVersion
    publicNetworkAccess: publicNetworkAccess
  }
  dependsOn: [
    accessConnector
    keyVault
    managedServicesKey
    managedDiskKey
    keyVaultRoleAssignment
  ]
}

resource databricksPrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-09-01' = {
  name: '${databricksName}-pe'
  location: location
  properties: {
    subnet: {
      id: privateEndpointSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'databricks-ui'
        properties: {
          privateLinkServiceId: databricks.outputs.workspaceId
          groupIds: [
            'databricks_ui_api'
          ]
        }
      }
    ]
  }
  dependsOn: [
    databricks
  ]
}

module storage './modules/storage.bicep' = {
  name: 'deploy-storage'
  params: {
    name: storageAccountName
    location: location
    keyVaultUri: keyVault.properties.vaultUri
    storageKeyName: storageKeyName
    storageKeyVersion: storageKeyVersion
    accessConnectorPrincipalId: accessConnector.outputs.principalId
    privateEndpointSubnetId: privateEndpointSubnet.id
  }
  dependsOn: [
    keyVaultRoleAssignment
    databricks
  ]
}

output databricksWorkspace string = databricksName
output accessConnectorPrincipalId string = accessConnector.outputs.principalId
output keyVaultUri string = keyVault.properties.vaultUri
output storageAccountName string = storage.outputs.storageAccountName
output storageDfsEndpoint string = storage.outputs.primaryEndpointDfs
