# Sesi 0 — Pengantar: Topologi Sistem & Teori Dasar

Sesi pembuka. Tujuannya memberi **gambaran umum** sistem IAM yang akan dibangun dan
**fondasi teori** yang dipakai berulang di sesi berikutnya. Detail teknis diperdalam
per sesi (`sesi-1` … `sesi-4`).

## Konvensi "di mana perintah dijalankan"

Sepanjang modul, setiap langkah diberi penanda tempat eksekusi agar tidak ambigu:

| Penanda | Tempat menjalankan |
|---------|--------------------|
| 🪟 **PowerShell (host)** | Di PC Windows peserta, PowerShell **Administrator** (mis. `build-lab.ps1`, `VBoxManage`). |
| 🐳 **Container (dc1/svc)** | Masuk ke container lewat `docker compose exec <service> …` (mis. `samba-dc` untuk `samba-tool`, `openbao`). |
| 🖥️ **VM Ubuntu** | Di dalam VM `srv1`/`client1` (SSH atau konsol VirtualBox), mis. `sudo join-domain.sh`, `sudo cis-scan.sh`. |
| 🌐 **Web UI** | Di browser peserta: Keycloak, Grafana, Warpgate, Mailpit. |

## a. Tujuan Sesi

Peserta memahami:
- Topologi dan Gambaran Umum keseluruhan sistem (komponen, jaringan, aliran data) sebelum masuk praktik.
- Konsep dasar identitas: **IAAA** (Identifikasi, Autentikasi, Otorisasi, Audit).
- Peran **AD/LDAP**, **SSO (SAML/OIDC)**, **MFA**, **PAM**, dan **audit/UBA** serta
  bagaimana semuanya saling terhubung.

## b. Output yang Diharapkan

- Peserta dapat menjelaskan alur "pengguna → aplikasi → IdP → direktori" dengan kata sendiri.
- Peserta mengenali posisi dan fungsi tiap komponen pada topologi.
- Lingkungan lab siap: VM AD berjalan, stack layanan berjalan, nama domain teruji.

## c. Teori Dasar

### Apa itu IAM dan mengapa "terpusat"?
**IAM (Identity & Access Management)** adalah disiplin mengelola *siapa boleh
mengakses apa, kapan, dan bagaimana membuktikannya*. Rangkanya adalah **IAAA**:

| Pilar | Makna | Tujuan | Analogi |
|------|-----------------|-------------------|---------|
| **Identifikasi** | Pengguna mengaku sebagai siapa (username) | Titik awal semua kontrol | Menyebut nama di resepsionis |
| **Autentikasi** | Membuktikan klaim identitas (faktor: sandi, OTP, biometrik) | Mencegah peniruan | Menunjukkan KTP + segel sekali pakai |
| **Otorisasi** | Menentukan hak (peran/izin) | Membatasi akses sesuai kebutuhan (*least privilege*) | Kartu hanya membuka lantai tertentu |
| **Audit** | Mencatat aktivitas | Pembuktian & deteksi penyalahgunaan | Buku tamu + CCTV |

Pihak yang terlibat adalah pengguna akhir, administrator (akun istimewa), akun layanan
(aplikasi), dan auditor. Kontrol bekerja saat login (autentikasi), saat mengakses fitur
(otorisasi), dan terus-menerus (audit). Identitas terpusat memindahkan keempat pilar dari
tiap aplikasi ke **satu direktori** (sumber kebenaran) dan **satu IdP** (gerbang): aplikasi
mendelegasikan login ke IdP, IdP memverifikasi ke direktori lalu menerbitkan token/assertion
yang dipercaya aplikasi.

_Analogi:_ dari "tiap pintu punya daftar tamu sendiri" menjadi "satu lobi, satu
petugas, satu buku tamu" — kebijakan konsisten, penonaktifan akun berlaku serentak,
jejak audit terkumpul di satu tempat.

### Komponen & perannya (dipetakan ke sesi)
- **Active Directory (AD/LDAP)** — direktori + *control plane* identitas: pengguna,
  grup, Kerberos, DNS, Group Policy. *(Sesi 1)*
