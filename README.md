# Pelatihan: Manajemen Identitas dan Akses Terpusat (IAM)

Modul praktik untuk membangun, mengamankan, dan memantau sistem identitas terpusat.
Seluruh data bersifat **sintetis** (domain `iamlab.test`) dan lab berjalan **terisolasi**
di PC peserta.

> ⚠️ **Etika & lingkup.** Topik serangan (Pass-the-Hash, Kerberoasting) dibahas secara
> **defensif** — hanya untuk menguji deteksi & mitigasi, memakai perkakas *open source*
> standar yang dikunci ke target lab, di jaringan Host-Only tanpa internet.

## Memulai

Seluruh lab dibangun satu skrip di **PowerShell (Administrator)** pada PC Windows peserta:
```powershell
cd <folder-repo>
Set-ExecutionPolicy -Scope Process Bypass -Force
.uild-lab.ps1          # Check -> Requirements -> Download -> Install -> Build
```
Skrip memasang VirtualBox + Docker Desktop (bila belum ada), menjalankan stack layanan
(termasuk Samba AD `dc1`), lalu membuat VM Ubuntu `srv1` & `client1` di jaringan Host-Only
`10.10.10.0/24`. Rinciannya di [Sesi 0](sesi-0-pengantar/README.md#deploy-awal-satu-skrip).
Untuk kelas, panitia memakai **paket build** siap-serah ([`build-bag/`](build-bag/README.md)).

> Setelah build: **OpenBao** menyala *sealed* (init/unseal di Sesi 3) dan **Warpgate** perlu
> *setup* sekali (Sesi 3) — ini normal. Endpoint & pengelolaan: [`deploy/README.md`](deploy/README.md).

## Peta Direktori

| Path | Isi | Dijalankan? |
|------|-----|-------------|
| `build-lab.ps1` | **Pembangun lab** di PC Windows (cek sistem, pasang deps, stack Docker, VM Ubuntu) | `.\build-lab.ps1` |
| `ALUR-PESERTA.md` | **Storyboard** langkah peserta semua sesi + checklist validasi | baca |
| `build-bag/` | Pembuat paket instalasi siap-serah untuk panitia | `build-bag/make-build-bag.ps1` |
| `lab/` | Berkas untuk VM: cloud-init, skrip (`join-domain.sh`, `cis-scan.sh`), Alloy host, aturan auditd | dipakai `build-lab.ps1` |
| `deploy/` | **Stack Docker**: `compose.yaml` + konfigurasi (Caddy, Keycloak, OpenBao, Warpgate, monitoring, **Samba AD**) + aplikasi | `docker compose up -d` |
| `sesi-0-pengantar/` | Pengantar: topologi + teori dasar | baca dulu |
| `sesi-1-direktori-akses-cis/` | Pengamanan Samba AD/LDAP, join domain, kebijakan akses & CIS + `import-ad.sh`, CSV | ikuti modul |
| `sesi-2-sso-mfa/` | SSO & MFA (Keycloak) + App-Komentar RBAC | ikuti modul |
| `sesi-3-pam/` | OpenBao (vault) + Warpgate (bastion) | ikuti modul |
| `sesi-4-audit-monitoring/` | Alloy/Loki/Grafana + capstone | ikuti modul |
| `attack-sim/` | Runner simulasi berpagar (dipakai Sesi 1) | via compose profil |
| `distribusi/` | Aset berat offline (`iam-images.tar`, installer) dibagikan manual (tidak di Git) | lihat README-nya |

## Alur Sesi (saling menyambung)

Tiap sesi **membangun di atas sesi sebelumnya** memakai data yang sama:

```
Sesi 1 (Samba AD: OU, grup GG-*, akun svc-*; join srv1/client1; kebijakan akses; CIS)
   └─► Sesi 2 (Keycloak federasi ke Samba AD via svc-keycloak; grup GG-App-* → peran; MFA)
          └─► Sesi 3 (Warpgate SSO ke Keycloak; OpenBao auth LDAP via svc-openbao + GG-Tier1-Admin; target srv1)
                 └─► Sesi 4 (audit event Sesi 1–3 + aktivitas user srv1/client1 → dashboard & deteksi)
```

## Prasyarat PC peserta

- Windows 10/11 Pro, RAM 16 GB, disk kosong ≥ 80 GB, virtualisasi (VT-x/AMD-V) aktif.
- VirtualBox (VM Ubuntu `srv1`/`client1`) + Docker Desktop (layanan IAM & Samba AD) — keduanya dipasang otomatis oleh `build-lab.ps1`.
- Google Authenticator / FreeOTP di ponsel.

> Aset berat (image Docker, installer) **tidak** di Git — dibagikan manual lewat `distribusi/`
> atau paket build (lihat [`build-bag/README.md`](build-bag/README.md)).

## Lisensi komponen

Komponen inti *open source*: Samba (GPL-3.0), Keycloak (Apache-2.0), OpenBao (MPL-2.0),
Warpgate (Apache-2.0), Grafana/Loki (AGPL-3.0), Caddy (Apache-2.0), Locust (MIT),
OpenSCAP + SCAP Security Guide (CIS, LGPL/public), Ubuntu 24.04 LTS. Tanpa komponen berbayar.
