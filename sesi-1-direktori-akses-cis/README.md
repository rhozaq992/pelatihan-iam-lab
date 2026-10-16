# Sesi 1 — Pengamanan Direktori Terpusat (Samba AD/LDAP), Join Domain & CIS

Indikator 1.1 (hardening direktori AD/LDAP) dan 1.2 (kebijakan keamanan terpusat ke
endpoint). Sesi ini membangun direktori **Samba AD DC** (`dc1`, container), menggabungkan
**VM Ubuntu** `srv1` (server) dan `client1` (desktop) ke domain, menerapkan **kebijakan akses
terpusat**, lalu mengaudit kepatuhan endpoint dengan **CIS Benchmark**.

Penanda tempat menjalankan: 🐳 **container `samba-dc` (dc1)** · 🖥️ **VM Ubuntu (srv1/client1)** ·
🖥️ **terminal host** (docker). (Lihat Sesi 0 untuk arti lengkap.)

## Keterhubungan dengan sesi lain

Ini sesi praktik pertama; ia memakai konsep identitas dari **Sesi 0** (IAAA, tiering).
**Yang dibuat di sini dipakai sesi berikutnya:** OU & grup `GG-*`, akun layanan `svc-keycloak`
(federasi Sesi 2), `svc-openbao` + grup `GG-Tier1-Admin` (Sesi 3), kebijakan sandi, serta
event audit direktori & endpoint yang dipantau di Sesi 4. **VM `srv1`** menjadi target SSH
untuk bastion (Sesi 3). Jadi selesaikan sesi ini lebih dulu.

## a. Tujuan Sesi

Peserta mampu:
- Mengatur direktori terpusat (OU, *tiering*, grup) di Samba AD dan melakukan *bulk import* pengguna.
- Menerapkan kebijakan kata sandi domain dan PSO untuk akun istimewa.
- *Hardening* direktori: LDAPS, AES-only Kerberos, menonaktifkan protokol lemah.
- Menggabungkan klien & server Linux ke domain dan menegakkan **kebijakan akses terpusat**
  (siapa boleh login ke mana, hak sudo berbasis grup).
- Mengaudit kepatuhan endpoint terhadap **CIS Benchmark** (OpenSCAP), meremediasi, lalu menilai ulang.
- Mengenali sinyal **Kerberoasting** & **Pass-the-Hash** pada log, lalu menutupnya dengan mitigasi.

## b. Output yang Diharapkan

- Direktori berisi ±220 pengguna di `OU=Pengguna`; anggota `Domain Admins` minimal.
- Akun layanan (`svc-*`) memakai enkripsi **AES** (bukan RC4); protokol lemah dinonaktifkan.
- `srv1` dan `client1` tergabung ke domain; pengguna direktori dapat login (SSH & GUI), hanya
  grup yang diizinkan, dan hak admin mengikuti keanggotaan grup AD.
- Laporan **CIS Level 1** untuk server (`srv1`) dan workstation (`client1`) tersimpan, dengan
  skor **meningkat** setelah remediasi.
- Pada simulasi: sebelum mitigasi tiket layanan memakai RC4 (hash `$krb5tgs$23$`); setelah
  AES-only, tiket memakai AES (`$krb5tgs$18$`).

## c. Teori dan Struktur Sistem

*Active Directory* (di sini **Samba AD**) adalah direktori + *control plane* identitas:
menyimpan pengguna/grup/komputer (LDAP), menerbitkan tiket **Kerberos** (KDC), dan menjadi
sumber kebenaran (source of truth) identitas bagi layanan (Keycloak, OpenBao) maupun host (klien Linux).

Kompromi pada Domain Controler (DC) atau akun Tier 0 sama dengan kompromi seluruh domain. Karena itu active direktori adalah aset paling bernilai yang harus di hardening lebih dulu.

