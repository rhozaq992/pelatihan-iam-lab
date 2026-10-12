# Pelatihan: Manajemen Identitas dan Akses Terpusat (IAM)

Modul praktik untuk membangun, mengamankan, dan memantau sistem identitas terpusat.
Seluruh data bersifat **sintetis** (domain `iamlab.test`) dan lab berjalan
**terisolasi** di PC peserta.

> ⚠️ **Etika & lingkup.** Topik serangan (Pass-the-Hash, Kerberoasting) dibahas
> secara **defensif** — hanya untuk menguji deteksi & mitigasi, memakai perkakas
> _open source_ standar yang dikunci ke target lab, di jaringan Host-Only tanpa
> internet. Jangan gunakan di luar lab.

## Cara memakai modul

Mulai dari **Sesi 0** untuk gambaran utuh sistem dan teori dasar, lalu kerjakan
Sesi 1–4 berurutan. Tiap sesi disusun dengan struktur yang sama:

- **a. Tujuan Sesi** — kompetensi yang dituju.
- **b. Output yang Diharapkan** — hasil yang mesti terlihat.
- **c. Teori dan Struktur Sistem** — konsep dan posisi komponen.
- **d. Praktik: Instalasi dan Konfigurasi** — langkah yang dikerjakan peserta.

## Daftar Sesi

| Sesi | Topik | Indikator |
|------|-------|-----------|
| [0](sesi-0-pengantar/) | Pengantar: topologi sistem & teori dasar | — |
| [1](sesi-1-direktori-gpo/) | Pengamanan Direktori (AD/LDAP) & GPO; simulasi terkendali | 1.1, 1.2 |
| [2](sesi-2-sso-mfa/) | SSO & MFA (Keycloak) + App-Komentar (RBAC) | 2.1, 2.2 |
| [3](sesi-3-pam/) | Privileged Access Management (OpenBao + Warpgate) | 3.1, 3.2 |
| [4](sesi-4-audit-monitoring/) | Audit & Monitoring (Alloy/Loki/Grafana) + capstone | 4.1, 4.2 |

## Catatan

Lingkungan lab (VM Active Directory dan stack layanan Docker) disiapkan terlebih
dahulu; peserta berfokus pada **konfigurasi keamanan** di tiap sesi, bukan instalasi
dari nol. Detail arsitektur dan aliran data ada di [Sesi 0](sesi-0-pengantar/).
