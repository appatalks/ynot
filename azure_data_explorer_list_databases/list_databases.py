#!/usr/bin/env python3
"""Azure Data Explorer helper.

This script connects to an Azure Data Explorer (Kusto) cluster and can:
- list databases you can access
- list tables in a database
- sample a few rows from a table

Why you kept seeing device-code prompts:
- Each `python list_databases.py ...` run is a new process.
- `DeviceCodeCredential` only caches tokens in-memory unless you enable
  persistent token cache.

This version enables persistent token caching so you typically authenticate
once per Codespace session (and often across sessions until the token expires).
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import subprocess
import sys
from typing import Any, List, Tuple

from azure.kusto.data import KustoClient, KustoConnectionStringBuilder
from azure.identity import (
    AuthenticationRecord,
    AzureCliCredential,
    DefaultAzureCredential,
    DeviceCodeCredential,
    TokenCachePersistenceOptions,
)


CLUSTER_URL_DEFAULT = None
KUSTO_SCOPE = "https://kusto.kusto.windows.net/.default"

# In-process cache (single Python run)
_CACHED_CREDENTIAL = None

# Cross-process cache (persists to disk). In a Linux Codespace container there is
# no OS keychain, so we allow unencrypted storage.
_CACHE_OPTIONS = TokenCachePersistenceOptions(
    name="ynot_adx_token_cache",
    allow_unencrypted_storage=True,
)

AUTH_RECORD_PATH = os.path.expanduser("~/.azure/ynot_adx_auth_record.json")


def _device_code_prompt(verification_uri: str, user_code: str, expires_on: datetime.datetime) -> None:
    print("To sign in, open the page below and enter the code:")
    print(f"  URL:  {verification_uri}")
    print(f"  Code: {user_code}")
    print(f"  Expires: {expires_on}")


def get_credential() -> Any:
    """Return a credential, using persistent cache to avoid repeated prompts."""
    global _CACHED_CREDENTIAL
    if _CACHED_CREDENTIAL is not None:
        return _CACHED_CREDENTIAL

    # 1) Prefer Azure CLI auth if available (no prompts), but this container's
    # `az` is usually not logged in.
    try:
        credential = AzureCliCredential()
        credential.get_token(KUSTO_SCOPE)
        _CACHED_CREDENTIAL = credential
        return credential
    except Exception:
        pass

    # 2) Device code auth with persistent token cache.
    try:
        auth_record = None
        if os.path.exists(AUTH_RECORD_PATH):
            with open(AUTH_RECORD_PATH, "r", encoding="utf-8") as f:
                auth_record = AuthenticationRecord.deserialize(f.read())

        credential = DeviceCodeCredential(
            prompt_callback=_device_code_prompt,
            cache_persistence_options=_CACHE_OPTIONS,
            authentication_record=auth_record,
        )

        # If we don't yet have an auth record, authenticate once and persist it.
        if auth_record is None:
            auth_record = credential.authenticate(scopes=[KUSTO_SCOPE])
            os.makedirs(os.path.dirname(AUTH_RECORD_PATH), exist_ok=True)
            with open(AUTH_RECORD_PATH, "w", encoding="utf-8") as f:
                f.write(auth_record.serialize())

        credential.get_token(KUSTO_SCOPE)
        _CACHED_CREDENTIAL = credential
        return credential
    except Exception:
        pass

    # 3) Final fallback: DefaultAzureCredential (managed identity / env vars).
    credential = DefaultAzureCredential()
    credential.get_token(KUSTO_SCOPE)
    _CACHED_CREDENTIAL = credential
    return credential


def _client(cluster_url: str) -> KustoClient:
    credential = get_credential()
    kcsb = KustoConnectionStringBuilder.with_azure_token_credential(cluster_url, credential)
    return KustoClient(kcsb)


def _extract_database_names(response) -> List[str]:
    """
    Extract database names from a Kusto query response.
    
    Args:
        response: The response object from a Kusto query
        
    Returns:
        List of database names
    """
    databases = []
    for row in response.primary_results[0]:
        # The first column is the DatabaseName
        db_name = row[0]
        databases.append(db_name)
    return databases


def _execute_database_query(client: KustoClient) -> List[str]:
    """
    Execute the database listing query on the cluster.
    
    Args:
        client: Authenticated KustoClient instance
        
    Returns:
        List of database names
    """
    query = ".show databases"
    print(f"Executing query: {query}")
    
    # Execute at cluster level (empty database parameter) for cluster-wide queries
    response = client.execute(database="", query=query)
    
    return _extract_database_names(response)


def get_databases(cluster_url: str) -> List[str]:
    client = _client(cluster_url)
    return _execute_database_query(client)


def get_tables(cluster_url: str, database_name: str) -> List[str]:
    client = _client(cluster_url)
    query = ".show tables"
    print(f"Executing query: {query}")
    response = client.execute(database=database_name, query=query)
    return [row[0] for row in response.primary_results[0]]


def _kusto_table_ref(table_name: str) -> str:
    """Return a safe table reference for KQL, handling names like `hello-world`."""
    escaped = table_name.replace("'", "''")
    return f"['{escaped}']"


def sample_rows(cluster_url: str, database_name: str, table_name: str, limit: int) -> Tuple[List[str], List[List[Any]]]:
    client = _client(cluster_url)
    query = f"{_kusto_table_ref(table_name)} | take {limit}"
    print(f"Executing query: {query}")
    response = client.execute(database=database_name, query=query)
    result = response.primary_results[0]
    columns = [col.column_name for col in result.columns]
    rows = [list(row) for row in result]
    return columns, rows


def _run_az_json(args: List[str]) -> Any:
    """Run an `az ... -o json` command and parse output."""
    try:
        proc = subprocess.run(
            ["az", *args, "-o", "json"],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
    except FileNotFoundError as e:
        raise SystemExit("Azure CLI ('az') not found on PATH. Install Azure CLI or run in Codespaces.") from e

    if proc.returncode != 0:
        stderr = (proc.stderr or "").strip()
        raise SystemExit(
            "Azure CLI command failed. If you are not logged in, run `az login` first.\n"
            f"Command: az {' '.join(args)} -o json\n"
            f"Error: {stderr}"
        )

    try:
        return json.loads(proc.stdout)
    except json.JSONDecodeError as e:
        raise SystemExit("Failed to parse Azure CLI JSON output.") from e


def discover_clusters() -> int:
    """Discover ADX clusters via Azure Resource Manager (requires Azure RBAC visibility)."""
    clusters = _run_az_json(["kusto", "cluster", "list"])
    if not isinstance(clusters, list):
        raise SystemExit("Unexpected output from `az kusto cluster list`. Expected a JSON array.")

    if not clusters:
        print("No clusters returned. You may lack Azure RBAC visibility (Reader) to ADX resources.")
        return 0

    print("Discovered ADX clusters (ARM-visible):")
    for c in clusters:
        name = c.get("name")
        resource_group = c.get("resourceGroup")
        subscription_id = c.get("subscriptionId")
        location = c.get("location")
        uri = (c.get("properties") or {}).get("uri")
        query_uri = uri or (f"https://{name}.{location}.kusto.windows.net" if name and location else None)

        parts = [p for p in [query_uri, name, location, resource_group, subscription_id] if p]
        print("- " + " | ".join(parts))

    return 0


def main():
    parser = argparse.ArgumentParser(description="ADX utility")
    parser.add_argument(
        "--cluster-url",
        default=os.getenv("ADX_CLUSTER_URL") or os.getenv("KUSTO_CLUSTER_URL") or CLUSTER_URL_DEFAULT,
        help="ADX cluster URL (or set ADX_CLUSTER_URL / KUSTO_CLUSTER_URL)",
    )
    parser.add_argument(
        "--discover-clusters",
        action="store_true",
        help="Discover ADX clusters via Azure CLI (requires Azure RBAC visibility)",
    )
    parser.add_argument("--tables", metavar="DBNAME", help="List tables in the given database")
    parser.add_argument(
        "--sample",
        nargs=2,
        metavar=("DBNAME", "TABLENAME"),
        help="Show sample rows from the given table",
    )
    parser.add_argument("--limit", type=int, default=2, help="Row limit for --sample (default: 2)")
    args = parser.parse_args()

    if args.discover_clusters:
        return discover_clusters()

    cluster_url = args.cluster_url
    if not cluster_url:
        if sys.stdin.isatty():
            cluster_url = input("Enter ADX cluster URL (https://<cluster>.<region>.kusto.windows.net): ").strip()
        if not cluster_url:
            raise SystemExit(
                "Missing cluster URL. Pass --cluster-url or set ADX_CLUSTER_URL (recommended for Codespaces secrets)."
            )

    print("=" * 80)
    print("Azure Data Explorer - Helper")
    print("=" * 80)
    print(f"\nCluster URL: {cluster_url}\n")

    try:
        if args.sample:
            dbname, tablename = args.sample
            columns, rows = sample_rows(cluster_url, dbname, tablename, limit=args.limit)
            print("\n" + "=" * 80)
            print(f"Sample rows from {dbname}.{tablename} (limit {args.limit}):")
            print("=" * 80)
            print(" | ".join(columns))
            print("-" * 80)
            for row in rows:
                print(" | ".join(str(x) for x in row))
            print("\n" + "=" * 80)
            return 0

        if args.tables:
            tables = get_tables(cluster_url, args.tables)
            print("\n" + "=" * 80)
            print(f"Successfully connected to database '{args.tables}'!")
            print(f"Found {len(tables)} table(s):")
            print("=" * 80)
            if tables:
                for i, tbl in enumerate(tables, 1):
                    print(f"{i}. {tbl}")
            else:
                print("No tables found or no access to any tables.")
            print("\n" + "=" * 80)
            return 0
        databases = get_databases(cluster_url)
        print("\n" + "=" * 80)
        print("Successfully connected to cluster!")
        print(f"Found {len(databases)} database(s):")
        print("=" * 80)
        if databases:
            for i, db_name in enumerate(databases, 1):
                print(f"{i}. {db_name}")
        else:
            print("No databases found or no access to any databases.")
        print("\n" + "=" * 80)
        return 0
    except Exception as e:
        print("\n" + "=" * 80)
        print("ERROR: Failed to retrieve information")
        print("=" * 80)
        print(f"\nError details: {e}")
        print("\n" + "=" * 80)
        return 1


if __name__ == "__main__":
    sys.exit(main())
