# ad-user-provisioning-lab

Project by Jack Lai

I built a small Windows-style user directory that runs on my own computer because I wanted a safe place to test my account scripts before pointing them at anything that matters. Microsoft's version (Active Directory) needs a Windows Server licence and a lot of setup, so I used Samba instead. Samba is free software that does the same job: it keeps the list of users, groups and passwords, and Windows computers can sign in to it.

## What it does

- **Creates users, groups and departments from a spreadsheet.** You list people in a CSV file (a plain text table you can open in Excel). The scripts create the folders (OUs), groups and accounts, and put each person in the groups they need for access.
- **Resets passwords.** Each new or reset password is random and must be changed at the next sign-in.
- **Disables people who have left.** Their account stops working but is not deleted, so it can be turned back on if needed.
- **Reports problem accounts.** One report lists accounts that are locked out after wrong passwords, and accounts that have not signed in for a long time (90 days by default) or never signed in.
- **Helps with sign-in problems.** `docs/troubleshooting.md` covers the common causes: wrong name format, lockouts, disabled accounts, password rules, clock differences and missing groups.

## How to use it

You need Docker Desktop and bash (macOS and Linux) or PowerShell 7 (Windows, macOS and Linux).

1. Copy the settings file and set your own admin password:
   ```bash
   cp lab/.env.example lab/.env
   # open lab/.env and change SAMBA_ADMIN_PASSWORD
   ```
2. Start the directory. The first start takes a few minutes while it creates the domain:
   ```bash
   docker compose -f lab/docker-compose.yml up -d --build
   bash scripts/bash/wait-for-dc.sh
   ```
3. Create the users and groups from the example file:
   ```bash
   bash scripts/bash/sync-users.sh examples/users.example.csv
   ```
   The new passwords are written to `out/new-passwords.txt`. Only you can read that file, and git ignores it.
4. Day-to-day tasks:
   ```bash
   bash scripts/bash/reset-password.sh jordan.lee
   bash scripts/bash/disable-user.sh alex.kim
   bash scripts/bash/unlock-user.sh jordan.lee
   bash scripts/bash/stale-report.sh --days 90
   ```
   PowerShell has the same scripts for users, passwords and disabling: `scripts/powershell/Sync-LabUsers.ps1`, `Reset-LabPassword.ps1` and `Disable-LabUser.ps1`.
5. Stop the lab when you are done. This keeps the data, so you can start it again later:
   ```bash
   docker compose -f lab/docker-compose.yml down
   ```

## The CSV format

```
username,given_name,surname,ou,groups
jordan.lee,Jordan,Lee,Staff,Finance;Printers
```

- `username`: lower case, starts with a letter, up to 20 characters (letters, digits, `.`, `_` and `-`).
- `ou`: the folder the user goes in. Leave it blank for the default Users folder.
- `groups`: group names separated by `;`. Missing groups are created.

Running the sync again is safe. Users and groups that exist are left alone, and only missing memberships are added.

## Technical details

**Domain controller.** `lab/Dockerfile` builds an Ubuntu 24.04 image with Samba. `lab/dc/entrypoint.sh` creates the domain on the first start (`samba-tool domain provision`) and then runs Samba in the foreground. The domain data lives in Docker volumes, so it survives restarts. The lab turns on simple LDAP binds, which the scripts need, and sets a lockout after 5 wrong passwords. Those two settings are for the lab only.

**Scripts.** Each script runs `samba-tool` and `ldapsearch` inside the `dc` container with `docker compose exec`, so the host needs no Samba install. Shared code is in `scripts/bash/lib.sh` and `scripts/powershell/LabCommon.ps1`. The stale and locked-out report reads an LDAP dump, works out each account's last sign-in from `lastLogonTimestamp` (Windows stores it as 100-nanosecond ticks since 1601), and reads `lockoutTime` and the disabled bit in `userAccountControl`.

**Tests.**
- `tests/bash/test-stale-report.sh` runs the report on a made-up LDAP dump with fixed sign-in times. It needs no Docker.
- `tests/integration/test-bash.sh` runs against the live domain. It syncs a CSV, checks that a second run creates nothing, resets a password, locks an account with 8 wrong passwords and checks that the report lists it, unlocks it, and disables another account.
- `tests/powershell/Lab.Tests.ps1` (Pester 5) does the same checks for the PowerShell scripts.

**CI.** `.github/workflows/lab-ci.yml` runs shellcheck, the offline test, and then builds the real container on GitHub, creates a random admin password for that run, and runs both integration suites. The container is removed at the end of the run.

**Layout**

| Path | What is in it |
| --- | --- |
| `lab/` | Dockerfile, entrypoint, Compose file, `.env.example` |
| `scripts/bash/` | sync, reset, disable, unlock, stale report, wait-for-dc |
| `scripts/powershell/` | sync, reset, disable (PowerShell 7) |
| `tests/` | offline and live tests for both script sets |
| `examples/users.example.csv` | sample user file with made-up names |
| `docs/troubleshooting.md` | sign-in problems and fixes |

## Limitations

- This is a lab, not a production server. It runs one domain controller with no backup, and the simple LDAP binds are turned on.
- I have only tested the scripts against Samba. I have not joined a real Windows computer to the lab.
- The reset and create scripts pass the new password to `samba-tool` as a command argument. That is fine inside a throwaway container, but it would not be acceptable on a shared machine.

## Test results

The last CI run passed every job:

- Offline stale-report test: 8 of 8 checks.
- Bash scripts against the live domain: 7 of 7 checks.
- PowerShell scripts against the live domain (Pester): 5 of 5 tests.
- Shellcheck on all shell scripts: clean.
