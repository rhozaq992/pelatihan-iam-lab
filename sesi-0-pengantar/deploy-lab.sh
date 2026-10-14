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
#   ./deploy-lab.sh --network-only  # hanya samakan .env + /etc/hosts (jaringan seragam)
#   ./deploy-lab.sh --down          # hentikan & bersihkan stack
#
# Jaringan OTOMATIS: setiap deploy menyelaraskan deploy/.env (LAB_DOMAIN/DC_IP/DC_HOST) dan
# /etc/hosts (*.iamlab.test → 127.0.0.1, dc1 → DC_IP) dari rencana kanonik di skrip ini —
# peserta TIDAK perlu menyetel apa pun. Panitia cukup ubah blok "RENCANA JARINGAN KANONIK".
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

# ---- RENCANA JARINGAN KANONIK (ubah DI SATU TEMPAT ini bila panitia pakai subnet lain) ----
# Nilai ini dipakai untuk mengisi .env dan /etc/hosts otomatis → peserta tak mengatur apa pun.
NET_DOMAIN="iamlab.test"
NET_DC_IP="10.10.10.10"          # IP VM Windows Server (DC) di VMnet lab
NET_DC_HOST="dc1.iamlab.test"
NET_DOCKER_IP="10.10.10.5"       # IP tetap host Docker di VMnet lab (dilihat dari VM klien)
NET_HOSTONLY_IP="$NET_DOCKER_IP" # IP adapter Host-Only di HOST (VirtualBox) = IP host Docker: OVA klien
                                 # memetakan *.iamlab.test ke .5, jadi host yang menjalankan Docker HARUS .5
NET_SUBS="kc app saml grafana bao mail pam"   # subdomain layanan (dilayani Caddy)

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
  --network-only) MODE="network";;
  --no-samba)     SAMBA=0;;
  -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) die "opsi tak dikenal: $a (coba --help)";;
esac; done

# ---- deteksi OS & arsitektur ----
detect_os(){ case "$(uname -s)" in
  Linux)  echo linux;; Darwin) echo darwin;;
  MINGW*|MSYS*|CYGWIN*) echo windows;; *) echo unknown;; esac; }
detect_arch(){ case "$(uname -m)" in
  x86_64|amd64) echo amd64;; aarch64|arm64) echo arm64;; *) echo "$(uname -m)";; esac; }
OS="$(detect_os)"; ARCH="$(detect_arch)"

# ---- Windows: tambahkan path default VirtualBox/VMware ke PATH bila belum terdeteksi ----
# Di Git Bash, VBoxManage.exe/ovftool jarang ada di PATH walau terpasang. Tambah lokasi baku.
if [ "$OS" = windows ]; then
  for p in "/c/Program Files/Oracle/VirtualBox" "/c/Program Files/VMware/VMware Workstation" \
           "/c/Program Files (x86)/VMware/VMware Workstation" "/c/Program Files/VMware/VMware Workstation/OVFTool"; do
    [ -d "$p" ] && case ":$PATH:" in *":$p:"*) :;; *) PATH="$PATH:$p";; esac
  done
  export PATH
  # Skrip ini memanggil exe Windows (docker.exe, VBoxManage.exe) dgn path host '/c/...'.
  # Konversi path otomatis Git Bash HARUS aktif agar '/c/Users/..' → 'C:\Users\..'.
  # (MSYS_NO_PATHCONV hanya untuk 'docker exec' berpath container — lihat README Sesi 3.)
  unset MSYS_NO_PATHCONV
fi

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

