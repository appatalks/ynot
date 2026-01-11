# GitHub Copilot Integration Guide

This guide provides step-by-step instructions for integrating Azure MCP servers with GitHub Copilot, enabling automatic discovery of Azure Data Explorer clusters and databases.

## Overview

GitHub Copilot's coding agent can connect to Azure resources through MCP (Model Context Protocol) servers. This enables:
- **Automatic discovery** of Azure Data Explorer clusters and databases
- **Natural language queries** to Azure resources
- **Secure authentication** via Azure CLI or Managed Identity
- **Seamless integration** with your GitHub repositories

This repository supports **two authentication models**:

### 🌐 Per-User Identity (Codespaces)
- Each collaborator uses their own Azure account
- Authentication via Azure CLI (`az login --use-device-code`)
- Zero configuration required
- Best for development and personal use

### 🔐 Shared Identity (GitHub.com)
- Repository-wide access via Managed Identity
- Configured once by repository admin using `azd coding-agent config`
- Best for team-wide production access

## Prerequisites

- GitHub Copilot subscription (Individual, Business, or Enterprise)
- Azure account with access to:
  - Azure Data Explorer clusters (for ADX integration)
  - Azure DevOps organization (optional, for DevOps integration)
- GitHub repository where you want to enable MCP

## Setup Methods

### Method 1: GitHub Codespaces with Per-User Azure Identity (Recommended for Collaborators) 🌐

This method allows **any collaborator** to use their personal Azure account in a Codespace without needing repository-level secrets.

#### Step 1: Create a Codespace

1. Open this repository on GitHub.com
2. Click **Code** → **Codespaces** → **Create codespace on main**
3. Wait for the Codespace to build (includes Node.js 18+ and Azure CLI)

#### Step 2: Authenticate with Azure

In the Codespace terminal, run:

```bash
az login --use-device-code
```

Follow the device code flow:
- Copy the code shown in the terminal
- Open https://microsoft.com/devicelogin in your browser
- Paste the code and sign in with your Azure account

#### Step 3: (Optional) Set Default Subscription

If you have multiple Azure subscriptions:

```bash
# List available subscriptions
az account list --output table

# Set the default subscription
az account set --subscription <subscription-id>
```

#### Step 4: Verify Authentication

```bash
az account show
```

#### Step 5: Start Using Copilot

1. Open Copilot Chat in VS Code (Ctrl+Shift+I or Cmd+Shift+I)
2. The `.github/mcp.json` configuration is automatically loaded
3. Azure and ADX MCP servers use your Azure CLI credentials
4. Try: "Show me all my Azure Data Explorer clusters"

**That's it!** No repository secrets or configuration files needed.

#### How It Works

- The `.github/mcp.json` is automatically loaded in Codespaces
- Azure and ADX MCP servers use Azure CLI authentication by default
- MCP servers discover resources based on **your Azure permissions**
- Each collaborator works with their own Azure identity

---

### Method 2: Automated Setup with Azure Developer CLI (For GitHub.com) 🚀

This method configures a **shared Managed Identity** for the entire repository, used when accessing GitHub Copilot on GitHub.com (not Codespaces).

This is the fastest and most secure method.

#### Step 1: Install Azure Developer CLI

**Windows:**
```powershell
winget install Microsoft.Azd
```

**macOS:**
```bash
brew install azure/azd/azd
```

**Linux:**
```bash
curl -fsSL https://aka.ms/install-azd.sh | bash
```

#### Step 2: Install Azure Coding Agent Extension

```bash
azd extension install azure.coding-agent
```

#### Step 3: Authenticate with Azure

```bash
az login
```

Select your Azure subscription when prompted.

#### Step 4: Configure GitHub Copilot Coding Agent

Navigate to your repository directory and run:

```bash
azd coding-agent config
```

This interactive command will:
1. ✅ Prompt you to select your Azure subscription
2. ✅ Select or create a User Managed Identity (UMI)
3. ✅ Assign necessary RBAC roles (Reader by default)
4. ✅ Set up federated credentials for passwordless auth
5. ✅ Configure GitHub repository environment variables
6. ✅ Generate MCP configuration JSON

#### Step 5: Apply Configuration to GitHub

The command will output a JSON configuration. Copy it and:

1. Go to your repository on GitHub.com
2. Navigate to **Settings** → **Code & automation** → **Copilot**
3. Click on **Coding agent** settings
4. Paste the configuration in the MCP configuration section
5. Save changes

Example configuration:
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

#### Step 6: Verify Setup

Open GitHub Copilot Chat in VS Code or GitHub.com and try:
```
"Show me all my Azure Data Explorer clusters"
```

---

### Method 3: Manual Configuration (Advanced)

If you prefer manual setup or need custom configuration for the shared identity model:

#### Step 1: Create MCP Configuration File

This repository already includes `.github/mcp.json`. You can customize it:

