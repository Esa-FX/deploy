#!/usr/bin/env bash
# Apply staging frontend S3 CORS for CRM + client buckets.
# Requires figo0703 (or admin) with s3:PutBucketCORS on these buckets.
set -euo pipefail

PROFILE="${AWS_PROFILE:-figo0703}"
REGION="${AWS_REGION:-ap-southeast-3}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORS_FILE="${SCRIPT_DIR}/frontend-buckets-cors.json"

BUCKETS=(
  "esafx-crm-frontend-staging-612524168745"
  "esafx-client-frontend-staging-612524168745"
)

if [[ ! -f "$CORS_FILE" ]]; then
  echo "Missing CORS file: $CORS_FILE" >&2
  exit 1
fi

for bucket in "${BUCKETS[@]}"; do
  echo "Putting CORS on s3://${bucket} (profile=${PROFILE}, region=${REGION})"
  aws s3api put-bucket-cors \
    --bucket "$bucket" \
    --cors-configuration "file://${CORS_FILE}" \
    --profile "$PROFILE" \
    --region "$REGION"
  echo "Current CORS for ${bucket}:"
  aws s3api get-bucket-cors \
    --bucket "$bucket" \
    --profile "$PROFILE" \
    --region "$REGION"
done

echo "Done."
