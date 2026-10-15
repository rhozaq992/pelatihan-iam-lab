# Pelatihan: Manajemen Identitas dan Akses Terpusat (IAM) — Modul Peserta

Repositori ini berisi **modul praktik** untuk peserta pelatihan IAM: membangun, mengamankan, dan
memantau sistem identitas terpusat. Seluruh data bersifat **sintetis** (domain `iamlab.test`) dan
lab berjalan **terisolasi** (jaringan Host-Only, tanpa internet).

> ⚠️ **Etika & lingkup.** Topik serangan (Pass-the-Hash, Kerberoasting) dibahas secara
> **defensif** — hanya untuk menguji deteksi & mitigasi, memakai perkakas *open source*
> standar yang dikunci ke target lab, di jaringan terisolasi.

## Lab sudah disiapkan fasilitator

Infrastruktur lab (Docker stack + Samba AD `dc1`, VM Ubuntu `srv1` & `client1`) **dibangun oleh
fasilitator sebelum pelatihan** memakai paket **IAMLAB-BuildBag** (di luar repo ini). Peserta
**tidak perlu** menjalankan `build-lab.ps1` atau memasang apa pun.

**Yang dilakukan peserta** di PC lab yang sudah disiapkan:

```powershell
# 1. masuk ke folder builder yang sudah disiapkan fasilitator
cd C:\Lab\IAMLAB-BuildBag
# 2. ambil modul (repo ini) ke dalam folder builder
git clone <url-repo> Pelatihan_IAM
# 3. mulai dari Sesi 0
cd Pelatihan_IAM
```

Hasil akhir tata letak di PC lab:

```
IAMLAB-BuildBag\            <- disiapkan fasilitator (stack + VM sudah jalan)
├─ build-lab.ps1  deploy\  lab\  attack-sim\  distribusi\
└─ Pelatihan_IAM\          <- modul ini (git clone)
   └─ sesi-0..4\ , README.md , ALUR-PESERTA.md
```

> **Menjalankan perintah lab.** Stack Docker ada di `IAMLAB-BuildBag\deploy`. Dari folder modul
> (`Pelatihan_IAM`), perintah `docker compose …` dijalankan setelah `cd ../deploy`. File modul yang
> perlu disalin ke container dirujuk sebagai `../Pelatihan_IAM/sesi-…` (lihat tiap sesi).

## Peta modul

| Path | Isi |
|------|-----|
| `sesi-0-pengantar/` | Pengantar: topologi + teori dasar — **baca dulu** |
| `sesi-1-direktori-akses-cis/` | Pengamanan Samba AD/LDAP, join domain, kebijakan akses & CIS (+ `import-ad.sh`, CSV) |
| `sesi-2-sso-mfa/` | SSO & MFA (Keycloak) + App-Komentar RBAC |
| `sesi-3-pam/` | OpenBao (vault) + Warpgate (bastion) |
| `sesi-4-audit-monitoring/` | Alloy/Loki/Grafana + capstone |
| `ALUR-PESERTA.md` | Storyboard langkah peserta semua sesi + checklist validasi |

> Infrastruktur build (`build-lab.ps1`, `deploy/`, `lab/`, `attack-sim/`, `distribusi/`) **tidak**
> ada di repo ini — semuanya di paket **IAMLAB-BuildBag** milik fasilitator.

## Alur Sesi (saling menyambung)

Tiap sesi **membangun di atas sesi sebelumnya** memakai data yang sama:

```
Sesi 1 (Samba AD: OU, grup GG-*, akun svc-*; join srv1/client1; kebijakan akses; CIS)
   └─► Sesi 2 (Keycloak federasi ke Samba AD via svc-keycloak; grup GG-App-* → peran; MFA)
          └─► Sesi 3 (Warpgate SSO ke Keycloak; OpenBao auth LDAP via svc-openbao + GG-Tier1-Admin; target srv1)
                 └─► Sesi 4 (audit event Sesi 1–3 + aktivitas user srv1/client1 → dashboard & deteksi)
```

## Yang perlu peserta siapkan

- Akun di PC lab (disiapkan fasilitator) dengan VirtualBox + Docker Desktop sudah terpasang & lab berjalan.
- Google Authenticator / FreeOTP di ponsel (untuk MFA di Sesi 2).

## Lisensi komponen

Komponen inti *open source*: Samba (GPL-3.0), Keycloak (Apache-2.0), OpenBao (MPL-2.0),
Warpgate (Apache-2.0), Grafana/Loki (AGPL-3.0), Caddy (Apache-2.0), Locust (MIT),
OpenSCAP + SCAP Security Guide (CIS, LGPL/public), Ubuntu 24.04 LTS. Tanpa komponen berbayar.
