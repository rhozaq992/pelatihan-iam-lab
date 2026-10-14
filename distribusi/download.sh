#!/usr/bin/env bash
# Siapkan iam-images.tar (semua image lab, termasuk Samba AD) dari PC ber-internet.
# Dijalankan di mesin dengan Docker. Untuk installer VirtualBox/Docker Desktop/VC++ dan
# Ubuntu cloud image, pakai build-lab.ps1 -Phase Download (mengisi .lab/cache) atau
# build-bag/make-build-bag.ps1.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p offline-images

echo "[1/2] Build & tarik semua image lab (profil lengkap)..."
( cd ../deploy
  docker compose --profile '*' pull --ignore-buildable
  docker compose --profile '*' build
  docker save $(docker compose --profile '*' config --images) \
    -o ../distribusi/offline-images/iam-images.tar )

echo "[2/2] Checksum..."
sha256sum offline-images/iam-images.tar > SHA256SUMS.txt
echo "Selesai. iam-images.tar siap dibagikan (lihat build-bag/)."
