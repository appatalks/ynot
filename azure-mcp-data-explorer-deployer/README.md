## ADX/Kusto cached device-code auth template (Codespaces-friendly)

This folder is meant to be copied into another repo.

For Copilot-focused setup guidance, see [copilot-instructions.md](copilot-instructions.md).

For MCP (Model Context Protocol) integration (ADX MCP server, Azure MCP server), see [MCP_SETUP.md](MCP_SETUP.md).

This template is **read-only by default**. Any KQL that looks like a management command (starts with `.`) or common write/alter operation is blocked unless you explicitly opt in with `--allow-admin`.

### What you get
- `adx_client.py`: ADX client + auth helper
- `adx_query.py`: small CLI that lists databases/tables and samples rows
- `.env.template`: configuration template
- `run.sh`: convenience wrapper that creates venv, installs deps, and runs the CLI

### Why you were prompted repeatedly before
In a Codespace, each `python ...` command is a **new process**. If you only cache tokens in memory, the cache is lost between runs.

This template avoids repeated prompts by using **both**:
- A persistent MSAL token cache (stored under `~/.IdentityService/`)
- A persisted `AuthenticationRecord` (stored at `~/.azure/adx_auth_record.json` by default)

Together, those usually allow **silent token acquisition** across runs.

### Setup
1) Create a `.env` file:
```bash
cp .env.template .env
```
Edit `.env` and set:
- `ADX_CLUSTER_URL`
- `ADX_DATABASE` (optional if you only list databases)

2) Run the helper:
```bash
./run.sh --databases
./run.sh --tables
./run.sh --sample "hello-world" --limit 2
```

### Don’t know your cluster URL?

If you have Azure RBAC visibility (e.g., Reader) to ADX resources, you can discover clusters via Azure CLI:

```bash
./run.sh --discover-clusters
```

This uses ARM discovery (`az kusto cluster list`) and may require `az login`.

### Run arbitrary KQL (read-only)

```bash
./run.sh --kql "MyTable | take 10"
```

If the query looks like a management/write operation, it will be refused unless you opt in.

### Opt-in: admin/write operations

Use this only when you intentionally need to run management commands (e.g. `.show ...`) or write/alter operations:

```bash
./run.sh --allow-admin --kql ".show databases"
```

### First-run authentication
On first run (or when cache expires), you will see a message like:
- URL: `https://microsoft.com/devicelogin`
- Code: `ABCD1234`

Open the URL in your browser, enter the code, and finish sign-in.

After that, subsequent runs should **not** re-prompt unless:
- You delete `~/.azure/adx_auth_record.json` or `~/.IdentityService/*`
- The refresh token expires / conditional access changes
- You run as a different OS user

### Notes for Codespaces
- `.env` should not be committed (contains environment-specific info).
- This template sets `ADX_ALLOW_UNENCRYPTED_CACHE=true` by default because Linux containers typically lack keychain/libsecret.

### Auth preference
- By default, if a cached device-code record/cache exists, the helper will use it and skip Azure CLI auth attempts.
- To prefer Azure CLI when you have `az login` working, set `ADX_TRY_AZURE_CLI_FIRST=true`.

### Security
- Do NOT commit `~/.azure/adx_auth_record.json` or anything under `~/.IdentityService/`.
- Do NOT share device codes.
