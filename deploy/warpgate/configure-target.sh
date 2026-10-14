#!/usr/bin/env bash
# =============================================================================
# configure-target.sh — Daftarkan target SSH + user + role di Warpgate via Admin API.
# Alternatif otomatis dari konfigurasi manual di konsol admin (Sesi 3 bagian C).
# Jalankan DI HOST setelah `unattended-setup` + `docker compose up -d warpgate`.
# Target = VM srv1 (10.10.10.20). Butuh akses SSH ke srv1 (labadmin) untuk memasang kunci klien.
#
# Pakai:
#   ./configure-target.sh                       # target srv1 (10.10.10.20, user labadmin), bastion user 'peserta'
#   ADMIN_PASS='...' TARGET=srv1 TGT_HOST=10.10.10.20 TGT_USER=labadmin \
#     BASTION_USER=peserta PUBKEY="$(cat ~/.ssh/id_ed25519.pub)" ./configure-target.sh
#
# Catatan penting (dari pengalaman):
#  • Cookie sesi Warpgate ber-domain external_host (pam.iamlab.test) → API HARUS diakses
#    lewat https://pam.iamlab.test (via Caddy), BUKAN https://warpgate:8888 langsung.
#    Skrip ini memakai pam.iamlab.test; pastikan nama itu resolve (build-lab.ps1 mengaturnya).
#  • Bila login SSH ke bastion gagal 'Permission denied' berulang, proteksi brute-force
#    Warpgate mungkin memblok IP sumber. Lihat bagian "Troubleshooting" di README.
# =============================================================================
set -euo pipefail
BASE="https://${WG_HOST:-pam.iamlab.test}"; API="$BASE/@warpgate/admin/api"
ADMIN_PASS="${ADMIN_PASS:-Warp#Lab2026}"
TARGET="${TARGET:-srv1}"; TGT_HOST="${TGT_HOST:-10.10.10.20}"; TGT_USER="${TGT_USER:-labadmin}"; TGT_PASS="${TGT_PASS:-Lab#Admin2026}"
BASTION_USER="${BASTION_USER:-peserta}"; ROLE="${ROLE:-pam-ssh}"; PUBKEY="${PUBKEY:-}"
JAR="$(mktemp)"; trap 'rm -f "$JAR"' EXIT
cj(){ curl -sk --cookie "$JAR" --cookie-jar "$JAR" "$@"; }   # jaga cookie sesi

echo "==> Login admin ($BASE)"
cj -o /dev/null -X POST "$BASE/@warpgate/api/auth/login" -H 'Content-Type: application/json' \
   -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PASS\"}"
who=$(cj "$BASE/@warpgate/api/info" | python3 -c "import sys,json;print(json.load(sys.stdin).get('username'))")
[ "$who" = admin ] || { echo "  login gagal (username=$who). Cek ADMIN_PASS / resolusi pam.iamlab.test."; exit 1; }
echo "  ok (admin)"

id_of(){ python3 -c "import sys,json;d=json.load(sys.stdin);print(next((x['id'] for x in d if x.get('name')==sys.argv[1] or x.get('username')==sys.argv[1]),''))" "$1"; }

echo "==> Role '$ROLE'"
RID=$(cj "$API/roles" | id_of "$ROLE")
[ -n "$RID" ] || RID=$(cj -X POST "$API/roles" -H 'Content-Type: application/json' -d "{\"name\":\"$ROLE\"}" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
echo "  $RID"

# Warpgate → target memakai KUNCI KLIEN Warpgate (bukan sandi): Sesi 3 bagian B mematikan
# PasswordAuthentication di srv1, jadi auth sandi akan putus setelah hardening.
echo "==> Kunci klien Warpgate -> authorized_keys $TGT_USER@$TGT_HOST (srv1)"
WGKEYS=$(cj "$API/ssh/own-keys" | python3 -c "import sys,json
try: print('\n'.join(k['kind']+' '+k['public_key_base64'] for k in json.load(sys.stdin)))
except Exception: pass")
AUTH="{\"kind\":\"PublicKey\"}"
if [ -n "$WGKEYS" ]; then
  # pasang kunci klien Warpgate ke srv1 via SSH (saat auth sandi masih aktif, atau pakai kunci Anda)
  printf '%s\n' "$WGKEYS" | ssh "$TGT_USER@$TGT_HOST" \
    "install -d -m 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys" \
    && echo "  ok ($(printf '%s\n' "$WGKEYS" | wc -l) kunci dipasang di srv1)" \
    || echo "  ! gagal SSH ke $TGT_HOST — pasang kunci manual di srv1, lalu ulangi."
else
  echo "  ! kunci klien Warpgate tak terbaca — sementara pakai sandi (putus setelah PasswordAuthentication no)."
  AUTH="{\"kind\":\"Password\",\"password\":\"$TGT_PASS\"}"
fi

echo "==> Target '$TARGET' (SSH $TGT_USER@$TGT_HOST:22)"
TID=$(cj "$API/targets" | id_of "$TARGET")
[ -n "$TID" ] || TID=$(cj -X POST "$API/targets" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$TARGET\",\"options\":{\"kind\":\"Ssh\",\"host\":\"$TGT_HOST\",\"port\":22,\"username\":\"$TGT_USER\",\"auth\":$AUTH}}" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
echo "  $TID"

echo "==> User bastion '$BASTION_USER'"
UID_=$(cj "$API/users" | id_of "$BASTION_USER")
[ -n "$UID_" ] || UID_=$(cj -X POST "$API/users" -H 'Content-Type: application/json' -d "{\"username\":\"$BASTION_USER\",\"credential_policy\":{}}" | python3 -c "import sys,json;print(json.load(sys.stdin)['id'])")
echo "  $UID_"

if [ -n "$PUBKEY" ]; then
  echo "==> Kredensial kunci publik utk '$BASTION_USER'"
  cj -o /dev/null -X POST "$API/users/$UID_/credentials/public-keys" -H 'Content-Type: application/json' \
     -d "{\"label\":\"$BASTION_USER-key\",\"openssh_public_key\":\"$PUBKEY\"}"
  echo "  ok"
else
  echo "  (PUBKEY kosong — set login via SSO/kata sandi di konsol, atau beri PUBKEY env)"
fi

echo "==> Grant: user→role, target→role"
cj -o /dev/null -X POST "$API/users/$UID_/roles/$RID" -H 'Content-Type: application/json' -d '{}'
cj -o /dev/null -X POST "$API/targets/$TID/roles/$RID" -H 'Content-Type: application/json' -d '{}' || true
echo
echo "Selesai. Uji akses via bastion (sesi direkam):"
echo "  ssh -p 2222 ${BASTION_USER}:${TARGET}@${WG_HOST:-pam.iamlab.test}   # -> srv1 ($TGT_HOST)"
