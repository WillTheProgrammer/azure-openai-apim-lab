#!/bin/bash
# ---------------------------------------------------------------------------
# Deploy the Azure OpenAI + APIM Load Balancing Lab
# ---------------------------------------------------------------------------
set -euo pipefail

RESOURCE_GROUP="${1:-rg-openai-apim-lab}"
LOCATION="${2:-eastus}"
USER_PRINCIPAL_ID="${3:-}"

echo "=== Azure OpenAI + APIM Lab Deployment ==="
echo "Resource Group : $RESOURCE_GROUP"
echo "Location       : $LOCATION"
echo ""

# Create resource group
echo ">>> Creating resource group..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none

# Deploy infrastructure
echo ">>> Deploying infrastructure (this takes ~15-25 minutes for APIM)..."
DEPLOY_PARAMS="environmentName=lab location=$LOCATION secondaryLocation=eastus2"

if [ -n "$USER_PRINCIPAL_ID" ]; then
  DEPLOY_PARAMS="$DEPLOY_PARAMS testUserPrincipalId=$USER_PRINCIPAL_ID"
  echo "    Will assign RBAC roles to principal: $USER_PRINCIPAL_ID"
fi

az deployment group create \
  --resource-group "$RESOURCE_GROUP" \
  --template-file infra/main.bicep \
  --parameters $DEPLOY_PARAMS \
  --output none

# Get outputs
echo ""
echo ">>> Retrieving deployment outputs..."
OUTPUTS=$(az deployment group show \
  --resource-group "$RESOURCE_GROUP" \
  --name main \
  --query properties.outputs \
  --output json 2>/dev/null || echo "{}")

OPENAI_1=$(echo "$OUTPUTS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('OPENAI_ENDPOINT_1',{}).get('value',''))" 2>/dev/null || echo "")
OPENAI_2=$(echo "$OUTPUTS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('OPENAI_ENDPOINT_2',{}).get('value',''))" 2>/dev/null || echo "")
APIM_URL=$(echo "$OUTPUTS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('APIM_GATEWAY_URL',{}).get('value',''))" 2>/dev/null || echo "")
SEARCH_EP=$(echo "$OUTPUTS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('AI_SEARCH_ENDPOINT',{}).get('value',''))" 2>/dev/null || echo "")
STORAGE_EP=$(echo "$OUTPUTS" | python3 -c "import sys,json; print(json.load(sys.stdin).get('STORAGE_BLOB_ENDPOINT',{}).get('value',''))" 2>/dev/null || echo "")

# Get APIM subscription key
APIM_NAME=$(az apim list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null || echo "")
APIM_KEY=""
if [ -n "$APIM_NAME" ]; then
  APIM_KEY=$(az rest --method post \
    --uri "/subscriptions/$(az account show --query id -o tsv)/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.ApiManagement/service/$APIM_NAME/subscriptions/lab-test-subscription/listSecrets?api-version=2024-05-01" \
    --query primaryKey -o tsv 2>/dev/null || echo "")
fi

# Write .env file
echo ""
echo ">>> Writing scripts/.env..."
cat > scripts/.env <<EOF
OPENAI_ENDPOINT_1=$OPENAI_1
OPENAI_ENDPOINT_2=$OPENAI_2
OPENAI_MODEL_DEPLOYMENT=gpt-4o
OPENAI_API_VERSION=2025-03-01-preview
APIM_GATEWAY_URL=$APIM_URL
APIM_SUBSCRIPTION_KEY=$APIM_KEY
AI_SEARCH_ENDPOINT=$SEARCH_EP
STORAGE_BLOB_ENDPOINT=$STORAGE_EP
AI_FOUNDRY_PROJECT_CONNECTION_STRING=
AI_SEARCH_INDEX_NAME=
EOF

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Endpoints:"
echo "  OpenAI (East US)  : $OPENAI_1"
echo "  OpenAI (East US 2): $OPENAI_2"
echo "  APIM Gateway      : $APIM_URL"
echo "  AI Search          : $SEARCH_EP"
echo "  Storage            : $STORAGE_EP"
echo ""
echo "Next steps:"
echo "  1. cd scripts && pip install -r requirements.txt"
echo "  2. Fill in AI_FOUNDRY_PROJECT_CONNECTION_STRING in scripts/.env"
echo "     (find it in Azure Portal > AI Foundry > Project > Overview)"
echo "  3. Apply APIM policy:"
echo "     az apim api operation policy create \\"
echo "       --resource-group $RESOURCE_GROUP \\"
echo "       --service-name $APIM_NAME \\"
echo "       --api-id azure-openai \\"
echo "       --operation-id all-operations \\"
echo "       --xml-file apim-policies/openai-load-balancer-simple.xml"
echo "  4. Run tests:"
echo "     python test_responses_api.py"
echo "     python test_apim_load_balancing.py"
echo "     python test_rbac_permissions.py"
