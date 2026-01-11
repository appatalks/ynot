# Azure MCP Server Integration

This repository supports **Azure MCP (Model Context Protocol) Servers**, allowing AI assistants like GitHub Copilot, Claude Desktop, and VS Code to interact with Azure resources including:
- **Azure Data Explorer (ADX)** - Automatic cluster and database discovery
- **Azure DevOps** - Work items, pull requests, and repositories
- **Azure Resources** - General Azure resource management

## What is MCP?

The Model Context Protocol (MCP) is an open standard for connecting AI systems with external resources and APIs. It allows AI assistants to securely access data sources, execute functions, and automate workflows through standardized API calls.

## Supported Azure MCP Servers

### 1. Azure Data Explorer (ADX) - **Automatic Discovery** ✨

The Azure Data Explorer MCP server enables AI assistants to:
- **Automatically discover** all ADX clusters in your subscription
- **List all databases** in any cluster
- Explore table schemas and column metadata
- Run KQL (Kusto Query Language) queries
- Sample and preview data
- Get cluster and database statistics

**Key Feature**: Just sign in to Azure, and the MCP server will automatically enumerate your available clusters and databases!

### 2. Azure MCP Server (General)

The general Azure MCP server provides:
- Access to Azure resource management APIs
- Query and manage Azure resources across services
- Integrated authentication via Azure CLI or Managed Identity

### 3. Azure DevOps

The Azure DevOps MCP server enables:
- Query work items, pull requests, and repositories
- Create and update work items
- Search code and view repository contents
- Access build and release pipelines

## Setup Instructions

This repository supports **two authentication models** for accessing Azure resources:

### 🌐 Per-User Identity (Codespaces)
- **Who:** Individual collaborators working in GitHub Codespaces
- **Authentication:** Azure CLI (`az login --use-device-code`)
- **Identity:** Each user's personal Azure account
- **Setup:** Zero configuration - works out-of-the-box
- **Best for:** Development, exploration, personal Azure subscriptions

### 🔐 Shared Identity (GitHub.com)
- **Who:** Repository-wide access via GitHub Copilot on GitHub.com
- **Authentication:** Managed Identity with federated credentials
- **Identity:** Single shared identity configured via `azd coding-agent config`
- **Setup:** One-time setup by repository admin
- **Best for:** Production, team-wide access, consistent permissions

**Choose the model that fits your workflow!** Most collaborators will use **Per-User Identity in Codespaces** for simplicity.

### Prerequisites

