#!/usr/bin/env bash
# Entrypoint Samba AD DC lab: provision domain sekali (volume kosong), lalu jalankan samba
# di foreground dengan log ke stdout (dipungut Alloy → Loki, Sesi 4).
set -euo pipefail
REALM="${REALM:-IAMLAB.TEST}"
DOMAIN="${DOMAIN:-IAMLAB}"
ADMIN_PASS="${ADMIN_PASS:?ADMIN_PASS wajib diisi}"
HOST_NAME="${HOST_NAME:-dc1}"

if [ ! -f /var/lib/samba/private/sam.ldb ]; then
  echo "[samba-dc] provision domain ${REALM} (sekali)…"
  rm -f /etc/samba/smb.conf
  samba-tool domain provision \
    --realm="$REALM" --domain="$DOMAIN" --server-role=dc --dns-backend=SAMBA_INTERNAL \
    --adminpass="$ADMIN_PASS" --host-name="$HOST_NAME" --use-rfc2307 \
    --option="netbios name = ${HOST_NAME^^}" \
    --option="log level = 1 auth_json_audit:3 dsdb_group_json_audit:5" \
    --option="tls enabled = yes" \
    --option="dns update command = /bin/true"
  echo "[samba-dc] provision selesai."
fi

# krb5.conf hasil provision → dipakai samba-tool/kinit di dalam container
cp -f /var/lib/samba/private/krb5.conf /etc/krb5.conf

# Ekspor CA TLS Samba (dibuat otomatis saat start pertama) agar mudah disalin peserta (Sesi 1):
#   docker compose cp samba-dc:/var/lib/samba/private/tls/ca.pem certs/ad-ca.pem
exec samba --foreground --no-process-group --debug-stdout
