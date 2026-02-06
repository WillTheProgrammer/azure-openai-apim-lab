"""
Test: Azure OpenAI Responses API
=================================
Demonstrates calling the Responses API in three ways:
  1. Directly against Azure OpenAI endpoint
  2. Through APIM (load-balanced)
  3. Through AI Foundry project endpoint

This script addresses the customer's questions:
  - "How do we access a model in OpenAI when we make a request to Responses API?"
  - "What will be the OpenAI URL that we need to specify if there is a connector
     to OpenAI instance from AI Foundry?"

Prerequisites:
  - pip install -r requirements.txt
  - cp .env.sample .env  (and fill in your values)
  - az login  (for DefaultAzureCredential)
"""

import os
import sys

from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
from openai import AzureOpenAI
from rich.console import Console
from rich.panel import Panel

load_dotenv()
console = Console()

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ENDPOINT_1 = os.environ["OPENAI_ENDPOINT_1"]
ENDPOINT_2 = os.environ["OPENAI_ENDPOINT_2"]
DEPLOYMENT = os.getenv("OPENAI_MODEL_DEPLOYMENT", "gpt-4o")
API_VERSION = os.getenv("OPENAI_API_VERSION", "2025-03-01-preview")

APIM_URL = os.getenv("APIM_GATEWAY_URL", "")
APIM_KEY = os.getenv("APIM_SUBSCRIPTION_KEY", "")

AI_FOUNDRY_CONN = os.getenv("AI_FOUNDRY_PROJECT_CONNECTION_STRING", "")

TEST_PROMPT = "Explain what Azure API Management is in two sentences."


def get_credential():
    return DefaultAzureCredential()


def get_token_provider():
    return get_bearer_token_provider(
        get_credential(), "https://cognitiveservices.azure.com/.default"
    )


# ---------------------------------------------------------------------------
# Test 1: Direct call to Azure OpenAI Responses API
# ---------------------------------------------------------------------------
def test_direct_responses_api(endpoint: str, label: str):
    """
    Call the Responses API directly on an Azure OpenAI resource.

    URL pattern:
      POST https://{resource}.openai.azure.com/openai/responses?api-version=2025-03-01-preview

    The OpenAI Python SDK handles this when you set:
      - azure_endpoint = your resource endpoint
      - api_version = 2025-03-01-preview (or later)
    """
    console.print(f"\n[bold cyan]>>> Test: Direct Responses API — {label}[/bold cyan]")
    console.print(f"    Endpoint: {endpoint}")

    client = AzureOpenAI(
        azure_endpoint=endpoint,
        api_version=API_VERSION,
        azure_ad_token_provider=get_token_provider(),
    )

    response = client.responses.create(
        model=DEPLOYMENT,
        input=TEST_PROMPT,
    )

    console.print(Panel(
        response.output_text,
        title=f"Response from {label}",
        subtitle=f"model={response.model} | tokens={response.usage.total_tokens}",
    ))
    return response


# ---------------------------------------------------------------------------
# Test 2: Call through APIM (load-balanced across both backends)
# ---------------------------------------------------------------------------
def test_apim_responses_api():
    """
    Call the Responses API through APIM, which load-balances to both backends.

    URL pattern:
      POST https://{apim}.azure-api.net/openai/responses?api-version=2025-03-01-preview

    The APIM policy:
      - Routes to the backend pool (round-robin East US / East US 2)
      - Authenticates to Azure OpenAI using APIM's managed identity
      - Retries on 429/5xx with failover to the other backend
    """
    if not APIM_URL:
        console.print("[yellow]>>> Skipping APIM test (APIM_GATEWAY_URL not set)[/yellow]")
        return None

    console.print("\n[bold cyan]>>> Test: Responses API via APIM (load-balanced)[/bold cyan]")
    console.print(f"    Gateway: {APIM_URL}")

    client = AzureOpenAI(
        azure_endpoint=APIM_URL,
        api_version=API_VERSION,
        api_key=APIM_KEY,  # APIM subscription key (APIM handles Entra auth to backend)
    )

    response = client.responses.create(
        model=DEPLOYMENT,
        input=TEST_PROMPT,
    )

    console.print(Panel(
        response.output_text,
        title="Response via APIM",
        subtitle=f"model={response.model} | tokens={response.usage.total_tokens}",
    ))
    return response


