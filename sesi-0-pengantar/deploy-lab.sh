#!/usr/bin/env bash
# =============================================================================
# deploy-lab.sh — Deploy Lab IAM satu perintah.
# Jaringan antar-VM / host / Docker SUDAH dikonfigurasi panitia; peserta tak perlu atur.
# Skrip ini: cek perkakas CLI (Docker + hypervisor), pasang Docker bila belum ada,
# muat image offline, lalu 'docker compose up -d'. Aman diulang (idempoten).
#
# Pakai:
#   ./deploy-lab.sh                 # deploy penuh: cek deps → pasang Docker (bila perlu) → load image → up
#   ./deploy-lab.sh --compose-only  # HANYA load image + compose up (bila langkah deps bermasalah)
#   ./deploy-lab.sh --check         # hanya laporkan OS/arch/deps, tidak mengubah apa pun
#   ./deploy-lab.sh --no-samba      # tanpa DC Samba (Sesi 1 Bagian A)
#   ./deploy-lab.sh --vms           # (DI HOST FISIK) impor & start VM klien dari distribusi/ova
#   ./deploy-lab.sh --down          # hentikan & bersihkan stack
#   ./deploy-lab.sh --help
#
# Dua konteks eksekusi:
#   • HOST FISIK (punya VMware/VirtualBox) → './deploy-lab.sh --vms' untuk menyalakan VM
#     (klien Ubuntu, DC, dll). Jaringan VM sudah dikonfigurasi panitia.
#   • VM/host Docker → './deploy-lab.sh' untuk stack kontainer.
# =============================================================================
set -euo pipefail

# ---- lokasi repo (skrip ada di sesi-0-pengantar/) ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEPLOY="$ROOT/deploy"
IMG_TAR="$ROOT/distribusi/offline-images/iam-images.tar"
INSTALLER="$ROOT/distribusi/installer"
OVADIR="$ROOT/distribusi/ova"
SAMBA=1; MODE="full"

# ---- util tampilan ----
if [ -t 1 ]; then B="\033[1m"; G="\033[32m"; Y="\033[33m"; R="\033[31m"; N="\033[0m"; else B=""; G=""; Y=""; R=""; N=""; fi
step(){ printf "${B}==> %s${N}\n" "$*"; }
ok(){   printf "  ${G}✓${N} %s\n" "$*"; }
warn(){ printf "  ${Y}!${N} %s\n" "$*"; }
die(){  printf "  ${R}✗ %s${N}\n" "$*" >&2; exit 1; }

# ---- argumen ----
for a in "$@"; do case "$a" in
  --compose-only) MODE="compose";;
  --check)        MODE="check";;
  --down)         MODE="down";;
  --vms)          MODE="vms";;
  --no-samba)     SAMBA=0;;
  -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) die "opsi tak dikenal: $a (coba --help)";;
esac; done

# ---- deteksi OS & arsitektur ----
detect_os(){ case "$(uname -s)" in
  Linux)  echo linux;; Darwin) echo darwin;;
  MINGW*|MSYS*|CYGWIN*) echo windows;; *) echo unknown;; esac; }
detect_arch(){ case "$(uname -m)" in
  x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) echo "$(uname -m)";; esac; }
OS="$(detect_os)"; ARCH="$(detect_arch)"

# ---- cek CLI hypervisor (informasional — jaringan sudah diatur panitia) ----
check_hypervisor_cli(){
  step "1. CLI hypervisor (VMware/VirtualBox)"
  local found=0
  command -v vmrun      >/dev/null 2>&1 && { ok "vmrun (VMware) tersedia";      found=1; }
  command -v VBoxManage >/dev/null 2>&1 && { ok "VBoxManage (VirtualBox) tersedia"; found=1; }
  if [ "$found" = 0 ]; then
    warn "vmrun/VBoxManage tidak di PATH — tidak wajib untuk deploy Docker ini."
    warn "Ia menyertai instalasi VMware Workstation/VirtualBox (lihat $INSTALLER)."
  fi
}

