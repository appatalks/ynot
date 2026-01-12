# ✅ ADX Query Agent - Quick Setup Checklist

Use this checklist to get your `@adx-query-agent` working with GitHub Copilot.

## Setup Steps (5-10 minutes)

### ☑️ Step 1: Verify Prerequisites

- [ ] I have an active GitHub Copilot subscription
- [ ] I have access to Azure Data Explorer clusters
- [ ] Azure CLI is installed (`az --version`)
- [ ] Python 3.8+ is installed (`python --version`)

### ☑️ Step 2: Authenticate with Azure

```bash
az login --use-device-code
```

- [ ] Authentication completed successfully
- [ ] Can see my account: `az account show`

### ☑️ Step 3: Install Python Dependencies

```bash
cd azure-mcp-data-explorer-deployer
pip install -r requirements.txt
```

- [ ] `azure-kusto-data` installed
- [ ] `azure-identity` installed
- [ ] No error messages

### ☑️ Step 4: Configure Environment

```bash
cd azure-mcp-data-explorer-deployer
cp .env.template .env
```

Edit `.env` and set:
```bash
ADX_CLUSTER_URL=https://<yourcluster>.<region>.kusto.windows.net
ADX_DATABASE=<your-database-name>
```

- [ ] `.env` file created
- [ ] `ADX_CLUSTER_URL` set to my cluster
- [ ] `ADX_DATABASE` set (optional)

**Don't know your cluster URL?** Discover it:
```bash
./run.sh --discover-clusters
```

### ☑️ Step 5: Test Connection

```bash
cd azure-mcp-data-explorer-deployer
./run.sh --databases
```

- [ ] Command runs successfully
- [ ] I can see my databases listed
- [ ] No authentication errors

### ☑️ Step 6: Verify Agent File

- [ ] File exists: `.github/agents/adx-query-agent.md`
- [ ] File starts with `---` (YAML frontmatter)
- [ ] `name: adx-query-agent` is present
- [ ] File ends without syntax errors

### ☑️ Step 7: Test in GitHub Copilot

1. Open GitHub Copilot Chat (`Ctrl+Shift+I` or `Cmd+Shift+I`)
2. Type `@` and look for `adx-query-agent` in autocomplete

- [ ] Agent appears in autocomplete menu
- [ ] Clicking it shows agent description

If agent doesn't appear:
- [ ] Reload VS Code: `Ctrl+Shift+P` → "Developer: Reload Window"
- [ ] Check file location again
- [ ] Verify YAML frontmatter syntax

### ☑️ Step 8: Test Agent Responses

Try each command in Copilot Chat:

```
@adx-query-agent Hello, are you working?
```
- [ ] Agent responds with introduction

```
@adx-query-agent Show me all my Azure Data Explorer clusters
```
- [ ] Agent attempts to discover clusters
- [ ] Shows results or provides guidance

```
@adx-query-agent List databases in my cluster
```
- [ ] Agent lists databases
- [ ] Results match what I saw in Step 5

```
@adx-query-agent Generate a KQL query to get the last 10 rows from a table
```
- [ ] Agent generates: `TableName | take 10`
- [ ] Explanation is clear and educational

## 🎉 Success Criteria

Your agent is working if:

- [✅] All steps above are checked
- [✅] Agent responds to queries in Copilot Chat
- [✅] Agent can generate valid KQL queries
- [✅] Agent can execute operations via terminal commands
- [✅] Agent provides helpful explanations

## 📖 Next Steps

Now that your agent is working:

1. **Learn more**: Read [QUICKSTART.md](QUICKSTART.md) for common use cases
2. **Deep dive**: Check [SETUP.md](SETUP.md) for advanced configuration
3. **Troubleshoot**: See [TESTING.md](TESTING.md) if issues arise
4. **Customize**: Edit [adx-query-agent.md](adx-query-agent.md) to add your patterns

## 🐛 Quick Troubleshooting

### Issue: Agent not found
**Fix**: Reload VS Code window
```
Ctrl+Shift+P → "Developer: Reload Window"
```

### Issue: Authentication error
**Fix**: Re-authenticate
```bash
az login --use-device-code
```

### Issue: Can't connect to cluster
**Fix**: Verify cluster URL
```bash
cd azure-mcp-data-explorer-deployer
./run.sh --discover-clusters
# Update .env with correct URL
```

### Issue: Scripts don't work
**Fix**: Reinstall dependencies
```bash
cd azure-mcp-data-explorer-deployer
pip install --upgrade -r requirements.txt
chmod +x run.sh
```

## 📞 Get Help

If you're stuck:

1. Review [TESTING.md](TESTING.md) - comprehensive troubleshooting guide
2. Check [SETUP.md](SETUP.md) - detailed setup instructions
3. See [CONFIGURATION.md](CONFIGURATION.md) - architecture and flow explanation

## 🎯 Try These Examples

Once everything works, try these with your agent:

```
@adx-query-agent Sample 5 rows from the [YourTableName] table
```

```
@adx-query-agent Query errors from the Logs table in the past hour
```

```
@adx-query-agent What's the schema of the Events table?
```

```
@adx-query-agent Count records by severity in the last 24 hours
```

```
@adx-query-agent Create a time series query for the Metrics table
```

---

**All done?** 🎊 Your Azure Data Explorer agent is ready to use!

Start exploring: `@adx-query-agent Show me all my databases`
