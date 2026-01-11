#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi

. .venv/bin/activate
python -m pip install --upgrade pip >/dev/null
pip install -r requirements.txt >/dev/null

set -a
if [[ -f .env ]]; then
  . ./.env
else
  echo "Missing .env. Create it from .env.template" >&2
  exit 1
fi
set +a

python adx_query.py "$@"
