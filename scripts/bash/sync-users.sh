#!/usr/bin/env bash
# Usage: sync-users.sh USERS.csv
#
# CSV columns: username,given_name,surname,ou,groups
#   ou      OU (folder) under the domain to put the user in. Blank = the default Users folder.
#   groups  Group names separated by ";". Missing groups are created.
#
# Creates missing OUs, groups and users, then adds each user to their groups.
# Objects that already exist are left alone, so running it again is safe.
# New passwords go to out/new-passwords.txt (readable by you only).
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

csv="${1:-}"
[ -n "$csv" ] && [ -f "$csv" ] || die "usage: $0 USERS.csv"
check_lab

ensure_group() {
  if ! dc samba-tool group list | grep -Fx -- "$1" >/dev/null; then
    local out
    out=$(dc samba-tool group add "$1" 2>&1) || die "could not create group $1: $out"
    echo "created group: $1"
  fi
}

add_member() {  # add_member GROUP USER
  if dc samba-tool group listmembers "$1" | grep -Fx -- "$2" >/dev/null; then
    return 0
  fi
  local out
  out=$(dc samba-tool group addmembers "$1" "$2" 2>&1) || die "could not add $2 to $1: $out"
  echo "  $2 added to $1"
}

while IFS=, read -r username given surname ou groups || [ -n "$username" ]; do
  groups=${groups%$'\r'}
  case "$username" in
    ''|username|\#*) continue ;;
  esac
  printf '%s' "$username" | grep -Eq '^[a-z][a-z0-9._-]{1,19}$' || die "bad username in CSV: $username"

  if [ -n "$ou" ] && ! ou_exists "$ou"; then
    out=$(dc samba-tool ou create "OU=$ou,$BASE_DN" 2>&1) || die "could not create OU $ou: $out"
    echo "created OU: $ou"
  fi

  if user_exists "$username"; then
    echo "exists: $username"
  else
    pw=$(new_password)
    args=(--given-name="$given" --surname="$surname" --must-change-at-next-login)
    if [ -n "$ou" ]; then
      args+=(--userou="OU=$ou")
    fi
    out=$(dc samba-tool user create "$username" "$pw" "${args[@]}" 2>&1) \
      || die "could not create $username: $out"
    save_password "$username" "$pw"
    echo "created user: $username"
  fi

  if [ -n "$groups" ]; then
    IFS=';' read -r -a group_list <<< "$groups"
    for g in "${group_list[@]}"; do
      [ -n "$g" ] || continue
      ensure_group "$g"
      add_member "$g" "$username"
    done
  fi
done < "$csv"

echo "Done. New passwords (if any) are in $LAB_OUT_DIR/new-passwords.txt"
