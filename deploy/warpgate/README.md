# Warpgate (bastion + rekam sesi)

Status: disiapkan (image + volume). Konfigurasi SSO & target = tugas peserta (Sesi 3).

## Setup pertama (sekali)
```
docker compose run --rm warpgate unattended-setup --data-path /data --http-port 8888 \
  --ssh-port 2222 --record-sessions --host-key-verification auto-accept \
  --admin-password 'Warp#Lab2026' --external-host pam.iamlab.test
```
Perintah unattended membuat config /data/warpgate.yaml + akun admin tanpa wizard interaktif.

## Yang dikonfigurasi peserta
- SSO OIDC ke Keycloak (https://kc.iamlab.test/realms/iamlab), MFA wajib
- Target SSH: srv-app01, srv-db01 (role per target)
- Aktifkan perekaman sesi; akses https://pam.iamlab.test dan `ssh -p 2222`

> Pin versi image ke rilis TERPATCH terbaru (≥ 0.28.3) saat build final.
