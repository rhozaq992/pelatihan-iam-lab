# Lab 4 — Privileged Access (OpenBao + Warpgate) (85') · Indikator 3.1, 3.2

**Tujuan:** amankan kredensial & pusatkan akses istimewa via bastion terekam.

## A. OpenBao (CLI di host Docker)
```bash
export BAO_ADDR=https://bao.iamlab.test        # via Caddy; atau http://localhost:8200 bila dipublikasi
alias bao='docker compose exec -e BAO_ADDR=http://127.0.0.1:8200 openbao bao'
# 1. init (3 share / ambang 2) — SIMPAN output dengan aman
bao operator init -key-shares=3 -key-threshold=2
# 2. unseal (jalankan 2x dengan unseal key berbeda)
bao operator unseal <key1> ; bao operator unseal <key2>
bao login <root-token>
# 3. audit device file (SEBELUM menyimpan rahasia)
bao audit enable file file_path=/openbao/file/audit.log
# 4. auth LDAP ke AD
bao auth enable ldap
bao write auth/ldap/config url="ldaps://dc1.iamlab.test:636" \
  userdn="OU=Pengguna,DC=iamlab,DC=test" groupdn="OU=Grup,DC=iamlab,DC=test" \
  binddn="CN=svc-openbao,OU=AkunLayanan,DC=iamlab,DC=test" bindpass="***" \
  userattr=sAMAccountName insecure_tls=false
# policy least privilege + map grup
bao policy write admin-t1 - <<'HCL'
path "kv/data/breakglass/*" { capabilities=["read"] }
path "ssh/sign/t1"          { capabilities=["update"] }
HCL
bao write auth/ldap/groups/GG-Tier1-Admin policies=admin-t1
# 5. KV break-glass
bao secrets enable -path=kv kv-v2
bao kv put kv/breakglass/srv-app01 user=root pass='BreakGlass#2026'
# 6. SSH CA
bao secrets enable ssh
bao write ssh/config/ca generate_signing_key=true
bao read -field=public_key ssh/config/ca   # → pasang di target (bagian B)
bao write ssh/roles/t1 key_type=ca allow_user_certificates=true default_user=labadmin ttl=30m
# 7. GATED: pastikan login LDAP admin BERHASIL dulu, simpan unseal key, BARU:
bao token revoke <root-token>
```

## B. Target percaya SSH CA
Jalankan dari HOST (CA pub diambil dari OpenBao lalu disalurkan ke target — `bao` tidak ada di dalam container target):
```bash
for t in srv-app01 srv-db01; do
  docker compose exec -e BAO_ADDR=http://127.0.0.1:8200 openbao bao read -field=public_key ssh/config/ca \
    | docker compose exec -T $t tee /etc/ssh/openbao_ca.pub >/dev/null
  docker compose exec $t sh -c 'printf "\nTrustedUserCAKeys /etc/ssh/openbao_ca.pub\nPasswordAuthentication no\nPermitRootLogin no\n" >> /etc/ssh/sshd_config; kill -HUP 1'
done
```

## C. Warpgate (bastion + rekam sesi)
```bash
docker compose run --rm warpgate warpgate --config /data/warpgate.yaml setup
docker compose up -d warpgate
```
Di `https://pam.iamlab.test`: aktifkan **SSO OIDC** ke Keycloak (MFA wajib), tambah target
`srv-app01`/`srv-db01` (role per target), **aktifkan perekaman sesi**. Uji `ssh -p 2222`.

## D. Serah-terima kredensial
Isi formulir (lihat `solutions/` / lampiran) untuk simulasi break-glass, lalu rotasi sandi.

## Hasil yang diharapkan
- OpenBao unsealed, audit aktif, root token tak valid, login LDAP admin berfungsi.
- Target menolak password; akses hanya via sertifikat CA / bastion.
- Sesi Warpgate terekam & dapat diputar ulang.
