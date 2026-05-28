#!/usr/bin/env bash
# MT staging EC2 is Windows Server (mt5manager is Windows-only).
set -euo pipefail

cat <<'EOF' >&2
deploy-mt-ec2.sh is not used on the MT host (Windows Server).

On the MT EC2 via SSM PowerShell:

  aws ssm start-session --target <mt-instance-id> --region ap-southeast-3

  cd C:\esafx\mt-bridge-service
  copy .env.staging into this folder, then:
  .\deploy\ec2-deploy.ps1

See deploy/staging/README.md and mt-bridge-service/README.md.
EOF
exit 1
