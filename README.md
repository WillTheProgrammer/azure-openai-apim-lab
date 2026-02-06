# Azure OpenAI + APIM Load Balancing + AI Foundry Lab

Lab environment demonstrating Azure OpenAI enterprise patterns. Covers:

1. **APIM load balancing** across multi-region Azure OpenAI instances (the following scenario)
2. **Responses API routing** through APIM and AI Foundry connectors
3. **Minimum RBAC permissions** for Responses API with BYO storage + AI Search (no Contributor needed)
4. **Working test scripts** for hands-on validation of all scenarios

## Architecture

```
                    ┌─────────────────────────────────────────┐
                    │              Client App                  │
                    └───────┬──────────────┬──────────────┬───┘
                            │              │              │
                   Direct call      Via APIM        Via AI Foundry
                            │              │              │
                            │    ┌─────────▼──────────┐   │
                            │    │   API Management    │   │
                            │    │   (Load Balancer)   │   │
                            │    │                     │   │
                            │    │  ┌──────────────┐   │   │
                            │    │  │ Backend Pool │   │   │
                            │    │  │  50% / 50%   │   │   │
                            │    │  └──┬───────┬───┘   │   │
                            │    └─────┼───────┼───────┘   │
                            │          │       │           │
                 ┌──────────▼──────────▼┐  ┌──▼───────────▼────────┐
                 │  Azure OpenAI        │  │  Azure OpenAI          │
                 │  East US             │  │  East US 2             │
                 │  (GPT-4o)            │  │  (GPT-4o)              │
                 └──────────────────────┘  └────────────────────────┘
                            ▲                          ▲
                            │      ┌───────────┐       │
                            └──────┤ AI Foundry ├──────┘
                                   │  Project   │
                                   │            │
                                   │ Connections:│
                                   │ • aoai-eus │
                                   │ • aoai-eus2│
                                   │ • ai-search│
                                   └──────┬─────┘
                                          │
                          ┌───────────────┼───────────────┐
                          │               │               │
                   ┌──────▼──────┐ ┌──────▼──────┐ ┌─────▼──────┐
                   │ BYO Storage │ │  AI Search  │ │  Key Vault │
                   │  Account    │ │             │ │            │
                   └─────────────┘ └─────────────┘ └────────────┘
```

## Quick Start

### Prerequisites

- Azure CLI (`az`) logged in with a subscription that can create resources
- Python 3.10+
- Bash shell

### 1. Deploy Infrastructure

```bash
# Basic deployment
./scripts/deploy.sh rg-openai-apim-lab eastus

# With RBAC role assignments for a specific user
USER_OID=$(az ad signed-in-user show --query id -o tsv)
./scripts/deploy.sh rg-openai-apim-lab eastus "$USER_OID"
```

> **Note:** APIM deployment takes ~15-25 minutes. Other resources deploy in ~5 minutes.

### 2. Apply APIM Load Balancing Policy

```bash
# Use the simplified policy (no Event Hub dependency)
az apim api operation policy create \
  --resource-group rg-openai-apim-lab \
  --service-name <apim-name> \
  --api-id azure-openai \
  --operation-id all-operations \
  --xml-file apim-policies/openai-load-balancer-simple.xml
```

### 3. Run Tests

```bash
cd scripts
pip install -r requirements.txt

# Test Responses API (direct, APIM, AI Foundry)
python test_responses_api.py

# Test load balancing distribution
python test_apim_load_balancing.py

# Validate RBAC permissions
python test_rbac_permissions.py
```

## Customer Questions & Answers

### Q1: How does APIM load balance OpenAI models, and how does it translate to AI Foundry?

**APIM Load Balancing:**
- APIM uses a **backend pool** (`openai-pool`) with two Azure OpenAI backends
- Requests are distributed via **weighted round-robin** (configurable 50/50, 70/30, etc.)
- The APIM policy adds **retry with failover**: if one backend returns 429 or 5xx, the request retries on the other backend
- APIM authenticates to Azure OpenAI using its **managed identity** (no API keys)

**Translation to AI Foundry:**
- AI Foundry does **not** natively provide APIM-style load balancing across connected OpenAI resources
- When you add multiple OpenAI connections to AI Foundry, each connection maps to a specific resource
- The project endpoint routes to whichever connected resource has the requested model deployment
- **Recommendation:** Keep APIM as the load balancer in front of OpenAI, and optionally connect APIM (as a single endpoint) to AI Foundry — or manage routing at the application layer

See: [`apim-policies/`](./apim-policies/) and [`scripts/test_apim_load_balancing.py`](./scripts/test_apim_load_balancing.py)

### Q2: What URL do we use for the Responses API with AI Foundry connectors?

Three access patterns are demonstrated:

| Pattern | URL | Auth |
|---------|-----|------|
| **Direct** | `https://{resource}.openai.azure.com/openai/responses?api-version=2025-03-01-preview` | Entra ID token (`cognitiveservices.azure.com`) |
| **Via APIM** | `https://{apim}.azure-api.net/openai/responses?api-version=2025-03-01-preview` | APIM subscription key (APIM handles Entra auth to backend) |
| **Via AI Foundry** | Use the SDK: `project_client.inference.get_azure_openai_client()` then call `client.responses.create()` | Entra ID token (SDK handles routing to the correct connected resource) |

**Key insight:** With AI Foundry, you do NOT specify the raw OpenAI resource URL. The SDK resolves which connected OpenAI resource to use based on the model deployment name and the project's connections.

See: [`scripts/test_responses_api.py`](./scripts/test_responses_api.py)

### Q3: What are the minimum RBAC permissions for Responses API with BYO storage + AI Search?

The `Azure AI User` role alone is **insufficient**. The minimum required roles are:

| Role | Scope | Purpose |
|------|-------|---------|
| **Cognitive Services OpenAI User** | Azure OpenAI resource(s) | Inference access |
| **Storage Blob Data Contributor** | BYO Storage Account | File operations for Responses API tools |
| **Search Index Data Contributor** | AI Search resource | Search queries for grounding |
| **Azure AI Developer** | AI Foundry Project | Project endpoint access |

See: [`docs/rbac-permissions.md`](./docs/rbac-permissions.md) for the full guide including CLI commands, troubleshooting, and why Contributor is not needed.

## Repo Structure

```
├── README.md                              # This file
├── infra/
│   ├── main.bicep                         # Main deployment orchestrator
│   ├── main.bicepparam                    # Default parameters
│   └── modules/
│       ├── openai.bicep                   # Azure OpenAI resource + model deployment
│       ├── apim.bicep                     # APIM + backend pool + API definition
│       ├── ai-foundry.bicep               # AI Foundry hub + project + connections
│       ├── ai-search.bicep                # AI Search resource
│       ├── storage.bicep                  # BYO storage account
│       └── rbac.bicep                     # All RBAC role assignments (documented)
├── apim-policies/
│   ├── openai-load-balancer.xml           # Full policy (with Event Hub logging)
│   └── openai-load-balancer-simple.xml    # Simplified policy (no dependencies)
├── scripts/
│   ├── deploy.sh                          # One-command deployment script
│   ├── .env.sample                        # Environment variable template
│   ├── requirements.txt                   # Python dependencies
│   ├── test_responses_api.py              # Test Responses API (3 access patterns)
│   ├── test_apim_load_balancing.py        # Test APIM load distribution
│   └── test_rbac_permissions.py           # Validate RBAC permissions
└── docs/
    └── rbac-permissions.md                # Detailed RBAC guide for the customer
```

## Cleanup

```bash
az group delete --name rg-openai-apim-lab --yes --no-wait
```