# ---------------------------------------------------------------------------
# Test 3: Call through AI Foundry project endpoint
# ---------------------------------------------------------------------------
def test_ai_foundry_responses_api():
    """
    Call the Responses API through an AI Foundry project.

    When you create a connection from AI Foundry to Azure OpenAI, the project
    exposes its own inference endpoint. The SDK resolves the correct backend
    OpenAI resource based on the model deployment and connection.

    The URL you use is the AI Foundry PROJECT endpoint, NOT the raw OpenAI
    resource endpoint. The project routes to whichever connected OpenAI
    resource has the requested model deployment.

    This answers the customer's question:
      "What will be the OpenAI URL if there is a connector to OpenAI from AI Foundry?"
      → You use the AI Foundry project's endpoint, and the project resolves the backend.
    """
    if not AI_FOUNDRY_CONN:
        console.print("[yellow]>>> Skipping AI Foundry test (connection string not set)[/yellow]")
        return None

    console.print("\n[bold cyan]>>> Test: Responses API via AI Foundry Project[/bold cyan]")
    console.print(f"    Connection: {AI_FOUNDRY_CONN}")

    try:
        from azure.ai.projects import AIProjectClient

        project_client = AIProjectClient.from_connection_string(
            conn_str=AI_FOUNDRY_CONN,
            credential=get_credential(),
        )

        # Get an AzureOpenAI client scoped to this project.
        # The project resolves which connected OpenAI resource to use.
        client = project_client.inference.get_azure_openai_client(
            api_version=API_VERSION,
        )

        response = client.responses.create(
            model=DEPLOYMENT,
            input=TEST_PROMPT,
        )

        console.print(Panel(
            response.output_text,
            title="Response via AI Foundry",
            subtitle=f"model={response.model} | tokens={response.usage.total_tokens}",
        ))
        return response

    except ImportError:
        console.print("[red]azure-ai-projects not installed. pip install azure-ai-projects[/red]")
        return None


# ---------------------------------------------------------------------------
# Test 4: Responses API with tools (file_search — requires BYO storage + AI Search)
# ---------------------------------------------------------------------------
def test_responses_api_with_search():
    """
    Call the Responses API with the file_search tool, which requires:
      - BYO storage account access (Storage Blob Data Contributor)
      - AI Search access (Search Index Data Contributor)
      - Cognitive Services OpenAI User on the OpenAI resource

    This is the scenario where the customer gets permission errors with only
    the "Azure AI User" role.
    """
    search_endpoint = os.getenv("AI_SEARCH_ENDPOINT", "")
    search_index = os.getenv("AI_SEARCH_INDEX_NAME", "")

    if not search_endpoint or not search_index:
        console.print("[yellow]>>> Skipping search grounding test (AI_SEARCH_* not set)[/yellow]")
        return None

    console.print("\n[bold cyan]>>> Test: Responses API with Azure AI Search grounding[/bold cyan]")

    client = AzureOpenAI(
        azure_endpoint=ENDPOINT_1,
        api_version=API_VERSION,
        azure_ad_token_provider=get_token_provider(),
    )

    response = client.responses.create(
        model=DEPLOYMENT,
        input="What are the key topics in the indexed documents?",
        tools=[
            {
                "type": "file_search",
                "file_search": {
                    "ranking_options": {
                        "ranker": "default_2024_08_21",
                    }
                },
            }
        ],
    )

    console.print(Panel(
        response.output_text,
        title="Response with AI Search grounding",
        subtitle=f"model={response.model}",
    ))
    return response


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    console.print(Panel.fit(
        "[bold]Azure OpenAI Responses API — Lab Test Suite[/bold]\n"
        "Tests direct, APIM, and AI Foundry access patterns",
        border_style="green",
    ))

    test_direct_responses_api(ENDPOINT_1, "East US (primary)")
    test_direct_responses_api(ENDPOINT_2, "East US 2 (secondary)")
    test_apim_responses_api()
    test_ai_foundry_responses_api()
    test_responses_api_with_search()

    console.print("\n[bold green]All tests complete.[/bold green]")


if __name__ == "__main__":
    main()