```json
{
  "mcpServers": {
    "azure": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "env": {
        "AZURE_TENANT_ID": "${AZURE_TENANT_ID}",
        "AZURE_CLIENT_ID": "${AZURE_CLIENT_ID}",
        "AZURE_SUBSCRIPTION_ID": "${AZURE_SUBSCRIPTION_ID}"
      }
    },
    "azure-data-explorer": {
      "command": "npx",
      "args": ["-y", "adx-mcp-server"],
      "env": {
        "AZURE_TENANT_ID": "${AZURE_TENANT_ID}",
        "AZURE_CLIENT_ID": "${AZURE_CLIENT_ID}",
        "AZURE_SUBSCRIPTION_ID": "${AZURE_SUBSCRIPTION_ID}"
      }
    }
  }
}
```

#### Step 2: Set Up GitHub Repository Secrets

1. Go to **Settings** → **Secrets and variables** → **Codespaces** (or **Actions**)
2. Add the following secrets with `COPILOT_MCP_` prefix:

   - `COPILOT_MCP_AZURE_TENANT_ID`: Your Azure tenant ID
   - `COPILOT_MCP_AZURE_CLIENT_ID`: Client ID of your managed identity or service principal
   - `COPILOT_MCP_AZURE_SUBSCRIPTION_ID`: Your Azure subscription ID

#### Step 3: Create Azure Managed Identity (if not exists)

```bash
# Create resource group (if needed)
az group create --name mcp-resources --location eastus

# Create user-assigned managed identity
az identity create \
  --name github-copilot-mcp \
  --resource-group mcp-resources

# Get the client ID
az identity show \
  --name github-copilot-mcp \
  --resource-group mcp-resources \
  --query clientId -o tsv
```

#### Step 4: Assign Permissions

Assign Reader role to the managed identity:

```bash
az role assignment create \
  --assignee <CLIENT_ID> \
  --role Reader \
  --scope /subscriptions/<SUBSCRIPTION_ID>
```

For Azure Data Explorer access, assign Kusto Database User role:

```bash
az kusto database-principal-assignment create \
  --cluster-name <CLUSTER_NAME> \
  --database-name <DATABASE_NAME> \
  --principal-id <CLIENT_ID> \
  --principal-type App \
  --role User \
  --resource-group <RESOURCE_GROUP>
```

#### Step 5: Configure Federated Credentials

Link your GitHub repository to the managed identity:

```bash
az identity federated-credential create \
  --name github-copilot-fed-cred \
  --identity-name github-copilot-mcp \
  --resource-group mcp-resources \
  --issuer https://token.actions.githubusercontent.com \
  --subject repo:<YOUR_ORG>/<YOUR_REPO>:ref:refs/heads/main \
  --audiences api://AzureADTokenExchange
```

---

## Using GitHub Copilot with Azure Data Explorer

### In VS Code

1. Open VS Code with your repository
2. Ensure GitHub Copilot extension is installed and activated
3. Open Copilot Chat (Ctrl+Shift+I or Cmd+Shift+I on Mac)
4. Start asking questions about your Azure resources!

### Example Prompts

**Discovery:**
```
"Show me all Azure Data Explorer clusters in my subscription"
"List all databases in cluster <cluster-name>"
"What tables are in database <database-name>?"
```

**Schema Exploration:**
```
"Show me the schema of table Logs"
"What columns does the Events table have?"
"Describe the structure of the Metrics table"
```

**Data Queries:**
```
"Query the last 100 records from the Logs table"
"Get error logs from the past hour"
"Show me distinct users from the Events table today"
"Count records in table Metrics by hour for the last 24 hours"
```

**Analysis:**
```
"Analyze error patterns in my ADX cluster"
"Show performance metrics from the last week"
"Find anomalies in the Telemetry table"
```

### In GitHub.com (Copilot Chat)

1. Go to your repository on GitHub.com
2. Look for the Copilot icon in the interface
3. Click to open Copilot Chat
4. Use the same prompts as above

---

## Authentication Flow

The authentication flow uses Azure Workload Identity (federated credentials):

```
GitHub Copilot Request
    ↓
Azure MCP Server
    ↓
Azure AD Token Request (with GitHub OIDC token)
    ↓
Azure AD validates GitHub identity
    ↓
Returns Azure access token
    ↓
MCP Server uses token to access Azure resources
    ↓
Automatic discovery of clusters/databases
    ↓
Results returned to GitHub Copilot
```

**Benefits:**
- ✅ No secrets stored in repository
- ✅ Automatic credential rotation
- ✅ Fine-grained access control
- ✅ Audit trail in Azure AD
- ✅ Works with GitHub Enterprise

---

## Advanced Configuration

### Multi-Environment Setup

Configure different MCP servers for different environments:

