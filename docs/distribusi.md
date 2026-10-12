# Folder Distribusi Lab IAM (dibagikan manual ke peserta)

File berat disimpan di sini agar waktu persiapan lab singkat (tidak unduh saat kelas).
Bagikan via flashdisk/USB SSD atau share drive lokal sebelum sesi.

## iso/
- WindowsServer2025_eval.iso        (unduh dari Microsoft Evaluation Center, 180 hari)
- Windows11_eval.iso                (opsional, untuk VM klien)
- ubuntu-24.04-live-server-amd64.iso

## ova/  (disarankan — paling cepat)
- IAMLAB-DC.ova          : Windows Server 2025 sudah promote DC iamlab.test (OVF/OVA, impor di VMware: File > Open)
- IAMLAB-DOCKER.ova      : Ubuntu + Docker + semua image ter-load (lihat offline-images)
- IAMLAB-WIN11.ova       : Windows 11 + RSAT/GPMC (opsional)

## offline-images/
- iam-images.tar         : hasil `docker save` seluruh image (keycloak, openbao, warpgate,
                           grafana, loki, alloy, caddy, postgres, mailpit, locust, impacket)
                           muat offline: `docker load -i iam-images.tar`

## installer/
- VMware Workstation Pro (gratis, dari Broadcom)
- Google Authenticator (tautan Play/App Store) / FreeOTP (APK) untuk peserta tanpa akses store

## Checksum
- SHA256SUMS.txt         : verifikasi integritas semua file sebelum dipakai
