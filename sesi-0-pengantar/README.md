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

Diagram berikut membagi sistem menjadi **tiga segmen** — Direktori & Klien,
Layanan IAM, dan Observability — dengan alur data/aktivitas **bernomor** yang dijelaskan
pada *Agenda Aktivitas* di bawahnya.

![Arsitektur & alur IAM — 3 partisi (Direktori & Klien · Layanan IAM · Observability) dengan alur bernomor](gambar/arsitektur.png)

*Gambar 1. Arsitektur & alur IAM (3 partisi, alur bernomor)*

**Agenda Aktivitas (penjelasan nomor pada diagram):**

| # | Aktivitas | Sistem terhubung |
|---|-----------|------------------|
| **1** | Pengguna membuka aplikasi/konsol lewat HTTPS; TLS diterminasi reverse proxy | Klien Windows/Linux → **Caddy** |
| **2** | Proxy meneruskan permintaan login ke Identity Provider (SSO) | Caddy → **Keycloak** |
| **3** | Keycloak memverifikasi kredensial & menarik atribut/grup lewat LDAPS 636 | Keycloak → **Windows Server AD (dc1)** |
| **3b** | Federasi direktori untuk sisi Linux | Keycloak → **Samba AD (dc2)** |
| **4** | Akses istimewa diarahkan ke bastion; login bastion memakai SSO Keycloak + MFA | Klien → **Warpgate** |
| **5** | Bastion mengambil kredensial *break-glass* / meminta sertifikat SSH berumur pendek | Warpgate → **OpenBao (Vault/SSH CA)** |
| **6** | Sesi SSH diproksikan ke target **dan direkam** | Warpgate → **Klien/target Linux** |
| **7** | Komponen mengirim event audit (login, akses vault, Windows Event) | Keycloak / OpenBao / Windows AD → **Alloy** |
| **8** | Log terstruktur disimpan | Alloy → **Loki** |
| **9** | Visualisasi dashboard & alert (UBA) | Loki → **Grafana** |

Secara **jaringan/penempatan**, blok-blok itu berjalan sebagai berikut:

![Topologi sistem IAM — 4 sistem (Windows Server AD, Samba AD, klien Windows & Linux) + layanan IAM, domain iamlab.test](gambar/topologi.png)

*Gambar 2. Topologi sistem IAM — 4 sistem + layanan IAM*

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

## Deploy awal (satu perintah)

Jaringan antar-VM / host / Docker **sudah dikonfigurasi panitia** — peserta tidak perlu
mengaturnya. Dari direktori ini (🖥️ **terminal host / VM Docker**), jalankan skrip
[`deploy-lab.sh`](deploy-lab.sh): ia mendeteksi OS & arsitektur, memasang Docker bila belum
ada, memuat image offline (`distribusi/offline-images/iam-images.tar`), lalu `docker compose up -d`.

> ### ⚠️ Prasyarat & Cek Kesiapan Host Windows (WAJIB dibaca)
> Lab ini diuji pada **Windows + VirtualBox + Docker Desktop** (sama seperti PC peserta).
> Sebelum `deploy-lab.sh`, pastikan:
>
> 1. **Git Bash: matikan konversi path otomatis.** Git Bash (MSYS) mengubah argumen
>    berawalan `/` (mis. `/openbao/file/audit.log`, `/data`) menjadi path Windows
>    sebelum sampai ke dalam container → perintah `docker … exec` bisa **gagal**
>    (`mkdir C:: permission denied`). Jalankan **sekali** di awal tiap sesi:
>    ```bash
>    export MSYS_NO_PATHCONV=1      # wajib di Git Bash Windows (abaikan di Linux/macOS)
>    ```
> 2. **Port 80 & 443 harus bebas.** Caddy (reverse proxy) mengikatnya. Jika **VMware**
>    terpasang, layanan `vmware-hostd` merebut `:443` dan browser akan menampilkan
>    halaman yang salah. Cek & bebaskan:
>    ```bash
>    netstat -ano | grep -E ":(80|443)\b"   # pastikan hanya com.docker.backend yang LISTEN
>    ```
>    Bila ada `vmware-hostd`/aplikasi lain: hentikan layanan itu (Services.msc → *VMware
>    Workstation Server* → Stop) sebelum lanjut.
> 3. **Docker Desktop berjalan** (ikon paus hijau) dan memakai image **amd64** (lihat di bawah).
> 4. **Untuk `--vms` (VirtualBox):** pastikan `VBoxManage` ada di PATH
>    (`export PATH="$PATH:/c/Program Files/Oracle/VirtualBox"`) dan panitia telah membuat
>    **Host-Only network `10.10.10.0/24`** (DC=10.10.10.10, host-Docker=10.10.10.5).

