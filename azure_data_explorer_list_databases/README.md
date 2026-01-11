# Azure Data Explorer Database Listing Tool

A Python script to connect to an Azure Data Explorer (ADX/Kusto) cluster and list all databases that you have access to.

## Overview

This tool connects to an Azure Data Explorer cluster URL you provide (via `--cluster-url` or environment variable) and displays all databases the authenticated user has access to.

## Prerequisites

- Python 3.6 or later
- Azure CLI installed and configured
- Access to the Azure Data Explorer cluster

## Installation

1. Install required Python packages:

```bash
pip install azure-kusto-data azure-identity
```

2. Authenticate with Azure CLI:

```bash
az login
```

If you have multiple subscriptions, set the appropriate one:

```bash
az account list --output table
az account set --subscription <subscription-id>
```

## Usage

Run the script:

```bash
python list_databases.py --cluster-url "https://<yourcluster>.<region>.kusto.windows.net"
```

Or set an environment variable (recommended for Codespaces):

```bash
export ADX_CLUSTER_URL="https://<yourcluster>.<region>.kusto.windows.net"
python list_databases.py
```

If you don’t know your cluster URL but have Azure RBAC visibility (e.g., Reader) to ADX resources, you can discover clusters via Azure CLI:

```bash
python list_databases.py --discover-clusters
```

This uses ARM discovery (`az kusto cluster list`) and may require `az login`.

Or make it executable and run directly:

```bash
chmod +x list_databases.py
./list_databases.py
```

## Output

The script will display:
- Connection status
- Total number of databases found
- List of database names (numbered)

Example output:
```
================================================================================
Azure Data Explorer - Database Listing Tool
================================================================================

Cluster URL: https://<yourcluster>.<region>.kusto.windows.net

Note: Make sure you've authenticated with Azure CLI by running 'az login'

Attempting authentication with Azure CLI credentials...
Executing query: .show databases

================================================================================
Successfully connected to cluster!
Found 3 database(s):
================================================================================
1. MyDatabase1
2. MyDatabase2
3. TestDatabase

================================================================================
```

## Authentication Methods

The script supports multiple authentication methods, tried in order:

1. **Azure CLI Credentials** (default, recommended for development)
   - Requires running `az login` first
   - Uses your personal Azure account

2. **DefaultAzureCredential** (fallback)
   - Managed Identity (when running in Azure services)
   - Service Principal (via environment variables)
   - Visual Studio Code authentication
   - Other Azure SDK authentication methods

## Troubleshooting

### Authentication Errors

If you see authentication errors:

1. Ensure you're logged in to Azure CLI:
   ```bash
   az login
   az account show
   ```

2. Verify your account has access to the cluster:
   - You need at least "Database Viewer" or "Database User" role
   - Contact your Azure administrator if you don't have access

### Connection Errors

If you can't connect to the cluster:

1. Verify the cluster URL is correct
2. Check network connectivity
3. Ensure the cluster exists and is running
4. Verify firewall rules allow your IP address

### No Databases Listed

If no databases appear:

1. You may not have permissions on any databases
2. The cluster might be empty
3. Contact your Azure administrator to grant appropriate permissions

## Permissions Required

To list databases, you need one of these roles on the cluster:
- **Database Viewer** - Can view database metadata
- **Database User** - Can query and view data
- **Database Admin** - Full database access
- **All Databases Viewer** - Can view all database metadata

## Related Resources

- [Azure Data Explorer Documentation](https://learn.microsoft.com/en-us/azure/data-explorer/)
- [Kusto Query Language (KQL)](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- [Azure Data Explorer Python SDK](https://learn.microsoft.com/en-us/azure/data-explorer/kusto/api/python/kusto-python-client-library)

## Integration with MCP Servers

This repository includes Azure Data Explorer MCP (Model Context Protocol) server integration. See [azure-mcp-data-explorer-deployer/MCP_SETUP.md](../azure-mcp-data-explorer-deployer/MCP_SETUP.md) for information on:
- Automatic cluster and database discovery
- AI assistant integration (GitHub Copilot, Claude Desktop, VS Code)
- Natural language queries to KQL translation

## License

See the LICENSE file in the repository root.
