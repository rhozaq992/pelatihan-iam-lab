# Sesi 4 — Audit & Monitoring Aktivitas Identitas

Indikator 4.1 (audit autentikasi/otorisasi) dan 4.2 (deteksi anomali). Membangun jejak
audit identitas *end-to-end* dan dashboard pemantauan. Penanda: 🖥️ **terminal peserta**
· 🐳 **container** · 🌐 **web UI (Grafana)**.

## Keterhubungan dengan sesi sebelumnya

Sesi ini **menutup rangkaian**: ia memanen event dari **Sesi 1** (Windows AD: logon,
Kerberos, perubahan grup), **Sesi 2** (Keycloak: LOGIN/LOGIN_ERROR, perubahan MFA), dan
**Sesi 3** (OpenBao: akses vault; Warpgate: sesi bastion; sshd target). Tanpa konfigurasi
audit di sesi-sesi itu (mis. Events Keycloak di Sesi 2, audit device OpenBao di Sesi 3),
dashboard di sini akan kosong — jadi pastikan sumbernya sudah aktif.

## a. Tujuan Sesi

Peserta mampu:
- Memahami cara pipeline log di-*deploy*, lalu **melengkapinya**.
- Mengumpulkan log identitas dari seluruh komponen ke satu tempat (Loki).
- Membuat **dashboard** audit identitas dan **aturan alert** di Grafana.
- Menerapkan **UBA dasar** untuk mendeteksi perilaku tak lazim / akun kompromi, lalu merespons.

## b. Output yang Diharapkan

- ≥ 5 sumber log tampil di Loki; dashboard menampilkan login sukses vs gagal, top IP gagal,
  aktivitas per klien, dan perubahan grup istimewa.
- Minimal 4 aturan alert aktif; alert memicu email uji di Mailpit.
- Pada capstone: akun terindikasi kompromi dikunci di semua layanan + laporan insiden.

## c. Teori dan Struktur Sistem

**Apa.** *Jejak audit identitas* menjawab "**siapa** mengakses **apa**, **kapan**,
dari **mana**, berhasil/gagal". **UBA (User Behavior Analytics) dasar** mencari
penyimpangan dari kebiasaan.

**Mengapa.** Kontrol pencegahan tidak pernah 100%; deteksi + respons memperpendek
waktu tinggal penyerang dan memenuhi kewajiban audit (mis. Peraturan BSSN tentang audit SPBE).

**Apa yang dicari.** Ledakan kegagalan login (brute force), gagal lalu
tiba-tiba berhasil, login di jam/IP tak lazim, perubahan keanggotaan grup istimewa,
tiket Kerberos RC4. *Analogi:* satpam yang hafal pola normal dan curiga saat ada yang
mencoba 100 pintu dalam semenit.

### Standar audit trail yang diterapkan

Rancangan audit lab mengikuti kerangka yang diakui luas sehingga jejaknya cukup untuk
investigasi pasca-insiden:

- **Peristiwa apa yang dicatat** (mengacu NIST SP 800-53 **AU-2** & CIS Control 8): login
  sukses/gagal, logoff, pembuatan/perubahan/penghapusan akun, perubahan hak & keanggotaan
  grup istimewa, akses kredensial (vault), serta start/stop layanan.
- **Isi tiap catatan** (mengacu NIST SP 800-53 **AU-3**): *apa* jenis event, *kapan*
  (timestamp tersinkron), *di mana* (host/sumber), *sumber* (IP/akun), *hasil*
  (sukses/gagal), dan *identitas* pelaku. Pipeline Alloy mengekstrak field ini (mis.
  `event`, `user`, `ip`) dari tiap sumber.
- **Pengelolaan** (mengacu NIST SP 800-92 & CIS Control 8): kumpulkan terpusat (Loki),
  **sinkronkan waktu** antar-komponen, tetapkan **retensi** (lab: 7 hari; produksi minimal
  90 hari), dan **tinjau berkala**. Di Indonesia hal ini selaras dengan kewajiban audit
  keamanan SPBE (Peraturan BSSN tentang audit).

> Rujukan: NIST SP 800-92 (manajemen log), NIST SP 800-53 AU-2/AU-3/AU-6/AU-9/AU-12,
> CIS Control 8 (Audit Log Management).

**Bagaimana pipeline bekerja:** tiap komponen menulis log → **Alloy** memungut,
mem-*parse*, memberi label → **Loki** menyimpan → **Grafana** menampilkan & memberi alert.

![Pipeline log identitas: sumber → Alloy → Loki → Grafana → notifikasi](gambar/pipeline-log.png)

*Legenda: teal = aliran log; label hanya service/event (low-cardinality). Nomor dijelaskan pada Agenda Aktivitas di bawah.*

**Agenda Aktivitas (nomor pada diagram):**
1. Sumber log (Windows AD, Keycloak, OpenBao, Warpgate/sshd, Caddy) mengirim ke **Alloy**.
2. Alloy mem-*parse* & memberi label (hanya `service`/`event`) lalu mengirim ke **Loki**.
3. **Grafana** membaca Loki untuk dashboard & evaluasi alert.
4. Alert dikirim sebagai email ke **Mailpit** (kotak surat uji).


**Prinsip label (penting).** Jadikan label hanya dimensi *low-cardinality* (`service`,
`event`); nilai seperti `user`/`ip` disimpan sebagai *structured metadata*/field (dikueri
LogQL), **bukan** label — agar kardinalitas tidak meledak dan Loki tetap cepat.

**Sumber log kunci:** Windows AD (Event 4624/4625, 4768/4769 Kerberos, 4728/4732
grup), Keycloak (LOGIN, LOGIN_ERROR), OpenBao (audit device), Warpgate, sshd, Caddy.

