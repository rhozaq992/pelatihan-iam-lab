#!/usr/bin/env bash
# =============================================================================
# setup-keycloak.sh — JALUR CEPAT (opsional) Sesi 2.
# Menyiapkan realm `iamlab` di Keycloak secara OTOMATIS via kcadm (di dalam container):
# realm + federasi LDAP ke Samba AD + mapper grup + clients (app-komentar/warpgate/app-saml)
# + Group Membership mapper (klaim `groups`) + brute-force + events + SMTP(Mailpit).
#
# GUNAKAN HANYA BILA STUCK melakukan langkah manual di konsol (README §1–§6) agar bisa lanjut
# ke lab lain. Langkah manual TETAP jalur utama pembelajaran — ini pintasan darurat.
#
# Jalankan DI HOST dari folder deploy (stack harus up, keycloak healthy):
#   cd IAMLAB-BuildBag/deploy
#   BIND_PW='<sandi svc-keycloak terbaru dari Sesi 1 langkah 5>' \
#     ../Pelatihan_IAM/sesi-2-sso-mfa/jalur-cepat/setup-keycloak.sh
#
# Yang TIDAK diotomasi (tetap manual, lihat README §5): MFA bersyarat (Conditional OTP flow) —
# alur autentikasi terlalu rinci/variatif antar versi untuk diskrip dengan aman.
# =============================================================================
set -euo pipefail

REALM="${REALM:-iamlab}"
ADMIN_USER="${KC_ADMIN_USER:-${KC_BOOTSTRAP_ADMIN_USERNAME:-admin}}"
ADMIN_PASS="${KC_ADMIN_PASS:-${KC_BOOTSTRAP_ADMIN_PASSWORD:-}}"
BIND_PW="${BIND_PW:-}"                      # WAJIB: sandi svc-keycloak terbaru (Sesi 1 langkah 5)
BASE_DOMAIN="${BASE_DOMAIN:-iamlab.test}"
DC_HOST="${DC_HOST:-dc1.${BASE_DOMAIN}}"
ENV_FILE="${ENV_FILE:-.env}"               # deploy/.env (ditulisi APP_OIDC_CLIENT_SECRET)
KCADM="/opt/keycloak/bin/kcadm.sh"
DC="docker compose exec -T keycloak"       # jalankan kcadm di dalam container keycloak

die(){ echo "  [X] $*" >&2; exit 1; }
ok(){ echo "  [OK] $*"; }
kc(){ $DC $KCADM "$@"; }                    # bungkus kcadm
# ambil nilai field dari output JSON kcadm (array/obyek) di host
jval(){ python3 -c "import sys,json;d=json.load(sys.stdin);d=d[0] if isinstance(d,list) and d else d;print((d or {}).get(sys.argv[1],'')) if isinstance(d,dict) else print('')" "$1"; }

[ -f "docker-compose.yaml" ] || [ -f "compose.yaml" ] || die "Jalankan dari folder deploy (tak ada compose.yaml)."
[ -n "$ADMIN_PASS" ] || die "KC admin password kosong. Set KC_ADMIN_PASS atau pastikan .env punya KC_BOOTSTRAP_ADMIN_PASSWORD."
[ -n "$BIND_PW" ]   || die "BIND_PW (sandi svc-keycloak) wajib. Contoh: BIND_PW='...' $0"

echo "==> Login kcadm (master/$ADMIN_USER)"
kc config credentials --server http://localhost:8080 --realm master --user "$ADMIN_USER" --password "$ADMIN_PASS" >/dev/null \
  || die "Login kcadm gagal. Cek kredensial admin & keycloak healthy."
ok "login"

echo "==> Realm '$REALM'"
if kc get "realms/$REALM" >/dev/null 2>&1; then ok "sudah ada"; else
  kc create realms -s realm="$REALM" -s enabled=true >/dev/null; ok "dibuat"
fi

