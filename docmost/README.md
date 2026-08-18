# Docmost (staff wiki) — production

Self-hosted [Docmost](https://github.com/docmost/docmost) Community. Official image only — no fork, no custom HTTP server.

**URL:** `https://wiki.esandardev.com`

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

- Fetch **main** and **staging** for every repo in `repos.yml`
- `docs/**/*.md` + root `README.md`
- Per-repo Coverage table + copies under `staging/` and `main/`
- Space `Esa-FX coverage` rolls up counts
- Daily **00:00 Asia/Jakarta**

## Ship order

1. Merge this `deploy` change to **`main`**.
2. `cd deploy/production/terraform-docmost && terraform init && terraform apply`
3. `bash deploy/production/ssm-send-docmost.sh`
4. Open `https://wiki.esandardev.com` → setup → update bot secret.
5. `systemctl start docmost-sync.service` once.