- **Node.js** (v18 or later) and npm/npx
- **Azure CLI** - Install from [Azure CLI Installation](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
- **Azure Account** with access to:
  - Data Explorer clusters (for ADX)
  - DevOps organization (for Azure DevOps)
- **GitHub Copilot** or **Claude Desktop** or another MCP-compatible AI assistant

---

## Option 1: GitHub Codespaces with Per-User Azure Identity 🌐

**Best for:** Collaborators who want to use their own Azure account in a Codespace without setting up shared credentials.

This option allows **any collaborator** to use GitHub Codespaces with their personal Azure identity via Azure CLI authentication. No repository-level secrets required!

### Setup Steps

1. **Create a Codespace**:
   - Open this repository on GitHub.com
   - Click **Code** → **Codespaces** → **Create codespace on main**
   - Wait for the Codespace to build (includes Node.js 18+ and Azure CLI pre-installed)

2. **Authenticate with Azure**:
   ```bash
   az login --use-device-code
   ```
   
   Follow the device code flow:
   - Copy the code shown in the terminal
   - Open https://microsoft.com/devicelogin in your browser
   - Paste the code and sign in with your Azure account

3. **(Optional) Select your subscription** if you have multiple:
   ```bash
   # List available subscriptions
   az account list --output table
   
   # Set the default subscription
   az account set --subscription <subscription-id>
   ```

4. **Verify authentication**:
   ```bash
   az account show
   ```

5. **Start using GitHub Copilot Chat**:
   - Open Copilot Chat in VS Code (Ctrl+Shift+I or Cmd+Shift+I)
   - The MCP servers will automatically use your Azure CLI credentials
   - Try: "Show me all my Azure Data Explorer clusters"

### How It Works

- The `.github/mcp.json` configuration is automatically loaded in Codespaces
- Azure and ADX MCP servers use **Azure CLI authentication** by default (no env vars needed!)
- The MCP servers discover whatever Azure resources **your account** has access to
- Each collaborator uses their own Azure identity (no shared credentials)

### Key Benefits

✅ **No shared secrets** - Each user brings their own Azure identity  
✅ **Zero configuration** - Works out-of-the-box in Codespaces  
✅ **Secure by default** - Uses Azure CLI authentication (user-delegated)  
✅ **Easy collaboration** - Any team member can spin up a Codespace and start working

---

## Option 2: GitHub Copilot Integration with Shared Identity (GitHub.com) 🚀

**Best for:** Using GitHub Copilot Coding Agent on GitHub.com with a shared managed identity for the entire repository.

The easiest way to integrate with GitHub Copilot on GitHub.com is using the Azure Developer CLI:

### Quick Setup with Azure Developer CLI

The easiest way to integrate with GitHub Copilot is using the Azure Developer CLI:

1. **Install Azure Developer CLI**:
   ```bash
   # Windows
   winget install Microsoft.Azd
   
   # macOS
   brew install azure/azd/azd
   
   # Linux
   curl -fsSL https://aka.ms/install-azd.sh | bash
   ```

2. **Install the Azure Coding Agent Extension**:
   ```bash
   azd extension install azure.coding-agent
   ```

3. **Authenticate with Azure**:
   ```bash
   az login
   ```

4. **Configure GitHub Copilot Coding Agent**:
   ```bash
   azd coding-agent config
   ```
   
   This command will:
   - Prompt you to select your Azure subscription
   - Create a User Managed Identity (UMI) for secure authentication
   - Set up federated credentials (no secrets needed!)
   - Configure GitHub repository environment variables
   - Generate MCP configuration for Copilot

5. **Enable in GitHub Repository**:
   - Go to your repository on GitHub.com
   - Navigate to **Settings** > **Code & automation** > **Copilot**
   - Click on **Coding agent** settings
   - Paste the MCP configuration provided by `azd coding-agent config`
   - The configuration will look like:
   ```json
   {
     "mcpServers": {
       "azure": {
         "command": "npx",
         "args": ["-y", "@azure/mcp@latest", "server", "start"],
         "tools": ["*"]
       }
     }
   }
   ```

6. **Set Repository Secrets** (if needed):
   - Go to **Settings** > **Secrets and variables** > **Codespaces** or **Actions**
   - Add secrets with `COPILOT_MCP_` prefix:
     - `COPILOT_MCP_AZURE_TENANT_ID`
     - `COPILOT_MCP_AZURE_CLIENT_ID`
     - `COPILOT_MCP_AZURE_SUBSCRIPTION_ID`

### Using GitHub Copilot with Azure Data Explorer

Once configured, you can use natural language in GitHub Copilot:

**Examples:**
- "Show me all Azure Data Explorer clusters in my subscription"
- "List databases in cluster [cluster-name]"
- "What tables are in database [database-name]?"
- "Run a KQL query to get the last 100 records from [table-name]"
- "Show schema for table [table-name] in ADX"
- "Query my ADX cluster for error logs in the past hour"

**The MCP server automatically discovers your resources - no manual configuration needed!**

---

## Option 3: Claude Desktop Setup

### 1. Authenticate with Azure CLI

First, authenticate with Azure to enable automatic resource discovery:

```bash
az login
```

Verify your subscription:
```bash
az account show
```

### 2. Configure Claude Desktop

1. **Locate your Claude Desktop configuration file:**
   - **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
   - **macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
   - **Linux**: `~/.config/Claude/claude_desktop_config.json`

2. **Add Azure MCP Server configurations:**

**Option A: Azure CLI Authentication (Recommended for Development)**

If you've run `az login`, you can use Azure CLI authentication without any environment variables:

```json
{
  "mcpServers": {
    "azure-data-explorer": {
      "command": "npx",
      "args": ["-y", "adx-mcp-server"]
    },
    "azure": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"]
    },
    "azure-devops": {
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp"],
      "env": {
        "ADO_PERSONAL_ACCESS_TOKEN": "your-azure-devops-pat-token",
        "ADO_ORG": "your-azure-devops-org-name"
      }
    }
  }
}
```

**Option B: Explicit Credentials (For Service Principal or Managed Identity)**

If you need to use specific credentials:

```json
{
  "mcpServers": {
    "azure-data-explorer": {
      "command": "npx",
      "args": ["-y", "adx-mcp-server"],
      "env": {
        "AZURE_TENANT_ID": "your-tenant-id",
        "AZURE_CLIENT_ID": "your-client-id",
        "AZURE_SUBSCRIPTION_ID": "your-subscription-id"
      }
    },
    "azure": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "env": {
        "AZURE_TENANT_ID": "your-tenant-id",
        "AZURE_CLIENT_ID": "your-client-id",
        "AZURE_SUBSCRIPTION_ID": "your-subscription-id"
      }
    },
    "azure-devops": {
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp"],
      "env": {
        "ADO_PERSONAL_ACCESS_TOKEN": "your-azure-devops-pat-token",
        "ADO_ORG": "your-azure-devops-org-name"
      }
    }
  }
}
```

3. **Restart Claude Desktop** to load the configuration.

---

## Option 4: VS Code with GitHub Copilot (Local Development)

The repository includes a `.github/mcp.json` configuration file that VS Code and GitHub Copilot can use automatically.

1. **Authenticate with Azure CLI**:
   ```bash
   az login
   ```

2. **Set environment variables** (optional - uses Azure CLI auth by default):
   ```bash
   export AZURE_TENANT_ID="your-tenant-id"
   export AZURE_CLIENT_ID="your-client-id"
   export AZURE_SUBSCRIPTION_ID="your-subscription-id"
   ```

3. **Open VS Code** with GitHub Copilot enabled - the MCP configuration will be detected automatically.

4. **Use Copilot Chat** with Azure-aware context:
   - Open Copilot Chat (Ctrl+Shift+I or Cmd+Shift+I)
   - Ask questions about your Azure resources
   - The AI will have access to your ADX clusters and databases

---

## Authentication Methods

### Azure CLI (Recommended for Development)

The simplest method - just run:
```bash
az login
```

The MCP servers will automatically use your Azure CLI credentials to access resources and discover clusters/databases.

### Managed Identity (For Production/CI/CD)

When running in Azure (App Service, Container Apps, VMs), use Managed Identity:
- No credentials needed in code
- Automatic authentication
- Set `AZURE_CLIENT_ID` to the Managed Identity's client ID

### Service Principal (For Automation)

Create a service principal for programmatic access:
```bash
az ad sp create-for-rbac --name "mcp-server-sp" --role reader
```

Use the output values:
- `AZURE_TENANT_ID`: Tenant ID
- `AZURE_CLIENT_ID`: App ID
- `AZURE_CLIENT_SECRET`: Password (store securely!)
- `AZURE_SUBSCRIPTION_ID`: Your subscription ID

---

## Getting Azure Credentials

### Find Your Tenant ID
```bash
az account show --query tenantId -o tsv
```

### Find Your Subscription ID
```bash
az account show --query id -o tsv
```

### Find Your Client ID (for Managed Identity)
```bash
# List managed identities
az identity list --query "[].{Name:name, ClientId:clientId}"
```

---

## Usage Examples

### Azure Data Explorer Queries

Once configured, use natural language with your AI assistant:

**Discovery:**
- "Show all my Azure Data Explorer clusters"
- "List databases in my ADX cluster"
- "What tables exist in database XYZ?"

**Data Exploration:**
- "Show me the schema of table Logs"
- "Get sample data from table Events"
- "How many records are in table Metrics?"

**KQL Queries:**
- "Query the last 100 error logs from my cluster"
- "Show distinct users from the Events table"
- "Get performance metrics for the past 24 hours"

### Azure DevOps Queries

- "List all work items in Azure DevOps"
- "Show recent pull requests in the main repository"
- "Create a bug work item for authentication issue"
- "Search for authentication code in Azure repos"

### General Azure Resources

- "List all my Azure resources"
- "Show me the status of my App Services"
- "What storage accounts do I have?"

---

## Security Considerations

### Best Practices

1. **Use Azure CLI for Development**: Simplest and most secure for local development
2. **Use Managed Identity for Production**: No secrets, automatic rotation
3. **Never commit credentials**: Use `.env` files (gitignored) or secret managers
4. **Principle of Least Privilege**: Grant only required permissions
5. **Rotate credentials regularly**: Especially Personal Access Tokens
6. **Use separate identities**: Different credentials for dev/staging/production

### Required Azure Permissions

For Azure Data Explorer automatic discovery:
- **Reader** role on subscription or resource group
- **Azure Kusto Database User** or higher on specific databases for querying

For Azure DevOps:
- **Code**: Read
- **Work Items**: Read & Write
- **Build**: Read
- **Project and Team**: Read

### GitHub Repository Secrets

When using GitHub Copilot Coding Agent:
- Store secrets with `COPILOT_MCP_` prefix
- Use GitHub Environments for different deployment stages
- Enable secret scanning for the repository

---

## Troubleshooting

### MCP Server not loading
- Verify Node.js version: `node --version` (should be v18+)
- Check Azure CLI authentication: `az account show`
- Ensure environment variables are set correctly
- Restart your AI assistant application

### Authentication errors
```bash
# Re-authenticate with Azure
az login

# Verify subscription access
az account list

# Check current subscription
az account show
```

### No clusters/databases visible
- Verify you have Reader permission on the subscription/resource group
- Ensure clusters exist in the subscription
- Check that `AZURE_SUBSCRIPTION_ID` matches your active subscription

### GitHub Copilot not detecting MCP
- Verify `.github/mcp.json` exists in repository
- Check repository secrets are prefixed with `COPILOT_MCP_`
- Ensure GitHub Copilot subscription is active
- Try reloading VS Code window

### ADX Query Errors
- Verify database permissions: Need at least "User" role
- Check KQL syntax
- Ensure cluster URI is correct
- Validate network connectivity to cluster

---

## Advanced Configuration

### Custom MCP Server Deployment

Deploy your own MCP server to Azure:

1. **Azure Functions**: Serverless MCP endpoints
2. **Azure Container Apps**: Containerized MCP servers
3. **Azure App Service**: Full web app with MCP integration

See [Azure MCP Server Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/) for deployment guides.

### Multi-Subscription Support

To access resources across multiple subscriptions:
```json
{
  "mcpServers": {
    "azure-prod": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "prod-subscription-id"
      }
    },
    "azure-dev": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "dev-subscription-id"
      }
    }
  }
}
```

---

## Additional Resources

### Official Documentation
- [Azure Data Explorer MCP Server](https://learn.microsoft.com/en-us/azure/data-explorer/integrate-mcp-servers)
- [Azure MCP Server (General)](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/)
- [GitHub Copilot MCP Integration](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/extend-coding-agent-with-mcp)
- [Model Context Protocol Specification](https://modelcontextprotocol.io/)

### Community Resources
- [Azure MCP Server GitHub](https://github.com/microsoft/mcp)
- [ADX MCP Server](https://github.com/pab1it0/adx-mcp-server)
- [Claude Desktop MCP Guide](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop)

### Video Tutorials
- [Azure Developer CLI + GitHub Copilot Setup](https://devblogs.microsoft.com/azure-sdk/azure-developer-cli-copilot-coding-agent-config/)
- [Azure Data Explorer MCP Demo](https://learn.microsoft.com/en-us/azure/data-explorer/)

---

## Contributing

If you encounter issues or have suggestions for improving the MCP integration, please open an issue or submit a pull request.

## Feedback

We'd love to hear about your experience using Azure MCP servers with this repository! Share your feedback, use cases, and success stories.
