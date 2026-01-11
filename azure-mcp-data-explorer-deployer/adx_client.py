from __future__ import annotations

import datetime
import os
from typing import Any

from azure.identity import (
    AuthenticationRecord,
    AzureCliCredential,
    DefaultAzureCredential,
    DeviceCodeCredential,
    TokenCachePersistenceOptions,
)
from azure.kusto.data import KustoClient, KustoConnectionStringBuilder

KUSTO_SCOPE = "https://kusto.kusto.windows.net/.default"

# In-process cache (single Python run)
_CACHED_CREDENTIAL: Any | None = None


def _expand_user(path: str) -> str:
    return os.path.expanduser(path)


def _bool_env(name: str, default: bool = False) -> bool:
    raw = os.getenv(name)
    if raw is None:
        return default
    return raw.strip().lower() in {"1", "true", "yes", "y", "on"}


def _device_code_prompt(verification_uri: str, user_code: str, expires_on: datetime.datetime) -> None:
    print("To sign in, open the page below and enter the code:")
    print(f"  URL:  {verification_uri}")
    print(f"  Code: {user_code}")
    print(f"  Expires: {expires_on}")


def _identityservice_has_cache(cache_name: str) -> bool:
    identity_dir = _expand_user("~/.IdentityService")
    if not os.path.isdir(identity_dir):
        return False
    try:
        for entry in os.listdir(identity_dir):
            # MSAL cache files are typically like: <name>.nocae / <name>.bin / <name>.json
            if entry == cache_name or entry.startswith(cache_name + "."):
                return True
    except OSError:
        return False
    return False


def get_credential() -> Any:
    """Return a credential that typically prompts only once in Codespaces.

    Order:
    1) Azure CLI (no prompts) when `az login` is active in the container.
    2) Device Code with persistent token cache + persisted AuthenticationRecord.
    3) DefaultAzureCredential (managed identity / env vars) as last fallback.

    Why both cache + auth record?
    - The persistent token cache stores tokens across processes.
    - The AuthenticationRecord tells DeviceCodeCredential *which account* to use
      for silent token acquisition across runs.
    """

    global _CACHED_CREDENTIAL
    if _CACHED_CREDENTIAL is not None:
        return _CACHED_CREDENTIAL

    # Device code auth w/ persistence settings
    allow_unencrypted = _bool_env("ADX_ALLOW_UNENCRYPTED_CACHE", default=True)
    cache_name = os.getenv("ADX_TOKEN_CACHE_NAME", "adx_token_cache")
    auth_record_path = _expand_user(os.getenv("ADX_AUTH_RECORD_PATH", "~/.azure/adx_auth_record.json"))

    cache_opts = TokenCachePersistenceOptions(
        name=cache_name,
        allow_unencrypted_storage=allow_unencrypted,
    )

    auth_record: AuthenticationRecord | None = None
    if os.path.exists(auth_record_path):
        with open(auth_record_path, "r", encoding="utf-8") as f:
            auth_record = AuthenticationRecord.deserialize(f.read())

    has_device_cache = auth_record is not None or _identityservice_has_cache(cache_name)
    try_azure_cli_first = _bool_env("ADX_TRY_AZURE_CLI_FIRST", default=not has_device_cache)

    # Prefer cached device-code credential when we already have a cache/auth record.
    if has_device_cache and not try_azure_cli_first:
        cred = DeviceCodeCredential(
            prompt_callback=_device_code_prompt,
            cache_persistence_options=cache_opts,
            authentication_record=auth_record,
        )

        try:
            cred.get_token(KUSTO_SCOPE)
            _CACHED_CREDENTIAL = cred
            return cred
        except Exception:
            # Cache exists but might be expired/invalid; fall through to other options.
            pass

    # Optionally try Azure CLI auth (only if requested or no device cache exists)
    if try_azure_cli_first:
        try:
            cred = AzureCliCredential()
            cred.get_token(KUSTO_SCOPE)
            _CACHED_CREDENTIAL = cred
            return cred
        except Exception:
            pass

    cred = DeviceCodeCredential(
        prompt_callback=_device_code_prompt,
        cache_persistence_options=cache_opts,
        authentication_record=auth_record,
    )

    # If we don't have an auth record yet, or if refresh fails, authenticate interactively.
    try:
        if auth_record is None:
            raise RuntimeError("No cached authentication record")
        cred.get_token(KUSTO_SCOPE)
    except Exception:
        auth_record = cred.authenticate(scopes=[KUSTO_SCOPE])
        os.makedirs(os.path.dirname(auth_record_path), exist_ok=True)
        with open(auth_record_path, "w", encoding="utf-8") as f:
            f.write(auth_record.serialize())
        cred = DeviceCodeCredential(
            prompt_callback=_device_code_prompt,
            cache_persistence_options=cache_opts,
            authentication_record=auth_record,
        )
        cred.get_token(KUSTO_SCOPE)

    _CACHED_CREDENTIAL = cred
    return cred


def get_kusto_client(cluster_url: str) -> KustoClient:
    credential = get_credential()
    kcsb = KustoConnectionStringBuilder.with_azure_token_credential(cluster_url, credential)
    return KustoClient(kcsb)


def kql_table_ref(table_name: str) -> str:
    """Safely reference tables with special characters (e.g., `hello-world`)."""
    escaped = table_name.replace("'", "''")
    return f"['{escaped}']"