# ---- jaringan seragam: .env kanonik + /etc/hosts otomatis (peserta tak mengatur) ----
hosts_path(){ case "$OS" in windows) echo "/c/Windows/System32/drivers/etc/hosts";; *) echo "/etc/hosts";; esac; }
write_hosts(){ # $1=file, butuh hak admin; idempoten via penanda
  local f="$1" s="# >>> lab-iam (otomatis, jangan sunting) >>>" e="# <<< lab-iam <<<"
  local line1="127.0.0.1"; for d in $NET_SUBS; do line1="$line1 $d.$NET_DOMAIN"; done
  local block="$s"$'\n'"$line1"$'\n'"$NET_DC_IP $NET_DC_HOST"$'\n'"$e"
  local tmp rc=0; tmp="$(mktemp)"
  # buang blok lama (jika ada) lalu tambah yang baru
  awk -v s="$s" -v e="$e" 'f&&$0==e{f=0;next} $0==s{f=1} !f' "$f" 2>/dev/null > "$tmp" || true
  printf '%s\n' "$block" >> "$tmp"
  if [ -w "$f" ]; then cat "$tmp" > "$f" || rc=$?
  elif sudo -n true 2>/dev/null; then sudo cp "$tmp" "$f" || rc=$?   # sudo tanpa prompt bila tersedia
  else sudo cp "$tmp" "$f" </dev/tty || rc=$?; fi                    # jika tidak, minta password sekali (butuh TTY)
  rm -f "$tmp"; return $rc
}
setup_network(){
  step "Konfigurasi jaringan seragam (otomatis — tanpa setel manual)"
  [ -d "$DEPLOY" ] || die "folder deploy tak ada"
  ( cd "$DEPLOY"; [ -f .env ] || cp .env.example .env
    for kv in "LAB_DOMAIN=$NET_DOMAIN" "DC_IP=$NET_DC_IP" "DC_HOST=$NET_DC_HOST"; do
      k="${kv%%=*}"
      if grep -q "^$k=" .env; then
        if [ "$OS" = darwin ]; then sed -i '' "s|^$k=.*|$kv|" .env; else sed -i "s|^$k=.*|$kv|" .env; fi
      else printf '%s\n' "$kv" >> .env; fi
    done )
  ok ".env diselaraskan (LAB_DOMAIN=$NET_DOMAIN, DC_IP=$NET_DC_IP, DC_HOST=$NET_DC_HOST)"
  local hf; hf="$(hosts_path)"
  if write_hosts "$hf" 2>/dev/null; then
    ok "hosts diset: *.$NET_DOMAIN → 127.0.0.1 (Caddy lokal), $NET_DC_HOST → $NET_DC_IP"
  else
    warn "tak bisa menulis $hf (perlu admin). Jalankan sekali dengan hak admin, atau tambah manual:"
    warn "  127.0.0.1 $(for d in $NET_SUBS; do printf '%s.%s ' "$d" "$NET_DOMAIN"; done)"
    warn "  $NET_DC_IP $NET_DC_HOST"
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

compose_down(){ step "Hentikan stack"; cd "$DEPLOY"; docker compose --profile direktori --profile attack --profile load --profile targets-extra down; ok "stack dihentikan."; }

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
    # --- pastikan Host-Only net lab (host=NET_HOSTONLY_IP, DC=NET_DC_IP) + DHCP utk klien ---
    local hoif
    hoif="$(VBoxManage list hostonlyifs | tr -d '\r' | awk -v ip="$NET_HOSTONLY_IP" '
      /^Name:/{sub(/^Name: */,"");n=$0} /^IPAddress:/{if($2==ip){print n;exit}}')"
    if [ -z "$hoif" ]; then
      ok "buat Host-Only network lab ($NET_HOSTONLY_IP/24)"
      hoif="$(VBoxManage hostonlyif create 2>&1 | tr -d '\r' | sed -n "s/.*Interface '\(.*\)' was successfully created.*/\1/p")"
      [ -n "$hoif" ] || die "gagal membuat host-only interface (jalankan sebagai Administrator)."
      VBoxManage hostonlyif ipconfig "$hoif" --ip "$NET_HOSTONLY_IP" --netmask 255.255.255.0 >/dev/null
    fi
    ok "Host-Only net: '$hoif' → $NET_HOSTONLY_IP/24 (DC=$NET_DC_IP, klien via DHCP .100-.200)"
    VBoxManage dhcpserver add --interface="$hoif" --server-ip "${NET_HOSTONLY_IP%.*}.2" \
      --netmask 255.255.255.0 --lower-ip "${NET_HOSTONLY_IP%.*}.100" --upper-ip "${NET_HOSTONLY_IP%.*}.200" \
      --enable >/dev/null 2>&1 || VBoxManage dhcpserver modify --interface="$hoif" --enable >/dev/null 2>&1 || true
    for ova in "${ovas[@]}"; do
      local name; name="$(basename "$ova" .ova)"
      if VBoxManage showvminfo "$name" >/dev/null 2>&1; then ok "VM '$name' sudah terdaftar"; else
        ok "impor $name.ova (VirtualBox)"; VBoxManage import "$ova" --vsys 0 --vmname "$name"
      fi
      # NIC1 → Host-Only lab (isolasi, akses ke layanan Docker di host $NET_HOSTONLY_IP & DC $NET_DC_IP)
      VBoxManage modifyvm "$name" --nic1 hostonly --hostonlyadapter1 "$hoif" >/dev/null 2>&1 \
        && ok "  NIC1 '$name' → Host-Only '$hoif'" || warn "  gagal set NIC '$name' (VM mungkin sedang berjalan)"
      if VBoxManage list runningvms | grep -q "\"$name\""; then ok "VM '$name' sudah berjalan";
      else ok "start '$name' (headless)"; VBoxManage startvm "$name" --type headless; fi
    done
  elif command -v vmrun >/dev/null 2>&1; then
    command -v ovftool >/dev/null 2>&1 || die "VMware terpasang tapi 'ovftool' tak ada (perlu untuk impor OVA)."
    local vmtype="fusion"; if [ "$(uname -s)" != Darwin ]; then vmtype="ws"; fi
    for ova in "${ovas[@]}"; do
      local name vmx; name="$(basename "$ova" .ova)"
      vmx="$(find "$OVADIR/$name" -name '*.vmx' 2>/dev/null | head -1 || true)"
      if [ -z "$vmx" ]; then
        ok "impor $name.ova (ovftool)"; ovftool --allowAllExtraConfig --name="$name" "$ova" "$OVADIR/$name/"
        vmx="$(find "$OVADIR/$name" -name '*.vmx' 2>/dev/null | head -1 || true)"
      fi
      [ -n "$vmx" ] || die "VMX tak ditemukan setelah impor $name."
      # OVA arm: (1) ovftool menyetel guestOS="other" → Fusion Apple Silicon menolak start;
      # (2) controller PVSCSI tak punya driver di initramfs arm → root gagal mount (stall di
      # initramfs). Paksa guestOS=arm-ubuntu-64 + EFI + pindahkan disk ke NVMe (driver nvme
      # selalu ada di initramfs) agar VM benar-benar boot. Idempoten.
      case "$name" in *-arm64)
        python3 - "$vmx" <<'PYVMX' && ok "VMX disetel profil ARM (guestOS arm-ubuntu-64, EFI, disk NVMe)"
