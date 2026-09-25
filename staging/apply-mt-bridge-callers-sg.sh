#!/usr/bin/env bash
# Staging-only: MT host on esafx-staging-mt-sg; callers SG on app host; narrow ALB :8003.
# Idempotent. --dry-run previews; --confirm required to mutate AWS.
set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-3}"
ENVIRONMENT="${ENVIRONMENT:-staging}"
if [[ "$ENVIRONMENT" == "production" ]]; then
  echo "Refusing to run against production; use production/terraform apply instead." >&2
  exit 1
fi

CRM_ENV_FILE="${CRM_ENV_FILE:-/opt/esafx/crm-service/.env.staging}"
# Override with APP_INSTANCE_ID / MT_INSTANCE_ID, or set tag filters (see runbook).
APP_INSTANCE_TAG_KEY="${APP_INSTANCE_TAG_KEY:-Tier}"
APP_INSTANCE_TAG_VALUE="${APP_INSTANCE_TAG_VALUE:-app-staging}"
MT_INSTANCE_TAG_KEY="${MT_INSTANCE_TAG_KEY:-Tier}"
MT_INSTANCE_TAG_VALUE="${MT_INSTANCE_TAG_VALUE:-mt-bridge}"

PREFIX="esafx-${ENVIRONMENT}"
CALLERS_SG_NAME="${PREFIX}-mt-bridge-callers-sg"
MT_SG_NAME="${PREFIX}-mt-sg"
APP_SG_NAME="${PREFIX}-app-sg"
ALB_SG_NAME="${PREFIX}-alb-sg"

DRY_RUN=false
CONFIRM=false

lookup_instance_id() {
  local tag_key="$1"
  local tag_value="$2"
  local id
  id="$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:${tag_key},Values=${tag_value}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)"
  if [[ -z "$id" || "$id" == "None" ]]; then
    echo "No running instance for tag ${tag_key}=${tag_value} (set APP_INSTANCE_ID / MT_INSTANCE_ID)" >&2
    return 1
  fi
  echo "$id"
}

usage() {
  echo "Usage: $0 [--dry-run] [--confirm]" >&2
  echo "  Instances: APP_INSTANCE_ID, MT_INSTANCE_ID, or tag filters APP_INSTANCE_TAG_* / MT_INSTANCE_TAG_*" >&2
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --confirm) CONFIRM=true ;;
    -h | --help) usage 0 ;;
    *) echo "Unknown option: $1" >&2; usage 2 ;;
  esac
  shift
done

aws_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] aws $*"
    return 0
  fi
  aws "$@"
}

sg_id_by_name() {
  local name="$1"
  aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=group-name,Values=${name}" \
    --query 'SecurityGroups[0].GroupId' --output text
}

sg_has_tcp_from_sg() {
  local sg="$1" port="$2" src="$3"
  python3 - "$sg" "$port" "$src" "$REGION" <<'PY'
import json, subprocess, sys
sg, port, src, region = sys.argv[1:5]
out = subprocess.check_output(
    ["aws", "ec2", "describe-security-groups", "--region", region, "--group-ids", sg],
    text=True,
)
data = json.loads(out)["SecurityGroups"][0]
port = int(port)
for perm in data.get("IpPermissions", []):
    if perm.get("FromPort") == port and perm.get("ToPort") == port:
        for pair in perm.get("UserIdGroupPairs", []):
            if pair.get("GroupId") == src:
                sys.exit(0)
sys.exit(1)
PY
}

rds_sg_from_env() {
  if [[ ! -f "$CRM_ENV_FILE" ]]; then
    echo "CRM env file not found: $CRM_ENV_FILE" >&2
    exit 1
  fi
  local db_host
  db_host="$(grep -E '^DB_HOST=' "$CRM_ENV_FILE" | head -1 | cut -d= -f2- | tr -d '\r')"
  [[ -n "$db_host" ]] || { echo "DB_HOST missing in $CRM_ENV_FILE" >&2; exit 1; }
  aws rds describe-db-instances --region "$REGION" \
    --query "DBInstances[?Endpoint.Address=='${db_host}'].VpcSecurityGroups[0].VpcSecurityGroupId | [0]" \
    --output text
}

instance_group_ids() {
  aws ec2 describe-instances --region "$REGION" --instance-ids "$1" \
    --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' --output text | tr '\t' ' '
}

ensure_sg() {
  local name="$1" desc="$2" vpc="$3"
  local existing
  existing="$(sg_id_by_name "$name")"
  if [[ -n "$existing" && "$existing" != "None" ]]; then
    echo "$existing"
    return 0
  fi
  if [[ "$DRY_RUN" == true ]]; then
    echo "[dry-run] would create security group $name"
    echo "sg-dry-run-placeholder"
    return 0
  fi
  aws ec2 create-security-group --region "$REGION" --group-name "$name" \
    --description "$desc" --vpc-id "$vpc" --query GroupId --output text
}

if [[ -z "${APP_INSTANCE_ID:-}" ]]; then
  APP_INSTANCE_ID="$(lookup_instance_id "$APP_INSTANCE_TAG_KEY" "$APP_INSTANCE_TAG_VALUE")"
fi
if [[ -z "${MT_INSTANCE_ID:-}" ]]; then
  MT_INSTANCE_ID="$(lookup_instance_id "$MT_INSTANCE_TAG_KEY" "$MT_INSTANCE_TAG_VALUE")"
fi

echo "Staging MT bridge SG plan"
echo "  App instance: $APP_INSTANCE_ID"
echo "  MT instance:  $MT_INSTANCE_ID"
echo "  CRM env:      $CRM_ENV_FILE"

