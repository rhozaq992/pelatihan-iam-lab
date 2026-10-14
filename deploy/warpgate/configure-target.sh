#!/usr/bin/env bash
# =============================================================================
# configure-target.sh — Daftarkan target SSH + user + role di Warpgate via Admin API.
# Alternatif otomatis dari konfigurasi manual di konsol admin (Sesi 3 bagian C).
# Jalankan DI HOST DOCKER setelah `unattended-setup` + `docker compose up -d warpgate`.
#
# Pakai:
#   ./configure-target.sh                       # default: target srv-app01 (user labadmin), user bastion 'peserta'
#   ADMIN_PASS='...' TARGET=srv-db01 TGT_USER=labadmin TGT_PASS='ChangeMe#2026' \
#     BASTION_USER=peserta PUBKEY="$(cat ~/.ssh/id_ed25519.pub)" ./configure-target.sh
#
# Catatan penting (dari pengalaman):
#  • Cookie sesi Warpgate ber-domain external_host (pam.iamlab.test) → API HARUS diakses
#    lewat https://pam.iamlab.test (via Caddy), BUKAN https://warpgate:8888 langsung.
#    Skrip ini memakai pam.iamlab.test; pastikan nama itu resolve (deploy-lab.sh mengaturnya).
#  • Bila login SSH ke bastion gagal 'Permission denied' berulang, proteksi brute-force
#    Warpgate mungkin memblok IP sumber. Lihat bagian "Troubleshooting" di README.
# =============================================================================
set -euo pipefail
BASE="https://${WG_HOST:-pam.iamlab.test}"; API="$BASE/@warpgate/admin/api"
ADMIN_PASS="${ADMIN_PASS:-Warp#Lab2026}"
TARGET="${TARGET:-srv-app01}"; TGT_USER="${TGT_USER:-labadmin}"; TGT_PASS="${TGT_PASS:-ChangeMe#2026}"
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
# PasswordAuthentication di target, jadi auth sandi akan putus setelah hardening.
echo "==> Kunci klien Warpgate → authorized_keys $TGT_USER@$TARGET"
WGKEYS=$(cj "$API/ssh/own-keys" | python3 -c "import sys,json
try: print('\n'.join(k['kind']+' '+k['public_key_base64'] for k in json.load(sys.stdin)))
except Exception: pass")
AUTH="{\"kind\":\"PublicKey\"}"
if [ -n "$WGKEYS" ]; then
  printf '%s\n' "$WGKEYS" | docker compose -f "$(dirname "$0")/../compose.yaml" exec -T "$TARGET" sh -c \
    "h=\$(getent passwd $TGT_USER | cut -d: -f6); install -d -m 700 -o $TGT_USER \$h/.ssh; cat >> \$h/.ssh/authorized_keys; chown $TGT_USER \$h/.ssh/authorized_keys; chmod 600 \$h/.ssh/authorized_keys"
  echo "  ok ($(printf '%s\n' "$WGKEYS" | wc -l) kunci)"
else
  echo "  ! kunci klien Warpgate tak terbaca — sementara pakai sandi (putus setelah PasswordAuthentication no)."
  AUTH="{\"kind\":\"Password\",\"password\":\"$TGT_PASS\"}"
fi

echo "==> Target '$TARGET' (SSH $TGT_USER@$TARGET:22)"
TID=$(cj "$API/targets" | id_of "$TARGET")
[ -n "$TID" ] || TID=$(cj -X POST "$API/targets" -H 'Content-Type: application/json' \
  -d "{\"name\":\"$TARGET\",\"options\":{\"kind\":\"Ssh\",\"host\":\"$TARGET\",\"port\":22,\"username\":\"$TGT_USER\",\"auth\":$AUTH}}" \
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
echo "  ssh -p 2222 ${BASTION_USER}:${TARGET}@${WG_HOST:-pam.iamlab.test}"
