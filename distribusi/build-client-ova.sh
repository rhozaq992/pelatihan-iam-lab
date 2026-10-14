#!/usr/bin/env bash
# =============================================================================
# build-client-ova.sh — Bangun OVA klien Ubuntu (domain member) dari Ubuntu
# cloud image resmi. realmd/sssd/adcli DIBAKING saat build (boot sekali dengan
# internet) agar klien bisa 'realm join' OFFLINE di kelas.
#
# Pakai:
#   ./build-client-ova.sh --arch amd64     # untuk PC peserta (x86-64)  → ubuntu-client-amd64.ova
#   ./build-client-ova.sh --arch arm64     # untuk instruktur Apple Silicon → ubuntu-client-arm64.ova
#   ./build-client-ova.sh --arch amd64 --release 24.04 --size 12G
#
# Output: distribusi/ova/ubuntu-client-<arch>.ova  (+ SHA256 di SHA256SUMS.txt)
# Butuh: qemu-img, qemu-system-<arch>, mkisofs/xorriso, curl, tar, sha256sum/shasum.
# Catatan: build amd64 di host ARM memakai emulasi TCG (lambat ~15-30 mnt). Di host
# x86 Linux dengan KVM jauh lebih cepat. Jaringan guest default DHCP (diatur panitia).
# =============================================================================
set -euo pipefail

ARCH="amd64"; RELEASE="24.04"; DISK_SIZE="12G"
DOMAIN="iamlab.test"; HOSTNAME_VM="ubuntu-client"; VM_USER="peserta"; VM_PASS="Peserta#Lab2026"
# Rencana jaringan kanonik (samakan dgn deploy-lab.sh) → klien self-configuring, tanpa setel manual.
NET_DC_IP="10.10.10.10"; NET_DOCKER_IP="10.10.10.5"
NET_SUBS="kc app saml grafana bao mail pam"
while [ $# -gt 0 ]; do case "$1" in
  --arch) ARCH="$2"; shift 2;; --release) RELEASE="$2"; shift 2;;
  --size) DISK_SIZE="$2"; shift 2;; -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
  *) echo "opsi tak dikenal: $1"; exit 1;; esac; done
case "$ARCH" in amd64|arm64) ;; *) echo "arch harus amd64|arm64"; exit 1;; esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$HERE/ova"; mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SHA(){ command -v sha256sum >/dev/null 2>&1 && sha256sum "$@" || shasum -a 256 "$@"; }
say(){ printf '\033[1m==> %s\033[0m\n' "$*"; }

# ---- 1. unduh cloud image resmi ----
IMG_QARCH="$ARCH"
URL="https://cloud-images.ubuntu.com/releases/$RELEASE/release/ubuntu-$RELEASE-server-cloudimg-$ARCH.img"
say "Unduh cloud image Ubuntu $RELEASE ($ARCH)"
curl -fL --retry 3 --no-progress-meter -o "$WORK/base.img" "$URL"
qemu-img resize "$WORK/base.img" "$DISK_SIZE"

# ---- 2. seed cloud-init: hostname, user, bake realmd/sssd, helper join, lalu poweroff ----
say "Siapkan cloud-init (bake paket domain)"
cat > "$WORK/meta-data" <<EOF
instance-id: $HOSTNAME_VM-001
local-hostname: $HOSTNAME_VM
EOF
DOCKER_SUBS_LINE="$NET_DOCKER_IP"; for s in $NET_SUBS; do DOCKER_SUBS_LINE="$DOCKER_SUBS_LINE $s.$DOMAIN"; done
cat > "$WORK/user-data" <<EOF
#cloud-config
hostname: $HOSTNAME_VM
fqdn: $HOSTNAME_VM.$DOMAIN
manage_etc_hosts: false
users:
  - name: $VM_USER
    groups: [sudo]
    lock_passwd: false
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
chpasswd:
  expire: false
  list: |
    $VM_USER:$VM_PASS
