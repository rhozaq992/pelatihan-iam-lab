# Warpgate (bastion + rekam sesi)

Status: disiapkan (image + volume). Konfigurasi SSO & target = tugas peserta (Lab 4).

## Setup pertama (sekali)
```
docker compose run --rm warpgate warpgate --config /data/warpgate.yaml setup
```
Ikuti wizard: set admin, port HTTP (8888) & SSH (2222), database SQLite di /data.

## Yang dikonfigurasi peserta
- SSO OIDC ke Keycloak (https://kc.iamlab.test/realms/iamlab), MFA wajib
- Target SSH: srv-app01, srv-db01 (role per target)
- Aktifkan perekaman sesi; akses https://pam.iamlab.test dan `ssh -p 2222`

> Pin versi image ke rilis TERPATCH terbaru (≥ 0.28.3) saat build final.
