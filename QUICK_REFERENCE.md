# Azure MCP Quick Reference

Quick reference card for Azure MCP Server integration with automatic discovery.

## 🚀 Quick Start (GitHub Copilot)

```bash
# 1. Install Azure Developer CLI
winget install Microsoft.Azd    # Windows
# or
brew install azure/azd/azd      # macOS

# 2. Install extension
azd extension install azure.coding-agent

# 3. Sign in to Azure
az login

# 4. Configure GitHub Copilot (one command!)
azd coding-agent config
```

**That's it!** Your GitHub Copilot can now automatically discover and query your Azure Data Explorer clusters.

---

## 📋 Common Commands

### Azure CLI Authentication
```bash
# Sign in to Azure
az login

# Check current subscription
az account show

# List all subscriptions
az account list --output table

# Switch subscription
az account set --subscription <subscription-id>
```

### Verify MCP Setup
```bash
# Check Node.js version (need v18+)
node --version

# Test npx access
npx --version

# Verify Azure CLI is authenticated
az account show --query "name" -o tsv
```

---

## 💬 Example Prompts for GitHub Copilot / Claude

### Discovery
```
"Show me all Azure Data Explorer clusters in my subscription"
"List databases in my ADX cluster"
"What clusters do I have in East US region?"
"Show me the largest cluster by data size"
```

### Schema Exploration
```
"What tables are in database LogsDB?"
"Show me the schema of table ErrorLogs"
"Describe the columns in table Metrics"
"List all tables sorted by record count"
```

### Data Queries
```
"Query the last 100 records from ErrorLogs table"
"Show me errors from the past hour"
"Get distinct users from Events table today"
"Count records by hour for the last 24 hours"
"Find anomalies in the Telemetry table"
```

### Analysis
```
"Analyze error patterns in my cluster"
"Show performance metrics from last week"
"What's the trend in error rates?"
"Compare today's metrics to yesterday"
```

### Azure DevOps
```
"List all work items assigned to me"
"Show recent pull requests"
"Create a bug work item for authentication issue"
"Search for TODO comments in the codebase"
```

---

## 🔐 Authentication Methods

| Method | Use Case | Setup Time | Security |
|--------|----------|------------|----------|
| **Azure CLI** | Development | 1 min | ⭐⭐⭐⭐ |
| **Managed Identity** | Production | 20 min | ⭐⭐⭐⭐⭐ |
| **Service Principal** | Automation | 10 min | ⭐⭐⭐ |

### Quick Setup: Azure CLI (Recommended for Dev)
```bash
az login
# Done! MCP servers will use your credentials
```

### Quick Setup: Managed Identity (Production)
```bash
# Run the automated setup
azd coding-agent config
# Follow prompts - it creates everything!
```

---

## 📁 File Locations

### GitHub Copilot
- **Config**: `.github/mcp.json` (in repository)
- **Secrets**: Repository Settings → Secrets → Codespaces
- **Prefix**: `COPILOT_MCP_*`

### Claude Desktop
- **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
- **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Linux**: `~/.config/Claude/claude_desktop_config.json`

### VS Code
- **Config**: `.github/mcp.json` or workspace settings
- **Extension**: GitHub Copilot (marketplace)

---

## 🔧 Environment Variables

### Required for Azure Data Explorer
```bash
AZURE_TENANT_ID=<your-tenant-id>
AZURE_CLIENT_ID=<your-client-id>         # Optional if using Azure CLI
AZURE_SUBSCRIPTION_ID=<your-subscription-id>
```

### Required for Azure DevOps
```bash
ADO_PERSONAL_ACCESS_TOKEN=<your-pat-token>
ADO_ORG=<your-org-name>
```

### Get Your Azure IDs
```bash
# Tenant ID
az account show --query tenantId -o tsv

# Subscription ID
az account show --query id -o tsv

# All subscriptions
az account list --query "[].{Name:name, ID:id}" -o table
```

---

## 🐛 Troubleshooting

### Problem: "No clusters found"
```bash
# Solution: Check subscription and permissions
az account show
az kusto cluster list --subscription <subscription-id>
```

### Problem: "Authentication failed"
```bash
# Solution: Re-authenticate
az login
az account set --subscription <subscription-id>
```

