# APIM ❤️ Logic Apps ❤️ Cosmos DB

## [Mileage Tracking Lab](mileage-tracking.ipynb)

[![flow](../../images/mileage-tracking-flow.png)](mileage-tracking.ipynb)

Build an end-to-end integration solution that demonstrates the **iPaaS pattern** with Azure API Management, Logic Apps, and Cosmos DB.

### Architecture

```
Client → APIM (Rate Limited) → Logic App (Managed ID) → Cosmos DB (RBAC)
         POST /mileage/calculate
```

### Features

- **API Management**: Gateway with rate limiting and subscription key authentication
- **Logic Apps**: Workflow orchestration with System-assigned Managed Identity
- **Cosmos DB**: NoSQL database with Azure AD (RBAC) authentication
- **Security**: No stored credentials - all authentication via Managed Identity

### Prerequisites

- [Python 3.12 or later version](https://www.python.org/) installed
- [VS Code](https://code.visualstudio.com/) installed with the [Jupyter notebook extension](https://marketplace.visualstudio.com/items?itemName=ms-toolsai.jupyter) enabled
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) installed
- [An Azure Subscription](https://azure.microsoft.com/free/) with Contributor permissions
- [Sign in to Azure with Azure CLI](https://learn.microsoft.com/cli/azure/authenticate-azure-cli-interactively)

### 🚀 Get started

Proceed by opening the [Jupyter notebook](mileage-tracking.ipynb), and follow the steps provided.

### 🗑️ Clean up resources

When you're finished with the lab, you should remove all your deployed resources from Azure to avoid extra charges and keep your Azure subscription uncluttered.
Use the [clean-up-resources notebook](clean-up-resources.ipynb) for that.

### Files

| File | Description |
|------|-------------|
| [main.bicep](main.bicep) | Infrastructure as Code template |
| [apim-policy.xml](apim-policy.xml) | APIM policy with rate limiting |
| [mileage-tracking.ipynb](mileage-tracking.ipynb) | Lab notebook |
| [clean-up-resources.ipynb](clean-up-resources.ipynb) | Cleanup notebook |
