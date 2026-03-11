# Azure Databricks Bicep Modules

Infrastructure-as-Code for deploying a secure, production-grade Azure Databricks workspace with:

- VNet injection with dedicated subnets
- Customer-managed keys (CMK) for managed services and managed disk encryption
- ADLS Gen2 storage account with CMK encryption
- Private endpoints for Databricks UI and storage
- Access Connector with system-assigned identity
- Public network access disabled by default

---

## Architecture

```
DataBrickRG
├── Key Vault (CMK for Databricks + Storage)
├── Databricks Access Connector (System-assigned identity)
├── Databricks Workspace (VNet injected, private endpoint)
├── Databricks Private Endpoint
├── ADLS Gen2 Storage Account (CMK encrypted)
└── Storage Private Endpoint

NetworkRG
├── VNet (10.0.0.0/16)
│   ├── default subnet (10.0.0.0/24) — Databricks public subnet
│   ├── databricks-private subnet (10.0.1.0/24) — Databricks private subnet
│   └── databricks-pe subnet (10.0.2.0/27) — Private endpoints
└── NSG (with required Databricks outbound rules)
```

---

## Prerequisites

### 1. Install tooling

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Bicep CLI](https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/install)

```bash
az bicep install
az login
```

### 2. Create Resource Groups

```bash
# Networking RG
az group create --name NetworkRG --location eastus

# Databricks RG
az group create --name DataBrickRG --location eastus
```

### 3. Create NSG with required Databricks rules

```bash
az network nsg create \
  --name dbx-ws-7f3k2-nsg \
  --resource-group NetworkRG \
  --location eastus

az network nsg rule create \
  --name databricks-worker-to-databricks-webapp \
  --nsg-name dbx-ws-7f3k2-nsg \
  --resource-group NetworkRG \
  --priority 100 \
  --protocol Tcp \
  --access Allow \
  --direction Outbound \
  --source-address-prefix VirtualNetwork \
  --source-port-range '*' \
  --destination-address-prefix AzureDatabricks \
  --destination-port-ranges 443 3306 8443-8451

az network nsg rule create \
  --name databricks-worker-to-sql \
  --nsg-name dbx-ws-7f3k2-nsg \
  --resource-group NetworkRG \
  --priority 110 \
  --protocol Tcp \
  --access Allow \
  --direction Outbound \
  --source-address-prefix VirtualNetwork \
  --source-port-range '*' \
  --destination-address-prefix Sql \
  --destination-port-ranges 3306

az network nsg rule create \
  --name databricks-worker-to-storage \
  --nsg-name dbx-ws-7f3k2-nsg \
  --resource-group NetworkRG \
  --priority 120 \
  --protocol Tcp \
  --access Allow \
  --direction Outbound \
  --source-address-prefix VirtualNetwork \
  --source-port-range '*' \
  --destination-address-prefix Storage \
  --destination-port-ranges 443

az network nsg rule create \
  --name databricks-worker-to-eventhub \
  --nsg-name dbx-ws-7f3k2-nsg \
  --resource-group NetworkRG \
  --priority 130 \
  --protocol Tcp \
  --access Allow \
  --direction Outbound \
  --source-address-prefix VirtualNetwork \
  --source-port-range '*' \
  --destination-address-prefix EventHub \
  --destination-port-ranges 9093
```

### 4. Create VNet and subnets

```bash
az network vnet create \
  --name testVnet \
  --resource-group NetworkRG \
  --location eastus \
  --address-prefix 10.0.0.0/16

az network vnet subnet create \
  --name default \
  --resource-group NetworkRG \
  --vnet-name testVnet \
  --address-prefix 10.0.0.0/24 \
  --delegations Microsoft.Databricks/workspaces \
  --network-security-group dbx-ws-7f3k2-nsg

az network vnet subnet create \
  --name databricks-private \
  --resource-group NetworkRG \
  --vnet-name testVnet \
  --address-prefix 10.0.1.0/24 \
  --delegations Microsoft.Databricks/workspaces \
  --network-security-group dbx-ws-7f3k2-nsg

az network vnet subnet create \
  --name databricks-pe \
  --resource-group NetworkRG \
  --vnet-name testVnet \
  --address-prefix 10.0.2.0/27
```

---

## Deployment

### 1. Configure parameters

Copy the example params file and fill in your values:

```bash
cp main.bicepparam.example main.bicepparam
```

Edit `main.bicepparam` with your resource names. See [Parameters](#parameters) below for reference.

### 2. Run what-if (dry run)

```bash
az deployment group what-if \
  --resource-group DataBrickRG \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### 3. Deploy

```bash
az deployment group create \
  --resource-group DataBrickRG \
  --template-file main.bicep \
  --parameters main.bicepparam
```

---

## Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `databricksName` | Databricks workspace name | Yes | — |
| `accessConnectorName` | Databricks Access Connector name | Yes | — |
| `vnetResourceGroup` | Resource group containing the VNet | Yes | — |
| `vnetName` | VNet name for VNet injection | Yes | — |
| `publicSubnetName` | Databricks public subnet name | Yes | — |
| `privateSubnetName` | Databricks private subnet name | Yes | — |
| `privateEndpointSubnetName` | Subnet for private endpoints | Yes | — |
| `keyVaultName` | Key Vault name for CMK | Yes | — |
| `managedServicesKeyName` | CMK key name for managed services | Yes | — |
| `managedDiskKeyName` | CMK key name for managed disk | Yes | — |
| `storageAccountName` | ADLS Gen2 storage account name | Yes | — |
| `storageKeyName` | CMK key name for storage | Yes | — |
| `workspaceSku` | Databricks SKU (`standard` or `premium`) | No | `premium` |
| `publicNetworkAccess` | Public network access (`Enabled` or `Disabled`) | No | `Disabled` |

> **Note:** Storage account names must be globally unique, lowercase, max 24 characters, no hyphens.

---

## Module Structure

```
.
├── main.bicep                  # Root template
├── main.bicepparam.example     # Example parameters file
├── .gitignore                  # Excludes sensitive param files
└── modules/
    ├── accessConnector.bicep   # Databricks Access Connector
    ├── databricks.bicep        # Databricks Workspace
    └── storage.bicep           # ADLS Gen2 Storage Account
```

### `modules/accessConnector.bicep`

Deploys a Databricks Access Connector with a system-assigned managed identity. This identity is used to grant Databricks access to Key Vault and storage.

### `modules/databricks.bicep`

Deploys the Databricks workspace with:
- VNet injection into existing subnets
- CMK encryption for managed services and managed disk
- Private endpoint support
- Public network access control

### `modules/storage.bicep`

Deploys an ADLS Gen2 storage account with:
- Hierarchical namespace enabled
- CMK encryption via Key Vault
- Private endpoint on the DFS endpoint
- `Storage Blob Data Contributor` role assigned to the Access Connector
- A `databricks` container created by default

---

## Security

- `main.bicepparam` is excluded from source control via `.gitignore` — never commit it
- All encryption uses customer-managed keys (CMK) stored in Key Vault
- Public network access is disabled by default — workspace is only accessible via private endpoint
- Storage account denies all public traffic by default
- Shared key access is disabled on the storage account — only Azure AD auth is permitted

---

## Outputs

| Output | Description |
|--------|-------------|
| `databricksWorkspace` | Databricks workspace name |
| `accessConnectorPrincipalId` | Managed identity principal ID |
| `keyVaultUri` | Key Vault URI |
| `storageAccountName` | Storage account name |
| `storageDfsEndpoint` | ADLS Gen2 DFS endpoint URL |