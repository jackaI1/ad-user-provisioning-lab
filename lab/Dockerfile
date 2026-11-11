# A Samba Active Directory domain controller (DC).
# Samba is free software that speaks the same protocols as Microsoft Active Directory.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        samba \
        samba-ad-dc \
        samba-ad-provision \
        samba-dsdb-modules \
        ldap-utils \
        attr \
        acl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY dc/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# DNS, Kerberos, LDAP, SMB and the global catalog ports.
EXPOSE 53/tcp 53/udp 88/tcp 88/udp 135/tcp 389/tcp 389/udp 445/tcp 464/tcp 636/tcp 3268/tcp 3269/tcp

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
