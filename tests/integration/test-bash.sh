#!/usr/bin/env bash
# Integration test: runs the bash scripts against the real Samba domain controller.
# The lab must be running (see the README). It only creates and changes ci.* accounts.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$here/../../scripts/bash"

LAB_OUT_DIR="$(mktemp -d)"
export LAB_OUT_DIR
trap 'rm -rf "$LAB_OUT_DIR"' EXIT
# shellcheck source=../../scripts/bash/lib.sh
source "$bin/lib.sh"
check_lab

pass=0
ok() { pass=$((pass + 1)); echo "ok - $1"; }
fail() { echo "not ok - $1"; exit 1; }

# in_section REPORT HEADING-START USERNAME: true when USERNAME is listed under that heading.
in_section() {
  printf '%s\n' "$1" | awk -v h="$2" -v n="$3" '
    index($0, h) == 1 { s = 1; next }
    /^[A-Z]/ { s = 0 }
    s && index($0, "  " n "  ") == 1 { found = 1 }
    END { exit found ? 0 : 1 }'
}

password_lines() { wc -l < "$LAB_OUT_DIR/new-passwords.txt" 2>/dev/null | tr -d ' ' || echo 0; }

fixture="$here/../fixtures/ci-bash.csv"

"$bin/sync-users.sh" "$fixture" >/dev/null
user_exists ci.alice || fail "sync did not create ci.alice"
user_exists ci.bob || fail "sync did not create ci.bob"
user_exists ci.lock || fail "sync did not create ci.lock"
ok "sync creates the fixture users"

dc samba-tool group listmembers Printers | grep -Fx ci.alice >/dev/null || fail "ci.alice is not in Printers"
dc samba-tool group listmembers Finance | grep -Fx ci.alice >/dev/null || fail "ci.alice is not in Finance"
ok "sync puts users in their groups"

before=$(password_lines)
"$bin/sync-users.sh" "$fixture" >/dev/null
after=$(password_lines)
[ "$before" = "$after" ] || fail "second sync changed the password file ($before -> $after)"
ok "running sync again is safe (no new passwords)"

"$bin/reset-password.sh" ci.bob >/dev/null
[ "$(password_lines)" -eq $((after + 1)) ] || fail "reset did not write a new password"
ok "reset-password writes a new password for ci.bob"

# Eight wrong passwords; the lab locks an account after five.
for n in 1 2 3 4 5 6 7 8; do
  dc ldapsearch -x -H ldap://127.0.0.1 -D "ci.lock@${SAMBA_REALM}" -w "wrong-password-$n" \
    -b "$BASE_DN" -s base dn >/dev/null 2>&1 || true
done
report=$("$bin/stale-report.sh" --days 90)
in_section "$report" "Locked out" ci.lock || fail "ci.lock should be in the locked-out list"
ok "stale-report lists ci.lock after wrong passwords"

"$bin/unlock-user.sh" ci.lock >/dev/null
report=$("$bin/stale-report.sh" --days 90)
in_section "$report" "Locked out" ci.lock && fail "ci.lock is still locked after unlock"
ok "unlock-user clears the lockout"

"$bin/disable-user.sh" ci.bob >/dev/null
uac=$(dc samba-tool user show ci.bob | sed -n 's/^userAccountControl: //p' | tr -d '\r')
[ $(( uac & 2 )) -eq 2 ] || fail "ci.bob is not disabled (userAccountControl=$uac)"
report=$("$bin/stale-report.sh" --days 90)
in_section "$report" "Stale" ci.bob && fail "disabled ci.bob should not be in the stale list"
ok "disable-user disables ci.bob and the report skips him"

echo "all $pass bash integration checks passed"
