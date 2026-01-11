# ynot
Wh(y)not | completely unsupported, yet adventurous playground. By AppaTalks

> [!NOTE]
> #### Repository is independently maintained and is not [supported](https://docs.github.com/en/enterprise-server@3.13/admin/monitoring-managing-and-updating-your-instance/monitoring-your-instance/setting-up-external-monitoring) by GitHub.

## 🤖 AI Assistant Integration with Azure

This repository supports **Azure MCP (Model Context Protocol) Servers** with **automatic resource discovery** for seamless AI-powered Azure integration.

**[→ View Complete Setup Guide](./MCP_SETUP.md)**

### 🚀 Quick Start: GitHub Copilot Integration

The easiest way to get started is with GitHub Copilot Coding Agent:

```bash
# Install Azure Developer CLI
winget install Microsoft.Azd  # or brew install azure/azd/azd

# Install coding agent extension
azd extension install azure.coding-agent

# Sign in to Azure
az login

# Configure GitHub Copilot with automatic Azure access
azd coding-agent config
```

This automatically configures GitHub Copilot to access your Azure resources with secure, passwordless authentication!

### ✨ Automatic Azure Data Explorer Discovery

Just sign in to Azure, and AI assistants can automatically:
- 🔍 **Discover** all your Azure Data Explorer (ADX) clusters
- 📊 **List** databases in any cluster
- 🗃️ **Explore** table schemas and metadata
- 🔎 **Query** data using natural language → KQL
- 📈 **Analyze** logs, metrics, and telemetry

**Example prompts:**
- "Show me all my Azure Data Explorer clusters"
- "List databases in cluster [name]"
- "Query error logs from the past hour in my ADX cluster"

### 🔧 Supported Azure Services

- **Azure Data Explorer (ADX)** - Automatic cluster/database discovery and KQL queries
- **Azure Resources** - General Azure resource management
- **Azure DevOps** - Work items, repos, pull requests, and pipelines

### 🎯 Usage

Once configured, use natural language in GitHub Copilot, Claude Desktop, or VS Code:

```
"Show all Azure Data Explorer clusters in my subscription"
"List databases in my ADX cluster"
"Query the Logs table for errors in the last 24 hours"
"Create an Azure DevOps work item for the bug I just found"
```

### 📚 Full Documentation

See [MCP_SETUP.md](./MCP_SETUP.md) for:
- Detailed GitHub Copilot integration steps
- Claude Desktop configuration
- VS Code setup
- Authentication methods (Azure CLI, Managed Identity, Service Principal)
- Security best practices
- Troubleshooting guide
