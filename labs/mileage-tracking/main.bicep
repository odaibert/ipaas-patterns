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

@description('API Management name')
param apimName string = 'apim-gateway-learning-${uniqueString(resourceGroup().id)}'

@description('Publisher email for APIM')
param publisherEmail string = 'student@learning.com'

@description('Publisher name for APIM')
param publisherName string = 'Student Architect'

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

// Get the Logic App trigger callback URL
var logicAppTriggerUrl = logicApp.listCallbackUrl().value

// ============================================================================
// API MANAGEMENT - BasicV2 tier (fast provisioning)
// ============================================================================

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: 'BasicV2'
    capacity: 1
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// ============================================================================
// API DEFINITION - Mileage API fronting Logic App
// ============================================================================

resource mileageApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'mileage-api'
  properties: {
    displayName: 'Mileage API'
    description: 'API for mileage tracking operations'
    serviceUrl: logicAppTriggerUrl
    path: 'mileage'
    protocols: [
      'https'
    ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
  }
}

// ============================================================================
// API OPERATION - POST /calculate with rate limiting
// ============================================================================

resource calculateOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: mileageApi
  name: 'calculate-mileage'
  properties: {
    displayName: 'Calculate Mileage'
    description: 'Submit mileage data for calculation and storage'
    method: 'POST'
    urlTemplate: '/calculate'
    request: {
      description: 'Mileage data to process'
      representations: [
        {
          contentType: 'application/json'
          examples: {
            default: {
              value: {
                id: 'mileage-001'
                vehicle: 'car-abc'
                mileage: 1500
                date: '2024-01-30'
              }
            }
          }
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'Mileage calculated successfully'
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
      {
        statusCode: 429
        description: 'Rate limit exceeded'
      }
    ]
  }
}

// ============================================================================
// OPERATION POLICY - Rate limiting (5 calls per 60 seconds)
// ============================================================================

// Named Value to store Logic App URL securely
resource logicAppUrlNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apimService
  name: 'logic-app-url'
  properties: {
    displayName: 'LogicAppUrl'
    value: logicAppTriggerUrl
    secret: true
  }
}

resource calculateOperationPolicy 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: calculateOperation
  name: 'policy'
  dependsOn: [logicAppUrlNamedValue]
  properties: {
    format: 'rawxml'
    value: '<policies><inbound><base /><rate-limit-by-key calls="5" renewal-period="60" counter-key="@(context.Request.IpAddress)" /><set-header name="Content-Type" exists-action="override"><value>application/json</value></set-header><set-backend-service base-url="{{LogicAppUrl}}" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
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
output logicAppUrl string = logicAppTriggerUrl

@description('Add Cosmos DB connector here')
output portalDesignerUrl string = 'https://portal.azure.com/#@/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${resourceGroup().name}/providers/Microsoft.Logic/workflows/${logicAppName}/designer'

// APIM Outputs
output apimName string = apimService.name
output apimGatewayUrl string = apimService.properties.gatewayUrl
output apimMileageApiPath string = '${apimService.properties.gatewayUrl}/mileage/calculate'
