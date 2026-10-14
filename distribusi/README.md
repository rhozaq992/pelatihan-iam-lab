# distribusi/ — Aset berat (dibagikan manual, TIDAK via Git)

Folder ini sengaja kosong di Git (hanya `.gitkeep`). Isi dengan file besar yang dibagikan ke
panitia/peserta lewat USB/share lokal **sebelum** kelas, agar `git clone` tetap ringan dan lab
dapat dibangun **offline**. Semua ini dipakai otomatis oleh [`build-lab.ps1`](../build-lab.ps1)
bila ada; bila tidak ada, `build-lab.ps1` mengunduhnya saat build (butuh internet sekali).

| Folder | Isi |
|--------|-----|
| `offline-images/` | `iam-images.tar` — hasil `docker save` **semua** image (layanan IAM + Samba AD). Dimuat otomatis oleh `build-lab.ps1`. |
| `installer/` | Installer **VirtualBox** (Win.exe), **Docker Desktop**, **WSL2** (`wsl-update.msi`), **VC++ runtime**. Dipakai otomatis oleh fase Install (tanpa unduh ulang). |
| `vms/` | `iamlab-srv1.vdi`, `iamlab-client1.vdi` — VM Ubuntu siap-pakai; diimpor tanpa provisioning (Ubuntu cloud image tak diperlukan). |

> Untuk kelas **sepenuhnya offline**, salin juga paket yang diunduh VM saat provisioning
> (sssd/adcli, auditd, OpenSCAP + SCAP Security Guide, Grafana Alloy, ubuntu-desktop-minimal)
> sebagai cache APT, atau sediakan cermin APT lokal. Tanpa itu, build pertama perlu internet
> sekali untuk kedua VM; sesudahnya lab berjalan terisolasi Host-Only.

## Menyiapkan paket build (build bag)
Lihat **[`../build-bag/README.md`](../build-bag/README.md)**: skrip `make-build-bag.ps1`
mengumpulkan **hanya** isi folder ini (installer, `iam-images.tar`, VDI) ke satu paket dengan
struktur yang sama. Peserta `git clone` repo lalu menyalin `distribusi\` dari paket ke sini.

## Membuat `iam-images.tar` (dari PC ber-internet)
```powershell
cd ..\deploy
docker compose --profile "*" pull --ignore-buildable
docker compose --profile "*" build          # termasuk image samba-dc
docker save (docker compose --profile "*" config --images) -o ..\distribusi\offline-images\iam-images.tar
```

Checksum dicatat di `SHA256SUMS.txt`; verifikasi dengan `sha256sum -c SHA256SUMS.txt`.
> Seluruh lab **amd64** (Ubuntu cloud image + image Docker amd64). Tidak ada komponen Windows guest.
