#!/usr/bin/env bash
# Unduh/siapkan aset berat lab ke folder distribusi (dijalankan di mesin lokal).
# ISO x86-64 untuk peserta (VirtualBox/VMware Workstation di PC Windows x86).
set -euo pipefail
cd "$(dirname "$0")"

echo "[1/3] Ubuntu Server 24.04 (x86-64) ISO..."
curl -L -o iso/ubuntu-24.04-live-server-amd64.iso \
  https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso || echo "  (lewati bila gagal)"

echo "[2/3] Windows Server 2025 Evaluation (x86-64)"
echo "  Unduh manual (butuh form) dari Microsoft Evaluation Center lalu simpan ke iso/:"
echo "  https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025"

echo "[3/3] Image Docker offline (dari host yang sudah pull/build):"
echo "  jalankan: cd ../deploy && docker compose --profile '*' pull --ignore-buildable \\"
echo "    && docker compose --profile '*' build \\"
echo "    && docker save \$(docker compose --profile '*' config --images) -o ../distribusi/offline-images/iam-images.tar"
echo "  (--profile '*' WAJIB: tanpa itu image samba-dc, locust, attacker, srv-db01 tidak ikut.)"
echo "Selesai. Buat checksum: sha256sum offline-images/* ova/* > SHA256SUMS.txt"
