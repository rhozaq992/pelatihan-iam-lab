#!/usr/bin/env bash
# =============================================================================
# join-domain.sh — gabungkan VM ini (srv1/client1) ke domain iamlab.test (Samba AD dc1).
# Jalankan: sudo join-domain.sh            (minta sandi Administrator domain)
#           sudo ADMIN_PASS='…' OU='OU=Server,DC=iamlab,DC=test' join-domain.sh
#
# Lab: DC berjalan sebagai container di Docker Desktop (port 88/389/464/636 di 10.10.10.5).
# Port DNS (53) tidak dipublikasikan, jadi DC ditunjuk LANGSUNG (/etc/hosts + krb5.conf +
# sssd ad_server) — padanannya di produksi: klien memakai DNS AD & record SRV (realm join).
# =============================================================================
set -euo pipefail
DOMAIN="iamlab.test"; REALM="IAMLAB.TEST"; DC="dc1.iamlab.test"
ADMIN_USER="${ADMIN_USER:-Administrator}"
FQDN="$(hostname -s).${DOMAIN}"
case "$(hostname -s)" in
  client*) DEF_OU="OU=Workstations,DC=iamlab,DC=test" ;;
  *)       DEF_OU="OU=Server,DC=iamlab,DC=test" ;;
esac
OU="${OU-$DEF_OU}"

[ "$(id -u)" -eq 0 ] || { echo "Jalankan dengan sudo."; exit 1; }
getent hosts "$DC" >/dev/null || { echo "✗ $DC tak ada di /etc/hosts"; exit 1; }

echo "==> 1. Cek jangkauan DC ($DC)"
for p in 88 389 464 636; do
  if timeout 3 bash -c "exec 3<>/dev/tcp/$DC/$p" 2>/dev/null; then echo "  ✓ tcp/$p"
  else echo "  ✗ tcp/$p tak terjangkau — Docker Desktop & samba-dc menyala? firewall host?"; exit 1; fi
done

echo "==> 2. Kerberos (/etc/krb5.conf) — KDC ditunjuk langsung, tanpa DNS"
cat > /etc/krb5.conf <<EOF
[libdefaults]
    default_realm = $REALM
    dns_lookup_kdc = false
    dns_lookup_realm = false
    rdns = false
    udp_preference_limit = 0
[realms]
    $REALM = {
        kdc = $DC
        admin_server = $DC
        kpasswd_server = $DC
    }
[domain_realm]
    .$DOMAIN = $REALM
    $DOMAIN = $REALM
EOF

echo "==> 3. Daftarkan akun komputer ($FQDN) ke domain${OU:+ di $OU}"
args=(join --domain="$DOMAIN" --domain-realm="$REALM" --domain-controller="$DC"
      --login-user="$ADMIN_USER" --host-fqdn="$FQDN" --show-details)
[ -n "$OU" ] && args+=(--domain-ou="$OU")
if [ -n "${ADMIN_PASS:-}" ]; then
  printf '%s' "$ADMIN_PASS" | adcli "${args[@]}" --stdin-password
else
  adcli "${args[@]}"
fi

echo "==> 4. SSSD (identitas & autentikasi dari AD)"
cat > /etc/sssd/sssd.conf <<EOF
[sssd]
domains = $DOMAIN
config_file_version = 2
services = nss, pam

[domain/$DOMAIN]
id_provider = ad
auth_provider = ad
chpass_provider = ad
# Sesi 1 langkah 'kebijakan akses': ganti 'permit' dengan 'simple' + simple_allow_groups
access_provider = permit
ad_domain = $DOMAIN
krb5_realm = $REALM
ad_server = $DC
ad_hostname = $FQDN
ad_gpo_access_control = disabled
dyndns_update = false
ldap_id_mapping = true
use_fully_qualified_names = false
fallback_homedir = /home/%u
default_shell = /bin/bash
cache_credentials = true
krb5_store_password_if_offline = true
EOF
chmod 600 /etc/sssd/sssd.conf
pam-auth-update --enable mkhomedir >/dev/null
systemctl enable --now sssd >/dev/null 2>&1 || true
systemctl restart sssd

echo "==> 5. Verifikasi"
sleep 2
if getent passwd administrator >/dev/null; then
  echo "  ✓ akun domain terbaca: $(getent passwd administrator)"
  echo "Selesai. Uji: id <user-domain>   (mis. id dewi.puspita001 setelah bulk import Sesi 1)"
else
  echo "  ! akun domain belum terbaca — cek: sudo journalctl -u sssd -n 50"; exit 1
fi
