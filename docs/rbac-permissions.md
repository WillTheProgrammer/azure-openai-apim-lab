# RBAC Permissions Guide: Azure OpenAI Responses API

## The Problem

The customer reports:

> "We get permission error while trying to access Responses API with BYO storage
> account, AI Search access even with Azure AI User role. We can't grant
> Contributor role and it has to be minimum required permission."

**Root cause:** The `Azure AI User` role only grants access to *use* an AI Foundry
project's UI and read project resources. It does **not** grant the underlying
data-plane permissions needed for the Responses API to interact with storage,
search, and cognitive services.

---

## Minimum Required Roles (No Contributor Needed)

### For a User / Service Principal calling the Responses API

| # | Role                                   | Scope                     | Why                                                     |
|---|----------------------------------------|---------------------------|---------------------------------------------------------|
| 1 | **Cognitive Services OpenAI User**     | Azure OpenAI resource(s)  | Grants inference access (Responses API, Chat, Embeddings) |
| 2 | **Storage Blob Data Contributor**      | BYO Storage Account       | Responses API reads/writes files for `file_search` and `code_interpreter` tools |
| 3 | **Search Index Data Contributor**      | AI Search resource        | Responses API queries and manages search indexes for grounding |
| 4 | **Azure AI Developer**                 | AI Foundry Project        | Allows using project inference endpoints and connections |

### For the AI Foundry Hub Managed Identity

| # | Role                                   | Scope                     | Why                                                     |
|---|----------------------------------------|---------------------------|---------------------------------------------------------|
| 1 | **Cognitive Services OpenAI User**     | Azure OpenAI resource(s)  | Hub needs to proxy inference calls                      |
| 2 | **Storage Blob Data Contributor**      | BYO Storage Account       | Hub manages file operations on behalf of users          |
| 3 | **Search Index Data Contributor**      | AI Search resource        | Hub manages search operations on behalf of users        |

### For the AI Foundry Project Managed Identity

| # | Role                                   | Scope                     | Why                                                     |
|---|----------------------------------------|---------------------------|---------------------------------------------------------|
| 1 | **Cognitive Services OpenAI User**     | Azure OpenAI resource(s)  | Project proxies inference calls to connected resources   |
| 2 | **Storage Blob Data Contributor**      | BYO Storage Account       | Project manages file operations for Responses API tools  |
| 3 | **Search Index Data Contributor**      | AI Search resource        | Project queries search for grounded responses            |

### For the APIM Managed Identity

| # | Role                                   | Scope                     | Why                                                     |
|---|----------------------------------------|---------------------------|---------------------------------------------------------|
| 1 | **Cognitive Services OpenAI User**     | Azure OpenAI resource(s)  | APIM uses managed identity to authenticate to backends  |

---

## Role Definition IDs (for Bicep / ARM / CLI)

```
Cognitive Services OpenAI User      5e0bd9bd-7b93-4f28-af87-19fc36ad61bd
Cognitive Services OpenAI Contrib.  a001fd3d-188f-4b5d-821b-7da978bf7442
Storage Blob Data Contributor       ba92f5b4-2d11-453d-a403-e96b0029c9fe
Search Index Data Reader            1407120a-92aa-4202-b7e9-c0e197c71c8f
Search Index Data Contributor       8ebe5a00-799e-43f5-93ac-243d3dce84a7
Azure AI Developer                  64702f94-c441-49e6-a78b-ef80e0188fee
Azure AI User                       53ca6127-dc72-4874-b2ec-3e57e4e8293f  (INSUFFICIENT alone)
```

---

## Why "Azure AI User" Is Not Enough

The `Azure AI User` role (ID: `53ca6127-dc72-4874-b2ec-3e57e4e8293f`) grants:

- `Microsoft.MachineLearningServices/workspaces/read`
- `Microsoft.MachineLearningServices/workspaces/connections/read`
- Various UI/portal read actions

It does **NOT** grant:

- `Microsoft.CognitiveServices/accounts/deployments/read` (needed for model inference)
- `Microsoft.CognitiveServices/accounts/deployments/completions/action`
- `Microsoft.CognitiveServices/accounts/deployments/responses/action`
- `Microsoft.Storage/storageAccounts/blobServices/containers/blobs/*`
- `Microsoft.Search/searchServices/indexes/documents/*`

This is why the Responses API fails with permission errors — the user can see the
project in the portal, but cannot actually invoke the underlying services.

---

## Why NOT to Use Contributor

The `Contributor` role grants:

- Full management-plane access (create/delete/modify resources)
- Data-plane access for many services
- Ability to modify network settings, RBAC (if Owner), etc.

This violates the principle of least privilege. The roles above grant **only**
the data-plane access needed to call the Responses API and its tools.

---

## CLI Commands to Assign Roles

```bash
# Variables
USER_PRINCIPAL_ID="<user-or-sp-object-id>"
OPENAI_RESOURCE_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.CognitiveServices/accounts/<name>"
STORAGE_RESOURCE_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<name>"
SEARCH_RESOURCE_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Search/searchServices/<name>"
PROJECT_RESOURCE_ID="/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.MachineLearningServices/workspaces/<project>"

# 1. Cognitive Services OpenAI User on OpenAI resource(s)
az role assignment create \
  --assignee $USER_PRINCIPAL_ID \
  --role "Cognitive Services OpenAI User" \
  --scope $OPENAI_RESOURCE_ID

# 2. Storage Blob Data Contributor on BYO storage
az role assignment create \
  --assignee $USER_PRINCIPAL_ID \
  --role "Storage Blob Data Contributor" \
  --scope $STORAGE_RESOURCE_ID

# 3. Search Index Data Contributor on AI Search
az role assignment create \
  --assignee $USER_PRINCIPAL_ID \
  --role "Search Index Data Contributor" \
  --scope $SEARCH_RESOURCE_ID

# 4. Azure AI Developer on AI Foundry project
az role assignment create \
  --assignee $USER_PRINCIPAL_ID \
  --role "Azure AI Developer" \
  --scope $PROJECT_RESOURCE_ID
```

---

## Troubleshooting Permission Errors

| Error Message | Missing Role | Scope |
|---------------|-------------|-------|
| `AuthorizationFailed` on `/deployments/*/responses` | Cognitive Services OpenAI User | Azure OpenAI resource |
| `AuthorizationPermissionMismatch` on blob operations | Storage Blob Data Contributor | Storage account |
| `403 Forbidden` on search queries | Search Index Data Contributor | AI Search resource |
| `AuthorizationFailed` on project endpoint | Azure AI Developer | AI Foundry project |
| `InvalidAuthenticationToken` | Token audience mismatch | Check `--resource` param |

**Note:** After assigning roles, allow **up to 5 minutes** for propagation before
retesting. Entra ID role assignments are eventually consistent.