```bash
# 🖥️ terminal host (Linux/Ubuntu, macOS, atau Windows via Git Bash)
export MSYS_NO_PATHCONV=1   # Windows/Git Bash saja (cegah path mangling)
cd sesi-0-pengantar
./deploy-lab.sh            # cek deps → pasang Docker (bila perlu) → muat image → nyalakan stack
```

> **✅ Validasi / Output yang diharapkan.** Di akhir skrip, `docker compose ps` menampilkan
> seluruh layanan `running` (Keycloak `healthy` setelah ±1 menit). Contoh nyata (amd64):
> ```text
> NAME                    STATUS
> iamlab-caddy-1          Up (running)
> iamlab-postgres-1       Up (healthy)
> iamlab-keycloak-1       Up (healthy)        # ±60 dtk sampai healthy
> iamlab-grafana-1        Up
> iamlab-loki-1           Up
> iamlab-alloy-1          Up
> iamlab-mailpit-1        Up (healthy)
> iamlab-openbao-1        Up                  # sealed — di-init di Sesi 3 (normal)
> iamlab-app-komentar-1   Up (unhealthy)      # normal: realm OIDC belum dibuat (Sesi 2)
> iamlab-srv-app01-1      Up
> iamlab-srv-db01-1       Up
> iamlab-app-saml-1       Up
> iamlab-samba-dc-1       Up (healthy)        # DC Samba Sesi 1A (profil 'direktori')
> iamlab-warpgate-1       Up (healthy)        # muncul/healthy setelah setup Sesi 3
> ```
> (Daftar di atas contoh ringkas; pada deploy default muncul ±14 kontainer — itu normal.)
> Pesan `✓ Selesai. Endpoint: https://kc.iamlab.test · …` menandakan sukses.
> **Pastikan TIDAK ada baris** `The requested image's platform (linux/arm64) does not match …`
> — bila muncul, image Anda masih arm64 (salah); minta tar `iam-images.tar` versi **amd64**.
> Verifikasi cepat arsitektur: `docker image inspect quay.io/keycloak/keycloak:26.1 --format '{{.Architecture}}'` → harus `amd64`.

| Opsi | Guna |
|------|------|
| `./deploy-lab.sh` | Deploy penuh (default). |
| `./deploy-lab.sh --check` | Hanya laporkan OS/arch/Docker/image — tidak mengubah apa pun. |
| `./deploy-lab.sh --compose-only` | **Bila langkah pasang-deps bermasalah**: lewati, langsung muat image + `compose up`. |
| `./deploy-lab.sh --vms` | **Di host fisik**: impor & nyalakan VM klien (mis. `ubuntu-client.ova`) dari `distribusi/ova` via VirtualBox/VMware. |
| `./deploy-lab.sh --no-samba` | Tanpa DC Samba (Sesi 1 Bagian A). |
| `./deploy-lab.sh --down` | Hentikan & bersihkan stack. |

**Dua konteks eksekusi** (jaringan antar-VM/host/Docker sudah diatur panitia):
- **Host fisik** (ber-VMware/VirtualBox) → `./deploy-lab.sh --vms` menyalakan VM (klien Ubuntu
  yang di-*realm join* pada Sesi 1, VM AD, dll). Nama VM = nama file `.ova`.
- **Di dalam VM/host Docker** → `./deploy-lab.sh` menyalakan stack kontainer.

> Docker Desktop (Windows/macOS) tak bisa dipasang via skrip — pasang dari
> `distribusi/installer` lebih dulu, lalu jalankan skrip. Di Ubuntu, skrip memakai paket
> `.deb` offline di `distribusi/installer/docker/` bila ada, atau `get.docker.com` bila online.
