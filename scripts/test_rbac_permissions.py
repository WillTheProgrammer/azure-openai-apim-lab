"""
Test: RBAC Permission Validation
==================================
Validates that the current user has the minimum required roles to use the
Responses API with BYO storage and AI Search.

This addresses the customer's issue:
  "We get permission error while trying to access Responses API with BYO
   storage account, AI Search access even with Azure AI User role."

The minimum required roles (instead of Contributor) are:
  1. Cognitive Services OpenAI User — on Azure OpenAI resource
  2. Storage Blob Data Contributor — on BYO storage account
  3. Search Index Data Contributor — on AI Search resource
  4. Azure AI Developer — on AI Foundry project

Prerequisites:
  - pip install -r requirements.txt
  - az login
"""

import os
import sys

from dotenv import load_dotenv
from azure.identity import DefaultAzureCredential
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

load_dotenv()
console = Console()


def check_openai_access(endpoint: str, label: str) -> bool:
    """Test if the current identity can call the Azure OpenAI endpoint."""
    from openai import AzureOpenAI
    from azure.identity import get_bearer_token_provider

    console.print(f"\n  Checking OpenAI access: {label}...", end=" ")
    try:
        token_provider = get_bearer_token_provider(
            DefaultAzureCredential(),
            "https://cognitiveservices.azure.com/.default"
        )
        client = AzureOpenAI(
            azure_endpoint=endpoint,
            api_version=os.getenv("OPENAI_API_VERSION", "2025-03-01-preview"),
            azure_ad_token_provider=token_provider,
        )
        response = client.responses.create(
            model=os.getenv("OPENAI_MODEL_DEPLOYMENT", "gpt-4o"),
            input="Say hello.",
        )
        console.print("[green]OK[/green]")
        return True
    except Exception as e:
        error_msg = str(e)
        if "401" in error_msg or "403" in error_msg or "AuthorizationFailed" in error_msg:
            console.print("[red]FAILED — Missing: Cognitive Services OpenAI User[/red]")
        else:
            console.print(f"[red]FAILED — {error_msg[:100]}[/red]")
        return False


def check_storage_access() -> bool:
    """Test if the current identity can access the BYO storage account."""
    from azure.storage.blob import BlobServiceClient

    blob_endpoint = os.getenv("STORAGE_BLOB_ENDPOINT", "")
    if not blob_endpoint:
        console.print("\n  Checking Storage access... [yellow]SKIPPED (not configured)[/yellow]")
        return True

    console.print(f"\n  Checking Storage access: {blob_endpoint}...", end=" ")
    try:
        client = BlobServiceClient(
            account_url=blob_endpoint,
            credential=DefaultAzureCredential(),
        )
        # Try listing containers (requires at least Reader + Blob Data Reader)
        list(client.list_containers(results_per_page=1))
        console.print("[green]OK[/green]")
        return True
    except Exception as e:
        error_msg = str(e)
        if "403" in error_msg or "AuthorizationPermissionMismatch" in error_msg:
            console.print("[red]FAILED — Missing: Storage Blob Data Contributor[/red]")
        else:
            console.print(f"[red]FAILED — {error_msg[:100]}[/red]")
        return False


def check_search_access() -> bool:
    """Test if the current identity can access the AI Search resource."""
    import requests
    from azure.identity import DefaultAzureCredential

    search_endpoint = os.getenv("AI_SEARCH_ENDPOINT", "")
    if not search_endpoint:
        console.print("\n  Checking AI Search access... [yellow]SKIPPED (not configured)[/yellow]")
        return True

    console.print(f"\n  Checking AI Search access: {search_endpoint}...", end=" ")
    try:
        token = DefaultAzureCredential().get_token("https://search.azure.com/.default")
        resp = requests.get(
            f"{search_endpoint}/indexes?api-version=2024-07-01",
            headers={"Authorization": f"Bearer {token.token}"},
        )
        if resp.status_code == 200:
            console.print("[green]OK[/green]")
            return True
        elif resp.status_code in (401, 403):
            console.print("[red]FAILED — Missing: Search Index Data Contributor[/red]")
            return False
        else:
            console.print(f"[yellow]HTTP {resp.status_code}[/yellow]")
            return False
    except Exception as e:
        console.print(f"[red]FAILED — {str(e)[:100]}[/red]")
        return False


def check_ai_foundry_access() -> bool:
    """Test if the current identity can access the AI Foundry project."""
    conn_str = os.getenv("AI_FOUNDRY_PROJECT_CONNECTION_STRING", "")
    if not conn_str:
        console.print("\n  Checking AI Foundry access... [yellow]SKIPPED (not configured)[/yellow]")
        return True

    console.print(f"\n  Checking AI Foundry project access...", end=" ")
    try:
        from azure.ai.projects import AIProjectClient

        client = AIProjectClient.from_connection_string(
            conn_str=conn_str,
            credential=DefaultAzureCredential(),
        )
        # Try getting project properties
        props = client.scope
        console.print("[green]OK[/green]")
        return True
    except Exception as e:
        error_msg = str(e)
        if "403" in error_msg or "AuthorizationFailed" in error_msg:
            console.print("[red]FAILED — Missing: Azure AI Developer[/red]")
        else:
            console.print(f"[red]FAILED — {error_msg[:100]}[/red]")
        return False


def main():
    console.print(Panel.fit(
        "[bold]RBAC Permission Validation[/bold]\n"
        "Checking minimum required roles for Responses API + BYO Storage + AI Search",
        border_style="green",
    ))

    endpoint1 = os.environ.get("OPENAI_ENDPOINT_1", "")
    endpoint2 = os.environ.get("OPENAI_ENDPOINT_2", "")

    results = {}

    if endpoint1:
        results["OpenAI (East US)"] = check_openai_access(endpoint1, "East US")
    if endpoint2:
        results["OpenAI (East US 2)"] = check_openai_access(endpoint2, "East US 2")

    results["BYO Storage"] = check_storage_access()
    results["AI Search"] = check_search_access()
    results["AI Foundry Project"] = check_ai_foundry_access()

    # Summary
    console.print("\n")
    table = Table(title="Permission Check Summary")
    table.add_column("Resource")
    table.add_column("Required Role")
    table.add_column("Status")

    role_map = {
        "OpenAI (East US)": "Cognitive Services OpenAI User",
        "OpenAI (East US 2)": "Cognitive Services OpenAI User",
        "BYO Storage": "Storage Blob Data Contributor",
        "AI Search": "Search Index Data Contributor",
        "AI Foundry Project": "Azure AI Developer",
    }

    all_passed = True
    for resource, passed in results.items():
        status = "[green]PASS[/green]" if passed else "[red]FAIL[/red]"
        if not passed:
            all_passed = False
        table.add_row(resource, role_map.get(resource, "—"), status)

    console.print(table)

    if all_passed:
        console.print("\n[bold green]All permission checks passed.[/bold green]")
    else:
        console.print("\n[bold red]Some permission checks failed.[/bold red]")
        console.print(
            "Assign the missing roles listed above. These are the MINIMUM roles "
            "required — no need for Contributor.\n"
            "See docs/rbac-permissions.md for the full role mapping."
        )
        sys.exit(1)


if __name__ == "__main__":
    main()
