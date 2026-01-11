# Azure MCP Server Integration

This repository supports the **Azure MCP (Model Context Protocol) Server**, allowing AI assistants like Claude Desktop and GitHub Copilot to interact with Azure DevOps resources.

## What is MCP?

The Model Context Protocol (MCP) is an open standard for connecting AI systems with external resources and APIs. It allows AI assistants to securely access data sources, execute functions, and automate workflows through standardized API calls.

## Azure MCP Server

The Azure MCP Server enables AI assistants to:
- Query Azure DevOps work items, pull requests, and repositories
- Create and update work items
- Search code and view repository contents
- Access Azure cloud resources and configurations

## Setup Instructions

### Prerequisites

- Node.js (v18 or later)
- npm or npx installed
- Azure DevOps Personal Access Token (PAT)
- Claude Desktop, VS Code with GitHub Copilot, or another MCP-compatible AI assistant

### For Claude Desktop

1. **Locate your Claude Desktop configuration file:**
   - **Windows**: `%APPDATA%\Claude\claude_desktop_config.json`
   - **MacOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`
   - **Linux**: `~/.config/Claude/claude_desktop_config.json`

2. **Add the Azure MCP Server configuration:**

```json
{
  "mcpServers": {
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

3. **Restart Claude Desktop** to load the new configuration.

### For VS Code / GitHub Copilot

The repository includes a `.github/mcp.json` configuration file that VS Code and GitHub Copilot can use.

1. **Set environment variables** in your shell or IDE:

```bash
export ADO_PERSONAL_ACCESS_TOKEN="your-azure-devops-pat-token"
export ADO_ORG="your-azure-devops-org-name"
```

2. **VS Code** will automatically detect and use the MCP configuration when working with this repository.

### Generating an Azure DevOps Personal Access Token

1. Go to your Azure DevOps organization (e.g., `https://dev.azure.com/{your-org}`)
2. Click on **User Settings** (gear icon) > **Personal Access Tokens**
3. Click **New Token**
4. Configure the token:
   - **Name**: "MCP Server Access" (or your choice)
   - **Organization**: Select your organization
   - **Scopes**: 
     - Code: Read
     - Work Items: Read & Write
     - Build: Read
     - Project and Team: Read
5. Click **Create** and **copy the token immediately** (it won't be shown again)

## Usage Examples

Once configured, you can use natural language commands with your AI assistant:

- "List all work items in Azure DevOps"
- "Show me recent pull requests in the main repository"
- "Create a new work item for bug tracking"
- "Search for authentication code in Azure repos"
- "What Azure resources are configured for this project?"

## Security Considerations

- **Never commit your Personal Access Token** to version control
- Store tokens securely using environment variables or secret management tools
- Grant minimal required scopes to your PAT
- Rotate tokens regularly
- Use separate tokens for different environments (dev, staging, production)

## Troubleshooting

### MCP Server not loading
- Verify Node.js version: `node --version` (should be v18+)
- Check that environment variables are set correctly
- Restart your AI assistant application

### Authentication errors
- Verify your PAT is valid and not expired
- Check that the PAT has the required scopes
- Ensure ADO_ORG matches your Azure DevOps organization name

### Connection issues
- Verify network connectivity to Azure DevOps
- Check firewall/proxy settings
- Ensure `@azure-devops/mcp` package can be accessed via npm

## Additional Resources

- [Model Context Protocol Documentation](https://modelcontextprotocol.io/)
- [Azure MCP Server GitHub](https://github.com/microsoft/azure-devops-mcp)
- [Microsoft MCP Documentation](https://learn.microsoft.com/en-us/azure/developer/azure-mcp-server/)
- [Claude Desktop MCP Guide](https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop)

## Contributing

If you encounter issues or have suggestions for improving the MCP integration, please open an issue or submit a pull request.
