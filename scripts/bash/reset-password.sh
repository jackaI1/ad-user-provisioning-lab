#!/usr/bin/env bash
# Usage: reset-password.sh USERNAME
#
# Sets a new random password and makes the user change it at the next sign-in.
# The new password is written to out/new-passwords.txt. It is not printed on screen.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

[ $# -eq 1 ] || die "usage: $0 USERNAME"
check_lab

username="$1"
user_exists "$username" || die "no such user: $username"

pw=$(new_password)
out=$(dc samba-tool user setpassword "$username" --newpassword="$pw" --must-change-at-next-login 2>&1) \
  || die "could not reset password for $username: $out"
save_password "$username" "$pw"
echo "Password reset for $username. The new password is in $LAB_OUT_DIR/new-passwords.txt"
