# Azure MCP Integration Architecture

This document provides architectural diagrams and flow charts for understanding the Azure MCP integration.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        GitHub Repository                         │
│                                                                  │
│  ┌────────────────┐         ┌─────────────────────┐            │
│  │ .github/       │         │ docs/              │            │
│  │   mcp.json     │────────▶│  - ARCHITECTURE.md │            │
│  │                │         │  - QUICK_REFERENCE │            │
│  │                │         │    .md             │            │
│  │                │         │  - GITHUB_COPILOT_ │            │
│  │                │         │    SETUP.md        │            │
│  └────────────────┘         │  (MCP guide lives  │            │
│                             │   in azure-mcp-    │            │
│                             │   data-explorer-   │            │
│                             │   deployer/        │            │
│                             │   MCP_SETUP.md)    │            │
│                             └─────────────────────┘            │
│          │                                                       │
└──────────┼───────────────────────────────────────────────────────┘
           │
           │ Configuration
           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    GitHub Copilot / Claude Desktop               │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              MCP Client (in AI Assistant)                 │  │
│  │                                                            │  │
│  │  Loads: .github/mcp.json or claude_desktop_config.json   │  │
│  └──────────────────────────────────────────────────────────┘  │
│           │                    │                    │            │
└───────────┼────────────────────┼────────────────────┼────────────┘
            │                    │                    │
            ▼                    ▼                    ▼
    ┌──────────────┐    ┌──────────────┐    ┌──────────────┐
    │ Azure MCP    │    │ Azure Data   │    │ Azure DevOps │
    │ Server       │    │ Explorer MCP │    │ MCP Server   │
    │ (@azure/mcp) │    │ (adx-mcp)    │    │ (@ado/mcp)   │
    └──────────────┘    └──────────────┘    └──────────────┘
            │                    │                    │
            └────────────────────┴────────────────────┘
                                 │
                                 ▼
                     ┌──────────────────────┐
                     │ Azure Authentication │
                     │                      │
                     │ • Azure CLI          │
                     │ • Managed Identity   │
                     │ • Service Principal  │
                     └──────────────────────┘
                                 │
                                 ▼
                    ┌────────────────────────┐
                    │    Azure Resources     │
                    │                        │
                    │ • ADX Clusters         │
                    │ • ADX Databases        │
                    │ • Azure Resources      │
                    │ • DevOps Projects      │
                    └────────────────────────┘
```

## GitHub Copilot Authentication Flow

```
┌──────────────────────────────────────────────────────────────────┐
│ 1. Developer runs: azd coding-agent config                       │
└──────────────────┬───────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│ 2. Azure Developer CLI:                                          │
│    • Creates User Managed Identity (UMI)                         │
│    • Assigns Reader RBAC role                                    │
│    • Creates Federated Credential (GitHub ↔ Azure)              │
│    • Sets GitHub repository environment variables                │
└──────────────────┬───────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│ 3. Repository configured with:                                   │
│    • COPILOT_MCP_AZURE_TENANT_ID                                │
│    • COPILOT_MCP_AZURE_CLIENT_ID                                │
│    • COPILOT_MCP_AZURE_SUBSCRIPTION_ID                          │
└──────────────────┬───────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│ 4. GitHub Copilot Chat invoked by user                          │
│    User: "Show me all Azure Data Explorer clusters"             │
└──────────────────┬───────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│ 5. GitHub Copilot:                                               │
│    • Loads .github/mcp.json configuration                        │
│    • Starts Azure MCP server with environment variables          │
└──────────────────┬───────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│ 6. Azure MCP Server:                                             │
│    • Gets GitHub OIDC token from environment                     │
│    • Exchanges for Azure AD token using Federated Credential    │
│    • Token scoped to User Managed Identity                       │
└──────────────────┬───────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│ 7. Azure AD validates:                                           │
│    • GitHub repository identity (via OIDC)                       │
│    • Federated Credential configuration                          │
│    • Returns Azure access token                                  │
└──────────────────┬───────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│ 8. MCP Server uses token to call Azure APIs:                    │
│    • List subscriptions                                          │
│    • Enumerate ADX clusters                                      │
│    • List databases in clusters                                  │
└──────────────────┬───────────────────────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────────────────────┐
│ 9. Results returned to GitHub Copilot:                          │
│    "Found 3 Azure Data Explorer clusters:                       │
│     • cluster1.eastus.kusto.windows.net                         │
│     • cluster2.westus.kusto.windows.net                         │
│     • cluster3.centralus.kusto.windows.net"                     │
└──────────────────────────────────────────────────────────────────┘
```

## Automatic Discovery Flow

```
User Query: "Show my ADX clusters"
         │
         ▼
