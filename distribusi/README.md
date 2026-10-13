# distribusi/ — Aset berat (dibagikan manual, TIDAK via Git)

Folder ini sengaja kosong di Git (hanya `.gitkeep`). Isi dengan file besar yang
dibagikan ke peserta lewat USB/share lokal **sebelum** kelas, agar `git clone` tetap ringan.

| Folder | Isi |
|--------|-----|
| `iso/` | WindowsServer2025_eval.iso (x86-64), ubuntu-24.04-live-server-amd64.iso |
| `ova/` | `ubuntu-client-amd64.ova` (klien Linux, PC peserta x86-64) & `ubuntu-client-arm64.ova` (instruktur Apple Silicon), `IAMLAB-DC.ova` (DC, opsional) — dipakai `deploy-lab.sh --vms` |
| `offline-images/` | `iam-images.tar` — hasil `docker save` semua image (muat: `docker load -i iam-images.tar`) |
| `installer/` | VMware Workstation Pro (gratis), Google Authenticator/FreeOTP, `docker/*.deb` (opsional, Ubuntu offline) |
| `iso/` + `iso/windows/` | ISO Ubuntu & Windows Server 2025 (x86-64); `autounattend.xml` + `Install-DC.ps1` hasil `prep-windows-server.sh` |

## Skrip penyiapan
- `./build-client-ova.sh --arch amd64` dan `--arch arm64` — bangun OVA klien Ubuntu dari
  Ubuntu cloud image resmi (realmd/sssd **dibaking** agar `realm join` jalan offline).
  `deploy-lab.sh --vms` otomatis memilih OVA sesuai arch host.
- `./prep-windows-server.sh` — verifikasi ISO WS2025 (x86-64, unduh manual dari Microsoft) +
  hasilkan `autounattend.xml` & `Install-DC.ps1` (promosi DC `iamlab.test` tanpa interaksi).
- `./download.sh` — unduh ISO Ubuntu + petunjuk ISO Windows.

Checksum ditambahkan ke `SHA256SUMS.txt` otomatis oleh skrip build; peserta verifikasi integritas.
> Hanya **amd64** untuk Windows (tak ada Windows Server arm). Klien Ubuntu disediakan **amd64 & arm64**.
