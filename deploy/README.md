# deploy/ — Stack layanan IAM (Docker)

Jalan di **Docker Desktop (WSL2)** atau **VM Ubuntu** pada VirtualBox/VMware.
AD (Windows Server 2025) ada di VM terpisah (lihat `DC_IP`).

## Menjalankan
```bash
cp .env.example .env            # sesuaikan DC_IP, sandi
# Lab tanpa internet: muat image offline dulu (image di-build perlu pip/apt → tak bisa di VM terisolasi).
docker load -i ../distribusi/offline-images/iam-images.tar
docker compose up -d            # pakai image yang sudah dimuat (tanpa build/pull)
docker compose ps
```
> Menyiapkan saat online? `docker compose pull && docker compose build` lalu `docker save` untuk offline.
> Samba DC (Sesi 1 Bagian A) butuh profil: `docker compose --profile direktori up -d samba-dc`.
Tambahkan ke hosts peserta (atau DNS DC) → IP host Docker:
```
kc.iamlab.test app.iamlab.test saml.iamlab.test grafana.iamlab.test bao.iamlab.test mail.iamlab.test pam.iamlab.test
```

## Endpoint
| Layanan | URL |
|---|---|
| Keycloak | https://kc.iamlab.test |
| App-Komentar | https://app.iamlab.test |
| App-SAML | https://saml.iamlab.test |
| Grafana | https://grafana.iamlab.test |
| OpenBao | https://bao.iamlab.test (API/CLI saja — image ini tanpa web UI) |
| Mailpit | https://mail.iamlab.test |
| Warpgate | https://pam.iamlab.test · ssh -p 2222 |
| Locust | http://localhost:8089 (profil `load`, Sesi 4) |
| Loki (push dari DC) | http://10.10.10.5:3100 |

## Deploy vs. Konfigurasi (prinsip lab)
Infrastruktur **berjalan tetapi belum aman/kosong**; peserta mengonfigurasi keamanan.

| Komponen | Disiapkan (deploy) | Dikonfigurasi peserta |
|---|---|---|
| Keycloak | server + DB + admin bootstrap | realm `iamlab`, federasi LDAP ke AD, client OIDC/SAML, MFA (Google Authenticator), brute force, events |
| App-Komentar | app berjalan (RBAC di server) | isi client OIDC di `.env`, group→role mapper, uji skenario S1–S7 |
| App-SAML | httpd+mellon berjalan | metadata IdP, proteksi `/protected` |
| OpenBao | server uninitialized | init/unseal, audit device, auth LDAP, policy, KV, SSH CA |
| Warpgate | image + volume | setup, SSO OIDC, target, rekam sesi |
| Target SSH | sshd (password auth aktif) | trust SSH CA OpenBao, matikan password auth |
| Monitoring | Loki+Grafana+Alloy (sumber Keycloak terisi) | lengkapi Alloy (OpenBao/Warpgate/sshd/Windows Event), dashboard, alert |
| Locust | berjalan | jalankan profil normal/anomali |

## Simulasi serangan (LAB-ONLY)
```bash
docker compose --profile attack up -d attacker
# jalankan runner berpagar (allowlist iamlab.test):
docker compose exec -e IAMLAB_CONFIRM=1 attacker /attack-sim/run.sh dc1.iamlab.test kerberoast
```
Hanya untuk menguji deteksi/mitigasi di jaringan Host-Only terisolasi. Lihat `../attack-sim/`.

## CA Active Directory (`certs/`)
Keycloak dan OpenBao berfederasi ke `ldaps://dc1.iamlab.test:636`, jadi keduanya harus
memercayai CA AD. Setelah Sesi 1 (langkah LDAPS), salin CA AD dalam format PEM ke
`certs/ad-ca.pem`, lalu `docker compose up -d --force-recreate keycloak openbao`.
Folder ini di-mount ke Keycloak (`/opt/keycloak/conf/truststores`, dipercaya otomatis) dan
OpenBao (`/openbao/certs`). Berkas `*.pem` tidak di-commit.

## Catatan
- AD tidak di compose; Windows Event dikirim oleh Alloy yang dipasang di VM DC (lihat `monitoring/alloy/config.alloy`).
