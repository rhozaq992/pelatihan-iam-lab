# distribusi/ — Aset berat (dibagikan manual, TIDAK via Git)

Folder ini sengaja kosong di Git (hanya `.gitkeep`). Isi dengan file besar yang
dibagikan ke peserta lewat USB/share lokal **sebelum** kelas, agar `git clone` tetap ringan.

| Folder | Isi |
|--------|-----|
| `iso/` | WindowsServer2025_eval.iso (x86-64), ubuntu-24.04-live-server-amd64.iso |
| `ova/` | `ubuntu-client.ova` (klien Ubuntu realm-join, Sesi 1), `IAMLAB-DC.ova` (DC), `IAMLAB-DOCKER.ova` (host Docker, opsional) — dipakai `deploy-lab.sh --vms` |
| `offline-images/` | `iam-images.tar` — hasil `docker save` semua image (muat: `docker load -i iam-images.tar`) |
| `installer/` | VMware Workstation Pro (gratis), Google Authenticator/FreeOTP |

Unduh aset dengan `./download.sh` (lihat skrip) lalu salin ke folder yang sesuai.
Checksum: buat `SHA256SUMS.txt` agar peserta bisa verifikasi integritas.