ssh_pwauth: true
package_update: true
packages:
  - realmd
  - sssd
  - sssd-tools
  - adcli
  - samba-common-bin
  - oddjob
  - oddjob-mkhomedir
  - packagekit
  - krb5-user
  - open-vm-tools
write_files:
  - path: /etc/hosts
    permissions: '0644'
    content: |
      127.0.0.1 localhost
      127.0.1.1 $HOSTNAME_VM.$DOMAIN $HOSTNAME_VM
      # Lab IAM — rencana jaringan seragam (dibaking, peserta tak menyetel)
      $NET_DC_IP dc1.$DOMAIN
      $DOCKER_SUBS_LINE
      ::1 localhost ip6-localhost ip6-loopback
  # Jaringan pasca-impor: cocokkan NIC apa pun (MAC berubah saat impor ke VirtualBox/VMware),
  # DHCP utk IP, tetapi DNS WAJIB ke DC agar 'realm join' menemukan record SRV domain.
  - path: /etc/netplan/99-iamlab.yaml
    permissions: '0600'
    content: |
      network:
        version: 2
        ethernets:
          lab:
            match: {name: "en*"}
            dhcp4: true
            dhcp4-overrides: {use-dns: false}
            nameservers: {addresses: [$NET_DC_IP], search: [$DOMAIN]}
  - path: /usr/local/sbin/join-domain.sh
    permissions: '0755'
    content: |
      #!/usr/bin/env bash
      # Gabungkan klien ini ke domain $DOMAIN (jalankan sbg root saat di kelas).
      set -e
      # Prasyarat: DNS klien = DC ($NET_DC_IP) — diset netplan 99-iamlab.yaml.
      resolvectl query -t SRV _ldap._tcp.$DOMAIN >/dev/null 2>&1 \
        || { echo "DNS belum menemukan DC $DOMAIN (cek DC menyala di $NET_DC_IP & 'resolvectl status')"; exit 1; }
      realm discover $DOMAIN || true
      realm join --user=Administrator $DOMAIN
      pam-auth-update --enable mkhomedir || true
      echo "Selesai. Uji: id budi.contoh@$DOMAIN"
  - path: /etc/motd
    content: |
      Klien Ubuntu Lab IAM — gabung domain: sudo join-domain.sh  (Sesi 1)
runcmd:
  - systemctl enable sssd || true
  # Lepas konfigurasi jaringan yang terikat MAC mesin build; cloud-init tak dijalankan lagi
  # setelah impor (tanpa seed ISO) agar tak menulis ulang netplan.
  - rm -f /etc/netplan/50-cloud-init.yaml
  - touch /etc/cloud/cloud-init.disabled
  - [ sh, -c, "if command -v realm >/dev/null && command -v adcli >/dev/null && command -v sssd >/dev/null && command -v vmtoolsd >/dev/null; then echo BUILD_DONE_$HOSTNAME_VM; else echo BUILD_FAIL_$HOSTNAME_VM; fi > /dev/console" ]
power_state:
  mode: poweroff
  timeout: 60
  condition: true
EOF
# ISO NoCloud (volid WAJIB 'cidata')
if command -v xorriso >/dev/null 2>&1; then
  xorriso -as mkisofs -output "$WORK/seed.iso" -volid cidata -joliet -rock "$WORK/user-data" "$WORK/meta-data"
elif command -v mkisofs >/dev/null 2>&1; then
  mkisofs -output "$WORK/seed.iso" -volid cidata -joliet -rock "$WORK/user-data" "$WORK/meta-data"
else echo "butuh xorriso atau mkisofs"; exit 1; fi

