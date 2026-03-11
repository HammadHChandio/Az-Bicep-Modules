param name string
param location string

resource accessConnector 'Microsoft.Databricks/accessConnectors@2023-05-01' = {
  name: name
  location: location
  identity: {
    type: 'SystemAssigned'
  }
}

output id string = accessConnector.id
output principalId string = accessConnector.identity.principalId
