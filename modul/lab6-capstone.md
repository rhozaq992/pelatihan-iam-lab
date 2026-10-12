# Lab 6 — Capstone Deteksi & Respons (55') · Indikator 4.2

**Tujuan:** deteksi anomali dari lalu lintas realistis + respons + hardening review.

## 1. Bangkitkan lalu lintas (Locust, `http://localhost:8089`)
Jalankan baseline lalu profil anomali (pilih salah satu via env `LAB_PROFILE`):
```bash
LAB_PROFILE=normal docker compose up -d locust       # baseline
# ganti profil:
docker compose run --rm -e LAB_PROFILE=spray locust -f /mnt/locust/locustfile.py --host https://app.iamlab.test --headless -u 20 -r 5 -t 2m
```
Profil: `normal | spray | fail-then-success | off-hours`. Gabungkan dengan hasil simulasi Lab 3.

## 2. Deteksi
Dari dashboard & alert (Lab 5): identifikasi akun/IP terindikasi (brute force, gagal→sukses,
perubahan grup istimewa, tiket RC4).

## 3. Respons (kunci akun kompromi di SEMUA layanan)
```powershell
Disable-ADAccount -Identity <user>          # AD
```
- Keycloak: verifikasi user ter-disable (sync) + *Sessions → Logout all*.
- OpenBao: `bao token revoke` token terkait.
- Warpgate: hapus akses/role user.

## 4. Laporan insiden
Tulis ringkas: timeline, bukti (query LogQL), tindakan. Templat di `solutions/`.

## 5. Hardening review
Jalankan checklist Bab 6 dokumen secara mandiri; catat gap.

## Hasil yang diharapkan
- Akun kompromi terkunci di semua layanan; laporan memuat bukti query; checklist terisi.