# ---- Docker: cek, pasang bila belum ada ----
have_docker(){ command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }
install_docker(){
  step "2. Pasang Docker ($OS/$ARCH)"
  case "$OS" in
    linux)
      # offline dulu: paket .deb di distribusi/installer/docker/ ; jika tak ada & online → get.docker.com
      if ls "$INSTALLER"/docker/*.deb >/dev/null 2>&1; then
        ok "pakai paket offline di installer/docker/"
        sudo dpkg -i "$INSTALLER"/docker/*.deb || sudo apt-get -f install -y
      elif curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>/dev/null; then
        warn "paket offline tak ada → pasang via get.docker.com (butuh internet)"
        sudo sh /tmp/get-docker.sh
      else
        die "Docker tak ada, tak ada paket offline, dan tak ada internet. Salin .deb ke $INSTALLER/docker/"
      fi
      sudo systemctl enable --now docker 2>/dev/null || true
      sudo usermod -aG docker "$USER" 2>/dev/null || true
      warn "jika baru ditambah ke grup docker, logout/login (atau 'newgrp docker') lalu ulangi."
      ;;
    darwin|windows)
      die "Docker Desktop tak bisa dipasang via skrip. Pasang dari $INSTALLER lalu jalankan ulang."
      ;;
    *) die "OS tak dikenal: $(uname -s)";;
  esac
}
ensure_docker(){
  step "2. Docker Engine"
  if have_docker; then ok "Docker aktif: $(docker --version | cut -d, -f1)"; else
    warn "Docker belum aktif."; [ "$MODE" = check ] && return 0
    install_docker; have_docker && ok "Docker siap." || die "Docker masih belum aktif — cek instalasi."
  fi
  docker compose version >/dev/null 2>&1 && ok "Docker Compose v2 tersedia" \
    || die "Plugin 'docker compose' tak ada — pasang docker-compose-plugin."
}

# ---- muat image offline ----
load_images(){
  step "3. Muat image lab (offline)"
  [ -f "$IMG_TAR" ] || die "tar image tak ditemukan: $IMG_TAR (salin dari USB/share panitia)"
  # lewati bila sebagian besar image sudah ada
  if docker image inspect quay.io/keycloak/keycloak:26.1 >/dev/null 2>&1 \
     && docker image inspect iamlab-app-komentar >/dev/null 2>&1; then
    ok "image inti sudah ada — lewati load."
  else
    ok "docker load -i $(basename "$IMG_TAR") (±4 GB, mohon tunggu)…"
    docker load -i "$IMG_TAR" | tail -3
  fi
}

# ---- compose up ----
compose_up(){
  step "4. Jalankan stack (docker compose up -d)"
  [ -d "$DEPLOY" ] || die "folder deploy tak ada: $DEPLOY"
  cd "$DEPLOY"
  [ -f .env ] || { cp .env.example .env && ok "buat .env dari contoh (sesuaikan DC_IP/sandi bila perlu)"; }
  docker compose up -d
  if [ "$SAMBA" = 1 ]; then
    ok "start DC Samba (Sesi 1 Bagian A, profil 'direktori')"
    docker compose --profile direktori up -d samba-dc
  fi
  echo; docker compose ps
  echo; ok "Selesai. Endpoint: https://kc.iamlab.test · https://app.iamlab.test · https://grafana.iamlab.test"
  warn "OpenBao menyala 'sealed' (init/unseal di Sesi 3); Warpgate perlu setup sekali (Sesi 3) — normal."
}

compose_down(){ step "Hentikan stack"; cd "$DEPLOY"; docker compose --profile direktori --profile attack --profile load down; ok "stack dihentikan."; }

# ---- deploy VM klien dari OVA (DIJALANKAN DI HOST FISIK ber-hypervisor) ----
# Jaringan VM sudah dikonfigurasi panitia → cukup impor + nyalakan. Nama VM = nama file OVA.
deploy_vms(){
  step "Deploy VM dari OVA ($OVADIR) — arch host: $ARCH"
  shopt -s nullglob; local all=("$OVADIR"/*.ova); shopt -u nullglob
  if [ ${#all[@]} -eq 0 ]; then
    warn "tak ada *.ova di $OVADIR — salin OVA klien (mis. ubuntu-client-$ARCH.ova) dari USB/share lalu ulangi."
    return 0
  fi
  # pilih OVA yang cocok arch host: lewati ubuntu-client-<arch lain>.ova; impor sisanya apa adanya.
  local ovas=() f base other
  other=$([ "$ARCH" = amd64 ] && echo arm64 || echo amd64)
  for f in "${all[@]}"; do base="$(basename "$f")"
    case "$base" in *-"$other".ova) ok "lewati $base (bukan arch host)"; continue;; esac
    ovas+=("$f")
  done
  if command -v VBoxManage >/dev/null 2>&1; then
    for ova in "${ovas[@]}"; do
      local name; name="$(basename "$ova" .ova)"
      if VBoxManage showvminfo "$name" >/dev/null 2>&1; then ok "VM '$name' sudah terdaftar"; else
        ok "impor $name.ova (VirtualBox)"; VBoxManage import "$ova" --vsys 0 --vmname "$name"
      fi
      if VBoxManage list runningvms | grep -q "\"$name\""; then ok "VM '$name' sudah berjalan";
      else ok "start '$name' (headless)"; VBoxManage startvm "$name" --type headless; fi
    done
  elif command -v vmrun >/dev/null 2>&1; then
    command -v ovftool >/dev/null 2>&1 || die "VMware terpasang tapi 'ovftool' tak ada (perlu untuk impor OVA)."
    for ova in "${ovas[@]}"; do
      local name vmx; name="$(basename "$ova" .ova)"; vmx="$OVADIR/$name/$name.vmx"
      [ -f "$vmx" ] || { ok "impor $name.ova (ovftool)"; ovftool --allowAllExtraConfig --name="$name" "$ova" "$OVADIR/$name/"; vmx="$(ls "$OVADIR/$name"/*.vmx | head -1)"; }
      if vmrun list | grep -qF "$vmx"; then ok "VM '$name' sudah berjalan";
      else ok "start '$name'"; vmrun -T ws start "$vmx" nogui; fi
    done
  else
    die "VMware (vmrun) / VirtualBox (VBoxManage) tak ditemukan di PATH — pasang hypervisor dulu."
  fi
  ok "VM selesai. Jaringan sudah terkonfigurasi; lanjut deploy stack Docker DI DALAM VM Docker."
}

# ---- alur utama ----
printf "${B}Lab IAM — deploy  (OS=%s arch=%s mode=%s)${N}\n" "$OS" "$ARCH" "$MODE"
case "$MODE" in
  down)    compose_down;;
  vms)     deploy_vms;;
  check)   check_hypervisor_cli; ensure_docker; [ -f "$IMG_TAR" ] && ok "tar image ada ($(du -h "$IMG_TAR"|cut -f1))" || warn "tar image belum ada"; shopt -s nullglob; o=("$OVADIR"/*.ova); shopt -u nullglob; [ ${#o[@]} -gt 0 ] && ok "OVA ditemukan: ${#o[@]}" || warn "belum ada OVA di distribusi/ova"; step "Check selesai (tidak ada perubahan).";;
  compose) load_images; compose_up;;
  full)    check_hypervisor_cli; ensure_docker; load_images; compose_up;;
esac
