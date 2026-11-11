#!/usr/bin/env bash
# Offline test for the stale and locked-out report. No Docker needed:
# it writes a small LDAP dump with fake sign-in times and checks what the report says.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
report_script="$here/../../scripts/bash/stale-report.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

now=$(date +%s)
# Unix seconds -> Windows FILETIME (100 ns ticks since 1601-01-01), as AD stores it.
filetime() { echo $(( ($1 + 11644473600) * 10000000 )); }

cat > "$tmp/dump.ldif" <<EOF
dn: CN=Alice,CN=Users,DC=lab,DC=example
sAMAccountName: alice
userAccountControl: 512
lastLogonTimestamp: $(filetime $((now - 5 * 86400)))

dn: CN=Bob,CN=Users,DC=lab,DC=example
sAMAccountName: bob
userAccountControl: 512
lastLogonTimestamp: $(filetime $((now - 200 * 86400)))

dn: CN=Carol,CN=Users,DC=lab,DC=example
sAMAccountName: carol
userAccountControl: 512

dn: CN=Dave,CN=Users,DC=lab,DC=example
sAMAccountName: dave
userAccountControl: 514

dn: CN=Erin,CN=Users,DC=lab,DC=example
sAMAccountName: erin
userAccountControl: 512
lastLogonTimestamp: $(filetime $((now - 3600)))
lockoutTime: $(filetime $((now - 60)))

dn: CN=Frank,CN=Users,DC=lab,DC=example
sAMAccountName: frank
userAccountControl: 512
lastLogonTimestamp: $(filetime $((now - 3600)))
lockoutTime: 0
EOF

pass=0
fail=0
check() {  # check DESCRIPTION OK-STATUS
  if [ "$2" = yes ]; then
    pass=$((pass + 1)); echo "ok - $1"
  else
    fail=$((fail + 1)); echo "not ok - $1"
  fi
}
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }
absent() { case "$1" in *"$2"*) echo no ;; *) echo yes ;; esac; }

out=$("$report_script" --days 90 --ldif "$tmp/dump.ldif")

check "bob (200 days, enabled) is stale" "$(has "$out" "  bob  (last sign-in 200 days ago)")"
check "carol (never signed in) is stale" "$(has "$out" "  carol  (never signed in)")"
check "erin is reported as locked out" "$(has "$out" "  erin  (lockout time is set")"
check "alice (signed in 5 days ago) is not reported" "$(absent "$out" "  alice  ")"
check "frank (lockout time 0) is not locked" "$(absent "$out" "  frank  (lockout")"
check "dave (disabled) is skipped" "$(absent "$out" "dave")"

short=$("$report_script" --days 365 --ldif "$tmp/dump.ldif")
check "a 365-day limit leaves bob out" "$(absent "$short" "  bob  (")"

if "$report_script" --days abc --ldif "$tmp/dump.ldif" >/dev/null 2>&1; then
  check "a non-number --days is rejected" no
else
  check "a non-number --days is rejected" yes
fi

echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
