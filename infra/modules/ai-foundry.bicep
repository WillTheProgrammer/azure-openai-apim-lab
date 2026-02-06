@description('Name of the AI Foundry hub')
param hubName string

@description('Name of the AI Foundry project')
param projectName string

@description('Location for the resource')
param location string

@description('Storage account ID for BYO storage')
param storageAccountId string

@description('AI Search resource ID to connect')
param aiSearchId string

@description('AI Search endpoint')
param aiSearchEndpoint string

@description('Primary Azure OpenAI resource ID')
param openaiResourceId1 string

@description('Primary Azure OpenAI endpoint')
param openaiEndpoint1 string

@description('Secondary Azure OpenAI resource ID')
param openaiResourceId2 string

@description('Secondary Azure OpenAI endpoint')
param openaiEndpoint2 string

param tags object = {}

// Key Vault for the hub (required)
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: 'kv-${uniqueString(resourceGroup().id, hubName)}'
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 7
  }
}

// AI Foundry Hub
resource hub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: hubName
  location: location
  tags: tags
  kind: 'Hub'
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'AI Foundry Lab Hub'
    storageAccount: storageAccountId
    keyVault: keyVault.id
  }
}

// Connection to primary Azure OpenAI
resource openaiConnection1 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: hub
  name: 'aoai-eastus'
  properties: {
    category: 'AzureOpenAI'
    authType: 'AAD'
    isSharedToAll: true
    target: openaiEndpoint1
    metadata: {
      ApiType: 'Azure'
      ResourceId: openaiResourceId1
    }
  }
}

// Connection to secondary Azure OpenAI
resource openaiConnection2 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: hub
  name: 'aoai-eastus2'
  properties: {
    category: 'AzureOpenAI'
    authType: 'AAD'
    isSharedToAll: true
    target: openaiEndpoint2
    metadata: {
      ApiType: 'Azure'
      ResourceId: openaiResourceId2
    }
  }
}

// Connection to AI Search
resource searchConnection 'Microsoft.MachineLearningServices/workspaces/connections@2024-10-01' = {
  parent: hub
  name: 'ai-search'
  properties: {
    category: 'CognitiveSearch'
    authType: 'AAD'
    isSharedToAll: true
    target: aiSearchEndpoint
    metadata: {
      ResourceId: aiSearchId
    }
  }
}

// AI Foundry Project
resource project 'Microsoft.MachineLearningServices/workspaces@2024-10-01' = {
  name: projectName
  location: location
  tags: tags
  kind: 'Project'
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    friendlyName: 'Customer Lab Project'
    hubResourceId: hub.id
  }
}

output hubId string = hub.id
output hubName string = hub.name
output hubPrincipalId string = hub.identity.principalId
output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
