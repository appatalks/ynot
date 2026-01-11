#!/usr/bin/env bash
#
# Aggregate to ynot.
#   - Madness has no purpose. Or reason. But it may have a goal.
#     – Mr. Spock_
# -- AppaTalks
#
set -euo pipefail

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo "→ set GITHUB_TOKEN to your PAT first" >&2
  exit 1
fi

if (( $# < 2 )); then
  echo "Usage: $0 appatalks/ynot appatalks/foo [appatalks/bar …]" >&2
  exit 1
fi

TARGET="$1"; shift
TARGET_DIR="$(basename "$TARGET")"

echo "→ Cloning target repo $TARGET…"
git clone "https://x-access-token:${GITHUB_TOKEN}@github.com/${TARGET}.git" "$TARGET_DIR"
cd "$TARGET_DIR"

for SRC in "$@"; do
  NAME="$(basename "$SRC")"
  REMOTE="$NAME"
  URL="https://x-access-token:${GITHUB_TOKEN}@github.com/${SRC}.git"

  echo "→ Importing $SRC into folder '$NAME/'…"
  git remote add "$REMOTE" "$URL"
  git fetch "$REMOTE"

  # default-branch detection
  if git ls-remote --exit-code --heads "$REMOTE" main &>/dev/null; then
    BR=main
  else
    BR=master
  fi

  git subtree add --prefix="$NAME" "$REMOTE" "$BR"

  echo "→ Stripping .github from '$NAME/' if present…"
  git rm -r --ignore-unmatch "$NAME/.github"
  # only commit if there were staged changes
  if ! git diff --cached --quiet; then
    git commit -m "Remove .github directory from $NAME subtree"
  else
    echo "   (no .github folder to remove)"
    git reset --quiet HEAD
  fi
done

echo "→ Pushing everything back to origin…"
git push origin "$(git rev-parse --abbrev-ref HEAD)"
