# Pelatihan: Manajemen Identitas dan Akses Terpusat (IAM)

Laboratorium praktik untuk membangun, mengamankan, dan memantau sistem identitas
terpusat. Seluruh data bersifat **sintetis** (domain `iamlab.test`) dan lab berjalan
**terisolasi** di PC peserta.

> ⚠️ **Etika & lingkup.** Topik serangan (Pass-the-Hash, Kerberoasting) dibahas
> secara **defensif** — hanya untuk menguji deteksi & mitigasi, memakai perkakas
> _open source_ standar (Impacket) yang **dikunci ke target lab** dan dijalankan di
> jaringan **Host-Only tanpa internet**. Jangan gunakan di luar lab.

## Sesi

| Sesi | Topik | Indikator | Folder |
|------|-------|-----------|--------|
| 1 | Pengamanan Direktori (AD/LDAP) & GPO; simulasi terkendali | 1.1, 1.2 | [`sesi-1-direktori-gpo/`](sesi-1-direktori-gpo/) |
| 2 | SSO & MFA (Keycloak) + App-Komentar RBAC | 2.1, 2.2 | [`sesi-2-sso-mfa/`](sesi-2-sso-mfa/) |
| 3 | Privileged Access Management (OpenBao + Warpgate) | 3.1, 3.2 | [`sesi-3-pam/`](sesi-3-pam/) |
| 4 | Audit & Monitoring (Alloy/Loki/Grafana) + capstone | 4.1, 4.2 | [`sesi-4-audit-monitoring/`](sesi-4-audit-monitoring/) |

## Arsitektur

- **AD**: Windows Server 2025 di VMware (Tier 0: DC, DNS, Kerberos, GPO) — Sesi 1.
- **Stack layanan** (Docker): Keycloak + PostgreSQL, OpenBao, Warpgate, Caddy
  (reverse proxy + CA internal), Mailpit, Grafana/Loki/Alloy, Locust, App-Komentar
  (RBAC), App-SAML, target SSH.
- Jaringan Host-Only, domain `iamlab.test`.

## Prasyarat & cara menjalankan

1. Baca [`docs/quickstart.md`](docs/quickstart.md) (prasyarat PC + langkah awal).
2. Siapkan AD (Windows Server 2025) di VMware — lihat Sesi 1.
3. Jalankan stack layanan:
   ```bash
   cd deploy
   cp .env.example .env          # sesuaikan DC_IP & sandi
   docker compose up -d --build
   ```
   Endpoint & detail: [`deploy/README.md`](deploy/README.md).
4. Ikuti modul per sesi secara berurutan.

## Struktur

| Folder | Isi |
|--------|-----|
| `deploy/` | Yang perlu di-deploy: compose + konfigurasi stack + aplikasi |
| `sesi-1..4/` | Modul praktik per sesi (langkah + hasil yang diharapkan) |
| `attack-sim/` | Runner simulasi berpagar (allowlist lab) |
| `docs/` | Quickstart & distribusi aset berat |
| `instruktur/` | Kunci & formulir (khusus instruktur) |
| `distribusi/` | Tempat aset berat (ISO/OVA/image) yang dibagikan manual |

> File berat (ISO/OVA/image) **tidak** disimpan di Git — dibagikan manual lewat
> `distribusi/` (lihat [`docs/distribusi.md`](docs/distribusi.md)).

## Lisensi komponen

Komponen inti _open source_: Keycloak (Apache-2.0), OpenBao (MPL-2.0), Warpgate
(Apache-2.0), Grafana/Loki (AGPL-3.0), Caddy (Apache-2.0), Locust (MIT), dll.
Windows Server memakai edisi evaluasi.
