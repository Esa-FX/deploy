#!/usr/bin/env bash
# Clone/fetch main + staging for each repo, then upsert markdown + coverage into Docmost.
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-3}"
ROOT="${ESAFX_ROOT:-/opt/esafx}"
SRC="${DOCMOST_SRC:-/var/lib/docmost-src}"
STATE="${DOCMOST_STATE:-/var/lib/docmost-sync/state.json}"
CONFIG="${DOCMOST_CONFIG:-$ROOT/deploy/docmost/repos.yml}"
SECRET_ID="${DOCMOST_BOT_SECRET:-esafx/production/docmost/bot}"
CLONE_SECRET="${GITHUB_CLONE_SECRET:-esafx/production/github-clone}"

mkdir -p "$SRC" "$(dirname "$STATE")"

GITHUB_TOKEN="$(aws secretsmanager get-secret-value --secret-id "$CLONE_SECRET" --region "$REGION" --query SecretString --output text)"
export BOT_JSON
BOT_JSON="$(aws secretsmanager get-secret-value --secret-id "$SECRET_ID" --region "$REGION" --query SecretString --output text)"
# Do not eval a heredoc inside double quotes — bash treats " in the Python as
# closing the outer quote (unexpected EOF at end of file).
export DOCMOST_URL DOCMOST_EMAIL DOCMOST_PASSWORD
DOCMOST_URL="$(python3 -c 'import json,os; print(json.loads(os.environ["BOT_JSON"]).get("url") or "https://wiki.esandardev.com")')"
DOCMOST_EMAIL="$(python3 -c 'import json,os; print(json.loads(os.environ["BOT_JSON"])["email"])')"
DOCMOST_PASSWORD="$(python3 -c 'import json,os; print(json.loads(os.environ["BOT_JSON"])["password"])')"

clone_or_fetch() {
  local name="$1"
  local branch="$2"
  local dest="$SRC/$name/$branch"
  local url="https://x-access-token:${GITHUB_TOKEN}@github.com/Esa-FX/${name}.git"
  mkdir -p "$SRC/$name"
  if git ls-remote --heads "$url" "$branch" | grep -q .; then
    if [[ -d "$dest/.git" ]]; then
      git -C "$dest" remote set-url origin "$url"
      git -C "$dest" fetch --depth 1 origin "$branch"
      git -C "$dest" checkout -f "FETCH_HEAD"
    else
      rm -rf "$dest"
      git clone --branch "$branch" --depth 1 "$url" "$dest"
    fi
    git -C "$dest" remote set-url origin "https://github.com/Esa-FX/${name}.git"
    git -C "$dest" rev-parse HEAD > "$dest/HEAD_SHA"
  else
    echo "WARN: $name has no origin/$branch" >&2
    rm -rf "$dest"
    mkdir -p "$dest"
    echo MISSING > "$dest/HEAD_SHA"
  fi
}

export DOCMOST_CONFIG="$CONFIG"
export DOCMOST_SYNC_DIR="$ROOT/deploy/docmost/sync"
mapfile -t REPOS < <(python3 -c 'import os,sys; from pathlib import Path; sys.path.insert(0, os.environ["DOCMOST_SYNC_DIR"]); from sync_docs import load_repos_yml; print("\n".join(load_repos_yml(Path(os.environ["DOCMOST_CONFIG"])).get("repos") or []))')

for repo in "${REPOS[@]}"; do
  echo "==> fetch $repo main+staging"
  clone_or_fetch "$repo" "main" || echo "WARN: skip main $repo" >&2
  clone_or_fetch "$repo" "staging" || echo "WARN: skip staging $repo" >&2
done

ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
STATE_BUCKET="${DOCMOST_STATE_BUCKET:-esafx-production-docmost-sync-${ACCOUNT}}"
aws s3 cp "s3://${STATE_BUCKET}/state.json" "$STATE" --region "$REGION" || true

unset GITHUB_TOKEN BOT_JSON
python3 "$ROOT/deploy/docmost/sync/sync_docs.py" \
  --config "$CONFIG" \
  --src-root "$SRC" \
  --state "$STATE"
aws s3 cp "$STATE" "s3://${STATE_BUCKET}/state.json" --region "$REGION" || echo "WARN: state upload failed" >&2
unset DOCMOST_PASSWORD
