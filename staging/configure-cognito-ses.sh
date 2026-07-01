#!/usr/bin/env bash
# Wire Cognito user-pool email (forgot-password codes, invites) through Amazon SES.
#
# Prerequisites:
#   - AWS CLI configured for ap-southeast-3
#   - Route53 hosted zone for the sender domain
#   - SES domain identity verified (DKIM + domain status SUCCESS)
#
# Usage:
#   DOMAIN=esandardev.com \
#   USER_POOL_ID=ap-southeast-3_xxx \
#   FROM_ADDRESS=noreply@esandardev.com \
#   ./deploy/staging/configure-cognito-ses.sh

set -euo pipefail

REGION="${AWS_REGION:-ap-southeast-3}"
DOMAIN="${DOMAIN:-esandardev.com}"
USER_POOL_ID="${USER_POOL_ID:-ap-southeast-3_diSA1PdqG}"
FROM_ADDRESS="${FROM_ADDRESS:-noreply@${DOMAIN}}"
REPLY_TO="${REPLY_TO:-support@${DOMAIN}}"

echo "Checking SES identity for ${DOMAIN}..."
STATUS=$(aws sesv2 get-email-identity \
  --email-identity "$DOMAIN" \
  --region "$REGION" \
  --query 'VerifiedForSendingStatus' \
  --output text)

if [[ "$STATUS" != "True" ]]; then
  echo "ERROR: ${DOMAIN} is not verified for sending in SES (${STATUS})."
  echo "Add DKIM CNAME records from:"
  aws sesv2 get-email-identity --email-identity "$DOMAIN" --region "$REGION" \
    --query 'DkimAttributes.Tokens' --output text
  exit 1
fi

echo "Updating Cognito pool ${USER_POOL_ID} to send via SES (${FROM_ADDRESS})..."
aws cognito-idp update-user-pool \
  --user-pool-id "$USER_POOL_ID" \
  --region "$REGION" \
  --email-configuration "EmailSendingAccount=DEVELOPER,SourceArn=arn:aws:ses:${REGION}:$(aws sts get-caller-identity --query Account --output text):identity/${DOMAIN},From=${FROM_ADDRESS},ReplyToEmailAddress=${REPLY_TO}"

echo "Done. Test forgot-password from Hosted UI or:"
echo "  aws cognito-idp forgot-password --client-id <app-client-id> --username <email> --region ${REGION}"
