
@description('Databricks Workspace Name')
param name string

@description('Location')
param location string

@description('Databricks SKU')
@allowed([
  'standard'
  'premium'
])
param sku string = 'premium'

@description('Access Connector Resource ID')
param accessConnectorId string

@description('Managed Resource Group Name')
param managedResourceGroupName string

@description('Custom VNet Resource ID')
param customVirtualNetworkId string

@description('Public Subnet Name')
param customPublicSubnetName string

@description('Private Subnet Name')
param customPrivateSubnetName string

@description('Key Vault URI')
param keyVaultUri string

@description('Managed Services CMK key name')
param managedServicesKeyName string

@description('Managed Services CMK key version')
param managedServicesKeyVersion string

@description('Managed Disk CMK key name')
param managedDiskKeyName string

@description('Managed Disk CMK key version')
param managedDiskKeyVersion string

@description('Controls public network access to Databricks workspace')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

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
            keyVaultUri: keyVaultUri
            keyVersion: managedServicesKeyVersion
          }
        }
        managedDisk: {
          keySource: 'Microsoft.Keyvault'
          keyVaultProperties: {
            keyName: managedDiskKeyName
            keyVaultUri: keyVaultUri
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