┌─────────────────────────────────────────┐
│ GitHub Copilot parses intent:           │
│ "User wants to list ADX clusters"       │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Copilot invokes MCP tool:               │
│ Tool: "list-kusto-clusters"             │
│ Params: { subscription: <sub-id> }      │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ ADX MCP Server:                         │
│ 1. Authenticates with Azure             │
│ 2. Calls Azure Resource Graph API       │
│ 3. Queries for Kusto clusters           │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Azure API Response:                     │
│ {                                        │
│   "data": [                              │
│     {                                    │
│       "name": "cluster1",                │
│       "location": "eastus",              │
│       "state": "Running",                │
│       "uri": "https://cluster1.eastus..."│
│     },                                   │
│     ...                                  │
│   ]                                      │
│ }                                        │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ MCP Server formats response             │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│ Copilot generates natural language:     │
│ "You have 3 ADX clusters:                │
│  1. cluster1 (East US) - Running        │
│  2. cluster2 (West US) - Running        │
│  3. cluster3 (Central US) - Running     │
│                                          │
│ Would you like to explore databases     │
│ in any of these clusters?"              │
└─────────────────────────────────────────┘
```

## Component Interaction Matrix

```
┌──────────────────┬─────────┬─────────┬─────────┬──────────┐
│                  │ GitHub  │ Claude  │ VS Code │ Azure    │
│                  │ Copilot │ Desktop │ Copilot │ CLI Auth │
├──────────────────┼─────────┼─────────┼─────────┼──────────┤
│ .github/mcp.json │   ✅    │   ❌    │   ✅    │   ✅     │
├──────────────────┼─────────┼─────────┼─────────┼──────────┤
│ claude_desktop   │   ❌    │   ✅    │   ❌    │   ✅     │
│ _config.json     │         │         │         │          │
├──────────────────┼─────────┼─────────┼─────────┼──────────┤
│ Federated        │   ✅    │   ❌    │   ✅    │   ❌     │
│ Credentials      │         │         │         │          │
├──────────────────┼─────────┼─────────┼─────────┼──────────┤
│ Environment      │   ✅    │   ✅    │   ✅    │   N/A    │
│ Variables        │         │         │         │          │
├──────────────────┼─────────┼─────────┼─────────┼──────────┤
│ Managed Identity │   ✅    │   ✅    │   ✅    │   N/A    │
├──────────────────┼─────────┼─────────┼─────────┼──────────┤
│ Automatic        │   ✅    │   ✅    │   ✅    │   ✅     │
│ Discovery        │         │         │         │          │
└──────────────────┴─────────┴─────────┴─────────┴──────────┘
```

## Setup Comparison

### Method 1: GitHub Copilot (azd)
```
Complexity:  ⭐ (Simple)
Time:        ~5 minutes
Security:    ⭐⭐⭐⭐⭐ (Excellent - No secrets)
Automation:  ⭐⭐⭐⭐⭐ (Fully automated)

Steps:
1. Install azd
2. Run azd coding-agent config
3. Copy/paste config to GitHub
Done!
```

### Method 2: Azure CLI Auth
```
Complexity:  ⭐⭐ (Easy)
Time:        ~2 minutes
Security:    ⭐⭐⭐⭐ (Good - Local credentials)
Automation:  ⭐⭐⭐ (Semi-automated)

Steps:
1. Run az login
2. Configure MCP client
Done!
```

### Method 3: Manual with Managed Identity
```
Complexity:  ⭐⭐⭐⭐ (Complex)
Time:        ~20 minutes
Security:    ⭐⭐⭐⭐⭐ (Excellent - No secrets)
Automation:  ⭐⭐ (Manual setup)

Steps:
1. Create managed identity
2. Assign RBAC roles
3. Configure federated credentials
4. Set environment variables
5. Configure MCP client
Done!
```

## Security Architecture

```
┌────────────────────────────────────────────────────────────┐
│                      Security Layers                        │
└────────────────────────────────────────────────────────────┘

