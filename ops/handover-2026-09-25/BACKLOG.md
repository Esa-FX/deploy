# EsaFX handover backlog — 2026-09-25

Open items from the retired DevOps, Security, Backend, and QA bots, deduplicated.
Owner runs every AWS step on the Windows PC (`--profile default --region ap-southeast-3`, SSM for Linux). This cloud agent has no AWS access.

Owners: **cloud agent** = git/PR work; **owner's PC** = AWS/SSM/GitHub settings on the laptop; **owner decision** = product, vendor, legal, or money.

| ID | Item | Why (plain English) | Owner | Priority | Dependencies |
|----|------|---------------------|-------|----------|--------------|
| B01 | Windows ACL on `C:\esafx\mt-bridge-service` (5 `.env*` files only) | Those env files hold live MT secrets and are too easy to read; 2,259 folders inherit from `C:\`, so never lock the whole drive. Backup already on the host: `C:\esafx-acl-before-prod-20260925.txt`. Emergency undo for a C:\-wide change: `icacls C:\ /restore`. Script: `windows-acl.ps1`. | owner's PC | P1 | Confirm the 5 names on the MT host (`i-0e81a8ed0002d028e`) before apply |
| B02 | Linux chmod on voip settings files and 7 files | Same problem on Linux: env/password files and voip CDR dir are world-readable or 777. Seven files: identity/pii-vault/audit-log/crm/client `.env.production`, `trading_db_password`, voip `.env.production`. VoIP settings: extra voip `.env*` plus `/opt/esafx/data/voip-cdr`. Script: `linux-chmod.ps1`. | owner's PC | P1 | B14 (deploy scripts still reset 644/777) |
| B03 | crm-api has no docker log rotation (~200 MB json log) | One noisy service can fill the CRM disk. Add json-file `max-size=10m` `max-file=3`. Script: `crm-api-logrotate.ps1`. Takes effect on next **recreate**, not `docker restart`. | owner's PC | P1 | Recreate after patch (B04) |
| B04 | Recurring crm-api pool stall | CRM stops answering when the trading DB pool wedges. Safe restart + PoolTimeout counts: `crm-api-restart.ps1`. | owner's PC | P0 if stalled now, else P1 | Prefer B03 first if you want rotation to go live on the same recreate |
| B05 | Delete `/root/crm-api-prerestart-20260925.log` and the `-1454-` dump on `i-06c9b4647a1fc8ee8` | Old log copies were left for the pool investigation. Delete only after that root cause is closed so evidence is not lost. | owner's PC | P2 | B04 RCA closed |
| B06 | Delete CloudTrail exports when the incident closes | Extra trail dumps cost money and hold account activity. Drop them only after the incident write-up is done. | owner's PC | P2 | Incident closed (owner decision) |
| B07 | 14-day AWS log retention (needs monthly cost estimate) | Keeping logs forever is expensive; 14 days is usually enough. Do not apply until you have a monthly dollar figure and approve it. | owner's PC (estimate) + owner decision (approve) | P2 | Cost estimate from current CloudWatch ingest/storage; no AWS from this agent |
| B08 | MT5 DB vendor request | Trading features wait on the MT5 vendor (access/schema). We cannot finish that in git. | owner decision | P2 | Vendor reply |
| B09 | GitHub Actions dead since 21 Sep (billing) | CI stopped because the GitHub bill was not paid. Builds and checks will stay red until billing is fixed. | owner's PC | P1 | GitHub billing login |
| B10 | Make this deploy repo private | The repo is public today. Deploy scripts, host IDs, and infra layout should not be on the open internet. | owner's PC | P1 | Decide who keeps clone access |
| B11 | Separate staging and prod DBs | Staging still leans on prod trading (backoffice AccSum / PR 36). A staging bug can read or load prod data. | owner decision + cloud agent | P1 | Replacement staging trading DB; stops B19 if staging no longer holds client data |
| B12 | No CI on crm, client, deploy, and backoffice | Those repos ship with no safety net. After billing (B09), add the smallest workflow that runs tests/lint. | cloud agent | P2 | B09 |
| B13 | 11 PRs older than 30 days | Stale PRs confuse what is live. In this repo the old opens are #43, #36, #28, #27; the rest live in private service repos. Close, merge, or rewrite. | owner decision | P2 | B09 if CI is required to merge |
| B14 | Deploy scripts undo chmod 644 / voip-cdr 777 | `sync-crm-trading-db-env.sh`, `seed-staging-clients.sh`, `sync-backoffice-trading-db-env.sh`, `deploy-voip-ec2.sh`, `deploy-app-ec2.sh`, `prepare-whatsapp-gateway.sh` still force weak modes. Next deploy reverts B02. | cloud agent | P1 | Can land without waiting on B02 |
| B15 | WhatsApp provider question | Staging has WAHA, Maytapi, and neonize paths (PRs #27/#28). Pick one provider so we stop running two gateways. | owner decision | P2 | None |
| B16 | Sentry quota | Error tracking will start dropping events when the quota is gone. Confirm the plan and the cap. | owner decision | P2 | Sentry billing page |
| B17 | Remove CRM password sign-in next round | Staff should sign in with Cognito only. Password login is an extra hole. | owner decision + cloud agent (crm/identity) | P3 | After #47 prod checks (B18) look sane |
| B18 | #47 prod identity checks | After the password-reset lockout work, we still need log counts. If nobody reset a password, print `not exercised`. Script: `p47-checks.ps1`. | owner's PC | P0 | None (read-only) |
| B19 | Possible UU PDP notice if staging stored client data | Indonesian privacy law may require notice if real client data sat in staging. Legal call, not a script. | owner decision | P1 | B11 (did staging hold client personal data?) |
| B20 | Recording-sync rework | VoIP `ca2313a`, crm-service `cursor/crm-voip-probe-isolation` @ `7280311`, crm PR **#998**. These three ship **together** after a staging load test. Do not prod-deploy one piece. | owner's PC (load test) + cloud agent (those repos) | P2 | Staging load test pass; then one coordinated ship |
| B21 | Staging QA leftover users/secrets + identity rollback | QA users `qa-newuser` / `qa-newuser2-staging` in pool `diSA1PdqG`, identity DB rows, and QA secrets. Revert staging identity to #48 `ed9b5e8` (tag `esafx-identity:rollback-stg-ed9b5e8-20260925-1520`) on `i-06e3745274ed0fac4`. Script: `staging-cleanup.ps1`. | owner's PC | P1 | After B18 if you still need staging #47; otherwise cleanup is safe |
| B22 | Overnight valid-lots leaves trading master secret in `/tmp` | Prod cron wrote the DB password to a temp file. Fix already in [PR #61](https://github.com/Esa-FX/deploy/pull/61). | owner's PC (merge/deploy) | P1 | Review + merge #61 |
| B23 | Cognito wiki ALB terraform not applied | [PR #62](https://github.com/Esa-FX/deploy/pull/62) pins pool settings. Do not apply until `terraform plan` shows in-place + one import, zero destroys. | owner's PC | P2 | Local terraform state in both stacks |

## Done in this folder (scripts only — owner still runs them)

- B18 → `p47-checks.ps1`
- B21 → `staging-cleanup.ps1`
- B04 → `crm-api-restart.ps1`
- B03 → `crm-api-logrotate.ps1` (compose snippet also in `production/docker-compose.crm.yml`)
- B01 → `windows-acl.ps1`
- B02 → `linux-chmod.ps1`
