# Samba AD DC lab (dc1.iamlab.test) — direktori AD/LDAP untuk klien Ubuntu (srv1, client1)
# dan sumber federasi Keycloak/OpenBao. Dibangun sendiri agar opsi log audit & TLS terkendali.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      samba samba-ad-dc samba-ad-provision samba-dsdb-modules samba-vfs-modules \
      winbind krb5-user ldb-tools ldap-utils ca-certificates python3-cryptography \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/samba/smb.conf
COPY entrypoint.sh /usr/local/sbin/entrypoint.sh
# samba-tool → audit JSON diteruskan ke log container (lihat komentar di wrapper)
COPY samba-tool-wrapper.sh /usr/local/bin/samba-tool
RUN chmod +x /usr/local/sbin/entrypoint.sh /usr/local/bin/samba-tool
# 88 Kerberos · 389 LDAP/CLDAP · 464 kpasswd · 636 LDAPS · 3268/3269 Global Catalog
EXPOSE 88/tcp 88/udp 389/tcp 389/udp 464/tcp 464/udp 636/tcp 3268/tcp 3269/tcp
VOLUME ["/var/lib/samba", "/etc/samba"]
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=10 \
  CMD ldapsearch -x -H ldap://127.0.0.1 -s base -b "" defaultNamingContext >/dev/null 2>&1 || exit 1
ENTRYPOINT ["/usr/local/sbin/entrypoint.sh"]
