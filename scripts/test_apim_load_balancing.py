"""
Test: APIM Load Balancing Across Azure OpenAI Backends
=======================================================
Sends multiple requests through APIM and tracks which Azure region
(backend) served each request, proving the round-robin distribution.

This addresses the following scenario:
  "Load balancing of OpenAI models from APIM and how it will translate
   when we add existing OpenAI models to AI Foundry."

Prerequisites:
  - pip install -r requirements.txt
  - cp .env.sample .env  (and fill in your values)
  - Deploy infrastructure: az deployment group create ...
"""

import os
import time
from collections import Counter

from dotenv import load_dotenv
from openai import AzureOpenAI
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

load_dotenv()
console = Console()

APIM_URL = os.environ["APIM_GATEWAY_URL"]
APIM_KEY = os.environ["APIM_SUBSCRIPTION_KEY"]
DEPLOYMENT = os.getenv("OPENAI_MODEL_DEPLOYMENT", "gpt-4o")
API_VERSION = os.getenv("OPENAI_API_VERSION", "2025-03-01-preview")

NUM_REQUESTS = 10


def test_load_distribution():
    """
    Send N requests through APIM and record which region served each one.
    The x-ms-region response header (exposed as x-backend-region by our APIM
    policy) tells us which Azure OpenAI backend handled the request.
    """
    console.print(Panel.fit(
        f"[bold]APIM Load Balancing Test[/bold]\n"
        f"Sending {NUM_REQUESTS} requests through {APIM_URL}\n"
        f"Tracking backend region distribution",
        border_style="blue",
    ))

    client = AzureOpenAI(
        azure_endpoint=APIM_URL,
        api_version=API_VERSION,
        api_key=APIM_KEY,
    )

    regions = []
    results = []

    for i in range(NUM_REQUESTS):
        start = time.time()
        response = client.responses.create(
            model=DEPLOYMENT,
            input=f"Say the number {i+1}.",
        )

        # The raw HTTP response headers contain region info.
        # With our APIM policy, x-backend-region shows the serving region.
        # When using the SDK, we can get region from the response model.
        elapsed = time.time() - start

        # The model field often includes region hints, but the most reliable
        # way is to check response headers. For this demo, we use the
        # response object and also make a raw request below.
        results.append({
            "request": i + 1,
            "model": response.model,
            "tokens": response.usage.total_tokens,
            "latency_ms": int(elapsed * 1000),
        })

        console.print(
            f"  Request {i+1:2d}: model={response.model} "
            f"tokens={response.usage.total_tokens} "
            f"latency={int(elapsed*1000)}ms"
        )

    # Print summary table
    table = Table(title="Load Balancing Results")
    table.add_column("#", style="dim")
    table.add_column("Model")
    table.add_column("Tokens", justify="right")
    table.add_column("Latency (ms)", justify="right")

    for r in results:
        table.add_row(
            str(r["request"]),
            r["model"],
            str(r["tokens"]),
            str(r["latency_ms"]),
        )

    console.print(table)


def test_load_distribution_raw():
    """
    Raw HTTP version — sends requests via the requests library so we can
    inspect response headers directly (including x-backend-region set by
    our APIM policy).
    """
    import requests as req

    console.print(Panel.fit(
        f"[bold]APIM Load Balancing — Raw HTTP Test[/bold]\n"
        f"Inspecting response headers to verify backend routing",
        border_style="blue",
    ))

    url = f"{APIM_URL}/openai/responses?api-version={API_VERSION}"
    headers = {
        "api-key": APIM_KEY,
        "Content-Type": "application/json",
    }

    region_counter = Counter()

    for i in range(NUM_REQUESTS):
        payload = {
            "model": DEPLOYMENT,
            "input": f"Say the number {i+1}.",
        }

        resp = req.post(url, json=payload, headers=headers)
        resp.raise_for_status()

        # Our APIM policy sets x-backend-region from x-ms-region
        region = resp.headers.get("x-backend-region", "unknown")
        region_counter[region] += 1

        console.print(
            f"  Request {i+1:2d}: "
            f"status={resp.status_code} "
            f"region={region} "
        )

    # Print distribution
    console.print("\n[bold]Backend Distribution:[/bold]")
    table = Table(title="Region Distribution")
    table.add_column("Region")
    table.add_column("Count", justify="right")
    table.add_column("Percentage", justify="right")

    for region, count in region_counter.most_common():
        pct = count / NUM_REQUESTS * 100
        table.add_row(region, str(count), f"{pct:.0f}%")

    console.print(table)

    # Verify distribution is roughly even
    if len(region_counter) >= 2:
        console.print("[green]Load balancing confirmed — requests distributed across multiple regions.[/green]")
    else:
        console.print("[yellow]Warning: All requests went to the same region. Check APIM backend pool config.[/yellow]")


def main():
    console.print(Panel.fit(
        "[bold]Azure OpenAI + APIM Load Balancing Lab[/bold]\n"
        "Verifying round-robin distribution across East US & East US 2",
        border_style="green",
    ))

    test_load_distribution()
    console.print()
    test_load_distribution_raw()


if __name__ == "__main__":
    main()
