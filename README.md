# Pelatihan: Manajemen Identitas dan Akses Terpusat (IAM)

Modul praktik untuk membangun, mengamankan, dan memantau sistem identitas terpusat.
Seluruh data bersifat **sintetis** (domain `iamlab.test`) dan lab berjalan **terisolasi**
di PC peserta.

> ⚠️ **Etika & lingkup.** Topik serangan (Pass-the-Hash, Kerberoasting) dibahas secara
> **defensif** — hanya untuk menguji deteksi & mitigasi, memakai perkakas *open source*
> standar yang dikunci ke target lab, di jaringan Host-Only tanpa internet.

## Memulai (setelah `git clone`)

```bash
cd deploy
cp .env.example .env            # sesuaikan DC_IP & sandi
# Lab Host-Only tanpa internet → muat image yang sudah disiapkan (USB/share lokal) lebih dulu.
# Image di-build butuh internet (pip/apt), jadi JANGAN andalkan auto-build di VM terisolasi.
docker load -i ../distribusi/offline-images/iam-images.tar
docker compose up -d            # image sudah ada → langsung menyala, tanpa build/pull
docker compose ps
```
> Punya internet saat menyiapkan? Boleh bangun sendiri: `docker compose pull && docker compose build`
> (lalu `docker save` untuk distribusi offline — lihat `distribusi/download.sh`).
> Catatan: setelah `up`, **OpenBao** menyala dalam keadaan *sealed* (perlu init/unseal di
> Sesi 3) dan **Warpgate** akan keluar sampai di-*setup* sekali (Sesi 3) — ini normal.

Tambahkan subdomain `*.iamlab.test` ke berkas `hosts` (atau DNS DC) → IP host Docker.
Rincian endpoint & pengelolaan: [`deploy/README.md`](deploy/README.md). Lalu ikuti modul
mulai [Sesi 0](sesi-0-pengantar/).

## Peta Direktori

| Path | Isi | Dijalankan? |
|------|-----|-------------|
| `deploy/` | **Yang di-deploy**: `compose.yaml` + konfigurasi (Caddy, Keycloak, OpenBao, Warpgate, monitoring) + aplikasi | `docker compose up -d` |
| `sesi-0-pengantar/` | Pengantar: topologi + teori dasar | baca dulu |
| `sesi-1-direktori-gpo/` | Pengamanan AD/LDAP & GPO + simulasi + skrip provisioning (`import-ad.ps1`, CSV) | ikuti modul |
| `sesi-2-sso-mfa/` | SSO & MFA (Keycloak) + App-Komentar RBAC | ikuti modul |
| `sesi-3-pam/` | OpenBao (vault) + Warpgate (bastion) | ikuti modul |
| `sesi-4-audit-monitoring/` | Alloy/Loki/Grafana + capstone | ikuti modul |
| `attack-sim/` | Runner simulasi berpagar (dipakai Sesi 1) | via compose profil |
| `distribusi/` | **Kosong di Git** — tempat ISO/OVA/image yang dibagikan manual | lihat README-nya |

## Alur Sesi (saling menyambung)

Tiap sesi **membangun di atas sesi sebelumnya** memakai data yang sama:

```
Sesi 1 (AD: OU, grup GG-*, akun svc-*, kebijakan sandi)
   └─► Sesi 2 (Keycloak federasi ke AD via svc-keycloak; grup GG-App-* → peran; MFA)
          └─► Sesi 3 (Warpgate SSO ke Keycloak; OpenBao auth LDAP via svc-openbao + GG-Tier1-Admin)
                 └─► Sesi 4 (audit semua event Sesi 1–3 → dashboard & deteksi)
```

## Prasyarat PC peserta

- Windows, RAM ≥ 16 GB (disarankan 32 GB), disk ≥ 120 GB, virtualisasi (VT-x/AMD-V) aktif.
- VMware Workstation Pro (gratis) untuk VM Windows Server 2025 (DC); Docker untuk stack layanan.
- Google Authenticator / FreeOTP di ponsel.

> Aset berat (ISO/OVA/image) **tidak** di Git — dibagikan manual lewat `distribusi/`
> (lihat [`distribusi/README.md`](distribusi/README.md)).

## Lisensi komponen

Komponen inti *open source*: Keycloak (Apache-2.0), OpenBao (MPL-2.0), Warpgate
(Apache-2.0), Grafana/Loki (AGPL-3.0), Caddy (Apache-2.0), Locust (MIT), dll. Windows
Server memakai edisi evaluasi.
