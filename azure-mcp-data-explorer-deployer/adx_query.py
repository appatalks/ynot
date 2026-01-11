from __future__ import annotations

import argparse
import os
import re
import json
import subprocess
from typing import Any

from adx_client import get_kusto_client, kql_table_ref


def _require(value: str | None, name: str) -> str:
    if value is None or not value.strip():
        raise SystemExit(f"Missing {name}. Pass it explicitly or set {name} in .env")
    return value.strip()


_MGMT_PREFIX = re.compile(r"^\s*\.")


def _looks_like_management_or_write(kql: str) -> bool:
    """Best-effort guardrail: block management commands and common write verbs by default."""
    if _MGMT_PREFIX.search(kql):
        return True
    lowered = kql.lower()
    # Not exhaustive, but catches common ingestion/update patterns.
    write_markers = [
        ".ingest",
        ".set",
        ".append",
        ".drop",
        ".delete",
        ".create",
        ".alter",
        ".rename",
        "set-or-append",
        "set-or-replace",
        "ingest inline",
    ]
    return any(marker in lowered for marker in write_markers)


def _run_az_json(args: list[str]) -> Any:
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

        # `properties.uri` is the query endpoint; fall back to a common pattern if missing.
        query_uri = uri or (f"https://{name}.{location}.kusto.windows.net" if name and location else None)

        parts = [p for p in [query_uri, name, location, resource_group, subscription_id] if p]
        print("- " + " | ".join(parts))

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="ADX quick query helper (cached device-code auth)")
    parser.add_argument("--cluster-url", default=os.getenv("ADX_CLUSTER_URL"))
    parser.add_argument("--database", default=os.getenv("ADX_DATABASE"))

    # Safety: read-only by default. You must opt in to run management/write KQL.
    parser.add_argument(
        "--allow-admin",
        action="store_true",
        help="Allow management commands and write operations (use with care)",
    )

    group = parser.add_mutually_exclusive_group()
    group.add_argument("--databases", action="store_true", help="List databases you can access")
    group.add_argument("--tables", action="store_true", help="List tables in the database")
    group.add_argument("--sample", metavar="TABLE", help="Sample rows from a table")
    group.add_argument("--kql", metavar="QUERY", help="Run an arbitrary KQL query (read-only by default)")
    group.add_argument(
        "--discover-clusters",
        action="store_true",
        help="Discover ADX clusters via Azure CLI (requires Azure RBAC visibility)",
    )

    parser.add_argument("--limit", type=int, default=2, help="Row limit for --sample")
    args = parser.parse_args()

    if args.discover_clusters:
        return discover_clusters()

    cluster_url = _require(args.cluster_url, "ADX_CLUSTER_URL")

    client = get_kusto_client(cluster_url)

    if args.databases:
        resp = client.execute(database="", query=".show databases")
        print("Databases:")
        for row in resp.primary_results[0]:
            print(f"- {row[0]}")
        return 0

    database = _require(args.database, "ADX_DATABASE")

    if args.tables:
        resp = client.execute(database, ".show tables")
        print(f"Tables in {database}:")
        for row in resp.primary_results[0]:
            print(f"- {row[0]}")
        return 0

    if args.sample:
        query = f"{kql_table_ref(args.sample)} | take {args.limit}"
        resp = client.execute(database, query)
        result = resp.primary_results[0]
        cols = [c.column_name for c in result.columns]
        print(" | ".join(cols))
        for row in result:
            print(" | ".join(str(v) for v in row))
        return 0

    if args.kql:
        if not args.allow_admin and _looks_like_management_or_write(args.kql):
            raise SystemExit(
                "Refusing to run management/write KQL without --allow-admin. "
                "If you intend to run admin commands, re-run with --allow-admin."
            )

        resp = client.execute(database, args.kql)
        result = resp.primary_results[0]
        cols = [c.column_name for c in result.columns]
        print(" | ".join(cols))
        for row in result:
            print(" | ".join(str(v) for v in row))
        return 0

    # Default action: show help-ish hint
    parser.print_help()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