```json
{
  "mcpServers": {
    "azure-prod": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "${AZURE_PROD_SUBSCRIPTION_ID}"
      }
    },
    "azure-dev": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "env": {
        "AZURE_SUBSCRIPTION_ID": "${AZURE_DEV_SUBSCRIPTION_ID}"
      }
    }
  }
}
```

### Custom Tool Filtering

Restrict which tools Copilot can access:

```json
{
  "mcpServers": {
    "azure": {
      "command": "npx",
      "args": ["-y", "@azure/mcp@latest", "server", "start"],
      "tools": [
        "list-clusters",
        "list-databases",
        "get-schema",
        "query-data"
      ]
    }
  }
}
```

### Combine Multiple Azure Services

```json
{
  "mcpServers": {
    "azure-data-explorer": {
      "command": "npx",
      "args": ["-y", "adx-mcp-server"]
    },
    "azure-devops": {
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp"],
      "env": {
        "ADO_PERSONAL_ACCESS_TOKEN": "${COPILOT_MCP_ADO_PAT}",
        "ADO_ORG": "${COPILOT_MCP_ADO_ORG}"
      }
    }
  }
}
```

---

## Troubleshooting

### MCP Server Not Detected

**Problem:** GitHub Copilot doesn't seem to recognize Azure resources.

**Solutions:**
1. Verify `.github/mcp.json` exists in repository root
2. Check that configuration is valid JSON
3. Ensure GitHub Copilot subscription is active
4. Try reloading VS Code window (Ctrl+Shift+P → "Reload Window")

### Authentication Failures

**Problem:** Getting 401 or 403 errors when accessing Azure.

**Solutions:**
1. Verify Azure CLI is authenticated: `az account show`
2. Check managed identity has Reader role: 
   ```bash
   az role assignment list --assignee <CLIENT_ID>
   ```
3. Ensure federated credential is configured correctly
4. Verify subscription ID in environment variables

### No Clusters/Databases Visible

**Problem:** Copilot says no clusters or databases found.

**Solutions:**
1. Verify clusters exist in the subscription:
   ```bash
   az kusto cluster list --subscription <SUBSCRIPTION_ID>
   ```
2. Check you're using the correct subscription ID
3. Ensure managed identity has permission to list clusters
4. Try specifying cluster URI explicitly

### Rate Limiting

**Problem:** Getting rate limit errors from Azure.

**Solutions:**
1. Reduce frequency of queries
2. Use more specific prompts to minimize API calls
3. Consider caching in custom MCP server implementation

### VS Code Extension Issues

**Problem:** GitHub Copilot extension not working properly.

**Solutions:**
1. Update VS Code to latest version
2. Update GitHub Copilot extension
3. Check VS Code output panel for errors
4. Try disabling and re-enabling Copilot extension

---

## Security Best Practices

### ✅ Do's

- ✅ Use Managed Identity for authentication
- ✅ Use federated credentials (no secrets)
- ✅ Apply principle of least privilege (minimal RBAC roles)
- ✅ Use separate identities for different environments
- ✅ Enable Azure AD audit logging
- ✅ Regularly review access permissions
- ✅ Use GitHub Environments for additional security

### ❌ Don'ts

- ❌ Don't store credentials in code or configuration files
- ❌ Don't use overly broad permissions (avoid Contributor/Owner roles)
- ❌ Don't share managed identity across unrelated projects
- ❌ Don't commit `.env` files with secrets
- ❌ Don't use service principals unless necessary

---

## Performance Tips

1. **Be Specific**: Use specific cluster/database names in prompts
2. **Limit Scope**: Query specific time ranges rather than all data
3. **Cache Results**: Store commonly-used schema information
4. **Use Filters**: Apply filters in KQL queries rather than post-processing
5. **Parallel Queries**: Multiple independent queries can run concurrently

---

## GitHub Copilot Spaces (Preview)

If you have access to GitHub Copilot Spaces (preview feature):

1. Create a new Copilot Space
2. Select your repository
3. The MCP configuration will be automatically loaded
4. You'll have a dedicated environment for Azure exploration

**Note:** Copilot Spaces is currently in limited preview.

---

## Getting Help

### Documentation
- [GitHub Copilot MCP Documentation](https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/extend-coding-agent-with-mcp)
- [Azure MCP Server Docs](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/)
- [Azure Data Explorer MCP](https://learn.microsoft.com/en-us/azure/data-explorer/integrate-mcp-servers)

### Community
- [GitHub Community Discussions](https://github.com/orgs/community/discussions)
- [Azure Developer Community](https://techcommunity.microsoft.com/azure)

### Support
- GitHub Copilot: support@github.com
- Azure: Azure Portal → Support → New support request

---

## What's Next?

- Explore more Azure MCP servers for other services
- Build custom MCP servers for your specific needs
- Share your integration patterns with the community
- Provide feedback to improve the experience

Happy coding with AI-powered Azure integration! 🚀