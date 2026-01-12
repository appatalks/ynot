# ynot
Wh(y)not | completely unsupported, yet adventurous playground. By AppaTalks

> [!NOTE]
> #### Repository is independently maintained and is not [supported](https://docs.github.com/en/enterprise-server@3.13/admin/monitoring-managing-and-updating-your-instance/monitoring-your-instance/setting-up-external-monitoring) by GitHub.

## 🤖 AI Assistant Integration with Azure

This repository supports **Azure MCP (Model Context Protocol) Servers** with **automatic resource discovery** for seamless AI-powered Azure integration.

**[→ View Complete Setup Guide](./azure-mcp-data-explorer-deployer/MCP_SETUP.md)**

### 🚀 Quick Start Options

**Option 1: GitHub Codespaces (Recommended for Collaborators)**

Use your personal Azure account in a Codespace - no setup required:

1. Create a Codespace from this repository
2. Run `az login --use-device-code` in the terminal
3. Start using Copilot Chat with Azure MCP tools!

**[→ View Codespaces Setup Guide](./azure-mcp-data-explorer-deployer/MCP_SETUP.md#option-1-github-codespaces-with-per-user-azure-identity-)**

**Option 2: GitHub Copilot on GitHub.com (Shared Identity)**

Configure a shared managed identity for the entire repository:

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

**[→ View Complete Setup Guide](./azure-mcp-data-explorer-deployer/MCP_SETUP.md)**

### 🤖 Custom Agent for Azure Data Explorer

This repository includes a **specialized GitHub Copilot agent** for Azure Data Explorer queries:

- **Expert in KQL**: Specialized knowledge of Kusto Query Language syntax and patterns
- **Query generation**: Convert natural language to optimized KQL queries
- **Security-first**: Read-only operations by default with safety guardrails
- **Educational**: Provides explanations and best practices with every query
- **Auto-discovery**: Automatically connects to your ADX clusters via Azure MCP

**Use the agent:**
```
@adx-query-agent Show me errors from the Logs table in the past hour
@adx-query-agent What's the schema of the Events table?
@adx-query-agent Count records by severity level
```

**[→ Learn more about the ADX Query Agent](./azure-mcp-data-explorer-deployer/MCP_SETUP.md#-custom-agent-azure-data-explorer-query-assistant)**

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

See [MCP_SETUP.md](./azure-mcp-data-explorer-deployer/MCP_SETUP.md) for:
- Detailed GitHub Copilot integration steps
- Claude Desktop configuration
- VS Code setup
- Authentication methods (Azure CLI, Managed Identity, Service Principal)
- Security best practices
- Troubleshooting guide