**Model tiering (Enterprise Access Model).** 
- Tier 0 (DC, sinkronisasi identitas) = bidang kendali tertinggi;
- Tier 1 (server/aplikasi);
- Tier 2 (perangkat pengguna).
Prinsipnya, kredensial tier tinggi tidak boleh terpapar di tier rendah, agar kompromi zona bawah tidak
naik ke atas.

### Kebijakan keamanan terpusat untuk endpoint Linux (padanan GPO)

Di AD Windows, kebijakan endpoint didorong lewat **GPO**. Pada direktori Linux, fungsi serupa
dicapai dengan menggabungkan klien ke domain lalu menegakkan kebijakan di sisi klien dari
sumber terpusat:

| Tujuan kebijakan | Mekanisme di lab Linux |
|------------------|------------------------|
| Siapa boleh login ke suatu host | `sssd` `access_provider = simple` + `simple_allow_groups` (grup AD per host) |
| Hak administratif (sudo) | aturan `sudoers` berbasis **grup AD** (mis. `%GG-Tier1-Admin`) |
| Baseline konfigurasi aman | **CIS Benchmark** via OpenSCAP (audit + remediasi), lihat bagian praktik |
| Kebijakan sandi & penguncian | kebijakan domain Samba + PSO untuk admin |

### Dua teknik serangan 
**Kerberoasting.** *Setiap* akun domain boleh meminta tiket layanan (TGS) untuk akun layanan
ber-SPN; bagian tiket terenkripsi dengan kunci turunan **sandi akun layanan**, lalu penyerang
menebak sandi itu **luring** (di luar jaringan, tanpa menyentuh DC lagi — itulah yang membuatnya
sulit terlihat). Ikuti prosesnya langkah demi langkah:

![Skema Kerberoasting (animasi langkah demi langkah)](gambar/kerberoasting.gif)

*Gambar 1. Skema Kerberoasting (animasi langkah demi langkah)*

![Skema Kerberoasting (ringkas) + titik mitigasi & deteksi](gambar/kerberoasting-skema.png)

*Gambar 2. Skema Kerberoasting ringkas — titik mitigasi & deteksi*

*Analogi:* meminjam gembok resmi, membawanya pulang, mencoba ribuan kunci di rumah.
**Mitigasi:** sandi akun layanan sangat panjang/acak, dan **Kerberos AES-only** sehingga tiket
RC4 lemah tak terbit. **Deteksi:** permintaan tiket untuk SPN layanan dari akun non-mesin;
akun umpan (*honey SPN* `svc-honey`).

**Pass-the-Hash (PtH).** Penyerang yang menguasai sebuah host mengambil *hash* kredensial dari
memori, lalu memakainya untuk autentikasi ke host lain **tanpa tahu sandi aslinya**.

![Skema Pass-the-Hash + titik mitigasi & deteksi](gambar/pass-the-hash.png)

*Gambar 3. Skema Pass-the-Hash — titik mitigasi & deteksi*

*Analogi:* mencuri cetakan sidik jari lalu memakainya di pemindai lain. **Mitigasi:** isolasi
tier, kurangi NTLM (`ntlm auth = ntlmv2-only` di Samba — tutup NTLMv1; *disabled* penuh memutus
federasi LDAP, lihat langkah 5), kredensial admin unik per host.
**Deteksi:** autentikasi NTLM lintas banyak host, logon tak lazim.

**Catatan enctype Kerberos:** pada tiket/hasil Kerberoasting, `$krb5tgs$23$` = RC4-HMAC
(lemah), `$krb5tgs$18$` = AES256 (kuat). Target mitigasi: hilangkan RC4.

## d. Praktik: Instalasi dan Konfigurasi

> **Deploy (disiapkan `build-lab.ps1`):** container `samba-dc` sudah ter-*provision* menjadi
> domain `iamlab.test`, dan VM `srv1`/`client1` sudah menyala di jaringan Host-Only. Peserta
> **mengonfigurasi keamanannya**.

