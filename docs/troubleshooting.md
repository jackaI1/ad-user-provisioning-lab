# Sign-in troubleshooting

These notes cover the sign-in problems I hit most often while testing the lab.
Commands run inside the lab's domain controller (the "dc" container). Shortcut used below:

```bash
DC="docker compose -f lab/docker-compose.yml exec -T dc"
```

## 1. "The user name or password is incorrect" but the password is right

- Check the name format. Use the plain user name (`jordan.lee`) or the full sign-in name (`jordan.lee@LAB.EXAMPLE`). The domain form is `LAB\jordan.lee`.
- Check whether the password was just reset. A reset password must be changed at the next sign-in, so the old one stops working right away.
- Check for a lockout (section 2).

## 2. "The account is locked out"

The lab locks an account for 30 minutes after 5 wrong passwords.

```bash
bash scripts/bash/stale-report.sh          # the "Locked out" list shows who is locked
bash scripts/bash/unlock-user.sh jordan.lee
```

If the lock keeps coming back, something is still sending the old password. Common causes are a saved password in a Windows credential store, a mapped drive, or a phone that still has the old password.

## 3. "The account has been disabled"

Disabled accounts are kept on purpose (nothing is deleted). Check the flag:

```bash
$DC samba-tool user show jordan.lee | grep userAccountControl
```

If the value has bit 2 set (514 instead of 512), the account is disabled. Enable it with `samba-tool user enable jordan.lee` inside the container.

## 4. "You must change your password" loop

The new password was refused because it did not meet the rules. Check the rules:

```bash
$DC samba-tool domain passwordsettings show
```

By default the password needs at least 7 characters and 3 of: upper case, lower case, digit, symbol. It also cannot contain the user name. `scripts/bash/reset-password.sh` always makes a password that meets these rules.

## 5. "The domain cannot be found" or "the server cannot be reached"

- The lab must be running: `docker compose -f lab/docker-compose.yml ps` should show `dc` as `running`.
- The first start takes a few minutes while the domain is created. Wait for `scripts/bash/wait-for-dc.sh` to print that it is answering.
- Check the logs: `docker compose -f lab/docker-compose.yml logs --tail 100 dc`.
- The name must be `dc.lab.example` (or `LAB.EXAMPLE` for the domain). Short names do not resolve outside the container.

## 6. Kerberos "clock skew" error

Kerberos (the sign-in protocol) refuses tickets when two clocks differ by more than 5 minutes. Compare the clocks:

```bash
date -u
$DC date -u
```

Restart Docker Desktop if the container clock has drifted after your computer slept.

## 7. A user can sign in but the wrong groups apply

Group membership is checked when the user signs in. Sign out and back in. Then confirm the membership:

```bash
$DC samba-tool user getgroups jordan.lee
```

If the group is missing, run `scripts/bash/sync-users.sh` again with the right CSV row. It only adds what is missing.

## 8. "Where is my new password?"

Passwords created by the scripts are written to `out/new-passwords.txt`. The file is readable only by you and is ignored by git. Keep it out of email and chat. Delete it when you no longer need it.
