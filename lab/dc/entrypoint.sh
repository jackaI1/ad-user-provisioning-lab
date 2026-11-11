#!/usr/bin/env bash
# Starts the Samba domain controller.
# First start: creates the domain. Later starts: only runs Samba on the saved data.
set -euo pipefail

: "${SAMBA_REALM:?SAMBA_REALM is not set}"
: "${SAMBA_DOMAIN:?SAMBA_DOMAIN is not set}"
: "${SAMBA_ADMIN_PASSWORD:?SAMBA_ADMIN_PASSWORD is not set (see lab/.env.example)}"

marker=/var/lib/samba/.lab-provisioned
if [ ! -f "$marker" ]; then
  echo "First start: creating domain ${SAMBA_REALM} ..."
  # No marker means no earlier provisioning finished. Clear any partial data so it starts clean.
  find /var/lib/samba -mindepth 1 -delete
  rm -f /etc/samba/smb.conf /etc/krb5.conf
  samba-tool domain provision \
    --use-rfc2307 \
    --realm="$SAMBA_REALM" \
    --domain="$SAMBA_DOMAIN" \
    --server-role=dc \
    --dns-backend=SAMBA_INTERNAL \
    --host-name=dc \
    --adminpass="$SAMBA_ADMIN_PASSWORD"

  # Lab only: allow simple LDAP binds (user name + password, no TLS).
  # The scripts use this to query the directory. Do not copy this setting to a real server.
  sed -i '/^\[global\]/a ldap server require strong auth = no' /etc/samba/smb.conf

  # Lock an account for 30 minutes after 5 wrong passwords, so the lockout report has something to show.
  samba-tool domain passwordsettings set --account-lockout-threshold=5

  touch "$marker"
  echo "Domain created."
fi

exec samba --foreground --no-process-group --debug-stdout
