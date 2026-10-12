# Formulir Serah-Terima Akses Istimewa (Lab)

Isi, kirim via email ke pemberi persetujuan, dan **minta dikembalikan dengan status
disetujui** sebelum akses dibuka. Semua data sintetis (lab).

| Field | Isi |
|-------|-----|
| No. tiket / tanggal | |
| Pemohon (nama, unit) | |
| Sistem / akun target | srv-app01 / srv-db01 / … |
| Justifikasi kebutuhan | |
| Durasi akses diminta | mis. 2 jam |
| Metode akses | Bastion Warpgate (SSO + MFA), sesi terekam |
| Kredensial | diambil dari OpenBao (teraudit) — TIDAK via chat |
| **Disetujui oleh** (dual control utk Tier 0) | nama 1: ____  nama 2: ____ |
| **Status dikembalikan** | ☐ Disetujui  ☐ Ditolak — tanggal/jam: ____ |
| Rotasi sandi setelah pakai | ☐ ya — waktu: ____ |
| Ditinjau oleh | |

**Alur email:** Pemohon mengirim formulir ini → pemberi persetujuan membalas email dengan
kolom *Disetujui* terisi (formulir kembali) → barulah akses dibuka di Warpgate/OpenBao →
setelah selesai, kirim bukti rotasi. Di lab, semua email tertangkap di **Mailpit**
(`https://mail.iamlab.test`).
