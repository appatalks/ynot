# Custom GitHub Copilot Agents

This directory contains custom GitHub Copilot agents that provide specialized expertise for working with Azure services.

## 📚 Documentation

- **[CHECKLIST.md](CHECKLIST.md)** - Quick setup checklist (start here!)
- **[QUICKSTART.md](QUICKSTART.md)** - Get started in 5 minutes
- **[SETUP.md](SETUP.md)** - Detailed setup and configuration guide
- **[TESTING.md](TESTING.md)** - Validation and troubleshooting
- **[CONFIGURATION.md](CONFIGURATION.md)** - Architecture and technical details

## Available Agents

### 🔍 Azure Data Explorer Query Agent (`adx-query-agent.md`)

A specialized AI assistant for Azure Data Explorer (ADX/Kusto) queries and data analysis.

**Purpose**: Provides an alternative to standard GitHub Copilot with deep expertise in:
- KQL (Kusto Query Language) syntax and patterns
- Azure Data Explorer operations and best practices
- Query optimization and performance
- Data exploration and schema discovery

**How to Use**:
```
@adx-query-agent Show me all my Azure Data Explorer clusters
@adx-query-agent Query errors from the Logs table in the past hour
@adx-query-agent What's the schema of the Events table?
@adx-query-agent Generate a KQL query to aggregate by time bins
```

**Features**:
- ✅ Automatic Azure resource discovery via MCP
- ✅ Generates optimized KQL queries
- ✅ Provides educational explanations
- ✅ Security-first (read-only by default)
- ✅ Validates queries before execution
- ✅ Follows KQL best practices

**Prerequisites**:
1. Authenticate with Azure: `az login --use-device-code`
2. Have access to Azure Data Explorer clusters
3. GitHub Copilot subscription

**Documentation**: See [MCP_SETUP.md](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md) for complete setup instructions.

---

## About Custom Agents

Custom agents are specialized AI assistants defined using Markdown files with YAML frontmatter. Each agent:
- Has specific expertise in a domain or technology
- Can access tools and MCP servers
- Provides focused, high-quality responses
- Can be invoked using `@agent-name` in GitHub Copilot Chat

### Adding New Agents

To create a new custom agent:

1. Create a new `.md` file in this directory
2. Add YAML frontmatter with agent configuration:
   ```yaml
   ---
   name: Agent Name
   description: What this agent does
   tools: ['*']
   ---
   ```
3. Add detailed instructions in Markdown below the frontmatter
4. Document the agent in this README

### Best Practices

- **Be specific**: Define clear boundaries for what the agent can and cannot do
- **Provide examples**: Include example queries and expected outputs
- **Include context**: Add relevant technical details and patterns
- **Set safety guidelines**: Specify what operations are allowed/disallowed
- **Test thoroughly**: Verify the agent works as expected before deployment

---

## Learn More

- [GitHub Custom Agents Documentation](https://docs.github.com/en/copilot/reference/custom-agents-configuration)
- [Azure MCP Server Integration](../../azure-mcp-data-explorer-deployer/MCP_SETUP.md)
- [Repository Main README](../../README.md)
