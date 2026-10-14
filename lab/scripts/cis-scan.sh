#!/usr/bin/env bash
# =============================================================================
# cis-scan.sh — audit CIS Benchmark Ubuntu 24.04 dengan OpenSCAP + SCAP Security Guide.
#
#   sudo cis-scan.sh                    # scan CIS Level 1 (server/workstation dideteksi otomatis)
#   sudo cis-scan.sh --level 2          # Level 2 (informasi tambahan — lebih ketat)
#   sudo cis-scan.sh --list-fail        # daftar rule yang GAGAL pada scan terakhir
#   sudo cis-scan.sh --fix <rule-id>    # remediasi SATU rule (terarah, bukan seluruh profil)
#
# Hasil: /var/log/cis/report-<waktu>.html (+ report-latest.html) dan satu baris JSON
# ringkasan di /var/log/cis/summary.log → dikirim Alloy ke Loki (dashboard Grafana Sesi 4).
# =============================================================================
set -euo pipefail
DS="${CIS_DS:-/opt/cis/ssg-ubuntu2404-ds.xml}"
OUT=/var/log/cis
LEVEL=1; ACTION=scan; RULE=""
while [ $# -gt 0 ]; do case "$1" in
  --level) LEVEL="$2"; shift 2;;
  --list-fail) ACTION=list; shift;;
  --fix) ACTION=fix; RULE="$2"; shift 2;;
  -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "opsi tak dikenal: $1"; exit 1;;
esac; done
[ "$(id -u)" -eq 0 ] || { echo "Jalankan dengan sudo."; exit 1; }
[ -f "$DS" ] || { echo "Datastream $DS tak ada (dipasang saat build lab)."; exit 1; }

if dpkg -s gdm3 >/dev/null 2>&1; then KIND=workstation; else KIND=server; fi
PROFILE="xccdf_org.ssgproject.content_profile_cis_level${LEVEL}_${KIND}"
mkdir -p "$OUT"; chmod 750 "$OUT"; chgrp adm "$OUT" 2>/dev/null || true

if [ "$ACTION" = list ]; then
  last="$(ls -1t "$OUT"/results-*.xml 2>/dev/null | head -1)"
  [ -n "$last" ] || { echo "Belum ada hasil scan."; exit 1; }
  python3 - "$last" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for rr in root.iter():
    if rr.tag.endswith('rule-result'):
        res = next((c.text for c in rr if c.tag.endswith('result')), '')
        if res == 'fail':
            print(rr.get('severity', '?').ljust(8), rr.get('idref'))
PY
  exit 0
fi

if [ "$ACTION" = fix ]; then
  [ -n "$RULE" ] || { echo "Pakai: cis-scan.sh --fix <rule-id> (lihat --list-fail)"; exit 1; }
  case "$RULE" in xccdf_*) ;; *) RULE="xccdf_org.ssgproject.content_rule_${RULE}";; esac
  echo "==> Remediasi terarah: $RULE"
  oscap xccdf eval --remediate --profile "$PROFILE" --rule "$RULE" "$DS" || true
  echo "Selesai. Jalankan ulang 'sudo cis-scan.sh' untuk melihat perubahan skor."
  exit 0
fi

TS="$(date +%Y%m%d-%H%M%S)"
echo "==> Scan $PROFILE (±3–10 menit)…"
rc=0
oscap xccdf eval --profile "$PROFILE" \
  --results "$OUT/results-$TS.xml" --report "$OUT/report-$TS.html" "$DS" >/dev/null || rc=$?
# rc 0 = semua lolos, 2 = ada rule gagal (normal), lainnya = galat
[ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || { echo "oscap galat (rc=$rc)"; exit "$rc"; }
ln -sf "report-$TS.html" "$OUT/report-latest.html"

python3 - "$OUT/results-$TS.xml" "$(hostname -s)" "cis_level${LEVEL}_${KIND}" "$OUT/report-$TS.html" >>"$OUT/summary.log" <<'PY'
import sys, json, datetime, collections, xml.etree.ElementTree as ET
path, host, profile, report = sys.argv[1:5]
root = ET.parse(path).getroot()
cnt = collections.Counter(); score = None
for el in root.iter():
    if el.tag.endswith('rule-result'):
        res = next((c.text for c in el if c.tag.endswith('result')), None)
        if res: cnt[res] += 1
    elif el.tag.endswith('}score') and score is None:
        score = round(float(el.text), 1)
print(json.dumps({"host": host, "profile": profile, "pass": cnt["pass"], "fail": cnt["fail"],
                  "notapplicable": cnt["notapplicable"], "score": score, "report": report,
                  "ts": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}))
PY
chmod 640 "$OUT"/summary.log; chgrp adm "$OUT"/summary.log 2>/dev/null || true
echo "==> Ringkasan: $(tail -1 "$OUT/summary.log")"
echo "Laporan: $OUT/report-latest.html   (buka di browser client1, atau salin ke host)"
