// ---------------------------------------------------------------------------
// RBAC Role Assignments — Minimum Required Permissions
// ---------------------------------------------------------------------------
// This module demonstrates the MINIMUM roles needed for the Responses API
// with BYO storage and AI Search. The customer reported permission errors
// with only "Azure AI User" — this module shows exactly what's needed
// WITHOUT granting the broad "Contributor" role.
// ---------------------------------------------------------------------------

@description('Principal ID of the user or service principal needing access')
param userPrincipalId string

@description('Principal type: User, Group, or ServicePrincipal')
param userPrincipalType string = 'User'

@description('Principal ID of the APIM managed identity')
param apimPrincipalId string

@description('Principal ID of the AI Foundry hub managed identity')
param hubPrincipalId string

@description('Principal ID of the AI Foundry project managed identity')
param projectPrincipalId string

@description('Primary Azure OpenAI resource name')
param openaiName1 string

@description('Secondary Azure OpenAI resource name')
param openaiName2 string

@description('Storage account name')
param storageName string

@description('AI Search resource name')
param searchName string

@description('AI Foundry hub name')
param hubName string

@description('AI Foundry project name')
param projectName string

// ---------------------------------------------------------------------------
// Built-in Role Definition IDs
// ---------------------------------------------------------------------------
// See: https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles

var roles = {
  // Cognitive Services OpenAI User — call OpenAI APIs (inference)
  cognitiveServicesOpenAIUser: '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
  // Cognitive Services OpenAI Contributor — manage deployments + inference
  cognitiveServicesOpenAIContributor: 'a001fd3d-188f-4b5d-821b-7da978bf7442'
  // Storage Blob Data Contributor — read/write/delete blobs (BYO storage)
  storageBlobDataContributor: 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
  // Search Index Data Reader — query search indexes
  searchIndexDataReader: '1407120a-92aa-4202-b7e9-c0e197c71c8f'
  // Search Index Data Contributor — read/write search indexes
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  // Search Service Contributor — manage search service (NOT data)
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  // Azure AI Developer — develop against AI Foundry project resources
  azureAIDeveloper: '64702f94-c441-49e6-a78b-ef80e0188fee'
  // Azure AI Inference Deployment Operator — manage inference endpoints
  azureAIInferenceDeploymentOperator: '3afb7f49-54cb-416e-8c09-6dc049efa503'
  // Reader — read-only access to resources
  reader: 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
}

// ---------------------------------------------------------------------------
// Existing resources (referenced for scoped role assignments)
// ---------------------------------------------------------------------------
resource openai1 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openaiName1
}

resource openai2 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: openaiName2
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageName
}

resource search 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: searchName
}

resource hub 'Microsoft.MachineLearningServices/workspaces@2024-10-01' existing = {
  name: hubName
}

resource project 'Microsoft.MachineLearningServices/workspaces@2024-10-01' existing = {
  name: projectName
}

// =====================================================================
// SECTION 1: User / Service Principal — minimum roles for Responses API
// =====================================================================

// 1a. Cognitive Services OpenAI User on BOTH OpenAI resources
//     This is required to call the Responses API, Chat Completions, etc.
resource userOpenAI1Role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openai1.id, userPrincipalId, roles.cognitiveServicesOpenAIUser)
  scope: openai1
  properties: {
    principalId: userPrincipalId
    principalType: userPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}

resource userOpenAI2Role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openai2.id, userPrincipalId, roles.cognitiveServicesOpenAIUser)
  scope: openai2
  properties: {
    principalId: userPrincipalId
    principalType: userPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}

// 1b. Storage Blob Data Contributor on the BYO storage account
//     Required for Responses API file_search / code_interpreter tools
//     that read/write files in customer-owned storage.
resource userStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, userPrincipalId, roles.storageBlobDataContributor)
  scope: storage
  properties: {
    principalId: userPrincipalId
    principalType: userPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
  }
}

// 1c. Search Index Data Contributor on the AI Search resource
//     Required to read AND write search index data (grounding with your data).
//     Use Reader variant if only querying is needed.
resource userSearchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, userPrincipalId, roles.searchIndexDataContributor)
  scope: search
  properties: {
    principalId: userPrincipalId
    principalType: userPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
  }
}

// 1d. Azure AI Developer on the AI Foundry project
//     Allows using AI Foundry project endpoints (including Responses API via project).
//     This is the KEY role missing when only "Azure AI User" is assigned.
resource userProjectRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(project.id, userPrincipalId, roles.azureAIDeveloper)
  scope: project
  properties: {
    principalId: userPrincipalId
    principalType: userPrincipalType
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.azureAIDeveloper)
  }
}

// =====================================================================
// SECTION 2: APIM Managed Identity — needs to call Azure OpenAI backends
// =====================================================================

resource apimOpenAI1Role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openai1.id, apimPrincipalId, roles.cognitiveServicesOpenAIUser)
  scope: openai1
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}

resource apimOpenAI2Role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openai2.id, apimPrincipalId, roles.cognitiveServicesOpenAIUser)
  scope: openai2
  properties: {
    principalId: apimPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}

// =====================================================================
// SECTION 3: AI Foundry Hub + Project Managed Identities
// =====================================================================

// Hub MI needs access to storage and OpenAI resources
resource hubStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, hubPrincipalId, roles.storageBlobDataContributor)
  scope: storage
  properties: {
    principalId: hubPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
  }
}

resource hubOpenAI1Role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openai1.id, hubPrincipalId, roles.cognitiveServicesOpenAIUser)
  scope: openai1
  properties: {
    principalId: hubPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}

resource hubOpenAI2Role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openai2.id, hubPrincipalId, roles.cognitiveServicesOpenAIUser)
  scope: openai2
  properties: {
    principalId: hubPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}

resource hubSearchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, hubPrincipalId, roles.searchIndexDataContributor)
  scope: search
  properties: {
    principalId: hubPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
  }
}

// Project MI needs access to storage and search for Responses API tools
resource projectStorageRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storage.id, projectPrincipalId, roles.storageBlobDataContributor)
  scope: storage
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataContributor)
  }
}

resource projectSearchRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(search.id, projectPrincipalId, roles.searchIndexDataContributor)
  scope: search
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
  }
}

resource projectOpenAI1Role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openai1.id, projectPrincipalId, roles.cognitiveServicesOpenAIUser)
  scope: openai1
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}

resource projectOpenAI2Role 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(openai2.id, projectPrincipalId, roles.cognitiveServicesOpenAIUser)
  scope: openai2
  properties: {
    principalId: projectPrincipalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cognitiveServicesOpenAIUser)
  }
}