- **Keycloak (Identity Provider)** — gerbang SSO yang memverifikasi ke direktori,
  menerbitkan token/assertion, dan menambahkan **MFA**. *(Sesi 2)*
- **MFA (Google Authenticator / TOTP)** — faktor "something you have" selain password
  "something you know". *(Sesi 2)*
- **PAM (OpenBao + Warpgate)** — brankas kredensial + *jump server* yang
  merekam sesi akses admin. *(Sesi 3)*
- **Audit & Monitoring (Alloy → Loki → Grafana)** — mengumpulkan log identitas dan
  menampilkan dashboard + alert; **UBA** mendeteksi perilaku tak lazim. *(Sesi 4)*

### Protokol federasi (ringkas — diperdalam di Sesi 2)
- **SAML 2.0** — autentikasi + atribut via XML Assertion bertanda tangan.
- **OAuth 2.0** — otorisasi akses sumber daya (bukan login).
- **OpenID Connect (OIDC)** — lapisan identitas di atas OAuth 2.0; token = ID Token
  (JWT). Alur aman lab: **Authorization Code + PKCE**.

_Analogi SSO:_ gelang masuk festival — diperiksa sekali di gerbang (IdP), lalu semua
panggung (aplikasi) menerimanya tanpa periksa ulang identitas.

## d. Struktur Sistem (Topologi)

Seluruh lab berjalan terisolasi di PC peserta (jaringan Host-Only `10.10.10.0/24`, tanpa
internet), domain sintetis **`iamlab.test`**. **Direktori AD/LDAP = Samba AD DC** yang
berjalan sebagai container bersama layanan lain di **Docker Desktop**; dua **VM Ubuntu**
(VirtualBox) menjadi server & klien yang bergabung ke domain.

Diagram berikut membagi sistem menjadi **tiga segmen** — Direktori & Klien, Layanan IAM,
dan Observability — dengan alur data/aktivitas **bernomor** yang dijelaskan pada *Agenda
Aktivitas* di bawahnya.

![Arsitektur & alur IAM — 3 partisi (Direktori & Klien · Layanan IAM · Observability) dengan alur bernomor](gambar/arsitektur.png)

*Gambar 1. Arsitektur & alur IAM (3 partisi, alur bernomor)*

**Agenda Aktivitas (penjelasan nomor pada diagram):**

| # | Aktivitas | Sistem terhubung |
|---|-----------|------------------|
| **1** | Pengguna membuka aplikasi/konsol lewat HTTPS; TLS diterminasi reverse proxy | Klien Ubuntu → **Caddy** |
| **2** | Proxy meneruskan permintaan login ke Identity Provider (SSO) | Caddy → **Keycloak** |
| **3** | Keycloak memverifikasi kredensial & menarik atribut/grup lewat LDAPS 636 | Keycloak → **Samba AD DC (dc1)** |
| **4** | Akses istimewa diarahkan ke bastion; login bastion memakai SSO Keycloak + MFA | Klien Ubuntu ⇢ **Warpgate** |
| **5** | Bastion mengambil kredensial *break-glass* / meminta sertifikat SSH berumur pendek | Warpgate → **OpenBao (Vault/SSH CA)** |
| **6** | Sesi SSH diteruskan ke VM target **dan direkam** | Warpgate → **VM Ubuntu (srv1/client1)** |
| **7** | Komponen & host mengirim event audit (login, akses vault, perintah, skor CIS) | Keycloak/OpenBao/dc1 → **Alloy** |
| **8** | Log terstruktur disimpan | Alloy → **Loki** |
| **9** | Divisualkan: dashboard & alert, **UBA** | Loki → **Grafana** |

> Nomor pada tabel cocok dengan badge di Gambar 1. Selain alur di atas, **VM `srv1`/`client1`
> bergabung ke domain** `dc1` (Kerberos/LDAP) di **Sesi 1** — ini mendasari login akun direktori
> di endpoint, dijelaskan penuh di sesi tersebut (bukan bagian alur layanan bernomor ini).

Secara **jaringan/penempatan**, blok-blok tersebut berjalan sebagai berikut:

