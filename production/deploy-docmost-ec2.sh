#!/usr/bin/env bash
# Bootstrap / refresh Docmost on the dedicated production wiki EC2.
set -euo pipefail

ROOT="${ESAFX_ROOT:-/opt/esafx}"
REGION="${AWS_REGION:-ap-southeast-3}"
BRANCH="${ESAFX_BRANCH:-main}"
COMPOSE_DIR="$ROOT/deploy/docmost"
SECRET_PREFIX="esafx/production/docmost"

sudo mkdir -p "$ROOT" /var/lib/docmost-src /var/lib/docmost-sync
sudo chmod 755 /var/lib/docmost-src /var/lib/docmost-sync

if ! command -v docker >/dev/null 2>&1; then
  echo "docker missing — instance user_data should have installed it" >&2
  exit 1
fi
if ! docker compose version >/dev/null 2>&1; then
  sudo mkdir -p /usr/libexec/docker/cli-plugins
  sudo curl -fsSL \
    "https://github.com/docker/compose/releases/download/v2.27.1/docker-compose-linux-x86_64" \
    -o /usr/libexec/docker/cli-plugins/docker-compose
  sudo chmod +x /usr/libexec/docker/cli-plugins/docker-compose
fi

clone_deploy() {
  local token
  token="$(aws secretsmanager get-secret-value --secret-id esafx/production/github-clone --region "$REGION" --query SecretString --output text)"
  local url="https://x-access-token:${token}@github.com/Esa-FX/deploy.git"
  if [[ -d "$ROOT/deploy/.git" ]]; then
    git -C "$ROOT/deploy" remote set-url origin "$url"
    git -C "$ROOT/deploy" fetch origin "$BRANCH"
    git -C "$ROOT/deploy" checkout "$BRANCH"
    git -C "$ROOT/deploy" reset --hard "origin/$BRANCH"
    git -C "$ROOT/deploy" remote set-url origin "https://github.com/Esa-FX/deploy.git"
  else
    sudo mkdir -p "$ROOT"
    git clone --branch "$BRANCH" --depth 1 "$url" "$ROOT/deploy"
    git -C "$ROOT/deploy" remote set-url origin "https://github.com/Esa-FX/deploy.git"
  fi
}

write_env() {
  local app_secret db_password
  app_secret="$(aws secretsmanager get-secret-value --secret-id "${SECRET_PREFIX}/app-secret" --region "$REGION" --query SecretString --output text)"
  db_password="$(aws secretsmanager get-secret-value --secret-id "${SECRET_PREFIX}/db-password" --region "$REGION" --query SecretString --output text)"
  umask 077
  cat > "$COMPOSE_DIR/.env" <<EOF
APP_URL=https://wiki.esandardev.com
APP_SECRET=${app_secret}
POSTGRES_PASSWORD=${db_password}
DOCMOST_IMAGE=docmost/docmost:v0.95.0
EOF
}

install_timer() {
  sudo cp "$COMPOSE_DIR/sync/docmost-sync.service" /etc/systemd/system/docmost-sync.service
  sudo cp "$COMPOSE_DIR/sync/docmost-sync.timer" /etc/systemd/system/docmost-sync.timer
  sudo chmod +x "$COMPOSE_DIR/sync/run.sh"
  sudo systemctl daemon-reload
  sudo systemctl enable --now docmost-sync.timer
}

clone_deploy
write_env
cd "$COMPOSE_DIR"
docker compose pull
docker compose up -d
install_timer
sleep 8
curl -sf "http://127.0.0.1:3000/api/health" && echo docmost-health-ok