### 1. 🐳 Struktur OU, grup, dan akun layanan
Jalankan `samba-tool` **di dalam container `samba-dc`**. Buka shell DC:
```bash
# 🖥️ terminal host (PowerShell/terminal apa pun dengan docker)
cd ../deploy        # stack di IAMLAB-BuildBag; modul diklon di IAMLAB-BuildBag/Pelatihan_IAM
docker compose exec samba-dc bash      # masuk ke container dc1
```
```bash
# 🐳 di dalam container samba-dc (dc1)
for ou in Tier0 Server Workstations Pengguna Grup AkunLayanan; do
  samba-tool ou create "OU=$ou,DC=iamlab,DC=test"; done
for g in GG-Pimpinan GG-Keuangan GG-SDM GG-TI GG-Operasional GG-Layanan GG-Hukum \
         GG-App-Viewer GG-App-Editor GG-App-Admin GG-Tier0-Admin GG-Tier1-Admin; do
  samba-tool group add "$g" --groupou="OU=Grup"; done
for s in svc-keycloak svc-openbao svc-app svc-honey; do
  samba-tool user create "$s" 'Svc#Lab2026!' --userou=OU=AkunLayanan --use-username-as-cn
  samba-tool user setexpiry "$s" --noexpiry; done
# SPN: svc-app = layanan nyata (sasaran simulasi), svc-honey = umpan deteksi
samba-tool spn add HTTP/app.iamlab.test   svc-app
samba-tool spn add HTTP/honey.iamlab.test svc-honey
# --- VALIDASI (bagian dari langkah — jalankan juga) ---
samba-tool ou list | sort                        # -> OU=AkunLayanan, OU=Grup, OU=Pengguna, OU=Server, OU=Tier0, OU=Workstations
samba-tool spn list svc-app                       # -> User CN=svc-app,... : HTTP/app.iamlab.test
```

**Keluaran yang diharapkan.** Tiap `ou create` membalas `Added ou "OU=…"`; tiap `group add` /
`user create` membalas `… added successfully`. `samba-tool ou list` memuat **enam** OU di atas,
dan `samba-tool spn list svc-app` memuat `HTTP/app.iamlab.test`.

### 2. 🐳 Bulk import pengguna
`import-ad.sh` membaca CSV lalu membuat akun + keanggotaan grup + sandi awal acak + flag
"ganti saat login pertama". Salin folder sesi ini ke container, lalu jalankan:
```bash
# 🖥️ terminal host
docker compose cp ../Pelatihan_IAM/sesi-1-direktori-akses-cis samba-dc:/tmp/sesi1
# 🐳 di dalam container samba-dc — --send-email mengirim sandi awal ke Mailpit
docker compose exec samba-dc bash /tmp/sesi1/import-ad.sh --csv /tmp/sesi1/users_dummy.csv --send-email
docker compose exec samba-dc bash /tmp/sesi1/import-ad.sh --csv /tmp/sesi1/users_batch2.csv   # latihan +20
docker compose exec samba-dc samba-tool user list | wc -l       # -> jumlah user (±223: 220 impor + svc-* + admin)
# --- VALIDASI ---
docker compose exec samba-dc samba-tool user show dewi.puspita001 | grep -Ei 'pwdLastSet|department|mail'  # -> pwdLastSet: 0 + atribut
```

**Keluaran yang diharapkan.** Ringkasan `Selesai: dibuat 200, …` (batch2: `dibuat 20`).
`user show dewi.puspita001` menampilkan `pwdLastSet: 0` (wajib ganti saat login pertama) plus
atribut department/title/mail. Email sandi awal tampak di Mailpit (`https://mail.iamlab.test`).
🖥️ Butuh data ulang? `python3 gen_dummy_users.py --count 200 --out users_dummy.csv`.

