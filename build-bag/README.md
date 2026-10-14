# build-bag/ — Paket instalasi siap-serah untuk panitia

Tujuan folder ini: menghasilkan **satu folder** berisi segala yang dibutuhkan untuk membangun
Lab IAM di PC peserta **tanpa internet**, sehingga panitia tinggal menyalin dan menjalankan
satu skrip. Lingkungannya terkontrol (versi image & installer dibekukan) untuk meminimalkan bug.

## Membuat paket (di PC penyiap, ada internet + Docker Desktop)

```powershell
# dari root repo, PowerShell
.\build-bag\make-build-bag.ps1            # rakit ke .\IAMLAB-BuildBag
.\build-bag\make-build-bag.ps1 -Zip      # sekalian buat .zip
```

Skrip akan:
1. Membangun & menyimpan **`iam-images.tar`** (semua image Docker: Samba AD + layanan IAM).
2. Mengunduh **installer** VirtualBox, Docker Desktop, VC++ runtime, dan **Ubuntu 24.04 cloud
   image** ke cache (`build-lab.ps1 -Phase Download`).
3. Menyalin repo lab (tanpa `.git`/`.lab`) + semua aset ke `IAMLAB-BuildBag\Pelatihan_IAM\`,
   lalu menulis `INSTALL.txt` dan `SHA256SUMS.txt`.

Hasil akhir (contoh):

```
IAMLAB-BuildBag/
├─ INSTALL.txt                      # petunjuk singkat untuk panitia
├─ SHA256SUMS.txt                   # checksum aset berat
└─ Pelatihan_IAM/
   ├─ build-lab.ps1                 # <- panitia menjalankan ini
   ├─ sesi-0-pengantar/ … sesi-4-…  # modul
   ├─ deploy/  lab/  attack-sim/
   └─ distribusi/
      ├─ offline-images/iam-images.tar
      └─ installer/  (VirtualBox, Docker Desktop, VC++, ubuntu-…-cloudimg-amd64.ova)
```

## Di PC peserta (panitia)

1. Salin folder `Pelatihan_IAM` ke PC peserta (mis. `C:\Lab\Pelatihan_IAM`).
2. PowerShell **Administrator**:
   ```powershell
   cd C:\Lab\Pelatihan_IAM
   Set-ExecutionPolicy -Scope Process Bypass -Force
   .\build-lab.ps1
   ```
3. Bila diminta **reboot** (pemasangan WSL2/Docker Desktop), reboot lalu jalankan `.\build-lab.ps1` lagi.
4. Verifikasi: `.\build-lab.ps1 -Phase Status` → kedua VM `running`, stack Docker `healthy`.

## Lingkungan terkontrol (minim bug)

- **Versi dibekukan:** image Docker dipin di `deploy/compose.yaml`; installer & cloud image
  disertakan apa adanya — tidak ada "ambil versi terbaru" saat di kelas.
- **IP & nama statis:** jaringan Host-Only `10.10.10.0/24` (host `.5`, srv1 `.20`, client1 `.30`),
  nama host & MAC tetap — mengurangi variasi antar-PC.
- **Idempoten:** `build-lab.ps1` aman dijalankan ulang; `-Rebuild` membangun ulang VM yang rusak.
- **Terisolasi:** NAT VM dilepas setelah provisioning; lab berjalan tanpa internet.

## Catatan kelas sepenuhnya offline
Build pertama tiap VM mengunduh paket Ubuntu (sssd/adcli, auditd, OpenSCAP+SSG, Alloy,
ubuntu-desktop-minimal). Untuk kelas tanpa internet sama sekali, siapkan **cermin APT lokal**
atau cache paket, lalu arahkan VM ke sana. Image Docker & installer sudah offline sepenuhnya.