RDS_SG="$(rds_sg_from_env)"
[[ -n "$RDS_SG" && "$RDS_SG" != "None" ]] || { echo "Could not resolve RDS SG from DB_HOST" >&2; exit 1; }
echo "  RDS security group: $RDS_SG"

if [[ "$CONFIRM" != true && "$DRY_RUN" != true ]]; then
  echo "Refusing to modify AWS without --confirm (preview with --dry-run)." >&2
  exit 1
fi

VPC_ID="$(aws ec2 describe-instances --region "$REGION" --instance-ids "$APP_INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].VpcId' --output text)"
APP_SG="$(sg_id_by_name "$APP_SG_NAME")"
ALB_SG="$(sg_id_by_name "$ALB_SG_NAME")"
CALLERS_SG="$(ensure_sg "$CALLERS_SG_NAME" "MT bridge callers (staging app host)" "$VPC_ID")"
MT_SG="$(ensure_sg "$MT_SG_NAME" "Windows MT bridge" "$VPC_ID")"

if [[ "$CALLERS_SG" != "sg-dry-run-placeholder" ]]; then
  APP_SGS="$(instance_group_ids "$APP_INSTANCE_ID")"
  if [[ " $APP_SGS " != *" $CALLERS_SG "* ]]; then
    read -r -a app_sg_list <<<"$APP_SGS"
    app_sg_list+=("$CALLERS_SG")
    aws_cmd ec2 modify-instance-attribute --region "$REGION" --instance-id "$APP_INSTANCE_ID" \
      --groups "${app_sg_list[@]}"
  else
    echo "Callers SG already on app instance"
  fi
fi

if [[ "$MT_SG" != "sg-dry-run-placeholder" ]]; then
  aws_cmd ec2 authorize-security-group-egress --region "$REGION" --group-id "$MT_SG" \
    --ip-permissions IpProtocol=-1,IpRanges='[{CidrIp=0.0.0.0/0}]' 2>/dev/null || true

  if ! sg_has_tcp_from_sg "$RDS_SG" 5432 "$MT_SG" 2>/dev/null; then
    aws_cmd ec2 authorize-security-group-ingress --region "$REGION" --group-id "$RDS_SG" \
      --protocol tcp --port 5432 --source-group "$MT_SG"
  else
    echo "RDS already allows 5432 from MT SG"
  fi

  if ! sg_has_tcp_from_sg "$MT_SG" 8003 "$CALLERS_SG" 2>/dev/null; then
    aws_cmd ec2 authorize-security-group-ingress --region "$REGION" --group-id "$MT_SG" \
      --protocol tcp --port 8003 --source-group "$CALLERS_SG"
  else
    echo "MT SG already allows 8003 from callers"
  fi

  MT_SGS="$(instance_group_ids "$MT_INSTANCE_ID")"
  if [[ " $MT_SGS " != *" $MT_SG "* ]]; then
    read -r -a mt_sg_list <<<"$MT_SGS"
    mt_sg_list+=("$MT_SG")
    aws_cmd ec2 modify-instance-attribute --region "$REGION" --instance-id "$MT_INSTANCE_ID" \
      --groups "${mt_sg_list[@]}"
    MT_SGS="$(instance_group_ids "$MT_INSTANCE_ID")"
  fi
  if [[ " $MT_SGS " == *" $APP_SG "* && " $MT_SGS " == *" $MT_SG "* ]]; then
    remaining=()
    for g in $MT_SGS; do
      [[ "$g" == "$APP_SG" ]] && continue
      remaining+=("$g")
    done
    aws_cmd ec2 modify-instance-attribute --region "$REGION" --instance-id "$MT_INSTANCE_ID" \
      --groups "${remaining[@]}"
  else
    echo "MT instance SG state OK or app-sg already detached"
  fi
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "[dry-run] would narrow ALB ingress on app-sg if 8000-8003 rule still present"
elif python3 - "$APP_SG" "$ALB_SG" "$REGION" <<'PY'
import json, subprocess, sys
app_sg, alb_sg, region = sys.argv[1:4]
out = subprocess.check_output(
    ["aws", "ec2", "describe-security-groups", "--region", region, "--group-ids", app_sg],
    text=True,
)
sg = json.loads(out)["SecurityGroups"][0]
for p in sg.get("IpPermissions", []):
    if p.get("FromPort") == 8000 and p.get("ToPort") == 8003:
        for u in p.get("UserIdGroupPairs", []):
            if u.get("GroupId") == alb_sg:
                sys.exit(0)
sys.exit(1)
PY
then
  aws_cmd ec2 revoke-security-group-ingress --region "$REGION" --group-id "$APP_SG" \
    --protocol tcp --port 8000-8003 --source-group "$ALB_SG"
  if ! python3 - "$APP_SG" "$ALB_SG" "$REGION" <<'PY'
import json, subprocess, sys
app_sg, alb_sg, region = sys.argv[1:4]
out = subprocess.check_output(
    ["aws", "ec2", "describe-security-groups", "--region", region, "--group-ids", app_sg],
    text=True,
)
sg = json.loads(out)["SecurityGroups"][0]
for p in sg.get("IpPermissions", []):
    if p.get("FromPort") == 8000 and p.get("ToPort") == 8002:
        for u in p.get("UserIdGroupPairs", []):
            if u.get("GroupId") == alb_sg:
                sys.exit(0)
sys.exit(1)
PY
  then
    aws_cmd ec2 authorize-security-group-ingress --region "$REGION" --group-id "$APP_SG" \
      --protocol tcp --port 8000-8002 --source-group "$ALB_SG"
  fi
else
  echo "ALB ingress on app-sg already excludes :8003 — skip"
fi

echo "Done."
