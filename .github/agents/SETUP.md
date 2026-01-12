# Setup Guide: Azure Data Explorer Custom Agent

This guide walks you through setting up the `@adx-query-agent` custom agent for GitHub Copilot.

## What This Agent Does

The `@adx-query-agent` is a specialized AI assistant that:
- Discovers Azure Data Explorer (ADX) clusters automatically
- Generates optimized KQL (Kusto Query Language) queries
- Provides real-time data analysis and exploration
- Connects to your Azure resources via MCP (Model Context Protocol) servers

## Prerequisites

1. **GitHub Copilot** subscription (Individual, Business, or Enterprise)
2. **Azure Account** with access to Azure Data Explorer clusters
3. **Azure CLI** installed (pre-installed in GitHub Codespaces)
4. **Python 3.8+** with pip

## Step-by-Step Setup

### 1. Authenticate with Azure

In your terminal or GitHub Codespace:

```bash
az login --use-device-code
```

Follow the prompts to complete authentication. Verify your login:

```bash
az account show
```

If you have multiple subscriptions, select the correct one:

```bash
az account list --output table
az account set --subscription <subscription-id>
```

### 2. Install Python Dependencies

Navigate to the Azure MCP deployer directory and install requirements:

```bash
cd azure-mcp-data-explorer-deployer
pip install -r requirements.txt
```

This installs:
- `azure-kusto-data` - Azure Data Explorer client library
- `azure-identity` - Azure authentication library

### 3. Configure Environment Variables

Create a `.env` file in the `azure-mcp-data-explorer-deployer` directory:

```bash
cd azure-mcp-data-explorer-deployer
cp .env.template .env
```

Edit `.env` and set your cluster details:

```bash
# Required: Your Azure Data Explorer cluster URL
ADX_CLUSTER_URL=https://<yourcluster>.<region>.kusto.windows.net

# Optional: Default database (leave empty for discovery mode)
ADX_DATABASE=<your-database-name>

# Optional: Authentication cache paths (defaults are usually fine)
ADX_AUTH_RECORD_PATH=~/.azure/adx_auth_record.json
ADX_TOKEN_CACHE_PATH=~/.IdentityService/
```

**Don't know your cluster URL?** You can discover it:

```bash
./run.sh --discover-clusters
```

### 4. Test the Connection

Verify everything works:

```bash
cd azure-mcp-data-explorer-deployer

# List all databases in your cluster
./run.sh --databases

# List all tables in a specific database
./run.sh --tables

# Sample data from a table
./run.sh --sample "YourTableName" --limit 5
```

If you see your databases/tables, you're ready to go! 🎉

### 5. Use the Agent in GitHub Copilot

Open GitHub Copilot Chat and invoke the agent:

```
@adx-query-agent Show me all my Azure Data Explorer clusters
```

## Configuration Details

### MCP Server Configuration

The agent uses two MCP servers defined in the frontmatter:

1. **azure-data-explorer** - Local Python-based ADX query server
   - Runs: `python azure-mcp-data-explorer-deployer/adx_query.py --mcp-mode`
   - Provides: Query execution, database/table listing, schema exploration

2. **azure** - Azure resource management server
   - Runs: `npx -y @azure/mcp@latest`
   - Provides: Azure subscription resources, cluster discovery

### Environment Variable Resolution

The agent configuration supports placeholders:
- `{{workspace}}` - Resolves to your workspace root directory
- `{{env.VAR_NAME}}` - Resolves to environment variable values

Make sure your `.env` file or shell environment has these set:
- `ADX_CLUSTER_URL`
- `ADX_DATABASE` (optional)

## Troubleshooting

### Issue: "Authentication failed"

**Solution:**
```bash
# Re-authenticate with Azure
az login --use-device-code

# Verify authentication
az account show

# Clear cached auth if needed
rm -f ~/.azure/adx_auth_record.json
rm -rf ~/.IdentityService/
```

### Issue: "No clusters found"

**Solutions:**
1. Verify your Azure subscription has ADX clusters:
   ```bash
   az kusto cluster list --output table
   ```

2. Check you're using the correct subscription:
   ```bash
   az account list --output table
   az account set --subscription <subscription-id>
   ```

3. Verify RBAC permissions (need at least Reader role on ADX resources)

### Issue: "Module not found" or "Import error"

**Solution:**
```bash
cd azure-mcp-data-explorer-deployer
pip install --upgrade -r requirements.txt
```

### Issue: "Agent not responding"

**Solutions:**
1. Verify the agent name is exact: `@adx-query-agent` (with hyphen, not space)
2. Check GitHub Copilot is active: Look for Copilot icon in status bar
3. Reload VS Code window: `Ctrl+Shift+P` → "Developer: Reload Window"
4. Check agent file is in correct location: `.github/agents/adx-query-agent.md`

### Issue: "Connection timeout" or "Cluster unreachable"

**Solutions:**
1. Verify cluster URL is correct in `.env`:
   ```bash
   echo $ADX_CLUSTER_URL
   ```

2. Test connectivity:
   ```bash
   curl -I $ADX_CLUSTER_URL
   ```

3. Check firewall rules if on corporate network

### Issue: "Permission denied" errors

**Solutions:**
1. Verify you have appropriate RBAC roles on the ADX cluster/database:
   - Database Viewer (read-only)
   - Database User (read + limited write)
   - Database Admin (full access)

2. Check database-level permissions:
   ```kql
   .show database <DatabaseName> principals
   ```

## Advanced Configuration

### Custom MCP Server Path

If you move the `azure-mcp-data-explorer-deployer` folder, update the agent configuration in `adx-query-agent.md`:

```yaml
mcp-servers:
  azure-data-explorer:
    command: python
    args: 
      - "{{workspace}}/path/to/your/folder/adx_query.py"
      - "--mcp-mode"
```

### Using Service Principal Authentication

For automated/production scenarios, set environment variables:

```bash
export AZURE_CLIENT_ID=<app-id>
export AZURE_CLIENT_SECRET=<secret>
export AZURE_TENANT_ID=<tenant-id>
```

The authentication library will automatically use these credentials.

### Read-Only Mode (Recommended)

By default, the agent blocks management commands (those starting with `.`) and write operations. To allow admin commands (use with caution):

```bash
./run.sh --allow-admin --kql ".show databases"
```

## Verification Checklist

Before opening an issue, verify:

- [ ] Azure CLI authentication works: `az account show`
- [ ] Python dependencies installed: `pip list | grep azure-kusto`
- [ ] Environment variables set: `echo $ADX_CLUSTER_URL`
- [ ] Test script works: `cd azure-mcp-data-explorer-deployer && ./run.sh --databases`
- [ ] Agent file exists: `.github/agents/adx-query-agent.md`
- [ ] GitHub Copilot is active and licensed
- [ ] Using correct agent name: `@adx-query-agent`

## Getting Help

- **Documentation**: See [MCP_SETUP.md](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md)
- **KQL Reference**: [Azure Data Explorer Query Language](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- **Azure MCP**: [Azure MCP GitHub](https://github.com/Azure/azure-mcp)

## Next Steps

Once setup is complete:

1. Try the [Quick Start Guide](QUICKSTART.md)
2. Learn [KQL Best Practices](../../azure-mcp-data-explorer-deployer/copilot-instructions.md)
3. Explore the [full MCP documentation](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md)

---

**Ready?** Test it now: `@adx-query-agent Show me all my Azure Data Explorer clusters`
