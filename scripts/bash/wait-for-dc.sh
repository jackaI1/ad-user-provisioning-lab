#!/usr/bin/env bash
# Waits until the Samba domain controller answers LDAP. The first start takes a few minutes.
set -euo pipefail
# shellcheck source=lib.sh
source "$(dirname "$0")/lib.sh"

if ! wait_for_dc; then
  docker compose -f "$LAB_COMPOSE_FILE" logs --no-color --tail 80 dc >&2 || true
  die "the Samba domain controller did not start"
fi
echo "Samba domain controller is answering LDAP."