### 3. 🐳 Batasi admin domain & siapkan admin Tier 1
Prinsip *least privilege*: jaga `Domain Admins` minimal, siapkan admin Tier 1 (dipakai login
OpenBao via LDAP di Sesi 3):
```bash
samba-tool group listmembers "Domain Admins"            # audit — sisakan seminimal mungkin
samba-tool user create adm-t1-anda 'Adm1#Lab2026' --userou=OU=Pengguna --use-username-as-cn
samba-tool group addmembers GG-Tier1-Admin adm-t1-anda
```

### 4. 🐳 Kebijakan kata sandi + PSO untuk admin
```bash
samba-tool domain passwordsettings set --min-pwd-length=14 --complexity=on --history-length=5
samba-tool domain passwordsettings set --account-lockout-threshold=10 --account-lockout-duration=15
# PSO lebih ketat khusus admin Tier 0:
samba-tool domain passwordsettings pso create PSO-Admin 10 --min-pwd-length=20 --complexity=on
samba-tool domain passwordsettings pso apply PSO-Admin GG-Tier0-Admin
# --- VALIDASI ---
samba-tool domain passwordsettings show                 # -> Minimum password length: 14 · Password complexity: on
samba-tool domain passwordsettings pso show PSO-Admin   # -> Minimum password length: 20
```

**Keluaran yang diharapkan.** `Minimum password length: 14` dan `Password complexity: on` pada
kebijakan domain; `PSO-Admin` menampilkan min length **20**.

### 5. 🐳🖥️ Hardening direktori: AES-only, NTLM, & LDAPS (Trust CA)
Tiga pengerasan berurutan dalam **satu langkah**. Jalankan semuanya — **termasuk baris validasi `# →`**.

**5.1 🐳 Kerberos AES-only untuk akun layanan** — buang RC4; reset sandi agar kunci Kerberos dibuat ulang (svc-app = sasaran simulasi, svc-keycloak = Sesi 2):
```bash
# 🐳 di dalam container samba-dc
for s in svc-app svc-keycloak svc-openbao svc-honey; do
  printf 'dn: CN=%s,OU=AkunLayanan,DC=iamlab,DC=test\nchangetype: modify\nreplace: msDS-SupportedEncryptionTypes\nmsDS-SupportedEncryptionTypes: 24\n' "$s" \
    | ldbmodify -H /var/lib/samba/private/sam.ldb
done
samba-tool user setpassword svc-keycloak --newpassword='Svc#Lab2026baru'   # CATAT -> Bind credential Sesi 2
# --- VALIDASI ---
ldbsearch -H /var/lib/samba/private/sam.ldb '(cn=svc-app)' msDS-SupportedEncryptionTypes \
  | grep -i SupportedEncryptionTypes      # -> msDS-SupportedEncryptionTypes: 24  (AES128+AES256, tanpa RC4)
```
> ⚠️ Sandi baru `svc-keycloak` (`Svc#Lab2026baru`) inilah yang diisi sebagai **Bind credential**
> federasi LDAP Keycloak di Sesi 2 — catat baik-baik.

**5.2 🐳 Batasi NTLM ke `ntlmv2-only`** — mitigasi Pass-the-Hash tanpa memutus LDAP simple-bind:
```bash
# 🐳 sisipkan DI DALAM seksi [global] smb.conf (bukan di akhir berkas -> akan masuk [netlogon] & tak berlaku)
sed -i '/^\[global\]/a\    ntlm auth = ntlmv2-only' /etc/samba/smb.conf
smbcontrol all reload-config
# --- VALIDASI ---
testparm -sv 2>/dev/null | grep -i 'ntlm auth'          # -> ntlm auth = ntlmv2-only
```
> ⚠️ **Jangan pakai `ntlm auth = disabled`.** Mematikan NTLM sepenuhnya juga mematahkan **LDAP
> simple-bind** (dipakai federasi Keycloak & auth LDAP OpenBao) — federasi gagal tanpa error
> setelah DC di-restart (`ldap_bind data 418`). `ntlmv2-only` sudah menutup NTLMv1 yang lemah.

