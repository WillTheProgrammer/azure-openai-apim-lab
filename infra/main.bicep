// ---------------------------------------------------------------------------
// Azure OpenAI + APIM Load Balancing + AI Foundry Lab
// ---------------------------------------------------------------------------
// Deploys a complete lab environment for demonstrating:
//   1. APIM load balancing across multi-region Azure OpenAI instances
//   2. AI Foundry hub/project with connected OpenAI + AI Search resources
//   3. Responses API with BYO storage
//   4. Minimum RBAC role assignments (no Contributor needed)
// ---------------------------------------------------------------------------

targetScope = 'resourceGroup'

@description('Environment name used as a prefix for all resources')
param environmentName string

@description('Primary Azure region')
param location string

@description('Secondary Azure region for OpenAI failover')
param secondaryLocation string

@description('OpenAI model to deploy')
param openaiModelName string = 'gpt-4o'

@description('Model version')
param openaiModelVersion string = '2024-11-20'

@description('Model SKU')
param openaiModelSkuName string = 'GlobalStandard'

@description('Model capacity (TPM in thousands)')
param openaiModelCapacity int = 30

@description('Principal ID of the user who will test the Responses API. Leave empty to skip user RBAC.')
param testUserPrincipalId string = ''

@description('Principal type for the test user')
param testUserPrincipalType string = 'User'

// ---------------------------------------------------------------------------
// Resource naming
// ---------------------------------------------------------------------------
var prefix = environmentName
var uniqueSuffix = uniqueString(resourceGroup().id, environmentName)
var openaiName1 = '${prefix}-aoai-eus-${uniqueSuffix}'
var openaiName2 = '${prefix}-aoai-eus2-${uniqueSuffix}'
var apimName = '${prefix}-apim-${uniqueSuffix}'
var searchName = '${prefix}-search-${uniqueSuffix}'
var storageName = '${prefix}st${uniqueSuffix}'
var hubName = '${prefix}-aifoundry-hub'
var projectName = '${prefix}-aifoundry-project'

var tags = {
  environment: environmentName
  purpose: 'openai-apim-lab'
}

// ---------------------------------------------------------------------------
// 1. Azure OpenAI — two regions
// ---------------------------------------------------------------------------
module openai1 'modules/openai.bicep' = {
  name: 'openai-eastus'
  params: {
    name: openaiName1
    location: location
    modelDeploymentName: openaiModelName
    modelName: openaiModelName
    modelVersion: openaiModelVersion
    modelSkuName: openaiModelSkuName
    modelCapacity: openaiModelCapacity
    tags: tags
  }
}

module openai2 'modules/openai.bicep' = {
  name: 'openai-eastus2'
  params: {
    name: openaiName2
    location: secondaryLocation
    modelDeploymentName: openaiModelName
    modelName: openaiModelName
    modelVersion: openaiModelVersion
    modelSkuName: openaiModelSkuName
    modelCapacity: openaiModelCapacity
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// 2. API Management with load-balanced backend pool
// ---------------------------------------------------------------------------
module apim 'modules/apim.bicep' = {
  name: 'apim'
  params: {
    name: apimName
    location: location
    openaiEndpoint1: openai1.outputs.endpoint
    openaiEndpoint2: openai2.outputs.endpoint
    openaiResourceId1: openai1.outputs.id
    openaiResourceId2: openai2.outputs.id
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// 3. BYO Storage Account
// ---------------------------------------------------------------------------
module storage 'modules/storage.bicep' = {
  name: 'storage'
  params: {
    name: storageName
    location: location
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// 4. AI Search
// ---------------------------------------------------------------------------
module search 'modules/ai-search.bicep' = {
  name: 'ai-search'
  params: {
    name: searchName
    location: location
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// 5. AI Foundry Hub + Project with connected resources
// ---------------------------------------------------------------------------
module aiFoundry 'modules/ai-foundry.bicep' = {
  name: 'ai-foundry'
  params: {
    hubName: hubName
    projectName: projectName
    location: location
    storageAccountId: storage.outputs.id
    aiSearchId: search.outputs.id
    aiSearchEndpoint: search.outputs.endpoint
    openaiResourceId1: openai1.outputs.id
    openaiEndpoint1: openai1.outputs.endpoint
    openaiResourceId2: openai2.outputs.id
    openaiEndpoint2: openai2.outputs.endpoint
    tags: tags
  }
}

// ---------------------------------------------------------------------------
// 6. RBAC — Minimum required role assignments
// ---------------------------------------------------------------------------
module rbac 'modules/rbac.bicep' = if (!empty(testUserPrincipalId)) {
  name: 'rbac'
  params: {
    userPrincipalId: testUserPrincipalId
    userPrincipalType: testUserPrincipalType
    apimPrincipalId: apim.outputs.principalId
    hubPrincipalId: aiFoundry.outputs.hubPrincipalId
    projectPrincipalId: aiFoundry.outputs.projectPrincipalId
    openaiName1: openaiName1
    openaiName2: openaiName2
    storageName: storageName
    searchName: searchName
    hubName: hubName
    projectName: projectName
  }
}

// ---------------------------------------------------------------------------
// Outputs — used by test scripts
// ---------------------------------------------------------------------------
output OPENAI_ENDPOINT_1 string = openai1.outputs.endpoint
output OPENAI_ENDPOINT_2 string = openai2.outputs.endpoint
output APIM_GATEWAY_URL string = apim.outputs.gatewayUrl
output AI_SEARCH_ENDPOINT string = search.outputs.endpoint
output STORAGE_BLOB_ENDPOINT string = storage.outputs.blobEndpoint
output AI_FOUNDRY_HUB_NAME string = aiFoundry.outputs.hubName
output AI_FOUNDRY_PROJECT_NAME string = aiFoundry.outputs.projectName
output RESOURCE_GROUP string = resourceGroup().name
