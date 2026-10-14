# build-bag/ — Paket aset build untuk panitia

Paket build berisi **hanya aset berat** yang dibutuhkan untuk membangun lab tanpa unduhan besar:
installer Windows, image Docker, dan VM Ubuntu siap-pakai. Modul, skrip, dan konfigurasi **tidak**
disertakan — peserta tetap mengambilnya dengan `git clone`, lalu menyalin folder `distribusi\`
dari paket ke repo hasil clone. Strukturnya sama persis dengan `distribusi\` di repo.

## Membuat paket (di PC penyiap, ada internet + Docker Desktop + VirtualBox)

```powershell
# dari root repo, PowerShell
.\build-lab.ps1                              # bangun lab sekali (VM ter-provision di .lab\vms)
.\build-bag\make-build-bag.ps1 -BakeVMs      # rakit ke ..\IAMLAB-BuildBag (di luar repo)
.\build-bag\make-build-bag.ps1 -Zip          # sekalian buat .zip
```

Skrip akan:
1. Mengunduh **installer** VirtualBox, Docker Desktop, WSL2 MSI, dan VC++ runtime ke cache
   (`build-lab.ps1 -Phase Download -BundleAll`).
2. Membangun & menyimpan **`iam-images.tar`** (semua image Docker: Samba AD + layanan IAM).
   Tar yang sudah ada diperiksa terhadap `docker compose config --images`; bila ada image yang
   kurang (tar usang), tar dibangun ulang.
3. (`-BakeVMs`) Mengekspor VDI `iamlab-srv1`/`iamlab-client1` yang sudah di-provision ke
   `distribusi\vms\`.
4. Menulis aset ke paket (hardlink bila satu volume, salin bila beda volume), lalu
   `INSTALL.txt` dan `SHA256SUMS.txt`.

Hasil akhir:

```
IAMLAB-BuildBag/
├─ INSTALL.txt                         # petunjuk singkat untuk panitia
├─ SHA256SUMS.txt                      # checksum semua aset (path relatif)
└─ distribusi/
   ├─ installer/       VirtualBox-*-Win.exe, DockerDesktopInstaller.exe, wsl-update.msi, vc_redist.x64.exe
   ├─ offline-images/  iam-images.tar
   └─ vms/             iamlab-srv1.vdi, iamlab-client1.vdi
```

Ubuntu cloud image dan datastream CIS **tidak** disertakan: keduanya hanya dipakai saat VM
di-provision dari nol, yang memang butuh internet (apt). Dengan `distribusi\vms\`, keduanya
tidak diperlukan.

## Di PC peserta (panitia)

1. `git clone https://github.com/rhozaq992/pelatihan-iam-lab.git C:\Lab\Pelatihan_IAM`
2. Salin `distribusi\` dari paket ke repo hasil clone:
   `robocopy <paket>\distribusi C:\Lab\Pelatihan_IAM\distribusi /E`
3. PowerShell **Administrator**:
   ```powershell
   cd C:\Lab\Pelatihan_IAM
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\build-lab.ps1
   ```
4. Bila diminta **reboot** (pemasangan WSL2/Docker Desktop), reboot lalu jalankan `.\build-lab.ps1` lagi.
5. Verifikasi: `.\build-lab.ps1 -Phase Status` → kedua VM `running`, stack Docker `healthy`.

`build-lab.ps1` otomatis memakai installer di `distribusi\installer\` (tanpa unduh ulang),
memuat `iam-images.tar`, dan mengimpor VM dari `distribusi\vms\`.

## Lingkungan terkontrol (minim bug)

- **Versi dibekukan:** image Docker dipin di `deploy/compose.yaml`; installer disertakan apa
  adanya — tidak ada "ambil versi terbaru" saat di kelas.
- **IP & nama statis:** jaringan Host-Only `10.10.10.0/24` (host `.5`, srv1 `.20`, client1 `.30`),
  nama host & MAC tetap — mengurangi variasi antar-PC.
- **Idempoten:** `build-lab.ps1` aman dijalankan ulang; `-Rebuild` membangun ulang VM yang rusak.
- **Terisolasi:** VM hanya terhubung ke jaringan Host-Only.
