# Sesi 2 — SSO dan MFA (+ App-Komentar RBAC)

Indikator 2.1 (integrasi SSO SAML/OIDC) dan 2.2 (penegakan MFA). Sebagian besar
dikerjakan di 🌐 **Keycloak admin** (`https://kc.iamlab.test`); beberapa langkah di
🖥️ **terminal peserta** dan 🐳 **container**.

## Keterhubungan dengan sesi sebelumnya

Sesi ini **memakai direktori hasil Sesi 1**: Keycloak berfederasi ke AD memakai akun
layanan `svc-keycloak` (dibuat di Sesi 1), dan memetakan grup `GG-App-Viewer/Editor/Admin`
(juga dari Sesi 1) menjadi peran aplikasi. Jadi pastikan Sesi 1 selesai (akun & grup ada)
sebelum mulai. **Dipakai sesi berikutnya:** SSO Keycloak ini menjadi login untuk Warpgate
(Sesi 3); event login yang dihasilkan di sini dipantau di Sesi 4.

## a. Tujuan Sesi

Peserta mampu:
- Memahami cara sistem SSO di-*deploy*, lalu **mengonfigurasinya** sendiri.
- Membuat *realm* dan **federasi LDAP** Keycloak ke Active Directory.
- Mengintegrasikan aplikasi via **OIDC** (Authorization Code + PKCE) dan **SAML 2.0**.
- Memetakan **grup → peran** sehingga beda hak akses terlihat nyata (RBAC).
- Menegakkan **MFA (Google Authenticator)** bersyarat pada layanan kritikal.

## b. Output yang Diharapkan

- Pengguna AD tersinkron ke Keycloak dan dapat login SSO.
- Pada **App-Komentar**: *Viewer* hanya melihat; *Editor* menulis & menghapus miliknya;
  *Admin* menghapus semua. Penolakan ditegakkan **di sisi server**.
- Akun admin/realm dipaksa memindai OTP; brute force aktif; *event* login tercatat.

## c. Teori dan Struktur Sistem