# ---- 3. boot sekali utk provisioning (cloud-init pasang paket lalu poweroff) ----
say "Provisioning boot ($ARCH) — cloud-init memasang paket, lalu mati sendiri"
QEMU="qemu-system-x86_64"; ACCEL="tcg"; FW_ARGS=()
if [ "$ARCH" = arm64 ]; then
  QEMU="qemu-system-aarch64"
  FW=""; for c in /opt/homebrew/share/qemu/edk2-aarch64-code.fd /usr/share/qemu-efi-aarch64/QEMU_EFI.fd /usr/share/AAVMF/AAVMF_CODE.fd; do [ -f "$c" ] && FW="$c" && break; done
  [ -n "$FW" ] || { echo "firmware edk2 aarch64 tak ditemukan"; exit 1; }
  FW_ARGS=(-machine virt -cpu max -drive "if=pflash,format=raw,readonly=on,file=$FW")
  [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ] && ACCEL="hvf"
else
  FW_ARGS=(-machine q35)
  [ "$(uname -m)" = x86_64 ] && [ -e /dev/kvm ] && ACCEL="kvm"
fi
# timeout portabel (macOS tak punya 'timeout'): jalankan qemu di latar + watchdog poll.
set +e
"$QEMU" "${FW_ARGS[@]}" -accel "$ACCEL" -m 2560 -smp 2 \
  -display none -monitor none -no-reboot \
  -drive "if=virtio,format=qcow2,file=$WORK/base.img" \
  -drive "if=virtio,format=raw,file=$WORK/seed.iso" \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -serial file:"$WORK/console.log" &
QPID=$!
RC=0
for _ in $(seq 1 180); do   # maks 180*10s = 30 mnt
  kill -0 "$QPID" 2>/dev/null || break
  if grep -qE "BUILD_(DONE|FAIL)_$HOSTNAME_VM" "$WORK/console.log" 2>/dev/null; then sleep 4; kill "$QPID" 2>/dev/null; break; fi
  sleep 10
done
kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null
set -e
if grep -q "BUILD_DONE_$HOSTNAME_VM" "$WORK/console.log" 2>/dev/null; then
  say "Provisioning sukses (paket domain terbaking)"
else
  echo "GAGAL: penanda BUILD_DONE tak ada (rc=$RC) — paket domain mungkin tak terbaking."
  echo "       20 baris terakhir console:"; tail -20 "$WORK/console.log" 2>/dev/null
  cp "$WORK/console.log" "$OUT/../build-$ARCH-console.log" 2>/dev/null || true
  echo "       console lengkap: distribusi/build-$ARCH-console.log"
  exit 1
fi

# ---- 4. konversi ke VMDK streamOptimized + bungkus OVA ----
say "Konversi disk → VMDK streamOptimized"
VMDK="ubuntu-client-$ARCH-disk1.vmdk"
qemu-img convert -O vmdk -o subformat=streamOptimized,adapter_type=lsilogic "$WORK/base.img" "$WORK/$VMDK"
VMDK_BYTES=$(stat -f%z "$WORK/$VMDK" 2>/dev/null || stat -c%s "$WORK/$VMDK")
CAP_BYTES=$(qemu-img info --output=json "$WORK/base.img" | python3 -c "import sys,json;print(json.load(sys.stdin)['virtual-size'])")
# Profil VM per-arch: amd64 = x86/BIOS (vmx-14, lsilogic); arm64 = ARM/EFI (vmx-20, PVSCSI).
# vmw:osType menentukan apakah VMware membuat VM x86 atau ARM (salah → "requires X86 architecture").
if [ "$ARCH" = arm64 ]; then
  HWVER="vmx-20"; OSTYPE="arm-ubuntu-64"; SCSISUB="VirtualSCSI"
  FWCFG='      <vmw:Config ovf:required="false" vmw:key="firmware" vmw:value="efi"/>'
else
  HWVER="vmx-14"; OSTYPE="ubuntu64Guest"; SCSISUB="lsilogic"; FWCFG=""
