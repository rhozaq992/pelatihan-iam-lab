# Sesi 0 — Pengantar: Topologi Sistem & Teori Dasar

Sesi pembuka. Tujuannya memberi **gambaran utuh** sistem IAM yang akan dibangun dan
**fondasi teori** yang dipakai berulang di sesi berikutnya. Detail teknis diperdalam
per sesi (`sesi-1` … `sesi-4`).

## Konvensi "di mana perintah dijalankan"

Sepanjang modul, setiap langkah diberi penanda tempat eksekusi agar tidak keliru:

| Penanda | Tempat menjalankan |
|---------|--------------------|
| 🪟 **DC (PowerShell)** | Di dalam VM Windows Server 2025 (Domain Controller), via PowerShell/Server Manager/GPMC. |
| 🐳 **Container (host)** | Di terminal PC peserta, memakai `docker compose exec <service> …` untuk masuk ke dalam container. |
| 🖥️ **Terminal peserta** | Di terminal PC peserta langsung (host), mis. `docker compose …`, `ssh …`, `python3 …`. |
| 🌐 **Web UI** | Di browser peserta: Keycloak, Grafana, Warpgate, Mailpit. |

## a. Tujuan Sesi

Peserta memahami:
- Peta keseluruhan sistem (komponen, jaringan, aliran data) sebelum masuk praktik.
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

| Pilar | **Apa** | **Mengapa** | Analogi |
|------|-----------------|-------------------|---------|
| **Identifikasi** | Pengguna mengaku sebagai siapa (username) | Titik awal semua kontrol | Menyebut nama di resepsionis |
| **Autentikasi** | Membuktikan klaim identitas (faktor: sandi, OTP, biometrik) | Mencegah peniruan | Menunjukkan KTP + segel sekali pakai |
| **Otorisasi** | Menentukan hak (peran/izin) | Membatasi akses sesuai kebutuhan (*least privilege*) | Kartu hanya membuka lantai tertentu |
| **Audit** | Mencatat aktivitas | Pembuktian & deteksi penyalahgunaan | Buku tamu + CCTV |

- **Siapa** yang terlibat: pengguna akhir, administrator (akun istimewa), akun
  layanan (aplikasi), dan auditor.
- **Kapan** kontrol bekerja: saat login (autentikasi), saat mengakses fitur
  (otorisasi), dan terus-menerus (audit).
- **Di mana**: identitas terpusat memindahkan keempat pilar dari tiap aplikasi
  ke **satu direktori** (sumber kebenaran) dan **satu IdP** (gerbang).
- **Bagaimana**: aplikasi mendelegasikan login ke IdP; IdP memverifikasi ke
  direktori dan menerbitkan token/assertion yang dipercaya aplikasi.

_Analogi:_ dari "tiap pintu punya daftar tamu sendiri" menjadi "satu lobi, satu
petugas, satu buku tamu" — kebijakan konsisten, penonaktifan akun berlaku serentak,
jejak audit terkumpul di satu tempat.

### Komponen & perannya (dipetakan ke sesi)
- **Active Directory (AD/LDAP)** — direktori + *control plane* identitas: pengguna,
  grup, Kerberos, DNS, Group Policy. *(Sesi 1)*
- **Keycloak (Identity Provider)** — gerbang SSO yang memverifikasi ke direktori,
  menerbitkan token/assertion, dan menegakkan **MFA**. *(Sesi 2)*
- **MFA (Google Authenticator / TOTP)** — faktor "sesuatu yang dimiliki" selain sandi
  "sesuatu yang diketahui". *(Sesi 2)*
- **PAM (OpenBao + Warpgate)** — brankas kredensial istimewa + *jump server* yang
  merekam sesi admin. *(Sesi 3)*
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

Seluruh lab berjalan terisolasi di PC peserta (jaringan Host-Only, tanpa internet),
domain sintetis **`iamlab.test`**. AD berjalan sebagai VM Windows Server 2025; sisanya
sebagai container Docker di belakang satu reverse proxy (Caddy) dengan TLS dari CA internal.

![Topologi sistem IAM — 4 sistem (Windows Server AD, Samba AD, klien Windows & Linux) + layanan IAM, domain iamlab.test](gambar/topologi.png)

**Legenda:**
- 🟦 **Zona Endpoint/Klien** — perangkat pengguna (klien Windows 11 & Linux).
- 🟥 **Zona Direktori (Tier 0)** — server identitas: Windows Server 2025 (`dc1`) untuk sisi
  Windows, Samba AD DC (`dc2`) untuk sisi Linux.
- 🟩 **Blok Layanan IAM (Docker)** — Keycloak, OpenBao, Warpgate, Grafana/Loki/Alloy, di
  belakang **Caddy** (reverse proxy + TLS CA internal).
- **Garis panah:** garis penuh = akses pengguna/aplikasi (HTTPS); **putus-putus** =
  federasi/autentikasi ke direktori (LDAPS 636); **teal** = aliran event audit ke pemantauan.
- Kotak **box-3D** = server/direktori; kotak biasa = klien; kotak membulat = layanan/proxy.

**Aliran data inti:** pengguna membuka aplikasi → diarahkan ke **Keycloak** →
Keycloak memverifikasi kredensial ke **AD** (LDAPS) dan meminta **MFA** bila perlu →
menerbitkan token → aplikasi memberi akses sesuai peran (klaim grup). Semua aktivitas
autentikasi/otorisasi mengalir sebagai log ke **Alloy → Loki → Grafana** untuk audit.

## Peta Sesi

| Sesi | Fokus | Indikator |
|------|-------|-----------|
| **1** | Pengamanan Direktori (AD/LDAP) & GPO; simulasi terkendali | 1.1, 1.2 |
| **2** | SSO & MFA (Keycloak) + App-Komentar (RBAC) | 2.1, 2.2 |
| **3** | Privileged Access Management (OpenBao + Warpgate) | 3.1, 3.2 |
| **4** | Audit & Monitoring (Alloy/Loki/Grafana) + capstone | 4.1, 4.2 |

> Lingkungan (VM AD + stack layanan) disiapkan terlebih dahulu; peserta berfokus pada
> **konfigurasi keamanan** di tiap sesi, bukan instalasi dari nol. Proses *deploy*
> awal tetap ditunjukkan di tiap sesi agar peserta paham cara sistem dinyalakan.