![Topologi sistem IAM — Docker Desktop (Samba AD + layanan IAM) + VM Ubuntu srv1 & client1, domain iamlab.test](gambar/topologi.png)

*Gambar 2. Topologi sistem IAM — Docker Desktop + 2 VM Ubuntu*

| Node | Peran | Alamat |
|------|-------|--------|
| **PC Windows Pro** (16 GB) | Menjalankan VirtualBox + Docker Desktop; browser peserta | adapter Host-Only `10.10.10.5` |
| **Container Docker** | Samba AD DC (`dc1`), Keycloak+Postgres, OpenBao, Warpgate, Mailpit, Caddy, Grafana/Loki/Alloy, App-Komentar, App-SAML | di `10.10.10.5` (port diexpose) |
| **VM `srv1`** (Ubuntu Server) | Anggota domain; target SSH/bastion; subjek CIS *server* | `10.10.10.20` |
| **VM `client1`** (Ubuntu Desktop) | Anggota domain; login GUI pengguna direktori; subjek CIS *workstation* | `10.10.10.30` |

**Legenda:**
- 🟦 **Zona Endpoint/Klien** — VM Ubuntu `srv1` & `client1`.
- 🟥 **Zona Direktori (Tier 0)** — Samba AD DC `dc1` (container): LDAP/LDAPS, Kerberos, direktori.
- 🟩 **Blok Layanan IAM (Docker)** — Keycloak, OpenBao, Warpgate, Grafana/Loki/Alloy, di
  belakang **Caddy** (reverse proxy + TLS CA internal).
- **Garis panah:** garis penuh = akses pengguna/aplikasi (HTTPS); **putus-putus** =
  federasi/autentikasi & join direktori (LDAPS/Kerberos); **teal** = aliran event audit.

**Aliran data inti:** pengguna membuka aplikasi → diarahkan ke **Keycloak** → Keycloak
memverifikasi kredensial ke **Samba AD** (LDAPS) dan meminta **MFA** bila perlu → menerbitkan
token → aplikasi memberi akses sesuai peran (klaim grup). Aktivitas autentikasi/otorisasi —
termasuk login & perintah di VM Ubuntu — mengalir sebagai log ke **Alloy → Loki → Grafana**.

> **Mengapa Samba, bukan Windows Server?** Samba AD menyediakan protokol direktori yang sama
> (LDAP, Kerberos, Group Policy) secara *open source* dan ringan, sehingga seluruh lab —
> direktori + layanan — muat di satu PC 16 GB tanpa lisensi Windows Server. Konsep AD/LDAP,
> *tiering*, dan kebijakan akses terpusat identik; yang berbeda hanya perkakas administrasinya
> (`samba-tool` dan kebijakan sisi klien Linux, bukan GPMC).

## Daftar Istilah & Singkatan

Rujukan cepat singkatan yang dipakai berulang di seluruh modul.

**Identitas & direktori**

| Singkatan | Kepanjangan | Arti ringkas |
|-----------|-------------|--------------|
| IAM | Identity & Access Management | Manajemen identitas & akses |
| IAAA | Identification, Authentication, Authorization, Accounting/Audit | Empat pilar kontrol identitas |
| AD | Active Directory | Direktori + control plane identitas (di lab: **Samba AD**) |
| DC | Domain Controller | Server pengendali domain (`dc1`) |
| LDAP | Lightweight Directory Access Protocol | Protokol akses direktori (port 389) |
| LDAPS | LDAP over TLS | LDAP terenkripsi (port 636) |
| OU | Organizational Unit | Unit/wadah objek di direktori |
| DN | Distinguished Name | Nama unik objek (mis. `CN=svc-keycloak,OU=AkunLayanan,…`) |
| DNS | Domain Name System | Resolusi nama → alamat |
| KDC | Key Distribution Center | Penerbit tiket Kerberos di DC |
| SPN | Service Principal Name | Nama layanan ber-Kerberos pada akun layanan |
| GPO | Group Policy Object | Kebijakan terpusat (padanan Linux: sssd + CIS) |
| PSO | Password Settings Object | Kebijakan sandi khusus per grup |

