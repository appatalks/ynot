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

Or use the helper script:
```bash
./run_example.sh
```

### 📋 What You'll Get

The script connects to:
```
https://kvc-k3qugk4g1mk0bzue1v.southcentralus.kusto.windows.net
```

And displays all databases you have access to:

```
================================================================================
Azure Data Explorer - Database Listing Tool
================================================================================

Cluster URL: https://kvc-k3qugk4g1mk0bzue1v.southcentralus.kusto.windows.net

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

The cluster URL is hardcoded in the script (`list_databases.py`) but can be easily modified:

```python
# Line 98 in list_databases.py
cluster_url = "https://kvc-k3qugk4g1mk0bzue1v.southcentralus.kusto.windows.net"
```

To use a different cluster, simply change this URL.

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
- [MCP Setup Guide](../MCP_SETUP.md) - AI assistant integration
- [Azure Data Explorer Docs](https://learn.microsoft.com/en-us/azure/data-explorer/)

### 🎯 Next Steps

After listing your databases, you can:
1. Query specific databases using KQL (Kusto Query Language)
2. Set up MCP server integration for AI-powered queries
3. Explore table schemas and data
4. Create custom queries and reports

See the main [README.md](README.md) for more advanced usage examples.
