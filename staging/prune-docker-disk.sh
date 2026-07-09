#!/usr/bin/env bash
# Reclaim Docker build cache and unused images on small EC2 volumes.
set -euo pipefail

MIN_FREE_MB="${MIN_FREE_MB:-2048}"

free_mb() {
  df -Pm /var/lib/docker 2>/dev/null | awk 'NR==2 {print $4}' || df -Pm / | awk 'NR==2 {print $4}'
}

echo "==> disk before prune"
df -h / /var/lib/docker 2>/dev/null || df -h /
docker system df 2>/dev/null || true

before="$(free_mb)"
echo "==> free space: ${before} MB"

echo "==> prune build cache"
docker builder prune -af 2>/dev/null || true

echo "==> prune dangling images"
docker image prune -f 2>/dev/null || true

if [[ "$(free_mb)" -lt "$MIN_FREE_MB" ]]; then
  echo "==> still low on space (${MIN_FREE_MB} MB target) — removing unused images"
  docker image prune -a -f 2>/dev/null || true
fi

after="$(free_mb)"
echo "==> free space after prune: ${after} MB (was ${before} MB)"
df -h / /var/lib/docker 2>/dev/null || df -h /

if [[ "$after" -lt "$MIN_FREE_MB" ]]; then
  echo "ERROR: less than ${MIN_FREE_MB} MB free after docker prune." >&2
  echo "Free host disk (logs, apt cache) or expand the EBS volume, then retry." >&2
  exit 1
fi
