#!/usr/bin/env bash
# =============================================================================
# provision-vm.sh <server|desktop> — dijalankan cloud-init SEKALI saat build-lab.ps1
# membangun VM (NIC NAT sementara aktif → bisa unduh paket). Setelah selesai VM dimatikan,
# NAT dilepas oleh build-lab.ps1 sehingga lab berjalan terisolasi Host-Only.
#
# Memasang: klien domain (sssd/adcli/krb5), auditd + aturan lab, OpenSCAP + SCAP Security
# Guide (CIS Ubuntu 24.04), Grafana Alloy (kirim log ke Loki 10.10.10.5:3100), skrip lab,
# dan untuk 'desktop': ubuntu-desktop-minimal (GDM).
# Variabel opsional: AUTOJOIN=1 ADMIN_PASS=… → langsung join domain (jalan pintas instruktur).
# =============================================================================
set -euo pipefail
ROLE="${1:?Pakai: provision-vm.sh <server|desktop>}"
PAYLOAD="$(cd "$(dirname "$0")/.." && pwd)"     # = /opt/iamlab/lab
export DEBIAN_FRONTEND=noninteractive
log(){ echo "[provision] $*"; echo "[provision] $*" > /dev/ttyS0 2>/dev/null || true; }
apt_install(){ apt-get install -y --no-install-recommends "$@"; }

log "1/7 paket dasar & klien domain"
apt-get update -q
apt_install sssd-ad sssd-tools libnss-sss libpam-sss adcli krb5-user oddjob oddjob-mkhomedir \
            ldap-utils auditd audispd-plugins openscap-scanner unzip curl gpg ca-certificates \
            python3 acl

log "2/7 skrip lab → /usr/local/sbin"
install -m 0755 "$PAYLOAD/scripts/join-domain.sh" /usr/local/sbin/join-domain.sh
install -m 0755 "$PAYLOAD/scripts/cis-scan.sh"    /usr/local/sbin/cis-scan.sh

log "3/7 auditd (rekam perintah user & perubahan identitas)"
install -m 0640 "$PAYLOAD/audit/iamlab.rules" /etc/audit/rules.d/iamlab.rules
sed -i -e 's/^log_format.*/log_format = ENRICHED/' -e 's/^log_group.*/log_group = adm/' /etc/audit/auditd.conf
grep -q '^log_group' /etc/audit/auditd.conf || echo 'log_group = adm' >> /etc/audit/auditd.conf
augenrules --load >/dev/null 2>&1 || true
systemctl enable auditd >/dev/null 2>&1; systemctl restart auditd || true
chgrp adm /var/log/audit /var/log/audit/audit.log 2>/dev/null || true
chmod 0750 /var/log/audit; chmod 0640 /var/log/audit/audit.log 2>/dev/null || true

log "4/7 SCAP Security Guide (CIS Benchmark Ubuntu 24.04)"
mkdir -p /opt/cis
DS=/opt/cis/ssg-ubuntu2404-ds.xml
# Versi DIPIN (lingkungan terkontrol, deterministik). Datastream v0.1.82 memuat profil
# cis_level1_server & cis_level1_workstation untuk Ubuntu 24.04. Prioritas: salinan offline
# dari payload (lab/cis/) bila disertakan, lalu unduh terpin dengan retry + cek integritas.
SSG_VER="${SSG_VER:-0.1.82}"
SSG_URL="https://github.com/ComplianceAsCode/content/releases/download/v${SSG_VER}/scap-security-guide-${SSG_VER}.zip"
if [ -f "$PAYLOAD/cis/ssg-ubuntu2404-ds.xml" ]; then
  install -m 0644 "$PAYLOAD/cis/ssg-ubuntu2404-ds.xml" "$DS"
  echo "offline payload" > /opt/cis/SOURCE
else
  ok=0
  for n in 1 2 3; do
    if curl -fL --retry 3 --connect-timeout 20 -o /tmp/ssg.zip "$SSG_URL" && unzip -t /tmp/ssg.zip >/dev/null 2>&1; then
      unzip -j -o /tmp/ssg.zip '*/ssg-ubuntu2404-ds.xml' -d /opt/cis >/dev/null && { ok=1; break; }
    fi
    log "  unduh SSG percobaan $n gagal, ulangi..."; sleep 5
  done
  rm -f /tmp/ssg.zip
  [ "$ok" = 1 ] || { log "GAGAL unduh/ekstrak SSG ($SSG_URL) - sertakan lab/cis/ssg-ubuntu2404-ds.xml utk offline"; exit 1; }
  echo "$SSG_URL" > /opt/cis/SOURCE
fi
[ -s "$DS" ] || { log "datastream SSG kosong/korup"; exit 1; }
KIND=$([ "$ROLE" = desktop ] && echo workstation || echo server)
PROFILE="xccdf_org.ssgproject.content_profile_cis_level1_${KIND}"
INFO="$(oscap info "$DS" 2>&1)"
echo "$INFO" | grep -q "cis_level1_${KIND}" \
  || { log "profil cis_level1_${KIND} tak ada. oscap info:"; echo "$INFO" | grep -iE 'profile|error|Id:' | head -20 > /dev/ttyS0 2>/dev/null; exit 1; }
mkdir -p /var/log/cis; chgrp adm /var/log/cis; chmod 0750 /var/log/cis

log "5/7 Grafana Alloy (log host → Loki lab)"
mkdir -p /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor --yes -o /etc/apt/keyrings/grafana.gpg
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
  > /etc/apt/sources.list.d/grafana.list
apt-get update -q && apt_install alloy
install -m 0644 "$PAYLOAD/alloy/host.alloy" /etc/alloy/config.alloy
usermod -aG adm alloy
systemctl enable alloy >/dev/null 2>&1; systemctl restart alloy || true

if [ "$ROLE" = desktop ]; then
  log "6/7 ubuntu-desktop-minimal (GDM) — bagian terlama (±15–30 menit)"
  apt-get install -y ubuntu-desktop-minimal
  systemctl set-default graphical.target
  # login GUI akun domain: tampilkan isian nama pengguna manual di GDM
  mkdir -p /etc/dconf/db/gdm.d /etc/dconf/profile
  printf 'user-db:user\nsystem-db:gdm\nfile-db:/usr/share/gdm/greeter-dconf-defaults\n' > /etc/dconf/profile/gdm
  printf '[org/gnome/login-screen]\ndisable-user-list=true\n' > /etc/dconf/db/gdm.d/00-iamlab
  dconf update || true
else
  log "6/7 (server) lewati desktop"
fi

log "7/7 bersih-bersih"
apt-get clean
if [ "${AUTOJOIN:-0}" = 1 ] && [ -n "${ADMIN_PASS:-}" ]; then
  log "AutoJoin: join domain sekarang"
  ADMIN_PASS="$ADMIN_PASS" /usr/local/sbin/join-domain.sh
fi
log "selesai"