**Single Sign-On (SSO)** berarti satu kali autentikasi ke *Identity Provider* (IdP), lalu banyak
aplikasi (*Service Provider*/*Relying Party*) memercayainya. Hasilnya: jumlah sandi berkurang,
kebijakan & audit terpusat, dan penonaktifan akun berlaku serentak.

**Alur data:**

![Alur SSO: aplikasi → Keycloak → federasi LDAP AD → MFA → token/assertion](gambar/alur-sso.png)

*Gambar 1. Alur SSO & MFA — login terfederasi*


*Legenda: garis penuh = langkah utama; putus-putus = redirect/token & sesi; teal = jejak audit. Nomor dijelaskan pada Agenda Aktivitas di bawah.*

**Agenda Aktivitas (nomor pada diagram):**
1. Pengguna membuka aplikasi (akses `/`).
2. Aplikasi mengarahkan ke Keycloak — OIDC *Authorization Code + PKCE* atau SAML *AuthnRequest*.
3. Pengguna mengisi form login di Keycloak.
4. Keycloak memverifikasi kredensial ke **Active Directory** (LDAPS 636) + menarik atribut/grup.
5. Keycloak meminta **MFA** bila kondisi (grup/klien kritikal) terpenuhi.
6. Keycloak mengembalikan **token/assertion** ke aplikasi.
7. Aplikasi membuka sesi; peran ditentukan dari klaim grup.
8. Event login (LOGIN/LOGIN_ERROR) dikirim ke **audit** (Alloy→Loki, Sesi 4).


*Gambar: pengguna menekan login di aplikasi → diarahkan ke Keycloak → Keycloak memeriksa kredensial ke AD lewat LDAPS, meminta OTP bila perlu → menerbitkan token yang dipercaya aplikasi.*

**Protokol:**
- *SAML 2.0* — XML Assertion bertanda tangan (App-SAML).
- *OIDC* — ID Token (JWT) di atas OAuth 2.0 (App-Komentar, Grafana, Warpgate). Alur aman:
  **Authorization Code + PKCE** (`code_challenge`/`code_verifier`), dilengkapi `state`
  (anti-CSRF) dan `nonce` (anti-replay ID Token). *Analogi PKCE:* saat menitip kunci
  Anda juga memberi teka-teki yang hanya Anda bisa jawab, agar tiket tak bisa dipakai
  pihak yang mencegatnya.

**MFA & tingkat jaminan (NIST SP 800-63B-4).** AAL2 mewajibkan MFA; peran istimewa
sebaiknya memakai autentikator *phishing-resistant* (WebAuthn/passkey). **Google
Authenticator** menghasilkan kode TOTP (RFC 6238) — faktor "sesuatu yang dimiliki".

**RBAC via klaim grup.** Keycloak menyertakan daftar grup pengguna di token; aplikasi
membaca klaim itu untuk menentukan izin. *Analogi:* gelang berwarna yang menentukan
panggung mana yang boleh dimasuki.

![Alur RBAC App-Komentar: grup AD/Keycloak → klaim token → izin aplikasi](gambar/alur-rbac.png)

*Gambar 2. Alur RBAC App-Komentar — grup → peran → izin*


*Legenda: putus-putus = klaim grup dalam token; nomor 1–3 = urutan grup → token → izin.*

*Gambar: grup tempat pengguna berada (Viewer/Editor/Admin) ikut dalam token sebagai klaim `groups`; aplikasi membaca klaim itu untuk memutuskan tombol & aksi yang boleh.*

## d. Praktik: Instalasi dan Konfigurasi

### 0. 🖥️ Deploy (sudah disiapkan — tetap dipahami)
Infrastruktur dinyalakan sekali dengan perintah di bawah; **ini bukan bagian yang
dinilai**, tetapi peserta perlu tahu cara sistem hidup. Konfigurasi detail (langkah
1–5) yang dikerjakan peserta.
```bash
cd deploy
cp .env.example .env            # sesuaikan DC_IP & sandi
docker compose up -d            # Keycloak + PostgreSQL + aplikasi + proxy berjalan (kosong)
```
Setelah ini Keycloak hidup di `https://kc.iamlab.test` tetapi **belum punya realm/
federasi/MFA** — semua itu Anda buat berikut.

> **✅ Validasi / Output yang diharapkan.** Keycloak butuh ±60 dtk sampai `healthy`:
> ```bash
> docker compose ps keycloak                       # → Up … (healthy)
> # dari host (setelah healthy); sertifikat CA internal → pakai -k
> curl -sk -o /dev/null -w "%{http_code}\n" https://kc.iamlab.test/realms/master   # → 200
> ```
> Di browser, `https://kc.iamlab.test` menampilkan halaman *Welcome to Keycloak*
> (login admin: `admin` / sandi dari `.env`).
> **⚠️ Jika dari host dapat `404`/halaman asing padahal container `healthy`:** ada
> aplikasi lain memegang **port 443** (sering `vmware-hostd` dari VMware Workstation).
> Uji cepat bahwa stack sebenarnya sehat dari dalam jaringan Docker:
> ```bash
> docker run --rm --network iamlab_iamnet curlimages/curl -s http://keycloak:8080/realms/master | head -c 80
> # → {"realm":"master","public_key":"MIIB…   (artinya Keycloak OK; masalah hanya di port host)
> ```
> Perbaikan: bebaskan port 443 di host (hentikan `vmware-hostd`/aplikasi lain) — lihat
> cek kesiapan host di **Sesi 0**.

### 1. 🌐 Realm + federasi LDAP ke AD
**Prasyarat (Sesi 1 langkah 5b):** CA AD sudah disalin ke `deploy/certs/ad-ca.pem` dan
Keycloak di-*recreate* — tanpa itu koneksi LDAPS gagal dengan galat sertifikat (PKIX).

Buat realm `iamlab`. Lalu **User federation → Add Ldap provider**, isi persis seperti ini:
- Vendor: *Active Directory* · Connection URL: `ldaps://dc1.iamlab.test:636`
- Bind DN: `CN=svc-keycloak,OU=AkunLayanan,DC=iamlab,DC=test` · Bind credential: sandi
  svc-keycloak **terbaru** (yang Anda set saat reset di Sesi 1 langkah 5)
- Edit mode: **READ_ONLY** · **Users DN: `DC=iamlab,DC=test`** (root — mencakup akun
  admin & layanan; jika hanya `OU=Pengguna`, login SSO admin gagal diam-diam)
- Username LDAP attr: `sAMAccountName` · UUID: `objectGUID`

Cocokkan layar Anda dengan tangkapan berikut (form terisi), lalu **Save → Test
connection & authentication → Synchronize all users**:

![Keycloak — form User federation LDAP terisi (Vendor AD, Connection URL ke AD)](gambar/kc-ldap-detail.png)

*Gambar 3. Keycloak — form User federation LDAP*


*Gambar: form federasi LDAP terisi — Vendor *Active Directory*, Connection URL `ldaps://dc1.iamlab.test:636`. Cocokkan nilai di layar Anda dengan ini sebelum menekan Save.*

Tambahkan **Mappers → group-ldap-mapper** (LDAP Groups DN `OU=Grup,DC=iamlab,DC=test`)
lalu **Sync LDAP groups**. Daftar provider federasi:

![Keycloak — User federation: provider LDAP (Enabled)](gambar/kc-user-federation.png)

*Gambar 4. Keycloak — User federation (provider LDAP aktif)*


### 2. 🌐 Client OIDC untuk App-Komentar
**Clients → Create → OpenID Connect**, Client ID `app-komentar`:
- Client authentication **On**; Standard flow **On**; **Direct access grants Off**.
- Valid redirect URIs: `https://app.iamlab.test/callback` · Web origins: `https://app.iamlab.test`.
- **Advanced → PKCE: S256** (aplikasi mewajibkannya — tanpa ini login gagal
  "Missing parameter: code_challenge_method").
- Tambah **Group Membership mapper**: claim `groups`, **Full group path = Off**.

Cocokkan layar pengaturan client:

![Keycloak — detail Client app-komentar (redirect URI, PKCE, akses)](gambar/kc-client-detail.png)

*Gambar 5. Keycloak — detail Client app-komentar*


Tab Advanced menampilkan PKCE S256 (wajib):

![Keycloak — Client app-komentar tab Advanced (PKCE S256)](gambar/kc-client-advanced.png)

*Gambar 6. Keycloak — Client tab Advanced (PKCE S256)*


![Keycloak — daftar Clients realm iamlab](gambar/kc-clients.png)

*Gambar 7. Keycloak — daftar Clients realm iamlab*


Lalu 🖥️ salin **Client secret** ke `deploy/.env` (`APP_OIDC_CLIENT_SECRET=…`) dan muat
ulang aplikasi: `docker compose up -d app-komentar`.

### 2b. 🌐 Client OIDC untuk Warpgate (dipakai Sesi 3)
**Clients → Create → OpenID Connect**, Client ID `warpgate`:
- Client authentication **On**; Standard flow **On**; Direct access grants **Off**.
- Valid redirect URIs: `https://pam.iamlab.test/@warpgate/api/sso/return`.
- Simpan **Client secret** — diisi di konfigurasi SSO Warpgate pada Sesi 3 bagian C.

### 3. 🌐 Client SAML untuk App-SAML
**Clients → Create → SAML**. Tukar metadata IdP
(`https://kc.iamlab.test/realms/iamlab/protocol/saml/descriptor`) untuk konfigurasi SP
(mod_auth_mellon); assertion **signed**.

### 4. 🌐 MFA bersyarat (Google Authenticator)
- **Authentication → Required actions**: *Configure OTP* = On.

  ![Keycloak — Required actions (Configure OTP aktif)](gambar/kc-required-actions.png)

*Gambar 8. Keycloak — Required actions (Configure OTP aktif)*

- **Authentication → Flows**: duplikat *Browser*, tambah sub-flow **Conditional OTP** →
  *OTP Form* **Required**, targetkan ke grup admin & client kritikal (Warpgate).

  ![Keycloak — Authentication flows (duplikat Browser lalu tambah sub-flow Conditional OTP = Required)](gambar/kc-auth-flows.png)

*Gambar 9. Keycloak — Authentication flows (Conditional OTP = Required)*

- Uji: pengguna biasa login App-Komentar tanpa OTP; **admin dipaksa memindai QR**
  Google Authenticator.

> Keamanan: Keycloak menampilkan banner "temporary admin user". Buat akun admin
> permanen (Realm master → Users) lalu hapus akun sementara sebelum produksi.

### 5. 🌐 Brute force, SMTP, events
- **Realm settings → Security defenses → Brute force detection: On**.
- **Realm settings → Email**: Host `mailpit`, Port `1025` (reset & verifikasi sandi).
- **Realm settings → Sessions/Tokens**: perpendek masa hidup sesi & token.
- **Realm settings → Events**: *Save events* (user + admin) + listener `jboss-logging`.

Cocokkan layar Anda dengan tiga tangkapan berikut:

![Keycloak — Security defenses: Brute force detection aktif](gambar/kc-bruteforce.png)

*Gambar 10. Keycloak — Brute force detection aktif*


*Gambar: proteksi brute force menyala — akun dikunci sementara setelah sejumlah kegagalan login (mis. 10), waktu tunggu bertambah.*

![Keycloak — Realm settings → Email (SMTP ke Mailpit)](gambar/kc-email.png)

*Gambar 11. Keycloak — Email (SMTP ke Mailpit)*


*Gambar: SMTP diarahkan ke Mailpit (`mailpit:1025`) agar email reset/verifikasi tertangkap di kotak surat uji, bukan terkirim ke internet.*

![Keycloak — konfigurasi Events (user + admin, listener jboss-logging)](gambar/kc-events.png)

*Gambar 12. Keycloak — konfigurasi Events*


*Gambar: pencatatan event diaktifkan sehingga login/perubahan admin terekam dan bisa dipanen Alloy → Loki di Sesi 4.*

### Hasil: beda hak akses (RBAC) pada App-Komentar
Login `https://app.iamlab.test` dengan tiga akun berbeda grup — perhatikan tombol/aksi
yang tersedia berbeda, dan penolakan ditegakkan **di server** (bukan sekadar tombol disembunyikan):

| Viewer (hanya lihat) | Editor (tulis + hapus miliknya) | Admin (hapus semua + step-up) |
|---|---|---|
| ![Viewer](gambar/app-viewer.png) | ![Editor](gambar/app-editor.png) | ![Admin](gambar/app-admin.png) |

*Gambar 13. App-Komentar — tampilan peran Viewer, Editor, Admin*

Halaman login SSO Keycloak yang muncul saat menekan "masuk":

![Halaman login Keycloak (SSO)](gambar/kc-login.png)

*Gambar 14. Halaman login Keycloak (SSO)*


### (Terkait) Distribusi kata sandi awal via email
Saat *bulk import* (Sesi 1), sandi awal dikirim ke **Mailpit** (kotak surat uji), dan
Keycloak juga mengirim email aksi akun (set sandi/verifikasi). Alurnya:

![Distribusi kata sandi awal via email (Mailpit) untuk akun AD & Keycloak](gambar/distribusi-sandi.png)

*Gambar 15. Distribusi kata sandi awal via email*


> Catatan: realm Keycloak 26 punya aksi default **Verify Profile**. Pengguna AD sudah
> lengkap (email/nama); jika membuat pengguna lokal untuk uji, isi email + firstName +
> lastName + sandi permanen, atau login ditolak "Account is not fully set up".
