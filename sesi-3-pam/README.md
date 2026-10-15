# Sesi 3 — Privileged Access Management (OpenBao + Warpgate)

Indikator 3.1 (jump server/bastion) dan 3.2 (password vault). Mengamankan kredensial
administratif dan memusatkan akses istimewa melalui bastion yang merekam sesi.
Penanda: 🖥️ **terminal peserta** · 🐳 **container** · 🌐 **web UI**.

## Keterhubungan dengan sesi sebelumnya

Sesi ini **memakai Sesi 1 & 2**: Warpgate login memakai **SSO Keycloak** (Sesi 2, MFA
wajib), dan OpenBao berautentikasi ke **AD** (Sesi 1) memakai `svc-openbao`, memetakan grup
`GG-Tier1-Admin` (Sesi 1) ke *policy*. Email serah-terima memakai **Mailpit** (sudah diset
di Sesi 2). **Dipakai Sesi 4:** audit OpenBao, sesi Warpgate, dan sshd menjadi sumber log.

## a. Tujuan Sesi

Peserta mampu:
- Memahami cara komponen PAM di-*deploy*, lalu **mengonfigurasinya**.
- Menginisialisasi & membuka (*unseal*) brankas kredensial **OpenBao**.
- Mengaktifkan **audit device**, auth LDAP, *policy* *least privilege*, KV *break-glass*, dan **SSH CA**.
- Mengonfigurasi **Warpgate** sebagai jump server ber-SSO + perekaman sesi, lalu
  **mengakses target via SSH melalui bastion**.

## b. Output yang Diharapkan

- OpenBao *unsealed*, audit aktif, *root token* dicabut setelah LDAP admin terbukti jalan.
- Target SSH menolak autentikasi sandi; akses hanya via sertifikat CA / bastion.
- Sesi admin melalui Warpgate **terekam** dan dapat diputar ulang.

## c. Teori dan Struktur Sistem

*Privileged Access Management* memperlakukan akun admin ("kunci induk")
secara khusus. **Vault** menyimpan kredensial terenkripsi, memberi akses berbasis
kebijakan, mencatat tiap pengambilan, dan dapat menerbitkan kredensial berumur pendek.
**Jump server/bastion** memaksa semua akses admin lewat satu pintu yang merekam sesi.

Kredensial admin statis yang tersebar = permukaan serang besar; akses
langsung ke server tanpa jejak = sulit diaudit. PAM menutup keduanya.

**Alur akses istimewa:**

![Alur PAM: SSO + MFA → Warpgate (bastion) → target; OpenBao untuk kredensial & SSH CA](gambar/alur-pam.png)

*Gambar 1. Alur PAM — SSO+MFA → Warpgate → target; OpenBao kredensial & SSH CA*

*Legenda: penuh = akses/sesi; putus-putus = SSO/auth & kredensial; teal = log. Nomor dijelaskan pada Agenda Aktivitas di bawah.*

**Agenda Aktivitas (nomor pada diagram):**
1. Admin login ke **bastion Warpgate**.
2. Warpgate meneruskan autentikasi ke **Keycloak** (SSO OIDC + MFA).
3. Keycloak mengembalikan **token + grup** ke Warpgate.
4. Sesi **SSH ke target** diproksikan lewat bastion **dan direkam**.
5. Admin mengambil kredensial *break-glass* / meminta **sertifikat SSH** dari **OpenBao**.
6. Target memercayai **SSH CA** OpenBao (atau memakai kredensial yang diambil).
7. Aktivitas (akses vault, sesi bastion, sshd) dikirim ke **audit** (Sesi 4).


**SSH CA.** Alih-alih menyebar kunci publik ke tiap server, server cukup
memercayai satu *Certificate Authority*; OpenBao menandatangani sertifikat SSH berumur
pendek (mis. 30 menit) untuk pengguna yang berhak — masa berlaku yang singkat membuat
kredensial curian tak berguna lama.

## d. Praktik: Instalasi dan Konfigurasi

### 0. 🖥️ Deploy (sudah disiapkan — tetap dipahami)
```bash
cd ../deploy        # stack di IAMLAB-BuildBag; modul diklon di IAMLAB-BuildBag/Pelatihan_IAM
docker compose up -d openbao warpgate      # OpenBao BELUM di-init; Warpgate perlu setup sekali
```
OpenBao sengaja mulai dalam keadaan *uninitialized*; Warpgate perlu *setup* sekali. **Target
akses istimewa di lab ini adalah VM `srv1`** (`10.10.10.20`, Ubuntu Server anggota domain dari
Sesi 1) — bukan container. Peserta mengakses `srv1` **hanya** lewat bastion Warpgate.