**5.3 🖥️ LDAPS: ekspor CA Samba ke layanan IAM** — agar Keycloak (Sesi 2) & OpenBao (Sesi 3)
memercayai LDAPS 636; sertifikat **wajib ber-SAN** untuk OpenBao (klien Go menolak CN-only:
`x509: legacy Common Name`). **Keluar dari shell container dulu**, lalu di terminal host dari folder `deploy`:
```bash
# 🖥️ terminal host (folder deploy) — pastikan cert LDAPS ber-SAN (idempoten; build baru sudah beres)
docker compose exec samba-dc sh -c 'cd /var/lib/samba/private/tls; \
  openssl x509 -in cert.pem -noout -text | grep -q "Subject Alternative Name" || { \
  openssl req -x509 -newkey rsa:4096 -keyout key.new -out cert.new -days 3650 -nodes \
    -subj "/O=Samba Administration/CN=DC1.iamlab.test" \
    -addext "subjectAltName=DNS:dc1.iamlab.test,IP:10.10.10.5"; \
  mv cert.new cert.pem; mv key.new key.pem; cp cert.pem ca.pem; chmod 600 key.pem; }'
docker compose restart samba-dc
docker compose cp samba-dc:/var/lib/samba/private/tls/ca.pem certs/ad-ca.pem   # ekspor CA
docker compose up -d --force-recreate keycloak openbao                         # muat truststore CA
# --- VALIDASI (dari host git-bash, atau dari srv1 via SSH — bukan docker compose exec) ---
echo | openssl s_client -connect 10.10.10.5:636 2>/dev/null \
  | openssl x509 -noout -subject -ext subjectAltName
#  -> subject= ... CN = DC1.iamlab.test
#  -> X509v3 Subject Alternative Name: DNS:dc1.iamlab.test, IP:10.10.10.5
```

**Keluaran yang diharapkan (langkah 5).** `msDS-SupportedEncryptionTypes: 24` (AES-only, tanpa RC4);
`testparm` menampilkan `ntlm auth = ntlmv2-only`; `openssl s_client` ke `:636` menampilkan subjek
`CN=DC1.iamlab.test` **dan** SAN `DNS:dc1.iamlab.test, IP:10.10.10.5`. CA otomatis dipercaya
Keycloak/OpenBao via mount `deploy/certs`. (`srv1`/`client1` adalah VM — validasi di VM lewat
SSH/konsol, bukan `docker compose exec`.)

### 6. 🖥️ Gabungkan `srv1` & `client1` ke domain
Login ke VM sebagai admin lokal (`labadmin` / `Lab#Admin2026`), lalu jalankan skrip join
(dibaking saat build). DNS tidak dipakai di lab (port 53 tak dipublikasikan) — skrip menunjuk
DC langsung.
```bash
# 🖥️ di srv1 (SSH: ssh labadmin@srv1.iamlab.test) DAN di client1 (konsol VirtualBox)
sudo join-domain.sh                 # minta sandi Administrator domain (Passw0rd#Lab2026)
# --- VALIDASI ---
id dewi.puspita001                  # -> uid=...(dewi.puspita001) grup: gg-pimpinan, gg-app-viewer, ...
```

**Keluaran yang diharapkan.** Skrip menampilkan `akun domain terbaca: …`; `id dewi.puspita001`
memuat grup `gg-pimpinan`, `gg-app-viewer`. Di `client1`, pada layar login GDM pilih
"Not listed?" lalu masuk sebagai `dewi.puspita001` (wajib ganti sandi awal).