Layer 1: GitHub Identity
┌──────────────────────────────────────────────────────────┐
│ • Repository-scoped OIDC tokens                          │
│ • Short-lived (minutes)                                   │
│ • Audience-restricted                                     │
│ • Subject claim: repo:{org}/{repo}:ref:refs/heads/main  │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
Layer 2: Azure AD Trust
┌──────────────────────────────────────────────────────────┐
│ • Federated Credential validates GitHub token            │
│ • Issuer: https://token.actions.githubusercontent.com    │
│ • Audience: api://AzureADTokenExchange                   │
│ • Subject match required                                  │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
Layer 3: Managed Identity
┌──────────────────────────────────────────────────────────┐
│ • User Managed Identity (UMI)                            │
│ • RBAC roles assigned (Reader, Database User, etc.)      │
│ • Scope: Subscription or Resource Group                  │
│ • No secrets - identity-based                            │
└──────────────────────────────────────────────────────────┘
                          │
                          ▼
Layer 4: Resource Access
┌──────────────────────────────────────────────────────────┐
│ • Azure Resource Manager APIs                            │
│ • Azure Data Explorer APIs                               │
│ • Azure DevOps REST APIs                                 │
│ • All access logged in Azure AD                          │
└──────────────────────────────────────────────────────────┘
```

## Data Flow: Natural Language to KQL

```
User: "Show me errors in the last hour from my ADX cluster"
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ GitHub Copilot LLM Analysis:                           │
│ • Intent: Query ADX for errors                          │
│ • Time filter: Last 1 hour                              │
│ • Needs: Cluster, Database, Table identification        │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ MCP Tool Invocation: list-clusters                      │
│ → Returns: cluster1, cluster2, cluster3                 │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ MCP Tool Invocation: list-databases (cluster1)          │
│ → Returns: LogsDB, MetricsDB, EventsDB                  │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ MCP Tool Invocation: list-tables (LogsDB)               │
│ → Returns: AppLogs, SystemLogs, ErrorLogs               │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ MCP Tool Invocation: get-schema (ErrorLogs)             │
│ → Returns: Timestamp, Level, Message, Source, ...       │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Copilot generates KQL:                                  │
│                                                          │
│ ErrorLogs                                                │
│ | where Timestamp > ago(1h)                             │
│ | where Level == "Error"                                │
│ | summarize count() by bin(Timestamp, 5m), Source      │
│ | order by Timestamp desc                               │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ MCP Tool Invocation: execute-query                      │
│ Params: { cluster, database, query }                    │
└─────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────┐
│ Results returned and formatted by Copilot               │
│                                                          │
│ "Found 147 errors in the last hour:                     │
│                                                          │
│  • 89 from Service-A (60%)                              │
│  • 43 from Service-B (29%)                              │
│  • 15 from Service-C (10%)                              │
│                                                          │
│  Peak: 15:35 (23 errors)                                │
│  Trend: Decreasing                                       │
│                                                          │
│  [Show detailed breakdown] [Export to CSV]"             │
└─────────────────────────────────────────────────────────┘
```

## Deployment Options

```
Development Environment:
┌─────────────────────────────────────┐
│ Local Machine                       │
│ • Azure CLI authentication          │
│ • VS Code + GitHub Copilot          │
│ • .github/mcp.json config           │
└─────────────────────────────────────┘

CI/CD Pipeline:
┌─────────────────────────────────────┐
│ GitHub Actions                      │
│ • Managed Identity (GitHub)         │
│ • Federated Credentials             │
│ • Automated testing                 │
└─────────────────────────────────────┘

Production:
┌─────────────────────────────────────┐
│ Azure Container Apps / Functions    │
│ • System Managed Identity           │
│ • VNet integration                  │
│ • Private endpoints                 │
└─────────────────────────────────────┘
```

## Summary

This architecture provides:
- ✅ **Zero secrets** in code (federated credentials)
- ✅ **Automatic discovery** of Azure resources
- ✅ **Natural language interface** for complex queries
- ✅ **Multi-platform support** (GitHub Copilot, Claude, VS Code)
- ✅ **Enterprise security** (Azure AD, RBAC, audit logs)
- ✅ **Scalable** (works from development to production)