# Testing the Azure Data Explorer Custom Agent

This guide helps you test and verify the `@adx-query-agent` custom agent setup.

## Pre-Flight Checklist

Before testing the agent, verify these requirements:

### 1. GitHub Copilot Access
- [ ] GitHub Copilot subscription is active
- [ ] You can see the Copilot icon in VS Code status bar
- [ ] Copilot Chat is accessible (`Ctrl+Shift+I` or `Cmd+Shift+I`)

### 2. Azure Setup
- [ ] Azure CLI is installed: `az --version`
- [ ] Authenticated with Azure: `az login --use-device-code`
- [ ] Can see your account: `az account show`
- [ ] Have access to ADX clusters: `az kusto cluster list`

### 3. Python Environment
- [ ] Python 3.8+ installed: `python --version` or `python3 --version`
- [ ] pip is available: `pip --version` or `pip3 --version`

### 4. Workspace Setup
- [ ] Agent file exists: `.github/agents/adx-query-agent.md`
- [ ] ADX scripts exist: `azure-mcp-data-explorer-deployer/adx_query.py`
- [ ] Dependencies installed:
  ```bash
  cd azure-mcp-data-explorer-deployer
  pip install -r requirements.txt
  ```

### 5. Configuration
- [ ] `.env` file created in `azure-mcp-data-explorer-deployer/`
- [ ] `ADX_CLUSTER_URL` is set in `.env`
- [ ] `ADX_DATABASE` is set (if you have a specific database)

## Testing Steps

### Level 1: Basic Agent Recognition

Test if GitHub Copilot recognizes the custom agent:

1. Open Copilot Chat in VS Code
2. Type `@` and see if `adx-query-agent` appears in the autocomplete
3. If it doesn't appear, try:
   - Reload VS Code window: `Ctrl+Shift+P` → "Developer: Reload Window"
   - Check the agent file is in the correct location: `.github/agents/adx-query-agent.md`
   - Verify the YAML frontmatter is valid (no syntax errors)

### Level 2: Agent Invocation

Test if the agent responds to queries:

1. In Copilot Chat, type:
   ```
   @adx-query-agent Hello, are you there?
   ```

2. Expected response: The agent should acknowledge and introduce itself as an Azure Data Explorer expert

3. If no response or error:
   - Check Copilot is active (green checkmark in status bar)
   - Try refreshing the agent cache: Reload VS Code
   - Check Output panel for errors: View → Output → Select "GitHub Copilot"

### Level 3: Script Execution

Test if the agent can execute the Python scripts:

1. **Test cluster discovery:**
   ```
   @adx-query-agent Can you discover my Azure Data Explorer clusters?
   ```
   
   Expected: Agent should execute `./run.sh --discover-clusters` and show results

2. **Test database listing:**
   ```
   @adx-query-agent List all databases in my cluster
   ```
   
   Expected: Agent should check your config and run `./run.sh --databases`

3. **Test table listing:**
   ```
   @adx-query-agent What tables are in my database?
   ```
   
   Expected: Agent should run `./run.sh --tables`

### Level 4: KQL Query Generation

Test the agent's KQL expertise:

1. **Simple query:**
   ```
   @adx-query-agent Generate a KQL query to get the last 10 rows from a table called Logs
   ```
   
   Expected: Agent should provide: `Logs | take 10`

2. **Time-filtered query:**
   ```
   @adx-query-agent Show me errors from the past hour in the Logs table
   ```
   
   Expected: Agent should generate:
   ```kql
   Logs
   | where Timestamp > ago(1h)
   | where Level == "Error"
   ```

3. **Aggregation query:**
   ```
   @adx-query-agent Count errors by source in the last 24 hours
   ```
   
   Expected: Agent should generate:
   ```kql
   Logs
   | where Timestamp > ago(24h)
   | where Level == "Error"
   | summarize count() by Source
   ```

### Level 5: Full Integration Test

Test end-to-end with your actual ADX cluster:

1. **Ensure you have a working cluster connection:**
   ```bash
   cd azure-mcp-data-explorer-deployer
   ./run.sh --databases
   ```
   
   If this works, proceed to step 2.

2. **Ask the agent to query real data:**
   ```
   @adx-query-agent Sample 5 rows from the [YourTableName] table
   ```
   
   Expected: Agent should execute the query and show results

3. **Test query execution:**
   ```
   @adx-query-agent Run this query: [YourTableName] | count
   ```
   
   Expected: Agent should execute and show the count

## Common Issues and Solutions

### Issue: Agent Not Found

**Symptoms:**
- `@adx-query-agent` doesn't appear in autocomplete
- Typing it manually shows "Agent not found"

**Solutions:**
1. Verify file location: `.github/agents/adx-query-agent.md`
2. Check YAML frontmatter syntax (lines 1-5 between `---` markers)
3. Ensure the `name:` field matches: `adx-query-agent` (with hyphen)
4. Reload VS Code window
5. Check repository is properly opened in VS Code (not just a folder)

### Issue: Agent Responds But Can't Execute Scripts

**Symptoms:**
- Agent acknowledges your message
- But shows errors when trying to run commands
- "Command not found" or "Script error" messages