### A. 🐳 OpenBao (brankas kredensial)
Jalankan `bao` **di dalam container** OpenBao. Tiap langkah dijelaskan di komentar:
```bash
alias bao='docker compose exec -T -e BAO_ADDR=http://127.0.0.1:8200 openbao bao'
bao operator init -key-shares=3 -key-threshold=2   # pecah master key jadi 3, butuh 2 utk buka
bao operator unseal <key1> ; bao operator unseal <key2>   # buka brankas (2 dari 3)
bao login <root-token>
bao audit enable file file_path=/openbao/file/audit.log    # catat SEMUA akses (sebelum isi rahasia)
bao audit enable -path=stdout file file_path=stdout        # salin audit ke STDOUT → Alloy→Loki (audit TERPUSAT)
bao auth enable ldap                                        # login pakai akun AD
# CA AD (Sesi 1 langkah 5b) sudah di deploy/certs/ad-ca.pem → ter-mount di /openbao/certs
bao write auth/ldap/config url="ldaps://dc1.iamlab.test:636" \
  certificate=@/openbao/certs/ad-ca.pem \
  userdn="DC=iamlab,DC=test" groupdn="OU=Grup,DC=iamlab,DC=test" \
  binddn="CN=svc-openbao,OU=AkunLayanan,DC=iamlab,DC=test" bindpass="***" userattr=sAMAccountName
bao policy write admin-t1 - <<'HCL'                         # izin minimal (least privilege)
path "kv/data/breakglass/*" { capabilities=["read"] }
path "ssh/sign/t1"          { capabilities=["update"] }
HCL
bao write auth/ldap/groups/GG-Tier1-Admin policies=admin-t1 # grup AD → policy
bao secrets enable -path=kv kv-v2                            # brankas KV
bao kv put kv/breakglass/srv1 user=labadmin pass='BreakGlass#2026'   # root login dimatikan di bagian B
bao secrets enable ssh                                       # mesin SSH CA
bao write ssh/config/ca generate_signing_key=true
# Role sign SSH: allowed_users WAJIB (OpenBao 2.x menolak sign tanpa principal), permit-pty
# agar sesi interaktif. Dikirim sbg JSON via stdin karena field map tak bisa inline di CLI.
bao write ssh/roles/t1 - <<'JSON'
{"key_type":"ca","allow_user_certificates":true,"allowed_users":"labadmin","default_user":"labadmin","default_extensions":{"permit-pty":""},"ttl":"30m"}
JSON
# GATED: buktikan login LDAP admin Tier 1 BERHASIL (akun adm-t1-anda dari Sesi 1 langkah 3,
# anggota GG-Tier1-Admin) → token harus memuat policy admin-t1. Simpan unseal key, BARU cabut root:
docker compose exec -e BAO_ADDR=http://127.0.0.1:8200 openbao bao login -method=ldap username=adm-t1-anda
bao token revoke <root-token>
```

> **⚠️ Windows/Git Bash:** perintah `bao audit enable file file_path=/openbao/file/audit.log`
> akan **gagal** (`unable to open "C:/Program Files/Git/openbao/…": mkdir C:: permission denied`)
> karena Git Bash menerjemahkan `/openbao/…` jadi path Windows. Jalankan
> `export MSYS_NO_PATHCONV=1` **sekali** di awal sesi (lihat Sesi 0), atau prefiks perintahnya:
> `MSYS_NO_PATHCONV=1 bao audit enable file file_path=/openbao/file/audit.log`.
>
> **✅ Validasi / Output yang diharapkan** (ditangkap nyata, amd64):
> ```text
> bao operator init …          → Unseal Key 1..3 + Initial Root Token (SIMPAN! tak bisa diulang)
> bao operator unseal <key1>   → Sealed true  · Unseal Progress 1/2
> bao operator unseal <key2>   → Sealed false            ← brankas terbuka
> bao audit enable file …      → Success! Enabled the file audit device at: file/
> bao auth enable ldap         → Success! Enabled ldap auth method at: ldap/
> bao secrets enable -path=kv kv-v2 → Success! Enabled the kv-v2 secrets engine at: kv/
> bao secrets enable ssh       → Success! Enabled the ssh secrets engine at: ssh/
> bao write ssh/config/ca …    → public_key  ssh-rsa AAAA…     ← kunci CA muncul
> bao write ssh/roles/t1 - …   → Success! Data written to: ssh/roles/t1
> ```
> Cek akhir: `bao status` → `Initialized true`, `Sealed false`, `Total Shares 3`, `Threshold 2`;
> `bao audit list` → **dua** baris: `file/  file` dan `stdout/  file` (yang kedua mengalirkan
> jejak audit ke Loki lewat Alloy — buktikan di Sesi 4 dengan `{service="openbao"}`).
> **Jika** `ssh/roles/t1` → `role is not configured to allow any principals`: `allowed_users`
> kosong — WAJIB diisi (lihat JSON di atas).
> **Jika** login LDAP gagal `x509: certificate signed by unknown authority` → `ad-ca.pem`
> belum ada/OpenBao belum di-*recreate* (lihat `deploy/README.md`). Jangan cabut root token
> sebelum `bao login -method=ldap` menampilkan `policies [admin-t1 default]`.

