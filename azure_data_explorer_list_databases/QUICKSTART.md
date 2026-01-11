# Quick Start Guide

## Azure Data Explorer Database Listing Tool

This guide will help you quickly connect to the Azure Data Explorer cluster and list your databases.

### 🚀 Quick Start (3 Steps)

#### 1. Install Dependencies

```bash
cd azure_data_explorer_list_databases
pip install -r requirements.txt
```

#### 2. Authenticate with Azure

```bash
az login
```

For device code authentication (useful in remote sessions):
```bash
az login --use-device-code
```

#### 3. Run the Script

```bash
python list_databases.py
```

If you don’t know your cluster URL but have Azure RBAC visibility to ADX resources:
```bash
python list_databases.py --discover-clusters
```

Or use the helper script:
```bash
./run_example.sh
```

### 📋 What You'll Get

The script connects to the ADX cluster URL you provide via `--cluster-url` or the `ADX_CLUSTER_URL` environment variable.

And displays all databases you have access to:

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
1. Database1
2. Database2
3. Database3

================================================================================
```

### ⚙️ Configuration

You can provide the cluster URL one of these ways:

1) Pass it explicitly:
```bash
python list_databases.py --cluster-url "https://<yourcluster>.<region>.kusto.windows.net"
```

2) Set an environment variable (recommended for Codespaces):
```bash
export ADX_CLUSTER_URL="https://<yourcluster>.<region>.kusto.windows.net"
python list_databases.py
```

In GitHub Codespaces, store `ADX_CLUSTER_URL` as a Codespaces/Repo secret so the URL isn’t committed into the repo.

### 🔧 Testing Without Azure Access

If you want to verify the script structure without Azure credentials:

```bash
python test_structure.py
```

This will verify:
- All imports work correctly
- Functions are properly defined
- Script is executable
- Package dependencies are installed

### 🆘 Troubleshooting

**Problem: "Please run 'az login' to setup account"**
- Solution: Run `az login` and authenticate with your Azure account

**Problem: "No databases found"**
- You may not have access to any databases
- Contact your Azure administrator to grant permissions
- Requires at least "Database Viewer" role

**Problem: "Connection timeout"**
- Check network connectivity
- Verify the cluster URL is correct
- Ensure firewall rules allow your IP

**Problem: Import errors**
- Make sure dependencies are installed: `pip install -r requirements.txt`
- Check Python version: `python --version` (needs 3.6+)

### 📚 Additional Resources

- [Full README](README.md) - Comprehensive documentation
- [MCP Setup Guide](../azure-mcp-data-explorer-deployer/MCP_SETUP.md) - AI assistant integration
- [Azure Data Explorer Docs](https://learn.microsoft.com/en-us/azure/data-explorer/)

### 🎯 Next Steps

After listing your databases, you can:
1. Query specific databases using KQL (Kusto Query Language)
2. Set up MCP server integration for AI-powered queries
3. Explore table schemas and data
4. Create custom queries and reports

See the main [README.md](README.md) for more advanced usage examples.
