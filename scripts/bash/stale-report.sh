#!/usr/bin/env bash
# Usage: stale-report.sh [--days N] [--ldif FILE]
#
# Prints two lists:
#   1. Locked out: accounts with a lockout time set.
#   2. Stale: enabled accounts that have not signed in for more than N days (default 90),
#      or have never signed in. Disabled accounts are skipped.
#
# By default it asks the running lab over LDAP. With --ldif it reads a saved LDAP dump
# instead (the tests use this, so they do not need Docker).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

days=90
ldif=""
while [ $# -gt 0 ]; do
  case "$1" in
    --days) days="${2:-}"; shift 2 ;;
    --ldif) ldif="${2:-}"; shift 2 ;;
    *) die "unknown option: $1" ;;
  esac
done
case "$days" in
  ''|*[!0-9]*) die "--days needs a whole number" ;;
esac

tmp=""
cleanup() { [ -z "$tmp" ] || rm -f "$tmp"; }
trap cleanup EXIT

if [ -z "$ldif" ]; then
  check_lab
  tmp=$(mktemp)
  ldif="$tmp"
  dc ldapsearch -x -LLL -o ldif-wrap=no -H ldap://127.0.0.1 \
    -D "$ADMIN_DN" -w "$SAMBA_ADMIN_PASSWORD" -b "$BASE_DN" \
    '(&(objectClass=user)(objectCategory=person))' \
    sAMAccountName userAccountControl lastLogonTimestamp lockoutTime > "$ldif" \
    || die "LDAP query failed"
fi
[ -r "$ldif" ] || die "cannot read $ldif"

now=$(date +%s)

# One output row per problem: TAG<TAB>username<TAB>detail
rows=$(awk -v now="$now" -v days="$days" '
  BEGIN { RS = ""; FS = "\n"; OFS = "\t" }
  {
    user = ""; uac = 0; ll = 0; lock = 0
    for (i = 1; i <= NF; i++) {
      if (match($i, /^[A-Za-z]+: /)) {
        key = substr($i, 1, RLENGTH - 2)
        val = substr($i, RLENGTH + 1)
        if (key == "sAMAccountName") user = val
        else if (key == "userAccountControl") uac = val + 0
        else if (key == "lastLogonTimestamp") ll = val + 0
        else if (key == "lockoutTime") lock = val + 0
      }
    }
    if (user == "") next
    if (lock > 0) print "LOCKED", user, "lockout time is set"
    disabled = (int(uac / 2) % 2 == 1)   # bit 0x2 = ACCOUNT_DISABLE
    if (disabled) next
    if (ll == 0) {
      print "STALE", user, "never signed in"
    } else {
      # lastLogonTimestamp counts 100-nanosecond intervals since 1601-01-01
      age = int(((now - (ll / 10000000 - 11644473600)) / 86400) + 0.5)
      if (age > days) print "STALE", user, "last sign-in " age " days ago"
    }
  }' "$ldif")

section() {  # section TAG HEADING
  local lines
  lines=$(printf '%s\n' "$rows" | awk -F'\t' -v t="$1" '$1 == t { print "  " $2 "  (" $3 ")" }' | sort)
  echo "$2"
  if [ -n "$lines" ]; then
    printf '%s\n' "$lines"
  else
    echo "  none"
  fi
  echo
}

section LOCKED "Locked out (lockout time is set; the lock may already have expired):"
section STALE "Stale enabled accounts (no sign-in for more than $days days, or never):"
