# Azure iPaaS Patterns

Infrastructure as Code (Bicep) templates for Azure Integration Platform as a Service (iPaaS) patterns.

## 🏗️ Resources Deployed

| Resource | Description |
|----------|-------------|
| **Cosmos DB Account** | SQL API database with session consistency |
| **Database** | `BackendSystems` |
| **Container** | `MileageData` with `/id` partition key |
| **Logic App** | Consumption tier with System-assigned Managed Identity |
| **RBAC** | Cosmos DB Data Contributor role for Logic App |

## 🚀 Deployment

### Prerequisites
- Azure CLI installed
- Logged into Azure (`az login`)
- Bicep CLI (included with Azure CLI)

### Deploy

```bash
# Create resource group
az group create --name rg-mileage-lab --location westus2

# Deploy infrastructure
az deployment group create \
  --resource-group rg-mileage-lab \
  --template-file main.bicep \
  --parameters location=westus2
```

## ⚠️ Post-Deployment Configuration

Due to Azure Policy disabling Cosmos DB access keys in many subscriptions, the Cosmos DB connector must be configured manually:

1. Open the Logic App in Azure Portal
2. Go to **Logic App Designer**
3. Click **"+"** → **"Add an action"**
4. Search for **"Azure Cosmos DB"**
5. Select **"Create or update document (V3)"**
6. Choose **"Logic Apps Managed Identity"** authentication
7. Configure:
   - Account name: `cosmos-mileage-{unique-string}`
   - Database ID: `BackendSystems`
   - Collection ID: `MileageData`
   - Document: Select **Body** from Dynamic content
8. **Save**

## 📋 Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   HTTP Client   │────▶│    Logic App    │────▶│   Cosmos DB     │
│                 │     │  (Managed ID)   │     │   (SQL API)     │
└─────────────────┘     └─────────────────┘     └─────────────────┘
                              │
                              ▼
                        ┌─────────────────┐
                        │  RBAC: Data     │
                        │  Contributor    │
                        └─────────────────┘
```

## 🔐 Security

- **Managed Identity**: Logic App uses System-assigned Managed Identity
- **RBAC**: Cosmos DB access via Azure AD (no access keys)
- **No Secrets**: All authentication handled via Azure AD

## 📁 Files

- `main.bicep` - Main infrastructure template
- `README.md` - This file

## 📄 License

MIT