**SSO, token & MFA**

| Singkatan | Kepanjangan | Arti ringkas |
|-----------|-------------|--------------|
| IdP | Identity Provider | Gerbang SSO (di lab: **Keycloak**) |
| SP / RP | Service Provider / Relying Party | Aplikasi yang memercayai IdP |
| SSO | Single Sign-On | Satu kali login untuk banyak aplikasi |
| MFA | Multi-Factor Authentication | Autentikasi >1 faktor |
| OTP / TOTP | One-Time Password / Time-based OTP | Kode sekali pakai (RFC 6238, Google Authenticator) |
| SAML | Security Assertion Markup Language | Federasi berbasis XML Assertion |
| OAuth 2.0 | Open Authorization | Kerangka otorisasi akses sumber daya |
| OIDC | OpenID Connect | Lapisan identitas di atas OAuth 2.0 |
| JWT | JSON Web Token | Format token (ID Token OIDC) |
| PKCE | Proof Key for Code Exchange | Pengaman alur Authorization Code |
| RBAC | Role-Based Access Control | Hak akses berbasis peran/grup |
| AAL | Authenticator Assurance Level | Tingkat jaminan autentikasi (NIST SP 800-63B) |

**PAM & kriptografi**

| Singkatan | Kepanjangan | Arti ringkas |
|-----------|-------------|--------------|
| PAM | Privileged Access Management | Pengelolaan akses istimewa (OpenBao + Warpgate) |
| CA | Certificate Authority | Penerbit sertifikat |
| SSH CA | SSH Certificate Authority | Penandatangan sertifikat SSH berumur pendek (OpenBao) |
| KV | Key-Value | Mesin rahasia OpenBao (brankas) |
| TLS | Transport Layer Security | Enkripsi transport (HTTPS/LDAPS) |
| SAN | Subject Alternative Name | Daftar host/IP sah pada sertifikat. LDAPS **wajib** ber-SAN; cert CN-only ditolak klien Go/OpenBao (`x509: legacy Common Name`) |
| AES / RC4 | Advanced Encryption Standard / Rivest Cipher 4 | Enctype Kerberos: AES (kuat) vs RC4 (lemah) |
| NTLM | NT LAN Manager | Protokol autentikasi lama (dibatasi `ntlmv2-only`) |

**Audit, kepatuhan & infrastruktur**

| Singkatan | Kepanjangan | Arti ringkas |
|-----------|-------------|--------------|
| UBA | User Behavior Analytics | Deteksi perilaku tak lazim |
| CIS | Center for Internet Security | Benchmark pengerasan (via OpenSCAP) |
| SCAP | Security Content Automation Protocol | Standar isi audit kepatuhan |
| LogQL | Log Query Language | Bahasa kueri log Loki |
| NIST | National Institute of Standards and Technology | Rujukan standar (SP 800-53/63/92) |
| SPBE / BSSN | Sistem Pemerintahan Berbasis Elektronik / Badan Siber dan Sandi Negara | Konteks kepatuhan audit di Indonesia |
| VM / VDI | Virtual Machine / Virtual Disk Image | Mesin & disk virtual (VirtualBox) |
| WSL | Windows Subsystem for Linux | Backend Docker Desktop |
| GUI / CLI | Graphical / Command-Line Interface | Antarmuka grafis / baris perintah |
| SMTP | Simple Mail Transfer Protocol | Pengiriman email (ke Mailpit) |

## Kredensial Lab (sintetis)

> ⚠️ **Semua kredensial di bawah HANYA untuk lab terisolasi & sintetis.** Jangan dipakai di
> produksi; ganti di `deploy/.env` dan saat *setup* untuk lingkungan nyata.

**Sistem & konsol**