echo "==> Federasi LDAP ke Samba AD"
LDAP_ID="$(kc get components -r "$REALM" -q name=ldap --fields id 2>/dev/null | jval id || true)"
if [ -z "$LDAP_ID" ]; then
  LDAP_ID="$(kc create components -r "$REALM" \
    -s name=ldap -s providerId=ldap -s providerType=org.keycloak.storage.UserStorageProvider \
    -s 'config.enabled=["true"]' -s 'config.priority=["0"]' -s 'config.importEnabled=["true"]' \
    -s 'config.editMode=["READ_ONLY"]' -s 'config.syncRegistrations=["false"]' \
    -s 'config.vendor=["ad"]' \
    -s 'config.usernameLDAPAttribute=["sAMAccountName"]' -s 'config.rdnLDAPAttribute=["cn"]' \
    -s 'config.uuidLDAPAttribute=["objectGUID"]' \
    -s 'config.userObjectClasses=["person, organizationalPerson, user"]' \
    -s "config.connectionUrl=[\"ldaps://${DC_HOST}:636\"]" \
    -s "config.usersDn=[\"DC=iamlab,DC=test\"]" \
    -s "config.bindDn=[\"CN=svc-keycloak,OU=AkunLayanan,DC=iamlab,DC=test\"]" \
    -s "config.bindCredential=[\"${BIND_PW}\"]" \
    -s 'config.searchScope=["2"]' -s 'config.pagination=["true"]' \
    -s 'config.useTruststoreSpi=["always"]' -s 'config.connectionPooling=["true"]' \
    -s 'config.trustEmail=["true"]' -s 'config.allowKerberosAuthentication=["false"]' \
    -i 2>/dev/null)" || die "Buat komponen LDAP gagal (cek CA/LDAPS & BIND_PW)."
  ok "provider LDAP dibuat ($LDAP_ID)"
else ok "provider LDAP sudah ada ($LDAP_ID)"; fi

echo "==> Mapper grup (group-ldap-mapper)"
GM_ID="$(kc get components -r "$REALM" -q parent="$LDAP_ID" -q name=group-ldap-mapper --fields id 2>/dev/null | jval id || true)"
if [ -z "$GM_ID" ]; then
  kc create components -r "$REALM" \
    -s name=group-ldap-mapper -s providerId=group-ldap-mapper \
    -s providerType=org.keycloak.storage.ldap.mappers.LDAPStorageMapper -s parentId="$LDAP_ID" \
    -s 'config."groups.dn"=["OU=Grup,DC=iamlab,DC=test"]' \
    -s 'config."group.name.ldap.attribute"=["cn"]' \
    -s 'config."group.object.classes"=["group"]' \
    -s 'config."preserve.group.inheritance"=["false"]' \
    -s 'config."membership.ldap.attribute"=["member"]' \
    -s 'config."membership.attribute.type"=["DN"]' \
    -s 'config."membership.user.ldap.attribute"=["cn"]' \
    -s 'config.mode=["READ_ONLY"]' \
    -s 'config."user.roles.retrieve.strategy"=["LOAD_GROUPS_BY_MEMBER_ATTRIBUTE"]' \
    -s 'config."drop.non.existing.groups.during.sync"=["false"]' >/dev/null
  ok "mapper grup dibuat"
else ok "mapper grup sudah ada"; fi

echo "==> Sinkronisasi (grup lalu user)"
kc create "user-storage/$LDAP_ID/mappers/$GM_ID/sync?direction=fedToKeycloak" -r "$REALM" >/dev/null 2>&1 || true
kc create "user-storage/$LDAP_ID/sync?action=triggerFullSync" -r "$REALM" >/dev/null 2>&1 \
  && ok "sync users dipicu" || echo "  [!] sync user gagal dipicu — jalankan manual: User federation > ldap > Action > Sync all users"

# ---- helper buat/ambil client ----
client_id(){ kc get clients -r "$REALM" -q clientId="$1" --fields id 2>/dev/null | jval id; }

echo "==> Client OIDC 'app-komentar'"
AK_ID="$(client_id app-komentar)"
if [ -z "$AK_ID" ]; then
  AK_ID="$(kc create clients -r "$REALM" -s clientId=app-komentar -s enabled=true \
    -s protocol=openid-connect -s publicClient=false -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s 'redirectUris=["https://app.iamlab.test/callback"]' \
    -s 'webOrigins=["https://app.iamlab.test"]' \
    -s 'attributes."pkce.code.challenge.method"="S256"' -i)"
  ok "dibuat ($AK_ID)"
else ok "sudah ada ($AK_ID)"; fi
# Group Membership mapper pada dedicated scope client (klaim groups)
if ! kc get "clients/$AK_ID/protocol-mappers/models" -r "$REALM" 2>/dev/null | grep -q '"name" : "groups"'; then
  kc create "clients/$AK_ID/protocol-mappers/models" -r "$REALM" \
    -s name=groups -s protocol=openid-connect -s protocolMapper=oidc-group-membership-mapper \
    -s 'config."claim.name"="groups"' -s 'config."full.path"="false"' \
    -s 'config."id.token.claim"="true"' -s 'config."access.token.claim"="true"' \
    -s 'config."userinfo.token.claim"="true"' >/dev/null
  ok "mapper klaim 'groups' ditambahkan"
