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
eval "$(python3 - <<'PY'
import json, os, shlex
cfg = json.loads(os.environ["BOT_JSON"])
url = cfg.get("url") or "https://wiki.esandardev.com"
print("export DOCMOST_URL=" + shlex.quote(url))
print("export DOCMOST_EMAIL=" + shlex.quote(cfg["email"]))
print("export DOCMOST_PASSWORD=" + shlex.quote(cfg["password"]))
PY
)"

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

mapfile -t REPOS < <(python3 - <<PY
from pathlib import Path
import sys
sys.path.insert(0, "${ROOT}/deploy/docmost/sync")
from sync_docs import load_repos_yml
print("\\n".join(load_repos_yml(Path("${CONFIG}")).get("repos") or []))
PY
)"

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
