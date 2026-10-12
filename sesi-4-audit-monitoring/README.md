# Sesi 4 — Audit & Monitoring Aktivitas Identitas

Indikator 4.1 (audit autentikasi/otorisasi) dan 4.2 (deteksi anomali). Membangun
jejak audit identitas _end-to-end_ dan dashboard pemantauan sederhana.

## a. Tujuan Sesi

Peserta mampu:
- Mengumpulkan log identitas dari seluruh komponen ke satu tempat (Loki).
- Membuat **dashboard** audit identitas dan **aturan alert** di Grafana.
- Menerapkan **UBA dasar** untuk mendeteksi perilaku tak lazim / akun kompromi.
- Melakukan respons insiden lintas layanan (capstone).

## b. Output yang Diharapkan

- ≥ 5 sumber log tampil di Loki; dashboard menampilkan login sukses vs gagal, top IP
  gagal, aktivitas per klien, dan perubahan grup istimewa.
- Minimal 4 aturan alert aktif; alert memicu email uji di Mailpit.
- Pada capstone: akun terindikasi kompromi dikunci di semua layanan, disertai
  laporan insiden berisi bukti query.

## c. Teori dan Struktur Sistem

- **Jejak audit identitas** menjawab "siapa mengakses apa, kapan, dari mana,
  berhasil/gagal". **UBA (User Behavior Analytics) dasar** mencari penyimpangan dari
  kebiasaan: ledakan kegagalan login (brute force), gagal lalu tiba-tiba berhasil,
  login di jam/IP tak lazim, atau perubahan keanggotaan grup istimewa. _Analogi:_
  satpam yang hafal pola normal dan curiga saat ada yang mencoba 100 pintu dalam semenit.
- **Pipeline:** tiap komponen menulis log → **Alloy** memungut, mem-_parse_, dan
  memberi label → **Loki** menyimpan → **Grafana** menampilkan & memberi alert.
- **Prinsip label (penting):** jadikan label hanya dimensi _low-cardinality_
  (`service`, `event`); nilai seperti `user`/`ip` disimpan sebagai _field_ (dikueri
  dengan LogQL), bukan label — agar kardinalitas tidak meledak.

**Sumber log kunci:** Windows AD (Event 4624/4625, 4768/4769 Kerberos, 4728/4732 grup),
Keycloak (LOGIN, LOGIN_ERROR, dsb.), OpenBao (audit device), Warpgate, sshd, Caddy.

## d. Praktik: Instalasi dan Konfigurasi

### 1. Lengkapi pipeline Alloy
Untuk tiap sumber, tambahkan tahap _parse_ + label (hanya `service`, `event`):
```alloy
stage.match {
  selector = "{service=\"openbao\"}"
  stage.json { expressions = { path = "request.path", bao_user = "auth.display_name", ip = "request.remote_address" } }
  stage.labels { values = { event = "path" } }
  stage.structured_metadata { values = { user = "bao_user", ip = "ip" } }
}
```
Lakukan serupa untuk Warpgate dan sshd. Untuk **Windows Event dari DC**, pasang Grafana
Alloy di VM DC dan kirim ke Loki lab:
```alloy
loki.source.windowsevent "sec" { eventlog_name = "Security" forward_to = [loki.write.lab.receiver] }
loki.write "lab" { endpoint { url = "http://<IP-host-docker>:3100/loki/api/v1/push" } }
```

### 2. Dashboard "Identity Audit" (`https://grafana.iamlab.test`)
Buat ≥ 4 panel (datasource Loki sudah terprovision). Label `event` berisi tipe event
Keycloak; `ip`/`user` tersedia sebagai _structured metadata_:
- Login sukses vs gagal: `sum(count_over_time({service="keycloak", event="LOGIN"}[5m]))` vs `event="LOGIN_ERROR"`.
- Top IP gagal: `topk(10, sum by (ip) (count_over_time({service="keycloak", event="LOGIN_ERROR"}[15m])))`.
- Aktivitas per klien · Perubahan grup istimewa (Windows Event 4728/4732).

### 3. Alert & UBA dasar
Buat aturan alert dengan _contact point_ Mailpit:
| Aturan | Logika (disederhanakan) | Ambang |
|--------|-------------------------|--------|
| Brute force / spraying | `LOGIN_ERROR` per IP | > 10 gagal / 5 menit |
| Gagal → sukses | ≥5 gagal lalu sukses (user sama) | 1 kejadian |
| Perubahan grup istimewa | Event 4728/4732 ke Domain Admins/GG-Tier0 | tiap kejadian |
| Tiket Kerberos RC4 | 4769 enctype `0x17` dari akun non-mesin | tiap kejadian |

---

## Capstone — Deteksi & Respons

### 1. Bangkitkan lalu lintas (Locust)
Jalankan profil `normal` sebagai baseline, lalu profil anomali yang dipilih instruktur
(`spray`, `fail-then-success`, `off-hours`), digabung dengan hasil simulasi Sesi 1.

### 2. Deteksi & respons
Dari dashboard & alert: identifikasi akun/IP terindikasi. Lalu kunci di **semua** layanan:
```powershell
Disable-ADAccount -Identity <user>        # AD
```
- Keycloak: verifikasi user ter-disable (sync) + *Sessions → Logout all*.
- OpenBao: `bao token revoke` token terkait.
- Warpgate: hapus akses/role user.

### 3. Laporan insiden
Tulis ringkas: _timeline_, bukti (query LogQL), tindakan. Tinjau juga checklist
_hardening_ secara mandiri.

**Hasil yang diharapkan:** akun kompromi terkunci di semua layanan; laporan memuat
bukti query.
