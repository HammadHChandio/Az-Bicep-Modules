param name string
param location string
param sku string

param accessConnectorId string
param managedResourceGroupName string

param customVirtualNetworkId string
param customPublicSubnetName string
param customPrivateSubnetName string

@description('Controls whether the Databricks workspace front-end is reachable over the public internet')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('Existing Key Vault Name')
param existingKeyVaultName string

@description('Key Vault Resource Group')
param keyVaultResourceGroup string

@description('Managed Services CMK key name')
param managedServicesKeyName string

@description('Managed Services CMK key version')
param managedServicesKeyVersion string

@description('Managed Disk CMK key name')
param managedDiskKeyName string

@description('Managed Disk CMK key version')
param managedDiskKeyVersion string

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: existingKeyVaultName
  scope: resourceGroup(keyVaultResourceGroup)
}

resource workspace 'Microsoft.Databricks/workspaces@2024-05-01' = {
  name: name
  location: location

  sku: {
    name: sku
  }

  properties: {

    defaultStorageFirewall: 'Enabled'

    managedResourceGroupId: subscriptionResourceId(
      'Microsoft.Resources/resourceGroups',
      managedResourceGroupName
    )

    accessConnector: {
      id: accessConnectorId
      identityType: 'SystemAssigned'
    }

    encryption: {
      entities: {
        managedServices: {
          keySource: 'Microsoft.Keyvault'
          keyVaultProperties: {
            keyName: managedServicesKeyName
            keyVaultUri: keyVault.properties.vaultUri
            keyVersion: managedServicesKeyVersion
          }
        }
        managedDisk: {
          keySource: 'Microsoft.Keyvault'
          keyVaultProperties: {
            keyName: managedDiskKeyName
            keyVaultUri: keyVault.properties.vaultUri
            keyVersion: managedDiskKeyVersion
          }
          rotationToLatestKeyVersionEnabled: true
        }
      }
    }

    parameters: {

      customVirtualNetworkId: {
        value: customVirtualNetworkId
      }

      customPublicSubnetName: {
        value: customPublicSubnetName
      }

      customPrivateSubnetName: {
        value: customPrivateSubnetName
      }

      enableNoPublicIp: {
        value: true
      }

      prepareEncryption: {
        value: true
      }

      requireInfrastructureEncryption: {
        value: false
      }

    }

    publicNetworkAccess: publicNetworkAccess

    requiredNsgRules: publicNetworkAccess == 'Disabled' ? 'NoAzureDatabricksRules' : 'AllRules'

  }
}

output workspaceId string = workspace.id
output workspaceName string = workspace.name
output workspaceUrl string = workspace.properties.workspaceUrl