### 7. 🖥️ Kebijakan akses terpusat (padanan GPO)
Batasi **siapa** boleh login ke tiap host dan **hak sudo** berbasis grup AD. Edit di tiap VM:
```bash
# 🖥️ di srv1 — hanya admin TI & Tier 1 boleh SSH ke server
sudo sed -i 's/^access_provider = .*/access_provider = simple/' /etc/sssd/sssd.conf
echo 'simple_allow_groups = GG-TI,GG-Tier1-Admin' | sudo tee -a /etc/sssd/sssd.conf
# sudo untuk anggota GG-Tier1-Admin (grup AD) — perhatikan tanda % dan \ untuk spasi
echo '%GG-Tier1-Admin ALL=(ALL) ALL' | sudo tee /etc/sudoers.d/iamlab-tier1
sudo systemctl restart sssd
# --- VALIDASI (tanpa perlu login; uji kebijakan akses sshd) ---
sudo sssctl user-checks dewi.puspita001 -s sshd   # -> access denied  (pimpinan, bukan TI/Tier1)
sudo sssctl user-checks adm-t1-anda   -s sshd     # -> access granted
sudo -l -U adm-t1-anda                            # -> (ALL) ALL  (hak sudo dari grup AD)
```
```bash
# 🖥️ di client1 — hanya pengguna umum & pimpinan boleh login workstation
sudo sed -i 's/^access_provider = .*/access_provider = simple/' /etc/sssd/sssd.conf
echo 'simple_allow_groups = GG-Pimpinan,GG-SDM,GG-TI,GG-Keuangan,GG-Operasional,GG-Layanan,GG-Hukum' | sudo tee -a /etc/sssd/sssd.conf
sudo systemctl restart sssd
```
**Keluaran yang diharapkan.** `sssctl user-checks dewi.puspita001` → **access denied**;
`adm-t1-anda` → **access granted** dengan `sudo -l` memuat `(ALL) ALL`. Uji nyata via SSH:
`ssh dewi.puspita001@srv1.iamlab.test` **ditolak**, `ssh adm-t1-anda@srv1.iamlab.test`
**diterima**. Kebijakan berlaku terpusat: ubah keanggotaan grup di `dc1` → efek di semua host.

### 8. 🖥️ Audit kepatuhan CIS Benchmark
`cis-scan.sh` (dibaking saat build) memakai **OpenSCAP + SCAP Security Guide**. Profil
dideteksi otomatis: *server* di `srv1`, *workstation* di `client1`.
```bash
# 🖥️ di srv1 dan client1
sudo cis-scan.sh                      # scan CIS Level 1 (±3–10 menit)
sudo cis-scan.sh --list-fail | head   # rule yang gagal, diurut tingkat keparahan
sudo cis-scan.sh --fix <rule-id>      # remediasi SATU rule (terarah), lalu:
sudo cis-scan.sh                      # scan ulang — skor harus naik
# --- VALIDASI ---
tail -n 2 /var/log/cis/summary.log    # -> 2 baris JSON; "score" scan KEDUA > scan pertama
ls -1 /var/log/cis/report-latest.html # -> laporan HTML ada
```

**Keluaran yang diharapkan.** Tiap scan menulis satu baris JSON ke `/var/log/cis/summary.log`
(`{"host":"srv1","profile":"cis_level1_server","pass":…,"fail":…,"score":…}`) + laporan HTML
`/var/log/cis/report-latest.html`. Skor scan **kedua** lebih tinggi (mis. 67.2 → 67.7). Ringkasan
dikirim ke Grafana (Sesi 4, panel skor CIS per host).

> **Level 2 (pengayaan, bukan target kelulusan Sesi 1).** `sudo cis-scan.sh --level 2`
> menjalankan profil yang lebih ketat.

---

## Simulasi Terkendali & Mitigasi (Kerberoasting & PtH)

