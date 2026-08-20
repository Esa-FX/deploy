# Production Docmost EC2 + ALB host rule

Dedicated wiki is **production**: `https://wiki.esandardev.com` → Docmost.
Hover graph: `https://graph.esandardev.com` → nginx :8080 on the same EC2.

Content still compares **staging vs main** git branches (coverage flags). Infra is not a staging stack.

Isolated terraform state from `deploy/production/terraform` (core VPC). Data sources attach to existing prod VPC + ALB.

```bash
cd deploy/production/terraform-docmost
terraform init
terraform plan
terraform apply
```

Then: `bash deploy/production/ssm-send-docmost.sh`
