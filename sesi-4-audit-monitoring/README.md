# Sesi 4 — Audit & Monitoring Aktivitas Identitas

> Indikator 4.1 (audit autentikasi/otorisasi) & 4.2 (deteksi anomali).


**Tujuan:** jejak audit end-to-end + dashboard pemantauan sederhana.

## 1. Lengkapi pipeline Alloy
Edit `lab/monitoring/alloy/config.alloy` — tambah `stage.match` untuk sumber lain
(bagian **TODO PESERTA**). Prinsip label: **hanya low-cardinality** (`service`, `event`);
`user`/`ip` sebagai field (`| json` di LogQL), jangan dijadikan label.
```alloy
stage.match {
  selector = "{service=\"openbao\"}"
  stage.json { expressions = { path = "request.path", bao_user = "auth.display_name", ip = "request.remote_address" } }
  stage.labels { values = { event = "path" } }
  stage.structured_metadata { values = { user = "bao_user", ip = "ip" } }
}
```
Reload: `docker compose restart alloy`.

## 2. Windows Event dari DC
Pasang **Grafana Alloy** di VM DC → kirim log Security ke Loki lab:
```alloy
loki.source.windowsevent "sec" { eventlog_name = "Security" forward_to = [loki.write.lab.receiver] }
loki.write "lab" { endpoint { url = "http://<IP-host-docker>:3100/loki/api/v1/push" } }
```

## 3. Dashboard "Identity Audit" di Grafana (`https://grafana.iamlab.test`)
Buat ≥ 4 panel (datasource Loki sudah terprovision). Label `event` berisi tipe event
Keycloak (LOGIN, LOGIN_ERROR, dst.); Alloy sudah mengekstrak `ip`/`user` sebagai
**structured metadata**, jadi bisa langsung dipakai di `sum by (...)`:
- Login sukses vs gagal: `sum(count_over_time({service="keycloak", event="LOGIN"}[5m]))` vs `event="LOGIN_ERROR"`.
- Top IP gagal: `topk(10, sum by (ip) (count_over_time({service="keycloak", event="LOGIN_ERROR"}[15m])))`.
- Aktivitas per client · Perubahan grup (dari Windows Event 4728/4732).

> Catatan: event **LOGIN (sukses)** muncul karena stack menyetel
> `KC_SPI_EVENTS_LISTENER_JBOSS_LOGGING_SUCCESS_LEVEL=info` (default DEBUG tersaring).

## 4. Alert rules + contact point Mailpit
- Rule brute force: LOGIN_ERROR per IP > 10 / 5m.
- Contact point: SMTP `mailpit:1025` → uji kirim.

## 5. Telusur satu login end-to-end
Login App-Komentar → lihat jejaknya di Keycloak (LOGIN) lalu LDAP bind di AD (Windows Event 4768/4769).

## Hasil yang diharapkan
- ≥ 5 sumber log tampil di Loki; dashboard menampilkan data; alert memicu email uji di Mailpit.

---

## Capstone — Deteksi & Respons


**Tujuan:** deteksi anomali dari lalu lintas realistis + respons + hardening review.

### 1. Bangkitkan lalu lintas (Locust, `http://localhost:8089`)
Jalankan baseline lalu profil anomali (pilih salah satu via env `LAB_PROFILE`):
```bash
LAB_PROFILE=normal docker compose up -d locust       # baseline
# ganti profil:
docker compose run --rm -e LAB_PROFILE=spray locust -f /mnt/locust/locustfile.py --host https://app.iamlab.test --headless -u 20 -r 5 -t 2m
```
Profil: `normal | spray | fail-then-success | off-hours`. Gabungkan dengan hasil simulasi Lab 3.

### 2. Deteksi
Dari dashboard & alert (Lab 5): identifikasi akun/IP terindikasi (brute force, gagal→sukses,
perubahan grup istimewa, tiket RC4).

### 3. Respons (kunci akun kompromi di SEMUA layanan)
```powershell
Disable-ADAccount -Identity <user>          # AD
```
- Keycloak: verifikasi user ter-disable (sync) + *Sessions → Logout all*.
- OpenBao: `bao token revoke` token terkait.
- Warpgate: hapus akses/role user.

### 4. Laporan insiden
Tulis ringkas: timeline, bukti (query LogQL), tindakan. Templat di `solutions/`.

### 5. Hardening review
Jalankan checklist Bab 6 dokumen secara mandiri; catat gap.

### Hasil yang diharapkan
- Akun kompromi terkunci di semua layanan; laporan memuat bukti query; checklist terisi.
