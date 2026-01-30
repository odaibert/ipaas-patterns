@description('Location for all resources')
param location string = 'eastus'

@description('Cosmos DB account name - must be globally unique')
param cosmosAccountName string = 'cosmos-mileage-${uniqueString(resourceGroup().id)}'

@description('Database name')
param databaseName string = 'BackendSystems'

@description('Container name')
param containerName string = 'MileageData'

@description('Logic App name')
param logicAppName string = 'logic-mileage-orchestrator'

// ============================================================================
// COSMOS DB RESOURCES
// ============================================================================

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-05-15' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
        isZoneRedundant: false
      }
    ]
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    publicNetworkAccess: 'Enabled'
    backupPolicy: {
      type: 'Periodic'
      periodicModeProperties: {
        backupIntervalInMinutes: 240
        backupRetentionIntervalInHours: 8
        backupStorageRedundancy: 'Local'
      }
    }
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2024-05-15' = {
  parent: cosmosAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2024-05-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: ['/id']
        kind: 'Hash'
      }
    }
  }
}

// ============================================================================
// COSMOS DB RBAC - Grant Logic App data access
// ============================================================================

var cosmosDataContributorRoleId = '00000000-0000-0000-0000-000000000002'

resource cosmosRoleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, logicApp.id, cosmosDataContributorRoleId)
  properties: {
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/${cosmosDataContributorRoleId}'
    principalId: logicApp.identity.principalId
    scope: cosmosAccount.id
  }
}

// ============================================================================
// LOGIC APP - Basic workflow with HTTP trigger and response
// ============================================================================
// NOTE: Logic Apps Consumption tier has limitations:
// - V2 connections (required for MSI) are NOT supported
// - Cosmos DB connector requires access keys (blocked by Azure Policy)
// - Manual portal configuration is required for the Cosmos DB connector
//
// WORKAROUND: The Logic App is deployed with a basic workflow.
// Add the Cosmos DB connector manually via the Azure Portal using
// the "Logic Apps Managed Identity" authentication option.

resource logicApp 'Microsoft.Logic/workflows@2019-05-01' = {
  name: logicAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    state: 'Enabled'
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {}
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            method: 'POST'
            schema: {
              type: 'object'
              properties: {
                id: { type: 'string' }
                vehicle: { type: 'string' }
                mileage: { type: 'number' }
                date: { type: 'string' }
              }
              required: ['id']
            }
          }
        }
      }
      actions: {
        Response: {
          type: 'Response'
          kind: 'Http'
          runAfter: {}
          inputs: {
            statusCode: 200
            body: {
              status: 'Workflow ready'
              message: 'Add Cosmos DB connector via Azure Portal'
              receivedData: '@triggerBody()'
            }
            headers: {
              'Content-Type': 'application/json'
            }
          }
        }
      }
    }
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output cosmosAccountName string = cosmosAccount.name
output cosmosAccountEndpoint string = cosmosAccount.properties.documentEndpoint
output databaseName string = database.name
output containerName string = container.name
output logicAppName string = logicApp.name
output logicAppPrincipalId string = logicApp.identity.principalId

@description('Logic App HTTP trigger URL')
output logicAppUrl string = logicApp.listCallbackUrl().value

@description('Add Cosmos DB connector here')
output portalDesignerUrl string = 'https://portal.azure.com/#@/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Logic/workflows/${logicAppName}/designer'
