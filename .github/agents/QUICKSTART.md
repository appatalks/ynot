# Quick Start: Azure Data Explorer Custom Agent

This guide helps you get started with the Azure Data Explorer custom agent in under 5 minutes.

## What You'll Get

A specialized AI assistant that can:
- 🔍 Discover all your Azure Data Explorer clusters
- 📊 Generate optimized KQL queries from natural language
- 🎓 Teach you KQL best practices
- ✅ Validate queries before execution
- 🔒 Default to read-only operations for safety

## Prerequisites

- GitHub Copilot subscription
- Azure account with access to Data Explorer clusters
- Azure CLI installed (comes pre-installed in Codespaces)

## Step 1: Authenticate with Azure

In your terminal (or GitHub Codespace terminal):

```bash
az login --use-device-code
```

Follow the prompts to sign in to Azure.

## Step 2: Open GitHub Copilot Chat

- **VS Code**: Press `Ctrl+Shift+I` (Windows/Linux) or `Cmd+Shift+I` (Mac)
- **Codespaces**: Same shortcuts, or click the Copilot icon in the sidebar

## Step 3: Use the Agent

Start your message with `@adx-query-agent`:

### Example 1: Discover Your Resources
```
@adx-query-agent Show me all my Azure Data Explorer clusters
```

The agent will list all ADX clusters you have access to.

### Example 2: Query Your Data
```
@adx-query-agent Query errors from the Logs table in the past hour
```

The agent will generate a KQL query like:
```kql
Logs
| where Timestamp > ago(1h)
| where Level == "Error"
| project Timestamp, Message, Source
| order by Timestamp desc
```

### Example 3: Learn KQL
```
@adx-query-agent How do I aggregate data by time bins in KQL?
```

The agent will explain and provide examples.

## Common Use Cases

### Data Exploration
```
@adx-query-agent What tables exist in database MyDatabase?
@adx-query-agent Show me the schema of the Events table
@adx-query-agent Sample 10 rows from the Metrics table
```

### Log Analysis
```
@adx-query-agent Find all errors in the last 24 hours
@adx-query-agent Show me the top 10 error messages
@adx-query-agent Count errors by source
```

### Performance Monitoring
```
@adx-query-agent What's the average response time by endpoint?
@adx-query-agent Show me slow requests over 1 second
@adx-query-agent Create a time series of request counts by hour
```

### Security Auditing
```
@adx-query-agent Find all failed login attempts
@adx-query-agent Show authentication events from suspicious IPs
@adx-query-agent List all admin operations in the past week
```

## Tips for Best Results

1. **Be specific**: Include table names, time ranges, and conditions
   - ✅ "Query errors from Logs in the past 2 hours"
   - ❌ "Show me some errors"

2. **Ask for explanations**: The agent loves to teach
   - "Explain what this query does: Logs | summarize count() by Level"

3. **Iterate**: Refine your queries based on results
   - "Now add a time range filter to that query"
   - "Sort by count descending"

4. **Request best practices**: Learn while you work
   - "What's the most efficient way to query this large table?"

## Troubleshooting

### "Authentication failed"
- Run `az login --use-device-code` again
- Check: `az account show` to verify you're logged in

### "No clusters found"
- Verify you have access to ADX clusters in your subscription
- Check: `az account show` to confirm the right subscription is active
- Try: `az account list` to see all available subscriptions

### "Agent not responding"
- Ensure you're using the exact agent name: `@adx-query-agent`
- Check that GitHub Copilot is active and licensed
- Try reloading VS Code/Codespaces window

### "Query failed"
- Verify the table/database name is correct
- Check you have read permissions on the database
- The agent will help debug query syntax errors

## Next Steps

- 📖 Read the [full documentation](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md)
- 🔧 Learn more about [Azure MCP servers](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md#what-is-mcp)
- 📚 Explore [KQL documentation](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/query/)

## Need Help?

Open an issue in this repository or check the [troubleshooting guide](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md#troubleshooting).

---

**Ready to query?** Start with: `@adx-query-agent Show me all my Azure Data Explorer clusters`
