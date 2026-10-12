# Pelatihan: Manajemen Identitas dan Akses Terpusat (IAM)

Laboratorium praktik 8 jam (1 hari) untuk membangun, mengamankan, dan memantau
sistem identitas terpusat. Seluruh data bersifat **sintetis** (domain `iamlab.test`)
dan lab berjalan **terisolasi** di PC peserta.

> ⚠️ **Etika & lingkup:** Topik serangan (Pass-the-Hash, Kerberoasting) dibahas
> secara **defensif** — hanya untuk menguji deteksi & mitigasi, memakai perkakas
> open source standar (Impacket) yang **dikunci ke target lab** dan dijalankan di
> jaringan **Host-Only tanpa internet**. Jangan gunakan di luar lab.

## Materi (indikator kompetensi)
1. Pengamanan Direktori (AD) & GPO — hardening, Pass-the-Hash & Kerberoasting (mitigasi/deteksi)
2. SSO & MFA — SAML/OIDC dengan Keycloak, federasi LDAP, Google Authenticator (OTP)
3. Privileged Access Management — OpenBao (vault) + Warpgate (bastion, rekam sesi)
4. Audit & Monitoring — Alloy → Loki → Grafana, UBA dasar, deteksi akun kompromi

## Arsitektur (ringkas)
- **AD**: Windows Server 2025 di VMware Workstation Pro (Tier 0: DC, DNS, Kerberos, GPO)
- **Stack lain**: Keycloak, OpenBao, Warpgate, Caddy, Mailpit, Grafana/Loki/Alloy,
  Locust, App-Komentar (RBAC) — di **Docker Desktop (WSL2)** *atau* VM Ubuntu
- Jaringan Host-Only (VMnet), domain `iamlab.test`

Lihat dokumen riset lengkap + topologi: [`docs/`](docs/).

## Struktur repo
| Folder | Isi |
|---|---|
| `docs/` | Dokumen riset & kesiapan lab (DOCX) |
| `lab/` | compose + konfigurasi stack (dikerjakan pada fase build) |
| `modul/` | Panduan peserta per lab (Lab 0–6) |
| `attack-sim/` | Runner simulasi berpagar (allowlist lab) |
| `data/` | Generator data dummy + CSV |
| `solutions/` | Konfigurasi solusi (khusus instruktur) |

> File berat (ISO/OVA/image) **tidak** disimpan di Git — dibagikan manual lewat
> folder `distribusi/` (lihat `distribusi/README.md`).

## Kebutuhan PC peserta
- Windows, RAM **≥ 16 GB** (disarankan 32 GB), disk ≥ 120 GB, VT-x/AMD-V aktif
- VMware Workstation Pro (gratis) + VMware Tools, dan Docker Desktop (profil ringan)
- Google Authenticator / FreeOTP di ponsel

## Lisensi komponen
Seluruh komponen inti bersifat open source (Keycloak Apache-2.0, OpenBao MPL-2.0,
Warpgate Apache-2.0, Grafana/Loki AGPL-3.0, Locust MIT, dll.). Windows Server
memakai edisi evaluasi.