Status nyata setelah init/unseal (OpenBao di lab ini berbasis **CLI**, tanpa web UI):

![Terminal — OpenBao: status (initialized/unsealed, 3/2), audit file, engine kv & ssh](gambar/openbao-cli.png)

*Gambar 2. Terminal OpenBao — status, audit, engine kv & ssh*

### B. 🖥️ Target `srv1` memercayai SSH CA
Ambil kunci publik CA dari OpenBao, pasang di **VM `srv1`** sebagai `TrustedUserCAKeys`, lalu
matikan autentikasi sandi (akses hanya via sertifikat SSH dari CA / bastion):
```bash
# 🖥️ terminal host — ambil kunci publik CA OpenBao
docker compose exec -T -e BAO_ADDR=http://127.0.0.1:8200 openbao \
  bao read -field=public_key ssh/config/ca > openbao_ca.pub
scp openbao_ca.pub labadmin@srv1.iamlab.test:/tmp/openbao_ca.pub
```
```bash
# 🖥️ di srv1
sudo install -m 644 /tmp/openbao_ca.pub /etc/ssh/openbao_ca.pub
printf 'TrustedUserCAKeys /etc/ssh/openbao_ca.pub\nPasswordAuthentication no\nPermitRootLogin no\n' \
  | sudo tee /etc/ssh/sshd_config.d/10-iamlab-ca.conf
sudo systemctl restart ssh
```

### C. 🌐 Warpgate (bastion + rekam sesi)
Setup sekali di 🖥️ terminal, lalu konfigurasi di 🌐 web UI `https://pam.iamlab.test`:
```bash
export MSYS_NO_PATHCONV=1    # Windows/Git Bash: agar '--data-path /data' tak jadi path Windows
docker compose run --rm warpgate unattended-setup \
  --data-path /data --http-port 8888 --ssh-port 2222 --record-sessions \
  --host-key-verification auto-accept --admin-password 'Warp#Lab2026' --external-host pam.iamlab.test
docker compose up -d warpgate
```

> **✅ Validasi / Output yang diharapkan** (nyata, amd64):
> ```text
> INFO warpgate::commands::setup: Admin user credentials:
> INFO warpgate::commands::setup:   * Username: admin
> INFO warpgate::commands::setup: You can now start Warpgate with: …
> ```
> Lalu `docker compose ps warpgate` → `Up … (healthy)` dalam ±15 dtk. Buka
> `https://pam.iamlab.test` (lewat Caddy, **bukan** `:8888` langsung) → halaman login Warpgate.
> **Jika** `docker compose ps` tak menampilkan warpgate / `Restarting`: setup belum
> dijalankan (config `/data/warpgate.yaml` belum ada) — ulangi `unattended-setup` dulu.
Agar login ke bastion **terkendali dan seragam**, arahkan autentikasi Warpgate ke
**SSO Keycloak** (bukan akun lokal Warpgate), sehingga **MFA dari Sesi 2 ikut berlaku** saat
masuk bastion. Provider SSO Warpgate diatur di berkas konfigurasi `/data/warpgate.yaml`
(bukan di web UI) memakai client `warpgate` yang dibuat di Sesi 2 langkah 2b:
```bash
# 🖥️ salin keluar, sunting, salin balik, lalu restart
docker compose cp warpgate:/data/warpgate.yaml ./warpgate.yaml
cat >> ./warpgate.yaml <<'YAML'
sso_providers:
  - name: keycloak
    label: Keycloak (iamlab)
    provider:
      type: custom
      client_id: warpgate
      client_secret: <secret client warpgate dari Keycloak>
      issuer_url: https://kc.iamlab.test/realms/iamlab
      scopes: ["email"]
YAML
docker compose cp ./warpgate.yaml warpgate:/data/warpgate.yaml && docker compose restart warpgate
```
Di konsol admin, beri pengguna Warpgate kredensial **SSO** (email sama dengan akun AD-nya).
Lalu tambahkan **target** SSH `srv1` (host `10.10.10.20`) dengan **role** terbatas, dan aktifkan
**perekaman sesi**. Warpgate masuk ke target memakai **kunci klien Warpgate** (konsol →
*SSH* → kunci milik Warpgate) yang dipasang di `authorized_keys` milik `labadmin` di `srv1` —
bukan sandi, karena sandi target sudah dimatikan di bagian B. Skrip `configure-target.sh` di
bawah mengerjakan ini:

![Warpgate — konsol admin (Config): tambah target SSH, Users, Access roles, perekaman sesi](gambar/warpgate-admin.png)

*Gambar 3. Warpgate — konsol admin (target SSH, Users, roles, rekam sesi)*

### C.1 🖥️ Akses target via SSH melalui bastion (sesuai silabus)
Peserta tidak SSH langsung ke server — selalu lewat bastion. Format Warpgate memakai
`user:target@bastion`; sesi direkam dan bisa diputar ulang di web UI:

![Diagram akses SSH ke srv1 melalui bastion Warpgate (SSO+MFA, SSH CA, rekam sesi)](gambar/ssh-bastion.png)

*Gambar 4. Akses SSH ke srv1 via bastion Warpgate*

*Legenda: penuh = koneksi/sesi; putus-putus = SSO/MFA & permintaan sertifikat; teal = rekaman sesi untuk audit.*

**Agenda Aktivitas (nomor pada diagram):**
1. Peserta `ssh -p 2222 <user>:srv1@pam.iamlab.test` ke **bastion**.
2. Warpgate meminta autentikasi via **Keycloak** (SSO OIDC + MFA).
3. Warpgate membuka sesi ke target memakai **kunci kliennya sendiri** (terdaftar di target).
   Jalur alternatif tanpa bastion — mis. *break-glass* — memakai **sertifikat SSH** berumur
   pendek yang ditandatangani **OpenBao** (SSH CA) untuk akun `labadmin`.
4. Sesi diteruskan ke **srv1**.
5. Sesi **direkam** → dapat diputar ulang & diaudit.

```bash
ssh -p 2222 <user>:srv1@pam.iamlab.test          # bastion mencegat, minta SSO/MFA, lalu teruskan
```

> **Otomasi (opsional).** Alih-alih klik di konsol, target+user+role bisa didaftarkan via
> Admin API dengan `configure-target.sh` (di `IAMLAB-BuildBag/deploy/warpgate/`)
> (mis. `PUBKEY="$(cat ~/.ssh/id_ed25519.pub)" ./configure-target.sh` → lalu
> `ssh -p 2222 peserta:srv1@pam.iamlab.test`). Diverifikasi tembus ke target
> sebagai `labadmin` dengan sesi terekam — peserta tak pernah memegang sandi server.
>
> **Troubleshooting (penting):**
> - **Admin API 401 walau login sukses:** cookie sesi Warpgate ber-domain `pam.iamlab.test`
>   (dari `external_host`). Akses API **lewat `https://pam.iamlab.test`** (via Caddy), bukan
>   `https://warpgate:8888` langsung.
> - **SSH ke bastion `Permission denied` berulang:** proteksi brute-force Warpgate memblok IP
>   sumber setelah banyak percobaan gagal (umum bila banyak klien berbagi satu IP NAT). Longgarkan
>   di konsol (Config) atau, untuk lab, hentikan Warpgate lalu kosongkan tabel `ip_blocks` &
>   `failed_login_attempts` pada `/data/db/db.sqlite3`, lalu jalankan kembali.

### D. Serah-terima kredensial via email + formulir
Akses istimewa tidak diberikan lisan. Alurnya **berbasis email dan formulir yang
dikembalikan**:
1. Pemohon mengisi [`formulir-serah-terima.docx`](formulir-serah-terima.docx) lalu mengirimnya
   via email ke pemberi persetujuan (di lab: lewat Mailpit `https://mail.iamlab.test`).
2. Pemberi persetujuan (dual control untuk Tier 0) **membalas email** dengan kolom
   *Status dikembalikan = Disetujui* terisi — inilah bukti formulir kembali.
3. Barulah kredensial diambil dari **OpenBao** (teraudit) dan akses dibuka lewat **bastion**
   (sesi terekam).
4. Setelah selesai: **rotasi** sandi *break-glass* dan kirim buktinya; pihak independen meninjau log.

**Hasil yang diharapkan:** OpenBao unsealed & audit aktif; root token tak valid; target
menolak sandi; akses hanya via bastion dan **terekam**.
