# build-bag/ — Paket mandiri untuk panitia

Paket build bersifat **mandiri (self-contained)**: berisi **seluruh repo lab** (skrip + modul
sesi-0..4) **ditambah** aset berat (installer Windows, `iam-images.tar`, VM Ubuntu siap-pakai).
Peserta **tidak perlu `git clone` maupun internet** — cukup salin folder `Pelatihan_IAM` dari
paket lalu jalankan `build-lab.ps1`.

## Membuat paket (di PC penyiap, ada internet + Docker Desktop + VirtualBox)

```powershell
# dari root repo, PowerShell
.\build-lab.ps1                              # bangun lab sekali (VM ter-provision di .lab\vms)
.\build-bag\make-build-bag.ps1 -BakeVMs      # rakit ke ..\..\IAMLAB-BuildBag (di luar repo)
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
4. Menyalin repo lab ke `<Out>\Pelatihan_IAM` (tanpa `.git`/`.lab` dan tanpa cruft v1
   `distribusi\iso`, `distribusi\ova`), menambahkan aset ke `Pelatihan_IAM\distribusi\`
   (hardlink bila satu volume, salin bila beda volume), lalu menulis `INSTALL.txt` dan
   `SHA256SUMS.txt`.

Hasil akhir:

```
IAMLAB-BuildBag/
├─ INSTALL.txt                         # petunjuk singkat untuk panitia
├─ SHA256SUMS.txt                      # checksum aset berat (path relatif)
└─ Pelatihan_IAM/                      # repo lab LENGKAP (siap jalan)
   ├─ build-lab.ps1                    # <- panitia menjalankan ini
   ├─ sesi-0-pengantar/ … sesi-4-…    # modul
   ├─ deploy/  lab/  attack-sim/  build-bag/
   └─ distribusi/
      ├─ installer/       VirtualBox-*-Win.exe, DockerDesktopInstaller.exe, wsl-update.msi, vc_redist.x64.exe
      ├─ offline-images/  iam-images.tar
      └─ vms/             iamlab-srv1.vdi, iamlab-client1.vdi
```

Ubuntu cloud image dan datastream CIS **tidak** disertakan: keduanya hanya dipakai saat VM
di-provision dari nol (butuh internet/apt). Dengan `distribusi\vms\`, VM diimpor langsung.

## Di PC peserta (panitia)

1. Salin folder `Pelatihan_IAM` dari paket ke PC peserta (mis. `C:\Lab\Pelatihan_IAM`).
2. PowerShell **Administrator**:
   ```powershell
   cd C:\Lab\Pelatihan_IAM
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\build-lab.ps1
   ```
3. Bila diminta **reboot** (pemasangan WSL2/Docker Desktop), reboot lalu jalankan `.\build-lab.ps1` lagi.
4. Verifikasi: `.\build-lab.ps1 -Phase Status` → kedua VM `running`, stack Docker `healthy`.

`build-lab.ps1` otomatis memakai installer di `distribusi\installer\` (tanpa unduh ulang),
memuat `iam-images.tar`, dan mengimpor VM dari `distribusi\vms\`.

> **client1 (desktop):** layar login (GDM) muncul **±3–5 menit** setelah VM nyala (render
> software karena VirtualBox berjalan di atas Hyper-V); pesan `vmwgfx ... unsupported hypervisor`
> di konsol VM **normal**. `srv1` berjalan *headless* (akses via SSH).

## Lingkungan terkontrol (minim bug)

- **Versi dibekukan:** image Docker dipin di `deploy/compose.yaml`; installer disertakan apa
  adanya — tidak ada "ambil versi terbaru" saat di kelas.
- **IP & nama statis:** jaringan Host-Only `10.10.10.0/24` (host `.5`, srv1 `.20`, client1 `.30`),
  nama host & MAC tetap — mengurangi variasi antar-PC.
- **Idempoten:** `build-lab.ps1` aman dijalankan ulang; `-Rebuild` membangun ulang VM yang rusak.
- **Terisolasi:** VM hanya terhubung ke jaringan Host-Only.