Bagian ini memperlihatkan **bagaimana serangan tampak dari sisi log**, lalu membuktikan bahwa
kontrol yang Anda pasang menutupnya. Sepenuhnya defensif dan berjalan di jaringan Host-Only
terisolasi: container `attacker` berjalan di jaringan `attacknet` (`internal: true`) yang hanya
menjangkau `dc1` tanpa rute ke internet, sehingga runner `attack-sim/run.sh` — yang hanya menerima
target dari allowlist `iamlab.test`, mewajibkan `IAMLAB_CONFIRM=1`, dan menolak berjalan bila
internet terjangkau — lolos pagar tanpa perlu memutus Wi-Fi/LAN PC. Tujuannya melatih
mata mengenali pola Kerberoasting/PtH dan merasakan efek mitigasi secara langsung.

1. 🐳 Pastikan SPN ada: `samba-tool spn list svc-app` menampilkan `HTTP/app.iamlab.test`
   (sasaran) dan `samba-tool spn list svc-honey` menampilkan `HTTP/honey.iamlab.test` (umpan).
2. 🐳 Jalankan runner dari container simulasi (`docker compose --profile attack up -d attacker`).
   Runner memvalidasi pagar lalu menampilkan perintah **Impacket** (`GetUserSPNs.py`) yang
   dijalankan instruktur untuk benar-benar meminta tiket layanan:
   ```bash
   # 🐳 (target harus ada di attack-sim/TARGETS.lab; konfirmasi wajib)
   docker compose exec -e IAMLAB_CONFIRM=1 attacker bash /attack-sim/run.sh dc1.iamlab.test kerberoast
   ```
   **Keluaran yang diharapkan.** Di lab terisolasi, runner **mencetak** (tidak mengeksekusi)
   perintah contoh. Bila dijalankan instruktur terhadap `svc-app`, hasilnya hash tiket:
   **sebelum** mitigasi terlihat `$krb5tgs$23$` (RC4); **sesudah** AES-only terlihat
   `$krb5tgs$18$` (AES256). Hash tidak dipecahkan di kelas — cukup amati perubahan enctype
   sebagai bukti mitigasi.
3. 🐳 Terapkan mitigasi pada akun layanan sasaran (AES-only), lalu ulangi langkah 2:
   ```bash
   # 🐳 di dalam container samba-dc — paksa AES-only utk svc-app, lalu reset sandi (kunci AES baru)
   printf 'dn: CN=svc-app,OU=AkunLayanan,DC=iamlab,DC=test\nchangetype: modify\nreplace: msDS-SupportedEncryptionTypes\nmsDS-SupportedEncryptionTypes: 24\n' \
     | ldbmodify -H /var/lib/samba/private/sam.ldb
   samba-tool user setpassword svc-app --newpassword='Svc#Lab2026AES'
   ```
4. **Diskusi PtH (tanpa langkah ofensif):** mengapa membatasi NTLM (`ntlm auth = ntlmv2-only`),
   isolasi tier, dan kredensial unik per host memutus pemakaian ulang hash.

> **Troubleshooting.** `GetUserSPNs.py` → `KRB_AP_ERR_SKEW`/galat waktu: selisih jam antara
> container penyerang dan DC. Samakan waktu (lab di satu host biasanya sudah sinkron) lalu ulangi.

**Relevansinya:** akun layanan ber-SPN dan hash kredensial adalah dua jalur eskalasi paling umum
di direktori. Dengan menjalankan simulasi lalu menerapkan AES-only/anti-NTLM, peserta melihat
sendiri perubahan enctype dari RC4 ke AES — bukti konkret bahwa mitigasi bekerja, bukan sekadar teori.

**Hasil yang diharapkan:** direktori terisi & terkeraskan; `srv1`/`client1` tergabung dengan
akses terpusat; laporan CIS membaik setelah remediasi; tiket Kerberos berpindah dari RC4 ke AES.

---

[⬅️ Sebelumnya: Sesi 0 — Pengantar](../sesi-0-pengantar/README.md) · [🏠 Home](../README.md) · [Selanjutnya: Sesi 2 — SSO & MFA ➡️](../sesi-2-sso-mfa/README.md)
