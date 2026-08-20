# Docmost (staff wiki) — production

Self-hosted [Docmost](https://github.com/docmost/docmost) Community. Official image only — no fork, no custom HTTP server.

**URL:** `https://wiki.esandardev.com` (hover graph; admin Cognito)
**Docmost:** still on EC2 :3000, not on this hostname.

**Infra is production** (prod VPC, prod ALB, `esafx/production/docmost/*`, `esafx/production/github-clone`). Dedicated `t3.small`.

**Content** still pulls **both** git branches. Coverage flags: `staging only` / `main only` / `both (same)` / `both (diff)`. That is a page feature, not a second environment.

## Size

| Type | RAM | Verdict |
|------|-----|---------|
| t3.nano | 0.5 GiB | No |
| t3.micro | 1 GiB | No as all-in-one |
| **t3.small** | **2 GiB** | **Floor** |

## Cognito

Community has **no OIDC/SAML**. First visit: create workspace owner in Docmost. Then put `{email,password,url}` in `esafx/production/docmost/bot`.

Do **not** put passwords in git.

## Sync

- Fetch **main** and **staging** for `Esa-FX/wiki` only (`repos.yml`)
- `content/**/*.md` + root `README.md`
- Coverage table + copies under `staging/` and `main/`
- Interactive hover graph: `https://wiki.esandardev.com` (static files from `Esa-FX/wiki`, nginx :8080, CRM prod Cognito, role `admin`)
- Daily **00:00 Asia/Jakarta**

## Ship order

1. Merge this `deploy` change to **`main`**.
2. `cd deploy/production/terraform-docmost && terraform init && terraform apply`
3. `bash deploy/production/ssm-send-wiki-graph.sh`
4. Open `https://wiki.esandardev.com` → CRM prod Cognito (`custom:role=admin`).
