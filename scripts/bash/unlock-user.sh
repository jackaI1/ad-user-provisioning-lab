#!/usr/bin/env bash
# Usage: unlock-user.sh USERNAME
#
# Clears a lockout after too many wrong passwords.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -eq 1 ] || die "usage: $0 USERNAME"
check_lab

username="$1"
user_exists "$username" || die "no such user: $username"
out=$(dc samba-tool user unlock "$username" 2>&1) || die "could not unlock $username: $out"
echo "unlocked: $username"
