# Jalur Cepat (opsional) — Sesi 2

> **Kapan dipakai?** HANYA bila Anda **stuck** melakukan konfigurasi manual di konsol Keycloak
> (README §1–§5) dan ingin **lanjut ke lab berikutnya**. Langkah manual tetap jalur utama
> pembelajaran — skrip ini pintasan darurat, bukan pengganti pemahaman.

## Isi
| Berkas | Fungsi |
|--------|--------|
| `setup-keycloak.sh` | Menyiapkan realm `iamlab` otomatis via `kcadm` (federasi LDAP + mapper grup + clients app-komentar/warpgate/app-saml + klaim `groups` + brute-force/events/SMTP). |

## Prasyarat
- Stack lab **up** dan Keycloak **healthy** (`docker compose ps keycloak` → `healthy`).
- **Prasyarat Sesi 1 langkah 5b** sudah dilakukan: CA Samba ada di `deploy/certs/ad-ca.pem` dan
  Keycloak di-*recreate* — tanpa ini koneksi LDAPS gagal (PKIX).
- Anda tahu **sandi `svc-keycloak` terbaru** (diset di Sesi 1 langkah 5).

## Cara pakai
```bash
# dari folder deploy (IAMLAB-BuildBag/deploy)
cd ../../..            # bila Anda di folder jalur-cepat; sesuaikan hingga berada di IAMLAB-BuildBag
cd deploy
BIND_PW='<sandi svc-keycloak terbaru>' \
  ../Pelatihan_IAM/sesi-2-sso-mfa/jalur-cepat/setup-keycloak.sh
```
Opsi env (opsional): `KC_ADMIN_USER`, `KC_ADMIN_PASS` (default dibaca dari `.env`
`KC_BOOTSTRAP_ADMIN_*`), `REALM` (default `iamlab`), `DC_HOST` (default `dc1.iamlab.test`).

Skrip **idempoten** — aman dijalankan ulang (yang sudah ada dilewati).

## Setelah skrip selesai (masih manual — sengaja)
1. `docker compose up -d app-komentar` — muat ulang app dengan `APP_OIDC_CLIENT_SECRET` baru
   (skrip sudah menuliskannya ke `deploy/.env`).
2. **MFA bersyarat (Conditional OTP)** — **tidak** diotomasi; ikuti **README §4**. Alur
   autentikasi terlalu rinci/variatif antar versi untuk diskrip dengan aman.
3. Secret `warpgate` dicetak di akhir skrip — pakai di **Sesi 3** (`warpgate.yaml`).

## Verifikasi (opsional)
- Klaim `groups`: **README §2** (Clients → app-komentar → Client scopes → **Evaluate**).
- Grup kosong anggotanya: **README §1** (kotak troubleshooting — biasanya cukup *Sync all users* ulang).

> ⚠️ **Catatan.** Skrip ini divalidasi penuh saat fasilitator menjalankan lab dari awal. Bila
> satu perintah `kcadm` gagal di lab Anda, skrip menyebut langkah manual padanannya di README —
> kerjakan bagian itu saja lalu lanjut. Tujuannya: **jangan sampai terhenti di satu lab**.
