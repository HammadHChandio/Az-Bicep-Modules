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

@description('Container name for Databricks data')
param containerName string = 'databricks'

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

// ============================================================
// FOUNDATION - CMK KEYS
// Three separate keys for managed services, managed disk
// and storage account encryption
// ============================================================

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

// Extract key versions from the key URIs
// Format: https://<vault>.vault.azure.net/keys/<n>/<version>
var managedServicesKeyVersion = last(split(managedServicesKey.properties.keyUriWithVersion, '/'))
var managedDiskKeyVersion = last(split(managedDiskKey.properties.keyUriWithVersion, '/'))
var storageKeyVersion = last(split(storageKey.properties.keyUriWithVersion, '/'))

// ============================================================
// FOUNDATION - ACCESS CONNECTOR
// Provides a managed identity for Databricks to authenticate
// to Key Vault and Storage without storing credentials
// ============================================================

module accessConnector './modules/accessConnector.bicep' = {
  name: 'deploy-access-connector'
  params: {
    name: accessConnectorName
    location: location
  }
}

// ============================================================
// FOUNDATION - KEY VAULT ROLE ASSIGNMENT
// Grants the Access Connector identity the
// 'Key Vault Crypto Service Encryption User' role
// so it can wrap/unwrap CMK keys for encryption
// ============================================================

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

// ============================================================
// STAGE 1 - DATABRICKS WORKSPACE (no CMK)
// ============================================================

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
    privateEndpointSubnetId: privateEndpointSubnet.id
    publicNetworkAccess: publicNetworkAccess
  }
  dependsOn: [
    accessConnector
    keyVaultRoleAssignment
  ]
}

// ============================================================
// STAGE 2 - DATABRICKS ENCRYPTION
// ============================================================

module databricksEncryption './modules/databricksEncryption.bicep' = {
  name: 'deploy-databricks-encryption'
  params: {
    name: databricksName
    location: location
    sku: workspaceSku
    accessConnectorId: accessConnector.outputs.id
    managedResourceGroupName: managedResourceGroupName
    customVirtualNetworkId: vnet.id
    customPublicSubnetName: publicSubnetName
    customPrivateSubnetName: privateSubnetName
    keyVaultUri: keyVault.properties.vaultUri
    managedServicesKeyName: managedServicesKeyName
    managedServicesKeyVersion: managedServicesKeyVersion
    managedDiskKeyName: managedDiskKeyName
    managedDiskKeyVersion: managedDiskKeyVersion
    publicNetworkAccess: publicNetworkAccess
  }
  dependsOn: [
    databricks
  ]
}

// ============================================================
// STAGE 3 - ADLS GEN2 STORAGE ACCOUNT
// Deploys storage with CMK encryption, private endpoint
// and grants Access Connector blob data contributor access
// ============================================================

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
    containerName: containerName
  }
  dependsOn: [
    keyVaultRoleAssignment
    databricksEncryption
  ]
}

// ============================================================
// OUTPUTS
// ============================================================

output databricksWorkspaceId string = databricks.outputs.workspaceId
output databricksWorkspaceUrl string = databricks.outputs.workspaceUrl
output accessConnectorPrincipalId string = accessConnector.outputs.principalId
output keyVaultUri string = keyVault.properties.vaultUri
output storageAccountName string = storage.outputs.storageAccountName
output storageDfsEndpoint string = storage.outputs.primaryEndpointDfs
