@description('Location for all resources')
param location string = 'eastus'

@description('Service Bus namespace name - must be globally unique')
param serviceBusNamespaceName string = 'sb-contact-${uniqueString(resourceGroup().id)}'

@description('Service Bus queue name')
param serviceBusQueueName string = 'contact-intake'

@description('API Management name')
param apimName string = 'apim-gateway-learning-${uniqueString(resourceGroup().id)}'

@description('Publisher email for APIM')
param publisherEmail string = 'student@learning.com'

@description('Publisher name for APIM')
param publisherName string = 'Student Architect'

// ============================================================================
// SERVICE BUS RESOURCES
// ============================================================================

resource sbNamespace 'Microsoft.ServiceBus/namespaces@2021-11-01' = {
  name: serviceBusNamespaceName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
}

resource sbQueue 'Microsoft.ServiceBus/namespaces/queues@2021-11-01' = {
  parent: sbNamespace
  name: serviceBusQueueName
  properties: {
    enablePartitioning: false
  }
}

resource sbSendRule 'Microsoft.ServiceBus/namespaces/queues/authorizationRules@2021-11-01' = {
  parent: sbQueue
  name: 'send-policy'
  properties: {
    rights: [
      'Send'
    ]
  }
}

var sbQueueUri = 'https://${serviceBusNamespaceName}.servicebus.windows.net/${serviceBusQueueName}'

// ============================================================================
// API MANAGEMENT - BasicV2 tier (fast provisioning) with Managed Identity
// ============================================================================

resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: apimName
  location: location
  sku: {
    name: 'BasicV2'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// Assign Service Bus Data Sender role to APIM managed identity
resource sbDataSenderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sbNamespace.id, apimService.id, 'Azure Service Bus Data Sender')
  scope: sbNamespace
  properties: {
    principalId: apimService.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39') // Azure Service Bus Data Sender
  }
}

// ============================================================================
// API DEFINITION - Contact Intake API (APIM -> Service Bus)
// ============================================================================

resource contactApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'contact-api'
  properties: {
    displayName: 'Contact Intake API'
    description: 'Accepts contact form submissions and enqueues them to Service Bus'
    path: 'contact'
    protocols: [
      'https'
    ]
    subscriptionRequired: false  // No API key needed - educational purposes only
  }
}

resource submitContactOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: contactApi
  name: 'submit-contact'
  properties: {
    displayName: 'Submit Contact Form'
    description: 'Accept a contact form submission and queue it for processing'
    method: 'POST'
    urlTemplate: '/submit'
    request: {
      description: 'Contact form data'
      representations: [
        {
          contentType: 'application/json'
          examples: {
            default: {
              value: {
                name: 'Jane Doe'
                email: 'jane@example.com'
                subject: 'Question about pricing'
                message: 'Can you share your pricing tiers?'
              }
            }
          }
        }
      ]
    }
    responses: [
      {
        statusCode: 202
        description: 'Accepted and queued'
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
// OPERATION POLICY - Using Managed Identity for Service Bus auth
// ============================================================================

resource sbQueueUriNamedValue 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apimService
  name: 'sb-queue-uri'
  properties: {
    displayName: 'sb-queue-uri'
    value: sbQueueUri
    secret: false
  }
}

var submitContactPolicy = '''
<policies>
  <inbound>
    <base />
    <rate-limit-by-key calls="10" renewal-period="60" counter-key="@(context.Request.IpAddress)" />
    <authentication-managed-identity resource="https://servicebus.azure.net" />
    <set-header name="Content-Type" exists-action="override">
      <value>application/json</value>
    </set-header>
    <set-backend-service base-url="{{sb-queue-uri}}" />
    <rewrite-uri template="/messages" />
  </inbound>
  <backend>
    <forward-request timeout="30" />
  </backend>
  <outbound>
    <base />
    <choose>
      <when condition="@(context.Response.StatusCode == 201)">
        <set-status code="202" reason="Accepted" />
        <set-body>@("{\"status\":\"queued\",\"messageId\":\"" + context.RequestId.ToString() + "\"}")</set-body>
      </when>
      <otherwise>
        <set-body>@("{\"status\":\"error\",\"backendStatus\":" + context.Response.StatusCode + ",\"message\":\"" + context.Response.StatusReason + "\"}")</set-body>
      </otherwise>
    </choose>
    <set-header name="Content-Type" exists-action="override">
      <value>application/json</value>
    </set-header>
  </outbound>
  <on-error>
    <base />
    <set-status code="500" reason="Internal Error" />
    <set-body>@("{\"status\":\"error\",\"message\":\"" + context.LastError.Message + "\"}")</set-body>
    <set-header name="Content-Type" exists-action="override">
      <value>application/json</value>
    </set-header>
  </on-error>
</policies>
'''

resource submitContactPolicyResource 'Microsoft.ApiManagement/service/apis/operations/policies@2023-05-01-preview' = {
  parent: submitContactOperation
  name: 'policy'
  dependsOn: [
    sbQueueUriNamedValue
    sbDataSenderRole  // Wait for RBAC to be assigned
  ]
  properties: {
    format: 'rawxml'
    value: submitContactPolicy
  }
}

// ============================================================================
// OUTPUTS
// ============================================================================

output serviceBusNamespaceName string = sbNamespace.name
output serviceBusQueueName string = sbQueue.name
output serviceBusQueueUri string = sbQueueUri
output apimName string = apimService.name
output apimGatewayUrl string = apimService.properties.gatewayUrl
output apimContactApiPath string = '${apimService.properties.gatewayUrl}/contact/submit'
