#!/bin/bash
set -e

# Display Azure MCP Server setup instructions
cat << 'EOF'

=== Azure MCP Server Setup ===

To use Azure MCP servers with your personal Azure account:

1. Authenticate with Azure CLI:
   az login --use-device-code

2. (Optional) Set your default subscription if you have multiple:
   az account list --output table
   az account set --subscription <subscription-id>

3. Verify your authentication:
   az account show

4. Start using GitHub Copilot Chat with Azure MCP tools!
   Example: "Show me all my Azure Data Explorer clusters"

For more details, see azure-mcp-data-explorer-deployer/MCP_SETUP.md
================================

EOF

exit 0
