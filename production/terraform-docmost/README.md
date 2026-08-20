# Production Docmost EC2 + ALB host rule

Dedicated wiki is **production**: `https://wiki.esandardev.com` → hover graph (nginx :8080).
Docmost remains on the instance :3000 with no public hostname.

Content still compares **staging vs main** git branches (coverage flags). Infra is not a staging stack.

Isolated terraform state from `deploy/production/terraform` (core VPC). Data sources attach to existing prod VPC + ALB.

```bash
cd deploy/production/terraform-docmost
terraform init
terraform plan
terraform apply
```

Then: `bash deploy/production/ssm-send-docmost.sh`