fi
cat > "$WORK/ubuntu-client-$ARCH.ovf" <<OVF
<?xml version="1.0" encoding="UTF-8"?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData" xmlns:vmw="http://www.vmware.com/schema/ovf">
  <References><File ovf:href="$VMDK" ovf:id="file1" ovf:size="$VMDK_BYTES"/></References>
  <DiskSection><Info>Disk</Info>
    <Disk ovf:capacity="$CAP_BYTES" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized"/>
  </DiskSection>
  <NetworkSection><Info>Jaringan</Info><Network ovf:name="VM Network"><Description>jaringan lab (diatur panitia)</Description></Network></NetworkSection>
  <VirtualSystem ovf:id="$HOSTNAME_VM-$ARCH">
    <Info>Klien Ubuntu $RELEASE ($ARCH) — domain member Lab IAM</Info>
    <OperatingSystemSection ovf:id="94" ovf:version="$RELEASE" vmw:osType="$OSTYPE"><Info>Ubuntu Linux 64-bit ($ARCH)</Info></OperatingSystemSection>
    <VirtualHardwareSection><Info>Perangkat keras virtual</Info>
      <System><vssd:ElementName>Virtual Hardware Family</vssd:ElementName><vssd:InstanceID>0</vssd:InstanceID><vssd:VirtualSystemType>$HWVER</vssd:VirtualSystemType></System>
      <Item><rasd:Description>CPU</rasd:Description><rasd:ElementName>2 vCPU</rasd:ElementName><rasd:InstanceID>1</rasd:InstanceID><rasd:ResourceType>3</rasd:ResourceType><rasd:VirtualQuantity>2</rasd:VirtualQuantity></Item>
      <Item><rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits><rasd:Description>Memori</rasd:Description><rasd:ElementName>2048 MB</rasd:ElementName><rasd:InstanceID>2</rasd:InstanceID><rasd:ResourceType>4</rasd:ResourceType><rasd:VirtualQuantity>2048</rasd:VirtualQuantity></Item>
      <Item><rasd:Address>0</rasd:Address><rasd:ElementName>SCSI Controller</rasd:ElementName><rasd:InstanceID>3</rasd:InstanceID><rasd:ResourceSubType>$SCSISUB</rasd:ResourceSubType><rasd:ResourceType>6</rasd:ResourceType></Item>
      <Item><rasd:ElementName>Disk</rasd:ElementName><rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource><rasd:InstanceID>4</rasd:InstanceID><rasd:Parent>3</rasd:Parent><rasd:ResourceType>17</rasd:ResourceType></Item>
      <Item><rasd:AutomaticAllocation>true</rasd:AutomaticAllocation><rasd:Connection>VM Network</rasd:Connection><rasd:ElementName>NIC</rasd:ElementName><rasd:InstanceID>5</rasd:InstanceID><rasd:ResourceSubType>VmxNet3</rasd:ResourceSubType><rasd:ResourceType>10</rasd:ResourceType></Item>
$FWCFG
    </VirtualHardwareSection>
  </VirtualSystem>
</Envelope>
OVF
# OVA = tar {ovf, vmdk}. Manifest (.mf) SENGAJA tidak disertakan: ovftool menghitung SHA
# VMDK streamOptimized berbeda dari sha256sum file → selalu "mismatch". Manifest opsional di
# OVF; integritas OVA utuh tetap dijaga via SHA256SUMS.txt. ustar + tanpa metadata macOS agar
# ovftool/VMware dapat membaca stream (pax header bikin gagal parse).
( cd "$WORK"
  COPYFILE_DISABLE=1 tar --format ustar -cf "$OUT/ubuntu-client-$ARCH.ova" \
    "ubuntu-client-$ARCH.ovf" "$VMDK" )
say "OVA siap: $OUT/ubuntu-client-$ARCH.ova ($(du -h "$OUT/ubuntu-client-$ARCH.ova"|cut -f1))"
( cd "$OUT/.." && SHA "ova/ubuntu-client-$ARCH.ova" >> SHA256SUMS.txt )
echo "Impor di kelas: deploy-lab.sh --vms  (atau VBoxManage import / ovftool)"
