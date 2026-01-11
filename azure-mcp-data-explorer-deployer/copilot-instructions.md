## Copilot instructions (Azure Data Explorer / Kusto in Codespaces)

### Goal
Use this folder to run **production-safe, read-only** queries against an Azure Data Explorer (ADX/Kusto) cluster from a GitHub Codespace with cached authentication.

### What’s in this folder
- `adx_client.py`: Creates an ADX client with cached auth (Azure CLI preferred; device-code fallback with persistent cache + auth record).
- `adx_query.py`: CLI helper for listing databases/tables, sampling rows, and running KQL.
- `run.sh`: Creates a Python venv, installs deps, loads `.env`, then runs `adx_query.py`.
- `.env.template`: Environment variables to configure cluster/database and cache paths.

### Setup (Codespaces)
1) Create `.env`:
- Run `cp .env.template .env`
- Set `ADX_CLUSTER_URL` to your cluster URL.
- Set `ADX_DATABASE` for table queries (optional for `--databases`).

2) Run a read-only command:
- `./run.sh --databases`
- `./run.sh --tables`
- `./run.sh --sample "YourTable" --limit 2`

If the user doesn’t know the cluster URL but has Azure RBAC visibility to ADX resources, they can run:
- `./run.sh --discover-clusters`
(Uses `az kusto cluster list`; may require `az login`.)

3) First-run auth:
- If prompted, complete device-code sign-in at `https://microsoft.com/devicelogin`.
- After that, subsequent runs should be silent because the token cache and auth record are persisted under your home directory.

### Read-only guardrails
- By default, `adx_query.py --kql "..."` refuses to run management commands (KQL starting with `.`) and common write/alter verbs.
- To intentionally run admin/write operations, you **must** pass `--allow-admin`.

### Auth selection (CLI vs cached device-code)
- If a cached device-code auth record/token cache exists, this template **skips Azure CLI auth attempts** by default.
- If you want to prefer Azure CLI (when you *do* have `az login` working), set `ADX_TRY_AZURE_CLI_FIRST=true`.

Examples:
- Read-only: `./run.sh --kql "MyTable | take 10"`
- Admin (explicit opt-in): `./run.sh --allow-admin --kql ".show databases"`

### Safety + hygiene
- Never commit `.env`.
- Never commit `~/.azure/*.json` auth records or anything under `~/.IdentityService/`.
- Prefer least-privilege roles in production (e.g., Database Viewer).

### If something fails
- Verify `ADX_CLUSTER_URL` is correct and reachable.
- If auth loops, delete the local caches and re-auth:
  - `rm -f ~/.azure/adx_auth_record.json`
  - `rm -rf ~/.IdentityService/`
