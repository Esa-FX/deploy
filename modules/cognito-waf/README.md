# Cognito WAF module

Regional AWS WAF web ACL for **Cognito user pools** (login DoS / credential stuffing). No Google reCAPTCHA.

Cognito public APIs (`InitiateAuth`, `ForgotPassword`, …) go to `cognito-idp.*`, not CloudFront. Associate the ACL with the **user pool**, not the SPA distribution.

## Rules

| Priority | Rule | Action |
|----------|------|--------|
| 0 | AWS managed IP reputation | group defaults (block known bad IPs) |
| 10 | Global rate (all IPs) | Block at `rate_limit_global` / window |
| 20 | Per-IP rate | Block at `rate_limit_per_ip` / window |
| 30 | ForgotPassword / ConfirmForgotPassword / SignUp / ResendConfirmationCode per IP | Block at `rate_limit_sensitive_per_ip` |

No CAPTCHA action: Amplify custom login cannot render AWS WAF puzzles (`ForbiddenException` instead).

Do **not** attach `AWSManagedRulesATPRuleSet` — Cognito rejects that group.

## Future pools

One ACL per environment. Add the new pool ARN to `user_pool_arns` and apply. Do not reuse this staff-tuned ACL on a high-volume public **client** signup pool without raising SignUp limits.

## Cost

AWS WAF bills per web ACL, per rule, and per million requests (separate from Cognito).
