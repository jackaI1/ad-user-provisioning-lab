#!/usr/bin/env bash
# Shared helpers for the lab scripts. This file is sourced, not run.
# Samba commands run inside the "dc" container through docker compose,
# so the scripts only need bash, docker and openssl on the host.

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAB_COMPOSE_FILE="${LAB_COMPOSE_FILE:-$LAB_ROOT/lab/docker-compose.yml}"
LAB_ENV_FILE="${LAB_ENV_FILE:-$LAB_ROOT/lab/.env}"
LAB_OUT_DIR="${LAB_OUT_DIR:-$LAB_ROOT/out}"

die() { echo "ERROR: $*" >&2; exit 1; }

if [ -f "$LAB_ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$LAB_ENV_FILE"
  set +a
fi
: "${SAMBA_REALM:=LAB.EXAMPLE}"
: "${SAMBA_ADMIN_PASSWORD:=}"

# LAB.EXAMPLE -> dc=lab,dc=example
BASE_DN="$(printf '%s' "$SAMBA_REALM" | tr '[:upper:]' '[:lower:]' | sed 's/\./,dc=/g; s/^/dc=/')"
ADMIN_DN="CN=Administrator,CN=Users,$BASE_DN"

# Runs a command in the dc container. </dev/null stops docker from eating
# the stdin of a "while read" loop that calls it.
dc() {
  docker compose -f "$LAB_COMPOSE_FILE" exec -T dc "$@" </dev/null
}

check_lab() {
  command -v docker >/dev/null 2>&1 || die "docker is not installed"
  dc samba-tool domain level show >/dev/null 2>&1 \
    || die "the lab is not running. Start it with: docker compose -f lab/docker-compose.yml up -d --build"
}

# Waits up to about 10 minutes for LDAP to answer (the first start creates the domain).
wait_for_dc() {
  for _ in $(seq 1 120); do
    if dc ldapsearch -x -H ldap://127.0.0.1 -s base -b "" -LLL namingContexts >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done
  return 1
}

user_exists() { dc samba-tool user list | grep -Fx -- "$1" >/dev/null; }

ou_exists() { ldap_dn_exists "OU=$1,$BASE_DN"; }

# ldap_dn_exists DN: succeeds when the object exists.
ldap_dn_exists() {
  dc ldapsearch -x -LLL -H ldap://127.0.0.1 -D "$ADMIN_DN" -w "$SAMBA_ADMIN_PASSWORD" \
    -b "$1" -s base dn >/dev/null 2>&1
}

# A random password that meets the default Samba complexity rules.
new_password() {
  printf 'Lab%s!9' "$(openssl rand -hex 10)"
}

# Appends "username<TAB>password" to the owner-only passwords file.
save_password() {
  mkdir -p "$LAB_OUT_DIR"
  (
    umask 077
    printf '%s\t%s\n' "$1" "$2" >> "$LAB_OUT_DIR/new-passwords.txt"
  )
}
