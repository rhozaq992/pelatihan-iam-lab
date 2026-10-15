#!/usr/bin/env bash
# attack-sim/run.sh — wrapper LAB-ONLY untuk perkakas open source (Impacket).
# Defensif: menghasilkan sinyal serangan agar deteksi/mitigasi dapat diuji.
# Pengaman: allowlist target + wajib konfirmasi + tolak bila internet BENAR-BENAR terjangkau.
set -euo pipefail
HERE="$(dirname "$0")"
ALLOW_FILE="$HERE/TARGETS.lab"; [[ -f "$ALLOW_FILE" ]] || ALLOW_FILE="/opt/TARGETS.lab"
TARGET="${1:?Pakai: run.sh <target-dari-TARGETS.lab> [kerberoast|ntlm-sim]}"
ACTION="${2:-kerberoast}"

[[ "${IAMLAB_CONFIRM:-0}" == "1" ]] || { echo "Tolak: set IAMLAB_CONFIRM=1 (lab only)"; exit 1; }
grep -qxF "$TARGET" "$ALLOW_FILE" || { echo "DITOLAK: $TARGET di luar allowlist lab"; exit 1; }

# Uji konektivitas internet NYATA (bukan sekadar ada default route): coba TCP 1.1.1.1:53, 2 dtk.
if timeout 2 bash -c 'exec 3<>/dev/tcp/1.1.1.1/53' 2>/dev/null; then
  echo "DITOLAK: internet terjangkau — lab HARUS Host-Only terisolasi (putus NAT/bridge keluar)"; exit 1
fi

echo "[lab] ($ACTION) simulasi terhadap $TARGET untuk menguji deteksi/mitigasi."
echo "[lab] Contoh perintah open source (jalankan manual oleh instruktur di lab):"
case "$ACTION" in
  kerberoast)
    echo "      GetUserSPNs.py iamlab.test/<user>:<pass> -request -dc-ip $TARGET" ;;
  *)
    echo "      (lihat modul Sesi 1 — hanya untuk menghasilkan sinyal pada log)" ;;
esac
echo "[lab] Setelah ini: amati permintaan tiket layanan (SPN) di log KDC Samba via Grafana/Loki"
echo "[lab] (Sesi 4); terapkan AES-only; ulangi & bandingkan enctype tiket: RC4 (\$krb5tgs\$23\$) -> AES (\$krb5tgs\$18\$)."