### Problem: "MCP server not loading"
```bash
# Solution: Check Node.js and restart
node --version    # Should be v18+
# Restart VS Code / Claude Desktop
```

### Problem: "Permission denied"
```bash
# Solution: Check RBAC roles
az role assignment list --assignee <your-user-id>
# Need at least "Reader" role
```

---

## 📊 MCP Server Capabilities

### Azure MCP Server (`@azure/mcp`)
- ✅ List all resources in subscription
- ✅ Query resource properties
- ✅ Get resource metrics
- ✅ Automatic resource discovery
- ✅ Multi-subscription support

### Azure Data Explorer MCP (`adx-mcp-server`)
- ✅ List clusters in subscription
- ✅ List databases in cluster
- ✅ List tables in database
- ✅ Get table schema
- ✅ Execute KQL queries
- ✅ Sample data preview
- ✅ Automatic discovery

### Azure DevOps MCP (`@azure-devops/mcp`)
- ✅ List work items
- ✅ Query pull requests
- ✅ Search code
- ✅ View repositories
- ✅ Access pipelines
- ✅ Create/update items

---

## 🎯 Permissions Required

### For Azure Data Explorer
```
Subscription Level:
• Reader

Cluster Level:
• Azure Kusto Database User (or higher)

Database Level:
• User, Viewer, or Admin based on needs
```

### For Azure DevOps
```
• Code: Read
• Work Items: Read & Write
• Build: Read
• Project and Team: Read
```

### Grant Permissions
```bash
# Azure Reader role
az role assignment create \
  --assignee <user-or-identity-id> \
  --role Reader \
  --scope /subscriptions/<subscription-id>

# ADX Database User
az kusto database-principal-assignment create \
  --cluster-name <cluster> \
  --database-name <database> \
  --principal-id <id> \
  --principal-type User \
  --role User \
  --resource-group <rg>
```

---

## 📚 Documentation Links

- **MCP Setup**: [MCP_SETUP.md](./MCP_SETUP.md)
- **GitHub Copilot**: [GITHUB_COPILOT_SETUP.md](./GITHUB_COPILOT_SETUP.md)
- **Architecture**: [ARCHITECTURE.md](./ARCHITECTURE.md)

### External Resources
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Azure MCP Server Docs](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/)
- [Azure Data Explorer Docs](https://learn.microsoft.com/en-us/azure/data-explorer/)
- [GitHub Copilot Docs](https://docs.github.com/en/copilot)

---

## 💡 Tips & Tricks

### Tip 1: Be Specific
Instead of: "Show me data"
Try: "Show me error logs from cluster1 in the last hour"

### Tip 2: Chain Commands
"List my ADX clusters, then show databases in the first cluster, then query the ErrorLogs table for today"

### Tip 3: Save Common Queries
Create shortcuts in your AI assistant for frequently used queries.

### Tip 4: Use Filters
Always specify time ranges and filters to reduce query time and cost.

### Tip 5: Check Cache
Some MCP servers cache results - use this for frequently accessed schemas.

---

## ⚡ Performance Optimization

1. **Use specific cluster/database names** - Avoid wildcards
2. **Limit time ranges** - Query last hour, not all time
3. **Apply filters early** - In KQL, not post-processing
4. **Cache schemas** - Store frequently used table structures
5. **Parallel queries** - Independent queries run concurrently

---

## 🔒 Security Checklist

- [ ] Use Azure CLI auth for development
- [ ] Use Managed Identity for production
- [ ] Never commit credentials to Git
- [ ] Use `.env` files (gitignored)
- [ ] Apply least privilege (minimal RBAC)
- [ ] Rotate tokens/credentials regularly
- [ ] Enable Azure AD audit logging
- [ ] Use separate identities per environment
- [ ] Review access permissions quarterly
- [ ] Use GitHub Environments for secrets

---

## 📞 Getting Help

### Documentation Issues
Open issue in this repository

### Azure Support
Azure Portal → Support → New support request

### GitHub Copilot Support
support@github.com

### Community
- [GitHub Discussions](https://github.com/orgs/community/discussions)
- [Azure Developer Community](https://techcommunity.microsoft.com/azure)
- [Stack Overflow](https://stackoverflow.com/questions/tagged/azure-data-explorer)

---

**Version**: 1.0  
**Last Updated**: 2026-01-11  
**Maintained By**: AppaTalks