| Sistem | Akses | Username | Password | Catatan |
|--------|-------|----------|----------|---------|
| Domain AD (Samba `dc1`) | `samba-tool` (🐳) | `Administrator` | `Passw0rd#Lab2026` | admin domain `iamlab.test` |
| VM `srv1` & `client1` (akun lokal) | SSH/konsol (🖥️) | `labadmin` | `Lab#Admin2026` | admin lokal VM |
| Keycloak (konsol admin) | `https://kc.iamlab.test` | `admin` | `ChangeMe_Admin#2026` | dari `deploy/.env` |
| Grafana | `https://grafana.iamlab.test` | `admin` | `ChangeMe_Grafana#2026` | dari `deploy/.env` |
| Warpgate (bastion) | `https://pam.iamlab.test` | `admin` | `Warp#Lab2026` | diset saat `unattended-setup` (Sesi 3) |
| Mailpit | `https://mail.iamlab.test` | — | *(tanpa autentikasi)* | kotak surat uji |
| OpenBao | CLI `docker compose exec openbao bao` | *(root token)* | dibuat saat `operator init` | + 3 *unseal key* (2 utk buka); tak ada login statis |
| PostgreSQL (internal Keycloak) | tak diekspos | `keycloak` | `ChangeMe_KcDb#2026` | hanya antar-container |

**Akun direktori & layanan (dibuat di Sesi 1)**

| Akun | Password | Peran |
|------|----------|-------|
| `svc-keycloak` | `Svc#Lab2026!` → direset `Svc#Lab2026baru` | *Bind credential* federasi LDAP Keycloak |
| `svc-openbao` | `Svc#Lab2026!` | *Bind* auth LDAP OpenBao |
| `svc-app`, `svc-honey` | `Svc#Lab2026!` | Akun layanan ber-SPN (AES-only) |
| `adm-t1-anda` | `Adm1#Lab2026` | Admin Tier 1 (login OpenBao via LDAP) |
| *break-glass* `srv1` (di OpenBao KV) | `labadmin` / `BreakGlass#2026` | kredensial darurat, teraudit |
| Pengguna direktori (*bulk import*) | **sandi awal acak** | dikirim ke **Mailpit**; wajib ganti saat login pertama |

> MFA (Sesi 2): butuh **Google Authenticator / FreeOTP** di ponsel untuk akun yang ditarget OTP.

## Peta Sesi

| Sesi | Fokus | Indikator |
|------|-------|-----------|
| **1** | Pengamanan Direktori (Samba AD/LDAP), join domain, kebijakan akses terpusat & **CIS Benchmark** | 1.1, 1.2 |
| **2** | SSO & MFA (Keycloak) + App-Komentar (RBAC) | 2.1, 2.2 |
| **3** | Privileged Access Management (OpenBao + Warpgate) | 3.1, 3.2 |
| **4** | Audit, Monitoring & **trace aktivitas pengguna** (Alloy/Loki/Grafana) + capstone | 4.1, 4.2 |

> Lingkungan (container layanan + 2 VM Ubuntu) **sudah dibangun fasilitator** memakai paket
> `IAMLAB-BuildBag`; peserta berfokus pada **konfigurasi keamanan** di tiap sesi, bukan instalasi.

## Untuk peserta: ambil modul & verifikasi lab

Lab **sudah disiapkan fasilitator** di PC. Peserta cukup mengambil modul ini lalu memastikan lab jalan:

```powershell
cd C:\Lab\IAMLAB-BuildBag          # folder builder yang disiapkan fasilitator
git clone <url-repo> Pelatihan_IAM  # modul ini
cd Pelatihan_IAM
cd ..\deploy; docker compose ps     # verifikasi stack jalan (atau: ..\build-lab.ps1 -Phase Status)
```

Tata letak di PC lab: `IAMLAB-BuildBag\{build-lab.ps1, deploy, lab, attack-sim, distribusi}` +
`IAMLAB-BuildBag\Pelatihan_IAM` (modul). Semua perintah `docker compose …` dijalankan dari
`IAMLAB-BuildBag\deploy` (dari folder modul: `cd ..\deploy`); file modul yang disalin ke container
dirujuk `../Pelatihan_IAM/sesi-…`.

Google Authenticator / FreeOTP di ponsel diperlukan untuk MFA (Sesi 2).

> **Gambaran lengkap langkah peserta** (semua sesi, dengan validasi tiap perintah):
> lihat [`../ALUR-PESERTA.md`](../ALUR-PESERTA.md).