else ok "mapper klaim 'groups' sudah ada"; fi
AK_SECRET="$(kc get "clients/$AK_ID/client-secret" -r "$REALM" 2>/dev/null | jval value)"

echo "==> Client OIDC 'warpgate'"
WG_ID="$(client_id warpgate)"
if [ -z "$WG_ID" ]; then
  WG_ID="$(kc create clients -r "$REALM" -s clientId=warpgate -s enabled=true \
    -s protocol=openid-connect -s publicClient=false -s standardFlowEnabled=true \
    -s directAccessGrantsEnabled=false \
    -s 'redirectUris=["https://pam.iamlab.test/@warpgate/api/sso/return"]' -i)"
  ok "dibuat ($WG_ID)"
else ok "sudah ada ($WG_ID)"; fi
WG_SECRET="$(kc get "clients/$WG_ID/client-secret" -r "$REALM" 2>/dev/null | jval value)"

echo "==> Client SAML (EntityID = SP mod_auth_mellon)"
SAML_ENTITY='https://saml.iamlab.test/mellon/metadata'
if [ -z "$(client_id "$SAML_ENTITY")" ]; then
  kc create clients -r "$REALM" -s clientId="$SAML_ENTITY" -s enabled=true -s protocol=saml \
    -s 'redirectUris=["https://saml.iamlab.test/*"]' \
    -s 'attributes."saml.assertion.signature"="true"' \
    -s 'attributes."saml.client.signature"="false"' \
    -s 'attributes."saml_name_id_format"="username"' >/dev/null
  ok "dibuat"
else ok "sudah ada"; fi

echo "==> Keamanan realm (brute force + events + SMTP Mailpit)"
kc update "realms/$REALM" \
  -s bruteForceProtected=true -s failureFactor=10 -s waitIncrementSeconds=60 -s maxFailureWaitSeconds=900 \
  -s eventsEnabled=true -s adminEventsEnabled=true -s adminEventsDetailsEnabled=true \
  -s 'eventsListeners=["jboss-logging"]' \
  -s 'smtpServer.host=mailpit' -s 'smtpServer.port=1025' -s 'smtpServer.from=no-reply@iamlab.test' \
  -s 'smtpServer.ssl=false' -s 'smtpServer.starttls=false' -s 'smtpServer.auth=false' >/dev/null \
  && ok "brute-force/events/SMTP diset" || echo "  [!] sebagian setelan realm gagal — set manual (README §6)"

# ---- tulis secret ke deploy/.env agar app-komentar langsung jalan ----
if [ -n "$AK_SECRET" ] && [ -f "$ENV_FILE" ]; then
  if grep -q '^APP_OIDC_CLIENT_SECRET=' "$ENV_FILE"; then
    sed -i "s#^APP_OIDC_CLIENT_SECRET=.*#APP_OIDC_CLIENT_SECRET=${AK_SECRET}#" "$ENV_FILE"
  else echo "APP_OIDC_CLIENT_SECRET=${AK_SECRET}" >> "$ENV_FILE"; fi
  grep -q '^APP_OIDC_CLIENT_ID=' "$ENV_FILE" || echo "APP_OIDC_CLIENT_ID=app-komentar" >> "$ENV_FILE"
  ok "APP_OIDC_CLIENT_SECRET ditulis ke $ENV_FILE"
fi

echo ""
echo "============================ SELESAI (Jalur Cepat Keycloak) ============================"
echo "  Realm '$REALM' siap: federasi LDAP, clients, klaim groups, brute-force/events/SMTP."
echo "  Client secret app-komentar : ${AK_SECRET:-<gagal baca — ambil di Keycloak>}"
echo "  Client secret warpgate     : ${WG_SECRET:-<gagal baca>}   (untuk Sesi 3 warpgate.yaml)"
echo ""
echo "  LANGKAH LANJUTAN (masih manual):"
echo "   1. docker compose up -d app-komentar   # muat ulang app dengan secret baru"
echo "   2. MFA bersyarat (Conditional OTP) — ikuti README §5 (tidak diotomasi)."
echo "   3. Verifikasi klaim groups — README §2 (Clients>app-komentar>Client scopes>Evaluate)."
echo "   4. Bila Members grup kosong — README §1 kotak troubleshooting (sync ulang)."
echo "======================================================================================="
