@description('Name of the APIM instance')
param name string

@description('Location for the resource')
param location string

@description('Primary Azure OpenAI endpoint')
param openaiEndpoint1 string

@description('Secondary Azure OpenAI endpoint')
param openaiEndpoint2 string

@description('Primary Azure OpenAI resource ID (for managed identity auth)')
param openaiResourceId1 string

@description('Secondary Azure OpenAI resource ID (for managed identity auth)')
param openaiResourceId2 string

param tags object = {}

resource apim 'Microsoft.ApiManagement/service@2024-05-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'BasicV2'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: 'lab-admin@contoso.com'
    publisherName: 'AI Lab'
  }
}

// ---------------------------------------------------------------------------
// Backend pool with two Azure OpenAI instances for load balancing
// ---------------------------------------------------------------------------
resource backend1 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'openai-eastus'
  properties: {
    title: 'Azure OpenAI - East US'
    description: 'Primary Azure OpenAI instance in East US'
    url: '${openaiEndpoint1}openai'
    protocol: 'http'
    type: 'Single'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

resource backend2 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'openai-eastus2'
  properties: {
    title: 'Azure OpenAI - East US 2'
    description: 'Secondary Azure OpenAI instance in East US 2'
    url: '${openaiEndpoint2}openai'
    protocol: 'http'
    type: 'Single'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
}

// Load-balanced backend pool
resource backendPool 'Microsoft.ApiManagement/service/backends@2024-05-01' = {
  parent: apim
  name: 'openai-pool'
  properties: {
    title: 'Azure OpenAI Load Balanced Pool'
    description: 'Round-robin pool across East US and East US 2'
    type: 'Pool'
    pool: {
      services: [
        {
          id: backend1.id
          priority: 1
          weight: 50
        }
        {
          id: backend2.id
          priority: 1
          weight: 50
        }
      ]
    }
  }
}

// ---------------------------------------------------------------------------
// API definition for Azure OpenAI
// ---------------------------------------------------------------------------
resource openaiApi 'Microsoft.ApiManagement/service/apis@2024-05-01' = {
  parent: apim
  name: 'azure-openai'
  properties: {
    displayName: 'Azure OpenAI'
    apiRevision: '1'
    path: 'openai'
    protocols: [ 'https' ]
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    serviceUrl: '${openaiEndpoint1}openai'
  }
}

// Catch-all operation to forward all OpenAI requests
resource allOps 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: openaiApi
  name: 'all-operations'
  properties: {
    displayName: 'All OpenAI Operations'
    method: 'POST'
    urlTemplate: '/*'
  }
}

// Responses API operation (explicit for demo clarity)
resource responsesOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: openaiApi
  name: 'responses'
  properties: {
    displayName: 'Responses API'
    method: 'POST'
    urlTemplate: '/responses'
  }
}

// Chat completions operation
resource chatOp 'Microsoft.ApiManagement/service/apis/operations@2024-05-01' = {
  parent: openaiApi
  name: 'chat-completions'
  properties: {
    displayName: 'Chat Completions'
    method: 'POST'
    urlTemplate: '/deployments/{deployment-id}/chat/completions'
    templateParameters: [
      {
        name: 'deployment-id'
        required: true
        type: 'string'
      }
    ]
  }
}

// Subscription for testing
resource subscription 'Microsoft.ApiManagement/service/subscriptions@2024-05-01' = {
  parent: apim
  name: 'lab-test-subscription'
  properties: {
    displayName: 'Lab Test Subscription'
    scope: openaiApi.id
    state: 'active'
  }
}

output id string = apim.id
output name string = apim.name
output gatewayUrl string = apim.properties.gatewayUrl
output principalId string = apim.identity.principalId
output subscriptionId string = subscription.id
