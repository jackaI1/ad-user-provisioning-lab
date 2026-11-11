#!/usr/bin/env bash
# Usage: disable-user.sh USERNAME [USERNAME ...]
#
# Disables the accounts of people who have left. A disabled account cannot sign in.
# Nothing is deleted, so the account can be enabled again if the person comes back.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -ge 1 ] || die "usage: $0 USERNAME [USERNAME ...]"
check_lab

for username in "$@"; do
  user_exists "$username" || die "no such user: $username (nothing was changed)"
done
for username in "$@"; do
  out=$(dc samba-tool user disable "$username" 2>&1) || die "could not disable $username: $out"
  echo "disabled: $username"
done