import sys,re
p=sys.argv[1]; L=open(p).read().splitlines()
disk=None
for l in L:
    m=re.match(r'(?i)^\s*scsi0:0\.fileName\s*=\s*"(.+)"',l)
    if m: disk=m.group(1)
    m=re.match(r'(?i)^\s*nvme0:0\.fileName\s*=\s*"(.+)"',l)
    if m: disk=m.group(1)
def setkv(lines,key,val):
    out=[];seen=False
    for l in lines:
        if re.match(r'(?i)^\s*'+re.escape(key)+r'\s*=',l): out.append('%s = "%s"'%(key,val));seen=True
        else: out.append(l)
    if not seen: out.append('%s = "%s"'%(key,val))
    return out
# buang semua baris scsi0*, set profil arm + disk nvme
L=[l for l in L if not re.match(r'(?i)^\s*scsi0',l)]
L=setkv(L,'guestOS','arm-ubuntu-64'); L=setkv(L,'firmware','efi')
if disk:
    L=setkv(L,'nvme0.present','TRUE'); L=setkv(L,'nvme0:0.present','TRUE')
    L=setkv(L,'nvme0:0.fileName',disk); L=setkv(L,'nvme0:0.deviceType','disk')
open(p,'w').write("\n".join(L)+"\n")
PYVMX
        ;;
      esac
      # Windows: vmrun mencetak path C:\..., bukan /c/... → bandingkan dgn path Windows (cygpath).
      local vmx_cmp="$vmx"; command -v cygpath >/dev/null 2>&1 && vmx_cmp="$(cygpath -w "$vmx")"
      if vmrun -T "$vmtype" list | tr -d '\r' | grep -qiF "$vmx_cmp"; then ok "VM '$name' sudah berjalan";
      else ok "start '$name' (headless)"; vmrun -T "$vmtype" start "$vmx" nogui; fi
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
  network) setup_network;;
  check)   check_hypervisor_cli; ensure_docker; [ -f "$IMG_TAR" ] && ok "tar image ada ($(du -h "$IMG_TAR"|cut -f1))" || warn "tar image belum ada"; shopt -s nullglob; o=("$OVADIR"/*.ova); shopt -u nullglob; [ ${#o[@]} -gt 0 ] && ok "OVA ditemukan: ${#o[@]}" || warn "belum ada OVA di distribusi/ova"; ok "rencana jaringan: domain=$NET_DOMAIN DC=$NET_DC_IP host-docker=$NET_DOCKER_IP"; step "Check selesai (tidak ada perubahan).";;
  compose) setup_network; load_images; compose_up;;
  full)    check_hypervisor_cli; ensure_docker; setup_network; load_images; compose_up;;
esac
