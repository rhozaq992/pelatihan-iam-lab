#!/usr/bin/env bash
# Wrapper samba-tool (dipasang di /usr/local/bin/samba-tool, mendahului /usr/bin di PATH).
# samba-tool yang dijalankan peserta mengubah direktori secara LOKAL, sehingga catatan audit
# JSON (mis. perubahan grup, eventId 4728/4732) dihasilkan di proses ini, bukan di daemon.
# Baris audit diteruskan ke stdout proses utama container (→ docker logs → Alloy → Loki)
# agar tampil di Grafana; terminal peserta tetap bersih.
set -o pipefail
/usr/bin/samba-tool "$@" 2>&1 | while IFS= read -r line; do
  case "$line" in
    '{"timestamp"'*) printf '%s\n' "$line" >> /proc/1/fd/1 ;;
    'WARNING: Using passwords on command line is insecure'*) ;;
    *) printf '%s\n' "$line" ;;
  esac
done
exit "${PIPESTATUS[0]}"
