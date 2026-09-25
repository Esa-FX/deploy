# Ops handover 2026-09-25

The EsaFX bots left open work. This folder is the one place to run it from your Windows PC. Nothing here talks to AWS until **you** run a script.

Run scripts in PowerShell 5.1 from this folder, with AWS CLI `--profile default --region ap-southeast-3`. Linux work goes through SSM. Host clocks are UTC. Scripts print modes, counts, and names — never secret values. Each mutating script captures state first, asks `YES`, then has a rollback path.

## What to run first

**1. Run p47-checks.ps1 first.** It only reads prod identity logs. You find out whether today's password-reset lockout work actually ran (or you see `not exercised`). Do this before you restart CRM, change ACLs, or wipe staging QA users.

**2. Then the CRM disk/pool pair, in this order:** `crm-api-logrotate.ps1` then a **recreate** if you want rotation live. `crm-api-restart.ps1` is a process restart for the pool stall; it does **not** apply log rotation. If the API is wedged now, restart first and come back to logrotate.

**3. Then lock files:** `windows-acl.ps1` (MT host, the five `.env*` files only — not `C:\`) and `linux-chmod.ps1` (seven env/password files + voip settings/CDR dir).

**4. Staging cleanup last.** `staging-cleanup.ps1` deletes QA users and secrets and rolls identity back to #48. Confirm every step. Do not run it until you no longer need those QA accounts.

Leave the prerestart log dumps and CloudTrail exports until the incidents are closed (see BACKLOG).

## Scripts

| Script | What it does | Host |
|--------|--------------|------|
| `p47-checks.ps1` | Read-only counts since `2026-09-25T09:37:03Z` for the four lockout/sign-out/`AccessDenied` strings, plus reset-password request counts (`not exercised` if zero) | core `i-0230b88ebf9b7adea`, container `esafx-identity` |
| `crm-api-logrotate.ps1` | json-file rotation on crm-api compose (`10m` × 3). Next recreate. | CRM `i-06c9b4647a1fc8ee8` |
| `crm-api-restart.ps1` | Health + `PoolTimeout` before/after, then `docker restart esafx-crm-api` | CRM `i-06c9b4647a1fc8ee8` |
| `windows-acl.ps1` | ACL on `.env*` under `C:\esafx\mt-bridge-service` only. Emergency C:\ dump: `C:\esafx-acl-before-prod-20260925.txt` | MT `i-0e81a8ed0002d028e` |
| `linux-chmod.ps1` | `600`/`640`/`750` on the seven files + voip settings | core, CRM, voip `i-081933f9f6a99b067` |
| `staging-cleanup.ps1` | Delete `qa-newuser` + `qa-newuser2-staging` (Cognito pool `ap-southeast-3_diSA1PdqG` + identity DB), revert identity to `ed9b5e8` / `esafx-identity:rollback-stg-ed9b5e8-20260925-1520`, schedule-delete QA secrets | staging app `i-06e3745274ed0fac4` |

```powershell
cd <clone>\ops\handover-2026-09-25
.\p47-checks.ps1
```

Captures land in `captures/` (gitignored). Open `BACKLOG.md` for everything that is not a script.

## Do not do from this agent

No AWS calls. No prod/staging apply. No `icacls C:\` except the documented emergency restore. No delete of `/root/crm-api-prerestart-20260925.log` or CloudTrail exports until you close those incidents.