## d. Praktik: Instalasi dan Konfigurasi

### 0. 🖥️ Deploy (sudah disiapkan)
Loki, Grafana, dan Alloy berjalan dari `docker compose up -d`; datasource Loki sudah
ter-*provision* di Grafana. Pipeline Keycloak sudah terisi sebagai contoh; sumber lain
Anda lengkapi.

### 1. 🐳 Lengkapi pipeline Alloy
Edit `deploy/monitoring/alloy/config.alloy`, tambahkan satu blok per sumber. Label hanya
`service`/`event`; `user`/`ip` sebagai *structured metadata*:
```alloy
stage.match {
  selector = "{service=\"openbao\"}"
  stage.json { expressions = { path = "request.path", bao_user = "auth.display_name", ip = "request.remote_address" } }
  stage.labels { values = { event = "path" } }
  stage.structured_metadata { values = { user = "bao_user", ip = "ip" } }
}
```
Lakukan serupa untuk Warpgate & sshd, lalu 🖥️ `docker compose restart alloy`.
Untuk **Windows Event dari DC**: 🪟 pasang Grafana Alloy di VM DC dan kirim ke Loki lab
(`loki.source.windowsevent` → `http://<IP-host-docker>:3100`).

### 2. 🌐 Dashboard "Identity Audit" (`https://grafana.iamlab.test`)
Buat panel di datasource Loki (sudah ada). Label `event` = tipe event Keycloak; `ip`/`user`
tersedia sebagai *structured metadata* sehingga langsung dipakai di `sum by (...)`.

**Empat panel ringkas (stat) di baris atas** — indikator identitas 24 jam:

| Panel | Arti | Kueri (LogQL) |
|---|---|---|
| **Jumlah User** | user unik yang terlihat di event | `count(sum by (user) (count_over_time({service="keycloak", event=~"LOGIN|LOGIN_ERROR"}[24h])))` |
| **User Aktif** | user unik dengan login **sukses** | `count(sum by (user) (count_over_time({service="keycloak", event="LOGIN"}[24h])))` |
| **Notifikasi Email Terkirim** | email akun terkirim (reset/verify/aksi) | `sum(count_over_time({service="keycloak"} \|~ "execute-actions-email\|SEND_" [24h]))` |
| **User Password Expired/Reset** | reset/ganti sandi (admin & self-service) | `sum(count_over_time({service="keycloak"} \|~ "reset-password\|UPDATE_PASSWORD\|RESET_PASSWORD" [24h]))` |

**Panel tren (timeseries/bargauge) di bawahnya:**
- Login sukses vs gagal: `sum(count_over_time({service="keycloak", event="LOGIN"}[5m]))` vs `event="LOGIN_ERROR"`.
- Top IP gagal: `topk(10, sum by (ip) (count_over_time({service="keycloak", event="LOGIN_ERROR"}[15m])))`.
- Aktivitas per layanan · Perubahan grup (Windows Event 4728/4732).

> Dua panel email & password memakai **line-filter** (`|~`) karena email akun dan reset sandi
> dipicu via Admin API Keycloak (tercatat sebagai operasi `ACTION`, bukan event `type=` biasa).
> Semua stat diberi `noValue: "0"` agar menampilkan angka, bukan "No data", saat jendela kosong.

Dashboard akhir yang diharapkan (berisi data nyata dari lalu lintas lab):

![Grafana — dashboard Identity Audit: jumlah user, user aktif, email terkirim, password reset, login sukses vs gagal, top IP gagal, aktivitas per layanan](gambar/grafana-dashboard.png)

> Catatan: event **LOGIN (sukses)** muncul karena stack menyetel
> `KC_SPI_EVENTS_LISTENER_JBOSS_LOGGING_SUCCESS_LEVEL=info` (default DEBUG tersaring).

### 3. 🌐 Alert & UBA dasar
Buat aturan alert dengan *contact point* Mailpit (kotak surat uji):

![Mailpit — kotak surat uji (menerima email alert & reset sandi)](gambar/mailpit.png)

| Aturan | Logika (disederhanakan) | Ambang |
|--------|-------------------------|--------|
| Brute force / spraying | `LOGIN_ERROR` per IP | > 10 gagal / 5 menit |
| Gagal → sukses | ≥5 gagal lalu sukses (user sama) | 1 kejadian |
| Perubahan grup istimewa | Event 4728/4732 ke Domain Admins/GG-Tier0 | tiap kejadian |
| Tiket Kerberos RC4 | 4769 enctype `0x17` dari akun non-mesin | tiap kejadian |

---

## Capstone — Deteksi & Respons

### 1. 🖥️ Bangkitkan lalu lintas (Locust)
Jalankan profil `normal` (baseline), lalu profil anomali pilihan instruktur
(`spray`, `fail-then-success`, `off-hours`), digabung hasil simulasi Sesi 1:
```bash
docker compose --profile load up -d locust      # UI di http://localhost:8089
```

### 2. Deteksi & respons (kunci akun di SEMUA layanan)
Dari dashboard & alert, identifikasi akun/IP terindikasi, lalu:
```powershell
Disable-ADAccount -Identity <user>        # 🪟 di DC
```
- 🌐 Keycloak: verifikasi user ter-disable (sync) + *Sessions → Logout all*.
- 🐳 OpenBao: `bao token revoke` token terkait.
- 🌐 Warpgate: hapus akses/role user.

### 3. Laporan insiden
Tulis ringkas: *timeline*, bukti (query LogQL), tindakan; tinjau checklist *hardening*.

**Hasil yang diharapkan:** akun kompromi terkunci di semua layanan; laporan memuat bukti query.
