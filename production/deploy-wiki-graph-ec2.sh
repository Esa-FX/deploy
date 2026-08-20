#!/usr/bin/env bash
# Clone Esa-FX/wiki and serve the hover graph on :8080 (nginx).
# ALB host graph.esandardev.com → this port. Docmost stays on :3000.
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-3}"
ROOT="/opt/esafx/wiki"
BRANCH="${ESAFX_WIKI_BRANCH:-main}"

clone_wiki() {
  local token
  token="$(aws secretsmanager get-secret-value --secret-id esafx/production/github-clone --region "$REGION" --query SecretString --output text)"
  local url="https://x-access-token:${token}@github.com/Esa-FX/wiki.git"
  sudo mkdir -p /opt/esafx
  if [[ -d "$ROOT/.git" ]]; then
    git -C "$ROOT" remote set-url origin "$url"
    git -C "$ROOT" fetch origin "$BRANCH"
    git -C "$ROOT" checkout "$BRANCH"
    git -C "$ROOT" reset --hard "origin/$BRANCH"
    git -C "$ROOT" remote set-url origin "https://github.com/Esa-FX/wiki.git"
  else
    sudo rm -rf "$ROOT"
    git clone --branch "$BRANCH" --depth 1 "$url" "$ROOT"
    git -C "$ROOT" remote set-url origin "https://github.com/Esa-FX/wiki.git"
  fi
}

run_nginx() {
  docker rm -f wiki-graph >/dev/null 2>&1 || true
  docker run -d --name wiki-graph --restart unless-stopped \
    -p 8080:80 \
    -v "$ROOT:/usr/share/nginx/html:ro" \
    nginx:1.27-alpine
}

clone_wiki
run_nginx
for _ in $(seq 1 20); do
  if curl -sf "http://127.0.0.1:8080/" >/dev/null; then
    echo wiki-graph-health-ok
    exit 0
  fi
  sleep 1
done
echo "wiki-graph health timeout" >&2
exit 1
