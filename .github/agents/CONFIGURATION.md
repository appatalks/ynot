# Azure Data Explorer Custom Agent - Configuration Summary

This document summarizes the configuration and files for the `@adx-query-agent` custom GitHub Copilot agent.

## 📁 File Structure

```
.github/agents/
├── adx-query-agent.md     # Main agent definition
├── README.md              # Agent directory overview
├── QUICKSTART.md          # 5-minute quick start guide
├── SETUP.md               # Detailed setup instructions
└── TESTING.md             # Testing and validation guide

azure-mcp-data-explorer-deployer/
├── adx_client.py          # ADX client with cached auth
├── adx_query.py           # CLI for ADX operations
├── run.sh                 # Convenience wrapper script
├── requirements.txt       # Python dependencies
├── .env.template          # Environment configuration template
├── .env                   # Your configuration (gitignored)
├── README.md              # Module documentation
├── MCP_SETUP.md           # MCP integration guide
└── copilot-instructions.md # Copilot usage patterns
```

## ⚙️ Configuration Files

### 1. Agent Definition (`.github/agents/adx-query-agent.md`)

**Purpose**: Defines the custom agent for GitHub Copilot

**Key Components**:
- **YAML Frontmatter**:
  ```yaml
  ---
  name: adx-query-agent
  description: Expert in Azure Data Explorer queries and KQL syntax
  tools: ['*']
  ---
  ```
- **Agent Instructions**: Detailed guidance on how the agent should behave
- **Capabilities**: What operations the agent can perform
- **Examples**: Common use cases and query patterns

**How It Works**:
- GitHub Copilot reads this file automatically when in the repository
- The agent becomes available as `@adx-query-agent` in Copilot Chat
- The agent follows the instructions in the Markdown content

### 2. Environment Configuration (`azure-mcp-data-explorer-deployer/.env`)

**Purpose**: Stores Azure Data Explorer connection details

**Required Variables**:
```bash
# Your ADX cluster URL (required)
ADX_CLUSTER_URL=https://<yourcluster>.<region>.kusto.windows.net

# Default database name (optional for discovery)
ADX_DATABASE=<your-database-name>

# Authentication cache paths (optional, defaults provided)
ADX_AUTH_RECORD_PATH=~/.azure/adx_auth_record.json
ADX_TOKEN_CACHE_PATH=~/.IdentityService/
```

**Setup**:
```bash
cd azure-mcp-data-explorer-deployer
cp .env.template .env
# Edit .env with your values
```

### 3. Python Dependencies (`azure-mcp-data-explorer-deployer/requirements.txt`)

**Purpose**: Specifies required Python packages

**Contents**:
```
azure-kusto-data>=6.0.0
azure-identity>=1.25.0
```

**Installation**:
```bash
cd azure-mcp-data-explorer-deployer
pip install -r requirements.txt
```

## 🔐 Authentication Flow

The agent uses the following authentication methods (in order):

1. **Azure CLI** (Preferred)
   - User runs: `az login --use-device-code`
   - Credentials cached by Azure CLI
   - Automatically used by Python scripts

2. **Device Code Flow** (Fallback)
   - Interactive browser-based authentication
   - Token cached persistently
   - Auth record saved for reuse

3. **Service Principal** (Advanced)
   - Environment variables: `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_TENANT_ID`
   - For automated/production scenarios

## 🛠️ How the Agent Works

### User Interaction Flow

1. **User invokes agent** in Copilot Chat:
   ```
   @adx-query-agent Show me all my databases
   ```

2. **Agent processes request**:
   - Understands the intent (list databases)
   - Checks prerequisites (authentication, config)
   - Determines appropriate action

3. **Agent executes operation**:
   - Uses terminal commands to run Python scripts
   - Example: `cd azure-mcp-data-explorer-deployer && ./run.sh --databases`

4. **Agent presents results**:
   - Parses output from scripts
   - Formats data in user-friendly way
   - Provides context and explanations

### Example Workflow

**User**: `@adx-query-agent Query errors from the Logs table in the past hour`

**Agent thinks**:
- User wants to query for errors
- Table is "Logs"
- Time filter is 1 hour
- Need to generate KQL query

**Agent generates KQL**:
```kql
Logs
| where Timestamp > ago(1h)
| where Level == "Error"
| project Timestamp, Message, Source
| order by Timestamp desc
```

**Agent executes**:
```bash
cd azure-mcp-data-explorer-deployer
./run.sh --kql "Logs | where Timestamp > ago(1h) | where Level == 'Error' | project Timestamp, Message, Source | order by Timestamp desc"
```

**Agent responds**:
- Shows the KQL query
- Explains what it does
- Displays the results
- Suggests follow-up queries

## 🎯 Available Operations

The agent can perform these operations via the Python scripts:

| Operation | Command | Description |
|-----------|---------|-------------|
| Discover clusters | `./run.sh --discover-clusters` | List all ADX clusters in subscription |
| List databases | `./run.sh --databases` | Show all databases in cluster |
| List tables | `./run.sh --tables` | Show all tables in database |
| Sample data | `./run.sh --sample "TableName" --limit 10` | Preview table data |
| Execute KQL | `./run.sh --kql "TableName \| take 10"` | Run custom query |
| Admin operations | `./run.sh --allow-admin --kql ".show databases"` | Run management commands |

## 🔒 Security Features

### Read-Only by Default

- Agent refuses management commands (starting with `.`) unless `--allow-admin` is used
- Agent blocks write/alter operations automatically
- Users must explicitly opt in to admin operations

### Blocked Operations (without `--allow-admin`)

- `.ingest` commands
- `.set`, `.append`, `.drop` commands
- `.create`, `.alter`, `.rename` commands
- Data modification operations

### Best Practices

1. **Use least-privilege roles**: Database Viewer for read-only access
2. **Audit admin operations**: Review before executing with `--allow-admin`
3. **Validate queries**: Agent explains queries before execution
4. **Time-bound queries**: Always include time ranges for large tables

## 🚀 Quick Start

### 1. Prerequisites
```bash
# Authenticate with Azure
az login --use-device-code

# Verify authentication
az account show
```

### 2. Setup Environment
```bash
# Install Python dependencies
cd azure-mcp-data-explorer-deployer
pip install -r requirements.txt

# Configure cluster connection
cp .env.template .env
# Edit .env with your ADX_CLUSTER_URL
```

### 3. Test Connection
```bash
# List databases
./run.sh --databases

# If successful, you're ready to use the agent!
```

### 4. Use the Agent
Open GitHub Copilot Chat and try:
```
@adx-query-agent Show me all my Azure Data Explorer clusters
```

## 📚 Documentation Files

- **[README.md](README.md)**: Overview of available agents
- **[QUICKSTART.md](QUICKSTART.md)**: Get started in 5 minutes
- **[SETUP.md](SETUP.md)**: Detailed configuration guide
- **[TESTING.md](TESTING.md)**: Validation and troubleshooting
- **[../azure-mcp-data-explorer-deployer/MCP_SETUP.md](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md)**: MCP integration details
- **[../azure-mcp-data-explorer-deployer/copilot-instructions.md](../../azure-mcp-data-explorer-deployer/copilot-instructions.md)**: Usage patterns

## 🐛 Troubleshooting

### Agent Not Found
- Check file location: `.github/agents/adx-query-agent.md`
- Verify YAML frontmatter syntax
- Reload VS Code window

### Authentication Errors
```bash
# Re-authenticate
az login --use-device-code

# Clear cached credentials
rm -f ~/.azure/adx_auth_record.json
rm -rf ~/.IdentityService/
```

### Connection Failures
```bash
# Verify cluster URL
echo $ADX_CLUSTER_URL

# Discover clusters
cd azure-mcp-data-explorer-deployer
./run.sh --discover-clusters
```

### Script Errors
```bash
# Test scripts manually
cd azure-mcp-data-explorer-deployer
./run.sh --help
./run.sh --databases
```

See [TESTING.md](TESTING.md) for comprehensive troubleshooting.

## 🎓 Learning Resources

- **KQL Tutorial**: [Azure Data Explorer Query Language](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/query/)
- **Best Practices**: [KQL Best Practices](https://docs.microsoft.com/en-us/azure/data-explorer/kusto/query/best-practices)
- **Azure MCP**: [Azure MCP Documentation](https://github.com/Azure/azure-mcp)
- **GitHub Copilot Agents**: [Custom Agents Documentation](https://docs.github.com/en/copilot/reference/custom-agents-configuration)

## 🤝 Contributing

To customize the agent:

1. Edit `.github/agents/adx-query-agent.md`
2. Modify the instructions, examples, or capabilities
3. Test changes: Reload VS Code and invoke the agent
4. Document changes in this file

## ✅ Verification Checklist

Setup is complete when:

- [ ] Agent appears in Copilot Chat autocomplete (`@adx-query-agent`)
- [ ] Agent responds to basic queries
- [ ] Scripts work manually: `./run.sh --databases`
- [ ] Agent can discover clusters
- [ ] Agent can list databases and tables
- [ ] Agent can execute KQL queries
- [ ] Agent generates valid KQL from natural language
- [ ] Read-only guardrails are working

## 📞 Support

For issues or questions:

1. Check [TESTING.md](TESTING.md) for troubleshooting steps
2. Review [SETUP.md](SETUP.md) for configuration details
3. Consult [MCP_SETUP.md](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md) for integration info
4. Open an issue in this repository with diagnostic information

---

**Configuration complete?** Start querying: `@adx-query-agent Show me all my clusters`