**Solutions:**
1. Verify Python scripts exist: `ls azure-mcp-data-explorer-deployer/`
2. Check scripts are executable: `chmod +x azure-mcp-data-explorer-deployer/run.sh`
3. Install dependencies: 
   ```bash
   cd azure-mcp-data-explorer-deployer
   pip install -r requirements.txt
   ```
4. Test scripts manually first:
   ```bash
   cd azure-mcp-data-explorer-deployer
   ./run.sh --help
   ```

### Issue: Authentication Failures

**Symptoms:**
- "Not authenticated" errors
- "No credentials found" messages
- "Access denied" errors

**Solutions:**
1. Authenticate with Azure:
   ```bash
   az login --use-device-code
   ```
2. Verify authentication:
   ```bash
   az account show
   ```
3. Check subscription:
   ```bash
   az account list --output table
   az account set --subscription <subscription-id>
   ```
4. Clear cached auth and re-authenticate:
   ```bash
   rm -f ~/.azure/adx_auth_record.json
   rm -rf ~/.IdentityService/
   az login --use-device-code
   ```

### Issue: Can't Connect to Cluster

**Symptoms:**
- "Connection timeout"
- "Cluster not found"
- "Invalid cluster URL"

**Solutions:**
1. Verify cluster URL in `.env`:
   ```bash
   cat azure-mcp-data-explorer-deployer/.env | grep ADX_CLUSTER_URL
   ```
2. Test cluster accessibility:
   ```bash
   curl -I $ADX_CLUSTER_URL
   ```
3. Discover clusters to find correct URL:
   ```bash
   cd azure-mcp-data-explorer-deployer
   ./run.sh --discover-clusters
   ```
4. Update `.env` with correct URL
5. Verify network connectivity (VPN if required)

### Issue: Permission Denied on Database/Table

**Symptoms:**
- Can list databases but not query them
- "Insufficient permissions" errors
- "Access denied to table"

**Solutions:**
1. Verify you have appropriate role assignment:
   - Minimum: Database Viewer (read-only)
   - Standard: Database User (read + limited write)
2. Check with cluster admin if unsure
3. Test with a different database/table you know you have access to

## Manual Testing Commands

If the agent isn't working, test the underlying scripts manually:

```bash
# Navigate to the ADX deployer directory
cd azure-mcp-data-explorer-deployer

# Discover clusters (requires az login)
./run.sh --discover-clusters

# List databases (requires ADX_CLUSTER_URL in .env)
./run.sh --databases

# List tables (requires ADX_CLUSTER_URL and ADX_DATABASE in .env)
./run.sh --tables

# Sample data (replace TableName with an actual table)
./run.sh --sample "TableName" --limit 5

# Run a KQL query
./run.sh --kql "TableName | take 10"

# Run admin/management query (use with caution)
./run.sh --allow-admin --kql ".show databases"
```

If these commands work but the agent doesn't, the issue is likely with:
- Agent configuration in the `.md` file
- GitHub Copilot not recognizing the agent
- Tool execution permissions in Copilot

## Validation Checklist

Use this checklist to confirm everything works:

- [ ] Agent appears in `@` autocomplete menu in Copilot Chat
- [ ] Agent responds to basic queries like "Hello"
- [ ] Agent understands Azure Data Explorer terminology
- [ ] Agent can generate valid KQL queries
- [ ] Agent can execute Python scripts via terminal commands
- [ ] Manual script execution works: `./run.sh --databases`
- [ ] Agent can discover clusters
- [ ] Agent can list databases
- [ ] Agent can list tables
- [ ] Agent can sample data from a table
- [ ] Agent can execute custom KQL queries
- [ ] Agent explains queries educationally
- [ ] Agent defaults to read-only operations
- [ ] Agent warns about admin/write operations

## Success Criteria

Your agent setup is successful when you can:

1. **Invoke the agent**: `@adx-query-agent` in Copilot Chat
2. **Get cluster info**: Agent can list your ADX clusters
3. **Query data**: Agent can execute queries and show results
4. **Learn KQL**: Agent explains queries and provides examples
5. **Stay safe**: Agent blocks admin operations without explicit permission

## Next Steps After Successful Testing

Once everything works:

1. ✅ Mark this setup as complete
2. 📚 Learn more KQL: See [Azure Data Explorer Documentation](https://docs.microsoft.com/en-us/azure/data-explorer/)
3. 🎯 Try the [QUICKSTART examples](QUICKSTART.md)
4. 🔧 Customize the agent: Edit `adx-query-agent.md` to add your own patterns
5. 📖 Share with team: Document your specific cluster/database setup

## Getting Help

If you're still stuck after trying these steps:

1. Check the [SETUP.md](SETUP.md) guide for detailed configuration
2. Review [MCP_SETUP.md](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md) for Azure MCP details
3. Check GitHub Copilot status: [GitHub Status](https://www.githubstatus.com/)
4. Open an issue in this repository with:
   - Agent response (or error message)
   - Output from `./run.sh --databases` (if it fails)
   - VS Code version and Copilot extension version
   - Operating system and Python version

---

**Testing completed?** Start using the agent: `@adx-query-agent Show me all my Azure Data Explorer clusters`
